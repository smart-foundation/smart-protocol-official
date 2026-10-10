# Write a new `schema/ai.capnp` — timeless, universal, complete

**One file. No companion schema.** `ai-vocabulary` is rejected: a second AI schema is duplication
and fragmentation (there are already 91 others). Conventional tokens live inside `ai.capnp` as
non-binding `const` values that nothing depends on.

## Context

`schema/ai.capnp` (564 lines, compiles clean, never implemented) has two independent defects.

**A. No reachable surface.** All 6 interfaces (`CompletionStream:232`, `ToolRegistry:279`,
`AgentService:356`, `KnowledgeBase:419`, `ConversationService:478`, `AISubscription:556`) are
returned by **zero** methods. `InferenceService` — advertised at `README.md:189` and
`docs/SCHEMAS.md:129` — exists in no schema. `CompletionRequest`, `ModelSpec`, `Tensor`,
`ModelInfo`, `ModelFilter`, `EmbedRequest/Response`, `Usage`, `LogProbs` are orphans. Capability
gating at `:561-564` is **commented out**; `Capability` is a dead import at `:18`;
`ToolRegistry.invoke` is unauthenticated remote code execution.

**B. Today's AI paradigm frozen into an eternal contract.** Ordinals are permanent within a
schema ID (`TIMELESSNESS.md:96`), so every enumerated choice is a permanent commitment:

| Frozen | Why it cannot be |
|---|---|
| `ModelArchitecture:34` (`.@0 = transformer`) | internal backend detail, and `@0` is Cap'n Proto's implicit default — an **absent** field silently means "transformer" |
| `Tensor:92`, `TensorDataType:75`, `ModelFormat:61` | a tensor is an ML-framework object; `q4km`/`q40`/`q50` are **GGUF filename tokens**; `onnx`/`safetensors`/`gguf` are product formats |
| `maxTokens/temperature/topP/topK/logitBias:135-147` | presuppose logits and a tokenizer. `diffusion @4` (`:38`) is **declared but unusable** — no autoregressive knobs, no per-token `index`, no delta stream. The enum says yes, the types say no |
| `MessageRole:160`, `ToolChoice:164`, `ResponseFormatType:186`, `FinishReason:211` | one vendor's 2023 chat API (`developer` is an already-renamed upstream role) |
| `SwarmTopology:377`, `MemoryType:313`, `ChunkingType:415`, `CompressionStrategy:488` | scheduler/indexing internals — fail the Swap Test (`TIMELESSNESS.md:84`) |
| `Embedding.vector:273 :List(Float32)`, `QueryResult.document:454` | defeats zero-copy at the highest-volume data in the system; returns the full Document **including its embedding** per hit |
| `vision @2`/`audio @3`/`multimodal @7` | declared but **impossible** — `ChatMessage.content:154`, `Document.content:429`, `Query.text:439` are all `Text` |
| `CompletionStream.pull:233` | omits the terminator every other chunked stream carries (`web.capnp:121`, `speech.capnp:105`) |
| `SessionId:27` | shadows `T.SessionId` (`types.capnp:6`), unused |

## Architecture

Timelessness is a **negative** constraint: you cannot enumerate what exists in 100 years, but you
can specify what must never appear. So the new file states only structural invariants, **contains
zero enums**, and expresses every technology-specific value as an open `T.StringMap` entry or a
`T.MimeType`. Nothing is forbidden (every model kind stays reachable); nothing is frozen.

**Authority = interface reference.** In Cap'n Proto RPC a capability *is* a reference: holding it
conveys authority to call it. So authority is expressed by *which reference you hold*, gated once at
acquisition — **not** by a `cap :Capability` parameter per method. Consequences:

- `Capability` appears **exactly once per gated service**, as the parameter of the accessor on
  `interface AI`. Zero occurrences inside service methods.
- Attenuation reuses `capability.capnp`'s existing `attenuate @2`; revocation invalidates the
  reference. No new authority vocabulary.
- This corrects `TIMELESSNESS.md:134-145` and `DESIGN_PRINCIPLES.md:376`, which mandate a per-method
  parameter — a rule that was never implemented (5 methods, all inside `capability.capnp`, and there
  it means "the capability being administered", not proof of authority). Task 11 amends both.
- Only `handshake` and `discover` are ungated, so capability discovery stays open while every
  resource-consuming or state-mutating operation requires a granted reference.

**Zero-copy is a correctness constraint, not a slogan.** Cap'n Proto's zero-copy applies to the
serialized message, not transport — anything placed in a message field (`List(Float32)`, `Text`,
`Data`) is copied into that message. Only `T.DataHandle` escapes it. Therefore **all bulk data must
be `T.DataHandle`** (rule E2), which is what makes the zero-copy claim true for tensors, embeddings,
documents and streams. (`README.md:18` and `:127` currently overclaim and are noted in task 12.)

Delete the old file outright — never implemented, and a broken draft must not become the core. Do
**not** reuse `@0xa1b2c3d4e5f60061`: that ID is bound *forever*, so retiring a wrong ID is the point.
Mint a fresh one, e.g. `@0xa1b2c3d4e5f60101` (verify unique across `schema/`). Old content is
recoverable at commit `e2446fb`; no schema imports `ai.capnp`.

**Reuse, never re-invent** (verified present): `T.MimeType` (`types.capnp:777` — the open
`type`/`subtype`/`parameters` content type, replacing every format/dtype enum), `T.DataHandle`
(`:382`), `T.StringMap` (`:142`), `T.Pagination` (`:248`), `T.BoolFilter` (`:244`, tri-state, used
this way in 11 schemas), `T.Timestamp` (`:106`), `T.MonotonicTimestamp` (`:111`), `T.Duration`
(`:107`), `T.Error` (`:196`), `T.Warning` (`:702`), `T.VoidResult` (`:182`), `Capability`
(`capability.capnp:22`), `capability.capnp`'s `attenuate`. New types are only opaque ID wrappers
and the payload/lifecycle structs below. Do **not** introduce a new Layer-1 vocabulary
(`Reference`/`Resource`/`Operation`/`Context`/`Policy`) — that duplicates `types.capnp` and would
force a rewrite of all 91 dependent schemas.

## Tasks

### 1. Replace the file
`git rm schema/ai.capnp`, then write the new one at the same path with a fresh schema ID. Header
must state: this is the eternal core; it contains **zero enums** by rule (E1); all values are open
maps or content types; unknown `T.MimeType` subtypes, capability names, contributors and statuses
**must be ignored, never rejected**; authority is the interface reference; the tokens in the final
section are conventions that nothing depends on.

### 2. Identifiers — opaque
`ModelId`, `RequestId`, `ToolId`, `AgentId`, `AgentGroupId`, `ConversationId`, `KnowledgeBaseId`,
`DocumentId` — each `struct X { id @0 :UInt64; }`, matching the `T.SessionId` (`types.capnp:6`)
pattern. **No** local `SessionId` shadow.

### 3. The one universal payload
```
struct Artifact { mimeType @0 :T.MimeType; data @1 :T.DataHandle; }
```
Replaces `Tensor`, `TensorShape`, `TensorDataType`, `ModelFormat`, `Embedding.vector`,
`Document.content`, `ChatMessage.content`, `Query.text`, `HybridQuery.vectorQuery`,
`ToolSpec.parameters/returns`, `ToolCall.arguments`, `ToolResult.result`,
`CompletionRequest.prompt/messages`, `MemoryConfig.retentionPolicy`. Carries non-text, zero-copy,
and future formats. This is what makes vision/audio/PDF-RAG actually expressible.

### 4. Discovery as data, never as an enum
```
struct CapabilityDescriptor {
    name @0 :Text;                        # opaque token; unknown names must be ignored
    parent @1 :Text;                      # vocabulary hierarchy, open
    inputTypes @2 :List(T.MimeType);
    outputTypes @3 :List(T.MimeType);
    parameters @4 :T.StringMap;
}
struct ModelDescriptor {
    id @0 :ModelId;
    name @1 :Text;
    capabilities @2 :List(CapabilityDescriptor);
    inputTypes @3 :List(T.MimeType);
    outputTypes @4 :List(T.MimeType);
    resident @5 :Bool;
    cost @6 :T.StringMap;                 # backend-declared keys: memory, price, latency
    metadata @7 :T.StringMap;             # architecture, parameter count, quantization, context length
}
```
`cost` + `metadata` absorb **everything** the deleted enums used to say — still readable by anyone
who cares, no longer frozen into the contract. Unknown future capabilities are representable by
construction. Note `"model"` here names the *holder of capabilities*, not an architecture: a
diffusion, neuro-symbolic or non-neural system is equally a `ModelDescriptor`, and its architecture
lives in `metadata` as opaque data.

### 5. Request / response / execution — no authority parameter
```
struct OutputContract { type @0 :T.MimeType; schema @1 :T.DataHandle; parameters @2 :T.StringMap; }
struct Usage { quantity @0 :Float64; unit @1 :Text; dimensions @2 :T.StringMap; }
struct ExecutionMode { union { complete @0 :Void; stream @1 :Void; } }
struct Part {
    artifact @0 :Artifact;
    contributor @1 :Text;                 # opaque token; "system"/"user"/"agent"/tool name
    annotations @2 :T.StringMap;
    replyTo @3 :RequestId;
}
struct InferenceRequest {
    request @0 :RequestId;                # idempotency: retry/dedupe is the caller's call
    model @1 :ModelId;
    inputs @2 :List(Part);                # multimodal + multi-agent from one construct
    output @3 :OutputContract;
    mode @4 :ExecutionMode;
    parameters @5 :T.StringMap;           # sampling knobs, tool selection, stop conditions — open keys
    budget @6 :T.Duration;
}
struct InferenceResponse {
    request @0 :RequestId;
    model @1 :ModelId;
    outputs @2 :List(Artifact);
    usage @3 :Usage;                      # open unit: tokens, bytes, seconds, joules, anything
    warnings @4 :List(T.Warning);
    custom @5 :Data;
}
```
Three universality moves: `ExecutionMode` as a **union** makes streaming an alternative execution
mode rather than a separate API, so a whole-sequence model needs no delta path; `Usage.unit :Text`
removes the tokenizer presupposition while keeping metering; `Part.contributor :Text` replaces the
role enum and makes an agent just another contributor.

### 6. Streams — structural terminator, backpressure, gap detection
```
struct StreamStatus { union { more @0 :Void; complete @1 :Void;
                             failed @2 :T.Error; cancelled @3 :Void; } }
struct StreamFrame { request @0 :RequestId; artifact @1 :Artifact;
                     status @2 :StreamStatus; sequence @3 :UInt64; }
interface ArtifactStream {
    pull @0 (maxBytes :UInt32) -> (frame :StreamFrame);
    cancel @1 () -> T.VoidResult;
}
```
`status` is the terminator (fixes the missing `done :Bool`); `maxBytes` is caller-driven
backpressure; `sequence` detects drops.

### 7. Tools — declarations are artifacts, so tool schemas are not frozen to JSON
```
struct ToolDeclaration { name @0 :Text; description @1 :Text; parameters @2 :Artifact;
                         result @3 :Artifact; annotations @4 :T.StringMap; }
struct ToolInvocation { request @0 :RequestId; tool @1 :ToolId; arguments @2 :Artifact; }
struct ToolOutcome { request @0 :RequestId; success @1 :Bool;
                     result @2 :Artifact; error @3 :T.Error; }
interface ToolRegistry {
    register @0 (tool :Artifact, declaration :ToolDeclaration) -> (tool :ToolId);
    unregister @1 (tool :ToolId) -> T.VoidResult;
    get @2 (tool :ToolId) -> (declaration :ToolDeclaration);
    list @3 (page :T.Pagination) -> (tools :List(ToolDeclaration), total :UInt64);
    invoke @4 (invocation :ToolInvocation) -> (outcome :ToolOutcome);
}
```
Holding `ToolRegistry` **is** the authority to invoke — the old signature had no authority at all.
`parameters`/`result` are artifacts (JSON Schema today, any declarative format tomorrow).

### 8. Models
```
struct ModelFilter { namePattern @0 :Text; capability @1 :Text; resident @2 :T.BoolFilter; }
interface ModelService {
    load @0 (declaration :Artifact, annotations @1 :T.StringMap) -> (model :ModelId);
    unload @1 (model :ModelId) -> T.VoidResult;
    release @2 (model :ModelId) -> T.VoidResult;
    describe @3 (model :ModelId) -> (descriptor :ModelDescriptor);
    list @4 (filter :ModelFilter, page :T.Pagination)
         -> (models :List(ModelDescriptor), total :UInt64);
}
```
`load` takes an `Artifact` declaration — a model arrives as content, so no serialization format is
frozen. Gives `ModelFilter` a real home.

### 9. Inference — one method for every single-shot task
```
interface InferenceService {
    derive @0 (request :InferenceRequest) -> (response : InferenceResponse);
    openStream @1 (request :InferenceRequest) -> (stream :ArtifactStream);
    cancel @2 (request :RequestId) -> T.VoidResult;
}
```
`derive` covers completion, embedding, classification, reranking, reward, moderation and any
future single-shot transform — embeddings are `derive` with an embedding content type, so there is
no embedding-specific API to outgrow. Discovery moves to the root (`interface AI.discover @1`),
ungated, so it is reachable before any reference is held. This is what makes `README.md:189` true.

### 10. Agents — no role, topology or memory enums
```
struct AgentDeclaration { name @0 :Text; description @1 :Text; model @2 :ModelId;
                          declaration @3 :Artifact; instructions @4 :Artifact;
                          memory @5 :Artifact; annotations @6 :T.StringMap; }
struct AgentDescriptor { id @0 :AgentId; declaration @1 :AgentDeclaration;
                         grantedAuthority @2 :List(Capability);   # informational, not a check
                         status @3 :Text; state @4 :T.StringMap; }
struct AgentMessage { request @0 :RequestId; from @1 :Text; to @2 :Text;
                      content @3 :Artifact; annotations @4 :T.StringMap; replyTo @5 :RequestId; }
struct AgentGroupSpec { name @0 :Text; members @1 :List(AgentId);
                        coordinator @2 :Text; topology @3 :T.StringMap; }
struct AgentFilter { namePattern @0 :Text; group @1 :AgentGroupId;
                     status @2 :Text; model @3 :ModelId; }
interface AgentService {
    spawn @0 (agent :AgentDeclaration) -> (agent :AgentId);
    terminate @1 (agent :AgentId, graceful :Bool) -> T.VoidResult;
    send @2 (message :AgentMessage) -> (reply :AgentMessage);
    describe @3 (agent :AgentId) -> (descriptor :AgentDescriptor);
    list @4 (filter :AgentFilter, page :T.Pagination)
         -> (agents :List(AgentDescriptor), total :UInt64);
    createGroup @5 (group :AgentGroupSpec) -> (group :AgentGroupId);
    broadcast @6 (group :AgentGroupId, message :AgentMessage) -> T.VoidResult;
    getGroup @7 (group :AgentGroupId) -> (group :AgentGroupSpec);
}
```
`instructions`/`memory` become artifacts (a text `systemPrompt` cannot hold images, audio or
retrieved evidence); `status` is an opaque token; `topology` is an open map — star/mesh/ring are
scheduler internals (`TIMELESSNESS.md:84`), not wire contract. `grantedAuthority` is reported
metadata about what the agent holds, not an authority check.

### 11. Knowledge — documents and queries are artifacts; queries return references
```
struct Document { id @0 :DocumentId; content @1 :List(Artifact);
                  annotations @2 :T.StringMap; }
struct DocumentRef { id @0 :DocumentId; annotations @1 :T.StringMap; }
struct RetrievalQuery { query @0 :Artifact; topK @1 :UInt32;
                        annotations @2 :T.StringMap; scoreThreshold @3 :Float32; }
struct RetrievalHit { document @0 :DocumentRef; score @1 :Float32; rank @2 :UInt32;
                     evidence @3 :Artifact; }
interface KnowledgeBaseService {
    create @0 (name :Text, embeddingModel :ModelId, configuration :T.StringMap)
        -> (base :KnowledgeBaseId);
    delete @1 (base :KnowledgeBaseId) -> T.VoidResult;
    add @2 (base :KnowledgeBaseId, documents :List(Document)) -> (ids :List(DocumentId));
    remove @3 (base :KnowledgeBaseId, ids :List(DocumentId)) -> T.VoidResult;
    get @4 (base :KnowledgeBaseId, id :DocumentId) -> (document :Document);
    query @5 (base :KnowledgeBaseId, query :RetrievalQuery) -> (hits :List(RetrievalHit));
    queryStream @6 (base :KnowledgeBaseId, query :RetrievalQuery) -> (stream :ArtifactStream);
}
```
`configuration` absorbs chunking strategy, index type and distance metric — backend configuration,
not protocol. `query :Artifact` allows text, image (visual search), vector, audio or anything
future. Returning `DocumentRef` + optional `evidence` fixes the old over-fetch of the entire
Document and its embedding vector per hit.

### 12. Conversations
```
struct ConversationSpec { model @0 :ModelId; tools @1 :List(ToolId);
                          context @2 :Artifact; configuration @3 :T.StringMap; }
struct Conversation { id @0 :ConversationId; spec @1 :ConversationSpec; messages @2 :List(Part);
                      created @3 :T.Timestamp; updated @4 :T.Timestamp;
                      usage @5 :Usage; annotations @6 :T.StringMap; }
struct ConversationFilter { model @0 :ModelId; since @1 :T.Timestamp;
                            annotations @2 :T.StringMap; }
interface ConversationService {
    create @0 (spec :ConversationSpec) -> (conversation :ConversationId);
    get @1 (conversation :ConversationId, page :T.Pagination)
        -> (conversation :Conversation, total :UInt64);
    append @2 (conversation :ConversationId, parts :List(Part)) -> (request :RequestId);
    fork @3 (conversation :ConversationId, fromIndex :UInt32) -> (conversation :ConversationId);
    delete @4 (conversation :ConversationId) -> T.VoidResult;
    list @5 (filter :ConversationFilter, page :T.Pagination)
         -> (conversations :List(Conversation), total :UInt64);
}
```
`get` is now paginated — the old one returned unbounded history.

### 13. Events — content-typed, so no event type can ever need adding
```
struct UnknownEvent { typeId @0 :UInt64; payload @1 :Data; }
struct AIEvent {
    union {
        request @0 :Artifact;        # lifecycle: started/progress/completed/failed
        model @1 :Artifact;
        agent @2 :Artifact;
        conversation @3 :Artifact;
        knowledge @4 :Artifact;
        notice @5 :T.Warning;
        unknown @6 :UnknownEvent;
    }
    at @7 :T.MonotonicTimestamp;
    sequence @8 :UInt64;
}
interface AISubscription {
    pull @0 () -> (events :List(AIEvent));
    cancel @1 () -> T.VoidResult;
}
```
`MonotonicTimestamp` for ordering (immune to clock changes), `sequence` for dedup, `unknown @6`
for safety.

### 14. Entry point — one root, zero orphans, sole site of authority
```
interface AI {
    handshake @0 () -> (info :T.Version, contentTypes :List(T.MimeType),
                        models :List(ModelDescriptor));
    discover @1 (model :ModelId) -> (descriptor :ModelDescriptor);
    models @2 (authority :Capability) -> (service :ModelService);
    inference @3 (authority :Capability) -> (service :InferenceService);
    tools @4 (authority :Capability) -> (service :ToolRegistry);
    agents @5 (authority :Capability) -> (service :AgentService);
    knowledge @6 (authority :Capability) -> (service :KnowledgeBaseService);
    conversations @7 (authority :Capability) -> (service :ConversationService);
    subscribe @8 (authority :Capability, filter :T.StringMap) -> (subscription :AISubscription);
}
```
Returns interfaces, matching `speech.capnp:104` / `web.capnp:118`. Nothing else in the repo returns
non-stream interfaces, so this establishes the pattern rather than conflicting with it. Only
`handshake` and `discover` are ungated — `handshake` publishes known models so discovery works
before any capability is held, closing the acquire→discover loop.

### 15. Conformance tokens — convention, not contract
Final section of the **same file**, marked as carrying no contractual weight:
```
const textContent   :T.MimeType = (type = "text",        subtype = "plain");
const jsonContent   :T.MimeType = (type = "application", subtype = "json");
const binaryContent :T.MimeType = (type = "application", subtype = "octet-stream");
const contributorSystem :Text = "system";
const contributorUser   :Text = "user";
const contributorAgent  :Text = "agent";
const contributorTool   :Text = "tool";
const statusRunning :Text = "running";
const statusIdle    :Text = "idle";
```
Plus commented examples for an embedding type and a JSON-Schema type. Header note: unknown values
must be ignored and never rejected; nothing in the contract depends on this section, so it can
grow without touching a single ordinal. Verify Cap'n Proto accepts struct-valued consts.

### 16. Amend the two principle docs to match the capability model
`TIMELESSNESS.md:134-145` and `DESIGN_PRINCIPLES.md:376` currently mandate a `cap :Capability`
parameter per privileged method, which the new schema contradicts by design. Update both to state
that authority is the interface reference, gated at acquisition, with attenuation/revocation
delegating to `capability.capnp`. Scoped to those statements — no other edits.

### 17. Repoint the four doc references
`ai.capnp` is referenced at `README.md:77`, `README.md:181` (`use smart_protocol::ai_capnp::*;`),
`README.md:243`, `docs/SCHEMAS.md:129` (advertises the nonexistent `InferenceService`). Update only
these to the new service names so they do not advertise a deleted interface.

### 18. Replace `scripts/validate.sh`
The current gate is unreliable text-mangling (`cut -d' ' -f2` plus awk ranges — cannot see inline
enums, comments, or mid-enum `custom`, so it passes almost everything). Replace with a real parser
(Python 3 stdlib; `capnp` 1.4.0 is at `/usr/bin/capnp`):

| Rule | Enforces | Scope |
|---|---|---|
| **E1** | `ai.capnp` contains **zero** enums — paradigm-freezing made structurally impossible | ai.capnp (error) |
| **E2** | no `List(Float32)` / `List(Text)` / `List(UInt8)` in `ai.capnp` — bulk data only via `T.DataHandle`; this is what makes zero-copy true | ai.capnp (error) |
| **E3** | `Capability` appears **only** as a parameter of an accessor on `interface AI` — never inside a service method | ai.capnp (error) |
| **E4** | every `ai.capnp` interface is returned by ≥1 method on `interface AI` | ai.capnp (error) |
| **E5** | every `*Stream` interface's `pull()` returns a structural terminator | ai.capnp (error) |
| **E6** | every union has an `unknown`/`custom` variant with `{typeId, payload}` | ai.capnp (error), others report |
| **E7** | every struct has an open extension point | ai.capnp (error), others report |
| **E8** | an enum's `@0` is the neutral sentinel (`any`/`none`/`absent`/`unknown`) | all schemas (report) |

Scope decisions made during implementation, each because the unscoped rule measured
nothing useful:

- **E4 is ai.capnp-only.** The repo's convention is that a schema's primary service is
  host-injected, so "returned by no method" is equally true of a legitimate root (`System`,
  `Audio`, `Files`) and of a forgotten helper. No mechanical rule separates them; a
  root-exemption heuristic made the rule vacuous across all 305 interfaces. For `ai.capnp`
  the root is explicit, so the rule is meaningful there.
- **E5 applies to `*Stream` interfaces only.** An event subscription returns an unbounded
  batch terminated by `cancel()`, which is the protocol's own convention
  (`appindex.capnp`, `media.capnp`, `access.capnp`, `storage.capnp`). Requiring a terminator
  there would contradict it.
- **E7 exempts opaque `UInt64` ID wrappers and `Artifact`.** `TIMELESSNESS.md:32` requires
  pushing types as far left as possible; an extension point on every ID would bloat every
  message. `Artifact`'s extension mechanism *is* `T.MimeType` + `T.DataHandle` — a new payload
  kind is a new subtype, not a new field. A bare `Data` field or a `custom` field also counts.
- **Comments are stripped before parsing.** The old validator matched raw text, so the phrase
  `List(Float32)` appearing in *prose* was indistinguishable from a real violation. This is
  the specific reason the old gate passed almost everything.

E4 and E8 run across all 92 schemas and **report without blocking**, since only `ai.capnp` is in
scope. Expected report: E4 flags the ~140 hand-duplicated `pull/cancel` subscription interfaces;
E8 flags `MessageRole.@0=system`, `CompressionStrategy.@0=summarize`, `EncodingFormat.@0=float`,
`FinishReason.@0=stop`, `AgentStatus.@0=idle`. Note only, do not fix: `T.SubscriptionResult` /
`T.SubscriptionData` (`types.capnp:903-920`) are dead code — the correct generic primitive used by
zero schemas.

## Validation

1. `capnp compile -o - -Ischema schema/*.capnp` — all 92 files green.
2. `scripts/validate.sh` — 0 errors on `ai.capnp` for E1–E7; E4/E8 protocol-wide report generated, not enforced.
3. **Reachability** — every interface in `ai.capnp` reachable from `interface AI`. Zero orphans.
4. **Authority is the reference** — (a) each gated accessor rejects an insufficient `Capability` with `T.ErrorCode.permissionDenied`; (b) holding the returned reference permits its calls with **no** further token; (c) `capability.capnp`'s `attenuate` yields a reference restricted to a subset, and revoking it makes subsequent calls fail with `permissionDenied`. Assert **zero** `Capability` parameters inside service methods.
5. **Universality matrix** — each row must serialize, round-trip and be expressible with no schema change:

| Model / AI class | Expression |
|---|---|
| text LLM (transformer, SSM, RNN) | `derive`, `text/plain` in/out |
| masked diffusion LM | `openStream`, whole sequence as one `Artifact`, `status=complete` — no delta, no index, no token field |
| encoder-only | `derive`, text → label/score artifact |
| embedding model | `derive` → embedding-type artifact as zero-copy `DataHandle` |
| vision-language | `inputs = [image Artifact, text Artifact]` |
| ASR / TTS / speech-to-speech | audio artifact in/out; `openStream` for streaming synthesis |
| reranker / classifier / reward / moderation | `derive`, text → score artifact |
| RAG over PDF, image or audio | `Document.content = List(Artifact)`, `RetrievalQuery.query = Artifact` |
| multi-agent / swarm | `Part.contributor` + `AgentService`, topology in an open map |
| tool-calling | `ToolRegistry`, JSON Schema today, any declarative format tomorrow |
| symbolic / neuro-symbolic / non-neural | `derive`, architecture recorded only in `ModelDescriptor.metadata` |
| remote API / local / distributed / NPU / WASM / future runtime | backend's concern; the protocol sees only capabilities, content types and references |

6. **Zero-copy** — a 4096-dim embedding and a 512-token sequence must both travel as `T.DataHandle`; assert buffer pointer sharing, no copy, on both ends.
7. **Paradigm-blind stream** — a backend returning a whole-sequence artifact in one `pull` with `status=complete` must need zero fields that did not exist for that model.
8. **Unknown tolerance** — an unknown `T.MimeType.subtype`, unknown capability name, unknown `contributor` token and unknown `status` must all be ignorable, never errors.
9. **Paging** — `list` and `get` return `total` and honour `T.Pagination`; conversation history no longer unbounded.
10. `capnp compile -o rust:/tmp/gen -Ischema schema/*.capnp` regenerates cleanly; `gen/` stays uncommitted.

## Risks

- **`T.MimeType` as `Text` loses compile-time checking.** Accepted: matches `clipboard.capnp:98` and
  `system_search.capnp`, and an open media type is the vocabulary that has survived 30 years.
  Mitigation: §15 tokens are discoverable in-file.
- **Opaque `metadata`/`cost` means string-parsing for parameter counts.** Deliberate: postpones
  freezing. Structured consumers read `ModelDescriptor`.
- **Zero enums means no compile-time exhaustiveness.** Deliberate — that exhaustiveness is what
  goes stale. Mitigation: E1 plus validation step 8.
- **Authority now depends entirely on reference distribution.** Nothing at the method level can
  distinguish "holds a valid reference" from "revoked" — the transport must enforce it. Mitigation:
  validation 4(c); recorded because it is a platform property, not a schema one.
- **Conformance tokens may themselves go stale.** Mitigated by the header declaring they carry no
  contractual weight — honest rather than falsely frozen.
- **Amending `TIMELESSNESS.md` / `DESIGN_PRINCIPLES.md` is protocol-wide in effect.** Those
  principles govern all 92 schemas, and the other 91 currently follow neither rule. Recorded, not
  fixed.

## Out of scope (recorded, not ignored)

Vendor leaks in the other 91 schemas (`boot.capnp:346` x86/arm, `storage.capnp:266` lvm/zfs/btrfs,
`endpoint.capnp:237` dbus/grpc/binder/mach, `audio.capnp:759` pulse/alsa/pipewire,
`hal.capnp:542` CPU-vendor IOMMU, `process.capnp:422` POSIX uid/gid, `files.capnp:373` POSIX
perms); `README.md:242`'s false "zero platform leaks" claim; the 89-vs-92 count contradiction;
missing `LICENSE` despite `README.md:260`; capability gating across the other 91 schemas;
wiring `T.SubscriptionResult`; the `ai` entry missing from `system.capnp`'s capability manifest
(`system.capnp:26` lists 49 domains, none of them AI) and from its 5-schema bootstrap
(`types`/`capability`/`app`/`endpoint`/`auth`) — so AI integration into `System` is a separate
task; a canonical prose specification tree and a reference runtime/conformance suite.

## Open questions

None.

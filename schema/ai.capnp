@0xa1b2c3d4e5f60109;

# ══════════════════════════════════════════════════════════════════════
# AI — universal contract for intelligence: inference, models, tools,
# agents, knowledge and conversations.
#
# REPLACES @0xa1b2c3d4e5f60061, which was never implemented and is deleted.
# The retired ID is deliberately not reused: an ID bound forever should not
# be inherited by a draft that was wrong.
#
# ── THE TIMELESSNESS RULE ───────────────────────────────────────────────
#
# This file contains ZERO enums. That is a hard rule, enforced by the
# validator (E1), not a preference.
#
# Why: in Cap'n Proto a field ordinal is permanent within a schema ID.
# Every enumerated value is therefore a permanent commitment to a
# technology that may not be the right one in twenty years. The previous
# revision froze `transformer`, `onnx`, `gguf`, `q4km`, `system/user/
# assistant`, `temperature`, `topP` and `logitBias` into the contract —
# i.e. it asserted that today's AI would still be today's AI.
#
# The rule replaces enumeration with open values:
#
#   technology-specific value  ->  T.MimeType   (open media-type vocabulary)
#   named-but-unbounded value  ->  T.StringMap (open key/value vocabulary)
#   payload of any size        ->  T.DataHandle
#
# Timelessness is a NEGATIVE constraint. You cannot enumerate what will
# exist in 100 years, because any list is today's list and it ages into
# a lie. You CAN specify what must never appear. So this file names no
# architecture, no vendor, no format, no tokenizer, no model family and
# no topology — only structural invariants, which hold regardless of what
# implements them.
#
# NOTHING IS FORBIDDEN. Every kind of intelligence — autoregressive,
# diffusion, state-space, recurrent, convolutional, symbolic,
# neuro-symbolic, non-neural, or something not yet conceived — is
# expressible, because none of them is named. Architecture is reported by
# the backend as opaque `metadata`; it is never prescribed.
#
# ── UNKNOWN TOLERANCE ──────────────────────────────────────────────────
#
# An unrecognized T.MimeType subtype, capability name, contributor token,
# status token or metadata key MUST be ignored, never rejected. A consumer
# that does not understand a value skips it; one that does, acts on it.
# This is what makes new capabilities addable without a schema change.
#
# ── AUTHORITY IS THE INTERFACE REFERENCE ───────────────────────────────
#
# In Cap'n Proto RPC a capability IS a reference: holding it conveys
# authority to call it. Authority is therefore expressed by WHICH
# REFERENCE YOU HOLD, gated exactly once at acquisition on `interface AI`.
# `Capability` appears nowhere inside a service method.
#
# Consequence: "discover what can I ask for" is available to everyone via
# the ungated `AI.handshake` / `AI.discover`, while every operation that
# consumes resources or mutates state requires a granted reference. An
# agent is not handed a privileged magic API; it is handed a capability,
# exactly like any other participant.
#
# Attenuation and revocation are not redefined here — they are
# `capability.capnp`'s `attenuate @2`, `revoke @4`, `revokeControlled @9`.
#
# ── ZERO-COPY IS A CONSTRAINT, NOT A SLOGAN ────────────────────────────
#
# Cap'n Proto's zero-copy applies to the serialized message, not to
# transport. Anything placed in a message field — List(Float32), Text,
# Data — is COPIED into that message and cannot be zero-copy. Only
# T.DataHandle (a shared buffer reference) escapes that.
#
# Therefore every bulk payload in this file is a T.DataHandle. A 4096-dim
# embedding or a 512-token sequence travels as a buffer reference, never as
# an inline list. The validator rejects List(Float32)/List(Text)/List(UInt8)
# in this file (E2) for this reason.
#
# ── WHAT "MODEL" MEANS HERE ────────────────────────────────────────────
#
# `ModelId` names the holder of a set of capabilities. It does NOT name an
# architecture. A diffusion engine, a neuro-symbolic solver and a
# non-neural reasoner are each a ModelDescriptor; what they are appears only
# in `metadata`, as opaque reported data. The protocol is agnostic, so it
# never asks — and never answers — "what kind of intelligence are you?"
# ══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ── Identifiers ─────────────────────────────────────────────────────────
# Opaque references (Opacity Principle). A ModelId is not a file path, a
# model family, or an architecture. It is a handle.

struct ModelId         { id @0 :UInt64; }
struct RequestId       { id @0 :UInt64; }
struct ToolId          { id @0 :UInt64; }
struct AgentId         { id @0 :UInt64; }
struct AgentGroupId    { id @0 :UInt64; }
struct ConversationId  { id @0 :UInt64; }
struct KnowledgeBaseId { id @0 :UInt64; }
struct DocumentId      { id @0 :UInt64; }

# ── The one universal payload ────────────────────────────────────────────
# Carries anything: text, image, audio, video, a vector, a PDF, a symbolic
# term, or a format not yet invented. `mimeType` tells a consumer how to
# decode; an unknown subtype is ignored, not an error.
#
# This single type replaces the previous revision's Tensor,
# TensorShape, TensorDataType, ModelFormat, Embedding.vector,
# Document.content, ChatMessage.content, Query.text, HybridQuery.vectorQuery,
# ToolSpec.parameters/returns, ToolCall.arguments, ToolResult.result,
# CompletionRequest.prompt/messages and MemoryConfig.retentionPolicy.
#
# It is what makes vision, audio and PDF retrieval actually expressible:
# the previous revision DECLARED vision/audio/multimodal capabilities while
# every payload field was Text, so those models could not be called at all.

struct Artifact {
    mimeType @0 :T.MimeType;
    data     @1 :T.DataHandle;
}

# ── Capability discovery, as data rather than as an enum ────────────────
# The previous revision froze `completion, embedding, vision, audio,
# toolUse, structuredOutput, reasoning, multimodal` into ModelCapability.
# That list is today's list; a capability invented next year had nowhere to
# go except a new ordinal in an eternal schema.
#
# Here a capability is a NAME plus the content types it accepts and
# produces. A capability that does not exist yet is representable today, by
# construction, with no schema change — a consumer that does not recognise
# the name ignores it.

struct CapabilityDescriptor {
    name        @0 :Text;                 # opaque token; unknown names are ignored
    parent      @1 :Text;                 # open hierarchy, e.g. "input"/"output"
    inputTypes  @2 :List(T.MimeType);     # content types accepted
    outputTypes @3 :List(T.MimeType);     # content types produced
    parameters  @4 :T.StringMap;          # open; backend-declared keys
}

# What a model IS, reported without prescribing it.
# `cost` and `metadata` absorb everything the deleted enums used to say:
# architecture, parameter count, quantization scheme, context length,
# memory footprint, price, latency. All of it stays readable by consumers
# who care — and none of it is frozen into the contract.
struct ModelDescriptor {
    id           @0 :ModelId;
    name         @1 :Text;
    capabilities @2 :List(CapabilityDescriptor);
    inputTypes   @3 :List(T.MimeType);
    outputTypes  @4 :List(T.MimeType);
    resident     @5 :Bool;                # currently held in memory
    cost         @6 :T.StringMap;         # backend keys: memory, price, latency
    metadata     @7 :T.StringMap;         # backend keys: architecture, params, quantization, context
}

# ── Output negotiation ──────────────────────────────────────────────────
# Replaces the frozen `ResponseFormat { text, jsonObject, jsonSchema }`
# enum with an open content type. `schema` is itself content-typed, so a
# future structural-output mechanism needs no protocol change.

struct OutputContract {
    type       @0 :T.MimeType;      # what the caller wants back
    schema     @1 :T.DataHandle;    # optional structural constraint
    parameters @2 :T.StringMap;
}

# ── Metering, without presupposing a tokenizer ──────────────────────────
# The previous revision counted tokens (promptTokens/completionTokens/
# totalTokens, maxTokens, tokenCount, MemoryConfig.maxTokens). A byte-level,
# character-level, continuous-latent or non-generative system has no tokens,
# yet metering is real for all of them.
#
# The unit is a Text token. A backend reports tokens, bytes, seconds,
# joules, or a unit invented next year. Metering survives; the tokenizer
# assumption does not.

struct Usage {
    quantity   @0 :Float64;
    unit       @1 :Text;             # open: "token", "byte", "second", ...
    dimensions @2 :T.StringMap;      # e.g. {"input": "12", "output": "30"}
}

# ── Execution mode, as a union rather than a second API ─────────────────
# Streaming is an ALTERNATIVE MODE of one operation, not a parallel API.
# That matters: the previous revision's CompletionStream returned a
# ChatMessage delta per pull, which only an autoregressive token model can
# produce. A masked diffusion model fills a whole sequence in parallel and
# has no delta, no token index and no causal order — it was declared
# (`ModelArchitecture.diffusion`) and simultaneously unusable.
#
# As a mode, a whole-sequence model simply returns its complete output as
# one Artifact. No field anywhere in this file assumes incremental tokens.

struct ExecutionMode {
    union {
        complete @0 :Void;
        stream   @1 :Void;
        # Forward compatibility: a mode added after this schema was frozen
        # arrives here rather than silently defaulting to `complete`.
        unknown  @2 :Void;
    }
}

# ── A piece of input ────────────────────────────────────────────────────
# Replaces the frozen MessageRole enum (system/user/assistant/tool/
# developer), which was one vendor's 2023 chat API — `developer` was
# already a renamed role upstream.
#
# `contributor` is an open token. That yields three things from one
# construct: multimodal input (a list of differently-typed Artifacts),
# multi-agent exchange (an agent is just another contributor, so no
# separate agent-message protocol is needed), and today's chat roles as
# ordinary conventions.

struct Part {
    artifact    @0 :Artifact;
    contributor @1 :Text;             # "system", "user", "agent", a tool name, ...
    annotations @2 :T.StringMap;
    replyTo     @3 :RequestId;        # non-zero when this is a tool result
}

struct InferenceRequest {
    request    @0 :RequestId;         # caller-chosen identity: retry/dedupe is idempotent
    model      @1 :ModelId;
    inputs     @2 :List(Part);
    output     @3 :OutputContract;
    mode       @4 :ExecutionMode;
    parameters @5 :T.StringMap;       # open: sampling knobs, tool selection, stop conditions
    budget     @6 :T.Duration;        # caller's time budget
}
# `parameters` deliberately replaces the frozen OpenAI-shaped fields
# maxTokens / temperature / topP / topK / stopSequences / presencePenalty /
# frequencyPenalty / logitBias / seed / toolChoice / responseFormat. Two
# reasons they cannot be fields: they presuppose logits and a tokenizer, so
# an energy-based, diffusion or retrieval-only backend must fill them with
# lies; and as published ordinals they could never be removed
# (TIMELESSNESS.md:96) even after they became meaningless. As open keys they
# cost nothing when absent and never need an ordinal.

struct InferenceResponse {
    request  @0 :RequestId;
    model    @1 :ModelId;
    outputs  @2 :List(Artifact);
    usage    @3 :Usage;
    warnings @4 :List(T.Warning);     # non-fatal degradation
    custom   @5 :Data;
}

# ── Streams ─────────────────────────────────────────────────────────────
# A STRUCTURAL terminator. Every chunked stream elsewhere in this protocol
# returns `done :Bool` (web.capnp, speech.capnp, system_search.capnp,
# archive.capnp); the previous ai.capnp returned neither, leaving clients to
# infer termination from a nested finishReason hint.

struct StreamStatus {
    union {
        more      @0 :Void;
        complete  @1 :Void;
        failed    @2 :T.Error;
        cancelled @3 :Void;
        unknown   @4 :Void;
    }
}

struct StreamFrame {
    request  @0 :RequestId;
    artifact @1 :Artifact;
    status   @2 :StreamStatus;
    sequence @3 :UInt64;              # monotonic; detects dropped frames
    custom   @4 :Data;
}

interface ArtifactStream {
    # maxBytes is caller-driven backpressure: the producer may never send
    # faster than the consumer pulls.
    pull  @0 (maxBytes :UInt32) -> (frame :StreamFrame);
    cancel @1 () -> T.VoidResult;
}

# ── Models ──────────────────────────────────────────────────────────────
# A model arrives as CONTENT, so no serialization format is frozen. The
# deleted ModelFormat enum named onnx / safetensors / gguf; q4km, q4_0,
# q5_0 and q8_0 in TensorDataType are GGUF FILENAME TOKENS, not concepts.

struct ModelFilter {
    namePattern @0 :Text;
    capability  @1 :Text;             # open token, matches CapabilityDescriptor.name
    resident    @2 :T.BoolFilter;     # any / yes / no
    annotations @3 :T.StringMap;
}

interface ModelService {
    # Holding this reference IS the authority to load and unload.
    load     @0 (declaration :Artifact, annotations :T.StringMap) -> (model :ModelId);
    unload   @1 (model :ModelId) -> T.VoidResult;
    release  @2 (model :ModelId) -> T.VoidResult;
    describe @3 (model :ModelId) -> (descriptor :ModelDescriptor);
    list     @4 (filter :ModelFilter, page :T.Pagination)
            -> (models :List(ModelDescriptor), total :UInt64);
}

# ── Inference ───────────────────────────────────────────────────────────
# ONE method for every single-shot transform. Completion, embedding,
# classification, reranking, reward scoring and moderation are all
# `derive` differing only in output contract — so there is no
# embedding-specific API, and no per-task API to outgrow as tasks appear.
#
# The previous revision's README advertised InferenceService.complete(),
# which existed in no schema, while CompletionRequest, CompletionResponse,
# EmbedRequest, EmbedResponse, ModelSpec and ModelInfo were orphans
# referenced by no method at all.

interface InferenceService {
    derive     @0 (request :InferenceRequest) -> (response :InferenceResponse);
    openStream @1 (request :InferenceRequest) -> (stream :ArtifactStream);
    cancel     @2 (request :RequestId) -> T.VoidResult;
}

# ── Tools ───────────────────────────────────────────────────────────────
# A tool declaration is content, so tool schemas are not frozen to JSON
# Schema: JSON Schema today, anything declarative tomorrow.
#
# invoke() carries no authority parameter because holding this reference IS
# the authority. The previous revision's ToolRegistry.invoke took no
# authority of any kind — unauthenticated remote code execution — while the
# file's own header claimed all privileged operations were capability-gated.

struct ToolDeclaration {
    name        @0 :Text;
    description @1 :Text;
    parameters  @2 :Artifact;
    result      @3 :Artifact;
    annotations @4 :T.StringMap;
}

struct ToolInvocation {
    request     @0 :RequestId;
    tool        @1 :ToolId;
    arguments   @2 :Artifact;
    annotations @3 :T.StringMap;
}

struct ToolOutcome {
    request @0 :RequestId;
    success @1 :Bool;
    result  @2 :Artifact;
    error   @3 :T.Error;
    custom  @4 :Data;
}

interface ToolRegistry {
    register   @0 (tool :Artifact, declaration :ToolDeclaration) -> (tool :ToolId);
    unregister @1 (tool :ToolId) -> T.VoidResult;
    get        @2 (tool :ToolId) -> (declaration :ToolDeclaration);
    list       @3 (page :T.Pagination) -> (tools :List(ToolDeclaration), total :UInt64);
    invoke     @4 (invocation :ToolInvocation) -> (outcome :ToolOutcome);
}

# ── Agents ──────────────────────────────────────────────────────────────
# No role enum, no MemoryType taxonomy (conversation/semantic/episodic/
# hybrid — a library's internal memory classes, not a wire contract), no
# ChunkingType, no SwarmTopology (star/mesh/ring/hierarchical are scheduler
# internals; TIMELESSNESS.md:84 rejects scheduler hints from the protocol).

struct AgentDeclaration {
    name         @0 :Text;
    description  @1 :Text;
    model        @2 :ModelId;
    declaration  @3 :Artifact;        # the agent's own contract/manifest
    instructions @4 :Artifact;        # content, not a text systemPrompt:
                                      # may carry images, audio, retrieved evidence
    memory       @5 :Artifact;        # memory described by content type,
                                      # implemented however the backend likes
    annotations  @6 :T.StringMap;
}

struct AgentDescriptor {
    id                @0 :AgentId;
    declaration       @1 :AgentDeclaration;
    grantedAuthority  @2 :List(Capability);  # reported, not checked here
    status            @3 :Text;        # opaque token; unknown values ignored
    state             @4 :T.StringMap;
}

struct AgentMessage {
    request     @0 :RequestId;
    from        @1 :Text;             # agent name/id, or any participant
    to          @2 :Text;
    content     @3 :Artifact;
    annotations @4 :T.StringMap;
    replyTo     @5 :RequestId;
}

struct AgentGroupSpec {
    name        @0 :Text;
    members     @1 :List(AgentId);
    coordinator @2 :Text;             # open; may be absent for emergent groups
    topology    @3 :T.StringMap;      # open map, not a frozen enum
}

struct AgentFilter {
    namePattern @0 :Text;
    group       @1 :AgentGroupId;
    status      @2 :Text;
    model       @3 :ModelId;
    annotations @4 :T.StringMap;
}

interface AgentService {
    spawn      @0 (agent :AgentDeclaration) -> (agent :AgentId);
    terminate  @1 (agent :AgentId, graceful :Bool) -> T.VoidResult;
    send       @2 (message :AgentMessage) -> (reply :AgentMessage);
    describe   @3 (agent :AgentId) -> (descriptor :AgentDescriptor);
    list       @4 (filter :AgentFilter, page :T.Pagination)
             -> (agents :List(AgentDescriptor), total :UInt64);
    createGroup @5 (group :AgentGroupSpec) -> (group :AgentGroupId);
    broadcast  @6 (group :AgentGroupId, message :AgentMessage) -> T.VoidResult;
    getGroup   @7 (group :AgentGroupId) -> (group :AgentGroupSpec);
}

# ── Knowledge ───────────────────────────────────────────────────────────
# Documents are LISTS OF ARTIFACTS, so retrieval covers PDFs, images, audio
# and video — not just text, as the previous revision's
# `Document.content :Text` made it.
#
# Queries are artifacts too: text, an image (visual search), a vector, audio
# or anything future.
#
# query() returns DocumentRef, not Document. The previous revision returned
# the entire Document — including its full List(Float32) embedding — for
# every hit, so topK=100 shipped 100 documents plus 100 copied vectors where
# the caller needed short passages. `evidence` carries the snippet;
# `KnowledgeBaseService.get` fetches a full document on demand.

struct Document {
    id          @0 :DocumentId;
    content     @1 :List(Artifact);
    annotations @2 :T.StringMap;
}

struct DocumentRef {
    id          @0 :DocumentId;
    annotations @1 :T.StringMap;
}

struct RetrievalQuery {
    query           @0 :Artifact;
    topK            @1 :UInt32;
    annotations     @2 :T.StringMap;
    scoreThreshold  @3 :Float32;
}

struct RetrievalHit {
    document    @0 :DocumentRef;
    score       @1 :Float32;
    rank        @2 :UInt32;
    evidence    @3 :Artifact;        # optional snippet
    annotations @4 :T.StringMap;
}

interface KnowledgeBaseService {
    # `configuration` absorbs index type, chunking strategy and distance
    # metric: backend configuration, not protocol.
    #
    # No embedding model is REQUIRED, because retrieval here is not
    # necessarily vector retrieval. An inverted index, a lexical ranker, a
    # graph walk, a SQL view, a symbolic triple store and a dense vector
    # store are all the same call. Requiring an embedding model would bake
    # today's dominant retrieval technique into an eternal contract — the
    # same error as freezing an architecture enum. Any model a backend uses
    # internally is named in `configuration`, and its capabilities are
    # discoverable through AI.discover.
    create      @0 (name :Text, configuration :T.StringMap)
               -> (base :KnowledgeBaseId);
    delete      @1 (base :KnowledgeBaseId) -> T.VoidResult;
    add         @2 (base :KnowledgeBaseId, documents :List(Document)) -> (ids :List(DocumentId));
    remove      @3 (base :KnowledgeBaseId, ids :List(DocumentId)) -> T.VoidResult;
    get         @4 (base :KnowledgeBaseId, id :DocumentId) -> (document :Document);
    query       @5 (base :KnowledgeBaseId, query :RetrievalQuery) -> (hits :List(RetrievalHit));
    queryStream @6 (base :KnowledgeBaseId, query :RetrievalQuery) -> (stream :ArtifactStream);
}

# ── Conversations ───────────────────────────────────────────────────────
# `context` is an Artifact, not a Text systemPrompt — a conversation can be
# grounded in images, audio or retrieved evidence.

struct ConversationSpec {
    model        @0 :ModelId;
    tools        @1 :List(ToolId);
    context      @2 :Artifact;
    configuration @3 :T.StringMap;   # compression strategy and the like, as open keys
}

struct Conversation {
    id          @0 :ConversationId;
    spec        @1 :ConversationSpec;
    messages    @2 :List(Part);
    created     @3 :T.Timestamp;
    updated     @4 :T.Timestamp;
    usage       @5 :Usage;
    annotations @6 :T.StringMap;
}

struct ConversationFilter {
    model        @0 :ModelId;
    since        @1 :T.Timestamp;
    annotations  @2 :T.StringMap;
}

interface ConversationService {
    create @0 (spec :ConversationSpec) -> (conversation :ConversationId);
    # Paginated: the previous revision's get returned unbounded history.
    get    @1 (conversation :ConversationId, page :T.Pagination)
         -> (conversation :Conversation, total :UInt64);
    append @2 (conversation :ConversationId, parts :List(Part)) -> (request :RequestId);
    fork   @3 (conversation :ConversationId, fromIndex :UInt32) -> (conversation :ConversationId);
    delete @4 (conversation :ConversationId) -> T.VoidResult;
    list   @5 (filter :ConversationFilter, page :T.Pagination)
         -> (conversations :List(Conversation), total :UInt64);
}

# ── Events ──────────────────────────────────────────────────────────────
# Content-typed, so no event type can ever need adding: a lifecycle event
# for a request, model, agent, conversation or knowledge base is an Artifact
# whose mimeType names it. The previous revision froze ModelEventType,
# AgentEventType and ConversationEventType — three enums, none of which had
# a custom variant, so a backend adding one had nowhere to go.
#
# at is monotonic, so ordering survives clock adjustment. sequence supports
# dedup and gap detection.

struct UnknownEvent {
    typeId  @0 :UInt64;
    payload @1 :Data;
}

struct AIEvent {
    union {
        request       @0 :Artifact;
        model         @1 :Artifact;
        agent         @2 :Artifact;
        conversation  @3 :Artifact;
        knowledge     @4 :Artifact;
        notice        @5 :T.Warning;
        unknown       @6 :UnknownEvent;
    }
    at       @7 :T.MonotonicTimestamp;
    sequence @8 :UInt64;
}

interface AISubscription {
    pull  @0 () -> (events :List(AIEvent));
    cancel @1 () -> T.VoidResult;
}

# ── Entry point ─────────────────────────────────────────────────────────
# ONE root, so every interface above is reachable — the previous revision
# declared six interfaces and not one method in the entire protocol returned
# any of them, so nothing in it could actually be called.
#
# Returning interfaces matches speech.capnp (AudioStream) and web.capnp
# (HttpStream).
#
# Authority is gated HERE, at acquisition, and nowhere else. Only handshake
# and discover are ungated, so capability discovery is open to everyone
# while every resource-consuming or state-mutating operation requires a
# reference that was granted. handshake publishes known models so that
# discovery is possible before any capability is held — otherwise
# acquire-to-discover would deadlock.

interface AI {
    handshake     @0 () -> (info :T.Version,
                            contentTypes :List(T.MimeType),
                            models :List(ModelDescriptor));
    discover      @1 (model :ModelId) -> (descriptor :ModelDescriptor);

    models        @2 (authority :Capability) -> (service :ModelService);
    inference     @3 (authority :Capability) -> (service :InferenceService);
    tools         @4 (authority :Capability) -> (service :ToolRegistry);
    agents        @5 (authority :Capability) -> (service :AgentService);
    knowledge     @6 (authority :Capability) -> (service :KnowledgeBaseService);
    conversations @7 (authority :Capability) -> (service :ConversationService);
    subscribe     @8 (authority :Capability, filter :T.StringMap) -> (subscription :AISubscription);
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Nothing above depends on any declaration in this section. They are
# published so that today's tools have a discoverable spelling, not so that
# the protocol can require one. This section can therefore grow without
# touching a single ordinal, and an unrecognized value MUST be ignored
# rather than rejected.
#
# They are Text and T.MimeType values, deliberately NOT enums: an enum here
# would be an eternal commitment to today's spelling of a concept.
# ══════════════════════════════════════════════════════════════════════

const textContent   :T.MimeType = (type = "text",        subtype = "plain");
const jsonContent   :T.MimeType = (type = "application", subtype = "json");
const binaryContent :T.MimeType = (type = "application", subtype = "octet-stream");

# A dense vector is content, not a List(Float32) in the schema. The subtype
# is a convention; parameters carry dimensionality, e.g. {"dimensions":"4096"}.
const embeddingContent :T.MimeType = (type = "application", subtype = "vnd.smart.embedding");

# Tool parameter schemas. Any declarative format is equally valid — a
# protocol that required JSON Schema would be frozen against its successor.
const jsonSchemaContent :T.MimeType = (type = "application", subtype = "schema+json");

const contributorSystem :Text = "system";
const contributorUser   :Text = "user";
const contributorAgent  :Text = "agent";
const contributorTool   :Text = "tool";

const statusIdle     :Text = "idle";
const statusRunning  :Text = "running";
const statusWaiting  :Text = "waiting";
const statusPaused   :Text = "paused";
const statusError    :Text = "error";
const statusFinished :Text = "finished";

# Audit — ai.capnp (622 lines)

## Verdict
**FIX (targeted).** The founder's claim that this is the best-executed schema in the tree is **substantially true and independently verified**: zero enums (E1 — grep confirms 0 `enum` declarations), zero inline `List(Float32)`/`List(Text)`/`List(UInt8)` (E2), every union forward-compatible with an `unknown` variant (`:201`, `:262`, `:546`), one root with every interface reachable by some method (R8), bulk payloads exclusively `T.DataHandle` (`:120`, `:143-154`, `:383`), and `Capability` confined to the seven `interface AI` accessors (`:578-584`) — the reference model the doctrine demands. Four defects remain in the body, plus one real hole. None is architectural; none justifies a rewrite.

## Wire-breakers
None. All method ordinals are unique per interface (`AI` @0–@8; `ModelService` @0–@4; `InferenceService` @0–@2; `ToolRegistry` @0–@4; `AgentService` @0–@7; `KnowledgeBaseService` @0–@6; `ConversationService` @0–@5; subscriptions @0–@1), all struct field ordinals are collision-free, and every `T.*` reference resolves against `types.capnp`. The retired ID `@0xa1b2c3d4e5f60061` is not reused (`:7-9`), which is the correct call.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R7 | `ai.capnp:344-350` `ToolOutcome` | `success @1 :Bool` and `error @3 :T.Error` are parallel fields, not a union | An implementer may return `success = false` with a nil `error`; a consumer then has a failure with no cause and must guess. The same file gets this right everywhere else (`T.VoidResult`, `HpkeOpenResult`-style unions at `:318`, `:345`'s siblings) — this struct is the one place a failure can be swallowed |
| R7 | `ai.capnp:413` `AgentService.send` | Returns a bare `AgentMessage`; no union, no `T.Error` | A crashed or refused agent turn has no wire representation. Every implementer invents one (empty `replyTo`? empty `artifact`?) and every consumer must write "did this fail or did the agent say nothing?" detection. Rule: methods that can fail MUST return a result union containing `Error` |
| R7 | `ai.capnp:573-575` `AI.handshake` | Ungated discovery returns an unbounded `List(ModelDescriptor)`; each descriptor carries two `T.StringMap`s and a capability list | A system with 500 registered models copies 500 descriptors (with their string maps) on every discovery call, and the count grows without bound. The paginated `ModelService.list @4` (`:299-300`) exists but sits behind a capability, so the ungated path is the unbounded one |
| R7 | `ai.capnp:553` `AISubscription.pull` | Unbounded `List(AIEvent)` with no backpressure or terminator, while the file's own stream API uses caller-driven backpressure (`ArtifactStream.pull @0 (maxBytes :UInt32)`, `:277`) | A high-throughput event subscriber exhausts consumer memory. This is exactly the failure that made `runtime_search.capnp:525-528` deprecate its unbounded `pull` in favour of `pullPage` — the gold standard has the defect it elsewhere names |
| R3 (soft) | `ai.capnp:381` `AgentDescriptor.grantedAuthority @2 :List(Capability)` | Authority data rides a data path | Two sources of truth for "what does this agent hold": this list and `CapabilityService.list` (`capability.capnp:172`). They can disagree, and a consumer that reads one and acts on it learns the wrong answer |

## Duplicates & overlaps
- `ai.capnp:381` vs `capability.capnp:172` — the agent's granted-authority list duplicates the capability listing above.
- No duplication with any other schema in the batch: `ConversationSpec`, `RetrievalQuery`, `AgentDeclaration` and friends have no counterpart elsewhere. This file is the batch's cleanest on R6.

## Gaps & holes
- **Agent tool-permission lifecycle (pre-fix finding; superseded by the 2026-10-26 E15 proposal below).** The audited baseline allowed `ToolRegistry.invoke` to select any `ToolId` per request and had no portable least-privilege agent binding. The security branch removes that generic invocation path, supplies one-tool `ToolExecutor` references to agents, and defines empty allowlists as deny-all. Runtime enforcement remains a separate acceptance gate; see the follow-up section.
- `KnowledgeBaseService.add @2` (`:477`) accepts an unbounded `List(Document)` and returns an unbounded `List(DocumentId)`; there is no chunked ingest contract. A 100k-document import exceeds the message limit. Lower priority than the above.
- `RetrievalHit.evidence @3 :Artifact` (`:454-458`) is documented "optional snippet" but is a required struct field; "absent" has no declared encoding, so backends each invent one.

## Zero-cost / eco
Correct throughout: every bulk payload is `T.DataHandle` (`:120`, `:164`, `:332-333`, `:341`, `:351`, `:383`). The only inline `Data` fields are the `custom` escape hatches (`:247`, `:271`, `:349`, `:535`) which are by design small. The two eco defects are the unbounded lists above (`:553`, `:573-575`), which are allocation pressure rather than copy cost.

## UX & implementer guidance
- The CONFORMANCE TOKENS section (`:587-622`) is the pattern the rest of the tree should copy: it publishes today's spellings (`"token"`, `"agent"`, `application/vnd.smart.embedding`) as `const` values that nothing requires and that unrecognized consumers ignore.
- `Part.contributor @1 :Text` (`:218`) and `AgentDescriptor.status @3 :Text` (`:382`) are correctly open, but the file gives no guidance on the registry that makes them interoperable. The conformance tokens at `:612-614` and `:617-622` are the answer; a sentence in the struct comments pointing at them would remove an implementer's first question.
- `InferenceRequest.parameters @5` (`:229`) is the right call against the frozen OpenAI-shaped fields, but because it is entirely open, a backend cannot discover *which* sampling knobs a peer backend honours. `CapabilityDescriptor.parameters @4` (`:138`) is the declared place for that; the file does not say so, so two backends will disagree about where a knob is advertised.

## Recommended actions
1. **Keep the file's architecture and wire shape.** Gain: preserves the one schema in the tree that demonstrably passes the Agnostic/Timeless Test; cost: none.
2. **Make `ToolOutcome` a union** (`success @0 :ToolOutcomeSuccess` / `error @1 :T.Error`). Gain: closes the one path where a failure can be reported with no cause; cost: one new struct, ordinals free at @0/@1 because `success` moves into the success variant.
3. **Give `AgentService.send @2` a result union.** Gain: agent failure becomes representable instead of silently encoded; cost: one wrapper type.
4. **Bound the ungated discovery path: `handshake` returns `List(ModelId)` and the existing ungated `discover @1` supplies the descriptor.** Gain: removes an unbounded copy on the path every consumer takes before holding any capability, without reintroducing the acquire-to-discover deadlock the header describes (`:567-570`); cost: one extra round trip callers already have available.
5. **Add `maxBytes` backpressure (or a `pullPage` variant) to `AISubscription`.** Gain: matches the file's own stream contract and stops subscriber memory exhaustion; cost: one method.
6. **Follow-up (2026-10-26): remove `AgentDescriptor.grantedAuthority`** in the E15 security revision. Descriptive state no longer duplicates capability-service state.
7. **Follow-up (2026-10-26): E15 replaces the minimal allowlist-only fix.** The revision adds `AgentDeclaration.tools`, `AgentToolBinding`, and a per-tool `ToolExecutor`; removes generic `ToolRegistry.invoke(ToolId, ...)`; and changes the schema ID for this pre-release breaking revision. Empty tool lists deny all. The schema gate cannot prove that runtime bindings are truthful, so implementation tests must verify exact matching, fail-closed startup, non-delegation of the global registry, and revocation at invocation time.


## Follow-up security review — 2026-10-26

This section supersedes the agent-tool lifecycle recommendation above for the
proposed branch `security/ai-agent-tool-capability-scope`; the earlier sections
record the pre-fix baseline.

- The schema ID is changed from `@0xa1b2c3d4e5f60109` to
  `@0xb6d9e41a73c20f85`. The immediately previous ID and the older retired
  `@0xa1b2c3d4e5f60061` are both recorded as retired and not reused. This is
  a pre-release breaking change, not a wire-compatible patch.
- `ToolRegistry` has no unscoped `invoke(ToolId, ...)` method. `open(tool)`
  returns a `ToolExecutor` for that one tool; its `invoke(ToolRequest)`
  input contains no tool selector.
- `AgentDeclaration.tools` is an explicit allowlist. Empty means deny all.
  `AgentService.spawn` receives explicit `AgentToolBinding` values; each
  binds one declared ID to one executor capability. Implementations must reject
  duplicate, missing, extraneous or mismatched bindings and must never pass
  the broad registry into agent execution.
- `AgentDescriptor` no longer carries a `List(Capability)` snapshot. The
  capability service remains the sole source for current authority state.
- Validator rule E15 checks the structural boundary only. It cannot prove
  that an implementation enforces the policy, checks revocation on each call,
  or isolates agent memory from unrelated capabilities. Schema compilation,
  CI and implementation-level negative tests must pass before merge/release.

This is a proposed fix until the pull request has passed verification; it is
not a claim that any existing runtime is already secured.

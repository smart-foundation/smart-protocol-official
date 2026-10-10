# Audit — signal.capnp (356 lines)

## Verdict
**FIX (targeted) — and resolve the duplicate delivery authority.** The kernel of the file is right: `T.SignalKind` (no POSIX numbers — the header's claims are true, `signal.capnp:14-17`), `T.DataHandle` payloads (`:64`, `:245`), filter+subscription+cancel. But three problems: (1) `send @0` (`:244`) competes with `kernel.capnp:117` `signal` and `process.capnp:27` `kill` — three signal-delivery authorities in one tree, none designated canonical; (2) the Audit-8/10 layers bolt on an invented feature stack (signal buffering, cascades with depth limits, persisted groups, *AI-assisted classification with automatic routing* — `:336-341`) that no 2046 implementer can derive from the contract; (3) `SignalMapping` (`:174-181`) re-imports POSIX signal numbers through the back door (`platformSignal @0 :UInt32`, `backendName "posix"/"linux"`) in the one file whose header promises "No POSIX signal number assumptions."

## Wire-breakers
None: ordinals unique (`@0..@40`), all `T.*` resolve.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R5 / contradiction | `signal.capnp:167-181` `SignalMappingTable { backendName "posix"/"windows"/"linux", platformSignal :UInt32 }`, `getSignalMapping @21` (`:302`) | POSIX signal numbers as first-class protocol data, in the file that says it has "No POSIX signal number assumptions" | Self-contradiction: the mapping table *requires* backends to expose native numbering. A non-POSIX, message-based runtime (a wasm/actor kernel) has no numbers to map; every consumer must now handle a POSIX table it was told didn't exist |
| R1 / 2046 test | `signal.capnp:336-337` `classifySignal -> (classification :SignalClassification)`, `:340-341` `routeSignal (… classification :SignalClassification)` | "AI-assisted routing" as an OS signal method | Fork risk: no declared classification vocabulary, confidence semantics, or fallback; `suggestedHandler @2 :Text` is backend-private. A 2046 signal path must implement an ML classifier to satisfy the interface, or stub it — and the stubs will differ |
| R1 (soft) | `signal.capnp:48-55` `SignalPriority { urgent, high, normal, low, background }`, `:140-146` `SignalTimeoutAction { escalate, abort, retry, log }`, `:220-225` `SignalCascadePolicy { forward, transform, drop }`, `:30-35` `SignalAction`, `:37-45` `SignalDeliveryResult` | Closed vocabularies; `SignalPriority` duplicates the `priorityHint` *intent* pattern the doctrine endorses (DESIGN_PRINCIPLES.md:77-81) with a frozen ladder | All have `custom` variants and none names a technology — these are the batch's milder enum debt; listed for completeness, not action |
| R3 (soft) | `signal.capnp:290` `exportAuditLog (filter, format :Text) -> (data :T.DataHandle)`; audit surfaces (`:286-287`) | Audit export as an ungated method | Audit trails are security-relevant; ungated export in a schema whose access model is otherwise "who can signal whom" leaves the audit surface open |
| R6 | `signal.capnp:244` `send` vs `kernel.capnp:117` `signal @4` vs `process.capnp:27` `kill @3` | Three delivery authorities with three identity styles (`T.ProcessId`+`T.ThreadId` vs `T.ProcessId` vs `T.ProcessId`+`T.SignalKind`) | Demonstrated fork: permission checks (who may signal whom) must be implemented three times and kept identical; `SignalDeliveryResult.notPermitted @2` exists here but the kernel's `signal` returns `T.VoidResult` — the same denial, two error models |
| R7 (soft) | `signal.capnp:107-114` `SignalSubscription` | `pull @0 (…) -> (events, pagination, total)` returns a `pagination` *echo* in results — ambiguous request/response pairing (cf. `pullPaged @2` which does it right) | Consumers can't tell whether to page; two pull methods with different contracts in one interface |
| R4 | `signal.capnp:198-207` `SignalGroup.groupId @0 :UInt32` | 32-bit group IDs ("0 = new group" magic value) | `UInt32` IDs are too small for distributed systems (DESIGN_PRINCIPLES.md:179 principle); the `0 = new` sentinel is an implementer trap |
| R2 (soft) | `signal.capnp:330` `flushBuffer -> (count :UInt32)`; buffering block `:326-333` | Buffered signals held server-side with no bound contract | A slow receiver forces either unbounded server memory or silent drops — no declared policy; every backend picks differently |

## Duplicates & overlaps
- Delivery: three authorities (above).
- Mask management: `setMask @6`/`getMask @7`/`setThreadMask @18` (`:261-262`, `:293`) vs `kernel.capnp` wait/notify — partial overlap in the "blocked/pending" concept (`SignalMask.blocked/pending` `:68-73`).
- Audit entries: `SignalAuditEntry` (`:150-163`) vs `capability.capnp:414` `AuditEntry` vs `logging.capnp`/`klog.capnp` audit shapes — four audit-entry shapes in the batch (see Batch-SUMMARY).
- `SignalEvent` duplicates `ExitNotification`/`StoppedService`-style lifecycle events — signals and lifecycle notifications are the same observation domain; three event types for it.

## Gaps & holes
- No declared semantics for *standard* signal kinds: `T.SignalKind.terminate` is defined by whom, and is a handler mandatory? `SignalInfo` (`:82-88`) can report `defaultAction`/`canBlock`/`canCatch` — but nothing says a backend *must* answer truthfully or what a consumer may assume when it doesn't. Fork: two systems where SIGTERM-equivalent means "cleanup then die" vs "die now."
- `sender @0 :T.ProcessId` with `0 = system signal` (`:60`): PID 0 as sentinel collides with kernels where PID 0 is a real (idle) task.

## Zero-cost / eco
`SignalEvent.payload @4 :T.DataHandle` (`:64`) — correct; the file's best R2 citizen detail. `bufferSignal`/`flushBuffer` pattern (server-held queue) is the eco-anti-pattern: where a subscription pull belongs, the design forces producer-side buffering.

## UX & implementer guidance
- Header principles block (`:13-25`) is accurate and rare — keep it.
- `send @0` takes four positional params (`signal, receiver, payload, threadId`, `:244-246`) while `sendBatch @1` takes a receiver list — consistent enough, but `SignalEvent` already exists as the natural single parameter; two shapes for one call.
- `replaySignal @22`/`replaySignalWith @34` (`:305`, `:344`): replaying a signal with a *modified* receiver is a privilege-escalation primitive if ungated — the capability to receive does not imply the capability to redirect.

## Recommended actions
1. **Designate one delivery authority.** Recommend: `SignalService.send` (richest identity + typed result + payload handle) becomes canonical; `kernel.capnp:117 signal` and `process.capnp:27 kill` delegate or are documented as thin wrappers. Gain: one permission-check implementation, one error model (`SignalDeliveryResult`), one identity shape; cost: two files trim methods — mechanical pre-release.
2. **Delete the Audit-8/10 feature stack**: buffering (`:326-333`), cascades (`:320-323`, `:354-355`), group persistence (`:347-351`), AI classification/routing (`:335-341`), replay-with-modification (`:344-345`), thread-mask duplication (`:292-299`). Gain: a signal contract a 2046 runtime can implement without inventing ML, cascade-depth, or persistence semantics; cost: none (unreachable-value features with zero consumers).
3. **Delete `SignalMappingTable`/`SignalMapping`/`getSignalMapping`** (`:167-181`, `:302`) — POSIX numbers are the exact assumption the file rejects; mapping tables belong in backend docs, not the wire. Gain: removes the self-contradiction and a platform-noun dependency; cost: none.
4. **Fix `pull`/`pullPaged` contract ambiguity** (`:107-113`): one paginated pull. Gain: removes the request/response pairing fork; cost: one ordinal retired.
5. **Declare standard-signal semantics** (what `terminate`/`kill` guarantee) and replace `0 = system` with an optional `sender` union. Gain: closes the fork where signal meaning is backend-private; cost: spec text + one field shape.

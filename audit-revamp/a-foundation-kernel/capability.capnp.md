# Audit — capability.capnp (527 lines)

## Verdict
**KEEP** (with a documented optional trim). This is the canonical authority schema and the batch's best citizen after `ai.capnp`: `id @0 :Data` opaque (`capability.capnp:27`), textual targets (`:31`), `proof` deliberately opaque (`:149`), attenuation/revocation owned here (`:163`, `:169`, `:184`), `T.Error`/`T.VoidResult`/`T.BoolResult` everywhere. Nothing in the file violates R1–R8 in a way that breaks a 2046 implementer. The Audit-7/9 method growth (negotiate/compose/exchange/transfer-approval, `:201-228`) is speculative machinery — a capability *market* — but each method is additive, typed, and error-honest, so removal is a judgement call about simplicity, not a correctness fix. Removing methods pre-release is permitted by the doctrine ("deprecated interfaces removed pre-release"), and the honest recommendation is to trim, not to keep by default.

## Wire-breakers
None. `Operation` (`:99`) is the enum every other schema in the batch should be importing — see Batch-SUMMARY for the duplicates that don't.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R3 (soft) | `capability.capnp:178` `pull @7 (subscription :CapabilitySubscription)` | The capability subscription has two call paths: hold the reference, or pass it back to the service | Two authority paths that must agree forever — exactly what the doctrine's reference model forbids (ai.capnp:54). Cost: every future consumer re-learns which path is safe; revocation semantics must be defined twice |
| R7 (soft) | `capability.capnp:299-313` `CapabilityEvent` union | Has `custom @4 :Text`, not `unknown @N :UnknownEvent { typeId, payload :Data }` | A backend cannot forward-propagate a new event kind with payload; it must squeeze it into a Text. Minor, but this is the one file that should model the pattern perfectly |
| R1 (soft) | `capability.capnp:77-83` `CapabilityConditionType` (network/time/location/device) | Closed list of condition classes | A 2046 condition ("inside trusted enclave", "during lunar night") has no ordinal. It has `custom @4`, so not fatal; the open-value pattern (T.StringMap params) would have cost nothing |
| Simplicity | `capability.capnp:198-228` negotiate/compose/proposeExchange/acceptExchange/rejectExchange/requestTransferApproval/approveTransfer/denyTransfer | Eight methods implementing a capability *market* with human approval flows | 2046 test: none of these is needed to "prove an operation on a target." They add a second, social protocol layer on top of the reference model. Cost: implementers must build an exchange/approval state machine the OS never asked for |

## Duplicates & overlaps
- `kernel.capnp:442` `CapOperation` and `kernel.capnp:451` `CapRights` duplicate `Operation` (`capability.capnp:99`) with a narrower vocabulary (read/write/execute/grant/delete). `kernel.capnp:164,437,798` use them. This file is the victim, not the cause — fix kernel.
- `types.capnp:576` `CapabilityHandle { handle @0 :UInt64 }` and `types.capnp:937` `CapabilityId` overlap in purpose; kernel's `CapId` (`kernel.capnp:45`) is a third spelling. Tolerance: acceptable, typed wrappers around the same wire UInt64.

## Gaps & holes
None material. One candidate: `Constraints.shareable`/`attenuatable` defaults are set (`:121-123`) but there is no declared behavior when a backend cannot honor a constraint (e.g., rate box). The `verify` result (`T.BoolResult`) does not distinguish "denied" from "un-enforceable" — an implementer will invent that distinction. Demonstrated fork risk: two backends answering "false" for different reasons; consumers cannot decide whether to retry.

## Zero-cost / eco
`operations @2 :List(Operation)` and `conditions @7 :List(...)` are small, bounded lists. `exportAudit` returns `T.DataHandle` (`:236`) — correct zero-cost choice. No copy-forcing payloads.

## UX & implementer guidance
- `Audit.proof` comment (`:146-149`) is exemplary — it names the opacity reason.
- `attenuate @2` doc says "Requires the parent has `attenuate` in its operations" (`:162`) but the schema does not enforce or express that precondition anywhere; a verifier must guess. State it in `Constraints` or leave to backend docs.
- Trailing comment block (`:523-527`) says audit methods "would be added… Actual integration requires updating the CapabilityService ordinal range" — but `queryAudit @14`, `exportAudit @15`, `generateComplianceReport @16` *are already integrated* at `:233-239`. Stale comment; misleads.

## Recommended actions
1. **Keep the file and its wire shape.** Gain: preserves the one correct authority contract; cost: none.
2. **Optional pre-release trim of `:198-228` (negotiate/exchange/transfer-approval).** Gain: deletes a speculative social protocol layer, leaving one authority path (reference model) that the doctrine actually defends; cost: any consumer that planned on exchange flows — there are none, nothing external consumes the protocol.
3. **Fix the stale comment at `:523-527`.** Gain: stops misleading implementers about which ordinals exist; cost: one line.
4. **Do not** add an `UnknownEvent` variant unless trimming happens anyway — adding ordinals is always allowed later; the honest cost/benefit of touching the canonical authority schema pre-release favors minimal diffs.

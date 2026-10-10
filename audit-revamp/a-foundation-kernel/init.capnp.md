# Audit — init.capnp (246 lines)

## Verdict
**FIX (targeted).** The observable-lifecycle core is right and matches the doctrine (`InitState`, `Phase`, lifecycle events, "init decides order · protocol sees state"). Three targeted defects: (1) two contradictory `RestartPolicy` enums coexist in one file — `init.capnp:66-72` (none/onFailure/always/onSuccessAfterFailure/custom) used by `ServiceSpec.onFailure @3` (`:57`), and `types.capnp:1954` (always/onFailure/never) used by `ServiceSupervisor.setPolicy @4` (`:161`) — a fork baked into the same schema; (2) three parallel supervision-registration paths (`InitService.registerService @16..@21`, `ServiceSupervisor`, `RuntimeRegistry`) none of which is reachable from any method in the protocol (R8); (3) raw `UInt8` codes where typed values exist (`policy :UInt8` `:135`, `state :3 :UInt8` `:224`, `pid @9 :UInt64` `:236`).

## Wire-breakers
None. `T.FailureReport` (`:157`), `T.RestartPolicy` (`:161`), `T.IsolatedScope`, `T.Quota` all resolve.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R6 | `init.capnp:66-72` vs `types.capnp:1954-1958` | Two `RestartPolicy` enums with *different vocabularies* in one file: local has `none`, `onSuccessAfterFailure`; canonical has `never` and lacks both | A backend must implement both tables and decide what `onSuccessAfterFailure` maps to when `types.capnp` says there are only three policies. Demonstrated fork: two init implementations, two restart grammars, apps that configure one and observe the other |
| R8 | `init.capnp:151-164` `ServiceSupervisor`, `:174-181` `RuntimeRegistry` | Declared interfaces that no method in any schema returns | R8: an interface with no consumer path cannot be validated or called. A 2028 implementer must guess whether `InitService` is supposed to expose them (and at which ordinal) or delete them |
| R4/R8 | `init.capnp:135` `registerService (… respawnPolicy :UInt8)`, `:140` `setServicePolicy (policy :UInt8)`, `:224` `state @3 :UInt8`, `:236` `pid @9 :UInt64`, `:163` `subscribeDeath (channelId :UInt32)` | Uninterpreted raw codes where typed values exist (`T.RestartPolicy`, `T.EntityState` `types.capnp:1969`, `T.ProcessId`) | Implementer trap: policy byte `2` means different things per backend; `state @3 :UInt8` forces the consumer to decode an undocumented lifecycle. Every backend invents its own table — classic fork |
| R7 | `init.capnp:183-191` `InitEvent` union | No `unknown`/`custom` variant | A backend adding a lifecycle event kind has nowhere to put it; the consumer rejects the whole pull |

## Duplicates & overlaps
- `InitService.start/stop/restart` (`:99-103`) vs `service.capnp:25-27` `Service.start/stop/restart` — two service controllers, different identity types (`T.ServiceName` vs `T.ServiceId`). One canonical controller needed.
- `subscribeDeath (channelId :UInt32)` (`:163`) duplicates `process.capnp:174` `subscribeDeath (pid, channelId)` — same raw-channel-id pattern, two homes.
- `SupervisedService` (`:216-241`) duplicates `service.capnp:203-214` `ServiceInfo` (name/pid/state/critical) with different fields.
- `InitState.pendingStart @4 :List(T.ServiceName)` (`:24`) — `T.ServiceName` is a numeric ID (`types.capnp:450`), so a *name* list is an ID list; see types audit.

## Gaps & holes
- `ServiceSpec.authority @5 :Text` (`:61`) — a free-text "authority header" is exactly the per-method authority token the doctrine abolished. Either it is a `Capability` reference (gated once, at acquisition) or it is nothing. As written, every backend invents its grammar; demonstrated fork risk for security-critical behavior.
- No declared behavior when `installHook`'s hook outlives the service it configures (hook target disappears between install and fire). `hookFailed` exists; garbage semantics don't.

## Zero-cost / eco
`InitSubscription.pull @0` (`:244`) is unbounded with no pagination parameter — contrast `session.capnp:136` which takes `T.Pagination`. High-volume boot event streams force the consumer to accept whatever batch arrives; cost is memory pressure on the pull side, not copies.

## UX & implementer guidance
- The file header documents three rule numbers (`Rule 2`, `Rule 7`, `Rule 9`) without a rule table; the numbers mean nothing to a reader.
- `ServiceSupervisor` header (`:146-149`) cites "services.toml" and "the compile-time RESTART_GRAPH" — an implementation artifact (config file format) leaking into a schema comment. TIMELESSNESS.md:89 rejects init dependency-resolution algorithm; a TOML contract is the same class of leak.

## Recommended actions
1. **Delete one `RestartPolicy`.** Keep the `types.capnp` canonical; delete the local enum (`:66-72`) and point `ServiceSpec.onFailure @3` at it, adding `none` semantics as `never` + a critical flag. Gain: one restart grammar for init, supervisor, and runtime registry; cost: the `onSuccessAfterFailure` refinement is expressible as `always` + hook.
2. **Collapse the three supervision paths into `InitService`** (register/heartbeat/respawn/list) and delete `ServiceSupervisor` and `RuntimeRegistry` (`:151-181`) — nothing returns them, so deletion costs no consumer. Gain: one supervision contract, R8 satisfied; cost: none pre-release.
3. **Replace raw `UInt8`/`UInt32` codes** (`:135`, `:140`, `:163`, `:224`, `:236`) with `T.RestartPolicy` / `T.ProcessId` / `T.EntityState`. Gain: removes the undocumented-code trap; cost: ordinals are free to repurpose pre-release.
4. **Add `custom` variant to `InitEvent`** (`:183-191`) and pagination to `InitSubscription.pull` (`:244`). Gain: R7 compliance + bounded pulls; cost: two ordinals.
5. **Decide `ServiceSpec.authority @5`**: capability-reference or delete. Gain: closes the free-text authority fork; cost: one field.

# Audit — system.capnp (110 lines)

## Verdict
**FIX (targeted), small file, one structural defect.** The handshake/ping/shutdown shape is right and honest. The defect: `Capabilities` (`system.capnp:39-87`) is 47 hardcoded booleans naming *today's* schema catalog — a closed set that cannot express a service invented in 2027, and is already stale (the tree contains `ai`, `tunnel`, `sandbox`, `crypto`, `mount`, `storage`, `endpoint` — none have a boolean, and `textInput @7` names a schema slated for deletion). DESIGN_PRINCIPLES.md:549 calls this "extensible"; a fixed bitmap is the opposite. Two smaller issues: a dual subscription-authority path (`:22-23` + `:36`) and stale comments referencing methods that don't exist (`:32`, `:104`).

## Wire-breakers
None.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R1 | `system.capnp:39-87` | 47 fixed `Bool` fields naming the current service list | 2046 failure: a system ships `ai.capnp` (the doctrine's own gold standard) and `handshake` has no field to declare it. The consumer sees `ai=false`-equivalent (absent) and refuses to use a service that exists. Every new service forever requires editing an eternal struct — the exact failure `ai.capnp:122-131` was written to prevent |
| R3 (soft) | `system.capnp:22-36` | `subscribeCapabilities @3 () -> (subscriptionId :UInt64)`, then `CapabilitiesSubscription.cancel @1 (subscriptionId :UInt64)` — the subscription takes its own id as a parameter | Two authority paths for one subscription (hold reference vs. present token); ai.capnp's model is holding the reference only. Cost: revocation/teardown semantics must be defined twice |
| UX | `system.capnp:32, 104` | Comments claim "Subscription interface (methods 100-101)" / "Subscription methods are on System at methods 100-101" | `System` defines only `@0..@8`. Misleading guidance — an implementer hunts for nonexistent ordinals |

## Duplicates & overlaps
- `system.capnp` `Capabilities` overlaps `abi.capnp:208` `Abi.features` (open list) and `discovery.capnp:380-396` `DiscoveryFilter` — three capability-declaration mechanisms in the batch. One canonical open form should exist.

## Gaps & holes
- `handshake @0` returns `sessionId :UInt64` (`:19`) but no other schema consumes a *system* session; `session.capnp`'s `Session` is a user session and also carries `T.SessionId` (`session.capnp:146`). Two unrelated concepts share one typed ID. Fork risk: a 2028 implementer wires the handshake session into user-session state and the two lifecycles diverge silently.

## Zero-cost / eco
No bulk payloads. No findings.

## UX & implementer guidance
- `SystemInfo.arch @3 :Text` (`:93`) — fine (open), consistent with `boot.capnp:331`'s typed+text approach, which then makes `boot.capnp:345-358` `Architecture` enum the inconsistent outlier (see boot audit).
- `getExtensionCapability @5` returns a bare `Bool` (`:25`) — a capability queried as a boolean is the permission-flag smell in miniature.

## Recommended actions
1. **Replace the `Capabilities` bitmap with an open set**: `capabilities @0 :List(Text)` (backend-interpreted tokens, unknown ignored) or `List(T.CapabilityId)` + name map. Gain: a 2046 service is declarable at handshake with no schema edit; the current bitmap is already wrong today (missing ai/tunnel/sandbox…). Cost: consumers must string-match instead of boolean-check — a real but small cost, dwarfed by the perpetual edit-forever cost.
2. **Fix the dual subscription path** (`:22-23`, `:36`): hold the `CapabilitiesSubscription` reference; drop the id parameter. Gain: one authority path per the reference model; cost: two ordinals repurposed pre-release, free.
3. **Delete the stale method-number comments** (`:32`, `:104`). Gain: honest docs; cost: nothing.

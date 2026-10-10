# Audit — tunnel.capnp (313 lines)

## Verdict
**FIX (targeted, small).** This is the cleanest schema in the batch: `T.DataHandle` frames, `T.Duration`/`T.Timestamp` everywhere, `T.VoidResult`, pull+cancel with a paginated variant, and a `custom` variant on every enum. Four targeted items: the `TunnelHandle` leaks routing state (exactly what DESIGN_PRINCIPLES.md:167 says to remove), `HealthStatus` and `MeshAlgorithm` are batch duplicates, `TunnelInfo` is dead, and `TunnelEncryption` freezes a 2024 crypto naming generation.

## Wire-breakers
None (compiles clean). `MeshTopology` name collision: `tunnel.capnp:133` (struct) vs `kernel.capnp:358` (enum) — importing both makes the name ambiguous. `HealthStatus` collides with `endpoint.capnp:171` (identical values) and `filesystem.capnp:204` (different values: failing/offline/checking vs unhealthy/unknown).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R4 | `tunnel.capnp:82-89` | `TunnelHandle { id, subject @1, meshId @2, logicalId @3 }` | DESIGN_PRINCIPLES.md:167 names this exact fix ("Remove `subject` from handle; it belongs in `TunnelSpec` and `TunnelInfo`") — still present, now joined by `meshId` and `logicalId`. A handle is a pure reference; routing state on it means two backends hand out handles that differ in fields consumers must not trust, and a capability attenuated to a mesh still carries the mesh id |
| R6 | `tunnel.capnp:291-297` | `HealthStatus` = healthy/degraded/unhealthy/unknown/custom | Third copy in the batch; `endpoint.capnp:171` is identical, `filesystem.capnp:204` is incompatible. One health vocabulary should exist |
| R6 | `tunnel.capnp:180-186` | `MeshAlgorithm` = flood/gossip/linkState/distanceVector | Exact duplicate of `network.capnp:310-316` `MeshRoutingAlgorithm` |
| R1 | `tunnel.capnp:203-218` | `TunnelEncryption` names `kyber768`, `kyber1024`, `hybridX25519Kyber768` | Kyber was renamed ML-KEM in 2024 — the enum already names a superseded standardization generation. A 2046 post-quantum scheme has no value; the 2046-test failure is not hypothetical, it's two years old |
| R8 | `tunnel.capnp:106-119` | `TunnelInfo` is returned by no method; `getMetrics @8` returns `TunnelMetrics`, `healthCheck @9` returns `TunnelHealth`, but nothing returns the aggregate | The struct a consumer would use to describe a tunnel (peer, spec, state, counters) is unreachable — implementers must assemble it manually or invent a getter |
| R7 | `tunnel.capnp:49-56` | `FlowPolicy @0 = reliableOrdered` | An absent/unset field silently means "reliable and ordered" — the most expensive default for a lossy link. The validator's E8 sentinel rule flags exactly this class |
| R7 | `tunnel.capnp:95` | `TunnelSubscription.pull @0` unbounded (documented) with `pullPaged @2` alongside | The unpaginated pull is the first ordinal; `capability.capnp:397-402` shows the repo's resolution (deprecate `pull`, keep `pullPaginated`). Same fix applies here with a comment |

Validator counts: E7 ×11, E8 ×6, E6 ×0.

## Duplicates & overlaps
- `HealthStatus` (3×), `MeshAlgorithm`/`MeshRoutingAlgorithm` (2×), `MeshTopology` (struct vs kernel enum).
- `TunnelSecurityPolicy.authentication` `TunnelAuth` (:220-229) vs `endpoint.capnp` TLS/`socket.capnp` TLS — transport security modeled per-schema rather than once.
- `QoSParams` (:233) vs `network.capnp` `QualityMetrics` (:421) vs `socket.capnp` `QosOption` (:139) — three QoS shapes.

## Gaps & holes
- No framing contract: `TunnelSpec.maxFrameSize @3` bounds frames, but nothing states what happens when a frame exceeds it mid-stream, or how `receive`'s `more :Bool` interacts with the max (the terminator exists — good — but the overflow behavior doesn't).
- `openLogical @10` returns a bare `UInt32` `logicalId` (:77) while `TunnelHandle.logicalId` also exists — two ways to name the same stream, one typed, one raw.

## Zero-cost / eco
- Model citizen: `send @2`/`receive @3` take/return `T.DataHandle`, `TunnelSubscription` pulls `List(T.DataHandle)`, `pullPaged` bounds memory. No inline bulk, no polling pattern. No findings.

## UX & implementer guidance
- `TunnelSecurityPolicy.trustedPeers @4 :List(Data)` (:200) — opaque peer keys with no identity pairing (which peer is which bytes). `TunnelPeer.peerId :T.NodeId` exists (:148) — the policy should reference it.
- `MeshTopology.localHandle @1` (:137) embeds a full `TunnelHandle` (with its leaked routing fields) inside topology data — the handle leak propagates.

## Recommended actions
1. **Strip `subject`, `meshId`, `logicalId` from `TunnelHandle`** (:82-89); the spec and info already carry them (`TunnelSpec.subject @1`, `MeshTopology.meshId @0`, `LogicalTunnel.logicalId @0`). Gain: handles become pure references as the doctrine demands; cost: three fields removed from a handle — wire-affecting only for anyone who read them, which is nobody (pre-release).
2. **Delete `TunnelInfo` or wire it in** (add `getInfo @13 (handle) -> (info :TunnelInfo)`). Gain: either removes a dead type or completes the info surface; cost: zero either way.
3. **Collapse `HealthStatus`** into one batch-wide definition (keep `tunnel.capnp`/`endpoint.capnp`'s five-value form; delete `filesystem.capnp`'s divergent copy when that file merges). Gain: one health vocabulary. Cost: one type moves.
4. **Replace `TunnelEncryption` with an open algorithm token** (`Text` + `T.StringMap` parameters) or reference a shared crypto vocabulary. Gain: stops naming a 2024 standardization generation; a 2046 PQ scheme is a string. Cost: consumers lose the enum switch — they should not be switching on crypto names anyway.
5. **Deprecate `TunnelSubscription.pull @0`** with a comment pointing at `pullPaged @2`, matching `capability.capnp:397-402`. Gain: consistent deprecation pattern across the batch. Cost: one comment.

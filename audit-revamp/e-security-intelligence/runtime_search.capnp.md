# Audit — runtime_search.capnp (777 lines)

## Verdict
**FIX (targeted).** This file contains the batch's worst platform freeze and its third permission model, but it also contains the batch's best subscription-migration pattern (`pullPage @2` with the unbounded `pull @0` explicitly deprecated, `:525-532`) and correctly uses the promoted `T.CapabilityId` (`types.capnp:937`). It has grown into a service-mesh control plane — cost models, live migration, traces, SLAs, on-call rotations — which is beyond a discovery contract, so the recommended actions include trimming as well as fixing.

## Wire-breakers
None. Method ordinals @0–@25 unique (`:405-500`); struct ordinals collision-free throughout; all `T.*` references resolve. One **name collision that will mislead every reader and every file importing both**: `struct Capability` at `runtime_search.capnp:238-248` has the same name as `capability.capnp:22-53` `Capability` and a completely different shape (this one is `{id :T.CapabilityId, name, permission, description, advertised}`). Nothing compiles wrong; everything reads wrong.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R5 | `runtime_search.capnp:203-220` `RuntimeKind` (unknown/wasmModule/wasmComponent/nativePlugin/nativeLibrary/microservice/ipcService/**unixDaemon**/**windowsService**/scriptRuntime/**jsRuntime**/**pythonRuntime**/**luaRuntime**/containerized/unikernel/custom) | Four values name operating systems and three name language runtimes, in a file whose header claims "Backend-agnostic: works with WASM runtimes, microservices, plugin systems, dynamic linkers, or any other mechanism" (`:11-13`) | A seL4/Cylophone-class runtime, a BEAM process, a GraalVM native image, or a 2046 mechanism has only `custom @15` carrying nothing. Because `RuntimeSearchQuery.kinds @1 :List(RuntimeKind)` (`:305`) filters on this enum, such a runtime is undiscoverable by kind, and `RuntimeSearchStats.byKind @1 :T.StringMap` (`:504`) cannot report it consistently. The alternative backends (a capability kernel, a unikernel host, a pure-microservice deployment) are each broken by different values in this list |
| R3/R6 | `runtime_search.capnp:238-257` `Capability` + `CapabilityPermission {domain :PermissionDomain, scope :Text, access :PermissionAccess}` | A permission model parallel to `capability.capnp:99` `Operation`, with its own domain taxonomy (15 values, `:259-275`) and its own access verbs (7 values, `:277-286`) | A third/fourth authority vocabulary in the batch (alongside `content.ContentPermission`, `sandbox.CapabilityGrant`, `auth.PermissionGrant`). Implementers must map `PermissionDomain.filesystemRead` → `Operation.read` + a target string, and no schema declares that mapping. Cost: authority expressed in one system is not portable to the other |
| R3 | `runtime_search.capnp:178-188` `ServiceAuth` (none/mtls/token/apiKey/custom), used at `RuntimeInstance.auth @23` (`:84`) | A second service-to-service authority mechanism alongside `capability.capnp` | Service authentication is expressed as a *mechanism name* while the protocol's authority model is capabilities. Two paths that must be reconciled by every consumer of a service that advertises both |
| R1 | `runtime_search.capnp:147-159` `DiscoveryMode` (centralRegistry/p2pMesh/broadcast/multicast/hybrid/custom) | Broadcast and multicast are specific network technologies | A DHT-, gossip-, or rendezvous-hash-based discovery mechanism lands in `custom @5` carrying nothing, and `RuntimeSearchQuery.discoveryMode @11` (`:323`) cannot express it |
| R7 | `runtime_search.capnp:374` `RuntimeSearchEvent.custom @7 :Data` | The one union in the file uses a raw `Data` payload rather than `unknown @N :UnknownEvent { typeId, payload :Data }` | A backend cannot forward-propagate a new event kind with a typed discriminator; the consumer cannot even key the payload. `ai.capnp:533-536` and `signature.capnp:236-239` show the correct shape |
| R4 | `runtime_search.capnp:467` `migrateService @17 -> (migrationId :Text)` | Unstructured Text lifecycle handle | Every other lifecycle handle in the protocol is a typed `UInt64` id; `getMigrationStatus @18 (migrationId :Text)` (`:470`) then string-matches, and two backends' migration-id namespaces are unrelated |

## Duplicates & overlaps
- `Capability`/`CapabilityPermission`/`PermissionDomain`/`PermissionAccess` (`:238-286`) ↔ `capability.capnp:22-124`.
- `ServiceAuth` ↔ `capability.capnp` `Operation`/`Constraints`.
- `ServiceSla`/`ServiceOwnership`/`ServiceCostModel`/`ApiDocumentation`/`ChangelogEntry` (`:690-777`) are organizational metadata with no protocol consumer in this batch; `ServiceCostModel.currency @4 :Text` (`:546`) coexists with a typed `T.FiatAmount`/`Currency` (`types.capnp:1357-1384`).
- `ChangeType` (`:769-777`) duplicates the concept behind `capability.capnp:435-447` `AuditEventType` and `content.capnp`'s action enums.
- `LogFilter`/`LogEntry`/`ServiceMetric`/`TraceSpan` (`:603-657`) overlap `logging.capnp` and `diagnostics.capnp` — three observability contracts.
- The file is explicitly the runtime sibling of `system_search.capnp` (`:7-13`) and duplicates its `VectorQuery`/similarity vocabulary conceptually.

## Gaps & holes
- **No contract for how a registered instance proves it is still the instance it registered as** — `TtlPolicy` (`:91-100`) and `HealthCheck` (`:104-117`) both exist, but nothing binds a registration to a capability. A process that dies and whose id is reused is indistinguishable from the original, and `getInstance @2` (`:414`) will happily return stale state.
- `migrateService @17` has no declared relationship to `ServiceDependency` (`:121-132`): dependents of a migrated instance are not told, and there is no event variant for it.
- `restore`/persistence semantics of `persistent @12`/`resilient @13` (`:62-64`) are asserted as booleans with no declared behaviour — a consumer cannot tell whether a reboot preserves an instance's `instanceId`.

## Zero-cost & eco
`getServiceMetrics @22 (metricNames :List(Text))` (`:487`) returns an unbounded metric list; `getServiceLogs @21` (`:483`) is paginated; `snapshot @4` (`:420`) returns a full enumeration with no pagination, which is exactly the unbounded read the file avoids elsewhere. `RuntimeInstance.dependencies @19 :List(ServiceDependency)` (`:76`) is unbounded but naturally small.

## UX & implementer guidance
- `RuntimeInstance.location @5 :Text` is documented as "(URI/handle/path-agnostic)" (`:48`) — three mutually exclusive kinds behind one `Text`. A consumer cannot know whether to open a URI or pass a handle, so every consumer must sniff the string.
- `TtlPolicy` and `HealthCheck` are both policy structs with `enabled` flags and overlapping thresholds (`failureThreshold @2` vs `unhealthyThreshold @3`), with no declared precedence when both are set.
- `RuntimeSearchStats.byState @2 :T.StringMap` (`:505`) enumerates states as strings while `RuntimeState` is a typed enum in the same file — a backend must invent the string spellings.
- The file's header (`:15-30`) documents its audit-3/audit-7 improvements accurately; the "backend-agnostic" claim is the one contradicted by the body.

## Recommended actions
1. **Open `RuntimeKind` to a `Text` token** (with `wasmModule`/`microservice`/`ipcService` published as conformance `const`s, as `ai.capnp:600-622` does). Gain: a capability-kernel or BEAM or 2046 runtime becomes discoverable by kind instead of vanishing into `custom`; cost: consumers switch on strings and the filter becomes a string match.
2. **Rename the local `Capability` struct and merge `CapabilityPermission` onto `capability.capnp`** — an instance's advertised authority is a `Capability` with a target and operations, nothing more. Gain: one authority vocabulary tree-wide and no name collision; cost: `RuntimeInstance.capabilities @6` and `CapabilityIndex` change type.
3. **Delete `ServiceAuth` in favour of an authenticated capability reference.** Gain: service auth joins the authority model; cost: consumers lose a one-field advertisement they should not have been reading anyway.
4. **Convert `migrationId` to a typed id.** Gain: consistent with every other lifecycle handle; cost: two signatures.
5. **Give `RuntimeSearchEvent` an `unknown :UnknownEvent` variant.** Gain: forward-compatible events; cost: one variant plus one struct.
6. **Trim the service-mesh surface (`getCostModel`, `migrateService`, `getServiceLogs`, `getServiceMetrics`, `getTrace`, the catalog/SLA/ownership types) unless a consumer exists.** Gain: a discovery contract instead of an observability platform; cost: any consumer of those methods — there are none, since nothing external consumes the protocol.

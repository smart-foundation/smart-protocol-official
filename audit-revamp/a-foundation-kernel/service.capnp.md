# Audit — service.capnp (468 lines)

## Verdict
**FIX (targeted) — strip the Audit-9 half.** The observation core (`listServices/getService/getState/subscribeState`, `:21-33`) is a legitimate external contract. Everything from `deploySidecar @26` (`:105`) onward is a cloud-datacenter orchestrator: sidecars, Consul/etcd discovery registration, blue-green/canary deployment, chaos engineering, autoscaling, SLA compliance, cost tracking in currency, namespace isolation. Two hard problems: the file duplicates `init.capnp`'s service control (start/stop/restart — a second, ungated service authority), and `injectFailure @44` (`:179`) is reachable with **no capability gate anywhere in the file** — any caller can inject failures into any service. That is a security defect, not a style issue.

## Wire-breakers
None. All `T.*` resolve.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R3 / security | `service.capnp:20-196` (whole interface, acute at `:179` `injectFailure`, `:137` `setNetworkPolicy`, `:68` `scaleFleet`) | No capability gating on any accessor; no root interface returning privileged variants; destructive/chaos methods flat on the public interface | Any process holding the `Service` reference can inject failures, rewrite network policy, or delete sidecars. ai.capnp:578-583 shows the pattern (`models @2 (authority :Capability)`). Concrete cost: an authority defect that cannot be fixed additively once clients exist — and it *will* be exploited, not merely misdesigned |
| R1 / 2046 test | `service.capnp:414-419` `DeploymentStrategy` (rolling/blueGreen/canary), `:386-390` `SidecarConfig` (image/port), `:398-401` `DiscoveryConfig` (Consul/etcd/ZooKeeper named in comment `:115`), `:449-452` `ChaosFailure` | Cloud-vendor/2026-datacenter vocabulary in required positions | 2046 test: a microkernel laptop or embedded controller has no sidecar image, no canary, no on-call anything. The contract still forces implementers to stub 20+ methods that name infrastructure that may not exist. Each stub is a place behavior forks |
| R6 | `service.capnp:25-27` vs `init.capnp:99-103`; `service.capnp:203-214` `ServiceInfo` vs `init.capnp:216-241` `SupervisedService`; `service.capnp:267-272` `ServiceDependency` vs `discovery.capnp:173-182`; `:459-462` `ServiceSla` vs `discovery.capnp:244-255`; `:454-457` `ServiceCost` vs `discovery.capnp:259-270` | Four duplicate type names across `service`/`init`/`discovery`, each pair with different shapes | Codegen collisions and two "service dependency" truths (`required` vs `dependencyType`). A consumer compiling all three schemas gets conflicting symbols; a consumer reading all three docs gets conflicting contracts |
| R1 | `service.capnp:230-238` `ServiceStatus` (active/reloading/activating/deactivating) and `:294-300` `ServiceHealthState`, `:371-379` `ServiceEventType` | Closed state lists | Weaker violations (all have `custom @6`); listed for completeness, not action |
| Simplicity | `service.capnp:78-87` metrics config/query, `:184-195` cost + SLA, `:168-174` event sourcing + replay | Observability-platform surface inside an OS contract | Each subsystem is a real external contract *for a datacenter*, not for "the system service." Complexity added that removes no bigger complexity |

## Duplicates & overlaps
- Service control: `init.capnp:99-103` vs `service.capnp:25-27` (different ID types: `T.ServiceName` vs `T.ServiceId`).
- Logging config: `service.capnp:321-328` `ServiceLogConfig` (level/destination/format/retention/maxFileSize) vs `logging.capnp:36-42`/`:65` (setLevel/setRetention) — a second, weaker log-configuration contract.
- Registration/supervision: `init.capnp:135` `registerService` vs `service.capnp:29` `registerDiscovery` vs `discovery.capnp:401` `register`.

## Gaps & holes
- `updateConfig @31` / `getConfig @32` (`:124-127`) take `T.StringMap` — fine — but nothing defines config *validation* or rollback; `rollbackDeployment @38` rolls back deployments, not config. An implementer must invent config versioning. Modest fork risk.
- `getMetrics @22` returns `ServiceMetrics` with `latencyP50/P95/P99` but no window semantics — since when? Each backend invents the sampling window.

## Zero-cost / eco
`getEventLog @42` / `replayEvents @43` (`:171-174`): replay pushes an event log with no bound; combined with `subscribeServiceEvents @25` this is a pull-heavy design where a bounded, backpressured subscription belongs. `injectSecrets @33` (`:132`) passes `List(ServiceSecret)` with `value @1 :Text` (`:405`) — secrets inline in the message, copied. Secrets belong in `secret.capnp` with opaque handles.

## UX & implementer guidance
- `ServiceTask.cpu @2 :Float32` comment (`:243-244`) documents 0-100 sum-across-cores — good — but `service.capnp:341` `requestRate :Float64` has no unit (per second? per minute?). Name the unit or use a typed value.
- The file's header claims ownership of "runtime observation" only (`:8-10`), yet the body implements start/stop/restart/scale — the header teaches one contract, the body another.

## Recommended actions
1. **Gate the interface**: introduce a root accessor pattern (`capability.capnp`-verified accessor returning `Service`) and strip ungated destructive methods, or split destructive control into an authority-gated interface. Gain: closes a live security hole (ungated `injectFailure`/`setNetworkPolicy`); cost: consumers re-acquire — none exist pre-release.
2. **Delete the cloud-orchestrator block** `@26..@48` (`:102-195`): sidecar, discovery registration, deployment strategies, rollback, autoscaling, namespace isolation, event sourcing, chaos, cost, SLA. Gain: an implementable contract for a single-device OS; removes ~10 vendor-vocabulary enums/structs; cost: features with zero consumers (verified: nothing external consumes the protocol).
3. **Merge the observation core into `init.capnp`** or formally split identity: pick `T.ServiceId` everywhere and delete one of `Service.start/stop/restart` and `init.start/stop/restart`. Gain: one service-control authority, one identity type; cost: moderate merge work — but cheaper than maintaining two.
4. **Point secrets at `secret.capnp`** (`injectSecrets`, `:132`). Gain: no secret copies through the service interface; cost: one method re-shape.

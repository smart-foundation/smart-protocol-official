# Audit — discovery.capnp (601 lines)

## Verdict
**FIX (targeted) — strip the service-mesh half.** The header makes a strong, true claim for the core: register/deregister/lookup/get/subscribe with no assumed registry mechanism (`discovery.capnp:6-8`). The Audit-7/9 growth then embeds an enterprise service mesh: per-request pricing, on-call rotations, canary traffic splitting, circuit breakers with HTTP retryable status codes, multi-region geo-distribution, changelogs, cluster health. The 2046 failure is immediate — none of it exists on a single device — and one line contradicts the file's own header directly: `RetryPolicy.retryableStatusCodes @5 :List(UInt16)` (`:325`) freezes HTTP semantics into the "zero backend assumptions" contract. Four duplicate type names with `service.capnp` (`ServiceCost`, `ServiceSla`, `ServiceDependency`, `ServiceState`) compound it.

## Wire-breakers
None: ordinals unique (`@0..@23`), `T.*` resolve (`T.HashOutput` at `types.capnp:1179`, `T.CapabilityId` at `:937`).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| Header contradiction / R5 | `discovery.capnp:325` `retryableStatusCodes @5 :List(UInt16)` (+ comment "HTTP status codes that trigger retry") | HTTP baked into a contract whose header says "No mDNS, DNS-SD, or platform-specific registry assumed. The backend decides the discovery mechanism" | Wire break on any non-HTTP transport (local IPC, unix socket, future fabric): the field is meaningless but required. Self-contradiction is the finding — the header promises what the body refuses |
| R1 / 2046 test | `discovery.capnp:274-285` `ServiceCanary`, `:289-309` `CircuitBreaker` + `CircuitState`, `:386-390` `SidecarConfig`-adjacent mesh concepts, `:259-270` `ServiceCost` (per-request pricing), `:218-225` `ServiceOwnership { team, contactEmail, oncallRotation }`, `:330-346` `ServiceGeoDistribution`, `:350-376` `ServiceChangelog` | Cloud-datacenter operations vocabulary in required struct fields of `ServiceDescriptor` (`:93-105`) | Every backend — laptop, embedded, capability kernel — must carry (and fake) ownership/on-call/pricing fields for every registered service. 2046 test: an on-call rotation is a 2015 org-chart artifact |
| R6 | `discovery.capnp:259-270` `ServiceCost` vs `service.capnp:454-457` `ServiceCost`; `:244-255` `ServiceSla` vs `service.capnp:459-462`; `:173-182` `ServiceDependency` vs `service.capnp:267-272`; `:116-125` `ServiceState` (enum) vs `service.capnp:223-228` (struct) | Four same-name-different-shape pairs across two files | Codegen collisions; `ServiceState` is an *enum* here and a *struct* there — the worst case, since they're not even the same kind of type |
| R3 | `discovery.capnp:75-78` `requiredCaps @7 :List(Text)` + `requiredCapabilityIds @11 :List(T.CapabilityId)` | Two capability specifications on one descriptor ("stringly-typed" vs "typed — preferred") | The file itself admits the first is wrong and keeps it: two authority paths that must agree forever (DESIGN_PRINCIPLES.md:394-396). Backends implement one; consumers read the other |
| R7 | `discovery.capnp:545-549` `DiscoverySubscription.pull () -> (events :List(DiscoveryEvent))` | Unbounded pull, no pagination/total — the file's own `lookup` is paginated (`:412`) and `BootSubscription` models `pullPaginated` (`boot.capnp:716-722`) | A burst of registrations floods one message; no `total` for gap detection |
| R1 (soft) | `discovery.capnp:44-62` `ServiceCategory` (15 values: media/network/…/iot), `:184-188` `DependencyType`, `:304-309` `CircuitState`, `:368-376` `ChangelogType` | Closed lists | All carry `custom`; the category list names today's subsystem map. Lower severity — flagged, not actioned |
| R2 | `discovery.capnp:452` `heartbeat (serviceId, liveness :Liveness)`; `:597-600` `Liveness { lastBeat, jitterTolerance, gracePeriod }` | Liveness heartbeats as a *pull/observe* pattern | The event alternative exists (`DiscoveryEvent` `:551-571`); a heartbeat method forces poll-shaped keep-alive per service. Eco cost at fleet scale |

## Duplicates & overlaps
- `HealthSubscription` (`:591-594`, `pull () -> (health :List(ServiceHealth))`) vs `diagnostics.capnp:95-98` (`pull (subscriptionId :UInt64) -> (status :HealthStatus)`) — same interface name, different signatures.
- `ServiceHealth` (`:154-169`) vs `service.capnp:302-307` `ServiceHealthStatus` — two health result shapes.
- Version negotiation (`negotiateVersion @17`, `:439-441`) vs `abi.capnp:279` `negotiate` — two negotiation contracts (service-level vs ABI-level).
- Dependency graph (`getDependencyGraph @19`, `:505-531`) vs `init.capnp` dependency ordering — two dependency models (observable graph vs declared startup order).

## Gaps & holes
- No declared behavior for *expired* registrations beyond the `expired` event (`:565`): does lookup filter them, and does `expireAt` imply auto-deregistration? Backends will differ; a consumer cannot know whether a stale descriptor is live.
- No consumer-visible contract for who may `register` a service (ungated, `:401`): any caller can register any service name. On a single device that is a hijack vector; the capability model is the declared answer but is not wired.

## Zero-cost / eco
- `ServiceEndpoint.address @0 :Text` etc. — small, fine.
- `subscribeServiceHealth @10` + `heartbeat @20` (`:420`, `:452`): health is poll-shaped (heartbeat in) while the file already owns an event stream out — asymmetric design; a subscription carrying health changes is the simpler single mechanism.
- `DiscoverySubscription.pull` unbounded (R7 row) is the eco concern: bounded pulls with `total` (as `lookup` has) belong on the stream too.

## UX & implementer guidance
- The header improvement log (`:10-38`) again records audit history; the contract's own rules (who may register, what expiry means) go undocumented — the reader learns the audit, not the system.
- `update @7` ("unified partial update — any field may be set", `:405`) coexists with `updateState @2`/`updateMetadata @3`/`updateEndpoints @8` ("kept for specific semantics") — four update paths, one descriptor. An implementer must guess which is normative.
- `ServiceAttestation.attestationType @3 :Text ("tpm", "sgx", "cosigning")` (`:213`) — open Text, correct pattern; the enums elsewhere in the file should have followed it.

## Recommended actions
1. **Delete the service-mesh block**: `ServiceCost`, `ServiceOwnership`, `ServiceCanary`, `CircuitBreaker`, `RetryPolicy`, `ServiceGeoDistribution`, `ServiceChangelog`, cluster health, heartbeat, and the `ServiceDescriptor` fields that carry them (`:92-105`, `:242-376`, `:452`, `:486-501`). Gain: the discovery contract a single-device OS can implement; removes the HTTP contradiction and four duplicate type names in one cut; cost: none (no consumers).
2. **Delete `requiredCaps`** (`:76`), keep `requiredCapabilityIds` (`:78`). Gain: one capability reference path; cost: backends that published strings lose a redundant field.
3. **Bound `DiscoverySubscription.pull`** (pagination + total, per `lookup`). Gain: bounded streams, gap detection; cost: one ordinal.
4. **Gate `register`/`deregister`/`update*`** behind capability-gated acquisition, or declare the local-trust assumption explicitly. Gain: closes the registration-hijack hole; cost: one root accessor.
5. **Define expired-registration semantics** (filtered from lookup? auto-deregistered?). Gain: closes the stale-descriptor fork; cost: one paragraph.
6. **Collapse the four update methods into `update`** (`:405`) with a patch struct. Gain: one mutation path; cost: three ordinals retired pre-release.

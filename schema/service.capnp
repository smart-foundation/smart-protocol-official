@0xa1b2c3d4e5f60021;

# ═══════════════════════════════════════════════════════════════════════
# Service — runtime observation of services declared in init.capnp.
#
# This schema OBSERVES. Init owns declarations and lifecycle control
# (`start`/`stop`/`restart` live there, once); discovery owns
# registration. This file answers "what is running, in what state, with
# what health, using what" — and it gates every mutation behind a
# capability-gated accessor, because the pre-revamp interface had none.
#
# ── THE AUTHORITY HOLE, CLOSED ─────────────────────────────────────────
#
# The pre-revamp `Service` interface was ungated: any caller holding the
# reference could `injectFailure` into any service, rewrite its network
# policy, delete its sidecar or scale its fleet. That is not a style
# issue — it is an authority defect that cannot be fixed additively once
# clients exist.
#
# The fix is the ai.capnp pattern, one accessor deep:
#
#     interface Service {
#         # ungated: observation stays open, so a caller can learn what
#         # exists and in what state
#         getState @N (serviceId) -> (state :ServiceInstanceState);
#
#         # gated once, at acquisition. Holding the returned
#         # ServiceControl reference IS the authority to call its methods.
#         control @M (authority :Capability) -> (control :ServiceControl);
#     }
#
# Every method on `ServiceControl` takes no token: the reference itself
# is the authority. There is no per-method capability parameter anywhere
# in this file.
#
# ── WHAT WAS DELETED, AND WHY ──────────────────────────────────────────
#
#   * the cloud-orchestrator half: `deploySidecar`, `removeSidecar`,
#     `registerDiscovery`/`deregisterDiscovery` (Consul/etcd/ZooKeeper),
#     `deployWithStrategy`, `rollbackDeployment`, `configureAutoscaling`,
#     `setNamespaceIsolation`, `getEventLog`/`replayEvents`,
#     `injectFailure`/`stopFailure`, `getCost`, `setSla`, `scaleFleet`,
#     `getFleet`. A microkernel laptop has no sidecar image, no canary and
#     no on-call rotation; each was a 2026-datacenter noun in a required
#     position, and each forced every backend to stub it.
#   * `start`/`stop`/`restart`/`enable`/`disable` — duplicated init.capnp's
#     control authority under a different identity type. One controller
#     remains; its identity is `T.ServiceId`.
#   * `injectSecrets` with `ServiceSecret.value :Text` — secrets inline
#     in the message, copied. Secret material belongs to secret.capnp
#     behind opaque handles.
#   * `ServiceCost` / `ServiceSla` / `ServiceSlaStatus` — per-request
#     pricing and uptime commitments. Also duplicated in discovery.capnp
#     under the same names with different fields; both copies are gone.
#   * `ServiceDependency` — duplicated in discovery.capnp. Discovery owns
#     it (a dependency is a fact about the service registry, not about
#     one running instance).
#   * `ServiceSecret`, `SidecarConfig`, `SidecarStatus`,
#     `DiscoveryConfig`, `DeploymentStrategy`, `DeploymentStatus`,
#     `AutoscalingConfig`, `AutoscalingStatus`, `NamespaceIsolationConfig`,
#     `ServiceEventEntry`, `ChaosFailure`, `ServiceFleet`,
#     `ServiceMetricsConfig` (a scrape endpoint config), `ServiceKind`
#     (systemDaemon/microservice/serverlessFunction/containerized — a
#     deployment taxonomy) — the type zoo that supported the above.
#   * `ServiceSecurityContext.capabilities :List(Text)` — authority as
#     free text. Now `List(Operation)`, the canonical vocabulary.
#
# ── HEALTH: TWO QUESTIONS, ONE ANSWER ──────────────────────────────────
#
# "Did the last check pass" (a probe) and "what is this service doing
# right now" (lifecycle) are different questions. A service can pass
# every probe and still be quarantined after a fault storm; reporting
# only the probe result is how a broken system looks fine.
# `ServiceHealth` carries both: the lifecycle state, the probe result,
# the quarantine flag, and the fault counters a quarantine threshold is
# measured against.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using D = import "discovery.capnp";
using import "capability.capnp".Capability;

# ── Observation (ungated) ───────────────────────────────────────────────

interface Service {
    # Bounded listing and lookup.
    listServices @0 (pagination :T.Pagination)
                -> (services :List(ServiceInstanceInfo), total :UInt64);
    getService @1 (serviceId :T.ServiceId) -> (info :ServiceInstanceInfo);

    # Current state of one service.
    getState @2 (serviceId :T.ServiceId) -> (state :ServiceInstanceState);
    # State change stream. Holding the subscription IS the authority.
    subscribeState @3 (serviceId :T.ServiceId) -> (subscription :ServiceStateSubscription);

    # Runtime health: lifecycle AND probe, one honest answer. The type
    # lives in discovery.capnp, which owns the registry-visible view of a
    # service; the pre-revamp copy here had a different shape.
    getHealth @4 (serviceId :T.ServiceId) -> (health :D.ServiceHealth);
    listHealth @5 (pagination :T.Pagination) -> (services :List(D.ServiceHealth), total :UInt64);
    # Services currently quarantined — running but not permitted to
    # serve. Distinct from failed: a quarantined service still consumes
    # resources and still has a handler published.
    listQuarantined @6 (pagination :T.Pagination) -> (services :List(D.ServiceHealth), total :UInt64);
    # Resolve a name to an id. Returns `present` rather than an error
    # when the name is unknown: a service that has not started yet is not
    # a failure to answer the question, it IS the answer.
    resolve @7 (name :Text) -> (serviceId :T.ServiceId, present :Bool);

    # Dependencies, from the canonical discovery contract.
    getDependencies @8 (serviceId :T.ServiceId) -> (dependencies :List(D.ServiceDependency));

    # Resource allocation and health-check configuration.
    getResourceAllocation @9 (serviceId :T.ServiceId) -> (allocation :ServiceResourceAllocation);
    getHealthCheck @10 (serviceId :T.ServiceId) -> (check :ServiceHealthCheck);

    # Runtime measurements, with a declared window so two backends cannot
    # answer "since when?" differently.
    getMetrics @11 (serviceId :T.ServiceId, window :T.Duration) -> (metrics :ServiceMetrics);

    # Service events. Holding the subscription IS the authority.
    subscribeServiceEvents @12 (serviceId :T.ServiceId) -> (subscription :ServiceEventSubscription);

    # ── The one gated surface ─────────────────────────────────
    # Every mutation in this schema lives behind this accessor. Authority
    # is the reference it returns; no method on ServiceControl takes a
    # token.
    control @13 (authority :Capability) -> (control :ServiceControl);
}

# ── Control (capability-gated at acquisition) ───────────────────────────

interface ServiceControl {
    # Dependencies (canonical discovery type).
    setDependencies @0 (serviceId :T.ServiceId, dependencies :List(D.ServiceDependency)) -> T.VoidResult;

    # Resource allocation (declared quota, platform-neutral).
    setResourceAllocation @1 (serviceId :T.ServiceId, allocation :ServiceResourceAllocation) -> T.VoidResult;

    # Health-check configuration.
    setHealthCheck @2 (serviceId :T.ServiceId, check :ServiceHealthCheck) -> T.VoidResult;

    # Configuration as an open map. The backend owns validation; the
    # protocol never freezes a config schema.
    updateConfig @3 (serviceId :T.ServiceId, config :T.StringMap) -> T.VoidResult;

    # Put a service into or out of quarantine. Requires the same
    # authority that could restart it.
    setQuarantine @4 (serviceId :T.ServiceId, quarantined :Bool, reason :Text) -> T.VoidResult;

    # Declared log level, over the canonical logging contract.
    setLogLevel @5 (serviceId :T.ServiceId, level :T.LogLevel) -> T.VoidResult;

    # Purge this service's retained metrics (the measurement store, not
    # the log store — that is logging.capnp's `clear`).
    clearMetrics @6 (serviceId :T.ServiceId) -> T.VoidResult;
}

interface ServiceStateSubscription {
    # Bounded pull.
    pull @0 (maxStates :UInt32) -> (states :List(ServiceInstanceState));
    cancel @1 () -> T.VoidResult;
}

# ── State ───────────────────────────────────────────────────────────────

struct ServiceInstanceInfo {
    id @0 :T.ServiceId;
    name @1 :Text;
    description @2 :Text;
    state @3 :ServiceInstanceState;
    enabled @4 :Bool;
    # Whether this service was started on demand (not at boot).
    onDemand @5 :Bool;
    # The manifest it was declared from, if any.
    manifest @6 :T.ManifestName;
}

# The state of one RUNNING service instance. Named `ServiceInstanceState`
# because discovery.capnp's `ServiceState` enum is the registry-visible
# lifecycle of a descriptor — the same name for two different kinds of
# type was the worst duplicate in the pair.
struct ServiceInstanceState {
    status @0 :ServiceStatus;
    # Which process currently holds the service's handler (zero = none).
    mainPid @1 :T.ProcessId;
    # When the service entered its current status.
    since @2 :T.Timestamp;
    # How long it has been in this status, as measured by the supervisor
    # that observed the transition. Zero with `sinceValid` false means "no
    # transition has been observed", not "it just changed".
    sinceUs @3 :UInt64;
    sinceValid @4 :Bool;
    # Running but not permitted to serve.
    quarantined @5 :Bool;
    # Why, whenever status is anything other than `active`. Never a
    # placeholder: a client that reads an empty reason should render
    # "unknown", not nothing.
    reason @6 :Text;
    metadata @7 :T.StringMap;
}

enum ServiceStatus {
    unknown @0;
    active @1;
    reloading @2;
    inactive @3;
    failed @4;
    activating @5;
    deactivating @6;
    custom @7;
}

# ── Health check configuration and measurements ─────────────────────────

struct ServiceHealthCheck {
    # Open target token: a channel id, a path, or whatever the backend
    # probes. The protocol never names a probe mechanism.
    endpoint @0 :Text;
    interval @1 :T.Duration;
    timeout @2 :T.Duration;
    unhealthyThreshold @3 :UInt32;
    healthyThreshold @4 :UInt32;
}

struct ServiceResourceAllocation {
    # Declared limits, platform-neutral (canonical T.Quota).
    quota @0 :T.Quota;
}

struct ServiceMetrics {
    serviceId @0 :T.ServiceId;
    # The window these numbers cover, so two backends cannot answer
    # "since when?" differently.
    window @1 :T.Duration;
    requestCount @2 :UInt64;
    errorCount @3 :UInt64;
    # Latency quantiles over the window (zero = not measured).
    latencyP50 @4 :T.Duration;
    latencyP95 @5 :T.Duration;
    latencyP99 @6 :T.Duration;
    # Active requests at the moment of the sample.
    activeRequests @7 :UInt32;
    # True when the backend could not measure some field in the window.
    partial @8 :Bool;
}

# ── Events ──────────────────────────────────────────────────────────────

struct ServiceEvent {
    union {
        stateChanged @0 :ServiceInstanceState;
        healthChanged @1 :D.ServiceHealth;
        configChanged @2 :T.StringMap;
        unknown @3 :T.UnknownEvent;
    }
    timestamp @4 :T.Timestamp;
    serviceId @5 :T.ServiceId;
}

enum ServiceEventType {
    unknown @0;
    started @1;
    stopped @2;
    failed @3;
    healthChanged @4;
    configChanged @5;
    custom @6;
}

interface ServiceEventSubscription {
    # Bounded pull.
    pull @0 (maxEvents :UInt32) -> (events :List(ServiceEvent));
    cancel @1 () -> T.VoidResult;
}

@0xa1b2c3d4e5f60041;

# ═══════════════════════════════════════════════════════════════════════
# Discovery — service registration and lookup.
#
# Zero-backend-assumption contract for service discovery. No mDNS, no
# DNS-SD, no platform-specific registry is assumed; the backend decides
# the mechanism. The protocol defines the contract: register a
# descriptor, look it up, watch it change, and know what state it is
# really in.
#
# ── AUTHORITY ───────────────────────────────────────────────────────────
#
# Lookup is ungated: a caller can learn what exists before it holds any
# authority (the ai.capnp rule — acquire-to-discover must not deadlock).
# Registration is gated once, at acquisition, through `Discovery.registry`:
# holding the returned `DiscoveryRegistry` reference IS the authority to
# register, deregister, update and deprecate. No method takes a token.
# The pre-revamp file let any caller register any service name, which on
# a single device is a hijack vector.
#
# ── THE SERVICE-MESH HALF, DELETED ─────────────────────────────────────
#
# The pre-revamp body embedded an enterprise service mesh beside the
# registry: per-request pricing, on-call rotations, canary traffic
# splitting, circuit breakers with HTTP retryable status codes,
# multi-region geo-distribution, changelogs and cluster health. One line
# contradicted the file's own header directly — `RetryPolicy
# .retryableStatusCodes :List(UInt16)`, commented "HTTP status codes
# that trigger retry", frozen into a contract that promises "no
# platform-specific registry assumed".
#
# All of it is gone. None of it exists on a single device, which is this
# protocol's core audience, and each field forced every backend to carry
# (and fake) 2015 org-chart and 2016 datacenter vocabulary. Deleted with
# it: `ServiceCost`, `ServiceOwnership`, `ServiceCanary`,
# `CircuitBreaker`, `CircuitState`, `RetryPolicy`,
# `ServiceGeoDistribution`, `ServiceRegion`, `ServiceChangelog`,
# `ChangelogEntry`, `ChangelogType`, `ClusterHealth`, `Liveness` +
# `heartbeat`.
#
# ── WHAT WAS IMPORTED FROM THE WORKING TREE ────────────────────────────
#
# The runtime-health block (`ServiceHealth`, `resolve` with `present`,
# `getRuntimeHealth`, `listRuntimeHealth`, `listQuarantined`) is a real,
# consumed contract: it answers "what is this service doing right now",
# which is a different question from "what did the last probe say". A
# service can pass every probe and be quarantined after a fault storm —
# and reporting only the probe result is how a broken system looks fine.
# `reason` is populated whenever the state is not `online`; an empty
# reason with a non-online state is a producer bug and a client should
# render "unknown".
#
# ── HOMES, UNIFIED ─────────────────────────────────────────────────────
#
# `ServiceDependency` is declared HERE and imported by service.capnp
# (which had its own copy with a different shape). `ServiceCost`,
# `ServiceSla` and their duplicates in service.capnp are deleted, not
# relocated: pricing and uptime commitments are datacenter vocabulary,
# not an OS contract. The health *result* type is `ServiceHealth`,
# declared here, also imported by service.capnp. System/component health
# (a different question) is diagnostics.capnp's `HealthStatus`.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using Diag = import "diagnostics.capnp";
using import "capability.capnp".Capability;

# ── Descriptor ──────────────────────────────────────────────────────────

struct ServiceDescriptor {
    id @0 :T.ServiceId;
    name @1 :Text;
    # Open category token ("media", "network", "storage", or a 2046 one).
    # Unknown tokens are ignored by consumers, never rejected.
    category @2 :Text;
    version @3 :VersionInfo;
    state @4 :ServiceState;
    # Structured endpoint addresses.
    endpoints @5 :List(ServiceEndpoint);
    metadata @6 :T.StringMap;
    # Capability ids a caller needs before using this service. Typed
    # references only: the pre-revamp `requiredCaps :List(Text)` beside
    # this field was a second, stringly-typed authority path that had to
    # agree with it forever.
    requiredCapabilityIds @7 :List(T.CapabilityId);
    # When this service was registered.
    registeredAt @8 :T.Timestamp;
    # Optional expiry for transient registrations. An expired
    # registration is filtered out of `lookup` and `getServiceByScope`,
    # emits an `expired` event first, and is then auto-deregistered — so a
    # consumer never reads a stale descriptor as live.
    expireAt @9 :T.Timestamp;
    # Tags for flexible categorisation beyond category.
    tags @10 :List(Text);
    # Deprecation metadata (absent = not deprecated).
    deprecation @11 :DeprecationInfo;
    # Attestation, if the service published one.
    attestation @12 :ServiceAttestation;
}

struct VersionInfo {
    version @0 :T.Version;
    # Minimum backward-compatible version.
    minCompatible @1 :T.Version;
    # The version that replaces this one (zero = no replacement).
    succeededBy @2 :T.Version;
}

enum ServiceState {
    unknown @0;
    online @1;
    offline @2;
    degraded @3;
    starting @4;
    maintenance @5;
    custom @6;
}

# A structured endpoint. The transport is an OPEN token: this file names
# no protocol, and a 2046 transport needs no ordinal.
struct ServiceEndpoint {
    # Open transport token ("capnp", "rest", "grpc", or a 2046 one).
    transport @0 :Text;
    # Transport address in the transport's own vocabulary.
    address @1 :Text;
    # Priority among the service's endpoints (lower = preferred).
    priority @2 :UInt32;
    metadata @3 :T.StringMap;
}

# ── Runtime health ──────────────────────────────────────────────────────
# The lifecycle question, as distinct from diagnostics' probe question.
# Both are real and they diverge.

struct ServiceHealth {
    serviceId @0 :T.ServiceId;
    # Current lifecycle state as discovery sees it.
    state @1 :ServiceState;
    # Why, whenever state is not `online`. Never a placeholder.
    reason @2 :Text;
    # Running but not permitted to serve. A quarantined service still
    # holds a handler slot and consumes resources, which is exactly why
    # it needs its own field.
    quarantined @3 :Bool;
    # How long the service has been in this state, in microseconds, as
    # measured by whoever observed the transition. `sinceValid` false
    # means no transition has been observed, NOT "it changed zero
    # microseconds ago".
    sinceUs @4 :UInt64;
    sinceValid @5 :Bool;
    # The last probe result. Distinct from `state`: a service can be
    # `online` and failing its probe.
    lastCheckPassed @6 :Bool;
    lastCheckAt @7 :T.Timestamp;
    # Faults taken since the service was last started. Never reset by a
    # passing probe — only a restart resets it. This is the counter a
    # quarantine threshold is measured against.
    faultCount @8 :UInt64;
    # Consecutive faults, for "is it flapping". Always ≤ faultCount.
    consecutiveFaults @9 :UInt32;
    # Restarts since last start.
    restarts @10 :UInt32;
}

# ── Dependencies, deprecation, attestation ──────────────────────────────
# The canonical dependency type: imported by service.capnp rather than
# declared a second time with a different shape.

struct ServiceDependency {
    # Service that is depended upon.
    serviceId @0 :T.ServiceId;
    dependencyType @1 :DependencyType;
    # Version constraint, as an open token (e.g. ">=1.0.0").
    versionConstraint @2 :Text;
    # Whether this dependency is currently satisfied.
    satisfied @3 :Bool;
}

enum DependencyType {
    unknown @0;
    required @1;
    optional @2;
    custom @3;
}

struct DeprecationInfo {
    # When this service was deprecated.
    deprecatedAt @0 :T.Timestamp;
    # What replaces it (zero = nothing).
    succeededBy @1 :T.ServiceId;
    # Human-readable reason.
    reason @2 :Text;
}

struct ServiceAttestation {
    # Attestation type as an OPEN token ("tpm", "sgx", "cosigning", or a
    # 2046 one) — this file already used the open pattern correctly.
    attestationType @0 :Text;
    # The attestation bytes, opaque and zero-copy.
    proof @1 :T.DataHandle;
    verifiedAt @2 :T.Timestamp;
    # Whether the attestation was verified against a trust root.
    verified @3 :Bool;
}

struct ServiceVersionCheck {
    serviceId @0 :T.ServiceId;
    clientVersion @1 :T.Version;
    compatible @2 :Bool;
    # The version the caller should use instead (zero = none).
    recommendedVersion @3 :T.Version;
    reason @4 :Text;
}

struct ServicePatch {
    state @0 :ServiceState;
    endpoints @1 :List(ServiceEndpoint);
    metadata @2 :T.StringMap;
    expireAt @3 :T.Timestamp;
    tags @4 :List(Text);
    # Deprecation update.
    deprecation @5 :DeprecationInfo;
    # Fields to explicitly unset, by name.
    clearFields @6 :List(Text);
}

# ── Filter ──────────────────────────────────────────────────────────────

struct DiscoveryFilter {
    name @0 :Text;
    # Open category token (empty = all).
    category @1 :Text;
    search @2 :Text;
    states @3 :List(ServiceState);
    requiredMetadata @4 :List(Text);
    tags @5 :List(Text);
    page @6 :T.Pagination;
    # Only return services whose runtime health is at least this state.
    healthState @7 :Diag.HealthState;
    # Exclude deprecated services.
    excludeDeprecated @8 :Bool;
    # Restrict to this isolation scope.
    scope @9 :T.IsolatedScope;
}

# ── The discovery contract ──────────────────────────────────────────────
# The root of the discovery domain: handed to the caller by the host, so
# it is deliberately not returned by any method. `DiscoveryRegistry` IS
# returned (by `registry`), and `DiscoverySubscription` by `subscribe`.

interface Discovery {
    # ── Ungated: discovery is open, so a caller can learn before it acts ──
    # Bounded lookup.
    lookup @0 (filter :DiscoveryFilter) -> (services :List(ServiceDescriptor), total :UInt64);
    get @1 (serviceId :T.ServiceId) -> (descriptor :ServiceDescriptor);

    # Resolve a name to a descriptor. Returns `present` rather than an
    # error when the name is unknown: a service that has not started yet
    # is not a failure to answer the question, it is the answer.
    resolve @2 (name :Text) -> (descriptor :ServiceDescriptor, present :Bool);

    # Watch registrations change. Holding the subscription IS the
    # authority to pull.
    subscribe @3 (filter :DiscoveryFilter) -> (subscription :DiscoverySubscription);

    # Runtime health of one service, as opposed to the descriptor's
    # declared `state`.
    getRuntimeHealth @4 (serviceId :T.ServiceId) -> (health :ServiceHealth);
    # Runtime health of every registered service.
    listRuntimeHealth @5 (pagination :T.Pagination) -> (services :List(ServiceHealth), total :UInt64);
    # Services running but quarantined from serving. Distinct from
    # offline: these still hold a handler slot and consume resources.
    listQuarantined @6 (pagination :T.Pagination) -> (services :List(ServiceHealth), total :UInt64);

    # Dependencies, from the canonical type.
    getServiceDependencies @7 (serviceId :T.ServiceId, pagination :T.Pagination)
                          -> (dependencies :List(ServiceDependency), total :UInt64);
    getDependents @8 (serviceId :T.ServiceId, pagination :T.Pagination)
                 -> (dependents :List(ServiceDependency), total :UInt64);

    # Deprecated services.
    listDeprecatedServices @9 (pagination :T.Pagination)
                          -> (services :List(ServiceDescriptor), total :UInt64);

    # Version compatibility (ABI-level negotiation is abi.capnp's
    # `negotiate`; this answers the per-service question).
    checkVersionCompatibility @10 (serviceId :T.ServiceId, clientVersion :T.Version)
                             -> (check :ServiceVersionCheck);

    # Lookup by scope — a caller inside an isolation tier sees only what
    # its tier may see.
    getServiceByScope @11 (scope :T.IsolatedScope, pagination :T.Pagination)
                     -> (services :List(ServiceDescriptor), total :UInt64);

    # ── The one gated surface ────────────────────────────────
    # Registration, deregistration, update and deprecation. Holding the
    # returned reference IS the authority; no method takes a token.
    registry @12 (authority :Capability) -> (service :DiscoveryRegistry);
}

interface DiscoveryRegistry {
    # Register a service. A registration whose `expireAt` has passed is
    # rejected; a live registration with the same id is replaced only by
    # the holder of this reference.
    register @0 (descriptor :ServiceDescriptor) -> T.VoidResult;

    # Deregister a service.
    deregister @1 (serviceId :T.ServiceId) -> T.VoidResult;

    # Unified partial update — any field of the patch may be set.
    update @2 (serviceId :T.ServiceId, patch :ServicePatch) -> T.VoidResult;

    # Mark a service deprecated (the pre-revamp separate
    # updateState/updateMetadata/updateEndpoints paths are folded in:
    # the patch carries all three).
    deprecateService @3 (serviceId :T.ServiceId, info :DeprecationInfo) -> T.VoidResult;

    # Declare which categories a scope may see. Discovery then honours the
    # boundary in `lookup` and `getServiceByScope`.
    setScopeBoundary @4 (scopeId :T.ScopeId, allowedCategories :List(Text)) -> T.VoidResult;
}

interface DiscoverySubscription {
    # Bounded pull: the caller states how many events it will take, so a
    # registration burst cannot flood one message.
    pull @0 (maxEvents :UInt32) -> (events :List(DiscoveryEvent));
    cancel @1 () -> T.VoidResult;
}

struct DiscoveryEvent {
    timestamp @0 :T.Timestamp;
    union {
        registered @1 :ServiceDescriptor;
        deregistered @2 :T.ServiceId;
        stateChanged @3 :ServiceStateChange;
        metadataChanged @4 :MetadataChange;
        endpointsChanged @5 :EndpointsChange;
        expired @6 :T.ServiceId;
        healthChanged @7 :ServiceHealth;
        deprecated @8 :DeprecationInfo;
        unknown @9 :T.UnknownEvent;
    }
}

struct ServiceStateChange {
    serviceId @0 :T.ServiceId;
    oldState @1 :ServiceState;
    newState @2 :ServiceState;
}

struct MetadataChange {
    serviceId @0 :T.ServiceId;
    metadata @1 :T.StringMap;
}

struct EndpointsChange {
    serviceId @0 :T.ServiceId;
    endpoints @1 :List(ServiceEndpoint);
}

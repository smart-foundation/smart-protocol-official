@0xa1b2c3d4e5f60060;

# ═══════════════════════════════════════════════════════════════════════
# Runtime Search - dynamic discovery of runtime services, capabilities,
#                  WASM modules, plugins, and IPC endpoints.
#
# This is the runtime counterpart to system_search.capnp (which is
# content-centric). Where system_search catalogs *what is stored*,
# runtime_search catalogs *what is currently providing*.
#
# That split is principled and is kept: the two files have disjoint
# consumers (this one is the service-manager-facing dependency surface),
# different truth conditions (instances are ephemeral, heartbeat-ed and
# state-machined; content is durable and indexed), and no shared type
# names beyond the genuine cross-collisions with logging/klog/discovery
# and discovery/service. Merging them would produce one file whose two
# halves disagree on the meaning of "query" and "result".
#
# Backend-agnostic: works with WASM runtimes, microservices, plugin
# systems, dynamic linkers, or any other mechanism that produces
# discoverable runtime units.
#
# ── THE SERVICE-MESH CONTROL PLANE WAS CUT ────────────────────────────
#
# This file had grown into a service-mesh orchestrator: cost models
# (getCostModel/setCostModel), live migration (migrateService/
# getMigrationStatus), a catalog with SLAs, ownership, on-call rotations,
# API docs and changelogs (getCatalogEntry/setCatalogEntry/searchCatalog/
# getCatalogStats), a fourth observability stack beside logging, klog and
# diagnostics (getServiceLogs/getServiceMetrics/getTrace) and lifecycle
# hooks (registerLifecycleHook/unregisterLifecycleHook).
#
# Not one of those fifteen methods had a consumer in the protocol. They
# are deleted, along with the twenty types that existed only to serve
# them. This is optimization, not capability loss: a discovery contract
# is what remains, and the observability/catalog concerns belong to the
# services that own them (logging.capnp, diagnostics.capnp) once they
# have a consumer.
#
# ── NO PARALLEL PERMISSION MODEL ───────────────────────────────────────
#
# The local `Capability` struct (which collided by name with
# capability.capnp's and had a different shape), `CapabilityPermission`,
# `PermissionDomain` (15 values) and `PermissionAccess` (7 values) were a
# third authority vocabulary in the batch. An instance's advertised
# authority is a Capability with a target and operations — nothing more.
# Implementers no longer have to invent a mapping from
# PermissionDomain.filesystemRead to Operation.read, because there is
# only one vocabulary.
#
# ── RUNTIME KIND IS AN OPEN TOKEN ──────────────────────────────────────
#
# `RuntimeKind` froze unixDaemon, windowsService, jsRuntime,
# pythonRuntime and luaRuntime into a required position, in a file whose
# header claims backend-agnosticism. Because the query filters on kind,
# a seL4-class runtime, a BEAM process, a GraalVM native image or a 2046
# mechanism was undiscoverable — it had only `custom` carrying nothing.
# Kind is now an open token published as a conformance const, so any
# runtime is discoverable and the stats map can report it consistently.
#
# Improvements (audit-3):
#   - RuntimeInstance references the canonical capability.capnp
#     Capability (was a local struct of the same name and different shape).
#   - RuntimeSearchSubscription.pullPage adds paginated variant.
#   - RuntimeSearchSubscription.pull deprecated in favor of pullPage
#     for bounded result sets (audit-5, Rule 9).
#
# Audit-7 improvements (kept — these are discovery contract, not mesh):
#   - TtlPolicy for ephemeral service auto-deregistration.
#   - HealthCheck for proactive failure detection.
#   - RuntimeServiceDependency for dependency declaration.
#   - VersionConstraint for semantic version compatibility.
#   - AttestationRequirement for confidential computing.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ── Runtime Instance ───────────────────────────────────────────────────

struct RuntimeInstance {
    # Stable identifier for this instance (across restarts if persistent).
    instanceId @0 :T.RuntimeInstanceId;
    # Final ID assigned by the registry backend.
    registryId @1 :T.ServiceId;
    # Display name (human-readable).
    name @2 :Text;
    # Semantic version.
    version @3 :T.Version;
    # Runtime kind, as an open token (see CONFORMANCE TOKENS): a WASM
    # module, a microservice, an IPC service, or a mechanism not yet
    # invented. An unrecognized token is ignored, never rejected.
    kind @4 :Text;
    # Where the runtime unit lives. Open token: the caller learns from
    # `locationKind` whether to open a URI or pass a handle back, so it
    # no longer has to sniff the string.
    location @5 :Text;
    locationKind @6 :Text;
    # Authority this instance advertises, as canonical Capability
    # references (target + operations).
    capabilities @7 :List(Capability);
    # Network/in-process endpoint (if reachable).
    endpoint @8 :Text;
    # State (startup, ready, draining, stopped, error).
    state @9 :RuntimeState;
    # Backend metadata.
    metadata @10 :T.StringMap;
    # When the instance was registered.
    registeredAt @11 :T.Timestamp;
    # Heartbeat / last-known-alive.
    lastSeenAt @12 :T.Timestamp;
    # Whether the instance persists across reboots.
    persistent @13 :Bool;
    # Whether it survives process restarts.
    resilient @14 :Bool;
    # Resource usage (if known).
    resources @15 :T.ResourceUsage;
    # Session or user this instance is associated with.
    scope @16 :RuntimeScope;
    # Trust tier (lower is more trusted).
    trust @17 :T.TrustLevel;
    # TTL-based auto-deregistration policy (empty = never auto-deregister).
    ttlPolicy @18 :TtlPolicy;
    # Health check configuration.
    healthCheck @19 :HealthCheck;
    # Dependencies on other services.
    dependencies @20 :List(RuntimeServiceDependency);
    # Version constraint for consumers.
    versionConstraint @21 :RuntimeVersionConstraint;
    # Discovery topology, as an open token. The previous enum named
    # broadcast and multicast — specific network technologies — so a
    # DHT-, gossip- or rendezvous-hash-based mechanism had only `custom`.
    discoveryMode @22 :Text;
    # Scaling state.
    scaling @23 :ServiceScaling;
    # What this instance requires of a caller to reach it, as an open
    # token. The previous ServiceAuth enum named mechanisms (mtls, token,
    # apiKey); a backend that authenticates by capability reference has
    # no value in that list, and authority itself is capability.capnp's
    # job, not an advertisement here.
    auth @24 :Text;
    # Attestation requirement.
    attestation @25 :AttestationRequirement;
}

# ── TTL Policy ─────────────────────────────────────────────────────────

struct TtlPolicy {
    # Maximum time between registrations before auto-deregistration.
    registrationTtl @0 :T.Duration;
    # Heartbeat interval (instance must send heartbeat within this window).
    heartbeatInterval @1 :T.Duration;
    # Number of missed heartbeats before marking as failed.
    failureThreshold @2 :UInt32;
    # Whether TTL-based auto-deregistration is enabled.
    enabled @3 :Bool;
    custom @4 :T.StringMap;
}

# ── Health Check ───────────────────────────────────────────────────────

struct HealthCheck {
    # Health check endpoint (path or method name).
    endpoint @0 :Text;
    # How often to check health.
    interval @1 :T.Duration;
    # Timeout for each health check.
    timeout @2 :T.Duration;
    # Consecutive failures before marking unhealthy.
    unhealthyThreshold @3 :UInt32;
    # Consecutive successes before marking healthy.
    healthyThreshold @4 :UInt32;
    # Whether health checking is enabled.
    enabled @5 :Bool;
    custom @6 :T.StringMap;
}

# ── Service Dependency ──────────────────────────────────────────────────

struct RuntimeServiceDependency {
    # Service ID of the dependency.
    serviceId @0 :T.ServiceId;
    # Whether this dependency is required for startup.
    required @1 :Bool;
    # Version constraint (e.g., ">=1.0.0").
    versionConstraint @2 :Text;
    # Human-readable description of why this dependency exists.
    reason @3 :Text;
}

# ── Version Constraint ─────────────────────────────────────────────────
# Named RuntimeVersionConstraint because discovery.capnp declares a
# `VersionConstraint` of its own; two same-named types with different
# shapes is an import hazard.

struct RuntimeVersionConstraint {
    # Minimum compatible version.
    minVersion @0 :T.Version;
    # Maximum compatible version.
    maxVersion @1 :T.Version;
    # Specific version this must be compatible with.
    compatibleWith @2 :T.Version;
}

# ── Discovery Mode ─────────────────────────────────────────────────────
# Open token; see CONFORMANCE TOKENS. Replaces an enum that named
# broadcast and multicast as permanent ordinals.

# ── Service Scaling ────────────────────────────────────────────────────

struct ServiceScaling {
    # Desired number of replicas.
    desiredReplicas @0 :UInt32;
    # Minimum replicas.
    minReplicas @1 :UInt32;
    # Maximum replicas.
    maxReplicas @2 :UInt32;
    # Current number of replicas.
    currentReplicas @3 :UInt32;
    # Whether auto-scaling is enabled.
    autoScaling @4 :Bool;
    custom @5 :T.StringMap;
}

# ── Attestation Requirement ────────────────────────────────────────────

struct AttestationRequirement {
    # Whether attestation is required.
    required @0 :Bool;
    # Expected attestor, as an open token ("tpm", "sgx", ...). Open
    # because a 2046 confidential-computing mechanism is not in any list
    # written in 2026.
    attestorType @1 :Text;
    # Policy for attestation verification.
    policy @2 :Text;
    custom @3 :T.StringMap;
}

# ── Runtime Kind ────────────────────────────────────────────────────────
# Open token; see CONFORMANCE TOKENS below.

enum RuntimeState {
    unknown @0;
    registered @1;
    resolving @2;
    starting @3;
    ready @4;
    draining @5;
    stopped @6;
    failed @7;
    suspended @8;
    upgrading @9;
    custom @10;
}

# ── Runtime Scope ───────────────────────────────────────────────────────

struct RuntimeScope {
    # Which user session owns this instance.
    userId @0 :T.UserId;
    # Which session ID this instance belongs to (empty = system).
    sessionId @1 :T.SessionId;
    # Which application spawned this instance.
    appId @2 :T.AppId;
}

# ── Search Query ────────────────────────────────────────────────────────

struct RuntimeSearchQuery {
    # Filter by free-text match against name/display.
    query @0 :Text;
    # Filter by exact kinds (open tokens).
    kinds @1 :List(Text);
    # Filter by capability names advertised.
    capabilities @2 :List(Text);
    # Filter by state.
    states @3 :List(RuntimeState);
    # Filter by scope (any-not-empty field narrows).
    scopeUserId @4 :T.UserId;
    scopeSessionId @5 :T.SessionId;
    scopeAppId @6 :T.AppId;
    # Trust filter: only show instances at or above this trust level.
    minTrust @7 :T.TrustLevel;
    # Whether to include persistent or only live instances.
    persistentOnly @8 :Bool;
    # Pagination.
    pagination @9 :T.Pagination;
    # Sort order.
    sort @10 :RuntimeSort;
    # Filter by discovery mode (open token).
    discoveryMode @11 :Text;
    # Filter by attestation requirement.
    requireAttestation @12 :Bool;
    # Filter by minimum scaling replicas.
    minReplicas @13 :UInt32;
    custom @14 :T.StringMap;
}

enum RuntimeSort {
    unspecified @0;   # Sentinel: an unset sort is not "newestFirst"
    newestFirst @1;
    nameAscending @2;
    trustLevel @3;
    resourceLightest @4;
    custom @5;
}

# ── Search Result ───────────────────────────────────────────────────────

struct RuntimeSearchResult {
    instances @0 :List(RuntimeInstance);
    # Total count for pagination.
    total @1 :UInt64;
    # Whether the result was cached or freshly enumerated.
    cached @2 :Bool;
    # When the snapshot was taken.
    snapshotAt @3 :T.Timestamp;
}

# ── Capability Index ────────────────────────────────────────────────────

struct CapabilityIndex {
    # All instances advertising a given capability name.
    capability @0 :Text;
    instances @1 :List(T.RuntimeInstanceId);
}

# ── Event Stream ────────────────────────────────────────────────────────

struct RuntimeSearchEvent {
    timestamp @0 :T.Timestamp;
    instanceId @1 :T.RuntimeInstanceId;
    union {
        registered @2 :RuntimeInstance;
        unregistered @3 :T.RuntimeInstanceId;
        stateChanged @4 :RuntimeStateChange;
        # Named to avoid the collision with system.capnp's
        # CapabilityChange (a list-diff vs a name/oldValue/newValue
        # triple — two unrelated shapes, one name).
        advertisedCapabilitiesChanged @5 :AdvertisedCapabilitiesChanged;
        heartbeatChanged @6 :HeartbeatEvent;
        # Forward compatibility: an event kind this schema does not name
        # arrives here with a typed discriminator, instead of a raw
        # Data payload no consumer can key. The file previously used
        # `custom @7 :Data`, which is the right primitive with the
        # wrong name.
        unknown @7 :T.UnknownEvent;
    }
}

struct RuntimeStateChange {
    fromState @0 :RuntimeState;
    toState @1 :RuntimeState;
    reason @2 :Text;
}

struct AdvertisedCapabilitiesChanged {
    added @0 :List(Capability);
    removed @1 :List(Capability);
    metadata @2 :T.StringMap;
}

struct HeartbeatEvent {
    lastSeenAt @0 :T.Timestamp;
    alive @1 :Bool;
}

# ── Filter ──────────────────────────────────────────────────────────────

struct RuntimeSearchFilter {
    kinds @0 :List(Text);
    states @1 :List(RuntimeState);
    # Subscribe to all events (no filter).
    watchAll @2 :Bool;
}

# ── Service ─────────────────────────────────────────────────────────────

interface RuntimeSearchService {
    # Search for runtime instances matching the query.
    findServices @0 (query :RuntimeSearchQuery) -> (result :RuntimeSearchResult);

    # Fast lookup by capability — returns just the instance ids.
    findCapabilities @1 (capabilityNames :List(Text), pagination :T.Pagination)
        -> (indices :List(CapabilityIndex), total :UInt64);

    # Direct lookup by registry id.
    getInstance @2 (instanceId :T.RuntimeInstanceId) -> (instance :RuntimeInstance);

    # Subscribe to live changes (stream-based, pull-style).
    subscribe @3 (filter :RuntimeSearchFilter) -> (subscription :RuntimeSearchSubscription);

    # Snapshot of current states (no events, just full enumeration).
    snapshot @4 (query :RuntimeSearchQuery) -> (result :RuntimeSearchResult);

    # Capability introspection — list all distinct capabilities advertised.
    listCapabilities @5 (pagination :T.Pagination)
        -> (capabilities :List(Capability), total :UInt64);

    # Aggregate statistics about the runtime registry.
    getStats @6 () -> (stats :RuntimeSearchStats);

    # ── Dependency Resolution ──
    getDependencies @7 (instanceId :T.RuntimeInstanceId, pagination :T.Pagination)
                    -> (dependencies :List(RuntimeServiceDependency), total :UInt64);
    getDependents @8 (instanceId :T.RuntimeInstanceId, pagination :T.Pagination)
                  -> (dependents :List(RuntimeServiceDependency), total :UInt64);

    # ── Version Checking ──
    checkVersionCompatibility @9 (instanceId :T.RuntimeInstanceId, clientVersion :T.Version)
                              -> (compatible :Bool, minRequired :T.Version, latestAvailable :T.Version);

    # ── Scaling ──
    getScalingState @10 (instanceId :T.RuntimeInstanceId) -> (scaling :ServiceScaling);
}

struct RuntimeSearchStats {
    totalInstances @0 :UInt64;
    # Counts by kind and by state, keyed by the open tokens above so a
    # backend never has to invent a string spelling for a typed value
    # it already has.
    byKind @1 :T.StringMap;
    byState @2 :T.StringMap;
    # Total unique capabilities advertised.
    capabilitiesCount @3 :UInt64;
    # Last registry mutation.
    lastMutation @4 :T.Timestamp;
}

interface RuntimeSearchSubscription {
    # DEPRECATED: Use pullPage instead. Unbounded event lists risk memory
    # exhaustion on long-lived subscriptions with high event throughput.
    pull @0 () -> (events :List(RuntimeSearchEvent));
    cancel @1 () -> T.VoidResult;
    # Paginated variant of pull for large event streams.
    pullPage @2 (pagination :T.Pagination) -> (events :List(RuntimeSearchEvent), total :UInt64);
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Today's spellings for the open `kind` and `discoveryMode` tokens above.
# Nothing requires them; an unrecognized token MUST be ignored rather
# than rejected, which is what lets a 2046 runtime be discoverable the
# day a backend ships it — no schema amendment, and no `custom` slot that
# carries nothing.
# ══════════════════════════════════════════════════════════════════════

const kindWasmModule    :Text = "wasm-module";
const kindWasmComponent :Text = "wasm-component";
const kindNativePlugin  :Text = "native-plugin";
const kindMicroservice  :Text = "microservice";
const kindIpcService    :Text = "ipc-service";

const discoveryCentralRegistry :Text = "central-registry";
const discoveryP2pMesh         :Text = "p2p-mesh";
const discoveryHybrid          :Text = "hybrid";

const locationUri    :Text = "uri";
const locationHandle :Text = "handle";
const locationPath   :Text = "path";

@0xa1b2c3d4e5f60060;

# ═══════════════════════════════════════════════════════════════════════
# Runtime Search - dynamic discovery of runtime services, capabilities,
#                  WASM modules, plugins, and IPC endpoints.
#
# This is the runtime counterpart to system_search.capnp (which is
# content-centric). Where system_search catalogs *what is stored*,
# runtime_search catalogs *what is currently providing*.
#
# Backend-agnostic: works with WASM runtimes, microservices, plugin
# systems, dynamic linkers, or any other mechanism that produces
# discoverable runtime units.
#
# Improvements (audit-3):
#   - Capability.id uses T.CapabilityId (was bare Text).
#   - RuntimeSearchSubscription.pullPage adds paginated variant.
#   - RuntimeSearchSubscription.pull deprecated in favor of pullPage
#     for bounded result sets (audit-5, Rule 9).
#
# Audit-7 improvements:
#   - TtlPolicy for ephemeral service auto-deregistration.
#   - HealthCheck for proactive failure detection.
#   - ServiceDependency for dependency declaration.
#   - VersionConstraint for semantic version compatibility.
#   - DiscoveryMode for mixed discovery topologies.
#   - ServiceScaling for horizontal scaling state.
#   - ServiceAuth for service-to-service authentication.
#   - AttestationRequirement for confidential computing.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

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
    # Runtime kind (WASM module, native plugin, IPC service, etc.).
    kind @4 :RuntimeKind;
    # Where the runtime unit lives (URI/handle/path-agnostic).
    location @5 :Text;
    # Capabilities this instance exposes.
    capabilities @6 :List(Capability);
    # Network/in-process endpoint (if reachable).
    endpoint @7 :Text;
    # State (startup, ready, draining, stopped, error).
    state @8 :RuntimeState;
    # Backend metadata.
    metadata @9 :T.StringMap;
    # When the instance was registered.
    registeredAt @10 :T.Timestamp;
    # Heartbeat / last-known-alive.
    lastSeenAt @11 :T.Timestamp;
    # Whether the instance persists across reboots.
    persistent @12 :Bool;
    # Whether it survives process restarts.
    resilient @13 :Bool;
    # Resource usage (if known).
    resources @14 :T.ResourceUsage;
    # Session or user this instance is associated with.
    scope @15 :RuntimeScope;
    # Trust tier (lower is more trusted).
    trust @16 :T.TrustLevel;
    # TTL-based auto-deregistration policy (empty = never auto-deregister).
    ttlPolicy @17 :TtlPolicy;
    # Health check configuration.
    healthCheck @18 :HealthCheck;
    # Dependencies on other services.
    dependencies @19 :List(ServiceDependency);
    # Version constraint for consumers.
    versionConstraint @20 :VersionConstraint;
    # Discovery topology.
    discoveryMode @21 :DiscoveryMode;
    # Scaling state.
    scaling @22 :ServiceScaling;
    # Authentication method for this instance.
    auth @23 :ServiceAuth;
    # Attestation requirement.
    attestation @24 :AttestationRequirement;
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
}

# ── Service Dependency ──────────────────────────────────────────────────

struct ServiceDependency {
    # Service ID of the dependency.
    serviceId @0 :T.ServiceId;
    # Whether this dependency is required for startup.
    required @1 :Bool;
    # Version constraint (e.g., ">=1.0.0").
    versionConstraint @2 :Text;
    # Whether this dependency is optional.
    optional @3 :Bool;
    # Human-readable description of why this dependency exists.
    reason @4 :Text;
}

# ── Version Constraint ─────────────────────────────────────────────────

struct VersionConstraint {
    # Minimum compatible version.
    minVersion @0 :T.Version;
    # Maximum compatible version.
    maxVersion @1 :T.Version;
    # Specific version this must be compatible with.
    compatibleWith @2 :T.Version;
}

# ── Discovery Mode ─────────────────────────────────────────────────────

enum DiscoveryMode {
    # Central registry (default).
    centralRegistry @0;
    # Peer-to-peer mesh discovery.
    p2pMesh @1;
    # Broadcast announcement.
    broadcast @2;
    # Multicast group.
    multicast @3;
    # Hybrid (multiple modes).
    hybrid @4;
    custom @5;
}

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
}

# ── Service Auth ───────────────────────────────────────────────────────

enum ServiceAuth {
    # No authentication required.
    none @0;
    # Mutual TLS.
    mtls @1;
    # Token-based (bearer, JWT).
    token @2;
    # API key.
    apiKey @3;
    custom @4;
}

# ── Attestation Requirement ────────────────────────────────────────────

struct AttestationRequirement {
    # Whether attestation is required.
    required @0 :Bool;
    # Expected attestor type (e.g., "tpm", "sgx", "cosigning").
    attestorType @1 :Text;
    # Policy for attestation verification.
    policy @2 :Text;
}

# ── Runtime Kind ────────────────────────────────────────────────────────

enum RuntimeKind {
    unknown @0;
    wasmModule @1;
    wasmComponent @2;
    nativePlugin @3;
    nativeLibrary @4;
    microservice @5;
    ipcService @6;
    unixDaemon @7;
    windowsService @8;
    scriptRuntime @9;
    jsRuntime @10;
    pythonRuntime @11;
    luaRuntime @12;
    containerized @13;
    unikernel @14;
    custom @15;
}

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

# ── Capability ──────────────────────────────────────────────────────────

struct Capability {
    id @0 :T.CapabilityId;
    # Symbolic capability name (e.g. "filesystem.read", "network.connect").
    name @1 :Text;
    # Typed capability reference.
    permission @2 :CapabilityPermission;
    # Description of what this capability allows.
    description @3 :Text;
    # Whether the capability is advertised vs internal.
    advertised @4 :Bool;
}

struct CapabilityPermission {
    # Typed permission dimension. Backend-agnostic.
    domain @0 :PermissionDomain;
    # Specific resource within that domain (filesystem path, network name).
    scope @1 :Text;
    # Whether read or write or both.
    access @2 :PermissionAccess;
}

enum PermissionDomain {
    unknown @0;
    filesystemRead @1;
    filesystemWrite @2;
    networkConnect @3;
    networkListen @4;
    deviceHardware @5;
    devicePeripheral @6;
    processManagement @7;
    userData @8;
    userIdentity @9;
    systemConfiguration @10;
    cryptographicOperation @11;
    systemLogging @12;
    backgroundWork @13;
    custom @14;
}

enum PermissionAccess {
    none @0;
    read @1;
    write @2;
    invoke @3;
    subscribe @4;
    execute @5;
    debug @6;
    custom @7;
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
    # Filter by exact kinds.
    kinds @1 :List(RuntimeKind);
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
    # Filter by discovery mode.
    discoveryMode @11 :DiscoveryMode;
    # Filter by attestation requirement.
    requireAttestation @12 :Bool;
    # Filter by minimum scaling replicas.
    minReplicas @13 :UInt32;
}

enum RuntimeSort {
    # Sort by registration time (newest first).
    newestFirst @0;
    # By name alphabetically.
    nameAscending @1;
    # By trust level (most-trusted first).
    trustLevel @2;
    # By resource consumption (smallest first).
    resourceLightest @3;
    custom @4;
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
    # All instances advertising a given capability.
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
        capabilitiesChanged @5 :CapabilityChange;
        heartbeatChanged @6 :HeartbeatEvent;
        # Unknown or backend-specific event type.
        custom @7 :Data;
    }
}

struct RuntimeStateChange {
    fromState @0 :RuntimeState;
    toState @1 :RuntimeState;
    reason @2 :Text;
}

struct CapabilityChange {
    added @0 :List(Capability);
    removed @1 :List(Capability);
}

struct HeartbeatEvent {
    lastSeenAt @0 :T.Timestamp;
    alive @1 :Bool;
}

# ── Filter ──────────────────────────────────────────────────────────────

struct RuntimeSearchFilter {
    kinds @0 :List(RuntimeKind);
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
                    -> (dependencies :List(ServiceDependency), total :UInt64);
    getDependents @8 (instanceId :T.RuntimeInstanceId, pagination :T.Pagination)
                  -> (dependents :List(ServiceDependency), total :UInt64);

    # ── Version Checking ──
    checkVersionCompatibility @9 (instanceId :T.RuntimeInstanceId, clientVersion :T.Version)
                              -> (compatible :Bool, minRequired :T.Version, latestAvailable :T.Version);

    # ── Scaling ──
    getScalingState @10 (instanceId :T.RuntimeInstanceId) -> (scaling :ServiceScaling);

    # ── Service Catalog (false positive: service_catalog.capnp) ──

    # Get catalog entry for a service instance.
    getCatalogEntry @11 (instanceId :T.RuntimeInstanceId) -> (entry :ServiceCatalogEntry);

    # Update catalog entry for a service instance.
    setCatalogEntry @12 (entry :ServiceCatalogEntry) -> T.VoidResult;

    # Search the service catalog by name, description, or tags.
    searchCatalog @13 (query :Text, pagination :T.Pagination) -> (entries :List(ServiceCatalogEntry), total :UInt32);

    # Get the service catalog summary (counts by tag, ownership).
    getCatalogStats @14 () -> (stats :CatalogStats);

    # ── Audit-9: Service Cost Model ──

    # Get the cost model for a service instance.
    getCostModel @15 (instanceId :T.RuntimeInstanceId) -> (cost :ServiceCostModel);

    # Set the cost model for a service instance.
    setCostModel @16 (instanceId :T.RuntimeInstanceId, cost :ServiceCostModel) -> T.VoidResult;

    # ── Audit-9: Service Migration ──

    # Initiate live migration of a service instance to another node.
    migrateService @17 (instanceId :T.RuntimeInstanceId, targetNode :Text, timeout :T.Duration) -> (migrationId :Text);

    # Get migration status.
    getMigrationStatus @18 (migrationId :Text) -> (status :ServiceMigration);

    # ── Audit-9: Service Configuration ──

    # Get runtime configuration for a service instance.
    getRuntimeConfig @19 (instanceId :T.RuntimeInstanceId) -> (config :ServiceRuntimeConfig);

    # Update runtime configuration (triggers hot-reload if supported).
    updateRuntimeConfig @20 (instanceId :T.RuntimeInstanceId, config :ServiceRuntimeConfig) -> T.VoidResult;

    # ── Audit-9: Service Observability ──

    # Get structured logs for a service instance.
    getServiceLogs @21 (instanceId :T.RuntimeInstanceId, filter :LogFilter, pagination :T.Pagination)
                    -> (entries :List(LogEntry), total :UInt32);

    # Get metrics for a service instance.
    getServiceMetrics @22 (instanceId :T.RuntimeInstanceId, metricNames :List(Text))
                      -> (metrics :List(ServiceMetric));

    # Get distributed trace for a specific request.
    getTrace @23 (traceId :Text) -> (spans :List(TraceSpan));

    # ── Audit-9: Service Lifecycle Hooks ──

    # Register a lifecycle hook for a service instance.
    registerLifecycleHook @24 (instanceId :T.RuntimeInstanceId, hook :ServiceLifecycleHook) -> T.VoidResult;

    # Unregister a lifecycle hook.
    unregisterLifecycleHook @25 (instanceId :T.RuntimeInstanceId, hookId :Text) -> T.VoidResult;
}

struct RuntimeSearchStats {
    totalInstances @0 :UInt64;
    byKind @1 :T.StringMap;
    byState @2 :T.StringMap;
    # Total unique capabilities advertised.
    capabilitiesCount @3 :UInt64;
    # Last registry mutation.
    lastMutation @4 :T.Timestamp;
}

struct CatalogStats {
    # Total catalog entries.
    totalEntries @0 :UInt32;
    # Count by ownership team.
    byTeam @1 :T.StringMap;
    # Count by SLA tier.
    bySlaTier @2 :T.StringMap;
    # Count by tag.
    byTag @3 :T.StringMap;
    # Services with outdated changelogs (no update in >30 days).
    staleEntries @4 :UInt32;
}

interface RuntimeSearchSubscription {
    # DEPRECATED: Use pullPage instead. Unbounded event lists risk memory
    # exhaustion on long-lived subscriptions with high event throughput.
    pull @0 () -> (events :List(RuntimeSearchEvent));
    cancel @1 () -> T.VoidResult;
    # Paginated variant of pull for large event streams.
    pullPage @2 (pagination :T.Pagination) -> (events :List(RuntimeSearchEvent), total :UInt64);
}

# ── Audit-9: Service Cost Model ────────────────────────────────────────
# Per-request pricing, compute cost, and storage cost for a service.
struct ServiceCostModel {
    # Cost per request (in microcurrency units).
    perRequestCost @0 :Float64;
    # Cost per compute-second (e.g., CPU time).
    perComputeSecond @1 :Float64;
    # Cost per GB of storage per hour.
    perStorageGbHour @2 :Float64;
    # Monthly flat fee (if applicable).
    monthlyFlatFee @3 :Float64;
    # Currency code (e.g., "USD", "ZAR").
    currency @4 :Text;
    # Free tier limit (requests per month before charges apply).
    freeTierRequests @5 :UInt64;
    # Whether the cost model is active.
    active @6 :Bool;
}

# ── Audit-9: Service Migration ─────────────────────────────────────────
# Live migration state for a service instance.
struct ServiceMigration {
    # Unique migration identifier.
    migrationId @0 :Text;
    # Instance being migrated.
    instanceId @1 :T.RuntimeInstanceId;
    # Source node.
    sourceNode @2 :Text;
    # Target node.
    targetNode @3 :Text;
    # Current migration state.
    state @4 :MigrationState;
    # Migration progress (0-100).
    progress @5 :UInt32;
    # When migration started.
    startedAt @6 :T.Timestamp;
    # Estimated completion time.
    estimatedCompletion @7 :T.Timestamp;
    # Migration reason (e.g., "load-balancing", "maintenance", "failure-recovery").
    reason @8 :Text;
}

enum MigrationState {
    pending @0;
    preparing @1;
    transferring @2;
    verifying @3;
    completing @4;
    completed @5;
    failed @6;
    rolledBack @7;
    custom @8;
}

# ── Audit-9: Service Runtime Configuration ─────────────────────────────
# Runtime configuration that can be updated without restart.
struct ServiceRuntimeConfig {
    # Configuration key-value pairs.
    config @0 :T.StringMap;
    # Configuration version (incremented on each update).
    version @1 :UInt32;
    # When the configuration was last updated.
    updatedAt @2 :T.Timestamp;
    # Whether the configuration requires a restart to take effect.
    requiresRestart @3 :Bool;
}

# ── Audit-9: Service Observability ─────────────────────────────────────

struct LogFilter {
    # Minimum log level (e.g., "debug", "info", "warn", "error").
    minLevel @0 :Text;
    # Filter by message substring.
    messageContains @1 :Text;
    # Only logs after this timestamp.
    since @2 :T.Timestamp;
    # Only logs before this timestamp.
    until @3 :T.Timestamp;
}

struct LogEntry {
    # Timestamp of the log entry.
    timestamp @0 :T.Timestamp;
    # Log level (e.g., "debug", "info", "warn", "error").
    level @1 :Text;
    # Log message.
    message @2 :Text;
    # Structured metadata.
    metadata @3 :T.StringMap;
    # Source component/module.
    component @4 :Text;
}

struct ServiceMetric {
    # Metric name (e.g., "requests_per_second", "latency_p99", "error_rate").
    name @0 :Text;
    # Metric value.
    value @1 :Float64;
    # Metric unit (e.g., "count", "seconds", "bytes", "percent").
    unit @2 :Text;
    # When this metric was sampled.
    sampledAt @3 :T.Timestamp;
    # Labels for the metric (e.g., "method=GET", "status=200").
    labels @4 :T.StringMap;
}

struct TraceSpan {
    # Span identifier.
    spanId @0 :Text;
    # Parent span identifier (empty for root span).
    parentSpanId @1 :Text;
    # Operation name.
    operation @2 :Text;
    # Service that produced this span.
    service @3 :Text;
    # Start time.
    startTime @4 :T.Timestamp;
    # End time.
    endTime @5 :T.Timestamp;
    # Whether this span represents an error.
    error @6 :Bool;
    # Span metadata.
    metadata @7 :T.StringMap;
}

# ── Audit-9: Service Lifecycle Hook ────────────────────────────────────
# Hook into service lifecycle events (pre-start, post-start, pre-stop, post-stop).
struct ServiceLifecycleHook {
    # Unique hook identifier.
    hookId @0 :Text;
    # Lifecycle event to hook into.
    event @1 :LifecycleHookEvent;
    # Priority (higher = runs first).
    priority @2 :UInt32;
    # Hook-specific parameters.
    params @3 :T.StringMap;
    # Whether the hook is currently enabled.
    enabled @4 :Bool;
}

enum LifecycleHookEvent {
    preStart @0;
    postStart @1;
    preStop @2;
    postStop @3;
    onHealthChange @4;
    onConfigChange @5;
    custom @6;
}

# ── Service Catalog (false positive: service_catalog.capnp) ────────────
# Rich service metadata: API documentation, ownership, SLAs, and
# changelogs. This is a metadata extension of service discovery, not
# a separate domain. The catalog provides a richer view of service
# metadata that can be queried alongside runtime discovery.

struct ServiceCatalogEntry {
    # Service instance this catalog entry describes.
    instanceId @0 :T.RuntimeInstanceId;
    # Human-readable service name.
    name @1 :Text;
    # Service description (what it does).
    description @2 :Text;
    # Ownership information.
    ownership @3 :ServiceOwnership;
    # API documentation reference.
    apiDocs @4 :ApiDocumentation;
    # Service-level agreement.
    sla @5 :ServiceSla;
    # Changelog entries.
    changelog @6 :List(ChangelogEntry);
    # Tags for categorization.
    tags @7 :List(Text);
    # When this catalog entry was last updated.
    updatedAt @8 :T.Timestamp;
}

struct ServiceOwnership {
    # Team or individual that owns this service.
    ownerTeam @0 :Text;
    # Primary contact email or identifier.
    contactEmail @1 :Text;
    # On-call rotation identifier.
    onCallId @2 :Text;
    # Organizational unit.
    orgUnit @3 :Text;
    # Cost center for billing.
    costCenter @4 :Text;
}

struct ApiDocumentation {
    # URL to OpenAPI/Swagger specification.
    openApiUrl @0 :T.Uri;
    # URL to human-readable documentation.
    docsUrl @1 :T.Uri;
    # API version.
    apiVersion @2 :T.Version;
    # Protocol (e.g., "REST", "gRPC", "GraphQL", "Cap'n Proto").
    protocol @3 :Text;
    # Whether the API is stable (not experimental).
    stable @4 :Bool;
    # Deprecation notice (if the API is deprecated).
    deprecationNotice @5 :Text;
}

struct ServiceSla {
    # Target uptime percentage (e.g., 99.9).
    uptimeTarget @0 :Float32;
    # Maximum acceptable latency (e.g., 100ms).
    maxLatency @1 :T.Duration;
    # Maximum acceptable error rate (e.g., 0.01 = 1%).
    maxErrorRate @2 :Float32;
    # SLA tier (e.g., "critical", "standard", "best-effort").
    tier @3 :Text;
    # Whether the SLA is currently met.
    met @4 :Bool;
    # Last SLA breach timestamp (zero = never breached).
    lastBreach @5 :T.Timestamp;
}

struct ChangelogEntry {
    # Version this change applies to.
    version @0 :T.Version;
    # When this change was released.
    releasedAt @1 :T.Timestamp;
    # Type of change.
    changeType @2 :ChangeType;
    # Summary of the change.
    summary @3 :Text;
    # Breaking change details (if any).
    breaking @4 :Bool;
    # Deprecation details (if any).
    deprecated @5 :Text;
}

enum ChangeType {
    feature @0;
    bugfix @1;
    security @2;
    breaking @3;
    deprecation @4;
    documentation @5;
    custom @6;
}

@0xa1b2c3d4e5f60041;

# ═══════════════════════════════════════════════════════════════════════
# Discovery — service registration and lookup.
#
# Zero-backend-assumption IPC contract for service discovery. No mDNS,
# DNS-SD, or platform-specific registry assumed. The backend decides
# the discovery mechanism; the protocol defines the contract.
#
# Improvements (audit):
#   - DiscoverySubscription has cancel() for explicit teardown.
#   - DiscoveryEvent union has custom variant for forward compatibility.
#   - ServiceCategory has other variant for forward compatibility.
#   - ServiceState has other variant for forward compatibility.
#   - ServiceDescriptor.registeredAt, expireAt, tags.
#   - VersionInfo.succeededBy for upgrade lifecycle.
#   - update method for unified partial updates.
#
# Audit-7 improvements:
#   - ServiceHealth struct for detailed health metrics.
#   - HealthStatus enum for granular health beyond ServiceState.
#   - ServiceEndpoint struct for structured endpoints (replaces List(Text)).
#   - ServiceDependency struct for dependency graph.
#   - DeprecationInfo struct for graceful deprecation workflow.
#   - ServiceAttestation struct for cryptographic attestation.
#   - ServiceVersionCheck for version compatibility.
#   - HealthSubscription for health change notifications.
#   - Richer DiscoveryFilter with trust level, attestation, health.
#
# Audit-9 improvements:
#   - ServiceSLA struct for uptime/latency/error rate commitments.
#   - ServiceCost struct for per-request pricing, compute/storage costs.
#   - ServiceCanary for gradual rollout with traffic splitting.
#   - CircuitBreaker struct for automatic failure detection.
#   - RetryPolicy for configurable retry behavior per service.
#   - ServiceGeoDistribution for multi-region deployment.
#   - ServiceChangelog for version history and event timeline.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ── Service Category ────────────────────────────────────────────────────

enum ServiceCategory {
    other @0;
    media @1;
    network @2;
    system @3;
    storage @4;
    input @5;
    display @6;
    audio @7;
    security @8;
    communication @9;
    application @10;
    data @11;
    messaging @12;
    location @13;
    iot @14;
    # Backend-specific service category.
    custom @15;
}

# ── Service Descriptor ───────────────────────────────────────────────────

struct ServiceDescriptor {
    id @0 :T.ServiceId;
    name @1 :Text;
    category @2 :ServiceCategory;
    version @3 :VersionInfo;
    state @4 :ServiceState;
    # Structured endpoint addresses.
    endpoints @5 :List(ServiceEndpoint);
    metadata @6 :T.StringMap;
    # Required capability names (stringly-typed — backend interprets).
    requiredCaps @7 :List(Text);
    # Required capability IDs (typed — preferred over requiredCaps).
    requiredCapabilityIds @11 :List(T.CapabilityId);

    # When this service was registered.
    registeredAt @8 :T.Timestamp;
    # Optional expiry for transient registrations.
    expireAt @9 :T.Timestamp;
    # Tags for flexible categorization beyond category.
    tags @10 :List(Text);
    # Deprecation metadata (empty = not deprecated).
    deprecation @12 :DeprecationInfo;
    # Service attestation (empty = not attested).
    attestation @13 :ServiceAttestation;
    # Service ownership information.
    ownership @14 :ServiceOwnership;
    # Service SLA commitments (empty = no SLA).
    sla @15 :ServiceSla;
    # Service cost information.
    cost @16 :ServiceCost;
    # Canary deployment configuration.
    canary @17 :ServiceCanary;
    # Circuit breaker configuration.
    circuitBreaker @18 :CircuitBreaker;
    # Retry policy for client requests.
    retryPolicy @19 :RetryPolicy;
    # Geo-distribution across regions.
    geoDistribution @20 :ServiceGeoDistribution;
    # Version history and event timeline.
    changelog @21 :ServiceChangelog;
}

struct VersionInfo {
    version @0 :T.Version;
    # Minimum backward-compatible version.
    minCompatible @1 :T.Version;
    # The version that replaces this one (empty = no replacement).
    succeededBy @2 :T.Version;
}

enum ServiceState {
    online @0;
    offline @1;
    degraded @2;
    starting @3;
    maintenance @4;
    other @5;
    # Backend-specific service state.
    custom @6;
}

# ── Structured Endpoint ────────────────────────────────────────────────

struct ServiceEndpoint {
    # Endpoint address (backend-decided format: IPC names, TCP host:port, etc.).
    address @0 :Text;
    # Load-balancing weight (higher = more traffic).
    weight @1 :UInt32;
    # Priority (lower = preferred).
    priority @2 :UInt32;
    # Whether this endpoint is healthy.
    healthy @3 :Bool;
    # Transport protocol (e.g., "tcp", "udp", "unix", "ipc").
    protocol @4 :Text;
    # Endpoint metadata.
    metadata @5 :T.StringMap;
}

# ── Health Status ───────────────────────────────────────────────────────

enum HealthStatus {
    healthy @0;
    degraded @1;
    unhealthy @2;
    unknown @3;
    custom @4;
}

struct ServiceHealth {
    # Service this health info belongs to.
    serviceId @0 :T.ServiceId;
    # Health status.
    status @1 :HealthStatus;
    # Latency percentiles.
    latencyP50 @2 :T.Duration;
    latencyP95 @3 :T.Duration;
    latencyP99 @4 :T.Duration;
    # Error rate (0.0 = none, 1.0 = all errors).
    errorRate @5 :Float32;
    # Throughput in requests per second.
    throughputRps @6 :UInt64;
    # When this health check was performed.
    lastChecked @7 :T.Timestamp;
}

# ── Service Dependency ──────────────────────────────────────────────────

struct ServiceDependency {
    # Service that is depended upon.
    serviceId @0 :T.ServiceId;
    # The dependency type.
    dependencyType @1 :DependencyType;
    # Version constraint (e.g., ">=1.0.0").
    versionConstraint @2 :Text;
    # Whether this dependency is currently satisfied.
    satisfied @3 :Bool;
}

enum DependencyType {
    required @0;
    optional @1;
    custom @2;
}

# ── Deprecation Info ────────────────────────────────────────────────────

struct DeprecationInfo {
    # When this service was marked deprecated.
    deprecatedAt @0 :T.Timestamp;
    # When this service will be removed (sunset).
    sunsetAt @1 :T.Timestamp;
    # The service that replaces this one (empty = no replacement).
    replacedBy @2 :T.ServiceId;
    # Human-readable reason for deprecation.
    reason @3 :Text;
}

# ── Service Attestation ─────────────────────────────────────────────────

struct ServiceAttestation {
    # When this attestation was performed.
    attestedAt @0 :T.Timestamp;
    # Cryptographic attestation data (e.g., signed hash).
    attestationData @1 :T.HashOutput;
    # Whether the attestation has been verified.
    verified @2 :Bool;
    # Attestation type (e.g., "tpm", "sgx", "cosigning").
    attestationType @3 :Text;
}

# ── Service Ownership ───────────────────────────────────────────────────

struct ServiceOwnership {
    # Team or group that owns this service.
    team @0 :Text;
    # Contact email for the owner.
    contactEmail @1 :Text;
    # On-call rotation identifier.
    oncallRotation @2 :Text;
}

# ── Service Version Check ───────────────────────────────────────────────

struct ServiceVersionCheck {
    # Service being checked.
    serviceId @0 :T.ServiceId;
    # Client's version.
    clientVersion @1 :T.Version;
    # Whether the client version is compatible.
    compatible @2 :Bool;
    # Minimum required version.
    minRequired @3 :T.Version;
    # Latest available version.
    latestAvailable @4 :T.Version;
}

# ── Service SLA ─────────────────────────────────────────────────────────

struct ServiceSla {
    # Uptime guarantee as a fraction (0.999 = 99.9%).
    uptimeGuarantee @0 :Float32;
    # Maximum latency commitment in milliseconds.
    maxLatencyMs @1 :UInt32;
    # Error rate budget as a fraction (0.001 = 0.1%).
    errorRateBudget @2 :Float32;
    # Whether SLA is currently being met.
    met @3 :Bool;
    # Last SLA check timestamp.
    lastChecked @4 :T.Timestamp;
}

# ── Service Cost ─────────────────────────────────────────────────────────

struct ServiceCost {
    # Per-request pricing (empty = free).
    perRequestPrice @0 :Float32;
    # Currency code.
    currency @1 :Text;
    # Compute cost per minute.
    computeCostPerMin @2 :Float32;
    # Storage cost per GB.
    storageCostPerGb @3 :Float32;
    # Free tier included units.
    freeTierUnits @4 :UInt64;
}

# ── Service Canary Deployment ────────────────────────────────────────────

struct ServiceCanary {
    # Traffic percentage routed to canary (0-100).
    canaryWeight @0 :UInt8;
    # Whether canary is active.
    active @1 :Bool;
    # Canary health status.
    health @2 :HealthStatus;
    # Number of successful canary requests.
    successCount @3 :UInt64;
    # Number of failed canary requests.
    failureCount @4 :UInt64;
}

# ── Circuit Breaker ───────────────────────────────────────────────────────

struct CircuitBreaker {
    # Failure threshold before opening circuit.
    failureThreshold @0 :UInt32;
    # Success threshold to close circuit.
    successThreshold @1 :UInt32;
    # Timeout in seconds before half-open attempt.
    timeoutSeconds @2 :UInt32;
    # Current circuit state.
    state @3 :CircuitState;
    # Consecutive failures.
    consecutiveFailures @4 :UInt32;
    # Consecutive successes.
    consecutiveSuccesses @5 :UInt32;
}

enum CircuitState {
    closed @0;
    open @1;
    halfOpen @2;
    custom @3;
}

# ── Retry Policy ──────────────────────────────────────────────────────────

struct RetryPolicy {
    # Maximum retry attempts.
    maxAttempts @0 :UInt32;
    # Base delay between retries.
    baseDelay @1 :T.Duration;
    # Maximum delay cap.
    maxDelay @2 :T.Duration;
    # Backoff multiplier.
    backoffMultiplier @3 :Float32;
    # Whether to use jitter.
    jitter @4 :Bool;
    # HTTP status codes that trigger retry.
    retryableStatusCodes @5 :List(UInt16);
}

# ── Service Geo-Distribution ──────────────────────────────────────────────

struct ServiceGeoDistribution {
    # Regions where this service is deployed.
    regions @0 :List(ServiceRegion);
    # Primary region.
    primaryRegion @1 :Text;
    # Failover region.
    failoverRegion @2 :Text;
}

struct ServiceRegion {
    # Region identifier (e.g., "us-east-1", "eu-west-2").
    region @0 :Text;
    # Number of replicas in this region.
    replicas @1 :UInt16;
    # Whether this region is currently healthy.
    healthy @2 :Bool;
}

# ── Service Changelog ──────────────────────────────────────────────────────

struct ServiceChangelog {
    # Chronological entries.
    entries @0 :List(ChangelogEntry);
}

struct ChangelogEntry {
    # When this change was made.
    timestamp @0 :T.Timestamp;
    # Semantic version after this change.
    version @1 :T.Version;
    # Change type.
    type @2 :ChangelogType;
    # Human-readable description.
    description @3 :Text;
    # Author or service that made the change.
    author @4 :Text;
}

enum ChangelogType {
    added @0;
    changed @1;
    deprecated @2;
    removed @3;
    fixed @4;
    security @5;
    custom @6;
}

# ── Discovery Filter ────────────────────────────────────────────────────

struct DiscoveryFilter {
    name @0 :Text;
    category @1 :ServiceCategory;
    search @2 :Text;
    states @3 :List(ServiceState);
    requiredMetadata @4 :List(Text);
    tags @5 :List(Text);
    page @6 :T.Pagination;
    # Minimum trust level for results.
    minTrustLevel @7 :Text;
    # Only return attested services.
    requireAttestation @8 :Bool;
    # Filter by health status.
    healthStatus @9 :HealthStatus;
    # Exclude deprecated services.
    excludeDeprecated @10 :Bool;
}

# ── Service ─────────────────────────────────────────────────────────────

interface DiscoveryService {
    register @0 (descriptor :ServiceDescriptor) -> T.VoidResult;
    deregister @1 (serviceId :T.ServiceId) -> T.VoidResult;

    # Unified partial update — any field may be set.
    update @7 (serviceId :T.ServiceId, patch :ServicePatch) -> T.VoidResult;

    # Partial updates (kept for specific semantics).
    updateState @2 (serviceId :T.ServiceId, state :ServiceState) -> T.VoidResult;
    updateMetadata @3 (serviceId :T.ServiceId, metadata :T.StringMap) -> T.VoidResult;
    updateEndpoints @8 (serviceId :T.ServiceId, endpoints :List(ServiceEndpoint)) -> T.VoidResult;

    lookup @4 (filter :DiscoveryFilter) -> (services :List(ServiceDescriptor), total :UInt64);

    get @5 (serviceId :T.ServiceId) -> (descriptor :ServiceDescriptor);

    subscribe @6 (filter :DiscoveryFilter) -> (subscription :DiscoverySubscription);

    # ── Service Health ──
    getServiceHealth @9 (serviceId :T.ServiceId) -> (health :ServiceHealth);
    subscribeServiceHealth @10 (serviceId :T.ServiceId) -> (subscription :HealthSubscription);

    # ── Service Dependencies ──
    getServiceDependencies @11 (serviceId :T.ServiceId, pagination :T.Pagination)
                           -> (dependencies :List(ServiceDependency), total :UInt64);
    getDependents @12 (serviceId :T.ServiceId, pagination :T.Pagination)
                   -> (dependents :List(ServiceDependency), total :UInt64);

    # ── Deprecation ──
    deprecateService @13 (serviceId :T.ServiceId, info :DeprecationInfo) -> T.VoidResult;
    sunsetService @14 (serviceId :T.ServiceId) -> T.VoidResult;
    listDeprecatedServices @15 (pagination :T.Pagination)
                           -> (services :List(ServiceDescriptor), total :UInt64);

    # ── Version Checking ──
    checkVersionCompatibility @16 (serviceId :T.ServiceId, clientVersion :T.Version)
                              -> (check :ServiceVersionCheck);

    # ── Version Negotiation ──
    negotiateVersion @17 (serviceId :T.ServiceId, clientVersion :T.Version,
                          constraints :List(VersionConstraint))
                     -> (result :VersionNegotiationResult);

    # ── Health Aggregation ──
    getClusterHealth @18 (serviceIds :List(T.ServiceId))
                     -> (health :ClusterHealth);

    # ── Dependency Graph Traversal ──
    getDependencyGraph @19 (serviceId :T.ServiceId, depth :UInt32)
                       -> (graph :DependencyGraph);

    # Heartbeat — services signal liveness.
    heartbeat @20 (serviceId :T.ServiceId, liveness :Liveness) -> T.VoidResult;

    # Change feed — push-style subscription for service events.
    changeFeed @21 (filter :DiscoveryFilter, scope :T.IsolatedScope) -> (subscription :DiscoverySubscription);

    # Set scope boundary — discovery respects isolation tiers.
    setScopeBoundary @22 (scopeId :UInt64, allowedCategories :List(ServiceCategory)) -> T.VoidResult;

    # Lookup by scope — quarantined services see only their tier.
    getServiceByScope @23 (scope :T.IsolatedScope, pagination :T.Pagination) -> (services :List(ServiceDescriptor), total :UInt64);
}

# ── Version Negotiation ────────────────────────────────────────────────

struct VersionConstraint {
    # Minimum version required.
    minVersion @0 :T.Version;
    # Maximum version allowed (empty = no upper bound).
    maxVersion @1 :T.Version;
    # Whether exact version match is required.
    exactMatch @2 :Bool;
}

struct VersionNegotiationResult {
    # Whether negotiation succeeded.
    success @0 :Bool;
    # Agreed-upon version.
    agreedVersion @1 :T.Version;
    # Available versions if negotiation failed.
    availableVersions @2 :List(T.Version);
    # Reason for failure (if any).
    reason @3 :Text;
}

# ── Cluster Health ─────────────────────────────────────────────────────

struct ClusterHealth {
    # Per-service health.
    services @0 :List(ServiceHealth);
    # Aggregate status (healthy if all healthy, degraded if any degraded, unhealthy if any unhealthy).
    aggregateStatus @1 :HealthStatus;
    # Total services in cluster.
    totalServices @2 :UInt32;
    # Healthy service count.
    healthyCount @3 :UInt32;
    # Degraded service count.
    degradedCount @4 :UInt32;
    # Unhealthy service count.
    unhealthyCount @5 :UInt32;
}

# ── Dependency Graph ───────────────────────────────────────────────────

struct DependencyGraph {
    # Root service.
    rootServiceId @0 :T.ServiceId;
    # All nodes in the graph (root + transitive dependencies).
    nodes @1 :List(DependencyGraphNode);
    # All edges in the graph.
    edges @2 :List(DependencyGraphEdge);
    # Maximum depth traversed.
    depthReached @3 :UInt32;
}

struct DependencyGraphNode {
    serviceId @0 :T.ServiceId;
    # Depth from root (0 = root).
    depth @1 :UInt32;
    # Health status of this node.
    health @2 :HealthStatus;
    # Whether this node is reachable from root.
    reachable @3 :Bool;
}

struct DependencyGraphEdge {
    fromServiceId @0 :T.ServiceId;
    toServiceId @1 :T.ServiceId;
    dependencyType @2 :DependencyType;
    satisfied @3 :Bool;
}

struct ServicePatch {
    state @0 :ServiceState;
    endpoints @1 :List(ServiceEndpoint);
    metadata @2 :T.StringMap;
    expireAt @3 :T.Timestamp;
    tags @4 :List(Text);
    # Fields to explicitly unset by name.
    clearFields @5 :List(Text);
    # Deprecation update.
    deprecation @6 :DeprecationInfo;
}

interface DiscoverySubscription {
    pull @0 () -> (events :List(DiscoveryEvent));
    # Explicit cancellation — stops the event stream and releases resources.
    cancel @1 () -> T.VoidResult;
}

struct DiscoveryEvent {
    timestamp @0 :T.Timestamp;
    union {
        registered @1 :ServiceDescriptor;
        deregistered @2 :T.ServiceId;
        stateChanged @3 :StateChange;
        metadataChanged @4 :MetadataChange;
        endpointsChanged @5 :EndpointsChange;
        expired @6 :T.ServiceId;
        # Health status changed.
        healthChanged @7 :ServiceHealth;
        # Service was deprecated.
        deprecated @8 :DeprecationInfo;
        # Service was sunset (final phase before removal).
        sunset @9 :T.ServiceId;
        # Attestation was verified.
        attestationVerified @10 :ServiceAttestation;
        # Backend-specific discovery event type.
        custom @11 :Data;
    }
}

struct StateChange {
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

# ── Health Subscription ─────────────────────────────────────────────────

interface HealthSubscription {
    pull @0 () -> (health :List(ServiceHealth));
    cancel @1 () -> T.VoidResult;
}

# ─── Liveness ────────────────────────────────────────────────
struct Liveness {
    lastBeat @0 :T.Timestamp;
    jitterTolerance @1 :T.Duration;
    gracePeriod @2 :T.Duration;
}

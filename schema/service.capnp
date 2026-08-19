@0xa1b2c3d4e5f60021;

using T = import "types.capnp";

# ══════════════════════════════════════════════════════════════════════
# Service — service lifecycle observation and control.
#
# This schema observes and controls services declared in init.capnp.
# init.capnp owns service declarations and startup; this schema owns
# runtime observation, state queries, and lifecycle control.
#
# Improvements beyond the original schema:
#   - listServices uses T.Pagination for bounded results.
#   - StateSubscription has cancel method.
#   - ServiceType and ServiceStatus have custom variants.
#   - ServiceTask.cpu has comment documenting unit (percentage, total across cores).
#   - ServiceTask.memory has comment documenting unit (resident set size in bytes).
# ══════════════════════════════════════════════════════════════════════

interface Service {
    listServices @0 (pagination :T.Pagination)
                 -> (services :List(ServiceInfo), total :UInt32);
    getService @1 (serviceId :T.ServiceId) -> (info :ServiceInfo);

    start @2 (serviceId :T.ServiceId) -> T.VoidResult;
    stop @3 (serviceId :T.ServiceId) -> T.VoidResult;
    restart @4 (serviceId :T.ServiceId) -> T.VoidResult;
    enable @5 (serviceId :T.ServiceId) -> T.VoidResult;
    disable @6 (serviceId :T.ServiceId) -> T.VoidResult;

    getState @7 (serviceId :T.ServiceId) -> (state :ServiceState);

    subscribeState @8 (serviceId :T.ServiceId) -> (subscription :StateSubscription);

    # ─── Service Dependencies ──────────────────────────────────

    # Get dependencies for a service.
    getDependencies @9 (serviceId :T.ServiceId) -> (dependencies :List(ServiceDependency));

    # Set dependencies for a service.
    setDependencies @10 (serviceId :T.ServiceId, dependencies :List(ServiceDependency)) -> T.VoidResult;

    # ─── Resource Allocation ───────────────────────────────────

    # Get resource allocation for a service.
    getResourceAllocation @11 (serviceId :T.ServiceId) -> (allocation :ServiceResourceAllocation);

    # Set resource allocation for a service.
    setResourceAllocation @12 (serviceId :T.ServiceId, allocation :ServiceResourceAllocation) -> T.VoidResult;

    # ─── Health Checks ─────────────────────────────────────────

    # Get health check configuration.
    getHealthCheck @13 (serviceId :T.ServiceId) -> (check :ServiceHealthCheck);

    # Set health check configuration.
    setHealthCheck @14 (serviceId :T.ServiceId, check :ServiceHealthCheck) -> T.VoidResult;

    # Get health check results.
    getHealthStatus @15 (serviceId :T.ServiceId) -> (status :ServiceHealthStatus);

    # ─── Fleet Management ──────────────────────────────────────

    # Get fleet state for a service.
    getFleet @16 (serviceId :T.ServiceId) -> (fleet :ServiceFleet);

    # Scale a service fleet.
    scaleFleet @17 (serviceId :T.ServiceId, replicas :UInt32) -> T.VoidResult;

    # ─── Logging ───────────────────────────────────────────────

    # Get log configuration for a service.
    getLogConfig @18 (serviceId :T.ServiceId) -> (config :ServiceLogConfig);

    # Set log configuration for a service.
    setLogConfig @19 (serviceId :T.ServiceId, config :ServiceLogConfig) -> T.VoidResult;

    # ─── Metrics ───────────────────────────────────────────────

    # Get metrics configuration for a service.
    getMetricsConfig @20 (serviceId :T.ServiceId) -> (config :ServiceMetricsConfig);

    # Set metrics configuration for a service.
    setMetricsConfig @21 (serviceId :T.ServiceId, config :ServiceMetricsConfig) -> T.VoidResult;

    # Get current metrics for a service.
    getMetrics @22 (serviceId :T.ServiceId) -> (metrics :ServiceMetrics);

    # ─── Security Context ──────────────────────────────────────

    # Get security context for a service.
    getSecurityContext @23 (serviceId :T.ServiceId) -> (context :ServiceSecurityContext);

    # Set security context for a service.
    setSecurityContext @24 (serviceId :T.ServiceId, context :ServiceSecurityContext) -> T.VoidResult;

    # ─── Service Events ────────────────────────────────────────

    # Subscribe to service events (lifecycle, health, fleet changes).
    subscribeServiceEvents @25 (serviceId :T.ServiceId) -> (subscription :ServiceEventSubscription);

    # ─── Audit-9: Service Mesh Sidecar Management ─────────────

    # Deploy a sidecar proxy for a service.
    deploySidecar @26 (serviceId :T.ServiceId, config :SidecarConfig) -> T.VoidResult;

    # Remove a sidecar proxy from a service.
    removeSidecar @27 (serviceId :T.ServiceId) -> T.VoidResult;

    # Get sidecar status for a service.
    getSidecarStatus @28 (serviceId :T.ServiceId) -> (status :SidecarStatus);

    # ─── Audit-9: Service Discovery Integration ───────────────

    # Register a service with external discovery (Consul, etcd, ZooKeeper).
    registerDiscovery @29 (serviceId :T.ServiceId, config :DiscoveryConfig) -> T.VoidResult;

    # Deregister a service from external discovery.
    deregisterDiscovery @30 (serviceId :T.ServiceId) -> T.VoidResult;

    # ─── Audit-9: Service Configuration Management ────────────

    # Update service configuration at runtime without restart.
    updateConfig @31 (serviceId :T.ServiceId, config :T.StringMap) -> T.VoidResult;

    # Get current service configuration.
    getConfig @32 (serviceId :T.ServiceId) -> (config :T.StringMap);

    # ─── Audit-9: Service Secret Injection ────────────────────

    # Inject secrets into a service instance.
    injectSecrets @33 (serviceId :T.ServiceId, secrets :List(ServiceSecret)) -> T.VoidResult;

    # ─── Audit-9: Service Network Policy ──────────────────────

    # Set network policy for a service (firewall rules, mTLS).
    setNetworkPolicy @34 (serviceId :T.ServiceId, policy :ServiceNetworkPolicy) -> T.VoidResult;

    # Get network policy for a service.
    getNetworkPolicy @35 (serviceId :T.ServiceId) -> (policy :ServiceNetworkPolicy);

    # ─── Audit-9: Service Deployment Strategies ───────────────

    # Deploy with a specific strategy (blue-green, canary, rolling).
    deployWithStrategy @36 (serviceId :T.ServiceId, strategy :DeploymentStrategy) -> (deploymentId :Text);

    # Get deployment status.
    getDeploymentStatus @37 (deploymentId :Text) -> (status :DeploymentStatus);

    # ─── Audit-9: Service Rollback ────────────────────────────

    # Rollback a deployment to the previous version.
    rollbackDeployment @38 (deploymentId :Text) -> T.VoidResult;

    # ─── Audit-9: Service Autoscaling ─────────────────────────

    # Configure autoscaling for a service.
    configureAutoscaling @39 (serviceId :T.ServiceId, config :AutoscalingConfig) -> T.VoidResult;

    # Get current autoscaling status.
    getAutoscalingStatus @40 (serviceId :T.ServiceId) -> (status :AutoscalingStatus);

    # ─── Audit-9: Service Namespace Isolation ─────────────────

    # Set namespace isolation for a service.
    setNamespaceIsolation @41 (serviceId :T.ServiceId, config :NamespaceIsolationConfig) -> T.VoidResult;

    # ─── Audit-9: Service Event Sourcing ──────────────────────

    # Get lifecycle events as an event stream.
    getEventLog @42 (serviceId :T.ServiceId, pagination :T.Pagination) -> (events :List(ServiceEventEntry), total :UInt32);

    # Replay events from a specific point.
    replayEvents @43 (serviceId :T.ServiceId, fromIndex :UInt64) -> T.VoidResult;

    # ─── Audit-9: Service Chaos Engineering ───────────────────

    # Inject a failure into a service for resilience testing.
    injectFailure @44 (serviceId :T.ServiceId, failure :ChaosFailure) -> (injectionId :Text);

    # Stop a failure injection.
    stopFailure @45 (injectionId :Text) -> T.VoidResult;

    # ─── Audit-9: Service Cost Tracking ───────────────────────

    # Get cost allocation for a service.
    getCost @46 (serviceId :T.ServiceId, period :T.Duration) -> (cost :ServiceCost);

    # ─── Audit-9: Service SLA Declaration ─────────────────────

    # Set SLA targets for a service.
    setSla @47 (serviceId :T.ServiceId, sla :ServiceSla) -> T.VoidResult;

    # Get SLA compliance status.
    getSlaStatus @48 (serviceId :T.ServiceId) -> (status :ServiceSlaStatus);
}

interface StateSubscription {
    pull   @0 () -> (state :ServiceState);
    cancel @1 () -> T.VoidResult;
}

struct ServiceInfo {
    id          @0 :T.ServiceId;
    name        @1 :Text;
    description @2 :Text;
    type        @3 :ServiceType;
    state       @4 :ServiceState;
    enabled     @5 :Bool;
    running     @6 :Bool;
    pid         @7 :T.ProcessId;
    # Whether this service was started on demand (not at boot).
    onDemand    @8 :Bool;
}

enum ServiceType {
    system  @0;
    user    @1;
    session @2;
    custom  @3;
}

struct ServiceState {
    status     @0 :ServiceStatus;
    activeEnter @1 :T.Timestamp;
    mainPid    @2 :T.ProcessId;
    tasks      @3 :List(ServiceTask);
}

enum ServiceStatus {
    active      @0;
    reloading   @1;
    inactive    @2;
    failed      @3;
    activating  @4;
    deactivating @5;
    custom      @6;
}

struct ServiceTask {
    pid    @0 :T.ProcessId;
    name   @1 :Text;
    # CPU usage as a percentage (0.0 - 100.0) summed across all cores.
    # On multi-core systems, a single-threaded process at full load shows ~100.0.
    cpu    @2 :Float32;
    # Resident set size (RSS) in bytes. This is physical memory currently
    # mapped into the process address space, not virtual memory size.
    memory @3 :UInt64;
}

# ─── Service Kind ─────────────────────────────────────────────

enum ServiceKind {
    systemDaemon @0;
    userDaemon @1;
    sessionService @2;
    microservice @3;
    wasmService @4;
    serverlessFunction @5;
    containerized @6;
    wireless @7;
    custom @8;
}

# ─── Service Dependencies ─────────────────────────────────────

struct ServiceDependency {
    serviceId @0 :T.ServiceId;
    required @1 :Bool;
    versionConstraint @2 :Text;
    healthCheck @3 :Bool;
}

# ─── Resource Allocation ──────────────────────────────────────

struct ServiceResourceAllocation {
    cpuShares @0 :UInt32;
    memoryLimitBytes @1 :UInt64;
    ioBandwidthBytesPerSec @2 :UInt64;
    networkBandwidthBytesPerSec @3 :UInt64;
    gpuPercent @4 :UInt32;
}

# ─── Health Check ─────────────────────────────────────────────

struct ServiceHealthCheck {
    endpoint @0 :Text;
    interval @1 :T.Duration;
    timeout @2 :T.Duration;
    unhealthyThreshold @3 :UInt32;
    healthyThreshold @4 :UInt32;
}

enum ServiceHealthState {
    healthy @0;
    unhealthy @1;
    unknown @2;
    starting @3;
    custom @4;
}

struct ServiceHealthStatus {
    state @0 :ServiceHealthState;
    lastCheck @1 :T.Timestamp;
    consecutiveFailures @2 :UInt32;
    message @3 :Text;
}

# ─── Fleet Management ─────────────────────────────────────────

struct ServiceFleet {
    serviceId @0 :T.ServiceId;
    desiredReplicas @1 :UInt32;
    currentReplicas @2 :UInt32;
    readyReplicas @3 :UInt32;
    updatingReplicas @4 :UInt32;
}

# ─── Logging Configuration ────────────────────────────────────

struct ServiceLogConfig {
    level @0 :Text;
    destination @1 :Text;
    retention @2 :T.Duration;
    format @3 :Text;
    maxFileSize @4 :UInt64;
    maxFiles @5 :UInt32;
}

# ─── Metrics Configuration ────────────────────────────────────

struct ServiceMetricsConfig {
    enabled @0 :Bool;
    endpoint @1 :Text;
    interval @2 :T.Duration;
    scrapeTimeout @3 :T.Duration;
}

struct ServiceMetrics {
    requestRate @0 :Float64;
    errorRate @1 :Float64;
    latencyP50 @2 :T.Duration;
    latencyP95 @3 :T.Duration;
    latencyP99 @4 :T.Duration;
    activeConnections @5 :UInt32;
    totalRequests @6 :UInt64;
    totalErrors @7 :UInt64;
}

# ─── Security Context ─────────────────────────────────────────

struct ServiceSecurityContext {
    userId @0 :T.UserId;
    capabilities @1 :List(Text);
    readOnlyRootFilesystem @2 :Bool;
}

# ─── Service Events ───────────────────────────────────────────

struct ServiceEvent {
    eventType @0 :ServiceEventType;
    serviceId @1 :T.ServiceId;
    timestamp @2 :T.Timestamp;
    failed @3 :Text;
    healthChanged @4 :ServiceHealthStatus;
    fleetChanged @5 :ServiceFleet;
    configChanged @6 :Text;
    customData @7 :Data;
}

enum ServiceEventType {
    started @0;
    stopped @1;
    failed @2;
    healthChanged @3;
    fleetChanged @4;
    configChanged @5;
    custom @6;
}

interface ServiceEventSubscription {
    pull @0 () -> (events :List(ServiceEvent));
    cancel @1 () -> T.VoidResult;
}

struct SidecarConfig {
    image @0 :Text;
    port @1 :UInt32;
    env @2 :T.StringMap;
}

struct SidecarStatus {
    running @0 :Bool;
    port @1 :UInt32;
    pid @2 :T.ProcessId;
}

struct DiscoveryConfig {
    provider @0 :Text;
    address @1 :Text;
}

struct ServiceSecret {
    name @0 :Text;
    value @1 :Text;
}

struct ServiceNetworkPolicy {
    ingress @0 :List(Text);
    egress @1 :List(Text);
    mTLS @2 :Bool;
}

enum DeploymentStrategy {
    rolling @0;
    blueGreen @1;
    canary @2;
    custom @3;
}

struct DeploymentStatus {
    id @0 :Text;
    state @1 :Text;
    replicas @2 :UInt32;
}

struct AutoscalingConfig {
    minReplicas @0 :UInt32;
    maxReplicas @1 :UInt32;
    targetCPU @2 :UInt32;
}

struct AutoscalingStatus {
    currentReplicas @0 :UInt32;
    desiredReplicas @1 :UInt32;
}

struct NamespaceIsolationConfig {
    enabled @0 :Bool;
    namespaces @1 :List(Text);
}

struct ServiceEventEntry {
    index @0 :UInt64;
    event @1 :Text;
    timestamp @2 :T.Timestamp;
}

struct ChaosFailure {
    type @0 :Text;
    target @1 :Text;
}

struct ServiceCost {
    amount @0 :Float64;
    currency @1 :Text;
}

struct ServiceSla {
    uptime @0 :Float32;
    latencyMs @1 :UInt32;
}

struct ServiceSlaStatus {
    uptime @0 :Float32;
    latencyMs @1 :UInt32;
    violations @2 :UInt32;
}

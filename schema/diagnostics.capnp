@0xa1b2c3d4e5f60101;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Diagnostics — system health telemetry, crash dumps, performance metrics,
# distributed tracing integration.
#
# Zero backend assumptions: no Prometheus, no OpenTelemetry, no systemd
# assumptions. Backend provides structured telemetry; protocol defines
# the contract.
#
# Used by: system.capnp (health queries), logging.capnp (structured telemetry)
# ═══════════════════════════════════════════════════════════════════════

interface DiagnosticsService {
    # Get current health status of the system or a component.
    getHealth @0 (component :Text) -> (health :HealthStatus);

    # Get current metrics snapshot.
    getMetrics @1 (filter :MetricFilter, pagination :T.Pagination) -> (metrics :List(Metric), totalCount :UInt32);

    # Subscribe to real-time metric updates.
    subscribeMetrics @2 (filter :MetricFilter) -> (subscriptionId :UInt64);

    # Start a distributed trace span.
    traceStart @3 (span :TraceSpan) -> (spanContext :TraceContext);

    # End a trace span.
    traceEnd @4 (context :TraceContext, status :TraceStatus) -> T.VoidResult;

    # Add an event to an active span.
    traceEvent @5 (context :TraceContext, event :TraceEvent) -> T.VoidResult;

    # Get crash dump for a process.
    getCrashDump @6 (processId :T.ProcessId, dumpId :Text) -> (dump :CrashDump);

    # List available crash dumps.
    listCrashDumps @7 (filter :CrashDumpFilter, pagination :T.Pagination) -> (dumps :List(CrashDumpInfo), totalCount :UInt32);

    # Trigger a diagnostic collection (system report).
    collectDiagnostics @8 (scope :DiagnosticScope) -> (report :DiagnosticReport);

    # Get performance profile data.
    getProfile @9 (target :ProfileTarget, duration :T.Duration) -> (profile :ProfileData);

    # Subscribe to health status changes.
    subscribeHealth @10 (component :Text) -> (subscriptionId :UInt64);

    # Audit-7: structured log query interface.
    queryLogs @11 (filter :LogFilter, pagination :T.Pagination) -> (entries :List(LogEntry), totalCount :UInt32);

    # Audit-7: alert rule management.
    createAlertRule @12 (rule :AlertRule) -> (id :Text);
    listAlertRules @13 (pagination :T.Pagination) -> (rules :List(AlertRule), total :UInt32);
    deleteAlertRule @14 (id :Text) -> T.VoidResult;

    # Audit-7: W3C trace context propagation helpers.
    injectTraceContext @15 (context :TraceContext, carrier :T.StringMap) -> T.VoidResult;
    extractTraceContext @16 (carrier :T.StringMap) -> (context :TraceContext);

    # Audit-7: profiling symbolication support.
    uploadDebugInfo @17 (processId :T.ProcessId, info :DebugInfo) -> T.VoidResult;

    # Audit-7: synthetic monitoring / uptime checks.
    createUptimeCheck @18 (check :UptimeCheck) -> (id :Text);
    getUptimeResults @19 (id :Text, pagination :T.Pagination) -> (results :List(UptimeResult), total :UInt32);
    deleteUptimeCheck @20 (id :Text) -> T.VoidResult;

    # ── Alert evaluation engine (audit-9 What's Still Missing) ──
    evaluateAlert @21 (ruleId :Text) -> (evaluation :AlertEvaluation);
    silenceAlert @22 (ruleId :Text, duration :T.Duration) -> T.VoidResult;

    # ── Symbolication method (audit-9 What's Still Missing) ──
    symbolicate @23 (processId :T.ProcessId, address :UInt64) -> (result :SymbolicationResult);

    # ── Trace context carrier format (audit-9 What's Still Missing) ──
    injectTraceContextTyped @24 (context :TraceContext, carrier :TraceCarrier) -> T.VoidResult;
    extractTraceContextTyped @25 (carrier :TraceCarrier) -> (context :TraceContext);

    # ── Resource forecasting method (audit-9 What's Still Missing) ──
    forecastResourceUtilization @26 (metricName :Text, window :T.Duration) -> (forecast :ResourceForecast);

    # ── GPU metric filtering (audit-9 What's Still Missing) ──
    getGpuMetrics @27 (pagination :T.Pagination) -> (metrics :List(GpuMetric), total :UInt32);
}

# ── Subscription interfaces (methods 100-101, 200-201) ──

interface MetricsSubscription {
    pull @0 (subscriptionId :UInt64) -> (metrics :List(Metric));
    cancel @1 (subscriptionId :UInt64) -> T.VoidResult;
}

interface HealthSubscription {
    pull @0 (subscriptionId :UInt64) -> (status :HealthStatus);
    cancel @1 (subscriptionId :UInt64) -> T.VoidResult;
}

# ─── Health Status ───────────────────────────────────────────────────

struct HealthStatus {
    # Overall health of the component/system.
    overall @0 :HealthState;

    # Per-component health breakdown.
    components @1 :List(ComponentHealth);

    # Timestamp of this health check.
    checkedAt @2 :T.Timestamp;

    # Human-readable summary.
    summary @3 :Text;

    # Backend-specific details.
    details @4 :T.StringMap;
}

enum HealthState {
    healthy @0;
    degraded @1;
    unhealthy @2;
    unknown @3;
    custom @4;
}

struct ComponentHealth {
    name @0 :Text;
    state @1 :HealthState;
    message @2 :Text;
    lastCheck @3 :T.Timestamp;
    metrics @4 :List(MetricRef);  # Key metrics for this component
}

# ─── Metric Value ────────────────────────────────────────────────────

struct MetricValue {
    union {
        # Monotonically increasing counter.
        counter @0 :UInt64;

        # Instantaneous value that can go up and down.
        gauge @1 :Float64;

        # Histogram with buckets.
        histogram @2 :HistogramValue;

        # Summary with quantiles.
        summary @3 :SummaryValue;

        # Custom/backend-specific value.
        custom @4 :Data;
    }
}

struct MetricRef {
    name @0 :Text;
    value @1 :MetricValue;
}

# ─── Metrics ──────────────────────────────────────────────────────────

struct Metric {
    # Metric name (e.g., "cpu_usage", "memory_bytes", "request_latency_ms").
    name @0 :Text;

    # Metric value (counter, gauge, histogram, summary).
    value @1 :MetricValue;

    # Labels/tags for dimensionality (e.g., {"instance": "web-1", "region": "us-east"}).
    labels @2 :T.StringMap;

    # Timestamp of the metric sample.
    timestamp @3 :T.Timestamp;

    # Metric type for proper handling.
    type @4 :MetricType;

    # Unit of measurement (e.g., "seconds", "bytes", "requests_per_second").
    unit @5 :Text;

    # Help text describing the metric.
    help @6 :Text;

    # Metric category for structured filtering.
    category @7 :MetricCategory;
}

enum MetricCategory {
    cpu @0;
    memory @1;
    disk @2;
    network @3;
    gpu @4;
    thermal @5;
    battery @6;
    process @7;
    io @8;
    ipc @9;
    scheduler @10;
    lockContention @11;
    application @12;
    custom @13;
}

struct HistogramValue {
    buckets @0 :List(HistogramBucket);
    sum @1 :Float64;
    count @2 :UInt64;
}

struct HistogramBucket {
    upperBound @0 :Float64;  # +Inf for last bucket
    count @1 :UInt64;
}

struct SummaryValue {
    quantiles @0 :List(Quantile);
    sum @1 :Float64;
    count @2 :UInt64;
}

struct Quantile {
    quantile @0 :Float64;  # 0.0-1.0 (e.g., 0.5 = median, 0.99 = p99)
    value @1 :Float64;
}

enum MetricType {
    counter @0;
    gauge @1;
    histogram @2;
    summary @3;
    # Gauge with labels for per-entity metrics (e.g., per-CPU, per-disk)
    labeledGauge @4;
    # Rate metric (derivatives of counters)
    rate @5;
    # Info metric (non-numeric metadata)
    info @6;
    # State metric (enum-like, maps to numeric)
    state @7;
    custom @8;
}

struct MetricFilter {
    # Name pattern (glob-style: "cpu_*", "memory.*").
    namePattern @0 :Text;

    # Label filters (all must match).
    labels @1 :T.StringMap;

    # Only metrics of these types.
    types @2 :List(MetricType);

    # Time range for historical queries.
    timeRange @3 :T.TimeRange;
}

# ─── Distributed Tracing ─────────────────────────────────────────────

struct TraceSpan {
    # Operation name (e.g., "http.request", "db.query", "cache.get").
    operation @0 :Text;

    # Parent span context (empty for root span).
    parent @1 :TraceContext;

    # Span tags/labels.
    tags @2 :T.StringMap;

    # Start timestamp (0 = now).
    startTime @3 :T.Timestamp;

    # Links to other spans (for fan-out/follows-from).
    links @4 :List(SpanLink);
}

struct TraceContext {
    # Globally unique trace ID (16 bytes / 128-bit, W3C trace-id format).
    traceId @0 :Data;

    # Unique span ID within trace (8 bytes / 64-bit, W3C span-id format).
    spanId @1 :Data;

    # Trace flags (sampled, debug, etc.).
    flags @2 :UInt8;

    # Trace state (vendor-specific, W3C tracestate format).
    traceState @3 :Text;
}

struct SpanLink {
    traceId @0 :Data;
    spanId @1 :Data;
    traceState @2 :Text;
}

struct TraceEvent {
    # Event name (e.g., "exception", "log", "cache.miss").
    name @0 :Text;

    # Event timestamp.
    timestamp @1 :T.Timestamp;

    # Event attributes.
    attributes @2 :T.StringMap;
}

enum TraceStatus {
    ok @0;
    error @1;
    cancelled @2;
    deadlineExceeded @3;
    unknown @4;
    custom @5;
}

# ─── Crash Dumps ─────────────────────────────────────────────────────

struct CrashDumpInfo {
    id @0 :Text;                    # Unique dump identifier
    processId @1 :T.ProcessId;      # Process that crashed
    processName @2 :Text;           # Process name
    timestamp @3 :T.Timestamp;      # When crash occurred
    signal @4 :Text;                # Signal/fault type (e.g., "SIGSEGV", "EXC_BAD_ACCESS")
    address @5 :UInt64;             # Fault address (if applicable)
    sizeBytes @6 :UInt64;           # Dump file size
    arch @7 :Text;                  # CPU architecture
    buildId @8 :Text;               # Build ID for symbolication
    custom @9 :T.StringMap;         # Backend-specific metadata
}

struct CrashDump {
    info @0 :CrashDumpInfo;
    # Crash dump data (minidump, coredump, or backend-specific format).
    # Use T.DataHandle for zero-copy large dumps.
    data @1 :T.DataHandle;

    # Thread backtraces (if available).
    threads @2 :List(ThreadBacktrace);

    # Loaded modules/images at crash time.
    modules @3 :List(LoadedModule);

    # Register state at crash.
    registers @4 :RegisterState;
}

struct ThreadBacktrace {
    threadId @0 :T.ThreadId;
    threadName @1 :Text;
    frames @2 :List(StackFrame);
    crashed @3 :Bool;  # Whether this thread caused the crash
}

struct StackFrame {
    address @0 :UInt64;
    functionName @1 :Text;
    fileName @2 :Text;
    lineNumber @3 :UInt32;
    column @4 :UInt32;
    modulePath @5 :Text;
    offsetInModule @6 :UInt64;
}

struct LoadedModule {
    path @0 :Text;
    baseAddress @1 :UInt64;
    size @2 :UInt64;
    buildId @3 :Text;
    debugInfoAvailable @4 :Bool;
}

struct RegisterState {
    # Architecture-specific register dump.
    # Format: key = register name, value = hex string.
    registers @0 :T.StringMap;
}

struct CrashDumpFilter {
    processId @0 :T.ProcessId;
    processName @1 :Text;
    since @2 :T.Timestamp;
    until @3 :T.Timestamp;
    signal @4 :Text;
    hasDump @5 :Bool;
}

# ─── Diagnostic Reports ──────────────────────────────────────────────

enum DiagnosticScope {
    full @0;
    system @1;
    process @2;
    network @3;
    storage @4;
    graphics @5;
    # GPU-specific diagnostics
    gpu @6;
    # Thermal and cooling diagnostics
    thermal @7;
    # Power and battery diagnostics
    power @8;
    # Audio subsystem diagnostics
    audio @9;
    # Input subsystem diagnostics
    input @10;
    # Memory subsystem (NUMA, huge pages, swap)
    memory @11;
    # Scheduler and CPU topology
    scheduler @12;
    # Security audit (capabilities, sandbox state)
    security @13;
    # IPC diagnostics (shared memory, pipes, message queues)
    ipc @14;
    # Battery-specific diagnostics (health, charge cycles, voltage)
    battery @15;
    # Lock contention analysis
    lockContention @16;
    # I/O latency and throughput analysis
    ioLatency @17;
    # Process scheduler latency analysis
    schedulerLatency @18;
    # Network I/O diagnostics
    networkIo @19;
    # Virtual memory and page fault diagnostics
    virtualMemory @20;
    custom @21;
}

struct DiagnosticReport {
    generatedAt @0 :T.Timestamp;
    scope @1 :DiagnosticScope;
    sections @2 :List(DiagnosticSection);
    summary @3 :Text;
}

struct DiagnosticSection {
    name @0 :Text;
    content @1 :T.DataHandle;  # Structured data (JSON, protobuf, etc.)
    format @2 :Text;           # e.g., "json", "protobuf", "text"
    metadata @3 :T.StringMap;
}

# ─── Profiling ────────────────────────────────────────────────────────

enum ProfileTarget {
    cpu @0;
    heap @1;
    lightweightThread @2;  # Lightweight thread (e.g., goroutine, async task)
    thread @3;
    mutex @4;
    block @5;
    # GPU utilization and kernel execution
    gpu @6;
    # Memory allocation (distinct from heap — includes mmap, shared)
    allocation @7;
    # I/O latency (disk, network, pipe)
    io @8;
    # Lock contention analysis
    lock @9;
    # Scheduler latency (time waiting for CPU)
    scheduler @10;
    # Wakeup analysis (who woke whom)
    wakeup @11;
    # Off-CPU profiling (time spent not running)
    offCpu @12;
    # Per-CPU profiling (individual CPU core utilization)
    perCpu @13;
    # NUMA node profiling
    numa @14;
    # Battery drain profiling
    battery @15;
    # Network send/receive profiling
    network @16;
    # GPU memory profiling
    gpuMemory @17;
    # Custom backend-specific profile
    custom @18;
}

struct ProfileData {
    target @0 :ProfileTarget;
    profile @1 :T.DataHandle;  # pprof, perf.data, or backend format
    format @2 :Text;           # "pprof", "perf", "jfr", "custom"
    duration @3 :T.Duration;
    sampleRate @4 :UInt32;     # Samples per second (if applicable)
    startTime @5 :T.Timestamp;
    endTime @6 :T.Timestamp;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-7: Extended diagnostics capabilities
#
# Structured log queries, alerting, trace context propagation,
# profiling symbolication, and synthetic monitoring. These extend
# the basic health/metrics/tracing model to support full-stack
# production observability.
# ═══════════════════════════════════════════════════════════════════════

# ── Structured Log Query ──────────────────────────────────────

struct LogEntry {
    timestamp @0 :T.Timestamp;
    level @1 :T.LogLevel;
    # Log source (e.g., "kernel", "init", "app-1234").
    source @2 :Text;
    # Structured log message.
    message @3 :Text;
    # Key-value pairs for structured logging.
    attributes @4 :T.StringMap;
    # Trace context correlation (if available).
    traceContext @5 :TraceContext;
}

struct LogFilter {
    # Minimum log level.
    minLevel @0 :T.LogLevel;
    # Source pattern (glob-style).
    sourcePattern @1 :Text;
    # Message pattern (glob-style).
    messagePattern @2 :Text;
    # Time range filter.
    timeRange @3 :T.TimeRange;
    # Attribute filters (all must match).
    attributes @4 :T.StringMap;
}

# ── Alert Rules ───────────────────────────────────────

struct AlertRule {
    id @0 :Text;
    name @1 :Text;
    description @2 :Text;
    # Metric name to monitor.
    metricName @3 :Text;
    # Condition that triggers the alert.
    condition @4 :AlertCondition;
    # Duration the condition must be true before firing.
    duration @5 :T.Duration;
    # Severity level.
    severity @6 :AlertSeverity;
    # Notification channels.
    notifications @7 :List(AlertNotification);
    # Whether this rule is currently active.
    active @8 :Bool;
}

enum AlertCondition {
    greaterThan @0;
    lessThan @1;
    equals @2;
    notEquals @3;
    anomaly @4;          # Statistical anomaly detection
    custom @5;
}

enum AlertSeverity {
    info @0;
    warning @1;
    error @2;
    critical @3;
    custom @4;
}

struct AlertNotification {
    # Notification channel type (e.g., "email", "webhook", "sms").
    channel @0 :Text;
    # Channel-specific configuration.
    config @1 :T.StringMap;
}

# ── Debug Info Upload (profiling symbolication) ────────

struct DebugInfo {
    processId @0 :T.ProcessId;
    # Debug info data (DWARF, PDB, or backend format).
    data @1 :T.DataHandle;
    format @2 :Text;           # "dwarf", "pdb", "breakpad", "custom"
    # Build ID for matching crash dumps to debug info.
    buildId @3 :Text;
}

# ── Synthetic Monitoring / Uptime Checks ──────────────────────

struct UptimeCheck {
    id @0 :Text;
    name @1 :Text;
    # Check type (e.g., "http", "tcp", "dns", "ping").
    type @2 :Text;
    # Target endpoint (URL, host:port, or domain).
    target @3 :Text;
    # Check interval.
    interval @4 :T.Duration;
    # Timeout for each check.
    timeout @5 :T.Duration;
    # Expected response code (for HTTP checks).
    expectedStatus @6 :UInt32;
    # Expected content pattern (regex).
    expectedContent @7 :Text;
    # Whether this check is currently active.
    active @8 :Bool;
}

struct UptimeResult {
    checkId @0 :Text;
    timestamp @1 :T.Timestamp;
    success @2 :Bool;
    # Response time in milliseconds.
    responseMs @3 :UInt32;
    # HTTP status code (for HTTP checks).
    statusCode @4 :UInt32;
    # Error message (if check failed).
    error @5 :Text;
}

# ── GPU Metrics ───────────────────────────────────────

struct GpuMetric {
    # GPU utilization percentage (0-100).
    utilization @0 :UInt32;
    # VRAM used in bytes.
    vramUsedBytes @1 :UInt64;
    # VRAM total in bytes.
    vramTotalBytes @2 :UInt64;
    # GPU temperature in Kelvin.
    temperature @3 :T.TemperatureKelvin;
    # Power draw in milliwatts.
    powerMw @4 :UInt32;
    # GPU clock speed in MHz.
    clockMhz @5 :UInt32;
}

# ── Battery Metrics ───────────────────────────────────

struct BatteryMetric {
    # Charge percentage (0-100).
    chargePercent @0 :UInt32;
    # Cycle count.
    cycleCount @1 :UInt32;
    # Voltage in millivolts.
    voltageMv @2 :UInt32;
    # Current in milliamps (positive = charging).
    currentMa @3 :Int32;
    # Temperature in Kelvin.
    temperature @4 :T.TemperatureKelvin;
    # State-of-health percentage (0-100).
    soh @5 :UInt32;
}

# ── Lock Contention Metrics ───────────────────────────

struct LockContentionMetric {
    # Lock name or identifier.
    lockName @0 :Text;
    # Total wait time in nanoseconds.
    waitTimeNs @1 :UInt64;
    # Number of contention events.
    contentionCount @2 :UInt64;
    # Thread holding the lock (if known).
    holderThread @3 :T.ThreadId;
    # Waiting thread(s).
    waitingThreads @4 :List(T.ThreadId);
}

# ── IPC Metrics ───────────────────────────────────────

struct IpcMetric {
    # IPC mechanism (e.g., "pipe", "shared_memory", "message_queue").
    mechanism @0 :Text;
    # Message queue depth (for message queues).
    queueDepth @1 :UInt32;
    # Shared memory used in bytes.
    sharedMemoryBytes @2 :UInt64;
    # Messages sent in the measurement period.
    messagesSent @3 :UInt64;
    # Messages received in the measurement period.
    messagesReceived @4 :UInt64;
    # Average latency in nanoseconds.
    avgLatencyNs @5 :UInt64;
}

# ── Resource Utilization Forecasting (audit-8 What's Still Missing) ──
struct ResourceForecast {
    metricName @0 :Text;
    predictedValue @1 :Float64;
    confidence @2 :Float32;
    forecastWindow @3 :T.Duration;
    modelType @4 :Text;
}

# ── Profiling Symbolication (audit-8 What's Still Missing) ──
struct SymbolicationResult {
    functionName @0 :Text;
    fileName @1 :Text;
    lineNumber @2 :UInt32;
    column @3 :UInt32;
    offsetInModule @4 :UInt64;
}

# ── Alert Rule Evaluation (audit-8 What's Still Missing) ──
struct AlertEvaluation {
    ruleId @0 :Text;
    triggered @1 :Bool;
    currentValue @2 :Float64;
    threshold @3 :Float64;
    evaluatedAt @4 :T.Timestamp;
}

# ── Trace Context Carrier Format (audit-9 What's Still Missing) ──
struct TraceCarrier {
    format @0 :TraceCarrierFormat;
    headers @1 :T.StringMap;
    metadata @2 :T.StringMap;
}

enum TraceCarrierFormat {
    httpHeaders @0;
    grpcMetadata @1;
    binary @2;
    textMap @3;
    custom @4;
}

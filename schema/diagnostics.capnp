@0xa1b2c3d4e5f60101;

# ═══════════════════════════════════════════════════════════════════════
# Diagnostics — system health, metrics, crash dumps and profiles.
#
# Zero backend assumptions: no Prometheus, no OpenTelemetry, no systemd.
# The header always said that; the pre-revamp body then carried
# `TraceCarrierFormat { httpHeaders, grpcMetadata }` — a 2016 vendor
# transport named in a required enum — and a web-ops uptime monitor with
# HTTP status expectations.
#
# This file now keeps exactly four jobs:
#   1. HEALTH — is this component healthy, and why not.
#   2. METRICS — sampled measurements with an open vocabulary.
#   3. CRASH DUMPS — retained failure state, zero-copy.
#   4. PROFILES — captured performance profiles, zero-copy.
#
# Log entries, log filters and trace primitives come from
# logging.capnp, which owns them. The pre-revamp copies of `LogEntry`,
# `LogFilter`, `TraceSpan`, `TraceContext` and `TraceStatus` under the
# SAME NAMES with DIFFERENT SHAPES were a codegen collision and a third
# log grammar for every consumer; they are deleted, as are the three
# metric structs no method returned (`BatteryMetric`,
# `LockContentionMetric`, `IpcMetric`) — orphans that taught implementers
# to build special cases beside the general `Metric` mechanism.
#
# ── WHAT WAS DELETED, AND WHY ──────────────────────────────────────────
#
#   * `DiagnosticScope` (22 values), `ProfileTarget` (19), `MetricCategory`
#     (14) — three closed taxonomies naming the 2026 subsystem map. A
#     2046 subsystem (fabric-attached memory, an inference co-processor)
#     has no ordinal and every consumer's parser breaks. All three are
#     now open `Text` tokens: unknown tokens are ignored, known ones act.
#   * `queryLogs` / `LogEntry` / `LogFilter` — a third log-query contract.
#   * alert rules, alert evaluation, silence — a stateful rule engine
#     this schema cannot keep consistent.
#   * uptime checks with HTTP status expectations — a web-ops monitor,
#     not an OS contract.
#   * `injectTraceContextTyped` / `extractTraceContextTyped` +
#     `TraceCarrierFormat` — the gRPC noun. The untyped
#     inject/extract over T.StringMap remain, and they are sufficient:
#     a carrier is whatever the transport says it is.
#   * `forecastResourceUtilization` + `ResourceForecast`,
#     `symbolicate` + `SymbolicationResult` — prediction and
#     symbolication as OS-scheduler methods.
#   * `getGpuMetrics` + `GpuMetric` — one device class's metrics as a
#     first-class method while every other device uses `Metric`.
#
# Authority is the interface reference: holding `DiagnosticsService` is
# the authority to collect. No per-method token (R3).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using L = import "logging.capnp";

interface DiagnosticsService {
    # Current health of the system or a named component. An empty name
    # means the system as a whole.
    getHealth @0 (component :Text) -> (health :HealthStatus);

    # Bounded metrics snapshot.
    getMetrics @1 (filter :MetricFilter, page :T.Pagination) -> (metrics :List(Metric), totalCount :UInt64);

    # Live metric updates. Holding the subscription IS the authority to
    # pull; there is no subscription id to present.
    subscribeMetrics @2 (filter :MetricFilter) -> (subscription :MetricsSubscription);

    # Start a distributed trace span (canonical types from logging.capnp).
    traceStart @3 (span :L.TraceSpan) -> (spanContext :L.TraceContext);

    # End a trace span.
    traceEnd @4 (context :L.TraceContext, status :L.SpanStatus) -> T.VoidResult;

    # Add an event to an active span.
    traceEvent @5 (context :L.TraceContext, event :TraceEvent) -> T.VoidResult;

    # Propagate trace context through an open carrier (a string map). The
    # carrier is whatever the transport wants — no transport is named.
    injectTraceContext @6 (context :L.TraceContext, carrier :T.StringMap) -> T.VoidResult;
    extractTraceContext @7 (carrier :T.StringMap) -> (context :L.TraceContext);

    # Get a crash dump for a process.
    getCrashDump @8 (processId :T.ProcessId, dumpId :T.CrashDumpId) -> (dump :CrashDump);

    # List retained crash dumps.
    listCrashDumps @9 (filter :CrashDumpFilter, page :T.Pagination) -> (dumps :List(CrashDumpInfo), totalCount :UInt64);

    # Trigger a diagnostic collection. `scope` is an OPEN token naming what
    # the caller wants ("memory", "ipc", "gpu", or a 2046 subsystem); the
    # report states its own bounds, so a "full" collection cannot return
    # an unbounded message.
    collectDiagnostics @10 (scope :Text, bounds :ReportBounds) -> (report :DiagnosticReport);

    # Capture a performance profile. `target` is an OPEN token naming what
    # to profile — the pre-revamp 19-value `ProfileTarget` enum froze
    # today's profiler targets.
    getProfile @11 (target :Text, duration :T.Duration, bounds :ReportBounds) -> (profile :ProfileData);

    # Upload debug information to make profiles and crash dumps
    # symbolicate without the backend owning a symbol store.
    uploadDebugInfo @12 (processId :T.ProcessId, info :DebugInfo) -> T.VoidResult;
}

interface MetricsSubscription {
    # Bounded pull.
    pull @0 (maxMetrics :UInt32) -> (metrics :List(Metric));
    cancel @1 () -> T.VoidResult;
}

# ── Health ──────────────────────────────────────────────────────────────
# The canonical health answer for the whole protocol: discovery.capnp
# imports this rather than declaring a second `HealthStatus` with a
# different shape. A service can be passing every probe and still be
# quarantined after a fault storm — `ComponentHealth` carries both the
# probe result and the lifecycle fact, so reporting only "healthy" can
# never hide a broken system.

struct HealthStatus {
    # Overall health of the component/system.
    overall @0 :HealthState;
    # Per-component breakdown.
    components @1 :List(ComponentHealth);
    # When this answer was produced.
    checkedAt @2 :T.Timestamp;
    # Human-readable summary. Populated whenever `overall` is not
    # `healthy`; an empty summary with a non-healthy state is a producer
    # bug and a client should render "unknown".
    summary @3 :Text;
    # Backend-specific details.
    details @4 :T.StringMap;
}

enum HealthState {
    unknown @0;
    healthy @1;
    degraded @2;
    unhealthy @3;
    custom @4;
}

struct ComponentHealth {
    name @0 :Text;
    state @1 :HealthState;
    # The last probe result, kept distinct from the lifecycle state.
    lastProbePassed @2 :Bool;
    lastProbeAt @3 :T.Timestamp;
    message @4 :Text;
    # Running but not permitted to serve. A quarantined component still
    # holds its resources, which is exactly why it needs its own field.
    quarantined @5 :Bool;
    # Consecutive failures since the last success.
    consecutiveFailures @6 :UInt32;
}

# ── Metrics ─────────────────────────────────────────────────────────────
# One general mechanism instead of a per-substruct zoo. What a metric IS
# comes from `name` and `labels`; how it is aggregated comes from the
# `MetricValue` union. A 2046 measurement is a new name, not a new struct.

struct Metric {
    # Open metric name (e.g. "memory.used_bytes", "ipc.round_trip_us").
    name @0 :Text;
    # Open labels — the dimensions a consumer groups by.
    labels @1 :T.StringMap;
    value @2 :MetricValue;
    # When the sample was taken.
    timestamp @3 :T.Timestamp;
    # Subsystem that produced it (zero = not a kernel subsystem).
    subsystem @4 :T.SubsystemId;
}

struct MetricValue {
    union {
        counter @0 :UInt64;        # monotonic; consumers compute deltas
        gauge @1 :Float64;         # instantaneous
        histogram @2 :HistogramValue;
        summary @3 :SummaryValue;
        unknown @4 :T.UnknownEvent;
    }
}

struct HistogramValue {
    buckets @0 :List(HistogramBucket);
    count @1 :UInt64;
    sum @2 :Float64;
}

struct HistogramBucket {
    upperBound @0 :Float64;
    count @1 :UInt64;
}

struct SummaryValue {
    quantiles @0 :List(Quantile);
    count @1 :UInt64;
    sum @2 :Float64;
}

struct Quantile {
    quantile @0 :Float64;
    value @1 :Float64;
}

enum MetricType {
    counter @0;
    gauge @1;
    histogram @2;
    summary @3;
    custom @4;
}

struct MetricFilter {
    # Exact metric names (empty = all).
    names @0 :List(Text);
    # Restrict to these subsystems (empty = all).
    subsystems @1 :List(T.SubsystemId);
    since @2 :T.Timestamp;
    until @3 :T.Timestamp;
    # Open label match.
    labels @4 :T.StringMap;
}

# ── Crash dumps ─────────────────────────────────────────────────────────
# Retained failure state, all of it zero-copy: the dump, the backtrace and
# the loaded module list are descriptions; the bytes are handles.

struct CrashDumpInfo {
    dumpId @0 :T.CrashDumpId;
    processId @1 :T.ProcessId;
    # Signal that caused the dump, typed — not a free-text "SIGSEGV"
    # string every consumer must match.
    signal @2 :T.SignalKind;
    # Opaque exit status as the backend reported it.
    exitStatus @3 :T.ExitStatus;
    # Platform/channel name the backend chose to report, open token.
    origin @4 :Text;
    createdAt @5 :T.Timestamp;
    sizeBytes @6 :UInt64;
    metadata @7 :T.StringMap;
}

struct CrashDump {
    dumpId @0 :T.CrashDumpId;
    processId @1 :T.ProcessId;
    signal @2 :T.SignalKind;
    # The dump itself, zero-copy.
    data @3 :T.DataHandle;
    # Thread backtraces at the moment of failure.
    backtraces @4 :List(ThreadBacktrace);
    # Modules loaded when the crash happened.
    modules @5 :List(LoadedModule);
    # Register state as raw bytes per register name — no hex-string
    # parsing in every consumer.
    registers @6 :T.StringDataMap;
    createdAt @7 :T.Timestamp;
}

struct ThreadBacktrace {
    threadId @0 :T.ThreadId;
    frames @1 :List(StackFrame);
}

struct StackFrame {
    # Instruction pointer.
    address @0 :UInt64;
    # Offset within the module, when known (zero = unknown).
    moduleOffset @1 :UInt64;
    moduleName @2 :Text;
    functionName @3 :Text;
    filePath @4 :Text;
    lineNumber @5 :UInt32;
    # Backend-chosen inline frame flag; consumers must not assume the
    # backend can answer.
    inlined @6 :Bool;
}

struct LoadedModule {
    name @0 :Text;
    baseAddress @1 :UInt64;
    sizeBytes @2 :UInt64;
    path @3 :Text;
    buildId @4 :Data;
}

struct DebugInfo {
    processId @0 :T.ProcessId;
    # Debug information, zero-copy.
    data @1 :T.DataHandle;
    # Open format token (DWARF, PDB, symtab, or a 2046 one).
    format @2 :Text;
    uploadedAt @3 :T.Timestamp;
}

struct CrashDumpFilter {
    processId @0 :T.ProcessId;
    signals @1 :List(T.SignalKind);
    since @2 :T.Timestamp;
    until @3 :T.Timestamp;
}

# ── Collection and profiles ─────────────────────────────────────────────
# Both are bounded by the caller and say so in the result: `truncated`
# is set when a bound was hit, so a consumer never mistakes a short
# answer for a complete one.

struct ReportBounds {
    # Maximum number of sections in a report.
    maxSections @0 :UInt32;
    # Maximum bytes per section.
    maxBytesPerSection @1 :UInt64;
    # Maximum time the collection may take.
    maxDuration @2 :T.Duration;
}

struct DiagnosticReport {
    # Open scope token, echoed from the request.
    scope @0 :Text;
    sections @1 :List(DiagnosticSection);
    generatedAt @2 :T.Timestamp;
    # True when any section or the section list hit a bound.
    truncated @3 :Bool;
}

struct DiagnosticSection {
    # Open section name ("memory.map", "ipc.state", "gpu.registers").
    name @0 :Text;
    data @1 :T.DataHandle;
    # True when this section hit its byte bound.
    truncated @2 :Bool;
    metadata @3 :T.StringMap;
}

struct ProfileData {
    # Open target token, echoed from the request.
    target @0 :Text;
    # The profile itself, zero-copy.
    profile @1 :T.DataHandle;
    # Open format token (perf, pprof, or a 2046 one).
    format @2 :Text;
    startedAt @3 :T.Timestamp;
    duration @4 :T.Duration;
    truncated @5 :Bool;
}

# ── Trace events ────────────────────────────────────────────────────────

struct TraceEvent {
    name @0 :Text;
    at @1 :T.Timestamp;
    attributes @2 :T.StringMap;
}

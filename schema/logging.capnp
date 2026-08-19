@0xa1b2c3d4e5f60024;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Logging - application-level structured log ingestion
#
# Distinct from klog.capnp (kernel messages). This is the application
# logging service: structured log entries with filtering, levels, output
# routing, and domain management.
#
# Backend-agnostic: works with stdout, file sinks, network sinks,
# or any future transport. The schema names no specific logging daemon;
# backends map to their native output (syslog, journald, etc.) at
# implementation time.
#
# Improvements (audit-7):
#   - Structured log fields (T.StringMap) for typed key-value metadata.
#   - Unified severity via T.LogLevel (trace..custom, crash/security/audit).
#   - Distributed tracing: traceId, spanId, parentSpanId on LogEntry.
#   - Correlation ID for linking related log entries across services.
#   - Log querying with LogQuery for SQL-like filtering.
#   - Log distillation for AI-summarized log streams.
#   - Log redaction for privacy-preserving field redaction.
#   - Log retention policies per domain.
#   - Structured log export for external analysis.
#   - Real-time log streaming with backpressure.
#   - Log lineage tracking.
# ═══════════════════════════════════════════════════════════════════════

interface Logging {
    getEntries @0 (filter :LogFilter, pagination :T.Pagination) -> (entries :List(LogEntry));
    subscribeEntries @1 (filter :LogFilter) -> (subscriptionId :UInt64);
    pullEntries @2 (subscriptionId :UInt64, pagination :T.Pagination) -> (entries :List(LogEntry));

    setLevel @3 (domain :Text, level :T.LogLevel) -> T.VoidResult;
    getLevel @4 (domain :Text) -> (level :T.LogLevel);

    clear @5 (domain :Text) -> T.VoidResult;
    # Clear all logs. If olderThan is specified, only logs older than
    # that timestamp are cleared. Zero timestamp means clear all.
    clearAll @6 (olderThan :T.Timestamp) -> T.VoidResult;

    setFormat @7 (format :LogFormat) -> T.VoidResult;
    setOutput @8 (output :LogOutput) -> T.VoidResult;

    subscribeDomains @9 () -> (subscriptionId :UInt64);
    pullDomains @10 (subscriptionId :UInt64, pagination :T.Pagination) -> (domains :List(LogDomain));

    # ── Audit-7 additions ────────────────────────────────────

    # Structured log querying with SQL-like filters.
    queryEntries @11 (query :LogQuery, pagination :T.Pagination) -> (entries :List(LogEntry), total :UInt64);

    # Real-time log streaming (WebSocket-style live tail).
    streamEntries @12 (filter :LogFilter) -> (streamId :UInt64);

    # AI-summarized log streams for high-volume systems.
    getDistilled @13 (filter :LogFilter, windowSize :T.Duration) -> (result :LogDistillResult);

    # Privacy-preserving log redaction with audit trail.
    redact @14 (filter :LogFilter, patterns :List(Text)) -> (redactedCount :UInt64);

    # Per-domain retention policies for compliance.
    setRetention @15 (domain :Text, retention :T.Duration) -> T.VoidResult;

    # Structured log export for external analysis.
    exportEntries @16 (filter :LogFilter, format :ExportFormat) -> (data :T.DataHandle);

    # Log aggregation across multiple sources.
    aggregateLogs @17 (sources :List(Text), filter :LogFilter, pagination :T.Pagination) -> (entries :List(LogEntry));

    # Register threshold-based alerts on log patterns.
    registerAlert @18 (pattern :Text, threshold :UInt32, action :Text) -> T.VoidResult;

    # Configurable sampling rates to reduce volume.
    setSamplingRate @19 (domain :Text, rate :Float32) -> T.VoidResult;

    # Attach additional context to existing log entries.
    enrichContext @20 (entryId :T.EventId, context :T.StringMap) -> T.VoidResult;

    # Audit-9: subscribe to alert notifications when thresholds are exceeded.
    subscribeAlerts @21 () -> (subscriptionId :UInt64);

    # Audit-9: query enriched context attached to log entries.
    getEnrichedContext @22 (entryId :T.EventId) -> (context :T.StringMap);

    # Audit-9: define a custom log query language expression.
    queryWithExpression @23 (expression :Text, pagination :T.Pagination) -> (entries :List(LogEntry), total :UInt64);

    # Audit-9: trace context propagation — extract trace from a log entry.
    getTraceContext @24 (entryId :T.EventId) -> (context :TraceContext);

    # Audit-9: create a distributed trace span linked to a log entry.
    createTraceSpan @25 (entryId :T.EventId, span :TraceSpan) -> (spanId :Text);

    # ── Core ingestion ─────────────────────────────────────────
    log @26 (severity :T.LogLevel, domain :Text, message :Text) -> T.VoidResult;
}

# ── Log Entry ────────────────────────────────────────────────

struct LogEntry {
    id @0 :T.EventId;
    timestamp @1 :T.Timestamp;
    level @2 :T.LogLevel;
    domain @3 :Text;
    message @4 :Text;
    source @5 :LogSource;
    metadata @6 :T.StringMap;
    # ── Audit-7 additions ────────────────────────────────────
    # Structured fields for machine parsing (typed key-value pairs).
    structuredFields @7 :T.StringMap;
    # Correlation ID for linking related entries across services.
    correlationId @8 :Text;
    # W3C trace-parent correlation (distributed tracing).
    traceId @9 :Text;
    # Span ID within a distributed trace.
    spanId @10 :Text;
    # Parent span ID for trace hierarchy.
    parentSpanId @11 :Text;
    # Which service/instance produced this log.
    lineageId @12 :Text;
    # Extended severity beyond T.LogLevel (stack trace indicators).
    severity @13 :T.LogLevel;
}

# ── Log Source ───────────────────────────────────────────────

struct LogSource {
    file @0 :Text;
    line @1 :UInt32;
    function @2 :Text;
}

# ── Log Filter ───────────────────────────────────────────────

struct LogFilter {
    domain @0 :Text;
    level @1 :T.LogLevel;
    since @2 :T.Timestamp;
    until @3 :T.Timestamp;
    pattern @4 :Text;
}

# ── Log Domain ───────────────────────────────────────────────

struct LogDomain {
    name @0 :Text;
    level @1 :T.LogLevel;
    description @2 :Text;
}

# ── Log Format ───────────────────────────────────────────────

enum LogFormat {
    text @0;
    json @1;
    xml @2;
    custom @3;
}

# ── Log Output ───────────────────────────────────────────────

enum LogOutput {
    stdout @0;
    stderr @1;
    # System log daemon (e.g., syslog, journald, Windows Event Log).
    # Backend maps to its native transport at implementation time.
    systemLog @2;
    # Structured log store (e.g., ELK, Loki, InfluxDB).
    structuredLog @3;
    file @4;
    custom @5;
}

# ── Log Query (audit-7) ──────────────────────────────────────
# Structured query for SQL-like log filtering without client-side scan.

struct LogQuery {
    # Full-text search pattern.
    search @0 :Text;
    # Filter by domain(s).
    domains @1 :List(Text);
    # Filter by minimum severity level.
    minSeverity @2 :T.LogLevel;
    # Filter by maximum severity level.
    maxSeverity @3 :T.LogLevel;
    # Filter by time range.
    since @4 :T.Timestamp;
    until @5 :T.Timestamp;
    # Filter by correlation ID.
    correlationId @6 :Text;
    # Filter by distributed trace ID.
    traceId @7 :Text;
    # Filter by field values (key:value syntax).
    fieldFilters @8 :List(LogFieldFilter);
    # Sort order.
    sortBy @9 :LogSortField;
    sortOrder @10 :LogSortOrder;
}

struct LogFieldFilter {
    field @0 :Text;
    operator @1 :LogFilterOperator;
    value @2 :Text;
}

enum LogFilterOperator {
    equals @0;
    contains @1;
    startsWith @2;
    endsWith @3;
    regex @4;
    greaterThan @5;
    lessThan @6;
    custom @7;
}

enum LogSortField {
    timestamp @0;
    level @1;
    domain @2;
    custom @3;
}

enum LogSortOrder {
    ascending @0;
    descending @1;
    custom @2;
}

# ── Log Distillation (audit-7) ───────────────────────────────
# AI-summarized log streams for high-volume systems.

struct LogDistillResult {
    # Summary of the log window.
    summary @0 :Text;
    # Anomalies detected in the log window.
    anomalies @1 :List(LogAnomaly);
    # Patterns extracted from the log window.
    patterns @2 :List(LogPattern);
    # Aggregate statistics.
    stats @3 :LogStats;
}

struct LogAnomaly {
    # The anomalous log entry.
    entry @0 :LogEntry;
    # Anomaly score (0.0 = normal, 1.0 = highly anomalous).
    score @1 :Float32;
    # Human-readable explanation of why this is anomalous.
    reason @2 :Text;
}

struct LogPattern {
    # Regex or template pattern.
    pattern @0 :Text;
    # How many times this pattern appeared.
    count @1 :UInt64;
    # Example entries matching this pattern.
    examples @2 :List(LogEntry);
    # Severity level of this pattern.
    severity @3 :T.LogLevel;
}

struct LogStats {
    # Total entries in the window.
    total @0 :UInt64;
    # Count by severity level.
    bySeverity @1 :List(LogSeverityCount);
    # Count by domain.
    byDomain @2 :List(LogDomainCount);
    # Time range covered.
    timeRange @3 :T.Duration;
}

struct LogSeverityCount {
    severity @0 :T.LogLevel;
    count @1 :UInt64;
}

struct LogDomainCount {
    domain @0 :Text;
    count @1 :UInt64;
}

# ── Export Format (audit-7) ──────────────────────────────────

enum ExportFormat {
    json @0;
    jsonl @1;        # JSON Lines
    csv @2;
    text @3;
    custom @4;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-9: Alert notifications, context enrichment query, log query
# language, distributed trace context propagation.
# ═══════════════════════════════════════════════════════════════════════

# ── Alert Notification ────────────────────────────────────────

struct LogAlertNotification {
    # Alert identifier.
    alertId @0 :Text;
    # Pattern that was matched.
    pattern @1 :Text;
    # Number of matching entries.
    matchCount @2 :UInt64;
    # Threshold that was exceeded.
    threshold @3 :UInt32;
    # When the alert fired.
    firedAt @4 :T.Timestamp;
    # Sample matching entries.
    samples @5 :List(LogEntry);
}

# ── Trace Context (audit-9) ──────────────────────────────────
# Distributed trace context for W3C trace-parent and OpenTelemetry.

struct TraceContext {
    # W3C trace-parent header value.
    traceParent @0 :Text;
    # OpenTelemetry trace ID.
    traceId @1 :Text;
    # OpenTelemetry span ID.
    spanId @2 :Text;
    # Trace flags (sampled, etc.).
    traceFlags @3 :UInt8;
    # Vendor-specific trace state.
    traceState @4 :Text;
    # Baggage items.
    baggage @5 :T.StringMap;
}

struct TraceSpan {
    # Span name.
    name @0 :Text;
    # Parent span ID (empty for root span).
    parentSpanId @1 :Text;
    # Span kind.
    kind @2 :SpanKind;
    # Start time.
    startTime @3 :T.Timestamp;
    # End time.
    endTime @4 :T.Timestamp;
    # Span status.
    status @5 :SpanStatus;
    # Key-value attributes.
    attributes @6 :T.StringMap;
}

enum SpanKind {
    internal @0;
    server @1;
    client @2;
    producer @3;
    consumer @4;
    custom @5;
}

enum SpanStatus {
    ok @0;
    error @1;
    cancelled @2;
    custom @3;
}

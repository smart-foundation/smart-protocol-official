@0xa1b2c3d4e5f60045;

# ═══════════════════════════════════════════════════════════════════════
# KLog - kernel log service
#
# Provides access to kernel-level log messages: diagnostics, boot
# messages, driver output, panic traces, and security audit events.
# Clients subscribe to a filtered stream or pull recent messages.
#
# This is a CONTRACT. A backend may route logs through a serial port,
# a ring buffer in shared memory, a network sink, or a framebuffer
# console. The protocol describes what messages look like and how to
# filter them, not where they go.
#
# KLog is distinct from the application-level Logging service. KLog
# is exclusively for kernel and driver output; it is the system
# equivalent of dmesg / syslog kernel messages.
#
# Improvements (audit-5):
#   - KLogMessage.source changed from bare Text to T.SubsystemId (Rule 2).
#   - KLogFilter.sources changed from List(Text) to List(T.SubsystemId) (Rule 2).
#
# Improvements (audit-7):
#   - Structured log fields (KLogField/KLogFieldValue) for typed key-value data.
#   - Log search with field-based search and facets.
#   - Log correlation with distributed traces (OpenTelemetry).
#   - Real-time log streaming with backpressure control.
#   - Log distillation for summarization and anomaly detection.
#   - Distributed trace context extraction.
#   - Structured log export with format and compression options.
#   - bufferSize returns bytesUsed in addition to count.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ── Log Message ───────────────────────────────────────────────

struct KLogMessage {
    # Sequence number (monotonically increasing, unique per backend).
    sequence @0 :UInt64;
    # Timestamp when the message was generated.
    timestamp @1 :T.Timestamp;
    # Severity of the message.
    severity @2 :KLogSeverity;
    # Component or subsystem that produced the message.
    source @3 :T.SubsystemId;
    # Human-readable message text.
    message @4 :Text;
    # Optional structured data (key-value pairs, backend-defined format).
    metadata @5 :T.StringDataMap;
    # ── Audit-7 additions ────────────────────────────────────
    # Structured fields for typed key-value data.
    fields @6 :List(KLogField);
    # Correlation ID for linking related log entries.
    correlationId @7 :Text;
    # Distributed trace ID (OpenTelemetry).
    traceId @8 :Text;
    # Span ID within a distributed trace.
    spanId @9 :Text;
    # Parent span ID for trace hierarchy.
    parentSpanId @10 :Text;
}

enum KLogSeverity {
    # Diagnostic information for developers.
    debug @0;
    # Informational messages about normal operation.
    info @1;
    # Unexpected conditions that did not break anything.
    warn @2;
    # Errors that affected a subsystem but the system continues.
    error @3;
    # Critical failures requiring immediate attention.
    critical @4;
    # Fatal: the system or subsystem is halting.
    panic @5;
    custom @6;
}

# ── Structured Fields (audit-7) ──────────────────────────────

struct KLogField {
    name @0 :Text;
    value @1 :KLogFieldValue;
}

struct KLogFieldValue {
    union {
        string @0 :Text;
        int @1 :Int64;
        float @2 :Float64;
        bool @3 :Bool;
        bytes @4 :Data;
        timestamp @5 :T.Timestamp;
        duration @6 :T.Duration;
        error @7 :T.Error;
        custom @8 :Data;
    }
}

# ── Filter ────────────────────────────────────────────────────

struct KLogFilter {
    # If non-empty, only include messages with severity >= this level.
    minSeverity @0 :KLogSeverity = info;
    # If non-empty, only include messages from these subsystems.
    sources @1 :List(T.SubsystemId);
    # Only include messages after this sequence number (0 = no lower bound).
    afterSequence @2 :UInt64;
    # Only include messages at or before this timestamp (zero = no upper bound).
    beforeTimestamp @3 :T.Timestamp;
    # Maximum number of messages to return per pull (0 = backend default).
    limit @4 :UInt32;
}

# ── Service Interface ─────────────────────────────────────────

interface KLogService {
    # Pull recent messages matching a filter.
    read @0 (filter :KLogFilter) -> (messages :List(KLogMessage));

    # Subscribe to a live stream of kernel log messages.
    subscribe @1 (filter :KLogFilter) -> (subscriptionId :UInt64);

    # Pull pending messages from a subscription.
    pull @2 (subscriptionId :UInt64) -> (messages :List(KLogMessage));

    # Query the current log buffer size (number of messages retained)
    # and memory usage.
    bufferSize @3 () -> (count :UInt32, bytesUsed :UInt64);

    # Clear the log buffer (requires appropriate authority).
    clear @4 () -> T.VoidResult;

    # ── Audit-7 additions ────────────────────────────────────

    # Search logs with field-based queries and facets.
    search @5 (request :KLogSearchRequest) -> (result :KLogSearchResult);

    # Start a real-time log streaming subscription with backpressure.
    stream @6 (request :KLogStreamRequest) -> (streamId :UInt64);

    # Distill (summarize, deduplicate, detect anomalies) log entries.
    distill @7 (request :KLogDistillRequest) -> (result :KLogDistillResult);

    # Extract distributed trace context for a log message.
    getTraceContext @8 (sequence :UInt64) -> (context :KLogTraceContext);

    # Export logs to external systems.
    export @9 (request :KLogExportRequest) -> T.VoidResult;

    # Audit-9: set log retention policy (auto-delete after duration).
    setRetentionPolicy @10 (policy :KLogRetentionPolicy) -> T.VoidResult;

    # Audit-9: get current log retention policy.
    getRetentionPolicy @11 () -> (policy :KLogRetentionPolicy);

    # Audit-9: archive old logs to cold storage.
    archiveLogs @12 (request :KLogArchiveRequest) -> (result :KLogArchiveResult);

    # Audit-9: encrypt sensitive log data at rest.
    encryptLogs @13 (request :KLogEncryptRequest) -> T.VoidResult;

    # Audit-9: set access control for log access.
    setAccessControl @14 (policy :KLogAccessPolicy) -> T.VoidResult;

    # Audit-9: get audit trail of log access.
    getAccessAudit @15 (pagination :T.Pagination) -> (entries :List(KLogAccessAuditEntry), totalCount :UInt32);

    # Audit-9: set sampling rate for performance.
    setSamplingRate @16 (rate :Float32) -> T.VoidResult;

    # Audit-9: get current sampling rate.
    getSamplingRate @17 () -> (rate :Float32);

    # Audit-9: aggregate logs across subsystems.
    aggregateLogs @18 (request :KLogAggregateRequest) -> (result :KLogAggregateResult);

    # Audit-9: register alert on log patterns.
    registerAlert @19 (request :KLogAlertRequest) -> (alertId :Text);

    # Audit-9: list registered alerts.
    listAlerts @20 (pagination :T.Pagination) -> (alerts :List(KLogAlert), totalCount :UInt32);

    # Audit-9: remove a registered alert.
    removeAlert @21 (alertId :Text) -> T.VoidResult;
}

# Subscription methods are on KLogService at methods 100-101.

# ── Log Search (audit-7) ─────────────────────────────────────

struct KLogSearchRequest {
    # Search query (supports field:value syntax).
    query @0 :Text;
    filter @1 :KLogFilter;
    page @2 :T.Pagination;
}

struct KLogSearchResult {
    messages @0 :List(KLogMessage);
    total @1 :UInt64;
    # Time taken to execute the search.
    took @2 :T.Duration;
    # Faceted results for field-based aggregation.
    facets @3 :List(KLogFacet);
}

struct KLogFacet {
    field @0 :Text;
    values @1 :List(KLogFacetValue);
}

struct KLogFacetValue {
    value @0 :Text;
    count @1 :UInt64;
}

# ── Log Streaming (audit-7) ──────────────────────────────────

struct KLogStreamRequest {
    filter @0 :KLogFilter;
    backpressure @1 :BackpressureMode;
    # Maximum messages per batch.
    batchSize @2 :UInt32;
    # Maximum time to wait before sending a partial batch.
    batchTimeout @3 :T.Duration;
}

enum BackpressureMode {
    # Drop messages when consumer is slow.
    drop @0;
    # Buffer messages (bounded, oldest dropped when full).
    buffer @1;
    # Block producer until consumer catches up.
    block @2;
    custom @3;
}

# Stream subscription methods are on KLogService at methods 102-103.

# ── Log Distillation (audit-7) ───────────────────────────────

struct KLogDistillRequest {
    messages @0 :List(KLogMessage);
    algorithm @1 :DistillAlgorithm;
    # Maximum number of output messages.
    maxOutput @2 :UInt32;
    # Time window for aggregation.
    timeWindow @3 :T.Duration;
}

enum DistillAlgorithm {
    # Summarize similar messages.
    summarize @0;
    # Detect anomalies.
    anomaly @1;
    # Extract patterns.
    pattern @2;
    # Deduplicate similar messages.
    deduplicate @3;
    # Aggregate by field.
    aggregate @4;
    custom @5;
}

struct KLogDistillResult {
    # Processed output messages.
    output @0 :List(KLogMessage);
    # Human-readable summary.
    summary @1 :Text;
    # Anomalies detected.
    anomalies @2 :List(KLogAnomaly);
    # Patterns extracted.
    patterns @3 :List(KLogPattern);
    # Aggregate statistics.
    stats @4 :KLogStats;
}

struct KLogAnomaly {
    message @0 :KLogMessage;
    # Anomaly score (0.0 = normal, 1.0 = highly anomalous).
    score @1 :Float32;
    # Human-readable explanation.
    reason @2 :Text;
}

struct KLogPattern {
    # Regex or template pattern.
    pattern @0 :Text;
    # How many times this pattern appeared.
    count @1 :UInt64;
    # Example entries matching this pattern.
    examples @2 :List(KLogMessage);
    # Severity level of this pattern.
    severity @3 :KLogSeverity;
}

struct KLogStats {
    total @0 :UInt64;
    bySeverity @1 :List(KLogSeverityCount);
    bySource @2 :List(KLogSourceCount);
    timeRange @3 :T.Duration;
}

struct KLogSeverityCount {
    severity @0 :KLogSeverity;
    count @1 :UInt64;
}

struct KLogSourceCount {
    source @0 :T.SubsystemId;
    count @1 :UInt64;
}

# ── Distributed Tracing (audit-7) ────────────────────────────

struct KLogTraceContext {
    # OpenTelemetry trace ID.
    traceId @0 :Text;
    # OpenTelemetry span ID.
    spanId @1 :Text;
    # Trace context flags.
    traceFlags @2 :UInt8;
    # Vendor-specific trace state.
    traceState @3 :Text;
    # Baggage items.
    baggage @4 :T.StringMap;
}

struct KLogTraceSpan {
    traceId @0 :Text;
    spanId @1 :Text;
    parentSpanId @2 :Text;
    name @3 :Text;
    kind @4 :SpanKind;
    startTime @5 :T.Timestamp;
    endTime @6 :T.Timestamp;
    status @7 :SpanStatus;
    attributes @8 :T.StringMap;
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

# ── Log Export (audit-7) ─────────────────────────────────────

struct KLogExportRequest {
    filter @0 :KLogFilter;
    format @1 :ExportFormat;
    # File path or endpoint URL.
    destination @2 :Text;
    compression @3 :ExportCompression;
}

enum ExportFormat {
    json @0;
    jsonl @1;        # JSON Lines
    protobuf @2;
    text @3;
    csv @4;
    custom @5;
}

enum ExportCompression {
    none @0;
    gzip @1;
    zstd @2;
    lz4 @3;
    custom @4;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-9: Log retention, archiving, encryption, access control, audit,
# sampling, aggregation, and alerting.
# ═══════════════════════════════════════════════════════════════════════

# ── Log Retention Policy ──────────────────────────────────────

struct KLogRetentionPolicy {
    # Maximum age of log messages before auto-deletion.
    maxAge @0 :T.Duration;
    # Maximum number of log messages to retain (0 = unlimited).
    maxCount @1 :UInt64;
    # Maximum total size of log buffer in bytes (0 = unlimited).
    maxSizeBytes @2 :UInt64;
    # Whether to archive before deleting.
    archiveBeforeDelete @3 :Bool;
}

# ── Log Archiving ─────────────────────────────────────────────

struct KLogArchiveRequest {
    # Archive logs older than this duration.
    olderThan @0 :T.Duration;
    # Destination for archived logs (URI or path).
    destination @1 :Text;
    # Archive format.
    format @2 :ExportFormat;
    # Compression for archive.
    compression @3 :ExportCompression;
}

struct KLogArchiveResult {
    # Number of messages archived.
    archivedCount @0 :UInt64;
    # Size of the archive in bytes.
    archiveSizeBytes @1 :UInt64;
    # Location of the archive.
    archivePath @2 :Text;
    # When the archive was created.
    archivedAt @3 :T.Timestamp;
}

# ── Log Encryption ────────────────────────────────────────────

struct KLogEncryptRequest {
    # Encryption key identifier.
    keyId @0 :Text;
    # Algorithm to use for encryption.
    algorithm @1 :Text;
    # Filter specifying which logs to encrypt.
    filter @2 :KLogFilter;
}

# ── Log Access Control ────────────────────────────────────────

struct KLogAccessPolicy {
    # Required role for read access.
    readRole @0 :Text;
    # Required role for write/clear access.
    writeRole @1 :Text;
    # Whether to allow anonymous read access.
    allowAnonymous @2 :Bool;
    # IP allowlist (empty = allow all).
    ipAllowlist @3 :List(Text);
}

struct KLogAccessAuditEntry {
    # Who accessed the logs.
    accessor @0 :Text;
    # What action was performed.
    action @1 :Text;
    # When the access occurred.
    timestamp @2 :T.Timestamp;
    # IP address of the accessor.
    ipAddress @3 :Text;
    # Number of messages accessed.
    messageCount @4 :UInt64;
}

# ── Log Sampling ──────────────────────────────────────────────
# Sampling rate is a Float32 between 0.0 and 1.0.
# 1.0 = keep all messages, 0.1 = keep 10%, 0.0 = keep none.

# ── Log Aggregation ───────────────────────────────────────────

struct KLogAggregateRequest {
    # Subsystems to aggregate from.
    sources @0 :List(T.SubsystemId);
    # Filter for messages to include.
    filter @1 :KLogFilter;
    # Time window for aggregation.
    window @2 :T.Duration;
}

struct KLogAggregateResult {
    # Aggregated messages.
    messages @0 :List(KLogMessage);
    # Total count before aggregation.
    totalCount @1 :UInt64;
    # Count after aggregation (deduplication).
    aggregatedCount @2 :UInt64;
    # Time range covered.
    timeRange @3 :T.Duration;
}

# ── Log Alerting ──────────────────────────────────────────────

struct KLogAlertRequest {
    # Alert name.
    name @0 :Text;
    # Pattern to match (regex).
    pattern @1 :Text;
    # Minimum severity to trigger alert.
    minSeverity @2 :KLogSeverity;
    # Threshold: number of matches within the window to trigger.
    threshold @3 :UInt32;
    # Time window for threshold counting.
    window @4 :T.Duration;
    # Action to take when alert fires.
    action @5 :Text;
}

struct KLogAlert {
    # Alert identifier.
    id @0 :Text;
    # Alert configuration.
    request @1 :KLogAlertRequest;
    # When the alert was created.
    createdAt @2 :T.Timestamp;
    # Whether the alert is currently active.
    active @3 :Bool;
    # Number of times this alert has fired.
    fireCount @4 :UInt64;
    # When the alert last fired.
    lastFired @5 :T.Timestamp;
}

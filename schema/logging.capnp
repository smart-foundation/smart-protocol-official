@0xa1b2c3d4e5f60024;

# ═══════════════════════════════════════════════════════════════════════
# Logging — application-level structured log ingestion.
#
# The canonical log contract for the whole protocol. `LogEntry`,
# `LogFilter`, `TraceContext`, `TraceSpan`, `SpanKind` and `SpanStatus`
# are defined HERE and imported by everyone else: klog.capnp (the kernel
# scribe) and diagnostics.capnp (telemetry) both return this `LogEntry`
# rather than declaring a third and fourth shape.
#
# ── THE RELEASE-BLOCKER, EXECUTED ──────────────────────────────────────
#
# DESIGN_PRINCIPLES.md has flagged this file since 2026-07-01: remove
# `LogFormat` and `LogOutput`, make `LogSource` opaque. The pre-revamp
# body kept all three. They are gone now, and here is what replaced them:
#
#   `LogFormat { text, json, xml }` — an output-format enum. A logging
#   backend may use binary, CBOR, protobuf, columnar storage or a format
#   invented in 2046; none of those has an ordinal. Replaced by
#   `export (format :T.MimeType)`, an open content type: a new format is
#   a new subtype, not a schema edit.
#
#   `LogOutput { stdout, stderr, systemLog, structuredLog, file }` — an
#   output-destination enum naming syslog/journald/ELK/Loki in its
#   comments. This is the exact row TIMELESSNESS.md:76 rejects. Deleted
#   outright: where a message GOES is the backend's business, and the
#   contract never needed to name it.
#
#   `LogSource { file, line, function }` — a structured source location
#   that assumes compiled languages with source files. WASM,
#   interpreted and JIT producers had to falsify three fields. Replaced
#   by `source @6 :Data`, opaque and backend-decided, exactly as
#   DESIGN_PRINCIPLES.md:181 prescribed.
#
# ── WHAT ELSE WAS DELETED ──────────────────────────────────────────────
#
# The pre-revamp file was also an observability platform: SQL-like
# queries, AI distillation, redaction, alert rules, enrichment and
# aggregation. Each of those either duplicates a query the caller can do
# over `getEntries`, mutates an append-only log (`redact`), or registers
# a stateful rule set this schema cannot keep consistent. Kept: the
# honest ingestion path, the query path, subscription, per-domain level,
# declared sampling, export. `setSamplingRate` stays because declared
# sampling is the honest alternative to silent drops.
#
# ── WHAT `log` RETURNS ─────────────────────────────────────────────────
#
# `T.VoidResult` swallows the outcome: accepted? sampled away? dropped?
# "NEVER swallow errors silently" (DESIGN_PRINCIPLES.md:428) — so
# `LogOutcome` distinguishes them, and a producer at volume can tell a
# deliberate sample from a failure.
#
# Authority is the interface reference: holding the `Logging` reference
# is the authority to write and to read. There is no per-method token
# (R3, ai.capnp precedent).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface Logging {
    # The hot path, and the first ordinal because it is the hottest.
    # A backend reports whether the entry was accepted, sampled away, or
    # dropped — never a silent success.
    log @0 (severity :T.LogLevel, domain :Text, message :Text) -> (outcome :LogOutcome);

    # Bounded query over retained entries.
    getEntries @1 (filter :LogFilter, page :T.Pagination) -> (entries :List(LogEntry), total :UInt64);

    # Live stream. Holding the returned subscription IS the authority to
    # pull — there is no subscription id to present.
    subscribe @2 (filter :LogFilter) -> (subscription :LogSubscription);

    # Per-domain level configuration.
    setLevel @3 (domain :Text, level :T.LogLevel) -> T.VoidResult;
    getLevel @4 (domain :Text) -> (level :T.LogLevel);

    # Clear one domain's retained entries.
    clear @5 (domain :Text) -> T.VoidResult;

    # Export retained entries in an OPEN content type. The format is a
    # T.MimeType, so a 2046 columnar or binary export needs no ordinal.
    export @6 (filter :LogFilter, format :T.MimeType) -> (data :T.DataHandle);

    # Declared sampling: a producer that will drop 90% of debug entries
    # says so, instead of a consumer discovering it statistically.
    setSamplingRate @7 (domain :Text, rate :Float32) -> T.VoidResult;

    # List known domains and their configured levels.
    listDomains @8 (page :T.Pagination) -> (domains :List(LogDomain), total :UInt64);
}

# ── The log entry ───────────────────────────────────────────────────────

struct LogEntry {
    id @0 :T.EventId;
    # Monotonic sequence within the producer's boot epoch. Supports
    # ordering, deduplication and gap detection: a consumer that pulls
    # 1, 2, 4 knows an entry was dropped. Two producers' sequences are
    # NOT comparable — correlate on (producer, sequence), never on
    # sequence alone.
    sequence @1 :UInt64;
    timestamp @2 :T.Timestamp;
    level @3 :T.LogLevel;
    domain @4 :Text;
    message @5 :Text;
    # Opaque source location: file/line for a compiled language, a cell
    # for a notebook, nothing for a JIT. Backend-decided, never parsed.
    source @6 :Data;
    # Typed identity of the producing subsystem (kernel scribe, driver,
    # …). Zero when the producer is not a kernel subsystem. Applications
    # group by `domain`; kernel components group here.
    subsystem @7 :T.SubsystemId;
    # Open key/value metadata.
    metadata @8 :T.StringMap;
    # Correlation across services.
    correlationId @9 :Text;
    # Distributed-trace correlation (see TraceContext).
    traceId @10 :Text;
    spanId @11 :Text;
    parentSpanId @12 :Text;
}

# ── The filter ──────────────────────────────────────────────────────────

struct LogFilter {
    # Empty domain = all domains.
    domain @0 :Text;
    # Minimum level (entries at or above this level only).
    minLevel @1 :T.LogLevel;
    since @2 :T.Timestamp;
    until @3 :T.Timestamp;
    # Plain substring match on the message. Not a query language.
    pattern @4 :Text;
    # Restrict to specific subsystems (empty = all).
    subsystems @5 :List(T.SubsystemId);
    # Only entries from this trace.
    traceId @6 :Text;
    # Only entries after this sequence (0 = no lower bound) — the
    # gap-detection lever.
    afterSequence @7 :UInt64;
    # Open metadata match.
}

# ── The outcome ─────────────────────────────────────────────────────────

struct LogOutcome {
    union {
        accepted @0 :Void;
        # Accepted by the sampling policy and not retained. Declared, so
        # a producer can reason about it.
        sampled @1 :Void;
        # Not retained for another reason (buffer full, rate limited).
        # `reason` is open; the caller decides what to do.
        dropped @2 :Void;
        error @3 :T.Error;
        unknown @4 :T.UnknownEvent;
    }
}

struct LogDomain {
    name @0 :Text;
    level @1 :T.LogLevel;
    description @2 :Text;
    # Configured sampling rate, so a consumer can see what it is missing.
    samplingRate @3 :Float32;
}

interface LogSubscription {
    # Bounded pull: the caller states how many entries it will take.
    pull @0 (maxEntries :UInt32) -> (entries :List(LogEntry));
    cancel @1 () -> T.VoidResult;
}

# ── Distributed tracing ─────────────────────────────────────────────────
# The canonical trace primitives, shared with diagnostics.capnp. Carriers
# are OPEN: the pre-revamp `TraceCarrierFormat { httpHeaders,
# grpcMetadata, … }` named a 2016 transport in a file whose header
# claimed "no Prometheus, no OpenTelemetry". A trace context is
# propagated as a string map, so whatever carries it in 2046 — a header,
# a socket option, a kernel channel — needs no schema change.

struct TraceContext {
    # Opaque trace id (the producer's spelling: W3C trace-parent, a
    # 128-bit hex id, or anything else). Consumers correlate on bytes,
    # not on a format.
    traceId @0 :Text;
    spanId @1 :Text;
    # Trace flags as an opaque octet (sampled bit, etc.).
    traceFlags @2 :UInt8;
    # Vendor/transport-specific trace state.
    traceState @3 :Text;
    # Propagation baggage — open key/value.
    baggage @4 :T.StringMap;
}

struct TraceSpan {
    name @0 :Text;
    # Parent span id (empty for a root span).
    parentSpanId @1 :Text;
    kind @2 :SpanKind;
    startTime @3 :T.Timestamp;
    endTime @4 :T.Timestamp;
    status @5 :SpanStatus;
    # Key-value attributes.
    attributes @6 :T.StringMap;
}

enum SpanKind {
    unknown @0;
    internal @1;
    server @2;
    client @3;
    producer @4;
    consumer @5;
    custom @6;
}

enum SpanStatus {
    unknown @0;
    ok @1;
    error @2;
    cancelled @3;
    custom @4;
}

@0xa1b2c3d4e5f60045;

# ═══════════════════════════════════════════════════════════════════════
# KLog — the kernel's scribe: retention and delivery of kernel and
#        driver output.
#
# Named honestly for what it is. The pre-revamp header called this file
# "the kernel log service … the system equivalent of dmesg / syslog
# kernel messages", and its body had grown a second observability
# platform: search, distillation, trace spans, export with compression
# codecs, retention policy, archiving, encryption, an RBAC access model,
# sampling, aggregation and alerting — a third copy of machinery
# logging.capnp already defines, plus a role-based permission model the
# doctrine forbids.
#
# This file now keeps ONLY the kernel-scribe surface:
#
#   * reading what the kernel wrote (`read`, over the canonical
#     `logging.LogEntry` — not a fourth log-entry shape)
#   * watching it arrive (`subscribe` + bounded `pull` + `cancel`)
#   * knowing what was LOST (`bufferStatus`)
#   * clearing and sampling the buffer
#
# Everything else moved to its owner: log entries, filters and trace
# primitives to logging.capnp; alerts and queries to whoever actually
# wants to build a query tool; access control to capability.capnp (the
# pre-revamp `KLogAccessPolicy { readRole, writeRole, ipAllowlist }` was
# a role-based permission model, and an IP allowlist, inside an
# IPC-only system — deleted).
#
# ── THE OVERFLOW CONTRACT ──────────────────────────────────────────────
#
# This was the file's most important missing contract, and it is now
# stated: the kernel ring buffer DROPS THE OLDEST message when full. The
# pre-revamp schema reported `bufferSize` and nothing else, so on the
# one boot that matters — the one that crashed — the messages explaining
# the crash were the ones silently gone.
#
# `bufferStatus` therefore reports `droppedOldest`, the running count of
# messages evicted. A consumer that reads entries with sequences
# 100..104 and 5000..5001 knows a gap exists and how many entries are
# missing, instead of assuming continuity.
#
# Authority is the interface reference: holding `KernelLogService` is the
# authority to read and to clear. There is no per-method token (R3).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using L = import "logging.capnp";

interface KernelLogService {
    # Read recent kernel messages matching a filter. `filter.limit` is a
    # required bound — a read with no limit is a request for an unbounded
    # message, and the backend answers with its own default only when the
    # caller asks for the default by passing zero.
    read @0 (filter :KLogFilter) -> (entries :List(L.LogEntry));

    # Watch kernel output arrive. Holding the subscription IS the
    # authority to pull; there is no subscription id to present.
    subscribe @1 (filter :KLogFilter) -> (subscription :KernelLogSubscription);

    # Ring-buffer status, including the overflow count that makes gap
    # detection possible.
    bufferStatus @2 () -> (capacityMessages :UInt32,
                           capacityBytes :UInt64,
                           retainedMessages :UInt32,
                           retainedBytes :UInt64,
                           droppedOldest :UInt64,
                           droppedNew :UInt64);

    # Clear the buffer.
    clear @3 () -> T.VoidResult;

    # Declared sampling: what fraction of messages the kernel retains.
    setSamplingRate @4 (rate :Float32) -> T.VoidResult;
    getSamplingRate @5 () -> (rate :Float32);
}

interface KernelLogSubscription {
    # Bounded pull: the caller states how many entries it will take.
    pull @0 (maxEntries :UInt32) -> (entries :List(L.LogEntry));
    cancel @1 () -> T.VoidResult;
}

# ── Kernel log filter ───────────────────────────────────────────────────
# Same shape as logging.LogFilter plus the kernel-specific levers: typed
# subsystems (the audit-5 fix, kept) and `afterSequence` for gap
# detection.

struct KLogFilter {
    # If set, only include messages at or above this level.
    minLevel @0 :T.LogLevel;
    # If non-empty, only include messages from these subsystems.
    subsystems @1 :List(T.SubsystemId);
    # Only include messages after this sequence (0 = no lower bound).
    afterSequence @2 :UInt64;
    # Only include messages at or before this timestamp (zero = no bound).
    beforeTimestamp @3 :T.Timestamp;
    # Maximum number of messages to return. Zero = backend default, which
    # MUST itself be bounded. A caller that never sets this is asking for
    # an unbounded read, and gets whatever the backend chose.
    limit @4 :UInt32;
    # Plain substring match on the message.
    pattern @5 :Text;
}

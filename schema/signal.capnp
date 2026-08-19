@0xa1b2c3d4e5f60065;

using T = import "types.capnp";

# ══════════════════════════════════════════════════════════════════════
# Signal — Typed signal/event system for inter-process notification.
#
# Referenced by:
#   - process.capnp (signal delivery, AppCrashEvent.signal)
#   - app.capnp (AppCrashEvent.signal)
#   - kernel.capnp (signal handling)
#
# Design principles:
#   - No POSIX signal number assumptions (SIGTERM=15, SIGKILL=9, etc.)
#   - No Android signal assumptions (signal 9 = kill)
#   - Signal semantics are cross-platform; backends map to native signals
#   - The T.SignalKind enum in types.capnp defines the canonical signal types
#   - This schema adds the service layer: send, subscribe, list, handle
#
# Signal semantics:
#   - Signals are asynchronous notifications sent to a process or thread
#   - Each signal has a kind (terminate, interrupt, kill, etc.) and optional payload
#   - Signals can carry a small data payload (user-defined signals)
#   - Signal delivery is best-effort; the receiver may not handle the signal
#   - Multiple signal handlers can be registered for different signal kinds
# ══════════════════════════════════════════════════════════════════════

# ── Enums ────────────────────────────────────────────────────

enum SignalAction {
    ignore @0;          # Discard the signal
    default @1;         # Use backend-default action for this signal
    handler @2;         # Invoke registered handler
    custom @3;          # Backend-specific action
}

enum SignalDeliveryResult {
    delivered @0;       # Signal was delivered to the target
    notFound @1;        # Target process/thread does not exist
    notPermitted @2;    # Caller lacks permission to send signal
    throttled @3;       # Signal delivery was rate-limited
    queued @4;          # Signal was queued (target not yet ready)
    timedOut @5;        # Signal delivery timed out
    custom @6;          # Backend-specific result
}

# Audit-8: Signal priority levels.
enum SignalPriority {
    urgent     @0;   # Highest priority, delivered immediately
    high       @1;   # High priority, delivered before normal
    normal     @2;   # Normal priority (default)
    low        @3;   # Low priority, delivered after normal
    background @4;   # Background priority, delivered when idle
    custom     @5;   # Backend-specific priority
}

# ── Structs ──────────────────────────────────────────────────

struct SignalEvent {
    sender @0 :T.ProcessId;          # 0 = system signal (no sender)
    receiver @1 :T.ProcessId;        # Target process
    signal @2 :T.SignalKind;         # Signal type (from types.capnp)
    timestamp @3 :T.Timestamp;
    payload @4 :T.DataHandle;        # Optional data payload (for userDefined signals)
    threadId @5 :T.ThreadId;         # 0 = process-level signal
}

struct SignalMask {
    # Which signal kinds are blocked (will not be delivered).
    blocked @0 :List(T.SignalKind);
    # Which signal kinds are pending (queued but not yet delivered).
    pending @1 :List(T.SignalKind);
}

struct SignalHandler {
    signal @0 :T.SignalKind;         # Which signal this handler is for
    action @1 :SignalAction;
    # For handler action: optional handler identifier
    handlerId @2 :Text;              # Backend-decided handler reference
}

struct SignalInfo {
    kind @0 :T.SignalKind;
    defaultAction @1 :SignalAction;  # What happens if no handler is registered
    description @2 :Text;            # Human-readable description
    canBlock @3 :Bool;               # Whether this signal can be blocked
    canCatch @4 :Bool;               # Whether this signal can have a custom handler
}

# ── Filter ───────────────────────────────────────────────────

struct SignalFilter {
    # Filter by sender (empty = any sender)
    sender @0 :T.ProcessId;
    # Filter by receiver (empty = any receiver)
    receiver @1 :T.ProcessId;
    # Filter by signal kinds (empty = all kinds)
    kinds @2 :List(T.SignalKind);
    # Filter by time range
    since @3 :T.Timestamp;           # 0 = no lower bound
    before @4 :T.Timestamp;          # 0 = no upper bound
    pagination @5 :T.Pagination;
}

# ── Subscription ─────────────────────────────────────────────

interface SignalSubscription {
    pull @0 () -> (events :List(SignalEvent), pagination :T.Pagination, total :UInt64);
    cancel @1 () -> T.VoidResult;

    # Audit-8: Paginated event retrieval.
    pullPaged @2 (pagination :T.Pagination)
        -> (events :List(SignalEvent), total :UInt64);
}

# ── Audit-8: Signal Rate Limit ────────────────────────────────────────

struct SignalRateLimit {
    # Maximum signals per second.
    maxPerSecond @0 :UInt32;
    # Maximum burst size.
    maxBurst @1 :UInt32;
    # Cooldown duration after burst.
    cooldownDuration @2 :T.Duration;
    # Whether rate limiting is enabled.
    enabled @3 :Bool;
}

# ── Audit-8: Signal Timeout ───────────────────────────────────────────

struct SignalTimeout {
    # Signal kind this timeout applies to.
    signalKind @0 :T.SignalKind;
    # Timeout duration.
    timeout @1 :T.Duration;
    # Action on timeout.
    onTimeout @2 :SignalTimeoutAction;
}

enum SignalTimeoutAction {
    escalate @0;   # Escalate to a higher-priority signal
    abort    @1;   # Abort the target process
    retry    @2;   # Retry signal delivery
    log      @3;   # Log the timeout and continue
    custom   @4;   # Backend-specific action
}

# ── Audit-8: Signal Audit Entry ───────────────────────────────────────

struct SignalAuditEntry {
    # When the signal was sent.
    timestamp @0 :T.Timestamp;
    # Sender process.
    sender @1 :T.ProcessId;
    # Receiver process.
    receiver @2 :T.ProcessId;
    # Signal kind.
    signal @3 :T.SignalKind;
    # Whether the signal was delivered.
    delivered @4 :Bool;
    # Handler result (if handled).
    handlerResult @5 :Text;
}

# ── Audit-8: Signal Mapping Table ─────────────────────────────────────

struct SignalMappingTable {
    # Backend name (e.g., "posix", "windows", "linux").
    backendName @0 :Text;
    # Signal mappings.
    mappings @1 :List(SignalMapping);
}

struct SignalMapping {
    # Platform-specific signal number.
    platformSignal @0 :UInt32;
    # Mapped cross-platform signal kind.
    mappedKind @1 :T.SignalKind;
    # Human-readable description.
    description @2 :Text;
}

# ── Audit-8: Replayable Signal ────────────────────────────────────────

struct ReplayableSignal {
    # Event ID of the original signal.
    eventId @0 :T.EventId;
    # Original timestamp.
    originalTimestamp @1 :T.Timestamp;
    # Signal kind.
    signal @2 :T.SignalKind;
    # Signal payload.
    payload @3 :T.DataHandle;
}

# ── Audit-8: Signal Group ─────────────────────────────────────────────

struct SignalGroup {
    # Group identifier (0 = new group).
    groupId @0 :UInt32;
    # Human-readable group name.
    name @1 :Text;
    # Processes in this group.
    processes @2 :List(T.ProcessId);
    # Signal kinds this group receives.
    signalKinds @3 :List(T.SignalKind);
}

# ── Audit-8: Signal Cascade ───────────────────────────────────────────

struct SignalCascade {
    # Original signal kind.
    originalSignal @0 :T.SignalKind;
    # Processes to cascade the signal to.
    cascadedTo @1 :List(T.ProcessId);
    # Cascade policy.
    cascadePolicy @2 :SignalCascadePolicy;
}

enum SignalCascadePolicy {
    forward   @0;   # Forward the signal as-is
    transform @1;   # Transform the signal (backend-specific)
    drop      @2;   # Drop the signal (no cascade)
    custom    @3;   # Backend-specific policy
}

# ── Audit-8: Signal Classification (AI-assisted) ─────────────────────

struct SignalClassification {
    # Signal kind.
    signalKind @0 :T.SignalKind;
    # Confidence score (0.0-1.0).
    confidence @1 :Float32;
    # Suggested handler name.
    suggestedHandler @2 :Text;
    # Classification category (e.g., "system", "user", "error").
    category @3 :Text;
}

# ── Service ──────────────────────────────────────────────────

interface SignalService {
    # Send a signal to a process or thread
    send @0 (signal :T.SignalKind, receiver :T.ProcessId,
             payload :T.DataHandle,
             threadId :T.ThreadId) -> (result :SignalDeliveryResult);

    # Batch send: send the same signal to multiple processes
    sendBatch @1 (signal :T.SignalKind, receivers :List(T.ProcessId),
                  payload :T.DataHandle) -> (results :List(SignalDeliveryResult));

    # Query available signal kinds and their default actions
    listAvailable @2 () -> (signals :List(SignalInfo));

    # Manage signal handlers for the calling process
    setHandler @3 (handler :SignalHandler) -> T.VoidResult;
    removeHandler @4 (signal :T.SignalKind) -> T.VoidResult;
    getHandlers @5 () -> (handlers :List(SignalHandler));

    # Manage signal mask for the calling process
    setMask @6 (mask :SignalMask) -> T.VoidResult;
    getMask @7 () -> (mask :SignalMask);

    # Query pending signals
    getPending @8 (processId :T.ProcessId) -> (pending :List(SignalEvent));

    # Signal history (for debugging / audit)
    listSignals @9 (filter :SignalFilter) -> (events :List(SignalEvent), total :UInt64);

    # Event subscription
    subscribe @10 (filter :SignalFilter) -> (subscription :SignalSubscription);

    # Audit-8: Send signal to a process group (cross-platform killpg equivalent).
    sendToGroup @11 (signal :T.SignalKind, groupId :UInt32,
        payload :T.DataHandle) -> (results :List(SignalDeliveryResult));

    # Audit-8: Get/set rate limits per signal kind.
    getRateLimit @12 (signal :T.SignalKind) -> (limit :SignalRateLimit);
    setRateLimit @13 (signal :T.SignalKind, limit :SignalRateLimit) -> T.VoidResult;

    # Audit-8: Get/set signal timeout for a process.
    getSignalTimeout @14 (processId :T.ProcessId) -> (timeout :SignalTimeout);
    setSignalTimeout @15 (processId :T.ProcessId, timeout :SignalTimeout) -> T.VoidResult;

    # Audit-8: Get signal audit log.
    getAuditLog @16 (filter :SignalFilter, pagination :T.Pagination)
        -> (entries :List(SignalAuditEntry), total :UInt64);

    # Audit-8: Export signal audit log for compliance.
    exportAuditLog @17 (filter :SignalFilter, format :Text) -> (data :T.DataHandle);

    # Audit-8: Set thread-level signal mask.
    setThreadMask @18 (threadId :T.ThreadId, mask :SignalMask) -> T.VoidResult;

    # Audit-8: Get thread-level signal mask.
    getThreadMask @19 (threadId :T.ThreadId) -> (mask :SignalMask);

    # Audit-8: Get thread-level pending signals.
    getThreadPending @20 (threadId :T.ThreadId) -> (pending :List(SignalEvent));

    # Audit-8: Get signal mapping for a backend.
    getSignalMapping @21 (backendName :Text) -> (mapping :SignalMappingTable);

    # Audit-8: Replay a previously delivered signal.
    replaySignal @22 (eventId :T.EventId) -> (result :SignalDeliveryResult);

    # Audit-8: List replayable signals.
    listReplayable @23 (filter :SignalFilter) -> (signals :List(ReplayableSignal));

    # Audit-8: Get signal group info.
    getSignalGroup @24 (groupId :UInt32) -> (group :SignalGroup);

    # Audit-8: Create a signal group.
    createSignalGroup @25 (group :SignalGroup) -> (groupId :UInt32);

    # Audit-8: Delete a signal group.
    deleteSignalGroup @26 (groupId :UInt32) -> T.VoidResult;

    # Audit-8: Configure signal cascade rules.
    setCascadeRule @27 (originalSignal :T.SignalKind, rule :SignalCascade) -> T.VoidResult;

    # Audit-8: Get signal cascade rules.
    getCascadeRule @28 (originalSignal :T.SignalKind) -> (rule :SignalCascade);

    # Audit-8: Buffer signals for slow receivers.
    bufferSignal @29 (signal :T.SignalKind, receiver :T.ProcessId,
        payload :T.DataHandle) -> T.VoidResult;

    # Audit-8: Flush buffered signals for a process.
    flushBuffer @30 (processId :T.ProcessId) -> (count :UInt32);

    # Audit-8: Get buffer size for a process.
    getBufferSize @31 (processId :T.ProcessId) -> (size :UInt32, oldestTimestamp :T.Timestamp);

    # Audit-8: Classify a signal using AI-assisted routing.
    classifySignal @32 (signal :T.SignalKind, payload :T.DataHandle)
        -> (classification :SignalClassification);

    # Audit-10: Route a signal automatically based on classification.
    routeSignal @33 (signal :T.SignalKind, payload :T.DataHandle, receiver :T.ProcessId,
        threadId :T.ThreadId) -> (result :SignalDeliveryResult, classification :SignalClassification);

    # Audit-10: Replay signal with modified payload.
    replaySignalWith @34 (eventId :T.EventId, modifiedPayload :T.DataHandle,
        modifiedReceiver :T.ProcessId) -> (result :SignalDeliveryResult);

    # Audit-10: Signal group persistence for cross-session management.
    persistSignalGroup @35 (groupId :UInt32) -> (persistenceId :Text);
    loadSignalGroup @36 (persistenceId :Text) -> (group :SignalGroup);
    deletePersistedGroup @37 (persistenceId :Text) -> T.VoidResult;
    listPersistedGroups @38 () -> (persistenceIds :List(Text));

    # Audit-10: Cascade depth limits to prevent infinite loops.
    setCascadeDepthLimit @39 (maxDepth :UInt32) -> T.VoidResult;
    getCascadeDepthLimit @40 () -> (maxDepth :UInt32, currentDepth :UInt32);
}

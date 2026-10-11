@0xa1b2c3d4e5f60065;

# ═══════════════════════════════════════════════════════════════════════
# Signal — typed asynchronous notification of processes and threads.
#
# The kernel of this file has always been right: `T.SignalKind` (no POSIX
# numbers, no exceptions), `T.DataHandle` payloads, filter + subscription
# + cancel. What surrounds it was an invented feature stack that no 2046
# implementer could derive from the contract.
#
# ── THE ONE DELIVERY AUTHORITY ─────────────────────────────────────────
#
# Three interfaces could deliver a signal — this one, `KernelService
# .signal`, and `Process.kill` — each with its own permission check and
# its own error model (`SignalDeliveryResult.notPermitted` here,
# `T.VoidResult` there). A supervisor had to implement and keep three
# checks identical.
#
# `SignalService.send` is now the ONLY delivery path, because it has the
# richest identity (process, thread or group), the typed result, and the
# zero-copy payload. The kernel still performs the delivery; the contract
# for asking it to is here. `kernel.signal` and `process.kill` are gone.
#
# ── WHAT WAS DELETED, AND WHY ──────────────────────────────────────────
#
#   * `SignalMappingTable` / `SignalMapping` / `getSignalMapping` — POSIX
#     signal numbers re-imported through the back door
#     (`platformSignal :UInt32`, `backendName "posix"/"linux"`) in the one
#     file whose header promises "No POSIX signal number assumptions". A
#     message-based runtime has no numbers to map; native numbering
#     belongs in backend documentation, not on the wire.
#   * the buffering block (`bufferSignal`, `flushBuffer`,
#     `getBufferSize`) — producer-side buffering of undelivered signals
#     with no bound and no declared policy. Where a subscription pull
#     belongs, the design forced server-held queues.
#   * cascades (`setCascadeRule`, `getCascadeRule`, `setCascadeDepthLimit`,
#     `getCascadeDepthLimit`) — an invented cascade algebra with depth
#     limits, no consumer, and no derivable semantics.
#   * group persistence (`persistSignalGroup`, `loadSignalGroup`,
#     `deletePersistedGroup`, `listPersistedGroups`) — a persistence
#     protocol for a grouping concept that process.capnp already owns as
#     `ProcessGroup`.
#   * `classifySignal` / `routeSignal` — "AI-assisted routing" as an OS
#     method: no classification vocabulary, no confidence semantics, no
#     fallback, and a `suggestedHandler` string every backend would spell
#     differently.
#   * `replaySignalWith` — replaying a recorded signal with a MODIFIED
#     payload and receiver. The capability to receive does not imply the
#     capability to redirect: this was a privilege-escalation primitive.
#   * thread-mask duplication (`setThreadMask`, `getThreadMask`,
#     `getThreadPending`) — a second mask model beside `setMask`/`getMask`.
#   * `SignalAuditEntry` + `getAuditLog` + `exportAuditLog` — a fourth
#     audit-entry shape (capability, session, klog, here) and an ungated
#     audit export. A signal delivery is a loggable event: it belongs in
#     the log stream with its typed kind, which keeps ONE audit grammar.
#   * `SignalGroup` — duplicated process.capnp's `ProcessGroup` under a
#     UInt32 id with a "0 = new group" sentinel.
#   * the `pull` / `pullPaged` ambiguity — two pull methods with different
#     request/response pairing. One paginated pull remains.
#
# ── STANDARD SIGNAL SEMANTICS, DECLARED ────────────────────────────────
#
# `T.SignalKind.terminate` means the receiver MUST stop. Whether it runs
# a handler first is the receiver's business. `listAvailable` is a
# CONTRACT, not a hint: a backend MUST answer truthfully about which
# kinds exist, what their default action is, and whether they can be
# blocked or caught. A consumer that is told `canCatch = false` may
# assume the signal cannot be intercepted.
#
# Authority is the interface reference: holding `SignalService` is the
# authority to send within the receivers the backend permits. No
# per-method token (R3).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# Who sent a signal. The pre-revamp `sender :T.ProcessId` with
# "0 = system signal" collided with kernels where PID 0 is a real (idle)
# task, so "was this the system?" was unanswerable.
struct SenderRef {
    union {
        process @0 :T.ProcessId;
        service @1 :T.ServiceId;
        # The system itself, with no process behind it.
        system @2 :Void;
        unknown @3 :T.UnknownEvent;
    }
}

# One signal, as delivered or as pending.
struct SignalEvent {
    id @0 :T.EventId;
    # Monotonic time, so ordering survives clock adjustment.
    at @1 :T.MonotonicTimestamp;
    signalKind @2 :T.SignalKind;
    sender @3 :SenderRef;
    # Payload, zero-copy.
    payload @4 :T.DataHandle;
    # What happened when the signal was delivered.
    result @5 :SignalDeliveryResult;
    # Thread the signal was delivered to (zero = any thread).
    threadId @6 :T.ThreadId;
    # Group the signal was addressed to (zero = none).
    groupId @7 :T.GroupId;
}

enum SignalDeliveryResult {
    unknown @0;
    # Handed to the receiver.
    delivered @1;
    # The receiver's mask blocks this kind; the signal is now pending.
    blocked @2;
    # The caller may not signal this receiver.
    notPermitted @3;
    # No handler and no default action: the kind is unknown to this
    # backend. A consumer must treat this as "nothing happened" and not
    # as success.
    noHandler @4;
    # Accepted for later delivery: the receiver is not runnable now.
    queued @5;
    custom @6;
}

struct SignalSendRequest {
    signalKind @0 :T.SignalKind;
    receiver @1 :T.ProcessId;
    # Payload, zero-copy. Small payloads inline automatically.
    payload @2 :T.DataHandle;
    # Thread to deliver to (zero = any thread of the receiver).
    threadId @3 :T.ThreadId;
    # Group to deliver to (zero = this process only). The group type is
    # process.capnp's canonical `ProcessGroup` identity.
    groupId @4 :T.GroupId;
    metadata @5 :T.StringMap;
}

struct SignalInfo {
    signalKind @0 :T.SignalKind;
    # What the backend does with this kind by default.
    defaultAction @1 :SignalAction;
    canBlock @2 :Bool;
    canCatch @3 :Bool;
    description @4 :Text;
}

enum SignalAction {
    unknown @0;
    # Stop the receiver (after any handler it is permitted to run).
    terminate @1;
    # Stop without running handlers.
    terminateNow @2;
    # Ignore.
    ignore @3;
    # Continue if stopped.
    continueExecution @4;
    # Stop without terminating.
    stop @5;
    custom @6;
}

struct SignalHandler {
    signalKind @0 :T.SignalKind;
    action @1 :SignalAction;
    # Thread the handler runs on (zero = any).
    threadId @2 :T.ThreadId;
}

# Which kinds the receiver blocks, and which are waiting.
struct SignalMask {
    blocked @0 :List(T.SignalKind);
    pending @1 :List(T.SignalKind);
}

struct SignalFilter {
    signalKinds @0 :List(T.SignalKind);
    # Restrict to signals from this sender.
    fromProcess @1 :T.ProcessId;
    # Restrict to signals addressed to this group.
    groupId @2 :T.GroupId;
    since @3 :T.Timestamp;
    # Restrict to signals delivered to this thread.
    threadId @4 :T.ThreadId;
    # Only signals with this delivery result.
    results @5 :List(SignalDeliveryResult);
}

# A declared ceiling, so a misbehaving producer cannot flood a receiver.
struct SignalRateLimit {
    # Maximum signals of this kind per window.
    maxPerWindow @0 :UInt32;
    window @1 :T.Duration;
    # What the backend does at the ceiling, so a producer can predict.
    atLimit @2 :SignalTimeoutAction;
}

struct SignalTimeout {
    # How long to wait for the receiver to acknowledge the signal.
    timeout @0 :T.Duration;
    # What to do when the timeout elapses.
    action @1 :SignalTimeoutAction;
}

enum SignalTimeoutAction {
    unknown @0;
    escalate @1;
    abort @2;
    retry @3;
    log @4;
    custom @5;
}

# ── The delivery authority ──────────────────────────────────────────────
# The root of the signal domain: handed to the caller by the host, so it
# is deliberately not returned by any method. `SignalSubscription` IS
# returned (by `subscribe`), so every interface here is reachable.

interface SignalService {
    # THE delivery path. One call, one typed result.
    send @0 (request :SignalSendRequest) -> (result :SignalDeliveryResult);

    # Batch send: several requests, one call, results in order.
    sendBatch @1 (requests :List(SignalSendRequest)) -> (results :List(SignalDeliveryResult));

    # Send to every member of a process group.
    sendToGroup @2 (request :SignalSendRequest) -> (results :List(SignalDeliveryResult));

    # Query the kinds this backend actually has, and their declared
    # semantics. Truthful by contract.
    listAvailable @3 () -> (signals :List(SignalInfo));

    # Handlers for the calling process.
    setHandler @4 (handler :SignalHandler) -> T.VoidResult;
    removeHandler @5 (signal :T.SignalKind) -> T.VoidResult;
    getHandlers @6 () -> (handlers :List(SignalHandler));

    # Mask for the calling process.
    setMask @7 (mask :SignalMask) -> T.VoidResult;
    getMask @8 () -> (mask :SignalMask);

    # What is waiting right now.
    getPending @9 (processId :T.ProcessId) -> (pending :List(SignalEvent));

    # History, bounded and paginated.
    listSignals @10 (filter :SignalFilter, pagination :T.Pagination)
               -> (events :List(SignalEvent), total :UInt64);

    # Live stream. Holding the subscription IS the authority to pull.
    subscribe @11 (filter :SignalFilter) -> (subscription :SignalSubscription);

    # Declared ceiling for one kind.
    getRateLimit @12 (signal :T.SignalKind) -> (limit :SignalRateLimit);
    setRateLimit @13 (signal :T.SignalKind, limit :SignalRateLimit) -> T.VoidResult;

    # Declared timeout behaviour.
    getSignalTimeout @14 (processId :T.ProcessId) -> (timeout :SignalTimeout);
    setSignalTimeout @15 (processId :T.ProcessId, timeout :SignalTimeout) -> T.VoidResult;
}

interface SignalSubscription {
    # ONE pull method, paginated: the request states the page, the
    # response states the total, so request and response pairing is
    # unambiguous. (The pre-revamp file had `pull` returning a pagination
    # echo and `pullPaged` doing it properly.)
    pull @0 (pagination :T.Pagination) -> (events :List(SignalEvent), total :UInt64);
    cancel @1 () -> T.VoidResult;
}

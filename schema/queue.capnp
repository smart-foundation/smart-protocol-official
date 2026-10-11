@0xa1b2c3d4e5f60030;

# ═══════════════════════════════════════════════════════════════════════
# Queue — message queue lifecycle, enqueue/dequeue, subscriptions.
#
# The core is one of the best citizens in the protocol: `T.DataHandle`
# payloads (correct zero-cost choice), `T.Pagination` on the bounded
# queries, typed ids throughout, ack/nack with a structured handle,
# dead-letter routing, declared flow control. This revamp keeps that and
# deletes the distributed message broker welded onto it.
#
# ── THE IMPOSSIBLE PROMISE, REMOVED ────────────────────────────────────
#
# `DeliveryMode.exactlyOnce` could not be kept. Exactly-once delivery
# over a lossy channel is the two-generals problem: it can only be
# approximated, and the approximation is a design decision. Two backends
# therefore answered the same value with different duplicate/loss
# profiles, and a consumer could not write a portable handler.
#
# What remains: `atMostOnce`, `atLeastOnce`, and `custom`, plus the two
# honest mechanisms that make at-least-once usable — `DeduplicationKey`
# (producer-chosen idempotence key, checked by `deduplicate`) and the
# ack/nack window. A consumer that needs exactly-once effects makes its
# handler idempotent, which is where that property has always lived.
#
# ── THE BROKER INFRASTRUCTURE, DELETED ─────────────────────────────────
#
# Federation, replication with leader election, failover policy and
# status, cross-queue transactions, a schema registry with automatic
# migration, a routing-rule engine (with `xpath`/`jsonPath`/`regex`
# match syntaxes), message traceability and trace-context injection.
#
# A single-device OS — this protocol's core audience — must stub twelve
# methods naming a cluster it does not have. Election timeouts, replica
# lag and failover states are one algorithm's steps; a different 2046
# algorithm could not express its own. Deleted with them: the
# `QueueTransaction`/`QueueOperation`/`TransactionStatus`,
# `RoutingRule`/`RoutingMatch`/`HeaderMatch`/`ContentMatch`/`TopicMatch`/
# `StringOperator`, `MessageSchema`/`SchemaCompatibility`/
# `SchemaMigrationStrategy`/`SchemaMigrationMode`, `QueueFederation`/
# `FederationDirection`, `QueueReplica`/`ReplicaRole`, `FailoverPolicy`/
# `FailoverAction`/`FailoverStatus`/`FailoverState`, `MessageTrace`/
# `CorrelationBaggageEntry`, `QueuePartition` and `QueueNamespace`
# families.
#
# `QueueNamespace.accessPolicy :Text` went for a second reason: an access
# policy as free text is the authority-by-string pattern capability.capnp
# replaces.
#
# ── THE OTHER FIXES ────────────────────────────────────────────────────
#
#   * `ReplayOffset` had three competing position identifiers and no
#     precedence. It now has ONE authoritative position (`sequence`) plus
#     optional hints the backend may ignore.
#   * No maximum message size was declared anywhere, so a producer
#     learned its limit by failing. `QueueInfo.maxMessageBytes` is it.
#   * `dequeue`'s zero-timeout semantics were undocumented. Stated below.
#   * `enqueueAll` was an unbounded bulk enqueue. It is now bounded by the
#     queue's `FlowControl.maxInflight`.
#   * `commitTransaction` took a raw UInt64 for an id the interface had
#     just returned as a reference — the two-authority-paths defect. With
#     transactions gone, the pattern is gone with them; every remaining
#     method takes the reference or the typed id, never both.
#   * `QueueMessage.mimeType :Text` → `T.MimeType`;
#     `QueueEncryption.keyId :Text` → `T.KeyId`.
#   * `QueueStats` renamed `QueueStatistics` (the name collided with
#     notification.capnp's unrelated `QueueStats`).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface Queue {
    # Enqueue one message.
    enqueue @0 (queueId :T.QueueId, message :QueueMessage) -> (id :T.QueueMessageId);

    # Dequeue one message.
    #
    # ZERO-TIMEOUT SEMANTICS (declared, so no consumer has to guess):
    # timeout zero returns immediately. If a message is available it is
    # returned; if not, the call succeeds with an empty message (id zero)
    # rather than blocking. Any non-zero timeout blocks until a message
    # arrives or the timeout elapses; on elapse the same empty message is
    # returned.
    dequeue @1 (queueId :T.QueueId, timeout :T.Duration) -> (message :QueueMessage);

    # Bounded peek: examine without dequeuing.
    peek @2 (queueId :T.QueueId, pagination :T.Pagination) -> (messages :List(QueueMessage), total :UInt32);

    getQueue @3 (queueId :T.QueueId) -> (info :QueueInfo);
    # Remove all pending messages but keep the queue and its statistics.
    clearQueue @4 (queueId :T.QueueId) -> T.VoidResult;
    # Remove the queue itself.
    deleteQueue @5 (queueId :T.QueueId) -> T.VoidResult;
    listQueues @6 (pagination :T.Pagination) -> (queues :List(QueueInfo), total :UInt32);

    # Live stream. Holding the subscription IS the authority to pull.
    subscribeQueue @7 (queueId :T.QueueId) -> (subscription :QueueSubscription);
    subscribeWithFilter @8 (queueId :T.QueueId, filter :MessageFilter) -> (subscription :QueueSubscription);

    getStatistics @9 (queueId :T.QueueId) -> (stats :QueueStatistics);

    # Batch enqueue: at most `FlowControl.maxInflight` messages. A caller
    # that submits more has the excess rejected with limitExceeded rather
    # than silently truncated.
    enqueueAll @10 (queueId :T.QueueId, messages :List(QueueMessage)) -> (ids :List(T.QueueMessageId));

    # -- Acknowledgment-based delivery --
    # Dequeue with an acknowledgment handle. The consumer MUST call ack
    # or nack within the handle's window, or the message is redelivered.
    dequeueAck @11 (queueId :T.QueueId, timeout :T.Duration) -> (message :QueueMessage, ackHandle :AckHandle);

    # Acknowledge successful processing — message is removed from queue.
    ack @12 (handle :AckHandle) -> T.VoidResult;
    # Negative acknowledge — message is requeued for redelivery.
    nack @13 (handle :AckHandle) -> T.VoidResult;

    # -- Replay --
    # Replay from a position. `offset.sequence` is the authoritative
    # position; the hints are advisory.
    replay @14 (queueId :T.QueueId, offset :ReplayOffset, pagination :T.Pagination)
             -> (messages :List(QueueMessage), total :UInt32);

    # -- Queue configuration --
    setDeliveryMode @15 (queueId :T.QueueId, mode :DeliveryMode) -> T.VoidResult;
    setDeadLetterPolicy @16 (queueId :T.QueueId, policy :DeadLetterPolicy) -> T.VoidResult;
    setOrdering @17 (queueId :T.QueueId, ordering :QueueOrdering) -> T.VoidResult;
    setEncryption @18 (queueId :T.QueueId, encryption :QueueEncryption) -> T.VoidResult;
    setMessageTtl @19 (queueId :T.QueueId, ttl :MessageTTL) -> T.VoidResult;
    setFlowControl @20 (queueId :T.QueueId, control :FlowControl) -> T.VoidResult;

    # -- Dead letter queue --
    # Messages in the dead letter queue for a given queue.
    listDeadLetters @21 (queueId :T.QueueId, pagination :T.Pagination)
                   -> (messages :List(QueueMessage), total :UInt32);
    # Retry a dead-lettered message — requeue it to the original queue.
    retryDeadLetter @22 (queueId :T.QueueId, messageId :T.QueueMessageId) -> T.VoidResult;

    # -- Consumer groups --
    # Multiple consumers share a queue; each message is delivered to
    # exactly one member (the work-queue pattern).
    createConsumerGroup @23 (queueId :T.QueueId, name :Text, strategy :ConsumerStrategy) -> (group :ConsumerGroup);
    deleteConsumerGroup @24 (groupId :T.GroupId) -> T.VoidResult;
    getConsumerGroup @25 (groupId :T.GroupId) -> (group :ConsumerGroup);
    listConsumerGroups @26 (queueId :T.QueueId, pagination :T.Pagination) -> (groups :List(ConsumerGroup), total :UInt32);
    addConsumerToGroup @27 (groupId :T.GroupId, consumerId :T.ProcessId) -> T.VoidResult;
    removeConsumerFromGroup @28 (groupId :T.GroupId, consumerId :T.ProcessId) -> T.VoidResult;
    dequeueFromGroup @29 (groupId :T.GroupId, timeout :T.Duration) -> (message :QueueMessage, ackHandle :AckHandle);

    # -- Idempotence --
    # The honest half of exactly-once: ask whether a producer-chosen key
    # has been seen. The backend keeps the window for
    # `DeduplicationKey.window`.
    deduplicate @30 (queueId :T.QueueId, key :DeduplicationKey) -> (isDuplicate :Bool);
}

interface QueueSubscription {
    # Bounded pull: the caller states how many messages it will take.
    pull @0 (maxMessages :UInt32) -> (messages :List(QueueMessage), total :UInt32);
    cancel @1 () -> T.VoidResult;
}

struct QueueMessage {
    id @0 :T.QueueMessageId;
    # Message payload — use the buffer reference for payloads >1KB.
    data @1 :T.DataHandle;
    # Content type, so a consumer can decode without guessing.
    mimeType @2 :T.MimeType;
    # Priority 0 (lowest) to 255 (highest). Default is 128.
    priority @3 :UInt8;
    createdAt @4 :T.Timestamp;
    headers @5 :T.StringMap;
    # Current lifecycle status of this message.
    status @6 :MessageStatus;
    # Delivery semantics for this message.
    deliveryMode @7 :DeliveryMode;
    # Per-message TTL override (zero = use queue default).
    ttl @8 :T.Duration;
    # Monotonic position in the queue, for replay and gap detection.
    sequence @9 :UInt64;
    # Producer-chosen idempotence key (zero = none).
    dedupeKey @10 :UInt64;
}

struct MessageFilter {
    # Only deliver messages in these statuses (empty = all).
    statuses @0 :List(MessageStatus);
    # Only deliver messages at or above this priority.
    minPriority @1 :UInt8;
    # Only deliver messages created after this time.
    since @2 :T.Timestamp;
    # Only deliver messages at or above this sequence.
    afterSequence @3 :UInt64;
}

struct QueueInfo {
    id @0 :T.QueueId;
    name @1 :Text;
    messageCount @2 :UInt64;
    totalEnqueued @3 :UInt64;
    totalDequeued @4 :UInt64;
    oldestMessage @5 :T.Timestamp;
    created @6 :T.Timestamp;
    # Delivery semantics configured for this queue.
    deliveryMode @7 :DeliveryMode;
    # Dead letter routing policy.
    deadLetterPolicy @8 :DeadLetterPolicy;
    # Message ordering guarantee.
    ordering @9 :QueueOrdering;
    # Encryption status.
    encryption @10 :QueueEncryption;
    # Default message TTL.
    messageTtl @11 :MessageTTL;
    # Flow control configuration — also bounds enqueueAll.
    flowControl @12 :FlowControl;
    # The largest message this queue accepts, in bytes. A producer can
    # pre-check instead of discovering the limit by failing. Zero means
    # the backend declares none.
    maxMessageBytes @13 :UInt64;
    # Highest sequence ever assigned, for replay positioning.
    latestSequence @14 :UInt64;
}

# Named `QueueStatistics` because notification.capnp has an unrelated
# `QueueStats` with disjoint fields: the same name for two different
# measurements is a codegen collision.
struct QueueStatistics {
    id @0 :T.QueueId;
    name @1 :Text;
    messages @2 :UInt64;
    # Number of active producers (processes that have enqueued recently).
    producers @3 :UInt32;
    # Number of active consumers (processes that have dequeued recently).
    consumers @4 :UInt32;
    enqueuedTotal @5 :UInt64;
    dequeuedTotal @6 :UInt64;
    failedTotal @7 :UInt64;
    # Messages the queue dropped because it was full, since creation. A
    # consumer that reads a sequence gap can tell which side dropped.
    droppedTotal @8 :UInt64;
    metadata @9 :T.StringMap;
}

# ── Delivery semantics ──────────────────────────────────────────────────

enum DeliveryMode {
    unknown @0;
    atMostOnce @1;
    atLeastOnce @2;
    custom @3;
}

# ── Acknowledgment handle ───────────────────────────────────────────────
# Structured ack handle for at-least-once delivery. The consumer must
# call ack() or nack() within the window, or the message is redelivered.
struct AckHandle {
    messageId @0 :T.QueueMessageId;
    queueId @1 :T.QueueId;
    # Position of the message in the queue.
    sequence @2 :UInt64;
    # When this handle expires. After that, ack/nack MAY answer notFound.
    expiresAt @3 :T.Timestamp;
}

# ── Reliability configuration ───────────────────────────────────────────

struct DeadLetterPolicy {
    enabled @0 :Bool;
    maxRetries @1 :UInt32;
    deadLetterQueueId @2 :T.QueueId;
    retryDelay @3 :T.Duration;
    maxAge @4 :T.Duration;
}

struct MessageTTL {
    defaultTtl @0 :T.Duration;
    perMessageTtl @1 :T.Duration;
}

struct QueueEncryption {
    enabled @0 :Bool;
    # Typed key reference (canonical), not free text.
    keyId @1 :T.KeyId;
    # Open algorithm token — a 2046 cipher needs no ordinal.
    algorithm @2 :Text;
}

struct ReplayOffset {
    # The ONE authoritative position: the monotonic sequence of the first
    # message to replay. A backend that cannot honour it answers with an
    # error rather than guessing which of several identifiers the caller
    # meant (the pre-revamp struct carried three and no precedence).
    sequence @0 :UInt64;
    # Optional hint: the message id the caller believes is at that
    # position. Ignored when `sequence` is set.
    messageIdHint @1 :T.QueueMessageId;
    # Optional hint: a timestamp the caller believes is at that position.
    timestampHint @2 :T.Timestamp;
}

enum QueueOrdering {
    unknown @0;
    fifo @1;
    lifo @2;
    priority @3;
    timestamp @4;
    custom @5;
}

struct FlowControl {
    maxInflight @0 :UInt32;
    rateLimitPerProducer @1 :UInt32;
    backpressureThreshold @2 :UInt32;
    # What the queue does when full: drop the newest, drop the oldest, or
    # refuse. Declared, so a producer can reason instead of discovering.
    whenFull @3 :OverflowPolicy;
}

enum OverflowPolicy {
    refuseNewest @0;
    dropOldest @1;
    blockProducer @2;
    custom @3;
}

# ── Message lifecycle ───────────────────────────────────────────────────

enum MessageStatus {
    unknown @0;
    pending @1;
    processing @2;
    completed @3;
    failed @4;
    deadLettered @5;
    custom @6;
}

# ── Consumer groups ─────────────────────────────────────────────────────

struct ConsumerGroup {
    groupId @0 :T.GroupId;
    queueId @1 :T.QueueId;
    name @2 :Text;
    strategy @3 :ConsumerStrategy;
    members @4 :List(T.ProcessId);
    # Position the group last consumed to, for resumption.
    committedSequence @5 :UInt64;
}

enum ConsumerStrategy {
    unknown @0;
    roundRobin @1;
    leastBusy @2;
    priority @3;
    custom @4;
}

# ── Idempotence ─────────────────────────────────────────────────────────

struct DeduplicationKey {
    # Producer-chosen key. Two producers using the same key are treated as
    # one logical producer, so a key must be unique per logical sender.
    key @0 :UInt64;
    # How long the backend remembers this key (zero = queue lifetime).
    window @1 :T.Duration;
    # What to do when the key is seen again.
    onDuplicate @2 :DuplicateAction;
}

enum DuplicateAction {
    unknown @0;
    reject @1;
    returnExisting @2;
    custom @3;
}

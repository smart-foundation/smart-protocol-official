@0xa1b2c3d4e5f60030;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Queue - message queue lifecycle, enqueue/dequeue, subscriptions.
#
# Improvements beyond the original schema:
#   - QueueId typed ID replaces bare Text for queue names.
#   - QueueMessageId typed ID replaces bare Text for message IDs.
#   - T.Duration for dequeue timeout (was raw UInt64 milliseconds).
#   - DataHandle for message data that may exceed 1KB.
#   - Subscription cancel method added.
#   - Pagination on listQueues, peek, and QueueSubscription.pull (audit-3).
#
# Audit-8 enhancements:
#   - DeliveryMode: atMostOnce, atLeastOnce, exactlyOnce semantics.
#   - AckHandle: structured acknowledgment for reliable delivery.
#   - DeadLetterPolicy: dead letter routing for failed messages.
#   - MessageTTL: time-to-live for automatic message expiry.
#   - QueueEncryption: encryption declaration for queue contents.
#   - ReplayOffset: replay messages from a specific position.
#   - QueueOrdering: explicit ordering guarantees.
#   - FlowControl: backpressure and rate limiting.
#   - QueueNamespace: multi-tenant queue isolation.
#   - MessageStatus: typed message lifecycle states.
# ═══════════════════════════════════════════════════════════════════════

interface Queue {
    enqueue @0 (queueId :T.QueueId, message :QueueMessage) -> (id :T.QueueMessageId);
    dequeue @1 (queueId :T.QueueId, timeout :T.Duration) -> (message :QueueMessage);
    peek @2 (queueId :T.QueueId, pagination :T.Pagination) -> (messages :List(QueueMessage), total :UInt32);

    getQueue @3 (queueId :T.QueueId) -> (info :QueueInfo);
    clearQueue @4 (queueId :T.QueueId) -> T.VoidResult;

    deleteQueue @5 (queueId :T.QueueId) -> T.VoidResult;
    listQueues @6 (pagination :T.Pagination) -> (queues :List(QueueInfo), total :UInt32);

    subscribeQueue @7 (queueId :T.QueueId) -> (subscription :QueueSubscription);

    getStats @8 (queueId :T.QueueId) -> (stats :QueueStats);

    # Batch enqueue: submit multiple messages atomically.
    # If any message fails, the entire batch is rejected (atomic semantics).
    enqueueAll @9 (queueId :T.QueueId, messages :List(QueueMessage))
               -> (ids :List(T.QueueMessageId));

    # -- Audit-8: Acknowledgment-based delivery --
    # Dequeue with acknowledgment handle. Consumer must ack/nack within timeout.
    dequeueAck @10 (queueId :T.QueueId, timeout :T.Duration)
               -> (message :QueueMessage, ackHandle :AckHandle);

    # Acknowledge successful processing — message is removed from queue.
    ack @11 (handle :AckHandle) -> T.VoidResult;

    # Negative acknowledge — message is requeued for redelivery.
    nack @12 (handle :AckHandle) -> T.VoidResult;

    # -- Audit-8: Replay --
    # Replay messages from a specific offset (timestamp or message ID).
    replay @13 (queueId :T.QueueId, offset :ReplayOffset, pagination :T.Pagination)
           -> (messages :List(QueueMessage), total :UInt32);

    # -- Audit-8: Queue configuration --
    setDeliveryMode @14 (queueId :T.QueueId, mode :DeliveryMode) -> T.VoidResult;
    setDeadLetterPolicy @15 (queueId :T.QueueId, policy :DeadLetterPolicy) -> T.VoidResult;
    setOrdering @16 (queueId :T.QueueId, ordering :QueueOrdering) -> T.VoidResult;
    setEncryption @17 (queueId :T.QueueId, encryption :QueueEncryption) -> T.VoidResult;
    setMessageTtl @18 (queueId :T.QueueId, ttl :MessageTTL) -> T.VoidResult;
    setFlowControl @19 (queueId :T.QueueId, control :FlowControl) -> T.VoidResult;

    # -- Audit-8: Dead letter queue --
    # List messages in the dead letter queue for a given queue.
    listDeadLetters @20 (queueId :T.QueueId, pagination :T.Pagination)
                    -> (messages :List(QueueMessage), total :UInt32);

    # Retry a dead-lettered message — requeue it to the original queue.
    retryDeadLetter @21 (queueId :T.QueueId, messageId :T.QueueMessageId) -> T.VoidResult;

    # Audit-9: consumer group management.
    createConsumerGroup @22 (queueId :T.QueueId, name :Text, strategy :ConsumerStrategy) -> (group :ConsumerGroup);
    deleteConsumerGroup @23 (groupId :UInt64) -> T.VoidResult;
    getConsumerGroup @24 (groupId :UInt64) -> (group :ConsumerGroup);
    listConsumerGroups @25 (queueId :T.QueueId, pagination :T.Pagination) -> (groups :List(ConsumerGroup), total :UInt32);
    addConsumerToGroup @26 (groupId :UInt64, consumerId :T.ProcessId) -> T.VoidResult;
    removeConsumerFromGroup @27 (groupId :UInt64, consumerId :T.ProcessId) -> T.VoidResult;
    dequeueFromGroup @28 (groupId :UInt64, timeout :T.Duration) -> (message :QueueMessage, ackHandle :AckHandle);

    # Audit-9: message deduplication.
    deduplicate @29 (queueId :T.QueueId, key :DeduplicationKey) -> (isDuplicate :Bool);

    # Audit-9: queue partitioning.
    createPartition @30 (queueId :T.QueueId, partitionId :UInt32) -> (partition :QueuePartition);
    getPartition @31 (queueId :T.QueueId, partitionId :UInt32) -> (partition :QueuePartition);
    listPartitions @32 (queueId :T.QueueId, pagination :T.Pagination) -> (partitions :List(QueuePartition), total :UInt32);
    deletePartition @33 (queueId :T.QueueId, partitionId :UInt32) -> T.VoidResult;

    # Audit-9: queue federation.
    createFederation @34 (localQueueId :T.QueueId, remoteEndpoint :Text, direction :FederationDirection) -> (federation :QueueFederation);
    deleteFederation @35 (federationId :UInt64) -> T.VoidResult;
    listFederations @36 (pagination :T.Pagination) -> (federations :List(QueueFederation), total :UInt64);

    # Audit-9: queue mirroring/replication.
    createReplica @37 (queueId :T.QueueId, nodeId :Text) -> (replica :QueueReplica);
    removeReplica @38 (replicaId :UInt64) -> T.VoidResult;
    listReplicas @39 (queueId :T.QueueId, pagination :T.Pagination) -> (replicas :List(QueueReplica), total :UInt64);
    promoteReplica @40 (replicaId :UInt64) -> T.VoidResult;

    # Audit-9: message schema evolution.
    registerSchema @41 (schema :MessageSchema) -> (schemaId :Text);
    getSchema @42 (schemaId :Text) -> (schema :MessageSchema);
    listSchemas @43 (pagination :T.Pagination) -> (schemas :List(MessageSchema), total :UInt64);

    # Audit-9: message filtering.
    subscribeWithFilter @44 (queueId :T.QueueId, filter :MessageFilter) -> (subscription :QueueSubscription);

    # Audit-9: transaction support.
    beginTransaction @45 () -> (transaction :QueueTransaction);
    commitTransaction @46 (transactionId :UInt64) -> T.VoidResult;
    abortTransaction @47 (transactionId :UInt64) -> T.VoidResult;

    # Audit-9: message routing.
    createRoutingRule @48 (rule :RoutingRule) -> (ruleId :UInt64);
    deleteRoutingRule @49 (ruleId :UInt64) -> T.VoidResult;
    listRoutingRules @50 (pagination :T.Pagination) -> (rules :List(RoutingRule), total :UInt64);

    # Audit-9: message traceability.
    traceMessage @51 (messageId :T.QueueMessageId) -> (trace :MessageTrace);
    injectTraceContext @52 (message :QueueMessage, trace :MessageTrace) -> (tracedMessage :QueueMessage);

    # Audit-10: HA failover configuration for replicas.
    setFailoverPolicy @53 (queueId :T.QueueId, policy :FailoverPolicy) -> T.VoidResult;
    getFailoverPolicy @54 (queueId :T.QueueId) -> (policy :FailoverPolicy);
    triggerFailover @55 (queueId :T.QueueId) -> T.VoidResult;
    getFailoverStatus @56 (queueId :T.QueueId) -> (status :FailoverStatus);

    # Audit-10: automatic schema migration for consumers/producers.
    setSchemaMigration @57 (queueId :T.QueueId, strategy :SchemaMigrationStrategy) -> T.VoidResult;
    getSchemaMigration @58 (queueId :T.QueueId) -> (strategy :SchemaMigrationStrategy);
    migrateMessages @59 (queueId :T.QueueId, fromVersion :UInt32, toVersion :UInt32) -> (migratedCount :UInt64);
}

interface QueueSubscription {
    pull @0 (pagination :T.Pagination) -> (messages :List(QueueMessage), total :UInt32);
    cancel @1 () -> T.VoidResult;
}

struct QueueMessage {
    id @0 :T.QueueMessageId;
    # Message payload — use buffer handle for payloads >1KB.
    data @1 :T.DataHandle;
    mimeType @2 :Text;
    # Priority 0 (lowest) to 255 (highest). Default is 128.
    priority @3 :UInt8;
    createdAt @4 :T.Timestamp;
    headers @5 :T.StringMap;
    # Audit-8: current lifecycle status of this message.
    status @6 :MessageStatus;
    # Audit-8: delivery semantics for this message.
    deliveryMode @7 :DeliveryMode;
    # Audit-8: per-message TTL override (null = use queue default).
    ttl @8 :T.Duration;
}

struct QueueInfo {
    id @0 :T.QueueId;
    name @1 :Text;
    messageCount @2 :UInt64;
    totalEnqueued @3 :UInt64;
    totalDequeued @4 :UInt64;
    oldestMessage @5 :T.Timestamp;
    created @6 :T.Timestamp;
    # Audit-8: delivery semantics configured for this queue.
    deliveryMode @7 :DeliveryMode;
    # Audit-8: dead letter routing policy.
    deadLetterPolicy @8 :DeadLetterPolicy;
    # Audit-8: message ordering guarantee.
    ordering @9 :QueueOrdering;
    # Audit-8: encryption status.
    encryption @10 :QueueEncryption;
    # Audit-8: namespace for multi-tenant isolation.
    namespace @11 :QueueNamespace;
    # Audit-8: default message TTL.
    messageTtl @12 :MessageTTL;
    # Audit-8: flow control configuration.
    flowControl @13 :FlowControl;
}

struct QueueStats {
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
}

# ── Audit-8: Delivery Semantics ───────────────────────────────────────
# Typed delivery guarantee replacing implicit destructive dequeue.
enum DeliveryMode {
    atMostOnce @0;
    atLeastOnce @1;
    exactlyOnce @2;
    custom @3;
}

# ── Audit-8: Acknowledgment Handle ────────────────────────────────────
# Structured ack handle for at-least-once delivery. Consumer must call
# ack() or nack() within the timeout window, or the message is redelivered.
struct AckHandle {
    messageId @0 :T.QueueMessageId;
    queueId @1 :T.QueueId;
    expiresAt @2 :T.Timestamp;
}

# ── Audit-8: Dead Letter Policy ───────────────────────────────────────
# Configures dead letter routing for messages that fail processing.
struct DeadLetterPolicy {
    enabled @0 :Bool;
    maxRetries @1 :UInt32;
    deadLetterQueueId @2 :T.QueueId;
    retryDelay @3 :T.Duration;
    maxAge @4 :T.Duration;
}

# ── Audit-8: Message TTL ──────────────────────────────────────────────
# Message time-to-live configuration. Messages expire after their TTL
# and are removed from the queue automatically.
struct MessageTTL {
    defaultTtl @0 :T.Duration;
    perMessageTtl @1 :T.Duration;
}

# ── Audit-8: Queue Encryption ─────────────────────────────────────────
# Encryption declaration for queue contents. Backend handles actual
# encryption; this struct declares configuration for key management.
struct QueueEncryption {
    enabled @0 :Bool;
    keyId @1 :Text;
    algorithm @2 :Text;
}

# ── Audit-8: Replay Offset ────────────────────────────────────────────
# Identifies a position in the queue for replay operations.
struct ReplayOffset {
    messageId @0 :T.QueueMessageId;
    timestamp @1 :T.Timestamp;
    offset @2 :UInt64;
}

# ── Audit-8: Queue Ordering ───────────────────────────────────────────
# Explicit ordering guarantee for message delivery.
enum QueueOrdering {
    fifo @0;
    lifo @1;
    priority @2;
    timestamp @3;
    custom @4;
}

# ── Audit-8: Flow Control ─────────────────────────────────────────────
# Backpressure and rate limiting for producers and consumers.
struct FlowControl {
    maxInflight @0 :UInt32;
    rateLimitPerProducer @1 :UInt32;
    backpressureThreshold @2 :UInt32;
}

# ── Audit-8: Queue Namespace ──────────────────────────────────────────
# Multi-tenant queue isolation. Different teams, apps, or environments
# share a queue infrastructure with namespace-level isolation.
struct QueueNamespace {
    namespaceId @0 :Text;
    description @1 :Text;
    accessPolicy @2 :Text;
}

# ── Audit-8: Message Status ───────────────────────────────────────────
# Typed message lifecycle beyond simple dequeue.
enum MessageStatus {
    pending @0;
    processing @1;
    completed @2;
    failed @3;
    deadLettered @4;
    custom @5;
}

# ── Audit-9: Consumer Groups ───────────────────────────────────────────
# Multiple consumers share a queue, each message delivered to exactly
# one consumer (work queue pattern like RabbitMQ, Kafka consumer groups).
struct ConsumerGroup {
    groupId @0 :UInt64;
    queueId @1 :T.QueueId;
    name @2 :Text;
    consumers @3 :List(T.ProcessId);
    strategy @4 :ConsumerStrategy;
    maxPoll @5 :UInt32;
}

enum ConsumerStrategy {
    roundRobin @0;
    sticky @1;
    fair @2;
    custom @3;
}

# ── Audit-9: Message Deduplication ─────────────────────────────────────
# Idempotent processing via deduplication keys stored for a TTL.
struct DeduplicationKey {
    key @0 :Text;
    ttl @1 :T.Duration;
}

# ── Audit-9: Queue Partitioning ─────────────────────────────────────────
struct QueuePartition {
    partitionId @0 :UInt32;
    queueId @1 :T.QueueId;
    messageCount @2 :UInt64;
    totalEnqueued @3 :UInt64;
}

# ── Audit-9: Queue Federation ───────────────────────────────────────────
struct QueueFederation {
    federationId @0 :UInt64;
    localQueueId @1 :T.QueueId;
    remoteEndpoint @2 :Text;
    direction @3 :FederationDirection;
}

enum FederationDirection {
    localToRemote @0;
    remoteToLocal @1;
    bidirectional @2;
    custom @3;
}

# ── Audit-9: Queue Mirroring/Replication ────────────────────────────────
# High-availability message replication across nodes.
struct QueueReplica {
    replicaId @0 :UInt64;
    queueId @1 :T.QueueId;
    nodeId @2 :Text;
    role @3 :ReplicaRole;
    lag @4 :T.Duration;
}

enum ReplicaRole {
    primary @0;
    sync @1;
    async @2;
    witness @3;
    custom @4;
}

# ── Audit-9: Message Schema Evolution ───────────────────────────────────
# Schema registry integration for producer/consumer evolution.
struct MessageSchema {
    schemaId @0 :Text;
    version @1 :UInt32;
    definition @2 :Data;
    compatibility @3 :SchemaCompatibility;
}

enum SchemaCompatibility {
    backward @0;
    forward @1;
    full @2;
    none @3;
    custom @4;
}

# ── Audit-9: Message Filtering ────────────────────────────────────────────
# Consumers filter messages by header, content, or pattern.
struct MessageFilter {
    expression @0 :Text;
    filterType @1 :MessageFilterType;
}

enum MessageFilterType {
    header @0;
    content @1;
    xpath @2;
    jsonPath @3;
    regex @4;
    custom @5;
}

# ── Audit-9: Transaction Support ─────────────────────────────────────────
# Atomic multi-queue operations.
struct QueueTransaction {
    transactionId @0 :UInt64;
    operations @1 :List(QueueOperation);
    status @2 :TransactionStatus;
}

struct QueueOperation {
    opType @0 :QueueOperationType;
    queueId @1 :T.QueueId;
    message @2 :QueueMessage;
}

enum QueueOperationType {
    enqueue @0;
    dequeue @1;
    ack @2;
    nack @3;
    custom @4;
}

enum TransactionStatus {
    open @0;
    committed @1;
    aborted @2;
    custom @3;
}

# ── Audit-9: Message Routing ─────────────────────────────────────────────
# Content-based, header-based, and topic-based routing.
struct RoutingRule {
    ruleId @0 :UInt64;
    name @1 :Text;
    match @2 :RoutingMatch;
    destination @3 :T.QueueId;
    priority @4 :UInt8;
}

struct RoutingMatch {
    union {
        header @0 :HeaderMatch;
        content @1 :ContentMatch;
        topic @2 :TopicMatch;
        custom @3 :Data;
    }
}

struct HeaderMatch {
    key @0 :Text;
    operator @1 :StringOperator;
    value @2 :Text;
}

struct ContentMatch {
    field @0 :Text;
    operator @1 :StringOperator;
    value @2 :Text;
}

struct TopicMatch {
    topic @0 :Text;
    pattern @1 :Bool;
}

enum StringOperator {
    equals @0;
    contains @1;
    startsWith @2;
    endsWith @3;
    regex @4;
    custom @5;
}

# ── Audit-9: Message Traceability ────────────────────────────────────────
# End-to-end tracing with correlation IDs and span IDs.
struct MessageTrace {
    traceId @0 :Text;
    spanId @1 :Text;
    parentSpanId @2 :Text;
    correlationId @3 :Text;
    baggage @4 :List(CorrelationBaggageEntry);
}

struct CorrelationBaggageEntry {
    key @0 :Text;
    value @1 :Text;
}

# ── Audit-10: HA Failover ─────────────────────────────────────────────────
# Automatic failover between replicas for high availability.
struct FailoverPolicy {
    enabled @0 :Bool;
    # Timeout before promoting a new primary.
    electionTimeout @1 :T.Duration;
    # Maximum acceptable replica lag before demotion.
    maxAcceptableLag @2 :T.Duration;
    # What to do when failover occurs.
    onFailover @3 :FailoverAction;
    # Whether to automatically attempt failover.
    automatic @4 :Bool;
}

enum FailoverAction {
    notify @0;           # Notify but do not act
    promote @1;           # Promote best replica to primary
    switchover @2;        # Switch to a specific replica
    shutdown @3;          # Shut down queue on failure
}

struct FailoverStatus {
    state @0 :FailoverState;
    lastFailoverAt @1 :T.Timestamp;
    failoverCount @2 :UInt64;
    currentPrimary @3 :UInt64;
    candidates @4 :List(UInt64);
}

enum FailoverState {
    normal @0;            # No failover in progress
    detecting @1;         # Detecting primary failure
    electing @2;          # Electing new primary
    promoting @3;         # Promoting new primary
    reconfiguring @4;     # Reconfiguring followers
    completed @5;         # Failover completed successfully
    failed @6;            # Failover failed
}

# ── Audit-10: Schema Migration ───────────────────────────────────────────
# Automatic message schema migration when consumers/producers differ.
struct SchemaMigrationStrategy {
    enabled @0 :Bool;
    # Migration mode.
    mode @1 :SchemaMigrationMode;
    # Timeout for each migration.
    timeout @2 :T.Duration;
    # Whether to fail on incompatible schema.
    failOnIncompatible @3 :Bool;
    # Batch size for migration.
    batchSize @4 :UInt32;
}

enum SchemaMigrationMode {
    none @0;              # No automatic migration
    additive @1;          # Add new fields with defaults
    backward @2;          # Strip unknown fields, preserve compatibility
    full @3;              # Full bidirectional transformation
}

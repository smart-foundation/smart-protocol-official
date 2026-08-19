@0xa1b2c3d4e5f6002d;

# ═══════════════════════════════════════════════════════════════════════
# Database — key-value storage with namespacing, batching, and change feeds.
#
# Zero-backend-assumption IPC contract. No SQL, no document store, no
# specific database engine assumed. The backend decides storage strategy.
#
# Improvements (audit):
#   - ChangesSubscription has cancel() for explicit teardown.
#   - ChangeType has custom variant for forward compatibility.
#   - listKeys returns paginated results (T.Pagination in filter).
#   - listNamespaces returns paginated results.
#   - exportNamespace/importNamespace use T.DataHandle for large payloads.
#   - NamespaceInfo.size documented as bytes.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface Database {
    get @0 (namespace :Text, key :Text) -> (value :Data);
    has @1 (namespace :Text, key :Text) -> (exists :Bool);
    # Paginated key listing — replaces unbounded List return.
    listKeys @2 (namespace :Text, prefix :Text, page :T.Pagination) -> (keys :List(Text), total :UInt64);
    count @3 (namespace :Text) -> (count :UInt64);

    set @4 (namespace :Text, key :Text, value :Data) -> T.VoidResult;
    delete @5 (namespace :Text, key :Text) -> T.VoidResult;
    clear @6 (namespace :Text) -> T.VoidResult;

    setBatch @7 (namespace :Text, entries :List(KeyValue)) -> T.VoidResult;
    getBatch @8 (namespace :Text, keys :List(Text)) -> (entries :List(KeyValue));
    deleteBatch @9 (namespace :Text, keys :List(Text)) -> T.VoidResult;

    # Paginated namespace listing.
    listNamespaces @10 (page :T.Pagination) -> (namespaces :List(NamespaceInfo), total :UInt64);
    deleteNamespace @11 (namespace :Text) -> T.VoidResult;

    exportNamespace @12 (namespace :Text) -> (data :T.DataHandle);
    importNamespace @13 (namespace :Text, data :T.DataHandle) -> T.VoidResult;

    subscribeChanges @14 (namespace :Text) -> (subscription :ChangesSubscription);
    pullChanges @15 (subscription :ChangesSubscription) -> (changes :List(KeyChange));

    # ─── Typed Values ──────────────────────────────────────────

    # Get with typed value access.
    getTyped @16 (namespace :Text, key :Text) -> (entry :KeyEntry);

    # Set with typed value.
    setTyped @17 (namespace :Text, key :Text, value :DatabaseValue) -> T.VoidResult;

    # ─── TTL (Time-to-Live) ────────────────────────────────────

    # Set key with per-key TTL (auto-expiry).
    setWithTtl @18 (namespace :Text, key :Text, value :Data, ttl :T.Duration) -> T.VoidResult;

    # Query remaining TTL for a key.
    getTtl @19 (namespace :Text, key :Text) -> (remaining :T.Duration, exists :Bool);

    # Batch set with per-key TTL.
    setBatchWithTtl @20 (namespace :Text, entries :List(KeyEntry)) -> T.VoidResult;

    # ─── Key Metadata ──────────────────────────────────────────

    # Retrieve key metadata without fetching value.
    getMetadata @21 (namespace :Text, key :Text) -> (metadata :KeyMetadata);

    # Retrieve metadata for multiple keys in one call.
    getBatchMetadata @22 (namespace :Text, keys :List(Text)) -> (metadata :List(KeyMetadata));

    # ─── Transactions ──────────────────────────────────────────

    # Start a multi-key transaction.
    beginTransaction @23 (namespace :Text, operations :List(TransactionOperation)) -> (transaction :Transaction);

    # Commit a transaction atomically.
    commitTransaction @24 (transactionId :UInt64) -> T.VoidResult;

    # Rollback a transaction.
    rollbackTransaction @25 (transactionId :UInt64) -> T.VoidResult;

    # Query transaction state.
    getTransactionStatus @26 (transactionId :UInt64) -> (status :TransactionStatus);

    # ─── Time-Series ───────────────────────────────────────────

    # Query keys modified within a time range.
    listKeysByTimeRange @27 (namespace :Text, timeRange :DatabaseTimeRange, page :T.Pagination) -> (keys :List(Text), total :UInt64);

    # Aggregate values over time (count, sum, avg per time bucket).
    getTimeSeries @28 (namespace :Text, key :Text, timeRange :DatabaseTimeRange, bucketSize :T.Duration) -> (buckets :List(TimeSeriesBucket));

    # ─── Schema Management ─────────────────────────────────────

    # Apply schema migration.
    applySchema @29 (schema :DatabaseSchema) -> T.VoidResult;

    # Retrieve current schema.
    getSchema @30 () -> (schema :DatabaseSchema);

    # ─── Namespace Info ────────────────────────────────────────

    # Get detailed info for a namespace by ID.
    getNamespace @31 (namespace :Text) -> (info :NamespaceInfo);

    # ─── Watch Key ─────────────────────────────────────────────

    # Subscribe to changes on a specific key.
    watchKey @32 (namespace :Text, key :Text) -> (subscription :KeySubscription);

    # ─── Compaction ────────────────────────────────────────────

    # Trigger compaction/garbage collection for a namespace.
    compactNamespace @33 (namespace :Text) -> T.VoidResult;

    # ─── Namespace Statistics ──────────────────────────────────

    # Detailed namespace statistics.
    getNamespaceStats @34 (namespace :Text) -> (stats :NamespaceStats);

    # ─── Backup / Restore ──────────────────────────────────────

    # Create a point-in-time backup of a namespace.
    backupNamespace @35 (namespace :Text) -> (backupId :Text, data :T.DataHandle);

    # Restore from a point-in-time backup.
    restoreNamespace @36 (namespace :Text, backupId :Text) -> T.VoidResult;

    # ─── Key History ───────────────────────────────────────────

    # Retrieve change history for a specific key.
    getKeyHistory @37 (namespace :Text, key :Text, page :T.Pagination) -> (history :List(ChangeCaptureEvent), total :UInt64);

    # ─── Encryption ────────────────────────────────────────────

    # Encrypt a key's value with specified key.
    encryptKey @38 (namespace :Text, key :Text, keyId :T.KeyId) -> T.VoidResult;

    # Decrypt a key's value (if authorized).
    decryptKey @39 (namespace :Text, key :Text) -> T.VoidResult;

    # ─── Change Data Capture (CDC) ─────────────────────────────

    # Subscribe to a CDC stream with exactly-once delivery guarantees.
    subscribeChangeStream @40 (options :ChangeStreamOptions) -> (subscription :ChangeStreamSubscription);

    # ─── Database Encryption at Rest ──────────────────────────

    # Enable encryption for an entire namespace.
    encryptNamespace @41 (namespace :Text, keyId :T.KeyId) -> T.VoidResult;

    # Get encryption status for a namespace.
    getNamespaceEncryptionStatus @42 (namespace :Text) -> (status :NamespaceEncryptionStatus);

    # ─── Database Audit Logging ─────────────────────────────────

    # Subscribe to audit log for compliance.
    subscribeAuditLog @43 (filter :AuditLogFilter) -> (subscription :AuditLogSubscription);

    # ─── Database Resource Monitoring ──────────────────────────

    # Get resource usage metrics for a namespace.
    getResourceMonitor @44 (namespace :Text) -> (metrics :ResourceMetrics);

    # ─── Connection Pooling ─────────────────────────────────────

    # Get connection pool status.
    getConnectionPoolStatus @45 () -> (status :ConnectionPoolStatus);

    # Configure connection pool.
    configureConnectionPool @46 (config :ConnectionPoolConfig) -> T.VoidResult;

    # ─── SQL-like Query ────────────────────────────────────────

    # Execute a structured query (backend-specific SQL-like syntax).
    query @47 (request :QueryRequest) -> (result :QueryResult);

    # ─── Database Indexing ─────────────────────────────────────

    # Create a custom index on a namespace.
    createIndex @48 (namespace :Text, index :IndexDefinition) -> T.VoidResult;

    # List indexes for a namespace.
    listIndexes @49 (namespace :Text) -> (indexes :List(IndexDefinition));

    # ─── Graph Data Model ─────────────────────────────────────

    # Add an edge to the graph.
    addGraphEdge @50 (namespace :Text, edge :GraphEdge) -> T.VoidResult;

    # Find shortest path between two keys.
    shortestPath @51 (namespace :Text, request :GraphQueryRequest) -> (path :GraphPath);

    # Detect communities in the graph.
    detectCommunities @52 (namespace :Text) -> (communities :List(Community));

    # Get neighbors of a key.
    getNeighbors @53 (namespace :Text, key :Text, edgeType :Text) -> (neighbors :List(GraphEdge));

    # ─── Vector Database ─────────────────────────────────────

    # Insert a vector embedding.
    insertVector @54 (namespace :Text, entry :VectorEntry) -> T.VoidResult;

    # Search by vector similarity.
    searchVector @55 (namespace :Text, request :VectorSearchRequest) -> (results :List(VectorSearchResult));

    # Delete a vector entry.
    deleteVector @56 (namespace :Text, key :Text) -> T.VoidResult;

    # ─── CRDT Data Types ─────────────────────────────────────

    # Set a CRDT value.
    setCrdt @57 (namespace :Text, value :CrdtValue) -> T.VoidResult;

    # Get a CRDT value.
    getCrdt @58 (namespace :Text, key :Text) -> (value :CrdtValue);

    # Merge two CRDT values (conflict resolution).
    mergeCrdt @59 (namespace :Text, key :Text, remoteValue :CrdtValue) -> (merged :CrdtValue);

    # ─── Multi-Node Replication ──────────────────────────────

    # Start replication to a remote node.
    startReplication @60 (config :DatabaseReplicationConfig) -> (replicationId :Text);

    # Get replication status.
    getReplicationStatus @61 (replicationId :Text) -> (status :ReplicationStatus);

    # Stop replication.
    stopReplication @62 (replicationId :Text) -> T.VoidResult;

    # ─── Event Sourcing ──────────────────────────────────────

    # Append an event to the event log.
    appendEvent @63 (namespace :Text, entry :EventLogEntry) -> (eventId :UInt64);

    # Replay events from a given event ID.
    replayEvents @64 (namespace :Text, fromEventId :UInt64, page :T.Pagination) -> (events :List(EventLogEntry), total :UInt64);

    # ─── Snapshot Isolation ──────────────────────────────────

    # Create a point-in-time snapshot for consistent reads.
    createSnapshot @65 (namespace :Text) -> (snapshot :DatabaseSnapshot);

    # Read from a snapshot (consistent point-in-time read).
    readFromSnapshot @66 (snapshotId :Text, key :Text) -> (value :Data, exists :Bool);

    # Delete a snapshot.
    deleteSnapshot @67 (snapshotId :Text) -> T.VoidResult;

    # ─── Sharding ────────────────────────────────────────────

    # Configure sharding for a namespace.
    configureSharding @68 (config :ShardConfig) -> T.VoidResult;

    # Get shard info for a namespace.
    getShardInfo @69 (namespace :Text) -> (shards :List(ShardInfo));
}

interface ChangesSubscription {
    pull @0 () -> (changes :List(KeyChange));
    # Explicit cancellation — stops the change stream and releases resources.
    cancel @1 () -> T.VoidResult;
}

struct KeyValue {
    key @0 :Text;
    value @1 :Data;
    timestamp @2 :T.Timestamp;
}

struct NamespaceInfo {
    name @0 :Text;
    count @1 :UInt64;
    # Total size in bytes of all values in this namespace.
    size @2 :UInt64;
    created @3 :T.Timestamp;
}

struct KeyChange {
    type @0 :ChangeType;
    key @1 :Text;
    namespace @2 :Text;
    timestamp @3 :T.Timestamp;
}

enum ChangeType {
    set @0;
    delete @1;
    clear @2;
    custom @3;
}

# ─── Typed Values ─────────────────────────────────────────────

struct DatabaseValue {
    union {
        text @0 :Text;
        integer @1 :Int64;
        real @2 :Float64;
        boolean @3 :Bool;
        bytes @4 :Data;
        null @5 :Void;
        # Backend-specific typed value.
        custom @6 :Data;
    }
}

# ─── Key Entry (enriched with TTL and version) ────────────────

struct KeyEntry {
    key @0 :Text;
    value @1 :DatabaseValue;
    timestamp @2 :T.Timestamp;
    ttl @3 :T.Duration;
    version @4 :UInt64;
}

# ─── Key Metadata ─────────────────────────────────────────────

struct KeyMetadata {
    key @0 :Text;
    sizeBytes @1 :UInt64;
    createdAt @2 :T.Timestamp;
    modifiedAt @3 :T.Timestamp;
    expiresAt @4 :T.Timestamp;
    version @5 :UInt64;
    encrypted @6 :Bool;
}

# ─── Transactions ─────────────────────────────────────────────

struct Transaction {
    id @0 :UInt64;
    namespace @1 :Text;
    operations @2 :List(TransactionOperation);
    status @3 :TransactionStatus;
}

struct TransactionOperation {
    type @0 :TransactionOpType;
    key @1 :Text;
    value @2 :DatabaseValue;
}

enum TransactionOpType {
    set @0;
    delete @1;
    get @2;
    custom @3;
}

enum TransactionStatus {
    committed @0;
    rolledBack @1;
    pending @2;
    failed @3;
    custom @4;
}

# ─── Change Capture ───────────────────────────────────────────

struct ChangeCaptureEvent {
    key @0 :Text;
    namespace @1 :Text;
    type @2 :ChangeType;
    oldValue @3 :DatabaseValue;
    newValue @4 :DatabaseValue;
    timestamp @5 :T.Timestamp;
    transactionId @6 :UInt64;
}

# ─── Time-Series ──────────────────────────────────────────────

struct DatabaseTimeRange {
    start @0 :T.Timestamp;
    end @1 :T.Timestamp;
}

struct TimeSeriesBucket {
    start @0 :T.Timestamp;
    end @1 :T.Timestamp;
    count @2 :UInt64;
    sum @3 :Float64;
    avg @4 :Float64;
    min @5 :Float64;
    max @6 :Float64;
}

# ─── Schema Management ────────────────────────────────────────

struct DatabaseSchema {
    version @0 :UInt32;
    namespaces @1 :List(NamespaceSchema);
    migrations @2 :List(SchemaMigration);
}

struct NamespaceSchema {
    name @0 :Text;
    keyPattern @1 :Text;
    valueType @2 :Text;
    indexes @3 :List(Text);
}

struct SchemaMigration {
    fromVersion @0 :UInt32;
    toVersion @1 :UInt32;
    upScript @2 :Text;
    downScript @3 :Text;
}

# ─── Key Subscription ─────────────────────────────────────────

struct KeySubscription {
    id @0 :UInt64;
}

# ─── Namespace Statistics ─────────────────────────────────────

struct NamespaceStats {
    namespace @0 :Text;
    keyCount @1 :UInt64;
    totalSizeBytes @2 :UInt64;
    avgValueSize @3 :UInt64;
    encryptedKeyCount @4 :UInt64;
    ttlKeyCount @5 :UInt64;
    oldestKey @6 :T.Timestamp;
    newestKey @7 :T.Timestamp;
}

# ─── Namespace Quota ──────────────────────────────────────────

struct NamespaceQuota {
    namespace @0 :Text;
    maxSizeBytes @1 :UInt64;
    maxKeys @2 :UInt64;
    maxTtlSeconds @3 :UInt64;
    currentSizeBytes @4 :UInt64;
    currentKeys @5 :UInt64;
}

# ─── Change Data Capture ────────────────────────────────────

enum DeliveryGuarantee {
    atLeastOnce @0;
    exactlyOnce @1;
    atMostOnce @2;
    custom @3;
}

struct ChangeStreamOptions {
    namespace @0 :Text;
    # Start reading from this timestamp (0 = from now).
    fromTimestamp @1 :T.Timestamp;
    # Delivery guarantee level.
    delivery @2 :DeliveryGuarantee;
    # Batch size for events.
    batchSize @3 :UInt32;
}

interface ChangeStreamSubscription {
    pull @0 () -> (events :List(ChangeCaptureEvent));
    cancel @1 () -> T.VoidResult;
}

# ─── Namespace Encryption Status ────────────────────────────

struct NamespaceEncryptionStatus {
    namespace @0 :Text;
    encrypted @1 :Bool;
    keyId @2 :T.KeyId;
    algorithm @3 :Text;
}

# ─── Audit Log ──────────────────────────────────────────────

enum AuditOperation {
    read @0;
    write @1;
    delete @2;
    create @3;
    update @4;
    custom @5;
}

struct AuditLogEntry {
    timestamp @0 :T.Timestamp;
    actor @1 :Text;
    namespace @2 :Text;
    key @3 :Text;
    operation @4 :AuditOperation;
    result @5 :Text;
    ipAddress @6 :Text;
}

struct AuditLogFilter {
    namespace @0 :Text;
    actor @1 :Text;
    operations @2 :List(AuditOperation);
    since @3 :T.Timestamp;
}

interface AuditLogSubscription {
    pull @0 () -> (entries :List(AuditLogEntry));
    cancel @1 () -> T.VoidResult;
}

# ─── Resource Metrics ───────────────────────────────────────

struct ResourceMetrics {
    namespace @0 :Text;
    storageUsedBytes @1 :UInt64;
    keyCount @2 :UInt64;
    avgQueryLatencyMs @3 :Float32;
    p99QueryLatencyMs @4 :Float32;
    connectionCount @5 :UInt32;
    cacheHitRate @6 :Float32;
    timestamp @7 :T.Timestamp;
}

# ─── Connection Pool ────────────────────────────────────────

struct ConnectionPoolConfig {
    minConnections @0 :UInt32;
    maxConnections @1 :UInt32;
    idleTimeout @2 :T.Duration;
    maxLifetime @3 :T.Duration;
}

struct ConnectionPoolStatus {
    activeConnections @0 :UInt32;
    idleConnections @1 :UInt32;
    totalRequests @2 :UInt64;
    waitingRequests @3 :UInt32;
}

# ─── Query Language ─────────────────────────────────────────

struct QueryRequest {
    query @0 :Text;
    parameters @1 :T.StringMap;
    page @2 :T.Pagination;
}

struct QueryResult {
    columns @0 :List(Text);
    rows @1 :List(T.StringMap);
    affectedCount @2 :UInt64;
    page @3 :T.Pagination;
}

# ─── Database Indexing ───────────────────────────────────────

enum IndexType {
    btree @0;
    hash @1;
    fullText @2;
    custom @3;
}

struct IndexDefinition {
    name @0 :Text;
    indexType @1 :IndexType;
    fields @2 :List(Text);
    unique @3 :Bool;
}

# ─── Graph Data Model ───────────────────────────────────────

struct GraphEdge {
    fromKey @0 :Text;
    toKey @1 :Text;
    edgeType @2 :Text;
    weight @3 :Float64;
    properties @4 :T.StringMap;
}

struct GraphPath {
    nodes @0 :List(Text);
    edges @1 :List(GraphEdge);
    totalWeight @2 :Float64;
}

struct Community {
    id @0 :UInt64;
    members @1 :List(Text);
    size @2 :UInt32;
    internalDensity @3 :Float32;
}

struct GraphQueryRequest {
    namespace @0 :Text;
    startKey @1 :Text;
    endKey @2 :Text;
    edgeType @3 :Text;
    maxDepth @4 :UInt32;
}

# ─── Vector Database ───────────────────────────────────────

enum SimilarityMetric {
    cosine @0;
    euclidean @1;
    dotProduct @2;
    manhattan @3;
    custom @4;
}

struct VectorEntry {
    key @0 :Text;
    vector @1 :List(Float32);
    metadata @2 :T.StringMap;
}

struct VectorSearchRequest {
    namespace @0 :Text;
    queryVector @1 :List(Float32);
    metric @2 :SimilarityMetric;
    topK @3 :UInt32;
    filter @4 :T.StringMap;
}

struct VectorSearchResult {
    key @0 :Text;
    score @1 :Float32;
    vector @2 :List(Float32);
    metadata @3 :T.StringMap;
}

# ─── CRDT Data Types ───────────────────────────────────────

enum CrdtType {
    gCounter @0;
    pnCounter @1;
    lwwRegister @2;
    orSet @3;
    orMap @4;
    custom @5;
}

struct CrdtValue {
    key @0 :Text;
    type @1 :CrdtType;
    value @2 :Data;
    vectorClock @3 :T.StringMap;
    timestamp @4 :T.Timestamp;
}

# ─── Multi-Node Replication ────────────────────────────────

enum ReplicationStrategy {
    push @0;
    pull @1;
    pushPull @2;
    custom @3;
}

struct DatabaseReplicationConfig {
    targetNamespace @0 :Text;
    targetNodeId @1 :Text;
    strategy @2 :ReplicationStrategy;
    syncInterval @3 :T.Duration;
    conflictResolution @4 :Text;
}

struct ReplicationStatus {
    sourceNamespace @0 :Text;
    targetNodeId @1 :Text;
    state @2 :Text;
    lagMs @3 :UInt64;
    lastSyncAt @4 :T.Timestamp;
}

# ─── Event Sourcing ────────────────────────────────────────

struct EventLogEntry {
    eventId @0 :UInt64;
    namespace @1 :Text;
    key @2 :Text;
    eventType @3 :Text;
    payload @4 :Data;
    timestamp @5 :T.Timestamp;
    metadata @6 :T.StringMap;
}

# ─── Snapshot Isolation ────────────────────────────────────

struct DatabaseSnapshot {
    snapshotId @0 :Text;
    namespace @1 :Text;
    createdAt @2 :T.Timestamp;
    keyCount @3 :UInt64;
}

# ─── Sharding ──────────────────────────────────────────────

enum ShardStrategy {
    hash @0;
    range @1;
    geo @2;
    custom @3;
}

struct ShardConfig {
    namespace @0 :Text;
    strategy @1 :ShardStrategy;
    shardCount @2 :UInt32;
    shardKey @3 :Text;
}

struct ShardInfo {
    shardId @0 :UInt32;
    namespace @1 :Text;
    keyRange @2 :Text;
    keyCount @3 :UInt64;
    sizeBytes @4 :UInt64;
    nodeId @5 :Text;
}

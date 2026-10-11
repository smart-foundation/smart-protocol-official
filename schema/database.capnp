@0xa1b2c3d4e5f6002d;

# ═══════════════════════════════════════════════════════════════════════
# Database — key-value storage with namespacing, batching, and change feeds.
#
# Zero-backend-assumption IPC contract. No SQL, no document store, no
# specific database engine assumed. The backend decides storage strategy.
#
# Revamp fixes (this wave):
#   - Vectors are content, not copied float lists. A top-100 search at
#     4096 dimensions shipped ~1.6 MB of copied floats per response, plus
#     the caller's query-vector copy on the way in — the exact pattern
#     ai.capnp rejects. Vector payloads are T.DataHandle now, with a
#     documented embedding MimeType convention.
#   - The value path is a handle. `get`/`set`/`setWithTtl` took and
#     returned inline `Data` while `exportNamespace` had already been
#     converted, so any blob-sized value copied inline on every operation.
#   - The header's "No SQL" claim is true: the query surface is now
#     CONTENT — a query language is a T.MimeType and the query body is a
#     T.DataHandle — so a backend declares which languages it accepts
#     instead of the schema promising a dialect it never specified.
#     `SchemaMigration` scripts are content too.
#   - Unbounded result sets are paginated (graph neighbors, community
#     detection, batch metadata, index listing).
#   - The change feed can resume: events carry a monotonic `sequence` and
#     the stream accepts `fromSequence`, so a reconnecting consumer
#     resumes deterministically instead of replaying or skipping.
#   - Snapshot ids are typed (T.SnapshotId), and the transaction handle
#     has one spelling.
#   - Storage-internals vocabularies (IndexType, ShardStrategy,
#     SimilarityMetric) became open tokens.
#   - Dead and duplicated surface is gone: NamespaceQuota, the local
#     ConnectionPoolConfig (endpoint.capnp is its canonical home) and
#     the duplicate `KeyValue` entry type.
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
    get @0 (namespace :Text, key :Text) -> (result :ValueResult);
    has @1 (namespace :Text, key :Text) -> (exists :Bool);
    # Paginated key listing — replaces unbounded List return.
    listKeys @2 (namespace :Text, prefix :Text, page :T.Pagination) -> (keys :List(Text), total :UInt64);
    count @3 (namespace :Text) -> (count :UInt64);

    set @4 (namespace :Text, key :Text, value :T.DataHandle) -> T.VoidResult;
    delete @5 (namespace :Text, key :Text) -> T.VoidResult;
    clear @6 (namespace :Text) -> T.VoidResult;

    setBatch @7 (namespace :Text, entries :List(KeyEntry)) -> T.VoidResult;
    getBatch @8 (namespace :Text, keys :List(Text)) -> (entries :List(KeyEntry));
    deleteBatch @9 (namespace :Text, keys :List(Text)) -> T.VoidResult;

    # Paginated namespace listing.
    listNamespaces @10 (page :T.Pagination) -> (namespaces :List(NamespaceInfo), total :UInt64);
    deleteNamespace @11 (namespace :Text) -> T.VoidResult;

    exportNamespace @12 (namespace :Text) -> (data :T.DataHandle);
    importNamespace @13 (namespace :Text, data :T.DataHandle) -> T.VoidResult;

    subscribeChanges @14 (namespace :Text) -> (subscription :NamespaceChangeSubscription);
    pullChanges @15 (subscription :NamespaceChangeSubscription) -> (changes :List(KeyChange));

    # ─── Typed Values ──────────────────────────────────────────

    # Get with typed value access.
    getTyped @16 (namespace :Text, key :Text) -> (entry :KeyEntry);

    # Set with typed value.
    setTyped @17 (namespace :Text, key :Text, value :DatabaseValue) -> T.VoidResult;

    # ─── TTL (Time-to-Live) ────────────────────────────────────

    # Set key with per-key TTL (auto-expiry).
    setWithTtl @18 (namespace :Text, key :Text, value :T.DataHandle, ttl :T.Duration) -> T.VoidResult;

    # Query remaining TTL for a key.
    getTtl @19 (namespace :Text, key :Text) -> (remaining :T.Duration, exists :Bool);

    # Batch set with per-key TTL.
    setBatchWithTtl @20 (namespace :Text, entries :List(KeyEntry)) -> T.VoidResult;

    # ─── Key Metadata ──────────────────────────────────────────

    # Retrieve key metadata without fetching value.
    getMetadata @21 (namespace :Text, key :Text) -> (metadata :EntryMetadata);

    # Retrieve metadata for multiple keys in one call.
    getBatchMetadata @22 (namespace :Text, page :T.Pagination) -> (metadata :List(EntryMetadata), totalCount :UInt64);

    # ─── Transactions ──────────────────────────────────────────

    # Start a multi-key transaction.
    beginTransaction @23 (namespace :Text, operations :List(TransactionOperation)) -> (transaction :Transaction);

    # Commit a transaction atomically.
    commitTransaction @24 (transactionId :TransactionId) -> T.VoidResult;

    # Rollback a transaction.
    rollbackTransaction @25 (transactionId :TransactionId) -> T.VoidResult;

    # Query transaction state.
    getTransactionStatus @26 (transactionId :TransactionId) -> (status :TransactionStatus);

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

    # What query languages this backend accepts. A consumer learns the
    # vocabulary instead of assuming a dialect.
    getQueryLanguages @31 () -> (languages :List(T.MimeType));

    # ─── Namespace Info ────────────────────────────────────────

    # Get detailed info for a namespace by ID.
    getNamespace @32 (namespace :Text) -> (info :NamespaceInfo);

    # ─── Watch Key ─────────────────────────────────────────────

    # Subscribe to changes on a specific key.
    watchKey @33 (namespace :Text, key :Text) -> (subscription :KeyChangeSubscription);

    # ─── Compaction ────────────────────────────────────────────

    # Trigger compaction/garbage collection for a namespace.
    compactNamespace @34 (namespace :Text) -> T.VoidResult;

    # ─── Namespace Statistics ──────────────────────────────────

    # Detailed namespace statistics.
    getNamespaceStats @35 (namespace :Text) -> (stats :NamespaceStats);

    # ─── Backup / Restore ──────────────────────────────────────

    # Create a point-in-time backup of a namespace.
    backupNamespace @36 (namespace :Text) -> (result :NamespaceBackupResult);

    # Restore from a point-in-time backup.
    restoreNamespace @37 (namespace :Text, backupId :T.BackupId) -> T.VoidResult;

    # ─── Key History ───────────────────────────────────────────

    # Retrieve change history for a specific key.
    getKeyHistory @38 (namespace :Text, key :Text, page :T.Pagination) -> (history :List(ChangeCaptureEvent), total :UInt64);

    # ─── Encryption ────────────────────────────────────────────

    # Encrypt a key's value with specified key.
    encryptKey @39 (namespace :Text, key :Text, keyId :T.KeyId) -> T.VoidResult;

    # Decrypt a key's value (if authorized).
    decryptKey @40 (namespace :Text, key :Text) -> T.VoidResult;

    # ─── Change Data Capture (CDC) ─────────────────────────────

    # Subscribe to a CDC stream with exactly-once delivery guarantees.
    subscribeChangeStream @41 (options :ChangeStreamOptions) -> (subscription :ChangeStreamSubscription);

    # ─── Database Encryption at Rest ──────────────────────────

    # Enable encryption for an entire namespace.
    encryptNamespace @42 (namespace :Text, keyId :T.KeyId) -> T.VoidResult;

    # Get encryption status for a namespace.
    getNamespaceEncryptionStatus @43 (namespace :Text) -> (status :NamespaceEncryptionStatus);

    # ─── Database Audit Logging ─────────────────────────────────

    # Subscribe to audit log for compliance.
    subscribeAuditLog @44 (filter :AuditLogFilter) -> (subscription :AuditLogSubscription);

    # ─── Database Resource Monitoring ──────────────────────────

    # Get resource usage metrics for a namespace.
    getResourceMonitor @45 (namespace :Text) -> (metrics :ResourceMetrics);

    # ─── Connection Pooling ─────────────────────────────────────

    # Get connection pool status.
    getConnectionPoolStatus @46 () -> (status :ConnectionPoolStatus);

    # Removed: `configureConnectionPool`. Pool configuration is the
    # transport layer's business (endpoint.capnp owns ConnectionPoolConfig);
    # a key-value service REPORTS its pool state, it does not take
    # transport configuration.

    # ─── SQL-like Query ────────────────────────────────────────

    # Execute a structured query (backend-specific SQL-like syntax).
    query @47 (request :QueryRequest) -> (result :QueryResult);

    # ─── Database Indexing ─────────────────────────────────────

    # Create a custom index on a namespace.
    createIndex @48 (namespace :Text, index :IndexDefinition) -> T.VoidResult;

    # List indexes for a namespace.
    listIndexes @49 (namespace :Text, pagination :T.Pagination) -> (indexes :List(IndexDefinition), totalCount :UInt64);

    # ─── Graph Data Model ─────────────────────────────────────

    # Add an edge to the graph.
    addGraphEdge @50 (namespace :Text, edge :GraphLink) -> T.VoidResult;

    # Find shortest path between two keys.
    shortestPath @51 (namespace :Text, request :GraphQueryRequest) -> (path :GraphPath);

    # Detect communities in the graph.
    detectCommunities @52 (namespace :Text, pagination :T.Pagination) -> (communities :List(Community), totalCount :UInt64);

    # Get neighbors of a key.
    getNeighbors @53 (namespace :Text, key :Text, edgeType :Text, pagination :T.Pagination) -> (neighbors :List(GraphLink), totalCount :UInt64);

    # ─── Vector Database ─────────────────────────────────────

    # Insert a vector embedding.
    insertVector @54 (namespace :Text, entry :VectorEntry) -> T.VoidResult;

    # Search by vector similarity.
    searchVector @55 (namespace :Text, request :VectorSearchRequest) -> (results :List(VectorSearchResult), totalCount :UInt64);

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
    startReplication @60 (config :DatabaseReplicationConfig) -> (replicationId :ReplicationId);

    # Get replication status.
    getReplicationStatus @61 (replicationId :ReplicationId) -> (status :DatabaseReplicationStatus);

    # Stop replication.
    stopReplication @62 (replicationId :ReplicationId) -> T.VoidResult;

    # ─── Event Sourcing ──────────────────────────────────────

    # Append an event to the event log.
    appendEvent @63 (namespace :Text, entry :EventLogEntry) -> (eventId :T.EventId);

    # Replay events from a given event ID.
    replayEvents @64 (namespace :Text, fromEventId :T.EventId, page :T.Pagination) -> (events :List(EventLogEntry), totalCount :UInt64);

    # ─── Snapshot Isolation ──────────────────────────────────

    # Create a point-in-time snapshot for consistent reads.
    createSnapshot @65 (namespace :Text) -> (snapshot :DatabaseSnapshot);

    # Read from a snapshot (consistent point-in-time read).
    readFromSnapshot @66 (snapshotId :T.SnapshotId, key :Text) -> (result :ValueResult);

    # Delete a snapshot.
    deleteSnapshot @67 (snapshotId :T.SnapshotId) -> T.VoidResult;

    # ─── Sharding ────────────────────────────────────────────

    # Configure sharding for a namespace.
    configureSharding @68 (config :ShardConfig) -> T.VoidResult;

    # Get shard info for a namespace.
    getShardInfo @69 (namespace :Text) -> (shards :List(ShardInfo));
}

# Renamed from ChangesSubscription (clipboard.capnp and secret.capnp each
# declare one): this is the namespace change feed.
interface NamespaceChangeSubscription {
    pull @0 () -> (changes :List(KeyChange));
    # Explicit cancellation — stops the change stream and releases resources.
    cancel @1 () -> T.VoidResult;
}

# The ONE entry type: opaque bytes, an optional decoded view, TTL and
# version. The previous `KeyValue` (opaque Data) and `KeyEntry` (typed
# union) were two spellings of one concept used by different batch
# methods, and `KeyValue` also collided with framebuffer.capnp's.
struct KeyEntry {
    key @0 :Text;
    value @1 :T.DataHandle;
    timestamp @2 :T.Timestamp;
    ttl @3 :T.Duration;
    version @4 :UInt64;
    # Decoded value when the backend can type it.
    typed @5 :DatabaseValue;
    metadata @6 :T.StringMap;
}

struct NamespaceInfo {
    name @0 :Text;
    count @1 :UInt64;
    # Total size in bytes of all values in this namespace.
    size @2 :UInt64;
    created @3 :T.Timestamp;
    metadata @4 :T.StringMap;
}

struct NamespaceBackupResult {
    union {
        backup @0 :NamespaceBackup;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct NamespaceBackup {
    backupId @0 :T.BackupId;
    data @1 :T.DataHandle;
    keyCount @2 :UInt64;
    metadata @3 :T.StringMap;
}

struct KeyChange {
    type @0 :ChangeType;
    key @1 :Text;
    namespace @2 :Text;
    timestamp @3 :T.Timestamp;
    metadata @4 :T.StringMap;
}

enum ChangeType {
    set @0;
    delete @1;
    clear @2;
    custom @3;
}

struct ValueResult {
    union {
        value @0 :T.DataHandle;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
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

# ─── Key Metadata ─────────────────────────────────────────────

struct EntryMetadata {
    key @0 :Text;
    sizeBytes @1 :UInt64;
    createdAt @2 :T.Timestamp;
    modifiedAt @3 :T.Timestamp;
    expiresAt @4 :T.Timestamp;
    version @5 :UInt64;
    encrypted @6 :Bool;
    metadata @7 :T.StringMap;
}

# ─── Transactions ─────────────────────────────────────────────

# A transaction has ONE handle spelling. The previous shape carried a raw
# UInt64 `id` that `commitTransaction`/`rollbackTransaction`/
# `getTransactionStatus` accepted directly, so holding the struct and
# holding its id both authorized a commit — two authority paths for one
# handle.
struct TransactionId { id @0 :UInt64; }

struct Transaction {
    id @0 :TransactionId;
    namespace @1 :Text;
    operations @2 :List(TransactionOperation);
    status @3 :TransactionStatus;
    metadata @4 :T.StringMap;
}

struct TransactionOperation {
    type @0 :TransactionOpType;
    key @1 :Text;
    value @2 :DatabaseValue;
    metadata @3 :T.StringMap;
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
    transactionId @6 :TransactionId;
    # Monotonic within the namespace. THE resume cursor: a reconnecting
    # consumer passes the last sequence it saw and continues
    # deterministically.
    sequence @7 :UInt64;
    metadata @8 :T.StringMap;
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
    metadata @3 :T.StringMap;
}

struct NamespaceSchema {
    name @0 :Text;
    keyPattern @1 :Text;
    valueType @2 :Text;
    indexes @3 :List(Text);
    metadata @4 :T.StringMap;
}

struct SchemaMigration {
    fromVersion @0 :UInt32;
    toVersion @1 :UInt32;
    # Migration scripts are CONTENT (a language plus a body), not a
    # promised dialect.
    upScript @2 :T.DataHandle;
    downScript @3 :T.DataHandle;
    metadata @4 :T.StringMap;
}

# ─── Key Subscription ─────────────────────────────────────────

# Renamed from KeySubscription (key_management.capnp declares an
# interface of that name): this is the per-key change feed's handle.
struct KeyChangeSubscription {
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
    metadata @8 :T.StringMap;
}

# Removed: NamespaceQuota — a third quota type (after the foundation's
# T.Quota and the filesystem one), and referenced by no method. Quota
# belongs to the resource-limit contract, not to the key-value one.
# ─── Change Data Capture ────────────────────────────────────

# The honest set. `exactlyOnce` used to sit here; it cannot be delivered
# by a durable-log consumer without a coordinator the protocol does not
# define, so a backend claiming it either lies or invents one. The feed
# carries a monotonic `sequence` (see ChangeCaptureEvent) so a consumer
# can achieve effective-exactly-once itself: resume from the last
# sequence it processed.
enum DeliveryGuarantee {
    unspecified @0;
    atMostOnce @1;
    atLeastOnce @2;
    custom @3;
}

struct ChangeStreamOptions {
    namespace @0 :Text;
    # Start reading from this timestamp (0 = from now).
    fromTimestamp @1 :T.Timestamp;
    # Resume from a monotonic sequence number. Present this and the
    # stream continues where the consumer stopped instead of replaying
    # from a timestamp (which may skip or duplicate events).
    fromSequence @2 :UInt64;
    # Delivery guarantee level.
    delivery @3 :DeliveryGuarantee;
    # Batch size for events.
    batchSize @4 :UInt32;
    metadata @5 :T.StringMap;
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
    metadata @4 :T.StringMap;
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
    metadata @7 :T.StringMap;
}

struct AuditLogFilter {
    namespace @0 :Text;
    actor @1 :Text;
    operations @2 :List(AuditOperation);
    since @3 :T.Timestamp;
    metadata @4 :T.StringMap;
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
    metadata @8 :T.StringMap;
}

# ─── Connection Pool ────────────────────────────────────────

struct ConnectionPoolStatus {
    activeConnections @0 :UInt32;
    idleConnections @1 :UInt32;
    totalRequests @2 :UInt64;
    waitingRequests @3 :UInt32;
}

# ─── Query Language ─────────────────────────────────────────

# A query is CONTENT: the language is a T.MimeType and the query body is
# a T.DataHandle. The previous `query :Text` promised a "SQL-like"
# dialect the file's own header forbids and nothing specified, so every
# backend invented one. A backend now declares which query languages it
# accepts (see `DatabaseDescriptor.queryLanguages`), and a consumer that
# does not recognise a language ignores it rather than guessing.
struct QueryRequest {
    language @0 :T.MimeType;
    query @1 :T.DataHandle;
    parameters @2 :T.StringMap;
    page @3 :T.Pagination;
}

struct QueryResult {
    union {
        rows @0 :QueryRows;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct QueryRows {
    columns @0 :List(Text);
    rows @1 :List(T.StringMap);
    affectedCount @2 :UInt64;
    page @3 :T.Pagination;
    # Set when the result was truncated to the page.
    truncated @4 :Bool;
}

# ─── Database Indexing ───────────────────────────────────────

# Index kind as an open token ("btree", "hash", "fullText", ...):
# storage-internals vocabulary. A 2046 index structure is a string.
struct IndexDefinition {
    name @0 :Text;
    indexType @1 :Text;
    fields @2 :List(Text);
    unique @3 :Bool;
    metadata @4 :T.StringMap;
}

# ─── Graph Data Model ───────────────────────────────────────

# Renamed from GraphEdge (system_search.capnp declares its own): this is
# the database graph's link type.
struct GraphLink {
    fromKey @0 :Text;
    toKey @1 :Text;
    edgeType @2 :Text;
    weight @3 :Float64;
    properties @4 :T.StringMap;
}

struct GraphPath {
    nodes @0 :List(Text);
    edges @1 :List(GraphLink);
    totalWeight @2 :Float64;
    metadata @3 :T.StringMap;
}

struct Community {
    id @0 :UInt64;
    members @1 :List(Text);
    size @2 :UInt32;
    internalDensity @3 :Float32;
    metadata @4 :T.StringMap;
}

struct GraphQueryRequest {
    namespace @0 :Text;
    startKey @1 :Text;
    endKey @2 :Text;
    edgeType @3 :Text;
    maxDepth @4 :UInt32;
    metadata @5 :T.StringMap;
}

# ─── Vector Database ────────────────────────────────────────
#
# Dense vectors are CONTENT: a 4096-dimension embedding is 16 KB of
# floats, and a top-100 search used to copy ~1.6 MB of them into one
# response (plus the query vector on the way in). The convention is
# `application/vnd.smart.embedding` (see ai.capnp): little-endian
# Float32, row-major, with the dimension count and element type declared
# in `parameters`. A consumer that does not recognise the type ignores
# the payload rather than misreading it.
#
# The similarity metric is an open token ("cosine", "euclidean",
# "dotProduct", ...): the mathematical set is defensible, the spellings
# are not, and the token lets a backend report what it actually used.

struct VectorEntry {
    key @0 :Text;
    vector @1 :T.DataHandle;
    # Dimension count, element type ("float32") and layout as declared
    # data, so the encoding travels with the payload.
    parameters @2 :T.StringMap;
    metadata @3 :T.StringMap;
}

struct VectorSearchRequest {
    namespace @0 :Text;
    queryVector @1 :T.DataHandle;
    # Similarity metric as an open token.
    metric @2 :Text;
    topK @3 :UInt32;
    filter @4 :T.StringMap;
    page @5 :T.Pagination;
}

struct VectorSearchResult {
    key @0 :Text;
    score @1 :Float32;
    # Present only when the caller asked for the vector itself; a search
    # no longer ships vectors nobody requested.
    vector @2 :T.DataHandle;
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

# A replication stream's id, typed so it cannot be confused with any
# other Text id in the file.
struct ReplicationId { id @0 :UInt64; }

struct DatabaseReplicationConfig {
    targetNamespace @0 :Text;
    targetNodeId @1 :Text;
    strategy @2 :ReplicationStrategy;
    syncInterval @3 :T.Duration;
    conflictResolution @4 :Text;
    metadata @5 :T.StringMap;
}

struct DatabaseReplicationStatus {
    sourceNamespace @0 :Text;
    targetNodeId @1 :Text;
    state @2 :Text;
    lagMs @3 :UInt64;
    lastSyncAt @4 :T.Timestamp;
    metadata @5 :T.StringMap;
}

# ─── Event Sourcing ────────────────────────────────────────

struct EventLogEntry {
    eventId @0 :T.EventId;
    namespace @1 :Text;
    key @2 :Text;
    # Event kind as an open token.
    eventType @3 :Text;
    # Event payload as content.
    payload @4 :T.DataHandle;
    timestamp @5 :T.Timestamp;
    metadata @6 :T.StringMap;
}


# ─── Snapshot Isolation ────────────────────────────────────

struct DatabaseSnapshot {
    snapshotId @0 :T.SnapshotId;
    namespace @1 :Text;
    createdAt @2 :T.Timestamp;
    keyCount @3 :UInt64;
    metadata @4 :T.StringMap;
}

# ─── Sharding ──────────────────────────────────────────────

# Sharding strategy as an open token ("hash", "range", "geo", ...):
# how a namespace is partitioned is storage-internals vocabulary.
struct ShardConfig {
    namespace @0 :Text;
    strategy @1 :Text;
    shardCount @2 :UInt32;
    shardKey @3 :Text;
    metadata @4 :T.StringMap;
}

struct ShardInfo {
    shardId @0 :UInt32;
    namespace @1 :Text;
    keyRange @2 :Text;
    keyCount @3 :UInt64;
    sizeBytes @4 :UInt64;
    nodeId @5 :Text;
    metadata @6 :T.StringMap;
}

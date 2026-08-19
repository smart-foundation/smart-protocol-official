@0xa1b2c3d4e5f60025;

# ═══════════════════════════════════════════════════════════════════════
# Files — file and directory operations with watch, search, permissions.
#
# Zero-backend-assumption IPC contract. No POSIX permission bits, no
# /dev paths, no Windows drive letters. The backend decides the
# filesystem representation; the protocol defines the contract.
#
# Improvements (audit):
#   - SpecialPathType imported from filesystem.capnp (canonical source).
#   - FileInfo.owner/group removed (POSIX UID/GID — not cross-platform).
#   - ExtendedMetadata.owner/group → Text (logical owner name, not UID).
#   - FileEventSubscription has cancel() for explicit teardown.
#   - readFile returns T.DataHandle (zero-copy for large reads).
#   - FileHandle.handle typed as T.FileHandleId (was bare UInt64).
#   - searchFiles paginated via T.Pagination.
#   - listDirectory paginated via T.Pagination in filter.
#   - walkTree paginated via T.Pagination.
#   - OpenRequest.flags typed as OpenFlag enum (was List(Text)).
#   - FilePermissions has other variant for forward compatibility.
#   - SortField has other variant for forward compatibility.
#   - FileEventType has other variant for forward compatibility.
#   - FileType has other variant for forward compatibility.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using FS = import "filesystem.capnp";

interface Files {
    openFile @0 (path :Text, request :OpenRequest) -> (handle :FileHandle);
    closeFile @1 (handle :FileHandle) -> T.VoidResult;

    readFile @2 (handle :FileHandle, offset :UInt64, size :UInt32) -> (data :T.DataHandle);
    writeFile @3 (handle :FileHandle, offset :UInt64, data :Data) -> (written :UInt32);
    flushFile @4 (handle :FileHandle) -> T.VoidResult;

    # Paginated directory listing.
    listDirectory @5 (path :Text, filter :DirectoryFilter) -> (entries :List(DirectoryEntry), total :UInt64);
    createDirectory @6 (path :Text, parents :Bool) -> T.VoidResult;

    statFile @7 (path :Text) -> (info :FileInfo);
    fileExists @8 (path :Text) -> (exists :Bool);
    renameFile @9 (oldPath :Text, newPath :Text) -> T.VoidResult;
    removeFile @10 (path :Text, recursive :Bool) -> T.VoidResult;
    copyFile @11 (src :Text, dst :Text) -> T.VoidResult;
    createSymlink @12 (target :Text, link :Text) -> T.VoidResult;

    # SpecialPathType is defined in filesystem.capnp (canonical source).
    getSpecialPath @13 (type :FS.SpecialPathType) -> (path :Text);

    watchDirectory @14 (path :Text) -> (subscription :FileEventSubscription);
    # Pull events from a subscription (convenience — canonical pull is on subscription interface).
    pullFileEvents @15 (subscription :FileEventSubscription) -> (events :List(FileEvent));

    # Paginated file search.
    searchFiles @16 (query :SearchQuery) -> (results :List(SearchResult), total :UInt64);

    getPermissions @17 (path :Text) -> (permissions :FilePermissions);
    setPermissions @18 (path :Text, permissions :FilePermissions) -> T.VoidResult;

    # File operations
    createFile @19 (path :Text, content :Data, parents :Bool) -> T.VoidResult;
    touch @20 (path :Text) -> T.VoidResult;
    removeDirectory @21 (path :Text, recursive :Bool) -> T.VoidResult;
    linkFile @22 (target :Text, link :Text, hard :Bool) -> T.VoidResult;
    resolveSymlink @23 (path :Text) -> (resolved :Text);

    # Directory traversal
    getCurrentDirectory @24 () -> (path :Text);
    changeDirectory @25 (path :Text) -> T.VoidResult;
    # Paginated tree walk.
    walkTree @26 (path :Text, maxDepth :UInt32, page :T.Pagination) -> (entries :List(DirectoryEntry), total :UInt64);

    # Disk usage
    getDiskUsage @27 (path :Text) -> (usage :DiskUsage);
    getFileMetadata @28 (path :Text) -> (metadata :ExtendedMetadata);

    # File comparison
    # DEPRECATED: Returns diff as bare Text. Use compareFilesV2 instead.
    # Kept for backward compatibility; will be removed in a future major version.
    compareFiles @29 (path1 :Text, path2 :Text) -> (identical :Bool, diff :Text);
    # File comparison with structured diff output via T.DataHandle.
    # PREFERRED: Always use this method over compareFiles.
    compareFilesV2 @30 (path1 :Text, path2 :Text) -> (identical :Bool, diff :T.DataHandle);

    # ─── File Locking ──────────────────────────────────────────

    # Acquire an advisory file lock (exclusive or shared).
    lockFile @31 (request :LockFileRequest) -> (lock :FileLock);

    # Release a previously acquired file lock.
    unlockFile @32 (lockId :UInt64) -> T.VoidResult;

    # List active locks on a file.
    getLocks @33 (path :Text) -> (locks :List(FileLock));

    # ─── File Versioning ───────────────────────────────────────

    # List versions of a file (paginated).
    getFileVersions @34 (path :Text, page :T.Pagination) -> (versions :List(FileVersion), total :UInt64);

    # Retrieve a specific file version.
    getFileVersion @35 (path :Text, versionId :UInt64) -> (version :FileVersion);

    # Restore file to a specific version.
    restoreVersion @36 (path :Text, versionId :UInt64) -> T.VoidResult;

    # Compare two versions (structured diff).
    compareVersions @37 (path :Text, versionA :UInt64, versionB :UInt64) -> (identical :Bool, diff :T.DataHandle);

    # ─── Content-Addressed Storage ─────────────────────────────

    # Retrieve file by content hash.
    getByHash @38 (request :GetByHashRequest) -> (handle :FileHandle, info :ContentAddressedRef);

    # Store file and return content hash.
    storeContentAddressed @39 (path :Text) -> (ref :ContentAddressedRef);

    # Find and merge duplicate content.
    deduplicate @40 (path :Text) -> (savedBytes :UInt64, referenceCount :UInt32);

    # ─── Ephemeral Files ───────────────────────────────────────

    # Create an ephemeral file with auto-delete policy.
    createEphemeral @41 (path :Text, config :EphemeralFileConfig) -> (handle :FileHandle);

    # ─── Encrypted Files ───────────────────────────────────────

    # Create an encrypted file.
    createEncrypted @42 (request :CreateEncryptedRequest) -> (handle :FileHandle);

    # Decrypt a file (if authorized).
    decryptFile @43 (path :Text, keyId :T.KeyId) -> T.VoidResult;

    # Retrieve encryption metadata.
    getEncryptionInfo @44 (path :Text) -> (info :EncryptedFileInfo);

    # ─── Cloud-Backed Files ────────────────────────────────────

    # Create a cloud-backed lazy file.
    createCloudBacked @45 (request :CreateCloudBackedRequest) -> (handle :FileHandle);

    # Check cloud sync status.
    getCloudSyncStatus @46 (path :Text) -> (status :CloudSyncStatus);

    # Force sync of cloud-backed file.
    forceCloudSync @47 (path :Text) -> T.VoidResult;

    # ─── Async I/O ─────────────────────────────────────────────

    # Non-blocking file read.
    readFileAsync @48 (handle :FileHandle, offset :UInt64, size :UInt32) -> (asyncHandle :AsyncFileHandle);

    # Non-blocking file write.
    writeFileAsync @49 (handle :FileHandle, offset :UInt64, data :Data) -> (asyncHandle :AsyncFileHandle);

    # Check async operation status.
    pollAsyncOperation @50 (asyncHandle :AsyncFileHandle) -> (status :AsyncOperationStatus);

    # Cancel an async operation.
    cancelAsyncOperation @51 (asyncHandle :AsyncFileHandle) -> T.VoidResult;

    # ─── Compression ───────────────────────────────────────────

    # Set compression for a file or directory.
    setCompression @52 (path :Text, config :FileCompressionConfig) -> T.VoidResult;

    # Get compression settings.
    getCompression @53 (path :Text) -> (config :FileCompressionConfig);

    # ─── Deduplication Stats ───────────────────────────────────

    # Get deduplication statistics for a path.
    getDeduplicationStats @54 (path :Text) -> (stats :FileDeduplicationInfo);

    # ─── Batch Operations ──────────────────────────────────────

    # Copy multiple files in one operation.
    batchCopy @55 (request :BatchCopyRequest) -> (result :BatchResult);

    # Move multiple files in one operation.
    batchMove @56 (request :BatchMoveRequest) -> (result :BatchResult);

    # Delete multiple files in one operation.
    batchDelete @57 (request :BatchDeleteRequest) -> (result :BatchResult);

    # ─── Directory Statistics ──────────────────────────────────

    # Get total size of directory (recursive).
    getDirectorySize @58 (path :Text) -> (size :UInt64);

    # Get detailed directory statistics.
    getDirectoryStats @59 (path :Text) -> (stats :DirectoryStats);

    # Compare two directories (diff).
    compareDirectories @60 (path1 :Text, path2 :Text) -> (identical :Bool, diff :T.DataHandle);

    # ─── File Activity & Permissions ───────────────────────────

    # Recent activity on a file (who modified, when).
    getFileActivity @61 (path :Text, page :T.Pagination) -> (activities :List(FileActivity), total :UInt64);

    # Check if current user has specific permissions.
    checkPermissions @62 (path :Text, required :FilePermissions) -> (allowed :Bool);

    # Detect file type by content (magic bytes).
    getFileType @63 (path :Text) -> (mimeType :Text, fileType :FileType);

    # Compute file hash (multiple algorithms supported).
    getFileHash @64 (path :Text, algorithm :HashAlgorithm) -> (hash :T.HashOutput);

    # Verify file integrity against stored checksum.
    getFileChecksum @65 (path :Text) -> (valid :Bool, stored :T.HashOutput, computed :T.HashOutput);

    # ─── File Lifecycle Management ───────────────────────────────

    # Set retention policy for a file or directory.
    setLifecycle @66 (path :Text, policy :RetentionPolicy) -> T.VoidResult;

    # Get retention policy for a path.
    getLifecycle @67 (path :Text) -> (policy :RetentionPolicy);

    # Apply lifecycle rules to a path (expiry, archival, disposal).
    applyLifecycle @68 (path :Text) -> (processed :UInt32);

    # ─── File Audit Trail ───────────────────────────────────────

    # Subscribe to file access audit events.
    subscribeFileAudit @69 (filter :FileAuditFilter) -> (subscription :FileAuditSubscription);

    # ─── File Content Analysis ───────────────────────────────────

    # Analyze file content (AI OCR, image recognition, classification).
    analyzeFileContent @70 (request :FileAnalysisRequest) -> (result :FileAnalysisResult);

    # ─── File Content Search ─────────────────────────────────────

    # Full-text search inside file content.
    searchFileContent @71 (query :ContentSearchQuery) -> (results :List(ContentSearchResult), total :UInt64);

    # ─── File Version Branching ──────────────────────────────────

    # Create a branch (fork) of a file version.
    branchVersion @72 (path :Text, versionId :UInt64, branchName :Text) -> (branch :FileBranch);

    # Merge a branch back into the main version.
    mergeBranch @73 (path :Text, branchName :Text) -> T.VoidResult;

    # List branches for a file.
    listBranches @74 (path :Text) -> (branches :List(FileBranch));

    # ─── File Backup Integration ─────────────────────────────────

    # Back up a file to the configured backup target.
    backupFile @75 (path :Text, config :BackupConfig) -> (backupId :Text);

    # Restore a file from backup.
    restoreBackup @76 (backupId :Text, targetPath :Text) -> T.VoidResult;

    # ─── File Synchronization ──────────────────────────────────

    # Sync a file or directory with a remote device.
    syncFile @77 (config :SyncConfig) -> (status :SyncStatus);

    # Get sync status for a path.
    getSyncStatus @78 (path :Text, deviceId :Text) -> (status :SyncStatus);

    # List all active sync configurations.
    listSyncConfigs @79 () -> (configs :List(SyncConfig));

    # ─── File ACL ─────────────────────────────────────────────

    # Set ACL entries for a file.
    setFileAcl @80 (path :Text, acl :FileAcl) -> T.VoidResult;

    # Get ACL entries for a file.
    getFileAcl @81 (path :Text) -> (acl :FileAcl);

    # Check if current user has a specific permission.
    checkAcl @82 (path :Text, permission :AclPermission) -> (allowed :Bool);

    # ─── File Metadata Cache ─────────────────────────────────

    # Get metadata cache statistics.
    getMetadataCacheStats @83 () -> (stats :MetadataCacheStats);

    # Invalidate metadata cache for a path.
    invalidateMetadataCache @84 (path :Text) -> T.VoidResult;

    # Pre-warm metadata cache for a directory.
    warmMetadataCache @85 (path :Text, maxDepth :UInt32) -> (entries :UInt32);
}

interface FileEventSubscription {
    pull @0 () -> (events :List(FileEvent));
    # Explicit cancellation — stops the event stream and releases resources.
    cancel @1 () -> T.VoidResult;
}

struct OpenRequest {
    mode @0 :OpenMode;
    flags @1 :List(OpenFlag);
    permissions @2 :FilePermissions;
}

enum OpenMode {
    read @0;
    write @1;
    readWrite @2;
    append @3;
    truncate @4;
    create @5;
    createNew @6;
    other @7;
    # Backend-specific open mode.
    custom @8;
}

enum OpenFlag {
    nonBlocking @0;
    append @1;
    exclusive @2;
    synchronous @3;
    # Backend-specific hint (e.g., temporary file, no-atime).
    hint @4;
    other @5;
    # Backend-specific open flag.
    custom @6;
}

struct FileHandle {
    # Typed file handle ID (not bare UInt64).
    handle @0 :T.FileHandleId;
    path @1 :Text;
    mode @2 :OpenMode;
}

struct DirectoryEntry {
    name @0 :Text;
    path @1 :Text;
    type @2 :FileType;
    size @3 :UInt64;
    modified @4 :T.Timestamp;
    permissions @5 :FilePermissions;
}

enum FileType {
    unknown @0;
    regular @1;
    directory @2;
    symlink @3;
    blockDevice @4;
    charDevice @5;
    fifo @6;
    socket @7;
    other @8;
    # Backend-specific file type.
    custom @9;
}

struct FileInfo {
    path @0 :Text;
    type @1 :FileType;
    size @2 :UInt64;
    created @3 :T.Timestamp;
    modified @4 :T.Timestamp;
    accessed @5 :T.Timestamp;
    permissions @6 :FilePermissions;
    mimeType @7 :Text;
}

struct FilePermissions {
    owner @0 :UInt8;
    group @1 :UInt8;
    other @2 :UInt8;
}

struct DirectoryFilter {
    patterns @0 :List(Text);
    includeHidden @1 :Bool;
    sortBy @2 :SortField;
    sortOrder @3 :SortOrder;
    recursive @4 :Bool;
    # Pagination for unbounded result sets.
    page @5 :T.Pagination;
}

enum SortField {
    name @0;
    size @1;
    modified @2;
    created @3;
    accessed @4;
    other @5;
    # Backend-specific sort field.
    custom @6;
}

enum SortOrder {
    ascending @0;
    descending @1;
    other @2;
    # Backend-specific sort order.
    custom @3;
}

struct FileEvent {
    id @0 :T.EventId;
    timestamp @1 :T.Timestamp;
    type @2 :FileEventType;
    path @3 :Text;
    oldPath @4 :Text;
}

enum FileEventType {
    create @0;
    delete @1;
    modify @2;
    rename @3;
    move @4;
    permission @5;
    other @6;
    # Backend-specific file event type.
    custom @7;
}

struct SearchQuery {
    path @0 :Text;
    pattern @1 :Text;
    recursive @2 :Bool;
    # Pagination for unbounded result sets.
    page @3 :T.Pagination;
}

struct SearchResult {
    path @0 :Text;
    name @1 :Text;
    type @2 :FileType;
    size @3 :UInt64;
    modified @4 :T.Timestamp;
    score @5 :Float32;
}

struct DiskUsage {
    total @0 :UInt64;
    used @1 :UInt64;
    free @2 :UInt64;
    percentUsed @3 :Float32;
    mountPoint @4 :Text;
    filesystem @5 :Text;
    # Typed mount reference (audit-6/7 fix — additive, backward compatible).
    mountId @6 :T.MountId;
    # Typed filesystem reference (audit-6/7 fix — additive, backward compatible).
    filesystemId @7 :T.FilesystemId;
}

struct ExtendedMetadata {
    path @0 :Text;
    name @1 :Text;
    type @2 :FileType;
    size @3 :UInt64;
    created @4 :T.Timestamp;
    modified @5 :T.Timestamp;
    accessed @6 :T.Timestamp;
    permissions @7 :FilePermissions;
    # Logical owner name (not POSIX UID — cross-platform).
    owner @8 :Text;
    # Logical group name (not POSIX GID — cross-platform).
    group @9 :Text;
    mimeType @10 :Text;
    target @11 :Text;
    isHidden @12 :Bool;
    isReadOnly @13 :Bool;
    isExecutable @14 :Bool;
    inode @15 :UInt64;
    device @16 :UInt64;
    hardLinks @17 :UInt32;
    # Content hash for deduplication and integrity (added audit-7).
    contentHash @18 :T.HashOutput;
    # Compressed size on disk (0 if not compressed).
    compressedSize @19 :UInt64;
    # Encryption key ID (0 if not encrypted).
    encryptionKey @20 :T.KeyId;
}

# ─── Disk Usage (extended with typed IDs) ─────────────────────

# DiskUsage extended with typed mount/filesystem references (audit-6/7).
# New fields are additive after ordinal 5 (backward compatible).

struct DiskUsageExtended {
    total @0 :UInt64;
    used @1 :UInt64;
    free @2 :UInt64;
    percentUsed @3 :Float32;
    mountPoint @4 :Text;
    filesystem @5 :Text;
    # Typed mount reference (audit-6/7 fix).
    mountId @6 :T.MountId;
    # Typed filesystem reference (audit-6/7 fix).
    filesystemId @7 :T.FilesystemId;
}

# ─── File Locking ─────────────────────────────────────────────

enum FileLockType {
    exclusive @0;
    shared @1;
    advisory @2;
    other @3;
    custom @4;
}

struct FileLock {
    lockId @0 :UInt64;
    handle @1 :FileHandle;
    lockType @2 :FileLockType;
    owner @3 :Text;
    acquiredAt @4 :T.Timestamp;
    expiresAt @5 :T.Timestamp;
}

struct LockFileRequest {
    path @0 :Text;
    lockType @1 :FileLockType;
    owner @2 :Text;
    timeout @3 :T.Duration;
}

# ─── File Versioning ──────────────────────────────────────────

struct FileVersion {
    versionId @0 :UInt64;
    contentHash @1 :T.HashOutput;
    createdAt @2 :T.Timestamp;
    author @3 :T.AppId;
    message @4 :Text;
    size @5 :UInt64;
}

# ─── Content-Addressed Storage ────────────────────────────────

struct ContentAddressedRef {
    hash @0 :T.HashOutput;
    algorithm @1 :Text;
    sizeBytes @2 :UInt64;
}

struct GetByHashRequest {
    hash @0 :T.HashOutput;
    algorithm @1 :Text;
}

# ─── Ephemeral Files ──────────────────────────────────────────

struct EphemeralFileConfig {
    deleteAfterRead @0 :Bool;
    maxAge @1 :T.Duration;
    maxReads @2 :UInt32;
}

# ─── Encrypted Files ──────────────────────────────────────────

struct CreateEncryptedRequest {
    path @0 :Text;
    content @1 :Data;
    keyId @2 :T.KeyId;
    algorithm @3 :Text;
    iv @4 :Data;
    parents @5 :Bool;
}

struct EncryptedFileInfo {
    keyId @0 :T.KeyId;
    algorithm @1 :Text;
    iv @2 :Data;
    encryptedSize @3 :UInt64;
}

# ─── Cloud-Backed Files ───────────────────────────────────────

enum CloudSyncPolicy {
    onDemand @0;
    full @1;
    incremental @2;
    custom @3;
}

struct CreateCloudBackedRequest {
    path @0 :Text;
    provider @1 :Text;
    remotePath @2 :Text;
    syncPolicy @3 :CloudSyncPolicy;
    cacheTtl @4 :T.Duration;
    parents @5 :Bool;
}

enum CloudSyncStatus {
    synced @0;
    syncing @1;
    pending @2;
    error @3;
    offline @4;
    custom @5;
}

# ─── Async I/O ────────────────────────────────────────────────

struct AsyncFileHandle {
    handle @0 :FileHandle;
    operationId @1 :UInt64;
    status @2 :AsyncOperationStatus;
}

enum AsyncOperationStatus {
    pending @0;
    completed @1;
    failed @2;
    cancelled @3;
    custom @4;
}

# ─── Compression ──────────────────────────────────────────────

enum CompressionAlgorithm {
    lz4 @0;
    zstd @1;
    gzip @2;
    none @3;
    custom @4;
}

struct FileCompressionConfig {
    algorithm @0 :CompressionAlgorithm;
    level @1 :UInt32;
}

# ─── Deduplication ────────────────────────────────────────────

struct FileDeduplicationInfo {
    contentHash @0 :T.HashOutput;
    referenceCount @1 :UInt32;
    savedBytes @2 :UInt64;
}

# ─── Hash Algorithm ───────────────────────────────────────────

enum HashAlgorithm {
    sha256 @0;
    sha512 @1;
    blake3 @2;
    md5 @3;
    sha1 @4;
    custom @5;
}

# ─── Batch Operations ─────────────────────────────────────────

struct BatchCopyRequest {
    sources @0 :List(Text);
    destination @1 :Text;
}

struct BatchMoveRequest {
    sources @0 :List(Text);
    destination @1 :Text;
}

struct BatchDeleteRequest {
    paths @0 :List(Text);
    recursive @1 :Bool;
}

struct BatchResult {
    success @0 :Bool;
    completed @1 :UInt32;
    failed @2 :UInt32;
    errors @3 :List(T.Error);
}

# ─── Directory Statistics ─────────────────────────────────────

struct DirectoryStats {
    totalFiles @0 :UInt32;
    totalDirectories @1 :UInt32;
    totalSize @2 :UInt64;
    byType @3 :List(FileTypeCount);
    largestFile @4 :Text;
    oldestFile @5 :Text;
    newestFile @6 :Text;
}

struct FileTypeCount {
    type @0 :FileType;
    count @1 :UInt32;
    totalSize @2 :UInt64;
}

# ─── File Activity ────────────────────────────────────────────

struct FileActivity {
    timestamp @0 :T.Timestamp;
    actor @1 :Text;
    action @2 :Text;
    path @3 :Text;
}

# ─── File Lifecycle Management ───────────────────────────────

enum LifecycleAction {
    retain @0;         # Keep indefinitely
    archive @1;         # Move to archival storage
    delete @2;          # Permanent deletion
    compress @3;        # Compress in place
    notify @4;          # Send notification only
    custom @5;
}

struct RetentionPolicy {
    path @0 :Text;
    action @1 :LifecycleAction;
    # Retention period (0 = use backend default).
    retentionPeriod @2 :T.Duration;
    # Minimum age before action applies.
    minAge @3 :T.Duration;
    # Whether policy is enabled.
    enabled @4 :Bool;
    # Policy description for compliance.
    description @5 :Text;
}

struct LifecycleRule {
    ruleId @0 :Text;
    pathPattern @1 :Text;
    policy @2 :RetentionPolicy;
    priority @3 :UInt32;
}

# ─── File Audit Trail ────────────────────────────────────────

enum AuditAction {
    read @0;
    write @1;
    delete @2;
    rename @3;
    permissionChange @4;
    create @5;
    custom @6;
}

struct FileAuditEntry {
    timestamp @0 :T.Timestamp;
    actor @1 :Text;
    action @2 :AuditAction;
    path @3 :Text;
    result @4 :Text;
    details @5 :Text;
}

struct FileAuditFilter {
    pathPattern @0 :Text;
    actor @1 :Text;
    actions @2 :List(AuditAction);
    since @3 :T.Timestamp;
}

interface FileAuditSubscription {
    pull @0 () -> (entries :List(FileAuditEntry));
    cancel @1 () -> T.VoidResult;
}

# ─── File Content Analysis ───────────────────────────────────

enum AnalysisType {
    ocr @0;
    imageRecognition @1;
    documentClassification @2;
    sentiment @3;
    custom @4;
}

struct FileAnalysisRequest {
    path @0 :Text;
    analysisTypes @1 :List(AnalysisType);
    language @2 :Text;
}

struct FileAnalysisResult {
    path @0 :Text;
    analysisType @1 :AnalysisType;
    result @2 :Text;
    confidence @3 :Float32;
    timestamp @4 :T.Timestamp;
}

# ─── File Content Search ─────────────────────────────────────

struct ContentSearchQuery {
    path @0 :Text;
    query @1 :Text;
    recursive @2 :Bool;
    mimeTypes @3 :List(Text);
    page @4 :T.Pagination;
}

struct ContentSearchResult {
    path @0 :Text;
    snippet @1 :Text;
    score @2 :Float32;
    lineNumber @3 :UInt32;
}

# ─── File Version Branching ───────────────────────────────────

struct FileBranch {
    branchId @0 :Text;
    branchName @1 :Text;
    path @2 :Text;
    baseVersion @3 :UInt64;
    createdAt @4 :T.Timestamp;
    author @5 :Text;
}

# ─── File Backup Integration ──────────────────────────────────

enum BackupTarget {
    local @0;
    cloud @1;
    network @2;
    custom @3;
}

struct BackupConfig {
    target @0 :BackupTarget;
    targetPath @1 :Text;
    includeMetadata @2 :Bool;
    compress @3 :Bool;
}

# ─── File Synchronization ───────────────────────────────────

enum SyncDirection {
    push @0;
    pull @1;
    bidirectional @2;
    custom @3;
}

enum SyncConflictResolution {
    keepLocal @0;
    keepRemote @1;
    newest @2;
    merge @3;
    custom @4;
}

struct SyncConfig {
    path @0 :Text;
    remotePath @1 :Text;
    deviceId @2 :Text;
    direction @3 :SyncDirection;
    conflictResolution @4 :SyncConflictResolution;
    syncMetadata @5 :Bool;
    excludes @6 :List(Text);
}

struct SyncStatus {
    path @0 :Text;
    deviceId @1 :Text;
    state @2 :Text;
    lastSyncAt @3 :T.Timestamp;
    conflictCount @4 :UInt32;
    pendingUploads @5 :UInt32;
    pendingDownloads @6 :UInt32;
}

# ─── File ACL ───────────────────────────────────────────────

enum AclPermission {
    read @0;
    write @1;
    execute @2;
    delete @3;
    admin @4;
    custom @5;
}

enum AclEntryType {
    user @0;
    group @1;
    everyone @2;
    named @3;
    custom @4;
}

struct AclEntry {
    entryType @0 :AclEntryType;
    identifier @1 :Text;
    permissions @2 :List(AclPermission);
    inherits @3 :Bool;
}

struct FileAcl {
    path @0 :Text;
    entries @1 :List(AclEntry);
    owner @2 :Text;
    defaultEntries @3 :List(AclEntry);
}

# ─── File Metadata Cache ────────────────────────────────────

struct MetadataCacheEntry {
    path @0 :Text;
    info @1 :FileInfo;
    cachedAt @2 :T.Timestamp;
    ttl @3 :T.Duration;
    hitCount @4 :UInt64;
}

struct MetadataCacheStats {
    totalEntries @0 :UInt32;
    totalHits @1 :UInt64;
    totalMisses @2 :UInt64;
    hitRate @3 :Float32;
    evictionCount @4 :UInt64;
}

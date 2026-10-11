@0xa1b2c3d4e5f60025;

# ═══════════════════════════════════════════════════════════════════════
# Files — the canonical file and directory contract.
#
# Zero-backend-assumption IPC contract. No POSIX permission bits, no
# inode numbers, no /dev paths, no Windows drive letters. The backend
# decides the filesystem representation; the protocol defines the
# contract: paths in, content out, handles as pure references.
#
# This file is the CANONICAL home for the file contract. It absorbed
# `filesystem.capnp` (deleted): `SpecialPathType`, trash, recent files
# and default apps now live here, so the canonical type no longer lives
# inside the schema the doctrine orders deleted. The mount surface of
# the absorbed file went to `mount.capnp`; pool-, volume- and
# replication-keyed administration lives in `storage.capnp`.
#
# Authority: a caller holds the `Files` reference (host-injected) or a
# `FileService` reference acquired with a capability. There is no
# permission model in this file — no owner/group/other, no ACL, no
# permission check by name. Access control is the capability system's
# job (capability.capnp); a file's access control is expressed by which
# reference the caller holds.
#
# Design rules applied (audit + DESIGN_PRINCIPLES/TIMELESSNESS):
#   - Every bulk payload is T.DataHandle (read AND write).
#   - `FileHandle` is a pure reference: no path, no mode. The path and
#     the open mode are reported by `FileInfo`.
#   - Every method that can fail returns a result union carrying T.Error.
#     A missing file is an error, not a zeroed struct.
#   - No inode, no device number, no hard-link count: filesystem
#     internals are backend metadata (T.StringMap), never required.
#   - Bulk lists are paginated; event streams are pull + cancel.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "capability.capnp".Capability;

interface Files {
    openFile @0 (path :Text, request :OpenRequest) -> (result :OpenResult);
    closeFile @1 (handle :FileHandle) -> T.VoidResult;

    readFile @2 (handle :FileHandle, offset :UInt64, size :UInt32) -> (data :T.DataHandle);
    writeFile @3 (handle :FileHandle, offset :UInt64, data :T.DataHandle) -> (written :UInt32);
    flushFile @4 (handle :FileHandle) -> T.VoidResult;

    # Paginated directory listing.
    listDirectory @5 (path :Text, filter :DirectoryFilter) -> (entries :List(DirectoryEntry), total :UInt64);
    createDirectory @6 (path :Text, parents :Bool) -> T.VoidResult;

    statFile @7 (path :Text) -> (result :FileInfoResult);
    fileExists @8 (path :Text) -> (exists :Bool);
    renameFile @9 (oldPath :Text, newPath :Text) -> T.VoidResult;
    removeFile @10 (path :Text, recursive :Bool) -> T.VoidResult;
    copyFile @11 (src :Text, dst :Text) -> T.VoidResult;
    createSymlink @12 (target :Text, link :Text) -> T.VoidResult;

    # SpecialPathType is defined here (absorbed from filesystem.capnp).
    getSpecialPath @13 (type :SpecialPathType) -> (result :TextResult);

    watchDirectory @14 (path :Text) -> (subscription :FileEventSubscription);

    # Paginated file search.
    searchFiles @15 (query :FileSearchQuery) -> (results :List(FileSearchResult), total :UInt64);

    createFile @16 (path :Text, content :T.DataHandle, parents :Bool) -> T.VoidResult;
    touch @17 (path :Text) -> T.VoidResult;
    removeDirectory @18 (path :Text, recursive :Bool) -> T.VoidResult;
    linkFile @19 (target :Text, link :Text, hard :Bool) -> T.VoidResult;
    resolveSymlink @20 (path :Text) -> (result :TextResult);

    getCurrentDirectory @21 () -> (path :Text);
    changeDirectory @22 (path :Text) -> T.VoidResult;

    # Paginated tree walk.
    walkTree @23 (path :Text, maxDepth :UInt32, page :T.Pagination) -> (entries :List(DirectoryEntry), total :UInt64);

    getDiskUsage @24 (path :Text) -> (usage :DiskUsage);
    getFileMetadata @25 (path :Text) -> (metadata :ExtendedMetadata);

    # File comparison with structured diff output via T.DataHandle.
    compareFiles @26 (path1 :Text, path2 :Text) -> (result :ComparisonResult);

    # ─── File Locking ──────────────────────────────────────────

    lockFile @27 (request :LockFileRequest) -> (lock :FileLock);
    unlockFile @28 (lockId :UInt64) -> T.VoidResult;
    getLocks @29 (path :Text) -> (locks :List(FileLock));

    # ─── File Versioning ───────────────────────────────────────

    getFileVersions @30 (path :Text, page :T.Pagination) -> (versions :List(FileVersion), total :UInt64);
    getFileVersion @31 (path :Text, versionId :UInt64) -> (result :VersionResult);
    restoreVersion @32 (path :Text, versionId :UInt64) -> T.VoidResult;
    compareVersions @33 (path :Text, versionA :UInt64, versionB :UInt64) -> (result :ComparisonResult);

    # ─── Content-Addressed Storage ─────────────────────────────

    getByHash @34 (request :GetByHashRequest) -> (result :ContentRefResult);
    storeContentAddressed @35 (path :Text) -> (result :ContentRefResult);
    deduplicate @36 (path :Text) -> (savedBytes :UInt64, referenceCount :UInt32);

    # ─── Ephemeral Files ───────────────────────────────────────

    createEphemeral @37 (path :Text, config :EphemeralFileConfig) -> (result :OpenResult);

    # ─── Encrypted Files ───────────────────────────────────────

    createEncrypted @38 (request :CreateEncryptedRequest) -> (result :OpenResult);
    decryptFile @39 (path :Text, keyId :T.KeyId) -> T.VoidResult;
    getEncryptionInfo @40 (path :Text) -> (result :EncryptionInfoResult);

    # ─── Compression ───────────────────────────────────────────

    setCompression @41 (path :Text, config :FileCompressionConfig) -> T.VoidResult;
    getCompression @42 (path :Text) -> (config :FileCompressionConfig);

    # ─── Deduplication Stats ───────────────────────────────────

    getDeduplicationStats @43 (path :Text) -> (stats :FileDeduplicationInfo);

    # ─── Batch Operations ──────────────────────────────────────

    batchCopy @44 (request :BatchCopyRequest) -> (result :BatchResult);
    batchMove @45 (request :BatchMoveRequest) -> (result :BatchResult);
    batchDelete @46 (request :BatchDeleteRequest) -> (result :BatchResult);

    # ─── Directory Statistics ──────────────────────────────────

    getDirectorySize @47 (path :Text) -> (size :UInt64);
    getDirectoryStats @48 (path :Text) -> (stats :DirectoryStats);
    compareDirectories @49 (path1 :Text, path2 :Text) -> (result :ComparisonResult);

    # ─── File Activity & Identity ──────────────────────────────

    getFileActivity @50 (path :Text, page :T.Pagination) -> (activities :List(FileActivity), total :UInt64);
    getFileType @51 (path :Text) -> (result :FileInfoResult);
    getFileHash @52 (path :Text, algorithm :Text) -> (result :FileHashResult);
    getFileChecksum @53 (path :Text) -> (result :ChecksumResult);

    # ─── Lifecycle Management ──────────────────────────────────

    setLifecycle @54 (path :Text, policy :LifecyclePolicy) -> T.VoidResult;
    getLifecycle @55 (path :Text) -> (result :LifecyclePolicyResult);
    applyLifecycle @56 (path :Text) -> (processed :UInt32);

    # ─── Audit Trail ───────────────────────────────────────────

    subscribeFileAudit @57 (filter :FileAuditFilter) -> (subscription :FileAuditSubscription);

    # ─── Content Analysis ──────────────────────────────────────

    # Analysis kinds are open tokens (ocr, image-recognition, ...): the
    # ai.capnp precedent is that a capability list is today's list.
    analyzeFileContent @58 (request :FileAnalysisRequest) -> (result :FileAnalysisResult);

    # ─── Content Search ────────────────────────────────────────

    searchFileContent @59 (query :ContentSearchQuery) -> (results :List(ContentSearchResult), total :UInt64);

    # ─── Version Branching ─────────────────────────────────────

    branchVersion @60 (path :Text, versionId :UInt64, branchName :Text) -> (result :BranchResult);
    mergeBranch @61 (path :Text, branchName :Text) -> T.VoidResult;
    listBranches @62 (path :Text, page :T.Pagination) -> (branches :List(FileBranch), total :UInt64);

    # ─── Trash (absorbed from filesystem.capnp) ─────────────────

    listTrash @63 (page :T.Pagination) -> (entries :List(TrashEntry), total :UInt64);
    restoreTrash @64 (entryId :Text, targetPath :Text) -> T.VoidResult;
    emptyTrash @65 () -> T.VoidResult;

    # ─── Recent Files (absorbed from filesystem.capnp) ──────────

    getRecentFiles @66 (page :T.Pagination) -> (files :List(RecentFile), total :UInt64);
    clearRecentFiles @67 () -> T.VoidResult;

    # ─── Default Apps (absorbed from filesystem.capnp) ──────────

    getDefaultApp @68 (mimeType :T.MimeType) -> (result :DefaultAppResult);

    # ─── Filesystem Health & Quota (absorbed, path-keyed) ───────

    getFilesystemHealth @69 (path :Text) -> (result :FilesystemHealthResult);
    getQuota @70 (path :Text) -> (quota :FilesystemQuota);
    setQuota @71 (path :Text, quota :FilesystemQuota) -> T.VoidResult;

    # Create a point-in-time snapshot of a path.
    createSnapshot @72 (path :Text, name :Text) -> (result :SnapshotRefResult);

    # ─── Delegated Access (the capability path) ─────────────────

    # The one gated method in this file. Present a capability whose
    # target is a path and receive a service bound to that path and to
    # nothing else. Attenuation and revocation are capability.capnp's
    # job; this is how a caller hands file authority to another
    # component without inventing an out-of-band scheme.
    acquireFile @73 (path :Text, authority :Capability) -> (service :FileService);
}

# A service bound to one path under a granted capability. Holding this
# reference IS the authority to operate on that path — no per-method
# token, no permission name, no ACL.
interface FileService {
    open @0 (request :OpenRequest) -> (result :OpenResult);
    read @1 (offset :UInt64, size :UInt32) -> (data :T.DataHandle);
    write @2 (offset :UInt64, data :T.DataHandle) -> (written :UInt32);
    stat @3 () -> (result :FileInfoResult);
    close @4 () -> T.VoidResult;
}

interface FileEventSubscription {
    pull @0 () -> (events :List(FileEvent));
    cancel @1 () -> T.VoidResult;
}

interface FileAuditSubscription {
    pull @0 () -> (entries :List(FileAuditEntry));
    cancel @1 () -> T.VoidResult;
}

# ─── Open / Handles ───────────────────────────────────────────────────

struct OpenRequest {
    mode @0 :OpenMode;
    flags @1 :List(OpenFlag);
}

struct OpenResult {
    union {
        handle @0 :FileHandle;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

enum OpenMode {
    unknown @0;
    read @1;
    write @2;
    readWrite @3;
    append @4;
    truncate @5;
    create @6;
    createNew @7;
    custom @8;
}

enum OpenFlag {
    unknown @0;
    nonBlocking @1;
    append @2;
    exclusive @3;
    synchronous @4;
    hint @5;
    custom @6;
}

# A pure reference. The path and the open mode are reported by FileInfo;
# a handle that carried them would force a backend to fabricate values a
# consumer then depends on.
struct FileHandle {
    handle @0 :T.FileHandleId;
    metadata @1 :T.StringMap;
}

struct DirectoryEntry {
    name @0 :Text;
    path @1 :Text;
    type @2 :FileType;
    size @3 :UInt64;
    modified @4 :T.Timestamp;
    metadata @5 :T.StringMap;
}

enum FileType {
    unknown @0;
    regular @1;
    directory @2;
    symlink @3;
    other @4;
    custom @5;
}

struct FileInfo {
    path @0 :Text;
    type @1 :FileType;
    size @2 :UInt64;
    created @3 :T.Timestamp;
    modified @4 :T.Timestamp;
    accessed @5 :T.Timestamp;
    mimeType @6 :T.MimeType;
    # Whether the backend can report this path's content hash.
    contentHash @7 :T.HashOutput;
    # Opaque backend extras — the only place filesystem internals
    # (inode, device, link count) may appear, and only as reported data.
    metadata @8 :T.StringMap;
}

struct DirectoryFilter {
    patterns @0 :List(Text);
    includeHidden @1 :Bool;
    sortBy @2 :SortField;
    sortOrder @3 :SortOrder;
    recursive @4 :Bool;
    page @5 :T.Pagination;
    annotations @6 :T.StringMap;
}

enum SortField {
    unknown @0;
    name @1;
    size @2;
    modified @3;
    created @4;
    accessed @5;
    custom @6;
}

enum SortOrder {
    unknown @0;
    ascending @1;
    descending @2;
    custom @3;
}

struct FileEvent {
    id @0 :T.EventId;
    timestamp @1 :T.Timestamp;
    type @2 :FileEventType;
    path @3 :Text;
    oldPath @4 :Text;
    metadata @5 :T.StringMap;
}

enum FileEventType {
    unknown @0;
    create @1;
    delete @2;
    modify @3;
    rename @4;
    move @5;
    custom @6;
}

struct FileSearchQuery {
    path @0 :Text;
    pattern @1 :Text;
    recursive @2 :Bool;
    page @3 :T.Pagination;
    annotations @4 :T.StringMap;
}

struct FileSearchResult {
    path @0 :Text;
    name @1 :Text;
    type @2 :FileType;
    size @3 :UInt64;
    modified @4 :T.Timestamp;
    score @5 :Float32;
    metadata @6 :T.StringMap;
}

struct DiskUsage {
    total @0 :UInt64;
    used @1 :UInt64;
    free @2 :UInt64;
    percentUsed @3 :Float32;
    mountPoint @4 :Text;
    mountId @5 :T.MountId;
    filesystemId @6 :T.FilesystemId;
    metadata @7 :T.StringMap;
}

struct ExtendedMetadata {
    path @0 :Text;
    name @1 :Text;
    type @2 :FileType;
    size @3 :UInt64;
    created @4 :T.Timestamp;
    modified @5 :T.Timestamp;
    accessed @6 :T.Timestamp;
    # Logical owner label, reported by the backend. It carries no
    # authority: the capability system decides who may act.
    owner @7 :Text;
    mimeType @8 :T.MimeType;
    target @9 :Text;
    isHidden @10 :Bool;
    isReadOnly @11 :Bool;
    isExecutable @12 :Bool;
    contentHash @13 :T.HashOutput;
    compressedSize @14 :UInt64;
    encryptionKey @15 :T.KeyId;
    # Backend-decided internals live here and nowhere else.
    metadata @16 :T.StringMap;
}

struct ComparisonResult {
    identical @0 :Bool;
    diff @1 :T.DataHandle;
    error @2 :T.Error;
    metadata @3 :T.StringMap;
}

# ─── File Locking ─────────────────────────────────────────────────────

enum FileLockType {
    unknown @0;
    exclusive @1;
    shared @2;
    custom @3;
}

struct FileLock {
    lockId @0 :UInt64;
    handle @1 :FileHandle;
    lockType @2 :FileLockType;
    owner @3 :Text;
    acquiredAt @4 :T.Timestamp;
    expiresAt @5 :T.Timestamp;
    metadata @6 :T.StringMap;
}

struct LockFileRequest {
    path @0 :Text;
    lockType @1 :FileLockType;
    owner @2 :Text;
    timeout @3 :T.Duration;
    metadata @4 :T.StringMap;
}

# ─── File Versioning ──────────────────────────────────────────────────

struct FileVersion {
    versionId @0 :UInt64;
    contentHash @1 :T.HashOutput;
    createdAt @2 :T.Timestamp;
    author @3 :T.AppId;
    message @4 :Text;
    size @5 :UInt64;
    metadata @6 :T.StringMap;
}

struct VersionResult {
    union {
        version @0 :FileVersion;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct BranchResult {
    union {
        branch @0 :FileBranch;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct FileBranch {
    branchId @0 :Text;
    branchName @1 :Text;
    path @2 :Text;
    baseVersion @3 :UInt64;
    createdAt @4 :T.Timestamp;
    author @5 :Text;
    metadata @6 :T.StringMap;
}

# ─── Content-Addressed Storage ────────────────────────────────────────

struct ContentAddressedRef {
    hash @0 :T.HashOutput;
    algorithm @1 :Text;
    sizeBytes @2 :UInt64;
    metadata @3 :T.StringMap;
}

struct ContentRefResult {
    union {
        ref @0 :ContentAddressedRef;
        handle @1 :FileHandle;
        error @2 :T.Error;
        unknown @3 :T.UnknownEvent;
    }
}

struct GetByHashRequest {
    hash @0 :T.HashOutput;
    algorithm @1 :Text;
    metadata @2 :T.StringMap;
}

# ─── Ephemeral Files ──────────────────────────────────────────────────

struct EphemeralFileConfig {
    deleteAfterRead @0 :Bool;
    maxAge @1 :T.Duration;
    maxReads @2 :UInt32;
}

# ─── Encrypted Files ──────────────────────────────────────────────────

struct CreateEncryptedRequest {
    path @0 :Text;
    content @1 :T.DataHandle;
    keyId @2 :T.KeyId;
    algorithm @3 :Text;
    parents @4 :Bool;
    metadata @5 :T.StringMap;
}

struct EncryptedFileInfo {
    keyId @0 :T.KeyId;
    algorithm @1 :Text;
    encryptedSize @2 :UInt64;
    metadata @3 :T.StringMap;
}

struct EncryptionInfoResult {
    union {
        info @0 :EncryptedFileInfo;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

# ─── Compression ──────────────────────────────────────────────────────

# The algorithm is an open token: a 2046 codec is a string with
# unknown-tolerance, not a new ordinal in an eternal enum.
struct FileCompressionConfig {
    algorithm @0 :Text;
    level @1 :UInt32;
    metadata @2 :T.StringMap;
}

# ─── Deduplication ────────────────────────────────────────────────────

struct FileDeduplicationInfo {
    contentHash @0 :T.HashOutput;
    referenceCount @1 :UInt32;
    savedBytes @2 :UInt64;
    metadata @3 :T.StringMap;
}

# ─── Results ──────────────────────────────────────────────────────────

struct FileInfoResult {
    union {
        info @0 :FileInfo;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct TextResult {
    union {
        value @0 :Text;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct FileHashResult {
    union {
        hash @0 :T.HashOutput;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct ChecksumResult {
    valid @0 :Bool;
    stored @1 :T.HashOutput;
    computed @2 :T.HashOutput;
    error @3 :T.Error;
    metadata @4 :T.StringMap;
}

struct LifecyclePolicyResult {
    union {
        policy @0 :LifecyclePolicy;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct BatchResult {
    completed @0 :UInt32;
    failed @1 :UInt32;
    errors @2 :List(T.Error);
    metadata @3 :T.StringMap;
}

# ─── Batch Operations ─────────────────────────────────────────────────

struct BatchCopyRequest {
    sources @0 :List(Text);
    destination @1 :Text;
    metadata @2 :T.StringMap;
}

struct BatchMoveRequest {
    sources @0 :List(Text);
    destination @1 :Text;
    metadata @2 :T.StringMap;
}

struct BatchDeleteRequest {
    paths @0 :List(Text);
    recursive @1 :Bool;
    metadata @2 :T.StringMap;
}

# ─── Directory Statistics ─────────────────────────────────────────────

struct DirectoryStats {
    totalFiles @0 :UInt64;
    totalDirectories @1 :UInt64;
    totalSize @2 :UInt64;
    byType @3 :List(FileTypeCount);
    largestFile @4 :Text;
    oldestFile @5 :Text;
    newestFile @6 :Text;
    metadata @7 :T.StringMap;
}

struct FileTypeCount {
    type @0 :FileType;
    count @1 :UInt64;
    totalSize @2 :UInt64;
}

# ─── File Activity ────────────────────────────────────────────────────

struct FileActivity {
    timestamp @0 :T.Timestamp;
    actor @1 :Text;
    action @2 :Text;
    path @3 :Text;
    metadata @4 :T.StringMap;
}

# ─── Lifecycle Management ─────────────────────────────────────────────

enum RetentionAction {
    unknown @0;
    retain @1;
    archive @2;
    delete @3;
    compress @4;
    notify @5;
    custom @6;
}

struct LifecyclePolicy {
    path @0 :Text;
    action @1 :RetentionAction;
    retentionPeriod @2 :T.Duration;
    minAge @3 :T.Duration;
    enabled @4 :Bool;
    description @5 :Text;
    metadata @6 :T.StringMap;
}

# ─── Audit Trail ──────────────────────────────────────────────────────

enum AuditAction {
    unknown @0;
    read @1;
    write @2;
    delete @3;
    rename @4;
    permissionChange @5;
    create @6;
    custom @7;
}

struct FileAuditEntry {
    timestamp @0 :T.Timestamp;
    actor @1 :Text;
    action @2 :AuditAction;
    path @3 :Text;
    result @4 :Text;
    details @5 :Text;
    metadata @6 :T.StringMap;
}

struct FileAuditFilter {
    pathPattern @0 :Text;
    actor @1 :Text;
    actions @2 :List(AuditAction);
    since @3 :T.Timestamp;
    metadata @4 :T.StringMap;
}

# ─── Content Analysis ─────────────────────────────────────────────────

struct FileAnalysisRequest {
    path @0 :Text;
    # Open tokens: "ocr", "image-recognition", ... Unknown kinds are
    # ignored, never rejected.
    analysisTypes @1 :List(Text);
    language @2 :Text;
    metadata @3 :T.StringMap;
}

struct FileAnalysisResult {
    path @0 :Text;
    analysisType @1 :Text;
    result @2 :T.DataHandle;
    confidence @3 :Float32;
    timestamp @4 :T.Timestamp;
    metadata @5 :T.StringMap;
}

# ─── Content Search ───────────────────────────────────────────────────

struct ContentSearchQuery {
    path @0 :Text;
    query @1 :Text;
    recursive @2 :Bool;
    mimeTypes @3 :List(T.MimeType);
    page @4 :T.Pagination;
    annotations @5 :T.StringMap;
}

struct ContentSearchResult {
    path @0 :Text;
    snippet @1 :Text;
    score @2 :Float32;
    lineNumber @3 :UInt32;
    metadata @4 :T.StringMap;
}

# ─── Trash (absorbed from filesystem.capnp) ───────────────────────────

struct TrashEntry {
    entryId @0 :Text;
    originalPath @1 :Text;
    deletedAt @2 :T.Timestamp;
    size @3 :UInt64;
    metadata @4 :T.StringMap;
}

# ─── Recent Files (absorbed) ──────────────────────────────────────────

struct RecentFile {
    path @0 :Text;
    mimeType @1 :T.MimeType;
    timestamp @2 :T.Timestamp;
    metadata @3 :T.StringMap;
}

# ─── Default Apps (absorbed) ──────────────────────────────────────────

struct DefaultAppInfo {
    appId @0 :T.AppId;
    name @1 :Text;
    icon @2 :T.DataHandle;
    metadata @3 :T.StringMap;
}

struct DefaultAppResult {
    union {
        app @0 :DefaultAppInfo;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

# ─── Filesystem Health & Quota (absorbed) ─────────────────────────────

# Status is an open token ("healthy", "degraded", "checking", ...): the
# three HealthStatus enums this batch carried were one vocabulary
# pretending to be three.
struct FilesystemHealth {
    status @0 :Text;
    lastCheck @1 :T.Timestamp;
    nextScheduled @2 :T.Timestamp;
    errors @3 :UInt64;
    warnings @4 :UInt64;
    details @5 :Text;
    metadata @6 :T.StringMap;
}

struct FilesystemHealthResult {
    union {
        health @0 :FilesystemHealth;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct FilesystemQuota {
    maxSizeBytes @0 :UInt64;
    maxFiles @1 :UInt64;
    currentSizeBytes @2 :UInt64;
    currentFiles @3 :UInt64;
    softLimitPercent @4 :UInt8;
}

struct SnapshotRefResult {
    union {
        snapshotId @0 :T.SnapshotId;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

# ─── Special Paths (absorbed from filesystem.capnp) ───────────────────
# Ordinals are unchanged from the absorbed file so `getSpecialPath`
# keeps its published wire shape.

enum SpecialPathType {
    home @0;
    documents @1;
    downloads @2;
    music @3;
    pictures @4;
    videos @5;
    desktop @6;
    templates @7;
    public @8;
    trash @9;
    cache @10;
    config @11;
    data @12;
    runtime @13;
    other @14;
}

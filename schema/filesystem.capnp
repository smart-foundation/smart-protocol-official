@0xa1b2c3d4e5f60017;

# ═══════════════════════════════════════════════════════════════════════
# Filesystem — special paths, mounts, trash, default apps.
#
# Zero-backend-assumption IPC contract. No POSIX mount(2), no Windows
# drive letters, no FUSE assumed. The backend decides the filesystem
# representation; the protocol defines the contract.
#
# Canonical source for SpecialPathType — imported by files.capnp.
#
# Improvements (audit-2):
#   - DefaultAppInfo.appId typed as T.AppId (was bare Text).
#   - DefaultAppInfo.icon → T.DataHandle for zero-copy large payloads.
#   - MountInfo has documentation for size/used fields (bytes).
#   - SpecialPathType has other variant for forward compatibility.
#   - MountOptions has other variant for forward compatibility.
#   - Mount/unmount return T.VoidResult with structured T.Error.
#
# Improvements (audit-3):
#   - getRecentFiles paginated with T.Pagination (Rule 9).
#   - getMounts paginated with T.Pagination (Rule 9).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface Filesystem {
    getSpecialPath @0 (type :SpecialPathType) -> (path :Text);

    getTrash @1 () -> (path :Text);
    emptyTrash @2 () -> T.VoidResult;

    getRecentFiles @3 (page :T.Pagination) -> (files :List(RecentFile));
    clearRecentFiles @4 () -> T.VoidResult;

    getDefaultApp @5 (mimeType :Text) -> (app :DefaultAppInfo);

    mount @6 (path :Text, options :MountOptions) -> T.VoidResult;
    unmount @7 (path :Text) -> T.VoidResult;
    getMounts @8 (page :T.Pagination) -> (mounts :List(MountInfo));

    # ─── Filesystem Health ─────────────────────────────────────

    # Get filesystem health status.
    getHealth @9 (path :Text) -> (health :FilesystemHealth);

    # ─── Snapshot / Clone / Quota ──────────────────────────────

    # Create a filesystem snapshot (if supported).
    snapshot @10 (path :Text, name :Text) -> (snapshotId :Text);

    # Clone a filesystem (copy-on-write).
    cloneFilesystem @11 (source :Text, destination :Text) -> T.VoidResult;

    # Get quota for a filesystem path.
    getQuota @12 (path :Text) -> (quota :FilesystemQuota);

    # Set quota for a filesystem path.
    setQuota @13 (path :Text, quota :FilesystemQuota) -> T.VoidResult;

    # ─── Overlay / Union Mount ─────────────────────────────────

    # Mount an overlay filesystem with typed layer management.
    mountOverlay @14 (request :OverlayMountRequest) -> T.VoidResult;

    # Get overlay layer information for an existing mount.
    getOverlayLayers @15 (path :Text) -> (layers :OverlayLayerInfo);

    # ─── FUSE / Userland Backend Registration ──────────────────

    # Register a userland filesystem backend (FUSE, 9P, virtiofs).
    registerBackend @16 (info :FuseBackendInfo) -> T.VoidResult;

    # ─── Network Filesystem ────────────────────────────────────

    # Get network mount details for a path.
    getNetworkMountInfo @17 (path :Text) -> (info :NetworkMountInfo);

    # ─── Content-Addressed Store ───────────────────────────────

    # Resolve a content hash to a file path.
    resolveContentHash @18 (algorithm :Text, hash :Data) -> (path :Text, info :ContentAddressedInfo);

    # ─── Tiered Storage ────────────────────────────────────────

    # Get tiered storage information for a path.
    getTieredStorageInfo @19 (path :Text) -> (info :TieredStorageInfo);

    # ─── Remount ───────────────────────────────────────────────

    # Remount with different options (atomic).
    remount @20 (path :Text, options :MountOptions) -> T.VoidResult;

    # ─── Auto-Mount Rules ──────────────────────────────────────

    # Enable auto-mount for device insertion.
    enableAutoMount @21 (rule :AutoMountRule) -> T.VoidResult;

    # Disable auto-mount rule.
    disableAutoMount @22 (ruleId :Text) -> T.VoidResult;

    # List auto-mount rules.
    listAutoMountRules @23 () -> (rules :List(AutoMountRule));

    # ─── Mount Event Subscription ──────────────────────────────

    # Subscribe to mount events with filtering.
    subscribeMountEvents @24 (filter :MountEventFilter) -> (subscription :MountEventSubscription);

    # ─── Overlay Mount Operations ───────────────────────────────

    # Unmount an overlay filesystem.
    unmountOverlay @25 (path :Text) -> T.VoidResult;

    # Modify an existing overlay mount (change layers, options).
    modifyOverlay @26 (path :Text, request :OverlayMountRequest) -> T.VoidResult;

    # Get statistics for an overlay mount.
    getOverlayStats @27 (path :Text) -> (stats :OverlayMountStats);

    # ─── Filesystem Encryption ─────────────────────────────────

    # Get encryption status for a filesystem path.
    getEncryptionStatus @28 (path :Text) -> (info :FilesystemEncryptionInfo);

    # ─── Filesystem Compression ────────────────────────────────

    # Get compression statistics for a filesystem path.
    getCompressionStats @29 (path :Text) -> (stats :FilesystemCompressionStats);

    # ─── Filesystem Deduplication ──────────────────────────────

    # Get deduplication statistics for a filesystem path.
    getDedupStats @30 (path :Text) -> (stats :FilesystemDedupStats);

    # ─── Filesystem Replication ────────────────────────────────

    # Start filesystem replication.
    startReplication @31 (config :FilesystemReplicationConfig) -> (replicationId :Text);

    # Get replication status.
    getReplicationStatus @32 (replicationId :Text) -> (status :FilesystemReplicationStatus);

    # Stop filesystem replication.
    stopReplication @33 (replicationId :Text) -> T.VoidResult;

    # ─── Filesystem I/O Stats ──────────────────────────────────

    # Subscribe to real-time I/O statistics for a filesystem.
    subscribeIoStats @34 (path :Text, interval :T.Duration) -> (subscription :FilesystemIoStatsSubscription);
}

struct RecentFile {
    path @0 :Text;
    mimeType @1 :Text;
    timestamp @2 :T.Timestamp;
}

struct DefaultAppInfo {
    appId @0 :T.AppId;
    name @1 :Text;
    # Icon as inline small data or buffer reference for large icons.
    icon @2 :T.DataHandle;
}

struct MountOptions {
    readOnly @0 :Bool;
    fsType @1 :Text;
    options @2 :T.StringMap;
}

struct MountInfo {
    path @0 :Text;
    device @1 :Text;
    fsType @2 :Text;
    options @3 :T.StringMap;
    # Total size in bytes.
    size @4 :UInt64;
    # Used space in bytes.
    used @5 :UInt64;
}

# Canonical SpecialPathType — imported by files.capnp.
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

# ─── Filesystem Health ────────────────────────────────────────

enum HealthStatus {
    healthy @0;
    degraded @1;
    failing @2;
    offline @3;
    checking @4;
    custom @5;
}

struct FilesystemHealth {
    status @0 :HealthStatus;
    lastCheck @1 :T.Timestamp;
    nextScheduled @2 :T.Timestamp;
    errors @3 :UInt64;
    warnings @4 :UInt64;
    details @5 :Text;
}

# ─── Filesystem Quota ─────────────────────────────────────────

struct FilesystemQuota {
    # Maximum size in bytes (0 = unlimited).
    maxSizeBytes @0 :UInt64;
    # Maximum number of files (0 = unlimited).
    maxFiles @1 :UInt64;
    # Current size in bytes.
    currentSizeBytes @2 :UInt64;
    # Current file count.
    currentFiles @3 :UInt64;
    # Soft limit warning threshold (percentage 0-100).
    softLimitPercent @4 :UInt8;
}

# ─── Overlay / Union Mount ────────────────────────────────────

enum OverlayIndexMode {
    auto @0;
    on @1;
    off @2;
    global @3;
    custom @4;
}

struct OverlayMountRequest {
    # Target mount point.
    target @0 :Text;
    # Writable upper layer.
    upperDir @1 :Text;
    # Read-only lower layers (bottom-up order).
    lowerDirs @2 :List(Text);
    # Working directory for atomicity.
    workDir @3 :Text;
    # Overlay index mode.
    indexMode @4 :OverlayIndexMode;
    # Additional mount options.
    options @5 :MountOptions;
}

struct OverlayLayerInfo {
    upperDir @0 :Text;
    lowerDirs @1 :List(Text);
    workDir @2 :Text;
    indexMode @3 :OverlayIndexMode;
    # Number of files in upper layer (modified files).
    upperFileCount @4 :UInt64;
}

# ─── FUSE / Userland Backend ──────────────────────────────────

enum FuseCapability {
    readdirPlus @0;
    fallocate @1;
    flush @2;
    fsync @3;
    lock @4;
    bmap @5;
    notify @6;
    poll @7;
    writebackCaching @8;
    custom @9;
}

struct FuseBackendInfo {
    name @0 :Text;
    # Protocol: "FUSE", "9P", "virtiofs".
    protocol @1 :Text;
    mountPoint @2 :Text;
    maxReadSize @3 :UInt32;
    capabilities @4 :List(FuseCapability);
}

# ─── Network Filesystem ───────────────────────────────────────

enum NetworkFsProtocol {
    nfs @0;
    cifs @1;
    smb @2;
    webdav @3;
    nineP @4;
    fuseSshfs @5;
    other @6;
}

enum NetworkFsAuth {
    none @0;
    guest @1;
    kerberos @2;
    ntlm @3;
    certificate @4;
    token @5;
    custom @6;
}

enum NetworkFsTransport {
    tcp @0;
    udp @1;
    rdma @2;
    unix @3;
    custom @4;
}

struct NetworkMountInfo {
    protocol @0 :NetworkFsProtocol;
    server @1 :Text;
    share @2 :Text;
    authMethod @3 :NetworkFsAuth;
    transport @4 :NetworkFsTransport;
    timeout @5 :T.Duration;
    reconnect @6 :Bool;
}

# ─── Content-Addressed Store ──────────────────────────────────

struct ContentAddressedInfo {
    # Hash algorithm (e.g., "sha256", "sha3-256", "blake3").
    scheme @0 :Text;
    hash @1 :Data;
    sizeBytes @2 :UInt64;
    mimeType @3 :Text;
    replicated @4 :Bool;
}

# ─── Tiered Storage ───────────────────────────────────────────

enum StorageTier {
    hot @0;
    warm @1;
    cold @2;
    archive @3;
    custom @4;
}

struct TieredStorageInfo {
    currentTier @0 :StorageTier;
    availableTiers @1 :List(StorageTier);
    # Bytes accessed threshold for promotion.
    promotionThreshold @2 :UInt64;
    # Time since last access for demotion.
    demotionAge @3 :T.Duration;
}

# ─── Auto-Mount Rules ─────────────────────────────────────────

struct AutoMountRule {
    ruleId @0 :Text;
    # Device pattern (e.g., "sd*", "mmcblk*", "nvme*").
    devicePattern @1 :Text;
    # Filesystem type to auto-mount.
    fsType @2 :Text;
    # Target mount point template.
    mountPoint @3 :Text;
    # Mount options.
    options @4 :MountOptions;
    # Whether rule is enabled.
    enabled @5 :Bool;
}

# ─── Mount Event Subscription ─────────────────────────────────

struct MountEventFilter {
    # Filter by path prefix.
    pathPrefix @0 :Text;
    # Filter by filesystem type.
    fsType @1 :Text;
    # Filter by mount operation.
    operations @2 :List(MountOperation);
}

interface MountEventSubscription {
    pull @0 () -> (events :List(MountEvent));
    cancel @1 () -> T.VoidResult;
}

struct MountEvent {
    timestamp @0 :T.Timestamp;
    mountId @1 :T.MountId;
    path @2 :Text;
    operation @3 :MountOperation;
}

enum MountOperation {
    mount @0;
    unmount @1;
    remount @2;
    custom @3;
}

# ─── Overlay Mount Statistics ────────────────────────────────

struct OverlayMountStats {
    path @0 :Text;
    # Number of files in upper (writable) layer.
    upperFileCount @1 :UInt64;
    # Number of files in lower (read-only) layers.
    lowerFileCount @2 :UInt64;
    # Total size of modified files in upper layer.
    upperSize @3 :UInt64;
    # Total size of all layers combined.
    totalSize @4 :UInt64;
    # Number of copy-up operations performed.
    copyUpCount @5 :UInt64;
    # Number of whiteout files (deleted in upper).
    whiteoutCount @6 :UInt64;
}

# ─── Filesystem Encryption Status ──────────────────────────

struct FilesystemEncryptionInfo {
    path @0 :Text;
    encrypted @1 :Bool;
    method @2 :Text;
    keyId @3 :T.KeyId;
    algorithm @4 :Text;
    keySize @5 :UInt32;
    unlocked @6 :Bool;
    # Backend-specific encryption metadata.
    metadata @7 :T.StringMap;
}

# ─── Filesystem Compression Stats ──────────────────────────

struct FilesystemCompressionStats {
    path @0 :Text;
    algorithm @1 :Text;
    level @2 :UInt32;
    # Pre-compression size in bytes.
    uncompressedBytes @3 :UInt64;
    # Post-compression size in bytes.
    compressedBytes @4 :UInt64;
    # Compression ratio (uncompressed/compressed).
    ratio @5 :Float32;
    # Number of compressed files.
    fileCount @6 :UInt32;
}

# ─── Filesystem Dedup Stats ────────────────────────────────

struct FilesystemDedupStats {
    path @0 :Text;
    # Total logical bytes.
    logicalBytes @1 :UInt64;
    # Actual physical bytes on disk.
    physicalBytes @2 :UInt64;
    # Dedup ratio (logical/physical).
    ratio @3 :Float32;
    # Number of duplicate blocks.
    duplicateBlocks @4 :UInt64;
    # Space saved in bytes.
    savedBytes @5 :UInt64;
}

# ─── Filesystem Replication ────────────────────────────────

enum FilesystemReplicationMode {
    sync @0;
    async @1;
    semiSync @2;
    custom @3;
}

struct FilesystemReplicationConfig {
    sourcePath @0 :Text;
    targetPath @1 :Text;
    targetNodeId @2 :Text;
    mode @3 :FilesystemReplicationMode;
    maxLagBytes @4 :UInt64;
    syncInterval @5 :T.Duration;
}

struct FilesystemReplicationStatus {
    sourcePath @0 :Text;
    targetNodeId @1 :Text;
    state @2 :Text;
    lagBytes @3 :UInt64;
    lastSyncAt @4 :T.Timestamp;
    bytesReplicated @5 :UInt64;
}

# ─── Filesystem I/O Stats ──────────────────────────────────

struct FilesystemIoStats {
    path @0 :Text;
    readBytes @1 :UInt64;
    writeBytes @2 :UInt64;
    readOps @3 :UInt64;
    writeOps @4 :UInt64;
    avgReadLatencyUs @5 :UInt32;
    avgWriteLatencyUs @6 :UInt32;
    queueDepth @7 :UInt32;
    timestamp @8 :T.Timestamp;
}

interface FilesystemIoStatsSubscription {
    pull @0 () -> (stats :List(FilesystemIoStats));
    cancel @1 () -> T.VoidResult;
}

# ═══════════════════════════════════════════════════════════════════════
# v0.0.2 additions — Filesystem Provider
#
# A filesystem driver (ext4, FAT, BTRFS, custom) is a capability.
# VFS asks the provider to mount, unmount, sync; inode ops go
# through the Filesystem interface (existing). Swap in a new
# filesystem backend without recompiling the rest of the stack.
# ═══════════════════════════════════════════════════════════════════════

interface FsProvider {
    # Static metadata of this fs implementation.
    getCapabilities @0 () -> (caps :FsCapabilities);
    # Probe — does this driver recognize this block device's contents?
    # (Driver may read only the first few blocks to decide.)
    probe @1 (geometry :BlockGeometryMask) -> (verdict :ProbeVerdict);
    # Mount.
    mount @2 (blockProvider :CapabilityId, mountOptions :FsMountOptions) -> (mount :FsMountHandle);
    # Unmount — must flush.
    unmount @3 (mount :FsMountHandle) -> (result :FsVoidResult);
    # Force sync of pending writes to the underlying block provider.
    sync @4 (mount :FsMountHandle) -> (result :FsVoidResult);
    # Driver-defined health ping.
    ping @5 () -> (health :T.DriverHealth);
}

# Capability reference (the block provider is itself a capability).
using CapabilityId = UInt64;

struct BlockGeometryMask {
    # Driver inspects only those fields it cares about.
    union {
        fromBlockProvider @0 :UInt64;
        sparse @1 :Data;
        custom @2 :Void;
    }
}

struct FsCapabilities {
    # Filesystem names this driver is registered for ("ext4", "btrfs").
    filesystems @0 :List(Text);
    # Whether the implementation supports COW snapshots.
    snapshots @1 :Bool;
    # Whether it supports encryption at rest.
    encryption @2 :Bool;
    # Whether it supports compression.
    compression @3 :Bool;
    # Maximum supported file size in bytes.
    maxFileSize @4 :UInt64;
    # Driver-defined backend class.
    driverClass @5 :Text;
    # Compatible smart-protocol kernel version range.
    compatibleVersion @6 :Text;
}

enum ProbeVerdict {
    recognized @0;
    uncertain  @1;
    mismatch  @2;
    corrupt   @3;
    custom    @4;
}

struct FsMountOptions {
    # Filesystem-specific options (e.g., "noatime", "errors=remount-ro").
    rawOptions @0 :Data;
    # Optional mount flags from FsMountFlag.
    flags @1 :UInt32;
    # Read-only?
    readOnly @2 :Bool;
    # Encoding hint for filenames (driver may ignore).
    encoding @3 :Text;
}

enum FsMountFlag {
    noAtime  @0;
    noExec   @1;
    noSuid   @2;
    sync     @3;
    custom   @4;
}

struct FsMountHandle {
    # Identifier issued by the driver.
    handle @0 :UInt64;
    # Filesystem type (driver fills in).
    filesystem @1 :Text;
    # Mountpoint identifier (VFS-issued).
    mountpoint @2 :Text;
    # Source block provider's capability id.
    blockProvider @3 :UInt64;
}

struct FsVoidResult {
    success @0 :Bool;
    code @1 :UInt32;
    message @2 :Text;
}

@0xa1b2c3d4e5f60107;

using T = import "types.capnp";
using FS = import "filesystem.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Mount — typed mount point and filesystem references.
#
# files.capnp getDiskUsage returns mountPoint/filesystem as bare Text.
# A typed MountId / FilesystemId enables cross-schema references
# (e.g., storage.capnp listing mount points).
#
# Zero backend assumptions: no /proc/mounts, no libmount, no
# FindVolume, no GetVolumeInformation. Backend provides mount info.
#
# Used by: files.capnp (getDiskUsage), storage.capnp (block device mounts),
#          filesystem.capnp (mount operations)
# ═══════════════════════════════════════════════════════════════════════

interface MountService {
    # List all mount points.
    listMounts @0 (filter :MountFilter, pagination :T.Pagination) -> (mounts :List(MountPoint), totalCount :UInt32);

    # Get detailed info for a mount point.
    getMountInfo @1 (mountId :T.MountId) -> (mount :MountPoint);

    # Get mount point for a path.
    getMountForPath @2 (path :Text) -> (mount :MountPoint);

    # Mount a filesystem.
    mount @3 (request :MountRequest) -> (mount :MountPoint);

    # Unmount a filesystem.
    unmount @4 (mountId :T.MountId, force :Bool, lazy :Bool) -> T.VoidResult;

    # Remount with different options.
    remount @5 (mountId :T.MountId, options :MountOptions) -> T.VoidResult;

    # Get filesystem info for a mount.
    getFilesystemInfo @6 (mountId :T.MountId) -> (fs :FilesystemInfo);

    # Detect filesystem type on a device.
    detectFilesystem @8 (devicePath :Text) -> (fsType :Text, label :Text, uuid :Text);

    # Check filesystem integrity.
    checkFilesystem @9 (mountId :T.MountId, repair :Bool) -> (result :FilesystemCheckResult);

    # Subscribe to mount events.
    subscribeMounts @7 () -> (subscription :MountSubscription);

    # ─── Mount Locking ─────────────────────────────────────────

    # Acquire an exclusive mount lock for concurrent safety.
    acquireMountLock @10 (mountId :T.MountId, timeout :T.Duration) -> (lockId :UInt64);

    # Release a mount lock.
    releaseMountLock @11 (lockId :UInt64) -> T.VoidResult;

    # ─── Auto-Mount ────────────────────────────────────────────

    # Enable auto-mount for device insertion.
    enableAutoMount @12 (rule :AutoMountRule) -> (ruleId :Text);

    # Disable auto-mount rule.
    disableAutoMount @13 (ruleId :Text) -> T.VoidResult;

    # List auto-mount rules.
    listAutoMountRules @14 () -> (rules :List(AutoMountRule));

    # ─── Overlay Mount ─────────────────────────────────────────

    # Mount an overlay filesystem with typed layers.
    mountOverlay @15 (request :OverlayMountRequest) -> (mount :MountPoint);

    # ─── Mount Namespace ───────────────────────────────────────

    # List mount namespaces.
    listMountNamespaces @16 () -> (namespaces :List(MountNamespace));

    # ─── Auto-Mount Policy ─────────────────────────────────────

    # Create an auto-mount policy (device insertion trigger).
    createAutoMountPolicy @17 (policy :AutoMountPolicy) -> (policyId :Text);

    # Update an existing auto-mount policy.
    updateAutoMountPolicy @18 (policyId :Text, policy :AutoMountPolicy) -> T.VoidResult;

    # Delete an auto-mount policy.
    deleteAutoMountPolicy @19 (policyId :Text) -> T.VoidResult;

    # List all auto-mount policies.
    listAutoMountPolicies @20 () -> (policies :List(AutoMountPolicy));

    # Subscribe to auto-mount events (device insertion, mount success/failure).
    subscribeAutoMountEvents @21 (filter :AutoMountEventFilter) -> (subscription :AutoMountEventSubscription);

    # ─── Filesystem Resize ─────────────────────────────────────

    # Resize a filesystem (online grow/shrink).
    resizeFilesystem @22 (request :FilesystemResizeRequest) -> T.VoidResult;

    # ─── Mount Stats Streaming ─────────────────────────────────

    # Subscribe to real-time mount point statistics.
    subscribeMountStats @23 (interval :T.Duration) -> (subscription :MountStatsSubscription);

    # Get current stats for a mount point.
    getMountStats @24 (mountId :T.MountId) -> (stats :MountStats);

    # ─── Device-Mapper Mount ───────────────────────────────────

    # Mount via device-mapper (dm-crypt, dm-thin, dm-linear).
    mountDeviceMapper @25 (request :DeviceMapperMountRequest) -> (mount :MountPoint);

    # Get device-mapper table info for a mount.
    getDeviceMapperInfo @26 (mountId :T.MountId) -> (dmType :Text, tableArgs :T.StringMap);
}

interface MountSubscription {
    pull @0 () -> (events :List(MountEvent));
    cancel @1 () -> T.VoidResult;
}

# ─── Mount Identity ──────────────────────────────────────────────────

struct MountId { id @0 :UInt64; }
struct FilesystemId { id @0 :UInt64; }

# ─── Mount Point ─────────────────────────────────────────────────────

struct MountPoint {
    id @0 :T.MountId;
    # Mount point path (where filesystem is attached).
    path @1 :Text;
    # Source device/spec (e.g., /dev/sda1, UUID=..., server:/path).
    source @2 :Text;
    # Filesystem type (ext4, xfs, btrfs, nfs, smb, etc.).
    fsType @3 :Text;
    # Mount options.
    options @4 :MountOptions;
    # Filesystem UUID/label.
    fsUuid @5 :Text;
    fsLabel @6 :Text;
    # Total size in bytes.
    totalSize @7 :UInt64;
    # Used space in bytes.
    usedSize @8 :UInt64;
    # Available space in bytes.
    availableSize @9 :UInt64;
    # Inode usage.
    totalInodes @10 :UInt64;
    usedInodes @11 :UInt64;
    # Mount flags.
    flags @12 :MountFlags;
    # Device ID (st_dev from stat).
    deviceId @13 :UInt64;
    # When this was mounted.
    mountedAt @14 :T.Timestamp;
    # Backend-specific metadata.
    metadata @15 :T.StringMap;
}

struct MountOptions {
    # Read-only.
    readonly @0 :Bool;
    # No suid.
    nosuid @1 :Bool;
    # No device files.
    nodev @2 :Bool;
    # No exec.
    noexec @3 :Bool;
    # Synchronous writes.
    sync @4 :Bool;
    # No atime updates.
    noatime @5 :Bool;
    # Relative atime.
    relatime @6 :Bool;
    # Directory sync.
    dirsync @7 :Bool;
    # Mandatory locking.
    mand @8 :Bool;
    # Bind mount.
    bind @9 :Bool;
    # Recursive bind.
    rbind @10 :Bool;
    # Move mount.
    move @11 :Bool;
    # Shared/private/slave/unbindable propagation.
    propagation @12 :PropagationType;
    # Filesystem-specific options (comma-separated).
    fsSpecific @13 :Text;
    # Custom options.
    custom @14 :T.StringMap;
}

enum PropagationType {
    private @0;
    shared @1;
    slave @2;
    unbindable @3;
    rprivate @4;
    rshared @5;
    rslave @6;
    runbindable @7;
}

struct MountFlags {
    readonly @0 :Bool;
    nosuid @1 :Bool;
    nodev @2 :Bool;
    noexec @3 :Bool;
    sync @4 :Bool;
    noatime @5 :Bool;
    relatime @6 :Bool;
    dirsync @7 :Bool;
    mand @8 :Bool;
    bind @9 :Bool;
    rbind @10 :Bool;
    move @11 :Bool;
    # Propagation flags.
    shared @12 :Bool;
    slave @13 :Bool;
    unbindable @14 :Bool;
}

# ─── Filesystem Info ─────────────────────────────────────────────────

struct FilesystemInfo {
    id @0 :T.FilesystemId;
    # Filesystem type.
    type @1 :Text;
    # Human-readable name.
    name @2 :Text;
    # Block size.
    blockSize @3 :UInt32;
    # Fragment size.
    fragmentSize @4 :UInt32;
    # Total blocks.
    totalBlocks @5 :UInt64;
    # Free blocks.
    freeBlocks @6 :UInt64;
    # Available blocks (for non-root).
    availableBlocks @7 :UInt64;
    # Total inodes.
    totalInodes @8 :UInt64;
    # Free inodes.
    freeInodes @9 :UInt64;
    # Filesystem ID (from statfs).
    fsId @10 :UInt64;
    # Mount flags.
    flags @11 :MountFlags;
    # Max filename length.
    maxNameLength @12 :UInt32;
    # Features supported.
    features @13 :List(FilesystemFeature);
    # Backend-specific info.
    metadata @14 :T.StringMap;
}

enum FilesystemFeature {
    journal @0;
    extents @1;
    compress @2;
    encrypt @3;
    snapshots @4;
    quotas @5;
    acl @6;
    xattr @7;
    reflink @8;
    dedup @9;
    custom @10;
}

# ─── Mount Request ────────────────────────────────────────────────────

struct MountRequest {
    # Source device/spec.
    source @0 :Text;
    # Target mount point.
    target @1 :Text;
    # Filesystem type (empty = auto-detect).
    fsType @2 :Text;
    # Mount options.
    options @3 :MountOptions;
    # Filesystem-specific mount data.
    data @4 :Text;
}

# ─── Mount Filter ────────────────────────────────────────────────────

struct MountFilter {
    # Filter by path prefix.
    pathPrefix @0 :Text;
    # Filter by filesystem type.
    fsType @1 :Text;
    # Filter by source pattern.
    sourcePattern @2 :Text;
    # Only mounted/read-only/bind/etc.
    flags @3 :MountFlags;
    # Pagination.
    page @4 :T.Pagination;
}

# ─── Mount Events ────────────────────────────────────────────────────

struct MountEvent {
    timestamp @0 :T.Timestamp;
    union {
        mounted @1 :MountPoint;
        unmounted @2 :MountUnmounted;
        remounted @3 :MountPoint;
        optionsChanged @4 :MountOptionsChanged;
        statsChanged @5 :MountStatsChanged;
        error @6 :MountError;
        custom @7 :Data;
    }
}

struct MountUnmounted {
    mountId @0 :T.MountId;
    path @1 :Text;
    forced @2 :Bool;
}

struct MountOptionsChanged {
    mountId @0 :T.MountId;
    oldOptions @1 :MountOptions;
    newOptions @2 :MountOptions;
}

struct MountStatsChanged {
    mountId @0 :T.MountId;
    oldUsed @1 :UInt64;
    newUsed @2 :UInt64;
    oldAvailable @3 :UInt64;
    newAvailable @4 :UInt64;
}

struct MountError {
    mountId @0 :T.MountId;
    operation @1 :MountOperation;
    error @2 :T.Error;
}

enum MountOperation {
    mount @0;
    unmount @1;
    remount @2;
    stat @3;
    custom @4;
}

# ─── Filesystem Check Result ─────────────────────────────────────

struct FilesystemCheckResult {
    success @0 :Bool;
    errorsFound @1 :UInt32;
    errorsFixed @2 :UInt32;
    details @3 :Text;
    duration @4 :T.Duration;
}

# ─── Known Filesystem Types ──────────────────────────────────────
# Structured filesystem type identification for cross-schema references.
# Replaces bare Text in MountPoint.fsType and FilesystemInfo.type.

enum FilesystemType {
    # Linux native
    ext2 @0;
    ext3 @1;
    ext4 @2;
    xfs @3;
    btrfs @4;
    f2fs @5;
    bcachefs @6;
    reiserfs @7;

    # Copy-on-write
    zfs @8;

    # Network filesystems
    nfs @9;
    nfs4 @10;
    cifs @11;      # SMB/CIFS
    smb @12;
    afs @13;
    ceph @14;
    glusterfs @15;
    lustre @16;
    pvfs2 @17;

    # FUSE
    fuse @18;
    fuseblk @19;

    # Windows
    ntfs @20;
    fat @21;
    fat32 @22;
    exfat @23;
    refs @24;

    # macOS
    apfs @25;
    hfs @26;
    hfsPlus @27;

    # Optical/disc
    iso9660 @28;
    udf @29;
    squashfs @30;

    # Virtual/container
    tmpfs @31;
    devtmpfs @32;
    proc @33;
    sysfs @34;
    devpts @35;
    overlay @36;
    virtiofs @37;
    v9fs @38;     # Plan 9 / 9p

    # Embedded
    romfs @39;
    cramfs @40;
    erofs @41;
    jffs2 @42;
    yaffs @43;

    custom @44;
}

# ─── Filesystem Identity (for cross-schema refs) ─────────────────────

# FilesystemId defined above. Used by storage.capnp Volume.mountPoint
# to reference the mounted filesystem.

# ─── Overlay Mount ─────────────────────────────────────────────

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
    # Priority (lower = higher priority).
    priority @6 :UInt32;
}

# ─── Network Mount Credentials ────────────────────────────────

struct NetworkMountCredentials {
    # Authentication method.
    authMethod @0 :NetworkFsAuth;
    # Username.
    username @1 :Text;
    # Password or token.
    credential @2 :Data;
    # Kerberos realm (if applicable).
    realm @3 :Text;
    # Certificate path (if certificate auth).
    certificatePath @4 :Text;
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

# ─── Mount Namespace ──────────────────────────────────────────

struct MountNamespace {
    namespaceId @0 :Text;
    # Name for display.
    name @1 :Text;
    # Number of mounts in this namespace.
    mountCount @2 :UInt32;
    # Whether this is the host namespace.
    isHost @3 :Bool;
    # Process IDs using this namespace.
    processIds @4 :List(T.ProcessId);
}

# ─── Auto-Mount Policy ───────────────────────────────────────

enum AutoMountTrigger {
    deviceInsertion @0;
    deviceRemoval @1;
    filesystemDetected @2;
    userLogin @3;
    networkAvailable @4;
    custom @5;
}

struct AutoMountPolicy {
    policyId @0 :Text;
    name @1 :Text;
    # Device pattern (e.g., "sd*", "nvme*", UUID="...").
    devicePattern @2 :Text;
    # Filesystem types to auto-mount.
    fsTypes @3 :List(Text);
    # Mount point template (e.g., "/mnt/{device}").
    mountPointTemplate @4 :Text;
    # Options for the mount.
    options @5 :MountOptions;
    # Triggers that activate this policy.
    triggers @6 :List(AutoMountTrigger);
    # Priority (lower = higher priority).
    priority @7 :UInt32;
    # Whether the policy is enabled.
    enabled @8 :Bool;
    # Device-mapper specific config (if applicable).
    dmConfig @9 :DeviceMapperConfig;
}

struct DeviceMapperConfig {
    # DM type: crypt, thin, linear, etc.
    dmType @0 :Text;
    # DM table arguments (key=value pairs).
    tableArgs @1 :T.StringMap;
}

struct AutoMountEventFilter {
    devicePattern @0 :Text;
    fsType @1 :Text;
    trigger @2 :AutoMountTrigger;
}

interface AutoMountEventSubscription {
    pull @0 () -> (events :List(AutoMountEvent));
    cancel @1 () -> T.VoidResult;
}

struct AutoMountEvent {
    timestamp @0 :T.Timestamp;
    eventType @1 :AutoMountEventType;
    device @2 :Text;
    mountPoint @3 :Text;
    fsType @4 :Text;
    error @5 :T.Error;
}

enum AutoMountEventType {
    deviceDetected @0;
    mountRequested @1;
    mountSucceeded @2;
    mountFailed @3;
    unmounted @4;
    custom @5;
}

# ─── Filesystem Resize ──────────────────────────────────────

struct FilesystemResizeRequest {
    mountId @0 :T.MountId;
    newSizeBytes @1 :UInt64;
    # Whether to grow (true) or shrink (false).
    grow @2 :Bool;
    # Force shrink even if data loss risk.
    force @3 :Bool;
}

# ─── Mount Stats Subscription ──────────────────────────────

struct MountStats {
    mountId @0 :T.MountId;
    path @1 :Text;
    totalBytes @2 :UInt64;
    usedBytes @3 :UInt64;
    availableBytes @4 :UInt64;
    inodeTotal @5 :UInt64;
    inodeUsed @6 :UInt64;
    timestamp @7 :T.Timestamp;
}

interface MountStatsSubscription {
    pull @0 () -> (stats :List(MountStats));
    cancel @1 () -> T.VoidResult;
}

# ─── Device-Mapper Mount ───────────────────────────────────

struct DeviceMapperMountRequest {
    # dm-crypt, dm-thin, dm-linear, etc.
    dmType @0 :Text;
    # Source device or logical volume.
    source @1 :Text;
    # Target mount point.
    target @2 :Text;
    # DM table arguments.
    tableArgs @3 :T.StringMap;
    # Mount options.
    options @4 :MountOptions;
    # Encryption key ID for dm-crypt.
    keyId @5 :T.KeyId;
}
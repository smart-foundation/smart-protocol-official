@0xa1b2c3d4e5f60107;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Mount — typed mount points and filesystem references.
#
# Canonical home for the mount contract. `filesystem.capnp` (deleted)
# carried a second, conflicting copy of this surface — two MountOptions
# with different fields, two MountInfo shapes, a struct-shaped MountEvent
# beside this file's union — so a consumer compiled against one could not
# consume the other. This file is the surviving shape; the overlay,
# network-mount and overlay-stats operations of the absorbed file were
# folded in here.
#
# `FilesystemInfo` and `FilesystemCheckResult` are defined here and are
# the canonical filesystem descriptors for the tree: storage.capnp and
# files.capnp reference them rather than declaring private copies.
#
# Zero backend assumptions: no /proc/mounts, no libmount, no
# FindVolume, no GetVolumeInformation, and no kernel flag names — mount
# options state INTENT (read-only, no execution), and the backend maps
# intent onto whatever mechanism it has.
#
# Used by: files.capnp (getDiskUsage), storage.capnp (volume mounts),
#          usb.capnp (removable-media mount options)
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

    # Unmount a filesystem. `force` requests immediate detachment; how the
    # backend retires pending I/O afterwards is its own business.
    unmount @4 (mountId :T.MountId, force :Bool) -> T.VoidResult;

    # Remount with different options.
    remount @5 (mountId :T.MountId, options :MountOptions) -> T.VoidResult;

    # Get filesystem info for a mount.
    getFilesystemInfo @6 (mountId :T.MountId) -> (fs :FilesystemInfo);

    # Detect filesystem type on a device.
    detectFilesystem @7 (devicePath :Text) -> (detected :FilesystemDetection);

    # Check filesystem integrity.
    checkFilesystem @8 (mountId :T.MountId, repair :Bool) -> (result :FilesystemCheckResult);

    # Subscribe to mount events.
    subscribeMounts @9 () -> (subscription :MountSubscription);

    # ─── Mount Locking ─────────────────────────────────────────

    acquireMountLock @10 (mountId :T.MountId, timeout :T.Duration) -> (lockId :UInt64);
    releaseMountLock @11 (lockId :UInt64) -> T.VoidResult;

    # ─── Auto-Mount ────────────────────────────────────────────

    enableAutoMount @12 (rule :AutoMountRule) -> (ruleId :Text);
    disableAutoMount @13 (ruleId :Text) -> T.VoidResult;
    listAutoMountRules @14 (pagination :T.Pagination) -> (rules :List(AutoMountRule), totalCount :UInt32);

    # ─── Overlay Mount ─────────────────────────────────────────

    mountOverlay @15 (request :OverlayMountRequest) -> (mount :MountPoint);
    unmountOverlay @16 (path :Text) -> T.VoidResult;
    modifyOverlay @17 (path :Text, request :OverlayMountRequest) -> T.VoidResult;
    getOverlayLayers @18 (path :Text) -> (layers :OverlayLayerInfo);
    getOverlayStats @19 (path :Text) -> (stats :OverlayMountStats);

    # ─── Mount Namespace ───────────────────────────────────────

    listMountNamespaces @20 (pagination :T.Pagination) -> (namespaces :List(MountNamespace), totalCount :UInt32);

    # ─── Auto-Mount Policy ─────────────────────────────────────

    createAutoMountPolicy @21 (policy :AutoMountPolicy) -> (policyId :Text);
    updateAutoMountPolicy @22 (policyId :Text, policy :AutoMountPolicy) -> T.VoidResult;
    deleteAutoMountPolicy @23 (policyId :Text) -> T.VoidResult;
    listAutoMountPolicies @24 (pagination :T.Pagination) -> (policies :List(AutoMountPolicy), totalCount :UInt32);

    # Subscribe to auto-mount events (device insertion, mount success/failure).
    subscribeAutoMountEvents @25 (filter :AutoMountEventFilter) -> (subscription :AutoMountEventSubscription);

    # ─── Filesystem Resize ─────────────────────────────────────

    resizeFilesystem @26 (request :FilesystemResizeRequest) -> T.VoidResult;

    # ─── Mount Stats Streaming ─────────────────────────────────

    subscribeMountStats @27 (interval :T.Duration) -> (subscription :MountStatsSubscription);
    getMountStats @28 (mountId :T.MountId) -> (stats :MountStats);

    # ─── Composed Devices ──────────────────────────────────────
    # Mount a block device composed from others (encrypted, thin-provisioned,
    # concatenated — the dmType is an open token naming the composition).

    mountComposedDevice @29 (request :ComposedDeviceRequest) -> (mount :MountPoint);
    getComposedDeviceInfo @30 (mountId :T.MountId) -> (composition :Text, tableArgs :T.StringMap);

    # ─── Network Mounts ────────────────────────────────────────
    # The protocol is an open token ("nfs", "smb", "webdav", ...): a 2046
    # network filesystem is a string, not a new ordinal. Absorbed from
    # filesystem.capnp.

    getNetworkMountInfo @31 (path :Text) -> (info :NetworkMountInfo);
}

interface MountSubscription {
    pull @0 () -> (events :List(MountEvent));
    cancel @1 () -> T.VoidResult;
}

# ─── Mount Point ─────────────────────────────────────────────────────

struct MountPoint {
    id @0 :T.MountId;
    # Mount point path (where filesystem is attached).
    path @1 :Text;
    # Source device/spec (opaque; a path, a UUID, a URI, backend-decided).
    source @2 :Text;
    # Filesystem type as an open token ("ext4", "zfs", "nfs", ...).
    fsType @3 :Text;
    # Mount options.
    options @4 :MountOptions;
    # Filesystem UUID/label.
    fsUuid @5 :T.Uuid;
    fsLabel @6 :Text;
    # Total size in bytes.
    totalSize @7 :UInt64;
    # Used space in bytes.
    usedSize @8 :UInt64;
    # Available space in bytes.
    availableSize @9 :UInt64;
    # When this was mounted.
    mountedAt @10 :T.Timestamp;
    # Backend-specific metadata.
    metadata @11 :T.StringMap;
}

# Mount options state intent. The previous struct named Linux mount(2)
# flags (nosuid, nodev, noatime, bind, rbind, propagation types), which a
# distributed, browser or capability backend can only answer with lies;
# a second struct (MountFlags) then re-declared twelve of the same
# booleans as "reported" state. One struct, intent-named, with the
# backend's own spelling preserved in `options`.
struct MountOptions {
    # Whether the mount is read-only.
    readOnly @0 :Bool;
    # Whether executables may be run from this mount.
    allowExec @1 :Bool = true;
    # Whether device nodes on this mount are honored.
    allowDeviceNodes @2 :Bool = true;
    # Whether privilege-escalation semantics apply to executables here.
    allowPrivilegeEscalation @3 :Bool = true;
    # Whether writes are committed synchronously.
    synchronous @4 :Bool;
    # Access-time update policy as an open token ("noatime", "relatime", ...).
    accessTimePolicy @5 :Text;
    # Whether this mount shares state with its source (bind-like intent).
    sharesSource @6 :Bool;
    # Backend/implementation-specific options, reported and accepted as data.
    options @7 :T.StringMap;
}

# ─── Filesystem Info ─────────────────────────────────────────────────
# Canonical filesystem descriptor (see the file header). Capacity is
# reported in bytes; block and inode counts, the statfs fs id and the
# fragment size were filesystem internals a non-POSIX backend had to
# fabricate, and are gone.

struct FilesystemInfo {
    id @0 :T.FilesystemId;
    # Filesystem type as an open token.
    type @1 :Text;
    # Human-readable name.
    name @2 :Text;
    # Block size in bytes.
    blockSize @3 :UInt32;
    # Total size in bytes.
    totalSize @4 :UInt64;
    # Free space in bytes.
    freeSize @5 :UInt64;
    # Available space in bytes (for unprivileged users).
    availableSize @6 :UInt64;
    # Max filename length.
    maxNameLength @7 :UInt32;
    # Open feature tokens ("journal", "compress", "snapshots", ...).
    features @8 :List(Text);
    # Backend-specific info.
    metadata @9 :T.StringMap;
}

struct FilesystemDetection {
    fsType @0 :Text;
    label @1 :Text;
    uuid @2 :T.Uuid;
    metadata @3 :T.StringMap;
}

# ─── Filesystem Check Result ─────────────────────────────────────────
# Canonical check-result contract (storage.capnp references this type
# instead of declaring a byte-identical copy).

struct FilesystemCheckResult {
    success @0 :Bool;
    errorsFound @1 :UInt32;
    errorsFixed @2 :UInt32;
    details @3 :Text;
    duration @4 :T.Duration;
    metadata @5 :T.StringMap;
}

# ─── Mount Request ────────────────────────────────────────────────────

struct MountRequest {
    # Source device/spec (opaque).
    source @0 :Text;
    # Target mount point.
    target @1 :Text;
    # Filesystem type (empty = auto-detect).
    fsType @2 :Text;
    # Mount options.
    options @3 :MountOptions;
    # Filesystem-specific mount data (opaque).
    mountData @4 :Data;
}

# ─── Mount Filter ────────────────────────────────────────────────────

struct MountFilter {
    pathPrefix @0 :Text;
    fsType @1 :Text;
    sourcePattern @2 :Text;
    options @3 :MountOptions;
    page @4 :T.Pagination;
    annotations @5 :T.StringMap;
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
    metadata @3 :T.StringMap;
}

struct MountOptionsChanged {
    mountId @0 :T.MountId;
    oldOptions @1 :MountOptions;
    newOptions @2 :MountOptions;
    metadata @3 :T.StringMap;
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
    metadata @3 :T.StringMap;
}

enum MountOperation {
    unknown @0;
    mount @1;
    unmount @2;
    remount @3;
    stat @4;
    custom @5;
}

# ─── Overlay Mount ─────────────────────────────────────────────

enum OverlayIndexMode {
    unknown @0;
    auto @1;
    on @2;
    off @3;
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
    metadata @6 :T.StringMap;
}

struct OverlayLayerInfo {
    upperDir @0 :Text;
    lowerDirs @1 :List(Text);
    workDir @2 :Text;
    indexMode @3 :OverlayIndexMode;
    upperFileCount @4 :UInt64;
    metadata @5 :T.StringMap;
}

struct OverlayMountStats {
    path @0 :Text;
    upperFileCount @1 :UInt64;
    lowerFileCount @2 :UInt64;
    upperSize @3 :UInt64;
    totalSize @4 :UInt64;
    copyUpCount @5 :UInt64;
    metadata @6 :T.StringMap;
}

# ─── Auto-Mount Rules ─────────────────────────────────────────

struct AutoMountRule {
    ruleId @0 :Text;
    # Device pattern (opaque; backend-decided glob).
    devicePattern @1 :Text;
    # Filesystem type to auto-mount (open token).
    fsType @2 :Text;
    # Target mount point template.
    mountPoint @3 :Text;
    # Mount options.
    options @4 :MountOptions;
    # Whether rule is enabled.
    enabled @5 :Bool;
    # Priority (lower = higher priority).
    priority @6 :UInt32;
    metadata @7 :T.StringMap;
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
    # Processes using this namespace.
    processIds @4 :List(T.ProcessId);
    metadata @5 :T.StringMap;
}

# ─── Auto-Mount Policy ───────────────────────────────────────

enum AutoMountTrigger {
    unknown @0;
    deviceInsertion @1;
    deviceRemoval @2;
    filesystemDetected @3;
    userLogin @4;
    networkAvailable @5;
    custom @6;
}

struct AutoMountPolicy {
    policyId @0 :Text;
    name @1 :Text;
    # Device pattern (opaque; backend-decided glob).
    devicePattern @2 :Text;
    # Filesystem types to auto-mount (open tokens).
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
    # Composition config, when the device is composed (see ComposedDeviceRequest).
    composition @9 :CompositionConfig;
    metadata @10 :T.StringMap;
}

struct CompositionConfig {
    # Composition kind as an open token ("encrypted", "thin", "concatenated", ...).
    kind @0 :Text;
    # Composition table arguments.
    tableArgs @1 :T.StringMap;
}

struct AutoMountEventFilter {
    devicePattern @0 :Text;
    fsType @1 :Text;
    trigger @2 :AutoMountTrigger;
    metadata @3 :T.StringMap;
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
    metadata @6 :T.StringMap;
}

enum AutoMountEventType {
    unknown @0;
    deviceDetected @1;
    mountRequested @2;
    mountSucceeded @3;
    mountFailed @4;
    unmounted @5;
    custom @6;
}

# ─── Filesystem Resize ──────────────────────────────────────

struct FilesystemResizeRequest {
    mountId @0 :T.MountId;
    newSizeBytes @1 :UInt64;
    # Whether to grow (true) or shrink (false).
    grow @2 :Bool;
    # Whether to shrink despite the risk of data loss. The backend refuses
    # rather than guessing; the flag records the caller's acknowledgement.
    acceptDataLossRisk @3 :Bool;
}

# ─── Mount Stats Subscription ──────────────────────────────

struct MountStats {
    mountId @0 :T.MountId;
    path @1 :Text;
    totalBytes @2 :UInt64;
    usedBytes @3 :UInt64;
    availableBytes @4 :UInt64;
    timestamp @5 :T.Timestamp;
    metadata @6 :T.StringMap;
}

interface MountStatsSubscription {
    pull @0 () -> (stats :List(MountStats));
    cancel @1 () -> T.VoidResult;
}

# ─── Composed Devices ───────────────────────────────────────

struct ComposedDeviceRequest {
    # Composition kind as an open token ("encrypted", "thin", "concatenated", ...).
    kind @0 :Text;
    # Source device or logical volume (opaque).
    source @1 :Text;
    # Target mount point.
    target @2 :Text;
    # Composition table arguments.
    tableArgs @3 :T.StringMap;
    # Mount options.
    options @4 :MountOptions;
    # Key for an encrypted composition (a reference, not key material).
    keyId @5 :T.KeyId;
}

# ─── Network Mounts ─────────────────────────────────────────
# Absorbed from filesystem.capnp. Protocol and authentication are open
# tokens: "nfs", "smb", "webdav", "none", "kerberos", "token" — a 2046
# network filesystem or auth mechanism is a string with
# unknown-tolerance.

struct NetworkMountInfo {
    protocol @0 :Text;
    server @1 :Text;
    share @2 :Text;
    authMethod @3 :Text;
    transport @4 :Text;
    timeout @5 :T.Duration;
    reconnect @6 :Bool;
    metadata @7 :T.StringMap;
}

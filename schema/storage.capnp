@0xa1b2c3d4e5f60103;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Storage — block device management, LVM/RAID, storage pools.
#
# Zero backend assumptions: no LVM, no mdadm, no ZFS, no Btrfs,
# no Storage Spaces, no VxVM. Backend provides storage management;
# protocol defines the contract.
#
# hal.capnp covers hardware; this covers OS-level storage pools.
#
# Used by: filesystem.capnp (mount sources), device.capnp (storage devices)
# ═══════════════════════════════════════════════════════════════════════

interface StorageService {
    # List all block devices.
    listDevices @0 (filter :DeviceFilter, pagination :T.Pagination) -> (devices :List(BlockDevice), totalCount :UInt32);

    # Get detailed info for a block device.
    getDevice @1 (deviceId :T.DeviceId) -> (device :BlockDevice);

    # List all storage pools.
    listPools @2 (pagination :T.Pagination) -> (pools :List(StoragePool), totalCount :UInt32);

    # Get detailed info for a storage pool.
    getPool @3 (poolId :T.StoragePoolId) -> (pool :StoragePool);

    # Create a new storage pool.
    createPool @4 (request :CreatePoolRequest) -> (pool :StoragePool);

    # Resize a storage pool (add/remove devices).
    resizePool @5 (poolId :T.StoragePoolId, request :ResizePoolRequest) -> T.VoidResult;

    # Delete a storage pool.
    deletePool @6 (poolId :T.StoragePoolId, force :Bool) -> T.VoidResult;

    # Create a volume in a pool.
    createVolume @7 (request :CreateVolumeRequest) -> (volume :Volume);

    # Resize a volume.
    resizeVolume @8 (volumeId :T.VolumeId, newSize :UInt64) -> T.VoidResult;

    # Delete a volume.
    deleteVolume @9 (volumeId :T.VolumeId, force :Bool) -> T.VoidResult;

    # List volumes in a pool.
    listVolumes @10 (poolId :T.StoragePoolId, pagination :T.Pagination) -> (volumes :List(Volume), totalCount :UInt32);

    # Get volume info.
    getVolume @11 (volumeId :T.VolumeId) -> (volume :Volume);

    # Create a snapshot of a volume.
    createSnapshot @12 (volumeId :T.VolumeId, name :Text) -> (snapshot :Snapshot);

    # List snapshots of a volume.
    listSnapshots @13 (volumeId :T.VolumeId, pagination :T.Pagination) -> (snapshots :List(Snapshot), totalCount :UInt32);

    # Rollback a volume to a snapshot.
    rollbackSnapshot @14 (volumeId :T.VolumeId, snapshotId :T.SnapshotId) -> T.VoidResult;

    # Delete a snapshot.
    deleteSnapshot @15 (snapshotId :T.SnapshotId) -> T.VoidResult;

    # Check and repair filesystem on a volume.
    checkFilesystem @16 (volumeId :T.VolumeId, repair :Bool) -> (result :FilesystemCheckResult);

    # Get SMART data for a block device.
    getSmartData @17 (deviceId :T.DeviceId) -> (smart :SmartData);

    # Run SMART self-test.
    runSmartTest @18 (deviceId :T.DeviceId, type :SmartTestType) -> (testId :Text);

    # Get SMART test results.
    getSmartTestResults @19 (deviceId :T.DeviceId) -> (results :List(SmartTestResult));

    # Subscribe to storage events (device added/removed, pool state changes, etc.).
    subscribeStorage @20 () -> (subscription :StorageSubscription);

    # Get I/O statistics for a device or pool.
    getIoStats @21 (target :IoStatsTarget, duration :T.Duration) -> (stats :IoStats);

    # Initiate a scrub on a storage pool (ZFS, btrfs).
    scrubPool @22 (poolId :T.StoragePoolId) -> (scrubId :Text);

    # Get scrub progress for a pool.
    getScrubProgress @23 (poolId :T.StoragePoolId) -> (progress :ScrubProgress);

    # Manage cache tier on a pool (add/remove cache device).
    manageCacheTier @24 (poolId :T.StoragePoolId, request :CacheTierRequest) -> T.VoidResult;

    # Partition a disk (create/modify/delete partition table).
    partitionDisk @25 (request :PartitionDiskRequest) -> (result :PartitionDiskResult);

    # Encrypt a volume (LUKS/dm-crypt).
    encryptVolume @26 (request :EncryptVolumeRequest) -> T.VoidResult;

    # ─── RAID Rebuild ──────────────────────────────────────────

    # Initiate RAID rebuild on a degraded pool.
    rebuildPool @27 (poolId :T.StoragePoolId, failedDevice :T.DeviceId, replacementDevice :T.DeviceId) -> (rebuildId :Text);

    # Get RAID rebuild progress.
    getRebuildProgress @28 (poolId :T.StoragePoolId) -> (progress :RebuildProgress);

    # ─── Thin Pool Management ──────────────────────────────────

    # Create a thin pool.
    createThinPool @29 (request :CreateThinPoolRequest) -> (pool :StoragePool);

    # Resize a thin volume.
    resizeThinVolume @30 (volumeId :T.VolumeId, newSize :UInt64) -> T.VoidResult;

    # Get thin pool statistics.
    getThinPoolStats @31 (poolId :T.StoragePoolId) -> (stats :ThinPoolStats);

    # ─── Device Replacement ────────────────────────────────────

    # Replace a failed device in a pool (hot-swap).
    replaceDevice @32 (poolId :T.StoragePoolId, failedDevice :T.DeviceId, newDevice :T.DeviceId) -> T.VoidResult;

    # ─── Pool Export / Import ──────────────────────────────────

    # Export a pool (make it portable).
    exportPool @33 (poolId :T.StoragePoolId) -> (exportData :T.DataHandle);

    # Import a pool from exported data.
    importPool @34 (request :ImportPoolRequest) -> (pool :StoragePool);

    # ─── Volume Clone ──────────────────────────────────────────

    # Create an instant copy (clone) of a volume.
    cloneVolume @35 (request :CloneVolumeRequest) -> (volume :Volume);

    # ─── Volume Migration ──────────────────────────────────────

    # Live-migrate a volume between pools/devices.
    migrateVolume @36 (request :MigrateVolumeRequest) -> (migrationId :Text);

    # Get migration progress.
    getMigrationProgress @37 (migrationId :Text) -> (progress :MigrationProgress);

    # ─── Storage Tiering ───────────────────────────────────────

    # Manage storage tier assignment for a volume.
    manageStorageTier @38 (request :StorageTierRequest) -> T.VoidResult;

    # Get current tier status for a volume.
    getStorageTierStatus @39 (volumeId :T.VolumeId) -> (status :StorageTierStatus);

    # ─── Replication ───────────────────────────────────────────

    # Set up async/sync replication between pools.
    replicatePool @40 (request :ReplicatePoolRequest) -> (replicationId :Text);

    # Get replication status.
    getReplicationStatus @41 (replicationId :Text) -> (status :ReplicationStatus);

    # Stop replication.
    stopReplication @42 (replicationId :Text) -> T.VoidResult;

    # ─── I/O Stats Streaming ───────────────────────────────────

    # Subscribe to real-time I/O statistics.
    subscribeIoStats @43 (target :IoStatsTarget, interval :T.Duration) -> (subscription :IoStatsSubscription);

    # ─── Encryption Key Management ─────────────────────────────

    # Change encryption key for a volume.
    changeEncryptionKey @44 (volumeId :T.VolumeId, oldKeyId :T.KeyId, newKeyId :T.KeyId) -> T.VoidResult;

    # Get encryption status for a volume.
    getEncryptionStatus @45 (volumeId :T.VolumeId) -> (status :EncryptionStatus);

    # ─── Deduplication Stats ────────────────────────────────────

    # Get deduplication statistics for a storage pool.
    getDeduplicationStats @46 (poolId :T.StoragePoolId) -> (stats :PoolDeduplicationStats);

    # ─── Compression Monitoring ─────────────────────────────────

    # Get compression statistics for a storage pool.
    getCompressionStats @47 (poolId :T.StoragePoolId) -> (stats :PoolCompressionStats);

    # ─── Historical I/O Stats Streaming ────────────────────────

    # Subscribe to historical I/O statistics with trends.
    subscribeHistoricalIoStats @48 (target :IoStatsTarget, interval :T.Duration, window :T.Duration)
        -> (subscription :HistoricalIoStatsSubscription);

    # ─── Volume-Level Deduplication Stats (audit-10) ─────────

    # Get deduplication statistics for a volume (not just pool).
    getVolumeDeduplicationStats @49 (volumeId :T.VolumeId) -> (stats :VolumeDeduplicationStats);

    # ─── Volume-Level Compression Stats (audit-10) ───────────

    # Get compression statistics for a volume (not just pool).
    getVolumeCompressionStats @50 (volumeId :T.VolumeId) -> (stats :VolumeCompressionStats);
}

interface StorageSubscription {
    pull @0 () -> (events :List(StorageEvent));
    cancel @1 () -> T.VoidResult;
}

# ─── Block Device ────────────────────────────────────────────────────

struct BlockDevice {
    id @0 :T.DeviceId;
    # Kernel/sysfs name (e.g., "sda", "nvme0n1", "mmcblk0").
    name @1 :Text;
    # Human-readable name (e.g., "Samsung SSD 970 EVO 1TB").
    model @2 :Text;
    # Serial number.
    serial @3 :Text;
    # Firmware revision.
    firmware @4 :Text;
    # Size in bytes.
    size @5 :UInt64;
    # Sector size in bytes (typically 512 or 4096).
    sectorSize @6 :UInt32;
    # Physical sector size in bytes.
    physicalSectorSize @7 :UInt32;
    # Device type.
    type @8 :BlockDeviceType;
    # Bus/interface type.
    bus @9 :BusType;
    # WWN (World Wide Name) for SCSI/FC devices.
    wwn @10 :Text;
    # NUMA node.
    numaNode @11 :Int32;
    # Rotational media (true = HDD, false = SSD/NVMe).
    rotational @12 :Bool;
    # Removable media.
    removable @13 :Bool;
    # Read-only.
    readOnly @14 :Bool;
    # Current I/O scheduler.
    scheduler @15 :Text;
    # Partition table type.
    partitionTable @16 :PartitionTableType;
    # Partitions on this device.
    partitions @17 :List(Partition);
    # SMART health status.
    smartStatus @18 :SmartHealthStatus;
    # Temperature in Celsius (if supported).
    temperatureCelsius @19 :Int32;
    # Power-on hours.
    powerOnHours @20 :UInt64;
    # Backend-specific metadata.
    metadata @21 :T.StringMap;
}

enum BlockDeviceType {
    unknown @0;
    disk @1;           # HDD, SSD, NVMe
    partition @2;
    loop @3;           # Loopback device
    ram @4;            # Ramdisk
    floppy @5;
    cdrom @6;
    tape @7;
    crypt @8;          # dm-crypt / LUKS
    lvm @9;            # LVM logical volume
    md @10;            # Linux md RAID
    zfs @11;           # ZFS zvol
    btrfs @12;         # Btrfs subvolume
    vhd @13;           # Virtual hard disk
    custom @14;
}

enum BusType {
    unknown @0;
    scsi @1;
    ata @2;
    sata @3;
    nvme @4;
    usb @5;
    sd @6;
    mmc @7;
    virtio @8;
    spdk @9;
    nbd @10;           # Network block device
    rbd @11;           # Ceph RBD
    iscsi @12;
    fc @13;            # Fibre Channel
    aoe @14;           # ATA over Ethernet
    custom @15;
}

enum PartitionTableType {
    none @0;
    mbr @1;
    gpt @2;
    bsd @3;
    sun @4;
    sgI @5;
    custom @6;
}

struct Partition {
    # Partition number (1-based).
    number @0 :UInt32;
    # Start sector.
    start @1 :UInt64;
    # Size in sectors.
    size @2 :UInt64;
    # Size in bytes.
    sizeBytes @3 :UInt64;
    # Partition type GUID/ID.
    typeGuid @4 :Text;
    # Partition label/name.
    label @5 :Text;
    # UUID.
    uuid @6 :Text;
    # Flags (boot, esp, lvm, raid, etc.).
    flags @7 :List(PartitionFlag);
    # Filesystem on this partition (if detected).
    filesystem @8 :FilesystemInfo;
}

enum PartitionFlag {
    boot @0;
    esp @1;           # EFI System Partition
    lvm @2;
    raid @3;
    swap @4;
    hidden @5;
    readonly @6;
    custom @7;
}

# ─── Storage Pool ────────────────────────────────────────────────────

struct StoragePoolId { id @0 :UInt64; }

struct StoragePool {
    id @0 :T.StoragePoolId;
    name @1 :Text;
    # Pool type / backend.
    type @2 :PoolType;
    # Devices composing this pool.
    devices @3 :List(T.DeviceId);
    # Total capacity in bytes.
    capacity @4 :UInt64;
    # Used space in bytes.
    used @5 :UInt64;
    # Available space in bytes.
    available @6 :UInt64;
    # Redundancy level.
    redundancy @7 :RedundancyLevel;
    # Pool state.
    state @8 :PoolState;
    # Filesystem type (if pool has a default fs).
    defaultFilesystem @9 :Text;
    # Encryption status.
    encrypted @10 :Bool;
    encryptionAlgorithm @11 :Text;
    # Compression.
    compression @12 :Text;
    # Deduplication.
    deduplication @13 :Bool;
    # Thin provisioning.
    thinProvisioned @14 :Bool;
    # Mount point (if mounted).
    mountPoint @15 :Text;
    # Volume count.
    volumeCount @16 :UInt32;
    # Snapshot count.
    snapshotCount @17 :UInt32;
    # Created timestamp.
    createdAt @18 :T.Timestamp;
    # Backend-specific metadata.
    metadata @19 :T.StringMap;
}

enum PoolType {
    unknown @0;
    lvm @1;            # LVM volume group
    mdraid @2;         # Linux md RAID
    zfs @3;            # ZFS zpool
    btrfs @4;          # Btrfs pool
    storagespaces @5;  # Windows Storage Spaces
    stratis @6;        # Stratis pool
    vdo @7;            # VDO (dedup/compression)
    bcache @8;         # bcache/bcachefs
    # Ceph distributed storage
    ceph @9;
    # GlusterFS volume
    gluster @10;
    # NetApp ONTAP
    ontap @11;
    # Veritas Volume Manager
    vvm @12;
    # Solaris ZFS (if distinct from Linux ZFS)
    illumosZfs @13;
    # VMware VMFS
    vmfs @14;
    # NVMe-oF namespace
    nvmeof @15;
    # Custom backend
    custom @16;
}

enum RedundancyLevel {
    none @0;           # No redundancy (JBOD, stripe)
    mirror @1;         # Mirror (RAID 1)
    raid5 @2;          # RAID 5 (single parity)
    raid6 @3;          # RAID 6 (dual parity)
    raid10 @4;         # RAID 10 (mirrored stripes)
    raidz1 @5;         # ZFS RAID-Z1
    raidz2 @6;         # ZFS RAID-Z2
    raidz3 @7;         # ZFS RAID-Z3
    custom @8;
}

enum PoolState {
    unknown @0;
    creating @1;
    healthy @2;
    degraded @3;       # One or more devices failed
    failed @4;         # Pool non-functional
    resyncing @5;      # Rebuilding/rebalancing
    scrubbing @6;      # Data integrity check in progress
    expanding @7;      # Adding capacity
    shrinking @8;      # Removing capacity
    suspended @9;      # I/O suspended
    offline @10;
    custom @11;
}

# ─── Volume ──────────────────────────────────────────────────────────

struct VolumeId { id @0 :UInt64; }

struct Volume {
    id @0 :T.VolumeId;
    name @1 :Text;
    poolId @2 :T.StoragePoolId;
    # Size in bytes.
    size @3 :UInt64;
    # Used space in bytes (if fs supports it).
    used @4 :UInt64;
    # Volume type.
    type @5 :VolumeType;
    # Filesystem.
    filesystem @6 :Text;
    # Mount point (if mounted).
    mountPoint @7 :Text;
    # Volume state.
    state @8 :VolumeState;
    # Encryption.
    encrypted @9 :Bool;
    encryptionAlgorithm @10 :Text;
    # Compression.
    compression @11 :Text;
    # Thin provisioned.
    thinProvisioned @12 :Bool;
    # Snapshot count.
    snapshotCount @13 :UInt32;
    # Created timestamp.
    createdAt @14 :T.Timestamp;
    # Labels/tags.
    labels @15 :T.StringMap;
    # Backend-specific metadata.
    metadata @16 :T.StringMap;
}

enum VolumeType {
    unknown @0;
    linear @1;         # Linear allocation
    striped @2;        # Striped across devices
    mirrored @3;       # Mirrored
    raid5 @4;          # RAID 5
    raid6 @5;          # RAID 6
    thin @6;           # Thin provisioned
    cache @7;          # Cache volume
    log @8;            # Log volume
    custom @9;
}

enum VolumeState {
    unknown @0;
    creating @1;
    active @2;
    inactive @3;
    suspended @4;
    degraded @5;
    failed @6;
    resyncing @7;
    custom @8;
}

# ─── Snapshot ────────────────────────────────────────────────────────

struct SnapshotId { id @0 :UInt64; }

struct Snapshot {
    id @0 :T.SnapshotId;
    name @1 :Text;
    volumeId @2 :T.VolumeId;
    # Size in bytes (for thick snapshots).
    size @3 :UInt64;
    # Used space in bytes.
    used @4 :UInt64;
    # Snapshot state.
    state @5 :SnapshotState;
    # Created timestamp.
    createdAt @6 :T.Timestamp;
    # Whether this is a read-only snapshot.
    readonly @7 :Bool;
    # Parent snapshot (for hierarchical snapshots).
    parentSnapshotId @8 :T.SnapshotId;
    # Labels/tags.
    labels @9 :T.StringMap;
    # Backend-specific metadata.
    metadata @10 :T.StringMap;
}

enum SnapshotState {
    unknown @0;
    creating @1;
    active @2;
    merging @3;        # Merging back into origin
    failed @4;
    custom @5;
}

# ─── Requests ────────────────────────────────────────────────────────

struct CreatePoolRequest {
    name @0 :Text;
    type @1 :PoolType;
    devices @2 :List(T.DeviceId);
    redundancy @3 :RedundancyLevel;
    # Filesystem to create on pool.
    filesystem @4 :Text;
    # Encryption.
    encrypt @5 :Bool;
    encryptionAlgorithm @6 :Text;
    # Compression.
    compression @7 :Text;
    # Deduplication.
    deduplication @8 :Bool;
    # Thin provisioning.
    thinProvisioned @9 :Bool;
    # Mount point.
    mountPoint @10 :Text;
    # Labels.
    labels @11 :T.StringMap;
    # Backend-specific options.
    options @12 :T.StringMap;
}

struct ResizePoolRequest {
    # Devices to add.
    addDevices @0 :List(T.DeviceId);
    # Devices to remove (must be empty/unused).
    removeDevices @1 :List(T.DeviceId);
    # New redundancy level (if changing).
    newRedundancy @2 :RedundancyLevel;
    # Force removal even if data movement required.
    force @3 :Bool;
}

struct CreateVolumeRequest {
    name @0 :Text;
    poolId @1 :T.StoragePoolId;
    size @2 :UInt64;
    type @3 :VolumeType;
    filesystem @4 :Text;
    encrypt @5 :Bool;
    encryptionAlgorithm @6 :Text;
    compression @7 :Text;
    thinProvisioned @8 :Bool;
    mountPoint @9 :Text;
    labels @10 :T.StringMap;
    options @11 :T.StringMap;
}

# ─── Filesystem Info ─────────────────────────────────────────────────

struct FilesystemInfo {
    type @0 :Text;           # ext4, xfs, btrfs, zfs, ntfs, fat32, etc.
    label @1 :Text;
    uuid @2 :Text;
    size @3 :UInt64;
    used @4 :UInt64;
    available @5 :UInt64;
    mountPoint @6 :Text;
    mountOptions @7 :List(Text);
    features @8 :List(Text);  # Filesystem-specific features
    lastChecked @9 :T.Timestamp;
    state @10 :FilesystemState;
}

enum FilesystemState {
    unknown @0;
    clean @1;
    dirty @2;
    error @3;
    checking @4;
    custom @5;
}

struct FilesystemCheckResult {
    success @0 :Bool;
    errorsFound @1 :UInt32;
    errorsFixed @2 :UInt32;
    details @3 :Text;
    duration @4 :T.Duration;
}

# ─── SMART Data ──────────────────────────────────────────────────────

struct SmartData {
    deviceId @0 :T.DeviceId;
    # Overall health assessment.
    health @1 :SmartHealthStatus;
    # Raw SMART attributes.
    attributes @2 :List(SmartAttribute);
    # Temperature in Celsius.
    temperatureCelsius @3 :Int32;
    # Power-on hours.
    powerOnHours @4 :UInt64;
    # Power cycle count.
    powerCycleCount @5 :UInt64;
    # Last self-test timestamp.
    lastTestTime @6 :T.Timestamp;
    # Last self-test result.
    lastTestResult @7 :SmartTestResult;
}

enum SmartHealthStatus {
    unknown @0;
    passed @1;
    failed @2;
    failing @3;       # Pre-fail attributes exceeded threshold
    custom @4;
}

struct SmartAttribute {
    id @0 :UInt8;              # SMART attribute ID (1-255)
    name @1 :Text;             # Attribute name
    value @2 :UInt8;           # Current normalized value (1-253)
    worst @3 :UInt8;           # Worst recorded value
    threshold @4 :UInt8;       # Failure threshold
    raw @5 :UInt64;            # Raw value
    flags @6 :UInt16;          # Attribute flags
    # Whether value is below threshold (pre-fail).
    failing @7 :Bool;
}

enum SmartTestType {
    short @0;        # Short self-test (~2 minutes)
    long @1;         # Extended self-test (~hours)
    conveyance @2;   # Conveyance test (for shipping)
    selective @3;    # Selective test (specific LBAs)
    custom @4;
}

struct SmartTestResult {
    type @0 :SmartTestType;
    status @1 :SmartTestStatus;
    progressPercent @2 :UInt8;
    startTime @3 :T.Timestamp;
    endTime @4 :T.Timestamp;
    # LBA of first error (if any).
    errorLba @5 :UInt64;
}

enum SmartTestStatus {
    unknown @0;
    running @1;
    completed @2;
    aborted @3;
    failed @4;
    custom @5;
}

# ─── I/O Statistics ──────────────────────────────────────────────────

struct IoStatsTarget {
    union {
        device @0 :T.DeviceId;
        pool @1 :T.StoragePoolId;
        volume @2 :T.VolumeId;
    }
}

struct IoStats {
    target @0 :IoStatsTarget;
    duration @1 :T.Duration;
    # Read statistics.
    reads @2 :UInt64;
    readBytes @3 :UInt64;
    readTime @4 :T.Duration;
    # Write statistics.
    writes @5 :UInt64;
    writeBytes @6 :UInt64;
    writeTime @7 :T.Duration;
    # Discard/trim statistics.
    discards @8 :UInt64;
    discardBytes @9 :UInt64;
    discardTime @10 :T.Duration;
    # Flush statistics.
    flushes @11 :UInt64;
    flushTime @12 :T.Duration;
    # Queue depth.
    avgQueueDepth @13 :Float32;
    maxQueueDepth @14 :UInt32;
    # Latency percentiles (microseconds).
    readLatencyP50 @15 :UInt32;
    readLatencyP95 @16 :UInt32;
    readLatencyP99 @17 :UInt32;
    writeLatencyP50 @18 :UInt32;
    writeLatencyP95 @19 :UInt32;
    writeLatencyP99 @20 :UInt32;
    # Errors.
    readErrors @21 :UInt64;
    writeErrors @22 :UInt64;
    # Timestamp of stats collection.
    collectedAt @23 :T.Timestamp;
}

# ─── Storage Events ──────────────────────────────────────────────────

struct StorageEvent {
    timestamp @0 :T.Timestamp;
    union {
        deviceAdded @1 :T.DeviceId;
        deviceRemoved @2 :T.DeviceId;
        deviceFailed @3 :DeviceFailed;
        poolCreated @4 :T.StoragePoolId;
        poolDeleted @5 :T.StoragePoolId;
        poolStateChanged @6 :PoolStateChanged;
        volumeCreated @7 :T.VolumeId;
        volumeDeleted @8 :T.VolumeId;
        volumeMounted @9 :VolumeMounted;
        volumeUnmounted @10 :VolumeUnmounted;
        snapshotCreated @11 :T.SnapshotId;
        snapshotDeleted @12 :T.SnapshotId;
        smartThresholdExceeded @13 :SmartThresholdExceeded;
        custom @14 :Data;
    }
}

struct DeviceFailed {
    deviceId @0 :T.DeviceId;
    reason @1 :Text;
    smartData @2 :SmartData;
}

struct PoolStateChanged {
    poolId @0 :T.StoragePoolId;
    oldState @1 :PoolState;
    newState @2 :PoolState;
}

struct VolumeMounted {
    volumeId @0 :T.VolumeId;
    mountPoint @1 :Text;
}

struct VolumeUnmounted {
    volumeId @0 :T.VolumeId;
    mountPoint @1 :Text;
}

struct SmartThresholdExceeded {
    deviceId @0 :T.DeviceId;
    attribute @1 :SmartAttribute;
}

# ─── Filters ─────────────────────────────────────────────────────────

struct DeviceFilter {
    type @0 :BlockDeviceType;
    bus @1 :BusType;
    namePattern @2 :Text;
    minSize @3 :UInt64;
    maxSize @4 :UInt64;
    rotational @5 :Bool;
    removable @6 :Bool;
    smartStatus @7 :SmartHealthStatus;
}

# ─── Scrub Operations ────────────────────────────────────────────

struct ScrubProgress {
    poolId @0 :T.StoragePoolId;
    # Bytes scanned so far.
    bytesScanned @1 :UInt64;
    # Total bytes to scan.
    totalBytes @2 :UInt64;
    # Errors found during scrub.
    errorsFound @3 :UInt32;
    # Errors repaired.
    errorsRepaired @4 :UInt32;
    # Whether scrub is complete.
    complete @5 :Bool;
    # Start timestamp.
    startedAt @6 :T.Timestamp;
    # Estimated completion.
    estimatedCompletion @7 :T.Timestamp;
}

# ─── Cache Tier Management ───────────────────────────────────────

struct CacheTierRequest {
    union {
        add @0 :CacheTierAdd;
        remove @1 :CacheTierRemove;
        status @2 :Void;
    }
}

struct CacheTierAdd {
    # Devices to use as cache.
    devices @0 :List(T.DeviceId);
    # Cache mode (write-back, write-through).
    mode @1 :CacheMode;
    # Cache size (0 = auto).
    cacheSize @2 :UInt64;
}

struct CacheTierRemove {
    # Devices to remove from cache tier.
    devices @0 :List(T.DeviceId);
    # Force removal even if cache is dirty.
    force @1 :Bool;
}

enum CacheMode {
    writeBack @0;     # Writes go to cache first, flushed later
    writeThrough @1;  # Writes go to both cache and backing device
    readAhead @2;     # Only read caching
    custom @3;
}

# ─── Partition Operations ────────────────────────────────────────

struct PartitionDiskRequest {
    # Device to partition.
    deviceId @0 :T.DeviceId;
    # Partition table type to create.
    tableType @1 :PartitionTableType;
    # Partitions to create.
    partitions @2 :List(PartitionCreate);
    # Wipe existing partition table first.
    wipe @3 :Bool = true;
}

struct PartitionCreate {
    # Start sector (0 = auto).
    startSector @0 :UInt64;
    # Size in sectors or bytes (0 = fill remaining).
    sizeSectors @1 :UInt64;
    # Partition type GUID (GPT) or hex ID (MBR).
    typeGuid @2 :Text;
    # Human-readable label.
    label @3 :Text;
    # Flags to set.
    flags @4 :List(PartitionFlag);
}

struct PartitionDiskResult {
    success @0 :Bool;
    partitions @1 :List(Partition);
    errors @2 :List(T.Error);
}

# ─── Volume Encryption ───────────────────────────────────────────

struct EncryptVolumeRequest {
    # Volume to encrypt.
    volumeId @0 :T.VolumeId;
    # Encryption method.
    method @1 :EncryptionMethod;
    # Key ID from crypto.capnp key management (replaces bare Data).
    keyId @2 :T.KeyId;
    # Cipher to use (empty = backend default).
    cipher @3 :Text;
    # Key size in bits (e.g., 256).
    keySize @4 :UInt32;
}

enum EncryptionMethod {
    luks1 @0;         # LUKS version 1
    luks2 @1;         # LUKS version 2
    bitlocker @2;     # Windows BitLocker
    filevault @3;     # macOS FileVault
    custom @4;
}

# ─── RAID Rebuild ─────────────────────────────────────────────

struct RebuildProgress {
    poolId @0 :T.StoragePoolId;
    # Percentage complete (0.0 - 100.0).
    percentComplete @1 :Float32;
    # Bytes rebuilt so far.
    bytesRebuilt @2 :UInt64;
    # Total bytes to rebuild.
    totalBytes @3 :UInt64;
    # Estimated time remaining.
    estimatedRemaining @4 :T.Duration;
    # Speed in bytes per second.
    speed @5 :UInt64;
    # Start timestamp.
    startedAt @6 :T.Timestamp;
}

# ─── Thin Pool Management ─────────────────────────────────────

struct CreateThinPoolRequest {
    name @0 :Text;
    poolId @1 :T.StoragePoolId;
    # Virtual size (may exceed physical — thin provisioned).
    virtualSize @2 :UInt64;
    # Metadata size.
    metadataSize @3 :UInt64;
    # Labels.
    labels @4 :T.StringMap;
}

struct ThinPoolStats {
    poolId @0 :T.StoragePoolId;
    # Total virtual capacity.
    virtualSize @1 :UInt64;
    # Physical usage.
    physicalUsed @2 :UInt64;
    # Overcommit ratio.
    overcommitRatio @3 :Float32;
    # Number of thin volumes.
    volumeCount @4 :UInt32;
    # Number of snapshots.
    snapshotCount @5 :UInt32;
}

# ─── Pool Export / Import ─────────────────────────────────────

struct ImportPoolRequest {
    exportData @0 :T.DataHandle;
    # Import name (empty = use original).
    name @1 :Text;
    # Devices to import to.
    devices @2 :List(T.DeviceId);
}

# ─── Volume Clone ─────────────────────────────────────────────

struct CloneVolumeRequest {
    # Source volume to clone.
    sourceVolumeId @0 :T.VolumeId;
    # Name for the cloned volume.
    name @1 :Text;
    # Target pool (empty = same pool as source).
    targetPoolId @2 :T.StoragePoolId;
    # Labels.
    labels @3 :T.StringMap;
}

# ─── Volume Migration ─────────────────────────────────────────

struct MigrateVolumeRequest {
    volumeId @0 :T.VolumeId;
    # Target pool for migration.
    targetPoolId @1 :T.StoragePoolId;
    # Target device (empty = auto).
    targetDevice @2 :T.DeviceId;
    # Whether to migrate live (minimal downtime).
    live @3 :Bool;
    # Bandwidth limit in bytes per second (0 = unlimited).
    bandwidthLimit @4 :UInt64;
}

enum MigrationState {
    pending @0;
    running @1;
    completed @2;
    failed @3;
    paused @4;
    cancelled @5;
    custom @6;
}

struct MigrationProgress {
    migrationId @0 :Text;
    volumeId @1 :T.VolumeId;
    state @2 :MigrationState;
    # Percentage complete.
    percentComplete @3 :Float32;
    # Bytes migrated.
    bytesMigrated @4 :UInt64;
    # Total bytes.
    totalBytes @5 :UInt64;
    # Estimated time remaining.
    estimatedRemaining @6 :T.Duration;
}

# ─── Storage Tiering ──────────────────────────────────────────

enum StorageTierAction {
    promote @0;       # Move to faster tier
    demote @1;        # Move to slower tier
    lock @2;          # Prevent tier changes
    unlock @3;        # Allow tier changes
    custom @4;
}

# ─── Storage Tier ──────────────────────────────────────────────

enum StorageTier {
    hot @0;
    warm @1;
    cold @2;
    archive @3;
    custom @4;
}

struct StorageTierRequest {
    volumeId @0 :T.VolumeId;
    action @1 :StorageTierAction;
    targetTier @2 :StorageTier;
}

struct StorageTierStatus {
    volumeId @0 :T.VolumeId;
    currentTier @1 :StorageTier;
    availableTiers @2 :List(StorageTier);
    lastTierChange @3 :T.Timestamp;
    tierReadCount @4 :UInt64;
    tierWriteCount @5 :UInt64;
}

# ─── Replication ──────────────────────────────────────────────

enum ReplicationMode {
    sync @0;          # Synchronous (zero data loss)
    async @1;         # Asynchronous (eventual consistency)
    semiSync @2;      # Semi-synchronous (configurable lag)
    custom @3;
}

struct ReplicatePoolRequest {
    sourcePoolId @0 :T.StoragePoolId;
    targetPoolId @1 :T.StoragePoolId;
    mode @2 :ReplicationMode;
    # Maximum allowed lag in seconds (async only).
    maxLagSeconds @3 :UInt32;
    # Bandwidth limit in bytes per second (0 = unlimited).
    bandwidthLimit @4 :UInt64;
}

enum ReplicationState {
    initializing @0;
    active @1;
    syncing @2;
    paused @3;
    failed @4;
    split @5;        # Source and target diverged
    custom @6;
}

struct ReplicationStatus {
    replicationId @0 :Text;
    sourcePoolId @1 :T.StoragePoolId;
    targetPoolId @2 :T.StoragePoolId;
    state @3 :ReplicationState;
    mode @4 :ReplicationMode;
    # Current lag in seconds.
    lagSeconds @5 :UInt32;
    # Bytes replicated.
    bytesReplicated @6 :UInt64;
    # Last sync timestamp.
    lastSyncAt @7 :T.Timestamp;
}

# ─── I/O Stats Subscription ───────────────────────────────────

interface IoStatsSubscription {
    pull @0 () -> (stats :List(IoStats));
    cancel @1 () -> T.VoidResult;
}

# ─── Encryption Status ────────────────────────────────────────

struct EncryptionStatus {
    volumeId @0 :T.VolumeId;
    encrypted @1 :Bool;
    method @2 :EncryptionMethod;
    algorithm @3 :Text;
    keyId @4 :T.KeyId;
    # Whether the volume is currently unlocked.
    unlocked @5 :Bool;
}

# ─── Pool Deduplication Stats ───────────────────────────────

struct PoolDeduplicationStats {
    poolId @0 :T.StoragePoolId;
    # Data bytes before dedup.
    preDedupBytes @1 :UInt64;
    # Data bytes after dedup.
    postDedupBytes @2 :UInt64;
    # Dedup ratio (pre/post).
    ratio @3 :Float32;
    # Number of duplicate blocks found.
    duplicateBlocks @4 :UInt64;
    # Total blocks in the pool.
    totalBlocks @5 :UInt64;
}

# ─── Pool Compression Stats ──────────────────────────────────

struct PoolCompressionStats {
    poolId @0 :T.StoragePoolId;
    # Data bytes before compression.
    preCompressBytes @1 :UInt64;
    # Data bytes after compression.
    postCompressBytes @2 :UInt64;
    # Compression ratio (pre/post).
    ratio @3 :Float32;
    # Compression algorithm used.
    algorithm @4 :Text;
}

# ─── Historical I/O Stats Subscription ──────────────────────

interface HistoricalIoStatsSubscription {
    pull @0 () -> (stats :List(IoStats), trend :IoStatsTrend);
    cancel @1 () -> T.VoidResult;
}

struct IoStatsTrend {
    # Slope of read throughput over window (bytes/sec^2).
    readThroughputSlope @0 :Float32;
    # Slope of write throughput over window (bytes/sec^2).
    writeThroughputSlope @1 :Float32;
    # Average read latency over window.
    avgReadLatency @2 :T.Duration;
    # Average write latency over window.
    avgWriteLatency @3 :T.Duration;
}

# ─── Volume Deduplication Stats (audit-10) ─────────────────

struct VolumeDeduplicationStats {
    volumeId @0 :T.VolumeId;
    # Data bytes before dedup.
    preDedupBytes @1 :UInt64;
    # Data bytes after dedup.
    postDedupBytes @2 :UInt64;
    # Dedup ratio (pre/post).
    ratio @3 :Float32;
    # Number of duplicate blocks.
    duplicateBlocks @4 :UInt64;
    # Total blocks.
    totalBlocks @5 :UInt64;
}

# ─── Volume Compression Stats (audit-10) ───────────────────

struct VolumeCompressionStats {
    volumeId @0 :T.VolumeId;
    # Data bytes before compression.
    preCompressBytes @1 :UInt64;
    # Data bytes after compression.
    postCompressBytes @2 :UInt64;
    # Compression ratio (pre/post).
    ratio @3 :Float32;
    # Compression algorithm.
    algorithm @4 :Text;
}
# ═══════════════════════════════════════════════════════════════════════
# v0.0.2 additions — Block Device Provider
#
# A block device driver is a capability. The filesystem/storage
# stack consumes logical block reads/writes through the buffer
# leased to the driver. Swap driver backends (NVMe, virtio-blk,
# USB-MSD, ...) without recompiling upper layers.
# ═══════════════════════════════════════════════════════════════════════

interface BlockProvider {
    # What does this block device look like?
    getGeometry @0 () -> (geometry :BlockGeometry);
    # Open the device for I/O.
    open @1 () -> (result :T.VoidResult);
    close @2 () -> (result :T.VoidResult);
    # Submit a batch of block I/O operations. The driver decides
    # reordering, completion ordering, queue depth.
    submit @3 (ops :List(BlockIoOp)) -> (result :T.VoidResult);
    # Drain outstanding operations.
    flush @4 () -> (result :T.VoidResult);
    # Health snapshot.
    getHealth @5 () -> (health :BlockHealth);
    # Driver-defined health ping.
    ping @6 () -> (health :T.DriverHealth);
}

struct BlockGeometry {
    # Logical block size (bytes). May be smaller than physical.
    logicalBlockSize @1 :UInt32;
    # Physical sector size (bytes).
    physicalBlockSize @2 :UInt32;
    # Total size in logical blocks.
    blocks @3 :UInt64;
    # Whether the device reports write-cache (volatile write coalescing).
    writeCache @4 :Bool;
    # Whether the device reports rotation. SSDs must report non-rotational.
    rotational @5 :Bool;
    # Whether the device supports DISCARD / TRIM.
    discard @6 :Bool;
    # Whether the device supports secure erase (e.g. NVMe format / sanitize).
    secureErase @7 :Bool;
    # Backend dispatch class (NVMe, AHCI, virtio-blk, USB-MSD, ...).
    driverClasses @0 :List(Text);
}

struct BlockIoOp {
    opId @0 :UInt64;
    union {
        read @1 :BlockRange;
        write @2 :BlockWriteOp;
        discard @3 :BlockRange;
        flush @4 :Void;
        custom @5 :Data;
    }
}

struct BlockRange {
    # Starting block (logical blocks, 0-indexed).
    startBlock @0 :UInt64;
    # Number of blocks.
    blockCount @1 :UInt32;
    # Buffer slot the driver reads from / writes to.
    bufferSlot @2 :UInt32;
}

struct BlockWriteOp {
    range @0 :BlockRange;
    # Bit flags from BlockIoFlags.
    flags @1 :UInt32;
}

struct BlockHealth {
    # Device temperature if available.
    temperatureC @0 :Float32;
    # Reallocated sector count (rotational) or similar SMART.
    reallocatedSectors @1 :UInt64;
    # Whether the device reports itself as failed.
    failed @2 :Bool;
    # Whether the device is degraded but functional.
    degraded @3 :Bool;
    # Driver-defined extras.
    extras @4 :List(BlockHealthEntry);
}

struct BlockHealthEntry {
    name @0 :Text;
    typeTag @1 :UInt8;
    value @2 :Int64;
}

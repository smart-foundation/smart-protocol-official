@0xa1b2c3d4e5f6002f;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Backup - backup/restore lifecycle, scheduling, and progress tracking
#
# Manages system snapshots: creation, scheduling, progress streaming,
# and restoration. Supports full, incremental, and differential backups.
# Encryption and integrity are first-class concerns.
#
# All IDs are typed. All durations use T.Duration. All errors use T.Error.
# All timestamps use T.Timestamp. Progress is multi-phase, not a float.
# ═══════════════════════════════════════════════════════════════════════

interface BackupService {
    # List all backups.
    listBackups @0 (pagination :T.Pagination) -> (backups :List(BackupInfo), totalCount :UInt32);

    # Get a single backup by ID.
    getBackup @1 (backupId :T.BackupId) -> (info :BackupInfo);

    # Create a backup.
    createBackup @2 (types :List(BackupType), options :BackupOptions)
                 -> (result :CreateBackupResult);

    # Restore from a backup.
    restoreBackup @3 (backupId :T.BackupId, options :RestoreOptions)
                  -> (result :RestoreBackupResult);

    # Delete a backup.
    deleteBackup @4 (backupId :T.BackupId) -> T.VoidResult;

    # Get backup schedule.
    getSchedule @5 () -> (schedule :BackupSchedule);

    # Set backup schedule.
    setSchedule @6 (schedule :BackupSchedule) -> T.VoidResult;

    # Estimate backup size before creating.
    getEstimatedSize @7 (types :List(BackupType), baseBackupId :T.BackupId)
                     -> (sizeBytes :UInt64, itemEstimate :UInt64);

    # Cancel a running backup/restore operation.
    cancelOperation @8 (operationId :T.BackupId) -> T.VoidResult;

    # Subscribe to backup progress events.
    subscribe @9 (operationId :T.BackupId) -> (subscription :BackupProgressSubscription);
    pull @10 (subscription :BackupProgressSubscription) -> (progress :BackupProgress);
    cancel @11 (subscription :BackupProgressSubscription) -> T.VoidResult;

    # Audit-8: sync backup to a remote target (false positive: backup_remote.capnp belongs here).
    syncToRemote @12 (backupId :T.BackupId, remoteTarget :RemoteTarget) -> T.VoidResult;

    # Audit-8: rotate encryption key for a backup.
    rotateEncryptionKey @13 (backupId :T.BackupId, newKeyId :T.KeyId) -> T.VoidResult;

    # Audit-8: get backup diff between two backups.
    getDiff @14 (backupIdA :T.BackupId, backupIdB :T.BackupId) -> (diff :BackupDiff);

    # Audit-8: get backup manifest for selective restore.
    getManifest @15 (backupId :T.BackupId) -> (manifest :BackupManifest);
}

# ── Backup Info ───────────────────────────────────────────────────────

struct BackupInfo {
    id @0 :T.BackupId;
    timestamp @1 :T.Timestamp;
    sizeBytes @2 :UInt64;
    types @3 :List(BackupType);
    description @4 :Text;
    success @5 :Bool;
    packages @6 :List(T.PackageId);
    kind @7 :BackupKind;
    # Base backup for incremental/differential.
    baseBackupId @8 :T.BackupId;
    # Integrity verification.
    checksum @9 :Checksum;
    # Encryption metadata.
    encryption @10 :EncryptionInfo;
    # Duration of the backup operation.
    duration @11 :T.Duration;
    # Error if success is false.
    error @12 :T.Error;
}

struct Checksum {
    algorithm @0 :ChecksumAlgorithm;
    hash @1 :Data;
}

enum ChecksumAlgorithm {
    sha256 @0;
    sha512 @1;
    blake2b @2;
    blake3 @3;
    xxhash @4;
    custom @5;
}

struct EncryptionInfo {
    encrypted @0 :Bool;
    algorithm @1 :EncryptionAlgorithm;
    keyId @2 :T.KeyId;
}

enum EncryptionAlgorithm {
    aes256Gcm @0;
    aes256Cbc @1;
    chacha20Poly1305 @2;
    xchacha20Poly1305 @3;
    custom @4;
}

# ── Backup Options ────────────────────────────────────────────────────

struct BackupOptions {
  types @0 :List(BackupType);
  overwrite @1 :Bool;
  includeApps @2 :Bool;
  includeData @3 :Bool;
  # For incremental/differential: base backup to diff against.
  baseBackupId @4 :T.BackupId;
  # Encryption settings.
  encrypt @5 :Bool;
  encryptionAlgorithm @6 :EncryptionAlgorithm;
  # Compression settings.
  compressionAlgorithm @7 :CompressionAlgorithm;
  compressionLevel @8 :UInt32; # 1-9
}

struct RestoreOptions {
    types @0 :List(BackupType);
    overwrite @1 :Bool;
    restoreApps @2 :Bool;
    restoreData @3 :Bool;
    # Selective restore: only these packages.
    packageFilter @4 :List(T.PackageId);
}

# ── Backup Types ──────────────────────────────────────────────────────

enum BackupType {
    system @0;
    apps @1;
    data @2;
    settings @3;
    credentials @4;
    photos @5;
    videos @6;
    music @7;
    documents @8;
    custom @9;
}

enum BackupKind {
  full @0;
  incremental @1;
  differential @2;
  mirror @3;
  snapshot @4;
  custom @5;
}

# ── Progress ──────────────────────────────────────────────────────────

struct BackupProgress {
    operationId @0 :T.BackupId;
    phase @1 :BackupPhase;
    # Progress within current phase (0.0 - 1.0).
    phaseProgress @2 :Float32;
    totalPhases @3 :UInt32;
    currentPhase @4 :UInt32;
    # Current item being processed.
    currentItemType @5 :Text;
    currentItemName @6 :Text;
    # Byte progress.
    bytesProcessed @7 :UInt64;
    totalBytes @8 :UInt64;
    # Item count progress.
    itemsProcessed @9 :UInt64;
    totalItems @10 :UInt64;
    # Elapsed time.
    elapsed @11 :T.Duration;
    # Estimated time remaining.
    estimatedRemaining @12 :T.Duration;
    # Error during progress (non-fatal, operation continues).
    error @13 :T.Error;
    # Whether the operation is complete.
    done @14 :Bool;
}

enum BackupPhase {
    scanning @0;
    hashing @1;
    compressing @2;
    encrypting @3;
    writing @4;
    verifying @5;
    cleaningUp @6;
    custom @7;
}

# ── Schedule ──────────────────────────────────────────────────────────

struct BackupSchedule {
  enabled @0 :Bool;
  interval @1 :ScheduleInterval;
  # Custom interval for 'custom' variant.
  customInterval @2 :T.Duration;
  # Time of day for daily/weekly/monthly.
  timeOfDay @3 :TimeOfDay;
  # Retention policy.
  retention @4 :RetentionPolicy;
  types @5 :List(BackupType);
}

# ── Time of Day (typed) ─────────────────────────────────────────────
struct TimeOfDay {
  hour @0 :UInt8;   # 0-23
  minute @1 :UInt8; # 0-59
  # Timezone offset (minutes from UTC).
  timezoneOffset @2 :Int16; # ± minutes from UTC
}

struct RetentionPolicy {
    union {
        countBased @0 :UInt32;
        ageBased @1 :T.Duration;
        spaceBased @2 :UInt64;
        custom @3 :Data;
    }
}

enum ScheduleInterval {
    hourly @0;
    daily @1;
    weekly @2;
    monthly @3;
    custom @4;
}

# ── Results ───────────────────────────────────────────────────────────

struct CreateBackupResult {
    union {
        success @0 :CreateBackupSuccess;
        error @1 :T.Error;
        custom @2 :Data;
    }
}

struct CreateBackupSuccess {
    backupId @0 :T.BackupId;
    progress @1 :BackupProgressSubscription;
}

struct RestoreBackupResult {
    union {
        success @0 :RestoreBackupSuccess;
        error @1 :T.Error;
        custom @2 :Data;
    }
}

struct RestoreBackupSuccess {
    operationId @0 :T.BackupId;
    progress @1 :BackupProgressSubscription;
}

# ── Subscription ──────────────────────────────────────────────────────

interface BackupProgressSubscription {
    pull @0 () -> (progress :BackupProgress);
    cancel @1 () -> T.VoidResult;
}

# Audit-8: remote backup target (cloud, NAS, etc.).
struct RemoteTarget {
    # Target type (e.g., "cloud", "nas", "sftp").
    type @0 :Text;
    # Target URI (opaque, backend-decoded).
    uri @1 :Text;
    # Authentication credentials reference.
    credentialsId @2 :T.KeyId;
    # Whether to encrypt data in transit.
    encryptInTransit @3 :Bool;
}

# Audit-8: backup diff between two backups.
struct BackupDiff {
    # Files added in backup B but not in A.
    added @0 :List(BackupManifestEntry);
    # Files removed from A but not in B.
    removed @1 :List(BackupManifestEntry);
    # Files modified between A and B.
    modified @2 :List(BackupManifestEntry);
}

# Audit-8: backup manifest for selective restore.
struct BackupManifest {
    backupId @0 :T.BackupId;
    # List of all entries in the backup.
    entries @1 :List(BackupManifestEntry);
    # Total size of all entries.
    totalSize @2 :UInt64;
    # Number of entries.
    entryCount @3 :UInt32;
    # Base backup ID (for incremental/differential).
    baseBackupId @4 :T.BackupId;
}

# Audit-8: a single entry in a backup manifest.
struct BackupManifestEntry {
    # Path within the backup.
    path @0 :Text;
    # Size in bytes.
    sizeBytes @1 :UInt64;
    # Checksum of the entry.
    checksum @2 :Checksum;
    # Type of entry (file, directory, symlink).
    type @3 :Text;
}

# Audit-8: backup verification result.
struct BackupVerification {
    # Whether verification passed.
    verified @0 :Bool;
    # Number of entries checked.
    entriesChecked @1 :UInt32;
    # Number of entries that matched checksums.
    entriesMatched @2 :UInt32;
    # Number of entries that mismatched.
    entriesMismatched @3 :UInt32;
    # Verification error if any.
    error @4 :T.Error;
}

# Audit-8: backup options extended with audit-8 features.
struct BackupOptionsExtended {
    # Base BackupOptions.
    base @0 :BackupOptions;
    # Compression algorithm (typed).
    compressionAlgorithm @1 :CompressionAlgorithm;
    # Exclude patterns (glob-based).
    excludePatterns @2 :List(Text);
    # Remote target for sync.
    remoteTarget @3 :RemoteTarget;
}

# Audit-8: typed compression algorithms.
enum CompressionAlgorithm {
    none @0;
    gzip @1;
    zstd @2;
    lz4 @3;
    brotli @4;
    custom @5;
}

# Audit-8: backup strategies.
enum BackupStrategy {
    full @0;
    incremental @1;
    differential @2;
    mirror @3;
    snapshot @4;
    custom @5;
}

# Audit-8: missed backup policy.
enum BackupMissedPolicy {
    runImmediately @0;
    skip @1;
    runNextWindow @2;
    custom @3;
}

# Audit-9: sync state for tracking remote sync progress.
struct SyncState {
    # Backup being synced.
    backupId @0 :T.BackupId;
    # Sync status.
    status @1 :SyncStatus;
    # Bytes transferred.
    bytesTransferred @2 :UInt64;
    # Total bytes to transfer.
    totalBytes @3 :UInt64;
    # Start time.
    startedAt @4 :T.Timestamp;
    # Last update time.
    updatedAt @5 :T.Timestamp;
    # Error if any.
    error @6 :T.Error;
}

enum SyncStatus {
    pending @0;
    inProgress @1;
    completed @2;
    failed @3;
    custom @4;
}

# Audit-9: deduplication metadata for block-level tracking.
struct DeduplicationMetadata {
    # Base backup ID.
    baseBackupId @0 :T.BackupId;
    # Block hashes for incremental backup.
    blockHashes @1 :List(BlockHash);
    # Block size in bytes.
    blockSize @2 :UInt32;
}

struct BlockHash {
    index @0 :UInt32;
    hash @1 :Data;
    offset @2 :UInt64;
    length @3 :UInt32;
}

# Audit-9: base backup cascade policy.
enum BaseBackupCascadePolicy {
    preserve @0;     # Never delete base backup
    cascade @1;       # Delete when no children reference it
    preserveN @2;     # Preserve N most recent
    custom @3;
}

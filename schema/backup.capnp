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
#
# Fixes this revision makes:
#   - `getManifest` and `getDiff` are PAGINATED. A manifest of a
#     full-system backup has millions of entries; one message carried
#     them all (tens of MB), in the same batch where every other listing
#     paginates.
#   - Verification is callable. `BackupVerification` existed as a type
#     with no method, so integrity checking — the single most demanded
#     operation on a backup — was unreachable.
#   - Six dead types are gone or wired: `BackupStrategy` (an exact
#     duplicate of `BackupKind`), `BackupOptionsExtended` (its unique
#     fields folded into `BackupOptions`), `BackupMissedPolicy` and
#     `BaseBackupCascadePolicy` (folded into `BackupSchedule` as open
#     tokens), `DeduplicationMetadata` (backend telemetry), and
#     `SyncState` (now returned by `syncToRemote`).
#   - Checksums use the promoted `T.HashOutput` instead of a local
#     `Checksum` with a different algorithm encoding.
#   - Compression and encryption algorithms are open tokens: the batch
#     carried four incompatible vocabularies for each.
#   - Remote sync can resume. `SyncState` carries a caller-chosen
#     `resumeToken` the backend honors, so an interrupted sync resumes
#     instead of restarting — previously every backend invented its own
#     cursor.
#   - A subscription has ONE address. The root used to offer
#     `subscribe(operationId)` and a convenience `pull(subscription)`
#     for the same stream; the convenience pair is gone.
#   - `phaseProgress` is gone: the header's own claim ("progress is
#     multi-phase, not a float") is now true — byte and item counters
#     carry the intra-phase progress.
#   - An operation id is not a backup id. `BackupOperationId` is its own
#     type, so cancelling an operation cannot silently target a backup.
# ═══════════════════════════════════════════════════════════════════════

interface BackupService {
    # List all backups.
    listBackups @0 (pagination :T.Pagination) -> (backups :List(BackupInfo), totalCount :UInt64);

    # Get a single backup by ID.
    getBackup @1 (backupId :T.BackupId) -> (result :BackupInfoResult);

    # Create a backup.
    createBackup @2 (options :BackupOptions) -> (result :CreateBackupResult);

    # Restore from a backup.
    restoreBackup @3 (backupId :T.BackupId, options :RestoreOptions) -> (result :RestoreBackupResult);

    # Delete a backup.
    deleteBackup @4 (backupId :T.BackupId) -> T.VoidResult;

    # Get backup schedule.
    getSchedule @5 () -> (schedule :BackupSchedule);

    # Set backup schedule.
    setSchedule @6 (schedule :BackupSchedule) -> T.VoidResult;

    # Estimate backup size before creating.
    getEstimatedSize @7 (options :BackupOptions) -> (result :SizeEstimate);

    # Cancel a running backup/restore OPERATION (not a backup).
    cancelOperation @8 (operationId :BackupOperationId) -> T.VoidResult;

    # Subscribe to operation progress. The subscription is the only
    # address for the stream — it carries its own pull and cancel.
    subscribe @9 (operationId :BackupOperationId) -> (subscription :BackupProgressSubscription);

    # Sync a backup to a remote target.
    syncToRemote @10 (backupId :T.BackupId, remoteTarget :RemoteTarget) -> (result :BackupSyncStateResult);

    # Get the sync state of a backup.
    getSyncState @11 (backupId :T.BackupId) -> (result :BackupSyncStateResult);

    # Resume an interrupted sync. `resumeToken` is the token the backend
    # reported; a backend that cannot resume says so with an error
    # rather than silently restarting.
    resumeSync @12 (backupId :T.BackupId, resumeToken :Data) -> (result :BackupSyncStateResult);

    # Rotate encryption key for a backup.
    rotateEncryptionKey @13 (backupId :T.BackupId, newKeyId :T.KeyId) -> T.VoidResult;

    # Get backup diff between two backups (paginated — see the type).
    getDiff @14 (backupIdA :T.BackupId, backupIdB :T.BackupId, page :T.Pagination)
              -> (result :BackupDiffResult);

    # Get backup manifest for selective restore (paginated).
    getManifest @15 (backupId :T.BackupId, page :T.Pagination) -> (result :BackupManifestResult);

    # Verify a backup's integrity. The operation Audit-8 declared and
    # then left unwired.
    verify @16 (backupId :T.BackupId) -> (result :BackupVerificationResult);
}

# ── Identifiers ────────────────────────────────────────────────────────

# An operation is not a backup: it used to share T.BackupId, so passing
# a backup id to `cancelOperation` silently targeted the wrong family.
struct BackupOperationId { id @0 :UInt64; }

# ── Backup Info ───────────────────────────────────────────────────────

struct BackupInfoResult {
    union {
        info @0 :BackupInfo;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

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
    checksum @9 :T.HashOutput;
    # Encryption metadata.
    encryption @10 :EncryptionInfo;
    duration @11 :T.Duration;
    # Error if success is false.
    error @12 :T.Error;
    metadata @13 :T.StringMap;
}

struct EncryptionInfo {
    encrypted @0 :Bool;
    # Algorithm as an open token ("aes256Gcm", "chacha20Poly1305", ...).
    algorithm @1 :Text;
    keyId @2 :T.KeyId;
    metadata @3 :T.StringMap;
}

# ── Backup Options ────────────────────────────────────────────────────
# `BackupOptionsExtended` (its unique fields folded in here) and
# `BackupStrategy` (an exact duplicate of BackupKind) are gone.

struct BackupOptions {
    types @0 :List(BackupType);
    overwrite @1 :Bool;
    includeApps @2 :Bool;
    includeData @3 :Bool;
    # For incremental/differential: base backup to diff against.
    baseBackupId @4 :T.BackupId;
    # Encryption settings.
    encrypt @5 :Bool;
    # Algorithm as an open token.
    encryptionAlgorithm @6 :Text;
    # Compression settings: algorithm as an open token, level 1-9.
    compressionAlgorithm @7 :Text;
    compressionLevel @8 :UInt32;
    # Exclude patterns (glob-based).
    excludePatterns @9 :List(Text);
    # Remote target for sync.
    remoteTarget @10 :RemoteTarget;
    # Caller-chosen token for resuming an interrupted operation.
    resumeToken @11 :Data;
    metadata @12 :T.StringMap;
}

struct RestoreOptions {
    types @0 :List(BackupType);
    overwrite @1 :Bool;
    restoreApps @2 :Bool;
    restoreData @3 :Bool;
    # Selective restore: only these packages.
    packageFilter @4 :List(T.PackageId);
    # Caller-chosen token for resuming an interrupted restore.
    resumeToken @5 :Data;
    metadata @6 :T.StringMap;
}

# ── Backup Types ──────────────────────────────────────────────────────

enum BackupType {
    unspecified @0;
    system @1;
    apps @2;
    data @3;
    settings @4;
    credentials @5;
    photos @6;
    videos @7;
    music @8;
    documents @9;
    custom @10;
}

enum BackupKind {
    unspecified @0;
    full @1;
    incremental @2;
    differential @3;
    mirror @4;
    snapshot @5;
    custom @6;
}

# ── Progress ──────────────────────────────────────────────────────────

struct BackupProgress {
    operationId @0 :BackupOperationId;
    backupId @1 :T.BackupId;
    phase @2 :BackupPhase;
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
    elapsed @11 :T.Duration;
    estimatedRemaining @12 :T.Duration;
    # Error during progress (non-fatal, operation continues).
    error @13 :T.Error;
    # Whether the operation is complete.
    done @14 :Bool;
    metadata @15 :T.StringMap;
}

enum BackupPhase {
    unspecified @0;
    scanning @1;
    hashing @2;
    compressing @3;
    encrypting @4;
    writing @5;
    verifying @6;
    cleaningUp @7;
    custom @8;
}

# ── Schedule ──────────────────────────────────────────────────────────

struct BackupSchedule {
    enabled @0 :Bool;
    interval @1 :ScheduleInterval;
    # Custom interval for a custom schedule.
    customInterval @2 :T.Duration;
    # Time of day for daily/weekly/monthly schedules.
    timeOfDay @3 :TimeOfDay;
    # Retention policy.
    retention @4 :BackupRetention;
    types @5 :List(BackupType);
    # What to do when a scheduled window was missed, as an open token
    # ("runImmediately", "skip", "runNextWindow", ...). The dead
    # `BackupMissedPolicy` enum is gone; the policy is one field.
    missedRunPolicy @6 :Text;
    # What happens to a base backup when its children are deleted, as an
    # open token ("preserve", "cascade", "preserveN", ...). The dead
    # `BaseBackupCascadePolicy` enum is folded in here.
    baseBackupRetention @7 :Text;
    metadata @8 :T.StringMap;
}

# ── Time of Day (typed) ─────────────────────────────────────────────
struct TimeOfDay {
    hour @0 :UInt8;   # 0-23
    minute @1 :UInt8; # 0-59
    # Timezone offset (minutes from UTC).
    timezoneOffset @2 :Int16;
}

# Renamed from `RetentionPolicy` (which collided with files.capnp's
# struct of the same name): how long a backup is kept, as a union.
struct BackupRetention {
    union {
        countBased @0 :UInt64;
        ageBased @1 :T.Duration;
        spaceBased @2 :UInt64;
        custom @3 :Data;
    }
}

enum ScheduleInterval {
    unspecified @0;
    hourly @1;
    daily @2;
    weekly @3;
    monthly @4;
    custom @5;
}

# ── Results ───────────────────────────────────────────────────────────

struct CreateBackupResult {
    union {
        success @0 :CreateBackupSuccess;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct CreateBackupSuccess {
    backupId @0 :T.BackupId;
    # The operation that is producing it.
    operationId @1 :BackupOperationId;
    progress @2 :BackupProgressSubscription;
    metadata @3 :T.StringMap;
}

struct RestoreBackupResult {
    union {
        success @0 :RestoreBackupSuccess;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct RestoreBackupSuccess {
    backupId @0 :T.BackupId;
    operationId @1 :BackupOperationId;
    progress @2 :BackupProgressSubscription;
    metadata @3 :T.StringMap;
}

struct SizeEstimate {
    union {
        estimate @0 :SizeEstimateValue;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct SizeEstimateValue {
    sizeBytes @0 :UInt64;
    # Number of entries the estimate covers. Stated, so a consumer knows
    # what was counted instead of guessing from a tuple.
    itemEstimate @1 :UInt64;
}

# ── Subscription ──────────────────────────────────────────────────────

interface BackupProgressSubscription {
    pull @0 () -> (progress :BackupProgress);
    cancel @1 () -> T.VoidResult;
}

# ── Remote sync ───────────────────────────────────────────────────────

struct RemoteTarget {
    # Target kind as an open token ("cloud", "nas", "sftp", ...).
    type @0 :Text;
    # Target URI (opaque, backend-decoded).
    uri @1 :T.Uri;
    # Authentication credentials reference.
    credentialsId @2 :T.KeyId;
    # Whether to encrypt data in transit.
    encryptInTransit @3 :Bool;
    metadata @4 :T.StringMap;
}

struct BackupSyncStateResult {
    union {
        state @0 :BackupSyncState;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct BackupSyncState {
    backupId @0 :T.BackupId;
    # Status as an open token ("pending", "inProgress", "completed",
    # "failed", ...).
    status @1 :Text;
    bytesTransferred @2 :UInt64;
    totalBytes @3 :UInt64;
    startedAt @4 :T.Timestamp;
    updatedAt @5 :T.Timestamp;
    # Token the backend reports so an interrupted transfer can resume.
    # A backend that cannot resume says so with an error rather than
    # silently restarting from zero.
    resumeToken @6 :Data;
    error @7 :T.Error;
    done @8 :Bool;
}

# ── Manifest / Diff / Verification ────────────────────────────────────

struct BackupManifestResult {
    union {
        page @0 :BackupManifestPage;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

# One page of a manifest. `totalCount` reports the size of the whole
# manifest so a consumer can page without a second call.
struct BackupManifestPage {
    backupId @0 :T.BackupId;
    entries @1 :List(BackupManifestEntry);
    totalCount @2 :UInt64;
    totalSize @3 :UInt64;
    baseBackupId @4 :T.BackupId;
    metadata @5 :T.StringMap;
}

struct BackupManifestEntry {
    # Path within the backup.
    path @0 :Text;
    sizeBytes @1 :UInt64;
    # Checksum of the entry.
    checksum @2 :T.HashOutput;
    # Type of entry as an open token ("file", "directory", "symlink").
    type @3 :Text;
    metadata @4 :T.StringMap;
}

struct BackupDiffResult {
    union {
        page @0 :BackupDiffPage;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct BackupDiffPage {
    # Files added in backup B but not in A.
    added @0 :List(BackupManifestEntry);
    # Files removed from A but not in B.
    removed @1 :List(BackupManifestEntry);
    # Files modified between A and B.
    modified @2 :List(BackupManifestEntry);
    # Totals for each list, so a diff of two full-system backups is
    # bounded instead of being one enormous message.
    totalAdded @3 :UInt64;
    totalRemoved @4 :UInt64;
    totalModified @5 :UInt64;
    metadata @6 :T.StringMap;
}

struct BackupVerificationResult {
    union {
        verification @0 :BackupVerification;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct BackupVerification {
    backupId @0 :T.BackupId;
    verified @1 :Bool;
    entriesChecked @2 :UInt64;
    entriesMatched @3 :UInt64;
    entriesMismatched @4 :UInt64;
    # Which entries failed, bounded; the totals say how many there were.
    mismatches @5 :List(BackupManifestEntry);
    totalMismatches @6 :UInt64;
    error @7 :T.Error;
    verifiedAt @8 :T.Timestamp;
    metadata @9 :T.StringMap;
}

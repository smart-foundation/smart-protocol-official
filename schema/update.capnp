@0xa1b2c3d4e5f6002e;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Update — OS / package / firmware update orchestration, and the FIRMWARE
# domain (transferred here from boot.capnp).
#
# Backend-agnostic: the Update service may be backed by OSTree, package
# managers, A/B partitions, container image deltas, or a future mechanism.
# Schemas describe intent and outcome; never the mechanism.
#
# All IDs are typed. All durations use T.Duration. All errors use T.Error.
# All timestamps use T.Timestamp. Progress is multi-phase, not a float.
#
# ── The firmware domain ───────────────────────────────────────────────
# boot.capnp deleted `firmwareUpdate`, `firmwareRollback` and
# `configureNetworkBoot` from BootService; they belong here. The imports
# are redesigned under R1–R8:
#   - an image is CONTENT: a URI (open scheme) or a T.DataHandle, never a
#     filesystem path and never an inline blob;
#   - algorithms and mechanisms are open tokens — the imported
#     `TpmAlgorithm` hash enum and the DHCP/TFTP/iSCSI constants are
#     gone, and their places are taken by the URI's own content and by
#     declared tokens;
#   - network-boot configuration lives HERE, deliberately. It answers
#     "how does this machine acquire its first image", which is the same
#     acquisition question `setUpdateSource` answers at runtime;
#     endpoint.capnp's rewrite carries no boot orchestration state, and
#     boot.capnp's manifest is declarative data produced FROM this
#     configuration. Putting it in endpoint would make a transport
#     address carry platform boot state, and putting it back in boot
#     would re-freeze the technology nouns the boot rewrite just removed.
#
# Fixes this revision makes:
#   - An update OPERATION is not a backup. `cancelOperation`,
#     `subscribe` and the progress events keyed operations by
#     `T.BackupId`, so an update id and a backup id were interchangeable
#     at compile time and unrelated at runtime.
#   - The changelog is a handle. The file's own comment conceded it
#     "should be treated as a reference" — with no mechanism to resolve
#     the reference, every listing copied it.
#   - The partition model is not A/B-only. Two fixed slots meant a
#     4-slot system (or a slotless one) could not be described, in a file
#     whose header promises backend agnosticism.
#   - Quarantine is readable. You could quarantine and release an update
#     and never read its state.
#   - One rollout representation instead of three.
#   - The engine state is a union, so `checking` and `downloading` can no
#     longer both be true with no rule between them.
#   - Downloads can resume: progress carries a checkpoint and install
#     accepts it.
#   - Types renamed away from package.capnp's and device.capnp's
#     (UpdateCheckResult, InstallOptions, DeviceGroup).
# ═══════════════════════════════════════════════════════════════════════

interface UpdateService {

    # Snapshot of the update engine state (a union — see UpdateState).
    getState @0 () -> (state :UpdateState);

    # List updates known to the engine (paged).
    listAvailable @1 (pagination :T.Pagination)
                   -> (updates :List(UpdateInfo), totalCount :UInt64);

    # Retrofit history of past installs (paged).
    getHistory @2 (pagination :T.Pagination)
                 -> (history :List(UpdateHistory), totalCount :UInt64);

    # Probe for fresh updates; returns what's pending.
    checkForUpdates @3 () -> (result :UpdateCheckReport);

    # Install a specific update by package id.
    installUpdate @4 (packageId :T.PackageId, options :UpdateInstallOptions)
                    -> (result :UpdateOperationResult);

    # Install every available update honoring current AutoUpdatePolicy.
    installAll @5 (options :UpdateInstallOptions) -> (result :UpdateOperationResult);

    # Roll back a previously installed update.
    rollback @6 (packageId :T.PackageId) -> T.VoidResult;

    # Reboot to apply staged updates.
    reboot @7 () -> T.VoidResult;

    # Read / write the auto-update policy.
    getAutoUpdatePolicy  @8 () -> (policy :AutoUpdatePolicy);
    setAutoUpdatePolicy  @9 (policy :AutoUpdatePolicy) -> T.VoidResult;

    # Set a remote update source URI (opaque; backend-decoded).
    setUpdateSource @10 (source :T.Uri) -> T.VoidResult;

    # When the engine last successfully checked for updates.
    getLastCheck @11 () -> (timestamp :T.Timestamp);

    # Subscribe to update lifecycle events.
    subscribe @12 () -> (subscription :UpdateEventSubscription);

    # Current rollout status for a package (the single rollout shape).
    getRolloutStatus @13 (packageId :T.PackageId) -> (result :RolloutStatusResult);

    # Partition/slot state (not A/B-only — see PartitionState).
    getPartitionState @14 () -> (state :PartitionState);

    # Apply a delta/incremental patch.
    applyDelta @15 (packageId :T.PackageId, delta :DeltaPatch) -> T.VoidResult;

    # Get update verification chain.
    getVerifyChain @16 (packageId :T.PackageId) -> (result :UpdateVerifyChainResult);

    # Check post-update health.
    getPostUpdateHealth @17 (packageId :T.PackageId) -> (result :PostUpdateHealthResult);

    # Get update dependencies (ordering constraints).
    getUpdateDependencies @18 (packageId :T.PackageId, pagination :T.Pagination)
                          -> (dependencies :List(UpdateDependency), totalCount :UInt64);

    # ── Fleet orchestration ──
    createDeviceGroup @19 (name :Text) -> (groupId :T.DeviceGroupId);
    deleteDeviceGroup @20 (groupId :T.DeviceGroupId) -> T.VoidResult;
    addDeviceToGroup @21 (groupId :T.DeviceGroupId, deviceId :T.DeviceId) -> T.VoidResult;
    removeDeviceFromGroup @22 (groupId :T.DeviceGroupId, deviceId :T.DeviceId) -> T.VoidResult;
    # Get all devices in a group (paged — a fleet group grows to UInt32 ids).
    getGroupDevices @23 (groupId :T.DeviceGroupId, pagination :T.Pagination)
                    -> (devices :List(T.DeviceId), totalCount :UInt64);

    # Advance a staged rollout to the next step.
    advanceRollout @24 (packageId :T.PackageId) -> (result :RolloutStepResult);

    # Set the next boot slot (there may be more than two).
    setNextBoot @25 (slot :UInt8) -> T.VoidResult;

    # Mark a slot as good (bootable, no rollback needed).
    markSlotGood @26 (slot :UInt8) -> T.VoidResult;

    # Place an update in quarantine (hold before activation).
    quarantineUpdate @27 (packageId :T.PackageId, reason :Text) -> T.VoidResult;

    # Release an update from quarantine.
    releaseUpdate @28 (packageId :T.PackageId) -> T.VoidResult;

    # Read an update's quarantine state — the half-wired feature's
    # missing getter.
    getQuarantineStatus @29 (packageId :T.PackageId) -> (result :UpdateQuarantineResult);

    # Generate a delta patch from source to target version.
    generateDelta @30 (packageId :T.PackageId, targetVersion :T.Version) -> (result :DeltaPatchResult);

    # Roll back all devices in a group simultaneously.
    rollbackGroup @31 (request :FleetRollbackRequest) -> (result :FleetRollbackResult);

    # Get fleet rollback status.
    getFleetRollbackStatus @32 (packageId :T.PackageId) -> (result :FleetRollbackResult);

    # Pause an active rollout.
    pauseRollout @33 (packageId :T.PackageId, reason :Text) -> T.VoidResult;

    # Resume a paused rollout.
    resumeRollout @34 (packageId :T.PackageId) -> T.VoidResult;

    # Verify and apply a signed update package.
    verifyAndApplyUpdate @35 (package :SignedUpdatePackage) -> T.VoidResult;

    # ── The firmware domain (transferred from boot.capnp) ──
    firmwareUpdate @36 (request :FirmwareInstallRequest) -> (result :FirmwareUpdateResult);
    firmwareRollback @37 (target :T.FirmwareId) -> T.VoidResult;
    getNetworkBootConfig @38 () -> (config :NetworkBootConfig);
    configureNetworkBoot @39 (config :NetworkBootConfig) -> T.VoidResult;
}

# ── Operation identity ────────────────────────────────────────────────

# An update operation is not a backup and not an upgrade: it gets its own
# typed id, so cancelling an operation can never silently target a
# backup.
struct UpdateOperationId { id @0 :UInt64; }

struct UpdateOperationResult {
    union {
        operationId @0 :UpdateOperationId;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

# ── State / Result / Options ───────────────────────────────────────────

# A union, not four independent booleans: `checking = true` and
# `downloading = true` used to be representable with no rule between them.
struct UpdateState {
    since @0 :T.Timestamp;
    union {
        idle @1 :Void;
        checking @2 :Void;
        downloading @3 :DownloadProgress;
        installing @4 :InstallProgress;
        staged @5 :Void;
        rebooting @6 :Void;
        failed @7 :T.Error;
        custom @8 :Data;
    }
}

struct UpdateCheckReport {
    # Renamed from UpdateCheckResult (package.capnp declares its own).
    union {
        report @0 :UpdateCheckReportData;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct UpdateCheckReportData {
    # Updates discovered since the last check.
    updates @0 :List(UpdateInfo);
    # Whether the check discovered anything new.
    available @1 :Bool;
    # When the check ran.
    checkedAt @2 :T.Timestamp;
    metadata @3 :T.StringMap;
}

# Renamed from InstallOptions (package.capnp declares its own).
struct UpdateInstallOptions {
    # If true, defer activation until reboot.
    stageOnly @0 :Bool = false;
    # If true, allow downgrading.
    allowDowngrade @1 :Bool = false;
    # Caller may specify a deadline for the install to begin.
    deadline @2 :T.Duration;
    # Free-form opaque token from the caller; surfaced in history.
    requestToken @3 :Data;
    # Resume an interrupted install from the checkpoint the engine
    # reported. A backend that cannot resume says so with an error
    # instead of silently restarting.
    resumeFrom @4 :Data;
    metadata @5 :T.StringMap;
}

# ── Info / History ─────────────────────────────────────────────────────

struct UpdateInfo {
    packageId     @0  :T.PackageId;
    name          @1  :Text;
    currentVersion @2 :T.Version;
    newVersion    @3  :T.Version;
    severity      @4  :UpdateSeverity;
    # The changelog is CONTENT: a handle, not a Text a consumer is told to
    # "treat as a reference" with no way to resolve it.
    changelog     @5  :T.DataHandle;
    # Download size in bytes (uncompressed payload the runtime must fetch).
    size          @6  :UInt64;
    releaseDate   @7  :T.Timestamp;
    # Per-update identifier assigned by the engine.
    upgradeId     @8  :T.UpgradeId;
    # Optional category for grouping, as an open token ("security",
    # "bugfix", ...): "runtime" vs "osKernel" is a 2020s distinction, and
    # a 2046 software stack has no ordinal for it.
    category      @9  :Text;
    # Whether reboot is required to complete the operation.
    requiresReboot @10 :Bool;
    metadata @11 :T.StringMap;
}

enum UpdateSeverity {
    unspecified @0;
    low @1;
    medium @2;
    high @3;
    critical @4;
    custom @5;
}

struct UpdateHistory {
    packageId    @0 :T.PackageId;
    name         @1 :Text;
    oldVersion   @2 :T.Version;
    newVersion   @3 :T.Version;
    timestamp    @4 :T.Timestamp;
    success      @5 :Bool;
    upgradeId    @6 :T.UpgradeId;
    duration     @7 :T.Duration;
    error        @8 :T.Error;
    # The operation that produced this history entry.
    operationId  @9 :UpdateOperationId;
    metadata @10 :T.StringMap;
}

enum AutoUpdatePolicy {
    unspecified @0;
    manual @1;
    auto @2;
    securityOnly @3;
    scheduled @4;
    custom @5;
}

# ── Events ─────────────────────────────────────────────────────────────

interface UpdateEventSubscription {
    pull   @0 () -> (events :List(UpdateEvent));
    cancel @1 () -> T.VoidResult;

    # Paginated event retrieval. Returns at most `pagination.limit` events
    # starting at `pagination.offset`.
    pullPaged @2 (pagination :T.Pagination)
              -> (events :List(UpdateEvent), totalCount :UInt64);
}

struct UpdateEvent {
    union {
        checkStarted   @0  :T.Timestamp;
        checkCompleted @1  :UpdateCheckReport;
        downloadStarted @2 :DownloadProgress;
        downloadProgress @3 :DownloadProgress;
        downloadCompleted @4 :DownloadComplete;
        installStarted @5  :InstallProgress;
        installStep    @6  :InstallProgress;
        installCompleted @7 :T.PackageId;
        installFailed  @8  :InstallFailure;
        rebootRequired @9  :T.PackageId;
        policyChanged  @10 :AutoUpdatePolicy;
        # The forward-compatibility slot, named as the project convention
        # names it. (The previous "unknown" arm at this ordinal was kept
        # for wire compatibility with a protocol nobody speaks;
        # pre-release, the rename is free and honest.)
        custom @11 :UpdateEventCustom;
    }
}

struct UpdateEventCustom {
    typeId @0 :UInt64;
    payload @1 :T.DataHandle;
    metadata @2 :T.StringMap;
}

struct DownloadProgress {
    packageId @0 :T.PackageId;
    bytesDone @1 :UInt64;
    bytesTotal @2 :UInt64;
    # Resumable checkpoint. Reported so an interrupted download can
    # continue from here instead of restarting in every backend's own
    # undocumented way.
    checkpoint @3 :Data;
    # True when the backend can actually resume from `checkpoint`.
    resumable @4 :Bool;
}

struct DownloadComplete {
    packageId @0 :T.PackageId;
    bytes @1 :UInt64;
    duration @2 :T.Duration;
}

struct InstallProgress {
    packageId @0 :T.PackageId;
    # 0..100
    percent @1 :UInt32;
    step @2 :Text;
    # Set when this step can be resumed after an interruption.
    checkpoint @3 :Data;
}

struct InstallFailure {
    packageId @0 :T.PackageId;
    error @1 :T.Error;
    partial @2 :Bool;
    metadata @3 :T.StringMap;
}

# ── Rollout (one representation) ───────────────────────────────────────
# `StagedRollout` (percentage + canary + target devices) and
# `RolloutStatus` (state + steps + percentage) used to be two shapes for
# one concept; they are one now.

struct RolloutStatusResult {
    union {
        status @0 :RolloutStatus;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct RolloutStepResult {
    union {
        step @0 :RolloutStep;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct RolloutStatus {
    packageId @0 :T.PackageId;
    state @1 :RolloutState;
    currentStep @2 :UInt32;
    totalSteps @3 :UInt32;
    percentageComplete @4 :UInt8;
    # Canary group name (e.g., "beta", "early-adopters").
    canaryGroup @5 :Text;
    # Target devices for this rollout.
    targetDevices @6 :List(T.DeviceId);
    startedAt @7 :T.Timestamp;
    scheduledComplete @8 :T.Timestamp;
    # Whether rollback is triggered on error.
    autoRollback @9 :Bool;
    # When the rollout was paused (if paused).
    pausedAt @10 :T.Timestamp;
    pauseReason @11 :Text;
    metadata @12 :T.StringMap;
}

struct RolloutStep {
    stepId @0 :UInt32;
    name @1 :Text;
    # Percentage of devices to advance to this step.
    targetPercentage @2 :UInt8;
    # Whether this step requires explicit confirmation.
    requiresConfirmation @3 :Bool;
    # Whether rollback is allowed from this step.
    rollbackAllowed @4 :Bool;
    metadata @5 :T.StringMap;
}

enum RolloutState {
    unspecified @0;
    running @1;
    paused @2;
    completed @3;
    failed @4;
    cancelled @5;
    custom @6;
}

# ── Partitions / slots ────────────────────────────────────────────────
# Not A/B-only: a list of slots plus the active one describes two, four,
# or no slots at all — the previous fixed slotA/slotB pair could not.

struct PartitionState {
    # All bootable slots (empty = the backend has no slot model).
    slots @0 :List(PartitionInfo);
    # Which slot is currently active (an index into `slots`).
    activeSlot @1 :UInt8;
    # Next boot slot (an index into `slots`; absent = no change).
    nextSlot @2 :UInt8;
    # Boot control configuration.
    bootControl @3 :BootControl;
    metadata @4 :T.StringMap;
}

struct PartitionInfo {
    slot @0 :UInt8;
    # Version installed on this slot.
    version @1 :T.Version;
    # Size in bytes.
    sizeBytes @2 :UInt64;
    # Health status as an open token.
    health @3 :Text;
    metadata @4 :T.StringMap;
}

struct BootControl {
    # Next boot slot (absent = no change).
    nextSlot @0 :UInt8;
    hasNextSlot @1 :Bool;
    # Whether the slot was marked good (no rollback needed).
    slotGood @2 :Bool;
    # Maximum number of boot attempts before rollback.
    maxBootAttempts @3 :UInt8;
    # Current boot attempt count.
    bootAttempts @4 :UInt8;
}

# ── Deltas / verification ─────────────────────────────────────────────

struct DeltaPatchResult {
    union {
        delta @0 :DeltaPatch;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct DeltaPatch {
    # Source version to patch from.
    sourceVersion @0 :T.Version;
    # Target version to patch to.
    targetVersion @1 :T.Version;
    # Size of the delta in bytes.
    deltaSizeBytes @2 :UInt64;
    # Delta data as content.
    deltaData @3 :T.DataHandle;
    # Checksum of the delta.
    checksum @4 :T.HashOutput;
    metadata @5 :T.StringMap;
}

struct UpdateVerifyChainResult {
    union {
        chain @0 :VerifyChain;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct VerifyChain {
    # Root of trust key fingerprint.
    root @0 :T.KeyFingerprint;
    # Target file hashes.
    targets @1 :List(T.HashOutput);
    # Snapshot hash.
    snapshot @2 :T.HashOutput;
    # Timestamp of the verification.
    timestamp @3 :T.Timestamp;
    # Signatures, as content.
    signatures @4 :List(T.DataHandle);
    metadata @5 :T.StringMap;
}

struct PostUpdateHealthResult {
    union {
        health @0 :PostUpdateHealth;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct PostUpdateHealth {
    errorRate @0 :Float32;
    crashRate @1 :Float32;
    performanceDelta @2 :Float32;
    rollbackRecommended @3 :Bool;
    checkedAt @4 :T.Timestamp;
}

struct UpdateDependency {
    packageId @0 :T.PackageId;
    # Packages that must be updated before this one.
    dependsOn @1 :List(T.PackageId);
    # Packages that conflict with this update.
    conflictWith @2 :List(T.PackageId);
    # Install order (lower = earlier).
    installOrder @3 :UInt32;
}

# ── Quarantine ────────────────────────────────────────────────────────

struct UpdateQuarantineResult {
    union {
        quarantine @0 :UpdateQuarantine;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct UpdateQuarantine {
    packageId @0 :T.PackageId;
    # Whether the update is in quarantine.
    quarantined @1 :Bool;
    reason @2 :Text;
    # When the update was placed in quarantine.
    quarantinedAt @3 :T.Timestamp;
    # Quarantine expires at this time (absent = never).
    expiresAt @4 :T.Timestamp;
    metadata @5 :T.StringMap;
}

# ── Fleet ─────────────────────────────────────────────────────────────

# Renamed from DeviceGroup (device.capnp declares its own): this is the
# update domain's device grouping.
struct UpdateDeviceGroup {
    groupId @0 :T.DeviceGroupId;
    name @1 :Text;
    deviceCount @2 :UInt32;
    createdAt @3 :T.Timestamp;
    metadata @4 :T.StringMap;
}

enum RollbackScope {
    unspecified @0;
    singleDevice @1;
    deviceGroup @2;
    fleet @3;
    custom @4;
}

struct FleetRollbackRequest {
    packageId @0 :T.PackageId;
    scope @1 :RollbackScope;
    groupId @2 :T.DeviceGroupId;
    # Whether to roll back immediately or staged.
    immediate @3 :Bool;
    # Maximum devices to roll back in parallel.
    batchSize @4 :UInt32;
}

struct FleetRollbackResult {
    union {
        status @0 :FleetRollbackStatus;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct FleetRollbackStatus {
    packageId @0 :T.PackageId;
    scope @1 :RollbackScope;
    groupId @2 :T.DeviceGroupId;
    # Total devices to roll back.
    totalDevices @3 :UInt64;
    # Devices rolled back successfully.
    completed @4 :UInt64;
    # Devices where rollback failed.
    failed @5 :UInt64;
    # Devices pending rollback.
    pending @6 :UInt64;
    # State as an open token.
    state @7 :Text;
    done @8 :Bool;
    metadata @9 :T.StringMap;
}

# ── Signed packages ───────────────────────────────────────────────────

struct SignedUpdatePackage {
    packageId @0 :T.PackageId;
    # Signed delta patch.
    delta @1 :DeltaPatch;
    # Verification chain.
    chain @2 :VerifyChain;
    # Signature over the entire package, as content.
    signature @3 :T.DataHandle;
    metadata @4 :T.StringMap;
}

# ═══════════════════════════════════════════════════════════════════════
# The firmware domain — transferred from boot.capnp
# ═══════════════════════════════════════════════════════════════════════

# An image is CONTENT: a URI with an open scheme (http://, pxe://,
# iscsi://, anything the backend understands) or a direct payload. The
# imported version took a bare `T.Uri` plus a raw hash and a TPM
# algorithm enum; the payload path is a T.DataHandle now, and the
# algorithm is the `T.HashOutput`'s own.
struct FirmwareImage {
    union {
        uri @0 :T.Uri;
        data @1 :T.DataHandle;
        custom @2 :Data;
    }
    sizeBytes @3 :UInt64;
    # Expected hash, verified before applying.
    hash @4 :T.HashOutput;
    # Version this image carries.
    version @5 :T.Version;
    # Backend-declared metadata (vendor, board, channel).
    metadata @6 :T.StringMap;
}

# Renamed from FirmwareUpdateRequest (usb.capnp declares its own for
# per-device flashing): this one installs the MACHINE firmware.
struct FirmwareInstallRequest {
    # The image to install.
    target @0 :FirmwareImage;
    # Whether to verify the signature before applying.
    verifySignature @1 :Bool = true;
    # Maximum time to wait for the update.
    timeout @2 :T.Duration;
    # Caller-chosen token; surfaced in history.
    requestToken @3 :Data;
}

struct FirmwareUpdateResult {
    union {
        success @0 :FirmwareUpdateSuccess;
        failed @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct FirmwareUpdateSuccess {
    # The firmware now installed (typed id).
    firmwareId @0 :T.FirmwareId;
    version @1 :T.Version;
    completedAt @2 :T.Timestamp;
    requiresRestart @3 :Bool;
}

# How the machine acquires its first image. See the file header for why
# this lives here rather than in boot.capnp or endpoint.capnp.
struct NetworkBootConfig {
    # Ordered acquisition sources, each an open URI. The URI carries the
    # host, the path and the protocol; the previous struct named DHCP,
    # TFTP and iSCSI in required fields, so a mechanism invented later
    # had nowhere to be.
    sources @0 :List(T.Uri);
    # How to choose among sources, as an open token ("firstAvailable",
    # "parallel", "strict").
    selection @1 :Text;
    # Maximum attempts per source.
    maxAttempts @2 :UInt32;
    # Timeout per attempt.
    attemptTimeout @3 :T.Duration;
    # Backend-declared extras.
    metadata @4 :T.StringMap;
}

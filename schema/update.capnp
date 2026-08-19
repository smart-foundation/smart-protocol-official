@0xa1b2c3d4e5f6002e;

# ═══════════════════════════════════════════════════════════════════════
# Update - OS / package / firmware update orchestration.
#
# Backend-agnostic: the Update service may be backed by OSTree, package
# managers, A/B partitions, container image deltas, or a future mechanism.
# Schemas describe intent and outcome; never the mechanism.
#
# Improvements beyond the original:
#   - All IDs are typed (T.PackageId, T.UpgradeId).
#   - All times use T.Duration / T.Timestamp (no raw UInt64).
#   - All errors use T.Error in VoidResult paths.
#   - source is a Text opaque URI rather than filesystem path.
#   - installUpdate, rollback, reboot use T.VoidResult with structured error.
#   - getHistory uses T.Pagination with total count.
#   - AutoUpdatePolicy / UpdateSeverity gained a custom variant.
#   - UpdateEventSubscription has pull + cancel.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface UpdateService {

    # Snapshot of the update engine state.
    getState @0 () -> (state :UpdateState);

    # List updates known to the engine (paged).
    listAvailable @1 (pagination :T.Pagination)
                   -> (updates :List(UpdateInfo), total :UInt64);

    # Retrofit history of past installs (paged).
    getHistory @2 (pagination :T.Pagination)
                 -> (history :List(UpdateHistory), total :UInt64);

    # Probe for fresh updates; returns what's pending.
    checkForUpdates @3 () -> UpdateCheckResult;

    # Install a specific update by package id.
    installUpdate @4 (packageId :T.PackageId, options :InstallOptions)
                    -> T.VoidResult;

    # Install every available update honoring current AutoUpdatePolicy.
    installAll @5 (options :InstallOptions) -> T.VoidResult;

    # Roll back a previously installed update.
    rollback @6 (packageId :T.PackageId) -> T.VoidResult;

    # Reboot to apply staged updates.
    reboot @7 () -> T.VoidResult;

    # Read / write the auto-update policy.
    getAutoUpdatePolicy  @8 () -> (policy :AutoUpdatePolicy);
    setAutoUpdatePolicy  @9 (policy :AutoUpdatePolicy) -> T.VoidResult;

    # Set a remote update source URI (opaque; backend-decoded).
    setUpdateSource @10 (source :Text) -> T.VoidResult;

    # When the engine last successfully checked for updates.
    getLastCheck @11 () -> (timestamp :T.Timestamp);

    # Subscribe to update lifecycle events.
    subscribe @12 () -> (subscription :UpdateEventSubscription);

    # Audit-8: staged rollout management (false positive: update_staging.capnp belongs here).
    getStagedRollout @13 (packageId :T.PackageId) -> (rollout :StagedRollout);

    # Audit-8: get A/B partition state (false positive: partition_manager.capnp belongs here).
    getPartitionState @14 () -> (state :PartitionState);

    # Audit-8: apply a delta/incremental patch.
    applyDelta @15 (packageId :T.PackageId, delta :DeltaPatch) -> T.VoidResult;

    # Audit-8: get update verification chain (false positive: update_verification.capnp belongs here).
    getVerifyChain @16 (packageId :T.PackageId) -> (chain :VerifyChain);

    # Audit-8: check post-update health.
    getPostUpdateHealth @17 (packageId :T.PackageId) -> (health :PostUpdateHealth);

    # Audit-8: get update dependencies (ordering constraints).
    getUpdateDependencies @18 (packageId :T.PackageId) -> (dependencies :List(UpdateDependency));

    # Audit-9: Fleet orchestration — create a device group for coordinated rollout.
    createDeviceGroup @19 (name :Text) -> (groupId :T.DeviceGroupId);

    # Audit-9: Delete a device group.
    deleteDeviceGroup @20 (groupId :T.DeviceGroupId) -> T.VoidResult;

    # Audit-9: Add a device to a group.
    addDeviceToGroup @21 (groupId :T.DeviceGroupId, deviceId :T.DeviceId) -> T.VoidResult;

    # Audit-9: Remove a device from a group.
    removeDeviceFromGroup @22 (groupId :T.DeviceGroupId, deviceId :T.DeviceId) -> T.VoidResult;

    # Audit-9: Get all devices in a group.
    getGroupDevices @23 (groupId :T.DeviceGroupId) -> (devices :List(T.DeviceId));

    # Audit-9: Advance a staged rollout to the next step.
    advanceRollout @24 (packageId :T.PackageId) -> (step :RolloutStep);

    # Audit-9: Set next boot slot for A/B partitions.
    setNextBoot @25 (slot :UInt8) -> T.VoidResult;

    # Audit-9: Mark a slot as good (bootable, no rollback needed).
    markSlotGood @26 (slot :UInt8) -> T.VoidResult;

    # Audit-9: Place an update in quarantine (hold before activation).
    quarantineUpdate @27 (packageId :T.PackageId, reason :Text) -> T.VoidResult;

    # Audit-9: Release an update from quarantine.
    releaseUpdate @28 (packageId :T.PackageId) -> T.VoidResult;

    # Audit-9: Generate a delta patch from source to target version.
    generateDelta @29 (packageId :T.PackageId, targetVersion :T.Version) -> (delta :DeltaPatch);

    # Audit-10: Roll back all devices in a group simultaneously.
    rollbackGroup @30 (request :FleetRollbackRequest) -> (status :FleetRollbackStatus);

    # Audit-10: Get fleet rollback status.
    getFleetRollbackStatus @31 (packageId :T.PackageId) -> (status :FleetRollbackStatus);

    # Audit-10: Pause an active rollout.
    pauseRollout @32 (packageId :T.PackageId, reason :Text) -> T.VoidResult;

    # Audit-10: Resume a paused rollout.
    resumeRollout @33 (packageId :T.PackageId) -> T.VoidResult;

    # Audit-10: Get current rollout status.
    getRolloutStatus @34 (packageId :T.PackageId) -> (status :RolloutStatus);

    # Audit-10: Verify and apply a signed update package.
    verifyAndApplyUpdate @35 (package :SignedUpdatePackage) -> T.VoidResult;
}

# ── State / Result / Options ───────────────────────────────────────────

struct UpdateState {
    checking    @0 :Bool;
    downloading @1 :Bool;
    updating    @2 :Bool;
    # Most recent terminal error, if any.
    error       @3 :T.Error;
    # When the engine transitioned into its current state.
    since       @4 :T.Timestamp;
}

struct UpdateCheckResult {
    # Updates discovered since the last check.
    updates     @0 :List(UpdateInfo);
    # Whether the check discovered anything new.
    available   @1 :Bool;
    # Structured error if the check itself failed.
    error       @2 :T.Error;
}

struct InstallOptions {
    # If true, defer activation until reboot.
    stageOnly       @0 :Bool = false;
    # If true, allow downgrading.
    allowDowngrade  @1 :Bool = false;
    # Caller may specify a deadline for the install to begin.
    deadline        @2 :T.Duration;
    # Free-form opaque token from the caller; surfaced in history.
    requestToken    @3 :Data;
}

# ── Info / History ─────────────────────────────────────────────────────

struct UpdateInfo {
    packageId     @0  :T.PackageId;
    name          @1  :Text;
    currentVersion @2 :T.Version;
    newVersion    @3  :T.Version;
    severity      @4  :UpdateSeverity;
    changelog     @5  :Text;
    # NOTE: changelog is Text for wire-format compatibility. For large
    # changelogs (>1KB), consumers should treat the Text as a reference
    # and fetch the full content via a DataHandle when needed. A future
    # schema version bump may change this to T.DataHandle.
    # Download size in bytes (uncompressed payload the runtime must fetch).
    size          @6  :UInt64;
    releaseDate   @7  :T.Timestamp;
    # Per-update identifier assigned by the engine.
    upgradeId     @8  :T.UpgradeId;
    # Optional category for grouping.
    category      @9  :UpdateCategory;
    # Whether reboot is required to complete the operation.
    requiresReboot @10 :Bool;
}

enum UpdateSeverity {
    low       @0;
    medium    @1;
    high      @2;
    critical  @3;
    custom    @4;
}

enum UpdateCategory {
    security  @0;
    bugfix    @1;
    feature   @2;
    driver    @3;
    firmware  @4;
    osKernel  @5;
    runtime   @6;
    custom    @7;
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
}

enum AutoUpdatePolicy {
    manual       @0;
    auto         @1;
    securityOnly @2;
    scheduled    @3;
    custom       @4;
}

# ── Events ─────────────────────────────────────────────────────────────

interface UpdateEventSubscription {
    pull   @0 () -> (events :List(UpdateEvent));
    cancel @1 () -> T.VoidResult;

    # Paginated event retrieval. Returns at most `pagination.limit` events
    # starting at `pagination.offset`. Caller should repeat with increasing
    # offset until all events are consumed.
    pullPaged @2 (pagination :T.Pagination)
              -> (events :List(UpdateEvent), total :UInt64);
}

struct UpdateEvent {
    union {
        checkStarted   @0  :T.Timestamp;
        checkCompleted @1  :UpdateCheckResult;
        downloadStarted @2 :DownloadProgress;
        downloadProgress @3 :DownloadProgress;
        downloadCompleted @4 :DownloadComplete;
        installStarted @5  :InstallProgress;
        installStep    @6  :InstallProgress;
        installCompleted @7 :T.PackageId;
        installFailed  @8  :InstallFailure;
        rebootRequired @9  :T.PackageId;
        policyChanged  @10 :AutoUpdatePolicy;
        # NOTE: This variant is named "unknown" instead of "custom"
        # for wire-format compatibility (ordinal @11). The project
        # convention is "custom" for forward-compatible escape hatches.
        # Renaming would break the wire format. Treat "unknown" as
        # the custom / forward-compatibility variant.
        unknown        @11 :UnknownUpdateEvent;
    }
}

struct DownloadProgress {
    packageId @0 :T.PackageId;
    bytesDone @1 :UInt64;
    bytesTotal @2 :UInt64;
}

struct DownloadComplete {
    packageId @0 :T.PackageId;
    bytes     @1 :UInt64;
    duration  @2 :T.Duration;
}

struct InstallProgress {
    packageId @0 :T.PackageId;
    # 0..100
    percent   @1 :UInt32;
    step      @2 :Text;
}

struct InstallFailure {
    packageId @0 :T.PackageId;
    error     @1 :T.Error;
    partial   @2 :Bool;
}

struct UnknownUpdateEvent {
    typeId  @0 :UInt64;
    payload @1 :Data;
}

# Audit-8: staged rollout configuration.
struct StagedRollout {
    packageId @0 :T.PackageId;
    # Current rollout percentage (0-100).
    percentage @1 :UInt8;
    # Canary group name (e.g., "beta", "early-adopters").
    canaryGroup @2 :Text;
    # Target devices for this rollout.
    targetDevices @3 :List(T.DeviceId);
    # When the rollout started.
    startedAt @4 :T.Timestamp;
    # When the rollout is scheduled to complete.
    scheduledComplete @5 :T.Timestamp;
    # Whether rollback is triggered on error.
    autoRollback @6 :Bool;
}

# Audit-8: A/B partition state.
struct PartitionState {
    # Slot A info.
    slotA @0 :PartitionInfo;
    # Slot B info.
    slotB @1 :PartitionInfo;
    # Which slot is currently active (0 = A, 1 = B).
    activeSlot @2 :UInt8;
    # Boot control configuration.
    bootControl @3 :BootControl;
}

# Audit-8: partition info for A/B updates.
struct PartitionInfo {
    # Version installed on this slot.
    version @0 :T.Version;
    # Size in bytes.
    sizeBytes @1 :UInt64;
    # Health status.
    health @2 :PartitionHealth;
}

# Audit-8: partition health status.
enum PartitionHealth {
    healthy @0;
    corrupted @1;
    empty @2;
    custom @3;
}

# Audit-8: boot control configuration.
struct BootControl {
    # Next boot slot (0 = A, 1 = B, 255 = no change).
    nextBoot @0 :UInt8;
    # Whether the slot was marked good (no rollback needed).
    slotGood @1 :Bool;
    # Maximum number of boot attempts before rollback.
    maxBootAttempts @2 :UInt8;
    # Current boot attempt count.
    bootAttempts @3 :UInt8;
}

# Audit-8: delta/incremental patch.
struct DeltaPatch {
    # Source version to patch from.
    sourceVersion @0 :T.Version;
    # Target version to patch to.
    targetVersion @1 :T.Version;
    # Size of the delta in bytes.
    deltaSizeBytes @2 :UInt64;
    # Delta data handle.
    deltaData @3 :T.DataHandle;
    # Checksum of the delta.
    checksum @4 :T.HashOutput;
}

# Audit-8: cryptographic verification chain (TUF-style).
struct VerifyChain {
    # Root of trust key fingerprint.
    root @0 :T.KeyFingerprint;
    # Target file hashes.
    targets @1 :List(T.HashOutput);
    # Snapshot hash.
    snapshot @2 :T.HashOutput;
    # Timestamp of the verification.
    timestamp @3 :T.Timestamp;
    # Signatures.
    signatures @4 :List(T.DataHandle);
}

# Audit-8: post-update health monitoring.
struct PostUpdateHealth {
    # Error rate after update (0.0-1.0).
    errorRate @0 :Float32;
    # Crash rate after update (0.0-1.0).
    crashRate @1 :Float32;
    # Performance delta (negative = slower, positive = faster).
    performanceDelta @2 :Float32;
    # Whether rollback is recommended.
    rollbackRecommended @3 :Bool;
    # Health check timestamp.
    checkedAt @4 :T.Timestamp;
}

# Audit-8: update dependency (ordering constraint).
struct UpdateDependency {
    packageId @0 :T.PackageId;
    # Packages that must be updated before this one.
    dependsOn @1 :List(T.PackageId);
    # Packages that conflict with this update.
    conflictWith @2 :List(T.PackageId);
    # Install order (lower = earlier).
    installOrder @3 :UInt32;
}

# Audit-9: device group for fleet orchestration.
struct DeviceGroup {
    groupId @0 :T.DeviceGroupId;
    name @1 :Text;
    deviceCount @2 :UInt32;
    createdAt @3 :T.Timestamp;
}

# Audit-9: rollout step for multi-step rollouts.
struct RolloutStep {
    stepId @0 :UInt32;
    name @1 :Text;
    # Percentage of devices to advance to this step.
    targetPercentage @2 :UInt8;
    # Whether this step requires explicit confirmation.
    requiresConfirmation @3 :Bool;
    # Whether rollback is allowed from this step.
    rollbackAllowed @4 :Bool;
}

# Audit-9: update quarantine status.
struct UpdateQuarantine {
    packageId @0 :T.PackageId;
    # Whether the update is in quarantine.
    quarantined @1 :Bool;
    # Reason for quarantine.
    reason @2 :Text;
    # When the update was placed in quarantine.
    quarantinedAt @3 :T.Timestamp;
    # Quarantine expires at this time (0 = never).
    expiresAt @4 :T.Timestamp;
}

# ─── Fleet Rollback (audit-10) ─────────────────────────────

enum RollbackScope {
    singleDevice @0;
    deviceGroup @1;
    fleet @2;
    custom @3;
}

struct FleetRollbackRequest {
    packageId @0 :T.PackageId;
    scope @1 :RollbackScope;
    groupId @2 :T.DeviceGroupId;
    # Whether to rollback immediately or staged.
    immediate @3 :Bool;
    # Maximum devices to rollback in parallel.
    batchSize @4 :UInt32;
}

struct FleetRollbackStatus {
    packageId @0 :T.PackageId;
    scope @1 :RollbackScope;
    groupId @2 :T.DeviceGroupId;
    # Total devices to rollback.
    totalDevices @3 :UInt32;
    # Devices rolled back successfully.
    completed @4 :UInt32;
    # Devices where rollback failed.
    failed @5 :UInt32;
    # Devices pending rollback.
    pending @6 :UInt32;
    state @7 :Text;
}

# ─── Rollout Pause/Resume (audit-10) ───────────────────────

enum RolloutState {
    running @0;
    paused @1;
    completed @2;
    failed @3;
    cancelled @4;
    custom @5;
}

struct RolloutStatus {
    packageId @0 :T.PackageId;
    state @1 :RolloutState;
    currentStep @2 :UInt32;
    totalSteps @3 :UInt32;
    percentageComplete @4 :UInt8;
    # When the rollout was paused (if paused).
    pausedAt @5 :T.Timestamp;
    # Reason for pause.
    pauseReason @6 :Text;
}

# ─── Signed Update Application (audit-10) ──────────────────

struct SignedUpdatePackage {
    packageId @0 :T.PackageId;
    # Signed delta patch.
    delta @1 :DeltaPatch;
    # Verification chain.
    chain @2 :VerifyChain;
    # Signature over the entire package.
    signature @3 :T.DataHandle;
}

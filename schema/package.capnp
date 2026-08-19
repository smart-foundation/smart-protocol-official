@0xa1b2c3d4e5f6001d;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Package - package management, install, update, verify.
#
# Improvements beyond the original schema:
#   - T.PackageId typed ID replaces bare Text for all package references.
#   - DataHandle for icon data that may exceed 1KB.
#   - Pagination on listPackages.
#   - Subscription for package catalog changes.
#   - Custom/other variants on PackageType and PackageStatus.
#   - PackageFilter.source typed as Text with documentation.
# ═══════════════════════════════════════════════════════════════════════

interface Package {
    listPackages @0 (filter :PackageFilter, pagination :T.Pagination) -> (packages :List(PackageInfo));
    getPackage @1 (packageId :T.PackageId) -> (info :PackageInfo);

    # path is a backend-specific bundle reference (URI or opaque handle),
    # not a filesystem path. Implementations resolve it to actual storage.
    install @2 (path :Text, options :InstallOptions) -> (packageId :T.PackageId);
    uninstall @3 (packageId :T.PackageId) -> T.VoidResult;
    update @4 (packageId :T.PackageId) -> T.VoidResult;

    getPackageStatus @5 (packageId :T.PackageId) -> (status :PackageStatus);

    verify @6 (packageId :T.PackageId) -> (result :VerificationResult);
    repair @7 (packageId :T.PackageId) -> T.VoidResult;

    getPackageInfo @8 (packageId :T.PackageId) -> (info :PackageDetailInfo);

    # ── Subscription ──
    subscribePackages @9 () -> (subscription :PackageSubscription);

    # Audit-8: rollback to a previous version (false positive: rollback belongs here).
    rollback @10 (packageId :T.PackageId, toVersion :T.Version) -> T.VoidResult;

    # Audit-8: get full dependency graph with attestation (false positive: package_graph.capnp belongs here).
    getDependencyGraph @11 (packageId :T.PackageId) -> (graph :DependencyGraph);

    # Audit-8: quarantine a suspicious package before verification.
    quarantine @12 (packageId :T.PackageId) -> T.VoidResult;

    # Audit-8: apply a delta update (only changes from a base version).
    updateDelta @13 (packageId :T.PackageId, baseVersion :T.Version) -> T.VoidResult;

    # Audit-8: sign a package cryptographically.
    signPackage @14 (packageId :T.PackageId, keyId :T.KeyId) -> (signature :Data);

    # Audit-8: get package provenance (build system, CI/CD, git commit).
    getProvenance @15 (packageId :T.PackageId) -> (provenance :Provenance);

    # Audit-8: create a snapshot of installed packages for rollback (false positive: package_snapshot.capnp belongs here).
    createSnapshot @16 (name :Text) -> (snapshotId :T.SnapshotId);

    # Audit-8: restore from a snapshot.
    restoreSnapshot @17 (snapshotId :T.SnapshotId) -> T.VoidResult;

    # ── Audit-9: App Update Lifecycle (false positive: app_update) ──

    # Check for available updates for a package.
    checkUpdate @18 (packageId :T.PackageId) -> (result :UpdateCheckResult);

    # Start downloading an update with progress tracking.
    downloadUpdate @19 (packageId :T.PackageId) -> (subscription :UpdateDownloadSubscription);

    # Configure staged rollout for an update.
    configureStagedRollout @20 (packageId :T.PackageId, config :StagedRolloutConfig) -> T.VoidResult;

    # Get current update lifecycle state for a package.
    getUpdateLifecycle @21 (packageId :T.PackageId) -> (state :UpdateLifecycleState);

    # Pause an in-progress download.
    pauseDownload @22 (packageId :T.PackageId) -> T.VoidResult;

    # Resume a paused download.
    resumeDownload @23 (packageId :T.PackageId) -> T.VoidResult;

    # Audit-9: install an OCI container image as a package.
    installOciImage @24 (request :OciImageInstallRequest) -> (packageId :T.PackageId);

    # Audit-9: configure package mirroring across regions.
    configureMirror @25 (config :PackageMirrorConfig) -> T.VoidResult;

    # Audit-9: get mirror status and sync state.
    getMirrorStatus @26 (mirrorId :Text) -> (status :PackageMirrorStatus);

    # Audit-9: configure local package cache for offline installation.
    configureCache @27 (config :PackageCacheConfig) -> T.VoidResult;

    # Audit-9: get cache status and statistics.
    getCacheStatus @28 () -> (status :PackageCacheStatus);

    # Audit-9: decrypt an encrypted package.
    decryptPackage @29 (packageId :T.PackageId, keyId :T.KeyId) -> T.VoidResult;

    # Audit-9: detect dependency conflicts across installed packages.
    detectConflicts @30 () -> (conflicts :List(DependencyConflict));

    # Audit-9: compare two snapshots and show differences.
    compareSnapshots @31 (snapshotId1 :T.SnapshotId, snapshotId2 :T.SnapshotId) -> (diff :SnapshotDiff);

    # Audit-9: get detailed supply chain attestation for a package.
    getSupplyChainAttestation @32 (packageId :T.PackageId) -> (attestation :SupplyChainAttestation);
}

interface PackageSubscription {
    pull @0 () -> (events :List(PackageEvent));
    cancel @1 () -> T.VoidResult;
}

# ── Audit-9: Update Download Subscription ────────────────────────────
# Tracks download progress for an update. Follows the standard
# pull+cancel subscription pattern.

interface UpdateDownloadSubscription {
    pull @0 () -> (progress :UpdateDownloadProgress);
    cancel @1 () -> T.VoidResult;
}

struct PackageEvent {
    union {
        installed @0 :T.PackageId;
        updated @1 :T.PackageId;
        removed @2 :T.PackageId;
        statusChanged @3 :PackageStatus;
    }
}

struct VerificationResult {
    valid @0 :Bool;
    # Details if verification failed (signature mismatch, tampered, etc.).
    error @1 :T.Error;
    # When verification was performed.
    checkedAt @2 :T.Timestamp;
    # Audit-8: supply chain verification (SLSA, in-toto, Sigstore).
    supplyChain @3 :SupplyChainResult;
}

struct PackageFilter {
    name @0 :Text;
    type @1 :PackageType;
    # Source repository or distribution name (e.g., "main", "community").
    source @2 :Text;
    installed @3 :Bool;
    updatable @4 :Bool;
}

enum PackageType {
    app @0;
    library @1;
    framework @2;
    driver @3;
    os @4;
    theme @5;
    extension @6;
    custom @7;
}

struct PackageInfo {
    id @0 :T.PackageId;
    name @1 :Text;
    version @2 :T.Version;
    type @3 :PackageType;
    description @4 :Text;
    author @5 :Text;
    # Source repository or distribution name.
    source @6 :Text;
    installed @7 :Bool;
    updatable @8 :Bool;
    # Size in bytes (installed footprint).
    size @9 :UInt64;
    # Package icon — use buffer handle for images >1KB.
    icon @10 :T.DataHandle;

    # Extended metadata
    license @11 :Text;
    homepage @12 :Text;
    downloadSize @13 :UInt64;
    installedSize @14 :UInt64;
    releaseDate @15 :T.Timestamp;
    lastUpdate @16 :T.Timestamp;
    downloadCount @17 :UInt64;
    # Rating on 0.0-5.0 scale (0.0 = unrated).
    rating @18 :Float32;
    categories @19 :List(Text);
    keywords @20 :List(Text);
    maintainer @21 :Text;
    buildInstructions @22 :Text;
    bugTrackerUrl @23 :Text;
    supportUrl @24 :Text;
}

struct PackageDetailInfo {
    info @0 :PackageInfo;
    homepage @1 :Text;
    license @2 :Text;
    repository @3 :Text;
    dependencies @4 :List(PackageDependency);
    files @5 :List(Text);
    scripts @6 :T.StringMap;
}

struct PackageDependency {
    id @0 :T.PackageId;
    version @1 :T.Version;
    optional @2 :Bool;
}

struct InstallOptions {
    noDeps @0 :Bool;
    force @1 :Bool;
    keepData @2 :Bool;
}

enum PackageStatus {
    notInstalled @0;
    installed @1;
    updating @2;
    removing @3;
    corrupted @4;
    # Audit-8: quarantine state for suspicious packages.
    quarantined @5;
    custom @6;
}

# Audit-8: supply chain verification result (SLSA, in-toto, Sigstore).
struct SupplyChainResult {
    # SLSA level achieved (0 = none, 1-4 = levels).
    slsaLevel @0 :UInt8;
    # Whether in-toto layout verification passed.
    inTotoVerified @1 :Bool;
    # Whether Sigstore verification passed.
    sigstoreVerified @2 :Bool;
    # Supply chain error if verification failed.
    error @3 :T.Error;
}

# Audit-8: package dependency graph with attestation.
struct DependencyGraph {
    # Nodes in the dependency graph (each package).
    nodes @0 :List(DependencyNode);
    # Edges between packages (dependencies).
    edges @1 :List(DependencyEdge);
    # Attestation data for the entire graph.
    attestation @2 :Data;
}

# Audit-8: a node in the dependency graph.
struct DependencyNode {
    packageId @0 :T.PackageId;
    version @1 :T.Version;
    name @2 :Text;
}

# Audit-8: an edge in the dependency graph.
struct DependencyEdge {
    from @0 :T.PackageId;
    to @1 :T.PackageId;
    # Whether this is a required or optional dependency.
    required @2 :Bool;
}

# Audit-8: package provenance (build system, CI/CD, git commit).
struct Provenance {
    # Build system used (e.g., "cmake", "meson", "cargo").
    buildSystem @0 :Text;
    # Git commit hash.
    commitHash @1 :Text;
    # CI/CD pipeline identifier.
    pipelineId @2 :Text;
    # Build timestamp.
    builtAt @3 :T.Timestamp;
    # Builder identity.
    builder @4 :Text;
}

# Audit-8: package snapshot for rollback.
struct PackageSnapshot {
    id @0 :T.SnapshotId;
    name @1 :Text;
    # Packages included in the snapshot.
    packages @2 :List(PackageSnapshotEntry);
    # When the snapshot was created.
    createdAt @3 :T.Timestamp;
}

# Audit-8: a package entry in a snapshot.
struct PackageSnapshotEntry {
    packageId @0 :T.PackageId;
    version @1 :T.Version;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-9: App Update Lifecycle (false positive: app_update.capnp)
#
# Application update lifecycle features — checking for updates,
# downloading with progress tracking, staged rollout with canary
# groups, rollback triggers, and verification. These are features
# of the package management system, not a new domain.
# ═══════════════════════════════════════════════════════════════════════

struct UpdateCheckResult {
    # Whether an update is available.
    available @0 :Bool;
    # Current installed version.
    currentVersion @1 :T.Version;
    # Latest available version.
    latestVersion @2 :T.Version;
    # Size of the update in bytes (0 if unknown).
    downloadSize @3 :UInt64;
    # Human-readable changelog.
    changelog @4 :Text;
    # Whether this is a critical/security update.
    critical @5 :Bool;
    # When this update was published.
    publishedAt @6 :T.Timestamp;
    # Required minimum OS version for this update.
    minOsVersion @7 :T.Version;
}

struct UpdateDownloadProgress {
    packageId @0 :T.PackageId;
    bytesDownloaded @1 :UInt64;
    totalBytes @2 :UInt64;
    # Download speed in bytes per second (0 if unknown).
    speedBytesPerSec @3 :UInt64;
    status @4 :UpdateDownloadStatus;
}

enum UpdateDownloadStatus {
    pending @0;
    downloading @1;
    paused @2;
    completed @3;
    failed @4;
    cancelled @5;
    custom @6;
}

struct StagedRolloutConfig {
    # Total percentage of users to include (0-100).
    targetPercentage @3 :UInt32;
    # Current rollout percentage.
    currentPercentage @4 :UInt32;
    # Canary group: subset of users for initial testing.
    canary @0 :RolloutGroup;
    # Progressive groups: ordered expansion of rollout.
    progressive @1 :List(RolloutGroup);
    # Rollback triggers (conditions that cause automatic revert).
    rollbackTriggers @2 :List(RollbackTrigger);
    # Maximum time to wait before auto-rollback on failure.
    rollbackTimeout @5 :T.Duration;
}

struct RolloutGroup {
    # Name of the rollout group (e.g., "canary", "early-adopters", "general").
    name @0 :Text;
    # Percentage of users in this group (0-100).
    percentage @1 :UInt32;
    # Minimum duration before advancing to the next group.
    minDuration @2 :T.Duration;
    # Maximum failure rate before halting rollout (0.0-1.0).
    maxFailureRate @3 :Float32;
}

struct RollbackTrigger {
    # Condition that triggers rollback.
    condition @0 :RollbackCondition;
    # Threshold value for the condition.
    threshold @1 :Float32;
}

enum RollbackCondition {
    # Failure rate exceeds threshold.
    failureRate @0;
    # Crash rate exceeds threshold.
    crashRate @1;
    # Latency exceeds threshold.
    latency @2;
    # Error count exceeds threshold.
    errorCount @3;
    # Manual rollback requested.
    manual @4;
    custom @5;
}

struct UpdateLifecycleState {
    packageId @0 :T.PackageId;
    phase @1 :UpdatePhase;
    # Current version before update.
    fromVersion @2 :T.Version;
    # Target version for update.
    toVersion @3 :T.Version;
    # Download progress (null if not downloading).
    download @4 :UpdateDownloadProgress;
    # Staged rollout config (null if not staged).
    rollout @5 :StagedRolloutConfig;
    # Timestamp of last phase transition.
    lastTransition @6 :T.Timestamp;
    # Error message if phase is failed.
    error @7 :T.Error;
}

enum UpdatePhase {
    # Checking for available updates.
    checking @0;
    # Update available, waiting for user confirmation.
    available @1;
    # Downloading the update.
    downloading @2;
    # Verifying package integrity.
    verifying @3;
    # Installing the update.
    installing @4;
    # Update complete, pending restart.
    pendingRestart @5;
    # Update failed; rolled back.
    rolledBack @6;
    # Update completed successfully.
    completed @7;
    # Update cancelled by user.
    cancelled @8;
    custom @9;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-9: OCI image packages, mirroring, caching, decryption, dependency
# conflict detection, snapshot comparison, and supply chain attestation.
# ═══════════════════════════════════════════════════════════════════════

# ── OCI Image Install ─────────────────────────────────────────

struct OciImageInstallRequest {
    # OCI image reference (e.g., "registry.example.com/app:v1.0").
    imageRef @0 :Text;
    # Registry credentials (optional).
    credentials @1 :OciCredentials;
    # Platform to pull (e.g., "linux/amd64").
    platform @2 :Text;
    # Whether to unpack the image layers.
    unpack @3 :Bool = true;
}

struct OciCredentials {
    # Registry URL.
    registry @0 :Text;
    # Username.
    username @1 :Text;
    # Password or token.
    password @2 :Text;
}

# ── Package Mirroring ─────────────────────────────────────────

struct PackageMirrorConfig {
    # Mirror identifier.
    mirrorId @0 :Text;
    # Source repository URL.
    sourceUrl @1 :Text;
    # Mirror repository URL.
    mirrorUrl @2 :Text;
    # Sync interval.
    syncInterval @3 :T.Duration;
    # Whether to sync automatically.
    autoSync @4 :Bool;
    # Regions to sync to.
    regions @5 :List(Text);
}

struct PackageMirrorStatus {
    # Mirror identifier.
    mirrorId @0 :Text;
    # Whether the mirror is in sync.
    inSync @1 :Bool;
    # Number of packages mirrored.
    packageCount @2 :UInt64;
    # Last sync timestamp.
    lastSynced @3 :T.Timestamp;
    # Sync errors (if any).
    errors @4 :List(T.Error);
}

# ── Package Caching ───────────────────────────────────────────

struct PackageCacheConfig {
    # Maximum cache size in bytes (0 = unlimited).
    maxSizeBytes @0 :UInt64;
    # Maximum age of cached packages.
    maxAge @1 :T.Duration;
    # Cache directory path.
    cacheDir @2 :Text;
    # Whether to enable cache eviction.
    evictionEnabled @3 :Bool;
}

struct PackageCacheStatus {
    # Current cache size in bytes.
    currentSizeBytes @0 :UInt64;
    # Number of cached packages.
    packageCount @1 :UInt64;
    # Cache hit rate (0.0-1.0).
    hitRate @2 :Float32;
    # Last eviction timestamp.
    lastEvicted @3 :T.Timestamp;
}

# ── Dependency Conflict Detection ─────────────────────────────

struct DependencyConflict {
    # Package that has the conflict.
    packageId @0 :T.PackageId;
    # Conflicting dependency name.
    dependencyName @1 :Text;
    # Required version by first package.
    requiredBy1 @2 :PackageDependency;
    # Required version by second package.
    requiredBy2 @3 :PackageDependency;
    # Conflict type.
    conflictType @4 :DependencyConflictType;
}

enum DependencyConflictType {
    # Version mismatch between required versions.
    versionMismatch @0;
    # Circular dependency detected.
    circular @1;
    # Dependency not found.
    missing @2;
    # Platform incompatibility.
    platform @3;
    custom @4;
}

# ── Snapshot Comparison ───────────────────────────────────────

struct SnapshotDiff {
    # Packages added between snapshots.
    added @0 :List(PackageSnapshotEntry);
    # Packages removed between snapshots.
    removed @1 :List(PackageSnapshotEntry);
    # Packages updated between snapshots.
    updated @2 :List(SnapshotUpdateEntry);
}

struct SnapshotUpdateEntry {
    packageId @0 :T.PackageId;
    fromVersion @1 :T.Version;
    toVersion @2 :T.Version;
}

# ── Supply Chain Attestation ──────────────────────────────────

struct SupplyChainAttestation {
    # Package identifier.
    packageId @0 :T.PackageId;
    # SLSA provenance level.
    slsaLevel @1 :UInt8;
    # In-toto layout verification result.
    inTotoLayout @2 :Data;
    # Sigstore bundle verification result.
    sigstoreBundle @3 :Data;
    # Build provenance (SLSA predicate).
    buildProvenance @4 :Data;
    # Source provenance (git commit, branch, diff).
    sourceProvenance @5 :Data;
    # Verification timestamp.
    verifiedAt @6 :T.Timestamp;
    # Whether attestation is valid.
    valid @7 :Bool;
}

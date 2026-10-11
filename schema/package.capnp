@0xa1b2c3d4e5f6001d;

# ═══════════════════════════════════════════════════════════════════════
# Package - package management, install, update, verify.
#
# WHAT THIS IS
#   Install, uninstall, update, verify, snapshot and inspect. This service
#   owns INSTALL STATE; what a bundle IS comes from manifest.capnp.
#
# THE BUNDLE SELF-DESCRIPTION IS THE MANIFEST
#   `PackageInfo` used to re-declare name, version, description, license,
#   homepage, author and dependencies — all of which `Manifest` already owns
#   and all of which had to be kept in sync by hand. `Provenance` was a
#   byte-identical twin of `ManifestProvenance`, which is the proof the
#   duplication had already drifted. `PackageInfo` now embeds the manifest
#   and carries only what this service knows: whether it is installed,
#   whether it is updatable, how big it is, and where it came from.
#
#   That closes the founder's rule for apps: AN APP FORMAT THAT DOES NOT
#   EXIST YET is describable by adding a Manifest, with no change to this
#   file. `PackageType` (app/library/framework/driver/os/theme/extension)
#   was a closed taxonomy of today's package kinds and is deleted — a 2046
#   bundle kind (a model, a policy pack, a sandbox profile) has no ordinal,
#   and `Manifest.shape` already answers the question with `custom`.
#
# NO PLAINTEXT CREDENTIALS ON THE WIRE
#   `OciCredentials { registry, username, password :Text }` put a registry
#   password in a protocol message. It is gone: a bundle fetch carries an
#   opaque SECRET REFERENCE the caller obtained from the secret service, and
#   the backend resolves it against credentials the protocol never sees.
#
# THE INSTALL PATH IS FORMAT-OPEN
#   `installOciImage` and `OciImageInstallRequest` made OCI containers a
#   first-class install path with OCI's own vocabulary (media types,
#   "linux/amd64" platform strings, unpack semantics) — one 2026 distribution
#   technology in an eternal contract. `installBundle` takes an opaque
#   reference, an open content type, an open platform token and a secret
#   reference. An OCI image is one content type among any number.
#
# INSTALL FAILURES STOP MASQUERADING AS SUCCESS
#   `install` returned a bare `T.PackageId`. Install failures are the NORMAL
#   case — signature mismatch, dependency conflict, quarantine verdict,
#   insufficient space — and every one of them arrived as a valid-looking id
#   an app would show as installed. It now returns `InstallResult`, mirroring
#   the `VerificationResult` shape this file already got right.
#
# WHAT ELSE WAS DELETED
#   - The mirror fleet (`configureMirror`, `getMirrorStatus`,
#     `PackageMirrorConfig`, `PackageMirrorStatus`) and the cache
#     (`configureCache`, `getCacheStatus`, `PackageCacheConfig`,
#     `PackageCacheStatus`): a distribution SERVER's topology and a cache
#     FILESYSTEM PATH as interop contract. Neither crosses a trust boundary;
#     both force every other package backend to pretend.
#   - The supply-chain apparatus (`SupplyChainResult`,
#     `SupplyChainAttestation`, `getSupplyChainAttestation`): SLSA, in-toto
#     and Sigstore named in required fields, which is today's tooling frozen
#     as a dependency. A 2035 attestation ecosystem names none of them, and
#     the fields would silently mean `false` forever. Verification is still
#     a first-class result — it just does not name today's three tools.
#   - `signPackage`: signing is signature.capnp's operation and the key is
#     key_management's, so this was a third home for one action.
#   - `decryptPackage`: decryption by key reference belongs to the secret
#     and key services, not the installer.
#   - Staged rollout (`configureStagedRollout`, `StagedRolloutConfig`,
#     `RolloutGroup`, `RollbackTrigger`, `RollbackCondition`): deployment-ops
#     vocabulary — canary percentages, rollback on latency or crash rate. A
#     distribution operator configures that; it is not interop.
#   - `PackageDetailInfo.scripts`: install scripts as protocol data with no
#     execution contract, which is the same hazard as extension.capnp's
#     script action.
#
# WHAT WAS KEPT, AND WHY
#   The update lifecycle (`checkUpdate`, `downloadUpdate`,
#   `getUpdateLifecycle`, pause/resume) is observable STATE, not an
#   algorithm — the Agnostic Test's own edge case says reject the algorithm
#     and accept the state, and every backend must report where an update is.
#     Snapshots, quarantine, verification and conflict detection are real
#     install-domain contracts.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using M = import "manifest.capnp";

interface Package {
    listPackages @0 (filter :PackageFilter, pagination :T.Pagination)
                 -> (packages :List(PackageInfo), total :UInt64);
    getPackage @1 (packageId :T.PackageId) -> (result :PackageInfoResult);

    # `reference` is a backend-specific bundle reference (URI, content
    # digest, or opaque handle), NOT a filesystem path. Implementations
    # resolve it to actual storage.
    install @2 (reference :Text, options :InstallOptions)
              -> (result :InstallResult);
    uninstall @3 (packageId :T.PackageId) -> T.VoidResult;
    update @4 (packageId :T.PackageId) -> T.VoidResult;

    getPackageStatus @5 (packageId :T.PackageId) -> (status :PackageStatus);

    verify @6 (packageId :T.PackageId) -> (result :PackageVerification);
    repair @7 (packageId :T.PackageId) -> T.VoidResult;

    getPackageInfo @8 (packageId :T.PackageId) -> (result :PackageDetailResult);

    # ── Subscription ──
    subscribePackages @9 () -> (subscription :PackageSubscription);

    # Rollback to a previous version.
    rollback @10 (packageId :T.PackageId, toVersion :T.Version) -> T.VoidResult;

    # Get the full dependency graph.
    getDependencyGraph @11 (packageId :T.PackageId)
                       -> (result :DependencyGraphResult);

    # Quarantine a suspicious package before verification.
    quarantine @12 (packageId :T.PackageId) -> T.VoidResult;

    # Apply a delta update (only changes from a base version).
    updateDelta @13 (packageId :T.PackageId, baseVersion :T.Version) -> T.VoidResult;

    # Create a snapshot of installed packages for rollback.
    createSnapshot @14 (name :Text) -> (snapshotId :T.SnapshotId);

    # Restore from a snapshot.
    restoreSnapshot @15 (snapshotId :T.SnapshotId) -> T.VoidResult;

    # ── Update Lifecycle ─────────────────────────────────────

    # Check for available updates for a package.
    checkUpdate @16 (packageId :T.PackageId) -> (result :UpdateCheckResult);

    # Start downloading an update with progress tracking.
    downloadUpdate @17 (packageId :T.PackageId)
                   -> (subscription :UpdateDownloadSubscription);

    # Get current update lifecycle state for a package.
    getUpdateLifecycle @18 (packageId :T.PackageId)
                       -> (state :UpdateLifecycleState);

    # Pause an in-progress download.
    pauseDownload @19 (packageId :T.PackageId) -> T.VoidResult;

    # Resume a paused download.
    resumeDownload @20 (packageId :T.PackageId) -> T.VoidResult;

    # ── Bundle install (format-open) ─────────────────────────

    # Install a bundle whose format is named by an open content type. An OCI
    # image is one such type; a 2035 bundle format is another, with no
    # schema change.
    installBundle @21 (bundle :BundleInstallRequest)
                  -> (result :InstallResult);

    # Detect dependency conflicts across installed packages.
    detectConflicts @22 () -> (conflicts :List(DependencyConflict));

    # Compare two snapshots and show differences.
    compareSnapshots @23 (snapshotId1 :T.SnapshotId, snapshotId2 :T.SnapshotId)
                     -> (diff :SnapshotDiff);
}

interface PackageSubscription {
    pull @0 (maxEvents :UInt32) -> (events :List(PackageEvent));
    cancel @1 () -> T.VoidResult;
}

# Tracks download progress for an update.
interface UpdateDownloadSubscription {
    pull @0 (maxEvents :UInt32) -> (progress :UpdateDownloadProgress);
    cancel @1 () -> T.VoidResult;
}

# ── Bundle install ───────────────────────────────────────────

# An install request whose format is a content type, not a named technology.
struct BundleInstallRequest {
    # Opaque reference: a URI, a content digest, or a backend handle.
    reference @0 :Text;
    # Open content type of the bundle, e.g. an OCI image media type or a
    # content-addressed archive.
    format @1 :T.MimeType;
    # Open platform token (e.g. "linux/amd64"), backend-interpreted. Absent
    # means "whatever this host is".
    platform @2 :Text;
    # Credentials to fetch the bundle, as an opaque reference to a secret the
    # caller is authorized to read. NEVER a username and password: a
    # plaintext credential in a protocol message is a credential on the wire.
    credential @3 :T.SecretKeyId;
    # Whether to unpack the bundle's layers.
    unpack @4 :Bool;
    metadata @5 :T.StringMap;
}

# ── Results ───────────────────────────────────────────────────

struct InstallResult {
    union {
        packageId @0 :T.PackageId;
        error     @1 :T.Error;
        unknown   @2 :Void;
    }
}

struct PackageInfoResult {
    union {
        info    @0 :PackageInfo;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct PackageDetailResult {
    union {
        detail  @0 :PackageDetailInfo;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct DependencyGraphResult {
    union {
        graph   @0 :PackageDependencyGraph;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct PackageVerification {
    valid @0 :Bool;
    # Details if verification failed (signature mismatch, tampered, etc.).
    error @1 :T.Error;
    # When verification was performed.
    checkedAt @2 :T.Timestamp;
    metadata @3 :T.StringMap;
}

# ── Events ────────────────────────────────────────────────────

struct PackageEvent {
    union {
        installed @0 :T.PackageId;
        updated @1 :T.PackageId;
        removed @2 :T.PackageId;
        statusChanged @3 :PackageStatus;
        unknown @4 :T.UnknownEvent;
    }
}

struct PackageFilter {
    name @0 :Text;
    installed @1 :T.BoolFilter;
    updatable @2 :T.BoolFilter;
    # Source repository or distribution name — an OPEN token; the sources a
    # backend recognises are published by the backend, not frozen here.
    source @3 :Text;
    # Restrict to a bundle shape (open, from manifest.capnp).
    shape @4 :Text;
}

# ── Package Info ──────────────────────────────────────────────

# The bundle's self-description plus this service's install state. Nothing
# descriptive is declared here: it is all in the Manifest.
struct PackageInfo {
    id @0 :T.PackageId;
    # The bundle's self-description — name, version, description, license,
    # homepage, vendor, capabilities, dependencies, entry points, assets and
    # provenance.
    manifest @1 :M.Manifest;
    installed @2 :Bool;
    updatable @3 :Bool;
    # Installed footprint in bytes.
    size @4 :UInt64;
    # Source repository or distribution name (open token).
    source @5 :Text;
}

struct PackageDetailInfo {
    info @0 :PackageInfo;
    # Installed file paths. Payload contents are assets in the manifest, not
    # duplicated here.
    files @1 :List(T.FilePath);
    metadata @2 :T.StringMap;
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
    # Quarantine state for suspicious packages.
    quarantined @5;
    custom @6;
}

# ── Dependency graph ─────────────────────────────────────────

# Named PackageDependencyGraph: `DependencyGraph` also exists in
# discovery.capnp for a SERVICE graph, and one name for two graphs is how a
# client reads the wrong one.
struct PackageDependencyGraph {
    # Nodes in the dependency graph (each package).
    nodes @0 :List(DependencyNode);
    # Edges between packages (dependencies).
    edges @1 :List(DependencyEdge);
    # Attestation data for the entire graph.
    attestation @2 :Data;
}

struct DependencyNode {
    packageId @0 :T.PackageId;
    version @1 :T.Version;
    name @2 :Text;
}

struct DependencyEdge {
    from @0 :T.PackageId;
    to @1 :T.PackageId;
    # Whether this is a required or optional dependency.
    required @2 :Bool;
}

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

# ── Snapshots ─────────────────────────────────────────────────

struct PackageSnapshot {
    id @0 :T.SnapshotId;
    name @1 :Text;
    # Packages included in the snapshot.
    packages @2 :List(PackageSnapshotEntry);
    # When the snapshot was created.
    createdAt @3 :T.Timestamp;
}

struct PackageSnapshotEntry {
    packageId @0 :T.PackageId;
    version @1 :T.Version;
}

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

# ── Update Lifecycle ─────────────────────────────────────────

struct UpdateCheckResult {
    union {
        available @0 :UpdateAvailable;
        # No update is available. An answer, not a fault.
        upToDate @1 :Void;
        error @2 :T.Error;
        unknown @3 :Void;
    }
}

struct UpdateAvailable {
    # Current installed version.
    currentVersion @0 :T.Version;
    # Latest available version.
    latestVersion @1 :T.Version;
    # Size of the update in bytes (0 if unknown).
    downloadSize @2 :UInt64;
    # Human-readable changelog.
    changelog @3 :Text;
    # Whether this is a critical/security update.
    critical @4 :Bool;
    # When this update was published.
    publishedAt @5 :T.Timestamp;
    # Required minimum OS version for this update.
    minOsVersion @6 :T.Version;
    metadata @7 :T.StringMap;
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

# Observable STATE, not the algorithm that produced it: every backend must
# report where an update is, and none is required to reach a phase the same
# way. `custom` covers a pipeline step this schema was frozen before.
struct UpdateLifecycleState {
    packageId @0 :T.PackageId;
    phase @1 :UpdatePhase;
    # Current version before update.
    fromVersion @2 :T.Version;
    # Target version for update.
    toVersion @3 :T.Version;
    # Download progress (absent if not downloading).
    download @4 :UpdateDownloadProgress;
    # Timestamp of last phase transition.
    lastTransition @5 :T.Timestamp;
    # Error if the phase is failed.
    error @6 :T.Error;
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

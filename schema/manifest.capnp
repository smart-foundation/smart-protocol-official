@0xa1b2c3d4e5f60037;

# ═══════════════════════════════════════════════════════════════════════
# Manifest - bundle self-description.
#
# Anything that is installed, dispatched, snapshotted, or distributed
# declares itself through a Manifest. Apps, services, devices, plug-ins,
# snapshots, payload bundles - all use the same shape.
#
# A Manifest can describe a frontend app on a phone, a backend service in
# a data center, a sensor firmware blob, or a web app zip. The protocol
# is timeless; implementations specialize at deploy time.
#
# ── WHY THIS FILE IS LOAD-BEARING ───────────────────────────────────────
#
# This is the answer to "an app format that does not exist yet must be
# describable without schema change". Format knowledge never enters the
# contract: a bundle declares its shape, its ABIs, its entry points, its
# capability requirements and its dependencies HERE, and every consumer
# (package.capnp, appindex.capnp, app.capnp) references this file rather
# than re-declaring bundle metadata. Until this revision nothing in the
# protocol consumed a Manifest at all — the package service, the index and
# the app service each carried their own copy of name/version/license/
# homepage, and the copies had already drifted.
#
# ── ADDRESSING, FIXED ───────────────────────────────────────────────────
#
# `resolve` took a `T.ManifestName`, which is an opaque UInt64, while this
# file's own text said a manifest name is "unique within issuer's
# namespace". A consumer that knows `org.example.editor` had no way to
# address anything, so every backend shipped its own name registry and a
# non-interoperable string→id map. `resolveByName` now exists, taking the
# human name and its issuer namespace; `resolve` remains for callers
# holding a typed reference.
#
# ── DELETED ─────────────────────────────────────────────────────────────
#
# `VersionRange` and `DependencyWithAttestation` were orphans referenced by
# no method, no struct and no interface — a second draft of `Dependency`
# that would have misled implementers about which shape was normative.
# `Dependency` already carries attestation and min/max.
#
# `OciImageManifest` and `OciDescriptor`, and `BundleShape.ociImage`: OCI is
# one 2010s container format, and naming it as a bundle SHAPE froze a
# distribution format into the timeless file. The generic `container` shape
# plus an open `Asset.mime` covers it, and a 2046 distribution format
# (content-addressed bundles, model packages) needs no ordinal.
#
# `Semver` — a second version type with 16-bit components, two schemas deep,
# while `T.Version` already carries UInt32 components, epoch and preRelease.
# A 16-bit major wraps at 65535. Every field in THIS file now uses
# `T.Version`, so app, package, index and manifest compare versions with one
# struct. The type is still exported, marked for deletion, for one external
# importer — see the compatibility note below.
#
# ── FIXED ───────────────────────────────────────────────────────────────
#
# `ManifestEvent` had no `unknown` variant — validator E6 flagged it, in the
# one file held up as timeless. A future catalog event (deprecation,
# migration, attestation revocation) arrived at old consumers as an
# unrecognizable union member with no dispatch data.
#
# `validate`, `verify` and `validateDependencies` returned
# `(valid :Bool, errors :List(Text))`: failures as prose, which a consumer
# cannot act on programmatically. They now carry `T.Error` alongside the
# human-readable detail.
#
# `Asset.sizeBytes` was UInt32, silently truncating multi-gigabyte assets.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "abi.capnp".Abi;
using import "capability.capnp".Operation;

struct Manifest {
    # Unique name within issuer's namespace. Opaque reference; the human
    # spelling is resolved through `ManifestService.resolveByName`.
    name @0 :T.ManifestName;
    # Human-readable label.
    displayName @1 :Text;
    # Optional description.
    description @2 :Text;
    # Vendor / author identity.
    vendor @3 :Text;
    # Semantic version. `T.Version`, not a second version type.
    version @4 :T.Version;
    # Stable content hash of the bundle contents.
    contentHash @5 :Data;
    # ABIs this bundle speaks.
    abis @6 :List(Abi);

    # Entry point(s) inside the bundle, backend-agnostic.
    entries @7 :List(EntryPoint);

    # Capabilities requested at install time. As operations over targets —
    # the model this file got right and the app/extension worlds copied
    # badly.
    capabilities @8 :List(CapabilityRequirement);

    # Schemas the bundle depends on for normal operation.
    depends @9 :List(Dependency);

    # Schemas the bundle publishes for dependents.
    offers @10 :List(Dependency);

    # Bundle shape.
    shape @11 :BundleShape;

    # Embedded assets (icons, fonts, etc.).
    assets @12 :List(Asset);

    # Runtime hints; backend may ignore.
    runtimeHints @13 :List(RuntimeHint);

    # Locale support list (BCP47 tags).
    locales @14 :List(Text);

    # Optional home / docs / source url (typed for cross-schema consistency).
    homepage @15 :T.Uri;
    docs @16 :T.Uri;
    source @17 :T.Uri;

    # Icon path(s) within the bundle.
    iconPaths @18 :List(Text);

    # Default CLI args baked into the manifest.
    defaultArgs @19 :List(Text);

    # Manifest inheritance (parent manifest to extend).
    extends @20 :T.ManifestName;

    # Attestation data for supply-chain verification.
    attestation @21 :Data;

    # Manifest provenance (build system, CI/CD, git commit). The single
    # provenance type: package.capnp's byte-identical twin is deleted.
    provenance @22 :ManifestProvenance;
}

struct EntryPoint {
    # Logical name for the entry (e.g. "main", "worker", "dev-mode").
    name @0 :Text;
    # Path inside the bundle.
    path @1 :Text;
    # Optional runtime hint (e.g. "wasm", "python", "native") — an open
    # token, because the runtime of a 2046 entry point has no ordinal.
    runtime @2 :Text;
    # Hint about expected ABI of the entry-point payload.
    payloadAbi @3 :Text;
}

struct CapabilityRequirement {
    # Target this requirement covers.
    target @0 :Text;
    # Operations required.
    operations @1 :List(Operation);
    # Whether the requirement is optional (graceful degradation).
    optional @2 :Bool = false;
    # Reasoning string for the user.
    reason @3 :Text;
}

struct Dependency {
    # Schema id (typed identifier).
    schemaId @0 :T.SchemaId;
    # Schema name (for humans).
    name @1 :Text;
    # Version constraint range.
    minVersion @2 :T.Version;
    maxVersion @3 :T.Version;
    # Whether the dependency is required or optional.
    optional @4 :Bool = false;
    # Attestation data for supply-chain verification.
    attestation @5 :Data;
}

enum BundleShape {
    # Absent means the backend decides; it must never mean a
    # specific paradigm value.
    unspecified @0;
    # Standalone end-user application.
    app @1;
    # Background service.
    service @2;
    # Firmware / device driver / kernel.
    firmware @3;
    # Plug-in for a host application.
    plugin @4;
    # Snapshot / saved state bundle.
    snapshot @5;
    # Pure assets (icons, packs, language data).
    asset @6;
    # Theme / visual customization.
    theme @7;
    # Library / contract provider without own entry point.
    library @8;
    # System manifest (whole-OS shape).
    system @9;
    # User manifest (user-level configuration).
    user @10;
    # Container manifest. The generic shape: an OCI image is an instance of
    # it, described by its assets and its own media types, not by a
    # format-specific ordinal.
    container @11;
    # Federated manifest (cross-repository composition).
    federated @12;
    custom @13;
}

struct Asset {
    # Path inside bundle.
    path @0 :Text;
    # Logical kind of the asset.
    kind @1 :AssetKind;
    # Optional MIME type hint.
    mime @2 :T.MimeType;
    # Optional size in bytes. UInt64: a UInt32 silently truncated
    # multi-gigabyte assets.
    sizeBytes @3 :UInt64;
}

enum AssetKind {
    icon @0;
    model @1;
    font @2;
    audio @3;
    video @4;
    image @5;
    data @6;
    custom @7;
}

struct RuntimeHint {
    # Hint key (e.g. "heap-size-bytes", "threading-model", "network-mode").
    name @0 :Text;
    # Hint value (free-form textual).
    value @1 :Text;
}

# ── Semver: DELETED ───────────────────────────────────────────
# This was a second version type in a protocol that already has `T.Version`
# (UInt32 components, epoch, preRelease). A 16-bit major wraps at 65535,
# and three files comparing versions with three structs is the "one
# canonical home per type" failure this revision removes everywhere else:
# manifest, package, app, appindex and now module.capnp all use `T.Version`.
#
# It survived the revamp for one external importer — module.capnp's
# `ModuleDesc.version` and `RuntimeBinding.minVersion/maxVersion`. The
# 2026-10-10 integration pass migrated that file to `T.Version` and deleted
# the struct. New code MUST use `T.Version`.

# Manifest service - lets backends expose manifest catalog and inscribe new.
interface ManifestService {
    # Resolve a manifest by its typed reference.
    resolve @0 (name :T.ManifestName) -> (result :ManifestResult);
    # List manifests matching a filter.
    list @1 (filter :ManifestFilter, pagination :T.Pagination)
         -> (manifests :List(Manifest), total :UInt64);
    # Subscribe to manifest catalog changes.
    subscribe @2 () -> (subscription :ManifestSubscription);
    pull @3 (maxEvents :UInt32) -> (events :List(ManifestEvent));

    # Compose multiple manifests into one.
    compose @4 (manifests :List(T.ManifestName)) -> (result :ComposeResult);

    # Diff two manifests.
    diff @5 (name1 :T.ManifestName, name2 :T.ManifestName)
         -> (changes :List(ManifestChange));

    # Validate a manifest against schema.
    validate @6 (manifest :Manifest) -> (result :ValidationResult);

    # Sign a manifest.
    sign @7 (name :T.ManifestName, keyId :T.KeyId) -> (signature :Data);

    # Verify a manifest signature.
    verify @8 (name :T.ManifestName) -> (result :VerificationResult);

    # Migrate a manifest to a different shape.
    migrate @9 (name :T.ManifestName, targetShape :BundleShape)
              -> (result :ManifestResult);

    # Create a manifest template.
    createTemplate @10 (base :T.ManifestName, overrides :Manifest)
                    -> (result :ManifestResult);

    # Compose manifests with explicit merge configuration.
    composeWithConfig @11 (manifests :List(T.ManifestName), config :MergeConfig)
                       -> (result :ComposeResult);

    # Validate manifest dependency graph for cycles.
    validateDependencies @12 (name :T.ManifestName) -> (result :ValidationResult);

    # Resolve a manifest by the name its users know, within an issuer
    # namespace. Without this, a consumer holding `org.example.editor` had no
    # way to address anything.
    resolveByName @13 (issuer :Text, name :Text) -> (result :ManifestResult);
}

struct ManifestFilter {
    namePrefix @0 :Text;
    vendorPrefix @1 :Text;
    shape @2 :BundleShape;
    offersSchemaId @3 :T.SchemaId;
}

struct ManifestEvent {
    union {
        added @0 :Manifest;
        removed @1 :T.ManifestName;
        updated @2 :Manifest;
        unknown @3 :T.UnknownEvent;
    }
}

interface ManifestSubscription {
    pull @0 (maxEvents :UInt32) -> (events :List(ManifestEvent));
    cancel @1 () -> T.VoidResult;
}

# ── Results ───────────────────────────────────────────────────

struct ManifestResult {
    union {
        manifest @0 :Manifest;
        # No manifest by that name/issuer. An answer, not a fault.
        notFound @1 :Void;
        error    @2 :T.Error;
        unknown  @3 :Void;
    }
}

struct ComposeResult {
    union {
        composed @0 :Manifest;
        error    @1 :T.Error;
        unknown  @2 :Void;
    }
}

struct VerificationResult {
    union {
        verified @0 :VerificationOk;
        rejected  @1 :T.Error;
        unknown   @2 :Void;
    }
}

struct VerificationOk {
    signer @0 :Text;
    verifiedAt @1 :T.Timestamp;
    metadata @2 :T.StringMap;
}

# Machine-routable failures. Human-readable detail rides alongside and is
# never the only channel: a consumer that must act on "invalid" needs a code.
struct ValidationResult {
    union {
        valid   @0 :Void;
        invalid @1 :List(T.Error);
        unknown @2 :Void;
    }
    details @3 :List(Text);
}

# ── Diffing and merging ──────────────────────────────────────

# A diff renders field values as text for DISPLAY. The authoritative value is
# read from the manifest itself; a typed union here could not hold a
# List(Dependency) or a List(Abi) without becoming a second model of the
# whole struct.
struct ManifestChange {
    field @0 :Text;
    oldValue @1 :Text;
    newValue @2 :Text;
}

# Manifest provenance (build system, CI/CD, git commit). The single
# provenance type in the protocol.
struct ManifestProvenance {
    buildSystem @0 :Text;
    commitHash @1 :Text;
    pipelineId @2 :Text;
    builtAt @3 :T.Timestamp;
    builder @4 :Text;
}

# Merge strategy for federated manifests.
enum MergeStrategy {
    # Absent means the backend decides; it must never mean a
    # specific paradigm value.
    unspecified @0;
    union @1;
    intersection @2;
    override @3;
    priority @4;
    custom @5;
}

# Explicit configuration for manifest merging.
struct MergeConfig {
    # Strategy for merging manifest fields.
    strategy @0 :MergeStrategy;
    # Fields to exclude from merging.
    excludeFields @1 :List(Text);
    # Fields to include only (empty = all fields).
    includeFields @2 :List(Text);
    # Priority order for priority-based merge (first = highest priority).
    priorityOrder @3 :List(T.ManifestName);
    # Whether to fail on merge conflicts (true = error, false = last-wins).
    strictConflicts @4 :Bool;
}

@0xa1b2c3d4e5f60037;

# ═══════════════════════════════════════════════════════════════════════
# Manifest - bundle self-description
#
# Anything that is installed, dispatched, snapshotted, or distributed
# declares itself through a Manifest. Apps, services, devices, plug-ins,
# snapshots, payload bundles - all use the same shape.
#
# A Manifest can describe a frontend app on a phone, a backend service in
# a data center, a sensor firmware blob, or a web app zip. The protocol
# is timeless; implementations specialize at deploy time.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

struct Manifest {
    # Unique name within issuer's namespace.
    name @0 :T.ManifestName;
    # Human-readable label.
    displayName @1 :Text;
    # Optional description.
    description @2 :Text;
    # Vendor / author identity.
    vendor @3 :Text;
    # Semantic version.
    version @4 :Semver;
    # Stable content hash of the bundle contents.
    contentHash @5 :Data;
    # ABIs this bundle speaks.
    abis @6 :List(Abi);

    # Entry point(s) inside the bundle, backend-agnostic.
    entries @7 :List(EntryPoint);

    # Capabilities requested at install time.
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

    # Audit-8: manifest inheritance (parent manifest to extend).
    extends @20 :T.ManifestName;

    # Audit-8: attestation data for supply-chain verification.
    attestation @21 :Data;

    # Audit-8: manifest provenance (build system, CI/CD, git commit).
    provenance @22 :ManifestProvenance;
}

using import "abi.capnp".Abi;

struct Semver {
    major @0 :UInt16;
    minor @1 :UInt16;
    patch @2 :UInt16;
    prerelease @3 :Text;
    build @4 :Text;
}

struct EntryPoint {
    # Logical name for the entry (e.g. "main", "worker", "dev-mode").
    name @0 :Text;
    # Path inside the bundle.
    path @1 :Text;
    # Optional runtime hint (e.g. "wasm", "python", "native").
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

using import "capability.capnp".Operation;

struct Dependency {
    # Schema id (typed identifier).
    schemaId @0 :T.SchemaId;
    # Schema name (for humans).
    name @1 :Text;
    # Version constraint range (semver-ish).
    minVersion @2 :Semver;
    maxVersion @3 :Semver;
    # Whether the dependency is required or optional.
    optional @4 :Bool = false;
    # Audit-9: attestation data for supply-chain verification.
    attestation @5 :Data;
}

enum BundleShape {
    # Standalone end-user application.
    app @0;
    # Background service.
    service @1;
    # Firmware / device driver / kernel.
    firmware @2;
    # Plug-in for a host application.
    plugin @3;
    # Snapshot / saved state bundle.
    snapshot @4;
    # Pure assets (icons, packs, language data).
    asset @5;
    # Theme / visual customization.
    theme @6;
    # Library / contract provider without own entry point.
    library @7;
    # Audit-8: system manifest (whole-OS shape).
    system @8;
    # Audit-8: user manifest (user-level configuration).
    user @9;
    # Audit-8: container manifest (OCI container shape).
    container @10;
    # Audit-8: OCI image manifest (Docker/OCI distribution).
    ociImage @11;
    # Audit-8: federated manifest (cross-repository composition).
    federated @12;
    custom @13;
}

struct Asset {
    # Path inside bundle.
    path @0 :Text;
    # Logical kind of the asset.
    kind @1 :AssetKind;
    # Optional MIME type hint.
    mime @2 :Text;
    # Optional size in bytes.
    sizeBytes @3 :UInt32;
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

# Manifest service - lets backends expose manifest catalog and inscribe new.
interface ManifestService {
    # Resolve a manifest by name.
    resolve @0 (name :T.ManifestName) -> (manifest :Manifest);
    # List manifests matching a filter.
    list @1 (filter :ManifestFilter, pagination :T.Pagination) -> (manifests :List(Manifest));
    # Subscribe to manifest catalog changes.
    subscribe @2 () -> (subscription :ManifestSubscription);
    pull @3 (subscription :ManifestSubscription) -> (events :List(ManifestEvent));

    # Audit-8: compose multiple manifests into one.
    compose @4 (manifests :List(T.ManifestName)) -> (composed :Manifest);

    # Audit-8: diff two manifests.
    diff @5 (name1 :T.ManifestName, name2 :T.ManifestName) -> (changes :List(ManifestChange));

    # Audit-8: validate a manifest against schema.
    validate @6 (manifest :Manifest) -> (valid :Bool, errors :List(Text));

    # Audit-8: sign a manifest.
    sign @7 (name :T.ManifestName, keyId :T.KeyId) -> (signature :Data);

    # Audit-8: verify a manifest signature.
    verify @8 (name :T.ManifestName) -> (verified :Bool, signer :Text);

    # Audit-8: migrate a manifest to a different shape.
    migrate @9 (name :T.ManifestName, targetShape :BundleShape) -> (migrated :Manifest);

    # Audit-8: create a manifest template.
    createTemplate @10 (base :T.ManifestName, overrides :Manifest) -> (template :Manifest);

    # Audit-10: compose manifests with explicit merge configuration.
    composeWithConfig @11 (manifests :List(T.ManifestName), config :MergeConfig) -> (composed :Manifest);

    # Audit-10: validate manifest dependency graph for cycles.
    validateDependencies @12 (name :T.ManifestName) -> (valid :Bool, errors :List(Text));
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
    }
}

interface ManifestSubscription {
    pull @0 () -> (events :List(ManifestEvent));
    cancel @1 () -> T.VoidResult;
}

# Audit-8: manifest change for diffing.
struct ManifestChange {
    field @0 :Text;
    oldValue @1 :Text;
    newValue @2 :Text;
}

# Audit-8: manifest provenance (build system, CI/CD, git commit).
struct ManifestProvenance {
    buildSystem @0 :Text;
    commitHash @1 :Text;
    pipelineId @2 :Text;
    builtAt @3 :T.Timestamp;
    builder @4 :Text;
}

# Audit-8: dependency with attestation.
struct DependencyWithAttestation {
    schemaId @0 :T.SchemaId;
    name @1 :Text;
    minVersion @2 :Semver;
    maxVersion @3 :Semver;
    optional @4 :Bool;
    attestation @5 :Data;
}

# Audit-8: version range for dependencies.
struct VersionRange {
    min @0 :Semver;
    max @1 :Semver;
}

# Audit-9: OCI image manifest details for ociImage bundle shape.
struct OciImageManifest {
    mediaType @0 :Text;
    schemaVersion @1 :UInt32;
    config @2 :OciDescriptor;
    layers @3 :List(OciDescriptor);
    annotations @4 :T.StringMap;
}

struct OciDescriptor {
    mediaType @0 :Text;
    size @1 :UInt64;
    digest @2 :Text;
}

# Audit-9: merge strategy for federated manifests.
enum MergeStrategy {
    union @0;
    intersection @1;
    override @2;
    priority @3;
    custom @4;
}

# Audit-10: explicit configuration for manifest merging.
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

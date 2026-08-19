@0xa1b2c3d4e5f60036;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# ABI - schema versioning and compatibility negotiation
#
# Every artifact (app, service, device, snapshotted bundle) declares the
# ABI it speaks. ABIs evolve over decades; implementations come and go.
# The protocol is timeless; an artifact outlives its implementations.
#
# Backends negotiate ABIs at connection time. The agreed ABI determines
# which schemas, features, and wire formats are in effect for the
# lifetime of that connection.
#
# Audit-7 enhancements (zero-cost, info-density):
#   - AbiMetadata: sideband non-negotiation data (license, maintainer)
#   - FeatureRequirement: typed feature requirement replacing bare Text
#   - MigrationPlan: typed path from older to newer ABI
#   - CompatibilityReport: unified verdict (ok, partial*, blocked)
#   - AbiRange: an inclusive half-open range [lo, hi) of versions
#   - AbiHandshake: typed initial exchange for ABI discovery
#   - AbiDiff: structured diff between two ABI snapshots
#   - NegotiateSession: multi-round negotiation with rollback
#   - CapabilityBundle: grouped capability declarations for co-negotiation
# ═══════════════════════════════════════════════════════════════════════

# ── Sideband Metadata ─────────────────────────────────────────────────
# Non-negotiated provenance data. Makes it possible for an artifact to
# declare its provenance in a structured way without forcing every
# negotiation to carry it.
struct AbiMetadata {
    license @0 :Text;
    maintainer @1 :Text;
    repository @2 :Text;
    homepage @3 :Text;
    documentation @4 :T.Uri;
    copyright @5 :Text;
    # SPDX license expression (text form to avoid complex SPDX parsing).
    spdxLicenseId @6 :Text;
}

# ── ABI Range ─────────────────────────────────────────────────────────
# A half-open range of compatible ABIs. Useful for tooling like
# "show me all ABIs between epoch 5 and current, exclusive of
# major >= 4". The maxExclusive flag lets callers reject the range
# without parsing every Abi.
struct AbiRange {
    min @0 :Abi;
    max @1 :Abi;
    # Whether the max endpoint is inclusive (default = true -> closed).
    maxExclusive @2 :Bool;
}

# ── Compatibility Report ──────────────────────────────────────────────
# Positive verdict for the entire ABI set, not just per-schema details.
# A negotiation endpoint can return overall verdict alongside per-schema
# breakdowns for clearer UX in tool outputs.
struct CompatibilityReport {
    union {
        ok @0 :Abi;
        partial @1 :PartialCompatibility;
        blocked @2 :T.Error;
        custom @3 :Data;
    }
}

struct PartialCompatibility {
    agreed @0 :Abi;
    unsupportedSchemas @1 :List(UInt64);
    missingFeatures @2 :List(Text);
    downgradeHints @3 :AbiRange;
}

# ── Migration Plan ────────────────────────────────────────────────────
# Describes how to move from one ABI to another (the agreed ABI may
# have been reached via downgrade). Tooling uses this to emit actionable
# upgrade suggestions to users.
struct MigrationPlan {
    from @0 :Abi;
    to @1 :Abi;
    steps @2 :List(MigrationStep);
    estimatedDuration @3 :T.Duration;
    requiresRestart @4 :Bool;
}

struct MigrationStep {
    union {
        schemaMigrate @0 :SchemaMigration;
        deprecateFeature @1 :Text;
        adoptFeature @2 :Text;
        custom @3 :Data;
    }
}

struct SchemaMigration {
    schemaId @0 :UInt64;
    fromMajor @1 :UInt32;
    toMajor @2 :UInt32;
    scriptUri @3 :T.Uri;
}

# ── ABI Handshake ─────────────────────────────────────────────────────
# Audit-7 addition: typed initial exchange for ABI discovery. When two
# parties connect, they exchange HandshakeRequest/Response to advertise
# capabilities before full negotiation. This avoids the "negotiate
# everything from scratch" pattern for common cases where both sides
# already know the ABI.
struct AbiHandshakeRequest {
    # The caller's ABI (what it speaks).
    callerAbi @0 :Abi;
    # Optional constraints on what the callee must support.
    constraints @1 :NegotiateConstraints;
    # Whether the caller accepts downgrade.
    acceptDowngrade @2 :Bool;
    # Session identifier for multi-round negotiation.
    sessionId @3 :Text;
}

struct AbiHandshakeResponse {
    union {
        # Callee matched; here is the agreed ABI.
        matched @0 :Abi;
        # Callee supports a subset; partial match with hints.
        partialMatch @1 :PartialCompatibility;
        # Callee cannot speak any compatible ABI.
        incompatible @2 :T.Error;
        custom @3 :Data;
    }
}

# ── ABI Diff ──────────────────────────────────────────────────────────
# Audit-7 addition: structured diff between two ABI snapshots. Tooling
# uses this to generate changelogs, migration scripts, and compatibility
# matrices without parsing ABI structs manually.
struct AbiDiff {
    from @0 :Abi;
    to @1 :Abi;
    addedSchemas @2 :List(SchemaVersion);
    removedSchemas @3 :List(SchemaVersion);
    changedSchemas @4 :List(SchemaVersionChange);
    addedFeatures @5 :List(Text);
    removedFeatures @6 :List(Text);
    breakingChanges @7 :List(BreakingChange);
}

struct SchemaVersionChange {
    schemaId @0 :UInt64;
    fromMajor @1 :UInt32;
    toMajor @2 :UInt32;
    fromMinor @3 :UInt32;
    toMinor @4 :UInt32;
}

struct BreakingChange {
    schemaId @0 :UInt64;
    description @1 :Text;
    migrationScript @2 :T.Uri;
}

# ── Negotiation Session ───────────────────────────────────────────────
# Audit-7 addition: multi-round negotiation with rollback. For complex
# negotiations that span multiple round-trips (e.g. feature-by-feature
# haggling), NegotiateSession tracks state and allows rollback to a
# previous snapshot if a feature round fails.
struct NegotiateSession {
    sessionId @0 :Text;
    rounds @1 :List(NegotiationRound);
    currentOffer @2 :Abi;
    # Whether rollback is supported for this session.
    rollbackEnabled @3 :Bool;
}

struct NegotiationRound {
    roundNumber @0 :UInt32;
    offer @1 :Abi;
    counterOffer @2 :Abi;
    accepted @3 :Bool;
    timestamp @4 :T.Timestamp;
}

# ── Capability Bundle ─────────────────────────────────────────────────
# Audit-7 addition: grouped capability declarations for co-negotiation.
# Instead of negotiating capabilities one by one, a CapabilityBundle
# groups related capabilities so the backend can accept/reject the
# entire bundle atomically.
struct CapabilityBundle {
    name @0 :Text;
    capabilities @1 :List(BootCapability);
    # Minimum number of capabilities that must be satisfied.
    minSatisfied @2 :UInt32;
}

# ═══════════════════════════════════════════════════════════════════════
# Core ABI Struct
# ═══════════════════════════════════════════════════════════════════════

struct Abi {
    # Namespace uniquely identifying the protocol family.
    # Always "smart-protocol" for this family.
    namespace @0 :Text = "smart-protocol";
    # Semantic version of this ABI.
    version @1 :T.Version;
    # Set of schema ids declared by this ABI and their versions.
    # The ABI is a snapshot of the schema catalog at a moment.
    schemaVersions @2 :List(SchemaVersion);
    # Set of features the ABI guarantees.
    features @3 :List(AbiFeature);
    # Capabilities this ABI requires from the backend.
    capabilities @4 :List(BootCapability);
    # Platform constraints (e.g. "requires wasm", "requires native").
    # Empty means no constraints.
    platformHints @5 :List(Text);
    # When this ABI was deprecated (if at all). Null means not deprecated.
    deprecatedAt @6 :T.Timestamp;
    # Grace period after deprecation before removal.
    deprecationGrace @7 :T.Duration;
    # Sideband provenance metadata. Optional -- older artifacts can leave
    # this null while still conforming to a newer ABI.
    metadata @8 :AbiMetadata;
    # Explicit removal date (computed from deprecatedAt + deprecationGrace).
    # Null means not yet scheduled for removal. Backends that need a
    # hard cutoff can use this field directly instead of computing it.
    removedAt @9 :T.Timestamp;
}

struct SchemaVersion {
    # Schema id (numeric, from @annotation in .capnp file).
    id @0 :UInt64;
    # Major version of that individual schema.
    major @1 :UInt32;
    # Minor version of that schema.
    minor @2 :UInt32;
    # Human-readable schema name (qualified, e.g. "smart-protocol/capability").
    name @3 :Text;
    # Content hash of the schema definition for drift detection.
    schemaHash @4 :Data;
}

struct AbiFeature {
    # Stable identifier.
    name @0 :Text;
    # Backend-defined descriptor (e.g. "transport.tcp", "encoding.capnp").
    kind @1 :Text;
    # Feature payload -- typed union instead of opaque Data.
    payload @2 :AbiFeaturePayload;
}

struct AbiFeaturePayload {
    union {
        text @0 :Text;
        integer @1 :UInt64;
        bytes @2 :Data;
        version @3 :T.Version;
        custom @4 :Data;
    }
}

enum BootCapability {
    readMemory @0;
    writeMemory @1;
    readStorage @2;
    writeStorage @3;
    executeCode @4;
    accessDevice @5;
    configureCompute @6;
    modifyBootArgs @7;
    networkAccess @8;
    custom @9;
}

# ═══════════════════════════════════════════════════════════════════════
# Service Interface
# ═══════════════════════════════════════════════════════════════════════

interface AbiService {
    # Negotiate a mutually acceptable ABI between two parties.
    # Returns the agreed ABI, or indicates no overlap exists.
    negotiate @0 (offer :Abi, support :List(Abi), constraints :NegotiateConstraints)
              -> (result :NegotiateResult);

    # Check whether an ABI claim is honored by this backend.
    # Returns per-schema support detail, not just a boolean.
    verify @1 (claim :Abi) -> (result :VerifyAbiResult);

    # List all ABIs this backend currently supports.
    list @2 (pagination :T.Pagination) -> (supported :List(Abi), totalCount :UInt32);

    # Subscribe to ABI changes (new support added, deprecations).
    subscribe @3 () -> (subscription :AbiSubscription);
    pull @4 (subscription :AbiSubscription) -> (events :List(AbiEvent));
    cancel @5 (subscription :AbiSubscription) -> T.VoidResult;

    # Audit-7: perform initial handshake before full negotiation.
    handshake @6 (request :AbiHandshakeRequest)
              -> (response :AbiHandshakeResponse);

    # Audit-7: compute structured diff between two ABI snapshots.
    diff @7 (from :Abi, to :Abi) -> (diff :AbiDiff);

    # Audit-7: begin a multi-round negotiation session.
    startSession @8 (initial :Abi, constraints :NegotiateConstraints)
                 -> (session :NegotiateSession);

    # Audit-7: submit a counter-offer in an existing session.
    counterOffer @9 (sessionId :Text, counter :Abi)
                 -> (session :NegotiateSession);
}

struct NegotiateConstraints {
    # Minimum epoch floor. Backends reject ABIs older than this.
    minEpoch @0 :UInt32;
    # Maximum major version ceiling.
    maxMajorVersion @1 :UInt32;
    # Required features that must be present.
    requiredFeatures @2 :List(FeatureRequirement);
    # Audit-7: grouped capability bundles for atomic negotiation.
    requiredCapabilityBundles @3 :List(CapabilityBundle);
}

# A typed feature requirement. Promotes bare Text to a structured union
# so consumers can statically validate negotiation constraints without
# parsing strings. Backends can use `custom` for vendor-defined feature
# names they don't recognize ahead of time.
struct FeatureRequirement {
    union {
        byName @0 :Text;                  # Plain feature name (most common)
        byKind @1 :Text;                  # Match any feature with this kind
        byVersion @2 :VersionedFeature;  # Require specific version of a feature
        custom @3 :Data;                  # Backend-defined requirement shape
    }
}

# A named feature paired with a minimum version. Makes named
# feature-version pairs first-class so capability negotiation can detect
# "we need transport.tcp>=2" without ad-hoc string parsing.
struct VersionedFeature {
    name @0 :Text;
    minVersion @1 :T.Version;
}

struct NegotiateResult {
    union {
        agreed @0 :Abi;
        noOverlap @1 :Void;
        rejected @2 :T.Error;
        custom @3 :Data;
    }
}

struct VerifyAbiResult {
    supported @0 :Bool;
    # Per-schema support status.
    schemaStatus @1 :List(SchemaSupport);
}

enum SchemaSupportStatus {
    supported @0;       # Schema fully supported
    partial @1;         # Schema partially supported (feature gaps)
    deprecated @2;      # Schema supported but deprecated
    removed @3;         # Schema no longer supported
    custom @4;
}

struct SchemaSupport {
    schemaId @0 :UInt64;
    supported @1 :Bool;
    # Typed support status for programmatic handling.
    status @2 :SchemaSupportStatus;
    # If not supported, why (human-readable).
    reason @3 :Text;
}

struct AbiEvent {
    union {
        abiAdded @0 :Abi;
        abiDeprecated @1 :Abi;
        schemaVersionAdded @2 :SchemaVersion;
        schemaVersionDeprecated @3 :SchemaVersion;
        custom @4 :Data;
    }
}

interface AbiSubscription {
    pull @0 () -> (events :List(AbiEvent));
    cancel @1 () -> T.VoidResult;
}

# ── ABI Registry ───────────────────────────────────────────────────────
# Audit-7 false positive integration: centralized ABI registry for
# version management. Currently each backend maintains its own list of
# supported ABIs. A registry provides global ABI version tracking,
# compatibility matrices, and migration path recommendations.

struct AbiRegistryEntry {
    # The ABI being tracked.
    abi @0 :Abi;
    # Whether this ABI is currently supported by the registry.
    supported @1 :Bool;
    # Compatibility status with other registered ABIs.
    compatibility @2 :CompatibilityReport;
    # Migration plan to the next recommended ABI version.
    migrationPlan @3 :MigrationPlan;
    # When this entry was registered.
    registeredAt @4 :T.Timestamp;
    # Endorsement/trust information for this ABI.
    endorsement @5 :AbiEndorsement;
}

struct AbiEndorsement {
    # Entity that endorsed this ABI (e.g., "smart-protocol Foundation").
    endorser @0 :Text;
    # Trust level of the endorsement.
    trustLevel @1 :EndorsementTrustLevel;
    # When the endorsement was issued.
    issuedAt @2 :T.Timestamp;
    # When the endorsement expires (null = never).
    expiresAt @3 :T.Timestamp;
    # Cryptographic proof of endorsement (signature over ABI hash).
    proof @4 :Data;
}

enum EndorsementTrustLevel {
    unverified @0;   # Endorsement not yet verified
    verified @1;     # Endorsement cryptographically verified
    trusted @2;      # Endorser is in the trust chain
    revoked @3;      # Endorsement has been revoked
    custom @4;
}

# ── ABI Registry Service ───────────────────────────────────────────────
# Audit-7 false positive integration: centralized ABI registry for
# version management. Each backend maintains its own list of supported
# ABIs; the registry provides a shared view across backends for global
# ABI version tracking, compatibility matrices, and migration path
# recommendations. Defined as a separate interface because Cap'n Proto
# does not allow extending an existing interface definition.

interface AbiRegistryService {
    # Register an ABI in the global registry.
    register @0 (entry :AbiRegistryEntry) -> T.VoidResult;

    # Look up a registered ABI by version.
    lookup @1 (version :T.Version) -> (entry :AbiRegistryEntry);

    # List all registered ABIs with pagination.
    list @2 (pagination :T.Pagination) -> (entries :List(AbiRegistryEntry), totalCount :UInt32);

    # Get compatibility matrix for a specific ABI version.
    getCompatibilityMatrix @3 (version :T.Version) -> (matrix :List(CompatibilityReport));

    # Endorse a registered ABI with trust information.
    endorse @4 (abi :Abi, endorsement :AbiEndorsement) -> T.VoidResult;

    # Remove an ABI from the registry (soft-delete).
    deregister @5 (version :T.Version) -> T.VoidResult;

    # Get migration path from one version to another.
    getMigrationPath @6 (from :T.Version, to :T.Version) -> (plan :MigrationPlan);

    # Audit-9: verify an endorsement cryptographically against a trust chain.
    # Returns verification result with chain-of-trust status.
    verifyEndorsement @7 (abi :Abi, endorsement :AbiEndorsement) -> (result :EndorsementVerificationResult);

    # Audit-9: subscribe to registry change events (new registrations, endorsements, removals).
    subscribeRegistryEvents @8 () -> (subscription :RegistryEventSubscription);

    # Audit-9: reverse lookup — find ABIs that support a specific capability set.
    searchByCapability @9 (capabilities :List(BootCapability), pagination :T.Pagination)
                       -> (entries :List(AbiRegistryEntry), totalCount :UInt32);

    # Audit-9: pin a specific ABI version for reproducible builds.
    # Pinned versions cannot be overridden by newer versions until unpinned.
    pinVersion @10 (version :T.Version, reason :Text) -> T.VoidResult;

    # Audit-9: unpin a previously pinned ABI version.
    unpinVersion @11 (version :T.Version) -> T.VoidResult;

    # Audit-9: list all pinned versions.
    listPinnedVersions @12 (pagination :T.Pagination) -> (pins :List(AbiVersionPin), totalCount :UInt32);
}

# ── Audit-9: Endorsement Verification ──────────────────────────────────
# Result of cryptographically verifying an endorsement against a trust chain.
struct EndorsementVerificationResult {
    # Whether the endorsement is valid.
    valid @0 :Bool;
    # Trust level after verification.
    trustLevel @1 :EndorsementTrustLevel;
    # Chain of trust items (intermediate endorsers).
    chain @2 :List(EndorsementChainItem);
    # Error message if verification failed.
    error @3 :T.Error;
    # When verification was performed.
    verifiedAt @4 :T.Timestamp;
}

# A single item in the endorsement trust chain.
struct EndorsementChainItem {
    # Entity that issued this endorsement in the chain.
    endorser @0 :Text;
    # Signature over the previous item or the ABI hash.
    signature @1 :Data;
    # When this chain item was issued.
    issuedAt @2 :T.Timestamp;
    # Public key identifier for verification.
    keyId @3 :Text;
}

# ── Audit-9: Registry Event Subscription ────────────────────────────────
# Subscription for real-time registry change events.
interface RegistryEventSubscription {
    pull @0 () -> (events :List(RegistryEvent));
    cancel @1 () -> T.VoidResult;
}

# An event emitted by the registry when state changes.
struct RegistryEvent {
    union {
        abiRegistered @0 :AbiRegistryEntry;
        abiEndorsed @1 :AbiRegistryEntry;
        abiDeregistered @2 :T.Version;
        endorsementRevoked @3 :T.Version;
        versionPinned @4 :AbiVersionPin;
        versionUnpinned @5 :T.Version;
        custom @6 :Data;
    }
}

# ── Audit-9: ABI Version Pin ───────────────────────────────────────────
# A pinned ABI version for reproducible builds.
struct AbiVersionPin {
    # The pinned ABI version.
    version @0 :T.Version;
    # Reason for pinning (e.g., "production deployment", "regression test").
    reason @1 :Text;
    # When the pin was created.
    pinnedAt @2 :T.Timestamp;
    # Who created the pin (optional).
    pinnedBy @3 :Text;
}

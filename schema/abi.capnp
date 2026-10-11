@0xa1b2c3d4e5f60036;

# ═══════════════════════════════════════════════════════════════════════
# Abi — ABI declaration, compatibility reporting and negotiation.
#
# The contract two parties use at startup to say which schemas they speak
# and at which versions, and to agree on an intersection before either
# commits to a call. It answers ONE question: what can we both speak?
#
# Zero backend assumptions: no registry, no endorsement authority, no
# version-pinning service, no trust chain. A backend declares the ABIs it
# supports; a caller negotiates against that list.
#
# ── WHAT WAS DELETED ───────────────────────────────────────────────────
#
#   * `BootCapability` (a permission enum: readMemory/writeMemory/…) —
#     byte-identical to boot.capnp's copy, two type IDs, one name, and a
#     second access-control grammar parallel to capability.capnp's
#     `Operation`. Capability authority is capability.capnp's job
#     (DESIGN_PRINCIPLES.md:399); an ABI declares which OPERATIONS it
#     requires, as open tokens.
#   * `AbiRegistryService` and its apparatus (endorsement chain,
#     version pinning, compatibility matrix, migration planner) — a global
#     registry with a trust service. Who operates it on an offline device?
#     Nothing in the protocol consumed it; each backend already lists what
#     it supports, which is the whole contract.
#   * `NegotiateSession` / `NegotiationRound` — multi-round haggling with
#     rollback. `handshake` + `negotiate` already answer the question in
#     one round trip; a session state machine was machinery, not contract.
#
# What remains is the negotiation core, which was already the best-shaped
# part of this schema: honest T.Error failure cases, a typed
# CompatibilityReport, paginated listing, subscription with cancel.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ── ABI ─────────────────────────────────────────────────────────────────

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
    # Operations this ABI requires of a backend, as OPEN tokens (e.g.
    # "read", "network"). Unknown tokens are ignored, never rejected —
    # the same unknown-tolerance rule ai.capnp states, applied to
    # authority so a 2046 capability need not be enumerated here.
    requiredOperations @4 :List(Text);
    # Platform constraints (e.g. "requires wasm", "requires native").
    # Empty means no constraints.
    platformHints @5 :List(Text);
    # When this ABI was deprecated (if at all). Zero means not deprecated.
    deprecatedAt @6 :T.Timestamp;
    # Grace period after deprecation before removal.
    deprecationGrace @7 :T.Duration;
    # Sideband provenance metadata. Optional — older artifacts can leave
    # this null while still conforming to a newer ABI.
    metadata @8 :AbiMetadata;
    # Explicit removal date (computed from deprecatedAt + deprecationGrace).
    # Zero means not yet scheduled for removal.
    removedAt @9 :T.Timestamp;
    # Open, backend-declared metadata. Unrecognised keys are ignored.
    custom @10 :T.StringMap;
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
    # Feature payload — typed union instead of opaque Data.
    payload @2 :AbiFeaturePayload;
}

struct AbiFeaturePayload {
    union {
        text @0 :Text;
        integer @1 :UInt64;
        bytes @2 :Data;
        version @3 :T.Version;
        unknown @4 :T.UnknownEvent;
    }
}

struct AbiMetadata {
    maintainer @0 :Text;
    description @1 :Text;
    homepage @2 :T.Uri;
    repository @3 :T.Uri;
    spdxLicenseId @4 :Text;
    keywords @5 :List(Text);
    custom @6 :T.StringMap;
}

# ── ABI Range ─────────────────────────────────────────────────────────
# A range of compatible ABIs. Useful for tooling like "show me all ABIs
# between epoch 5 and current". `maxInclusive` says whether the upper
# endpoint itself is acceptable; the name matches the flag's effect, so a
# caller never has to guess which way a default leans.
struct AbiRange {
    min @0 :Abi;
    max @1 :Abi;
    # Whether the max endpoint is included in the range (default = true).
    maxInclusive @2 :Bool = true;
}

# ── Compatibility Report ──────────────────────────────────────────────
# Positive verdict for the entire ABI set, not just per-schema details.
# A negotiation endpoint can return an overall verdict alongside
# per-schema breakdowns for clearer UX in tool outputs.
struct CompatibilityReport {
    union {
        ok @0 :Abi;
        partial @1 :PartialCompatibility;
        blocked @2 :T.Error;
        unknown @3 :T.UnknownEvent;
    }
}

struct PartialCompatibility {
    agreed @0 :Abi;
    # Schema ids the callee does not support (typed references).
    unsupportedSchemas @1 :List(T.SchemaId);
    missingFeatures @2 :List(Text);
    downgradeHints @3 :AbiRange;
}

# ── ABI Diff ──────────────────────────────────────────────────────────
# Structured diff between two ABI snapshots. Tooling uses this to
# generate changelogs and compatibility matrices without parsing ABI
# structs by hand.
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

# ── ABI Handshake ─────────────────────────────────────────────────────
# Typed initial exchange for ABI discovery. When two parties connect,
# they exchange HandshakeRequest/Response to advertise capabilities
# before full negotiation. This avoids the "negotiate everything from
# scratch" pattern for common cases where both sides already know the ABI.
struct AbiHandshakeRequest {
    # The caller's ABI (what it speaks).
    callerAbi @0 :Abi;
    # Optional constraints on what the callee must support.
    constraints @1 :NegotiateConstraints;
    # Whether the caller accepts downgrade.
    acceptDowngrade @2 :Bool;
    # Session identifier for this exchange (opaque; not a session state
    # machine — the handshake completes in one round trip).
    sessionId @3 :T.SessionId;
}

struct AbiHandshakeResponse {
    union {
        # Callee matched; here is the agreed ABI.
        matched @0 :Abi;
        # Callee supports a subset; partial match with hints.
        partialMatch @1 :PartialCompatibility;
        # Callee cannot speak any compatible ABI.
        incompatible @2 :T.Error;
        unknown @3 :T.UnknownEvent;
    }
}

# ── Service ────────────────────────────────────────────────────────────

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
    cancel @4 (subscription :AbiSubscription) -> T.VoidResult;

    # Perform initial handshake before full negotiation.
    handshake @5 (request :AbiHandshakeRequest) -> (response :AbiHandshakeResponse);

    # Compute structured diff between two ABI snapshots.
    diff @6 (from :Abi, to :Abi) -> (diff :AbiDiff);
}

struct NegotiateConstraints {
    # Minimum epoch floor. Backends reject ABIs older than this.
    minEpoch @0 :UInt32;
    # Maximum major version ceiling.
    maxMajorVersion @1 :UInt32;
    # Required features that must be present.
    requiredFeatures @2 :List(FeatureRequirement);
    # Required operations, as open tokens (matches Abi.requiredOperations).
    requiredOperations @3 :List(Text);
}

# A typed feature requirement. Promotes bare Text to a structured union
# so consumers can statically validate negotiation constraints without
# parsing strings. Backends can use `unknown` for vendor-defined feature
# names they don't recognise ahead of time.
struct FeatureRequirement {
    union {
        byName @0 :Text;                  # Plain feature name (most common)
        byKind @1 :Text;                  # Match any feature with this kind
        byVersion @2 :VersionedFeature;   # Require specific version of a feature
        unknown @3 :T.UnknownEvent;       # Backend-defined requirement shape
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
        unknown @3 :T.UnknownEvent;
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
    unknown @4;
    custom @5;
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
        unknown @4 :T.UnknownEvent;
    }
}

interface AbiSubscription {
    pull @0 () -> (events :List(AbiEvent));
    cancel @1 () -> T.VoidResult;
}

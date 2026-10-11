@0xa1b2c3d4e5f60064;

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ══════════════════════════════════════════════════════════════════════
# Key Management — Cryptographic key lifecycle management.
#
# Provides generation, import/export, rotation, revocation, and
# metadata for cryptographic keys. Referenced by:
#   - auth.capnp (token signing keys)
#   - backup.capnp (encryption keys for backup data)
#   - biometric.capnp (crypto-binding keys for biometric templates)
#   - signature.capnp (signing/verification key references)
#   - secret.capnp (encryption key references)
#   - content.capnp (content encryption keys, T.KeyId)
#
# Design principles:
#   - No OS-specific key storage assumptions (Keychain, TPM, PKCS#11)
#   - No algorithm-specific assumptions: the algorithm is an OPEN TOKEN
#     (see crypto.capnp's CONFORMANCE TOKENS), so this file names no
#     RSA, ECC, AES or post-quantum family and needs no amendment when
#     a construction appears. The previous `KeyAlgorithmFamily` enum
#     named three post-quantum families permanently — in a file whose
#     own header claims "No algorithm-specific assumptions" — and
#     required BOTH the family and a free-text spec, so two backends
#     could disagree about which family an algorithm belonged to while
#     the real spec lived in the Text.
#   - Keys are opaque references; the protocol defines lifecycle, not internals
#   - Key material never crosses the protocol boundary (T.DataHandle only
#     for encrypted/exported blobs, never raw key bytes)
#
# ── KEY IDENTITY ───────────────────────────────────────────────────────
#
# This file used to declare a local `struct KeyId { id @0 :UInt64 }`
# while types.capnp carried the promoted `T.KeyId` with a cross-schema
# note naming this file's migration. Two declarations of one identity
# across one protocol: content.capnp and backup.capnp already speak
# T.KeyId, so a consumer bridging them and this service had two
# nominally distinct types with identical layout — a call-site type
# error, or a silent crossing of two id namespaces. The local copy is
# deleted; every key reference below is T.KeyId.
#
# ── AUTHORITY IS THE INTERFACE REFERENCE ───────────────────────────────
#
# The whole store is obtained through one accessor that takes a
# Capability, and no method below takes an authority token. Previously
# `syncExport` (bulk export of every key for a device named by a
# free-form string), `escrowKey` and `restoreKey` were reachable by any
# holder of the service reference, alongside `exportKey` which hands out
# key material. Holding `KeyManagementService` is now itself the grant.
# ══════════════════════════════════════════════════════════════════════

interface KeyManagement {
    # Gated once, at acquisition. `target` names the key set (or the
    # whole store); `operations` narrows what the holder may do.
    store @0 (authority :Capability) -> (service :KeyManagementService);
}

# ── Key lifecycle ─────────────────────────────────────────────────────

interface KeyManagementService {
    generateKey @0 (request :KeyGenerationRequest) -> KeyGenerationResult;
    importKey @1 (request :KeyImportRequest) -> KeyImportResult;
    exportKey @2 (request :KeyExportRequest) -> KeyExportResult;
    rotateKey @3 (request :KeyRotationRequest) -> KeyRotationResult;
    revokeKey @4 (keyId :T.KeyId, reason :Text) -> KeyRevocationResult;

    # Key query
    getKey @5 (keyId :T.KeyId) -> (metadata :KeyMetadata);
    listKeys @6 (filter :KeyFilter) -> (keys :List(KeyMetadata), total :UInt64);

    # Bulk operations
    revokeAll @7 (filter :KeyFilter) -> T.VoidResult;

    # Event subscription
    subscribe @8 () -> (subscription :KeySubscription);

    # Key usage (optional — backends may track usage statistics)
    getUsage @9 (keyId :T.KeyId) -> (usage :KeyUsage);

    # Verify hardware attestation for a key.
    verifyAttestation @10 (keyId :T.KeyId) -> (attested :Bool, issuer :Text);

    # Derive a child key from a parent key. The algorithm is an open
    # token, so a derivation contract with an undeclared algorithm is no
    # longer representable.
    deriveKey @11 (parentId :T.KeyId, purpose :KeyPurpose,
        algorithm :Text, name :Text) -> KeyGenerationResult;

    # Escrow a key with M-of-N recovery shares. `keyId` binds the shares
    # to a key: previously the shares were bound to nothing, so two
    # backends could reconstruct different keys from the same share set.
    escrowKey @12 (keyId :T.KeyId, recoveryShares :List(T.DataHandle))
        -> (result :T.VoidResult);

    # Restore a key from recovery shares. `keyId` is the escrowed key the
    # shares belong to; a backend MUST refuse shares that do not
    # reconstruct that key rather than returning whatever it rebuilt.
    restoreKey @13 (keyId :T.KeyId, shares :List(T.DataHandle)) -> KeyGenerationResult;

    # Export keys encrypted for a specific target device. `deviceId` is
    # the promoted T.DeviceId, previously a free-form Text whose
    # namespaces were unrelated between backends.
    syncExport @14 (deviceId :T.DeviceId) -> (encryptedBundle :T.DataHandle);

    # Import keys from an encrypted device bundle.
    syncImport @15 (encryptedBundle :T.DataHandle) -> (count :UInt32);
}

struct KeyUsage {
    keyId @0 :T.KeyId;
    operationCount @1 :UInt64;        # Total operations performed with this key
    lastUsedAt @2 :T.Timestamp;       # 0 = never used
    lastOperation @3 :Text;           # Backend-decided (e.g., "encrypt", "sign")
}

# ── Enums ────────────────────────────────────────────────────
# Kept deliberately small and closed by the operations cryptography
# itself defines. Anything naming a technology moved to an open Text
# token (see the header).

enum KeyPurpose {
    unspecified @0;      # Sentinel: an unset purpose is not "encryption"
    encryption @1;       # Symmetric or asymmetric encryption
    signing @2;          # Digital signatures (code signing, document signing)
    authentication @3;   # Authentication tokens, challenge-response
    keyExchange @4;      # Key agreement
    mac @5;              # Message authentication codes
    custom @6;           # Backend-specific purpose
}

enum KeyStatus {
    unspecified @0;      # Sentinel: an unset status is not "active"
    active @1;           # Key is valid and usable
    rotated @2;          # Key has been replaced by a newer key
    revoked @3;          # Key has been explicitly revoked
    expired @4;          # Key has passed its expiration time
    pending @5;          # Key is generated but not yet activated
    custom @6;           # Backend-specific status
}

# ── Structs ──────────────────────────────────────────────────

struct KeyMetadata {
    id @0 :T.KeyId;
    name @1 :Text;                    # Human-readable label (e.g., "backup-2026-key")
    purpose @2 :KeyPurpose;
    # The algorithm, as an open token (crypto.capnp CONFORMANCE TOKENS).
    # This single field replaces the previous pair
    # (algorithmFamily enum + algorithmDetails Text): two backends could
    # disagree about which family an algorithm belonged to while the real
    # spec lived in the Text.
    algorithm @3 :Text;
    # Self-describing fingerprint of this key, so it can be correlated
    # with signature.capnp's keyId and crypto.capnp's reported
    # fingerprints without a length heuristic.
    fingerprint @4 :T.KeyFingerprint;
    status @5 :KeyStatus;
    createdAt @6 :T.Timestamp;
    expiresAt @7 :T.Timestamp;        # 0 = no expiration
    rotatedAt @8 :T.Timestamp;       # 0 = not yet rotated
    revokedAt @9 :T.Timestamp;       # 0 = not revoked
    version @10 :UInt32;             # Key version (1 = original, incremented on rotation)
    tags @11 :List(T.TagId);         # Cross-schema tag references
    metadata @12 :T.StringMap;       # Backend-specific key metadata
    # HSM-backed key flag.
    hsmBacked @13 :Bool;             # True = key never leaves hardware
    # Key lineage (parent key derivation).
    derivedFrom @14 :T.KeyId;         # 0 = not derived (root key)
    # Key revocation graph (transitive revocation).
    revokedBy @15 :T.KeyId;           # 0 = not revoked by another key
    # Custodial key flag.
    custodial @16 :Bool;             # True = managed by institutional custodian
    # Key attestation data (hardware proof).
    attestation @17 :T.DataHandle;   # Hardware attestation blob (empty = none)
    # Bound identity (device/user binding).
    boundIdentity @18 :Text;         # Bound to device/user (empty = unbound)
    # Derived attributes (context computed from key).
    derivedAttributes @19 :T.StringMap;
}

struct KeyGenerationRequest {
    purpose @0 :KeyPurpose;
    # The algorithm, as an open token. Key size, curve, mode and the
    # rest are carried here rather than in a family enum, so a new
    # construction needs no new ordinal.
    algorithm @1 :Text;
    name @2 :Text;                    # Human-readable label
    expirationDuration @3 :T.Duration;  # 0 = no expiration
    tags @4 :List(T.TagId);
    metadata @5 :T.StringMap;         # Backend-specific generation options
    # Algorithm-specific knobs (keyBits, curve, ...).
    parameters @6 :T.StringMap;
    # Maximum operations before auto-revocation (0 = unlimited).
    maxOperations @7 :UInt64;
    # Rotation policy for this key.
    rotationPolicy @8 :RotationPolicy;
    # Threshold key configuration (M-of-N).
    thresholdKey @9 :ThresholdKey;
}

# Rotation policy for automated key lifecycle.
#
# The grace window is THE question every implementer of this contract has
# to answer, and the schema used to be silent on it, which meant two
# backends answered differently and a consumer that encrypted under the
# "old" key during the window could produce data the new key could not
# read. Declared here:
#
#   - During `gracePeriod` the old key remains usable for DECRYPT and
#     VERIFY only. New encryption, signing and agreement MUST use the
#     successor.
#   - The backend announces the transition through KeyLifecycleEvent.rotated,
#     whose KeyRotationInfo names both keys and the timestamp.
#   - Who re-encrypts existing data is the CALLER's decision, declared
#     by `reEncryptExisting`: a backend that re-encrypts reports it in
#     KeyLifecycleEvent.rotated's reason. The protocol does not guess.
struct RotationPolicy {
    # Rotate after this duration (0 = no time-based rotation).
    rotateAfter @0 :T.Duration;
    # Rotate after this many operations (0 = no usage-based rotation).
    rotateAfterOperations @1 :UInt64;
    # Grace period after rotation before old key is revoked.
    gracePeriod @2 :T.Duration;
    # Notify before expiration (0 = no notification).
    notifyBefore @3 :T.Duration;
    # Whether the backend re-encrypts existing data under the successor
    # once the grace period ends. When false, the caller owns re-encryption.
    reEncryptExisting @4 :Bool;
    custom @5 :T.StringMap;
}

# Threshold key configuration (M-of-N).
struct ThresholdKey {
    # Total number of shares (N).
    totalShares @0 :UInt8;
    # Minimum shares required (M).
    threshold @1 :UInt8;
    # Key IDs of the share holders.
    shares @2 :List(T.KeyId);
}

struct KeyImportRequest {
    keyData @0 :T.DataHandle;         # Encrypted key material (never raw)
    # Encoding, as an open token ("der", "pem", "jwk", ...). The previous
    # KeyExportFormat enum could not name PEM or DER at all, so a backend
    # holding a PEM key had to pre-decode it outside the protocol, and
    # "raw" meant different things to different backends.
    format @1 :Text;
    purpose @2 :KeyPurpose;
    algorithm @3 :Text;
    name @4 :Text;
    passphrase @5 :T.DataHandle;      # Optional passphrase for encrypted import
    tags @6 :List(T.TagId);
    metadata @7 :T.StringMap;
    parameters @8 :T.StringMap;
}

struct KeyExportRequest {
    keyId @0 :T.KeyId;
    format @1 :Text;
    passphrase @2 :T.DataHandle;      # Optional passphrase for encrypted export
    # E2E-encrypted export flag.
    encryptedExport @3 :Bool;         # True = export blob is E2E encrypted
    parameters @4 :T.StringMap;
}

struct KeyRotationRequest {
    keyId @0 :T.KeyId;
    # Optional: change algorithm on rotation (open token).
    newAlgorithm @1 :Text;
    expirationDuration @2 :T.Duration;  # Optional: new expiration for rotated key
    parameters @3 :T.StringMap;
}

struct KeyFilter {
    purposes @0 :List(KeyPurpose);    # Filter by purpose (empty = all)
    statuses @1 :List(KeyStatus);     # Filter by status (empty = all)
    # Filter by algorithm token (empty = all).
    algorithms @2 :List(Text);
    tags @3 :List(T.TagId);           # Filter by tags (empty = all)
    nameContains @4 :Text;            # Substring match on name (empty = no filter)
    createdAfter @5 :T.Timestamp;     # 0 = no lower bound
    createdBefore @6 :T.Timestamp;    # 0 = no upper bound
    pagination @7 :T.Pagination;
    parameters @8 :T.StringMap;
}

# ── Results ──────────────────────────────────────────────────

struct KeyGenerationResult {
    union {
        success @0 :KeyMetadata;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct KeyImportResult {
    union {
        success @0 :KeyMetadata;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct KeyExportResult {
    union {
        success @0 :KeyExportData;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct KeyExportData {
    keyData @0 :T.DataHandle;         # Encrypted exported key material
    format @1 :Text;
    metadata @2 :KeyMetadata;
}

struct KeyRotationResult {
    union {
        success @0 :KeyMetadata;      # New key metadata (old key is now "rotated")
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct KeyRevocationResult {
    union {
        success @0 :Void;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

# ── Events ───────────────────────────────────────────────────

struct KeyLifecycleEvent {
    union {
        generated @0 :KeyMetadata;
        imported @1 :KeyMetadata;
        exported @2 :T.KeyId;         # Export event (not the key data)
        rotated @3 :KeyRotationInfo;
        revoked @4 :T.KeyId;
        expired @5 :T.KeyId;
        statusChanged @6 :KeyStatusChange;
        # Emitted when a key's operation count reached maxOperations, so
        # the auto-revocation is observable rather than only inferable
        # from a later getUsage call.
        usageExhausted @7 :T.KeyId;
        custom @8 :Data;
    }
}

struct KeyRotationInfo {
    oldKeyId @0 :T.KeyId;
    newKeyId @1 :T.KeyId;
    timestamp @2 :T.Timestamp;
    # What the backend did about data encrypted under the old key (open
    # token, e.g. "re-encrypted", "caller-responsible").
    dataDisposition @3 :Text;
}

struct KeyStatusChange {
    keyId @0 :T.KeyId;
    oldStatus @1 :KeyStatus;
    newStatus @2 :KeyStatus;
    timestamp @3 :T.Timestamp;
}

# ── Subscription ─────────────────────────────────────────────

interface KeySubscription {
    # Bounded pull: the previous unbounded `pull` also returned
    # `pagination`/`total` for events the caller never paginated, implying
    # a shape the caller does not control. `cancel` was missing entirely,
    # leaving a long-lived subscription with no teardown path.
    # The bound is a plain max-count parameter, exactly as ai.capnp's
    # streams bound theirs: an offset is meaningless on a live event
    # queue, so there is nothing to paginate.
    pull @0 (maxCount :UInt32) -> (events :List(KeyLifecycleEvent));
    cancel @1 () -> T.VoidResult;
}

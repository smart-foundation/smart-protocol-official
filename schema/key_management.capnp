@0xa1b2c3d4e5f60064;

using T = import "types.capnp";
using DB = import "database.capnp";

# ══════════════════════════════════════════════════════════════════════
# Key Management — Cryptographic key lifecycle management.
#
# Provides generation, import/export, rotation, revocation, and
# metadata for cryptographic keys. Referenced by:
#   - auth.capnp (token signing keys, EncryptionInfo.keyId)
#   - backup.capnp (encryption keys for backup data)
#   - biometric.capnp (crypto-binding keys for biometric templates)
#   - signature.capnp (signing/verification key references)
#   - secret.capnp (encryption key references)
#
# Design principles:
#   - No OS-specific key storage assumptions (Keychain, TPM, PKCS#11)
#   - No algorithm-specific assumptions (RSA, ECC, AES — backend decides)
#   - Keys are opaque references; the protocol defines lifecycle, not internals
#   - Key material never crosses the protocol boundary (use DataHandle only
#     for encrypted/exported blobs, never raw key bytes)
# ══════════════════════════════════════════════════════════════════════

# ── Identity ─────────────────────────────────────────────────

struct KeyId { id @0 :UInt64; }

# ── Enums ────────────────────────────────────────────────────

enum KeyPurpose {
    encryption @0;       # Symmetric or asymmetric encryption
    signing @1;          # Digital signatures (code signing, document signing)
    authentication @2;   # Authentication tokens, challenge-response
    keyExchange @3;      # Key agreement (Diffie-Hellland, ECDH)
    mac @4;              # Message authentication codes
    custom @5;           # Backend-specific purpose
}

enum KeyStatus {
    active @0;           # Key is valid and usable
    rotated @1;          # Key has been replaced by a newer key
    revoked @2;          # Key has been explicitly revoked
    expired @3;          # Key has passed its expiration time
    pending @4;          # Key is generated but not yet activated
    custom @5;           # Backend-specific status
}

enum KeyAlgorithmFamily {
    symmetric @0;        # AES, ChaCha20, etc.
    asymmetric @1;       # RSA, ECC, Ed25519, etc.
    hash @2;             # SHA-256, BLAKE3, etc. (for key derivation)
    kdf @3;              # Key derivation functions (PBKDF2, Argon2, etc.)
    mac @4;              # HMAC, CMAC, etc.
    # Audit-8: Post-quantum algorithm families (NIST PQC standards).
    mlKem @5;            # ML-KEM (Module Lattice Key Encapsulation)
    mlDsa @6;            # ML-DSA (Module Lattice Digital Signature)
    slhDsa @7;           # SLH-DSA (Stateless Hash-Based Digital Signature)
    hybridPq @8;         # Hybrid post-quantum + classical
    custom @9;           # Backend-specific algorithm family
}

enum KeyExportFormat {
    raw @0;              # Raw key bytes (encrypted)
    pkcs8 @1;            # PKCS#8 private key format
    spki @2;             # SubjectPublicKeyInfo format
    jwk @3;              # JSON Web Key format
    # Audit-8: Post-quantum export formats.
    mlKemSeed @4;        # ML-KEM seed format
    mlDsaBytes @5;       # ML-DMA raw key bytes
    custom @6;           # Backend-specific format
}

# ── Structs ──────────────────────────────────────────────────

struct KeyMetadata {
    id @0 :KeyId;
    name @1 :Text;                    # Human-readable label (e.g., "backup-2026-key")
    purpose @2 :KeyPurpose;
    algorithmFamily @3 :KeyAlgorithmFamily;
    algorithmDetails @4 :Text;        # Backend-decided (e.g., "AES-256-GCM", "Ed25519")
    status @5 :KeyStatus;
    createdAt @6 :T.Timestamp;
    expiresAt @7 :T.Timestamp;        # 0 = no expiration
    rotatedAt @8 :T.Timestamp;       # 0 = not yet rotated
    revokedAt @9 :T.Timestamp;       # 0 = not revoked
    version @10 :UInt32;             # Key version (1 = original, incremented on rotation)
    tags @11 :List(T.TagId);         # Cross-schema tag references
    metadata @12 :T.StringMap;       # Backend-specific key metadata
    # Audit-8: HSM-backed key flag.
    hsmBacked @13 :Bool;             # True = key never leaves hardware (FIPS 140-3)
    # Audit-8: Key lineage (parent key derivation).
    derivedFrom @14 :KeyId;          # 0 = not derived (root key)
    # Audit-8: Key revocation graph (transitive revocation).
    revokedBy @15 :KeyId;            # 0 = not revoked by another key
    # Audit-8: Custodial key flag.
    custodial @16 :Bool;             # True = managed by institutional custodian
    # Audit-8: Key attestation data (hardware proof).
    attestation @17 :T.DataHandle;   # Hardware attestation blob (empty = none)
    # Audit-8: Bound identity (device/user binding).
    boundIdentity @18 :Text;         # Bound to device/user (empty = unbound)
    # Audit-8: Derived attributes (context computed from key).
    derivedAttributes @19 :T.StringMap;
}

struct KeyGenerationRequest {
    purpose @0 :KeyPurpose;
    algorithmFamily @1 :KeyAlgorithmFamily;
    algorithmDetails @2 :Text;        # Backend-decided algorithm spec
    name @3 :Text;                    # Human-readable label
    expirationDuration @4 :T.Duration;  # 0 = no expiration
    tags @5 :List(T.TagId);
    metadata @6 :T.StringMap;         # Backend-specific generation options
    # Audit-8: Maximum operations before auto-revocation (0 = unlimited).
    maxOperations @7 :UInt64;
    # Audit-8: Rotation policy for this key.
    rotationPolicy @8 :RotationPolicy;
    # Audit-8: Threshold key configuration (M-of-N).
    thresholdKey @9 :ThresholdKey;
}

# Audit-8: Rotation policy for automated key lifecycle.
struct RotationPolicy {
    # Rotate after this duration (0 = no time-based rotation).
    rotateAfter @0 :T.Duration;
    # Rotate after this many operations (0 = no usage-based rotation).
    rotateAfterOperations @1 :UInt64;
    # Grace period after rotation before old key is revoked.
    gracePeriod @2 :T.Duration;
    # Notify before expiration (0 = no notification).
    notifyBefore @3 :T.Duration;
}

# Audit-8: Threshold key configuration (M-of-N).
struct ThresholdKey {
    # Total number of shares (N).
    totalShares @0 :UInt8;
    # Minimum shares required (M).
    threshold @1 :UInt8;
    # Key IDs of the share holders.
    shares @2 :List(KeyId);
}

struct KeyImportRequest {
    keyData @0 :T.DataHandle;         # Encrypted key material (never raw)
    format @1 :KeyExportFormat;
    purpose @2 :KeyPurpose;
    algorithmFamily @3 :KeyAlgorithmFamily;
    algorithmDetails @4 :Text;
    name @5 :Text;
    passphrase @6 :T.DataHandle;      # Optional passphrase for encrypted import
    tags @7 :List(T.TagId);
    metadata @8 :T.StringMap;
}

struct KeyExportRequest {
    keyId @0 :KeyId;
    format @1 :KeyExportFormat;
    passphrase @2 :T.DataHandle;      # Optional passphrase for encrypted export
    # Audit-8: E2E-encrypted export flag.
    encryptedExport @3 :Bool;         # True = export blob is E2E encrypted
}

struct KeyRotationRequest {
    keyId @0 :KeyId;
    newAlgorithmDetails @1 :Text;     # Optional: change algorithm on rotation
    expirationDuration @2 :T.Duration;  # Optional: new expiration for rotated key
}

struct KeyFilter {
    purposes @0 :List(KeyPurpose);    # Filter by purpose (empty = all)
    statuses @1 :List(KeyStatus);     # Filter by status (empty = all)
    algorithmFamilies @2 :List(KeyAlgorithmFamily);
    tags @3 :List(T.TagId);           # Filter by tags (empty = all)
    nameContains @4 :Text;            # Substring match on name (empty = no filter)
    createdAfter @5 :T.Timestamp;     # 0 = no lower bound
    createdBefore @6 :T.Timestamp;    # 0 = no upper bound
    pagination @7 :T.Pagination;
}

# ── Results ──────────────────────────────────────────────────

struct KeyGenerationResult {
    union {
        success @0 :KeyMetadata;
        error @1 :T.Error;
    }
}

struct KeyImportResult {
    union {
        success @0 :KeyMetadata;
        error @1 :T.Error;
    }
}

struct KeyExportResult {
    union {
        success @0 :KeyExportData;
        error @1 :T.Error;
    }
}

struct KeyExportData {
    keyData @0 :T.DataHandle;         # Encrypted exported key material
    format @1 :KeyExportFormat;
    metadata @2 :KeyMetadata;
}

struct KeyRotationResult {
    union {
        success @0 :KeyMetadata;      # New key metadata (old key is now "rotated")
        error @1 :T.Error;
    }
}

struct KeyRevocationResult {
    union {
        success @0 :Void;
        error @1 :T.Error;
    }
}

# ── Events ───────────────────────────────────────────────────

struct KeyEvent {
    union {
        generated @0 :KeyMetadata;
        imported @1 :KeyMetadata;
        exported @2 :KeyId;           # Export event (not the key data)
        rotated @3 :KeyRotationInfo;
        revoked @4 :KeyId;
        expired @5 :KeyId;
        statusChanged @6 :KeyStatusChange;
        custom @7 :Data;
    }
}

struct KeyRotationInfo {
    oldKeyId @0 :KeyId;
    newKeyId @1 :KeyId;
    timestamp @2 :T.Timestamp;
}

struct KeyStatusChange {
    keyId @0 :KeyId;
    oldStatus @1 :KeyStatus;
    newStatus @2 :KeyStatus;
    timestamp @3 :T.Timestamp;
}

# ── Subscription ─────────────────────────────────────────────

interface KeySubscription {
    pull @0 () -> (events :List(KeyEvent), pagination :T.Pagination, total :UInt64);
    cancel @1 () -> T.VoidResult;
}

# ── Service ──────────────────────────────────────────────────

interface KeyManagementService {
    # Key lifecycle
    generateKey @0 (request :KeyGenerationRequest) -> KeyGenerationResult;
    importKey @1 (request :KeyImportRequest) -> KeyImportResult;
    exportKey @2 (request :KeyExportRequest) -> KeyExportResult;
    rotateKey @3 (request :KeyRotationRequest) -> KeyRotationResult;
    revokeKey @4 (keyId :KeyId, reason :Text) -> KeyRevocationResult;

    # Key query
    getKey @5 (keyId :KeyId) -> (metadata :KeyMetadata);
    listKeys @6 (filter :KeyFilter) -> (keys :List(KeyMetadata), total :UInt64);

    # Bulk operations
    revokeAll @7 (filter :KeyFilter) -> T.VoidResult;

    # Event subscription
    subscribe @8 () -> DB.KeySubscription;

    # Key usage (optional — backends may track usage statistics)
    getUsage @9 (keyId :KeyId) -> (usage :KeyUsage);

    # Audit-8: Verify hardware attestation for a key.
    verifyAttestation @10 (keyId :KeyId) -> (attested :Bool, issuer :Text);

    # Audit-8: Derive a child key from a parent key.
    deriveKey @11 (parentId :KeyId, purpose :KeyPurpose,
        algorithmDetails :Text, name :Text) -> KeyGenerationResult;

    # Audit-8: Escrow a key with M-of-N recovery shares.
    escrowKey @12 (keyId :KeyId, recoveryShares :List(T.DataHandle))
        -> (result :T.VoidResult);

    # Audit-8: Restore a key from recovery shares.
    restoreKey @13 (shares :List(T.DataHandle)) -> KeyGenerationResult;

    # Audit-8: Export keys encrypted for a specific target device.
    syncExport @14 (deviceId :Text) -> (encryptedBundle :T.DataHandle);

    # Audit-8: Import keys from an encrypted device bundle.
    syncImport @15 (encryptedBundle :T.DataHandle) -> (count :UInt32);
}

struct KeyUsage {
    keyId @0 :KeyId;
    operationCount @1 :UInt64;        # Total operations performed with this key
    lastUsedAt @2 :T.Timestamp;       # 0 = never used
    lastOperation @3 :Text;           # Backend-decided (e.g., "encrypt", "sign")
}

@0xa1b2c3d4e5f60028;

using T = import "types.capnp";

# ══════════════════════════════════════════════════════════════════════
# Secret — secret/credential storage with namespace isolation.
#
# Improvements beyond the original schema:
#   - listSecrets now uses T.Pagination for bounded results.
#   - ChangesSubscription has cancel method.
#   - SecretChangeType has custom variant for forward compatibility.
#   - SecretEntry timestamps use T.Timestamp (already correct).
#   - namespace uses T.SecretNamespaceId (audit-3, replaces bare Text).
#   - key uses T.SecretKeyId (audit-3, replaces bare Text).
#   - ChangesSubscription.pull accepts T.Pagination (audit-4).
# ══════════════════════════════════════════════════════════════════════

interface Secret {
    listSecrets @0 (namespace :T.SecretNamespaceId, pagination :T.Pagination)
                -> (secrets :List(SecretEntry), total :UInt32);
    getSecret   @1 (key :T.SecretKeyId, namespace :T.SecretNamespaceId) -> (value :Data);
    hasSecret   @2 (key :T.SecretKeyId, namespace :T.SecretNamespaceId) -> (exists :Bool);

    # Batch existence check: verify multiple secrets exist without fetching values.
    hasSecrets @7 (keys :List(T.SecretKeyId), namespace :T.SecretNamespaceId)
               -> (results :List(Bool));

    setSecret      @3 (key :T.SecretKeyId, value :Data, namespace :T.SecretNamespaceId, metadata :T.StringMap)
                   -> T.VoidResult;
    deleteSecret   @4 (key :T.SecretKeyId, namespace :T.SecretNamespaceId) -> T.VoidResult;
    clearNamespace @5 (namespace :T.SecretNamespaceId) -> T.VoidResult;

    subscribeChanges @6 (namespace :T.SecretNamespaceId) -> (subscription :ChangesSubscription);

    # Audit-8: Get secret version history.
    getVersions @8 (key :T.SecretKeyId, namespace :T.SecretNamespaceId)
        -> (versions :List(SecretVersion));

    # Audit-8: Get a specific secret version.
    getVersion @9 (key :T.SecretKeyId, namespace :T.SecretNamespaceId, version :UInt32)
        -> (value :Data);

    # Audit-8: Rollback to a previous secret version.
    rollbackVersion @10 (key :T.SecretKeyId, namespace :T.SecretNamespaceId, version :UInt32)
        -> T.VoidResult;

    # Audit-8: Get rotation policy for a secret.
    getRotationPolicy @11 (key :T.SecretKeyId, namespace :T.SecretNamespaceId)
        -> (policy :RotationPolicy);

    # Audit-8: Set rotation policy for a secret.
    setRotationPolicy @12 (key :T.SecretKeyId, namespace :T.SecretNamespaceId, policy :RotationPolicy)
        -> T.VoidResult;

    # Audit-8: Apply secret overlay (environment-specific overrides).
    applyOverlay @13 (namespace :T.SecretNamespaceId, overlay :SecretOverlay)
        -> T.VoidResult;

    # Audit-8: Get secret access audit log.
    getAccessAudit @14 (namespace :T.SecretNamespaceId, pagination :T.Pagination)
        -> (entries :List(AccessAuditEntry), total :UInt64);

    # Audit-8: Export access audit log for compliance.
    exportAccessAudit @15 (namespace :T.SecretNamespaceId, format :Text)
        -> (data :T.DataHandle);

    # Audit-8: Derive a key from a password using KDF.
    deriveKey @16 (request :DeriveKeyRequest) -> (derivedKey :Data);

    # Audit-8: Split a secret using Shamir's Secret Sharing.
    splitSecret @17 (key :T.SecretKeyId, namespace :T.SecretNamespaceId,
        totalShards :UInt32, requiredShards :UInt32)
        -> (shards :List(Data));

    # Audit-8: Reconstruct a secret from shards.
    reconstructSecret @18 (shards :List(Data)) -> (secret :Data);

    # Audit-8: Inject a secret into a process (env var or file).
    injectSecret @19 (key :T.SecretKeyId, namespace :T.SecretNamespaceId,
        injection :SecretInjection) -> T.VoidResult;

    # Audit-8: Get HSM backing status for a secret.
    getHsmBacking @20 (key :T.SecretKeyId, namespace :T.SecretNamespaceId)
        -> (backing :HsmBacking);

    # Audit-9: Secret Templates — structured secret schemas.

    # List available secret templates.
    listSecretTemplates @21 () -> (templates :List(SecretTemplate));

    # Create a secret from a template (generates structured fields).
    createFromTemplate @22 (templateId :Text, namespace :T.SecretNamespaceId, fields :T.StringMap)
        -> (key :T.SecretKeyId);

    # Audit-9: Secret Generation — generate random passwords/API keys/certificates.

    # Generate a random secret from a template.
    generateSecret @23 (request :SecretGenerateRequest) -> (value :Data, metadata :T.StringMap);

    # Audit-9: Secret Comparison — constant-time comparison to prevent timing attacks.

    # Constant-time comparison of two secret values.
    compareSecrets @24 (secret1 :Data, secret2 :Data) -> (equal :Bool);

    # Audit-9: Secret Wrapping — encrypt a secret with a wrapping key.

    # Wrap (encrypt) a secret with a wrapping key.
    wrapSecret @25 (key :T.SecretKeyId, namespace :T.SecretNamespaceId, wrappingKeyId :T.SecretKeyId)
        -> (wrapped :Data);

    # Unwrap (decrypt) a wrapped secret.
    unwrapSecret @26 (wrapped :Data, wrappingKeyId :T.SecretKeyId, namespace :T.SecretNamespaceId)
        -> (secret :Data);
}

interface ChangesSubscription {
    pull   @0 (pagination :T.Pagination) -> (changes :List(SecretChange), total :UInt32);
    cancel @1 () -> T.VoidResult;
}

struct SecretEntry {
    key       @0 :T.SecretKeyId;
    namespace @1 :T.SecretNamespaceId;
    created   @2 :T.Timestamp;
    modified  @3 :T.Timestamp;
    metadata  @4 :T.StringMap;
    # Size of the secret value in bytes. Enables callers to assess
    # secret size without fetching the value itself.
    sizeBytes @5 :UInt64;
}

struct SecretChange {
    type      @0 :SecretChangeType;
    key       @1 :T.SecretKeyId;
    namespace @2 :T.SecretNamespaceId;
}

enum SecretChangeType {
    created @0;
    updated @1;
    deleted @2;
    custom  @3;
}

# ── Audit-8: Secret Version ───────────────────────────────────────────

struct SecretVersion {
    # Version number (1 = original, incremented on rotation).
    version @0 :UInt32;
    # When this version was created.
    createdAt @1 :T.Timestamp;
    # When this version expires (0 = no expiration).
    expiresAt @2 :T.Timestamp;
    # Whether this is the current active version.
    active @3 :Bool;
    # Hash of the secret value for integrity checking.
    hash @4 :Data;
}

# ── Audit-8: Rotation Policy ──────────────────────────────────────────

struct RotationPolicy {
    # Rotate after this duration (0 = no time-based rotation).
    interval @0 :T.Duration;
    # Whether to rotate immediately on compromise.
    onCompromise @1 :Bool;
    # Maximum age before forced rotation (0 = unlimited).
    maxAge @2 :T.Duration;
    # Notify before expiration (0 = no notification).
    notifyBefore @3 :T.Duration;
}

# ── Audit-8: Secret Overlay ───────────────────────────────────────────

struct SecretOverlay {
    # Environment identifier (e.g., "dev", "staging", "production").
    environmentId @0 :Text;
    # Priority (higher = overrides lower).
    priority @1 :UInt32;
    # Merge strategy (e.g., "replace", "merge", "append").
    mergeStrategy @2 :Text;
    # Key-value overrides for this environment.
    overrides @3 :T.StringMap;
}

# ── Audit-8: Access Audit Entry ───────────────────────────────────────

struct AccessAuditEntry {
    # When the access occurred.
    timestamp @0 :T.Timestamp;
    # Key that was accessed.
    keyId @1 :T.SecretKeyId;
    # Namespace of the accessed key.
    namespace @2 :T.SecretNamespaceId;
    # Action performed (e.g., "read", "write", "delete").
    action @3 :Text;
    # Who performed the access.
    actor @4 :Text;
    # Source IP address.
    sourceIp @5 :Text;
}

# ── Audit-8: HSM Backing ──────────────────────────────────────────────

struct HsmBacking {
    # Whether HSM backing is available.
    supported @0 :Bool;
    # HSM provider type (e.g., "PKCS#11", "TPM", "Secure Enclave").
    providerType @1 :Text;
    # HSM key identifier.
    keyId @2 :Text;
    # Algorithm used in HSM.
    algorithm @3 :Text;
}

# ── Audit-8: Secret Injection ─────────────────────────────────────────

struct SecretInjection {
    # Target process ID.
    processId @0 :T.ProcessId;
    # Injection method (e.g., "env", "file", "memfd").
    method @1 :Text;
    # Target path (for file injection) or env var name.
    path @2 :Text;
}

# ── Audit-8: Key Derivation Request ───────────────────────────────────

struct DeriveKeyRequest {
    # KDF algorithm (e.g., "PBKDF2", "scrypt", "Argon2", "HKDF").
    algorithm @0 :Text;
    # Password or base key material.
    password @1 :Data;
    # Salt for the KDF.
    salt @2 :Data;
    # Number of iterations (for iterative KDFs).
    iterations @3 :UInt32;
    # Desired key length in bytes.
    keyLength @4 :UInt32;
}

# ── Audit-8: Secret Compliance Policy (false positive: secret_compliance.capnp) ─

struct SecretCompliancePolicy {
    # Minimum secret length in bytes.
    minLength @0 :UInt32;
    # Maximum secret length in bytes (0 = unlimited).
    maxLength @1 :UInt32;
    # Required character classes (e.g., "upper", "lower", "digit", "special").
    requiredClasses @2 :List(Text);
    # Maximum age before forced rotation.
    maxAge @3 :T.Duration;
    # Whether HSM backing is required.
    requireHsm @4 :Bool;
    # Whether audit logging is required.
    requireAudit @5 :Bool;
}

# ── Audit-9: Secret Template ───────────────────────────────────────────
# Structured secret schemas (password = username+password, API key = key+secret+endpoint).
struct SecretTemplate {
    # Template identifier.
    templateId @0 :Text;
    # Human-readable template name.
    name @1 :Text;
    # Description of what this template generates.
    description @2 :Text;
    # Field definitions for this template.
    fields @3 :List(SecretTemplateField);
    # Default generation parameters.
    defaults @4 :SecretGenerateRequest;
}

struct SecretTemplateField {
    # Field name (e.g., "username", "password", "endpoint").
    name @0 :Text;
    # Field type (e.g., "text", "password", "url", "email").
    type @1 :Text;
    # Whether this field is required.
    required @2 :Bool;
    # Default value (if any).
    defaultValue @3 :Text;
    # Validation pattern (regex, if applicable).
    validationPattern @4 :Text;
    # Whether this field should be masked in UI.
    sensitive @5 :Bool;
}

# ── Audit-9: Secret Generation Request ─────────────────────────────────
struct SecretGenerateRequest {
    # Generation algorithm (e.g., "random", "diceware", "xkcd", "uuid", "certificate").
    algorithm @0 :Text;
    # Desired length in characters/bits (interpretation depends on algorithm).
    length @1 :UInt32;
    # Character set to use (for random generation).
    characterSet @2 :Text;
    # Number of words (for diceware/xkcd).
    wordCount @3 :UInt32;
    # Word list to use (for diceware/xkcd).
    wordList @4 :Text;
    # Certificate subject (for certificate generation).
    certificateSubject @5 :Text;
    # Certificate validity duration.
    certificateValidity @6 :T.Duration;
}

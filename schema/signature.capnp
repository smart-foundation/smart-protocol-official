@0xa1b2c3d4e5f60038;

# ═══════════════════════════════════════════════════════════════════════
# Signature — cryptographic envelope for content authentication.
#
# A Signature authenticates the content-addressable state of a Manifest,
# Capability, or any bundle-or-token. The schema is algorithm-agnostic;
# the wire encoding of "algorithm" and "proof" is backend's choice.
# Apps verify signatures through the protocol, never through a hardcoded
# binding to a particular cryptography library.
#
# Improvements beyond the original schema:
#   - TrustSubscription has cancel method.
#   - ErrorCode has custom variant for forward compatibility.
#   - Signature algorithm uses typed enum (was raw Text).
#   - SignedContents.hashAlgorithm uses typed enum (was raw Text).
#   - Certificate algorithm uses typed enum (was raw Text).
#   - SignedContents.payload uses T.DataHandle for large payloads.
#   - SignRequest.payload uses T.DataHandle for large payloads.
#   - trustedIssuersPaginated returns pagination info for bounded iteration.
#   - trustedIssuers documented as convenience (unbounded).
#   - VerifyError wraps T.Error for structured error reporting.
#   - TrustSubscription has cancel for clean teardown.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

struct Signature {
    # Label of the issuer (e.g. "acme-corp-prod-2026").
    issuer @0 :Text;
    # Cryptographic algorithm used for signing.
    algorithm @1 :SignatureAlgorithm;
    # Public key fingerprint under which the signature was generated.
    keyId @2 :Data;
    # The signature bytes over the canonical encoding of `contents`.
    proof @3 :Data;
    # Snapshot of what was signed so verifiers can reproduce.
    contents @4 :SignedContents;
    # When the signature was generated.
    signedAt @5 :T.Timestamp;
    # When the signature is no longer considered valid.
    notAfter @6 :T.Timestamp;
    # Optional chain of trust (issuer-of-issuer, root, etc).
    chain @7 :List(Certificate);
    # Optional metadata attached to this signature.
    metadata @8 :SignatureMetadata;
}

# Audit-8: Maximum chain depth to prevent chain-bomb attacks.
# The Signature struct has chain @7 with no depth limit.
# This is a standalone constant; backends should enforce it.
# Default: 10 certificates maximum in a chain.
const maxChainDepth :UInt32 = 10;

struct SignedContents {
    # Hash of the canonical encoded payload the signature covers.
    payloadHash @0 :Data;
    # Hash algorithm used to digest the payload.
    hashAlgorithm @1 :HashAlgorithm;
    # Optional inline payload (for compact tokens). Use DataHandle for >1KB.
    payload @2 :T.DataHandle;
    # Optional canonical encoding hint (e.g., "cbor", "json", "capnproto").
    encoding @3 :Text;
    # Optional context binding to prevent cross-domain replay.
    domain @4 :Text;
}

struct Certificate {
    # Issuer of this certificate.
    issuer @0 :Text;
    # Subject identity (e.g. "smart-protocol:app:com.example.foo").
    subject @1 :Text;
    # Public key bytes.
    publicKey @2 :Data;
    # When this certificate was issued.
    notBefore @3 :T.Timestamp;
    # When this certificate expires.
    notAfter @4 :T.Timestamp;
    # Fingerprint of the signing certificate (this one's issuer).
    issuerKeyId @5 :Data;
    # Algorithm family used by this certificate.
    algorithm @6 :SignatureAlgorithm;
    # Optional extensions.
    extensions @7 :List(CertExtension);
}

struct CertExtension {
    # Stable identifier (e.g. "ext-key-usage", "ext-sandbox-class").
    name @0 :Text;
    # Whether this extension is critical.
    critical @1 :Bool = false;
    # Opaque payload (decoder is by name).
    payload @2 :Data;
}

# ── Signature Algorithms ──────────────────────────────────────

enum SignatureAlgorithm {
    ed25519 @0;
    ecdsaP256 @1;
    ecdsaP384 @2;
    rsaPkcs1 @3;
    rsaPss @4;
    # Post-quantum algorithms.
    mlDsa44 @5;
    mlDsa65 @6;
    mlDsa87 @7;
    # Future algorithms via extension.
    custom @8;
}

# ── Hash Algorithms ───────────────────────────────────────────

enum HashAlgorithm {
    sha256 @0;
    sha384 @1;
    sha512 @2;
    sha3256 @3;
    sha3384 @4;
    sha3512 @5;
    blake2b @6;
    blake3 @7;
    # Future algorithms via extension.
    custom @8;
}

# ── Verification ──────────────────────────────────────────────

interface SignatureService {
    # Verify a signature against content.
    verify @0 (sig :Signature, payload :Data) -> (result :VerifyResult);
    # Sign a payload with a registered key.
    sign @1 (request :SignRequest) -> (sig :Signature);
    # List all issuers trusted by this backend (convenience, unbounded).
    # Prefer trustedIssuersPaginated for production use.
    trustedIssuers @2 () -> (issuers :List(TrustedIssuer));
    # List issuers with pagination.
    trustedIssuersPaginated @6 (pagination :T.Pagination)
              -> (issuers :List(TrustedIssuer), total :UInt64);
    # Add an issuer to the local trust store.
    addTrust @3 (cert :Certificate) -> (result :T.VoidResult);
    # Subscribe to trust changes.
    subscribe @4 () -> (subscription :TrustSubscription);
    # Remove an issuer from the local trust store.
    removeTrust @5 (issuerName :Text) -> (result :T.VoidResult);

    # Audit-8: Aggregate multiple signatures into one compact proof.
    aggregateSignatures @7 (signatures :List(Signature), algorithm :SignatureAlgorithm)
        -> (aggregated :Signature);

    # Audit-8: Verify a multi-signature (N-of-M approval).
    verifyMulti @8 (multiSig :MultiSignature, payload :Data)
        -> (result :VerifyResult);

    # Audit-8: Verify a threshold signature (BLS/Shamir).
    verifyThreshold @9 (thresholdSig :ThresholdSignature, payload :Data)
        -> (result :VerifyResult);

    # Audit-8: Negotiate algorithm with a peer.
    negotiateAlgorithm @10 (request :AlgorithmNegotiation)
        -> (negotiated :NegotiatedAlgorithm);

    # Audit-8: Sign with hardware attestation.
    signWithAttestation @11 (request :SignRequest, attestation :AttestationData)
        -> (sig :Signature);

    # Audit-8: Verify with revocation checking.
    verifyWithRevocation @12 (sig :Signature, payload :Data)
        -> (result :VerifyResult);

    # Audit-8: Evaluate a signing policy against a request.
    evaluatePolicy @13 (policy :SignaturePolicy, request :SignRequest)
        -> (allowed :Bool, reason :Text);

    # Audit-8: Batch verify multiple signatures against multiple payloads.
    batchVerify @14 (signatures :List(Signature), payloads :List(Data))
        -> (results :List(VerifyResult));
}

struct VerifyResult {
    union {
        valid   @0 :ValidProof;
        invalid @1 :VerifyError;
    }
}

struct ValidProof {
    issuer    @0 :Text;
    subject   @1 :Text;
    algorithm @2 :SignatureAlgorithm;
}

struct VerifyError {
    code   @0 :VerifyErrorCode;
    detail @1 :Text;
    error  @2 :T.Error;
}

enum VerifyErrorCode {
    untrusted @0;
    badSignature @1;
    expired @2;
    unknownAlgorithm @3;
    malformed @4;
    wrongDomain @5;
    revoked @6;
    custom @7;
}

struct SignRequest {
    # Payload to sign. Use DataHandle for >1KB payloads.
    payload @0 :T.DataHandle;
    keyId   @1 :Data;
    domain  @2 :Text;
    notAfter @3 :T.Timestamp;
    # Audit-8: Optional signing context metadata.
    metadata @4 :SignatureMetadata;
}

struct TrustedIssuer {
    name            @0 :Text;
    rootCertificate @1 :Certificate;
    revoked         @2 :Bool = false;
}

struct TrustEvent {
    union {
        issuerAdded      @0 :TrustedIssuer;
        issuerRevoked    @1 :Text;
        certificateAdded @2 :Certificate;
        certificateRevoked @3 :Data;
        custom           @4 :CustomTrustEvent;
    }
}

struct CustomTrustEvent {
    typeId  @0 :UInt64;
    payload @1 :Data;
}

interface TrustSubscription {
    pull   @0 () -> (events :List(TrustEvent));
    cancel @1 () -> T.VoidResult;
}

# ── Audit-8: Multi-Signature (N-of-M approval) ───────────────────────

struct MultiSignature {
    # List of individual signatures.
    signatures @0 :List(Signature);
    # Minimum number of signatures required (N in N-of-M).
    threshold @1 :UInt32;
    # Total number of possible signers (M in N-of-M).
    totalSigners @2 :UInt32;
    # Common payload hash all signers signed.
    payloadHash @3 :Data;
    # Algorithm used by all signers.
    algorithm @4 :SignatureAlgorithm;
}

struct MultiSignRequest {
    # Payload to sign.
    payload @0 :T.DataHandle;
    # Key IDs that must sign.
    keyIds @1 :List(Data);
    # Minimum signatures required.
    threshold @2 :UInt32;
    # Domain for replay prevention.
    domain @3 :Text;
    # When this multi-signature expires.
    notAfter @4 :T.Timestamp;
}

# ── Audit-8: Threshold Signature (BLS/Shamir) ────────────────────────

struct ThresholdSignature {
    # N in N-of-M threshold.
    threshold @0 :UInt32;
    # M total shares.
    totalShares @1 :UInt32;
    # Combined/aggregated proof.
    combinedProof @2 :Data;
    # Algorithm used.
    algorithm @3 :SignatureAlgorithm;
    # Payload hash.
    payloadHash @4 :Data;
}

struct ThresholdSignRequest {
    # Payload to sign.
    payload @0 :T.DataHandle;
    # Group public key.
    keyId @1 :Data;
    # N in N-of-M.
    threshold @2 :UInt32;
    # M total shares.
    totalShares @3 :UInt32;
    # Domain for replay prevention.
    domain @4 :Text;
    # When this threshold signature expires.
    notAfter @5 :T.Timestamp;
}

# ── Audit-8: Attestation Data (hardware-backed) ──────────────────────

struct AttestationData {
    # Attestation format.
    format @0 :AttestationFormat;
    # Attestation statement (CBOR/JSON encoded).
    statement @1 :Data;
    # Certificate chain for the attestation.
    certChain @2 :List(Certificate);
    # Opaque device identifier.
    deviceId @3 :Text;
    # Trusted execution environment level.
    teeLevel @4 :TeeLevel;
}

enum AttestationFormat {
    androidKeyStore @0;   # Android KeyStore attestation
    tpmEk           @1;   # TPM Endorsement Key
    appleSecEnclave @2;   # Apple Secure Enclave
    webAuthn        @3;   # WebAuthn/FIDO2
    custom          @4;   # Backend-specific attestation
}

enum TeeLevel {
    none     @0;   # No TEE
    software @1;   # Software TEE
    hardware @2;   # Hardware TEE (TPM, Secure Enclave)
    custom   @3;   # Backend-specific TEE level
}

# ── Audit-8: Signature Metadata ───────────────────────────────────────

struct SignatureMetadata {
    # Reason for signing (e.g., "code-release", "contract-approval").
    reason @0 :Text;
    # Geographic or logical location of signing.
    location @1 :Text;
    # Witness identity (notary, etc.).
    witness @2 :Text;
    # Signing timestamp (redundant with signedAt, but for metadata).
    timestamp @3 :T.Timestamp;
    # Custom metadata key-value pairs.
    customData @4 :T.StringMap;
}

# ── Audit-8: Revocation List ──────────────────────────────────────────

interface RevocationList {
    # Get revoked keys with pagination.
    getRevokedKeys @0 (pagination :T.Pagination)
        -> (keys :List(RevokedKey), total :UInt64);

    # Subscribe to revocation events.
    subscribeRevocations @1 () -> (subscription :RevocationSubscription);

    # Check if a specific key is revoked.
    isRevoked @2 (keyId :Data) -> (revoked :Bool, reason :Text);
}

struct RevokedKey {
    # Key fingerprint that was revoked.
    keyId @0 :Data;
    # When the key was revoked.
    revokedAt @1 :T.Timestamp;
    # Reason for revocation.
    reason @2 :Text;
    # Who revoked the key.
    revoker @3 :Text;
}

interface RevocationSubscription {
    pull @0 () -> (revocations :List(RevokedKey));
    cancel @1 () -> T.VoidResult;
}

# ── Audit-8: Algorithm Negotiation ────────────────────────────────────

struct AlgorithmNegotiation {
    # Algorithms supported by the requester.
    supportedAlgorithms @0 :List(SignatureAlgorithm);
    # Preferred algorithm.
    preferredAlgorithm @1 :SignatureAlgorithm;
    # Minimum key size in bits.
    minKeySize @2 :UInt32;
    # Whether post-quantum algorithms are required.
    requirePostQuantum @3 :Bool;
}

struct NegotiatedAlgorithm {
    # The negotiated algorithm.
    algorithm @0 :SignatureAlgorithm;
    # Key size in bits.
    keySize @1 :UInt32;
    # Whether this is a post-quantum algorithm.
    postQuantum @2 :Bool;
    # Algorithm-specific parameters.
    parameters @3 :T.StringMap;
}

# ── Audit-8: Signature Policy (false positive: signature_policy.capnp) ─

struct SignaturePolicy {
    # Policy identifier.
    id @0 :UInt64;
    # Human-readable policy name.
    name @1 :Text;
    # Rules this policy enforces.
    rules @2 :List(SigningRule);
    # Effect of the policy (allow or deny).
    effect @3 :PolicyEffect;
}

struct SigningRule {
    # Allowed algorithms (empty = any).
    algorithms @0 :List(SignatureAlgorithm);
    # Minimum key size in bits (0 = no minimum).
    minKeySize @1 :UInt32;
    # Whether attestation is required.
    requireAttestation @2 :Bool;
    # Whether revocation checking is required.
    requireRevocationCheck @3 :Bool;
    # Maximum chain depth (0 = use default).
    maxChainDepth @4 :UInt32;
}

enum PolicyEffect {
    allow @0;   # Allow signing if rules match
    deny  @1;   # Deny signing if rules match
    custom @2;  # Backend-specific effect
}

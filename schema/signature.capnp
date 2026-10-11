@0xa1b2c3d4e5f60038;

# ═══════════════════════════════════════════════════════════════════════
# Signature — cryptographic envelope for content authentication.
#
# A Signature authenticates the content-addressable state of a Manifest,
# Capability, or any bundle-or-token. Apps verify signatures through the
# protocol, never through a hardcoded binding to a particular
# cryptography library.
#
# ── ALGORITHM VOCABULARY: ONE HOME, OPEN TOKENS ────────────────────────
#
# This file used to declare `SignatureAlgorithm` and `HashAlgorithm`
# locally, at ordinals that DIVERGED from crypto.capnp's enums of the same
# names: ed25519 was @0 here and @12 there, sha256 was @0 here and @1
# there, and the ordinal 5 meant mlDsa44 in one file and ecdsaSha256 in
# the other. Nothing failed to compile — neither file imported the other —
# but any service, log line, or stored message carrying a bare algorithm
# ordinal across that boundary was silently reinterpreted.
#
# The fix is structural, not cosmetic: there are no algorithm enums left
# anywhere in this batch. crypto.capnp is the canonical vocabulary home
# and publishes open tokens plus conformance `const` values; this file
# uses the same open `Text` tokens, so a divergent ordinal cannot exist.
# Interoperability is preserved by the published spellings, not by a
# frozen list.
#
# Everything else is imported as well: the verification outcome type and
# the certificate representation come from crypto.capnp (the canonical
# vocabulary home), and the forward-compatibility primitive is
# T.UnknownEvent from types.capnp. One shape per concept.
#
# ── SYMMETRY: EVERY PAYLOAD IS A HANDLE ─────────────────────────────────
#
# The sign path always took T.DataHandle; every verify path took inline
# Data. Verification is the hot path — every app start verifies something
# — and it copied the entire payload into the message: verifying a 50 MB
# artifact cost a 50 MB copy while signing the same artifact was free.
# `batchVerify` copied N payloads into one message on the path designed
# for bulk verification. All payload parameters are now handles.
#
# ── KEY IDENTITY ────────────────────────────────────────────────────────
#
# Keys were addressed by opaque fingerprint bytes with no declared
# algorithm, so a backend had to guess from the byte length (the
# types.capnp comment admitted "use keyId length as heuristic; legacy").
# Every key reference is now T.KeyFingerprint, which pairs the bytes with
# the hash that produced them, and correlates with key_management's
# T.KeyId.
#
# ── REACHABILITY ────────────────────────────────────────────────────────
#
# The `RevocationList` interface and its subscription were returned by no
# method in the entire protocol — nothing could obtain one — so revocation
# existed only as dead surface here and as live surface in
# capability.capnp and key_management.capnp. Both are deleted; the trust
# store this service already maintains (addTrust / removeTrust /
# TrustSubscription) is the revocation path, and `verifyWithRevocation`
# consults it.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using Crypto = import "crypto.capnp";

struct Signature {
    # Label of the issuer (e.g. "acme-corp-prod-2026").
    issuer @0 :Text;
    # Algorithm that produced this signature, as an open token
    # (see crypto.capnp's CONFORMANCE TOKENS).
    algorithm @1 :Text;
    # Fingerprint of the key under which the signature was generated.
    # Self-describing, so a verifier does not infer the fingerprint
    # algorithm from the byte length.
    keyId @2 :T.KeyFingerprint;
    # The signature bytes over the canonical encoding of `contents`.
    proof @3 :Data;
    # Snapshot of what was signed so verifiers can reproduce.
    contents @4 :SignedContents;
    # When the signature was generated.
    signedAt @5 :T.Timestamp;
    # When the signature is no longer considered valid.
    notAfter @6 :T.Timestamp;
    # Optional chain of trust (issuer-of-issuer, root, etc).
    chain @7 :List(Crypto.CertificateInfo);
    # Optional metadata attached to this signature.
    metadata @8 :SignatureMetadata;
    # Backend-specific extras.
    custom @9 :Data;
}

# Audit-8: Maximum chain depth to prevent chain-bomb attacks.
# The Signature struct has chain @7 with no depth limit.
# This is a standalone constant; backends should enforce it.
# Default: 10 certificates maximum in a chain.
const maxChainDepth :UInt32 = 10;

# Canonical encoding of the signed bytes. A backend that produced a
# signature over a different canonical form than the verifier expects
# yields a valid signature that verifies against itself and fails
# everywhere else, with no way to tell why. The token is open; the
# published spelling below is a convention, not a requirement.
const encodingCapnproto :Text = "capnproto";
const encodingCbor       :Text = "cbor";
const encodingJson       :Text = "json";

struct SignedContents {
    # Hash of the canonical encoded payload the signature covers.
    payloadHash @0 :Data;
    # Hash used to digest the payload, as an open token.
    hashAlgorithm @1 :Text;
    # Optional inline payload (for compact tokens). Use DataHandle for >1KB.
    payload @2 :T.DataHandle;
    # Canonical encoding hint; see conformance tokens above. A backend
    # MUST declare which encoding it produced when it sets this, and a
    # verifier MUST refuse to verify across an encoding it does not
    # implement rather than guessing.
    encoding @3 :Text;
    # Optional context binding to prevent cross-domain replay.
    domain @4 :Text;
}

# ── Verification ──────────────────────────────────────────────

interface SignatureService {
    verify @0 (sig :Signature, payload :T.DataHandle) -> (result :Crypto.SignatureVerifyResult);
    # Sign a payload with a registered key.
    sign @1 (request :SignatureRequest) -> (sig :Signature);
    # List all issuers trusted by this backend (convenience, unbounded).
    # Prefer trustedIssuersPaginated for production use.
    trustedIssuers @2 () -> (issuers :List(TrustedIssuer));
    # List issuers with pagination.
    addTrust @3 (cert :Crypto.CertificateInfo) -> (result :T.VoidResult);
    # Subscribe to trust changes.
    subscribe @4 () -> (subscription :TrustSubscription);
    # Remove an issuer from the local trust store.
    removeTrust @5 (issuerName :Text) -> (result :T.VoidResult);

    # Audit-8: Aggregate multiple signatures into one compact proof.
    # Returns a MultiSignature so the aggregate carries its own threshold
    # metadata: a bare Signature gave a verifier no way to learn how many
    # signatures it represented or what the threshold was.
    trustedIssuersPaginated @6 (pagination :T.Pagination)
              -> (issuers :List(TrustedIssuer), total :UInt64);
    # Add an issuer to the local trust store.
    aggregateSignatures @7 (signatures :List(Signature), algorithm :Text)
        -> (aggregated :MultiSignature);

    # Audit-8: Verify a multi-signature (N-of-M approval).
    verifyMulti @8 (multiSig :MultiSignature, payload :T.DataHandle)
        -> (result :Crypto.SignatureVerifyResult);

    # Audit-8: Verify a threshold signature (BLS/Shamir).
    verifyThreshold @9 (thresholdSig :ThresholdSignature, payload :T.DataHandle)
        -> (result :Crypto.SignatureVerifyResult);

    # Audit-8: Negotiate algorithm with a peer.
    negotiateAlgorithm @10 (request :AlgorithmNegotiation)
        -> (negotiated :NegotiatedAlgorithm);

    # Audit-8: Sign with hardware attestation.
    signWithAttestation @11 (request :SignatureRequest, attestation :AttestationData)
        -> (sig :Signature);

    # Audit-8: Verify with revocation checking (against the trust store
    # maintained by addTrust/removeTrust and observed through
    # TrustSubscription).
    verifyWithRevocation @12 (sig :Signature, payload :T.DataHandle)
        -> (result :Crypto.SignatureVerifyResult);

    # Audit-8: Evaluate a signing policy against a request. Returns a
    # union: the previous bare Bool let a policy evaluation fail with no
    # wire representation of why.
    evaluatePolicy @13 (policy :SignaturePolicy, request :SignatureRequest)
        -> (result :PolicyEvaluationResult);

    # Audit-8: Batch verify multiple signatures against multiple payloads.
    batchVerify @14 (signatures :List(Signature), payloads :List(T.DataHandle))
        -> (results :List(Crypto.SignatureVerifyResult));
}

    # Verify a signature against content.
struct SignatureRequest {
    # Payload to sign.
    payload @0 :T.DataHandle;
    # Fingerprint of the signing key.
    keyId @1 :T.KeyFingerprint;
    domain @2 :Text;
    notAfter @3 :T.Timestamp;
    # Algorithm to sign with, as an open token.
    algorithm @4 :Text;
    # Audit-8: Optional signing context metadata.
    metadata @5 :SignatureMetadata;
    # Backend-specific extras. Named `SignatureRequest`, not
    # `SignRequest`, so it cannot collide with crypto.capnp's primitive
    # `SignRequest` — same name, different shape, is an import hazard
    # (R6), and this request addresses a REGISTERED KEY by fingerprint
    # while the primitive one takes raw key material.
    custom @6 :T.StringMap;
}

struct TrustedIssuer {
    name @0 :Text;
    rootCertificate @1 :Crypto.CertificateInfo;
    revoked @2 :Bool = false;
    custom @3 :Data;
}

struct TrustEvent {
    union {
        issuerAdded @0 :TrustedIssuer;
        issuerRevoked @1 :Text;
        certificateAdded @2 :Crypto.CertificateInfo;
        certificateRevoked @3 :T.KeyFingerprint;
        # Forward compatibility: a trust event kind this schema does not
        # name arrives here with a typed discriminator, instead of being
        # forced into an untyped `custom` payload no consumer can key.
        unknown @4 :T.UnknownEvent;
    }
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
    # Algorithm used by all signers, as an open token.
    algorithm @4 :Text;
    custom @5 :Data;
}

# ── Audit-8: Threshold Signature (BLS/Shamir) ────────────────────────

struct ThresholdSignature {
    # N in N-of-M threshold.
    threshold @0 :UInt32;
    # M total shares.
    totalShares @1 :UInt32;
    # Combined/aggregated proof.
    combinedProof @2 :Data;
    # Algorithm used, as an open token.
    algorithm @3 :Text;
    # Payload hash.
    payloadHash @4 :Data;
    custom @5 :Data;
}

# ── Audit-8: Attestation Data (hardware-backed) ──────────────────────

struct AttestationData {
    # Attestation format, as an open token. The previous enum named
    # Android KeyStore, Apple Secure Enclave, TPM EK and WebAuthn — two
    # of them vendor products — so a Linux, Windows, or open-hardware
    # attestation and any 2046 platform had only `custom` carrying
    # nothing, and this field could not report what the attestation
    # actually was. The backend reports the mechanism it used.
    format @0 :Text;
    # Attestation statement (CBOR/JSON encoded).
    statement @1 :T.DataHandle;
    # Certificate chain for the attestation.
    certChain @2 :List(Crypto.CertificateInfo);
    # Opaque device identifier.
    deviceId @3 :T.DeviceId;
    # Trusted execution environment level.
    teeLevel @4 :TeeLevel;
    custom @5 :T.StringMap;
}

enum TeeLevel {
    none @0;   # No TEE
    software @1;
    hardware @2;
    custom @3;
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

# ── Audit-8: Algorithm Negotiation ────────────────────────────────────

struct AlgorithmNegotiation {
    # Algorithms supported by the requester, as open tokens.
    supportedAlgorithms @0 :List(Text);
    # Preferred algorithm.
    preferredAlgorithm @1 :Text;
    # Minimum key size in bits.
    minKeySize @2 :UInt32;
    # Whether post-quantum algorithms are required.
    requirePostQuantum @3 :Bool;
    custom @4 :T.StringMap;
}

struct NegotiatedAlgorithm {
    algorithm @0 :Text;
    keySize @1 :UInt32;
    # Whether this is a post-quantum algorithm.
    postQuantum @2 :Bool;
    # Algorithm-specific parameters.
    parameters @3 :T.StringMap;
}

# ── Audit-8: Signature Policy ─────────────────────────────────────────
# Declarative constraints on what may be signed. Authority itself is NOT
# expressed here — it is the interface reference plus capability.capnp's
# attenuation. This vocabulary governs the shape of an acceptable
# signature, not who may produce one; the two must not be conflated, and
# a policy denial here does not substitute for a capability granted there.

struct SignaturePolicy {
    # Policy identifier.
    id @0 :UInt64;
    # Human-readable policy name.
    name @1 :Text;
    # Rules this policy enforces.
    rules @2 :List(SigningRule);
    # Effect of the policy.
    effect @3 :PolicyEffect;
    custom @4 :T.StringMap;
}

struct SigningRule {
    # Allowed algorithms, as open tokens (empty = any).
    algorithms @0 :List(Text);
    # Minimum key size in bits (0 = no minimum).
    minKeySize @1 :UInt32;
    # Whether attestation is required.
    requireAttestation @2 :Bool;
    # Whether revocation checking is required.
    requireRevocationCheck @3 :Bool;
    # Maximum chain depth (0 = use the maxChainDepth constant).
    maxChainDepth @4 :UInt32;
    custom @5 :T.StringMap;
}

enum PolicyEffect {
    # Sentinel: an unset effect means "no verdict", never "allow".
    unspecified @0;
    allow @1;
    deny  @2;
    custom @3;
}

struct PolicyEvaluationResult {
    union {
        allowed @0 :PolicyAllowed;
        denied @1 :PolicyDenied;
        unknown @2 :T.UnknownEvent;
    }
}

struct PolicyAllowed {
    reason @0 :Text;
    appliedRule @1 :Text;
    custom @2 :T.StringMap;
}

struct PolicyDenied {
    # Open token naming the rule class that refused (see
    # crypto.capnp's verification failure tokens); never a permission
    # string — authority is capability.capnp's job, not this file's.
    reason @0 :Text;
    detail @1 :Text;
    error @2 :T.Error;
    custom @3 :T.StringMap;
}

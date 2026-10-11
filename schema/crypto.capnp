@0xa1b2c3d4e5f60104;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Crypto — general-purpose cryptographic operations.
#
# Zero backend assumptions: no OpenSSL, no libsodium, no CryptoAPI,
# no WebCrypto, no BoringSSL, no TPM, no HSM vendor. The backend provides
# the primitives; this file defines the contract.
#
# ── THE VOCABULARY RULE ─────────────────────────────────────────────────
#
# This file contains NO algorithm enums. That is deliberate, and it is the
# same rule ai.capnp states at the top of its own header: an enum ordinal
# is a permanent commitment to a technology, and any list of algorithms is
# today's list.
#
# The proof is this file's own history. It was amended once already — NIST
# FIPS 203/204/205 (ML-KEM, ML-DSA, SLH-DSA) had to be appended as new
# permanent ordinals because the original list lacked them. Every future
# construction would have cost the same tax forever, and a backend could
# never be asked for an algorithm the list happened to omit. Two backends
# therefore could not interoperate on anything invented after the list was
# frozen, and `custom @N` carried no identification, so even a working
# "custom" exchange was unintelligible to the peer.
#
# So an algorithm is an OPEN TOKEN (Text) plus an open parameter map:
#
#   algorithm  @0 :Text;          # see CONFORMANCE TOKENS below
#   parameters @1 :T.StringMap;   # key sizes, modes, cost knobs
#
# Interoperability is preserved by the tokens being published as `const`
# values that nothing requires and that an unrecognized consumer ignores —
# exactly the pattern ai.capnp's CONFORMANCE TOKENS section establishes.
# New constructions become requestable with NO schema change and NO new
# ordinal. `getSupportedAlgorithms` reports the same spellings, so a caller
# can ask a peer what it supports before asking for it.
#
# This file is the canonical crypto vocabulary home. signature.capnp,
# key_management.capnp, biometric.capnp and secret.capnp import these
# tokens; none of them re-declares an algorithm list. (The previous local
# copies in signature.capnp and this file carried the SAME enum names at
# DIVERGENT ordinals — ed25519 @0 vs @12, sha256 @0 vs @1 — so a bare
# algorithm ordinal crossing that boundary was silently reinterpreted.)
#
# ── AUTHORITY IS THE INTERFACE REFERENCE ───────────────────────────────
#
# No method takes a Capability parameter. Holding the reference IS the
# authority to use the primitive; attenuation and revocation belong to
# capability.capnp.
#
# ── ZERO-COPY IS A CONSTRAINT ──────────────────────────────────────────
#
# Every bulk payload is a T.DataHandle: ciphertexts, plaintexts, key
# material, wrapped keys, shared secrets, random output, certificate
# blobs. Request sides already were handle-based; result sides now are
# too, so an encrypt→decrypt round trip of a 100 MB payload no longer
# copies it twice. Small, construction-bounded values (digests, tags,
# nonces, signatures, fingerprints) stay inline `Data`: a handle for a
# 16-byte tag would add a copy, not remove one.
# ═══════════════════════════════════════════════════════════════════════

interface CryptoService {
    # ─── Hashing ────────────────────────────────────────────────────

    # Compute hash of data.
    hash @0 (request :HashRequest) -> (result :HashResult);

    # Compute hash of data using streaming (for large inputs).
    hashStream @1 (request :HashStreamRequest) -> (stream :HashStream);

    # ─── HMAC ──────────────────────────────────────────────────────

    # Compute HMAC.
    hmac @2 (request :HmacRequest) -> (result :HmacResult);

    # Compute HMAC using streaming.
    hmacStream @3 (request :HmacStreamRequest) -> (stream :HmacStream);

    # ─── Key Derivation (KDF) ──────────────────────────────────────

    # Derive key from password/passphrase.
    deriveKey @4 (request :DeriveKeyRequest) -> (result :DeriveKeyResult);

    # Derive key from key material (HKDF, KBKDF).
    deriveKeyFromKey @5 (request :DeriveKeyFromKeyRequest) -> (result :DeriveKeyResult);

    # ─── Secure Random ──────────────────────────────────────────────

    # Generate cryptographically secure random bytes. The result is a
    # handle: the previous inline `Data` return capped generation at the
    # message size, so a key or nonce larger than one message could not
    # be produced at all.
    randomBytes @6 (length :UInt32) -> (bytes :T.DataHandle);

    # Generate random bytes into a buffer (for large requests).
    randomBytesBuffer @7 (bufferId :T.BufferId, offset :UInt64, length :UInt32) -> T.VoidResult;

    # ─── Symmetric Encryption ──────────────────────────────────────

    # Encrypt data with symmetric key (AEAD).
    encrypt @8 (request :EncryptRequest) -> (result :EncryptResult);

    # Decrypt data with symmetric key (AEAD).
    decrypt @9 (request :DecryptRequest) -> (result :DecryptResult);

    # ─── Asymmetric Operations ─────────────────────────────────────

    # Generate asymmetric key pair.
    generateKeyPair @10 (request :GenerateKeyPairRequest) -> (result :GenerateKeyPairResult);

    # Sign data with private key.
    sign @11 (request :SignRequest) -> (result :SignResult);

    # Verify signature with public key.
    verify @12 (request :SignatureVerifyRequest) -> (result :SignatureVerifyResult);
    # Key agreement (ECDH, X25519, ML-KEM, ...).
    keyAgreement @13 (request :KeyAgreementRequest) -> (result :KeyAgreementResult);

    # ─── Key Wrapping/Unwrapping ──────────────────────────────────

    # Wrap (encrypt) a key with another key.
    wrapKey @14 (request :WrapKeyRequest) -> (result :WrapKeyResult);

    # Unwrap (decrypt) a key with another key.
    unwrapKey @15 (request :UnwrapKeyRequest) -> (result :UnwrapKeyResult);

    # ─── Key Import/Export ────────────────────────────────────────

    # ─── Certificate Operations ────────────────────────────────────

    # Parse a certificate. `format` is an open token ("der", "pem", ...);
    # the previous signature accepted only raw DER, which made DER
    # effectively mandatory for every backend.
    parseCertificate @16 (certificate :T.DataHandle, format :Text) -> (cert :CertificateInfo);

    # Verify certificate chain. `format` names the encoding of every blob
    # in `chain` and `trustAnchors`.
    verifyCertificateChain @17 (chain :List(T.DataHandle), trustAnchors :List(T.DataHandle),
                                format :Text) -> (result :VerifyChainResult);

    # ─── Constant-Time Operations ──────────────────────────────────

    # Constant-time memory comparison. Both operands are handles: copying
    # two secrets inline before the "constant-time" step both defeated the
    # property the method exists to provide and left two secrets in the
    # message arena.
    constantTimeCompare @18 (a :T.DataHandle, b :T.DataHandle) -> (equal :Bool);

    # Constant-time memory copy (for secret data).
    constantTimeCopy @19 (dst :T.BufferId, src :T.DataHandle, offset :UInt64) -> T.VoidResult;

    # ─── Capability Query ──────────────────────────────────────────

    # Report the algorithms this backend supports, as open tokens.
    getSupportedAlgorithms @20 () -> (algorithms :SupportedAlgorithms);

    # Check if an algorithm (and hardware acceleration for it) is available.
    isAlgorithmSupported @21 (algorithm :AlgorithmSpec) -> (supported :Bool, hardwareAccelerated :Bool);

    # Import a key. `format` is an open token, so a backend holding a key
    # in any encoding (DER, PEM, JWK, a future one) can hand it over
    # instead of pre-decoding outside the protocol.
    importKey @22 (request :ImportKeyRequest) -> (result :ImportKeyResult);

    # Export a key to a named format.
    exportKey @23 (request :ExportKeyRequest) -> (result :ExportKeyResult);

    # ─── Streaming AEAD ───────────────────────────────────────────

    # Streaming encrypt for large data (chunked AEAD).
    encryptStream @24 (request :EncryptStreamRequest) -> (stream :EncryptStream);

    # Streaming decrypt for large data (chunked AEAD).
    decryptStream @25 (request :DecryptStreamRequest) -> (stream :DecryptStream);

    # ─── DRBG (Deterministic Random Bit Generator) ────────────────

    # Create a DRBG instance for deterministic randomness.
    createDrbg @26 (request :CreateDrbgRequest) -> (handle :DrbgHandle);

    # Generate random bytes from a DRBG.
    drbgGenerate @27 (handle :DrbgHandle, length :UInt32) -> (bytes :T.DataHandle);

    # ─── HPKE (Hybrid Public Key Encryption) ──────────────────────

    # Seal (encrypt) using hybrid public key encryption.
    hpkeSeal @28 (request :HpkeSealRequest) -> (result :HpkeSealResult);

    # Open (decrypt) using hybrid public key encryption.
    hpkeOpen @29 (request :HpkeOpenRequest) -> (result :HpkeOpenResult);
}

# ─── Algorithm identification ────────────────────────────────────────
# ONE open spelling for every algorithm field in this file. A caller
# names an algorithm with a token; `parameters` carries the knobs that
# are not part of the identity (key size, mode, cost).
#
# This single struct replaces the previous `AlgorithmSpec` union of eight
# families plus `PostQuantumSpec`: a union of families is a closed
# taxonomy of what cryptography can be, and the post-quantum arm had to
# be ADDED to it, which is the amendment loop made visible.

struct AlgorithmSpec {
    # Open token; see CONFORMANCE TOKENS. Unrecognized tokens are
    # reported by getSupportedAlgorithms rather than rejected here.
    algorithm @0 :Text;
    # Algorithm-specific parameters (keyBits, mode, memoryKib, ...).
    parameters @1 :T.StringMap;
    # Backend-specific extras.
    custom @2 :Data;
}

struct SupportedAlgorithms {
    hashes @0 :List(Text);
    kdfs @1 :List(Text);
    aeads @2 :List(Text);
    asymmetric @3 :List(Text);
    signatures @4 :List(Text);
    wraps @5 :List(Text);
    # Hardware acceleration hints.
    hwAcceleration @6 :List(HwAcceleration);
    # Exportable key encodings (open tokens: "der", "pem", "jwk", ...).
    keyFormats @7 :List(Text);
    # DRBG mechanisms (open tokens).
    drbgMechanisms @8 :List(Text);
}

struct HwAcceleration {
    algorithm @0 :AlgorithmSpec;
    # Which accelerator the backend is using, as the backend describes it.
    # Deliberately not a vendor enum: naming AES-NI, QAT or a GPU here
    # would freeze today's accelerator market into the contract.
    provider @1 :Text;
    description @2 :Text;
}

# ─── Streaming AEAD ──────────────────────────────────────────────────

struct EncryptStreamRequest {
    algorithm @0 :Text;
    key @1 :T.DataHandle;
    nonce @2 :T.DataHandle;
    associatedData @3 :T.DataHandle;
}

interface EncryptStream {
    # Handle on both directions: the previous inline `Data` chunk forced
    # the caller to buffer, on an API that exists to avoid buffering.
    update @0 (data :T.DataHandle) -> T.VoidResult;

    # Finalize and get ciphertext + tag.
    finalize @1 () -> (ciphertext :T.DataHandle, tag :Data);

    # Reset stream for reuse.
    reset @2 () -> T.VoidResult;
}

struct DecryptStreamRequest {
    algorithm @0 :Text;
    key @1 :T.DataHandle;
    nonce @2 :T.DataHandle;
    associatedData @3 :T.DataHandle;
}

interface DecryptStream {
    update @0 (data :T.DataHandle) -> T.VoidResult;
    finalize @1 () -> (plaintext :T.DataHandle);
    reset @2 () -> T.VoidResult;
}

# ─── DRBG ────────────────────────────────────────────────────────────

struct CreateDrbgRequest {
    # DRBG mechanism, open token.
    mechanism @0 :Text;
    # Entropy input (seed).
    entropy @1 :T.DataHandle;
    # Personalization string (optional).
    personalization @2 :Data;
    # Maximum number of bytes before reseeding required.
    reseedInterval @3 :UInt64;
    # Declared behaviour, so backends do not invent it: a DRBG used past
    # `reseedInterval` bytes MUST either refuse further generation with
    # T.Error(unavailable) or reseed transparently and report it in
    # `custom`. The two choices are not equivalent, so a backend declares
    # which it implements rather than leaving it per-implementation.
    custom @4 :T.StringMap;
}

struct DrbgHandle {
    # Opaque DRBG instance handle.
    id @0 :UInt64;
}

# ─── HPKE ────────────────────────────────────────────────────────────

struct HpkeSealRequest {
    # KEM algorithm for key encapsulation (open token).
    kem @0 :Text;
    # KDF algorithm for key derivation (open token).
    kdf @1 :Text;
    # AEAD algorithm for symmetric encryption (open token).
    aead @2 :Text;
    # Recipient's public key.
    recipientPublicKey @3 :T.DataHandle;
    # Plaintext to encrypt.
    plaintext @4 :T.DataHandle;
    # Additional authenticated data.
    aad @5 :T.DataHandle;
    # Application-specific context.
    info @6 :Data;
}

struct HpkeSealResult {
    # Encapsulated key (ciphertext of the shared secret). Bounded by the
    # KEM construction, so it stays inline.
    encapsulatedKey @0 :Data;
    # Encrypted plaintext.
    ciphertext @1 :T.DataHandle;
    # Additional authenticated data (echoed for the caller's convenience).
    aad @2 :Data;
}

struct HpkeOpenRequest {
    kem @0 :Text;
    kdf @1 :Text;
    aead @2 :Text;
    recipientPrivateKey @3 :T.DataHandle;
    encapsulatedKey @4 :T.DataHandle;
    ciphertext @5 :T.DataHandle;
    aad @6 :T.DataHandle;
    info @7 :Data;
}

struct HpkeOpenResult {
    union {
        success @0 :HpkeOpenSuccess;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct HpkeOpenSuccess {
    plaintext @0 :T.DataHandle;
    metadata @1 :T.StringMap;
}

# ─── Hashing ────────────────────────────────────────────────────────

struct HashRequest {
    # Open token; see CONFORMANCE TOKENS.
    algorithm @0 :Text;
    data @1 :T.DataHandle;
    # For XOFs (SHAKE, BLAKE3): output length in bytes.
    outputLength @2 :UInt32;
    # Backend-specific options.
    custom @3 :T.StringMap;
}

struct HashResult {
    algorithm @0 :Text;
    # Bounded by the digest construction (32-64 bytes for today's hashes),
    # so a handle would add a copy rather than remove one.
    hash @1 :Data;
}

# Note on T.HashOutput (types.capnp:1179): it was promoted with a
# cross-schema note naming this file, but it encodes `algorithm` as a
# UInt16 ORDINAL of the local enums this rewrite deletes. Adopting it
# would re-freeze algorithm identity into an ordinal and undo the rule
# above, so this file reports the open token instead. See report.md.

struct HashStreamRequest {
    algorithm @0 :Text;
    outputLength @1 :UInt32;
}

interface HashStream {
    update @0 (data :T.DataHandle) -> T.VoidResult;
    finalize @1 () -> (hash :T.DataHandle);
    reset @2 () -> T.VoidResult;
}

# ─── HMAC ────────────────────────────────────────────────────────────

struct HmacRequest {
    # Underlying hash, as an open token.
    algorithm @0 :Text;
    key @1 :T.DataHandle;
    data @2 :T.DataHandle;
}

struct HmacResult {
    algorithm @0 :Text;
    mac @1 :Data;
}

struct HmacStreamRequest {
    algorithm @0 :Text;
    key @1 :T.DataHandle;
}

interface HmacStream {
    update @0 (data :T.DataHandle) -> T.VoidResult;
    finalize @1 () -> (mac :T.DataHandle);
    reset @2 () -> T.VoidResult;
}

# ─── Key Derivation ──────────────────────────────────────────────────

struct DeriveKeyRequest {
    # Open token; see CONFORMANCE TOKENS.
    algorithm @0 :Text;
    password @1 :T.DataHandle;
    salt @2 :T.DataHandle;
    # Output key length in bytes.
    keyLength @3 :UInt32;

    # Algorithm-specific parameters. A field that does not apply to the
    # requested algorithm is left at zero; the open token names which
    # ones matter, so a new KDF needs no new field and no new ordinal.
    iterations @4 :UInt32;
    memoryKib @5 :UInt32;
    parallelism @6 :UInt32;
    version @7 :UInt32;
    scryptN @8 :UInt32;
    scryptR @9 :UInt32;
    scryptP @10 :UInt32;
    bcryptCost @11 :UInt8;
    # HKDF/X9.63: info/context
    info @12 :Data;

    # Custom parameters (backend-specific), including any knob the named
    # fields above do not carry.
    custom @13 :T.StringMap;
}

struct DeriveKeyFromKeyRequest {
    algorithm @0 :Text;
    inputKey @1 :T.DataHandle;   # Input key material (IKM)
    salt @2 :T.DataHandle;
    keyLength @3 :UInt32;
    info @4 :Data;
    # For SSKDF (NIST SP 800-56C): additional fixed info.
    fixedInfo @5 :Data;
    custom @6 :T.StringMap;
}

struct DeriveKeyResult {
    algorithm @0 :Text;
    key @1 :T.DataHandle;
    # The parameters actually used, echoed back so a verifier can
    # reproduce the derivation. Replaces the previous `KdfParameters`
    # union of seven per-family structs plus a closed family taxonomy:
    # a new KDF needed a new ordinal there and nowhere else.
    parameters @2 :T.StringMap;
    custom @3 :T.StringMap;
}

# ─── Symmetric Encryption (AEAD) ─────────────────────────────────────

struct EncryptRequest {
    algorithm @0 :Text;
    key @1 :T.DataHandle;
    # MUST be unique per key. A backend that receives a reused nonce
    # refuses it with T.Error(alreadyExists) rather than producing the
    # eventual AEAD failure with no cause; this is stated in the contract
    # so the refusal is typed and not a comment.
    nonce @2 :T.DataHandle;
    plaintext @3 :T.DataHandle;
    associatedData @4 :T.DataHandle;
}

struct EncryptResult {
    algorithm @0 :Text;
    ciphertext @1 :T.DataHandle;
    # Bounded by the AEAD construction; inline.
    tag @2 :Data;
    # Nonce used (if the backend generated it). Inline for the same reason.
    nonce @3 :Data;
}

struct DecryptRequest {
    algorithm @0 :Text;
    key @1 :T.DataHandle;
    nonce @2 :T.DataHandle;
    ciphertext @3 :T.DataHandle;
    tag @4 :T.DataHandle;         # Separate tag (if not appended)
    associatedData @5 :T.DataHandle;
}

struct DecryptResult {
    algorithm @0 :Text;
    plaintext @1 :T.DataHandle;
    metadata @2 :T.StringMap;
}

# ─── Asymmetric Operations ──────────────────────────────────────────

struct GenerateKeyPairRequest {
    # Open token; see CONFORMANCE TOKENS.
    algorithm @0 :Text;
    # Where the generated key is registered, as the promoted foundation
    # type (types.capnp:1041 names this field explicitly). Previously a
    # free-form Text id, i.e. a second key-identity namespace beside
    # key_management's.
    keyId @1 :T.KeyId;
    # Export public key in the request.
    includePublic @2 :Bool;
    # Algorithm-specific generation options (key size, curve, ...).
    parameters @3 :T.StringMap;
    custom @4 :T.StringMap;
}

struct GenerateKeyPairResult {
    algorithm @0 :Text;
    publicKey @1 :T.DataHandle;
    # Only present when the backend can export private key material.
    privateKey @2 :T.DataHandle;
    keyId @3 :T.KeyId;
    # `privateKeyExported` makes the "if" visible on the wire: a caller
    # can now tell "export unsupported" from "export produced nothing"
    # without out-of-band knowledge of the backend.
    privateKeyExported @4 :Bool;
    # Self-describing fingerprint, so a verifier does not have to guess
    # the fingerprint algorithm from the byte length.
    fingerprint @5 :T.KeyFingerprint;
    metadata @6 :T.StringMap;
}

struct SignRequest {
    # Open token; see CONFORMANCE TOKENS.
    algorithm @0 :Text;
    privateKey @1 :T.DataHandle;
    data @2 :T.DataHandle;
    # For pre-hashed algorithms (Ed25519ph, RSA-PSS with external hash).
    prehashed @3 :Bool;
    # The hash that produced the pre-hashed input, as an open token.
    hashAlgorithm @4 :Text;
    # Deterministic ECDSA (RFC 6979)
    deterministic @5 :Bool = false;
    custom @6 :T.StringMap;
}

struct SignResult {
    algorithm @0 :Text;
    # Bounded by the signature scheme; inline.
    signature @1 :Data;
    # Self-describing fingerprint of the signing key.
    keyId @2 :T.KeyFingerprint;
}

# One canonical verification outcome for the whole tree: signature.capnp
# imports this type rather than declaring a second `VerifyResult` with the
# same name and a different shape.
struct SignatureVerifyResult {
    union {
        valid @0 :ValidSignature;
        invalid @1 :SignatureVerifyError;
        unknown @2 :T.UnknownEvent;
    }
}

# The verification REQUEST, named to avoid the collision the previous
# `VerifyRequest` had with capability.capnp's `VerifyRequest`
# (capability verification vs signature verification — two unrelated
# domains, one name, an import hazard).
struct SignatureVerifyRequest {
    # Open token; see CONFORMANCE TOKENS.
    algorithm @0 :Text;
    publicKey @1 :T.DataHandle;
    data @2 :T.DataHandle;
    signature @3 :T.DataHandle;
    prehashed @4 :Bool;
    hashAlgorithm @5 :Text;
    # Domain/context binding the signature must carry (open token).
    domain @6 :Text;
    custom @7 :T.StringMap;
}

struct ValidSignature {
    algorithm @0 :Text;
    signer @1 :T.KeyFingerprint;
    # When the signature was made / expires, as reported by the backend.
    signedAt @2 :T.Timestamp;
    custom @3 :Data;
}

struct SignatureVerifyError {
    algorithm @0 :Text;
    # Open token naming the failure class; see CONFORMANCE TOKENS. This
    # replaces a closed error enum for the same reason algorithms are
    # open, and it carries the underlying T.Error so a caller never has
    # to pattern-match text to learn why verification could not be
    # attempted (unknown algorithm, malformed input, hardware failure).
    kind @1 :Text;
    error @2 :T.Error;
    custom @3 :T.StringMap;
}

struct KeyAgreementRequest {
    algorithm @0 :Text;
    privateKey @1 :T.DataHandle;
    peerPublicKey @2 :T.DataHandle;
}

struct KeyAgreementResult {
    algorithm @0 :Text;
    sharedSecret @1 :T.DataHandle;
    custom @2 :T.StringMap;
}

# ─── Key Wrapping ────────────────────────────────────────────────────

struct WrapKeyRequest {
    algorithm @0 :Text;
    wrappingKey @1 :T.DataHandle;
    keyToWrap @2 :T.DataHandle;
    associatedData @3 :Data;  # For KWP
    custom @4 :T.StringMap;
}

struct WrapKeyResult {
    algorithm @0 :Text;
    wrappedKey @1 :T.DataHandle;
    metadata @2 :T.StringMap;
}

struct UnwrapKeyRequest {
    algorithm @0 :Text;
    wrappingKey @1 :T.DataHandle;
    wrappedKey @2 :T.DataHandle;
    associatedData @3 :Data;
    expectedKeyLength @4 :UInt32;
    custom @5 :T.StringMap;
}

struct UnwrapKeyResult {
    algorithm @0 :Text;
    key @1 :T.DataHandle;
    metadata @2 :T.StringMap;
}

# ─── Key Import/Export ───────────────────────────────────────────────

struct ImportKeyRequest {
    # Key data to import.
    data @0 :T.DataHandle;
    # Encoding of the input data, open token ("der", "pem", "jwk", ...).
    format @1 :Text;
    # Password for encrypted private keys.
    password @2 :Data;
    # Intended use (a small closed set: the operations asymmetric
    # cryptography itself defines).
    intendedUse @3 :KeyUse;
    # Validate key against intendedUse (may fail if mismatch).
    validateUse @4 :Bool = true;
    # Detected algorithm, reported by the backend as an open token.
    algorithm @5 :Text;
    custom @6 :T.StringMap;
}

# The four things a key can be for. Closed because public-key
# cryptography closes it: a key signs, encrypts, agrees, or wraps. A new
# use would be a new mathematical operation, not a marketing category.
enum KeyUse {
    # Sentinel: an unset intended use means "undeclared", never
    # "signature" — a backend asked to validate a key against an
    # absent purpose must not assume one.
    unspecified @0;
    signature @1;       # Signing/verification
    encryption @2;      # Encryption/decryption
    keyAgreement @3;    # Key agreement
    keyWrapping @4;     # Key wrapping/unwrapping
    any @5;
}

struct ImportKeyResult {
    union {
        success @0 :ImportKeySuccess;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct ImportKeySuccess {
    # Detected algorithm, open token.
    algorithm @0 :Text;
    publicKey @1 :T.DataHandle;
    privateKey @2 :T.DataHandle;
    fingerprint @3 :T.KeyFingerprint;
    use @4 :KeyUse;
    metadata @5 :T.StringMap;
}

struct ExportKeyRequest {
    data @0 :T.DataHandle;
    format @1 :Text;
    password @2 :Data;
    custom @3 :T.StringMap;
}

struct ExportKeyResult {
    union {
        success @0 :ExportKeySuccess;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct ExportKeySuccess {
    data @0 :T.DataHandle;
    format @1 :Text;
    metadata @2 :T.StringMap;
}

# ─── Certificate Operations ──────────────────────────────────────────
# ONE certificate representation for the tree: signature.capnp imports
# this struct, so a chain verified here can be attached to a Signature
# there without a conversion step no schema defined.

struct CertificateInfo {
    subject @0 :Text;
    issuer @1 :Text;
    serialNumber @2 :Data;
    notBefore @3 :T.Timestamp;
    notAfter @4 :T.Timestamp;
    # Open token naming the subject public key algorithm.
    subjectPublicKeyAlgorithm @5 :Text;
    subjectPublicKey @6 :T.DataHandle;
    extensions @7 :List(CertificateExtension);
    # The full certificate, as a handle: PEM of a chain is bulk and was
    # being copied inline.
    der @8 :T.DataHandle;
    pem @9 :Text;
    sha256Fingerprint @10 :Data;
    sha1Fingerprint @11 :Data;
}

struct CertificateExtension {
    oid @0 :Text;
    critical @1 :Bool;
    value @2 :Data;
}

# Typed chain failure. Replaces `errors @1 :List(Text)`, which forced
# every consumer to pattern-match free-form strings to learn why a chain
# failed — while carrying no position and no underlying cause.
struct VerifyChainResult {
    valid @0 :Bool;
    errors @1 :List(ChainError);
    leafCertificate @2 :CertificateInfo;
    chain @3 :List(CertificateInfo);
}

struct ChainError {
    # Open token naming the failure class; see CONFORMANCE TOKENS.
    kind @0 :Text;
    # Position in the chain that failed (0 = leaf).
    index @1 :UInt32;
    # The underlying cause, so a consumer never string-parses to learn it.
    error @2 :T.Error;
    custom @3 :T.StringMap;
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Nothing above depends on any declaration in this section. They are
# published so today's tools have a discoverable spelling, and so two
# backends have a shared name for an algorithm without the protocol
# requiring one. An unrecognized token MUST be ignored, never rejected:
# that is what lets a new construction be requested with no schema
# change. This section can grow without touching a single ordinal.
#
# They are Text values, deliberately NOT enums: an enum here would be an
# eternal commitment to today's spelling of a concept.
# ══════════════════════════════════════════════════════════════════════

# Digests
const hashSha256   :Text = "sha256";
const hashSha384   :Text = "sha384";
const hashSha512   :Text = "sha512";
const hashSha3256 :Text = "sha3-256";
const hashSha3512 :Text = "sha3-512";
const hashBlake2b  :Text = "blake2b";
const hashBlake3   :Text = "blake3";

# KDFs
const kdfPbkdf2    :Text = "pbkdf2";
const kdfArgon2id  :Text = "argon2id";
const kdfScrypt    :Text = "scrypt";
const kdfHkdf      :Text = "hkdf";
const kdfKbkdf     :Text = "kbkdf";

# AEADs
const aeadAes256Gcm       :Text = "aes-256-gcm";
const aeadAes128Gcm       :Text = "aes-128-gcm";
const aeadChaCha20Poly1305 :Text = "chacha20-poly1305";
const aeadXChaCha20Poly1305 :Text = "xchacha20-poly1305";
const aeadAes256Siv       :Text = "aes-256-siv";

# Asymmetric / signature schemes
const asymEd25519      :Text = "ed25519";
const asymEcdsaP256    :Text = "ecdsa-p256";
const asymEcdsaP384    :Text = "ecdsa-p384";
const asymRsa2048      :Text = "rsa-2048";
const asymRsaPssSha256 :Text = "rsa-pss-sha256";
const asymX25519       :Text = "x25519";
const asymMlKem768     :Text = "ml-kem-768";
const asymMlDsa65      :Text = "ml-dsa-65";
const asymSlhDsaSha2128s :Text = "slh-dsa-sha2-128s";

# Key wrapping
const wrapAes256Kw :Text = "aes-256-kw";
const wrapAes256Kwp :Text = "aes-256-kwp";

# Key encodings
const fmtDer   :Text = "der";
const fmtPem   :Text = "pem";
const fmtPkcs8 :Text = "pkcs8";
const fmtSpki  :Text = "spki";
const fmtJwk   :Text = "jwk";

# DRBG mechanisms
const drbgHmacDrbg :Text = "hmac-drbg";
const drbgCtrDrbg  :Text = "ctr-drbg";

# Verification failure classes
const verifyBadSignature   :Text = "bad-signature";
const verifyUntrusted      :Text = "untrusted";
const verifyExpired        :Text = "expired";
const verifyUnknownAlgorithm :Text = "unknown-algorithm";
const verifyMalformed      :Text = "malformed";
const verifyWrongDomain    :Text = "wrong-domain";
const verifyRevoked        :Text = "revoked";

# Chain failure classes
const chainExpired       :Text = "expired";
const chainNotYetValid   :Text = "not-yet-valid";
const chainUntrustedRoot :Text = "untrusted-root";
const chainIncomplete    :Text = "incomplete";
const chainBadSignature  :Text = "bad-signature";

@0xa1b2c3d4e5f60104;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Crypto — general-purpose cryptographic operations.
#
# Zero backend assumptions: no OpenSSL, no libsodium, no CryptoAPI,
# no WebCrypto, no BoringSSL, no TPM assumptions. Backend provides
# cryptographic primitives; protocol defines the contract.
#
# Deduplicates crypto bits from auth.capnp, biometric.capnp,
# backup.capnp, signature.capnp, key_management.capnp.
#
# Used by: auth.capnp (password hashing), backup.capnp (checksum),
# signature.capnp (hash algorithms), key_management.capnp (key ops)
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

    # Generate cryptographically secure random bytes.
    randomBytes @6 (length :UInt32) -> (bytes :Data);

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
    verify @12 (request :VerifyRequest) -> (result :VerifyResult);

    # Key agreement (ECDH, X25519, etc.).
    keyAgreement @13 (request :KeyAgreementRequest) -> (result :KeyAgreementResult);

    # ─── Key Wrapping/Unwrapping ──────────────────────────────────

    # Wrap (encrypt) a key with another key.
    wrapKey @14 (request :WrapKeyRequest) -> (result :WrapKeyResult);

    # Unwrap (decrypt) a key with another key.
    unwrapKey @15 (request :UnwrapKeyRequest) -> (result :UnwrapKeyResult);

    # ─── Key Import/Export ────────────────────────────────────────

    # Import a key from a standard format (PKCS#8, SPKI, JWK, PEM).
    importKey @22 (request :ImportKeyRequest) -> (result :ImportKeyResult);

    # Export a key to a standard format.
    exportKey @23 (request :ExportKeyRequest) -> (result :ExportKeyResult);

    # ─── Certificate Operations ────────────────────────────────────

    # Parse X.509 certificate.
    parseCertificate @16 (der :Data) -> (cert :CertificateInfo);

    # Verify certificate chain.
    verifyCertificateChain @17 (chain :List(Data), trustAnchors :List(Data)) -> (result :VerifyChainResult);

    # ─── Constant-Time Operations ──────────────────────────────────

    # Constant-time memory comparison.
    constantTimeCompare @18 (a :Data, b :Data) -> (equal :Bool);

    # Constant-time memory copy (for secret data).
    constantTimeCopy @19 (dst :T.BufferId, src :Data, offset :UInt64) -> T.VoidResult;

    # ─── Capability Query ──────────────────────────────────────────

    # Get supported algorithms.
    getSupportedAlgorithms @20 () -> (algorithms :SupportedAlgorithms);

    # Check if algorithm/hardware acceleration is available.
    isAlgorithmSupported @21 (algorithm :AlgorithmSpec) -> (supported :Bool, hardwareAccelerated :Bool);

    # ─── Streaming AEAD (Audit-7) ──────────────────────────────────

    # Streaming encrypt for large data (chunked AEAD).
    encryptStream @24 (request :EncryptStreamRequest) -> (stream :EncryptStream);

    # Streaming decrypt for large data (chunked AEAD).
    decryptStream @25 (request :DecryptStreamRequest) -> (stream :DecryptStream);

    # ─── DRBG (Audit-7: Deterministic Random Bit Generator) ───────

    # Create a DRBG instance for deterministic randomness.
    createDrbg @26 (request :CreateDrbgRequest) -> (handle :DrbgHandle);

    # Generate random bytes from a DRBG.
    drbgGenerate @27 (handle :DrbgHandle, length :UInt32) -> (bytes :Data);

    # ─── HPKE (Audit-7: Hybrid Public Key Encryption) ────────────

    # Seal (encrypt) using hybrid public key encryption.
    hpkeSeal @28 (request :HpkeSealRequest) -> (result :HpkeSealResult);

    # Open (decrypt) using hybrid public key encryption.
    hpkeOpen @29 (request :HpkeOpenRequest) -> (result :HpkeOpenResult);
}

# ─── Streaming AEAD ──────────────────────────────────────────────────

struct EncryptStreamRequest {
    algorithm @0 :AeadAlgorithm;
    key @1 :T.DataHandle;
    nonce @2 :T.DataHandle;
    associatedData @3 :T.DataHandle;
}

interface EncryptStream {
    # Feed plaintext chunk.
    update @0 (data :Data) -> T.VoidResult;

    # Finalize and get ciphertext + tag.
    finalize @1 () -> (ciphertext :Data, tag :Data);

    # Reset stream for reuse.
    reset @2 () -> T.VoidResult;
}

struct DecryptStreamRequest {
    algorithm @0 :AeadAlgorithm;
    key @1 :T.DataHandle;
    nonce @2 :T.DataHandle;
    associatedData @3 :T.DataHandle;
}

interface DecryptStream {
    # Feed ciphertext chunk.
    update @0 (data :Data) -> T.VoidResult;

    # Finalize and get plaintext.
    finalize @1 () -> (plaintext :Data);

    # Reset stream for reuse.
    reset @2 () -> T.VoidResult;
}

# ─── DRBG (Deterministic Random Bit Generator) ───────────────────────

struct CreateDrbgRequest {
    # DRBG mechanism.
    mechanism @0 :DrbgMechanism;
    # Entropy input (seed).
    entropy @1 :T.DataHandle;
    # Personalization string (optional).
    personalization @2 :Data;
    # Maximum number of bytes before reseeding required.
    reseedInterval @3 :UInt64;
}

enum DrbgMechanism {
    hmacDrbg @0;     # HMAC-DRBG (NIST SP 800-90A)
    hashDrbg @1;     # Hash-DRBG (NIST SP 800-90A)
    ctrDrbg @2;      # CTR-DRBG (NIST SP 800-90A)
    custom @3;
}

struct DrbgHandle {
    # Opaque DRBG instance handle.
    id @0 :UInt64;
}

# ─── HPKE (Hybrid Public Key Encryption, RFC 9180) ──────────────────

struct HpkeSealRequest {
    # KEM algorithm for key encapsulation.
    kem @0 :AsymmetricAlgorithm;
    # KDF algorithm for key derivation.
    kdf @1 :KdfAlgorithm;
    # AEAD algorithm for symmetric encryption.
    aead @2 :AeadAlgorithm;
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
    # Encapsulated key (ciphertext of the shared secret).
    encapsulatedKey @0 :Data;
    # Encrypted plaintext.
    ciphertext @1 :Data;
    # Additional authenticated data (may be empty).
    aad @2 :Data;
}

struct HpkeOpenRequest {
    # KEM algorithm.
    kem @0 :AsymmetricAlgorithm;
    # KDF algorithm.
    kdf @1 :KdfAlgorithm;
    # AEAD algorithm.
    aead @2 :AeadAlgorithm;
    # Recipient's private key.
    recipientPrivateKey @3 :T.DataHandle;
    # Encapsulated key from seal.
    encapsulatedKey @4 :T.DataHandle;
    # Ciphertext to decrypt.
    ciphertext @5 :T.DataHandle;
    # Additional authenticated data.
    aad @6 :T.DataHandle;
    # Application-specific context.
    info @7 :Data;
}

struct HpkeOpenResult {
    union {
        success @0 :HpkeOpenSuccess;
        error @1 :T.Error;
    }
}

struct HpkeOpenSuccess {
    # Decrypted plaintext.
    plaintext @0 :Data;
}

# ─── Hashing ────────────────────────────────────────────────────────

enum HashAlgorithm {
    # SHA-2 family
    sha224 @0;
    sha256 @1;
    sha384 @2;
    sha512 @3;
    sha512224 @4;   # was: sha512_224
    sha512256 @5;   # was: sha512_256

    # SHA-3 family
    sha3224 @6;     # was: sha3_224
    sha3256 @7;     # was: sha3_256
    sha3384 @8;     # was: sha3_384
    sha3512 @9;     # was: sha3_512
    shake128 @10;
    shake256 @11;

    # BLAKE2
    blake2b @12;
    blake2s @13;
    blake2bp @14;  # parallel
    blake2sp @15;  # parallel

    # BLAKE3
    blake3 @16;

    # Legacy (for compatibility only)
    md5 @17;
    sha1 @18;
    ripemd160 @19;

    # Custom/backend-specific
    custom @20;
}

struct HashRequest {
    algorithm @0 :HashAlgorithm;
    data @1 :T.DataHandle;  # Inline or buffer reference
    # For SHAKE: output length in bytes.
    outputLength @2 :UInt32;
}

struct HashResult {
    algorithm @0 :HashAlgorithm;
    hash @1 :Data;
}

struct HashStreamRequest {
    algorithm @0 :HashAlgorithm;
    # For SHAKE: output length in bytes.
    outputLength @1 :UInt32;
}

interface HashStream {
    # Feed data into the hash.
    update @0 (data :Data) -> T.VoidResult;

    # Finalize and get hash.
    finalize @1 () -> (hash :Data);

    # Reset stream for reuse.
    reset @2 () -> T.VoidResult;
}

# ─── HMAC ────────────────────────────────────────────────────────────

struct HmacRequest {
    algorithm @0 :HashAlgorithm;  # Underlying hash for HMAC
    key @1 :T.DataHandle;         # HMAC key
    data @2 :T.DataHandle;        # Data to authenticate
}

struct HmacResult {
    algorithm @0 :HashAlgorithm;
    mac @1 :Data;
}

struct HmacStreamRequest {
    algorithm @0 :HashAlgorithm;
    key @1 :T.DataHandle;
}

interface HmacStream {
    update @0 (data :Data) -> T.VoidResult;
    finalize @1 () -> (mac :Data);
    reset @2 () -> T.VoidResult;
}

# ─── Key Derivation ──────────────────────────────────────────────────

enum KdfAlgorithm {
    # Password-based KDFs
    pbkdf2HmacSha256 @0;   # was: pbkdf2_hmac_sha256
    pbkdf2HmacSha512 @1;   # was: pbkdf2_hmac_sha512
    argon2id @2;
    argon2i @3;
    argon2d @4;
    scrypt @5;
    bcrypt @6;  # For password hashing only

    # Key-based KDFs
    hkdfSha256 @7;      # was: hkdf_sha256
    hkdfSha384 @8;      # was: hkdf_sha384
    hkdfSha512 @9;      # was: hkdf_sha512
    hkdfBlake2b @10;    # was: hkdf_blake2b
    hkdfBlake3 @11;     # was: hkdf_blake3

    # KBKDF (NIST SP 800-108)
    kbkdfHmacSha256 @12;  # was: kbkdf_hmac_sha256
    kbkdfHmacSha384 @13;  # was: kbkdf_hmac_sha384
    kbkdfHmacSha512 @14;  # was: kbkdf_hmac_sha512
    kbkdfAesCmac @15;     # was: kbkdf_aes_cmac

    # X9.63 KDF
    x963Sha256 @16;     # was: x963_sha256
    x963Sha384 @17;     # was: x963_sha384
    x963Sha512 @18;     # was: x963_sha512

    # Custom
    custom @19;
}

struct DeriveKeyRequest {
    algorithm @0 :KdfAlgorithm;
    password @1 :T.DataHandle;    # Password/passphrase
    salt @2 :T.DataHandle;        # Salt (random, per-derivation)
    # Output key length in bytes.
    keyLength @3 :UInt32;

    # Algorithm-specific parameters:
    # PBKDF2: iterations
    iterations @4 :UInt32;

    # Argon2: memory (KB), parallelism, version
    memoryKib @5 :UInt32;
    parallelism @6 :UInt32;
    version @7 :UInt32;

    # Scrypt: N, r, p
    scryptN @8 :UInt32;
    scryptR @9 :UInt32;
    scryptP @10 :UInt32;

    # Bcrypt: cost (log2 rounds)
    bcryptCost @11 :UInt8;

    # HKDF/X9.63: info/context
    info @12 :Data;

    # Custom parameters (backend-specific)
    custom @13 :T.StringMap;
}

struct DeriveKeyFromKeyRequest {
  algorithm @0 :KdfAlgorithm;
  inputKey @1 :T.DataHandle; # Input key material (IKM)
  salt @2 :T.DataHandle; # Salt (optional for some KDFs)
  keyLength @3 :UInt32;
  info @4 :Data; # Context/application info
  # For SSKDF (NIST SP 800-56C): additional fixed info.
  fixedInfo @5 :Data;
  custom @6 :T.StringMap;
}

struct DeriveKeyResult {
    algorithm @0 :KdfAlgorithm;
    key @1 :Data;
    # Parameters used (for storage/verification).
    parameters @2 :KdfParameters;
}

struct KdfParameters {
    union {
        pbkdf2 @0 :Pbkdf2Params;
        argon2 @1 :Argon2Params;
        scrypt @2 :ScryptParams;
        bcrypt @3 :BcryptParams;
        hkdf @4 :HkdfParams;
        kbkdf @5 :KbkdfParams;
        x963 @6 :X963Params;
        custom @7 :T.StringMap;
    }
}

struct Pbkdf2Params {
    algorithm @0 :HashAlgorithm;
    iterations @1 :UInt32;
    salt @2 :Data;
    keyLength @3 :UInt32;
}

struct Argon2Params {
    algorithm @0 :KdfAlgorithm;  # argon2id, argon2i, argon2d
    memoryKib @1 :UInt32;
    parallelism @2 :UInt32;
    iterations @3 :UInt32;
    version @4 :UInt32;
    salt @5 :Data;
    keyLength @6 :UInt32;
}

struct ScryptParams {
    n @0 :UInt32;
    r @1 :UInt32;
    p @2 :UInt32;
    salt @3 :Data;
    keyLength @4 :UInt32;
}

struct BcryptParams {
    cost @0 :UInt8;
    salt @1 :Data;
}

struct HkdfParams {
    algorithm @0 :HashAlgorithm;
    salt @1 :Data;
    info @2 :Data;
    keyLength @3 :UInt32;
}

struct KbkdfParams {
    algorithm @0 :HashAlgorithm;
    label @1 :Data;
    context @2 :Data;
    keyLength @3 :UInt32;
}

struct X963Params {
    algorithm @0 :HashAlgorithm;
    sharedInfo @1 :Data;
    keyLength @2 :UInt32;
}

# ─── Secure Random ───────────────────────────────────────────────────

struct RandomRequest {
    length @0 :UInt32;
    # If true, use buffer reference for large requests.
    useBuffer @1 :Bool;
    bufferId @2 :T.BufferId;
    offset @3 :UInt64;
}

# ─── Symmetric Encryption (AEAD) ─────────────────────────────────────

enum AeadAlgorithm {
    aes256Gcm @0;       # was: aes256_gcm
    aes128Gcm @1;       # was: aes128_gcm
    chacha20Poly1305 @2;    # was: chacha20_poly1305
    xchacha20Poly1305 @3;   # was: xchacha20_poly1305
    aes256Ccm @4;       # was: aes256_ccm
    aes128Ccm @5;       # was: aes128_ccm
    aes256GcmSiv @6;    # was: aes256_gcm_siv
    aes128GcmSiv @7;    # was: aes128_gcm_siv
    # AES-SIV (RFC 5297) — misuse-resistant AEAD
    aes256Siv @8;       # was: aes256_siv
    aes128Siv @9;       # was: aes128_siv
    # Post-quantum hybrid AEAD (NIST ML-KEM + AES-GCM)
    pqcHybrid @10;      # was: pqc_hybrid
    custom @11;
}

struct EncryptRequest {
    algorithm @0 :AeadAlgorithm;
    key @1 :T.DataHandle;
    nonce @2 :T.DataHandle;       # Must be unique per key!
    plaintext @3 :T.DataHandle;
    associatedData @4 :T.DataHandle;  # AAD (optional)
}

struct EncryptResult {
    algorithm @0 :AeadAlgorithm;
    ciphertext @1 :Data;
    tag @2 :Data;                 # Authentication tag (appended to ciphertext in some APIs)
    nonce @3 :Data;               # Nonce used (if generated)
}

struct DecryptRequest {
    algorithm @0 :AeadAlgorithm;
    key @1 :T.DataHandle;
    nonce @2 :T.DataHandle;
    ciphertext @3 :T.DataHandle;
    tag @4 :T.DataHandle;         # Separate tag (if not appended)
    associatedData @5 :T.DataHandle;  # AAD (optional)
}

struct DecryptResult {
    algorithm @0 :AeadAlgorithm;
    plaintext @1 :Data;
}

# ─── Asymmetric Operations ──────────────────────────────────────────

enum AsymmetricAlgorithm {
    # RSA
    rsa2048 @0;
    rsa3072 @1;
    rsa4096 @2;
    rsa8192 @3;

    # ECDSA
    ecdsaP256 @4;      # was: ecdsa_p256
    ecdsaP384 @5;      # was: ecdsa_p384
    ecdsaP521 @6;      # was: ecdsa_p521
    ecdsaSecp256k1 @7; # was: ecdsa_secp256k1

    # EdDSA
    ed25519 @8;
    ed448 @9;

    # ECDH / X25519 / X448
    ecdhP256 @10;      # was: ecdh_p256
    ecdhP384 @11;      # was: ecdh_p384
    ecdhP521 @12;      # was: ecdh_p521
    x25519 @13;
    x448 @14;

    # RSA-PSS
    rsaPssSha256 @15;  # was: rsa_pss_sha256
    rsaPssSha384 @16;  # was: rsa_pss_sha384
    rsaPssSha512 @17;  # was: rsa_pss_sha512

    # RSA-OAEP
    rsaOaepSha256 @18; # was: rsa_oaep_sha256
    rsaOaepSha384 @19; # was: rsa_oaep_sha384
    rsaOaepSha512 @20; # was: rsa_oaep_sha512

    # Post-quantum (NIST FIPS 203/204/205 — ML-KEM, ML-DSA, SLH-DSA)
    mlKem512 @21;      # was: ml_kem_512 (CRYSTALS-Kyber-512)
    mlKem768 @22;      # was: ml_kem_768 (CRYSTALS-Kyber-768)
    mlKem1024 @23;     # was: ml_kem_1024 (CRYSTALS-Kyber-1024)
    mlDsa44 @24;       # was: ml_dsa_44 (CRYSTALS-Dilithium-44)
    mlDsa65 @25;       # was: ml_dsa_65 (CRYSTALS-Dilithium-65)
    mlDsa87 @26;       # was: ml_dsa_87 (CRYSTALS-Dilithium-87)
    slhDsaSha2128s @27;    # was: slh_dsa_sha2_128s
    slhDsaSha2192s @28;    # was: slh_dsa_sha2_192s
    slhDsaSha2256s @29;    # was: slh_dsa_sha2_256s

    # Hybrid (classical + post-quantum)
    x25519MlKem768 @30;     # was: x25519_ml_kem_768
    ecdsaP256MlDsa65 @31;  # was: ecdsa_p256_ml_dsa_65

    # Custom
    custom @32;
}

enum SignatureAlgorithm {
    # RSA
    rsaPkcs1Sha256 @0;   # was: rsa_pkcs1_sha256
    rsaPkcs1Sha384 @1;   # was: rsa_pkcs1_sha384
    rsaPkcs1Sha512 @2;   # was: rsa_pkcs1_sha512
    rsaPssSha256 @3;     # was: rsa_pss_sha256
    rsaPssSha384 @4;     # was: rsa_pss_sha384
    rsaPssSha512 @5;     # was: rsa_pss_sha512

    # ECDSA
    ecdsaSha256 @6;      # was: ecdsa_sha256
    ecdsaSha384 @7;      # was: ecdsa_sha384
    ecdsaSha512 @8;      # was: ecdsa_sha512
    ecdsaSha256Der @9;   # was: ecdsa_sha256_der (DER-encoded)
    ecdsaSha384Der @10;  # was: ecdsa_sha384_der
    ecdsaSha512Der @11;  # was: ecdsa_sha512_der

    # EdDSA
    ed25519 @12;
    ed25519ph @13;  # Pre-hashed
    ed448 @14;
    ed448ph @15;

    # Custom
    custom @16;
}

struct GenerateKeyPairRequest {
    algorithm @0 :AsymmetricAlgorithm;
    # For key management integration.
    keyId @1 :Text;
    # Export public key in request.
    includePublic @2 :Bool;
}

struct GenerateKeyPairResult {
    algorithm @0 :AsymmetricAlgorithm;
    publicKey @1 :Data;
    privateKey @2 :Data;  # Only if backend supports export
    keyId @3 :Text;
}

struct SignRequest {
  algorithm @0 :SignatureAlgorithm;
  privateKey @1 :T.DataHandle;
  data @2 :T.DataHandle;
  # For pre-hashed algorithms (Ed25519ph, RSA-PSS with external hash)
  prehashed @3 :Bool;
  hashAlgorithm @4 :HashAlgorithm; # If prehashed
  # Deterministic ECDSA (RFC 6979)
  deterministic @5 :Bool = false;
}

struct SignResult {
    algorithm @0 :SignatureAlgorithm;
    signature @1 :Data;
}

struct VerifyRequest {
    algorithm @0 :SignatureAlgorithm;
    publicKey @1 :T.DataHandle;
    data @2 :T.DataHandle;
    signature @3 :T.DataHandle;
    prehashed @4 :Bool;
    hashAlgorithm @5 :HashAlgorithm;  # If prehashed
}

struct VerifyResult {
    valid @0 :Bool;
    algorithm @1 :SignatureAlgorithm;
}

struct KeyAgreementRequest {
    algorithm @0 :AsymmetricAlgorithm;
    privateKey @1 :T.DataHandle;
    peerPublicKey @2 :T.DataHandle;
}

struct KeyAgreementResult {
    algorithm @0 :AsymmetricAlgorithm;
    sharedSecret @1 :Data;
}

# ─── Key Wrapping ────────────────────────────────────────────────────

enum WrapAlgorithm {
    # AES Key Wrap (RFC 3394)
    aes256Kw @0;      # was: aes256_kw
    aes128Kw @1;      # was: aes128_kw
    aes192Kw @2;      # was: aes192_kw

    # AES Key Wrap with Padding (RFC 5649)
    aes256Kwp @3;     # was: aes256_kwp
    aes128Kwp @4;     # was: aes128_kwp
    aes192Kwp @5;     # was: aes192_kwp

    # RSA-OAEP
    rsaOaepSha256 @6; # was: rsa_oaep_sha256
    rsaOaepSha384 @7; # was: rsa_oaep_sha384
    rsaOaepSha512 @8; # was: rsa_oaep_sha512

    # Custom
    custom @9;
}

struct WrapKeyRequest {
    algorithm @0 :WrapAlgorithm;
    wrappingKey @1 :T.DataHandle;
    keyToWrap @2 :T.DataHandle;
    associatedData @3 :Data;  # For KWP
}

struct WrapKeyResult {
    algorithm @0 :WrapAlgorithm;
    wrappedKey @1 :Data;
}

struct UnwrapKeyRequest {
    algorithm @0 :WrapAlgorithm;
    wrappingKey @1 :T.DataHandle;
    wrappedKey @2 :T.DataHandle;
    associatedData @3 :Data;  # For KWP
    expectedKeyLength @4 :UInt32;  # For validation
}

struct UnwrapKeyResult {
    algorithm @0 :WrapAlgorithm;
    key @1 :Data;
}

# ─── Key Import/Export ───────────────────────────────────────────────

enum KeyFormat {
    pkcs8 @0;         # PKCS#8 (private key, DER/PEM)
    spki @1;          # SubjectPublicKeyInfo (public key, DER/PEM)
    pkcs12 @2;        # PKCS#12 / PFX (cert + key bundle)
    jwk @3;           # JSON Web Key
    pem @4;           # PEM-encoded (auto-detect key type)
    der @5;           # DER-encoded (auto-detect key type)
    openssh @6;       # OpenSSH public key format
    custom @7;
}

struct ImportKeyRequest {
  # Key data to import.
  data @0 :T.DataHandle;
  # Format of the input data.
  format @1 :KeyFormat;
  # Password for encrypted private keys (PKCS#8, PKCS#12).
  password @2 :Data;
  # Intended use (for JWK kty parameter hint).
  intendedUse @3 :KeyUse;
  # Validate key against intendedUse (may fail if mismatch).
  validateUse @4 :Bool = true;
  # Backend-specific import options.
  custom @5 :T.StringMap;
}

enum KeyUse {
    signature @0;       # Signing/verification
    encryption @1;      # Encryption/decryption
    keyAgreement @2;    # Key agreement (ECDH)
    keyWrapping @3;     # Key wrapping/unwrapping
    any @4;
}

struct ImportKeyResult {
    union {
        success @0 :ImportKeySuccess;
        error @1 :T.Error;
    }
}

struct ImportKeySuccess {
    # Detected algorithm.
    algorithm @0 :AsymmetricAlgorithm;
    # Public key (always present).
    publicKey @1 :Data;
    # Private key (only if private key was imported and backend supports export).
    privateKey @2 :Data;
    # Fingerprint of the imported key.
    fingerprint @3 :T.KeyFingerprint;
    # Key use hint.
    use @4 :KeyUse;
}

struct ExportKeyRequest {
    # Key data to export (private or public key).
    data @0 :T.DataHandle;
    # Format to export to.
    format @1 :KeyFormat;
    # Password to encrypt private key on export.
    password @2 :Data;
    # Backend-specific export options.
    custom @3 :T.StringMap;
}

struct ExportKeyResult {
    union {
        success @0 :ExportKeySuccess;
        error @1 :T.Error;
    }
}

struct ExportKeySuccess {
    # Exported key data.
    data @0 :Data;
    # Format used for export.
    format @1 :KeyFormat;
}

# ─── Certificate Operations ──────────────────────────────────────────

struct CertificateInfo {
    subject @0 :Text;
    issuer @1 :Text;
    serialNumber @2 :Data;
    notBefore @3 :T.Timestamp;
    notAfter @4 :T.Timestamp;
    subjectPublicKeyAlgorithm @5 :AsymmetricAlgorithm;
    subjectPublicKey @6 :Data;
    extensions @7 :List(CertificateExtension);
    # PEM or DER encoded full certificate.
    der @8 :Data;
    pem @9 :Text;
    # Fingerprints.
    sha256Fingerprint @10 :Data;
    sha1Fingerprint @11 :Data;
}

struct CertificateExtension {
    oid @0 :Text;
    critical @1 :Bool;
    value @2 :Data;
}

struct VerifyChainResult {
    valid @0 :Bool;
    errors @1 :List(Text);
    leafCertificate @2 :CertificateInfo;
    chain @3 :List(CertificateInfo);
}

# ─── Algorithm Support ───────────────────────────────────────────────

struct AlgorithmSpec {
    union {
        hash @0 :HashAlgorithm;
        kdf @1 :KdfAlgorithm;
        aead @2 :AeadAlgorithm;
        asymmetric @3 :AsymmetricAlgorithm;
        signature @4 :SignatureAlgorithm;
        wrap @5 :WrapAlgorithm;
        # Audit-7: post-quantum algorithm variant.
        postQuantum @6 :PostQuantumSpec;
        custom @7 :Data;
    }
}

# Audit-7: post-quantum algorithm specification for capability queries.
struct PostQuantumSpec {
    # The post-quantum algorithm family.
    algorithm @0 :PostQuantumAlgorithm;
    # Key size in bits.
    keyBits @1 :UInt32;
    # Security level (1, 3, or 5 for NIST ML-KEM/ML-DSA).
    securityLevel @2 :UInt32;
}

enum PostQuantumAlgorithm {
    mlKem @0;        # Module-Lattice Key Encapsulation (CRYSTALS-Kyber)
    mlDsa @1;        # Module-Lattice Digital Signature (CRYSTALS-Dilithium)
    slhDsa @2;       # Stateless Hash-Based Digital Signature (SPHINCS+)
    hybrid @3;       # Hybrid classical + post-quantum
    custom @4;
}

struct SupportedAlgorithms {
    hashes @0 :List(HashAlgorithm);
    kdfs @1 :List(KdfAlgorithm);
    aeads @2 :List(AeadAlgorithm);
    asymmetric @3 :List(AsymmetricAlgorithm);
    signatures @4 :List(SignatureAlgorithm);
    wraps @5 :List(WrapAlgorithm);
    # Hardware acceleration hints.
    hwAcceleration @6 :List(HwAcceleration);
}

struct HwAcceleration {
    algorithm @0 :AlgorithmSpec;
    provider @1 :Text;  # e.g., "AES-NI", "ARMv8 Crypto", "Intel QAT", "NVIDIA GPU"
    description @2 :Text;
}
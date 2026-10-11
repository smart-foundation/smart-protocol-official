@0xa1b2c3d4e5f60015;

using T = import "types.capnp";
using import "capability.capnp".Capability;
# The canonical app icon: appindex.capnp declares it (data, mimeType, width,
# height, metadata) and app.capnp consumes it. auth.capnp carried a reduced
# three-field copy, so an icon fetched for a consent screen and the same icon
# fetched for a launcher were two shapes a backend had to keep in agreement.
using AI = import "appindex.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Auth - authentication, credential management, and token lifecycle.
#
# This schema handles the full auth lifecycle: authentication (who are
# you?), credential management, and token lifecycle. Biometric hardware
# interaction lives in biometric.capnp; device lock, MFA state machine
# and credential recovery live in access.capnp, which is the canonical
# owner of those flows — this file delegates to it rather than carrying
# competing copies.
#
# ── AUTHORITY IS THE INTERFACE REFERENCE ───────────────────────────────
#
# Authentication is ungated: proving who you are cannot require authority
# you do not yet have. Everything that MUTATES credential or token state
# sits behind `interface AuthService`, obtained once through an accessor
# that takes a Capability. No method below takes an authority token.
#
# This file used to carry a second, parallel authorization system —
# PermissionRequest / PermissionGrant / PermissionCheck with permission
# ids, resource strings and `grantedBy` — which DESIGN_PRINCIPLES.md:399
# forbids outright ("Do NOT define permission strings, boolean flags, or
# role-based access control in the protocol. The capability system IS the
# access control mechanism."). Its cost was concrete: a grant made here
# could outlive or contradict a capability revoked in capability.capnp,
# and every consumer had to learn two access models and reconcile them.
# Grants are Capabilities now; attenuation and revocation belong to
# capability.capnp.
#
# ── REFRESH REQUIRES PROOF OF POSSESSION ──────────────────────────────
#
# `refreshToken` used to take a token ID and mint a fresh token.
# T.AuthTokenId is a UInt64, i.e. enumerable, so anyone who learned or
# guessed any id could extend a session forever, and the id was never
# bound to the secret it represented. The refresh call now presents the
# token value itself, and a backend MUST verify it matches before
# issuing a successor.
#
# ── AUTH METHOD TYPE IS AN OPEN TOKEN ─────────────────────────────────
#
# The previous AuthMethodType enum named fingerprint, face, iris, voice,
# gesture and smartCard — platform biometric specifics — so a 2046
# modality (DNA, brainwave, odour, behavioural fusion) had only `custom`
# carrying nothing, and a consumer could not tell what it was. The type
# is now an open token published as a conformance const below.
# ═══════════════════════════════════════════════════════════════════════

# ── Root: ungated authentication and discovery ─────────────────────────

interface Auth {
    # Authenticate with credentials.
    authenticate @0 (request :AuthRequest) -> (result :AuthResult);

    # List available auth methods.
    listAuthMethods @1 (pagination :T.Pagination) -> (methods :List(AuthMethodInfo), totalCount :UInt32);

    # Get supported auth factors.
    getSupportedFactors @2 (pagination :T.Pagination) -> (factors :List(AuthFactor), totalCount :UInt32);

    # ── MFA flow ──
    # The challenge state machine itself belongs to access.capnp; these
    # two are the authentication-side entry points into it.
    startMfa @3 (methodId :T.AuthMethodId) -> (challenge :AuthMfaChallenge);
    verifyMfa @4 (challengeId :T.MfaChallengeId, response :Data) -> (result :AuthResult);

    # ── Lockout status (observation) ──
    getLockoutStatus @5 () -> (status :LockoutStatus);

    # Audit-7: read-only token introspection without refresh/revoke.
    introspectToken @6 (tokenId :T.AuthTokenId) -> (token :AuthToken, valid :Bool);

    # Audit-7: get the current auth method display order.
    getAuthMethodOrder @7 () -> (orderedIds :List(T.AuthMethodId));

    # Audit-9: look up a scope descriptor by T.ScopeId.
    getScope @8 (scopeId :T.ScopeId) -> (info :ScopeInfo);

    # Audit-9: list all registered scopes.
    listScopes @9 (pagination :T.Pagination) -> (scopes :List(ScopeInfo), total :UInt32);

    # ── Gated once, at acquisition ──────────────────────────────────
    # Holding `service` IS the authority to register credentials, issue,
    # refresh and revoke tokens, and reorder methods. No method inside
    # takes an authority token.
    session @10 (authority :Capability) -> (service :AuthService);
}

# ── Privileged surface: obtained with a Capability ──────────────────────
# Method ordinals were re-issued when this surface was split off the flat
# interface: the surface is pre-release and nothing external consumed the
# old shape, so a clean sequence is clearer than one with holes.

interface AuthService {
    # Register a custom auth method handler.
    registerAuthMethod @0 (method :AuthMethodInfo, handler :AuthHandler) -> T.VoidResult;

    # Unregister an auth method.
    unregisterAuthMethod @1 (methodId :T.AuthMethodId) -> T.VoidResult;

    # ── Token lifecycle ──
    # Proof of possession is mandatory: see the header.
    refreshToken @2 (tokenId :T.AuthTokenId, proof :T.DataHandle) -> (result :AuthTokenResult);
    revokeToken @3 (tokenId :T.AuthTokenId) -> T.VoidResult;
    # Revoke every token held by the CALLER. The previous `revokeAllTokens`
    # said "all" without saying whose, and every implementer chose: this
    # session, this user, or the whole system — a security-critical
    # choice made invisible on the wire. The blast radius is now part of
    # the contract. Revoking another principal's tokens is a capability
    # operation, not this method's.
    revokeAllTokens @4 (scope :T.ScopeId) -> T.VoidResult;
    listActiveTokens @5 (pagination :T.Pagination) -> (tokens :List(AuthToken), totalCount :UInt32);

    # ── Credential enrollment ──
    # Gated: enrolling a credential you do not hold (someone else's
    # biometric template, for instance) is no longer open to any holder
    # of the reference.
    enrollCredential @6 (request :EnrollRequest) -> (result :EnrollResult);

    # ── Events ──
    subscribe @7 () -> (subscription :AuthSubscription);
    pull @8 (subscription :AuthSubscription) -> (events :List(AuthEvent));
    cancel @9 (subscription :AuthSubscription) -> T.VoidResult;

    # Audit-7: let users reorder preferred auth methods.
    setAuthMethodOrder @10 (orderedIds :List(T.AuthMethodId)) -> T.VoidResult;

    # Audit-9: enforce auth method priority.
    enforceAuthMethodPriority @11 (methodId :T.AuthMethodId, minPriority :UInt32) -> (enforced :Bool);

    # Audit-9: validate claims against an expected schema.
    validateClaims @12 (claims :ClaimsSet, expectedSchema :ClaimsSchema) -> (valid :Bool, violations :List(Text));

    # Audit-9: register a typed scope descriptor.
    registerScope @13 (info :ScopeInfo) -> T.VoidResult;
}

interface AuthHandler {
    authenticate @0 (credentials :Credentials) -> (result :AuthResult);
}

# ── Auth Request ──────────────────────────────────────────────────────

struct AuthRequest {
    method @0 :T.AuthMethodId;
    credentials @1 :Credentials;
    # Optional challenge for challenge-response auth.
    challenge @2 :Data;
    # Scopes identified by typed T.ScopeId for cross-schema references.
    scopeIds @3 :List(T.ScopeId);
}

struct Credentials {
    union {
        # Secret fields are opaque Data, not Text: a password
        # materialised as text in the message arena is copied, exposed to
        # any crash dump or message log, and trivially greppable.
        password @0 :Data;
        pin @1 :Data;
        biometric @2 :BiometricCredential;
        otp @3 :Data;
        token @4 :Data;
        challenge @5 :Data;
        custom @6 :T.StringMap;
    }
}

struct BiometricCredential {
    # Reference to biometric template (from biometric.capnp).
    templateId @0 :T.BiometricId;
    # Signed challenge (crypto-binding).
    signature @1 :Data;
    # Modality used, as an open token.
    modality @2 :Text;
}

# ── Auth Result ───────────────────────────────────────────────────────

struct AuthResult {
    union {
        success @0 :AuthSuccess;
        failed @1 :T.Error;
        mfaRequired @2 :AuthMfaChallenge;
        lockout @3 :LockoutStatus;
        custom @4 :Data;
    }
}

struct AuthSuccess {
    token @0 :AuthToken;
    # Scopes actually granted, as typed T.ScopeId. The previous
    # List(Text) response forced a consumer to round-trip Text → ScopeId
    # through getScope just to compare it against what it asked for:
    # three spellings of "scope" in one file, the weakest of them on the
    # response side a user sees.
    grantedScopes @1 :List(T.ScopeId);
}

# ── Auth Token ────────────────────────────────────────────────────────

struct AuthToken {
    id @0 :T.AuthTokenId;
    type @1 :TokenType;
    # Opaque token value (backend-decided format). This is the secret
    # refreshToken requires as proof of possession; it is never the id.
    value @2 :Data;
    issuedAt @3 :T.Timestamp;
    expiresAt @4 :T.Timestamp;
    issuer @5 :Text;
    audience @6 :Text;
    scopeIds @7 :List(T.ScopeId);
    claims @8 :ClaimsSet;
    # Whether a refresh may be issued against this token more than once.
    # Declared on the wire so replay behaviour is not a per-backend
    # secret.
    reusable @9 :Bool;
}

# Result of a refresh or token lifecycle operation. Previously a bare
# wrapper struct, so an expired, revoked or unproven refresh had no
# failure representation at all.
struct AuthTokenResult {
    union {
        token @0 :AuthToken;
        error @1 :T.Error;
        custom @2 :Data;
    }
}

# Audit-7 addition: typed common claims replacing bare StringMap.
struct ClaimsSet {
    subject @0 :Text;
    issuer @1 :Text;
    audience @2 :Text;
    expiresAt @3 :T.Timestamp;
    notBefore @4 :T.Timestamp;
    issuedAt @5 :T.Timestamp;
    scopeIds @6 :List(T.ScopeId);
    # Human-readable scope descriptors (mirrors scopeIds for display).
    scopeDescriptions @7 :List(Text);
    custom @8 :T.StringMap;
}

enum TokenType {
    unspecified @0;   # Sentinel: an unset type is not "bearer"
    bearer @1;
    capability @2;
    mac @3;
    custom @4;
}

# ── Auth Method ───────────────────────────────────────────────────────

struct AuthMethodInfo {
    id @0 :T.AuthMethodId;
    # Open token; see conformance consts below. An unrecognized token is
    # ignored, never rejected.
    type @1 :Text;
    name @2 :Text;
    description @3 :Text;
    icon @4 :AI.AppIcon;
    enabled @5 :Bool;
    # Higher values = higher priority in UI display order.
    priority @6 :UInt32;
    requiredFactors @7 :List(AuthFactor);
}


# ── Auth Factor ───────────────────────────────────────────────────────

struct AuthFactor {
    id @0 :T.AuthMethodId;
    type @1 :Text;
    name @2 :Text;
    available @3 :Bool;
    icon @4 :AI.AppIcon;
    description @5 :Text;
}

# ── MFA ───────────────────────────────────────────────────────────────

struct AuthMfaChallenge {
    challengeId @0 :T.MfaChallengeId;
    type @1 :Text;
    payload @2 :Data;
    expiresAt @3 :T.Timestamp;
}

# ── Enrollment ────────────────────────────────────────────────────────

struct EnrollRequest {
    type @0 :Text;
    credentials @1 :Credentials;
    label @2 :Text;
}

struct EnrollResult {
    union {
        success @0 :EnrollSuccess;
        error @1 :T.Error;
        custom @2 :Data;
    }
}

struct EnrollSuccess {
    credentialId @0 :T.AccessCredentialId;
    type @1 :Text;
}

# ── Lockout ───────────────────────────────────────────────────────────

struct LockoutStatus {
    locked @0 :Bool;
    remainingAttempts @1 :UInt32;
    lockoutExpiresAt @2 :T.Timestamp;
    kind @3 :LockoutKind;
}

enum LockoutKind {
    none @0;
    permanent @1;
    timed @2;
    temporary @3;
    custom @4;
}

# ── Events ────────────────────────────────────────────────────────────

interface AuthSubscription {
    pull @0 () -> (events :List(AuthEvent));
    cancel @1 () -> T.VoidResult;
}

struct AuthEvent {
    union {
        authenticated @0 :AuthEventAuthenticated;
        failed @1 :AuthEventFailed;
        tokenIssued @2 :AuthEventTokenIssued;
        tokenRevoked @3 :AuthEventTokenRevoked;
        lockoutStarted @4 :AuthEventLockout;
        lockoutEnded @5 :AuthEventLockout;
        # Audit-9: admin-initiated token revocation.
        tokenRevokedByAdmin @6 :AuthEventTokenRevokedByAdmin;
        custom @7 :Data;
    }
}

struct AuthEventAuthenticated {
    method @0 :T.AuthMethodId;
    timestamp @1 :T.Timestamp;
}

struct AuthEventFailed {
    method @0 :T.AuthMethodId;
    reason @1 :T.Error;
    remainingAttempts @2 :UInt32;
    timestamp @3 :T.Timestamp;
}

struct AuthEventTokenIssued {
    tokenId @0 :T.AuthTokenId;
    expiresAt @1 :T.Timestamp;
    timestamp @2 :T.Timestamp;
}

struct AuthEventTokenRevoked {
    tokenId @0 :T.AuthTokenId;
    timestamp @1 :T.Timestamp;
}

struct AuthEventLockout {
    remainingAttempts @0 :UInt32;
    expiresAt @1 :T.Timestamp;
    timestamp @2 :T.Timestamp;
}

# Audit-9: richer factor metadata for UI display.
struct AuthFactorInfo {
    methodId @0 :T.AuthMethodId;
    type @1 :Text;
    name @2 :Text;
    color @3 :Text;
    badge @4 :Text;
    recommended @5 :Bool;
    ready @6 :Bool;
    lastUsedAt @7 :T.Timestamp;
}

# Audit-9: claims validation schema — defines expected claim constraints.
struct ClaimsSchema {
    requiredFields @0 :List(Text);
    expectedIssuer @1 :Text;
    expectedAudience @2 :Text;
    maxLifetime @3 :T.Duration;
    requiredScopes @4 :List(T.ScopeId);
}

# Audit-9: token revocation notification event.
struct AuthEventTokenRevokedByAdmin {
    tokenId @0 :T.AuthTokenId;
    revokedBy @1 :Text;
    reason @2 :Text;
    timestamp @3 :T.Timestamp;
}

# Audit-9: typed scope descriptor for cross-schema scope identification.
struct ScopeInfo {
    scopeId @0 :T.ScopeId;
    name @1 :Text;
    description @2 :Text;
    sensitive @3 :Bool;
    registeredAt @4 :T.Timestamp;
    registeredBy @5 :Text;
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Today's spellings for the open `type` fields above. Nothing requires
# them; an unrecognized token MUST be ignored rather than rejected. This
# section can grow without touching a single ordinal, so a 2046 modality
# becomes nameable the day a backend ships it — no schema amendment, and
# no `custom` slot that carries nothing.
# ══════════════════════════════════════════════════════════════════════

const methodPassword  :Text = "password";
const methodPin       :Text = "pin";
const methodFingerprint :Text = "fingerprint";
const methodFace      :Text = "face";
const methodIris      :Text = "iris";
const methodVoice     :Text = "voice";
const methodGesture   :Text = "gesture";
const methodDevice    :Text = "device";
const methodOtp       :Text = "otp";
const methodChallenge :Text = "challenge";
const methodSmartCard :Text = "smartcard";
const methodPassphrase :Text = "passphrase";

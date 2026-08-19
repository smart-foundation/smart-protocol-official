@0xa1b2c3d4e5f60015;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Auth - authentication, authorization, and credential management
#
# This schema handles the full auth lifecycle: authentication (who are
# you?), authorization (what can you do?), credential management, and
# token lifecycle. Biometric hardware interaction lives in
# biometric.capnp; this schema orchestrates the auth flow.
#
# All permissions are resource-scoped and typed. All errors are T.Error.
# All tokens carry structured metadata. All IDs are typed.
# ═══════════════════════════════════════════════════════════════════════

interface AuthService {
    # Authenticate with credentials.
    authenticate @0 (request :AuthRequest) -> (result :AuthResult);

    # Request a permission grant for a resource.
    requestPermission @1 (request :PermissionRequest) -> (grant :PermissionGrant);

    # Check if a permission is granted.
    checkPermission @2 (permission :T.PermissionId, resource :Text) -> (result :PermissionCheck);

    # List available auth methods.
    listAuthMethods @3 (pagination :T.Pagination) -> (methods :List(AuthMethodInfo), totalCount :UInt32);

    # Register a custom auth method handler.
    registerAuthMethod @4 (method :AuthMethodInfo, handler :AuthHandler) -> T.VoidResult;

    # Unregister an auth method.
    unregisterAuthMethod @5 (methodId :T.AuthMethodId) -> T.VoidResult;

    # Get supported auth factors.
    getSupportedFactors @6 (pagination :T.Pagination) -> (factors :List(AuthFactor), totalCount :UInt32);

    # ── Token lifecycle ──
    refreshToken @7 (tokenId :T.AuthTokenId) -> (result :AuthTokenResultWrapper);
    revokeToken @8 (tokenId :T.AuthTokenId) -> T.VoidResult;
    revokeAllTokens @9 () -> T.VoidResult;
    listActiveTokens @10 (pagination :T.Pagination) -> (tokens :List(AuthToken), totalCount :UInt32);

    # ── MFA flow ──
    startMfa @11 (methodId :T.AuthMethodId) -> (challenge :MfaChallenge);
    verifyMfa @12 (challengeId :T.MfaChallengeId, response :Data) -> (result :AuthResult);

    # ── Credential enrollment ──
    enrollCredential @13 (request :EnrollRequest) -> (result :EnrollResult);

    # ── Lockout status ──
    getLockoutStatus @14 () -> (status :LockoutStatus);

    # ── Events ──
    subscribe @15 () -> (subscription :AuthSubscription);
    pull @16 (subscription :AuthSubscription) -> (events :List(AuthEvent));
    cancel @17 (subscription :AuthSubscription) -> T.VoidResult;

    # Audit-7: read-only token introspection without refresh/revoke.
    introspectToken @18 (tokenId :T.AuthTokenId) -> (token :AuthToken, valid :Bool);

    # Audit-7: let users reorder preferred auth methods.
    setAuthMethodOrder @19 (orderedIds :List(T.AuthMethodId)) -> T.VoidResult;

    # Audit-7: get the current auth method display order.
    getAuthMethodOrder @20 () -> (orderedIds :List(T.AuthMethodId));

    # Audit-9: enforce auth method priority (returns true if method is above threshold).
    enforceAuthMethodPriority @21 (methodId :T.AuthMethodId, minPriority :UInt32) -> (enforced :Bool);

    # Audit-9: validate claims against an expected schema.
    validateClaims @22 (claims :ClaimsSet, expectedSchema :ClaimsSchema) -> (valid :Bool, violations :List(Text));

    # Audit-9: register a typed scope descriptor.
    registerScope @23 (info :ScopeInfo) -> T.VoidResult;

    # Audit-9: look up a scope descriptor by T.ScopeId.
    getScope @24 (scopeId :T.ScopeId) -> (info :ScopeInfo);

    # Audit-9: list all registered scopes.
    listScopes @25 (pagination :T.Pagination) -> (scopes :List(ScopeInfo), total :UInt32);
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
    # Audit-9: scopes identified by typed T.ScopeId for cross-schema references.
    # Migration note: previous List(Text) field renamed; consumers using string
    # scopes should pair with the ScopeInfo registry.
    scopeIds @3 :List(T.ScopeId);
}

struct Credentials {
    union {
        password @0 :Text;
        pin @1 :Text;
        biometric @2 :BiometricCredential;
        otp @3 :Text;
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
    # Modality used.
    modality @2 :Text;
}

# ── Auth Result ───────────────────────────────────────────────────────

struct AuthResult {
    union {
        success @0 :AuthSuccess;
        failed @1 :T.Error;
        mfaRequired @2 :MfaChallenge;
        lockout @3 :LockoutStatus;
        custom @4 :Data;
    }
}

struct AuthSuccess {
    token @0 :AuthToken;
    # Scopes actually granted.
    grantedScopes @1 :List(Text);
}

# ── Auth Token ────────────────────────────────────────────────────────

struct AuthToken {
    id @0 :T.AuthTokenId;
    type @1 :TokenType;
    # Opaque token value (backend-decided format).
    value @2 :Data;
    issuedAt @3 :T.Timestamp;
    expiresAt @4 :T.Timestamp;
    issuer @5 :Text;
    audience @6 :Text;
    # Audit-9: scopes as typed T.ScopeId (was List(Text) @7).
    scopeIds @7 :List(T.ScopeId);
    # Audit-7: structured claims for token introspection.
    claims @8 :ClaimsSet;
}

# Wrapper for token refresh result.
struct AuthTokenResultWrapper {
    token @0 :AuthToken;
}

# Audit-7 addition: typed common claims replacing bare StringMap.
# Provides structured access to standard JWT-like claims while
# retaining extensibility for custom claims via the custom field.
struct ClaimsSet {
    # Subject (who the token represents).
    subject @0 :Text;
    # Issuer (who issued the token).
    issuer @1 :Text;
    # Audience (who the token is intended for).
    audience @2 :Text;
    # Expiration time.
    expiresAt @3 :T.Timestamp;
    # Not-before time.
    notBefore @4 :T.Timestamp;
    # Issued-at time.
    issuedAt @5 :T.Timestamp;
    # Audit-9: granted scopes as typed T.ScopeId for cross-schema references.
    scopeIds @6 :List(T.ScopeId);
    # Audit-9: human-readable scope descriptors (mirrors scopeIds for display).
    scopeDescriptions @7 :List(Text);
    # Custom claims (backend-defined). Renamed @7 → @8 to keep insertion order.
    custom @8 :T.StringMap;
}

enum TokenType {
    bearer @0;
    capability @1;
    mac @2;
    custom @3;
}

# ── Permissions ───────────────────────────────────────────────────────

struct PermissionRequest {
    permission @0 :T.PermissionId;
    resource @1 :Text;
    # Optional TTL for temporary grants.
    ttl @2 :T.Duration;
    # Reason for the request (shown in UI).
    reason @3 :Text;
}

struct PermissionGrant {
    permission @0 :T.PermissionId;
    resource @1 :Text;
    granted @2 :Bool;
    grantedAt @3 :T.Timestamp;
    expiresAt @4 :T.Timestamp;
    grantedBy @5 :Text;
}

struct PermissionCheck {
    granted @0 :Bool;
    expiresAt @1 :T.Timestamp;
}

# ── Auth Method ───────────────────────────────────────────────────────

struct AuthMethodInfo {
    id @0 :T.AuthMethodId;
    type @1 :AuthMethodType;
    name @2 :Text;
    description @3 :Text;
    icon @4 :AppIcon;
    enabled @5 :Bool;
    # Higher values = higher priority in UI display order.
    priority @6 :UInt32;
    # Required factors for this method.
    requiredFactors @7 :List(AuthFactor);
}

struct AppIcon {
    data @0 :Data;
    mimeType @1 :Text;
}

enum AuthMethodType {
    password @0;
    pin @1;
    fingerprint @2;
    face @3;
    iris @4;
    voice @5;
    gesture @6;
    device @7;
    otp @8;
    challenge @9;
    smartCard @10;
    passphrase @11;
    custom @12;
}

# ── Auth Factor ───────────────────────────────────────────────────────

struct AuthFactor {
    # Audit-7: promoted to typed reference for cross-schema identification.
    id @0 :T.AuthMethodId;
    type @1 :AuthMethodType;
    name @2 :Text;
    available @3 :Bool;
    # Audit-7: UI hint icon for the factor.
    icon @4 :AppIcon;
    # Audit-7: human-readable description.
    description @5 :Text;
}

# ── MFA ───────────────────────────────────────────────────────────────

struct MfaChallenge {
    challengeId @0 :T.MfaChallengeId;
    type @1 :AuthMethodType;
    payload @2 :Data;
    expiresAt @3 :T.Timestamp;
}

# ── Enrollment ────────────────────────────────────────────────────────

struct EnrollRequest {
    type @0 :AuthMethodType;
    credentials @1 :Credentials;
    # Optional name/label for the credential.
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
    type @1 :AuthMethodType;
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
        permissionGranted @4 :AuthEventPermissionGranted;
        permissionDenied @5 :AuthEventPermissionDenied;
        lockoutStarted @6 :AuthEventLockout;
        lockoutEnded @7 :AuthEventLockout;
        # Audit-9: admin-initiated token revocation.
        tokenRevokedByAdmin @9 :AuthEventTokenRevokedByAdmin;
        custom @8 :Data;
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

struct AuthEventPermissionGranted {
    permission @0 :T.PermissionId;
    resource @1 :Text;
    expiresAt @2 :T.Timestamp;
    timestamp @3 :T.Timestamp;
}

struct AuthEventPermissionDenied {
    permission @0 :T.PermissionId;
    resource @1 :Text;
    reason @2 :T.Error;
    timestamp @3 :T.Timestamp;
}

struct AuthEventLockout {
    remainingAttempts @0 :UInt32;
    expiresAt @1 :T.Timestamp;
    timestamp @2 :T.Timestamp;
}

# Audit-9: richer factor metadata for UI display.
struct AuthFactorInfo {
    # Factor identifier.
    methodId @0 :T.AuthMethodId;
    # Factor type.
    type @1 :AuthMethodType;
    # Human-readable name.
    name @2 :Text;
    # Background color for UI badge (CSS hex, e.g., "#4CAF50").
    color @3 :Text;
    # Badge text (e.g., "Recommended", "Primary", "Backup").
    badge @4 :Text;
    # Whether this factor is recommended by the system.
    recommended @5 :Bool;
    # Whether the factor is currently enrolled and usable.
    ready @6 :Bool;
    # When the factor was last used.
    lastUsedAt @7 :T.Timestamp;
}

# Audit-9: claims validation schema — defines expected claim constraints.
struct ClaimsSchema {
    # Required claim fields (must be non-empty).
    requiredFields @0 :List(Text);
    # Expected issuer (empty = any issuer).
    expectedIssuer @1 :Text;
    # Expected audience (empty = any audience).
    expectedAudience @2 :Text;
    # Maximum allowed token lifetime (zero = no limit).
    maxLifetime @3 :T.Duration;
    # Required scope set (all must be present).
    requiredScopes @4 :List(T.ScopeId);
}

# Audit-9: token revocation notification event — triggered when an admin revokes a token.
struct AuthEventTokenRevokedByAdmin {
    # Token that was revoked.
    tokenId @0 :T.AuthTokenId;
    # Admin or system that performed the revocation.
    revokedBy @1 :Text;
    # Reason for revocation (audit trail).
    reason @2 :Text;
    timestamp @3 :T.Timestamp;
}

# Audit-9: typed scope descriptor for cross-schema scope identification.
# Replaces bare List(Text) scope strings with structured T.ScopeId references.
struct ScopeInfo {
    # Typed scope identifier.
    scopeId @0 :T.ScopeId;
    # Human-readable scope name (e.g., "read:calendar", "write:files").
    name @1 :Text;
    # Description of what this scope permits.
    description @2 :Text;
    # Whether this scope is sensitive (redacted in logs).
    sensitive @3 :Bool;
    # When this scope was registered.
    registeredAt @4 :T.Timestamp;
    # Owner / registering entity.
    registeredBy @5 :Text;
}

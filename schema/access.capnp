@0xa1b2c3d4e5f60059;

# ═══════════════════════════════════════════════════════════════════════
# Access - device lock, authentication gates, session credentials,
#          biometric unlock integration, lockout policy, MFA flows.
#
# This schema defines the device unlocking surface. It is intentionally
# backend-agnostic: any implementation may use TPM, secure enclave,
# smart card, software keychain, or anything else. The protocol describes
# *what* must be possible, not *how* it is implemented.
#
# The schema covers the device lock state machine:
#   1. Locked (requires credential)
#   2. Unlocked (credential accepted)
#   3. Attempt metering (rate-limit failed attempts)
#   4. Lockout (cooldown after too many failures)
#
# Audit-7 enhancements (zero-cost, info-density):
#   - CredentialStrength: typed weak/medium/strong with entropy hint
#   - LockMethodRequirement: composed multi-factor policy with ordering
#   - SessionDescriptor: rich session info — caller identity, scope, scope
#     expiry, remote attestation, device-boundness
#   - AccessErrorCode: typed enumeration of common access failures
#   - LockReason: discriminated cause for explicit locks (user, idle, policy,
#     remote-admin, failure-recovery, scheduled)
#   - AccessSession: tracked session with scope and expiry
#   - PolicyViolation: detailed policy enforcement reasons
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ── Credential Strength ───────────────────────────────────────────────
# Typed strength indicator with entropy bits. Backends report this on
# enrolled credentials so unlock UX can warn users with weak passwords /
# PINs without parsing strings.
enum CredentialStrength {
    unknown @0;       # Backend could not determine
    weak @1;          # < 28 bits of entropy / 4-digit PIN / common password
    fair @2;          # 28-47 bits
    strong @3;        # 48-71 bits
    veryStrong @4;    # >= 72 bits / hardware-bound key
    custom @5;
}

struct CredentialStrengthAssessment {
    strength @0 :CredentialStrength;
    # Estimated entropy in bits; -1 = unknown.
    entropyBits @1 :Int64;
    # Human-readable explanation ("dictionary word", "4-digit PIN", etc.).
    notes @2 :Text;
}

# ── Lock Method Requirement (Composed Multi-Factor) ──────────────────
# LockMethod may be a single factor, but real-world deployments
# frequently need ordered multi-factor policies ("password AND
# biometric, with biometric optional if device credential present").
# LockMethodRequirement makes this composable without exploding the
# primary LockMethod enum.
struct LockMethodRequirement {
    union {
        # Single-factor requirement.
        single @0 :LockMethod;
        # All factors must succeed (AND).
        allOf @1 :List(LockMethod);
        # At least N of these factors must succeed (N-of-M).
        anyOf @2 :AnyOfPolicy;
        # Custom backend-defined composition.
        custom @3 :Data;
    }
}

struct AnyOfPolicy {
    requiredCount @0 :UInt32;
    factors @1 :List(LockMethod);
}

# ── Session Descriptor ─────────────────────────────────────────────────
# Real consumers (audit logging, remote attestation, MDM) need caller
# identity, scope, and policy binding. SessionDescriptor captures that
# without breaking the existing UnlockSuccess shape.
struct SessionDescriptor {
    sessionId @0 :UInt64;
    unlockedAt @1 :T.Timestamp;
    sessionValidFor @2 :T.Duration;
    method @3 :LockMethod;
    mfaUsed @4 :Bool;
    # Optional caller identity established as part of the unlock.
    callerIdentity @5 :CallerIdentity;
    # How broadly this session is trusted.
    scope @6 :SessionScope;
    # Optional remote attestation evidence.
    attestation @7 :RemoteAttestation;
    # Whether this session is cryptographically bound to the device.
    deviceBound @8 :Bool;
}

struct CallerIdentity {
    userId @0 :Text;
    displayName @1 :Text;
    # Credentials presented (each LockMethod contributes one).
    methodsUsed @2 :List(LockMethod);
    # Optional originating app/process.
    processId @3 :T.ProcessId;
}

enum SessionScope {
    # Session valid only for the current seat.
    seat @0;
    # Session valid for the whole device.
    device @1;
    # Session valid across paired devices (SaaS-style trust).
    paired @2;
    # Session valid for a specific app only.
    application @3;
    custom @4;
}

struct RemoteAttestation {
    # Opaque evidence (TPM quote, secure enclave report, etc.).
    evidence @0 :Data;
    # Backend-decoded format identifier.
    format @1 :Text;
    # Whether the attestation succeeded verification.
    verified @2 :Bool;
}

# ── Access Error Code ──────────────────────────────────────────────────
# Callers parsing T.Error.message text must pattern-match substrings.
# AccessErrorCode lifts common signals into a typed enum so consumers
# can branch on the discriminant without parsing.
enum AccessErrorCode {
    none @0;
    badPassword @1;
    badPin @2;
    badBiometric @3;
    badSmartCard @4;
    badSsoToken @5;
    lockoutActive @6;
    cooldownActive @7;
    mfaRequired @8;
    mfaExpired @9;
    mfaDenied @10;
    backendDisabled @11;
    backendBusy @12;
    backendOffline @13;
    credentialRevoked @14;
    credentialExpired @15;
    credentialNotEnrolled @16;
    hardwareBusy @17;
    hardwareOffline @18;
    rateLimited @19;
    policyViolation @20;
    integrityFailure @21;
    sessionExpired @22;
    wrongCaller @23;
    userDenied @24;
    cancelled @25;
    timedOut @26;
    notSupported @27;
    custom @28;
}

# ── Lock Reason ────────────────────────────────────────────────────────
# Audit-7 addition: discriminated cause for explicit locks. When the
# device is locked, callers need to know WHY — was it user action,
# idle timeout, policy enforcement, remote admin command, or failure
# recovery? LockReason provides that without string parsing.
enum LockReason {
    user @0;              # User explicitly locked the device
    idle @1;              # Idle timeout triggered lock
    policy @2;            # Policy enforcement (e.g. screen lock policy)
    remoteAdmin @3;       # Remote admin / MDM command
    failureRecovery @4;   # Lock after too many failed attempts
    scheduled @5;         # Scheduled lock (e.g. end-of-day)
    boot @6;              # Device booted in locked state
    suspend @7;           # Device resumed from suspend and requires auth
    custom @8;
}

# ── Policy Violation ──────────────────────────────────────────────────
# Audit-7 addition: detailed policy enforcement reasons. When an unlock
# attempt is denied due to policy, callers need specifics — not just
# "denied" but which policy was violated and what the requirement is.
struct PolicyViolation {
    # Which policy was violated.
    policy @0 :Text;
    # Human-readable explanation of the violation.
    reason @1 :Text;
    # What the policy requires (e.g. "strong biometric required").
    requirement @2 :Text;
    # Whether the user can override this violation.
    overrideable @3 :Bool;
}

# ── Access Session ─────────────────────────────────────────────────────
# Audit-7 addition: tracked session with scope and expiry. After a
# successful unlock, the system creates an AccessSession that tracks
# what the session is allowed to do, when it expires, and whether it
# can be revoked.
struct AccessSession {
    # Unique session identifier.
    sessionId @0 :UInt64;
    # When the session was created.
    createdAt @1 :T.Timestamp;
    # When the session expires (null = never).
    expiresAt @2 :T.Timestamp;
    # Current session scope.
    scope @3 :SessionScope;
    # Who owns this session.
    callerIdentity @4 :CallerIdentity;
    # Whether this session is device-bound.
    deviceBound @5 :Bool;
    # Methods used to establish this session.
    methodsUsed @6 :List(LockMethod);
    # Whether MFA was used.
    mfaUsed @7 :Bool;
    # Whether the session is currently active.
    active @8 :Bool;
}

# ── Credential Recovery ────────────────────────────────────────────────
# Audit-7 false positive integration: credential recovery and backup.
# Currently access.capnp handles enrollment and revocation but not
# recovery. Recovery codes, backup credentials, and MDM-initiated
# recovery flows complete the credential lifecycle.

enum RecoveryMethod {
    recoveryCode @0;       # One-time recovery codes
    backupCredential @1;   # Backup credential (second device, hardware key)
    mdmInitiated @2;       # MDM-initiated credential reset
    trustedDevice @3;      # Trusted device recovery
    helpDesk @4;           # Help desk / admin-assisted recovery
    custom @5;
}

struct RecoveryCode {
    # The recovery code value (hashed or encrypted).
    code @0 :Data;
    # When this code was generated.
    generatedAt @1 :T.Timestamp;
    # When this code expires (null = never).
    expiresAt @2 :T.Timestamp;
    # Whether this code has been used.
    used @3 :Bool;
    # When this code was used (null = not yet used).
    usedAt @4 :T.Timestamp;
    # Which recovery method this code supports.
    method @5 :RecoveryMethod;
    # Maximum number of submission attempts before lockout (0 = unlimited).
    maxAttempts @6 :UInt32;
    # Number of failed submission attempts so far.
    failedAttempts @7 :UInt32;
    # Whether the code is locked due to too many failed attempts.
    locked @8 :Bool;
}

struct BackupCredential {
    # Reference to the backup credential (e.g., T.AccessCredentialId).
    credentialId @0 :T.AccessCredentialId;
    # Human-readable label ("YubiKey 5", "Recovery phone").
    label @1 :Text;
    # When the backup was enrolled.
    enrolledAt @2 :T.Timestamp;
    # Whether the backup is currently active.
    active @3 :Bool;
    # Maximum number of uses (0 = unlimited).
    maxUses @4 :UInt32;
    # Number of times this backup has been used.
    usedCount @5 :UInt64;
}

struct RecoverySession {
    # Unique recovery session identifier.
    sessionId @0 :UInt64;
    # When the recovery session was initiated.
    initiatedAt @1 :T.Timestamp;
    # When the recovery session expires.
    expiresAt @2 :T.Timestamp;
    # Recovery method being used.
    method @3 :RecoveryMethod;
    # Current state of the recovery flow.
    state @4 :RecoveryState;
    # Whether MFA is required during recovery.
    mfaRequired @5 :Bool;
    # Whether the recovery requires admin approval.
    adminApprovalRequired @6 :Bool;
}

enum RecoveryState {
    initiated @0;       # Recovery flow started
    awaitingCode @1;    # Waiting for recovery code input
    awaitingMfa @2;     # Waiting for MFA verification
    awaitingApproval @3; # Waiting for admin approval
    inProgress @4;      # Recovery being processed
    completed @5;       # Recovery successful
    failed @6;          # Recovery failed
    expired @7;         # Recovery session expired
    custom @8;
}

# ── Lock Method ─────────────────────────────────────────────────────────

enum LockMethod {
    none @0;
    password @1;
    pin @2;
    pattern @3;
    biometric @4;
    smartCard @5;
    combined @6;
    sso @7;
    custom @8;
}

# ── Credential ──────────────────────────────────────────────────────────

struct Credential {
    method @0 :LockMethod;
    # Credential value (semantics depend on method).
    value @1 :CredentialValue;
    # Friendly identifier for the credential (e.g. "user's right thumb").
    label @2 :Text;
    # When the credential was enrolled.
    enrolledAt @3 :T.Timestamp;
    # When the credential was last used successfully.
    lastUsedAt @4 :T.Timestamp;
    # How often this credential has been used.
    useCount @5 :UInt64;
    # Whether credential is currently revoked/disabled.
    revoked @6 :Bool;
    # Audit-7: typed strength assessment for this credential.
    strength @7 :CredentialStrengthAssessment;
}

# Default untyped credential value. Implementations may use richer types
# (e.g. biometric templates) via `custom` variant.
struct CredentialValue {
    union {
        password @0 :Text;
        pin @1 :Text;
        pattern @2 :List(UInt8);
        # Reference to a biometric template in biometric.capnp space.
        biometricTemplate @3 :T.BiometricId;
        # PKCS#11 / PIV token identifier.
        smartCard @4 :Data;
        # Single-sign-on bearer token.
        ssoToken @5 :Data;
        # Backend-defined opaque credential.
        custom @6 :Data;
    }
}

# ── Lockout Policy ──────────────────────────────────────────────────────

struct LockoutPolicy {
    # Maximum number of failed attempts before lockout kicks in.
    # Zero disables lockout entirely.
    maxAttempts @0 :UInt32;
    # How long the lockout lasts once triggered.
    lockoutDuration @1 :T.Duration;
    # Cooldown per failed attempt (progressive delay) before the next
    # attempt is allowed. Zero = no cooldown (only full lockout).
    cooldownPerAttempt @2 :T.Duration;
    # Whether to wipe credentials after N failed attempts.
    wipeAfter @3 :UInt32;
    # Whether to require a secondary factor after M failed attempts.
    requireMfaAfter @4 :UInt32;
    # Audit-7: how many lockout windows to remember for progressive policy.
    lockoutWindowHistory @5 :UInt32;
}

# ── Lock State ──────────────────────────────────────────────────────────

struct AccessState {
    # Whether the device is currently locked.
    locked @0 :Bool;
    # Current lock method.
    method @1 :LockMethod;
    # Current lockout policy.
    lockoutPolicy @2 :LockoutPolicy;
    # When the device was last locked.
    lockedAt @3 :T.Timestamp;
    # When the device was last unlocked.
    unlockedAt @4 :T.Timestamp;
    # Failed attempt count in the current window.
    failedAttempts @5 :UInt32;
    # Whether the device is currently in lockout.
    lockout @6 :LockoutInfo;
    # For how long the current user has been authenticated.
    authenticatedFor @7 :T.Duration;
    # Audit-7: reason for the current lock (if locked explicitly).
    lockReason @8 :LockReason;
    # Audit-7: active session (if unlocked).
    activeSession @9 :AccessSession;
}

struct LockoutInfo {
    # When the lockout started.
    startedAt @0 :T.Timestamp;
    # When the lockout will end (if timed).
    endsAt @1 :T.Timestamp;
    # Total failed attempts that triggered this lockout.
    failedAttempts @2 :UInt32;
    # Whether this lockout is timed (vs permanent).
    timed @3 :Bool;
}

# ── Unlock Attempt Outcome ──────────────────────────────────────────────

struct UnlockOutcome {
    union {
        # Credential accepted.
        success @0 :UnlockSuccess;
        # Credential rejected but device not locked out.
        failed @1 :UnlockFailure;
        # Lockout triggered (or already active).
        lockedOut @2 :LockoutInfo;
        # MFA required as additional challenge.
        mfaRequired @3 :MfaChallenge;
        # Backend refused to engage (system disabled, etc.).
        denied @4 :T.Error;
        # Audit-7: policy violation prevented unlock.
        policyViolation @5 :PolicyViolation;
        # Backend-specific outcome.
        custom @6 :Data;
    }
}

struct UnlockSuccess {
    # How the unlock was accomplished.
    method @0 :LockMethod;
    # Timestamp of acceptance.
    unlockedAt @1 :T.Timestamp;
    # Validity window for the session (zero = until explicit lock).
    sessionValidFor @2 :T.Duration;
    # Whether MFA was used in conjunction.
    mfaUsed @3 :Bool;
    # Audit-7: the newly created session descriptor.
    session @4 :AccessSession;
}

struct UnlockFailure {
    # Why the credential was rejected.
    reason @0 :UnlockFailureReason;
    # Failed attempt count after this attempt.
    newFailedAttempts @1 :UInt32;
    # Time until next attempt is allowed (cooldown).
    cooldownEndsAt @2 :T.Timestamp;
    # Audit-7: typed error code for programmatic handling.
    errorCode @3 :AccessErrorCode;
}

enum UnlockFailureReason {
    unknown @0;
    invalidCredential @1;
    expired @2;
    revoked @3;
    notEnrolled @4;
    backendError @5;
    custom @6;
}

# ── MFA ──────────────────────────────────────────────────────────────────

struct MfaChallenge {
    # Identifier for the challenge instance.
    challengeId @0 :T.MfaChallengeId;
    # Method required (TOTP, push, hardware key, etc.).
    method @1 :MfaMethod;
    # When this challenge was issued.
    issuedAt @2 :T.Timestamp;
    # When it must be answered by.
    expiresAt @3 :T.Timestamp;
    # Challenge-specific payload (TOTP URI, push challenge nonce, etc.).
    payload @4 :Data;
}

# MFA Verify Result
struct MfaVerifyResult {
    union {
        # MFA challenge satisfied successfully.
        success @0 :Void;
        # MFA response rejected (wrong code, invalid response, etc.).
        denied @1 :T.Error;
        # Challenge expired before response was submitted.
        expired @2 :Void;
        # Backend-specific MFA verification outcome.
        custom @3 :Data;
    }
}

enum MfaMethod {
    totp @0;
    push @1;
    hardwareKey @2;
    backupCode @3;
    sms @4;
    email @5;
    custom @6;
}

struct MfaEnrollment {
    method @0 :MfaMethod;
    # Free-form label for human reference.
    label @1 :Text;
    # When this MFA was enrolled.
    enrolledAt @2 :T.Timestamp;
    # Whether the enrollment is currently active.
    active @3 :Bool;
}

# ── Unlock Request ──────────────────────────────────────────────────────

struct UnlockRequest {
    # Credential to present.
    credential @0 :Credential;
    # Optional MFA challenge response to satisfy alongside.
    mfaResponse @1 :Data;
    # Optional caller-provided reason (for audit log).
    reason @2 :Text;
    # Audit-7: requested session scope.
    requestedScope @3 :SessionScope;
    # Audit-7: requested session duration.
    requestedDuration @4 :T.Duration;
}

# ── Access Events ───────────────────────────────────────────────────────

struct AccessEvent {
    timestamp @0 :T.Timestamp;
    union {
        locked @1 :Void;
        unlocked @2 :UnlockSuccess;
        failedAttempt @3 :UnlockFailure;
        lockoutStarted @4 :LockoutInfo;
        lockoutEnded @5 :T.Timestamp;
        authMethodChanged @6 :LockMethod;
        lockoutPolicyChanged @7 :LockoutPolicy;
        mfaEnrolled @8 :MfaEnrollment;
        mfaRevoked @9 :T.MfaChallengeId;
        credentialEnrolled @10 :Credential;
        credentialRevoked @11 :Credential;
        backendUnavailable @12 :T.Error;
        # Audit-7: session revoked (timeout, remote admin, policy).
        sessionRevoked @13 :AccessSession;
        # Audit-9: recovery flow state change (initiated, code submitted, completed, failed).
        recoveryStateChange @15 :RecoveryStateChangeEvent;
        # Audit-9: backup credential rotated.
        backupRotated @16 :BackupRotatedEvent;
        custom @14 :Data;
    }
}

# ── Filter ──────────────────────────────────────────────────────────────

struct AccessFilter {
    # Restrict the subscription to specific event types.
    eventTypes @0 :List(AccessEventType);
    # Only events since this timestamp.
    since @1 :T.Timestamp;
    # Whether to include failed-attempt telemetry.
    includeTelemetry @2 :Bool;
    # Audit-7: restrict to specific lock reasons.
    lockReasons @3 :List(LockReason);
}

enum AccessEventType {
    locked @0;
    unlocked @1;
    failedAttempt @2;
    lockoutStarted @3;
    lockoutEnded @4;
    authMethodChanged @5;
    lockoutPolicyChanged @6;
    mfaEnrolled @7;
    mfaRevoked @8;
    credentialEnrolled @9;
    credentialRevoked @10;
    backendUnavailable @11;
    sessionRevoked @12;
    recoveryStateChange @13;
    backupRotated @14;
    custom @15;
}

# ── Service ─────────────────────────────────────────────────────────────

interface AccessService {
    # Current state of the access subsystem.
    getState @0 () -> (state :AccessState);

    # Lock the device immediately.
    lock @1 (reason :LockReason) -> T.VoidResult;

    # Attempt to unlock with the given credential.
    unlock @2 (request :UnlockRequest) -> (outcome :UnlockOutcome);

    # Whether the device is currently locked.
    isLocked @3 () -> (locked :Bool);

    # Configure the primary lock method.
    setLockMethod @4 (method :LockMethod) -> T.VoidResult;
    getLockMethod @5 () -> (method :LockMethod);

    # Lockout policy.
    getLockoutPolicy @6 () -> (policy :LockoutPolicy);
    setLockoutPolicy @7 (policy :LockoutPolicy) -> T.VoidResult;

    # Credentials.
    listCredentials @8 (pagination :T.Pagination) -> (credentials :List(Credential), total :UInt32);
    enrollCredential @9 (credential :Credential) -> (credId :T.AccessCredentialId);
    revokeCredential @10 (credId :T.AccessCredentialId) -> T.VoidResult;

    # MFA.
    requestMfaChallenge @11 (method :MfaMethod) -> (challenge :MfaChallenge);
    verifyMfaChallenge @12 (challengeId :T.MfaChallengeId, response :Data) -> (result :MfaVerifyResult);
    listMfaEnrollments @13 (pagination :T.Pagination) -> (enrollments :List(MfaEnrollment), total :UInt32);
    enrollMfa @14 (enrollment :MfaEnrollment) -> (id :T.MfaEnrollmentId);
    revokeMfa @15 (id :T.MfaEnrollmentId) -> T.VoidResult;

    # Backend selection (multi-implementation systems).
    listBackends @16 (pagination :T.Pagination) -> (backends :List(AccessBackend), totalCount :UInt32);
    setActiveBackend @17 (backendId :T.AccessBackendId) -> T.VoidResult;

    # Subscribe to access events.
    subscribe @18 (filter :AccessFilter) -> (subscription :AccessSubscription);

    # Audit-7: list active sessions.
    listSessions @19 (pagination :T.Pagination) -> (sessions :List(AccessSession), totalCount :UInt32);

    # Audit-7: revoke a specific session.
    revokeSession @20 (sessionId :UInt64) -> T.VoidResult;

    # Audit-7: query lock reason for the current lock.
    getLockReason @21 () -> (reason :LockReason);

    # Audit-7: evaluate credential strength without enrolling.
    assessCredential @22 (credential :Credential) -> (assessment :CredentialStrengthAssessment);

    # Audit-7: initiate a credential recovery flow.
    startRecovery @23 (method :RecoveryMethod) -> (session :RecoverySession);

    # Audit-7: submit a recovery code during recovery.
    submitRecoveryCode @24 (sessionId :UInt64, code :Data) -> (result :RecoveryResult);

    # Audit-7: list available recovery methods.
    listRecoveryMethods @25 () -> (methods :List(RecoveryMethod));

    # Audit-7: enroll a backup credential for recovery.
    enrollBackup @26 (credential :Credential, label :Text) -> (backup :BackupCredential);

    # Audit-7: list enrolled backup credentials.
    listBackups @27 (pagination :T.Pagination) -> (backups :List(BackupCredential), total :UInt32);

    # Audit-7: revoke a backup credential.
    revokeBackup @28 (credentialId :T.AccessCredentialId) -> T.VoidResult;

    # Audit-7: generate recovery codes for the current user.
    generateRecoveryCodes @29 (count :UInt32) -> (codes :List(RecoveryCode));

    # Audit-9: rotate a backup credential (issue new, invalidate old).
    rotateBackup @30 (credentialId :T.AccessCredentialId) -> (newBackup :BackupCredential);

    # Audit-9: get the recovery code rate limit policy.
    getRecoveryRateLimitPolicy @31 () -> (policy :RecoveryRateLimitPolicy);

    # Audit-9: set the recovery code rate limit policy.
    setRecoveryRateLimitPolicy @32 (policy :RecoveryRateLimitPolicy) -> T.VoidResult;
}

# Audit-9: rate limit policy for recovery code submission.
struct RecoveryRateLimitPolicy {
    # Maximum failed submission attempts per recovery session (0 = unlimited).
    maxAttemptsPerSession @0 :UInt32;
    # Maximum failed submission attempts per credential per window (0 = unlimited).
    maxAttemptsPerCredential @1 :UInt32;
    # Window duration for per-credential attempts.
    credentialWindow @2 :T.Duration;
    # Cooldown per failed attempt (progressive delay).
    cooldownPerAttempt @3 :T.Duration;
    # Base cooldown before the first attempt is allowed after recovery starts.
    initialCooldown @4 :T.Duration;
    # Whether to trigger lockout when limits are exceeded.
    lockoutOnExceed @5 :Bool;
}

struct RecoveryResult {
    union {
        success @0 :Void;
        failed @1 :T.Error;
        requiresMfa @2 :MfaChallenge;
        requiresApproval @3 :Void;
        custom @4 :Data;
    }
}

struct AccessBackend {
    id @0 :T.AccessBackendId;
    name @1 :Text;
    # Capabilities this backend supports.
    supportedMethods @2 :List(LockMethod);
    # Whether the backend currently can service unlock requests.
    available @3 :Bool;
    # Human-readable backend kind (e.g. "tpm", "secureEnclave", "software").
    kind @4 :Text;
    # Trust level of this backend (higher = more trusted).
    trustLevel @5 :BackendTrustLevel;
}

enum BackendTrustLevel {
    untrusted @0;
    low @1;
    medium @2;
    high @3;
    maximum @4;
    custom @5;
}

struct RecoveryStateChangeEvent {
    # Recovery session identifier.
    sessionId @0 :UInt64;
    # Previous state of the recovery flow.
    previousState @1 :RecoveryState;
    # New state of the recovery flow.
    newState @2 :RecoveryState;
    # When the state change occurred.
    timestamp @3 :T.Timestamp;
    # Optional human-readable reason for the state change.
    reason @4 :Text;
}

struct BackupRotatedEvent {
    # The backup credential that was rotated.
    oldCredentialId @0 :T.AccessCredentialId;
    # The new backup credential that replaced it.
    newCredentialId @1 :T.AccessCredentialId;
    # When the rotation occurred.
    timestamp @2 :T.Timestamp;
}

interface AccessSubscription {
    pull @0 () -> (events :List(AccessEvent));
    cancel @1 () -> T.VoidResult;
}

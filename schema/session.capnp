@0xa1b2c3d4e5f6000d;

# ═══════════════════════════════════════════════════════════════════════
# Session — the user session: lock, unlock, identity, idle, persistence.
#
# ── THE SERVICE SESSION PATTERN (canonical, documented once) ───────────
#
# Five schemas own a SERVICE session, and this one owns the USER session.
# They are acceptable — each is a distinct service domain, and merging them
# would merge unrelated contracts (DESIGN_PRINCIPLES.md:213). Until the
# 2026-10-10 integration pass they all shared the bare name `Session`, six
# declarations of one name that a consumer had to disambiguate by which
# import it was reading. The five service sessions are now named for their
# domain — `compositor.CompositorSession`, `shell.ShellSession`,
# `windowmanager.WindowManagerSession`, `ime.ImeSession`,
# `screenlock.ScreenlockSession` — and the plain name `Session` belongs to
# this file alone, because this is the user session the doctrine names.
#
# What was NOT documented was the SHAPE they all share, so each drifted
# into its own spelling. The canonical pattern is:
#
#   1. `handshake` or the domain's opening call is @0.
#   2. Every method after it takes no authority token: holding the
#      session reference IS the authority (R3).
#   3. Observation returns a SUBSCRIPTION REFERENCE, never an id: the
#      caller holds `XSubscription`, pulls with a stated bound, and
#      cancels it. There is no subscription id parameter anywhere.
#   4. Every event union terminates with `unknown @N :T.UnknownEvent`.
#   5. The session reports state; it never dictates mechanism (idle
#      detection, lock animation, credential storage are all backend).
#
# This file is the reference implementation of that pattern, and every
# session-shaped interface in the protocol is expected to match it.
#
# ── WHAT WAS DELETED, AND WHY ──────────────────────────────────────────
#
#   * the device-class feature block: `SpatialSessionInfo` (AR/VR),
#     `WatchGlanceSession` (wearables), `VoiceSessionInfo` (voice-only),
#     `SessionRecording`, `MultiDeviceSession`, `HandoffRequest` /
#     `SessionHandoff` / `ConflictResolution` — today's device classes
#     frozen into an eternal contract. A 2046 session (a room-scale
#     holographic one, an agent's with no user at all) has no fields for
#     them, and every backend had to stub the accessors even when no such
#     device exists. Device-specific work belongs in device-specific
#     schemas, composed at the shell.
#   * `SessionAccessControl { allowedUsers, deniedUsers, public, … }` —
#     an allow/deny ACL. "Do NOT define permission strings, boolean
#     flags, or role-based access control in the protocol. The capability
#     system IS the access control mechanism"
#     (DESIGN_PRINCIPLES.md:399). A user granted by capability and denied
#     by ACL had undefined authority.
#   * `SessionTemplate` + `applyTemplate` / `getTemplates` — a template
#     registry duplicating manifest-style self-description.
#   * `SessionAccessibilitySettings`, `SessionPowerSettings`,
#     `SessionNetworkConfig` — settings that belong to accessibility.capnp,
#     power.capnp and network.capnp. A session contract that re-declares
#     them must be kept in agreement with all three forever.
#   * `trustLevel :UInt32` — a hand-rolled 0-100 scale where the
#     canonical `T.TrustLevel` exists.
#   * `Text` identities (`SessionHandoff.id`, `templateId`) where typed
#     ids exist.
#
# ── CREDENTIALS ────────────────────────────────────────────────────────
#
# `Session` is the canonical user-session contract and canonical
# user-identity home. `UnlockCredential` — the authority carrier a caller
# presents to unlock a session — is imported from screenlock.capnp, which
# owns it (single definition, no duplicate).
#
# `unlock` failure semantics are stated rather than invented: after
# `maxAttempts` consecutive failures within `attemptWindow`, the session
# enters `locked` with `lockoutRemaining` set, and further attempts are
# refused without evaluation until the window elapses. A backend that
# cannot count attempts reports `attemptsKnown = false`.
#
# The credential AND the result are `screenlock.capnp`'s — the lock
# domain owns both, so the two schemas cannot disagree about what a
# refusal or a lockout looks like.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using Screenlock = import "screenlock.capnp";

# The canonical session handshake: the opening call of a session-shaped
# interface. It establishes identity and reports what the backend will
# do, before any privileged operation is possible.
interface Session {
    # --- the session lifecycle (the Service Session pattern) ---
    # Lock the session. Idempotent: locking a locked session succeeds.
    lock @0 () -> T.VoidResult;

    # Unlock the session by presenting a credential. `outcome` says
    # whether the credential was accepted, refused, or not evaluated
    # because the session is in lockout — three different answers the
    # pre-revamp T.VoidResult collapsed into one.
    unlock @1 (credential :Screenlock.UnlockCredential) -> (result :Screenlock.UnlockResult);

    # Current session state, including lockout information.
    getState @2 () -> (state :SessionState);

    # --- idle ---
    # How long the session has been idle.
    idleTime @3 () -> (idleTime :T.Duration);
    # Configure the idle threshold at which the session locks.
    setIdleTimeout @4 (timeout :T.Duration) -> T.VoidResult;
    # Both facts in one call: whether the session is idle, and for how
    # long. (The pre-revamp file had `idleTime` and `getIdleState` as two
    # methods answering overlapping questions.)
    getIdleState @5 () -> (idle :Bool, idleTime :T.Duration);

    # --- identity ---
    # The user this session belongs to.
    getUserInfo @6 () -> (user :UserInfo);

    # --- observation ---
    # Holding the returned subscription IS the authority to pull.
    subscribeEvents @7 () -> (subscription :SessionEventSubscription);

    # --- persistence ---
    # Save the session state for restore after a reboot. The blob is
    # opaque to the protocol; a backend MUST record the schema version it
    # wrote, and a restore MUST ignore fields it does not recognise
    # (forward compatibility, TIMELESSNESS.md:5).
    saveSession @8 () -> (handle :T.DataHandle);
    # Restore a previously saved session. Returns the schema version the
    # blob was written with, so a caller can tell whether the restore was
    # complete or partial.
    restoreSession @9 (handle :T.DataHandle) -> (restored :SessionRestore);

    # --- expiration ---
    setExpirationPolicy @10 (policy :SessionExpirationPolicy) -> T.VoidResult;
    getExpirationPolicy @11 () -> (policy :SessionExpirationPolicy);

    # --- security posture ---
    # What the backend observed about how this session was
    # authenticated. Reported, not prescribed.
    getSecurityContext @12 () -> (context :SessionSecurityContext);

    # --- audit ---
    # The session's own audit trail, paginated.
    getSessionAuditTrail @13 (pagination :T.Pagination)
                         -> (entries :List(SessionAuditEntry), total :UInt64);
}

# ── State ───────────────────────────────────────────────────────────────

struct SessionState {
    locked @0 :Bool;
    active @1 :Bool;
    user @2 :UserInfo;
    sessionId @3 :T.SessionId;
    # How the session became locked: user action, idle timeout, expiry,
    # or lockout after failed unlock attempts.
    lockedReason @4 :Text;
    # When the session locked.
    lockedAt @5 :T.Timestamp;
    # Remaining lockout after failed unlock attempts (zero = none).
    lockoutRemaining @6 :T.Duration;
    # Whether the backend counts unlock attempts at all. When false, a
    # consumer must not infer "no failures happened" from a zero count.
    attemptsKnown @7 :Bool;
}

struct UserInfo {
    # T.UserId, not a POSIX uid: a capability system has no uid, and a
    # UInt64 is wide enough for any identity namespace.
    id @0 :T.UserId;
    name @1 :Text;
    # Display name that may differ from the system username. May be empty.
    realName @2 :Text;
}

# ── Events ──────────────────────────────────────────────────────────────

struct SessionEvent {
    id @0 :T.EventId;
    timestamp @1 :T.Timestamp;
    type @2 :SessionEventType;
    # Open payload for the event, backend-declared.
    data @3 :T.StringMap;
}

enum SessionEventType {
    unknown @0;
    unlock @1;
    lock @2;
    sleep @3;
    wake @4;
    disconnect @5;
    reconnect @6;
    switchUser @7;
    idle @8;
    active @9;
    expired @10;
    securityChanged @11;
    custom @12;
}

interface SessionEventSubscription {
    # Bounded pull: the caller states how many events it will take.
    pull @0 (maxEvents :UInt32) -> (events :List(SessionEvent), total :UInt32);
    cancel @1 () -> T.VoidResult;
}

# ── Persistence ─────────────────────────────────────────────────────────

struct SessionRestore {
    sessionId @0 :T.SessionId;
    # Schema version the blob was written with.
    blobVersion @1 :T.Version;
    # Fields the backend could not restore, as open names. A non-empty
    # list means the restore was partial, and the caller can say so
    # instead of assuming completeness.
    unrestored @2 :List(Text);
    error @3 :T.Error;
    metadata @4 :T.StringMap;
}

struct SessionExpirationPolicy {
    # Maximum session lifetime (zero = no limit).
    maxLifetime @0 :T.Duration;
    # Inactivity timeout (zero = no timeout).
    inactivityTimeout @1 :T.Duration;
    # Whether to warn before expiration, and how long before.
    warnBeforeExpiration @2 :Bool;
    warningDuration @3 :T.Duration;
    # Whether to auto-extend on user activity.
    autoExtend @4 :Bool;
}

# ── Security posture ────────────────────────────────────────────────────

struct SessionSecurityContext {
    # Whether multi-factor authentication was used.
    mfaRequired @0 :Bool;
    # Canonical trust level, not a hand-rolled 0-100 scale.
    trustLevel @1 :T.TrustLevel;
    # Risk score (0.0 = no risk, 1.0 = high risk), as the backend
    # assesses it. Opaque: the protocol never says how.
    riskScore @2 :Float32;
    # Whether biometric verification was used.
    biometricVerified @3 :Bool;
    # Authentication methods used in this session, as open tokens.
    authMethods @4 :List(Text);
    # Attestation proof, if the backend has one — opaque bytes, backend
    # format. The pre-revamp `attested :Bool` answered "attested by whom,
    # to what root?" with a boolean and no proof.
    attestation @5 :Data;
    metadata @6 :T.StringMap;
}

# ── Audit ───────────────────────────────────────────────────────────────

struct SessionAuditEntry {
    auditId @0 :UInt64;
    timestamp @1 :T.Timestamp;
    sessionId @2 :T.SessionId;
    # Event type as an open token ("lock", "unlock", "switchUser", …).
    eventType @3 :Text;
    # Who performed the action.
    actor @4 :T.UserId;
    description @5 :Text;
    metadata @6 :T.StringMap;
}

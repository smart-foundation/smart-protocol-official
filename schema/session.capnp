@0xa1b2c3d4e5f6000d;

using T = import "types.capnp";
using Screenlock = import "screenlock.capnp";

# ══════════════════════════════════════════════════════════════════════
# Session — user session lifecycle, authentication, idle management.
#
# This schema owns user session lifecycle and identity (UserInfo).
# screenlock.capnp owns lock screen credentials (UnlockCredential).
# UnlockCredential is imported from screenlock.capnp.
#
# Improvements beyond the original schema:
#   - unlock uses Screenlock.UnlockCredential union (was local duplicate).
#   - idleTime returns T.Duration (was raw UInt64 ms).
#   - setIdleTimeout takes T.Duration (was raw UInt64 timeoutMs).
#   - UserInfo.id uses T.UserId (was raw UInt32 POSIX UID).
#   - Removed POSIX-specific UserInfo.homeDir and UserInfo.shell.
#   - SessionEventSubscription has cancel method.
#   - SessionEventType has custom variant for forward compatibility.
#   - pullEvents @6 is deprecated: use SessionEventSubscription.pull instead.
#   - SessionEventSubscription.pull accepts T.Pagination (audit-4).
#
# Improvements (audit-7):
#   - SessionHandoff for cross-device session migration (Continuity).
#   - MultiDeviceSession for sessions spanning multiple devices.
#   - SpatialSessionInfo for AR/VR spatial sessions.
#   - WatchGlanceSession for ultra-short wearable sessions.
#   - VoiceSessionInfo for voice-only sessions (no display).
#   - SessionRecording for session capture and replay.
#   - SessionSecurityContext for session-level security state.
#   - Session persistence for resume after reboot.
# ══════════════════════════════════════════════════════════════════════

interface Session {
    lock   @0 () -> T.VoidResult;
    unlock @1 (credential :Screenlock.UnlockCredential) -> T.VoidResult;
    getState @2 () -> (state :SessionState);

    idleTime      @3 () -> (idleTime :T.Duration);
    setIdleTimeout @4 (timeout :T.Duration) -> T.VoidResult;

    subscribeEvents @5 () -> (subscription :SessionEventSubscription);
    # DEPRECATED: Use SessionEventSubscription.pull instead.
    # Pull exists on the subscription interface per Rule 7 (pull+cancel on subscription).
    pullEvents @6 (subscription :SessionEventSubscription) -> (events :List(SessionEvent));

    # Query user information for the current session.
    getUserInfo @7 () -> (user :UserInfo);

    # Query session idle state: whether the session is idle and for how long.
    getIdleState @8 () -> (idle :Bool, duration :T.Duration);

    # ── Audit-7 additions ────────────────────────────────────

    # Initiate cross-device session handoff (Continuity).
    startHandoff @9 (request :HandoffRequest) -> (handoff :SessionHandoff);

    # Accept a session handoff from another device.
    acceptHandoff @10 (handoffId :Text, state :Data) -> T.VoidResult;

    # Get multi-device session state.
    getMultiDeviceSession @11 () -> (session :MultiDeviceSession);

    # Get AR/VR spatial session info.
    getSpatialInfo @12 () -> (info :SpatialSessionInfo);

    # Get wearable glance session info.
    getWatchInfo @13 () -> (info :WatchGlanceSession);

    # Get voice-only session info.
    getVoiceInfo @14 () -> (info :VoiceSessionInfo);

    # Start session recording for debugging/replay.
    startRecording @15 () -> T.VoidResult;

    # Stop session recording.
    stopRecording @16 () -> (recording :SessionRecording);

    # Get session security context.
    getSecurityContext @17 () -> (context :SessionSecurityContext);

    # ── Session persistence (audit-7) ────────────────────────
    # Save session state for persistence across reboots.
    saveSession @18 () -> (handle :T.DataHandle);

    # Restore a previously saved session state.
    restoreSession @19 (handle :T.DataHandle) -> T.VoidResult;

    # ── Audit-9 additions ────────────────────────────────────────

    # Resolve conflict when two devices modify the same session state.
    resolveConflict @20 (sessionId :T.SessionId, resolution :ConflictResolution) -> T.VoidResult;

    # Get access control list for a session.
    getSessionAccessControl @21 () -> (acl :SessionAccessControl);

    # Update access control for a session.
    setSessionAccessControl @22 (acl :SessionAccessControl) -> T.VoidResult;

    # Get the audit trail for session events.
    getSessionAuditTrail @23 (pagination :T.Pagination) -> (entries :List(SessionAuditEntry), total :UInt32);

    # Configure session expiration policy.
    setExpirationPolicy @24 (policy :SessionExpirationPolicy) -> T.VoidResult;

    # Get session expiration policy.
    getExpirationPolicy @25 () -> (policy :SessionExpirationPolicy);

    # Apply a session template (pre-configured session type).
    applyTemplate @26 (templateId :Text) -> T.VoidResult;

    # Get available session templates.
    getTemplates @27 () -> (templates :List(SessionTemplate));

    # Get session-level accessibility settings.
    getAccessibilitySettings @28 () -> (settings :SessionAccessibilitySettings);

    # Set session-level accessibility settings.
    setAccessibilitySettings @29 (settings :SessionAccessibilitySettings) -> T.VoidResult;

    # Get session-aware power management settings.
    getPowerSettings @30 () -> (settings :SessionPowerSettings);

    # Set session-aware power management settings.
    setPowerSettings @31 (settings :SessionPowerSettings) -> T.VoidResult;

    # Get session networking configuration.
    getNetworkConfig @32 () -> (config :SessionNetworkConfig);

    # Set session networking configuration.
    setNetworkConfig @33 (config :SessionNetworkConfig) -> T.VoidResult;
}

interface SessionEventSubscription {
    pull   @0 (pagination :T.Pagination) -> (events :List(SessionEvent), total :UInt32);
    cancel @1 () -> T.VoidResult;
}

# ── Session State ─────────────────────────────────────────────

struct SessionState {
    locked    @0 :Bool;
    active    @1 :Bool;
    user      @2 :UserInfo;
    sessionId @3 :T.SessionId;
}

struct UserInfo {
    id        @0 :T.UserId;
    name      @1 :Text;
    # Display name that may differ from the system username.
    # In some systems, this may be empty or identical to name.
    realName  @2 :Text;
}

# ── Events ───────────────────────────────────────────────────

struct SessionEvent {
    id        @0 :T.EventId;
    timestamp @1 :T.Timestamp;
    type      @2 :SessionEventType;
}

enum SessionEventType {
    unlock     @0;
    lock       @1;
    sleep      @2;
    wake       @3;
    disconnect @4;
    reconnect  @5;
    switchUser @6;
    idle       @7;
    active     @8;
    # Audit-9: conflict detected, expired, access changed, etc.
    conflictDetected @10;
    expired @11;
    accessChanged @12;
    custom     @9;
}

# ── Cross-Device Handoff (audit-7) ───────────────────────────

struct HandoffRequest {
    # Target device identifier.
    targetDevice @0 :Text;
    # Session state to transfer (serialized).
    state @1 :Data;
    # Maximum time to wait for acceptance.
    timeout @2 :T.Duration;
}

struct SessionHandoff {
    # Unique handoff identifier.
    id @0 :Text;
    # Source device.
    sourceDevice @1 :Text;
    # Target device.
    targetDevice @2 :Text;
    # Current handoff state.
    state @3 :HandoffState;
    # Transfer progress (0-100).
    progress @4 :UInt32;
    # When the handoff was initiated.
    initiatedAt @5 :T.Timestamp;
    # When the handoff completed (zero if still in progress).
    transferredAt @6 :T.Timestamp;
}

enum HandoffState {
    pending @0;
    transferring @1;
    completed @2;
    failed @3;
    custom @4;
}

# ── Multi-Device Session (audit-7) ───────────────────────────

struct MultiDeviceSession {
    # Session identifier.
    sessionId @0 :T.SessionId;
    # Devices participating in this session.
    devices @1 :List(MultiDeviceEntry);
    # The device currently in control.
    primaryDevice @2 :Text;
    # Whether all devices are synchronized.
    synchronized @3 :Bool;
}

struct MultiDeviceEntry {
    # Device identifier.
    device @0 :Text;
    # Device type (e.g., "phone", "laptop", "tablet", "watch").
    type @1 :Text;
    # Whether this device is currently connected.
    connected @2 :Bool;
    # When this device last synced.
    lastSynced @3 :T.Timestamp;
}

# ── AR/VR Spatial Session (audit-7) ──────────────────────────

struct SpatialSessionInfo {
    # Number of spatial anchors placed.
    anchorsCount @0 :UInt32;
    # Whether occlusion is enabled.
    occlusionEnabled @1 :Bool;
    # Whether passthrough (camera feed) is enabled.
    passthroughEnabled @2 :Bool;
    # Whether hand gesture input is enabled.
    gestureEnabled @3 :Bool;
    # Whether spatial mesh reconstruction is enabled.
    spatialMeshEnabled @4 :Bool;
    # Display configuration for the spatial session.
    displayConfig @5 :T.DisplayConfiguration;
}

# ── Wearable Glance Session (audit-7) ────────────────────────

struct WatchGlanceSession {
    # Total glance duration.
    duration @0 :T.Duration;
    # Number of glances in this session.
    glanceCount @1 :UInt32;
    # When the last glance was dismissed.
    dismissedAt @2 :T.Timestamp;
    # Whether the watch is in ambient/always-on mode.
    ambientMode @3 :Bool;
}

# ── Voice-Only Session (audit-7) ─────────────────────────────

struct VoiceSessionInfo {
    # Session language (BCP 47 tag).
    language @0 :Text;
    # Whether the wake word was detected.
    wakeWordDetected @1 :Bool;
    # Ambient noise level (0.0 = silent, 1.0 = very loud).
    noiseLevel @2 :Float32;
    # Whether far-field mode is active (far from microphone).
    farField @3 :Bool;
    # Current speech recognition state.
    recognitionState @4 :SpeechRecognitionState;
}

enum SpeechRecognitionState {
    idle @0;
    listening @1;
    processing @2;
    speaking @3;
    custom @4;
}

# ── Session Recording (audit-7) ──────────────────────────────

struct SessionRecording {
    # Session that was recorded.
    sessionId @0 :T.SessionId;
    # When the recording started.
    startedAt @1 :T.Timestamp;
    # Total recording duration.
    duration @2 :T.Duration;
    # Recording size in bytes.
    sizeBytes @3 :UInt64;
    # Recording format (e.g., "json", "protobuf", "binary").
    format @4 :Text;
}

# ── Session Security Context (audit-7) ───────────────────────

struct SessionSecurityContext {
    # Whether multi-factor authentication was used.
    mfaRequired @0 :Bool;
    # Trust level of the session (0 = untrusted, 100 = fully trusted).
    trustLevel @1 :UInt32;
    # Risk score (0.0 = no risk, 1.0 = high risk).
    riskScore @2 :Float32;
    # Whether the session has been attested (cryptographic proof of integrity).
    attested @3 :Bool;
    # Whether biometric verification was used.
    biometricVerified @4 :Bool;
    # Authentication methods used in this session.
    authMethods @5 :List(Text);
}

# ══════════════════════════════════════════════════════════════════════
# AUDIT-9 ADDITIONS — Conflict Resolution, Access Control, Audit, etc.
# ══════════════════════════════════════════════════════════════════════

# ── Conflict Resolution (audit-9) ───────────────────────────

struct ConflictResolution {
    # Which device's state to keep (source or target).
    winningDevice @0 :Text;
    # Strategy for merging non-conflicting fields.
    mergeStrategy @1 :ConflictMergeStrategy;
    # Whether to notify the user of the conflict.
    notifyUser @2 :Bool;
    # Human-readable resolution description.
    description @3 :Text;
}

enum ConflictMergeStrategy {
    keepSource @0;      # Keep the source device's state
    keepTarget @1;      # Keep the target device's state
    mergeFields @2;     # Merge non-conflicting fields, keep source for conflicts
    prompt @3;          # Prompt the user to resolve
    custom @4;
}

# ── Session Access Control (audit-9) ────────────────────────

struct SessionAccessControl {
    # Users allowed to join this session.
    allowedUsers @0 :List(T.UserId);
    # Users explicitly denied from this session.
    deniedUsers @1 :List(T.UserId);
    # Whether the session is publicly joinable.
    public @2 :Bool;
    # Maximum number of concurrent participants.
    maxParticipants @3 :UInt32;
    # Whether to require approval for new participants.
    requireApproval @4 :Bool;
}

# ── Session Audit Trail (audit-9) ───────────────────────────

struct SessionAuditEntry {
    # Unique audit identifier.
    auditId @0 :UInt64;
    # When the event occurred.
    timestamp @1 :T.Timestamp;
    # Session identifier.
    sessionId @2 :T.SessionId;
    # Type of event (join, leave, modify, conflict, etc.).
    eventType @3 :Text;
    # Who performed the action.
    actor @4 :T.UserId;
    # Description of the event.
    description @5 :Text;
    # Event-specific metadata.
    metadata @6 :T.StringMap;
}

# ── Session Expiration Policy (audit-9) ─────────────────────

struct SessionExpirationPolicy {
    # Maximum session lifetime (zero = no limit).
    maxLifetime @0 :T.Duration;
    # Inactivity timeout (zero = no timeout).
    inactivityTimeout @1 :T.Duration;
    # Whether to warn before expiration.
    warnBeforeExpiration @2 :Bool;
    # Warning lead time.
    warningDuration @3 :T.Duration;
    # Whether to auto-extend on user activity.
    autoExtend @4 :Bool;
}

# ── Session Template (audit-9) ──────────────────────────────

struct SessionTemplate {
    # Template identifier.
    templateId @0 :Text;
    # Human-readable template name.
    name @1 :Text;
    # Description of the session type.
    description @2 :Text;
    # Default security settings for this template.
    securityContext @3 :SessionSecurityContext;
    # Default expiration policy.
    expirationPolicy @4 :SessionExpirationPolicy;
    # Default access control.
    accessControl @5 :SessionAccessControl;
}

# ── Session Accessibility (audit-9) ─────────────────────────

struct SessionAccessibilitySettings {
    # Screen reader verbosity level.
    screenReaderVerbosity @0 :Text;
    # Whether to enable high-contrast mode for session UI.
    highContrast @1 :Bool;
    # Whether to enable reduced motion animations.
    reducedMotion @2 :Bool;
    # Keyboard navigation mode.
    keyboardNavigation @3 :Text;
    # Caption language for audio content.
    captionLanguage @4 :Text;
    # Whether captions are enabled.
    captionsEnabled @5 :Bool;
}

# ── Session Power Management (audit-9) ──────────────────────

struct SessionPowerSettings {
    # Whether to allow the session to prevent system sleep.
    preventSleep @0 :Bool;
    # Maximum CPU usage allowed for this session (percent, 0-100).
    maxCpuPercent @1 :UInt32;
    # Whether to enable background processing.
    backgroundProcessing @2 :Bool;
    # Power saving mode for this session.
    powerSavingMode @3 :Text;
}

# ── Session Networking (audit-9) ────────────────────────────

struct SessionNetworkConfig {
    # Whether the session requires a network connection.
    requireNetwork @0 :Bool;
    # Allowed network interfaces (e.g., "wifi", "cellular", "ethernet").
    allowedInterfaces @1 :List(Text);
    # Whether to prefer low-latency connections.
    preferLowLatency @2 :Bool;
    # Maximum bandwidth limit (bytes per second, 0 = unlimited).
    maxBandwidth @3 :UInt64;
    # Whether to enable offline mode.
    offlineMode @4 :Bool;
}

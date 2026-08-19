@0xa1b2c3d4e5f60033;

using T = import "types.capnp";

# ══════════════════════════════════════════════════════════════════════
# Screen Lock — device lock screen, idle management, lock/unlock lifecycle.
#
# This schema is the canonical source for lock screen credentials
# (UnlockCredential). session.capnp imports UnlockCredential from here.
#
# Improvements beyond the original schema:
#   - All duration fields now use T.Duration (was raw UInt64 ms).
#   - applicationId uses T.AppId (was raw Text).
#   - UnlockCredential is the canonical credential union.
#   - IdleChangedEvent uses T.Duration (was raw UInt64 ms).
#   - HandshakeResult has custom variant for forward compatibility.
#   - UnlockResult has custom variant for forward compatibility.
#   - UnlockResult.failedError uses T.Error (audit-3, replaces raw UInt32).
#   - UnlockResult.lockedOutDuration uses T.Duration (audit-3, replaces raw UInt32).
#   - All enums have forward-compatibility escape hatches.
#
# Audit-7 improvements:
#   - UnlockCredential extended: pattern, face, voice, presence, nfc, duress.
#   - Session methods: addLockScreenWidget, removeLockScreenWidget, listLockScreenWidgets,
#     setSecurityPolicy, getSecurityPolicy, reportHostileEnvironment,
#     setBiometricStepUp, getBiometricStepUp, reportWearablePresence,
#     addLockScreenNotification, removeLockScreenNotification.
#   - LockScreenWidget for lock screen customization.
#   - LockSecurityPolicy for max attempts, lockout, pattern complexity.
#   - HostileEnvironmentSignal for theft detection.
#   - DuressCredential for coercion protection.
#   - BiometricStepUp for multi-factor unlock flows.
#   - LockScreenNotification for lock screen notification display.
#   - WearablePresence for proximity-based unlock.
# ══════════════════════════════════════════════════════════════════════

interface Session {

    struct HandshakeRequest {
        applicationId @0 :T.AppId;
        version       @1 :T.Version;
        metadata      @2 :List(T.Meta);
    }

    struct HandshakeResponse {
        sessionId @0 :T.SessionId;
        result    @1 :HandshakeResult;
    }

    enum HandshakeResult {
        accepted @0;
        rejected @1;
        custom   @2;
    }

    handshake @0 (request :HandshakeRequest)
               -> (response :HandshakeResponse);

    # -- System Side --

    lock            @1 () -> (result :T.VoidResult);
    unlock          @2 (credential :UnlockCredential) -> (result :UnlockResult);
    isLocked        @3 () -> (locked :Bool);

    # -- Lock Screen App --

    registerLockScreen @4 (surface :T.SurfaceId)
                        -> (result :T.VoidResult);

    # -- Idle --

    getIdleTime     @5 () -> (idleTime :T.Duration);
    setIdlePolicy   @6 (policy :IdlePolicy) -> (result :T.VoidResult);
    inhibitIdle     @7 (reason :Text) -> (handle :T.InhibitHandle);
    uninhibitIdle   @8 (handle :T.InhibitHandle) -> (result :T.VoidResult);

    # -- Events --

    subscribe       @9 () -> (stream :LockEventStream);

    # -- Audit-7 additions: Lock screen customization --

    addLockScreenWidget @10 (widget :LockScreenWidget) -> T.VoidResult;
    removeLockScreenWidget @11 (widgetId :Text) -> T.VoidResult;
    listLockScreenWidgets @12 () -> (widgets :List(LockScreenWidget));

    # -- Audit-7 additions: Security policy --
    setSecurityPolicy @13 (policy :LockSecurityPolicy) -> T.VoidResult;
    getSecurityPolicy @14 () -> (policy :LockSecurityPolicy);

    # -- Audit-7 additions: Hostile environment detection --
    reportHostileEnvironment @15 (signal :HostileEnvironmentSignal) -> T.VoidResult;

    # -- Audit-7 additions: Biometric step-up --
    setBiometricStepUp @16 (stepUp :BiometricStepUp) -> T.VoidResult;
    getBiometricStepUp @17 () -> (stepUp :BiometricStepUp);

    # -- Audit-7 additions: Wearable presence --
    reportWearablePresence @18 (presence :WearablePresence) -> T.VoidResult;

    # -- Audit-7 additions: Lock screen notifications --
    addLockScreenNotification @19 (notification :LockScreenNotification) -> T.VoidResult;
    removeLockScreenNotification @20 (appId :T.AppId) -> T.VoidResult;

    # -- Audit-9 additions: Pattern lock configuration --

    # Configure Android-style pattern lock (swipe on 3x3 grid).
    setPatternLock @21 (pattern :PatternLockConfig) -> T.VoidResult;

    # Get pattern lock configuration.
    getPatternLockConfig @22 () -> (config :PatternLockConfig);

    # -- Audit-9 additions: Face unlock configuration --

    # Configure face unlock attention/mask detection.
    setFaceUnlockConfig @23 (config :FaceUnlockConfig) -> T.VoidResult;

    # Get face unlock configuration.
    getFaceUnlockConfig @24 () -> (config :FaceUnlockConfig);

    # -- Audit-9 additions: Voice match configuration --

    # Configure voice match unlock with liveness detection.
    setVoiceMatchConfig @25 (config :VoiceMatchConfig) -> T.VoidResult;

    # Get voice match configuration.
    getVoiceMatchConfig @26 () -> (config :VoiceMatchConfig);

    # -- Audit-9 additions: Trusted device proximity unlock --

    # Configure Bluetooth/NFC proximity unlock.
    setTrustedDeviceConfig @27 (config :TrustedDeviceConfig) -> T.VoidResult;

    # Get trusted device proximity unlock configuration.
    getTrustedDeviceConfig @28 () -> (config :TrustedDeviceConfig);
}

# ── Credentials ───────────────────────────────────────────────

struct UnlockCredential {
    union {
        password  @0 :Text;
        pin       @1 :Text;
        biometric @2 :Void;
        custom    @3 :Text;
        # Audit-7 additions: new unlock methods.
        pattern   @4 :Text;
        face      @5 :Void;
        voice     @6 :Void;
        presence  @7 :Void;
        nfc       @8 :Void;
        duress    @9 :DuressCredential;
    }
}

# ── Unlock Result ─────────────────────────────────────────────
# The failed @1 and lockedOut @2 variants use raw types for
# backward compatibility. New code should prefer failedError @4
# and lockedOutDuration @5 which use proper T.Error and T.Duration.

struct UnlockResult {
    union {
        success   @0 :Void;
        # DEPRECATED: Use failedError instead. Raw error code from auth backend.
        failed    @1 :UInt32;
        # DEPRECATED: Use lockedOutDuration instead. Seconds until lockout expires (0 if none).
        lockedOut @2 :UInt32;
        custom    @3 :Text;
        # Typed error from the authentication backend (preferred over failed @1).
        failedError @4 :T.Error;
        # Duration until lockout expires (preferred over lockedOut @2).
        # Zero duration means no active lockout.
        lockedOutDuration @5 :T.Duration;
    }
}

# ── Idle Policy ───────────────────────────────────────────────

struct IdlePolicy {
    idleTimeout    @0 :T.Duration;
    lockOnIdle     @1 :Bool;
    lockDelay      @2 :T.Duration;
    suspendOnIdle  @3 :Bool;
    suspendTimeout @4 :T.Duration;
}

# ── Events ────────────────────────────────────────────────────

interface LockEventStream {
    next   @0 () -> (event :LockEvent);
    cancel @1 () -> T.VoidResult;
}

struct LockEvent {
    union {
        locked      @0 :Void;
        unlocked    @1 :Void;
        dimming     @2 :Void;
        idleChanged @3 :IdleChangedEvent;
        custom      @4 :CustomLockEvent;
    }
}

struct IdleChangedEvent {
    idle     @0 :Bool;
    duration @1 :T.Duration;
}

struct CustomLockEvent {
    typeId  @0 :UInt64;
    payload @1 :Data;
}

# ══════════════════════════════════════════════════════════════════════
# AUDIT-7 ADDITIONS — Widgets, Security, Hostile Environment, Step-Up, Presence
# ══════════════════════════════════════════════════════════════════════

# ── Lock Screen Widget ──
struct LockScreenWidget {
    widgetId @0 :Text;
    position @1 :Text;
    enabled @2 :Bool;
    permissions @3 :List(Text);
}

# ── Lock Security Policy ──
struct LockSecurityPolicy {
    maxAttempts @0 :UInt32;
    lockoutDuration @1 :T.Duration;
    requireBiometricForSensitive @2 :Bool;
    patternMinLength @3 :UInt32;
    cooldownPeriod @4 :T.Duration;
}

# ── Hostile Environment Signal ──
struct HostileEnvironmentSignal {
    signalType @0 :Text;
    confidence @1 :Float32;
    timestamp @2 :T.Timestamp;
    triggerSource @3 :Text;
}

# ── Duress Credential ──
struct DuressCredential {
    marker @0 :Bool;
    silentAlert @1 :Bool;
    notifyContact @2 :Bool;
}

# ── Biometric Step-Up ──
struct BiometricStepUp {
    primaryMethod @0 :Text;
    stepUpMethod @1 :Text;
    stepUpTimeout @2 :T.Duration;
    required @3 :Bool;
}

# ── Lock Screen Notification ──
struct LockScreenNotification {
    appId @0 :T.AppId;
    title @1 :Text;
    body @2 :Text;
    priority @3 :UInt32;
    sensitive @4 :Bool;
    visibleOnLock @5 :Bool;
}

# ── Wearable Presence ──
struct WearablePresence {
    deviceType @0 :Text;
    proximity @1 :Bool;
    rssi @2 :Int32;
    trusted @3 :Bool;
}

# ══════════════════════════════════════════════════════════════════════
# AUDIT-9 ADDITIONS — Pattern Lock, Face, Voice, Trusted Device
# ══════════════════════════════════════════════════════════════════════

# ── Pattern Lock Configuration ──
# Android-style pattern lock (3x3 grid of dots).
struct PatternLockConfig {
    # Whether pattern lock is enabled.
    enabled @0 :Bool;
    # Minimum number of dots in a valid pattern.
    minDots @1 :UInt32;
    # Maximum number of dots (typically 9 for 3x3 grid).
    maxDots @2 :UInt32;
    # Whether diagonal connections are allowed.
    allowDiagonal @3 :Bool;
    # Whether to show the pattern trail on entry.
    showTrail @4 :Bool;
    # Pattern hash (hashed value of the dot sequence).
    patternHash @5 :Data;
    # Maximum failed attempts before pattern lockout.
    maxAttempts @6 :UInt32;
}

# ── Face Unlock Configuration ──
# Face unlock with attention detection and mask-aware recognition.
struct FaceUnlockConfig {
    # Whether face unlock is enabled.
    enabled @0 :Bool;
    # Whether attention detection is required (user must be looking at device).
    requireAttention @1 :Bool;
    # Whether mask-aware mode is enabled (3D recognition works with masks).
    maskAware @2 :Bool;
    # Liveness detection method for face unlock.
    livenessMethod @3 :FaceLivenessMethod;
    # Maximum angle of face rotation accepted (degrees, e.g., 30).
    maxRotationDegrees @4 :UInt32;
    # Whether to require eyes open.
    requireEyesOpen @5 :Bool;
    # Timeout for face recognition (ms).
    timeoutMs @6 :UInt32;
}

enum FaceLivenessMethod {
    none @0;           # No liveness check (2D only)
    depthMap @1;       # 3D depth map validation
    infrared @2;       # Infrared liveness detection
    textureAnalysis @3; # Spoofing texture analysis
    blink @4;          # Blink detection
    challenge @5;      # Random challenge-response
    custom @6;
}

# ── Voice Match Configuration ──
# Voice unlock with liveness detection and multi-user support.
struct VoiceMatchConfig {
    # Whether voice match unlock is enabled.
    enabled @0 :Bool;
    # Whether liveness detection is enabled (prevents recorded voice replay).
    livenessDetection @1 :Bool;
    # Number of enrollment phrases required.
    requiredPhrases @2 :UInt32;
    # Whether multi-user voice profiles are supported.
    multiUser @3 :Bool;
    # Match confidence threshold (0.0 = accept all, 1.0 = require perfect match).
    confidenceThreshold @4 :Float32;
    # Maximum noise level for voice recognition (0.0 = silent only, 1.0 = any noise).
    maxNoiseLevel @5 :Float32;
    # Whether far-field mode is supported (far from microphone).
    farFieldSupported @6 :Bool;
    # Timeout for voice recognition (ms).
    timeoutMs @7 :UInt32;
}

# ── Trusted Device Configuration ──
# Bluetooth/NFC proximity unlock with trusted devices.
struct TrustedDeviceConfig {
    # Whether proximity unlock is enabled.
    enabled @0 :Bool;
    # Trusted Bluetooth devices (list of MAC addresses or device IDs).
    trustedBluetoothDevices @1 :List(TrustedDeviceEntry);
    # Trusted NFC tags.
    trustedNfcTags @2 :List(TrustedDeviceEntry);
    # Maximum RSSI for proximity detection (stronger signal = closer).
    maxRssi @3 :Int32;
    # Timeout after the trusted device goes out of range before locking (seconds).
    lockDelaySeconds @4 :UInt32;
    # Whether to require the trusted device to be authenticated.
    requireDeviceAuth @5 :Bool;
}

struct TrustedDeviceEntry {
    # Device identifier (MAC address for Bluetooth, tag ID for NFC).
    deviceId @0 :Text;
    # Human-readable label ("Work laptop", "Car Bluetooth").
    label @1 :Text;
    # Device type.
    deviceType @2 :TrustedDeviceType;
    # When this device was added as trusted.
    addedAt @3 :T.Timestamp;
    # Whether this device is currently active.
    active @4 :Bool;
}

enum TrustedDeviceType {
    bluetooth @0;
    nfc @1;
    uwb @2;          # Ultra-wideband (precise ranging)
    wifi @3;         # Wi-Fi aware / hotspot
    custom @4;
}

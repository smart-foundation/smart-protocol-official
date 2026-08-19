@0xa1b2c3d4e5f60054;

# ═══════════════════════════════════════════════════════════════════════
# Biometric - fingerprint, face, iris, voice, and multi-modal auth.
#
# This schema handles biometric hardware interaction: sensor enumeration,
# template enrollment, authentication, and crypto-binding. Auth
# orchestration lives in auth.capnp; this schema provides the biometric
# capability.
#
# All IDs are typed (T.BiometricId). All durations use T.Duration.
# All errors use T.Error. All timestamps use T.Timestamp.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ── Modality ─────────────────────────────────────────────────────────────

enum BiometricModality {
    fingerprint @0;
    face @1;
    iris @2;
    voice @3;
    # Audit-7 additions: emerging biometric modalities
    gesture @5;       # Behavioral biometric (typing, walking patterns)
    vein @6;          # Palm/finger vein pattern
    retina @7;        # Retinal scan
    gait @8;          # Walking pattern recognition
    keystroke @9;     # Typing pattern biometric
    ear @10;          # Ear shape biometric
    custom @4;
}

# ── Hardware Info ─────────────────────────────────────────────────────────

struct BiometricHardware {
    id @0 :T.BiometricId;
    modality @1 :BiometricModality;
    name @2 :Text;
    securityLevel @3 :SecurityLevel;
    maxTemplates @4 :UInt32;
    falseAcceptRate @5 :Float32;
    falseRejectRate @6 :Float32;
    # Audit-7: typed sensor location replacing bare Text.
    location @7 :SensorLocation;
    # Audit-7: typed sensor subtype replacing bare Text.
    sensorType @8 :SensorSubtype;
    # Whether the sensor can detect liveness.
    livenessDetection @9 :Bool;
    # Hardware revision.
    revision @10 :Text;
    # Audit-7: hardware health monitoring.
    health @11 :BiometricHealth;
}

# Audit-7: typed sensor locations replacing bare Text.
enum SensorLocation {
    display @0;           # Under-display sensor (fingerprint)
    sideButton @1;        # Side-mounted sensor
    rearCamera @2;        # Rear camera (face recognition)
    frontCamera @3;       # Front camera (face recognition)
    topEdge @4;           # Top-mounted sensor
    bottomEdge @5;        # Bottom-mounted sensor
    underDisplay @6;      # Under-display optical sensor
    externalUsb @7;       # External USB biometric device
    wearable @8;          # Wearable device sensor
    custom @9;
}

# Audit-7: typed sensor subtypes replacing bare Text.
enum SensorSubtype {
    optical @0;           # Optical sensor (under-display fingerprint)
    capacitive @1;        # Capacitive sensor (traditional fingerprint)
    ultrasonic @2;        # Ultrasonic sensor (under-display fingerprint)
    tof @3;               # Time-of-flight sensor (depth sensing)
    iris @4;              # Iris scanner
    camera @5;            # Camera-based sensor (face recognition)
    microphone @6;        # Microphone-based sensor (voice biometric)
    pressure @7;          # Pressure-sensitive sensor
    thermal @8;           # Thermal imaging sensor
    radar @9;             # Radar sensor (gesture recognition)
    lidar @10;            # LiDAR sensor (3D scanning)
    custom @11;
}

enum SecurityLevel {
    weak @0;
    balanced @1;
    strong @2;
    custom @3;
}

# ── Availability ─────────────────────────────────────────────────────────

struct BiometricAvailability {
    available @0 :Bool;
    hardware @1 :List(BiometricHardware);
    enrolledCount @2 :UInt32;
    isEnrolled @3 :Bool;
    hardwarePresent @4 :Bool;
    error @5 :T.Error;
    # Current failed attempts across all modalities.
    failedAttempts @6 :UInt32;
    # Lockout state (when failedAttempts >= max).
    lockout @7 :LockoutInfo;
    # Whether biometric is currently locked out.
    isLockedOut @8 :Bool;
}

struct LockoutInfo {
    # Remaining attempts before lockout (0 = locked out).
    remainingAttempts @0 :UInt32;
    # When the current lockout expires (if timed).
    lockoutExpiresAt @1 :T.Timestamp;
    # Total failed attempts in this streak.
    failedAttemptCount @2 :UInt32;
    # Type of lockout.
    kind @3 :LockoutKind;
}

enum LockoutKind {
    none @0;
    permanent @1;
    timed @2;
    temporary @3;
    custom @4;
}

# ── Authentication ───────────────────────────────────────────────────────

struct AuthPrompt {
    title @0 :Text;
    subtitle @1 :Text;
    negativeButtonText @2 :Text;
    allowedModalities @3 :List(BiometricModality);
    requireConfirmation @4 :Bool;
    allowDeviceCredential @5 :Bool;
    timeout @6 :T.Duration;
    # Require a specific template ID (for app-specific auth).
    templateId @7 :T.BiometricId;
    # Crypto-binding: challenge to sign into the token.
    challenge @8 :Data;
    # Audit-7: per-app auth configuration.
    authConfig @9 :BiometricAuthConfig;
    # Audit-7: multi-modal authentication requirements.
    multiModal @10 :MultiModalAuth;
}

# Audit-7: per-app biometric authentication configuration.
struct BiometricAuthConfig {
    # Modalities allowed for this authentication.
    allowedModalities @0 :List(BiometricModality);
    # Whether user confirmation is required after biometric match.
    requireConfirmation @1 :Bool;
    # Whether device credential (PIN/pattern) can be used as fallback.
    allowDeviceCredential @2 :Bool;
    # Authentication timeout.
    timeout @3 :T.Duration;
    # Challenge for crypto-binding.
    challenge @4 :Data;
    # Maximum number of attempts before lockout.
    maxAttempts @5 :UInt32;
}

# Audit-7: multi-modal authentication (N-of-M policy).
struct MultiModalAuth {
    # Required modalities (all must succeed).
    requiredModalities @0 :List(BiometricModality);
    # Combine strategy: all must pass, any must pass, best quality wins.
    combineStrategy @1 :MultiModalStrategy;
    # Timeout for the multi-modal challenge.
    timeout @2 :T.Duration;
    # Number of modalities that must succeed (for anyOf strategy).
    requiredCount @3 :UInt32;
}

enum MultiModalStrategy {
    all @0;     # All required modalities must succeed
    any @1;     # Any one of the required modalities must succeed
    best @2;    # Best quality match wins
    custom @3;
}

# Audit-7: hardware health monitoring.
struct BiometricHealth {
    # Whether the sensor is functioning normally.
    sensorOk @0 :Bool;
    # When the sensor was last calibrated.
    lastCalibration @1 :T.Timestamp;
    # When the next calibration is due (null = not scheduled).
    calibrationDue @2 :T.Timestamp;
    # False accept rate (lower = more secure).
    falseAcceptRate @3 :Float32;
    # False reject rate (lower = more convenient).
    falseRejectRate @4 :Float32;
    # Total number of sensor failures.
    failureCount @5 :UInt32;
    # Last error message (if any).
    lastError @6 :Text;
}

struct AuthAttempt {
    # When the authentication attempt completed.
    timestamp @0 :T.Timestamp;
    # Whether it succeeded.
    success @1 :Bool;
    # Remaining attempts (present after a failed attempt).
    remainingAttempts @2 :UInt32;
    # Which modality authenticated (or was attempted).
    modality @3 :BiometricModality;
    # Template used (if known).
    templateId @4 :T.BiometricId;
    # Quality score of the match (0.0 - 1.0).
    quality @5 :Float32;
}

enum AuthResult {
    success @0;
    failed @1;
    error @2;
    cancelled @3;
    timeout @4;
    lockout @5;
    deviceCredential @6;
    custom @7;
}

# ── Template ──────────────────────────────────────────────────────────────

# Audit-9: typed signing algorithm replacing bare Text for crypto agility.
enum SigningAlgorithm {
    hmacSha256 @0;
    hmacSha384 @1;
    hmacSha512 @2;
    ecdsaP256 @3;
    ecdsaP384 @4;
    ed25519 @5;
    rsa2048 @6;
    rsa4096 @7;
    custom @8;
}

# Audit-9: structured template version for migration (major.minor).
struct TemplateVersion {
    # Major version (breaking changes in template format).
    major @0 :UInt32;
    # Minor version (backward-compatible additions).
    minor @1 :UInt32;
    # Patch version (bug fixes, no format changes).
    patch @2 :UInt32;
}

# Audit-9: multi-phrase voice enrollment profile with noise profiling.
struct VoiceEnrollmentProfile {
    # Enrollment phrases (multiple for robustness).
    phrases @0 :List(Text);
    # Ambient noise level during enrollment (0.0 = silent, 1.0 = loud).
    enrollmentNoiseLevel @1 :Float32;
    # Whether noise profiling was performed.
    noiseProfiled @2 :Bool;
    # Background noise profile (spectral fingerprint).
    noiseProfile @3 :Data;
    # Voice activity detection threshold used during enrollment.
    vadThreshold @4 :Float32;
    # Whether far-field enrollment was used.
    farField @5 :Bool;
}

struct BiometricTemplate {
    id @0 :T.BiometricId;
    modality @1 :BiometricModality;
    name @2 :Text;
    enrolledAt @3 :T.Timestamp;
    # Last successful authentication.
    lastUsedAt @4 :T.Timestamp;
    # How many times this template authenticated.
    useCount @5 :UInt64;
    # Which hardware sensor enrolled this.
    hardwareId @6 :T.BiometricId;
    # Face-specific: enrolled with liveness detection.
    hasLiveness @7 :Bool;
    # Voice-specific: phrase hash used during enrollment.
    voicePhraseHash @8 :Data;
    # Audit-9: structured template version for migration.
    version @9 :TemplateVersion;
    # Audit-9: whether the template is encrypted at rest.
    encryptedAtRest @10 :Bool;
    # Audit-9: voice-specific enrollment profile (null for non-voice modalities).
    voiceProfile @11 :VoiceEnrollmentProfile;
}

# ── Biometric Token (crypto-binding) ─────────────────────────────────────

struct BiometricToken {
    # HMAC of the challenge using the biometric-derived key.
    signature @0 :Data;
    # Algorithm used to produce the signature (for crypto agility).
    algorithm @1 :SigningAlgorithm;
    # Which modality was used.
    modality @2 :BiometricModality;
    # Template that produced this token.
    templateId @3 :T.BiometricId;
    # Server-side challenge that was signed.
    challenge @4 :Data;
    # Expiry (wall clock; token is only valid until this time).
    expiresAt @5 :T.Timestamp;
    # Whether the device credential was used as fallback.
    usedDeviceCredential @6 :Bool;
    # Issued at timestamp.
    issuedAt @7 :T.Timestamp;
}

# ── Service ───────────────────────────────────────────────────────────────

interface BiometricService {
    getAvailability @0 () -> (availability :BiometricAvailability);

    # Authenticate and receive a signed token (optional crypto-binding).
    authenticate @1 (prompt :AuthPrompt)
                  -> (subscription :AuthSubscription);

    # Get enrolled templates.
    getEnrolled @2 (pagination :T.Pagination) -> (templates :List(BiometricTemplate), totalCount :UInt32);

    # Enroll a new template.
    enroll @3 (modality :BiometricModality, name :Text) -> (subscription :EnrollSubscription);

    # Remove a template.
    remove @4 (templateId :T.BiometricId) -> T.VoidResult;

    # Remove all templates.
    removeAll @5 () -> T.VoidResult;

    # Check if a specific modality is available.
    isModalityAvailable @6 (modality :BiometricModality) -> (available :Bool);

    # Verify a biometric token from a previous authenticate call.
    verifyToken @7 (token :BiometricToken) -> (valid :Bool);

    # Subscribe to biometric events (enrollment progress, lockout changes).
    subscribe @8 () -> (subscription :BiometricEventSubscription);
    pull @9 (subscription :BiometricEventSubscription) -> (events :List(BiometricEvent));
    cancel @10 (subscription :BiometricEventSubscription) -> T.VoidResult;

    # Audit-9: enroll voice with multi-phrase profile and noise profiling.
    enrollVoice @11 (name :Text, profile :VoiceEnrollmentProfile) -> (subscription :EnrollSubscription);

    # Audit-9: get template version compatibility matrix.
    getTemplateCompatibility @12 (fromVersion :TemplateVersion, toVersion :TemplateVersion) -> (compatible :Bool, migrationRequired :Bool);

    # Audit-9: declare encryption-at-rest status for a template.
    setTemplateEncryption @13 (templateId :T.BiometricId, encrypted :Bool) -> T.VoidResult;
}

interface AuthSubscription {
    pull @0 () -> (result :AuthResult, attempt :AuthAttempt);
    cancel @1 () -> T.VoidResult;
}

interface EnrollSubscription {
    pull @0 () -> (progress :EnrollProgress);
    cancel @1 () -> T.VoidResult;
}

struct EnrollProgress {
    # Progress percentage (0-100).
    percent @0 :UInt32;
    step @1 :EnrollStep;
    templateId @2 :T.BiometricId;
    # Remaining steps.
    remainingSteps @3 :UInt32;
}

enum EnrollStep {
    waitingForSensor @0;
    partialEnrollment @1;
    captureComplete @5;
    processing @6;
    qualityCheck @7;
    templateStored @8;
    complete @2;
    failed @3;
    custom @4;
}

# Audit-7: structured liveness detection result.
struct LivenessCheck {
    # Whether liveness check passed.
    passed @0 :Bool;
    # Method used for liveness detection.
    method @1 :LivenessMethod;
    # Confidence score (0.0 - 1.0).
    confidence @2 :Float32;
    # When the liveness check was performed.
    timestamp @3 :T.Timestamp;
}

enum LivenessMethod {
    blink @0;          # Blink detection (front camera)
    depth @1;          # Depth sensing (ToF sensor)
    texture @2;        # Texture analysis (spoofing detection)
    motion @3;         # Motion detection (natural movement)
    challenge @4;      # Challenge-response (random prompt)
    custom @5;
}

# ── Events ───────────────────────────────────────────────────────────────

interface BiometricEventSubscription {
    pull @0 () -> (events :List(BiometricEvent));
    cancel @1 () -> T.VoidResult;
}

struct BiometricEvent {
    union {
        lockoutStarted @0 :LockoutEvent;
        lockoutEnded @1 :LockoutEvent;
        templateEnrolled @2 :TemplateEvent;
        templateRemoved @3 :TemplateEvent;
        hardwareChanged @4 :HardwareChangedEvent;
        # Audit-7: new event types for richer event stream
        templateUpdated @6 :TemplateEvent;
        livenessFailure @7 :LivenessCheck;
        hardwareError @8 :HardwareErrorEvent;
        calibrationDue @9 :CalibrationDueEvent;
        custom @5 :Data;
    }
}

# Audit-7: hardware error event.
struct HardwareErrorEvent {
    hardwareId @0 :T.BiometricId;
    errorCode @1 :Text;
    description @2 :Text;
    timestamp @3 :T.Timestamp;
}

# Audit-7: calibration due event.
struct CalibrationDueEvent {
    hardwareId @0 :T.BiometricId;
    lastCalibration @1 :T.Timestamp;
    recommendedInterval @2 :T.Duration;
    timestamp @3 :T.Timestamp;
}

struct LockoutEvent {
    lockout @0 :LockoutInfo;
    timestamp @1 :T.Timestamp;
}

struct TemplateEvent {
    templateId @0 :T.BiometricId;
    modality @1 :BiometricModality;
    timestamp @2 :T.Timestamp;
}

struct HardwareChangedEvent {
    hardware @0 :List(BiometricHardware);
    timestamp @1 :T.Timestamp;
}

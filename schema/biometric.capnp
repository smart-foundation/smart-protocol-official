@0xa1b2c3d4e5f60054;


# ═══════════════════════════════════════════════════════════════════════
# Biometric - fingerprint, face, iris, voice, and multi-modal auth.
#
# This schema handles biometric hardware interaction: sensor enumeration,
# template enrollment, authentication, and crypto-binding. Auth
# orchestration lives in auth.capnp; device lock, MFA state machine and
# credential recovery live in access.capnp.
#
# ── FOUR DEFECTS, FIXED ────────────────────────────────────────────────
#
# 1. MODALITY AND SENSOR WERE CLOSED VOCABULARIES. `BiometricModality`
#    named fingerprint/face/iris/voice/gesture/vein/retina/gait/keystroke/
#    ear — R5 names "platform biometric specifics" explicitly, and the
#    Audit-7 additions were themselves a technology snapshot. 2046
#    hardware (DNA, brainwave, odour, a behavioural fusion sensor, a
#    camera-based vein/pulse system) mapped to `custom` carrying nothing,
#    and the value is consumed by BiometricPrompt.allowedModalities,
#    MultiModalAuth.requiredModalities, BiometricAuthConfig.
#    allowedModalities and isModalityAvailable, so an undescribed
#    modality could not even be requested. Modality is an open token now;
#    the security-relevant fact (SecurityLevel) stays typed.
#
# 2. ONE ID FOR TWO NAMESPACES. T.BiometricId was used for both hardware
#    sensors and enrolled templates, while the promoted
#    T.BiometricTemplateId sat unused. `getAvailability` returns hardware
#    and `getEnrolled` returns templates, both keyed by the same type, so
#    nothing on the wire distinguished them and BiometricAuthOutcome's templateId
#    could be either. Hardware keeps T.BiometricId; every template
#    reference is T.BiometricTemplateId.
#
# 3. THE AUTH RESULT COULD NOT SAY WHY. `BiometricAuthOutcome` was a bare enum
#    with no payload — `failed` and `error` were indistinguishable, the
#    reason existed nowhere on the wire, and the subscription had no
#    terminator, so a consumer could not tell an ended stream from a
#    slow one. It carries a payload and a `done` flag now.
#
# 4. THE TOKEN VERIFIER RETURNED A BARE BOOL. `verifyToken` could not
#    distinguish "invalid" from "could not verify" (unknown algorithm,
#    malformed token, hardware failure).
#
# ── THE ALGORITHM FIELD IS AN OPEN TOKEN ────────────────────────────────
#
# `SigningAlgorithm` was a third crypto vocabulary in the batch, in a
# required position, on a struct whose own comment said "for crypto
# agility" — the exact opposite of what a closed enum delivers. A 2046
# signature scheme had `custom` carrying nothing, so a verifier reading
# `BiometricToken.algorithm` could not know what to verify. It is now an
# open token drawn from crypto.capnp's published vocabulary.
#
# ── THE SENSOR AXES ARE DECLARED ───────────────────────────────────────
#
# `SensorLocation` and `SensorSubtype` had overlapping members
# (location.rearCamera vs subtype.camera), so an implementer had to
# decide which axis a rear camera belonged to and a consumer filtering on
# one axis missed devices recorded on the other. The split rule is now
# declared — location is WHERE the transducer sits, subtype is WHAT KIND
# of transducer it is — and both are open tokens.
#
# Zero-cost posture, kept: no inline bulk payloads, getEnrolled is
# paginated, and the BiometricEvent union carries a custom variant.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ── Modality ─────────────────────────────────────────────────────────────
# Open token; see the CONFORMANCE TOKENS at the bottom of this file.

# ── Hardware Info ─────────────────────────────────────────────────────────

struct BiometricHardware {
    # Hardware sensors keep T.BiometricId.
    id @0 :T.BiometricId;
    # Modality, as an open token.
    modality @1 :Text;
    name @2 :Text;
    securityLevel @3 :SecurityLevel;
    maxTemplates @4 :UInt32;
    falseAcceptRate @5 :Float32;
    falseRejectRate @6 :Float32;
    # WHERE the transducer sits, as an open token.
    location @7 :Text;
    # WHAT KIND of transducer it is, as an open token. The split rule
    # between the two axes is declared above; a rear camera is
    # location = "rear-camera", sensorType = "camera", and a consumer
    # filtering on either axis now sees the same device.
    sensorType @8 :Text;
    livenessDetection @9 :Bool;
    revision @10 :Text;
    health @11 :BiometricHealth;
    parameters @12 :T.StringMap;
}

enum SecurityLevel {
    unspecified @0;   # Sentinel: an unset level is not "weak"
    weak @1;
    balanced @2;
    strong @3;
    custom @4;
}

# ── Availability ─────────────────────────────────────────────────────────

struct BiometricAvailability {
    available @0 :Bool;
    hardware @1 :List(BiometricHardware);
    enrolledCount @2 :UInt32;
    isEnrolled @3 :Bool;
    hardwarePresent @4 :Bool;
    error @5 :T.Error;
    failedAttempts @6 :UInt32;
    lockout @7 :BiometricLockoutInfo;
    isLockedOut @8 :Bool;
}

struct BiometricLockoutInfo {
    remainingAttempts @0 :UInt32;
    lockoutExpiresAt @1 :T.Timestamp;
    failedAttemptCount @2 :UInt32;
    kind @3 :BiometricLockoutKind;
}

enum BiometricLockoutKind {
    none @0;
    permanent @1;
    timed @2;
    temporary @3;
    custom @4;
}

# ── Authentication ───────────────────────────────────────────────────────

# ONE prompt policy. `BiometricPrompt`, `BiometricAuthConfig` and
# `MultiModalAuth` used to carry the same knobs (allowedModalities,
# timeout, challenge, maxAttempts) with no precedence declared — two
# knobs for one policy inside one file. The two duplicates are deleted;
# the multi-modal fields live here.
struct BiometricPrompt {
    title @0 :Text;
    subtitle @1 :Text;
    negativeButtonText @2 :Text;
    # Modalities allowed, as open tokens.
    allowedModalities @3 :List(Text);
    requireConfirmation @4 :Bool;
    allowDeviceCredential @5 :Bool;
    timeout @6 :T.Duration;
    # Require a specific template (for app-specific auth).
    templateId @7 :T.BiometricTemplateId;
    # Crypto-binding: challenge to sign into the token.
    challenge @8 :Data;

    # ── Multi-modal policy (was the separate MultiModalAuth struct) ──
    # Modalities that must all succeed (open tokens).
    requiredModalities @9 :List(Text);
    # Combine strategy: all must pass, any must pass, best quality wins.
    combineStrategy @10 :MultiModalStrategy;
    # Number of modalities that must succeed (for the any strategy).
    requiredCount @11 :UInt32;
    # Maximum number of attempts before lockout.
    maxAttempts @12 :UInt32;
}

enum MultiModalStrategy {
    unspecified @0;   # Sentinel: an unset strategy is not "all"
    all @1;
    any @2;
    best @3;
    custom @4;
}

# ── Hardware health monitoring ───────────────────────────────────────────
struct BiometricHealth {
    sensorOk @0 :Bool;
    lastCalibration @1 :T.Timestamp;
    calibrationDue @2 :T.Timestamp;
    falseAcceptRate @3 :Float32;
    falseRejectRate @4 :Float32;
    failureCount @5 :UInt32;
    lastError @6 :Text;
    parameters @7 :T.StringMap;
}

struct BiometricAuthAttempt {
    timestamp @0 :T.Timestamp;
    success @1 :Bool;
    remainingAttempts @2 :UInt32;
    # Modality, as an open token.
    modality @3 :Text;
    # Template used (if known) — the template namespace, not hardware.
    templateId @4 :T.BiometricTemplateId;
    quality @5 :Float32;
    metadata @6 :T.StringMap;
}

# The outcome of one authentication, WITH its cause. Previously a bare
# enum, so `failed` and `error` were indistinguishable and the reason
# existed nowhere on the wire.
struct BiometricAuthOutcome {
    union {
        success @0 :BiometricAuthSuccess;
        failed @1 :BiometricAuthFailure;
        error @2 :T.Error;
        cancelled @3 :Void;
        timeout @4 :Void;
        lockout @5 :BiometricLockoutInfo;
        # Forward compatibility for an outcome this schema does not name.
        custom @6 :Data;
    }
}

struct BiometricAuthSuccess {
    token @0 :BiometricToken;
    attempt @1 :BiometricAuthAttempt;
    metadata @2 :T.StringMap;
}

struct BiometricAuthFailure {
    # Open token naming the failure class (see the CONFORMANCE TOKENS).
    reason @0 :Text;
    attempt @1 :BiometricAuthAttempt;
    remainingAttempts @2 :UInt32;
    error @3 :T.Error;
    metadata @4 :T.StringMap;
}

# ── Template ──────────────────────────────────────────────────────────────

# Structured template version for migration (major.minor).
struct TemplateVersion {
    major @0 :UInt32;
    minor @1 :UInt32;
    patch @2 :UInt32;
}

# Multi-phrase voice enrollment profile with noise profiling.
struct VoiceEnrollmentProfile {
    phrases @0 :List(Text);
    enrollmentNoiseLevel @1 :Float32;
    noiseProfiled @2 :Bool;
    # Background noise profile (spectral fingerprint) — small and opaque.
    noiseProfile @3 :Data;
    vadThreshold @4 :Float32;
    farField @5 :Bool;
    parameters @6 :T.StringMap;
}

struct BiometricTemplate {
    # Templates get their own identity: T.BiometricTemplateId, not
    # T.BiometricId, so a sensor id and a template id can never be
    # crossed.
    id @0 :T.BiometricTemplateId;
    modality @1 :Text;
    name @2 :Text;
    enrolledAt @3 :T.Timestamp;
    lastUsedAt @4 :T.Timestamp;
    useCount @5 :UInt64;
    # Which hardware sensor enrolled this — the hardware namespace.
    hardwareId @6 :T.BiometricId;
    hasLiveness @7 :Bool;
    voicePhraseHash @8 :Data;
    version @9 :TemplateVersion;
    encryptedAtRest @10 :Bool;
    voiceProfile @11 :VoiceEnrollmentProfile;
    metadata @12 :T.StringMap;
}

# ── Biometric Token (crypto-binding) ─────────────────────────────────────

struct BiometricToken {
    signature @0 :Data;
    # Algorithm, as an open token drawn from crypto.capnp's vocabulary,
    # so a 2046 scheme is nameable and a verifier knows what it is
    # verifying. The previous closed enum was a third crypto vocabulary
    # in a batch that already had two.
    algorithm @1 :Text;
    modality @2 :Text;
    # Template that produced this token — the template namespace.
    templateId @3 :T.BiometricTemplateId;
    challenge @4 :Data;
    expiresAt @5 :T.Timestamp;
    usedDeviceCredential @6 :Bool;
    issuedAt @7 :T.Timestamp;
    parameters @8 :T.StringMap;
}

# A verification outcome that can say WHY, not just "no". Previously a
# bare Bool, so "invalid" and "could not verify" were the same answer.
struct BiometricTokenResult {
    union {
        valid @0 :ValidToken;
        invalid @1 :InvalidToken;
        error @2 :T.Error;
        custom @3 :Data;
    }
}

struct ValidToken {
    templateId @0 :T.BiometricTemplateId;
    algorithm @1 :Text;
    expiresAt @2 :T.Timestamp;
    metadata @3 :T.StringMap;
}

struct InvalidToken {
    # Open token naming the failure class (see the CONFORMANCE TOKENS).
    reason @0 :Text;
    error @1 :T.Error;
    metadata @2 :T.StringMap;
}

# ── Service ───────────────────────────────────────────────────────────────

interface BiometricService {
    getAvailability @0 () -> (availability :BiometricAvailability);

    # Authenticate and receive a signed token (optional crypto-binding).
    authenticate @1 (prompt :BiometricPrompt)
                  -> (subscription :BiometricAuthSubscription);

    # Get enrolled templates.
    getEnrolled @2 (pagination :T.Pagination) -> (templates :List(BiometricTemplate), totalCount :UInt32);

    # Enroll a new template.
    enroll @3 (modality :Text, name :Text) -> (subscription :EnrollSubscription);

    # Remove a template.
    remove @4 (templateId :T.BiometricTemplateId) -> T.VoidResult;

    # Remove all templates.
    removeAll @5 () -> T.VoidResult;

    # Check if a specific modality is available.
    isModalityAvailable @6 (modality :Text) -> (available :Bool);

    # Verify a biometric token from a previous authenticate call.
    verifyToken @7 (token :BiometricToken) -> (result :BiometricTokenResult);

    # Subscribe to biometric events (enrollment progress, lockout changes).
    subscribe @8 () -> (subscription :BiometricEventSubscription);
    pull @9 (subscription :BiometricEventSubscription) -> (events :List(BiometricEvent));
    cancel @10 (subscription :BiometricEventSubscription) -> T.VoidResult;

    # Enroll voice with multi-phrase profile and noise profiling.
    enrollVoice @11 (name :Text, profile :VoiceEnrollmentProfile) -> (subscription :EnrollSubscription);

    # Get template version compatibility.
    #
    # Declared semantics: `migrationRequired = true` means the backend
    # will migrate this template ON NEXT USE, transparently. There is no
    # in-place migration method, so a caller that requires an immediate
    # migration MUST remove and re-enroll. The version scheme itself:
    # a MAJOR bump is breaking (the template can no longer be matched),
    # a MINOR bump is backward-compatible (the old matcher still
    # matches), a PATCH changes no matching behaviour. Previously none of
    # this was declared, so a backend reporting migrationRequired = true
    # left the caller with nothing to call.
    getTemplateCompatibility @12 (fromVersion :TemplateVersion, toVersion :TemplateVersion)
        -> (compatible :Bool, migrationRequired :Bool, breakingChange :Bool);

    # Declare encryption-at-rest status for a template.
    setTemplateEncryption @13 (templateId :T.BiometricTemplateId, encrypted :Bool) -> T.VoidResult;
}

interface BiometricAuthSubscription {
    # `done` is a STRUCTURAL TERMINATOR: a consumer can now tell an
    # ended stream from a slow one, which the previous shape could not.
    pull @0 () -> (result :BiometricAuthOutcome, attempt :BiometricAuthAttempt, done :Bool);
    cancel @1 () -> T.VoidResult;
}

interface EnrollSubscription {
    pull @0 () -> (progress :EnrollProgress);
    cancel @1 () -> T.VoidResult;
}

struct EnrollProgress {
    percent @0 :UInt32;
    step @1 :EnrollStep;
    templateId @2 :T.BiometricTemplateId;
    remainingSteps @3 :UInt32;
}

enum EnrollStep {
    waitingForSensor @0;
    partialEnrollment @1;
    captureComplete @2;
    processing @3;
    qualityCheck @4;
    templateStored @5;
    complete @6;
    failed @7;
    custom @8;
}

# Structured liveness detection result.
struct LivenessCheck {
    passed @0 :Bool;
    # Method, as an open token.
    method @1 :Text;
    confidence @2 :Float32;
    timestamp @3 :T.Timestamp;
    parameters @4 :T.StringMap;
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
        templateUpdated @5 :TemplateEvent;
        livenessFailure @6 :LivenessCheck;
        hardwareError @7 :HardwareErrorEvent;
        calibrationDue @8 :CalibrationDueEvent;
        custom @9 :Data;
    }
}

# Audit-7: hardware error event.
struct HardwareErrorEvent {
    hardwareId @0 :T.BiometricId;
    # Error code, as an open token, so a consumer can branch on the
    # class rather than parse free text.
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
    lockout @0 :BiometricLockoutInfo;
    timestamp @1 :T.Timestamp;
}

struct TemplateEvent {
    templateId @0 :T.BiometricTemplateId;
    modality @1 :Text;
    timestamp @2 :T.Timestamp;
}

struct HardwareChangedEvent {
    hardware @0 :List(BiometricHardware);
    timestamp @1 :T.Timestamp;
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Today's spellings for the open tokens above (modalities, sensor types,
# sensor locations, token failure classes). Nothing requires them; an
# unrecognized token MUST be ignored rather than rejected, so 2046
# hardware is requestable and reportable the day a backend ships it —
# no schema amendment, and no `custom` slot that carries nothing.
# ══════════════════════════════════════════════════════════════════════

const modalityFingerprint :Text = "fingerprint";
const modalityFace        :Text = "face";
const modalityIris        :Text = "iris";
const modalityVoice       :Text = "voice";
const modalityGesture     :Text = "gesture";
const modalityVein        :Text = "vein";
const modalityRetina      :Text = "retina";
const modalityGait        :Text = "gait";
const modalityKeystroke   :Text = "keystroke";
const modalityEar         :Text = "ear";

const sensorTypeOptical     :Text = "optical";
const sensorTypeCapacitive  :Text = "capacitive";
const sensorTypeUltrasonic  :Text = "ultrasonic";
const sensorTypeTof         :Text = "tof";
const sensorTypeIris        :Text = "iris";
const sensorTypeCamera      :Text = "camera";
const sensorTypeMicrophone  :Text = "microphone";
const sensorTypePressure    :Text = "pressure";
const sensorTypeThermal     :Text = "thermal";
const sensorTypeRadar       :Text = "radar";
const sensorTypeLidar       :Text = "lidar";

const sensorLocationDisplay      :Text = "display";
const sensorLocationSideButton   :Text = "side-button";
const sensorLocationRearCamera   :Text = "rear-camera";
const sensorLocationFrontCamera  :Text = "front-camera";
const sensorLocationTopEdge      :Text = "top-edge";
const sensorLocationBottomEdge   :Text = "bottom-edge";
const sensorLocationUnderDisplay :Text = "under-display";
const sensorLocationExternalUsb  :Text = "external-usb";
const sensorLocationWearable     :Text = "wearable";

const livenessBlink    :Text = "blink";
const livenessDepth    :Text = "depth";
const livenessTexture  :Text = "texture";
const livenessMotion   :Text = "motion";
const livenessChallenge :Text = "challenge";

const tokenFailureExpired           :Text = "expired";
const tokenFailureMalformed         :Text = "malformed";
const tokenFailureUnknownAlgorithm  :Text = "unknown-algorithm";
const tokenFailureWrongChallenge    :Text = "wrong-challenge";
const tokenFailureRevoked           :Text = "revoked";
const tokenFailureUnsupported       :Text = "unsupported";

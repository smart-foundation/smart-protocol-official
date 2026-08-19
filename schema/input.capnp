@0xa1b2c3d4e5f60008;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Input - per-device input state, layouts, modifiers, idle, emulation,
#         rumble, surface grab, gestures, biometrics, hotplug.
#
# Improvements (audit-3):
#   - All list-returning methods paginated with T.Pagination (Rule 9).
#   - emulateKey and KeyTrigger.key use T.KeyCode (was bare UInt32) (Rule 2).
#
# Improvements (audit-5):
#   - BindingScope.seatId changed from bare Text to T.SeatId (Rule 2).
# ═══════════════════════════════════════════════════════════════════════

interface Input {
    # ── Layouts ──
    getLayouts @0 (page :T.Pagination) -> (layouts :List(KeyboardLayout));
    getActiveLayout @1 () -> (layout :KeyboardLayout);
    setLayout @2 (layoutId :T.KeyboardLayoutId) -> T.VoidResult;
    subscribeLayout @3 () -> (subscription :LayoutSubscription);
    pullLayout @4 (subscription :LayoutSubscription) -> (layout :KeyboardLayout);

    # ── Modifiers / Idle ──
    getModifiers @5 () -> (state :T.ModifierState);
    subscribeModifiers @6 () -> (subscription :ModifierSubscription);
    pullModifiers @7 (subscription :ModifierSubscription) -> (state :T.ModifierState);

    getIdleTime @8 () -> (idleTime :T.Duration);
    getIdleTimeout @9 () -> (timeout :T.Duration);
    setIdleTimeout @10 (timeout :T.Duration) -> T.VoidResult;
    subscribeIdle @11 () -> (subscription :IdleSubscription);
    pullIdle @12 (subscription :IdleSubscription) -> (idleTime :T.Duration);

    # ── Devices & subkinds ──
    listDevices @13 (page :T.Pagination) -> (devices :List(InputDevice));
    getDevice @14 (deviceId :T.DeviceId) -> (device :InputDevice);
    subscribeDevices @15 (filter :DeviceFilter) -> (subscription :DeviceSubscription);
    pullDevices @16 (subscription :DeviceSubscription) -> (events :List(DeviceEvent));

    getGamepads @17 () -> (gamepads :List(GamepadState));
    subscribeGamepads @18 () -> (subscription :GamepadSubscription);
    pullGamepads @19 (subscription :GamepadSubscription) -> (states :List(GamepadState));

    # ── Haptics / Rumble ──
    # Intensity values are normalized 0.0..1.0. Duration is explicit T.Duration.
    playRumble @20 (deviceId :T.DeviceId, weak :Float32, strong :Float32, duration :T.Duration) -> T.VoidResult;
    stopRumble @21 (deviceId :T.DeviceId) -> T.VoidResult;
    engageHaptic @22 (deviceId :T.DeviceId, waveform :HapticWaveform) -> (instanceId :UInt64);
    stopHaptic @23 (deviceId :T.DeviceId, instanceId :UInt64) -> T.VoidResult;

    # ── Key bindings / shortcuts ──
    registerKeyBinding @24 (binding :KeyBinding) -> (id :T.KeyBindingId);
    unregisterKeyBinding @25 (id :T.KeyBindingId) -> T.VoidResult;
    listKeyBindings @26 (page :T.Pagination) -> (bindings :List(KeyBinding));

    # ── Emulation ──
    emulateKey @27 (key :T.KeyCode, pressed :Bool, mods :T.ModifierState) -> T.VoidResult;
    emulateSequence @28 (text :Text) -> T.VoidResult;

    # ── Surface-level input grab ──
    grab @29 (surfaceId :T.SurfaceId) -> T.VoidResult;
    releaseGrab @30 () -> T.VoidResult;
    isGrabbed @31 () -> (grabbed :Bool, surfaceId :T.SurfaceId);

    # ── Biometrics ──
    listBiometricsTemplates @32 (modality :BiometricModality, page :T.Pagination) -> (templates :List(BiometricTemplate));
    enrollBiometric @33 (modality :BiometricModality, name :Text) -> (template :BiometricTemplate);
    removeBiometric @34 (templateId :T.BiometricTemplateId) -> T.VoidResult;

    # ── Gestures (system-wide) ──
    registerGesture @35 (gesture :GestureDef) -> (id :T.GestureId);
    unregisterGesture @36 (id :T.GestureId) -> T.VoidResult;
    listGestures @37 (page :T.Pagination) -> (gestures :List(GestureDef));
    subscribeGestures @38 () -> (subscription :GestureSubscription);
    pullGestures @39 (subscription :GestureSubscription) -> (events :List(GestureEvent));

    # ── Audit-7: device-specific capability queries ──
    getEyeTrackerInfo @40 (deviceId :T.DeviceId) -> (info :EyeTrackerInfo);
    getVoiceInputInfo @41 (deviceId :T.DeviceId) -> (info :VoiceInputDeviceInfo);
    getBrainInputInfo @42 (deviceId :T.DeviceId) -> (info :BrainInputInfo);
    getSpatialInputInfo @43 (deviceId :T.DeviceId) -> (info :SpatialInputInfo);
    getDigitalCrownInfo @44 (deviceId :T.DeviceId) -> (info :DigitalCrownInfo);
    getCabinAttentionInfo @45 (deviceId :T.DeviceId) -> (info :CabinAttentionInfo);

    # ── Audit-9: extended input event subscription ──
    subscribeInputEvents @46 (filter :DeviceFilter) -> (subscription :InputEventSubscription);
    pullInputEvents @47 (subscription :InputEventSubscription) -> (events :List(InputEvent));

    # Audit-10: input event replay/macro for recording and replaying sequences.
    createInputMacro @48 (name :Text, events :List(InputEvent)) -> (macroId :UInt64);
    deleteInputMacro @49 (macroId :UInt64) -> T.VoidResult;
    listInputMacros @50 (page :T.Pagination) -> (macros :List(InputMacroInfo));
    replayInputMacro @51 (macroId :UInt64, speed :Float32, loop :Bool) -> T.VoidResult;
    stopInputMacro @52 (macroId :UInt64) -> T.VoidResult;
    getInputMacroInfo @53 (macroId :UInt64) -> (info :InputMacroInfo);

    # Audit-10: gesture learning for teaching custom gestures.
    startGestureLearning @54 (gestureKind :GestureKind) -> (sessionId :UInt64);
    addGestureSample @55 (sessionId :UInt64, points :List(TouchPoint)) -> T.VoidResult;
    finalizeLearnedGesture @56 (sessionId :UInt64, name :Text) -> (gestureId :T.GestureId);
    cancelGestureLearning @57 (sessionId :UInt64) -> T.VoidResult;

    # Audit-10: multi-device coordination.
    getDeviceCoordination @58 (deviceIds :List(T.DeviceId)) -> (coordination :DeviceCoordination);
    setDeviceCoordination @59 (coordination :DeviceCoordination) -> T.VoidResult;
}

interface LayoutSubscription {
    pull @0 () -> (layout :KeyboardLayout);
    cancel @1 () -> T.VoidResult;
}
interface ModifierSubscription {
    pull @0 () -> (state :T.ModifierState);
    cancel @1 () -> T.VoidResult;
}
interface IdleSubscription {
    pull @0 () -> (idleTime :T.Duration);
    cancel @1 () -> T.VoidResult;
}
interface DeviceSubscription {
    pull @0 () -> (events :List(DeviceEvent));
    cancel @1 () -> T.VoidResult;
}
interface GamepadSubscription {
    pull @0 () -> (states :List(GamepadState));
    cancel @1 () -> T.VoidResult;
}
interface GestureSubscription {
    pull @0 () -> (events :List(GestureEvent));
    cancel @1 () -> T.VoidResult;
}

struct KeyboardLayout {
    id @0 :T.KeyboardLayoutId;
    name @1 :Text;
    vendor @2 :Text;
    options @3 :List(Text);
    # Backend-specific layout rules file (e.g. XKB rules on Linux) — optional.
    rules @4 :Text;
    # ISO layout identifier.
    isoCode @5 :Text;
}

struct InputDevice {
    id @0 :T.DeviceId;
    name @1 :Text;
    kind @2 :DeviceKind;
    # Whether the device is currently enabled.
    enabled @3 :Bool = true;
    # Vendor identifier (USB/PCI vendor, or backend-specific).
    vendorId @4 :UInt16;
    # Product identifier.
    productId @5 :UInt16;
    # Battery level (0-100). 0xFFFF if unknown.
    batteryPercent @6 :UInt16;
    # Whether the device supports haptic feedback.
    haptic @7 :Bool;
    # Backend-specific metadata (formerly `sysPath`).
    backendSpecific @8 :T.StringMap;
}

enum DeviceKind {
    keyboard @0;
    pointer @1;
    touchpad @2;
    touch @3;
    mouse @4;
    gamepad @5;
    joystick @6;
    tablet @7;
    stylus @8;
    microphone @9;
    fingerprintReader @10;
    faceAuthCamera @11;
    irisScanner @12;
    voiceAuthMic @13;
    pen @14;
    airGesture @15;
    hapticsOnly @16;
    other @17;
    # Audit-7: extended input modality device kinds.
    eyeTracker @18;
    voiceInput @19;
    brainInput @20;
    spatialInput @21;
    digitalCrown @22;
    cabinAttention @23;
    custom @24;
}

struct DeviceFilter {
    kinds @0 :List(DeviceKind);
    vendorId @1 :UInt16;
    productId @2 :UInt16;
    onlyEnabled @3 :Bool = true;
    # Capacities — devices must advertise all listed in this set.
    requireCapabilities @4 :List(Text);
    # Audit-9: typed capability flags. Use instead of requireCapabilities
    # for type-safe capability filtering.
    requireCapabilityFlags @5 :List(InputCapability);
}

struct DeviceEvent {
    union {
        added @0 :InputDevice;
        removed @1 :InputDevice;
        enabled @2 :EnabledChange;
        battery @3 :BatteryChange;
        upgraded @4 :InputDevice;
    }
}

struct EnabledChange {
    deviceId @0 :T.DeviceId;
    previousEnabled @1 :Bool;
    currentEnabled @2 :Bool;
}

struct BatteryChange {
    deviceId @0 :T.DeviceId;
    previousPercent @1 :UInt16;
    currentPercent @2 :UInt16;
}

# Analog gamepad input — `values :List(Float32)` is the broad
# catch-all (triggers / axes). `buttonsBool :List(Bool)` gives clean
# boolean button state without resolution.
struct GamepadState {
    id @0 :T.DeviceId;
    name @1 :Text;
    # Float-axis values (-1.0..+1.0 typically).
    values @2 :List(Float32);
    # Digital bits — one per physical button.
    buttonsBool @3 :List(Bool);
    # Hat switch values (-1, 0, 1) per hat; empty if no hats.
    hats @4 :List(Int32);
    # Battery / power.
    batteryPercent @5 :UInt16;
    # Touchpad mode if any (DS4-style).
    touchpad @6 :TouchpadState;
    # Carry-flag: a frame was just dropped to keep latency low.
    dropped @7 :Bool;
}

struct TouchpadState {
    width @0 :UInt32;
    height @1 :UInt32;
    active @2 :Bool;
    points @3 :List(TouchPoint);
}

struct TouchPoint {
    slot @0 :UInt32;
    position @1 :T.Vec2i;
    pressure @2 :Float32;
    # Stylus-specific extras when known.
    tilt @3 :Float32;
    barrelRotation @4 :UInt16;
    tool @5 :StylusTool;
}

enum StylusTool {
    unknown @0;
    pen @1;
    eraser @2;
    brush @3;
    pencil @4;
    airbrush @5;
    finger @6;
    palmReject @7;
    custom @8;
}

# ── Haptic playback ──
struct HapticWaveform {
    # Waveform shape, backend-decoded.
    pattern @0 :HapticPattern;
    # Continuous-amplitude stream (amplitude 0.0..1.0).
    amplitudeEnvelope @1 :List(Float32);
    duration @2 :T.Duration;
    # Replay count: zero = loop forever.
    loop @3 :UInt32 = 0;
    # Audit-9: explicit amplitude points with timestamps.
    # Use instead of amplitudeEnvelope when precise timing is needed.
    amplitudePoints @4 :List(AmplitudePoint);
}

enum HapticPattern {
    click @0;
    doubleClick @1;
    tick @2;
    thud @3;
    alert @4;
    error @5;
    notification @6;
    custom @7;
    ringing @8;
    silence @9;
}

# ── Key bindings (global/system shortcuts) ──
struct KeyBinding {
    id @0 :T.KeyBindingId;
    # Which key (logical name or scancode).
    trigger @1 :KeyTrigger;
    # What to invoke when triggered.
    action @2 :KeyAction;
    # Optional application/service context this binding is scoped to.
    scope @3 :BindingScope;
}

struct KeyTrigger {
    key @0 :T.KeyCode;
    modifiers @1 :T.ModifierState;
    # Whether this triggers on key-down (true) or key-up (false).
    onPress @2 :Bool = true;
    # Whether to also activate when keys are held.
    holdable @3 :Bool = false;
}

struct KeyAction {
    union {
        runCommand @0 :Text;
        sendUri @1 :Text;
        activateSurface @2 :T.SurfaceId;
        invokeIntent @3 :IntentReference;
        triggerHaptic @4 :HapticWaveform;
        custom @5 :T.StringMap;
    }
}

struct IntentReference {
    action @0 :Text;
    dataUri @1 :Text;
    mimeType @2 :Text;
    extras @3 :T.StringMap;
}

struct BindingScope {
    # Empty = global/system binding.
    surfaceId @0 :T.SurfaceId;
    applicationId @1 :T.AppId;
    seatId @2 :T.SeatId;
}

# ── Biometrics (high-level reference, biometric.capnp is the spec) ──
enum BiometricModality {
    fingerprint @0;
    face @1;
    iris @2;
    voice @3;
    custom @4;
}

struct BiometricTemplate {
    id @0 :T.BiometricTemplateId;
    modality @1 :BiometricModality;
    name @2 :Text;
    # When the template was created (wall clock).
    enrolledAt @3 :T.Timestamp;
    # Last successful use.
    lastUsedAt @4 :T.Timestamp;
    # How often it has matched.
    useCount @5 :UInt64;
}

# ── Gestures system-wide ──
struct GestureDef {
    id @0 :T.GestureId;
    kind @1 :GestureKind;
    # Number of touch points required to match (1 for tap, 2 for pinch).
    touches @2 :UInt32;
    # Threshold scalar (0..1).
    threshold @3 :Float32;
    # Where the gesture is session-bound to a surface (or empty = global).
    surfaceId @4 :T.SurfaceId;
}

enum GestureKind {
    tap @0;
    doubleTap @1;
    longPress @2;
    drag @3;
    pinch @4;
    spread @5;
    rotate @6;
    edgeSwipe @7;
    doubleEdgeSwipe @8;
    twoFingerTap @9;
    threeFingerTap @10;
    fourFingerTap @11;
    pinchToZoom @12;
    swipeLeft @13;
    swipeRight @14;
    swipeUp @15;
    swipeDown @16;
    circle @17;
    tripleTap @18;
    fourFingerSwipeUp @19;
    fourFingerSwipeDown @20;
    knuckleTap @21;
    pressure @22;
    freeform @23;
    custom @24;
}

struct GestureEvent {
    gestureId @0 :T.GestureId;
    timestamp @1 :T.Timestamp;
    surfaceId @2 :T.SurfaceId;
    position @3 :T.Vec2i;
    scale @4 :Float32;
    rotation @5 :Float32;
    velocity @6 :T.Vec2;
    touches @7 :List(TouchPoint);
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-7: Extended input modality support
#
# Eye-tracking, voice input, brain-computer interface, AR/VR spatial
# input, digital crown (wearables), and cabin attention (automotive).
# These structs describe device capabilities and events for each
# extended input modality. Zero-cost: inline structs, no heap.
# ═══════════════════════════════════════════════════════════════════════

# ── Eye Tracking ──────────────────────────────────────────────

struct EyeTrackerInfo {
    type @0 :EyeTrackingType;
    # Accuracy in degrees of visual angle.
    accuracy @1 :Float32;
    # Precision in degrees of visual angle.
    precision @2 :Float32;
    # Sampling rate in Hz.
    samplingRate @3 :UInt32;
    latency @4 :T.Duration;
    # Whether the device supports calibration.
    calibration @5 :Bool;
    # Whether the device compensates for head movement.
    headMovement @6 :Bool;
}

enum EyeTrackingType {
    remote @0;           # Screen-mounted tracker
    wearable @1;         # Glasses-mounted tracker
    integrated @2;       # Built into display
    custom @3;
}

struct EyeTrackingEvent {
    # Gaze position (normalized 0-1 in screen coordinates).
    gaze @0 :T.Vec2;
    # Pupil diameter in millimeters.
    pupil @1 :Float32;
    blink @2 :Bool;
    # Whether this is a fixation (stable gaze).
    fixation @3 :Bool;
    # Whether this is a saccade (rapid eye movement).
    saccade @4 :Bool;
    timestamp @5 :T.Timestamp;
}

# ── Voice Input Device ────────────────────────────────────────

struct VoiceInputDeviceInfo {
    type @0 :VoiceInputType;
    # Number of microphones in the array.
    array @1 :UInt32;
    noiseReduction @2 :Bool;
    echoCancellation @3 :Bool;
    beamforming @4 :Bool;
    # Whether the device supports wake word detection.
    wakeWord @5 :Bool;
}

enum VoiceInputType {
    nearfield @0;        # Close-talk microphone
    farfield @1;         # Far-field microphone array
    ambient @2;          # Ambient sound capture
    bone @3;             # Bone conduction
    custom @4;
}

# ── Brain-Computer Interface ──────────────────────────────────

struct BrainInputInfo {
    type @0 :BrainInputType;
    # Number of EEG/EMG channels.
    channels @1 :UInt32;
    # Sampling rate in Hz.
    samplingRate @2 :UInt32;
    # ADC resolution in bits.
    resolution @3 :UInt32;
    latency @4 :T.Duration;
    # Whether the device supports mental state classification.
    classification @5 :Bool;
}

enum BrainInputType {
    eeg @0;             # Electroencephalography
    emg @1;             # Electromyography
    fnirs @2;           # Functional near-infrared spectroscopy
    custom @3;
}

struct BrainInputEvent {
    # Decoded command string from neural signal processing.
    command @0 :Text;
    confidence @1 :Float32;
    mentalState @2 :MentalState;
    timestamp @3 :T.Timestamp;
}

enum MentalState {
    relaxed @0;
    focused @1;
    stressed @2;
    drowsy @3;
    custom @4;
}

# ── AR/VR Spatial Input ───────────────────────────────────────

struct SpatialInputInfo {
    tracking @0 :SpatialTrackingType;
    handTracking @1 :Bool;
    eyeTracking @2 :Bool;
    headTracking @3 :Bool;
    bodyTracking @4 :Bool;
    # Whether the device provides environment understanding (mesh, planes).
    environment @5 :Bool;
    # Whether the device handles occlusion (virtual objects behind real objects).
    occlusion @6 :Bool;
}

enum SpatialTrackingType {
    insideOut @0;        # Camera-based (Quest, Vision Pro)
    outsideIn @1;        # External sensors (Vive)
    hybrid @2;           # Combination
    custom @3;
}

struct SpatialInputEvent {
    kind @0 :SpatialInputKind;
    # 2D screen-space position.
    position @1 :T.Vec2;
    # 3D pose (position + rotation) in world space.
    pose @2 :SpatialPose;
    confidence @3 :Float32;
    timestamp @4 :T.Timestamp;
}

enum SpatialInputKind {
    hand @0;
    eye @1;
    head @2;
    body @3;
    controller @4;
    custom @5;
}

struct SpatialPose {
    position @0 :T.Vec3;
    rotation @1 :T.Quaternion;
    velocity @2 :T.Vec3;
    angularVelocity @3 :T.Vec3;
}

# ── Digital Crown (Watch) ─────────────────────────────────────

struct DigitalCrownInfo {
    # Whether the crown supports rotation.
    rotation @0 :Bool;
    # Whether the crown supports press.
    press @1 :Bool;
    doublePress @2 :Bool;
    longPress @3 :Bool;
    # Whether the crown provides haptic feedback on rotation.
    haptic @4 :Bool;
    # Rotation sensitivity multiplier (1.0 = default).
    sensitivity @5 :Float32;
}

struct DigitalCrownEvent {
    action @0 :CrownAction;
    # Rotation delta in radians (positive = clockwise).
    delta @1 :Float32;
    # Rotation velocity in radians per second.
    velocity @2 :Float32;
    timestamp @3 :T.Timestamp;
}

enum CrownAction {
    rotate @0;
    press @1;
    doublePress @2;
    longPress @3;
    custom @4;
}

# ── Cabin Attention (Car) ─────────────────────────────────────

struct CabinAttentionInfo {
    # Number of monitoring cameras.
    cameras @0 :UInt32;
    driverMonitoring @1 :Bool;
    passengerDetection @2 :Bool;
    # Whether the system detects child presence in rear seats.
    childPresence @3 :Bool;
    # Whether the system detects driver distraction.
    distraction @4 :Bool;
    # Whether the system detects driver drowsiness.
    drowsiness @5 :Bool;
    # Whether the system tracks driver gaze direction.
    gaze @6 :Bool;
}

struct CabinAttentionEvent {
    kind @0 :AttentionKind;
    # Subject identifier (e.g., "driver", "passenger-1", "child-rear").
    subject @1 :Text;
    # Observed state (e.g., "alert", "distracted", "drowsy").
    state @2 :Text;
    confidence @3 :Float32;
    timestamp @4 :T.Timestamp;
}

enum AttentionKind {
    driver @0;
    passenger @1;
    child @2;
    pet @3;
    custom @4;
}

# ── Haptic Direction (spatial haptics) ────────────────────────

struct HapticDirection {
    # Direction in radians (0 = forward, pi/2 = right).
    azimuth @0 :Float32;
    # Elevation in radians (0 = level, pi/2 = up).
    elevation @1 :Float32;
    # Distance from center (0 = center, 1 = edge of haptic area).
    distance @2 :Float32;
    # Intensity (0.0-1.0).
    intensity @3 :Float32;
}

# Explicit amplitude point with timestamp. Use instead of
# HapticWaveform.amplitudeEnvelope when precise timing is needed.
struct AmplitudePoint {
    # Time offset from start of the waveform.
    time @0 :T.Duration;
    # Amplitude value (0.0-1.0).
    amplitude @1 :Float32;
}

# ── Input Capability Enumeration ──────────────────────────────

# Typed capability flags for input devices. Replaces the bare
# Text convention in DeviceFilter.requireCapabilities.
enum InputCapability {
    keyboard @0;
    mouse @1;
    touchpad @2;
    touchscreen @3;
    gamepad @4;
    joystick @5;
    stylus @6;
    eyeTracker @7;
    voiceInput @8;
    gesture @9;
    brainInput @10;
    haptics @11;
    spatialInput @12;
    digitalCrown @13;
    cabinAttention @14;
    other @15;
    custom @16;
}

# ── Input Event Subscription (Audit-9) ────────────────────────────
# Typed event subscription for extended input modalities.
# Exposes EyeTrackingEvent, BrainInputEvent, SpatialInputEvent,
# DigitalCrownEvent, and CabinAttentionEvent via subscription
# instead of requiring polling via get*Info methods.

# Union of all extended input events.
struct InputEvent {
    union {
        eyeTracking @0 :EyeTrackingEvent;
        brainInput @1 :BrainInputEvent;
        spatialInput @2 :SpatialInputEvent;
        digitalCrown @3 :DigitalCrownEvent;
        cabinAttention @4 :CabinAttentionEvent;
        custom @5 :Data;
    }
}

interface InputEventSubscription {
    pull @0 () -> (events :List(InputEvent));
    cancel @1 () -> T.VoidResult;
}

# ── Input Macro (Audit-10) ────────────────────────────────────────────────
# Mechanism to record and replay input event sequences.
struct InputMacroInfo {
    macroId @0 :UInt64;
    name @1 :Text;
    eventCount @2 :UInt32;
    duration @3 :T.Duration;
    createdAt @4 :T.Timestamp;
    lastPlayedAt @5 :T.Timestamp;
    playCount @6 :UInt32;
}

# ── Device Coordination (Audit-10) ──────────────────────────────────────
# Coordinate input across multiple devices for synchronized actions.
struct DeviceCoordination {
    # Devices involved in the coordination.
    deviceIds @0 :List(T.DeviceId);
    # Coordination mode.
    mode @1 :CoordinationMode;
    # Maximum time difference between devices for synchronization.
    syncTolerance @2 :T.Duration;
    # Whether to synchronize haptics across devices.
    syncHaptics @3 :Bool;
    # Whether to synchronize LED/RGB indicators.
    syncIndicators @4 :Bool;
}

enum CoordinationMode {
    independent @0;      # No coordination
    synchronized @1;     # Strictly synchronized actions
    masterSlave @2;       # One device leads, others follow
    collaborative @3;     # Devices contribute to a shared state
}

# ── Gesture Learning Session (Audit-10) ──────────────────────────────────
# Session for teaching custom gestures to the system.

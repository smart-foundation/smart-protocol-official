@0xa1b2c3d4e5f60032;

using T = import "types.capnp";

# ══════════════════════════════════════════════════════════════════════
# IME - input method editor session
#
# Manages the lifecycle of an IME session: context creation, input
# method switching, virtual keyboard control, text commit/preedit,
# and event subscriptions. Backend-agnostic — works with on-screen
# keyboards, physical keyboards, handwriting recognition, voice input,
# or any future input modality.
#
# Improvements (audit-3):
#   - InputMethodState.currentMethod documented: zero-value ID means "none" (Rule 2).
#   - destroyContext, enable, disable, reset now return T.VoidResult (Rule 5).
#
# Improvements (audit-6):
#   - TextInputEvent unknown variant renamed to custom for naming consistency (Rule 8).
# ══════════════════════════════════════════════════════════════════════

interface Session {

    struct HandshakeRequest {
        applicationId @0 :T.AppId;
        version       @1 :T.Version;
        metadata      @2 :List(T.Meta);
    }

    struct HandshakeResponse {
        sessionId @0 :T.SessionId;
        inputMethods @1 :List(InputMethodInfo);
        result    @2 :HandshakeResult;
    }

    enum HandshakeResult {
        accepted @0;
        rejected @1;
        custom @2;
    }

    handshake @0 (request :HandshakeRequest)
               -> (response :HandshakeResponse);

    # -- Context --

    createContext  @1 (request :ContextRequest) -> (id :T.ImeContextId);
    destroyContext @2 (id :T.ImeContextId) -> T.VoidResult;
    updateContext  @3 (id :T.ImeContextId, update :ContextUpdate) -> ();

    # -- Enable / Disable --

    enable         @4 (id :T.ImeContextId) -> T.VoidResult;
    disable        @5 () -> T.VoidResult;
    reset          @6 () -> T.VoidResult;

    # -- Input Method --

    listInputMethods    @7 () -> (methods :List(InputMethodInfo));
    switchInputMethod   @8 (id :T.InputMethodId) -> (result :T.VoidResult);
    getInputMethodState @9 () -> (state :InputMethodState);

    # -- Virtual Keyboard --

    showVirtualKeyboard @10 (type :KeyboardType) -> (result :T.VoidResult);
    hideVirtualKeyboard @11 () -> (result :T.VoidResult);

    # -- Direct Actions --

    commitText     @12 (text :Text) -> ();
    setPreedit     @13 (text :Text, cursorOffset :UInt32) -> ();
    confirmPreedit @14 () -> ();
    cancelPreedit  @15 () -> ();

    # -- Events --

    subscribe      @16 (filter :TextInputEventFilter)
                    -> (stream :TextInputEventStream);

    # -- Audit-7: Input modality support --

    # Enumerate available input modalities (keyboard, voice, handwriting, etc.).
    listModalities  @17 () -> (modalities :List(InputModalityInfo));

    # Query voice input capabilities for the current IME.
    getVoiceInfo    @18 () -> (info :VoiceInputInfo);

    # Query handwriting recognition capabilities.
    getHandwritingInfo @19 () -> (info :HandwritingInfo);

    # Query predictive input capabilities.
    getPredictionInfo @20 () -> (info :PredictionInfo);

    # Audit-10: per-context modality override for switchInputMethod.
    switchInputMethodForContext @21 (ctx :T.ImeContextId, id :T.InputMethodId, overrideModality :InputModality) -> (result :T.VoidResult);
}

# ── Context ───────────────────────────────────────────────────

struct ContextRequest {
    contentType    @0 :ContentType;
    purpose        @1 :TextPurpose;
    multiline      @2 :Bool;
    maxLength      @3 :UInt32;
    surrounding    @4 :Text;
    cursorPosition @5 :UInt32;
    metadata       @6 :List(T.Meta);
}

struct ContextUpdate {
    union {
        surrounding @0 :SurroundingText;
        contentType @1 :ContentType;
        purpose     @2 :TextPurpose;
    }
}

struct SurroundingText {
    text           @0 :Text;
    cursorPosition @1 :UInt32;
    selectStart    @2 :UInt32;
    selectEnd      @3 :UInt32;
}

enum ContentType {
    plainText @0;
    password  @1;
    number    @2;
    email     @3;
    phone     @4;
    url       @5;
    search    @6;
    date      @7;
    time      @8;
    dateTime  @9;
    filename  @10;
    custom    @11;
    # Audit-7: additional content types for IME behavior.
    code      @12;
    math      @13;
    emoji     @14;
    markup    @15;
    searchQuery @16;
}

enum TextPurpose {
    normal   @0;
    alpha    @1;
    digits   @2;
    number   @3;
    phone    @4;
    url      @5;
    email    @6;
    password @7;
    terminal @8;
    custom   @9;
}

enum KeyboardType {
    systemDefault @0;
    full     @1;
    compact  @2;
    numeric  @3;
    phone    @4;
    terminal @5;
    custom   @6;
}

# ── Input Method ──────────────────────────────────────────────

struct InputMethodInfo {
    id        @0 :T.InputMethodId;
    name      @1 :Text;
    languages @2 :List(Text);
    active    @3 :Bool;
    builtin   @4 :Bool;
    # Audit-9: input modality for this method (keyboard, voice, etc.).
    modality  @5 :InputModality;
}

struct InputMethodState {
    active        @0 :Bool;
    # The currently active input method. A zero-value ID (id == 0)
    # means no method has been selected yet. When `active` is false,
    # this field is irrelevant.
    currentMethod @1 :T.InputMethodId;
    composing     @2 :Bool;
    preeditText   @3 :Text;
    preeditCursor @4 :UInt32;
}

# ── Events ────────────────────────────────────────────────────

interface TextInputEventStream {
    next   @0 () -> (event :TextInputEvent);
    cancel @1 () -> T.VoidResult;
}

struct TextInputEventFilter {
    contextIds @0 :List(T.ImeContextId);
    kinds      @1 :List(TextInputEventKind);
}

enum TextInputEventKind {
    commit                @0;
    preedit               @1;
    key                   @2;
    inputMethodChanged    @3;
    virtualKeyboardShown  @4;
    virtualKeyboardHidden @5;
    custom                @6;
}

struct TextInputEvent {
    union {
        commit               @0 :CommitEvent;
        preedit              @1 :PreeditEvent;
        keyEvent             @2 :KeyEvent;
        inputMethodChanged   @3 :InputMethodInfo;
        virtualKeyboardShown @4 :KeyboardType;
        virtualKeyboardHidden @5 :Void;
        # Audit-9: voice input event (from VoiceInputEvent).
        voiceInput           @6 :VoiceInputEvent;
        # Audit-9: handwriting recognition event.
        handwriting          @7 :HandwritingEvent;
        # Audit-9: neural (BCI) input event.
        neuralInput          @8 :NeuralInputEvent;
        custom               @9 :UnknownTextInputEvent;
    }
}

struct CommitEvent {
    contextId @0 :T.ImeContextId;
    text      @1 :Text;
}

struct PreeditEvent {
    contextId      @0 :T.ImeContextId;
    text           @1 :Text;
    cursorPosition @2 :UInt32;
    selectStart    @3 :UInt32;
    selectEnd      @4 :UInt32;
}

struct KeyEvent {
    key       @0 :Text;
    codepoint @1 :UInt32;
    action    @2 :KeyAction;
    modifiers @3 :T.ModifierState;
}

enum KeyAction {
    pressed  @0;
    released @1;
    custom   @2;
}

struct UnknownTextInputEvent {
    typeId  @0 :UInt64;
    payload @1 :Data;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-7: Extended input modality support for IME
#
# Voice input, handwriting recognition, predictive input, AR/spatial
# keyboard, and brain-computer interface. These structs describe
# capabilities for each input modality beyond keyboard.
# ═══════════════════════════════════════════════════════════════════════

# ── Input Modality ────────────────────────────────────────────

enum InputModality {
    keyboard @0;
    voice @1;
    handwriting @2;
    gesture @3;
    neural @4;            # Brain-computer interface
    spatial @5;           # AR/spatial keyboard
    hybrid @6;            # Combination of modalities
    custom @7;
}

struct InputModalityInfo {
    modality @0 :InputModality;
    name @1 :Text;
    # Languages supported by this modality.
    languages @2 :List(Text);
    # Whether this modality is currently available.
    available @3 :Bool;
    # Capabilities of this modality.
    capabilities @4 :List(IMECapability);
}

# ── Voice Input ───────────────────────────────────────────────

struct VoiceInputInfo {
    # BCP 47 language tag for voice recognition.
    language @0 :Text;
    # Whether continuous dictation is supported.
    continuous @1 :Bool;
    # Whether offline recognition is available.
    offline @2 :Bool;
    # Optional wake word that activates listening.
    wakeWord @3 :Text;
    noiseSuppression @4 :Bool;
    autoPunctuation @5 :Bool;
    # Maximum recording duration before auto-commit.
    maxDuration @6 :T.Duration;
}

struct VoiceInputEvent {
    state @0 :VoiceInputState;
    # Recognized text (empty for partial results).
    text @1 :Text;
    # Recognition confidence (0.0-1.0).
    confidence @2 :Float32;
    # Whether this is a partial (interim) result.
    partial @3 :Bool;
    # Alternative recognitions ranked by confidence.
    alternatives @4 :List(Text);
}

enum VoiceInputState {
    idle @0;
    listening @1;
    processing @2;
    error @3;
    custom @4;
}

# ── Handwriting Recognition ───────────────────────────────────

struct HandwritingInfo {
    # Languages supported for handwriting recognition.
    languages @0 :List(Text);
    # Whether multi-stroke recognition is supported.
    strokes @1 :Bool;
    # Whether continuous handwriting (sentence-level) is supported.
    continuous @2 :Bool;
    # Whether gesture shortcuts (delete, space) are recognized.
    gestures @3 :Bool;
    recognition @4 :HandwritingRecognition;
}

enum HandwritingRecognition {
    online @0;          # Real-time stroke recognition
    offline @1;         # Image-based recognition
    hybrid @2;          # Both online and offline
    custom @3;
}

struct HandwritingEvent {
    strokes @0 :List(Stroke);
    recognized @1 :Text;
    alternatives @2 :List(Text);
    confidence @3 :Float32;
}

struct Stroke {
    points @0 :List(T.Vec2);
    pressure @1 :List(Float32);
    timestamp @2 :T.Timestamp;
}

# ── Predictive Input / AI Suggestions ─────────────────────────

struct PredictionInfo {
    # Model name or version identifier.
    model @0 :Text;
    # Whether inference runs on-device.
    offline @1 :Bool;
    # Whether the model personalizes from user input.
    personalization @2 :Bool;
    # Number of words of context used for prediction.
    contextWindow @3 :UInt32;
    maxSuggestions @4 :UInt32;
}

struct PredictionEvent {
    suggestions @0 :List(Text);
    completions @1 :List(Text);
    corrections @2 :List(Text);
    emojis @3 :List(Text);
    timestamp @4 :T.Timestamp;
}

# ── AR/Spatial Keyboard ───────────────────────────────────────

struct SpatialKeyboardInfo {
    tracking @0 :SpatialTracking;
    handedness @1 :Handedness;
    # Relative key size multiplier (1.0 = default).
    keySize @2 :Float32;
    feedback @3 :SpatialFeedback;
}

enum SpatialTracking {
    hand @0;            # Hand tracking
    eye @1;             # Eye tracking
    head @2;            # Head tracking
    hybrid @3;          # Combination
    custom @4;
}

enum Handedness {
    left @0;
    right @1;
    both @2;
    custom @3;
}

enum SpatialFeedback {
    visual @0;
    haptic @1;
    audio @2;
    none @3;
    custom @4;
}

struct SpatialKeyEvent {
    # Finger position in 3D space.
    finger @0 :T.Vec3;
    # Detected key character or label.
    key @1 :Text;
    confidence @2 :Float32;
    timestamp @3 :T.Timestamp;
}

# ── Brain-Computer Interface ──────────────────────────────────

struct NeuralInputInfo {
    type @0 :NeuralInputType;
    # Number of EEG/EMG channels.
    channels @1 :UInt32;
    # Sampling rate in Hz.
    samplingRate @2 :UInt32;
    # ADC resolution in bits.
    resolution @3 :UInt32;
    latency @4 :T.Duration;
}

enum NeuralInputType {
    eeg @0;             # Electroencephalography
    emg @1;             # Electromyography
    fnirs @2;           # Functional near-infrared spectroscopy
    custom @3;
}

struct NeuralInputEvent {
    # Decoded command string from neural signal processing.
    command @0 :Text;
    confidence @1 :Float32;
    timestamp @2 :T.Timestamp;
}

# ── IME Capability Enumeration ────────────────────────────────

# Typed capability flags for IME input methods.
enum IMECapability {
    keyboard @0;
    voice @1;
    handwriting @2;
    gesture @3;
    neural @4;
    spatial @5;
    prediction @6;
    completion @7;
    correction @8;
    emoji @9;
    other @10;
    custom @11;
}

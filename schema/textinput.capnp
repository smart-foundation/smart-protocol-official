@0xa1b2c3d4e5f60009;

using T = import "types.capnp";

# ══════════════════════════════════════════════════════════════════════
# TextInput — text input method (IME) management and event streaming.
#
# Improvements beyond the original schema:
#   - InputMethodInfo.id uses T.InputMethodId (was raw Text).
#   - InputMethodInfo.icon uses T.DataHandle (was raw Data).
#   - InputMethodInfo.languages uses List(T.Language) (Audit-6) to enable
#     language availability queries without separate locale calls.
#   - listInputMethods uses T.Pagination.
#   - commitText @36 = T.DataHandle variant for very large text pastes
#     (pasting entire documents). Original @11 retained for short strings.
#   - All enums have custom variants for forward compatibility.
#   - EventSubscription has cancel for clean teardown.
#   - TextInputEvent union has custom variant.
#   - SurroundingText supports pagination via offset/limit.
# ══════════════════════════════════════════════════════════════════════

interface TextInput {
    createContext @0 (surfaceId :T.SurfaceId, request :ContextRequest) -> (contextId :T.ImeContextId);
    destroyContext @1 (contextId :T.ImeContextId) -> T.VoidResult;
    updateContext @2 (contextId :T.ImeContextId, request :ContextRequest) -> T.VoidResult;

    enable @3 (contextId :T.ImeContextId) -> T.VoidResult;
    disable @4 (contextId :T.ImeContextId) -> T.VoidResult;
    reset @5 (contextId :T.ImeContextId) -> T.VoidResult;

    listInputMethods @6 (pagination :T.Pagination) -> (methods :List(InputMethodInfo), total :UInt64);
    switchInputMethod @7 (methodId :T.InputMethodId) -> T.VoidResult;
    getInputMethodState @8 (contextId :T.ImeContextId) -> (state :InputMethodState);

    showKeyboard @9 (contextId :T.ImeContextId) -> T.VoidResult;
    hideKeyboard @10 (contextId :T.ImeContextId) -> T.VoidResult;

    commitText @11 (contextId :T.ImeContextId, text :Text) -> T.VoidResult;
    setPreedit @12 (contextId :T.ImeContextId, text :Text, cursor :UInt32) -> T.VoidResult;
    confirmPreedit @13 (contextId :T.ImeContextId) -> T.VoidResult;
    cancelPreedit @14 (contextId :T.ImeContextId) -> T.VoidResult;

    # Audit-6: listLanguages enables caller to discover which input methods
    # support a given locale without cross-referencing translation.capnp.
    listLanguages @18 (pagination :T.Pagination) -> (languages :List(T.Language), total :UInt64);

    # Audit-6: large-payload commit. For very large text pastes (entire documents)
    # the backend should use T.DataHandle to avoid 1MB inline text limits.
    commitTextHandle @19 (contextId :T.ImeContextId, text :T.DataHandle, encoding :TextEncoding) -> T.VoidResult;

    subscribeEvents @15 () -> (subscription :EventSubscription);
    pullEvents @16 (subscription :EventSubscription) -> (events :List(TextInputEvent));
    cancelEvents @17 (subscription :EventSubscription) -> T.VoidResult;

    # Audit-7: Dictation (voice-to-text) pipeline.
    startDictation @20 (contextId :T.ImeContextId, request :DictationRequest) -> (session :DictationSession);
    commitDictation @21 (session :DictationSession) -> T.VoidResult;
    cancelDictation @22 (session :DictationSession) -> T.VoidResult;

    # Audit-7: Handwriting recognition pipeline.
    submitStroke @23 (contextId :T.ImeContextId, stroke :StrokeData) -> (result :RecognitionResult);
    recognizeGesture @24 (contextId :T.ImeContextId, strokes :List(StrokeData)) -> (result :RecognitionResult);

    # Audit-7: Predictive text.
    getSuggestions @25 (contextId :T.ImeContextId, pagination :T.Pagination) -> (suggestions :List(TextSuggestion), total :UInt32);
    addUserWord @26 (word :Text) -> T.VoidResult;
    removeUserWord @27 (word :Text) -> T.VoidResult;

    # Audit-10: request user input during composition (e.g., password prompt, confirmation).
    requestInput @28 (contextId :T.ImeContextId, request :ImeInputRequest) -> (handle :ImeInputHandle);

    # Audit-10: respond to an IME input request.
    respondInput @29 (handle :ImeInputHandle, response :ImeInputResponse) -> T.VoidResult;

    # Audit-10: cancel a pending IME input request.
    cancelInput @30 (handle :ImeInputHandle) -> T.VoidResult;
}

interface EventSubscription {
    pull @0 () -> (events :List(TextInputEvent));
    cancel @1 () -> T.VoidResult;
    # Audit-9: bounded pull to prevent unbounded event lists.
    pullPaged @2 (pagination :T.Pagination) -> (events :List(TextInputEvent), totalCount :UInt32);
}

struct ContextRequest {
    contentType @0 :ContentType;
    textPurpose @1 :TextPurpose;
    multiline @2 :Bool;
    maxLength @3 :UInt32;
    surrounding @4 :SurroundingText;
    cursorPos @5 :UInt32;
}

enum ContentType {
    normal @0;
    text @1;
    password @2;
    email @3;
    url @4;
    phone @5;
    name @6;
    number @7;
    date @8;
    time @9;
    datetime @10;
    custom @11;
    # Audit-7: additional content types for IME behavior.
    code @12;
    math @13;
    emoji @14;
    markup @15;
    searchQuery @16;
    numeric @17;
    currency @18;
    address @19;
}

enum TextPurpose {
    normal @0;
    title @1;
    label @2;
    description @3;
    custom @4;
}

struct SurroundingText {
    text @0 :Text;
    cursor @1 :UInt32;
    anchor @2 :UInt32;
    # Pagination for large surrounding text contexts (UInt64 for large docs).
    offset @3 :UInt64;
    limit @4 :UInt64;
}

struct InputMethodInfo {
    id @0 :T.InputMethodId;
    name @1 :Text;
    icon @2 :T.DataHandle;
    enabled @3 :Bool;
    # Languages supported by this input method. Added in Audit-6 to enable
    # cross-schema language availability queries (consulted by translation,
    # speech, app locale negotiation).
    languages @4 :List(T.Language);
}

struct InputMethodState {
    composing @0 :Bool;
    preeditText @1 :Text;
    preeditCursor @2 :UInt32;
    # Audit-9: language stack for code-switching during composition.
    languageStack @3 :List(T.Language);
    # Currently active language for this composition.
    activeLanguage @4 :T.Language;
}

struct TextInputEvent {
    id @0 :T.EventId;
    contextId @1 :T.ImeContextId;
    timestamp @2 :T.Timestamp;
    type @3 :TextInputEventType;
    text @4 :Text;
    # Audit-9: per-character timing data for latency profiling.
    charTimings @5 :List(CharTiming);
}

# Audit-9: per-character timing data.
struct CharTiming {
    char @0 :Text;
    utf8Offset @1 :UInt32;
    keydownToCommitMs @2 :UInt32;
}

enum TextInputEventType {
    cursorMove @0;
    selection @1;
    contentChange @2;
    activate @3;
    deactivate @4;
    custom @5;
}

# Audit-6: encoding hint for large text commited via commitTextHandle.
# Plain UTF-8 by default; custom variant allows registry of future encodings.
enum TextEncoding {
    utf8 @0;
    utf16 @1;
    utf32 @2;
    custom @3;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-7: Dictation, handwriting, and predictive text support
#
# Voice-to-text pipeline, gesture/text recognition, and autocomplete.
# These structs extend the keyboard-centric TextInput schema to support
# additional input modalities.
# ═══════════════════════════════════════════════════════════════════════

# ── Dictation (Voice-to-Text) ─────────────────────────────────

struct DictationRequest {
    # BCP 47 language tag for recognition.
    language @0 :Text;
    # Whether to use offline (on-device) recognition.
    offline @1 :Bool;
    # Whether to enable noise suppression.
    noiseSuppression @2 :Bool;
    # Maximum recording duration before auto-commit.
    maxDuration @3 :T.Duration;
}

struct DictationSession {
    id @0 :Text;
    contextId @1 :T.ImeContextId;
    state @2 :DictationState;
}

enum DictationState {
    idle @0;
    listening @1;
    processing @2;
    committed @3;
    cancelled @4;
    error @5;
    custom @6;
}

# ── Handwriting Recognition ───────────────────────────────────

struct StrokeData {
    # Ordered list of points forming the stroke.
    points @0 :List(T.Vec2i);
    # Pressure values per point (empty if not available).
    pressure @1 :List(Float32);
    # Timestamp of stroke start.
    timestamp @2 :T.Timestamp;
}

struct RecognitionResult {
    # Top recognized text.
    text @0 :Text;
    # Alternative recognitions ranked by confidence.
    alternatives @1 :List(Text);
    # Recognition confidence (0.0-1.0).
    confidence @2 :Float32;
}

# ── Predictive Text ───────────────────────────────────────────

struct TextSuggestion {
    # Suggested text.
    text @0 :Text;
    # Confidence score (0.0-1.0).
    score @1 :Float32;
    # Source of the suggestion.
    source @2 :SuggestionSource;
}

enum SuggestionSource {
    model @0;           # Language model prediction
    user @1;            # User dictionary entry
    history @2;         # Based on user's typing history
    custom @3;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-10: Interactive Input During Composition
#
# Allows IME to request user input mid-composition (e.g., password
# entry, confirmation dialogs, file path selection). This is a
# deeper protocol change enabling bidirectional stdin during IME.
# ═══════════════════════════════════════════════════════════════════════

struct ImeInputRequest {
    # What kind of input is being requested.
    type @0 :ImeInputType;
    # Prompt message displayed to the user.
    message @1 :Text;
    # Whether input is required (null = optional).
    required @2 :Bool;
    # Timeout for the input request (null = no timeout).
    timeout @3 :T.Duration;
}

enum ImeInputType {
    text @0;
    password @1;
    confirm @2;
    choice @3;
    path @4;
    number @5;
    custom @6;
}

struct ImeInputHandle {
    id @0 :Text;
    contextId @1 :T.ImeContextId;
}

struct ImeInputResponse {
    union {
        text @0 :Text;
        confirmed @1 :Bool;
        cancelled @2 :Void;
        custom @3 :Data;
    }
}

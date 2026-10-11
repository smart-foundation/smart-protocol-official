@0xa1b2c3d4e5f60032;

# ══════════════════════════════════════════════════════════════════════
# IME — input method editing: text contexts, composition, input methods.
#
# WHAT THIS IS
#   The ONE text-input contract in the protocol. textinput.capnp was merged
#   into this file and deleted: the two files had drifted into incompatible
#   twins (`ContextRequest`, `SurroundingText`, `InputMethodInfo` and
#   `InputMethodState` existed in both with different fields), so a client
#   written against one got silently wrong data on the other.
#
#   This file keeps the ImeSession-based design and absorbs textinput's better
#   halves: per-surface contexts, per-context enable/disable/reset, a
#   `T.DataHandle` commit for document-sized pastes, the language stack, the
#   dictation/stroke/suggestion pipelines, and interactive input requests
#   (a password prompt is an IME concern).
#
# WHO CONSUMES IT
#   Apps that accept text (create a context, receive commits), the shell and
#   on-screen keyboards (drive composition), automation.
#
# WHAT IS DELIBERATELY OPEN
#   Every vocabulary that a future input modality would have to extend is an
#   open token, not an enum: modality, content type, purpose and keyboard
#   type. A modality invented in 2046 — gaze dictation, mid-air haptics, a
#   direct neural channel — is representable today, with no schema change
#   and no ordinal. The previous draft froze `InputModality`
#   {keyboard, voice, handwriting, gesture, neural, spatial, hybrid} and then
#   put it in a REQUIRED position (`switchInputMethodForContext`), so the one
#   file that promises "any future input modality" could not express one.
#
# WHAT IS DELIBERATELY OPAQUE
#   Context identity (`T.ImeContextId`), method identity (`T.InputMethodId`),
#   stroke payloads (`T.DataHandle`), session and input-request handles
#   (server-issued).
#
# HOW IT RELATES TO OTHER SERVICES
#   compositor.capnp publishes the service-session handshake, the key-action
#   vocabulary and the unknown-event envelope; this file imports them rather
#   than declaring rivals.
# ══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using C = import "compositor.capnp";

# ══════════════════════════════════════════════════════════════════════
# SESSION
#
# `handshake` takes the shared `compositor.SessionRequest`, so every
# session-based service in the protocol is entered through the same door.
#
# Ordinal note: Cap'n Proto requires sequential interface ordinals, so
# absorbing textinput renumbered this interface. The prior draft's @0–@21
# mapped as: handshake @0, createContext @1, destroyContext @2, updateContext
# @3, enable @4, disable @5, reset @6, listInputMethods @7, switchInputMethod
# @8, getInputMethodState @9, showVirtualKeyboard @10, hideVirtualKeyboard
# @11, commitText @12, setPreedit @13, confirmPreedit @14, cancelPreedit @15,
# subscribe @16, listModalities @17, getVoiceInfo @18, getHandwritingInfo @19,
# getPredictionInfo @20, switchInputMethodForContext @21. Everything from @22
# on is absorbed from the deleted textinput.capnp.
# ══════════════════════════════════════════════════════════════════════

interface ImeSession {

    struct HandshakeResponse {
        sessionId     @0 :T.SessionId;
        agreedVersion @1 :T.Version;
        granted       @2 :List(C.GrantedCapability);
        denied        @3 :List(C.DeniedCapability);
        service       @4 :C.ServiceInfo;
        result        @5 :C.HandshakeResult;
        # Ungated discovery: the methods that exist are published before any
        # capability is held, so a caller can learn what it could switch to.
        inputMethods  @6 :List(InputMethodInfo);
    }

    handshake @0 (request :C.SessionRequest)
               -> (response :HandshakeResponse);

    # -- Context --

    createContext  @1 (surface :T.SurfaceId, request :ContextRequest)
                    -> (result :ContextResult);
    destroyContext @2 (id :T.ImeContextId) -> (result :T.VoidResult);
    updateContext  @3 (id :T.ImeContextId, update :ContextUpdate)
                    -> (result :T.VoidResult);

    # -- Enable / Disable / Reset (per context) --

    enable  @4 (id :T.ImeContextId) -> (result :T.VoidResult);
    disable @5 (id :T.ImeContextId) -> (result :T.VoidResult);
    reset   @6 (id :T.ImeContextId) -> (result :T.VoidResult);

    # -- Input Method --

    listInputMethods    @7 (pagination :T.Pagination)
                         -> (methods :List(InputMethodInfo), total :UInt64);
    switchInputMethod   @8 (id :T.InputMethodId) -> (result :T.VoidResult);
    getInputMethodState @9 (id :T.ImeContextId) -> (state :InputMethodState);
    switchInputMethodForContext @10 (id :T.ImeContextId,
                                     method :T.InputMethodId,
                                     overrideModality :Text)
                                 -> (result :T.VoidResult);

    # -- Virtual Keyboard --

    showVirtualKeyboard @11 (id :T.ImeContextId, type :Text)
                         -> (result :T.VoidResult);
    hideVirtualKeyboard @12 (id :T.ImeContextId) -> (result :T.VoidResult);

    # -- Direct Actions --

    commitText     @13 (id :T.ImeContextId, text :Text)
                    -> (result :T.VoidResult);
    # Large commits (pasting a document) travel as a buffer reference.
    commitTextHandle @14 (id :T.ImeContextId, text :T.DataHandle,
                          encoding :Text)
                      -> (result :T.VoidResult);
    setPreedit     @15 (id :T.ImeContextId, text :Text, cursorOffset :UInt32)
                    -> (result :T.VoidResult);
    confirmPreedit @16 (id :T.ImeContextId) -> (result :T.VoidResult);
    cancelPreedit  @17 (id :T.ImeContextId) -> (result :T.VoidResult);

    # -- Events --

    subscribe @18 (filter :TextInputEventFilter)
               -> (stream :TextInputEventStream);

    # -- Modalities --

    listModalities @19 () -> (modalities :List(InputModalityInfo));
    # One open method instead of one per modality: a backend that has no
    # voice engine no longer needs a stub for a method it cannot answer, and
    # a modality the schema has never heard of publishes its parameters
    # through `parameters` with no new field.
    getModalityInfo @20 (modality :Text) -> (info :ModalityInfo);

    # -- Languages --

    listLanguages @21 (pagination :T.Pagination)
                   -> (languages :List(T.Language), total :UInt64);

    # -- Dictation (absorbed from textinput.capnp) --

    startDictation  @22 (id :T.ImeContextId, request :DictationRequest)
                     -> (result :DictationResult);
    commitDictation @23 (session :DictationSession) -> (result :T.VoidResult);
    cancelDictation @24 (session :DictationSession) -> (result :T.VoidResult);

    # -- Handwriting (absorbed from textinput.capnp) --

    submitStroke     @25 (id :T.ImeContextId, stroke :Stroke)
                     -> (result :RecognitionResult);
    recognizeGesture @26 (id :T.ImeContextId, strokes :List(Stroke))
                     -> (result :RecognitionResult);

    # -- Predictive text (absorbed from textinput.capnp) --

    getSuggestions @27 (id :T.ImeContextId, pagination :T.Pagination)
                    -> (suggestions :List(TextSuggestion), total :UInt64);
    addUserWord    @28 (word :Text) -> (result :T.VoidResult);
    removeUserWord @29 (word :Text) -> (result :T.VoidResult);

    # -- Interactive input during composition (absorbed from textinput.capnp) --

    requestInput @30 (id :T.ImeContextId, request :ImeInputRequest)
                  -> (handle :ImeInputHandle);
    respondInput @31 (handle :ImeInputHandle, response :ImeInputResponse)
                 -> (result :T.VoidResult);
    cancelInput  @32 (handle :ImeInputHandle) -> (result :T.VoidResult);
}

# ── Context ───────────────────────────────────────────────────

struct ContextResult {
    union {
        context @0 :T.ImeContextId;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct ContextRequest {
    # Open tokens: today's spellings are published as conformance constants
    # at the end of this file; an unrecognised one is ignored, not rejected.
    contentType @0 :Text;
    purpose     @1 :Text;
    multiline   @2 :Bool;
    maxLength   @3 :UInt32;
    surrounding @4 :SurroundingText;
    metadata    @5 :List(T.Meta);
}

struct ContextUpdate {
    union {
        surrounding @0 :SurroundingText;
        contentType @1 :Text;
        purpose     @2 :Text;
        custom      @3 :T.StringMap;
        unknown     @4 :Void;
    }
}

struct SurroundingText {
    text           @0 :Text;
    cursorPosition @1 :UInt32;
    selectStart    @2 :UInt32;
    selectEnd      @3 :UInt32;
    # Pagination for large surrounding-text contexts.
    offset @4 :UInt64;
    limit  @5 :UInt64;
}

# ── Input Method ──────────────────────────────────────────────

struct InputMethodInfo {
    id        @0 :T.InputMethodId;
    name      @1 :Text;
    icon      @2 :T.DataHandle;
    languages @3 :List(T.Language);
    active    @4 :Bool;
    enabled   @5 :Bool;
    builtin   @6 :Bool;
    # Open token — see the conformance constants at the end of this file.
    modality  @7 :Text;
}

struct InputMethodState {
    active    @0 :Bool;
    # Explicit, not a sentinel: a zero-value ID used to mean "no method",
    # which collided with a legal ID 0.
    currentMethod @1 :CurrentMethod;
    composing     @2 :Bool;
    preeditText   @3 :Text;
    preeditCursor @4 :UInt32;
    languageStack @5 :List(T.Language);
    activeLanguage @6 :T.Language;
}

struct CurrentMethod {
    union {
        none    @0 :Void;
        method  @1 :T.InputMethodId;
        unknown @2 :Void;
    }
}

# ── Modalities ────────────────────────────────────────────────

struct InputModalityInfo {
    modality    @0 :Text;
    name        @1 :Text;
    languages   @2 :List(T.Language);
    available   @3 :Bool;
    capabilities @4 :List(Text);
}

# One open descriptor replaces the per-modality info museum (voice,
# handwriting, prediction, spatial keyboard each had their own struct and
# their own method). Everything a modality needs to declare is an open key,
# so a modality invented tomorrow needs no ordinal.
struct ModalityInfo {
    modality    @0 :Text;
    name        @1 :Text;
    languages   @2 :List(T.Language);
    available   @3 :Bool;
    capabilities @4 :List(Text);
    parameters  @5 :T.StringMap;
}

# ── Events ────────────────────────────────────────────────────

interface TextInputEventStream {
    pull   @0 (maxEvents :UInt32) -> (events :List(TextInputEvent));
    cancel @1 () -> T.VoidResult;
}

struct TextInputEventFilter {
    contextIds @0 :List(T.ImeContextId);
    # `other` is a filterable kind, so a consumer can ask for "every event
    # kind this schema was frozen before".
    kinds      @1 :List(TextInputEventKind);
}

enum TextInputEventKind {
    commit                @0;
    preedit               @1;
    keyEvent              @2;
    inputMethodChanged    @3;
    virtualKeyboardShown  @4;
    virtualKeyboardHidden @5;
    voiceInput            @6;
    handwriting           @7;
    neuralInput           @8;
    prediction            @9;
    spatialKey            @10;
    other                 @11;
    custom                @12;
}

struct TextInputEvent {
    union {
        commit               @0 :CommitEvent;
        preedit              @1 :PreeditEvent;
        keyEvent             @2 :ImeKeyEvent;
        inputMethodChanged   @3 :InputMethodInfo;
        virtualKeyboardShown @4 :Text;
        virtualKeyboardHidden @5 :Void;
        voiceInput           @6 :VoiceInputEvent;
        handwriting          @7 :HandwritingEvent;
        neuralInput          @8 :NeuralInputEvent;
        prediction           @9 :PredictionEvent;
        spatialKey           @10 :SpatialKeyEvent;
        unknown              @11 :T.UnknownEvent;
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

struct ImeKeyEvent {
    # The logical key. `name` is an open token; neither it nor `codepoint`
    # asserts a keyboard layout or a key-numbering scheme.
    key       @0 :Text;
    codepoint @1 :UInt32;
    transition @2 :C.KeyTransition;
    modifiers @3 :T.ModifierState;
    metadata @4 :T.StringMap;
}

# ── Voice, handwriting, neural, prediction, spatial ───────────

struct VoiceInputEvent {
    state        @0 :Text;
    text         @1 :Text;
    confidence   @2 :Float32;
    partial      @3 :Bool;
    alternatives @4 :List(Text);
}

struct HandwritingEvent {
    strokes      @0 :List(Stroke);
    recognized   @1 :Text;
    alternatives @2 :List(Text);
    confidence   @3 :Float32;
}

struct NeuralInputEvent {
    command    @0 :Text;
    confidence @1 :Float32;
    timestamp  @2 :T.Timestamp;
}

struct PredictionEvent {
    suggestions @0 :List(Text);
    completions @1 :List(Text);
    corrections @2 :List(Text);
    emojis      @3 :List(Text);
    timestamp   @4 :T.Timestamp;
}

struct SpatialKeyEvent {
    finger     @0 :T.Vec3;
    key        @1 :Text;
    confidence @2 :Float32;
    timestamp  @3 :T.Timestamp;
}

# A stroke's point and pressure arrays travel as BUFFER REFERENCES. A stylus
# generates hundreds of points per second; an inline list is a copy per
# stroke, forever. Both arrays are `pointCount` entries long, so the payload
# is decodable without any side channel.
struct Stroke {
    points     @0 :T.DataHandle;
    pressure   @1 :T.DataHandle;
    pointCount @2 :UInt32;
    timestamp  @3 :T.Timestamp;
}

struct DictationRequest {
    language          @0 :Text;
    offline           @1 :Bool;
    noiseSuppression  @2 :Bool;
    maxDuration       @3 :T.Duration;
    metadata @4 :T.StringMap;
}

struct DictationSession {
    sessionId @0 :UInt64;
    contextId @1 :T.ImeContextId;
    state     @2 :Text;
    metadata @3 :T.StringMap;
}

struct DictationResult {
    union {
        session @0 :DictationSession;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct RecognitionResult {
    text         @0 :Text;
    alternatives @1 :List(Text);
    confidence   @2 :Float32;
    metadata @3 :T.StringMap;
}

struct TextSuggestion {
    text  @0 :Text;
    score @1 :Float32;
    source @2 :Text;
    metadata @3 :T.StringMap;
}

# ── Interactive input during composition ──────────────────────

struct ImeInputRequest {
    type     @0 :Text;
    message  @1 :Text;
    required @2 :Bool;
    timeout  @3 :T.Duration;
    metadata @4 :T.StringMap;
}

struct ImeInputHandle {
    id        @0 :UInt64;
    contextId @1 :T.ImeContextId;
}

struct ImeInputResponse {
    union {
        text       @0 :Text;
        confirmed  @1 :Bool;
        cancelled  @2 :Void;
        custom     @3 :T.StringMap;
        unknown    @4 :Void;
    }
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Published so today's tools have a discoverable spelling. They are Text and
# deliberately NOT enums: an enum here would be an eternal commitment to
# today's list of input modalities, content types and keyboard layouts.
# An unrecognised value MUST be ignored, never rejected.
# ══════════════════════════════════════════════════════════════════════

const modalityKeyboard    :Text = "keyboard";
const modalityVoice       :Text = "voice";
const modalityHandwriting :Text = "handwriting";
const modalityGesture     :Text = "gesture";
const modalityNeural      :Text = "neural";
const modalitySpatial     :Text = "spatial";
const modalityHybrid      :Text = "hybrid";

const contentPlainText :Text = "plainText";
const contentPassword  :Text = "password";
const contentNumber    :Text = "number";
const contentEmail     :Text = "email";
const contentPhone     :Text = "phone";
const contentUrl       :Text = "url";
const contentSearch    :Text = "search";
const contentDate      :Text = "date";
const contentTime      :Text = "time";
const contentDateTime  :Text = "dateTime";
const contentFilename  :Text = "filename";
const contentCode      :Text = "code";
const contentMath      :Text = "math";
const contentEmoji     :Text = "emoji";
const contentMarkup    :Text = "markup";

const purposeNormal      :Text = "normal";
const purposeAlpha       :Text = "alpha";
const purposeDigits      :Text = "digits";
const purposeNumber      :Text = "number";
const purposePhone       :Text = "phone";
const purposeUrl         :Text = "url";
const purposeEmail       :Text = "email";
const purposePassword    :Text = "password";
const purposeTerminal    :Text = "terminal";
const purposeTitle       :Text = "title";
const purposeLabel       :Text = "label";
const purposeDescription :Text = "description";

const keyboardSystemDefault :Text = "systemDefault";
const keyboardFull          :Text = "full";
const keyboardCompact       :Text = "compact";
const keyboardNumeric       :Text = "numeric";
const keyboardSplit         :Text = "split";
const keyboardProjected     :Text = "projected";

const encodingUtf8  :Text = "utf8";
const encodingUtf16 :Text = "utf16";
const encodingUtf32 :Text = "utf32";

const inputText     :Text = "text";
const inputPassword :Text = "password";
const inputConfirm  :Text = "confirm";
const inputChoice   :Text = "choice";
const inputPath     :Text = "path";
const inputNumber   :Text = "number";

const suggestionModel  :Text = "model";
const suggestionUser   :Text = "user";
const suggestionHistory :Text = "history";

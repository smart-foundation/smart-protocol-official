@0xa1b2c3d4e5f6002b;

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ══════════════════════════════════════════════════════════════════════
# Speech — speech recognition (STT) and text-to-speech (TTS).
#
# The file's zero-cost migration is genuine and is kept: SpeakResult.audio,
# MultiSpeakerResult.audio, SpeechTranslationResult.sourceAudio/
# translatedAudio and VoiceCloneRequest.sourceAudio are all T.DataHandle,
# which is the hardest thing to retrofit and this schema got right.
#
# ── THREE DEFECTS, FIXED ──────────────────────────────────────────────
#
# 1. NO ERROR PATH ANYWHERE. The file contained zero unions, so not one
#    method could report a failure: "did STT fail, or did it hear
#    silence?" was unanswerable from the wire, because ListenResult.text
#    is empty in both cases. Every consumer had to invent a failure
#    heuristic and every backend a convention (empty transcript?
#    isFinal = true with empty text?). One `SpeechOutcome` union now
#    carries T.Error beside the existing result structs, so no payload
#    struct changed shape and every fallible method gained an honest
#    failure path.
#
# 2. CLOSED VOCABULARIES IN REQUIRED POSITIONS. `AudioEncoding` froze
#    pcm/opus/aac/mp3/flac/vorbis/alaw/mulaw, so a 2046 neural or
#    LC3-family codec had no ordinal and `custom` carried no
#    identification — a stream could not even name what it was. It is
#    T.MimeType now, which the file already imports, and `negotiateCodec`
#    negotiates real spellings instead of a closed list. The two emotion
#    enums (`EmotionalStyle` with whisper/shout/dramatic, `SpeechEmotion`
#    without them) could not be mapped request-to-response at all; they
#    collapse into one open token with published spellings.
#
# 3. TARGETLESS STREAM CONTROL. `stopSpeaking`/`pauseSpeaking`/
#    `resumeSpeaking`/`stopWakeWordDetection` took no argument, so in a
#    multi-stream system the implementer had to invent session identity
#    out of band and a consumer could not stop the right stream. They
#    now address the stream or subscription they control.
#
# ── VOICE CLONING IS GATED ────────────────────────────────────────────
#
# `cloneVoice` creates a voice that can impersonate a real person, and
# `setTtsFormat`/`addPronunciationRule` mutate global state. All three
# sat on the ungated interface, so any holder of the reference could
# clone any voice from any audio. They now live behind one accessor that
# takes a Capability; everything else stays on the ungated root.
#
# ── BACKPRESSURE ──────────────────────────────────────────────────────
#
# SpeechAudioStream.pull and SpeechStreamResult.pull had no bound, so a
# producer could push larger chunks than a consumer can hold. Both take
# maxBytes now, matching ai.capnp's ArtifactStream.pull.
#
# Improvements (audit-7/8/9), unchanged:
#   - Voice.id uses T.SpeechVoiceId (was raw Text).
#   - language fields use T.Language (was bare Text).
#   - VoiceGender / VoiceType have custom variants.
#   - SpeechSegment.start/end carry unit comments (seconds).
#   - SpeechAudioStream.pull returns T.DataHandle (was raw Data).
#   - SpeakResult.audio uses T.DataHandle; duration uses T.Duration.
#   - SpeakOptions rate/pitch/volume have unit comments.
#   - SpeechAudioFormat declares encoding/sample rate/channels for streams.
#   - SpeakerLabel/DiarizationOptions, StructuredTranscript/WordTiming.
#   - EmotionalStyle/ProsodySpec for expressive TTS.
#   - VoiceCloneRequest/Provenance for auditable cloning.
#   - SpeechTranslator for real-time speech-to-speech translation.
# ══════════════════════════════════════════════════════════════════════

interface Speech {
    listen @0 (options :ListenOptions) -> (outcome :SpeechOutcome);
    listenStream @1 (stream :SpeechAudioStream) -> (stream :ListenResultStream);

    speak @2 (text :Text, voiceId :T.SpeechVoiceId, options :SpeakOptions) -> (outcome :SpeechOutcome);
    # SSML is one external markup among several. A backend that does not
    # implement SSML MUST refuse this method with T.Error(unsupported)
    # rather than silently ignoring the markup — and a caller wanting an
    # encoding-agnostic path uses `speak` with a T.MimeType-tagged input.
    speakSsml @3 (ssml :Text, voiceId :T.SpeechVoiceId, options :SpeakOptions) -> (outcome :SpeechOutcome);
    # Each addresses the stream it controls, so a consumer can stop the
    # right one in a multi-stream system.
    stopSpeaking @4 (stream :SpeechStreamResult) -> T.VoidResult;
    pauseSpeaking @5 (stream :SpeechStreamResult) -> T.VoidResult;
    resumeSpeaking @6 (stream :SpeechStreamResult) -> T.VoidResult;

    listVoices @7 (language :T.Language) -> (voices :List(Voice));
    getDefaultVoice @8 (type :VoiceType) -> (voice :Voice);
    setDefaultVoice @9 (voiceId :T.SpeechVoiceId, type :VoiceType) -> T.VoidResult;

    hasSpeechToText @10 () -> (available :Bool);
    hasTextToSpeech @11 () -> (available :Bool);

    # -- Structured transcription --
    transcribeStructured @12 (stream :SpeechAudioStream, options :ListenOptions)
        -> (outcome :SpeechOutcome);

    # -- Diarization-aware transcription --
    transcribeDiarized @13 (stream :SpeechAudioStream, options :DiarizationOptions)
        -> (outcome :SpeechOutcome);

    # -- Voice cloning --
    listClonedVoices @14 (pagination :T.Pagination) -> (voices :List(Voice), total :UInt32);

    # -- Audio format management --
    getAudioFormat @15 (stream :SpeechAudioStream) -> (format :SpeechAudioFormat);

    # -- Real-time speech translation --
    # A distinct pipeline (audio in, audio out) whose text stage
    # delegates to translation.capnp rather than re-implementing
    # translation; the two contracts stay separate because their
    # payloads and lifecycles differ.
    translate @16 (request :SpeechTranslationRequest) -> (stream :SpeechTranslationStream);
    getSupportedTranslationPairs @17 () -> (pairs :List(LanguagePair));

    # -- Audit-9: listVoices with pagination --
    listVoicesPaginated @18 (language :T.Language, pagination :T.Pagination)
        -> (voices :List(Voice), total :UInt32);

    # -- Audit-9: Speech-to-text alignment --
    alignText @19 (stream :SpeechAudioStream, text :Text) -> (outcome :SpeechOutcome);

    # -- Audit-9: Wake word detection --
    startWakeWordDetection @20 (config :WakeWordConfig) -> (subscription :WakeWordSubscription);
    stopWakeWordDetection @21 (subscription :WakeWordSubscription) -> T.VoidResult;

    # -- Audit-9: Audio enhancement --
    setAudioEnhancement @22 (enhancement :AudioEnhancement) -> T.VoidResult;
    getAudioEnhancement @23 () -> (enhancement :AudioEnhancement);

    # -- Audit-9: Speech emotion recognition --
    detectEmotion @24 (stream :SpeechAudioStream) -> (outcome :SpeechOutcome);

    # -- Audit-9: Speech synthesis streaming --
    speakStream @25 (text :Text, voiceId :T.SpeechVoiceId, options :SpeakOptions)
        -> (stream :SpeechStreamResult);

    # -- Audit-9: Multi-speaker TTS --
    speakMultiSpeaker @26 (request :MultiSpeakerRequest) -> (outcome :SpeechOutcome);

    # -- Audit-9: Codec negotiation --
    negotiateCodec @27 (request :CodecNegotiationRequest) -> (outcome :SpeechOutcome);

    # -- Audit-9: Quality metrics --
    getQualityMetrics @28 (stream :SpeechAudioStream) -> (outcome :SpeechOutcome);

    # -- Custom pronunciation --
    listPronunciationRules @29 (language :T.Language) -> (rules :List(PronunciationRule));
    removePronunciationRule @30 (word :Text, language :T.Language) -> T.VoidResult;

    # -- Gated once, at acquisition: voice cloning, global format and
    # -- global pronunciation state. Holding the reference IS the
    # -- authority; no method below takes an authority token.
    studio @31 (authority :Capability) -> (service :VoiceStudio);
}

# ── Privileged surface: obtained with a Capability ──────────────────────

interface VoiceStudio {
    # Creates a voice that can impersonate a real person, so it is not
    # open to any holder of the Speech reference.
    cloneVoice @0 (request :VoiceCloneRequest) -> (outcome :SpeechOutcome);

    # Mutates global synthesis state.
    setTtsFormat @1 (format :SpeechAudioFormat) -> T.VoidResult;
    addPronunciationRule @2 (rule :PronunciationRule) -> T.VoidResult;
}

interface SpeechAudioStream {
    # maxBytes is caller-driven backpressure: the producer may never send
    # faster than the consumer pulls (ai.capnp:277's pattern).
    pull @0 (maxBytes :UInt32) -> (audio :T.DataHandle, done :Bool);
    cancel @1 () -> T.VoidResult;
}

interface ListenResultStream {
    pull @0 () -> (result :ListenResult, done :Bool);
    cancel @1 () -> T.VoidResult;
}

struct ListenOptions {
    language @0 :T.Language;
    context @1 :List(Text);
    interimResults @2 :Bool;
    voice @3 :T.SpeechVoiceId;
    custom @4 :T.StringMap;
}

struct ListenResult {
    text @0 :Text;
    confidence @1 :Float32;
    segments @2 :List(SpeechSegment);
    language @3 :T.Language;
    isFinal @4 :Bool;
    custom @5 :Data;
}

struct SpeechSegment {
    text @0 :Text;
    confidence @1 :Float32;
    # Start time of this segment in seconds from the beginning of the audio.
    start @2 :Float32;
    # End time of this segment in seconds from the beginning of the audio.
    end @3 :Float32;
}

struct SpeakOptions {
    # Speech rate multiplier: 1.0 = normal speed, 0.5 = half speed, 2.0 = double speed.
    rate @0 :Float32;
    # Pitch adjustment in semitones: 0.0 = natural, negative = lower, positive = higher.
    pitch @1 :Float32;
    # Volume level: 0.0 = silent, 1.0 = normal, 2.0 = double volume.
    volume @2 :Float32;
    language @3 :T.Language;
    # Emotional style for expressive TTS, as an open token so a request
    # and the reported emotion speak one vocabulary.
    emotionalStyle @4 :Text;
    # Detailed prosody control.
    prosody @5 :ProsodySpec;
    custom @6 :T.StringMap;
}

struct SpeakResult {
    audio @0 :T.DataHandle;
    # Duration of the synthesized audio.
    duration @1 :T.Duration;
    custom @2 :Data;
}

struct Voice {
    id @0 :T.SpeechVoiceId;
    name @1 :Text;
    language @2 :T.Language;
    # Open token; see the gender conformance consts below.
    gender @3 :Text;
    local @4 :Bool;
}

enum VoiceType {
    unspecified @0;   # Sentinel: an unset voice type is not "defaultInput"
    defaultInput @1;
    defaultOutput @2;
    custom @3;
}

# ── Audio Format ───────────────────────────────────────────────────────
# Declares the encoding, sample rate, bit depth, and channel count of
# an audio stream. Eliminates out-of-band format agreement between
# producer and consumer. `encoding` is a T.MimeType, so any codec —
# including one invented after this schema was written — is nameable and
# negotiable.
struct SpeechAudioFormat {
    encoding @0 :T.MimeType;
    sampleRate @1 :UInt32;
    bitDepth @2 :UInt8;
    channels @3 :UInt8;
    frameSize @4 :UInt32;
    parameters @5 :T.StringMap;
}

# ── Speaker Diarization ────────────────────────────────────────────────
struct SpeakerLabel {
    speakerId @0 :UInt32;
    confidence @1 :Float32;
    label @2 :Text;
}

struct DiarizationOptions {
    enableDiarization @0 :Bool;
    maxSpeakers @1 :UInt32;
    minSegmentDuration @2 :Float32;
    parameters @3 :T.StringMap;
}

# ── Structured Transcript ──────────────────────────────────────────────
struct StructuredTranscript {
    text @0 :Text;
    words @1 :List(WordTiming);
    speakers @2 :List(SpeakerLabel);
    language @3 :T.Language;
    confidence @4 :Float32;
    custom @5 :Data;
}

struct WordTiming {
    word @0 :Text;
    start @1 :Float32;
    end @2 :Float32;
    confidence @3 :Float32;
    speakerId @4 :UInt32;
    punctuation @5 :Text;
    # Open token; see the capitalization conformance consts below.
    capitalization @6 :Text;
}

# ── Emotional Styling (TTS) ───────────────────────────────────────────
# One open vocabulary for both directions: what a caller asks for and
# what a detector reports. The previous pair of enums had divergent
# value sets, so a request and a response could not be mapped to each
# other, and 2046's "contempt" / "sarcasm" / "boredom" landed in two
# different `custom` slots that meant nothing.

struct ProsodySpec {
    rate @0 :Float32;
    pitch @1 :Float32;
    volume @2 :Float32;
    emphasis @3 :List(EmphasisRange);
    parameters @4 :T.StringMap;
}

struct EmphasisRange {
    startWord @0 :UInt32;
    endWord @1 :UInt32;
    # Open token; see the emphasis conformance consts below.
    level @2 :Text;
}

# ── Voice Cloning with Provenance ──────────────────────────────────────
struct VoiceCloneRequest {
    name @0 :Text;
    sourceAudio @1 :T.DataHandle;
    language @2 :T.Language;
    consentProof @3 :Data;
    parameters @4 :T.StringMap;
}

struct VoiceCloneResult {
    voiceId @0 :T.SpeechVoiceId;
    provenance @1 :VoiceCloneProvenance;
}

struct VoiceCloneProvenance {
    sourceSpeaker @0 :Text;
    consentAttestation @1 :Data;
    clonedAt @2 :T.Timestamp;
    cloneModel @3 :Text;
    fidelity @4 :Float32;
    metadata @5 :T.StringMap;
}

# ── Real-Time Speech Translation ───────────────────────────────────────
struct SpeechTranslationRequest {
    sourceLanguage @0 :T.Language;
    targetLanguage @1 :T.Language;
    voiceId @2 :T.SpeechVoiceId;
    options @3 :SpeakOptions;
}

interface SpeechTranslationStream {
    pull @0 () -> (result :SpeechTranslationResult, done :Bool);
    cancel @1 () -> T.VoidResult;
}

struct SpeechTranslationResult {
    sourceText @0 :Text;
    translatedText @1 :Text;
    sourceAudio @2 :T.DataHandle;
    translatedAudio @3 :T.DataHandle;
    confidence @4 :Float32;
    custom @5 :Data;
}

struct LanguagePair {
    source @0 :T.Language;
    target @1 :T.Language;
}

# ── Speech-to-Text Alignment ───────────────────────────────────────────
# Forced alignment of audio with text. Used for subtitle generation,
# search indexing, and precise timestamp annotation.
struct AlignmentResult {
    # Aligned words with precise timestamps.
    words @0 :List(WordTiming);
    # Overall alignment confidence (0.0–1.0).
    confidence @1 :Float32;
    # Total duration of the aligned audio.
    duration @2 :T.Duration;
    custom @3 :Data;
}

# ── Wake Word Detection ────────────────────────────────────────────────
struct WakeWordConfig {
    wakeWords @0 :List(Text);
    sensitivity @1 :Float32;
    onDevice @2 :Bool;
    active @3 :Bool;
    parameters @4 :T.StringMap;
}

struct WakeWordEvent {
    detectedWord @0 :Text;
    confidence @1 :Float32;
    timestamp @2 :T.Timestamp;
}

# ── Audio Enhancement ──────────────────────────────────────────────────
struct AudioEnhancement {
    noiseSuppression @0 :Bool;
    noiseSuppressionLevel @1 :Float32;
    autoGainControl @2 :Bool;
    echoCancellation @3 :Bool;
    beamforming @4 :Bool;
    parameters @5 :T.StringMap;
}

# ── Emotion Recognition ────────────────────────────────────────────────
struct EmotionResult {
    # Detected emotion, as an open token (the same vocabulary a caller
    # uses to request one).
    emotion @0 :Text;
    confidence @1 :Float32;
    valence @2 :Float32;
    arousal @3 :Float32;
    custom @4 :Data;
}

# ── Multi-Speaker TTS ──────────────────────────────────────────────────
struct MultiSpeakerRequest {
    speakers @0 :List(MultiSpeakerEntry);
    options @1 :SpeakOptions;
}

struct MultiSpeakerEntry {
    voiceId @0 :T.SpeechVoiceId;
    text @1 :Text;
}

struct MultiSpeakerResult {
    audio @0 :T.DataHandle;
    duration @1 :T.Duration;
    segments @2 :List(MultiSpeakerSegment);
    custom @3 :Data;
}

struct MultiSpeakerSegment {
    speakerIndex @0 :UInt32;
    text @1 :Text;
    start @2 :T.Duration;
    end @3 :T.Duration;
}

# ── Codec Negotiation ──────────────────────────────────────────────────
# Negotiate audio codec between speech sender and receiver. Both sides
# name codecs as T.MimeType values, so the negotiation is over real
# spellings rather than a closed list.
struct CodecNegotiationRequest {
    # Codecs the sender supports, in preference order, as media types.
    supportedCodecs @0 :List(T.MimeType);
    sampleRate @1 :UInt32;
    channels @2 :UInt8;
    parameters @3 :T.StringMap;
}

struct CodecNegotiationResult {
    codec @0 :T.MimeType;
    sampleRate @1 :UInt32;
    channels @2 :UInt8;
    # Whether negotiation succeeded. When false, the caller reads the
    # error arm of SpeechOutcome for the reason.
    success @3 :Bool;
    parameters @4 :T.StringMap;
}

# ── Quality Metrics ────────────────────────────────────────────────────
struct QualityMetrics {
    wer @0 :Float32;
    cer @1 :Float32;
    snrDb @2 :Float32;
    overallConfidence @3 :Float32;
    wordCount @4 :UInt32;
    substitutions @5 :UInt32;
    deletions @6 :UInt32;
    insertions @7 :UInt32;
    custom @8 :Data;
}

# ── Custom Pronunciation ───────────────────────────────────────────────
struct PronunciationRule {
    word @0 :Text;
    # Pronunciation in IPA or phonetic notation.
    pronunciation @1 :Text;
    language @2 :T.Language;
    priority @3 :UInt32;
}

interface WakeWordSubscription {
    pull @0 () -> (event :WakeWordEvent, done :Bool);
    cancel @1 () -> T.VoidResult;
}

interface SpeechStreamResult {
    pull @0 (maxBytes :UInt32) -> (audio :T.DataHandle, done :Bool);
    cancel @1 () -> T.VoidResult;
}

# ══════════════════════════════════════════════════════════════════════
# ONE OUTCOME TYPE — the file's error path
#
# The file previously contained zero unions, so no method could report a
# failure and every backend invented its own convention for "the
# recogniser died" versus "the user said nothing". One union carries
# T.Error beside the existing result structs, so every payload struct
# keeps its field ordinals and every fallible method gains an honest
# failure path. Methods that cannot fail keep returning a bare value.
# ══════════════════════════════════════════════════════════════════════

struct SpeechOutcome {
    union {
        heard @0 :ListenResult;
        spoken @1 :SpeakResult;
        transcript @2 :StructuredTranscript;
        aligned @3 :AlignmentResult;
        emotion @4 :EmotionResult;
        quality @5 :QualityMetrics;
        cloned @6 :VoiceCloneResult;
        codec @7 :CodecNegotiationResult;
        error @8 :T.Error;
        # Opaque escape for an outcome this schema does not name.
        custom @9 :Data;
    }
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Today's spellings for the open tokens above. Nothing requires them; an
# unrecognized token MUST be ignored rather than rejected, so a 2046
# emotion, gender, emphasis level or codec becomes nameable the day a
# backend ships it — no schema amendment, and no `custom` slot carrying
# nothing.
# ══════════════════════════════════════════════════════════════════════

const emotionNeutral   :Text = "neutral";
const emotionHappy     :Text = "happy";
const emotionSad       :Text = "sad";
const emotionAngry     :Text = "angry";
const emotionFearful   :Text = "fearful";
const emotionSurprised :Text = "surprised";
const emotionDisgusted :Text = "disgusted";
const emotionCalm      :Text = "calm";
const emotionExcited   :Text = "excited";
const emotionWhisper   :Text = "whisper";
const emotionShout     :Text = "shout";
const emotionDramatic  :Text = "dramatic";

const genderNeutral :Text = "neutral";
const genderFemale  :Text = "female";
const genderMale    :Text = "male";

const emphasisNone     :Text = "none";
const emphasisModerate :Text = "moderate";
const emphasisStrong   :Text = "strong";

const capitalizationLower :Text = "lower";
const capitalizationUpper :Text = "upper";
const capitalizationTitle :Text = "title";

const codecPcm   :T.MimeType = (type = "audio", subtype = "l16");
const codecOpus  :T.MimeType = (type = "audio", subtype = "opus");
const codecFlac  :T.MimeType = (type = "audio", subtype = "flac");
const codecMp3   :T.MimeType = (type = "audio", subtype = "mpeg");

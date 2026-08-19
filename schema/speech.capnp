@0xa1b2c3d4e5f6002b;

using T = import "types.capnp";
using Translation = import "translation.capnp";

# ══════════════════════════════════════════════════════════════════════
# Speech — speech recognition (STT) and text-to-speech (TTS).
#
# Improvements beyond the original schema:
#   - Voice.id uses T.SpeechVoiceId (was raw Text).
#   - language fields use T.Language (was bare Text).
#   - VoiceGender has custom variant for forward compatibility.
#   - VoiceType has custom variant for forward compatibility.
#   - SpeechSegment.start/end have unit comments (seconds).
#   - voiceId parameters use T.SpeechVoiceId.
#   - AudioStream.pull returns T.DataHandle (was raw Data).
#   - SpeakResult.audio uses T.DataHandle (was raw Data).
#   - SpeakResult.duration uses T.Duration (was raw Float32 seconds).
#   - SpeakOptions rate/pitch/volume have unit comments.
#
# Audit-8 enhancements:
#   - AudioFormat: declared encoding/sample rate/channels for streams.
#   - SpeakerLabel/DiarizationOptions: meeting transcription support.
#   - StructuredTranscript/WordTiming: word-level timestamps + speakers.
#   - EmotionalStyle/ProsodySpec: expressive TTS with emotion control.
#   - VoiceCloneRequest/Provenance: auditable voice cloning.
#   - SpeechTranslator: real-time speech-to-speech translation.
# ══════════════════════════════════════════════════════════════════════

interface Speech {
    listen @0 (options :ListenOptions) -> (result :ListenResult);
    listenStream @1 (stream :AudioStream) -> (stream :ListenResultStream);

    speak @2 (text :Text, voiceId :T.SpeechVoiceId, options :SpeakOptions) -> (result :SpeakResult);
    speakSsml @3 (ssml :Text, voiceId :T.SpeechVoiceId, options :SpeakOptions) -> (result :SpeakResult);
    stopSpeaking @4 () -> T.VoidResult;
    pauseSpeaking @5 () -> T.VoidResult;
    resumeSpeaking @6 () -> T.VoidResult;

    listVoices @7 (language :T.Language) -> (voices :List(Voice));
    getDefaultVoice @8 (type :VoiceType) -> (voice :Voice);
    setDefaultVoice @9 (voiceId :T.SpeechVoiceId, type :VoiceType) -> T.VoidResult;

    hasSpeechToText @10 () -> (available :Bool);
    hasTextToSpeech @11 () -> (available :Bool);

    # -- Audit-8: Structured transcription --
    transcribeStructured @12 (stream :AudioStream, options :ListenOptions)
        -> (transcript :StructuredTranscript);

    # -- Audit-8: Diarization-aware transcription --
    transcribeDiarized @13 (stream :AudioStream, options :DiarizationOptions)
        -> (transcript :StructuredTranscript);

    # -- Audit-8: Voice cloning --
    cloneVoice @14 (request :VoiceCloneRequest) -> (result :VoiceCloneResult);
    listClonedVoices @15 () -> (voices :List(Voice));

    # -- Audit-8: Audio format management --
    getAudioFormat @16 (stream :AudioStream) -> (format :AudioFormat);
    setTtsFormat @17 (format :AudioFormat) -> T.VoidResult;

    # -- Audit-8: Real-time speech translation --
    translate @18 (request :SpeechTranslationRequest) -> (stream :SpeechTranslationStream);
    getSupportedTranslationPairs @19 () -> (pairs :List(LanguagePair));

    # -- Audit-9: listVoices with pagination --
    listVoicesPaginated @20 (language :T.Language, pagination :T.Pagination)
        -> (voices :List(Voice), total :UInt32);

    # -- Audit-9: Speech-to-text alignment --
    alignText @21 (stream :AudioStream, text :Text) -> (result :AlignmentResult);

    # -- Audit-9: Wake word detection --
    startWakeWordDetection @22 (config :WakeWordConfig) -> (subscription :WakeWordSubscription);
    stopWakeWordDetection @23 () -> T.VoidResult;

    # -- Audit-9: Audio enhancement --
    setAudioEnhancement @24 (enhancement :AudioEnhancement) -> T.VoidResult;
    getAudioEnhancement @25 () -> (enhancement :AudioEnhancement);

    # -- Audit-9: Speech emotion recognition --
    detectEmotion @26 (stream :AudioStream) -> (result :EmotionResult);

    # -- Audit-9: Speech synthesis streaming --
    speakStream @27 (text :Text, voiceId :T.SpeechVoiceId, options :SpeakOptions)
        -> (stream :SpeechStreamResult);

    # -- Audit-9: Multi-speaker TTS --
    speakMultiSpeaker @28 (request :MultiSpeakerRequest) -> (result :MultiSpeakerResult);

    # -- Audit-9: Codec negotiation --
    negotiateCodec @29 (request :CodecNegotiationRequest) -> (result :CodecNegotiationResult);

    # -- Audit-9: Quality metrics --
    getQualityMetrics @30 (stream :AudioStream) -> (metrics :QualityMetrics);

    # -- Audit-9: Custom pronunciation --
    addPronunciationRule @31 (rule :PronunciationRule) -> T.VoidResult;
    removePronunciationRule @32 (word :Text, language :T.Language) -> T.VoidResult;
    listPronunciationRules @33 (language :T.Language) -> (rules :List(PronunciationRule));
}

interface AudioStream {
    pull @0 () -> (audio :T.DataHandle, done :Bool);
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
}

struct ListenResult {
    text @0 :Text;
    confidence @1 :Float32;
    segments @2 :List(SpeechSegment);
    language @3 :T.Language;
    isFinal @4 :Bool;
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
    # Audit-8: emotional style for expressive TTS.
    emotionalStyle @4 :EmotionalStyle;
    # Audit-8: detailed prosody control.
    prosody @5 :ProsodySpec;
}

struct SpeakResult {
    audio @0 :T.DataHandle;
    # Duration of the synthesized audio.
    duration @1 :T.Duration;
}

struct Voice {
    id @0 :T.SpeechVoiceId;
    name @1 :Text;
    language @2 :T.Language;
    gender @3 :VoiceGender;
    local @4 :Bool;
}

enum VoiceGender {
    neutral @0;
    female @1;
    male @2;
    custom @3;
}

enum VoiceType {
    defaultInput @0;
    defaultOutput @1;
    custom @2;
}

# ════════════════════════════════════════════════════════════════════════
# Audit-8 additions: audio format declaration, speaker diarization,
# structured transcripts, emotional TTS, voice cloning, translation.
# ════════════════════════════════════════════════════════════════════════

# ── Audio Format ───────────────────────────────────────────────────────
# Declares the encoding, sample rate, bit depth, and channel count of
# an audio stream. Eliminates out-of-band format agreement between
# producer and consumer.
struct AudioFormat {
    encoding @0 :AudioEncoding;
    sampleRate @1 :UInt32;
    bitDepth @2 :UInt8;
    channels @3 :UInt8;
    frameSize @4 :UInt32;
}

enum AudioEncoding {
    pcm @0;
    opus @1;
    aac @2;
    mp3 @3;
    flac @4;
    vorbis @5;
    alaw @6;
    mulaw @7;
    custom @8;
}

# ── Speaker Diarization ────────────────────────────────────────────────
# Speaker identification for meeting transcription. Each speaker
# receives a unique label with confidence score.
struct SpeakerLabel {
    speakerId @0 :UInt32;
    confidence @1 :Float32;
    label @2 :Text;
}

struct DiarizationOptions {
    enableDiarization @0 :Bool;
    maxSpeakers @1 :UInt32;
    minSegmentDuration @2 :Float32;
}

# ── Structured Transcript ──────────────────────────────────────────────
# Rich transcription output with word-level timestamps, speaker labels,
# and punctuation. Replaces flat text output for downstream processing.
struct StructuredTranscript {
    text @0 :Text;
    words @1 :List(WordTiming);
    speakers @2 :List(SpeakerLabel);
    language @3 :T.Language;
    confidence @4 :Float32;
}

struct WordTiming {
    word @0 :Text;
    start @1 :Float32;
    end @2 :Float32;
    confidence @3 :Float32;
    speakerId @4 :UInt32;
    punctuation @5 :Text;
    capitalization @6 :WordCapitalization;
}

enum WordCapitalization {
    lower @0;
    upper @1;
    title @2;
    custom @3;
}

# ── Emotional Styling (TTS) ───────────────────────────────────────────
# Emotion/style directives for expressive text-to-speech. Backend
# interprets the style and adjusts prosody accordingly.
enum EmotionalStyle {
    neutral @0;
    happy @1;
    sad @2;
    angry @3;
    fearful @4;
    surprised @5;
    disgusted @6;
    whisper @7;
    shout @8;
    excited @9;
    calm @10;
    dramatic @11;
    custom @12;
}

struct ProsodySpec {
    rate @0 :Float32;
    pitch @1 :Float32;
    volume @2 :Float32;
    emphasis @3 :List(EmphasisRange);
}

struct EmphasisRange {
    startWord @0 :UInt32;
    endWord @1 :UInt32;
    level @2 :EmphasisLevel;
}

enum EmphasisLevel {
    none @0;
    moderate @1;
    strong @2;
    custom @3;
}

# ── Voice Cloning with Provenance ──────────────────────────────────────
# Voice cloning with auditable provenance. Records source speaker,
# consent attestation, and clone fidelity for compliance.
struct VoiceCloneRequest {
    name @0 :Text;
    sourceAudio @1 :T.DataHandle;
    language @2 :T.Language;
    consentProof @3 :Data;
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
}

# ── Real-Time Speech Translation ───────────────────────────────────────
# Speech-to-speech translation pipeline. Translates audio from one
# language to another in real time, producing translated text and audio.
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
}

struct LanguagePair {
    source @0 :T.Language;
    target @1 :T.Language;
}

# ════════════════════════════════════════════════════════════════════════
# Audit-9 additions: listVoices pagination, speech-to-text alignment,
# wake word detection, noise suppression, emotion recognition,
# synthesis streaming, multi-speaker TTS, codec negotiation,
# quality metrics, and custom pronunciation.
# ════════════════════════════════════════════════════════════════════════

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
}

# ── Wake Word Detection ────────────────────────────────────────────────
# Configuration for wake word / keyword spotting. Detects a specific
# word or phrase to activate the speech system.
struct WakeWordConfig {
    # Wake word(s) to detect.
    wakeWords @0 :List(Text);
    # Detection sensitivity (0.0 = low, 1.0 = high).
    sensitivity @1 :Float32;
    # Whether to use on-device detection (vs. cloud).
    onDevice @2 :Bool;
    # Whether the wake word detector is currently active.
    active @3 :Bool;
}

struct WakeWordEvent {
    # Which wake word was detected.
    detectedWord @0 :Text;
    # Confidence of the detection.
    confidence @1 :Float32;
    # Timestamp of detection.
    timestamp @2 :T.Timestamp;
}

# ── Audio Enhancement ──────────────────────────────────────────────────
# Audio preprocessing options for noise suppression and enhancement.
# Applied before speech recognition for improved accuracy.
struct AudioEnhancement {
    # Whether to enable noise suppression.
    noiseSuppression @0 :Bool;
    # Noise suppression strength (0.0 = off, 1.0 = maximum).
    noiseSuppressionLevel @1 :Float32;
    # Whether to enable automatic gain control.
    autoGainControl @2 :Bool;
    # Whether to enable echo cancellation.
    echoCancellation @3 :Bool;
    # Whether to enable beamforming (for multi-mic arrays).
    beamforming @4 :Bool;
}

# ── Emotion Recognition ────────────────────────────────────────────────
# Speech emotion detection from audio. Identifies the speaker's
# emotional state from vocal characteristics.
struct EmotionResult {
    # Detected emotion.
    emotion @0 :SpeechEmotion;
    # Confidence of the emotion detection (0.0–1.0).
    confidence @1 :Float32;
    # Valence score (-1.0 = negative, 1.0 = positive).
    valence @2 :Float32;
    # Arousal score (0.0 = calm, 1.0 = excited).
    arousal @3 :Float32;
}

enum SpeechEmotion {
    neutral @0;
    happy @1;
    sad @2;
    angry @3;
    fearful @4;
    surprised @5;
    disgusted @6;
    calm @7;
    excited @8;
    custom @9;
}

# ── Multi-Speaker TTS ──────────────────────────────────────────────────
# Generate dialogue between multiple voices. Each speaker is
# assigned a voice and a sequence of lines to speak.
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
    # Per-segment timestamps for subtitle synchronization.
    segments @2 :List(MultiSpeakerSegment);
}

struct MultiSpeakerSegment {
    speakerIndex @0 :UInt32;
    text @1 :Text;
    start @2 :T.Duration;
    end @3 :T.Duration;
}

# ── Codec Negotiation ──────────────────────────────────────────────────
# Negotiate audio codec between speech sender and receiver. Ensures
# both parties agree on encoding before streaming begins.
struct CodecNegotiationRequest {
    # Codecs the sender supports (in preference order).
    supportedCodecs @0 :List(AudioEncoding);
    # Preferred sample rate.
    sampleRate @1 :UInt32;
    # Preferred channel count.
    channels @2 :UInt8;
}

struct CodecNegotiationResult {
    # The negotiated codec.
    codec @0 :AudioEncoding;
    # Agreed sample rate.
    sampleRate @1 :UInt32;
    # Agreed channel count.
    channels @2 :UInt8;
    # Whether negotiation succeeded.
    success @3 :Bool;
}

# ── Quality Metrics ────────────────────────────────────────────────────
# Speech recognition quality metrics. Measures Word Error Rate (WER),
# Character Error Rate (CER), and other accuracy indicators.
struct QualityMetrics {
    # Word Error Rate (lower = better, 0.0 = perfect).
    wer @0 :Float32;
    # Character Error Rate (lower = better, 0.0 = perfect).
    cer @1 :Float32;
    # Signal-to-noise ratio in dB.
    snrDb @2 :Float32;
    # Overall confidence of the recognition result.
    overallConfidence @3 :Float32;
    # Number of words recognized.
    wordCount @4 :UInt32;
    # Number of substitutions, deletions, insertions.
    substitutions @5 :UInt32;
    deletions @6 :UInt32;
    insertions @7 :UInt32;
}

# ── Custom Pronunciation ───────────────────────────────────────────────
# Specify pronunciation for proper nouns and domain-specific terms.
# Uses phonetic notation or IPA for precise control.
struct PronunciationRule {
    # The word or phrase to override.
    word @0 :Text;
    # Pronunciation in IPA or phonetic notation.
    pronunciation @1 :Text;
    # Language this rule applies to.
    language @2 :T.Language;
    # Priority (higher = overrides lower priority rules).
    priority @3 :UInt32;
}

interface WakeWordSubscription {
    pull @0 () -> (event :WakeWordEvent, done :Bool);
    cancel @1 () -> T.VoidResult;
}

interface SpeechStreamResult {
    pull @0 () -> (audio :T.DataHandle, done :Bool);
    cancel @1 () -> T.VoidResult;
}

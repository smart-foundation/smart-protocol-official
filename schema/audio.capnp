@0xa1b2c3d4e5f60010;

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ═══════════════════════════════════════════════════════════════════════
# Audio - volume, devices, streams, focus, spatial, codecs, routing,
#         effects, presets, and accessibility.
#
# Improvements beyond the original schema (audit_analysis.md):
#   - All UInt64 stream/focus IDs -> T.AudioStreamId, T.AudioFocusId
#   - All UInt64 timeouts -> T.Duration
#   - T.Pagination on listDevices/listStreams/listCodecs
#   - cancel() on every subscription interface
#   - T.Error in failure paths
#
# 2026-10-10 integration pass:
#   - FocusEvent -> AudioFocusEvent, HealthStatus -> AudioHealth: three
#     files each declared those names for different concepts.
#     compositor.capnp's surface focus event is SurfaceFocusEvent and the
#     canonical health struct is diagnostics.capnp's HealthStatus.
#   - Every subscription's `pull` is bounded by `maxEvents`, and the
#     convenience `pull*` methods on the root forward the bound. A device
#     arrival burst used to be able to flood one message.
#   - codec :Text -> T.CodecId typed
#   - custom/other variants on all enums
#   - Recording consent typology (RecordConsentRequest formalized)
#   - SpatialProfile has typed ChannelMode
#   - DuckPolicy gained duckKind union
#
# Audit-7 enhancements (zero-cost, info-density):
#   - AudioEffect: parametric EQ, reverb, compressor, limiter, etc.
#   - AudioPreset: user-facing audio profiles (flat, bass boost, etc.)
#   - GlobalDuckPolicy: system-wide duck for incoming calls
#   - AudioStream enhancements (bufferSize, underrunCount)
#   - LoudnessEnhancer for accessibility
#   - AudioMetering for real-time level monitoring
# ═══════════════════════════════════════════════════════════════════════

interface Audio {
    # -- Core --
    getState @0 () -> (state :AudioState);

    listDevices @1 (pagination :T.Pagination) -> (devices :List(AudioDevice), total :UInt32);
    listStreams @2 (pagination :T.Pagination) -> (streams :List(AudioStream), total :UInt32);

    setVolume @3 (device :T.AudioDeviceId, volume :Float32) -> T.VoidResult;
    setMute @4 (device :T.AudioDeviceId, mute :Bool) -> T.VoidResult;
    setStreamVolume @5 (streamId :T.AudioStreamId, volume :Float32) -> T.VoidResult;
    setStreamMute @6 (streamId :T.AudioStreamId, mute :Bool) -> T.VoidResult;

    # -- Device lifecycle --
    enableDevice @7 (device :T.AudioDeviceId) -> T.VoidResult;
    disableDevice @8 (device :T.AudioDeviceId) -> T.VoidResult;

    # -- Subscriptions --
    subscribeState @9 () -> (subscription :AudioStateSubscription);
    pullState @10 (subscription :AudioStateSubscription, maxEvents :UInt32)
                 -> (state :AudioState);
    cancelState @11 (subscription :AudioStateSubscription) -> T.VoidResult;

    subscribeDevices @12 () -> (subscription :DevicesSubscription);
    pullDevices @13 (subscription :DevicesSubscription, maxEvents :UInt32)
                   -> (devices :List(AudioDevice));
    cancelDevices @14 (subscription :DevicesSubscription) -> T.VoidResult;

    subscribeStreams @15 () -> (subscription :StreamsSubscription);
    pullStreams @16 (subscription :StreamsSubscription, maxEvents :UInt32)
                    -> (streams :List(AudioStream));
    cancelStreams @17 (subscription :StreamsSubscription) -> T.VoidResult;

    # -- Focus / priority --
    requestFocus @18 (request :FocusRequest) -> (focusId :T.AudioFocusId);
    releaseFocus @19 (focusId :T.AudioFocusId) -> T.VoidResult;
    subscribeFocus @20 () -> (subscription :FocusSubscription);
    pullFocus @21 (subscription :FocusSubscription, maxEvents :UInt32)
                  -> (events :List(AudioFocusEvent));
    cancelFocus @22 (subscription :FocusSubscription) -> T.VoidResult;

    # -- Spatial --
    setStreamPosition @23 (streamId :T.AudioStreamId, position :SpatialPosition) -> T.VoidResult;
    setListenerPosition @24 (listener :SpatialPosition) -> T.VoidResult;
    setStreamSpatialProfile @25 (streamId :T.AudioStreamId, profile :SpatialProfile) -> T.VoidResult;

    # -- Recording --
    recordConsent @26 (request :RecordConsentRequest) -> (decision :ConsentDecision);
    declareRecordingPolicy @27 (policy :RecordingPolicy) -> T.VoidResult;

    # -- Codecs --
    listCodecs @28 (pagination :T.Pagination) -> (codecs :List(AudioCodec), totalCount :UInt32);
    negotiateCodec @29 (streamId :T.AudioStreamId, codec :T.CodecId) -> (result :NegotiationResult);
    subscribeCodecs @30 () -> (subscription :CodecSubscription);
    pullCodecs @31 (subscription :CodecSubscription, maxEvents :UInt32)
                   -> (codecs :List(AudioCodec));
    cancelCodecs @32 (subscription :CodecSubscription) -> T.VoidResult;

    # -- Routing --
    setRoute @33 (streamId :T.AudioStreamId, route :AudioRoute) -> T.VoidResult;
    duckOnCall @34 (streamId :T.AudioStreamId, policy :DuckPolicy) -> T.VoidResult;

    # -- Audit-7: Effects --
    listEffects @35 (pagination :T.Pagination) -> (effects :List(AudioEffect), totalCount :UInt32);
    addEffect @36 (streamId :T.AudioStreamId, effect :AudioEffect) -> (effectId :UInt32);
    removeEffect @37 (effectId :UInt32) -> T.VoidResult;
    setEffectEnabled @38 (effectId :UInt32, enabled :Bool) -> T.VoidResult;
    setEffectParameter @39 (effectId :UInt32, param :EffectParameter) -> T.VoidResult;

    # -- Audit-7: Presets --
    listPresets @40 (pagination :T.Pagination) -> (presets :List(AudioPreset), totalCount :UInt32);
    applyPreset @41 (presetId :Text) -> T.VoidResult;
    saveCustomPreset @42 (preset :AudioPreset) -> (presetId :Text);
    deleteCustomPreset @43 (presetId :Text) -> T.VoidResult;

    # -- Audit-7: Global Duck --
    setGlobalDuckPolicy @44 (policy :GlobalDuckPolicy) -> T.VoidResult;
    getGlobalDuckPolicy @45 () -> (policy :GlobalDuckPolicy);

    # -- Audit-7: Metering --
    getStreamMetering @46 (streamId :T.AudioStreamId) -> (meter :AudioMetering);
    getDeviceMetering @47 (device :T.AudioDeviceId) -> (meter :AudioMetering);

    # -- Audit-8: Audio session coordination --
    createSession @48 (request :AudioSessionRequest) -> (sessionId :Text);
    joinSession @49 (sessionId :Text, appId :T.AppId) -> T.VoidResult;
    leaveSession @50 (sessionId :Text, appId :T.AppId) -> T.VoidResult;
    getSession @51 (sessionId :Text) -> (session :AudioSession);
    listSessions @52 (pagination :T.Pagination) -> (sessions :List(AudioSession), total :UInt32);
    setSessionRouting @53 (sessionId :Text, routing :CrossDeviceRouting) -> T.VoidResult;

    # -- Audit-9: Typed transport query --
    getAudioTransport @54 (device :T.AudioDeviceId) -> (transport :Text);

    # -- Audit-9: Typed channel layouts --
    listChannelLayouts @55 (device :T.AudioDeviceId) -> (layouts :List(ChannelLayout));

    # -- Audit-9: Per-role duck levels --
    setPerRoleDuckLevels @56 (levels :List(PerRoleDuckLevel)) -> T.VoidResult;
    getPerRoleDuckLevels @57 () -> (levels :List(PerRoleDuckLevel));

    # -- Audit-9: HRTF data management --
    setHrtfData @58 (streamId :T.AudioStreamId, hrtf :HrtfData) -> T.VoidResult;
    getHrtfData @59 (streamId :T.AudioStreamId) -> (hrtf :HrtfData);

    # ═══════════════════════════════════════════════════════════════════
    # Audit-10: Timeless OS Audio Features
    #
    # System-level audio services: sound events, monitoring, privacy,
    # safety, analysis, routing intelligence, transport abstraction.
    # These are OS contracts, not application features.
    # ═══════════════════════════════════════════════════════════════════

    # -- Sound Events (system sounds, clicks, alerts) --
    playSoundEvent @60 (event :SoundEvent) -> (handle :UInt64);
    stopSoundEvent @61 (handle :UInt64) -> T.VoidResult;
    setSoundEventVolume @62 (category :SoundCategory, volume :Float32) -> T.VoidResult;
    getSoundEventVolume @63 (category :SoundCategory) -> (volume :Float32);
    listSoundEvents @64 (pagination :T.Pagination) -> (events :List(SoundEventDef), total :UInt32);
    loadSoundTheme @65 (themeId :Text) -> T.VoidResult;
    getActiveSoundTheme @66 () -> (themeId :Text);

    # -- Audio Analysis (real-time monitoring) --
    getStreamAnalysis @67 (streamId :T.AudioStreamId) -> (analysis :AudioAnalysis);
    getDeviceAnalysis @68 (device :T.AudioDeviceId) -> (analysis :AudioAnalysis);
    subscribeAnalysis @69 (streamId :T.AudioStreamId) -> (subscription :AnalysisSubscription);
    pullAnalysis @70 (subscription :AnalysisSubscription, maxEvents :UInt32)
                     -> (analysis :AudioAnalysis);
    cancelAnalysis @71 (subscription :AnalysisSubscription) -> T.VoidResult;

    # -- Privacy Controls (microphone firewall) --
    getMicAccess @72 (appId :T.AppId) -> (access :MicAccess);
    requestMicAccess @73 (request :MicAccessRequest) -> (decision :MicAccessDecision);
    revokeMicAccess @74 (appId :T.AppId) -> T.VoidResult;
    listMicAccess @75 () -> (access :List(MicAccessEntry));
    setMicPolicy @76 (policy :MicPolicy) -> T.VoidResult;
    getMicPolicy @77 () -> (policy :MicPolicy);

    # -- Safety Limits (hearing protection) --
    setLoudnessLimit @78 (limit :LoudnessLimit) -> T.VoidResult;
    getLoudnessLimit @79 () -> (limit :LoudnessLimit);
    getLoudnessHistory @80 (duration :T.Duration) -> (history :LoudnessHistory);
    setSafetyMode @81 (mode :SafetyMode) -> T.VoidResult;
    getSafetyMode @82 () -> (mode :SafetyMode);

    # -- Audio Routing Intelligence --
    suggestRoute @83 (streamId :T.AudioStreamId, context :RoutingContext) -> (suggestion :AudioRoute);
    getRoutingRules @84 () -> (rules :List(RoutingRule));
    setRoutingRules @85 (rules :List(RoutingRule)) -> T.VoidResult;
    getActiveRoutes @86 () -> (routes :List(ActiveRoute));

    # -- Transport Abstraction --
    listTransports @87 () -> (transports :List(AudioTransportInfo));
    getTransportInfo @88 (transport :Text) -> (info :AudioTransportInfo);
    setTransportPriorities @89 (priorities :List(TransportPriority)) -> T.VoidResult;

    # -- Device Health & Hot-Plug --
    getDeviceHealth @90 (device :T.AudioDeviceId) -> (health :DeviceHealth);
    subscribeDeviceHealth @91 () -> (subscription :DeviceHealthSubscription);
    pullDeviceHealth @92 (subscription :DeviceHealthSubscription, maxEvents :UInt32)
                        -> (events :List(DeviceHealthEvent));
    cancelDeviceHealth @93 (subscription :DeviceHealthSubscription) -> T.VoidResult;

    # -- Multi-Zone Audio (spatial zones) --
    createAudioZone @94 (request :AudioZoneRequest) -> (zoneId :Text);
    removeAudioZone @95 (zoneId :Text) -> T.VoidResult;
    listAudioZones @96 () -> (zones :List(AudioZone));
    setZoneRoute @97 (zoneId :Text, route :AudioRoute) -> T.VoidResult;
    setZoneVolume @98 (zoneId :Text, volume :Float32) -> T.VoidResult;

    # -- Driver framework entry point --
    # An audio driver is a capability acquired once. Everything the
    # provider can do — set the system volume, route a stream, mute the
    # device, revoke another app's microphone consent, disable hearing
    # protection — is reachable by anyone merely holding this `Audio`
    # reference, which is why it was never safe to hand out. Gating the
    # whole privileged surface behind one accessor follows ai.capnp:578-
    # 584: ungated discovery above stays open so a caller can learn what
    # exists before it holds any authority.
    # Returns the provider directly, exactly as ai.capnp:578-584 does. A
    # backend that refuses the capability fails the call; there is no
    # per-method token and no wrapper to hold a second authority for the
    # same outcome.
    openDriver @99 (authority :Capability) -> (provider :AudioProvider);
}

interface AudioStateSubscription {
    # Bounded by the caller, so a state flip-flop (a volume slider dragged
    # while a device connects) cannot flood one message. ai.capnp's own
    # `AISubscription.pull (maxEvents)` discipline.
    pull @0 (maxEvents :UInt32) -> (state :AudioState);
    cancel @1 () -> T.VoidResult;
}
interface DevicesSubscription {
    # The caller states how many it will take, so a device arrival burst or a
    # focus flip-flop cannot flood one message (ai.capnp's own
    # `AISubscription.pull (maxEvents)` discipline). An unstated bound used to
    # let a producer outrun its consumer.
    pull @0 (maxEvents :UInt32) -> (devices :List(AudioDevice));
    cancel @1 () -> T.VoidResult;
}
interface StreamsSubscription {
    # The caller states how many it will take, so a device arrival burst or a
    # focus flip-flop cannot flood one message (ai.capnp's own
    # `AISubscription.pull (maxEvents)` discipline). An unstated bound used to
    # let a producer outrun its consumer.
    pull @0 (maxEvents :UInt32) -> (streams :List(AudioStream));
    cancel @1 () -> T.VoidResult;
}
interface FocusSubscription {
    # The caller states how many it will take, so a device arrival burst or a
    # focus flip-flop cannot flood one message (ai.capnp's own
    # `AISubscription.pull (maxEvents)` discipline). An unstated bound used to
    # let a producer outrun its consumer.
    pull @0 (maxEvents :UInt32) -> (events :List(AudioFocusEvent));
    cancel @1 () -> T.VoidResult;
}
interface CodecSubscription {
    # The caller states how many it will take, so a device arrival burst or a
    # focus flip-flop cannot flood one message (ai.capnp's own
    # `AISubscription.pull (maxEvents)` discipline). An unstated bound used to
    # let a producer outrun its consumer.
    pull @0 (maxEvents :UInt32) -> (codecs :List(AudioCodec));
    cancel @1 () -> T.VoidResult;
}

struct AudioState {
    version @0 :T.Version;
    volume @1 :Float32;
    mute @2 :Bool;
    defaultOutput @3 :T.AudioDeviceId;
    defaultInput @4 :T.AudioDeviceId;
    balance @5 :Float32;
    focusHolder @6 :T.AppId;
    duckOnOther @7 :Bool;
    currentRoute @8 :Text;
    # Time at which this snapshot was generated.
    capturedAt @9 :T.Timestamp;
    # Audit-7: active preset ID (null = no preset).
    activePreset @10 :Text;
    # Audit-7: global duck policy in effect.
    globalDuck @11 :GlobalDuckPolicy;
}

struct AudioDevice {
    id @0 :T.AudioDeviceId;
    name @1 :Text;
    description @2 :Text;
    type @3 :AudioDeviceType;
    volume @4 :Float32;
    mute @5 :Bool;
    card @6 :Text;
    profile @7 :Text;
    capabilities @8 :List(Text);
    sampleRates @9 :List(UInt32);
    channelLayouts @10 :List(Text);
    builtinMic @11 :Bool;
    isEchoCanceller @12 :Bool;
    inputLatency @13 :T.Duration;
    outputLatency @14 :T.Duration;
    # Backend-decided transport (usb, pcm, bluetooth-a2dp, etc.).
    transport @15 :Text;
    # Whether device is currently the default for its direction.
    isDefault @16 :Bool;
    # Last successful activity timestamp.
    lastActiveAt @17 :T.Timestamp;
    # Whether this device is currently plugged in / connected.
    pluggedIn @18 :Bool;
    # Audit-7: supported audio effects on this device.
    supportedEffects @19 :List(Text);
}

enum AudioDeviceType {
    sink @0;
    source @1;
    server @2;
    custom @3;
}

struct AudioStream {
    id @0 :T.AudioStreamId;
    device @1 :T.AudioDeviceId;
    type @2 :AudioStreamType;
    role @3 :StreamRole;
    name @4 :Text;
    volume @5 :Float32;
    mute @6 :Bool;
    format @7 :AudioFormat;
    sampleRate @8 :UInt32;
    channels @9 :UInt32;
    targetLatency @10 :T.Duration;
    priority @11 :Int8;
    suppressed @12 :Bool;
    owner @13 :T.AppId;
    startedAt @14 :T.Timestamp;
    # Open container media type (e.g. "audio/ogg") — see the codec note above.
    containerFormat @15 :T.MimeType;
    # Audit-7 additions:
    # Buffer size in bytes.
    bufferSize @16 :UInt32;
    # Number of underruns since stream started.
    underrunCount @17 :UInt32;
    # Number of overruns since stream started.
    overrunCount @18 :UInt32;
    # Whether the stream is currently being recorded (input streams).
    recording @19 :Bool;
    # Current metering level (0.0 - 1.0).
    meterLevel @20 :Float32;
}

enum AudioStreamType {
    output @0;
    input @1;
    effect @2;
    monitor @3;
    communication @4;
    accessibility @5;
    custom @6;
}

# What the stream is FOR. Not a set of stream *flags*: `duckable`
# (removed) is the same decision as FocusRequest.duckable, and
# `emergency` (removed) is a lifecycle flag, not a usage — each was a
# second authority for a fact the contract already carries somewhere
# else, and two authorities that can disagree is the failure
# DESIGN_PRINCIPLES.md:394 exists to prevent.
enum StreamRole {
    media @0;
    music @1;
    movie @2;
    game @3;
    voiceCall @4;
    navigation @5;
    notification @6;
    alarm @7;
    ringtone @8;
    accessibility @9;
    system @10;
    custom @11;
}

# ── Sample format ──────────────────────────────────────────────────────
# T.PcmFormat (types.capnp:1732) is the one PCM vocabulary in the
# protocol: rate, channels, bits, float/int, endianness, signedness.
#
# The local 19-value AudioSampleFormat modelled the same quantity while
# encoding endianness TWICE — once in the enum (s16LE @1) and once in a
# sibling Bool (littleEndian @1) with no rule for which wins when they
# disagree — omitted isUnsigned entirely, and had no analogue for
# s24Pack. Two models of one fact, disagreeing, in one file.
struct AudioFormat {
    sampleFormat @0 :T.AudioSampleFormat;
    channelLayout @1 :ChannelLayout;
    bitRate @2 :UInt32;
}

struct FocusRequest {
    streamId @0 :T.AudioStreamId;
    role @1 :StreamRole;
    duckable @2 :Bool = true;
    transient @3 :Bool = false;
    reason @4 :Text;
    # Whether this request can survive app restart.
    persistent @5 :Bool = false;
    # Application id requesting focus.
    appId @6 :T.AppId;
}

struct AudioFocusEvent {
    timestamp @0 :T.Timestamp;
    union {
        granted @1 :FocusGrant;
        lost @2 :FocusLoss;
        duckRequested @3 :DuckRequest;
        focusChanged @4 :FocusChange;
        focusExpired @5 :T.AudioFocusId;
        custom @6 :Data;
    }
}

struct FocusGrant {
    focusId @0 :T.AudioFocusId;
    streamId @1 :T.AudioStreamId;
    role @2 :StreamRole;
    appId @3 :T.AppId;
}

struct FocusLoss {
    focusId @0 :T.AudioFocusId;
    reason @1 :Text;
    suggestedRetry @2 :T.Duration;
    losingAppId @3 :T.AppId;
}

struct DuckRequest {
    focusId @0 :T.AudioFocusId;
    targetGain @1 :Float32;
    # How long until duck should begin.
    gracePeriod @2 :T.Duration;
}

struct FocusChange {
    focusId @0 :T.AudioFocusId;
    previousHolder @1 :T.AppId;
    newHolder @2 :T.AppId;
}

struct SpatialPosition {
    x @0 :Float32;
    y @1 :Float32;
    z @2 :Float32;
    # Optional: time at which this position was sampled.
    sampledAt @3 :T.Timestamp;
}

struct SpatialProfile {
    threeD @0 :Bool;
    hrtf @1 :Text;
    channelMap @2 :List(Text);
    maxDistance @3 :Float32;
    rolloff @4 :Float32;
    # Channel strategy.
    mode @5 :ChannelMode;
}

enum ChannelMode {
    automatic @0;
    forced @1;
    mono @2;
    stereo @3;
    binaural @4;
    surround51 @5;   # was: surround_5_1
    surround71 @6;   # was: surround_7_1
    ambisonic @7;
    custom @8;
}

struct RecordConsentRequest {
    appId @0 :T.AppId;
    purpose @1 :Text;
    dataTypes @2 :List(RecordableDataType);
    expiresAt @3 :T.Timestamp;
    # Whether consent must be re-obtained every session.
    perSession @4 :Bool;
}

enum RecordableDataType {
    audio @0;
    video @1;
    biometric @2;
    environmental @3;
    custom @4;
}

struct ConsentDecision {
    granted @0 :Bool;
    grantedUntil @1 :T.Timestamp;
    reason @2 :Text;
    receiptId @3 :Text;
    # Failure reason if denied.
    denialReason @4 :T.Error;
}

struct RecordingPolicy {
    appId @0 :T.AppId;
    foregroundOnly @1 :Bool;
    showIndicator @2 :Bool;
    allowBiometric @3 :Bool;
    # Whether persisted recordings are encrypted at rest.
    encrypt @4 :Bool;
    # Storage quota for persisted recordings.
    storageQuotaBytes @5 :UInt64;
}

# ── Audio Effect ──────────────────────────────────────────────────────
# Audit-7 addition: parametric audio effects. Apps can apply EQ,
# reverb, compressor, limiter, and other effects to streams. Effects
# are parameterized and can be toggled on/off.
struct AudioEffect {
    id @0 :UInt32;
    type @1 :AudioEffectType;
    name @2 :Text;
    enabled @3 :Bool;
    # Effect-specific parameters.
    parameters @4 :List(EffectParameter);
    # Which stream this effect is applied to.
    streamId @5 :T.AudioStreamId;
    # Processing order (lower = earlier in chain).
    order @6 :UInt32;
}

enum AudioEffectType {
    equalizer @0;
    bassBoost @1;
    virtualizer @2;
    reverb @3;
    chamberReverb @4;
    largeRoomReverb @5;
    compressor @6;
    limiter @7;
    noiseSuppressor @8;
    agc @9;
    loudnessEnhancer @10;
    downmix @11;
    volumeShaper @12;
    crossover @13;
    delay @14;
    custom @15;
}

struct EffectParameter {
    name @0 :Text;
    value @1 :EffectParameterValue;
    # Minimum value (for UI sliders).
    minValue @2 :Float32;
    # Maximum value (for UI sliders).
    maxValue @3 :Float32;
}

struct EffectParameterValue {
    union {
        float @0 :Float32;
        integer @1 :Int32;
        boolean @2 :Bool;
        text @3 :Text;
        custom @4 :Data;
    }
}

# ── Audio Preset ──────────────────────────────────────────────────────
# Audit-7 addition: user-facing audio profiles. Presets bundle a set
# of effect parameters for common use cases (flat, bass boost, vocal,
# cinematic, gaming). Users select a preset; the system applies all
# effects in the preset.
struct AudioPreset {
    id @0 :Text;
    name @1 :Text;
    description @2 :Text;
    # Whether this is a built-in preset (not user-created).
    builtin @3 :Bool;
    # Effects in this preset.
    effects @4 :List(AudioEffect);
    # Volume adjustment (relative to current volume).
    volumeAdjust @5 :Float32;
    # Spatial profile override (null = no change).
    spatialProfile @6 :SpatialProfile;
    # Category for UI grouping.
    category @7 :PresetCategory;
}

enum PresetCategory {
    flat @0;
    bassBoost @1;
    vocal @2;
    cinematic @3;
    gaming @4;
    podcast @5;
    classical @6;
    electronic @7;
    jazz @8;
    rock @9;
    custom @10;
}

# ── Global Duck Policy ────────────────────────────────────────────────
# Audit-7 addition: system-wide duck for incoming calls. When a voice
# call arrives, all media streams are ducked according to this policy.
# Per-stream duck (DuckPolicy) still applies on top.
struct GlobalDuckPolicy {
    enabled @0 :Bool;
    # Target gain for all duckable streams during a call.
    targetGain @1 :Float32;
    # How long until duck takes effect after call arrives.
    gracePeriod @2 :T.Duration;
    # Fade-in duration.
    fadeIn @3 :T.Duration;
    # Fade-out duration.
    fadeOut @4 :T.Duration;
    # Whether to pause streams that are too quiet to duck.
    pauseBelowThreshold @5 :Bool;
    # Gain threshold below which streams are paused.
    pauseThreshold @6 :Float32;
    # Roles that are never ducked.
    exemptRoles @7 :List(StreamRole);
}

# ── Audio Metering ────────────────────────────────────────────────────
# Audit-7 addition: real-time level monitoring. Apps and accessibility
# tools use metering to display volume levels, detect silence, or
# trigger visual feedback.
struct AudioMetering {
    # Current peak level (0.0 - 1.0).
    peakLevel @0 :Float32;
    # Current RMS level (0.0 - 1.0).
    rmsLevel @1 :Float32;
    # Whether the signal is below the noise floor.
    silence @2 :Bool;
    # Number of channels being metered.
    channelCount @3 :UInt32;
    # Per-channel peak levels.
    channelPeaks @4 :List(Float32);
    # Timestamp of this metering snapshot.
    sampledAt @5 :T.Timestamp;
}

# ── Codec ─────────────────────────────────────────────────────────────

# ── Codec and container ────────────────────────────────────────────────
# CodecFamily was a 32-value enum naming eleven vendor products
# (aptx = Qualcomm, ldac = Sony, mqa, dsd, wma, atrac ...) and it grew
# by three in Audit-7 alone — proof it is closed by release schedules,
# not by mathematics. AudioContainerFormat was 18 values of the same
# class. Both are now T.MimeType.
#
# The 2046 test, stated plainly: a codec invented next year must either
# add an ordinal to an eternal schema, or be reported as `custom @31` —
# a bare ordinal that carries no semantics — and every consumer doing
# `family == CodecFamily.opus` loses the comparison. The information was
# never in the enum anyway: T.MimeType plus AudioCodec's numeric
# sample-rate / bit-rate / channel fields is the same data, openly
# spelled (ai.capnp:24-26 does exactly this substitution).
#
# Cost, stated plainly: a consumer can no longer `switch (family)`. It
# could only switch over this decade's codecs anyway, and MIME subtype
# comparison is the same operation.
struct AudioCodec {
    id @0 :T.CodecId;
    # Open media type — e.g. "audio/opus", "audio/mp4", "audio/x-dsd".
    family @1 :T.MimeType;
    supportedSampleRates @2 :List(UInt32);
    supportedBitRates @3 :List(UInt32);
    supportedChannels @4 :UInt32;
    hw @5 :Bool;
    lowLatency @6 :Bool;
    # Open container media types — e.g. "audio/ogg", "video/mp4".
    supportedContainers @7 :List(T.MimeType);
}

struct AudioRoute {
    deviceIds @0 :List(T.AudioDeviceId);
    group @1 :Text;
    exclusive @2 :Bool = false;
    kickExisting @3 :Bool = false;
    # Whether routing should persist across restarts.
    persistent @4 :Bool;
}

struct DuckPolicy {
    targetGain @0 :Float32;
    fadeIn @1 :T.Duration;
    fadeOut @2 :T.Duration;
    onCancel @3 :DuckCancel;
    # Maximum number of seconds the duck may last.
    maxDuration @4 :T.Duration;
}

enum DuckCancel {
    pauseAndResume @0;
    stop @1;
    continue @2;
    custom @3;
}

# -- Codec Negotiation Result --
# Returned by negotiateCodec to indicate whether the requested codec
# was accepted, rejected, or partially adapted.

struct NegotiationResult {
    union {
        # Codec fully accepted with the negotiated format parameters.
        accepted @0 :AudioFormat;
        # Codec rejected -- stream should use its default codec.
        rejected @1 :T.Error;
        # Codec accepted with modified format (e.g., lower sample rate).
        adapted @2 :AudioFormat;
        custom @3 :Data;
    }
}

# ── Audit-8: Audio Session Coordination ────────────────────────────────
# Multi-app audio session coordination. Tracks active audio sessions,
# their participants, and cross-device routing. Solves "two apps sharing
# a Bluetooth speaker" and "app handoff between audio output devices."
struct AudioSession {
    sessionId @0 :Text;
    name @1 :Text;
    participants @2 :List(AudioSessionParticipant);
    routing @3 :CrossDeviceRouting;
    createdAt @4 :T.Timestamp;
    active @5 :Bool;
}

struct AudioSessionParticipant {
    appId @0 :T.AppId;
    streamId @1 :T.AudioStreamId;
    role @2 :StreamRole;
    joinedAt @3 :T.Timestamp;
}

struct AudioSessionRequest {
    name @0 :Text;
    appId @1 :T.AppId;
    routing @2 :CrossDeviceRouting;
}

struct CrossDeviceRouting {
    targetDevices @0 :List(T.AudioDeviceId);
    syncPlayback @1 :Bool;
    latencyMode @2 :LatencyMode;
}

enum LatencyMode {
    low @0;
    balanced @1;
    highQuality @2;
    custom @3;
}

# ── Audit-9: Audio Transport ────────────────────────────────────────────
# OPEN TOKEN, was an enum naming this decade's audio *servers*
# (pulseAudio, alsa, jack, pipewire) beside the transports.
#
# A sound server is an implementation, not a transport: TIMELESSNESS.md:25
# rejects "Open PulseAudio stream" as implementation detail, and the
# doctrine's own PipeWire→Rust-server swap test (DESIGN_PRINCIPLES.md:454)
# cites this file as its example. Naming the backends inside the contract
# makes that swap fail on the file that is supposed to prove it works, and
# it leaves a network-audio or embedded backend with no name to report
# except `custom @13`, which carries no semantics.
#
# The transport is therefore a backend-declared open token. Documented
# vocabulary (not exhaustive, not checked):
#   "usb", "pcm", "bluetooth-a2dp", "bluetooth-hfp", "hdmi", "spdif",
#   "network", "virtual", "builtin"
# An unrecognised token is ignored, never rejected (ai.capnp:43-47).

# ── Audit-9: Channel Layout ─────────────────────────────────────────────
# Kept as a typed enum. Unlike transport, a channel layout is a
# property of the audio content that a consumer must interpret
# numerically (which speaker is sample 4?), so the value set is closed
# by the geometry of the reproduction — a 7.1.4 or ambisonic layout
# needs an ordinal, but `other`/`custom` cover a backend-private
# arrangement, and the alternative (parsing free text) is how the
# previous revision shipped four untyped spellings of the same fact.
enum ChannelLayout {
    mono @0;
    stereo @1;
    surround21 @2;   # was: surround2_1
    surround40 @3;   # was: surround4_0
    surround41 @4;   # was: surround4_1
    surround50 @5;   # was: surround5_0
    surround51 @6;   # was: surround5_1
    surround70 @7;   # was: surround7_0
    surround71 @8;   # was: surround7_1
    octagonal @9;
    hexagonal @10;
    ambisonicB1 @11;
    ambisonicB2 @12;
    ambisonicB3 @13;
    other @14;
    custom @15;
}

# ── Audit-9: Per-Role Duck Levels ──────────────────────────────────────
# Granular per-role duck configuration. Replaces the binary
# exempt/not-exempt model in GlobalDuckPolicy.exemptRoles with
# per-role target gains for fine-grained audio ducking.
struct PerRoleDuckLevel {
    role @0 :StreamRole;
    targetGain @1 :Float32;
    # Whether this role is completely exempt from ducking.
    exempt @2 :Bool;
}

# ── Audit-9: HRTF Data ─────────────────────────────────────────────────
# Transferable HRTF data for custom head-related transfer functions.
# Replaces the Text reference in SpatialProfile.hrtf with structured
# data that can carry impulse responses.
struct HrtfData {
    # Name/identifier for this HRTF dataset.
    name @0 :Text;
    # HRTF impulse response data (raw or compressed).
    impulseData @1 :T.DataHandle;
    # Sampling rate of the impulse response.
    sampleRate @2 :UInt32;
    # Number of measurement positions.
    positionCount @3 :UInt32;
    # Whether this is a personalized HRTF.
    personalized @4 :Bool;
}

# ═══════════════════════════════════════════════════════════════════════
# v0.0.2 additions — Audio Provider
#
# An audio driver is a capability. It accepts streams of PCM frames
# from the audio service and pushes them to its hardware. Replace
# the backend (Hound, ALSA, PipeWire, symphonia...) without
# recompiling consumers.
#
# REACHABILITY: this interface — and AudioDriverStream below it — were
# returned by no method anywhere in the protocol, so the entire driver
# half of this file was uncallable contract. The entry point is
# `Audio.openDriver` on interface Audio above; nothing else needs to
# know a driver exists.
# ═══════════════════════════════════════════════════════════════════════

interface AudioProvider {
    # Capability metadata for routing decisions.
    getCapabilities @0 () -> (caps :AudioProviderCaps);
    # Open an output or input stream. The driver decides how to
    # acknowledge completion (immediate, async, polled).
    openStream @1 (config :StreamConfig, direction :StreamDirection)
        -> (stream :AudioDriverStream,
           negotiatedFormat :T.AudioSampleFormat,
           negotiatedLayout :ChannelLayout,
           framesPerBuffer :UInt32);
    # Close a stream. T.AudioStreamId, not a bare UInt64: the file's
    # own header records that every stream id was promoted off UInt64,
    # and this one was missed — so a caller holding an `AudioStream`
    # had two spellings to choose between and no rule.
    closeStream @2 (streamId :T.AudioStreamId) -> (result :T.VoidResult);
    # Driver-defined health ping.
    ping @3 () -> (health :T.DriverHealth);
}

# What openStream agrees to is returned as named results, because the
# negotiated format is part of the contract and not an implementation
# detail: the previous revision's comment said "Framing is
# implementation-defined; consumer uses the negotiated sampleFormat"
# while openStream returned no negotiation outcome at all — so the frame
# boundary and the sample format were never agreed, and two
# independently written drivers could not interoperate without being
# tested against each other by hand.
#
#   negotiatedFormat  the format the driver actually opened at, which is
#                     the only format the submit path will accept
#   negotiatedLayout  the channel layout at that format
#   framesPerBuffer   frames per submit

struct AudioProviderCaps {
    # Sample rates in Hz this provider natively supports.
    sampleRates @0 :List(UInt32);
    # Bits per sample natively supported.
    bitsPerSample @1 :List(UInt16);
    # Channel layouts supported (1.0, 2.0, 5.1, 7.1, ambisonic, ...).
    channelLayouts @2 :List(Text);
    # Latency class in microseconds (driver's worst-case).
    latencyClass @3 :LatencyClass;
    # Whether this provider supports duplex (simultaneous in/out).
    duplex @4 :Bool;
    # Backend hardware class (HD-Audio, USB, Bluetooth, virtio-snd, ...).
    hardwareClasses @5 :List(Text);
}

enum LatencyClass {
    ultraLow @0;  # <5ms (pro audio)
    low      @1;  # <20ms (gaming, music production)
    standard @2;  # <50ms (general multimedia)
    high     @3;  # <200ms (notifications, voice)
    relaxed  @4;  # >200ms (background streaming)
    custom   @5;
}

struct StreamConfig {
    sampleFormat @0 :T.AudioSampleFormat;
    channelLayout @1 :ChannelLayout;
    # Engagement profile — does this stream need ultra-low latency?
    latencyClass @2 :LatencyClass;
    # Suggested buffer duration in ms (driver may ignore).
    suggestedBufferMs @3 :UInt32;
}

enum StreamDirection {
    playback @0;
    capture  @1;
    duplex   @2;
    custom   @3;
}

interface AudioDriverStream {
    # Submit a buffer of decoded frames for playback, or read
    # captured frames.
    #
    # T.DataHandle, not inline `Data`. This is the driver boundary and
    # the hottest path in the file: 48 kHz stereo s16 is 192 KB/s per
    # stream, so a 10 ms buffer is 1,920 bytes submitted 100 times a
    # second per stream — and every inline submit copies its payload
    # into the message arena and then again into the driver's ring. On
    # N streams that is the dominant CPU cost of audio playback and
    # therefore the dominant idle-power cost on a battery device.
    # T.DataHandle's `inline` variant still covers sub-1 KB frames
    # cheaply, so the small case does not regress (ai.capnp:74-75;
    # this file's own HrtfData.impulseData already does this).
    #
    # Framing is fixed by AudioDriverOpenInfo.framesPerBuffer at the
    # negotiated format — see the note on openStream.
    submit @0 (frames :T.DataHandle) -> (result :T.VoidResult);
    drain @1 () -> (result :T.VoidResult);
    # Pause/resume without closing.
    pause @2 () -> (result :T.VoidResult);
    resume @3 () -> (result :T.VoidResult);
    # Position queries in sample frames (lower-bound latency-corrected).
    getPosition @4 () -> (position :UInt64);
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-10: Timeless OS Audio Feature Types
# ═══════════════════════════════════════════════════════════════════════

# ── Sound Events ──────────────────────────────────────────────────────
# System sounds: clicks, alerts, notifications. Theme-able.
# Apps request sound events; OS decides volume/category routing.

struct SoundEvent {
    # Event identifier (e.g., "click", "alert.warning", "notification.new").
    eventId @0 :Text;
    # Optional parameterization (e.g., alert severity).
    params @1 :List(SoundEventParam);
    # Volume override (null = use category default).
    volume @2 :Float32;
    # Whether to respect silent/do-not-disturb mode.
    respectSilent @3 :Bool = true;
}

struct SoundEventParam {
    name @0 :Text;
    value @1 :Text;
}

struct SoundEventDef {
    id @0 :Text;
    name @1 :Text;
    category @2 :SoundCategory;
    description @3 :Text;
    # Default volume for this event (0.0 - 1.0).
    defaultVolume @4 :Float32;
    # Whether this event can be silenced by user.
    silencable @5 :Bool = true;
}

enum SoundCategory {
    ui @0;           # Clicks, taps, UI feedback
    notification @1; # App notifications
    alert @2;        # System alerts, warnings
    alarm @3;        # Alarms, timers
    ringtone @4;     # Incoming calls
    media @5;        # Media playback
    navigation @6;   # Navigation prompts
    accessibility @7; # Accessibility alerts
    system @8;       # System events (boot, shutdown)
    custom @9;
}

# ── Audio Analysis ────────────────────────────────────────────────────
# Real-time audio analysis for monitoring, visualization, diagnostics.

struct AudioAnalysis {
    # Peak level per channel (0.0 - 1.0).
    peakLevels @0 :List(Float32);
    # RMS level per channel (0.0 - 1.0).
    rmsLevels @1 :List(Float32);
    # LUFS loudness (EBU R128).
    lufs @2 :Float32;
    # Loudness range (LRA).
    lra @3 :Float32;
    # True peak (dBTP).
    truePeak @4 :Float32;
    # Spectral centroid (Hz).
    spectralCentroid @5 :Float32;
    # Spectral rolloff (Hz).
    spectralRolloff @6 :Float32;
    # Zero crossing rate.
    zeroCrossingRate @7 :Float32;
    # Whether signal is below noise floor.
    isSilent @8 :Bool;
    # Timestamp of this analysis snapshot.
    sampledAt @9 :T.Timestamp;
}

interface AnalysisSubscription {
    # The caller states how many it will take, so a device arrival burst or a
    # focus flip-flop cannot flood one message (ai.capnp's own
    # `AISubscription.pull (maxEvents)` discipline). An unstated bound used to
    # let a producer outrun its consumer.
    pull @0 (maxEvents :UInt32) -> (analysis :AudioAnalysis);
    cancel @1 () -> T.VoidResult;
}

# ── Privacy Controls ──────────────────────────────────────────────────
# Microphone access control. OS-level firewall.

struct MicAccess {
    appId @0 :T.AppId;
    granted @1 :Bool;
    # What the app is allowed to capture.
    allowedSources @2 :List(MicSourceType);
    # Whether access is foreground-only.
    foregroundOnly @3 :Bool;
    # When access was last granted.
    grantedAt @4 :T.Timestamp;
    # When access expires (null = never).
    expiresAt @5 :T.Timestamp;
    # User-visible purpose string.
    purpose @6 :Text;
}

enum MicSourceType {
    microphone @0;
    systemAudio @1;
    screenAudio @2;
    ambient @3;
    custom @4;
}

struct MicAccessRequest {
    appId @0 :T.AppId;
    sources @1 :List(MicSourceType);
    purpose @2 :Text;
    foregroundOnly @3 :Bool = true;
    # Requested duration (null = session only).
    duration @4 :T.Duration;
}

struct MicAccessDecision {
    granted @0 :Bool;
    # Which sources were actually granted.
    grantedSources @1 :List(MicSourceType);
    # Denial reason if not granted.
    reason @2 :Text;
    # Receipt for audit trail.
    receiptId @3 :Text;
}

struct MicAccessEntry {
    appId @0 :T.AppId;
    access @1 :MicAccess;
}

# Microphone firewall policy.
#
# The previous shape carried `blockedApps`/`trustedApps` — app allow and
# deny lists. Those are permission strings, which
# DESIGN_PRINCIPLES.md:399 forbids outright ("The capability system IS
# the access control mechanism"), and they are also the wrong shape:
# an allow-list has to name every app that may ever use the microphone,
# so a 2046 backend must either invent app-id-to-capability mapping
# rules or ship a list that grants everything by omission.
#
# Authority is expressed once, at acquisition: `requestMicAccess`
# returns a MicAccessEntry that holds the granted capability
# reference, and `revokeMicAccess` revokes it. There is no list of
# names to keep in sync, and no second authority path for the same
# decision.
struct MicPolicy {
    # Default policy for new apps.
    defaultGrant @0 :MicGrantPolicy;
    # Whether to show indicator when mic is active.
    showIndicator @1 :Bool = true;
    # Whether to log all mic access.
    auditLog @2 :Bool = true;
    # Open metadata for backends that need to carry extra policy.
    properties @3 :T.StringMap;
}

enum MicGrantPolicy {
    askEveryTime @0;
    foregroundOnly @1;
    alwaysAsk @2;
    denyAll @3;
}

# ── Safety Limits ─────────────────────────────────────────────────────
# Hearing protection. Enforces loudness limits.

struct LoudnessLimit {
    # Maximum integrated loudness (LUFS). EU regulation: -23 LUFS.
    maxLufs @0 :Float32;
    # Maximum true peak (dBTP). EU regulation: -1 dBTP.
    maxTruePeak @1 :Float32;
    # Maximum exposure time at current level (minutes).
    maxExposureMinutes @2 :UInt32;
    # Whether limit is enforced (false = advisory only).
    enforced @3 :Bool = true;
    # Action to take when limit exceeded.
    action @4 :SafetyAction;
}

enum SafetyAction {
    none @0;        # Advisory only
    reduceVolume @1; # Auto-reduce volume
    pause @2;       # Pause playback
    notify @3;      # Notify user
    custom @4;
}

struct LoudnessHistory {
    # Time series of LUFS measurements.
    samples @0 :List(LoudnessSample);
    # Average LUFS over duration.
    averageLufs @1 :Float32;
    # Maximum LUFS over duration.
    maxLufs @2 :Float32;
    # Whether exposure limit was reached.
    limitReached @3 :Bool;
}

struct LoudnessSample {
    timestamp @0 :T.Timestamp;
    lufs @1 :Float32;
    truePeak @2 :Float32;
}

enum SafetyMode {
    off @0;          # No safety limits
    advisory @1;     # Show warnings, don't enforce
    moderate @2;     # Reduce volume at high levels
    strict @3;       # Enforce EU regulations
    parental @4;     # Strict limits for children
    custom @5;
}

# ── Audio Routing Intelligence ────────────────────────────────────────
# Smart routing based on context.

struct RoutingContext {
    # What the audio is for.
    usage @0 :StreamRole;
    # Current location (if available).
    location @1 :Text;
    # Connected devices.
    connectedDevices @2 :List(T.AudioDeviceId);
    # User preferences.
    preferences @3 :RoutingPreferences;
}

struct RoutingPreferences {
    # Preferred device type (if any).
    preferredDeviceType @0 :AudioDeviceType;
    # Whether to prefer lowest latency.
    preferLowLatency @1 :Bool;
    # Whether to prefer highest quality.
    preferHighQuality @2 :Bool;
    # Devices to never route to.
    excludeDevices @3 :List(T.AudioDeviceId);
}

struct RoutingRule {
    id @0 :Text;
    # Condition to match.
    condition @1 :RoutingCondition;
    # Action to take.
    action @2 :RoutingAction;
    # Priority (higher = evaluated first).
    priority @3 :Int32;
    # Whether rule is enabled.
    enabled @4 :Bool = true;
}

struct RoutingCondition {
    union {
        role @0 :StreamRole;
        device @1 :T.AudioDeviceId;
        app @2 :T.AppId;
        always @3 :Bool;
        custom @4 :Data;
    }
}

struct RoutingAction {
    union {
        routeTo @0 :T.AudioDeviceId;
        routeToType @1 :AudioDeviceType;
        exclude @2 :T.AudioDeviceId;
        duck @3 :Float32;
        custom @4 :Data;
    }
}

struct ActiveRoute {
    streamId @0 :T.AudioStreamId;
    deviceId @1 :T.AudioDeviceId;
    # Latency in microseconds.
    latencyUs @2 :UInt32;
    # Sample rate in Hz.
    sampleRate @3 :UInt32;
}

# ── Transport Abstraction ─────────────────────────────────────────────
# Abstract audio transport layer.

struct AudioTransportInfo {
    # Open backend-declared transport token — see the transport note above.
    transport @0 :Text;
    name @1 :Text;
    # Maximum channels supported.
    maxChannels @2 :UInt32;
    # Supported sample rates.
    sampleRates @3 :List(UInt32);
    # Typical latency range (microseconds).
    minLatencyUs @4 :UInt32;
    maxLatencyUs @5 :UInt32;
    # Whether transport is currently available.
    available @6 :Bool;
    # Whether transport supports duplex.
    duplex @7 :Bool;
}

struct TransportPriority {
    # Open backend-declared transport token — see the transport note above.
    transport @0 :Text;
    # Priority (higher = preferred).
    priority @1 :Int32;
}

# ── Device Health ─────────────────────────────────────────────────────
# Device health monitoring and hot-plug events.

struct DeviceHealth {
    device @0 :T.AudioDeviceId;
    # Overall health status.
    status @1 :AudioHealth;
    # Temperature (millidegrees Celsius, null if unknown).
    temperature @2 :Int32;
    # Bit error rate (0-100%, null if unknown).
    bitErrors @3 :Float32;
    # Clock drift (ppm, null if unknown).
    clockDrift @4 :Float32;
    # Buffer underruns since last check.
    underruns @5 :UInt32;
    # Buffer overruns since last check.
    overruns @6 :UInt32;
    # Last health check timestamp.
    checkedAt @7 :T.Timestamp;
}

enum AudioHealth {
    healthy @0;
    degraded @1;
    failing @2;
    disconnected @3;
    unknown @4;
}

interface DeviceHealthSubscription {
    # The caller states how many it will take, so a device arrival burst or a
    # focus flip-flop cannot flood one message (ai.capnp's own
    # `AISubscription.pull (maxEvents)` discipline). An unstated bound used to
    # let a producer outrun its consumer.
    pull @0 (maxEvents :UInt32) -> (events :List(DeviceHealthEvent));
    cancel @1 () -> T.VoidResult;
}

struct DeviceHealthEvent {
    device @0 :T.AudioDeviceId;
    timestamp @1 :T.Timestamp;
    union {
        pluggedIn @2 :T.AudioDeviceId;
        unplugged @3 :T.AudioDeviceId;
        healthChanged @4 :DeviceHealth;
        errorDetected @5 :DeviceError;
        custom @6 :Data;
    }
}

struct DeviceError {
    code @0 :UInt32;
    message @1 :Text;
    # Whether error is recoverable.
    recoverable @2 :Bool;
}

# ── Multi-Zone Audio ──────────────────────────────────────────────────
# Spatial audio zones for multi-room/multi-area setups.

struct AudioZoneRequest {
    name @0 :Text;
    # Devices in this zone.
    devices @1 :List(T.AudioDeviceId);
    # Spatial position of zone center.
    position @2 :SpatialPosition;
}

struct AudioZone {
    zoneId @0 :Text;
    name @1 :Text;
    devices @2 :List(T.AudioDeviceId);
    position @3 :SpatialPosition;
    volume @4 :Float32;
    # Current route for this zone.
    route @5 :AudioRoute;
}

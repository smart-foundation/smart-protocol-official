@0xa1b2c3d4e5f60053;

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ═══════════════════════════════════════════════════════════════════════
# Telephony - cellular network, calls, SMS, MMS, RCS, conference calls.
#
# Fixes this revision makes:
#   - Every feature service is now REACHABLE. The Audit-8 additions came
#     in as whole interfaces returned by nothing: line management, call
#     recording, voicemail and screening advertised themselves to a
#     consumer that had no way to obtain the service, so every backend
#     invented a root name for each. They are now gated accessors on
#     `TelephonyService`, the doctrine's reference model: present a
#     capability, receive the service, and holding the service IS the
#     authority.
#   - Satellite and mesh telephony are DELETED, with the reason stated
#     rather than implied: satellite SOS and mesh calling are 2020s
#     product features, not timeless contracts, and the same wave deleted
#     the mesh stack from network.capnp. Nothing in the tree consumes
#     them.
#   - `makeCall` can fail. A call that cannot be placed (SIM locked,
#     network busy, airplane mode) had no representation, so backends
#     reported it as an empty call list or a synthetic disconnected
#     state.
#   - Technology enumerations became open tokens: the cellular
#     generation catalog (6G has no value), the physical-SIM lifecycle
#     (an eSIM or a non-cellular backend must map onto card-reader
#     semantics or lie), and the RCS content-type feature list (the next
#     RCS release's content type has no ordinal).
#   - The calendar free/busy contract is gone: calendar.capnp owns
#     availability, and telephony re-declared it with a different shape.
#   - Opaque `Data` id namespaces are now typed ids, so a recording id
#     passed where a message id belongs is a compile error.
#   - The dead `LanguageFallback` type and its cross-file import of
#     translation.capnp are gone.
# ═══════════════════════════════════════════════════════════════════════

struct SimInfo {
    slot @0 :UInt32;
    present @1 :Bool;
    carrierName @2 :Text;
    # Card identifiers, as reported data. They carry no authority: what
    # a caller may do is decided by which reference it holds.
    serialNumber @3 :Text;
    phoneNumber @4 :Text;
    # SIM lifecycle state as an open token ("ready", "pinRequired",
    # "networkLocked", ...). An eSIM, a soft-SIM or a non-cellular
    # backend reports its own states instead of mapping onto a
    # card reader's.
    state @5 :Text;
    mcc @6 :Text;
    mnc @7 :Text;
    iccid @8 :Text;
    isDataActive @9 :Bool;
    metadata @10 :T.StringMap;
}

struct CellularNetworkInfo {
    operatorName @0 :Text;
    # Link technology as an open token ("lte", "nr5G", "satellite", ...).
    # A 6G release is a string, not a new ordinal.
    type @1 :Text;
    # Signal strength in dBm (typically -120 to -30).
    signalStrength @2 :Int32;
    signalStrengthMeasured @3 :Bool;
    # Normalized signal level 0-4 (0=none, 4=excellent).
    signalLevel @4 :UInt32;
    dataConnected @5 :Bool;
    dataRoaming @6 :Bool;
    # Cell identifiers, as reported data.
    cellId @7 :UInt64;
    lac @8 :UInt64;
    tac @9 :UInt64;
    volte @10 :Bool;
    vowifi @11 :Bool;
    mcc @12 :Text;
    mnc @13 :Text;
    metadata @14 :T.StringMap;
}

enum CallState {
    unknown @0;
    dialing @1;
    alerting @2;
    active @3;
    held @4;
    disconnected @5;
    waiting @6;
    custom @7;
}

enum CallDirection {
    unknown @0;
    incoming @1;
    outgoing @2;
    custom @3;
}

# Call media kind as an open token ("voice", "video", "data").
enum CallType {
    unknown @0;
    voice @1;
    video @2;
    data @3;
    custom @4;
}

struct CallInfo {
    id @0 :T.CallId;
    number @1 :T.PhoneNumber;
    state @2 :CallState;
    direction @3 :CallDirection;
    startTime @4 :T.Timestamp;
    duration @5 :T.Duration;
    displayName @6 :Text;
    conferenceId @7 :T.ConferenceId;
    callType @8 :CallType;
    forwarded @9 :Bool;
    onHold @10 :Bool;
    slot @11 :UInt32;
    metadata @12 :T.StringMap;
}

# A placed call or an honest failure — never an empty list standing in
# for "the network refused us".
struct CallResult {
    union {
        callId @0 :T.CallId;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

enum DtmfTone {
    unknown @0;
    digit0 @1; digit1 @2; digit2 @3; digit3 @4; digit4 @5;
    digit5 @6; digit6 @7; digit7 @8; digit8 @9; digit9 @10;
    star @11; hash @12;
    a @13; b @14; c @15; d @16;
    flash @17; hold @18; voiceMail @19;
    custom @20;
}

struct IncomingSmsEvent {
    slot @0 :UInt32;
    sender @1 :Text;
    body @2 :Text;
    timestamp @3 :T.Timestamp;
    # Encoding as an open token ("gsm7", "utf16", ...).
    encoding @4 :Text;
    smsCenter @5 :Text;
    pduType @6 :UInt8;
    metadata @7 :T.StringMap;
}

struct SmsStatusReport {
    messageId @0 :T.TelephonyMessageId;
    status @1 :SmsStatus;
    timestamp @2 :T.Timestamp;
    recipient @3 :Text;
    metadata @4 :T.StringMap;
}

enum SmsStatus {
    unknown @0;
    received @1;
    stored @2;
    sent @3;
    failed @4;
    pending @5;
    custom @6;
}

struct MmsPart {
    id @0 :T.MmsPartId;
    contentType @1 :T.MimeType;
    data @2 :T.DataHandle;
    filename @3 :Text;
    contentId @4 :Text;
    forwarded @5 :Bool;
    metadata @6 :T.StringMap;
}

struct IncomingMmsEvent {
    slot @0 :UInt32;
    sender @1 :Text;
    subject @2 :Text;
    parts @3 :List(MmsPart);
    timestamp @4 :T.Timestamp;
    read @5 :Bool;
    retrievalStatus @6 :MmsRetrievalStatus;
    metadata @7 :T.StringMap;
}

enum MmsRetrievalStatus {
    unknown @0;
    notRetrieved @1;
    retrieving @2;
    retrieved @3;
    deferred @4;
    custom @5;
}

struct MmsSendRequest {
    to @0 :Text;
    subject @1 :Text;
    parts @2 :List(MmsPart);
    smsFallback @3 :Bool;
    metadata @4 :T.StringMap;
}

struct RcsMessage {
    id @0 :T.TelephonyMessageId;
    to @1 :Text;
    body @2 :Text;
    timestamp @3 :T.Timestamp;
    direction @4 :CallDirection;
    status @5 :RcsStatus;
    # Content type as an open token ("text", "image", "fileTransfer", ...).
    # The next RCS release's content type is a string.
    contentType @6 :Text;
    isDelivered @7 :Bool;
    isRead @8 :Bool;
    replyTo @9 :T.TelephonyMessageId;
    metadata @10 :T.StringMap;
}

enum RcsStatus {
    unknown @0;
    sending @1;
    sent @2;
    delivered @3;
    displayed @4;
    failed @5;
    custom @6;
}

struct ConferenceInfo {
    id @0 :T.ConferenceId;
    name @1 :Text;
    participantCount @2 :UInt32;
    state @3 :CallState;
    participants @4 :List(CallInfo);
    # Pagination for participants. Used when participantCount exceeds
    # practical in-message limits; the backend may page participants
    # without affecting participantCount (which always reports the total).
    participantsPagination @5 :T.Pagination;
    metadata @6 :T.StringMap;
}

struct DataUsage {
    mobileBytesRx @0 :UInt64;
    mobileBytesTx @1 :UInt64;
    totalBytesRx @2 :UInt64;
    totalBytesTx @3 :UInt64;
    periodStart @4 :T.Timestamp;
    periodEnd @5 :T.Timestamp;
}

# ── Root service ───────────────────────────────────────────────────────

interface TelephonyService {
    getSimInfo @0 (slot :UInt32) -> (result :SimInfoResult);
    getSimSlots @1 () -> (slots :List(SimInfo));

    getNetworkInfo @2 () -> (info :CellularNetworkInfo);

    makeCall @3 (number :T.PhoneNumber) -> (result :CallResult);
    answerCall @4 (callId :T.CallId) -> T.VoidResult;
    hangUp @5 (callId :T.CallId) -> T.VoidResult;
    getActiveCalls @6 (pagination :T.Pagination) -> (calls :List(CallInfo), totalCount :UInt32);

    sendDtmf @7 (callId :T.CallId, tone :DtmfTone) -> T.VoidResult;
    startDtmf @8 (callId :T.CallId, tone :DtmfTone) -> T.VoidResult;
    stopDtmf @9 (callId :T.CallId) -> T.VoidResult;

    createConference @10 (participants :List(T.CallId)) -> (result :ConferenceResult);
    mergeCalls @11 (callIds :List(T.CallId)) -> (result :ConferenceResult);
    splitConference @12 (conferenceId :T.ConferenceId) -> (calls :List(CallInfo));
    addConferenceParticipant @13 (conferenceId :T.ConferenceId, callId :T.CallId) -> T.VoidResult;
    removeConferenceParticipant @14 (conferenceId :T.ConferenceId, callId :T.CallId) -> T.VoidResult;
    getConferenceInfo @15 (conferenceId :T.ConferenceId) -> (result :ConferenceInfoResult);

    sendSms @16 (number :T.PhoneNumber, message :Text) -> T.VoidResult;
    getSmsStatus @17 (messageId :T.TelephonyMessageId) -> (result :SmsStatusResult);

    sendMms @18 (request :MmsSendRequest) -> (result :MmsResult);
    # Download MMS by typed message id.
    downloadMms @19 (slot :UInt32, messageId :T.TelephonyMessageId) -> (result :IncomingMmsResult);

    sendRcs @20 (message :RcsMessage) -> T.VoidResult;
    getRcsMessages @21 (chatId :Text, since :T.Timestamp, pagination :T.Pagination)
                  -> (messages :List(RcsMessage), totalCount :UInt64);

    getSignalStrength @22 () -> (result :SignalStrengthResult);
    getDataUsage @23 () -> (usage :DataUsage);
    setMobileData @24 (enabled :Bool) -> T.VoidResult;
    isMobileDataEnabled @25 () -> (enabled :Bool);
    setDataRoaming @26 (enabled :Bool) -> T.VoidResult;

    subscribeCalls @27 () -> (subscription :CallSubscription);
    cancelCalls @28 (subscription :CallSubscription) -> T.VoidResult;
    subscribeNetwork @29 () -> (subscription :NetworkSubscription);
    cancelNetwork @30 (subscription :NetworkSubscription) -> T.VoidResult;
    subscribeSms @31 () -> (subscription :SmsSubscription);
    cancelSms @32 (subscription :SmsSubscription) -> T.VoidResult;
    subscribeMms @33 () -> (subscription :MmsSubscription);
    cancelMms @34 (subscription :MmsSubscription) -> T.VoidResult;

    # ── Call management ──
    holdCall @35 (callId :T.CallId) -> T.VoidResult;
    unholdCall @36 (callId :T.CallId) -> T.VoidResult;
    getCallLog @37 (pagination :T.Pagination) -> (calls :List(CallInfo), totalCount :UInt32);

    # ── Call quality monitoring ──
    getCallQuality @38 (callId :T.CallId) -> (result :CallQualityResult);

    # ── Carrier settings ──
    getCarrierSettings @39 () -> (settings :CarrierSettings);
    setCarrierSettings @40 (settings :CarrierSettings) -> T.VoidResult;

    # ── Emergency numbers ──
    # Safety-critical: the caller must hold a TelephonyService reference
    # granted for administration (the capability system is the access
    # control mechanism). No per-method token.
    setEmergencyNumber @41 (entry :EmergencyNumber) -> T.VoidResult;
    getEmergencyNumbers @42 (pagination :T.Pagination) -> (entries :List(EmergencyNumber), totalCount :UInt64);

    # ── Data usage breakdown ──
    getDataUsageBreakdown @43 (pagination :T.Pagination)
                          -> (breakdown :List(AppDataUsage), totalCount :UInt64, totalBytes :UInt64);

    # ── E2E encryption for SMS/MMS ──
    getE2eEncryptionStatus @44 () -> (encryption :E2eEncryption);
    setE2eEncryption @45 (encryption :E2eEncryption) -> T.VoidResult;

    # ── Call transfer and forwarding ──
    transferCall @46 (callId :T.CallId, targetNumber :T.PhoneNumber) -> T.VoidResult;
    acceptTransfer @47 (callId :T.CallId) -> T.VoidResult;
    rejectTransfer @48 (callId :T.CallId) -> T.VoidResult;
    setCallForwarding @49 (enabled :Bool, targetNumber :T.PhoneNumber) -> T.VoidResult;
    getCallForwarding @50 () -> (result :CallForwardingResult);

    # ── Video call support ──
    startVideoCall @51 (number :T.PhoneNumber) -> (result :CallResult);
    getVideoQuality @52 (callId :T.CallId) -> (result :VideoQualityResult);

    # ── Gated feature services ─────────────────────────────────────────
    # Four features that used to be unreachable. Each accessor takes a
    # capability and returns the service; the returned reference is the
    # authority to use the feature (no per-method token inside).

    # Multi-line / dual-SIM management.
    lineManager @53 (authority :Capability) -> (service :LineManager);

    # Call recording.
    callRecording @54 (authority :Capability) -> (service :CallRecordingService);

    # Visual voicemail.
    voicemail @55 (authority :Capability) -> (service :VoicemailService);

    # Call screening / spam blocking.
    callScreening @56 (authority :Capability) -> (service :CallScreeningService);
}

struct SimInfoResult {
    union {
        info @0 :SimInfo;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct ConferenceResult {
    union {
        conferenceId @0 :T.ConferenceId;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct ConferenceInfoResult {
    union {
        info @0 :ConferenceInfo;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct SmsStatusResult {
    union {
        report @0 :SmsStatusReport;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct IncomingMmsResult {
    union {
        event @0 :IncomingMmsEvent;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct MmsResult {
    union {
        ok @0 :Void;
        messageId @1 :T.TelephonyMessageId;
        error @2 :T.Error;
        unknown @3 :T.UnknownEvent;
    }
}

struct SignalStrengthResult {
    # dBm, present only when measured.
    strength @0 :Int32;
    strengthMeasured @1 :Bool;
    # Normalized 0-4 level.
    level @2 :UInt32;
}

struct CallQualityResult {
    union {
        quality @0 :CallQuality;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct VideoQualityResult {
    union {
        quality @0 :VideoQuality;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct CallForwardingResult {
    union {
        forwarding @0 :CallForwarding;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct CallForwarding {
    enabled @0 :Bool;
    targetNumber @1 :T.PhoneNumber;
    metadata @2 :T.StringMap;
}

# ── Subscriptions ──────────────────────────────────────────────────────

interface CallSubscription {
    pull @0 (pagination :T.Pagination) -> (calls :List(CallInfo), totalCount :UInt32);
    cancel @1 () -> T.VoidResult;
}

interface NetworkSubscription {
    pull @0 () -> (info :CellularNetworkInfo);
    cancel @1 () -> T.VoidResult;
}

interface SmsSubscription {
    pull @0 () -> (events :List(IncomingSmsEvent));
    cancel @1 () -> T.VoidResult;
}

interface MmsSubscription {
    pull @0 () -> (events :List(IncomingMmsEvent));
    cancel @1 () -> T.VoidResult;
}

# ── Gated feature services ─────────────────────────────────────────────

# ── Line Manager (multi-line / dual-SIM management) ────────────────────
interface LineManager {
    listLines @0 (pagination :T.Pagination) -> (lines :List(PhoneLine), totalCount :UInt64);
    getActiveLine @1 () -> (result :PhoneLineResult);
    setActiveLine @2 (lineId :LineId) -> T.VoidResult;
    getLineSettings @3 (lineId :LineId) -> (result :LineSettingsResult);
}

# Line identity is a typed id, not a free-text label.
struct LineId {
    id @0 :Text;
    # Display label, if the backend has one.
    label @1 :Text;
    extensions @2 :T.StringMap;
}

struct PhoneLineResult {
    union {
        line @0 :PhoneLine;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct LineSettingsResult {
    union {
        settings @0 :LineSettings;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct PhoneLine {
    lineId @0 :LineId;
    name @1 :Text;
    simSlot @2 :UInt32;
    phoneNumber @3 :T.PhoneNumber;
    isActive @4 :Bool;
    # Capabilities as open tokens.
    capabilities @5 :List(Text);
    metadata @6 :T.StringMap;
}

struct LineSettings {
    callForwarding @0 :Bool;
    callWaiting @1 :Bool;
    # Caller-id presentation as an open token ("show", "hide", ...).
    callerId @2 :Text;
    voicemail @3 :Text;
    metadata @4 :T.StringMap;
}

# ── Call Recording ─────────────────────────────────────────────────────
interface CallRecordingService {
    startRecording @0 (callId :T.CallId) -> (result :RecordingIdResult);
    stopRecording @1 (recordingId :T.RecordingId) -> T.VoidResult;
    getRecordingStatus @2 (recordingId :T.RecordingId) -> (result :RecordingStatusResult);
    listRecordings @3 (pagination :T.Pagination) -> (recordings :List(CallRecording), totalCount :UInt64);
    getRecordingData @4 (recordingId :T.RecordingId) -> (result :RecordingDataResult);
    setRecordingEncryption @5 (recordingId :T.RecordingId, encryption :RecordingEncryption) -> T.VoidResult;
    getRecordingEncryption @6 (recordingId :T.RecordingId) -> (result :RecordingEncryptionResult);
}

struct RecordingIdResult {
    union {
        recordingId @0 :T.RecordingId;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct RecordingStatusResult {
    union {
        status @0 :RecordingStatus;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct RecordingDataResult {
    union {
        data @0 :RecordingData;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct RecordingEncryptionResult {
    union {
        encryption @0 :RecordingEncryption;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct CallRecording {
    recordingId @0 :T.RecordingId;
    callId @1 :T.CallId;
    startTime @2 :T.Timestamp;
    endTime @3 :T.Timestamp;
    duration @4 :T.Duration;
    # Encoding as an open token ("opus", "pcm", ...).
    format @5 :Text;
    sizeBytes @6 :UInt64;
    encrypted @7 :Bool;
    metadata @8 :T.StringMap;
}

enum RecordingStatus {
    unknown @0;
    recording @1;
    paused @2;
    stopped @3;
    error @4;
    custom @5;
}

struct RecordingData {
    audio @0 :T.DataHandle;
    format @1 :Text;
    metadata @2 :T.StringMap;
}

struct RecordingEncryption {
    enabled @0 :Bool;
    # Algorithm as an open token ("aes-256-gcm", "chacha20-poly1305", ...).
    algorithm @1 :Text;
    # Wrapped key material, as content.
    encryptedKey @2 :T.DataHandle;
    # Key identifier for rotation.
    keyId @3 :T.KeyId;
    createdAt @4 :T.Timestamp;
    metadata @5 :T.StringMap;
}

# ── Visual Voicemail ───────────────────────────────────────────────────
interface VoicemailService {
    listVoicemails @0 (pagination :T.Pagination) -> (voicemails :List(Voicemail), totalCount :UInt64);
    getVoicemail @1 (voicemailId :VoicemailId) -> (result :VoicemailResult);
    playVoicemail @2 (voicemailId :VoicemailId) -> (result :VoicemailDataResult);
    deleteVoicemail @3 (voicemailId :VoicemailId) -> T.VoidResult;
    markRead @4 (voicemailId :VoicemailId) -> T.VoidResult;
    subscribeVoicemail @5 () -> (subscription :VoicemailSubscription);
}

struct VoicemailId { id @0 :UInt64; }

struct VoicemailResult {
    union {
        voicemail @0 :Voicemail;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct VoicemailDataResult {
    union {
        data @0 :VoicemailData;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct Voicemail {
    voicemailId @0 :VoicemailId;
    sender @1 :Text;
    timestamp @2 :T.Timestamp;
    duration @3 :T.Duration;
    read @4 :Bool;
    transcription @5 :Text;
    sizeBytes @6 :UInt64;
    metadata @7 :T.StringMap;
}

struct VoicemailData {
    audio @0 :T.DataHandle;
    format @1 :Text;
    metadata @2 :T.StringMap;
}

interface VoicemailSubscription {
    pull @0 () -> (events :List(VoicemailEvent));
    cancel @1 () -> T.VoidResult;
}

struct VoicemailEvent {
    union {
        received @0 :Voicemail;
        deleted @1 :VoicemailId;
        custom @2 :Data;
    }
}

# ── Call Screening ─────────────────────────────────────────────────────
interface CallScreeningService {
    screenCall @0 (callerId :T.PhoneNumber) -> (result :SpamScoreResult);
    getBlockList @1 (pagination :T.Pagination) -> (numbers :List(T.PhoneNumber), totalCount :UInt64);
    blockNumber @2 (number :T.PhoneNumber) -> T.VoidResult;
    unblockNumber @3 (number :T.PhoneNumber) -> T.VoidResult;
}

struct SpamScoreResult {
    union {
        score @0 :SpamScore;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

# ── Quality, Screening and Carrier (audit-9) ───────────────────────────

struct CallQuality {
    mosScore @0 :Float32;
    latency @1 :T.Duration;
    jitter @2 :T.Duration;
    packetLoss @3 :Float32;
    # Codec as an open token.
    codec @4 :Text;
    metadata @5 :T.StringMap;
}

struct VideoQuality {
    width @0 :UInt16;
    height @1 :UInt16;
    frameRate @2 :UInt16;
    bitrate @3 :UInt32;
    packetLossPercent @4 :Float32;
    codec @5 :Text;
    metadata @6 :T.StringMap;
}

struct SpamScore {
    # Spam likelihood score (0.0 = not spam, 1.0 = definitely spam).
    score @0 :Float32;
    blocked @1 :Bool;
    # Category as an open token ("telemarketer", "scam", "survey", ...).
    category @2 :Text;
    metadata @3 :T.StringMap;
}

struct CarrierSettings {
    apn @0 :Text;
    mmsc @1 :Text;
    mmsProxy @2 :T.IpAddress;
    mmsPort @3 :T.Port;
    # Authentication type as an open token.
    authType @4 :Text;
    isDefault @5 :Bool;
    metadata @6 :T.StringMap;
}

struct E2eEncryption {
    enabled @0 :Bool;
    # Algorithm as an open token.
    algorithm @1 :Text;
    keysVerified @2 :Bool;
    metadata @3 :T.StringMap;
}

struct AppDataUsage {
    appId @0 :T.AppId;
    appName @1 :Text;
    bytesRx @2 :UInt64;
    bytesTx @3 :UInt64;
    metadata @4 :T.StringMap;
}

struct EmergencyNumber {
    # Lower = answered first.
    priority @0 :UInt32;
    number @1 :T.PhoneNumber;
    # Region this number applies to (open token; empty = everywhere).
    region @2 :Text;
    metadata @3 :T.StringMap;
}

@0xa1b2c3d4e5f60053;

using T = import "types.capnp";
using Trans = import "translation.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Telephony - cellular network, calls, SMS, MMS, RCS, conference calls.
#
# Improvements beyond the original schema (audit):
#   - Incoming SMS events via subscribeSms.
#   - MMS sending/receiving via sendMms + MmsPart.
#   - RCS message struct + sendRcs with SMS fallback.
#   - conferenceId on CallInfo (multi-party calls).
#   - DTMF tone sending via sendDtmf (IVR support).
#   - displayName on CallInfo (caller-id display).
#   - CallType on subscription (voice/data/video).
#   - Cell tower info extended with TAC (tracking area code).
#   - Satellite network type.
#   - CallInfo.duration uses T.Duration.
#   - Call.id uses T.CallId from types.capnp.
#   - ConferenceInfo.id uses T.ConferenceId from types.capnp.
#   - MmsPart.id uses T.MmsPartId from types.capnp (was raw UInt64).
#   - MmsPart.contentType uses T.MimeType (was raw Text).
#   - MmsPart.data uses T.DataHandle for large payloads.
#   - RcsMessage.id uses T.TelephonyMessageId (was raw Text).
#   - MmsResult.messageId uses T.TelephonyMessageId (was raw Text).
#   - ConferenceInfo.participantsPagination for bounded iteration (Audit-6).
#   - MmsResult.error uses T.Error.
#   - All subscription interfaces have cancel for clean teardown.
#   - MmsRetrievalStatus enum has custom variant.
#   - NetworkType enum has custom variant.
#   - CallState/CallDirection/CallType have custom variants.
#   - SmsEncoding has custom variant.
#   - signalStrength comment documents unit (dBm).
#
# Audit-8 enhancements:
#   - SatelliteService: emergency off-grid satellite communication.
#   - MeshCallService/MeshMessageService: Bluetooth/Wi-Fi mesh calling.
#   - FreeBusyQuery: calendar-attached availability checking.
#   - LineManager: dual-SIM / work-personal line management.
#   - CallRecordingService: standardized call recording.
#   - VoicemailService: visual voicemail management.
#   - LanguageFallback: multi-language IVR voice menu support.
#
# Audit-9 improvements:
#   - CallQuality struct for call quality metrics.
#   - SpamScore struct for call screening.
#   - CarrierSettings for APN/MMSC configuration.
#   - E2eEncryption for SMS/MMS encryption.
#   - CallScreeningService for call screening.
#   - DataUsageBreakdown for per-app data tracking.
# ═══════════════════════════════════════════════════════════════════════

struct SimInfo {
    slot @0 :UInt32;
    present @1 :Bool;
    carrierName @2 :Text;
    serialNumber @3 :Text;
    phoneNumber @4 :Text;
    state @5 :SimState;
    mcc @6 :Text;
    mnc @7 :Text;
    iccid @8 :Text;
    isDataActive @9 :Bool;
}

enum SimState {
    absent @0;
    pinRequired @1;
    pukRequired @2;
    networkLocked @3;
    ready @4;
    notReady @5;
    permDisabled @6;
    cardIOError @7;
    custom @8;
}

struct CellularNetworkInfo {
    operatorName @0 :Text;
    type @1 :NetworkType;
    # Signal strength in dBm (typically -120 to -30).
    signalStrength @2 :Int32;
    # Normalized signal level 0-4 (0=none, 4=excellent).
    signalLevel @3 :UInt32;
    dataConnected @4 :Bool;
    dataRoaming @5 :Bool;
    cellId @6 :UInt32;
    lac @7 :UInt32;
    tac @8 :UInt32;
    volte @9 :Bool;
    vowifi @10 :Bool;
    mcc @11 :Text;
    mnc @12 :Text;
}

enum NetworkType {
    unknown @0;
    gprs @1;
    edge @2;
    umts @3;
    hsdpa @4;
    hsupa @5;
    hspa @6;
    hspaPlus @7;
    lte @8;
    nr5G @9;
    wifi @10;
    satellite @11;
    custom @12;
}

enum CallState {
    dialing @0;
    alerting @1;
    active @2;
    held @3;
    disconnected @4;
    waiting @5;
    custom @6;
}

enum CallDirection {
    incoming @0;
    outgoing @1;
    custom @2;
}

enum CallType {
    voice @0;
    video @1;
    data @2;
    custom @3;
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
}

enum DtmfTone {
    digit0 @0; digit1 @1; digit2 @2; digit3 @3; digit4 @4;
    digit5 @5; digit6 @6; digit7 @7; digit8 @8; digit9 @9;
    star @10; hash @11;
    a @12; b @13; c @14; d @15;
    flash @16; hold @17; voiceMail @18;
    custom @19;
}

struct IncomingSmsEvent {
    slot @0 :UInt32;
    sender @1 :Text;
    body @2 :Text;
    timestamp @3 :T.Timestamp;
    encoding @4 :SmsEncoding;
    smsCenter @5 :Text;
    pduType @6 :UInt8;
}

enum SmsEncoding {
    gsm7 @0;
    utf16 @1;
    eightBit @2;
    custom @3;
}

struct SmsStatusReport {
    messageId @0 :T.TelephonyMessageId;
    status @1 :SmsStatus;
    timestamp @2 :T.Timestamp;
    recipient @3 :Text;
}

enum SmsStatus {
    received @0;
    stored @1;
    sent @2;
    failed @3;
    pending @4;
    custom @5;
}

struct MmsPart {
    id @0 :T.MmsPartId;
    contentType @1 :T.MimeType;
    data @2 :T.DataHandle;
    filename @3 :Text;
    contentId @4 :Text;
    forwarded @5 :Bool;
}

struct IncomingMmsEvent {
    slot @0 :UInt32;
    sender @1 :Text;
    subject @2 :Text;
    parts @3 :List(MmsPart);
    timestamp @4 :T.Timestamp;
    read @5 :Bool;
    retrievalStatus @6 :MmsRetrievalStatus;
}

enum MmsRetrievalStatus {
    notRetrieved @0;
    retrieving @1;
    retrieved @2;
    deferred @3;
    custom @4;
}

struct MmsSendRequest {
    to @0 :Text;
    subject @1 :Text;
    parts @2 :List(MmsPart);
    smsFallback @3 :Bool;
}

struct RcsMessage {
    id @0 :T.TelephonyMessageId;
    to @1 :Text;
    body @2 :Text;
    timestamp @3 :T.Timestamp;
    direction @4 :CallDirection;
    status @5 :RcsStatus;
    contentType @6 :RcsContentType;
    isDelivered @7 :Bool;
    isRead @8 :Bool;
    replyTo @9 :Text;
}

enum RcsStatus {
    sending @0;
    sent @1;
    delivered @2;
    displayed @3;
    failed @4;
    custom @5;
}

enum RcsContentType {
    text @0;
    image @1;
    video @2;
    audio @3;
    fileTransfer @4;
    geolocation @5;
    typingIndicator @6;
    readReceipt @7;
    custom @8;
}

struct ConferenceInfo {
    id @0 :T.ConferenceId;
    name @1 :Text;
    participantCount @2 :UInt32;
    state @3 :CallState;
    participants @4 :List(CallInfo);
    # Pagination for participants. Used when participantCount exceeds practical
    # in-message limits; backend may page participants without affecting
    # participantCount (which always reports the total).
    participantsPagination @5 :T.Pagination;
}

struct DataUsage {
    mobileBytesRx @0 :UInt64;
    mobileBytesTx @1 :UInt64;
    totalBytesRx @2 :UInt64;
    totalBytesTx @3 :UInt64;
    periodStart @4 :T.Timestamp;
    periodEnd @5 :T.Timestamp;
}

interface TelephonyService {
    getSimInfo @0 (slot :UInt32) -> (info :SimInfo);
    getSimSlots @1 () -> (slots :List(SimInfo));

    getNetworkInfo @2 () -> (info :CellularNetworkInfo);

    makeCall @3 (number :Text) -> (callId :T.CallId);
    answerCall @4 (callId :T.CallId) -> T.VoidResult;
    hangUp @5 (callId :T.CallId) -> T.VoidResult;
    getActiveCalls @6 () -> (calls :List(CallInfo));

    sendDtmf @15 (callId :T.CallId, tone :DtmfTone) -> T.VoidResult;
    startDtmf @16 (callId :T.CallId, tone :DtmfTone) -> T.VoidResult;
    stopDtmf @17 (callId :T.CallId) -> T.VoidResult;

    createConference @18 (participants :List(T.CallId)) -> (conferenceId :T.ConferenceId);
    mergeCalls @19 (callIds :List(T.CallId)) -> (conferenceId :T.ConferenceId);
    splitConference @20 (conferenceId :T.ConferenceId) -> (calls :List(CallInfo));
    addConferenceParticipant @21 (conferenceId :T.ConferenceId, callId :T.CallId) -> T.VoidResult;
    removeConferenceParticipant @22 (conferenceId :T.ConferenceId, callId :T.CallId) -> T.VoidResult;
    getConferenceInfo @23 (conferenceId :T.ConferenceId) -> (info :ConferenceInfo);

    sendSms @7 (number :Text, message :Text) -> T.VoidResult;
    getSmsStatus @24 (messageId :T.TelephonyMessageId) -> (status :SmsStatusReport);

    sendMms @25 (request :MmsSendRequest) -> (result :MmsResult);
    downloadMms @26 (slot :UInt32, messageId :Text) -> (event :IncomingMmsEvent);

    sendRcs @27 (message :RcsMessage) -> T.VoidResult;
    getRcsMessages @28 (chatId :Text, since :T.Timestamp) -> (messages :List(RcsMessage), pagination :T.Pagination, total :UInt64);

    getSignalStrength @8 () -> (strength :Int32, level :UInt32);
    getDataUsage @9 () -> (usage :DataUsage);
    setMobileData @10 (enabled :Bool) -> T.VoidResult;
    isMobileDataEnabled @11 () -> (enabled :Bool);
    setDataRoaming @12 (enabled :Bool) -> T.VoidResult;

    subscribeCalls @13 () -> (subscription :CallSubscription);
    cancelCalls @29 (subscription :CallSubscription) -> T.VoidResult;
    subscribeNetwork @14 () -> (subscription :NetworkSubscription);
    cancelNetwork @30 (subscription :NetworkSubscription) -> T.VoidResult;
    subscribeSms @31 () -> (subscription :SmsSubscription);
    cancelSms @32 (subscription :SmsSubscription) -> T.VoidResult;
    subscribeMms @33 () -> (subscription :MmsSubscription);
    cancelMms @34 (subscription :MmsSubscription) -> T.VoidResult;

    # Download MMS by typed message ID (replaces text-based messageId at ordinal 26).
    downloadMmsById @35 (slot :UInt32, messageId :T.TelephonyMessageId) -> (event :IncomingMmsEvent);

    # -- Audit-8: Call management --
    holdCall @36 (callId :T.CallId) -> T.VoidResult;
    unholdCall @37 (callId :T.CallId) -> T.VoidResult;
    getCallLog @38 (pagination :T.Pagination) -> (calls :List(CallInfo), total :UInt32);

    # -- Audit-8: Calendar integration --
    getFreeBusy @39 (query :FreeBusyQuery) -> (result :FreeBusyResult);

    # -- Audit-9: Call quality monitoring --
    getCallQuality @40 (callId :T.CallId) -> (quality :CallQuality);

    # -- Audit-9: Carrier settings --
    getCarrierSettings @41 () -> (settings :CarrierSettings);
    setCarrierSettings @42 (settings :CarrierSettings) -> T.VoidResult;

    # -- Audit-9: Emergency numbers --
    setEmergencyNumber @43 (number :Text) -> T.VoidResult;

    # -- Audit-9: Data usage breakdown --
    getDataUsageBreakdown @44 () -> (breakdown :DataUsageBreakdown);

    # -- Audit-9: E2E encryption for SMS/MMS --
    getE2eEncryptionStatus @45 () -> (encryption :E2eEncryption);
    setE2eEncryption @46 (encryption :E2eEncryption) -> T.VoidResult;

    # -- Audit-9: Call transfer and forwarding --
    transferCall @47 (callId :T.CallId, targetNumber :Text) -> T.VoidResult;
    acceptTransfer @48 (callId :T.CallId) -> T.VoidResult;
    rejectTransfer @49 (callId :T.CallId) -> T.VoidResult;
    setCallForwarding @50 (enabled :Bool, targetNumber :Text) -> T.VoidResult;
    getCallForwarding @51 () -> (enabled :Bool, targetNumber :Text);

    # -- Audit-9: Video call support --
    startVideoCall @52 (number :Text) -> (callId :T.CallId);
    getVideoQuality @53 (callId :T.CallId) -> (quality :VideoQuality);

    # -- Audit-9: Emergency calling --
    getEmergencyNumbers @54 () -> (numbers :List(Text), priorityList :List(Text));
}

struct MmsResult {
    ok @0 :Bool;
    messageId @1 :T.TelephonyMessageId;
    error @2 :T.Error;
}

interface CallSubscription {
    pull @0 (pagination :T.Pagination) -> (calls :List(CallInfo), total :UInt32);
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

# ════════════════════════════════════════════════════════════════════════
# Audit-8 additions: satellite SOS, mesh calling/messaging, calendar
# free-busy, multi-line management, call recording, visual voicemail,
# language fallback for IVR systems.
# ════════════════════════════════════════════════════════════════════════

# ── Satellite Service (emergency off-grid communication) ────────────────
interface SatelliteService {
    checkAvailability @0 () -> (available :Bool, signalStrength :Int32);
    sendSos @1 (message :Text, location :T.GeoCoordinate) -> (messageId :Data);
    sendMessage @2 (number :Text, message :Text) -> (messageId :Data);
    receiveMessages @3 () -> (messages :List(SatelliteMessage));
    subscribeSatellite @4 () -> (subscription :SatelliteSubscription);
}

struct SatelliteMessage {
    messageId @0 :Data;
    sender @1 :Text;
    body @2 :Text;
    timestamp @3 :T.Timestamp;
    channel @4 :SatelliteChannel;
    encrypted @5 :Bool;
}

enum SatelliteChannel {
    sos @0;
    text @1;
    tracking @2;
    weather @3;
    custom @4;
}

interface SatelliteSubscription {
    pull @0 () -> (messages :List(SatelliteMessage));
    cancel @1 () -> T.VoidResult;
}

# ── Mesh Call Service (Bluetooth/Wi-Fi mesh calls) ─────────────────────
interface MeshCallService {
    meshCall @0 (peerId :Data, callType :CallType) -> (callId :T.CallId);
    answerMeshCall @1 (callId :T.CallId) -> T.VoidResult;
    getMeshCallQuality @2 (callId :T.CallId) -> (quality :MeshCallQuality);
    discoverMeshPeers @3 () -> (peers :List(MeshTelephonyPeer));
}

struct MeshTelephonyPeer {
    peerId @0 :Data;
    name @1 :Text;
    signalLevel @2 :UInt8;
    hops @3 :UInt8;
    capabilities @4 :List(Text);
    lastSeen @5 :T.Timestamp;
}

struct MeshCallQuality {
    signalStrength @0 :Int32;
    latency @1 :T.Duration;
    packetLoss @2 :Float32;
    codec @3 :Text;
}

# ── Mesh Message Service (mesh messaging) ──────────────────────────────
interface MeshMessageService {
    sendMeshMessage @0 (peerId :Data, body :Text) -> (messageId :Data);
    broadcastMeshMessage @1 (body :Text) -> (messageId :Data);
    receiveMeshMessages @2 () -> (messages :List(MeshMessage));
    subscribeMeshMessages @3 () -> (subscription :MeshMessageSubscription);
}

struct MeshMessage {
    messageId @0 :Data;
    sender @1 :Data;
    body @2 :Text;
    timestamp @3 :T.Timestamp;
    hops @4 :UInt8;
    ttl @5 :UInt8;
}

interface MeshMessageSubscription {
    pull @0 () -> (messages :List(MeshMessage));
    cancel @1 () -> T.VoidResult;
}

# ── Calendar Free-Busy (availability-aware calling) ────────────────────
struct FreeBusyQuery {
    phoneNumber @0 :Text;
    timeRange @1 :TimeRange;
    calendarId @2 :Text;
}

struct TimeRange {
    start @0 :T.Timestamp;
    end @1 :T.Timestamp;
}

struct FreeBusyResult {
    available @0 :Bool;
    busyPeriods @1 :List(TimeRange);
    nextFreeSlot @2 :T.Timestamp;
    calendarEvent @3 :Text;
}

# ── Line Manager (multi-line / dual-SIM management) ────────────────────
interface LineManager {
    listLines @0 () -> (lines :List(PhoneLine));
    getActiveLine @1 () -> (line :PhoneLine);
    setActiveLine @2 (lineId :Text) -> T.VoidResult;
    getLineSettings @3 (lineId :Text) -> (settings :LineSettings);
}

struct PhoneLine {
    lineId @0 :Text;
    name @1 :Text;
    simSlot @2 :UInt32;
    phoneNumber @3 :Text;
    isActive @4 :Bool;
    capabilities @5 :List(Text);
}

struct LineSettings {
    callForwarding @0 :Bool;
    callWaiting @1 :Bool;
    callerId @2 :CallerIdMode;
    voicemail @3 :Text;
}

enum CallerIdMode {
    show @0;
    hide @1;
    custom @2;
}

# ── Language Fallback (multi-language IVR) ─────────────────────────────
struct LanguageFallback {
    primary @0 :Trans.Translation;
    fallbacks @1 :List(Trans.Translation);
    maxAttempts @2 :UInt32;
}

# ── Call Recording Service ─────────────────────────────────────────────
interface CallRecordingService {
    startRecording @0 (callId :T.CallId) -> (recordingId :Data);
    stopRecording @1 (recordingId :Data) -> T.VoidResult;
    getRecordingStatus @2 (recordingId :Data) -> (status :RecordingStatus);
    listRecordings @3 (pagination :T.Pagination)
        -> (recordings :List(CallRecording), total :UInt64);
    getRecordingData @4 (recordingId :Data) -> (audio :T.DataHandle, format :RecordAudioFormat);
    # Audit-10: Recording encryption
    setRecordingEncryption @5 (recordingId :Data, encryption :RecordingEncryption) -> T.VoidResult;
    getRecordingEncryption @6 (recordingId :Data) -> (encryption :RecordingEncryption);
}

struct CallRecording {
    recordingId @0 :Data;
    callId @1 :T.CallId;
    startTime @2 :T.Timestamp;
    endTime @3 :T.Timestamp;
    duration @4 :T.Duration;
    format @5 :RecordAudioFormat;
    sizeBytes @6 :UInt64;
    encrypted @7 :Bool;
}

enum RecordingStatus {
    recording @0;
    paused @1;
    stopped @2;
    error @3;
    custom @4;
}

struct RecordAudioFormat {
    encoding @0 :Text;
    sampleRate @1 :UInt32;
    channels @2 :UInt8;
}

# ── Voicemail Service (visual voicemail) ───────────────────────────────
interface VoicemailService {
    listVoicemails @0 (pagination :T.Pagination)
        -> (voicemails :List(Voicemail), total :UInt64);
    getVoicemail @1 (voicemailId :Data) -> (voicemail :Voicemail);
    playVoicemail @2 (voicemailId :Data) -> (audio :T.DataHandle, format :RecordAudioFormat);
    deleteVoicemail @3 (voicemailId :Data) -> T.VoidResult;
    markRead @4 (voicemailId :Data) -> T.VoidResult;
    subscribeVoicemail @5 () -> (subscription :VoicemailSubscription);
}

struct Voicemail {
    voicemailId @0 :Data;
    sender @1 :Text;
    timestamp @2 :T.Timestamp;
    duration @3 :T.Duration;
    read @4 :Bool;
    transcription @5 :Text;
    sizeBytes @6 :UInt64;
}

interface VoicemailSubscription {
    pull @0 () -> (events :List(VoicemailEvent));
    cancel @1 () -> T.VoidResult;
}

struct VoicemailEvent {
    union {
        received @0 :Voicemail;
        deleted @1 :Data;
        custom @2 :Data;
    }
}

# ── Call Quality (audit-9) ────────────────────────────────────────────────

struct CallQuality {
    # MOS score (1.0-5.0).
    mosScore @0 :Float32;
    # Round-trip latency in milliseconds.
    latencyMs @1 :UInt32;
    # Jitter in milliseconds.
    jitterMs @2 :UInt32;
    # Packet loss as fraction (0.0-1.0).
    packetLoss @3 :Float32;
    # Audio codec in use.
    codec @4 :Text;
}

# ── Spam Score (audit-9) ─────────────────────────────────────────────────

struct SpamScore {
    # Spam likelihood score (0.0 = not spam, 1.0 = definitely spam).
    score @0 :Float32;
    # Whether call is blocked.
    blocked @1 :Bool;
    # Category (telemarketer, scam, survey, etc.).
    category @2 :Text;
}

# ── Carrier Settings (audit-9) ──────────────────────────────────────────

struct CarrierSettings {
    # APN name.
    apn @0 :Text;
    # MMSC URL.
    mmsc @1 :Text;
    # MMS proxy.
    mmsProxy @2 :Text;
    # MMS port.
    mmsPort @3 :UInt16;
    # Authentication type.
    authType @4 :Text;
    # Whether carrier is default.
    isDefault @5 :Bool;
}

# ── E2E Encryption (audit-9) ─────────────────────────────────────────────

struct E2eEncryption {
    # Whether E2E encryption is enabled.
    enabled @0 :Bool;
    # Encryption algorithm.
    algorithm @1 :Text;
    # Whether keys are verified.
    keysVerified @2 :Bool;
}

# ── Data Usage Breakdown (audit-9) ───────────────────────────────────────

struct DataUsageBreakdown {
    # Per-app data usage.
    apps @0 :List(AppDataUsage);
    # Total as computed from apps.
    totalBytes @1 :UInt64;
}

struct AppDataUsage {
    appId @0 :T.AppId;
    appName @1 :Text;
    bytesRx @2 :UInt64;
    bytesTx @3 :UInt64;
}

# ── Call Screening Service (audit-9) ─────────────────────────────────────

interface CallScreeningService {
    # Screen a call and return spam score.
    screenCall @0 (callerId :Text) -> (score :SpamScore);

    # Get current block list.
    getBlockList @1 (pagination :T.Pagination) -> (numbers :List(Text), total :UInt64);

    # Add a number to block list.
    blockNumber @2 (number :Text) -> T.VoidResult;

    # Remove a number from block list.
    unblockNumber @3 (number :Text) -> T.VoidResult;
}

# ── Video Quality (audit-9) ────────────────────────────────────────────────

struct VideoQuality {
    # Resolution width.
    width @0 :UInt16;
    # Resolution height.
    height @1 :UInt16;
    # Frame rate in fps.
    frameRate @2 :UInt16;
    # Bitrate in kbps.
    bitrate @3 :UInt32;
    # Packet loss percentage (0.0-100.0).
    packetLossPercent @4 :Float32;
    # Video codec in use.
    codec @5 :Text;
}

# ── Recording Encryption (audit-10) ────────────────────────────────────

struct RecordingEncryption {
    # Whether encryption is enabled.
    enabled @0 :Bool;
    # Encryption algorithm (e.g., "aes-256-gcm", "chacha20-poly1305").
    algorithm @1 :Text;
    # Encryption key (encrypted with device key, not plaintext).
    encryptedKey @2 :Data;
    # Key identifier for key rotation.
    keyId @3 :Text;
    # When the key was created.
    createdAt @4 :T.Timestamp;
}

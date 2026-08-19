@0xa1b2c3d4e5f60052;

# ═══════════════════════════════════════════════════════════════════════
# NFC - near-field communication, ISO-DEP APDU, HCE, secure elements.
#
# Improvements beyond the original schema:
#   - NfcTagId typed ID replaces raw UInt64.
#   - NfcServiceId typed ID for HCE service names (was raw Data).
#   - T.Duration for ISO-DEP timeout.
#   - Subscription cancel methods added.
#   - Custom/other variants on all enums.
#   - HceService.name changed from Data to Text (names are strings).
#
# Audit-7 improvements:
#   - NFC-EV charging (electric vehicle charging via NFC).
#   - NFC-WLC (wireless charging negotiation via NFC).
#   - Contactless payment (mobile wallets, tokenized payments).
#   - NFC relay detection (verify proximity, prevent relay attacks).
#   - NFC transaction logging (payment history).
#   - NFC access control (physical access: doors, gates, turnstiles).
#   - NFC data integrity verification.
#   - NFC multi-tag detection.
#   - NFC card emulation configuration.
#   - NFC reader mode configuration.
#
# Audit-9 improvements:
#   - DigitalIdentity for passport/driver's license verification.
#   - LoyaltyProgram for loyalty card emulation.
#   - TransitSession for public transit payment.
#   - SmartPoster for interactive tap-to-download/connect/pay.
#   - MultiTag for simultaneous multiple tag detection.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ── NFC State ───────────────────────────────────────────────

enum NfcState {
    off @0;
    turningOn @1;
    on @2;
    turningOff @3;
    custom @4;
}

# ── Tag Types ───────────────────────────────────────────────

enum TagType {
    unknown @0;
    ndef @1;
    mifareClassic @2;
    mifareUltralight @3;
    isoDep @4;
    nfcA @5;
    nfcB @6;
    nfcF @7;
    nfcV @8;
    ndefFormatable @9;
    iso15693 @10;
    jewel @11;
    custom @12;
}

# ── Tag ─────────────────────────────────────────────────────

struct NfcTag {
    id @0 :T.NfcTagId;
    type @1 :TagType;
    # Unique tag identifier (hardware UID).
    tagId @2 :Data;
    size @3 :UInt32;
    readOnly @4 :Bool;
    ndefRecords @5 :List(NdefRecord);
    techData @6 :T.StringMap;
    # ATS (Answer-to-Select) for ISO-DEP tags.
    ats @7 :Data;
    # SAK (Select Acknowledge) for ISO-DEP.
    sak @8 :UInt16;
    # Which secure element this tag is routed to.
    routedTo @9 :SecureElement;
    # ISO-DEP command timeout.
    timeout @10 :T.Duration;
    # Whether a relay attack was detected on this tag.
    relayDetected @11 :Bool;
    # Whether data integrity check passed.
    integrityCheck @12 :Bool;
}

# ── NDEF Record ─────────────────────────────────────────────

struct NdefRecord {
    tnf @0 :NdefTnf;
    type @1 :Data;
    id @2 :Data;
    payload @3 :Data;
}

enum NdefTnf {
    empty @0;
    wellKnown @1;
    mediaType @2;
    absoluteUri @3;
    externalType @4;
    unknown @5;
    unchanged @6;
    reserved @7;
    custom @8;
}

# ── Secure Element ──────────────────────────────────────────

enum SecureElement {
    unknown @0;
    # Embedded secure element (eSE).
    embedded @1;
    # SIM card secure element (UICC).
    sim @2;
    # Secure digital card.
    sd @3;
    # Host.
    host @4;
    custom @5;
}

# ── APDU ────────────────────────────────────────────────────

struct ApduCommand {
    cla @0 :UInt8;
    ins @1 :UInt8;
    p1 @2 :UInt8;
    p2 @3 :UInt8;
    data @4 :Data;
    # Expected response length (Le field).
    le @5 :UInt16;
}

struct ApduResponse {
    data @0 :Data;
    sw1 @1 :UInt8;
    sw2 @2 :UInt8;
    # Whether the command completed normally (sw1=0x90, sw2=0x00).
    ok @3 :Bool;
}

# ── HCE ─────────────────────────────────────────────────────

enum HceState {
    inactive @0;
    active @1;
    error @2;
    custom @3;
}

struct HceService {
    # Logical service name (typed identifier).
    name @0 :T.NfcServiceId;
    displayName @1 :Text;
    # AIDs this service wants to handle (subset of what the app declares).
    allowedAids @2 :List(Data);
    # Which secure element to route to.
    secureElement @3 :SecureElement;
    # Lost-on-disconnect semantics.
    lostOnDisconnect @4 :Bool;
    # Whether to use ISO-DEP protocol.
    isoDep @5 :Bool;
}

# ── P2P (Beam-style) ───────────────────────────────────────

struct NdefMessage {
    records @0 :List(NdefRecord);
}

struct BeamEvent {
    # Peer device address (or empty if unknown).
    peerAddress @0 :Text;
    # NDEF message received from peer.
    message @1 :NdefMessage;
    timestamp @2 :T.Timestamp;
    # Whether P2P data exchange was encrypted.
    encrypted @3 :Bool;
}

# ── NFC-EV Charging ─────────────────────────────────────────

struct EvChargingSession {
    # Charging station identifier.
    stationId @0 :Text;
    # Charging power in kW.
    powerKw @1 :Float32;
    # Session duration.
    duration @2 :T.Duration;
    # Cost of the session.
    cost @3 :Float32;
    # Currency code (e.g., "USD", "EUR").
    currency @4 :Text;
    # Connector type (e.g., "CCS", "CHAdeMO", "Type2").
    connectorType @5 :Text;
    # Session state.
    state @6 :EvChargingState;
}

enum EvChargingState {
    idle @0;
    negotiating @1;
    charging @2;
    complete @3;
    error @4;
    custom @5;
}

# ── NFC-WLC (Wireless Charging) ─────────────────────────────

struct WirelessChargingSession {
    # Charger type (e.g., "Qi", "PMA", "AirFuel").
    chargerType @0 :Text;
    # Maximum power the charger supports (watts).
    maxPowerW @1 :UInt32;
    # Negotiated power (watts).
    negotiatedPowerW @2 :UInt32;
    # Whether charging is active.
    active @3 :Bool;
    # Charging state.
    state @4 :WirelessChargingState;
}

enum WirelessChargingState {
    detected @0;
    negotiating @1;
    charging @2;
    complete @3;
    error @4;
    custom @5;
}

# ── Contactless Payment ─────────────────────────────────────

struct PaymentSession {
    # Merchant identifier.
    merchantId @0 :Text;
    # Transaction amount.
    amount @1 :Float32;
    # Currency code (e.g., "USD", "EUR").
    currency @2 :Text;
    # Payment token (tokenized card data).
    token @3 :Data;
    # Transaction state.
    state @4 :PaymentState;
    # Transaction identifier.
    transactionId @5 :Text;
    # Whether the transaction was approved.
    approved @6 :Bool;
}

enum PaymentState {
    idle @0;
    processing @1;
    approved @2;
    declined @3;
    error @4;
    custom @5;
}

# ── NFC Access Control ──────────────────────────────────────

struct AccessControlSession {
    # Door/gate/turnstile identifier.
    doorId @0 :Text;
    # Whether access was granted.
    accessGranted @1 :Bool;
    # When access was checked.
    timestamp @2 :T.Timestamp;
    # Access control credential type used.
    credentialType @3 :AccessCredentialType;
    # User identifier (if known).
    userId @4 :Text;
}

enum AccessCredentialType {
    nfc @0;
    ble @1;
    pin @2;
    biometric @3;
    combined @4;
    custom @5;
}

# ── NFC Transaction Log ─────────────────────────────────────

struct NfcTransaction {
    # Transaction identifier.
    transactionId @0 :Text;
    # Transaction type.
    type @1 :TransactionType;
    # When the transaction occurred.
    timestamp @2 :T.Timestamp;
    # Tag identifier (if applicable).
    tagId @3 :Data;
    # Amount (if applicable).
    amount @4 :Float32;
    # Currency code.
    currency @5 :Text;
    # Transaction state.
    success @6 :Bool;
    # Additional metadata.
    metadata @7 :T.StringMap;
}

enum TransactionType {
    payment @0;
    accessControl @1;
    dataExchange @2;
    transit @3;
    loyalty @4;
    custom @5;
}

# ── Card Emulation Config ───────────────────────────────────

struct CardEmulationConfig {
    # Card type to emulate (e.g., "credit", "transit", "identity").
    cardType @0 :Text;
    # Application IDs to route to this emulation.
    aidList @1 :List(Data);
    # Which secure element to use.
    secureElement @2 :SecureElement;
    # Whether to use ISO-DEP protocol.
    isoDep @3 :Bool;
}

# ── Reader Mode ─────────────────────────────────────────────

enum ReaderMode {
    # Normal mode: read tags, HCE, P2P.
    normal @0;
    # Reader-only mode: only read tags, no HCE.
    readerOnly @1;
    # Card emulation only: no tag reading.
    cardEmulation @2;
    # Peer-to-peer only.
    peerToPeer @3;
    custom @4;
}

# ── NFC Digital Identity ────────────────────────────────────────────────

struct DigitalIdentity {
    # Document type.
    documentType @0 :IdentityDocumentType;
    # Document number.
    documentNumber @1 :Text;
    # Date of birth.
    dateOfBirth @2 :T.Timestamp;
    # Expiry date.
    expiryDate @3 :T.Timestamp;
    # Issuing country (ISO 3166-1 alpha-3).
    issuingCountry @4 :Text;
    # Holder's full name.
    holderName @5 :Text;
    # Whether the document was verified.
    verified @6 :Bool;
}

enum IdentityDocumentType {
    passport @0;
    driversLicense @1;
    nationalId @2;
    residencePermit @3;
    custom @4;
}

# ── NFC Loyalty Program ─────────────────────────────────────────────────

struct LoyaltyProgram {
    # Program identifier.
    programId @0 :Text;
    # Program name.
    programName @1 :Text;
    # Member identifier.
    memberId @2 :Text;
    # Current point balance.
    points @3 :Int64;
    # Tier level.
    tier @4 :Text;
    # Points type.
    pointType @5 :LoyaltyPointType;
}

enum LoyaltyPointType {
    currency @0;
    miles @1;
    points @2;
    custom @3;
}

# ── NFC Transit ────────────────────────────────────────────────────────

struct TransitSession {
    # Transit card type.
    cardType @0 :TransitCardType;
    # Card identifier.
    cardId @1 :Text;
    # Current balance.
    balance @2 :Float32;
    # Currency code.
    currency @3 :Text;
    # Whether in a transit zone.
    inTransit @4 :Bool;
    # Current zone (if in transit).
    currentZone @5 :Text;
}

enum TransitCardType {
    subway @0;
    bus @1;
    train @2;
    ferry @3;
    multimodal @4;
    custom @5;
}

# ── NFC Smart Poster ───────────────────────────────────────────────────

struct SmartPoster {
    # Title text.
    title @0 :Text;
    # URL to open.
    url @1 :Text;
    # Action to perform.
    action @2 :SpAction;
    # Icon/SW identifier.
    icon @3 :Data;
    # Wi-Fi credentials (for tap-to-connect).
    wifiCredentials @4 :WifiCredentials;
}

enum SpAction {
    open @0;
    do @1;
    save @2;
    send @3;
    custom @4;
}

struct WifiCredentials {
    ssid @0 :Text;
    password @1 :Text;
    securityType @2 :Text;
}

# ── NFC Multi-Tag ───────────────────────────────────────────────────────

struct MultiTag {
    # All tags detected simultaneously.
    tags @0 :List(NfcTag);
    # Number of tags detected.
    count @1 :UInt8;
    # Whether all tags were read successfully.
    allRead @2 :Bool;
}

# ── Service ─────────────────────────────────────────────────

interface NfcService {
    getState @0 () -> (state :NfcState);
    enable @1 () -> T.VoidResult;
    disable @2 () -> T.VoidResult;
    isAvailable @3 () -> (available :Bool);

    startDiscovery @4 () -> (subscription :DiscoverySubscription);
    stopDiscovery @5 () -> T.VoidResult;

    readNdef @6 (tagId :T.NfcTagId) -> (records :List(NdefRecord));
    writeNdef @7 (tagId :T.NfcTagId, records :List(NdefRecord)) -> T.VoidResult;
    formatNdef @13 (tagId :T.NfcTagId) -> T.VoidResult;
    makeReadOnly @14 (tagId :T.NfcTagId) -> T.VoidResult;

    # ── ISO-DEP APDU (ISO7816) ──
    # Raw APDU exchange with ISO-DEP tags (payment, identity).
    transceive @15 (tagId :T.NfcTagId, command :ApduCommand) -> (response :ApduResponse);

    # ── HCE ──
    registerHceService @8 (service :HceService) -> T.VoidResult;
    unregisterHceService @9 (serviceName :T.NfcServiceId) -> T.VoidResult;
    startHce @10 (serviceName :T.NfcServiceId) -> T.VoidResult;
    stopHce @11 () -> T.VoidResult;
    getHceState @12 () -> (state :HceState);

    # ── Secure element queries ──
    listSecureElements @16 (pagination :T.Pagination) -> (elements :List(SecureElementInfo));

    # ── P2P ──
    sendNdef @17 (message :NdefMessage) -> T.VoidResult;

    # ── Subscriptions ──
    subscribeTags @18 () -> (subscription :TagSubscription);
    subscribeHce @19 () -> (subscription :HceSubscription);
    subscribeBeam @20 () -> (subscription :BeamSubscription);

    # ── NFC-EV Charging ──
    startEvCharging @21 (stationId :Text) -> (session :EvChargingSession);
    stopEvCharging @22 () -> T.VoidResult;
    getEvChargingSession @23 () -> (session :EvChargingSession);

    # ── NFC-WLC ──
    getWirelessChargingSession @24 () -> (session :WirelessChargingSession);

    # ── Contactless Payment ──
    startPayment @25 (merchantId :Text, amount :Float32, currency :Text) -> (session :PaymentSession);
    getPaymentSession @26 () -> (session :PaymentSession);

    # ── Transaction Log ──
    getTransactions @27 (pagination :T.Pagination) -> (transactions :List(NfcTransaction), total :UInt64);

    # ── Access Control ──
    checkAccess @28 (doorId :Text) -> (session :AccessControlSession);

    # ── Card Emulation ──
    setCardEmulation @29 (config :CardEmulationConfig) -> T.VoidResult;
    getCardEmulation @30 () -> (config :CardEmulationConfig);

    # ── Reader Mode ──
    setReaderMode @31 (mode :ReaderMode) -> T.VoidResult;
    getReaderMode @32 () -> (mode :ReaderMode);

    # ── Digital Identity ──
    verifyDigitalIdentity @33 (documentType :IdentityDocumentType, data :Data)
        -> (identity :DigitalIdentity);

    # ── Loyalty Program ──
    getLoyaltyPoints @34 (programId :Text) -> (program :LoyaltyProgram);

    # ── Loyalty Program Management ──
    createLoyaltyProgram @39 (programName :Text, pointType :LoyaltyPointType) -> (program :LoyaltyProgram);
    updateLoyaltyProgram @40 (program :LoyaltyProgram) -> T.VoidResult;
    deleteLoyaltyProgram @41 (programId :Text) -> T.VoidResult;
    accrueLoyaltyPoints @42 (programId :Text, points :Int64) -> (newBalance :Int64);
    redeemLoyaltyPoints @43 (programId :Text, points :Int64) -> (success :Bool, newBalance :Int64);

    # ── Transit ──
    useTransitBalance @35 (cardType :TransitCardType, amount :Float32)
        -> (session :TransitSession);
    getTransitBalance @44 (cardType :TransitCardType) -> (balance :Float32);
    topUpTransit @45 (cardType :TransitCardType, amount :Float32) -> (success :Bool);

    # ── Smart Poster ──
    readSmartPoster @36 (tagId :T.NfcTagId) -> (poster :SmartPoster);

    # ── Multi-Tag Detection ──
    detectMultiTag @37 () -> (multiTag :MultiTag);

    # ── P2P Encryption ──
    encryptPeerMessage @38 (data :Data, recipientId :Text) -> (encryptedData :Data);
    decryptPeerMessage @46 (encryptedData :Data, senderId :Text) -> (data :Data);

    # ── Smart Poster Actions ──
    performSmartPosterAction @47 (tagId :T.NfcTagId, action :SpAction) -> (result :SmartPosterActionResult);

    # ── Digital Identity Attestation Verification ──
    verifyDigitalIdentityAttestation @48 (documentType :IdentityDocumentType, data :Data,
        attestation :Data, publicKey :Data) -> (result :DigitalIdentityAttestationResult);

    # ── Multi-Tag Arbitration ──
    selectTag @49 (multiTag :MultiTag, criteria :TagSelectionCriteria) -> (selected :NfcTag);
}

struct SecureElementInfo {
    element @0 :SecureElement;
    name @1 :Text;
    # Whether this element is accessible.
    available @2 :Bool;
    # Whether the element is reserved for payment.
    paymentReserved @3 :Bool;
}

# ── Subscriptions ───────────────────────────────────────────

interface DiscoverySubscription {
    pull @0 () -> (tags :List(NfcTag));
    cancel @1 () -> T.VoidResult;
}

interface TagSubscription {
    pull @0 () -> (tags :List(NfcTag));
    cancel @1 () -> T.VoidResult;
}

interface HceSubscription {
    pull @0 () -> (event :HceEvent);
    cancel @1 () -> T.VoidResult;
}

interface BeamSubscription {
    pull @0 () -> (event :BeamEvent);
    cancel @1 () -> T.VoidResult;
}

struct HceEvent {
    # Which HCE service was activated.
    serviceName @0 :T.NfcServiceId;
    # APDU command received.
    command @1 :ApduCommand;
    # Whether this is a "lost on disconnect" session.
    lostOnDisconnect @2 :Bool;
}

# ── Smart Poster Action Result ────────────────────────────────

struct SmartPosterActionResult {
    # Whether the action completed successfully.
    success @0 :Bool;
    # Action that was performed.
    action @1 :SpAction;
    # Result data (URL opened, contact saved, etc.).
    resultData @2 :Data;
    # Error message (if failed).
    error @3 :Text;
}

# ── Digital Identity Attestation Result ────────────────────────

struct DigitalIdentityAttestationResult {
    # Whether attestation verification succeeded.
    verified @0 :Bool;
    # Identity data (if verification succeeded).
    identity @1 :DigitalIdentity;
    # Attestation status.
    status @2 :AttestationStatus;
    # Reason for failure (if any).
    reason @3 :Text;
    # When verification was performed.
    verifiedAt @4 :T.Timestamp;
}

enum AttestationStatus {
    verified @0;
    pending @1;
    failed @2;
    expired @3;
    revoked @4;
    custom @5;
}

# ── Tag Selection Criteria ────────────────────────────────────

struct TagSelectionCriteria {
    # Preferred tag type.
    preferredType @0 :TagType;
    # Minimum size in bytes.
    minSize @1 :UInt32;
    # Whether tag must be writable.
    writable @2 :Bool;
    # Required NDEF record type.
    requiredNdefType @3 :Data;
    # Prefer tag with relay detection cleared.
    noRelay @4 :Bool;
}

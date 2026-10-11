@0xa1b2c3d4e5f60052;

# ═══════════════════════════════════════════════════════════════════════
# NFC — the radio transport, and nothing else.
#
# This file is the contract between a component and an NFC field: which
# tags are in range, what a tag carries (NDEF), how to exchange an
# application-protocol data unit with an ISO-DEP tag (ISO 7816, a real
# closed standard), how host card emulation is registered and routed to
# a secure element, and how two devices beam NDEF to each other.
#
# ── WHAT WAS REMOVED, AND WHY (REWRITE, scope) ─────────────────────────
#
# From line 184 onward the previous revision stopped being NFC and
# became an application stack bolted onto a radio: contactless payment
# (`PaymentSession`, `startPayment`), loyalty (`LoyaltyProgram`,
# `accrueLoyaltyPoints`), transit (`TransitSession`, `topUpTransit`),
# EV charging (`EvChargingSession`), physical access control
# (`AccessControlSession`, `checkAccess`), government identity
# (`DigitalIdentity`, `IdentityDocumentType`), a Wi-Fi credential
# handoff (`WifiCredentials` with a plaintext `password :Text`), and a
# private cryptography primitive (`encryptPeerMessage` /
# `decryptPeerMessage` keyed by a `Text` recipient, with no algorithm
# field at all).
#
# Every one of those failed the Agnostic/Timeless Test at litmus #2
# (DESIGN_PRINCIPLES.md:110): a consumer does not need a
# payment-settlement contract in order to interoperate with an NFC
# RADIO. Each was also closed by today's institutions rather than by
# mathematics — a 2046 transit network with a new fare model, a new
# identity scheme, or a post-quantum payment token has to be forced
# into `PaymentState` or `TransitCardType`.
#
# The removal is a gain, not a cut of capability:
#
#   * `startPayment`/`getPaymentSession` were UNGATED. Any client
#     holding this reference could initiate a payment and then observe
#     it. That is the sharpest missing gate in the protocol, and it is
#     gone because the payment path is gone — a payment service built
#     on this transport gates itself.
#   * `WifiCredentials.password :Text` was a plaintext secret carried
#     from a TAG, in a schema with no authority model at all. It is gone
#     because a credential handoff is not a radio operation.
#   * `encryptPeerMessage` declared a crypto primitive with no
#     algorithm and no negotiation, where crypto.capnp already exists
#     (DESIGN_PRINCIPLES.md:96 Edge Case 4: reject the mechanism,
#     accept the contract). Two backends' "encrypted" peer messages were
#     mutually unreadable.
#   * `NdefMessage`/`NdefRecord` are unchanged — a NDEF message is a
#     container, and a 2046 smart poster, loyalty card or transit pass
#     is DATA in that container, which is exactly what a transport
#     should carry.
#
# What remains is smaller and completely transport-shaped: tag
# discovery, tag read/write, APDU exchange, card emulation, secure
# element routing, P2P beam, and the RF configuration that controls
# which of those the controller performs.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ── NFC State ───────────────────────────────────────────────

enum NfcState {
    unknown @0;
    off @1;
    turningOn @2;
    on @3;
    turningOff @4;
    custom @5;
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

# The NFC Forum's Type Name Format values. Faithful to the standard,
# which is a genuinely closed set — this is one of the few enums in the
# protocol that is closed by a published specification rather than by a
# product schedule.
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

# An APDU response, faithful to ISO 7816: `ok` reports the status word,
# and the transport-level failure (the tag went away mid-exchange, which
# a ~100 ms tap makes routine) is reported separately by the enclosing
# result union rather than by overloading sw1/sw2.
struct ApduResponse {
    data @0 :Data;
    sw1 @1 :UInt8;
    sw2 @2 :UInt8;
    # Whether the command completed normally (sw1=0x90, sw2=0x00).
    ok @3 :Bool;
}

# ── HCE ─────────────────────────────────────────────────────

enum HceState {
    unknown @0;
    inactive @1;
    active @2;
    error @3;
    custom @4;
}

struct HceService {
    # Logical service name. SET BY THE BACKEND on registration and
    # returned to the caller — the previous shape made this a
    # caller-invented UInt64, so two apps registering the same value
    # silently took over each other's HCE service.
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
    # Peer device, as an opaque reference. The previous `peerAddress
    # :Text` was an address by string with no relation to
    # T.DeviceAddress — the same schism that made bluetooth.capnp's
    # scan results unusable, fixed here by exposing the opaque type.
    peer @0 :T.DeviceAddress;
    # Printable form where one exists (a MAC string). Display only.
    peerAddressText @1 :Text;
    # NDEF message received from peer.
    message @2 :NdefMessage;
    timestamp @3 :T.Timestamp;
    # Whether P2P data exchange was encrypted.
    encrypted @4 :Bool;
}

# ── RF configuration ────────────────────────────────────────

struct CardEmulationConfig {
    # Which secure element to route emulation to.
    secureElement @0 :SecureElement;
    # AIDs emulated on the host.
    hostAids @1 :List(Data);
    # AIDs routed to the secure element.
    seAids @2 :List(Data);
}

enum ReaderMode {
    unknown @0;
    # RF field on, reading tags.
    reader @1;
    # RF field on, emulating a card.
    cardEmulation @2;
    # Both (peer-to-peer capable).
    peer @3;
    custom @4;
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

# Several tags in the field at once. A transport fact, not an
# application one: the radio sees all of them, and the client says
# which one it wants.
struct MultiTag {
    tags @0 :List(NfcTag);
}

struct SecureElementInfo {
    element @0 :SecureElement;
    name @1 :Text;
    # Whether this element is accessible.
    accessible @2 :Bool;
    # Whether this element is reserved for a specific use and therefore
    # not available to this caller.
    reserved @3 :Bool;
}

struct HceEvent {
    # Which HCE service was activated.
    serviceName @0 :T.NfcServiceId;
    # APDU command received.
    command @1 :ApduCommand;
    # Whether this is a "lost on disconnect" session.
    lostOnDisconnect @2 :Bool;
}

# ═══════════════════════════════════════════════════════════════════════
# Service
#
# The split follows ai.capnp:578-584. Discovery and reading are ungated
# so a caller can learn what is in range before it holds any authority;
# everything that writes to a tag, starts an RF field, emulates a card,
# or claims a secure element is behind ONE accessor, and the methods on
# the returned controller take no capability parameter — the reference
# is the authority.
# ═══════════════════════════════════════════════════════════════════════
interface NfcService {
    # ── Ungated: state and discovery ──
    getState @0 () -> (state :NfcState);
    isAvailable @1 () -> (available :Bool);

    # Start discovery. This powers the RF field and is the single largest
    # radio-power consumer in the protocol, which is why it is on the
    # gated controller below rather than here.
    subscribeTags @2 () -> (subscription :TagSubscription);
    detectMultiTag @3 () -> (result :MultiTagResult);
    selectTag @4 (multiTag :MultiTag, criteria :TagSelectionCriteria)
               -> (result :TagSelectionResult);

    readNdef @5 (tagId :T.NfcTagId) -> (result :NdefReadResult);
    readSmartPosterRecords @6 (tagId :T.NfcTagId) -> (records :List(NdefRecord));

    listSecureElements @7 (pagination :T.Pagination)
                       -> (elements :List(SecureElementInfo), total :UInt64);

    subscribeHce @8 () -> (subscription :HceSubscription);
    subscribeBeam @9 () -> (subscription :BeamSubscription);

    # ── Gated once, at acquisition ──
    # `enable`/`disable` and all RF configuration, tag writing, card
    # emulation and secure-element routing live on the controller: each
    # of them changes what the radio does or writes to a physical tag,
    # and none of them was gated before.
    openController @10 (authority :Capability) -> (controller :NfcController);
}

struct NdefReadResult {
    union {
        ok @0 :List(NdefRecord);
        # The tag was removed, or is unreadable, or is empty. The
        # previous bare-list return made all three the same fact.
        error @1 :T.Error;
    }
}

struct MultiTagResult {
    union {
        ok @0 :MultiTag;
        error @1 :T.Error;
    }
}

struct TagSelectionResult {
    union {
        ok @0 :NfcTag;
        error @1 :T.Error;
    }
}

interface NfcController {
    enable @0 () -> T.VoidResult;
    disable @1 () -> T.VoidResult;

    startDiscovery @2 () -> (subscription :TagSubscription);
    stopDiscovery @3 () -> T.VoidResult;

    writeNdef @4 (tagId :T.NfcTagId, records :List(NdefRecord)) -> T.VoidResult;
    formatNdef @5 (tagId :T.NfcTagId) -> T.VoidResult;
    makeReadOnly @6 (tagId :T.NfcTagId) -> T.VoidResult;

    # Raw APDU exchange with ISO-DEP tags. The status word is in the
    # response; a transport failure (the tag left the field) is the
    # union's error arm, which the previous shape could not express.
    transceive @7 (tagId :T.NfcTagId, command :ApduCommand)
                -> (result :ApduResult);

    registerHceService @8 (service :HceService) -> (result :HceRegistrationResult);
    unregisterHceService @9 (serviceName :T.NfcServiceId) -> T.VoidResult;
    startHce @10 (serviceName :T.NfcServiceId) -> T.VoidResult;
    stopHce @11 () -> T.VoidResult;
    getHceState @12 () -> (state :HceState);

    sendNdef @13 (message :NdefMessage) -> T.VoidResult;

    setCardEmulation @14 (config :CardEmulationConfig) -> T.VoidResult;
    getCardEmulation @15 () -> (config :CardEmulationConfig);
    setReaderMode @16 (mode :ReaderMode) -> T.VoidResult;
    getReaderMode @17 () -> (mode :ReaderMode);
}

struct ApduResult {
    union {
        ok @0 :ApduResponse;
        error @1 :T.Error;
    }
}

struct HceRegistrationResult {
    union {
        ok @0 :T.NfcServiceId;
        error @1 :T.Error;
    }
}

# ── Subscriptions ────────────────────────────────────────────
#
# One subscription for tag discovery. The previous revision had two with
# identical signatures (`startDiscovery` and `subscribeTags`) and no
# stated difference — does one power the RF field and the other merely
# observe? The dual pattern DESIGN_PRINCIPLES.md:255 flags. Now: the
# gated controller's `startDiscovery` powers the field, and this
# ungated subscription observes. One meaning each.
interface TagSubscription {
    pull @0 (maxTags :UInt32) -> (tags :List(NfcTag));
    cancel @1 () -> T.VoidResult;
}

interface NfcTagEventSubscription {
    pull @0 (maxEvents :UInt32) -> (events :List(TagEvent));
    cancel @1 () -> T.VoidResult;
}

# Unknown values are ignored, never rejected (ai.capnp:43-47).
struct UnknownNfcEvent {
    typeId @0 :UInt64;
    payload @1 :Data;
}

struct TagEvent {
    at @0 :UInt64;
    union {
        tagArrived @1 :NfcTag;
        tagDeparted @2 :T.NfcTagId;
        unknown @3 :UnknownNfcEvent;
    }
}

interface HceSubscription {
    pull @0 (maxEvents :UInt32) -> (events :List(HceEvent));
    cancel @1 () -> T.VoidResult;
}

interface BeamSubscription {
    pull @0 (maxEvents :UInt32) -> (events :List(BeamEvent));
    cancel @1 () -> T.VoidResult;
}

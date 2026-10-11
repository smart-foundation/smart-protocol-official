@0xa1b2c3d4e5f60051;

# ═══════════════════════════════════════════════════════════════════════
# Bluetooth - BR/EDR + LE dual-mode, GATT services, pairing flows
#
# Transport-agnostic Bluetooth contract covering scan, pair, connect,
# profile management, and GATT operations. The same schema works on
# Linux (BlueZ), macOS (IOBluetooth), Windows (BTHPORT), and custom
# stacks.
#
# All addresses are typed Text (MAC addresses are backend-resolved).
# All subscriptions have cancel methods. All lists are paginated where
# unbounded. GATT handles are UInt16 (BT spec-defined).
#
# Audit-7 improvements:
#   - BluetoothUuid struct: typed UUID with short16/full128/custom union.
#   - GattProperties struct: typed boolean properties replacing UInt8 bitfield.
#   - LE Audio profiles (LE Audio, HFP AG/HF, MCP, VCP, CSIS, TBS, MBS).
#   - LeAudioConfig struct for LE Audio device configuration.
#   - GattServiceFilter for targeted service discovery.
#   - BluetoothDevice.bondedAt/lastSeenAt timestamps.
#   - ScanFilter.maxAge for staleness filtering.
#   - ScanFilter.addressTypes for address type filtering.
#   - BluetoothConnectionEvent.profileConnected/profileDisconnected/bonded/unbonded.
#   - GattEvent.added/removed for dynamic GATT databases.
#
# Audit-9 improvements:
#   - ClassicAudioCodec struct for A2DP codec negotiation.
#   - AuracastService for LE Audio broadcast scanning/joining.
#   - RSSI filtering per service UUID.
#   - BluetoothMeshNode for mesh networking.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ── Bluetooth UUID ─────────────────────────────────────────────────────

struct BluetoothUuid {
    union {
        # 16-bit standard UUID (e.g., 0x180D for Heart Rate).
        short16 @0 :UInt16;
        # 128-bit custom UUID (16 bytes, network byte order).
        full128 @1 :Data;
        # Backend-specific UUID format.
        custom @2 :Data;
    }
}

# ── Bluetooth State ─────────────────────────────────────────────────────

enum BluetoothState {
    off @0;
    turningOn @1;
    on @2;
    turningOff @3;
    custom @4;
}

# ── Device Info ─────────────────────────────────────────────────────────

# ── Device Info ─────────────────────────────────────────────────────────
#
# THE ADDRESS. Every method in this file that takes a device takes
# `T.DeviceAddress` — an opaque, backend-issued reference — while the
# descriptor used to expose `address :Text`, a MAC string. The two were
# unrelated types with no method to convert one to the other, so a scan
# result literally could not be passed to ANY method: a 2046 client that
# scanned, got `BluetoothDevice.address = "AA:BB:CC:DD:EE:FF"`, and then
# called `getDevice`, `pair`, `connectProfile`, `readCharacteristic` or
# anything else had no way to do it. That is a total break of the primary
# use case, and it is fixed here by making the descriptor expose the
# same opaque type the methods accept.
#
# The human-readable form is kept as a separate, non-authoritative
# field, because a UI must show something and an address is what users
# see. It is NOT an identifier: nothing accepts it, and a backend that
# cannot determine a printable form (a device behind a resolving
# identity address, a device whose MAC never left the controller) leaves
# it empty rather than inventing one.
struct BluetoothDevice {
    # Opaque, backend-issued reference. This is what every method takes.
    address @0 :T.DeviceAddress;
    name @1 :Text;
    alias @2 :Text;
    # Class of device (24-bit CoD). 0 if not available.
    class @3 :UInt32;
    paired @4 :Bool;
    connected @5 :Bool;
    bonded @6 :Bool;
    trusted @7 :Bool;
    rssi @8 :Int32;
    txPower @9 :Int32;
    # Service UUIDs advertised by this device.
    uuids @10 :List(Text);
    # Physical transport: classic, le, dual.
    transport @11 :BleTransport;
    # Connection parameters (valid when connected via LE).
    connectionParams @12 :BleConnectionParams;
    # Manufacturer name.
    manufacturerName @13 :Text;
    # Model name.
    modelName @14 :Text;
    # Firmware revision.
    firmwareRevision @15 :Text;
    # Hardware revision.
    hardwareRevision @16 :Text;
    # When bonding occurred (empty = not bonded).
    bondedAt @17 :T.Timestamp;
    # When this device was last seen in a scan.
    lastSeenAt @18 :T.Timestamp;
    # Printable form of the address (a MAC string where one exists).
    # Display only: nothing accepts it, and a backend that cannot
    # determine a printable form leaves it empty rather than inventing
    # one.
    addressText @19 :Text;
}

enum BleTransport {
    auto @0;
    le @1;
    bredr @2;
    dual @3;
    custom @4;
}

struct BleConnectionParams {
    connIntervalMin @0 :UInt16;
    connIntervalMax @1 :UInt16;
    slaveLatency @2 :UInt16;
    supervisionTimeout @3 :UInt16;
    # Current connection interval in use (1.25ms units).
    currentInterval @4 :UInt16;
    # Current slave latency.
    currentLatency @5 :UInt16;
}

# ── Advertisement ───────────────────────────────────────────────────────

struct AdvertisementRecord {
    # Advertisement type.
    type @0 :AdvType;
    # Service UUIDs advertised.
    serviceUuids @1 :List(Text);
    # Manufacturer-specific data.
    manufacturerData @2 :List(ManufacturerData);
    # Service data entries.
    serviceData @3 :List(ServiceDataEntry);
    # TX power level advertised (dBm).
    txPowerLevel @4 :Int32;
    # Device name in scan response.
    deviceName @5 :Text;
    # Solicited service UUIDs.
    solicitServiceUuids @6 :List(Text);
    # Whether this is a connectable advertisement.
    connectable @7 :Bool;
    # Whether this is a scannable advertisement.
    scannable @8 :Bool;
}

enum AdvType {
    advInd @0;
    advDirectInd @1;
    advScanInd @2;
    advNonConnInd @3;
    scanResponse @4;
    custom @5;
}

struct ManufacturerData {
    companyId @0 :UInt16;
    payload @1 :Data;
}

struct ServiceDataEntry {
    # Service UUID (typed for consistency with GATT UUIDs).
    uuid @0 :BluetoothUuid;
    data @1 :Data;
}

# ── GATT Properties ────────────────────────────────────────────────────

struct GattProperties {
    read @0 :Bool;
    write @1 :Bool;
    writeWithoutResponse @2 :Bool;
    notify @3 :Bool;
    indicate @4 :Bool;
    authenticatedSignedWrites @5 :Bool;
    extendedProperties @6 :Bool;
}

# ── Profiles ────────────────────────────────────────────────────────────

enum BluetoothProfile {
    a2dp @0;
    hfp @1;
    hid @2;
    opp @3;
    pbap @4;
    map @5;
    sap @6;
    pan @7;
    spp @8;
    avrcp @9;
    mapClient @10;
    hidd @11;
    # Device ID Profile.
    did @12;
    # LE Audio (LC3, Auracast).
    leAudio @13;
    # HFP Audio Gateway.
    hfpAg @14;
    # HFP Hands-Free.
    hfpHf @15;
    # Battery Service.
    bas @16;
    # Device Information Service.
    dis @17;
    # User Data Service.
    uds @18;
    # Wideband Speech.
    wbs @19;
    # Media Control Profile.
    mcp @20;
    # Volume Control Profile.
    vcp @21;
    # Coordinated Set Identification Service.
    csis @22;
    # Telephone Bearer Service.
    tbs @23;
    # Media Broadcast Service.
    mbs @24;
    custom @25;
}

struct ProfileState {
    profile @0 :BluetoothProfile;
    connected @1 :Bool;
}

# ── LE Audio Configuration ─────────────────────────────────────────────

struct LeAudioConfig {
    # LE Audio group identifier.
    groupId @0 :UInt16;
    # Rank within the group (1 = primary, 2+ = secondary).
    rank @1 :UInt16;
    # Audio location (bitmask: front-left, front-right, etc.).
    location @2 :UInt32;
    # Available audio contexts (bitmask).
    availableContexts @3 :UInt32;
    # Supported audio contexts (bitmask).
    supportedContexts @4 :UInt32;
    # Volume level (0-255).
    volume @5 :UInt8;
    # Whether microphone is muted.
    microphoneMute @6 :Bool;
}

# ── Classic Audio Codec (A2DP) ──────────────────────────────────────────────

struct ClassicAudioCodec {
    # Codec name (SBC, AAC, aptX, LDAC, LC3).
    codecId @0 :AudioCodecId;
    # Supported sample rates.
    sampleRates @1 :List(UInt32);
    # Channel modes (mono, stereo, etc.).
    channelModes @2 :List(AudioChannelMode);
    # Bitpool range for SBC.
    bitpoolRange @3 :List(UInt8);
    # Whether VBR is supported.
    vbr @4 :Bool;
    # Maximum bitrate in bps.
    maxBitrate @5 :UInt32;
}

enum AudioCodecId {
    sbc @0;
    aac @1;
    aptx @2;
    aptxHd @3;
    ldac @4;
    lc3 @5;
    custom @6;
}

enum AudioChannelMode {
    mono @0;
    stereo @1;
    jointStereo @2;
    dualChannel @3;
    custom @4;
}

# ── Auracast LE Audio Broadcast ─────────────────────────────────────────────

interface AuracastService {
    # Start broadcasting audio (as a transmitter).
    startBroadcast @0 (config :BroadcastConfig) -> (broadcastId :Data);

    # Stop broadcasting.
    stopBroadcast @1 (broadcastId :Data) -> T.VoidResult;

    # Scan for Auracast broadcasts.
    scanBroadcasts @2 (pagination :T.Pagination) -> (broadcasts :List(AuracastBroadcast), total :UInt32);

    # Join an existing broadcast as a listener.
    joinBroadcast @3 (broadcastId :Data) -> (session :AuracastSession);

    # Leave a broadcast session.
    leaveBroadcast @4 (session :AuracastSession) -> T.VoidResult;

    # Get broadcast quality metrics.
    getBroadcastQuality @5 (broadcastId :Data) -> (quality :BroadcastQuality);
}

struct BroadcastConfig {
    # Broadcast name (for discovery).
    name @0 :Text;
    # Audio codec to use.
    codec @1 :ClassicAudioCodec;
    # Audio location bitmask.
    audioLocation @2 :UInt32;
    # Supported contexts bitmask.
    supportedContexts @3 :UInt32;
    # Whether to use encrypted broadcast.
    encrypted @4 :Bool;
}

struct AuracastBroadcast {
    # Broadcast identifier.
    broadcastId @0 :Data;
    # Broadcast name.
    name @1 :Text;
    # Broadcasting device address.
    deviceAddress @2 :T.DeviceAddress;
    # Received signal strength.
    rssi @3 :Int32;
    # Audio codec advertised.
    codec @4 :AudioCodecId;
    # Audio location available.
    audioLocation @5 :UInt32;
    # Number of current listeners.
    listenerCount @6 :UInt16;
}

struct AuracastSession {
    sessionId @0 :Data;
    broadcastId @1 :Data;
    # Whether actively receiving audio.
    active @2 :Bool;
    # Sync handle for isochronous streaming.
    syncHandle @3 :UInt16;
}

struct BroadcastQuality {
    # Packet loss percentage (0.0-100.0).
    packetLossPercent @0 :Float32;
    # Audio latency in milliseconds.
    latencyMs @1 :UInt16;
    # Current bitrate in bps.
    bitrate @2 :UInt32;
}

# ── Bluetooth Mesh Node ─────────────────────────────────────────────────────

struct BluetoothMeshNode {
    # Node address.
    address @0 :Text;
    # Node UUID.
    uuid @1 :Data;
    # Element count.
    elementCount @2 :UInt8;
    # Whether this node is a relay.
    isRelay @3 :Bool;
    # Whether this node is a proxy.
    isProxy @4 :Bool;
    # Whether this node is a friend node.
    isFriend @5 :Bool;
    # Low power node capability.
    isLpn @6 :Bool;
    # Network key identifiers.
    networkKeyIds @7 :List(Text);
    # Device key identifier.
    deviceKeyId @8 :Text;
}

# ── GATT Service Filter ────────────────────────────────────────────────

struct GattServiceFilter {
    # Filter by specific service UUIDs.
    uuids @0 :List(BluetoothUuid);
    # Only return primary services.
    primaryOnly @1 :Bool;
    # Include characteristics inline.
    includeCharacteristics @2 :Bool;
    # Include descriptors inline.
    includeDescriptors @3 :Bool;
}

# ── Scan Result ─────────────────────────────────────────────────────────

struct ScanResult {
    device @0 :BluetoothDevice;
    timestamp @1 :T.Timestamp;
    advertisement @2 :AdvertisementRecord;
}

# ── Bonding ─────────────────────────────────────────────────────────────

enum BondState {
    none @0;
    bonding @1;
    bonded @2;
    failed @3;
    custom @4;
}

struct PairingConfig {
    # Type of pairing to attempt.
    type @0 :PairingType;
    # For passkey entry: the passkey displayed/entered.
    passkey @1 :UInt32;
    # For numeric comparison: accept.
    accept @2 :Bool;
}

enum PairingType {
    displayOnly @0;
    displayYesNo @1;
    keyboardOnly @2;
    noInputNoOutput @3;
    passkeyEntry @4;
    numericComparison @5;
    custom @6;
}

struct PairingEvent {
    address @0 :T.DeviceAddress;
    type @1 :PairingType;
    # Display value (for displayOnly/displayYesNo/passkeyEntry).
    passkey @2 :UInt32;
    # Device name for confirmation.
    deviceName @3 :Text;
}

# ── GATT ─────────────────────────────────────────────────────────────────

struct GattService {
    # GATT handle (16-bit).
    handle @0 :UInt16;
    # UUID of this service (typed for standard 16-bit and custom 128-bit).
    uuid @1 :BluetoothUuid;
    # Whether this is a primary service (vs included).
    isPrimary @2 :Bool;
    # GATT type: service, included-service, characteristic, descriptor.
    kind @3 :GattKind;
    # Included service (when kind=included).
    includedService @4 :UInt16;
    # The characteristic handle (when kind=characteristic).
    characteristicHandle @5 :UInt16;
}

enum GattKind {
    service @0;
    includedService @1;
    characteristic @2;
    descriptor @3;
    custom @4;
}

struct GattCharacteristic {
    # 16-bit handle.
    handle @0 :UInt16;
    # UUID (typed for standard 16-bit and custom 128-bit).
    uuid @1 :BluetoothUuid;
    # Typed properties (replaces raw UInt8 bitfield).
    properties @2 :GattProperties;
    # Current value.
    value @3 :Data;
    # Attribute permissions, as an open token list rather than a raw
    # bitmask: the previous `permissions :UInt8` documented two of its
    # bits ("READ=1, WRITE=2") and left the rest undefined, so no two
    # backends agreed on what the field meant — and it read as an
    # authority declaration when it is an ATT-layer hardware fact.
    # Documented vocabulary: "read", "write", "notify", "indicate",
    # "encryptRead", "encryptWrite", "authRead", "authWrite".
    permissions @4 :List(Text);
    # Service this characteristic belongs to.
    serviceHandle @5 :UInt16;
    # Maximum value length.
    maxLength @6 :UInt32;
}

struct GattDescriptor {
    handle @0 :UInt16;
    uuid @1 :BluetoothUuid;
    value @2 :Data;
    # Same open token vocabulary as GattCharacteristic.permissions.
    permissions @3 :List(Text);
}

struct GattWriteRequest {
    deviceAddress @0 :T.DeviceAddress;
    serviceHandle @1 :UInt16;
    characteristicHandle @2 :UInt16;
    value @3 :Data;
    # write vs write-without-response.
    writeType @4 :GattWriteType;
}

enum GattWriteType {
    write @0;
    writeWithoutResponse @1;
    signedWrite @2;
    custom @3;
}

struct GattNotifyRequest {
    deviceAddress @0 :T.DeviceAddress;
    serviceHandle @1 :UInt16;
    characteristicHandle @2 :UInt16;
    enabled @3 :Bool;
}

# ── Service ───────────────────────────────────────────────────────────────

interface BluetoothService {
    # ── General ──
    getState @0 () -> (state :BluetoothState);
    enable @1 () -> T.VoidResult;
    disable @2 () -> T.VoidResult;
    setName @3 (name :Text) -> T.VoidResult;
    getName @4 () -> (name :Text);

    # ── Scan (LE + classic) ──
    startScan @5 (filter :ScanFilter) -> (subscription :ScanSubscription);
    stopScan @6 () -> T.VoidResult;

    # ── Device queries ──
    getDevice @7 (address :T.DeviceAddress) -> (device :BluetoothDevice);
    getPairedDevices @8 (pagination :T.Pagination)
                     -> (devices :List(BluetoothDevice), totalCount :UInt32);
    getConnectedDevices @9 (pagination :T.Pagination)
                        -> (devices :List(BluetoothDevice), totalCount :UInt32);

    # ── Device subscriptions ──
    subscribeDevice @10 (address :T.DeviceAddress) -> (subscription :BluetoothDeviceSubscription);
    subscribeConnection @11 (address :T.DeviceAddress) -> (subscription :BluetoothConnectionSubscription);

    # ── Pairing ──
    pair @12 (address :T.DeviceAddress, config :PairingConfig) -> (subscription :BondSubscription);
    cancelPair @13 (address :T.DeviceAddress) -> T.VoidResult;
    unpair @14 (address :T.DeviceAddress) -> T.VoidResult;
    respondToPairing @15 (address :T.DeviceAddress, config :PairingConfig) -> T.VoidResult;

    # ── Profile connections ──
    connectProfile @16 (address :T.DeviceAddress, profile :BluetoothProfile) -> T.VoidResult;
    disconnectProfile @17 (address :T.DeviceAddress, profile :BluetoothProfile) -> T.VoidResult;
    getProfileState @18 (address :T.DeviceAddress, pagination :T.Pagination)
                    -> (states :List(ProfileState), totalCount :UInt32);

    # ── GATT (LE) ──
    discoverServices @19 (address :T.DeviceAddress, pagination :T.Pagination)
                     -> (services :List(GattService), totalCount :UInt32);
    getService @20 (address :T.DeviceAddress, serviceHandle :UInt16) -> (service :GattService);
    getCharacteristics @21 (address :T.DeviceAddress, serviceHandle :UInt16, pagination :T.Pagination)
                       -> (chars :List(GattCharacteristic), totalCount :UInt32);
    getDescriptors @22 (address :T.DeviceAddress, serviceHandle :UInt16, charHandle :UInt16, pagination :T.Pagination)
                       -> (descs :List(GattDescriptor), totalCount :UInt32);
    readCharacteristic @23 (address :T.DeviceAddress, serviceHandle :UInt16, charHandle :UInt16)
                           -> (value :Data);
    writeCharacteristic @24 (request :GattWriteRequest) -> T.VoidResult;
    readDescriptor @25 (address :T.DeviceAddress, serviceHandle :UInt16, descHandle :UInt16)
                       -> (value :Data);
    writeDescriptor @26 (request :GattWriteRequest) -> T.VoidResult;
    setNotify @27 (request :GattNotifyRequest) -> T.VoidResult;
    subscribeGatt @28 (address :T.DeviceAddress) -> (subscription :GattSubscription);

    # ── File transfer (OPP) ──
    sendFile @29 (address :T.DeviceAddress, fileHandle :T.FileId) -> T.VoidResult;

    # ── State subscription ──
    subscribeState @30 () -> (subscription :BluetoothStateSubscription);

    # ── Cancel all subscriptions ──
    cancelScan @31 (subscription :ScanSubscription) -> T.VoidResult;
    cancelDevice @32 (subscription :BluetoothDeviceSubscription) -> T.VoidResult;
    cancelConnection @33 (subscription :BluetoothConnectionSubscription) -> T.VoidResult;
    cancelBond @34 (subscription :BondSubscription) -> T.VoidResult;
    cancelGatt @35 (subscription :GattSubscription) -> T.VoidResult;
    cancelState @36 (subscription :BluetoothStateSubscription) -> T.VoidResult;

    discoverServicesFiltered @37 (address :T.DeviceAddress, filter :GattServiceFilter, pagination :T.Pagination)
                             -> (services :List(GattService), totalCount :UInt32);

    # ── Classic Audio Codec (A2DP) ──
    negotiateAudioCodec @38 (address :T.DeviceAddress, codecs :List(ClassicAudioCodec))
        -> (selectedCodec :ClassicAudioCodec);

    # ── Auracast LE Audio Broadcast ──
    getAuracastService @39 () -> (service :AuracastService);

    # ── Bluetooth Mesh ──
    provisionMeshNode @40 (deviceAddress :T.DeviceAddress, provisionData :Data)
        -> (node :BluetoothMeshNode);
    # T.DeviceAddress, not Text. A mesh node is a device like any other,
    # so it is addressed like every other device — the previous Text
    # address here was a second, incompatible addressing scheme beside
    # the typed one used by provisionMeshNode.
    getMeshNode @41 (address :T.DeviceAddress) -> (node :BluetoothMeshNode);
    sendMeshMessage @42 (destination :T.DeviceAddress, data :Data, appKeyId :Text) -> T.VoidResult;
}

struct ServiceUuidRssiFilter {
    # Service UUID to filter by.
    serviceUuid @0 :BluetoothUuid;
    # Minimum RSSI for this specific service UUID.
    minRssi @1 :Int32;
    # Maximum RSSI for this specific service UUID.
    maxRssi @2 :Int32;
}

struct ScanFilter {
    # Filter by service UUIDs.
    serviceUuids @0 :List(Text);
    # Filter by device name (substring match).
    nameContains @1 :Text;
    # Filter by RSSI minimum.
    minRssi @2 :Int32;
    # Filter by transport.
    transport @3 :BleTransport;
    # Filter by whether device is connectable.
    connectable @4 :T.BoolFilter;
    # Maximum age of scan results (staleness filter).
    maxAge @5 :T.Duration;
    # Filter by address type (public, random, identity, resolving).
    addressTypes @6 :List(AddressType);
    # Filter by RSSI maximum.
    maxRssi @7 :Int32;
    # Per-service UUID RSSI thresholds.
    serviceUuidRssiFilters @8 :List(ServiceUuidRssiFilter);
}

enum AddressType {
    public @0;
    random @1;
    identity @2;
    resolving @3;
    custom @4;
}

# ── Subscriptions ──────────────────────────────────────────────────────

interface ScanSubscription {
    pull @0 () -> (results :List(ScanResult));
    cancel @1 () -> T.VoidResult;
}

interface BondSubscription {
    pull @0 () -> (state :BondState);
    cancel @1 () -> T.VoidResult;
}

interface BluetoothStateSubscription {
    pull @0 () -> (state :BluetoothState);
    cancel @1 () -> T.VoidResult;
}

interface BluetoothDeviceSubscription {
    pull @0 () -> (device :BluetoothDevice);
    cancel @1 () -> T.VoidResult;
}

interface BluetoothConnectionSubscription {
    pull @0 () -> (event :BluetoothConnectionEvent);
    cancel @1 () -> T.VoidResult;
}

interface GattSubscription {
    pull @0 () -> (events :List(GattEvent));
    cancel @1 () -> T.VoidResult;
}

# ── Events ──────────────────────────────────────────────────────────────

struct BluetoothConnectionEvent {
    address @0 :T.DeviceAddress;
    connected @1 :Bool;
    profile @2 :BluetoothProfile;
    timestamp @3 :T.Timestamp;
    # Whether a profile was just connected (for multi-profile tracking).
    profileConnected @4 :Bool;
    # Whether a profile was just disconnected.
    profileDisconnected @5 :Bool;
    # Whether bonding just occurred.
    bonded @6 :Bool;
    # Whether unbonding just occurred.
    unbonded @7 :Bool;
}

struct GattEvent {
    address @0 :T.DeviceAddress;
    serviceHandle @1 :UInt16;
    characteristicHandle @2 :UInt16;
    value @3 :Data;
    timestamp @4 :T.Timestamp;
    kind @5 :GattEventKind;
}

enum GattEventKind {
    valueChanged @0;
    writeCompleted @1;
    notification @2;
    indication @3;
    connectionStateChanged @4;
    # A new service was added (dynamic GATT database).
    added @5;
    # A service was removed (dynamic GATT database).
    removed @6;
    custom @7;
}

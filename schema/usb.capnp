@0xa1b2c3d4e5f60027;

# ═══════════════════════════════════════════════════════════════════════
# USB — Universal Serial Bus device enumeration, control, and events.
#
# USB is hardware-specific but the Smart Protocol never assumes a
# particular host controller backend (xHCI on Linux/FreeBSD, WASM device
# proxy, virtual hub on headless servers). All identifiers are opaque
# backend-assigned values; the schema describes capability, not transport.
#
# Improvements beyond the original:
#   - Device addresses use a typed UsbDeviceAddress (UInt64-backed).
#   - descriptors is a T.DataHandle (raw bytes when large).
#   - subscribeEvents + pullEvents -> EventSubscription with pull + cancel.
#   - All errors on mutations go through T.VoidResult.
#   - All enums have a custom variant.
#   - MountOptions.fsType uses a typed FilesystemType union
#     (imported from filesystem.capnp) instead of bare Text.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using Fs = import "filesystem.capnp";

interface UsbService {
    listDevices @0 (pagination :T.Pagination)
                  -> (devices :List(UsbDevice), total :UInt64);

    getDevice @1 (deviceAddress :UsbDeviceAddress)
                -> (device :UsbDevice);

    mountDevice   @2 (deviceAddress :UsbDeviceAddress,
                      options :Fs.MountOptions) -> T.VoidResult;
    unmountDevice @3 (deviceAddress :UsbDeviceAddress) -> T.VoidResult;
    ejectDevice   @4 (deviceAddress :UsbDeviceAddress) -> T.VoidResult;

    getDeviceInfo @5 (deviceAddress :UsbDeviceAddress)
                    -> (info :UsbDeviceInfo);

    authorizeDevice   @6 (deviceAddress :UsbDeviceAddress) -> T.VoidResult;
    unauthorizeDevice @7 (deviceAddress :UsbDeviceAddress) -> T.VoidResult;

    subscribeEvents @8 () -> (subscription :EventSubscription);

    # USB Power Delivery: query PD state for a device.
    getPowerDelivery @9 (deviceAddress :UsbDeviceAddress)
        -> (pd :UsbPowerDelivery);

    # USB-C Alt Modes: list active alt modes for a device.
    getAltModes @10 (deviceAddress :UsbDeviceAddress)
        -> (modes :List(UsbAltMode));

    # USB-C cable information: query cable e-marker and capabilities.
    getCableInfo @11 (deviceAddress :UsbDeviceAddress)
        -> (cable :UsbCableInfo);

    # USB power budget: query power distribution for a hub/port.
    getPowerBudget @12 (deviceAddress :UsbDeviceAddress)
        -> (budget :UsbPowerBudget);

    # USB4/Thunderbolt: query router topology.
    getTopology @13 () -> (topology :UsbTopology);

    # Device quirks: get workaround flags for a device.
    getDeviceQuirks @14 (deviceAddress :UsbDeviceAddress)
        -> (quirks :UsbDeviceQuirks);

    # Device quirks: set workaround flags for a device.
    setDeviceQuirks @15 (quirks :UsbDeviceQuirks) -> T.VoidResult;

    # ── UsbAuthentication integration (audit-9 What's Still Missing) ──
    getAuthentication @16 () -> (auth :UsbAuthentication);

    # ── USB PD negotiation initiation (audit-9 What's Still Missing) ──
    initiatePdNegotiation @17 (request :UsbPdoRequest) -> T.VoidResult;

    # ── USB4 tunnel management (audit-9 What's Still Missing) ──
    createTunnel @18 (deviceAddress :UsbDeviceAddress, protocol :UsbAltModeProtocol, bandwidthBps :UInt64) -> (tunnelId :UInt32);
    destroyTunnel @19 (tunnelId :UInt32) -> T.VoidResult;

    # ── USB device firmware update (audit-9 What's Still Missing) ──
    queryFirmwareVersion @20 (deviceAddress :UsbDeviceAddress) -> (version :Text);
    updateFirmware @21 (deviceAddress :UsbDeviceAddress, firmwareData :T.DataHandle) -> T.VoidResult;

    # ── USB error recovery (audit-9 What's Still Missing) ──
    recoverDevice @22 (recovery :UsbErrorRecovery) -> T.VoidResult;
}

# ── Identifiers ───────────────────────────────────────────────────────

struct UsbDeviceAddress {
    # Opaque backend-assigned address. On Linux xHCI these encode bus+device
    # but the protocol does not assume that.
    value @0 :UInt64;
}

# ── Device / Interface / Endpoint ─────────────────────────────────────

# NOTE: UsbSpeed ordinals start at @1 (ordinal @0 is intentionally
# unused). This is valid Cap'n Proto and preserves backward compatibility
# with schemas that referenced the original speed values.

struct UsbDevice {
    address       @0  :UsbDeviceAddress;
    busNumber     @1  :UInt8;
    deviceNumber  @2  :UInt8;
    vendorId      @3  :UInt16;
    productId     @4  :UInt16;
    speed         @5  :UsbSpeed;
    manufacturer  @6  :Text;
    product       @7  :Text;
    serial        @8  :Text;
    interfaceCount @9 :UInt8;
    mounted       @10 :Bool;
    authorized    @11 :Bool;
    # When the device became attached.
    attachedAt    @12 :T.Timestamp;
}

enum UsbSpeed {
    low       @0;
    full      @1;
    high      @2;
    super     @3;
    superPlus @4;
    # Backend does not know; treat unknown as lowest common denominator.
    unknown   @5;
    custom    @6;
}

# Extended speeds for USB4 and Thunderbolt.
enum UsbSpeedExtended {
    usb420G         @0;   # USB4 Gen 2x1 (20 Gbps)
    usb440G         @1;   # USB4 Gen 3x2 (40 Gbps)
    usb480G         @2;   # USB4 Gen 4 (80 Gbps)
    thunderbolt340G @3;  # Thunderbolt 3 (40 Gbps)
    thunderbolt440G @4;  # Thunderbolt 4 (40 Gbps)
    thunderbolt580G @5;  # Thunderbolt 5 (80 Gbps)
    custom           @6;
}

# USB endpoint transfer type (bmAttributes bits 0-1).
enum UsbTransferType {
    control     @0;   # Control transfers (setup, status)
    isochronous @1;   # Isochronous transfers (real-time data)
    bulk        @2;   # Bulk transfers (large data, no timing guarantee)
    interrupt   @3;   # Interrupt transfers (periodic, low-latency)
    custom      @4;   # Backend-specific transfer type
}

# USB-C power role negotiation.
enum UsbPowerRole {
    source   @0;   # Provides VBUS power
    sink     @1;   # Consumes VBUS power
    dualRole @2;   # Can be either source or sink
    custom   @3;   # Backend-specific power role
}

# USB-C data role negotiation.
enum UsbDataRole {
    host     @0;   # USB host (downstream)
    device   @1;   # USB device (upstream)
    dualRole @2;   # Can be either host or device
    custom   @3;   # Backend-specific data role
}

struct UsbDeviceInfo {
    device      @0 :UsbDevice;
    interfaces  @1 :List(UsbInterface);
    # Raw descriptor bytes (may be large). Inline when small, buffer-handle
    # when the descriptor tree exceeds 1KB.
    descriptors @2 :T.DataHandle;
}

struct UsbInterface {
    interfaceNumber   @0 :UInt8;
    alternateSetting  @1 :UInt8;
    # USB-IF standard class codes (e.g., 0x03=HID, 0x08=Mass Storage).
    # Raw UInt8 is appropriate for hardware-defined constants; no typed
    # UsbClass enum needed for a timeless protocol.
    interfaceClass    @2 :UInt8;
    interfaceSubClass @3 :UInt8;
    interfaceProtocol @4 :UInt8;
    endpoints         @5 :List(UsbEndpoint);
    # Driver string the backend has bound to this interface (if any).
    driver            @6 :Text;
}

struct UsbEndpoint {
    address      @0 :UInt8;
    direction    @1 :EndpointDirection;
    # bmAttributes; bit layout left to backend interpretation by direction.
    attributes   @2 :UInt8;
    maxPacketSize @3 :UInt16;
    # Polling interval; backend-given unit (frames for full/high,
    # microframes for super). Documented here, not assumed by the schema.
    interval     @4 :UInt8;
    # Transfer type for this endpoint (control, isochronous, bulk, interrupt).
    transferType @5 :UsbTransferType;
}

enum EndpointDirection {
    in     @0;
    out    @1;
    custom @2;
}

# ── USB Power Delivery ────────────────────────────────────────────────

struct UsbPowerDelivery {
    # Voltage contract in volts (e.g., 5.0, 9.0, 15.0, 20.0).
    voltageContract @0 :Float32;
    # Current contract in amperes (e.g., 1.5, 3.0).
    currentContract @1 :Float32;
    # Maximum voltage the device supports (volts).
    maxVoltage @2 :Float32;
    # Maximum current the device supports (amperes).
    maxCurrent @3 :Float32;
    # Current battery level (0-100 percent). 0 = not reporting.
    batteryLevel @4 :UInt8;
    # Current charging state.
    chargingState @5 :UsbChargingState;
    # USB-C power role (source, sink, dual-role).
    powerRole @6 :UsbPowerRole;
    # USB-C data role (host, device, dual-role).
    dataRole @7 :UsbDataRole;
    # PDO (Power Data Object) index currently selected.
    activePdoIndex @8 :UInt32;
    # Available PDOs from the power source.
    availablePdos @9 :List(UsbPdo);
}

enum UsbChargingState {
    idle       @0;   # Not charging
    charging   @1;   # Actively charging
    discharging @2;  # Providing power (battery-powered)
    full       @3;   # Battery full
    error      @4;   # Charging error
    custom     @5;   # Backend-specific charging state
}

struct UsbPdo {
    # PDO type (fixed, variable, battery, AVS, PPS, EPR).
    pdoType @0 :Text;
    # Voltage in volts (0 for non-voltage PDOs).
    voltage @1 :Float32;
    # Current in amperes (0 for non-current PDOs).
    current @2 :Float32;
    # Maximum current in amperes.
    maxCurrent @3 :Float32;
}

# ── USB-C Alt Mode ────────────────────────────────────────────────────

struct UsbAltMode {
    # Alt mode identifier (assigned by USB-IF or vendor).
    modeId @0 :UInt32;
    # Protocol carried by this alt mode.
    protocol @1 :UsbAltModeProtocol;
    # Whether this alt mode is currently active.
    active @2 :Bool;
    # Bandwidth allocated to this alt mode (bits per second).
    bandwidthBps @3 :UInt64;
}

enum UsbAltModeProtocol {
    displayPort @0;   # DisplayPort Alt Mode
    hdmi        @1;   # HDMI Alt Mode
    pcie        @2;   # PCIe Alt Mode (Thunderbolt)
    usb3        @3;   # USB 3.x Alt Mode
    mhl         @4;   # MHL (Mobile High-Definition Link)
    custom      @5;   # Vendor-specific alt mode
}

# ── USB-C Cable Information ───────────────────────────────────────────

struct UsbCableInfo {
    # Whether the cable has an e-marker chip.
    eMarkerPresent @0 :Bool;
    # Cable orientation (flip detection).
    orientation @1 :UsbCableOrientation;
    # Whether the cable supports USB4.
    supportsUsb4 @2 :Bool;
    # Maximum data rate the cable supports.
    maxDataRate @3 :UsbSpeed;
    # Whether the cable supports USB Power Delivery.
    supportsPd @4 :Bool;
    # Cable length in meters (0 = unknown).
    cableLength @5 :Float32;
    # Cable vendor name (empty = unknown).
    vendorName @6 :Text;
    # Cable product name (empty = unknown).
    productName @7 :Text;
}

enum UsbCableOrientation {
    normal   @0;   # Normal orientation
    flipped  @1;   # Flipped orientation
    unknown  @2;   # Orientation unknown
    custom   @3;   # Backend-specific orientation state
}

# ── USB Authentication ────────────────────────────────────────────────

interface UsbAuthentication {
    # Authenticate a USB device or cable.
    authenticateDevice @0 (deviceAddress :UsbDeviceAddress)
        -> (result :UsbAuthResult);

    # Get the current authentication state for a device.
    getAuthState @1 (deviceAddress :UsbDeviceAddress)
        -> (state :UsbAuthState);

    # Block a device from being used (unauthorized).
    blockDevice @2 (deviceAddress :UsbDeviceAddress) -> T.VoidResult;

    # Unblock a previously blocked device.
    unblockDevice @3 (deviceAddress :UsbDeviceAddress) -> T.VoidResult;

    # List all blocked devices.
    listBlockedDevices @4 (pagination :T.Pagination)
        -> (devices :List(UsbDeviceAddress), total :UInt64);
}

struct UsbAuthState {
    # Whether the device is currently authenticated.
    authenticated @0 :Bool;
    # Certificate chain for device authentication (if available).
    certificateChain @1 :T.DataHandle;
    # Device identity (manufacturer, product, serial).
    deviceIdentity @2 :Text;
    # Authentication method used (e.g., "usb-auth-2.0", "custom").
    authMethod @3 :Text;
}

struct UsbAuthResult {
    union {
        success @0 :UsbAuthState;
        error   @1 :T.Error;
    }
}

# ── USB Power Budget ──────────────────────────────────────────────────

struct UsbPowerBudget {
    # Total power budget for the USB port/hub (watts).
    totalPowerWatts @0 :Float32;
    # Power currently allocated to devices (watts).
    allocatedWatts @1 :Float32;
    # Power available for new devices (watts).
    availableWatts @2 :Float32;
    # Thermal limit — maximum power before thermal throttling (watts).
    thermalLimit @3 :Float32;
    # Whether power budgeting is active.
    active @4 :Bool;
}

# ── Thunderbolt Tunnel ────────────────────────────────────────────────

struct ThunderboltTunnel {
    # Unique tunnel identifier.
    tunnelId @0 :UInt32;
    # Protocol carried by this tunnel.
    protocol @1 :UsbAltModeProtocol;
    # Bandwidth allocated to this tunnel (bits per second).
    bandwidthBps @2 :UInt64;
    # Whether this tunnel is currently active.
    active @3 :Bool;
    # Devices connected through this tunnel.
    connectedDevices @4 :List(UsbDeviceAddress);
}

# ── USB4 Router ───────────────────────────────────────────────────────

struct Usb4Router {
    # Unique router identifier.
    routerId @0 :UInt32;
    # Ports on this router.
    ports @1 :List(Usb4Port);
    # Active tunnels through this router.
    tunnels @2 :List(ThunderboltTunnel);
    # Topology version (incremented on topology changes).
    topologyVersion @3 :UInt32;
}

struct Usb4Port {
    # Port number on the router.
    portNumber @0 :UInt8;
    # Maximum speed supported by this port.
    maxSpeed @1 :UsbSpeed;
    # Whether a device is connected to this port.
    connected @2 :Bool;
    # Device address if connected (0 = no device).
    deviceAddress @3 :UsbDeviceAddress;
}

# ── USB Device Quirks ─────────────────────────────────────────────────

struct UsbDeviceQuirks {
    # Device that needs quirks.
    deviceAddress @0 :UsbDeviceAddress;
    # List of quirk identifiers (backend-defined).
    quirks @1 :List(Text);
    # Bitmask of workaround flags (backend-defined).
    workaroundFlags @2 :UInt32;
}

# ── USB Topology ──────────────────────────────────────────────────────

struct UsbTopology {
    # Root hub of the USB bus tree.
    rootHub @0 :UsbHub;
    # Total number of ports in the topology.
    totalPorts @1 :UInt32;
    # Maximum depth of the hub tree.
    maxDepth @2 :UInt8;
}

struct UsbHub {
    # Hub identifier.
    hubId @0 :UInt32;
    # Ports on this hub.
    ports @1 :List(UsbPort);
    # Hub depth in the tree (0 = root hub).
    depth @2 :UInt8;
}

struct UsbPort {
    # Port number on the hub.
    portNumber @0 :UInt8;
    # Device connected to this port (if any).
    device @1 :UsbDevice;
    # Child hub downstream of this port (if any).
    childHub @2 :UsbHub;
    # Whether this port is powered.
    powered @3 :Bool;
    # Whether this port supports USB4.
    supportsUsb4 @4 :Bool;
}

# ── Events ────────────────────────────────────────────────────────────

interface EventSubscription {
    pull   @0 () -> (events :List(UsbEvent));
    cancel @1 () -> T.VoidResult;

    # Paginated event retrieval. Returns at most `pagination.limit` events
    # starting at `pagination.offset`. Caller should repeat with increasing
    # offset until all events are consumed.
    pullPaged @2 (pagination :T.Pagination)
              -> (events :List(UsbEvent), total :UInt64);
}

struct UsbEvent {
    id        @0 :T.EventId;
    timestamp @1 :T.Timestamp;
    type      @2 :UsbEventType;
    device    @3 :UsbDevice;
}

enum UsbEventType {
    connect    @0;
    disconnect @1;
    mount      @2;
    unmount    @3;
    authorize  @4;
    unblock    @5;
    error      @6;
    custom     @7;
}

# ── USB PD Negotiation API (audit-8 What's Still Missing) ──
struct UsbPdoRequest {
    deviceAddress @0 :UsbDeviceAddress;
    pdoIndex @1 :UInt32;
    requestedVoltage @2 :Float32;
    requestedCurrent @3 :Float32;
}

# ── USB Error Recovery (audit-8 What's Still Missing) ──
struct UsbErrorRecovery {
    deviceAddress @0 :UsbDeviceAddress;
    portReset @1 :Bool;
    linkReset @2 :Bool;
    warmReset @3 :Bool;
}

# ═══════════════════════════════════════════════════════════════════════
# v0.0.2 additions — USB Host Provider
#
# A USB host controller driver (xHCI, EHCI, ...) is a capability.
# USB devices arrive/leave through it; the USB stack consumes
# device descriptors and submits transfers. Swap host controllers
# without recompiling upper USB layers.
# ═══════════════════════════════════════════════════════════════════════

interface UsbHostProvider {
    # Host controller capabilities.
    getCapabilities @0 () -> (caps :UsbHostCaps);
    # Enumerate attached devices. The driver decides polling cadence;
    # fresh snapshots appear via the subscription.
    enumerateDevices @1 () -> (devices :List(UsbTopoNode));
    # Subscribe to device arrival/removal.
    subscribeTopology @2 () -> (subscription :UsbTopologySubscription);
    # Submit a control transfer (always supported).
    controlTransfer @3 (device :UInt32, endpoint :UInt8, setup :Data, dataSlot :UInt32, dataLength :UInt32) -> (result :UInt32);
    # Submit a bulk transfer.
    bulkTransfer @4 (device :UInt32, endpoint :UInt8, direction :UsbTransferDirection, dataSlot :UInt32, length :UInt32, timeoutMs :UInt32) -> (transferId :UInt64);
    # Submit an interrupt transfer.
    interruptTransfer @5 (device :UInt32, endpoint :UInt8, direction :UsbTransferDirection, dataSlot :UInt32, length :UInt32, periodMs :UInt32) -> (transferId :UInt64);
    # Cancel an outstanding transfer.
    cancelTransfer @6 (transferId :UInt64) -> (result :VoidOpResult);
    # Pull transfer completions.
    pullCompletions @7 () -> (completions :List(UsbTransferCompletion));
    # Driver-defined health ping.
    ping @8 () -> (health :T.DriverHealth);
}

struct UsbHostCaps {
    # Maximum number of devices the controller can address.
    maxDevices @0 :UInt32;
    # USB speed grades supported (1.1 / 2.0 / 3.x / ...).
    supportedSpeeds @1 :List(Text);
    # Backend bus class (xHCI, EHCI companion, ...).
    hostClass @2 :Text;
    # Number of root hub ports.
    rootHubPorts @3 :UInt8;
}

struct UsbTopoNode {
    # USB address the host assigned.
    address @0 :UInt32;
    # High-speed hub chain depth.
    hubDepth @1 :UInt8;
    # Connection speed.
    speed @2 :Text;
    # Device descriptor (header-encoded).
    deviceDescriptor @3 :Data;
    # Configuration descriptors.
    configs @4 :List(Data);
    union {
        hub @5 :UsbHubInfo;
        composite @6 :List(UInt8);
        custom @7 :Void;
    }
}

struct UsbHubInfo {
    numPorts @0 :UInt8;
    # Per-port status (driver-defined length).
    portStatus @1 :List(UInt32);
}

enum UsbTransferDirection {
    out @0;
    in @1;
    setupOut @2;
    setupIn @3;
    custom @4;
}

struct UsbTransferCompletion {
    transferId @0 :UInt64;
    # Bytes actually transferred.
    bytesTransferred @1 :UInt32;
    # USB status code (driver-defined mapping).
    status @2 :UInt32;
    # Buffer slot the transfer used.
    dataSlot @3 :UInt32;
    struct UsbTransferCompletionResult {
        # Whether the status indicates success.
        success @0 :Bool;
        # Underlying error code if not success.
        errorCode @1 :UInt32;
    }
}

struct VoidOpResult {
    success @0 :Bool;
    code @1 :UInt32;
    message @2 :Text;
}

interface UsbTopologySubscription {
    pull @0 () -> (events :List(UsbTopologyEvent));
    cancel @1 () -> VoidOpResult;
}

struct UsbTopologyEvent {
    at @0 :UInt64;
    union {
        attached @1 :UsbTopoNode;
        detached @2 :UInt32;
        speedChanged @3 :UsbSpeedChange;
        custom @4 :Void;
    }
}

struct UsbSpeedChange {
    address @0 :UInt32;
    oldSpeed @1 :Text;
    newSpeed @2 :Text;
}

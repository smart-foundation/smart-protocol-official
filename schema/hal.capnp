@0xa1b2c3d4e5f6003c;

# ═══════════════════════════════════════════════════════════════════════
# HAL — hardware abstraction primitives for driver-apps.
#
# HAL describes what hardware-access a driver may ask for, NOT how those
# requests are implemented. Backends implement interrupts however they
# want (line, message, polled, msi); the protocol only commits to the
# affordances a driver gets:
#
#   - claiming authority over a device class
#   - mapping memory regions
#   - subscribing to interrupt lines and receiving FIRINGS
#   - DMA channels and shared buffers
#   - power control of devices
#   - discovering the bus topology and describing the hardware
#
# Each is backend-agnostic; a driver moves between architectures
# naturally.
#
# ── WHAT WAS DELETED, AND WHY ──────────────────────────────────────────
#
#   * The "Hardware Foundation" block: `allocPhysicalPage`,
#     `freePhysicalPage`, `createAddressSpace`, `destroyAddressSpace`,
#     `mapVirtual`, `unmapVirtual`, `switchAddressSpace`, `mapRawMmio`,
#     `registerIrq`, `enableIrq`/`disableIrq`, `allocMsi`/`allocMsix`/
#     `programMsi`, `registerWatchdog`, `getX86PortIo` + `interface
#     X86PortIo`. Page tables and interrupt dispatch are KEEPS OUT
#     (DESIGN_PRINCIPLES.md:65 and :68); a kernel without page tables —
#     single-address-space, capability-paged, CHERI-style — cannot
#     implement `mapVirtual` at all, and every non-x86 backend had to
#     stub six port-I/O methods that cannot exist. Raw MMIO and physical
#     pages are exposed as `T.MappedRegionId` handles instead: the driver
#     never sees an address it must not compute with.
#   * `parseAcpi` + `HardwareDescFormat { deviceTree, acpi, smbios,
#     devicetreeOverlay }` — firmware-table names in a required enum,
#     returning full ACPI tables inline. Replaced by `describeHardware`,
#     which returns an OPEN format token and the bytes as a T.DataHandle.
#   * The duplicate primitives: `MemFlag` (T.PageFlags), `IrqLevel`
#     (T.InterruptLevel), `HalCapability` (T.CapabilityType), `PowerState`
#     (T.PowerSleepState), `DeviceResource` (T.DeviceResource) — five
#     name/semantic collisions across the two most-imported files in the
#     tree.
#   * `PciDeviceInfo` + `enumeratePci` — a PCI enumeration struct. Bus
#     discovery is `describeBus`/`probe` over `BusTopology` and
#     `DeviceDescriptor`, which are transport-neutral; config-space
#     access is kept as a bounded window into a device the driver already
#     holds.
#   * `DmaBufInfo.fd :UInt32` — a POSIX file descriptor in a required
#     position. Replaced by a T.BufferId handle.
#   * `UserlandDriverInfo` + `UserlandCapability`, `CloudHalInfo` +
#     `CloudAuth`, `VirtualHalInfo`, `AiAcceleratorInfo` +
#     `AiAcceleratorType`/`AiPrecision`, `IommuInfo` + `IommuType`,
#     `SerialBusInfo` + `SerialBusType` — six unreachable type families
#     naming today's vendors, accelerators and IOMMU generations. HalDeviceInfo
#     (class/vendor/model/capabilities) and `describeHardware` cover the
#     general case; a 2046 accelerator needs no ordinal.
#   * `waitIrq` / `subscribeIrq` / `waitIrqHandle` / `unsubscribeIrq` /
#     `ackIrqHandle` — THREE interrupt paths, none of which delivered
#     events: every IRQ cost a blocking RPC or a poll. One mechanism
#     remains, and it delivers firings as a subscription.
#   * raw `UInt8`/`UInt64` codes and addresses: `respawnPolicy`,
#     `registerDevice(policy)`, `getRespawnContext(state)`, `mapMmio`,
#     `allocDmaBuf`, `IrqRequest.mode`, `DmaAddrRequest.direction`.
#
# Authority is the interface reference: `claim` returns evidence of what
# the driver may touch, and holding that reference (or the HalService
# reference for unclaimed affordances) is the authority. There is no
# per-method token (R3).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# What the driver asks to map. `base` is zero to let the backend choose.
struct MemoryAccess {
    # Physical or bus address (backend-decided; zero = backend picks).
    # On systems with an IOMMU this may be a DMA address rather than a
    # true physical address. The backend documents its interpretation.
    base @0 :UInt64;
    length @1 :UInt64;
    # Typed page attributes (canonical).
    flags @2 :T.PageFlags;
    # Backend may map this with cache disabled, write-through, etc.
    cacheMode @3 :MapCacheMode;
}

enum MapCacheMode {
    unknown @0;
    defaultCached @1;
    writeBack @2;
    writeThrough @3;
    uncacheable @4;
    custom @5;
}

# How a driver wants an interrupt line to behave. The trigger
# (`level`) is a physical property of the line and is typed
# (T.InterruptLevel); everything else is intent.
struct IrqRequest {
    vector @0 :UInt32;
    # Physical trigger: edge, level, or message-signalled. Closed by
    # hardware, not by fashion.
    level @1 :T.InterruptLevel;
    # Optional reference to the process:task that handles the firing.
    handler @2 :T.ProcessId;
    # If true, ack to the backend after the handler completes.
    needingAck @3 :Bool = true;
    # Open parameters the backend understands.
    parameters @4 :T.StringMap;
}

struct IrqTicket {
    vector @0 :UInt32;
    level @1 :T.InterruptLevel;
    # Time the interrupt was claimed.
    lastFiredAt @2 :T.Timestamp;
    # Total count of firings observed.
    count @3 :UInt64;
    # Open metadata.
}

# One delivery of an interrupt. The subscription yields these; a driver
# no longer blocks in a wait or polls a vector.
struct IrqFiring {
    vector @0 :UInt32;
    # Monotonic time of the firing, so ordering survives clock adjustment.
    at @1 :T.MonotonicTimestamp;
    # Running count of firings on this vector, for gap detection.
    count @2 :UInt64;
    # Whether the firing was acknowledged by the handler.
    acknowledged @3 :Bool;
}

struct DmaChannel {
    # Channel identifier (backend-assigned; not a global DMA engine).
    id @0 :T.DmaChannelId;
    direction @1 :DmaDirection;
    # Bus width in bits (8, 16, 32, 64).
    width @2 :UInt32;
    # Maximum burst size in bytes.
    maxBurst @3 :UInt32;
    # Whether this channel supports scatter-gather.
    scatterGather @4 :Bool;
}

enum DmaDirection {
    unknown @0;
    deviceToHost @1;
    hostToDevice @2;
    both @3;
    custom @4;
}

struct HalDevicePowerState {
    state @0 :T.PowerSleepState;
    # Power consumed in milliwatts (zero if unknown).
    milliwatts @1 :UInt32;
    # Time the device becomes ready from this state (backend-decided
    # unit; typically nanoseconds on hardware with known resume
    # latencies).
    resumeLatency @2 :T.Duration;
}

# What a driver was granted. Handles, not addresses.
struct HalAuthority {
    # Memory access the driver may claim.
    memory @0 :List(MemoryAccess);
    # Interrupts the driver may subscribe to.
    vectors @1 :List(IrqRequest);
    # DMA channels the driver may operate.
    channels @2 :List(DmaChannel);
    # Authority over power state transitions of which devices.
    powerTargets @3 :List(T.HalDeviceId);
    # Open metadata.
}

# ── Device and bus description ──────────────────────────────────────────

struct DeviceDescriptor {
    id @0 :T.HalDeviceId;
    name @1 :Text;
    # Open class token ("pci", "usb", "platform", "i2c", or a 2046 one).
    class @2 :Text;
    vendor @3 :Text;
    model @4 :Text;
    revision @5 :UInt8;
    # Open bus token, matching BusTopology's vocabulary.
    busType @6 :Text;
    # Typed resource list (canonical).
    resources @7 :List(T.DeviceResource);
    # Typed capability list (canonical).
    capabilities @8 :List(T.CapabilityType);
    # Interrupt levels this device can use, as typed values.
    interruptModes @9 :List(T.InterruptLevel);
    # Open metadata: anything else enumeration produced.
}

struct HalDeviceInfo {
    deviceId @0 :T.HalDeviceId;
    # Open class token.
    class @1 :Text;
    vendor @2 :Text;
    model @3 :Text;
    # Typed capability list (canonical).
    capabilities @4 :List(T.CapabilityType);
    # Maximum mapped regions.
    maxRegions @5 :UInt32;
    # Maximum DMA channels.
    maxDmaChannels @6 :UInt32;
}

# ── Hardware description ────────────────────────────────────────────────
# The firmware table / device tree, as an OPEN format token and a
# zero-copy handle. The pre-revamp enum named four table formats; a
# boot ROM with none of them had to answer with a lie.

struct HardwareDescription {
    # Open format token ("devicetree", "acpi", "smbios", or a 2046 one).
    format @0 :Text;
    # The table bytes, zero-copy.
    data @1 :T.DataHandle;
    # Overlay / runtime-modification data, if any.
    overlay @2 :T.DataHandle;
    # Signature identifying this specific description (OEM id, DT root
    # compatible string, …), open and backend-declared.
    signature @3 :Text;
}

# ── Bus topology ────────────────────────────────────────────────────────

struct BusTopology {
    # Identifier assigned by the kernel/HAL implementation.
    rootBus @0 :T.BusAddress;
    # Children discovered at probe time.
    children @1 :List(BusNode);
    # Topology walk depth.
    depth @2 :UInt16;
}

struct BusNode {
    address @0 :T.BusAddress;
    # Devices attached at this address (drivers manage the attach
    # lifecycle via device.capnp's DeviceService).
    attachedDevices @1 :List(T.HalDeviceId);
    parent @2 :T.BusAddress;
    # Open bus token for this node.
    busType @3 :Text;
}

interface BusDiscoveryService {
    # Probe the bus tree. Implementation decides how — walking a device
    # tree, PCIe enumeration, virtio config space, …
    probe @0 (bounds :BusProbeBounds) -> (topology :BusTopology);
    # Subscribe to topology changes (hotplug, device removal). Holding
    # the subscription IS the authority to pull.
    subscribeTopology @1 () -> (subscription :BusTopologySubscription);
    # Resolve a bus address to a device id (if attached).
    resolveAddress @2 (address :T.BusAddress) -> (device :T.HalDeviceId);
}

struct BusProbeBounds {
    # Maximum nodes to return (zero = backend default, itself bounded).
    maxNodes @0 :UInt32;
    # Maximum depth to walk.
    maxDepth @1 :UInt16;
    # True when the walk hit a bound, so a consumer knows the topology is
    # partial rather than complete.
    truncated @2 :Bool;
}

interface BusTopologySubscription {
    # Bounded pull.
    pull @0 (maxEvents :UInt32) -> (events :List(BusTopologyEvent));
    cancel @1 () -> T.VoidResult;
}

struct BusTopologyEvent {
    at @0 :T.MonotonicTimestamp;
    union {
        deviceAttached @1 :BusAttachEvent;
        deviceDetached @2 :T.BusAddress;
        busRescanned @3 :T.BusAddress;
        unknown @4 :T.UnknownEvent;
    }
}

struct BusAttachEvent {
    address @0 :T.BusAddress;
    device @1 :T.HalDeviceId;
    # Open hardware class token (network, display, storage, …).
    hardwareClass @2 :Text;
}

# ── Per-address DMA helpers ─────────────────────────────────────────────
# Some backends require DMA-address negotiation per bus address.

struct DmaAddrRequest {
    device @0 :T.HalDeviceId;
    bus @1 :T.BusAddress;
    lengthBytes @2 :UInt64;
    direction @3 :DmaDirection;
    # Driver may hint; backend overrides with physical it can map.
    preferredAddress @4 :UInt64;
}

interface DmaMapService {
    map @0 (request :DmaAddrRequest) -> (handle :T.DmaHandle);
    unmap @1 (handle :T.DmaHandle) -> (result :T.VoidResult);
    syncForDevice @2 (handle :T.DmaHandle) -> (result :T.VoidResult);
    syncForCpu @3 (handle :T.DmaHandle) -> (result :T.VoidResult);
}

# ── DMA-BUF sharing ─────────────────────────────────────────────────────

struct DmaBufInfo {
    # Buffer handle, NOT a POSIX file descriptor.
    bufferId @0 :T.BufferId;
    sizeBytes @1 :UInt64;
    format @2 :T.PixelFormat;
    width @3 :UInt32;
    height @4 :UInt32;
    # Buffer modifier (tiling, compression), backend-declared.
    modifier @5 :UInt64;
    # Sync file for implicit sync, zero-copy.
    syncFile @6 :T.DataHandle;
    # Processes that currently share this buffer.
    sharedWith @7 :List(T.ProcessId);
    metadata @8 :T.StringMap;
}

struct DmaBufShareRequest {
    sizeBytes @0 :UInt64;
    format @1 :T.PixelFormat;
    width @2 :UInt32;
    height @3 :UInt32;
    modifier @4 :UInt64;
    # Processes that should have access to this buffer.
    shareWith @5 :List(T.ProcessId);
    label @6 :Text;
}

struct MappedRegionInfo {
    regionId @0 :T.MappedRegionId;
    base @1 :UInt64;
    length @2 :UInt64;
    flags @3 :T.PageFlags;
    cacheMode @4 :MapCacheMode;
    # Process that owns this mapping.
    owner @5 :T.ProcessId;
    # What the mapping is for, as an open token ("mmio", "dma", "shared").
    purpose @6 :Text;
}

# ── Config space ────────────────────────────────────────────────────────
# A bounded window into a device's own configuration space. The driver
# already holds authority over the device; the window is bounded so a
# mistake cannot dump an entire bus.

struct PcieConfigSpace {
    deviceId @0 :T.HalDeviceId;
    offset @1 :UInt16;
    size @2 :UInt16;
}

# ── Device respawn ──────────────────────────────────────────────────────
# Typed policy and typed failure reports; the pre-revamp UInt8 codes are
# gone (T.RestartPolicy / T.EntityState / T.FailureReport).

struct DeviceRegistration {
    deviceId @0 :T.HalDeviceId;
    policy @1 :T.RestartPolicy;
    label @2 :Text;
    metadata @3 :T.StringMap;
}

# ── The HAL contract ────────────────────────────────────────────────────
# The root of the hardware-affordance domain: handed to a driver by the
# host, so it is deliberately not returned by any method. The
# sub-services (bus discovery, DMA mapping) ARE returned by accessors
# below, so every interface here is reachable.

interface HalService {
    # Request HAL authority for a driver-cap class.
    claim @0 (request :ClaimRequest) -> (authority :HalAuthority);

    # Map a memory region the authority covers.
    map @1 (region :MemoryAccess) -> (regionId :T.MappedRegionId);
    # Unmap a memory region previously mapped.
    unmap @2 (regionId :T.MappedRegionId) -> (result :T.VoidResult);

    # ── Interrupts: ONE mechanism, and it delivers ─────────────
    # Subscribe to an interrupt line; the returned subscription yields
    # firings. No blocking wait, no per-vector poll.
    subscribeIrq @3 (request :IrqRequest) -> (subscription :IrqSubscription);
    # Acknowledge a firing (manual ack; auto-ack otherwise).
    ackIrq @4 (vector :UInt32) -> (result :T.VoidResult);
    # Interrupt metadata for a vector.
    getInterruptInfo @5 (vector :UInt32) -> (info :InterruptInfo);

    # Power state control.
    setPower @6 (deviceId :T.HalDeviceId, state :HalDevicePowerState) -> (result :T.VoidResult);
    getPower @7 (deviceId :T.HalDeviceId) -> (state :HalDevicePowerState);

    # DMA allocation.
    allocDma @8 (request :DmaAllocRequest) -> (channel :DmaChannel);
    freeDma @9 (channelId :T.DmaChannelId) -> (result :T.VoidResult);

    # Query currently mapped regions.
    listRegions @10 (page :T.Pagination) -> (regions :List(MappedRegionInfo), total :UInt32);

    # Query device capabilities and limits.
    getDeviceInfo @11 (deviceId :T.HalDeviceId) -> (info :HalDeviceInfo);

    # Share a mapped region with another process.
    shareRegion @12 (regionId :T.MappedRegionId, targetPid :T.ProcessId) -> (result :T.VoidResult);

    # DMA-BUF sharing for cross-device buffer access.
    shareBuffer @13 (request :DmaBufShareRequest) -> (info :DmaBufInfo);
    unshareBuffer @14 (bufferId :T.BufferId) -> T.VoidResult;

    # Map device MMIO. Returns a HANDLE: the driver never receives a raw
    # address it must compute with.
    mapMmio @15 (deviceId :T.HalDeviceId, offset :UInt64, size :UInt64) -> (regionId :T.MappedRegionId);
    unmapMmio @16 (regionId :T.MappedRegionId) -> (result :T.VoidResult);

    # Allocate a DMA buffer, returning the channel (with its handle).
    allocDmaBuf @17 (size :UInt64, align :UInt32, direction :DmaDirection)
                -> (channel :DmaChannel, info :DmaBufInfo);
    freeDmaBuf @18 (channelId :T.DmaChannelId) -> (result :T.VoidResult);
    syncDmaForDevice @19 (channelId :T.DmaChannelId) -> (result :T.VoidResult);
    syncDmaForCpu @20 (channelId :T.DmaChannelId) -> (result :T.VoidResult);

    # Config space, as a bounded window.
    readConfigSpace @21 (window :PcieConfigSpace) -> (data :T.DataHandle);
    writeConfigSpace @22 (window :PcieConfigSpace, data :T.DataHandle) -> T.VoidResult;

    # ── Discovery ──────────────────────────────────────────────
    # The bus discovery contract, as a reachable sub-service.
    describeBus @23 () -> (service :BusDiscoveryService);
    # The per-address DMA contract, as a reachable sub-service.
    describeDma @24 () -> (service :DmaMapService);
    # Hardware description: an OPEN format token plus the bytes,
    # zero-copy.
    describeHardware @25 () -> (description :HardwareDescription);

    # Probe one device and describe it.
    probeDevice @26 (deviceId :T.HalDeviceId) -> (descriptor :DeviceDescriptor);
    # Bounded device listing.
    listDevices @27 (filter :HalDeviceFilter, page :T.Pagination)
               -> (devices :List(DeviceDescriptor), total :UInt64);

    # ── Device lifecycle ───────────────────────────────────────
    claimDevice @28 (deviceId :T.HalDeviceId, registration :DeviceRegistration)
               -> (authority :HalAuthority);
    releaseDevice @29 (deviceId :T.HalDeviceId) -> (result :T.VoidResult);
    reportFailure @30 (deviceId :T.HalDeviceId, report :T.FailureReport) -> (result :T.VoidResult);
    getRespawnContext @31 (deviceId :T.HalDeviceId)
                     -> (state :T.EntityState, attempts :UInt32, fallbackActive :Bool);
}

interface IrqSubscription {
    # Bounded pull: the caller states how many firings it will take.
    pull @0 (maxFirings :UInt32) -> (firings :List(IrqFiring), total :UInt64);
    cancel @1 () -> T.VoidResult;
}

struct ClaimRequest {
    label @0 :Text;
    # Opaque proof the backend asks for (a signed statement, a manifest
    # reference, …). What it must contain is backend-defined and stated
    # in the backend's own documentation; the protocol does not parse it.
    proof @1 :Data;
    expectedResources @2 :HalAuthority;
    metadata @3 :T.StringMap;
}

struct DmaAllocRequest {
    direction @0 :DmaDirection;
    width @1 :UInt32;
    maxBurst @2 :UInt32;
    scatterGather @3 :Bool;
    label @4 :Text;
}

struct InterruptInfo {
    vector @0 :UInt32;
    level @1 :T.InterruptLevel;
    count @2 :UInt64;
    lastFiredAt @3 :T.Timestamp;
    enabled @4 :Bool;
    owner @5 :T.ProcessId;
}

struct HalDeviceFilter {
    # Open class token (empty = all).
    class @0 :Text;
    # Restrict to devices attached at this bus address.
    bus @1 :T.BusAddress;
    # Require these capabilities.
    capabilities @2 :List(T.CapabilityType);
    metadata @3 :T.StringMap;
}

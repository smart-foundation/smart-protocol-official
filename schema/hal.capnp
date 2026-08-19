@0xa1b2c3d4e5f6003c;

# ═══════════════════════════════════════════════════════════════════════
# HAL - hardware abstraction primitives
#
# Smart-protocol is confirmed hybrid: it spans from user-facing schemas
# down to primitives needed by driver-apps. HAL is the layer where
# apps that ARE drivers (firmware, sandboxed kernel, embedded controllers)
# negotiate hardware access with the kernel.
#
# HAL describes what hardware-access a driver may ask for, NOT how those
# requests are implemented. Backends implement interrupts however they
# want (line, message, polled, msi). The protocol only cares about the
# affordances a driver gets:
#   - mapping memory regions
#   - subscribing to interrupt lines
#   - DMA channels
#   - power control of devices
# Each is backend-agnostic; a smart-protokol driver moves between
# architectures naturally.
#
# Improvements (audit-3):
#   - HalService.map returns T.MappedRegionId instead of bare UInt64 (Rule 2).
#   - HalService.unmap takes T.MappedRegionId instead of (base, length) pair.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "capability.capnp".Capability;

struct MemoryAccess {
    # Physical or bus address (backend-decided; zero = backend picks).
    # On systems with an IOMMU, this may be a DMA address rather than
    # a true physical address. The backend documents its interpretation.
    base @0 :UInt64;
    length @1 :UInt64;
    flags @2 :List(MemFlag);
    # Backend may map this with cache disabled, write-through, etc.
    cacheMode @3 :CacheMode;
}

enum MemFlag {
    read @0;
    write @1;
    execute @2;
    prefetchable @3;
    uncacheable @4;
    writeCombined @5;
    writeThrough @6;
    io @7;
    guarded @8;
    shared @9;
    custom @10;
}

enum CacheMode {
    defaultCached @0;
    writeBack @1;
    writeThrough @2;
    uncacheable @3;
    custom @4;
}

struct IrqRequest {
    vector @0 :UInt32;
    level @1 :IrqLevel;
    handler @2 :HandlerRef;
    # If true, ack to backend after handler completes.
    needingAck @3 :Bool = true;
}

enum IrqLevel {
    edge @0;
    level @1;
    message @2;
    custom @3;
}

struct HandlerRef {
    # Optional reference to a process:task which handles.
    task @0 :T.ProcessId;
}

struct IrqTicket {
    vector @0 :UInt32;
    level @1 :IrqLevel;
    # Time the interrupt was claimed.
    lastFiredAt @2 :T.Timestamp;
    # Total count of firings observed.
    count @3 :UInt64;
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
    deviceToHost @0;
    hostToDevice @1;
    both @2;
    custom @3;
}



struct DevicePowerState {
    state @0 :PowerState;
    # Power consumed in milliwatts (zero if unknown).
    milliwatts @1 :UInt32;
    # Time the device becomes ready from this state (backend-decided unit;
    # typically nanoseconds on hardware with known resume latencies).
    resumeLatency @2 :T.Duration;
}

enum PowerState {
    on @0;
    active @1;
    idle @2;
    standby @3;
    sleep @4;
    deepSleep @5;
    off @6;
    custom @7;
}

struct HalAuthority {
    # Memory access the driver may claim.
    memory @0 :List(MemoryAccess);
    # Interrupts the driver may subscribe to.
    vectors @1 :List(IrqRequest);
    # DMA channels the driver may operate.
    channels @2 :List(DmaChannel);
    # Authority over power state transitions of which devices.
    powerTargets @3 :List(T.HalDeviceId);
}

# ── Audit-5: PCI Device Info ─────────────────────────────────
# Raw PCI configuration space snapshot from bus enumeration.

struct PciDeviceInfo {
    bus @0 :UInt8;
    device @1 :UInt8;
    function @2 :UInt8;
    vendorId @3 :UInt16;
    deviceId @4 :UInt16;
    class @5 :UInt8;
    subclass @6 :UInt8;
    progIf @7 :UInt8;
    revision @8 :UInt8;
    headerType @9 :UInt8;
    bar @10 :List(UInt32);
    interruptLine @11 :UInt8;
    interruptPin @12 :UInt8;
    capabilitiesOffset @13 :UInt8;
    isMultifunction @14 :Bool;
}

# ── Audit-5: Device Descriptor ───────────────────────────────
# Low-level hardware descriptor produced by bus enumeration.

struct DeviceDescriptor {
    id @0 :T.HalDeviceId;
    name @1 :Text;
    class @2 :Text;
    vendor @3 :UInt16;
    product @4 :UInt16;
    revision @5 :UInt8;
    busType @6 :UInt8;
    capabilities @7 :List(UInt8);
    resources @8 :List(DeviceResource);
    driver @9 :DriverInfo;
    interruptModes @10 :List(UInt8);
}

# ── Audit-5: Device Resource ─────────────────────────────────
# Hardware resource assigned to a device.

struct DeviceResource {
    type @0 :UInt8;
    address @1 :UInt64;
    size @2 :UInt64;
    flags @3 :UInt32;
}

# ── Audit-5: Driver Info ─────────────────────────────────────
# Information about the driver bound to a device.

struct DriverInfo {
    name @0 :Text;
    version @1 :UInt32;
    vendor @2 :Text;
    supportsHotSwap @3 :Bool;
    respawnPolicy @4 :UInt8;
}

interface HalService {
    # Request HAL authority for a driver-cap class.
    claim @0 (request :ClaimRequest) -> (authority :HalAuthority);
    # Map a memory region the authority covers.
    map @1 (region :MemoryAccess) -> (regionId :T.MappedRegionId);
    # Unmap a memory region previously mapped.
    unmap @2 (regionId :T.MappedRegionId) -> (result :T.VoidResult);
    # Subscribe to an IRQ vector.
    subscribe @3 (request :IrqRequest) -> (ticket :IrqTicket);
    # Unsubscribe.
    unsubscribe @4 (vector :UInt32) -> (result :T.VoidResult);
    # Wait for an IRQ firing.
    waitIrq @5 (vector :UInt32, timeout :T.Duration) -> (result :T.BoolResult);
    # Acknowledge an IRQ (manual ack; auto-ack otherwise).
    ackIrq @6 (vector :UInt32) -> (result :T.VoidResult);

    # Power state control.
    setPower @7 (deviceId :T.HalDeviceId, state :DevicePowerState) -> (result :T.VoidResult);
    getPower @8 (deviceId :T.HalDeviceId) -> (state :DevicePowerState);

    # DMA allocation.
    allocDma @9 (request :DmaAllocRequest) -> (channel :DmaChannel);
    freeDma @10 (channelId :T.DmaChannelId) -> (result :T.VoidResult);

    # Audit-7: query currently mapped regions.
    listRegions @11 (page :T.Pagination) -> (regions :List(MappedRegionInfo), total :UInt32);

    # Audit-7: query device capabilities and limits.
    getDeviceInfo @12 (deviceId :T.HalDeviceId) -> (info :HalDeviceInfo);

    # Audit-7: query interrupt metadata.
    getInterruptInfo @13 (vector :UInt32) -> (info :InterruptInfo);

    # Audit-7: share a mapped region with another process.
    shareRegion @14 (regionId :T.MappedRegionId, targetPid :T.ProcessId) -> (result :T.VoidResult);

    # Audit-7: DMA-BUF sharing for cross-device buffer access.
    shareBuffer @15 (request :DmaBufShareRequest) -> (info :DmaBufInfo);
    unshareBuffer @16 (fd :UInt32) -> T.VoidResult;

    # Audit-9: PCIe configuration space read/write methods.
    readPcieConfigSpace @17 (request :PcieConfigSpace) -> (data :T.DataHandle);
    writePcieConfigSpace @18 (request :PcieConfigSpace, data :T.DataHandle) -> T.VoidResult;

    # Audit-5: Hardware Discovery
    discoverBus @19 () -> (topology :BusTopology);
    enumeratePci @20 () -> (devices :List(PciDeviceInfo));
    parseAcpi @21 (tableSig :UInt32) -> (data :Data);
    probeDevice @22 (deviceId :T.HalDeviceId) -> (descriptor :DeviceDescriptor);

    # Audit-5: Device Management
    claimDevice @23 (deviceId :T.HalDeviceId, driver :Text) -> (authority :HalAuthority);
    releaseDevice @24 (deviceId :T.HalDeviceId) -> (result :T.VoidResult);
    listDevices @25 () -> (devices :List(DeviceDescriptor));

    # Audit-5: MMIO
    mapMmio @26 (deviceId :T.HalDeviceId, offset :UInt64, size :UInt64) -> (virt :UInt64, handle :UInt64);
    unmapMmio @27 (handle :UInt64) -> (result :T.VoidResult);

    # Audit-5: DMA
    allocDmaBuf @28 (size :UInt64, align :UInt32) -> (phys :UInt64, virt :UInt64, handle :UInt64);
    freeDmaBuf @29 (handle :UInt64) -> (result :T.VoidResult);
    syncDmaForDevice @30 (handle :UInt64) -> (result :T.VoidResult);
    syncDmaForCpu @31 (handle :UInt64) -> (result :T.VoidResult);

    # Audit-5: Interrupts
    subscribeIrq @32 (deviceId :T.HalDeviceId, mode :UInt8) -> (vector :UInt8, handle :UInt64);
    unsubscribeIrq @33 (handle :UInt64) -> (result :T.VoidResult);
    waitIrqHandle @34 (handle :UInt64, timeoutNs :UInt64) -> (fired :Bool);
    ackIrqHandle @35 (handle :UInt64) -> (result :T.VoidResult);

    # Audit-5: Respawn
    registerDevice @36 (deviceId :T.HalDeviceId, policy :UInt8) -> (handle :UInt64);
    reportFailure @37 (deviceId :T.HalDeviceId, report :Data) -> (result :T.VoidResult);
    getRespawnContext @38 (deviceId :T.HalDeviceId) -> (state :UInt8, attempts :UInt32, fallbackActive :Bool);
    setFallbackActive @39 (deviceId :T.HalDeviceId, active :Bool) -> (result :T.VoidResult);

    # ── Hardware Foundation (low-level physical/raw access) ──────────────────
    # These methods provide direct hardware access for backends that manage
    # physical memory, I/O ports, and interrupt controllers. The higher-level
    # methods above (claim, map, subscribe) are preferred for driver-apps;
    # these are for backends and the kernel's own TCB implementation.

    # Physical page management
    allocPhysicalPage @40 () -> (phys :UInt64);
    freePhysicalPage @41 (phys :UInt64) -> (result :T.VoidResult);

    # Raw MMIO mapping (phys-based, not device-bound)
    mapRawMmio @42 (phys :UInt64, size :UInt64, flags :UInt32) -> (virt :UInt64, handle :UInt64);
    unmapRawMmio @43 (handle :UInt64) -> (result :T.VoidResult);

    # Page table management
    createAddressSpace @44 (levels :UInt8, mode :UInt8) -> (asid :UInt64);
    destroyAddressSpace @45 (asid :UInt64) -> (result :T.VoidResult);
    mapVirtual @46 (asid :UInt64, virt :UInt64, phys :UInt64, flags :UInt32) -> (result :T.VoidResult);
    unmapVirtual @47 (asid :UInt64, virt :UInt64) -> (result :T.VoidResult);
    switchAddressSpace @48 (asid :UInt64) -> (result :T.VoidResult);

    # Page table management
    registerIrq @49 (vector :UInt8, mode :UInt8) -> (handle :UInt64);
    unregisterIrq @50 (handle :UInt64) -> (result :T.VoidResult);
    enableIrq @51 (vector :UInt8) -> (result :T.VoidResult);
    disableIrq @52 (vector :UInt8) -> (result :T.VoidResult);

    # MSI/MSI-X for PCIe devices
    allocMsi @53 (deviceId :UInt64, count :UInt8) -> (vectors :List(UInt8), handle :UInt64);
    allocMsix @54 (deviceId :UInt64, count :UInt16) -> (vectors :List(UInt8), handle :UInt64);
    freeMsi @55 (handle :UInt64) -> (result :T.VoidResult);
    programMsi @56 (handle :UInt64, affinity :UInt32) -> (result :T.VoidResult);

    # Watchdog management
    registerWatchdog @57 (timeoutNs :UInt64) -> (handle :UInt64);
    unregisterWatchdog @58 (handle :UInt64) -> (result :T.VoidResult);
    petWatchdog @59 (handle :UInt64) -> (result :T.VoidResult);

    # x86 Port I/O (optional, x86-only). Returns None-equivalent on non-x86.
    getX86PortIo @60 () -> (service :X86PortIo);
}

struct ClaimRequest {
    label @0 :Text;
    proof @1 :Data;
    expectedResources @2 :HalAuthority;
}

struct DmaAllocRequest {
    direction @0 :DmaDirection;
    width @1 :UInt32;
    maxBurst @2 :UInt32;
    scatterGather @3 :Bool;
    label @4 :Text;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-7: Extended HAL capabilities
#
# Userland drivers, cloud hardware, virtual HAL, AI accelerators,
# device tree/ACPI, and DMA-BUF sharing. These extend the
# kernel-managed hardware model to support diverse hardware
# abstraction needs.
# ═══════════════════════════════════════════════════════════════════════

# ── Userland HAL ──────────────────────────────────────────────

struct UserlandDriverInfo {
    name @0 :Text;
    # Protocol identifier (e.g., "FUSE", "user-space-i2c", "user-space-gpio").
    protocol @1 :Text;
    pid @2 :T.ProcessId;
    capabilities @3 :List(UserlandCapability);
    # Whether the driver requires elevated privileges.
    privileged @4 :Bool;
}

enum UserlandCapability {
    filesystem @0;
    network @1;
    device @2;
    ipc @3;
    custom @4;
}

# ── Cloud HAL ─────────────────────────────────────────────────

struct CloudHalInfo {
    # Cloud provider identifier (e.g., "aws", "azure", "gcp").
    provider @0 :Text;
    region @1 :Text;
    # Service type (e.g., "nitro", "shielded-vm", "confidential-computing").
    service @2 :Text;
    # API endpoint URL.
    endpoint @3 :Text;
    authMethod @4 :CloudAuth;
    # Whether hardware attestation is available.
    attestation @5 :Bool;
}

enum CloudAuth {
    none @0;
    iam @1;
    token @2;
    certificate @3;
    custom @4;
}

# ── Virtual HAL (Paravirtualized) ─────────────────────────────

struct VirtualHalInfo {
    # Hypervisor identifier (e.g., "kvm", "xen", "hyper-v", "vmware").
    hypervisor @0 :Text;
    # Whether virtio transport is used.
    virtio @1 :Bool;
    # virtio device IDs.
    deviceIds @2 :List(Text);
    # Transport type (e.g., "pci", "mmio", "ccw").
    transport @3 :Text;
    # Whether memory balloon is supported.
    balloon @4 :Bool;
    # Whether VM snapshot is supported.
    snapshot @5 :Bool;
}

# ── AI Accelerator HAL ────────────────────────────────────────

struct AiAcceleratorInfo {
    type @0 :AiAcceleratorType;
    vendor @1 :Text;
    model @2 :Text;
    memoryBytes @3 :UInt64;
    computeUnits @4 :UInt32;
    # Supported precision formats.
    precision @5 :List(AiPrecision);
    # Supported ML frameworks (e.g., "tensorflow", "pytorch", "onnx").
    frameworks @6 :List(Text);
}

enum AiAcceleratorType {
    tpu @0;
    npu @1;
    gpu @2;
    fpga @3;
    dsp @4;
    custom @5;
}

enum AiPrecision {
    fp32 @0;
    fp16 @1;
    bf16 @2;
    int8 @3;
    int4 @4;
    binary @5;
    custom @6;
}

# ── Device Tree / ACPI Query ──────────────────────────────────

struct HardwareDescription {
    format @0 :HardwareDescFormat;
    # Device tree blob or ACPI table data.
    data @1 :T.DataHandle;
    # Overlay/dtso for runtime modifications.
    overlay @2 :T.DataHandle;
}

enum HardwareDescFormat {
    deviceTree @0;
    acpi @1;
    smbios @2;
    devicetreeOverlay @3;
    custom @4;
}

# ── DMA-BUF Sharing ──────────────────────────────────────────

struct DmaBufInfo {
    # DMA-BUF file descriptor.
    fd @0 :UInt32;
    sizeBytes @1 :UInt64;
    format @2 :T.PixelFormat;
    width @3 :UInt32;
    height @4 :UInt32;
    # Buffer modifier (tiling, compression).
    modifier @5 :UInt64;
    # Sync file for implicit sync.
    syncFile @6 :Data;
}

struct DmaBufShareRequest {
    sizeBytes @0 :UInt64;
    format @1 :T.PixelFormat;
    width @2 :UInt32;
    height @3 :UInt32;
    modifier @4 :UInt64;
    # Processes that should have access to this buffer.
    shareWith @5 :List(T.ProcessId);
}

# ── Mapped Region Info ────────────────────────────────────────

struct MappedRegionInfo {
    regionId @0 :T.MappedRegionId;
    base @1 :UInt64;
    length @2 :UInt64;
    flags @3 :List(MemFlag);
    cacheMode @4 :CacheMode;
    # Process that owns this mapping.
    owner @5 :T.ProcessId;
}

# ── HAL Capability ──────────────────────────────────────────────

enum HalCapability {
    dma @0;
    irq @1;
    mmio @2;
    portIo @3;
    busMaster @4;
    custom @5;
}

# ── Device Info ───────────────────────────────────────────────

struct HalDeviceInfo {
    deviceId @0 :T.HalDeviceId;
    # Device class (e.g., "pci", "usb", "platform").
    class @1 :Text;
    vendor @2 :Text;
    model @3 :Text;
    # Device capabilities.
    capabilities @4 :List(HalCapability);
    # Maximum mapped regions.
    maxRegions @5 :UInt32;
    # Maximum DMA channels.
    maxDmaChannels @6 :UInt32;
}

# ── Interrupt Info ────────────────────────────────────────────

struct InterruptInfo {
    vector @0 :UInt32;
    level @1 :IrqLevel;
    count @2 :UInt64;
    lastFiredAt @3 :T.Timestamp;
    enabled @4 :Bool;
    owner @5 :T.ProcessId;
}

# ── IOMMU/SMMU Support (audit-8 What's Still Missing) ──
struct IommuInfo {
    deviceId @0 :T.HalDeviceId;
    type @1 :IommuType;
    supportsTranslation @2 :Bool;
    supportsIsolation @3 :Bool;
    supportsPassthrough @4 :Bool;
    iovaBitWidth @5 :UInt8;
    maxIova @6 :UInt64;
}

enum IommuType {
    smmu @0;
    intelIommu @1;
    amdVi @2;
    armSmmu @3;
    virtioIommu @4;
    custom @5;
}

struct PcieConfigSpace {
    bus @0 :UInt8;
    device @1 :UInt8;
    function @2 :UInt8;
    offset @3 :UInt16;
    size @4 :UInt16;
}

# ── Serial Bus Access (SPI/I2C for embedded devices) ──
struct SerialBusInfo {
    busId @0 :UInt32;
    type @1 :SerialBusType;
    chipSelect @2 :UInt8;
    maxFrequencyHz @3 :UInt32;
    mode @4 :UInt8;
}

enum SerialBusType {
    spi @0;
    i2c @1;
    i3c @2;
    mipiCsi @3;
    custom @4;
}

# ═══════════════════════════════════════════════════════════════════════
# v0.0.2 additions — Bus Discovery & Topology
#
# Drivers and the kernel share an abstract Bus interface. The
# implementation walks the bus topology however it wants; the
# protocol only commits to the affordances.
# ═══════════════════════════════════════════════════════════════════════

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
    # Devices attached at this address (drivers manage the
    # attach lifecycle via device.capnp's DeviceService).
    attachedDevices @1 :List(T.HalDeviceId);
    parent @2 :T.BusAddress;
}

interface BusDiscoveryService {
    # Probe the bus tree. Implementation decides how — walking ACPI,
    # PCIe enumeration, device-tree blob, virtio config space, ...
    probe @0 () -> (topology :BusTopology);
    # Subscribe to topology changes (hotplug, device removal).
    subscribeTopology @1 () -> (subscription :BusTopologySubscription);
    # Resolve a bus address to a device id (if attached).
    resolveAddress @2 (address :T.BusAddress) -> (device :T.HalDeviceId);
}

interface BusTopologySubscription {
    pull @0 () -> (events :List(BusTopologyEvent));
    cancel @1 () -> T.VoidResult;
}

struct BusTopologyEvent {
    at @0 :UInt64;
    union {
        deviceAttached @1 :BusAttachEvent;
        deviceDetached @2 :T.BusAddress;
        busRescanned @3 :T.BusAddress;
        custom @4 :Void;
    }
}

struct BusAttachEvent {
    address @0 :T.BusAddress;
    device @1 :T.HalDeviceId;
    # Hardware class (network, display, storage, ...).
    hardwareClass @2 :Text;
}

# ── Per-Address DMA Helpers ──────────────────────────────────
# Some backends require DMA-address negotiation per bus address.

struct DmaAddrRequest {
    device @0 :T.HalDeviceId;
    bus @1 :T.BusAddress;
    lengthBytes @2 :UInt64;
    direction @3 :UInt8;
    # Driver may hint; backend overrides with physical it can map.
    preferredAddress @4 :UInt64;
}

interface DmaMapService {
    map @0 (request :DmaAddrRequest) -> (handle :T.DmaHandle);
    unmap @1 (handle :T.DmaHandle) -> (result :T.VoidResult);
    syncForDevice @2 (handle :T.DmaHandle) -> (result :T.VoidResult);
    syncForCpu @3 (handle :T.DmaHandle) -> (result :T.VoidResult);
}

# ── x86 Port I/O (optional, x86-only) ────────────────────────
# Architecture-specific. Only present on x86/x86_64 systems.
# Not part of the arch-agnostic HalService core.

interface X86PortIo {
    inb @0 (port :UInt16) -> (val :UInt8);
    outb @1 (port :UInt16, val :UInt8) -> (result :T.VoidResult);
    inw @2 (port :UInt16) -> (val :UInt16);
    outw @3 (port :UInt16, val :UInt16) -> (result :T.VoidResult);
    inl @4 (port :UInt16) -> (val :UInt32);
    outl @5 (port :UInt16, val :UInt32) -> (result :T.VoidResult);
}


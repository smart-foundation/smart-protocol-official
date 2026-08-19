@0xa1b2c3d4e5f6003a;

# ═══════════════════════════════════════════════════════════════════════
# Boot - handoff from bootloader to OS, and OS to apps
#
# Stage-transitioning artifacts: firmware/bootloader hands off to kernel;
# kernel announces startup to init; init announces state to apps.
# Each stage produces a BootManifest that the next stage consumes.
# Backends may add stages or fold them; the protocol is timeless.
#
# All identifiers are typed. All durations use T.Duration.
# All timestamps use T.Timestamp. All errors use T.Error.
# Architecture is typed enum with Text fallback.
#
# The ONLY well-known capability in SpaceOS:
#   Handle 1 in every process's capability table = KernelService.
#   The kernel MUST place this at handle 1 before entering userspace.
#   This is the bootstrap capability — no other handles are hardcoded.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using K = import "kernel.capnp";
using FB = import "framebuffer.capnp";

    struct IpcChannel {
        requestArenaVaddr @0 :UInt64;
        requestArenaSize @1 :UInt32;
        replyArenaVaddr @2 :UInt64;
        replyArenaSize @3 :UInt32;
    }

struct BootManifest {
    # Identifier of the producing stage.
    producer @0 :BootStage;
    # Identifier of the intended next stage.
    nextStage @1 :BootStage;
    # Time the producer started.
    startedAt @2 :T.Timestamp;
    # Time the handoff fired.
    finishedAt @3 :T.Timestamp;
    # Duration of this stage.
    duration @4 :T.Duration;

    # Memory plan the next stage inherits.
    memory @5 :List(MemoryRange);

    # Storage devices discovered.
    devices @6 :List(StorageDevice);

    # Logical CPUs / cores available.
    compute @7 :List(ComputeNode);

    # Persistent variables / boot args.
    args @8 :T.StringMap;

    # Optional initrd or initial filesystem blob.
    # For blobs >1KB, use a reference handle instead.
    initrd @9 :BootBlob;

    # Negotiated log level.
    logLevel @10 :T.LogLevel;

    # Capabilities / authority handed to next stage.
    capabilities @11 :List(BootCapability);

    # Firmware information.
    firmware @12 :FirmwareInfo;

    # Boot mode.
    bootMode @13 :BootMode;

    # Secure boot state.
    secureBoot @14 :SecureBootState;

    # Boot diagnostics (timing, warnings).
    diagnostics @15 :List(BootDiagnostic);

    # Partition tables discovered on block devices.
    partitionTables @16 :List(PartitionTable);

    # Network boot information (if applicable).
    networkBoot @17 :NetworkBootInfo;

    # Device tree blob (ARM/RISC-V systems).
    deviceTree @18 :DeviceTreeBlob;

    # Hardware devices discovered.
    hardware @19 :List(HardwareDevice);

    # ACPI tables discovered.
    acpiTables @20 :List(AcpiTable);

    # SMBIOS entries discovered.
    smbios @21 :List(SmbiosEntry);

    # DMI system information.
    dmi @22 :DmiInfo;

    # Bootloader information.
    bootloader @23 :BootloaderInfo;

    # TPM capability.
    tpmCapability @24 :TpmCapability;

    # Initrd metadata (format, compression, modules).
    initrdMetadata @25 :InitrdMetadata;

    # Serial devices discovered.
    serialDevices @26 :List(SerialDevice);

    # Audit-7: boot optimization and resilience.
    # Per-stage timing profile for boot optimization.
    profile @27 :BootStageProfile;
    # Typed boot environment (bareMetal, container, vm, etc.).
    environment @28 :BootEnvironment;
    # Ordered failover chains for boot resilience.
    failoverChains @29 :List(FailoverChain);
    # Capability requests from each stage.
    capabilityRequests @30 :List(BootCapabilityRequest);

    # ── SpaceOS Bootstrap ─────────────────────────────────────────────────
    # The ONLY hardcoded capability in SpaceOS.
    # Every process's capability table at handle 1 is KernelService.
    # The kernel places this here so init and all subsequent processes
    # can immediately call spawn(), exec(), mapRegion(), etc.
    # All other capabilities are dynamic — issued by KernelService or services.
    kernelService @31 :K.KernelService;
    # Framebuffer (mode + physical address). The kernel renders the boot
    # screen from this; in the SAS model the kernel maps the physical
    # range via HHDM and writes pixels.
    framebuffer @32 :FB.Framebuffer;
    # The boot path exposes a long-lived capnp BootService peer channel
    # (request/response). The kernel reads this capability from the manifest
    # and calls methods on it (handOff, state, subscribe, configureCompute,
    # enableHardwareDevice, etc.) — never via a side-channel Rust API.
    bootService @33 :BootService;
    # IPC channels mapped to userspace-accessible shared memory.
    # The kernel populates this list so init can discover channel addresses.
    channels @34 :List(IpcChannel);
    # All userland images the bootloader handed us.
    userlandImages @35 :List(T.UserlandImage);
    # Isolation boundaries declared at boot.
    isolationManifest @36 :List(T.IsolatedScope);
    # Binary data blobs referenced by UserlandImage.moduleIndex.
    modules @37 :List(Module);
    # Virtual address where kernel places BootstrapInfo for each service.
    bootstrapVaddr @38 :UInt64;
}

struct BootBlob {
    union {
        inline @0 :Data;
        reference @1 :BootBlobRef;
    }
    # Metadata about the blob (format, compression, modules).
    metadata @2 :InitrdMetadata;
}

struct BootBlobRef {
    handle @0 :UInt64;
    sizeBytes @1 :UInt64;
    hash @2 :Data;
    format @3 :Text;
}

enum BootStage {
    firmware @0;
    bootloader @1;
    kernel @2;
    init @3;
    userspace @4;
    custom @5;
    # Audit-7: extended boot stages for container/VM/embedded.
    container @6;
    hypervisor @7;
    wasm @8;
    embedded @9;
}

struct MemoryRange {
    base @0 :UInt64;
    length @1 :UInt64;
    kind @2 :MemoryKind;
    # Typed memory flags instead of raw UInt32.
    flags @3 :MemoryFlags;
}

struct MemoryFlags {
    cacheable @0 :Bool;
    writeCombining @1 :Bool;
    writeProtected @2 :Bool;
    executeDisabled @3 :Bool;
    nonVolatile @4 :Bool;
}

enum MemoryKind {
    ram @0;
    rom @1;
    mmio @2;
    acpi @3;
    persistent @4;
    reserved @5;
    unusable @6;
    device @7;
    bootloader @8;
    kernel @9;
    user @10;
    custom @11;
}

struct StorageDevice {
    id @0 :Text;
    # Backend-assigned device identifier (opaque to the protocol).
    deviceId @1 :Text;
    kind @2 :StorageKind;
    sectors @3 :UInt64;
    sectorBytes @4 :UInt32;
    # Typed capabilities instead of List(Text).
    capabilities @5 :List(StorageCapability);
    # Human-readable name.
    name @6 :Text;
    # Total size in bytes.
    sizeBytes @7 :UInt64;
    # Storage bus protocol.
    bus @8 :StorageBus;
    # Partition table on this device (if applicable).
    partitionTable @9 :PartitionTable;
    # Bus-specific info (backend populates the relevant one).
    # NVMe-specific info (if bus is nvme).
    nvmeInfo @10 :NvmeInfo;
    # AHCI-specific info (if bus is ahci).
    ahciInfo @11 :AhciInfo;
    # SCSI-specific info (if bus is scsi).
    scsiInfo @12 :ScsiInfo;
}

enum StorageKind {
    block @0;
    network @1;
    memory @2;
    optical @3;
    virtual @4;
    removable @5;
    persistent @6;
    custom @7;
}

enum StorageCapability {
    read @0;
    write @1;
    trim @2;
    flush @3;
    secureErase @4;
    cache @5;
    custom @6;
}

enum StorageBus {
    nvme @0;
    ahci @1;
    ide @2;
    scsi @3;
    virtio @4;
    sd @5;
    emmc @6;
    fsblk @7;
    usb @8;
    fcoe @9;
    custom @10;
}

struct NvmeInfo {
    controllerId @0 :UInt32;
    namespaceId @1 :UInt32;
    queueCount @2 :UInt32;
    maxTransferSize @3 :UInt32;
    nvmeVersion @4 :Text;
    lbaFormat @5 :UInt32;
    utilization @6 :UInt64;
}

struct AhciInfo {
    port @0 :UInt32;
    deviceType @1 :Text;
    commandListDepth @2 :UInt32;
    signature @3 :UInt32;
}

struct ScsiInfo {
    targetId @0 :UInt32;
    lun @1 :UInt32;
    vendor @2 :Text;
    product @3 :Text;
    revision @4 :Text;
    scsiVersion @5 :Text;
}

enum PartitionTableKind {
    gpt @0;
    mbr @1;
    apt @2;
    sun @3;
    custom @4;
}

struct PartitionTable {
    kind @0 :PartitionTableKind;
    diskGuid @1 :Text;
    entryCount @2 :UInt32;
    backupLba @3 :UInt64;
    currentLba @4 :UInt64;
    partitions @5 :List(Partition);
}

struct Partition {
    index @0 :UInt32;
    typeGuid @1 :Text;
    uniqueGuid @2 :Text;
    firstLba @3 :UInt64;
    lastLba @4 :UInt64;
    sizeBytes @5 :UInt64;
    name @6 :Text;
    attributes @7 :UInt64;
    bootable @8 :Bool;
    filesystem @9 :Text;
}

struct ComputeNode {
    id @0 :Text;
    # Typed architecture enum with Text fallback.
    arch @1 :Architecture;
    vendor @2 :Text;
    cores @3 :UInt32;
    threads @4 :UInt32;
    # Typed CPU feature flags.
    features @5 :List(CpuFeature);
    # Clock speed in MHz (0 if unknown).
    clockMhz @6 :UInt32;
    # L1 cache size in bytes (0 if unknown).
    l1CacheBytes @7 :UInt32;
    # L2 cache size in bytes (0 if unknown).
    l2CacheBytes @8 :UInt32;
}

enum Architecture {
    x86 @0;
    x8664 @1;
    arm32 @2;
    aarch64 @3;
    riscv32 @4;
    riscv64 @5;
    wasm32 @6;
    wasm64 @7;
    ppc64 @8;
    s390x @9;
    unknown @10;
    custom @11;
}

enum CpuFeature {
    sse @0;
    sse2 @1;
    sse3 @2;
    ssse3 @3;
    sse41 @4;
    sse42 @5;
    avx @6;
    avx2 @7;
    avx512 @8;
    neon @9;
    fp16 @10;
    atomics @11;
    riscvV @12;
    wasmSimd @13;
    custom @14;
}

struct FirmwareInfo {
    vendor @0 :Text;
    version @1 :Text;
    # Firmware type.
    kind @2 :FirmwareKind;
    # UEFI/BIOS/Libreboot/coreboot version string.
    firmwareVersion @3 :Text;
    # Secure boot database status.
    secureBootDb @4 :Text;
}

enum FirmwareKind {
    uefi @0;
    bios @1;
    coreboot @2;
    libreboot @3;
    uBoot @4;
    bareMetal @5;
    custom @6;
}

enum BootMode {
    normal @0;
    recovery @1;
    safe @2;
    diagnostic @3;
    maintenance @4;
    custom @5;
}

struct SecureBootState {
    enabled @0 :Bool;
    # Whether the boot chain is verified.
    verified @1 :Bool;
    # TPM PCR measurements (if available).
    pcrMeasurements @2 :List(PcrMeasurement);
    # Signing key database status.
    keyDatabaseStatus @3 :Text;
    # TPM version detected.
    tpmVersion @4 :TpmVersion;
    # TPM capability information.
    tpmCapability @5 :TpmCapability;
    # Attestation quote (if available).
    attestation @6 :AttestationQuote;
    # Audit-7: chain-of-trust attestation items.
    chainItems @7 :List(BootChainItem);
    # Audit-7: boot policy (required/optional stages).
    policy @8 :BootPolicy;
    # Audit-7: typed boot environment.
    environment @9 :BootEnvironment;
}

struct PcrMeasurement {
    index @0 :UInt32;
    algorithm @1 :Text;
    digest @2 :Data;
}

enum TpmVersion {
    tpm12 @0;
    tpm20 @1;
    custom @2;
}

enum TpmAlgorithm {
    sha1 @0;
    sha256 @1;
    sha384 @2;
    sha512 @3;
    custom @4;
}

struct TpmCapability {
    version @0 :TpmVersion;
    pcrBanks @1 :List(TpmPcrBank);
    nvStorage @2 :Bool;
    keyStorage @3 :Bool;
    attestation @4 :Bool;
}

struct TpmPcrBank {
    algorithm @0 :TpmAlgorithm;
    pcrCount @1 :UInt32;
}

struct AttestationQuote {
    pcrSelection @0 :List(UInt32);
    pcrValues @1 :List(Data);
    signature @2 :Data;
    timestamp @3 :T.Timestamp;
}

enum BootloaderKind {
    grub @0;
    grub2 @1;
    refind @2;
    shim @3;
    uBoot @4;
    barebox @5;
    custom @6;
    limine @7;
}

struct BootloaderInfo {
    kind @0 :BootloaderKind;
    version @1 :Text;
    configPath @2 :Text;
    secureBootChain @3 :Bool;
    shimTrustAnchor @4 :Text;
    hhdmOffset @5 :UInt64;
}

enum NetworkBootMethod {
    pxe @0;
    http @1;
    ipxe @2;
    iscsi @3;
    custom @4;
}

struct NetworkBootInfo {
    method @0 :NetworkBootMethod;
    dhcpLease @1 :DhcpLease;
    serverAddress @2 :Text;
    bootFile @3 :Text;
    httpUrl @4 :Text;
    proxy @5 :Text;
}

struct DhcpLease {
    ip @0 :Text;
    subnet @1 :Text;
    gateway @2 :Text;
    dns @3 :List(Text);
    leaseTime @4 :T.Duration;
    serverName @5 :Text;
}

struct DeviceTreeBlob {
    handle @0 :UInt64;
    sizeBytes @1 :UInt64;
    hash @2 :Data;
    compatible @3 :List(Text);
    overlay @4 :Bool;
}

struct HardwareDevice {
    id @0 :Text;
    class @1 :Text;
    vendor @2 :Text;
    model @3 :Text;
    drivers @4 :List(Text);
    dtCompatible @5 :List(Text);
    acpiPath @6 :Text;
}

struct AcpiTable {
    signature @0 :Text;
    oemId @1 :Text;
    revision @2 :UInt32;
    sizeBytes @3 :UInt32;
    handle @4 :UInt64;
}

struct SmbiosEntry {
    type @0 :UInt32;
    length @1 :UInt32;
    handle @2 :UInt16;
    data @3 :Data;
}

struct DmiInfo {
    systemManufacturer @0 :Text;
    systemProductName @1 :Text;
    biosVersion @2 :Text;
    biosVendor @3 :Text;
    chassisType @4 :Text;
    chassisManufacturer @5 :Text;
    boardManufacturer @6 :Text;
    boardProductName @7 :Text;
}

enum InitrdFormat {
    cpioGz @0;
    cpioXz @1;
    cpioZstd @2;
    erofs @3;
    squashfs @4;
    none @5;
    custom @6;
}

struct InitrdMetadata {
    format @0 :InitrdFormat;
    compression @1 :Text;
    sizeBytes @2 :UInt64;
    hash @3 :Data;
    rootFilesystem @4 :Text;
    kernelModules @5 :List(Text);
}

enum UartParity {
    none @0;
    odd @1;
    even @2;
    mark @3;
    space @4;
    custom @5;
}

enum UartFlowControl {
    none @0;
    hardware @1;
    software @2;
    custom @3;
}

struct UartConfig {
    baudRate @0 :UInt32;
    dataBits @1 :UInt8;
    stopBits @2 :UInt8;
    parity @3 :UartParity;
    flowControl @4 :UartFlowControl;
}

struct SerialDevice {
    port @0 :Text;
    irq @1 :UInt32;
    dmaChannel @2 :UInt32;
    uartConfig @3 :UartConfig;
    fifoDepth @4 :UInt32;
}

struct BootDiagnostic {
    stage @0 :BootStage;
    message @1 :Text;
    level @2 :T.LogLevel;
    timestamp @3 :T.Timestamp;
    # Duration of the operation being diagnosed.
    duration @4 :T.Duration;
}

struct BootState {
    # Currently active stage.
    currentStage @0 :BootStage;
    # All stages that have completed.
    completed @1 :List(BootStage);
    # All stages remaining.
    pending @2 :List(BootStage);
    # Total boot time so far.
    totalDuration @3 :T.Duration;
}

# Capability filter extension for boot - which authority level a stage holds.
struct BootAuthority {
    level @0 :AuthorityLevel;
    # Specific stage tokens available.
    stages @1 :List(BootStage);
}

enum AuthorityLevel {
    firmware @0;
    bootloader @1;
    kernel @2;
    init @3;
    userspace @4;
    custom @5;
}

enum BootCapability {
    readMemory @0;
    writeMemory @1;
    readStorage @2;
    writeStorage @3;
    executeCode @4;
    accessDevice @5;
    configureCompute @6;
    modifyBootArgs @7;
    networkAccess @8;
    custom @9;
}

# Boot service - observable boot-progress; lets apps know what's going on.
interface BootService {
    # Get the most-recent handoff artifact.
    handOff @0 () -> (manifest :BootManifest);
    # Get current boot state.
    state @1 () -> (state :BootState);
    # Subscribe to boot events.
    subscribe @2 () -> (subscription :BootSubscription);
    pull @3 (subscription :BootSubscription) -> (events :List(BootEvent));
    cancel @4 (subscription :BootSubscription) -> T.VoidResult;

    # Audit-9: verify the full attestation chain against a trust root.
    # Returns chain-of-trust verification result with per-item status.
    verifyAttestationChain @5 (chain :List(BootChainItem), trustRoot :Data)
                           -> (result :AttestationVerificationResult);

    # Audit-9: trigger a firmware update with integrity verification.
    firmwareUpdate @6 (request :FirmwareUpdateRequest) -> (result :FirmwareUpdateResult);

    # Audit-9: rollback firmware to a previous version.
    firmwareRollback @7 (targetVersion :Text) -> T.VoidResult;

    # Audit-9: manage network boot orchestration (DHCP→TFTP→iSCSI chain).
    configureNetworkBoot @8 (config :NetworkBootConfig) -> T.VoidResult;

    # Audit-9: enable a hardware device during boot.
    enableHardwareDevice @9 (deviceId :Text, driver :Text) -> T.VoidResult;

    # Audit-9: delegate capabilities from one boot stage to another.
    delegateCapability @10 (request :CapabilityDelegationRequest) -> T.VoidResult;
}

struct BootEvent {
    union {
        stageStarted @0 :BootManifest;
        stageFinished @1 :BootManifest;
        commFailed @2 :CommFailure;
        diagnosticsReady @3 :List(BootDiagnostic);
    }
}

struct CommFailure {
    stage @0 :BootStage;
    reason @1 :T.Error;
    retryHint @2 :T.Duration;
    recoveryAction @3 :RecoveryAction;
}

enum RecoveryAction {
    retry @0;
    skip @1;
    fallback @2;
    halt @3;
    custom @4;
}

interface BootSubscription {
    # Deprecated: use pullPaginated for bounded results.
    pull @0 () -> (events :List(BootEvent));
    cancel @1 () -> T.VoidResult;
    # Paginated pull — returns at most `limit` events starting from `offset`.
    pullPaginated @2 (pagination :T.Pagination) -> (result :BootPullResult);
}

struct BootPullResult {
    events    @0 :List(BootEvent);
    totalCount @1 :UInt32;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-7: Extended boot capabilities
#
# Boot attestation chain, boot analytics, multi-environment boot,
# failover chains, and boot policy. These extend the basic
# firmware-to-userspace model to support container, VM, embedded,
# and distributed boot scenarios.
# ═══════════════════════════════════════════════════════════════════════

# ── Boot Chain Attestation ────────────────────────────────────

struct BootChainItem {
    # Stage that produced this attestation.
    stage @0 :BootStage;
    # Cryptographic hash of the next stage's expected state.
    hash @1 :Data;
    # Algorithm used for the hash.
    algorithm @2 :TpmAlgorithm;
    # Timestamp of this attestation.
    timestamp @3 :T.Timestamp;
}

# ── Boot Stage Profile (analytics) ────────────────────────────

struct BootStageProfile {
    # Stage being profiled.
    stage @0 :BootStage;
    # Duration of this stage in the current boot.
    duration @1 :T.Duration;
    # Historical average duration (rolling window).
    averageDuration @2 :T.Duration;
    # Whether this stage exceeded its time budget.
    exceeded @3 :Bool;
    # CPU time consumed by this stage.
    cpuTime @4 :T.Duration;
    # Memory peak during this stage.
    memoryPeakBytes @5 :UInt64;
}

# ── Boot Environment ──────────────────────────────────────────

enum BootEnvironment {
    bareMetal @0;
    container @1;
    vm @2;
    wasm @3;
    embedded @4;
    hypervisor @5;
    custom @6;
}

# ── Boot Policy ───────────────────────────────────────────────

struct BootPolicy {
    # Stages that must complete for a successful boot.
    required @0 :List(BootStage);
    # Stages that are optional (failure does not block boot).
    optional @1 :List(BootStage);
    # Maximum total boot time before forced escalation.
    maxBootTime @2 :T.Duration;
}

# ── Failover Chain ────────────────────────────────────────────

struct FailoverChain {
    # Primary stage to attempt.
    primary @0 :BootStage;
    # Ordered list of fallback stages.
    fallbacks @1 :List(BootStage);
    # Maximum retries per stage before falling back.
    maxRetries @2 :UInt32;
}

# ── Boot Capability Request ───────────────────────────────────

struct BootCapabilityRequest {
    # Stage requesting the capability.
    stage @0 :BootStage;
    # Capabilities required from the previous stage.
    required @1 :List(BootCapability);
    # Capabilities that are nice-to-have.
    preferred @2 :List(BootCapability);
}

# ── A/B Partition Boot ────────────────────────────────────────

struct AbPartitionState {
    # Currently active boot slot ("a" or "b").
    activeSlot @0 :Text;
    # Boot attempt count for the active slot.
    bootAttempts @1 :UInt32;
    # Maximum boot attempts before fallback.
    maxBootAttempts @2 :UInt32;
    # Whether the slot has been marked successful.
    slotSuccessful @3 :Bool;
    # Last update timestamp.
    lastUpdate @4 :T.Timestamp;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-9: Extended boot capabilities
#
# Attestation chain verification, firmware update protocol, network boot
# orchestration, hardware enablement, and capability delegation.
# ═══════════════════════════════════════════════════════════════════════

# ── Attestation Verification ──────────────────────────────────

struct AttestationVerificationResult {
    # Whether the full chain is valid.
    valid @0 :Bool;
    # Per-item verification results.
    items @1 :List(AttestationItemResult);
    # Error if chain verification failed.
    error @2 :T.Error;
    # When verification was performed.
    verifiedAt @3 :T.Timestamp;
}

struct AttestationItemResult {
    stage @0 :BootStage;
    valid @1 :Bool;
    error @2 :T.Error;
}

# ── Firmware Update Protocol ──────────────────────────────────

struct FirmwareUpdateRequest {
    # Target firmware version.
    targetVersion @0 :Text;
    # Firmware image data or URI.
    imageUri @1 :T.Uri;
    # Expected hash of the firmware image.
    expectedHash @2 :Data;
    # Algorithm used for hash verification.
    hashAlgorithm @3 :TpmAlgorithm;
    # Whether to verify signature before applying.
    verifySignature @4 :Bool = true;
    # Maximum time to wait for the update.
    timeout @5 :T.Duration;
}

struct FirmwareUpdateResult {
    union {
        success @0 :FirmwareUpdateSuccess;
        failed @1 :T.Error;
        custom @2 :Data;
    }
}

struct FirmwareUpdateSuccess {
    # New firmware version after update.
    version @0 :Text;
    # When the update completed.
    completedAt @1 :T.Timestamp;
    # Whether a restart is required.
    requiresRestart @2 :Bool;
}

# ── Network Boot Orchestration ────────────────────────────────

struct NetworkBootConfig {
    # Ordered list of boot methods to try.
    methods @0 :List(NetworkBootMethod);
    # DHCP configuration (if applicable).
    dhcp @1 :DhcpConfig;
    # TFTP server configuration.
    tftp @2 :TftpConfig;
    # iSCSI configuration (if applicable).
    iscsi @3 :IscsiConfig;
    # Maximum retry attempts per method.
    maxRetries @4 :UInt32;
    # Timeout per boot method attempt.
    attemptTimeout @5 :T.Duration;
    # Failover policy on method failure.
    failoverPolicy @6 :NetworkBootFailoverPolicy;
}

struct DhcpConfig {
    # Interface to use for DHCP.
    interface @0 :Text;
    # Requested IP address (optional).
    requestedIp @1 :Text;
    # Vendor class identifier.
    vendorClass @2 :Text;
}

struct TftpConfig {
    # TFTP server address.
    server @0 :Text;
    # Boot file path on TFTP server.
    bootFile @1 :Text;
    # Block size for TFTP transfers.
    blockSize @2 :UInt32;
}

struct IscsiConfig {
    # iSCSI target address.
    targetAddress @0 :Text;
    # iSCSI target name.
    targetName @1 :Text;
    # iSCSI initiator name.
    initiatorName @2 :Text;
    # LUN number.
    lun @3 :UInt32;
}

enum NetworkBootFailoverPolicy {
    # Try next method in sequence.
    sequential @0;
    # Try all methods in parallel, use first success.
    parallel @1;
    # Stop on first failure.
    strict @2;
    custom @3;
}

# ── Capability Delegation Chain ───────────────────────────────

struct CapabilityDelegationRequest {
    # Source stage that holds the capability.
    sourceStage @0 :BootStage;
    # Target stage to receive the capability.
    targetStage @1 :BootStage;
    # Capabilities to delegate.
    capabilities @2 :List(BootCapability);
    # Subset of capabilities to delegate (if delegating a subset).
    subset @3 :List(BootCapability);
    # Expiry for the delegation.
    expiry @4 :T.Duration;
    # Whether the target can further delegate.
    transitive @5 :Bool;
}

# ═══════════════════════════════════════════════════════════════════════
# Boot-Agnostic Additions
#
# These additions enable:
# - Multiple bootloader support
# - Boot protocol detection (not hardcoded to one protocol)
# - Kernel selection at boot time (runtime + compile-time)
# - Binary format typing for cross-language kernel loading
# ═══════════════════════════════════════════════════════════════════════

# ── Boot Protocol Detection ───────────────────────────────────
# The kernel detects WHICH protocol delivered the boot, not which
# specific bootloader binary. This is the agnostic layer.

enum BootProtocolKind {
    limine @0;
    multibootV1 @1;
    multibootV2 @2;
    uefi @3;
    deviceTree @4;
    openBoot @5;
    custom @6;
}

struct BootProtocolInfo {
    kind @0 :BootProtocolKind;
    version @1 :Text;
    # Protocol-specific magic value (e.g., 0x2BADB002 for Multiboot1).
    magicValue @2 :UInt64;
    # Physical address of the response struct (protocol-specific).
    responseAddr @3 :UInt64;
    # Physical address of the request struct (if applicable).
    requestAddr @4 :UInt64;
}

# ── Kernel Selection (Boot-Time Polymorphism) ─────────────────
# Enables runtime kernel selection via boot menu.
# Kernels show up in boot menu, selectable at runtime.

struct KernelSelection {
    # The kernel envelope type (from kernel.capnp).
    envelope @0 :K.KernelType;
    # Unique identifier for this kernel implementation.
    implementationId @1 :Text;
    # Binary format of the kernel (ELF, PE, WASM, etc.).
    binaryFormat @2 :T.BinaryFormat;
    # Offset of the entry point from the binary base.
    entryPointOffset @3 :UInt64;
    # ABI version this kernel conforms to.
    abiVersion @4 :T.Version;
    # Human-readable name for boot menu display.
    displayName @5 :Text;
    # Architecture this kernel targets.
    architecture @6 :Text;
}

# ── Bootloader Implementation Info ────────────────────────────
# Identifies which specific bootloader produced this manifest.
# Used for debugging and bootloader-specific features.

struct BootloaderImplementation {
    # Bootloader name (e.g., "cyberspace-boot", "helenos-boot").
    name @0 :Text;
    # Version string.
    version @1 :Text;
    # Source repository URL.
    sourceRepository @2 :Text;
    # Git commit hash (20 bytes).
    commitHash @3 :Data;
    # Build artifact hash (SHA-256).
    buildId @4 :Data;
    # Target triple (e.g., "x86_64-unknown-none").
    targetTriple @5 :Text;
}

# ── Boot Origin ───────────────────────────────────────────────
# How this boot stage was initiated.

enum BootOrigin {
    firmwareDirect @0;     # Firmware handed control directly to kernel
    bootloaderLoaded @1;   # Bootloader loaded kernel (current model)
    chainload @2;          # Bootloader A loaded us via bootloader B
    networkBoot @3;        # PXE/iPXE/HTTP boot
    recursiveBoot @4;      # This stage is itself in a chainload
    custom @5;
}

# ── Boot Chain (Multi-Stage Handoff) ─────────────────────────
# Supports multi-stage: firmware -> bootloader -> kernel-1 -> kernel-2

struct BootChainEntry {
    stage @0 :BootStage;
    bootloader @1 :BootloaderImplementation;
    kernel @2 :KernelSelection;
    # Pointer to this stage's manifest (physical address).
    manifestAddr @3 :UInt64;
    # Index of next entry in the chain, or 0xFFFFFFFF if last.
    nextChainEntry @4 :UInt32;
}

struct BootChain {
    entries @0 :List(BootChainEntry);
    # Index of the current entry in the chain.
    currentIndex @1 :UInt32;
}

# ── Handoff Resources (Kernel-Swap Support) ──────────────────
# When kernel-2 boots after kernel-1 was swapped out, it needs:
# - Memory map kernel-1 left behind
# - IO devices kernel-1 was using
# - Persistent state (filesystem, network)
# - Capability tokens passed through

struct BootHandoffResources {
    # Memory ranges released by previous kernel.
    memoryReleased @0 :List(MemoryRange);
    # IO devices transferred from previous kernel.
    ioTransferred @1 :List(HardwareDevice);
    # Handles to persistent state (filesystem, network).
    persistentStateHandles @2 :List(UInt64);
    # Capabilities passed through from previous kernel.
    capabilitiesPassed @3 :List(BootCapability);
}

# ── Boot Handoff ──────────────────────────────────────────────
# The schema takes ownership of every memory handoff.
# 24 bytes at a well-known address, then everything is capnp.

struct HandoffPointer {
    # 0x534D4152545F5052 = "SMART_PR" (truncated to fit UInt64).
    magic        @0 :UInt64;
    # Virtual address of the BootHandoff capnp message (kernel pre-maps it).
    handoffAddr  @1 :UInt64;
    handoffBytes @2 :UInt64;
}

struct BootHandoff {
    abiVersion       @0 :T.Version;
    producer         @1 :BootStage;
    entryContext     @2 :T.EntryContext;
    manifest         @3 :BootManifest;
    serviceEndpoints @4 :List(ServiceEndpoint);
    channels         @5 :List(ChannelInfo);
    images           @6 :List(BootImage);
    # Virtual address of the kernel's handler table. Services write their
    # dispatch fn pointer here at their channel slot index.
    handlerTableVaddr @7 :UInt64;
}

struct Module {
    name @0 :Text;
    data @1 :Data;
    hash @2 :Data;
}

struct ChannelInfo {
    requestArenaVaddr @0 :UInt64;
    requestArenaSize @1 :UInt32;
    replyArenaVaddr @2 :UInt64;
    replyArenaSize @3 :UInt32;
    # Virtual address of the request doorbell (caller bumps to signal arrival).
    requestDoorbellVaddr @4 :UInt64;
    # Virtual address of the reply doorbell (service bumps after writing reply).
    replyDoorbellVaddr @5 :UInt64;
}

struct ServiceEndpoint {
    name @0 :Text;
    serviceId @1 :T.ServiceId;
    mappedBase @2 :UInt64;
    doorbell @3 :T.CapabilityHandle;
    # Index into the channels list (0 = kernel, 1..N = services).
    channelSlot @4 :UInt32;
}

struct LoadSegment {
    offset @0 :UInt64;
    virtualAddress @1 :UInt64;
    sizeBytes @2 :UInt64;
    bssBytes @3 :UInt64;
    perms @4 :List(T.MemoryPerms);
    align @5 :UInt32;
}

struct BootImage {
    name @0 :Text;
    format @1 :T.BinaryFormat;
    entryOffset @2 :UInt64;
    linkAddress @3 :UInt64;
    stackBytes @4 :UInt64;
    segments @5 :List(LoadSegment);
    hash @6 :Data;
    signature @7 :Data;
}

struct BootstrapInfo {
    channelCount @0 :UInt32;
    channels @1 :List(ChannelInfo);
    # Optional HHDM offset for services that need physical-to-virtual
    # translation. # note recommended: leave empty; kernel pre-maps all
    # needed regions and provides vaddrs via ChannelInfo. Only populate
    # when a service has a genuine need not covered by the schema.
  #  hhdmOffset @2 :UInt64;
}

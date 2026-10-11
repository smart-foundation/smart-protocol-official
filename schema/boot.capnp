@0xa1b2c3d4e5f6003a;

# ═══════════════════════════════════════════════════════════════════════
# Boot — the handoff from bootloader to OS, and OS to apps.
#
# ── THE FOUNDER'S DESIGN DIRECTIVE ─────────────────────────────────────
#
#   The bootloader contract must be TRIVIAL. The bootloader's ONLY job is
#   to place typed capnp data at ONE well-known pointer. No HHDM, no
#   handoff math, no old-paradigm orchestration. Abstracting is the
#   winner: a person writing an operating system should be able to write
#   a bootloader for this protocol without learning the machine.
#
# What that means concretely, and what this schema therefore contains:
#
#   1. ONE well-known pointer. `HandoffPointer` — 24 bytes at a fixed
#      address — points at a `BootHandoff` capnp message. That message
#      carries the `BootManifest`. Everything else in this file is either
#      in that chain or is the configuration plane a running system uses
#      to talk about boot. There is no second handoff mechanism and no
#      raw function-pointer table: the pre-revamp
#      `BootHandoff.handlerTableVaddr` (services writing dispatch
#      pointers into a table by slot index) is DELETED. Channels and
#      `ServiceEndpoint` replace it.
#
#   2. The manifest is DECLARATIVE. It describes what was handed over:
#      memory regions with opaque kind/flags, modules as opaque regions,
#      the kernel-selection menu, an optional framebuffer handle, and
#      args as a string map. It does not compute anything: no physical
#      address arithmetic, no page-table concepts, no hhdmOffset
#      anywhere. A region's base is reported, never derived.
#
#   3. No technology museum. The pre-revamp file named 2026 storage
#      buses, bootloaders, firmware, partition tables, initrd
#      compression formats, UART parity, ACPI/SMBIOS/DMI table layouts
#      and CPU feature sets — every one a frozen commitment. All of it is
#      gone. What survives is either an opaque handle to the bytes
#      (`T.DataHandle`) or an open token the backend declares
#      (`T.StringMap` / `Text`). A 2046 bootloader satisfies this
#      contract unmodified, which is the Swap Test the doctrine claims
#      this file already passed.
#
#   4. Hardware bring-up is not boot's job. Bus enumeration, device
#      discovery and hardware description belong to hal.capnp and
#      device.capnp. This manifest says what memory and which images it
#      received; it does not catalogue the machine.
#
# ── THE BOOTSTRAP CAPABILITY ───────────────────────────────────────────
#
# The ONLY well-known capability: handle 1 in every process's capability
# table is `KernelService`. The kernel MUST place it there before
# entering userspace. Every other capability is dynamic — issued by
# capability.capnp's `CapabilityService.issue` and delegated with
# `attenuate` + `transfer`. There is no boot capability enum and no
# delegation method here; both were pre-revamp second authority
# grammars.
#
# Authority, everywhere in this file, is the interface reference: the
# `BootService` reference is granted once, at acquisition, and each of
# its methods takes no authority token (R3, ai.capnp precedent).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using K = import "kernel.capnp";

# ── The one well-known pointer ─────────────────────────────────────────
# 24 bytes at a fixed address, then everything is capnp. The magic is
# "SMART_PR" truncated to fit a UInt64. `handoffAddr` is a VIRTUAL address
# the kernel pre-maps, so no stage ever performs address translation.

struct HandoffPointer {
    magic        @0 :UInt64;
    handoffAddr  @1 :UInt64;
    handoffBytes @2 :UInt64;
}

# The capnp message the well-known pointer resolves to.
struct BootHandoff {
    abiVersion       @0 :T.Version;
    producer         @1 :BootStage;
    entryContext     @2 :T.EntryContext;
    manifest         @3 :BootManifest;
    serviceEndpoints @4 :List(HandoffEndpoint);
    channels         @5 :List(ChannelInfo);
    images           @6 :List(BootImage);
    # Modules as opaque regions (see Module): bytes already mapped, never
    # copied into the message.
    modules          @7 :List(Module);
}

# ── The manifest ───────────────────────────────────────────────────────
# Purely declarative. Everything optional is optional because a minimal
# boot is minimal: a stage that has one memory region, one image and no
# args is fully described.

struct BootManifest {
    # Identifier of the producing stage.
    producer @0 :BootStage;
    # Identifier of the intended next stage.
    nextStage @1 :BootStage;
    # Time the producer started / the handoff fired / how long it took.
    startedAt @2 :T.Timestamp;
    finishedAt @3 :T.Timestamp;
    duration @4 :T.Duration;

    # Memory plan the next stage inherits. `kind` is an OPEN token
    # ("ram", "mmio", "reserved", "persistent", or a 2046 kind); the
    # pre-revamp 12-value `MemoryKind` enum named today's taxonomy and
    # forced a 2046 backend to extend an eternal contract. `base` is
    # reported, never derived — the protocol performs no address
    # arithmetic and prescribes no translation.
    memory @5 :List(MemoryRegion);

    # Boot arguments: kernel command line, environment, and anything else
    # the producer must pass. Open keys, unknown ones ignored.
    args @6 :T.StringMap;

    # Optional initrd / initial filesystem blob. Inline for small
    # payloads, a reference for anything larger (R2).
    initrd @7 :BootBlob;

    # Negotiated log level.
    logLevel @8 :T.LogLevel;

    # The boot-time kernel menu: every envelope this boot can hand control
    # to, which one was selected, and why.
    kernels @9 :KernelSelectionSet;

    # Optional framebuffer handed over by the bootloader, as a HANDLE.
    # Mode and pixel format are queried from the framebuffer contract —
    # the manifest does not carry a physical address for it.
    framebuffer @10 :T.FramebufferId;

    # A long-lived BootService peer channel (request/response). The next
    # stage calls methods on it, never a side-channel API.
    bootService @11 :BootService;

    # IPC channels mapped to userspace-accessible shared memory.
    channels @12 :List(IpcChannel);

    # All userland images the bootloader handed us.
    images @13 :List(BootImage);

    # Modules: opaque regions, never inline bytes.
    modules @14 :List(Module);

    # Isolation boundaries declared at boot.
    isolationManifest @15 :List(T.IsolatedScope);

    # The bootstrap capability. The kernel places KernelService at handle
    # 1 in every process before entering userspace, so init and every
    # later stage can immediately call the kernel contract.
    kernelService @16 :K.KernelService;

    # Measured per-stage timings, reported. Declarative: no history, no
    # analytics, no optimisation target.
    timings @17 :List(StageTiming);

    # Anything else the producer must say, as open metadata.
    metadata @18 :T.StringMap;
}

struct StageTiming {
    stage @0 :BootStage;
    duration @1 :T.Duration;
    startedAt @2 :T.Timestamp;
}

# The stage chain. `custom` covers a 2046 stage (payload verification, a
# firmware second phase) without extending an eternal enum.
enum BootStage {
    firmware @0;
    bootloader @1;
    kernel @2;
    init @3;
    userspace @4;
    custom @5;
}

struct MemoryRegion {
    # Open kind token: "ram", "rom", "mmio", "reserved", "persistent",
    # "unusable", or a kind invented after this schema was frozen.
    kind @0 :Text;
    # Where the region is, as the producer sees it. The protocol never
    # computes with it.
    base @1 :UInt64;
    length @2 :UInt64;
    # Typed page attributes (canonical).
    flags @3 :T.PageFlags;
    # Open metadata the producer wants to attach.
    metadata @4 :T.StringMap;
}

# ── Blobs ──────────────────────────────────────────────────────────────
# The inline/reference union is the correct R2 shape: a small payload
# rides inline, a large one is a handle. Small stays cheap, large stays
# zero-copy.

struct BootBlob {
    union {
        inline @0 :Data;
        reference @1 :BootBlobRef;
        unknown @2 :T.UnknownEvent;
    }
    # Metadata about the blob: format and hash as open tokens, never an
    # enum of today's container formats.
    metadata @3 :BootBlobMetadata;
}

struct BootBlobRef {
    handle @0 :UInt64;
    sizeBytes @1 :UInt64;
    hash @2 :Data;
    # Open format token ("cpio.gz", "erofs", "squashfs", or a 2046 one).
    format @3 :Text;
}

struct BootBlobMetadata {
    # Open format token, as above.
    format @0 :Text;
    compression @1 :Text;
    sizeBytes @2 :UInt64;
    hash @3 :Data;
    # Module names contained in the blob, if the producer knows them.
    moduleNames @4 :List(Text);
}

# A module is an opaque region the producer already mapped: address,
# length, hash. No module blob is ever copied into a message.
struct Module {
    name @0 :Text;
    vaddr @1 :UInt64;
    size @2 :UInt64;
    hash @3 :Data;
    metadata @4 :T.StringMap;
}

# ── Kernel selection ───────────────────────────────────────────────────
# Selection as DATA, not as a string in a build script. Every envelope
# this boot can hand control to, in menu order, plus which one was chosen
# and how that choice came about.
#
# The honesty pair is `selectedIndex` + `selectedPresent`: a manifest that
# lists one envelope and selects nothing is telling the truth ("no choice
# was made"); one that selects index 0 of 1 claims a decision that was
# never taken. Both are representable, which is the point.

struct KernelSelectionSet {
    # Every envelope this boot can hand control to, in menu order.
    available @0 :List(KernelSelection);
    # Index into `available` of the envelope control was actually passed
    # to. Meaningful only when `selectedPresent` is true.
    selectedIndex @1 :UInt32;
    selectedPresent @2 :Bool;
    # Index the boot flow would have chosen with no user input. Differs
    # from selectedIndex whenever a human or supervisor overrode it, and
    # "the default was overridden" is worth knowing.
    defaultIndex @3 :UInt32;
    defaultPresent @4 :Bool;
    # Why the selection came out as it did, for the boot log. Empty is
    # not acceptable for an override: record the source, so a boot that
    # entered an unexpected kernel can be explained afterwards.
    selectedBy @5 :KernelSelectionSource;
    metadata @6 :T.StringMap;
}

enum KernelSelectionSource {
    # Nothing selected: single-envelope boot, control fell through. The
    # common case on a normal boot, and it is stated, not implied.
    fallthrough @0;
    # The default entry of `available`, applied without user input.
    defaultEntry @1;
    # A human chose from the boot menu.
    interactiveMenu @2;
    # A supervisor, hypervisor or configuration chose it.
    externalRequest @3;
    # Previous boot failed; this was a failover.
    failover @4;
    custom @5;
}

# One selectable kernel. `implementationId` is opaque; the format,
# architecture and ABI are open tokens / typed versions — a kernel
# paradigm that does not exist yet needs no ordinal here.
struct KernelSelection {
    implementationId @0 :Text;
    # Open binary-format token ("elf", "pe", "wasm", or a 2046 one).
    binaryFormat @1 :Text;
    # ABI version this kernel conforms to.
    abiVersion @2 :T.Version;
    # Human-readable name for boot menu display.
    displayName @3 :Text;
    # Architecture as an open token ("x86_64", "aarch64", "riscv64", …).
    architecture @4 :Text;
    # Open metadata: anything else the boot menu wants to show.
}

# ── Images ─────────────────────────────────────────────────────────────
# Declarative image description. `virtualAddress`/`linkAddress` are
# addresses in the image's OWN address space, assigned by the loader —
# they are not machine addresses and the protocol performs no arithmetic
# on them.

struct BootImage {
    name @0 :Text;
    # Open binary-format token.
    format @1 :Text;
    entryOffset @2 :UInt64;
    linkAddress @3 :UInt64;
    stackBytes @4 :UInt64;
    segments @5 :List(LoadSegment);
    hash @6 :Data;
    signature @7 :Data;
    metadata @8 :T.StringMap;
}

struct LoadSegment {
    offset @0 :UInt64;
    virtualAddress @1 :UInt64;
    sizeBytes @2 :UInt64;
    bssBytes @3 :UInt64;
    perms @4 :List(T.MemoryPerms);
    align @5 :UInt32;
}

# ── Channels and endpoints ─────────────────────────────────────────────
# Shared-memory arenas with doorbells: the zero-copy path. This is the
# mechanism that replaced the raw handler table.

struct IpcChannel {
    requestArenaVaddr @0 :UInt64;
    requestArenaSize @1 :UInt32;
    replyArenaVaddr @2 :UInt64;
    replyArenaSize @3 :UInt32;
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

struct HandoffEndpoint {
    name @0 :Text;
    serviceId @1 :T.ServiceId;
    mappedBase @2 :UInt64;
    doorbell @3 :T.CapabilityHandle;
    # Index into the channels list (0 = kernel, 1..N = services).
    channelSlot @4 :UInt32;
    metadata @5 :T.StringMap;
}

# ── Boot service ───────────────────────────────────────────────────────
# TWO surfaces, one interface:
#
#   * the configuration plane — how a running system reads and changes
#     what the next boot will do. This is the live variant of the
#     pre-revamp interface: it reports what the firmware and bootloader
#     actually handed over, and it never fabricates a value.
#   * the handoff core — reading back the artifact this boot produced,
#     and observing stages as they complete.
#
# DELETED from the pre-revamp `BootService`, with where each went:
#   firmwareUpdate / firmwareRollback / configureNetworkBoot — the update
#   domain (they configure a future boot, not this one).
#   enableHardwareDevice (deviceId, driver :Text) — hardware bring-up is
#   hal/device's job; a driver named as free text is an authority-by-name
#   path with no verification.
#   delegateCapability — capability delegation is capability.capnp's
#   `attenuate` + `transfer`; boot had no way to enforce it.
#   verifyAttestationChain STAYS, capability-gated at acquisition: the
#   caller already holds this reference, so no token is passed per call.

interface BootService {
    # ── Configuration plane ──────────────────────────────────────
    # Get the current boot information (firmware, bootloader, timing, arch).
    getInfo @0 () -> (info :BootInfo);

    # Get boot parameters (timeout, menu, quiet/debug flags, cmdline).
    getParameters @1 () -> (params :BootParameters);

    # Set boot parameters (applied on the next boot).
    setParameters @2 (params :BootParameters) -> T.VoidResult;

    # List boot entries (OS/kernel options).
    listEntries @3 () -> (entries :List(BootEntry));

    # Get the default boot entry.
    getDefaultEntry @4 () -> (entry :BootEntry);

    # Set the default boot entry, by opaque id.
    setDefaultEntry @5 (entryId :T.BootEntryId) -> T.VoidResult;

    # Set the boot entry for the next boot only (one-shot).
    setNextBootEntry @6 (entryId :T.BootEntryId) -> T.VoidResult;

    # Get boot log, filtered.
    getBootLog @7 (filter :BootLogFilter) -> (entries :List(BootLogEntry), total :UInt32);

    # Get boot splash configuration.
    getSplashConfig @8 () -> (config :BootSplashConfig);

    # Set boot splash configuration.
    setSplashConfig @9 (config :BootSplashConfig) -> T.VoidResult;

    # Enable/disable recovery mode on the next boot.
    setRecoveryMode @10 (enable :Bool) -> T.VoidResult;

    # Get recovery mode status.
    getRecoveryMode @11 () -> (enabled :Bool, reason :Text);

    # Get secure boot status.
    getSecureBoot @12 () -> (status :SecureBootStatus);

    # List secure boot keys.
    listSecureBootKeys @13 () -> (keys :List(SecureBootKey));

    # Get boot attempt counters (for A/B slot rotation).
    getBootAttempts @14 () -> (attempts :BootAttempts);

    # Mark the current boot as successful (resets the A/B attempt counter).
    markBootSuccessful @15 () -> T.VoidResult;

    # Subscribe to boot events. Holding the subscription IS the authority
    # to pull; there is no subscription id to present.
    subscribe @16 () -> (subscription :BootSubscription);

    # ── Handoff core ────────────────────────────────────────────
    # Get the most-recent handoff artifact.
    handOff @17 () -> (manifest :BootManifest);

    # Get current boot state, including the failures this boot recorded.
    state @18 () -> (state :BootState);

    # Verify the full attestation chain against a trust root. Authority is
    # the reference held by the caller (R3).
    verifyAttestationChain @19 (chain :List(BootChainItem), trustRoot :T.DataHandle)
                           -> (result :AttestationVerificationResult);
}

# ── Configuration-plane data ───────────────────────────────────────────

struct BootInfo {
    # Unique boot identifier, derived from the manifest's startedAt
    # timestamp — stable and unique per physical boot, needs no extra
    # kernel field.
    bootId @0 :UInt64;
    # How we got here, as an open token ("efi", "bios", "coreboot",
    # "uboot", or a 2046 mechanism). The pre-revamp `BootMethod` enum
    # named today's five firmware paths.
    method @1 :Text;
    # Firmware identity as an open token plus a verbatim version string.
    firmware @2 :Text;
    firmwareVersion @3 :Text;
    # Bootloader name and version, verbatim from the manifest.
    bootloader @4 :Text;
    bootloaderVersion @5 :Text;
    # Kernel command line, from the manifest args.
    kernelCommandLine @6 :Text;
    # Firmware start → userspace ready.
    bootDuration @7 :T.Duration;
    # Whether this was a cold boot.
    coldBoot @8 :Bool;
    # Target architecture, as an open token.
    architecture @9 :Text;
    # Whatever else the backend chooses to report.
    metadata @10 :T.StringMap;
}

struct BootParameters {
    # Kernel command line arguments.
    kernelArgs @0 :List(Text);
    # How long the menu waits. Zero = do not show a menu. A duration, not
    # a signed sentinel: "negative means wait forever" is a trap.
    menuTimeout @1 :T.Duration;
    # Default entry, by opaque id (zero = none).
    defaultEntry @2 :T.BootEntryId;
    # One-shot next entry, by opaque id (zero = none).
    nextEntry @3 :T.BootEntryId;
    # Whether graphical boot is used.
    graphicalBoot @4 :Bool;
    # Whether verbose/debug boot output is enabled.
    debugMode @5 :Bool;
    # Whether quiet boot is enabled.
    quietMode @6 :Bool;
    # Open parameters the backend understands and the protocol does not
    # need to name.
    custom @7 :T.StringMap;
}

struct BootEntry {
    id @0 :T.BootEntryId;
    title @1 :Text;
    description @2 :Text;
    # Opaque reference to the kernel envelope in the manifest's
    # KernelSelectionSet. The protocol does not interpret it.
    kernelRef @3 :Text;
    # Initrd reference, as an open token in the bootloader's own
    # vocabulary (never a path the protocol resolves).
    initrdRef @4 :Text;
    # Kernel command line for this entry.
    kernelArgs @5 :List(Text);
    # Architecture, as an open token.
    architecture @6 :Text;
    # Whether this entry is bootable.
    bootable @7 :Bool;
    # Whether this is a recovery entry.
    recovery @8 :Bool;
    # Last boot time / whether the last boot of this entry succeeded.
    lastBooted @9 :T.Timestamp;
    lastBootSuccess @10 :Bool;
    # Open metadata.
    metadata @11 :T.StringMap;
}

struct BootLogEntry {
    timestamp @0 :T.Timestamp;
    # Which stage the entry occurred in.
    stage @1 :BootStage;
    # Severity (shared T.LogLevel).
    level @2 :T.LogLevel;
    subsystem @3 :Text;
    message @4 :Text;
    duration @5 :T.Duration;
    metadata @6 :T.StringMap;
}

struct BootLogFilter {
    stages @0 :List(BootStage);
    levels @1 :List(T.LogLevel);
    subsystems @2 :List(Text);
    since @3 :T.Timestamp;
    # Plain substring match. Not a query language.
    pattern @4 :Text;
    # Bound on the number of entries returned (zero = backend default,
    # which MUST still be bounded).
    limit @5 :UInt32;
    metadata @6 :T.StringMap;
}

struct BootSplashConfig {
    enabled @0 :Bool;
    theme @1 :Text;
    # Colours and image references as open tokens in the backend's own
    # vocabulary (a colour space, a URI, whatever the backend resolves).
    backgroundColor @2 :Text;
    logoRef @3 :Text;
    # Progress-bar style as an open token ("none", "line", "blocks", …).
    # The pre-revamp `SplashProgressBar` enum froze today's four styles.
    progressBar @4 :Text;
    backgroundImageRef @5 :Text;
    custom @6 :T.StringMap;
}

# Secure boot status reported verbatim from the manifest's SecureBootState.
# The TPM version is an OPEN token: the pre-revamp `TpmVersion`
# {tpm12, tpm20} enum could not name a TPM 3.0, let alone whatever
# replaces TPMs.
struct SecureBootStatus {
    enabled @0 :Bool;
    # Whether the boot chain was verified.
    verified @1 :Bool;
    # Signing key database status text.
    keyDatabaseStatus @2 :Text;
    # TPM identity as an open token ("tpm12", "tpm20", …).
    tpmVersion @3 :Text;
    # Measured PCR values, if any. Algorithm per measurement is open.
    pcrMeasurements @4 :List(PcrMeasurement);
    # Open metadata.
    metadata @5 :T.StringMap;
}

struct SecureBootKey {
    id @0 :T.KeyId;
    # Key type as an open token ("pk", "kek", "db", "dbx", or a 2046 one).
    keyType @1 :Text;
    # Owner of the key.
    owner @2 :Text;
    # Fingerprint of the key, for out-of-band identification.
    fingerprint @3 :T.KeyFingerprint;
    validFrom @4 :T.Timestamp;
    validTo @5 :T.Timestamp;
    metadata @6 :T.StringMap;
}

# A/B boot attempt counters, reported verbatim from the manifest.
struct BootAttempts {
    # Current attempt count for the active slot.
    current @0 :UInt32;
    # Maximum attempts before fallback.
    max @1 :UInt32;
    # Whether the active slot is marked successful.
    successful @2 :Bool;
    # Last successful boot time.
    lastSuccessful @3 :T.Timestamp;
    # Which slot is active, as an open token ("a", "b", or a 2046 scheme).
    activeSlot @4 :Text;
    metadata @5 :T.StringMap;
}

# ── Secure boot / attestation data ─────────────────────────────────────
# The protocol keeps the DATA and refuses to freeze the ALGORITHMS: every
# algorithm field is an open token, every digest stays opaque bytes.

struct SecureBootState {
    enabled @0 :Bool;
    # Whether the boot chain was verified.
    verified @1 :Bool;
    # TPM PCR measurements, if available.
    pcrMeasurements @2 :List(PcrMeasurement);
    # Signing key database status.
    keyDatabaseStatus @3 :Text;
    # TPM identity as an open token.
    tpmVersion @4 :Text;
    # Attestation quote, if available (opaque; algorithm is open).
    attestation @5 :AttestationQuote;
    # Trust-chain items measured by each stage.
    chainItems @6 :List(BootChainItem);
    # Open metadata: what the backend chose to report.
}

struct PcrMeasurement {
    index @0 :UInt32;
    # Open algorithm token ("sha1", "sha256", "sha384", or a post-quantum
    # digest). The pre-revamp `TpmAlgorithm` enum ended at sha-512.
    algorithm @1 :Text;
    digest @2 :Data;
}

struct AttestationQuote {
    # Open algorithm token for the quote.
    algorithm @0 :Text;
    # The quote itself, zero-copy. Never parsed here.
    quote @1 :T.DataHandle;
    # Which PCRs the quote covers: a bitmask, bit i set = PCR i selected.
    # One word instead of a list, because a selection is a set.
    pcrSelectionMask @2 :UInt64;
    timestamp @3 :T.Timestamp;
    metadata @4 :T.StringMap;
}

struct BootChainItem {
    # Stage that produced this attestation.
    stage @0 :BootStage;
    # Cryptographic hash of the next stage's expected state.
    hash @1 :Data;
    # Open algorithm token.
    algorithm @2 :Text;
    timestamp @3 :T.Timestamp;
}

struct AttestationVerificationResult {
    # Whether the full chain is valid.
    valid @0 :Bool;
    # Per-item verification results.
    items @1 :List(AttestationItemResult);
    # Error if chain verification failed.
    error @2 :T.Error;
    # When verification was performed.
    verifiedAt @3 :T.Timestamp;
    # Open metadata: which trust root, which verifier, what was skipped.
}

struct AttestationItemResult {
    stage @0 :BootStage;
    valid @1 :Bool;
    error @2 :T.Error;
}

# ── Boot state and events ──────────────────────────────────────────────
# A failed stage is REPORTED, not inferred: the producer records a
# CommFailure in BootState.failures and emits it as a BootEvent, so a
# consumer learns the boot degraded instead of guessing from a stage that
# never completed. (This was the pre-revamp gap: `FailoverChain` named
# fallbacks and nothing said when they engage.)

struct BootState {
    # Currently active stage.
    currentStage @0 :BootStage;
    # All stages that have completed.
    completed @1 :List(BootStage);
    # All stages remaining.
    pending @2 :List(BootStage);
    # Total boot time so far.
    totalDuration @3 :T.Duration;
    # Failures recorded during this boot, in order. Empty means none.
    failures @4 :List(CommFailure);
}

struct BootEvent {
    union {
        stageStarted @0 :BootManifest;
        stageFinished @1 :BootManifest;
        commFailed @2 :CommFailure;
        diagnosticsReady @3 :List(BootDiagnostic);
        unknown @4 :T.UnknownEvent;
    }
}

struct CommFailure {
    stage @0 :BootStage;
    reason @1 :T.Error;
    retryHint @2 :T.Duration;
    # Canonical recovery vocabulary (types.capnp), not a local copy.
    recoveryAction @3 :T.RecoveryAction;
}

struct BootDiagnostic {
    stage @0 :BootStage;
    message @1 :Text;
    level @2 :T.LogLevel;
    timestamp @3 :T.Timestamp;
    # Duration of the operation being diagnosed.
    duration @4 :T.Duration;
}

interface BootSubscription {
    # Bounded pull: the caller states how many events it will take, so a
    # registration burst cannot flood one message.
    pull @0 (maxEvents :UInt32) -> (events :List(BootEvent));
    cancel @1 () -> T.VoidResult;
}

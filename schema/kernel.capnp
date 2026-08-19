@0xa1b2c3d4e5f60039;

# ═══════════════════════════════════════════════════════════════════════
# Kernel - universal kernel boundaries exposed to apps
#
# Defines what apps observe and demand of an OS kernel. The kernel is
# always backend-agnostic. A microkernel, a monolithic kernel, an exokernel,
# a sandbox runtime, a distributed-actor scheduler - any of them can satisfy
# these contracts by implementation. Smart-protocol is timeless; backends
# may change.
#
# This schema describes the EXTERNAL interface apps see. Internal kernel
# machinery (scheduling algorithm, page-table structures, ring isolation,
# interrupt dispatch) belongs to the backend, not the protocol.
#
# Improvements (audit-4):
#   - Removed local SignalKind enum; Signal.kind now uses T.SignalKind
#     from types.capnp directly (Rule 2: shared type, no duplication).
#     T.SignalKind includes child/stop/continue added in Batch 10.
#
# Improvements (audit-5):
#   - TaskFilter.name changed from bare Text to T.TaskName (Rule 2).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using B = import "boot.capnp";
using import "capability.capnp".Operation;
using import "capability.capnp".CapabilityService;

struct TaskInfo {
    id @0 :T.ProcessId;
    parent @1 :T.ProcessId;
    name @2 :Text;
    label @3 :Text;
    state @4 :TaskState;
    priority @5 :Int8;
    capabilities @6 :List(CapId);
    children @7 :List(T.ProcessId);
    createdAt @8 :T.Timestamp;
    lastScheduled @9 :T.Timestamp;
    cpuTime @10 :T.Duration;
    memoryBytes @11 :UInt64;
}

struct CapId {
    # Reference to a capability held by container of this task.
    # Wire format is UInt64 (T.CapabilityHandle); the schema enforces type safety.
    id @0 :T.CapabilityHandle;
}

enum TaskState {
    # Created, not yet run.
    newBorn @0;
    # Ready to run but not scheduled yet.
    ready @1;
    # Currently running on a compute unit.
    running @2;
    # Blocked on a resource or channel.
    waiting @3;
    # Suspended by signal.
    stopped @4;
    # Finished, awaiting cleanup.
    terminated @5;
    # Zombie: exited, awaiting parent reaping.
    zombie @6;
    custom @7;
}

struct RegionSpec {
    # Requested base address (zero = backend picks).
    base @0 :UInt64;
    # Length in bytes.
    length @1 :UInt64;
    # Permissions requested.
    perms @2 :T.MemoryPerms;
    # Optional backing-storage target id.
    backing @3 :UInt64;
    # Optional name (debugging).
    label @4 :Text;
    # Optional alignment (must be power of two, zero = default).
    alignment @5 :UInt32;
}

struct RegionInfo {
    base @0 :UInt64;
    length @1 :UInt64;
    perms @2 :T.MemoryPerms;
    label @3 :Text;
    backing @4 :UInt64;
    sharedWith @5 :List(T.ProcessId);
}

enum WaitResult {
    signalled @0;
    timedOut @1;
    cancelled @2;
    deadLine @3;
    custom @4;
}

# Typed signal kind — uses T.SignalKind from types.capnp directly.
# The shared definition includes all cross-platform signal types:
# terminate, interrupt, kill, hangUp, userDefined1-4, custom,
# child, stop, and continue. No local duplication needed.

struct Signal {
    kind @0 :T.SignalKind;
    data @1 :Data;
}

interface KernelService {
    # Task creation, replacement, and termination.
    spawn @0 (request :SpawnRequest) -> (task :T.ProcessId);
    fork @1 (request :ForkRequest) -> (task :T.ProcessId);
    exec @2 (pid :T.ProcessId, manifestBytes :Data) -> (result :T.VoidResult);
    exit @3 (pid :T.ProcessId, exitStatus :T.ExitStatus) -> (result :T.VoidResult);
    signal @4 (target :T.ProcessId, sig :Signal) -> (result :T.VoidResult);

    # Task query and observation.
    getInfo @5 (pid :T.ProcessId) -> (info :TaskInfo);
    list @6 (filter :TaskFilter, page :T.Pagination) -> (tasks :List(TaskInfo));
    subscribe @7 (filter :TaskFilter) -> (subscription :TaskSubscription);
    # Deprecated: use subscription.pull() instead. Kept for backward compatibility.
    pull @8 (subscription :TaskSubscription) -> (events :List(TaskEvent));

    # Address space regions (memory abstraction, backend-decided granularity).
    mapRegion @9 (pid :T.ProcessId, spec :RegionSpec) -> (info :RegionInfo);
    unmapRegion @10 (pid :T.ProcessId, base :UInt64) -> (result :T.VoidResult);
    protectRegion @11 (pid :T.ProcessId, base :UInt64, perms :T.MemoryPerms) -> (result :T.VoidResult);
    shareRegion @12 (pid :T.ProcessId, base :UInt64, shareWith :T.ProcessId, perms :T.MemoryPerms) -> (result :T.VoidResult);
    listRegions @13 (pid :T.ProcessId) -> (regions :List(RegionInfo));

    # Synchronization primitives (kernel-level, backend-decided).
    wait @14 (filter :WaitableFilter, timeout :T.Duration) -> (result :WaitResult);
    notify @15 (filter :WaitableFilter, sig :Signal) -> (result :T.VoidResult);

    # Authority / boundary primitives.
    # Wire format for all capabilities is T.CapabilityHandle (UInt64).
    # The kernel maps this to its internal capability representation (kobject, cslot, etc.).
    issueCapability @16 (request :IssueCapRequest) -> (handle :T.CapabilityHandle);
    publishCapability @17 (cap :T.CapabilityHandle, recipient :T.ProcessId) -> (result :T.BoolResult);
    enterNamespace @18 (cap :T.CapabilityHandle) -> (result :T.BoolResult);

    # Sub-services exposed (these are *not* the capability service; they're the variants).
    capabilities @19 () -> (service :CapabilityService);

    # Audit-7: kernel info and extension management.
    getKernelInfo @20 () -> (info :KernelTypeInfo);
    listKernelInstances @21 (page :T.Pagination) -> (instances :List(KernelInstanceInfo), total :UInt32);
    installExtension @22 (extension :KernelExtension) -> T.VoidResult;
    removeExtension @23 (name :Text) -> T.VoidResult;
    listExtensions @24 (page :T.Pagination) -> (extensions :List(KernelExtension), total :UInt32);

    # Audit-9: subscribe to container process events.
    subscribeContainerEvents @25 () -> (subscription :ContainerEventSubscription);

    # Audit-9: join the kernel mesh network.
    joinMesh @26 (node :KernelNode) -> T.VoidResult;

    # Audit-9: leave the kernel mesh network.
    leaveMesh @27 (nodeId :Text) -> T.VoidResult;

    # Audit-9: delegate a capability grant from one process to another.
    delegateCapability @28 (grant :CapabilityGrant, delegateTo :T.ProcessId, subset :List(CapOperation)) -> (delegated :CapabilityGrant);

    # Audit-9: query kernel internals for debugging.
    introspect @29 (request :KernelIntrospectionRequest) -> (result :KernelIntrospectionResult);

    # Stage a userland image into a process address space.
    stage @30 (targetPid :T.ProcessId, image :T.UserlandImage) -> T.VoidResult;

    # Replace a process image with a new one.
    replace @31 (targetPid :T.ProcessId, image :T.UserlandImage, args :List(Text)) -> T.VoidResult;

    # Enter userspace (set CR3/RSP/RIP, switch to ring 3).
    enterUserspace @32 (targetPid :T.ProcessId) -> T.VoidResult;

    # Read the entry context for a process.
    readEntryContext @33 (targetPid :T.ProcessId) -> (ctx :T.EntryContext);

    # Set isolation scope for a process.
    setQuarantine @34 (targetPid :T.ProcessId, scope :T.IsolatedScope) -> T.VoidResult;

    # Cross isolation barrier (requires explicit capability).
    crossIsolationBarrier @35 (fromPid :T.ProcessId, toPid :T.ProcessId, cap :T.CapabilityHandle) -> T.VoidResult;

    # Service registry — replaces raw handler table at fixed physical address.
    registerService @36 (endpoint :B.ServiceEndpoint) -> T.VoidResult;
    resolveService @37 (name :Text) -> (endpoint :B.ServiceEndpoint);
}

struct SpawnRequest {
    label @0 :Text;
    manifestBytes @1 :Data;
    args @2 :List(Text);
    env @3 :T.StringMap;
    workingDir @4 :Text;
    requestedCaps @5 :List(IssueCapRequest);
    priorityHint @6 :Int8;
}

# Typed fork flags — replaces Linux CLONE_* string lists.
enum ForkFlag {
    shareMemory @0;
    shareFiles @1;
    shareSignal @2;
    shareCwd @3;
    shareIpc @4;
    custom @5;
}

struct ForkRequest {
    parent @0 :T.ProcessId;
    flags @1 :List(ForkFlag);
}

struct TaskFilter {
    name @0 :T.TaskName;
    state @1 :TaskState;
    userspace @2 :Bool = true;
}

struct WaitableFilter {
    domain @0 :Text;
    topic @1 :Text;
}

struct IssueCapRequest {
    target @0 :Text;
    operations @1 :List(Operation);
    recipient @2 :T.ProcessId;
    expiry @3 :T.Duration;
}

struct TaskEvent {
    union {
        started @0 :TaskInfo;
        exited @1 :ExitedTask;
        stopped @2 :TaskInfo;
        resumed @3 :TaskInfo;
        signaled @4 :SignaledTask;
    }
}

struct ExitedTask {
    pid @0 :T.ProcessId;
    exitStatus @1 :T.ExitStatus;
    reason @2 :T.Error;
}

struct SignaledTask {
    pid @0 :T.ProcessId;
    signal @1 :Signal;
}

interface TaskSubscription {
    pull @0 () -> (events :List(TaskEvent));
    cancel @1 () -> T.VoidResult;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-7: Extended kernel types
#
# Kernel type detection, container kernel access, WASM kernel,
# unikernel host call, kernel mesh, extension contracts, and
# capability kernel (seL4-style). These extend the microkernel
# model to support diverse kernel architectures.
# ═══════════════════════════════════════════════════════════════════════

# ── Kernel Type Detection ─────────────────────────────────────

enum KernelType {
    microkernel @0;
    monolithic @1;
    exokernel @2;
    unikernel @3;
    hybrid @4;
    nanokernel @5;
    library @6;          # Library OS
    distributed @7;
    custom @8;
}

struct KernelTypeInfo {
    type @0 :KernelType;
    name @1 :Text;
    version @2 :T.Version;
    # CPU architecture (e.g., "x86_64", "aarch64", "riscv64").
    architecture @3 :Text;
    capabilities @4 :List(KernelCapability);
    extensions @5 :List(KernelExtension);
    metadata @6 :List(T.Meta);
}

enum KernelCapability {
    processManagement @0;
    memoryManagement @1;
    ipc @2;
    scheduling @3;
    interrupts @4;
    dma @5;
    extensions @6;
    containers @7;
    wasm @8;
    unikernel @9;
    mesh @10;
    capabilities @11;
    other @12;
}

# ── Container Kernel Access ───────────────────────────────────

struct ContainerKernelInfo {
    runtime @0 :Text;
    isolation @1 :T.IsolatedScope;
    rootless @2 :Bool;
    userlandIsolation @3 :Bool;
}

# ── Unikernel Host Call ───────────────────────────────────────

struct UnikernelInfo {
    # Unikernel runtime identifier (e.g., "mirage", "includeos", "nanos").
    runtime @0 :Text;
    singleAddress @1 :Bool;     # Single address space
    directHardware @2 :Bool;    # Direct hardware access
    minimal @3 :Bool;           # Minimal footprint
    bootTime @4 :T.Duration;    # Measured boot time
    memorySize @5 :UInt64;      # Memory footprint in bytes
}

# ── Kernel Mesh (Distributed) ─────────────────────────────────

struct KernelMeshInfo {
    nodes @0 :List(KernelNode);
    topology @1 :MeshTopology;
    synchronization @2 :MeshSync;
    # Whether the mesh handles network partitions gracefully.
    partition @3 :Bool;
}

struct KernelNode {
    id @0 :Text;
    address @1 :Text;
    kernel @2 :KernelTypeInfo;
    latency @3 :T.Duration;
    status @4 :NodeStatus;
}

enum NodeStatus {
    online @0;
    offline @1;
    degraded @2;
    syncing @3;
    custom @4;
}

enum MeshTopology {
    star @0;
    mesh @1;
    ring @2;
    tree @3;
    custom @4;
}

enum MeshSync {
    strong @0;          # Strong consistency
    eventual @1;        # Eventual consistency
    causal @2;          # Causal consistency
    custom @3;
}

# ── Kernel Extension Contract ─────────────────────────────────

struct KernelExtension {
    name @0 :Text;
    version @1 :T.Version;
    type @2 :ExtensionType;
    scope @3 :ExtensionScope;
    capabilities @4 :List(Text);
    author @5 :Text;
    license @6 :Text;
    metadata @7 :List(T.Meta);
}

enum ExtensionType {
    module @0;          # Loadable kernel module
    ebpf @1;            # eBPF program
    dtrace @2;          # DTrace probe
    custom @3;
}

enum ExtensionScope {
    system @0;          # System-wide
    container @1;       # Container-scoped
    process @2;         # Process-scoped
    custom @3;
}

# ── Kernel Instance Info ──────────────────────────────────────

struct KernelInstanceInfo {
    id @0 :Text;
    type @1 :KernelType;
    name @2 :Text;
    # Processes managed by this kernel instance.
    processCount @3 :UInt32;
    # Memory used by this kernel instance in bytes.
    memoryBytes @4 :UInt64;
    # Uptime of this kernel instance.
    uptime @5 :T.Duration;
    status @6 :NodeStatus;
}

# ── Capability Kernel (seL4-style) ────────────────────────────

struct CapabilityKernelInfo {
    # Whether the kernel has been formally verified.
    formalVerification @0 :Bool;
    # Thread control block count.
    tcb @1 :UInt32;
    # Capability slot count.
    slots @2 :UInt32;
    # Scheduling domain count.
    domains @3 :UInt32;
    # Mixed-criticality systems support.
    mcs @4 :Bool;
    # Supported architectures.
    architectures @5 :List(B.Architecture);
}

struct CapabilityGrant {
    # Wire format is T.CapabilityHandle (UInt64). Kernel maps to internal representation.
    cap @0 :T.CapabilityHandle;
    source @1 :T.ProcessId;
    target @2 :T.ProcessId;
    operations @3 :List(CapOperation);
    rights @4 :CapRights;
    expiry @5 :T.Duration;
}

enum CapOperation {
    read @0;
    write @1;
    execute @2;
    grant @3;
    delete @4;
    custom @5;
}

struct CapRights {
    read @0 :Bool;
    write @1 :Bool;
    execute @2 :Bool;
    grant @3 :Bool;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-9: Container process events, WASM module lifecycle, kernel mesh
# orchestration, capability delegation chain, and kernel introspection.
# ═══════════════════════════════════════════════════════════════════════

# ── Container Process Events ──────────────────────────────────

struct ContainerProcessEvent {
    # Container identifier.
    containerId @0 :Text;
    # Process within the container.
    processId @1 :T.ProcessId;
    # Event type.
    event @2 :ContainerProcessEventType;
    # Timestamp of the event.
    timestamp @3 :T.Timestamp;
    # Exit status (if process exited).
    exitStatus @4 :T.ExitStatus;
}

enum ContainerProcessEventType {
    created @0;
    started @1;
    exited @2;
    oomKilled @3;
    signalDelivered @4;
    custom @5;
}

interface ContainerEventSubscription {
    pull @0 () -> (events :List(ContainerProcessEvent));
    cancel @1 () -> T.VoidResult;
}



# ── Kernel Introspection ─────────────────────────────────────

struct KernelIntrospectionRequest {
    # What to introspect.
    target @0 :KernelIntrospectionTarget;
    # Specific process to query (if target is process).
    processId @1 :T.ProcessId;
    # Specific memory region to query (if target is memory).
    regionBase @2 :UInt64;
}

enum KernelIntrospectionTarget {
    # Query scheduler state.
    scheduler @0;
    # Query memory allocator state.
    memory @1;
    # Query IPC state.
    ipc @2;
    # Query process state.
    process @3;
    # Query interrupt state.
    interrupts @4;
    # Query all subsystems.
    all @5;
    custom @6;
}

struct KernelIntrospectionResult {
    # Subsystem name being introspected.
    subsystem @0 :Text;
    # Key-value pairs of introspection data.
    data @1 :T.StringMap;
    # Human-readable summary.
    summary @2 :Text;
    # Timestamp of the introspection.
    timestamp @3 :T.Timestamp;
}

# ═══════════════════════════════════════════════════════════════════════
# v0.0.2 additions — SMP, IPI, per-CPU, memory sharing
#
# The kernel boundary is what apps/drivers observe. How the kernel
# schedules across CPUs and routes IPIs is backend-agnostic. The
# protocol only commits to the affordances.
# ═══════════════════════════════════════════════════════════════════════

# ── SMP Topology ──────────────────────────────────────────────
# A driver or scheduler asks "what CPUs exist?" and "what CPU am I
# on?" without learning the topology algorithm.

interface SmpService {
    # Static topology (what exists).
    getTopology @0 () -> (topology :T.SmpTopology);
    # Mask of currently-online CPUs.
    getOnlineMask @1 () -> (mask :UInt64);
    # Which CPU is the calling context running on?
    getCurrentCpu @2 () -> (cpu :T.CpuId);
    # Subscribe to topology changes (CPU hotplug, NUMA rebalance).
    subscribe @3 () -> (subscription :SmpTopologySubscription);
}

interface SmpTopologySubscription {
    pull @0 () -> (events :List(SmpTopologyEvent));
    cancel @1 () -> T.VoidResult;
}

struct SmpTopologyEvent {
    at @0 :UInt64;
    union {
        cpuOnline @1 :T.CpuId;
        cpuOffline @2 :T.CpuId;
        topologyChanged @3 :Void;
        custom @4 :Void;
    }
}

# ── Inter-Processor Interrupts ────────────────────────────────
# Drivers and kernel-level schedulers send IPIs. The contract is
# opaque payload + affinity mask; the backend picks the mechanism.

interface IpiService {
    # Send an IPI to the given CPU(s). Payload is opaque bytes the
    # recipient interprets (driver-defined).
    send @0 (targetMask :UInt64, payload :Data) -> (result :T.VoidResult);
    # Receive IPIs. The subscription is per-task; IPIs targeting
    # this task's registered vector are dispatched here.
    subscribe @1 (vector :UInt32) -> (subscription :IpiSubscription);
}

interface IpiSubscription {
    pull @0 () -> (events :List(IpiEvent));
    cancel @1 () -> T.VoidResult;
}

struct IpiEvent {
    at @0 :UInt64;
    fromCpu @1 :T.CpuId;
    vector @2 :UInt32;
    payload @3 :Data;
}

# ── Memory Sharing ────────────────────────────────────────────
# Zero-copy region sharing is a kernel affordance; the contract is
# structured (size, flags, peer handle) so backends can implement
# it any way they like.

struct ShareRequest {
    pid @0 :T.ProcessId;
    region @1 :RegionInfo;
    peer @2 :T.ProcessId;
    perms @3 :T.MemoryPerms;
}

struct ShareResult {
    # Optional: backend may rewrite the peer-side base address.
    # Original region's base on the source side is preserved.
    peerBase @0 :UInt64;
    grantedPerms @1 :T.MemoryPerms;
}

# ── Per-CPU State ─────────────────────────────────────────────
# Drivers register per-CPU scratch state for the kernel to
# allocate. The kernel can reset/restore around driver restarts.

struct PerCpuState {
    handle @0 :UInt64;
    sizeBytes @1 :UInt64;
    # Backend-mediated alignment hint.
    alignment @2 :UInt32;
}

interface PerCpuService {
    allocate @0 (state :PerCpuState) -> (handle :UInt64);
    release @1 (handle :UInt64) -> (result :T.VoidResult);
    get @2 (cpu :T.CpuId, handle :UInt64) -> (address :UInt64);
}

# ═══════════════════════════════════════════════════════════════════════
# Boot-Agnostic + Multi-Paradigm Additions
#
# These additions close gaps for:
# - Binary format typing (Gap A)
# - Kernel swap semantics (Gap B)
# - Typed capabilities + proof levels (Gap C)
# - A/B slot management (Gap D)
# - Formal verification artifacts (Gap F)
# - Multi-kernel coordination (Gap H)
# - Kernel envelope defaults (Gap I)
#
# Linux-compat (Gap E) is intentionally excluded.
# Linux is not a paradigm — it's one specific monolithic implementation.
# The correct abstraction is KernelType.libraryOS, not "linux compat".
# ═══════════════════════════════════════════════════════════════════════

# ── Gap A: Binary Format Typing ───────────────────────────────
# Kernels can be ELF, PE/COFF, WASM, or custom formats.
# BinaryFormat is defined in types.capnp (T.BinaryFormat).

struct KernelBinaryDescriptor {
    format @0 :T.BinaryFormat;
    entryPoint @1 :UInt64;
    # Architecture-specific identifier (e.g., EM_X86_64 = 0x3E for ELF).
    machineId @2 :UInt16;
    # ABI identifier (e.g., "sysv", "wasi", "uefi").
    abi @3 :Text;
    # Cryptographic signature of the binary (if signed).
    signature @4 :Data;
    # Binary size in bytes.
    sizeBytes @5 :UInt64;
    # Hash of the binary (SHA-256).
    hash @6 :Data;
}

# ── Gap B: Kernel Swap Semantics ──────────────────────────────
# Supports runtime kernel envelope switching without recompilation.
# Cyber-microkernel can be replaced with seL4-style at runtime.

enum KernelMigrationStrategy {
    coldSwap @0;        # Save state, reboot into other kernel
    warmSwap @1;        # Live process migration
    hybridCoexist @2;   # Both kernels run, share capabilities
}

struct KernelSwapRequest {
    targetEnvelope @0 :KernelType;
    targetKernel @1 :KernelBinaryDescriptor;
    migrationStrategy @2 :KernelMigrationStrategy;
    # Maximum time to wait for swap completion.
    timeout @3 :T.Duration;
    # Whether to preserve process state across swap.
    preserveProcesses @4 :Bool;
}

struct KernelSwapEvent {
    timestamp @0 :T.Timestamp;
    sourceKernel @1 :Text;
    targetKernel @2 :Text;
    strategy @3 :KernelMigrationStrategy;
    success @4 :Bool;
    error @5 :T.Error;
    duration @6 :T.Duration;
}

interface KernelSwapSubscription {
    pull @0 () -> (events :List(KernelSwapEvent));
    cancel @1 () -> T.VoidResult;
}

# ── Gap C: Typed Capabilities + Proof Levels ──────────────────
# Capabilities are typed sets, not flat booleans.
# Proof level describes formal verification depth.

enum ProofLevel {
    unverified @0;
    tested @1;
    raceDetectorOnly @2;
    staticAnalysisOnly @3;
    formalPartial @4;
    formalComplete @5;
    formalEndToEnd @6;
}

struct KernelCapabilityTag {
    # The capability this kernel provides.
    capability @0 :KernelCapability;
    # Whether this capability is formally verified.
    verified @1 :Bool;
    # Proof level for this specific capability.
    proofLevel @2 :ProofLevel;
    # Scope of the proof (e.g., "scheduler", "ipc", "memory").
    proofScope @3 :Text;
}

struct KernelTypedCapabilities {
    # Each kernel declares its exact capability surface as tags.
    capabilityTags @0 :List(KernelCapabilityTag);
    # Overall proof level for this kernel.
    proofLevel @1 :ProofLevel;
    # Total number of formally verified capabilities.
    verifiedCount @2 :UInt32;
    # Total number of capabilities.
    totalCount @3 :UInt32;
}

# ── Gap D: A/B Slot Management ───────────────────────────────
# Kernel-side interface for active A/B slot selection during kernel-swap.

struct AbSlotInfo {
    activeSlot @0 :Text;
    secondarySlot @1 :Text;
    attemptCount @2 :UInt32;
    maxAttempts @3 :UInt32;
    # Whether the active slot has been marked successful.
    activeSuccessful @4 :Bool;
    # Timestamp of last slot update.
    lastUpdate @5 :T.Timestamp;
}

# ── Gap F: Formal Verification Artifacts ──────────────────────
# For space/military grade, the level and scope of formal proof
# must be in the schema so bootloaders can validate.

enum FormalProofScope {
    scheduler @0;
    ipc @1;
    memoryManagement @2;
    capabilityManagement @3;
    interruptHandling @4;
    dma @5;
    endToEnd @6;
    custom @7;
}

struct FormalVerificationArtifact {
    proofLevel @0 :ProofLevel;
    proofScope @1 :List(FormalProofScope);
    # Verification tool used (e.g., "Isabelle/HOL", "Coq", "seL4/SPARK").
    verifierTool @2 :Text;
    # Hash of the specification being verified.
    specHash @3 :Data;
    # Hash of the C/Rust source being verified.
    sourceHash @4 :Data;
    # Hash of the proof script.
    proofScriptHash @5 :Data;
    # When the proof was last verified.
    proofDate @6 :T.Timestamp;
    # Maximum depth of the proof tree.
    maxProofDepth @7 :UInt32;
    # Whether the proof covers all code paths.
    completeCoverage @8 :Bool;
}

# ── Gap H: Multi-Kernel Coordination ─────────────────────────
# Within a single computer, multiple kernels must coordinate.
# e.g., cyber-microkernel + capability-kernel sharing capabilities.

struct CrossKernelCapability {
    # Source kernel that created this capability.
    sourceKernel @0 :Text;
    # Target kernel that receives this capability.
    targetKernel @1 :Text;
    # The capability being shared.
    capability @2 :T.CapabilityHandle;
    # Operations the target kernel can perform.
    operations @3 :List(CapOperation);
    # Expiry for this cross-kernel capability.
    expiry @4 :T.Duration;
}

# ── Gap I: Kernel Envelope Defaults ───────────────────────────
# What capabilities a given envelope gives by default.
# Required to reason about safer vs faster envelopes.

struct KernelEnvelopeDefaults {
    # The kernel type this envelope describes.
    envelope @0 :KernelType;
    # Default capabilities granted to all processes.
    defaultCapabilities @1 :List(KernelCapability);
    # Default memory permissions for new processes.
    defaultMemoryPerms @2 :T.MemoryPerms;
    # Whether capabilities are sealed by default (microkernel = true).
    capabilitiesSealed @3 :Bool;
    # Whether processes can escape their capability set.
    capabilityEscape @4 :Bool;
    # Default isolation level.
    isolationLevel @5 :IsolationLevel;
}

enum IsolationLevel {
    none @0;            # No isolation (monolithic)
    process @1;         # Process-level isolation
    capability @2;      # Capability-based isolation
    hardware @3;        # Hardware-enforced isolation (MMU,TrustZone)
    formal @4;          # Formally verified isolation
}

# ═══════════════════════════════════════════════════════════════════════
# Extended KernelService Methods
#
# These methods are added to KernelService to support the gaps above.
# They use field numbers starting from @30 (after existing @31).
# ═══════════════════════════════════════════════════════════════════════

# Note: The following methods would be added to the KernelService interface.
# Since Cap'n Proto doesn't allow extending interfaces after definition,
# these are defined as separate interfaces that the kernel implements.

interface KernelSwapService {
    # Request a kernel envelope swap.
    requestSwap @0 (req :KernelSwapRequest) -> (result :T.VoidResult);
    # Get history of kernel swaps.
    getSwapHistory @1 (page :T.Pagination) -> (history :List(KernelSwapEvent));
    # Subscribe to kernel swap events.
    subscribeSwap @2 () -> (subscription :KernelSwapSubscription);
}

interface AbSlotService {
    # Get the currently active boot slot.
    getActiveSlot @0 () -> (slot :AbSlotInfo);
    # Mark the current boot as successful (resets attempt counter).
    markBootSuccessful @1 () -> T.VoidResult;
    # Set the active boot slot.
    setActiveSlot @2 (slot :Text) -> T.VoidResult;
    # Get the current boot attempt count.
    getBootAttempt @3 () -> (attempts :UInt32);
}

interface MultiKernelCoordinator {
    # Request a capability from another kernel.
    requestCapability @0 (targetKernel :Text, capability :Text) -> (cap :T.CapabilityHandle);
    # Publish a capability to another kernel.
    publishCapability @1 (cap :T.CapabilityHandle, targetKernel :Text) -> T.VoidResult;
    # List all active kernels on this machine.
    listActiveKernels @2 () -> (kernels :List(KernelInstanceInfo));
    # Get typed capabilities for a specific kernel.
    getKernelCapabilities @3 (kernelId :Text) -> (caps :KernelTypedCapabilities);
}

# ── Kernel ABI ────────────────────────────────────────────────
# The timelessness guarantee: a bootloader from 2028 can negotiate
# a 2026 kernel via schema fields, not compile-time hacks.

struct KernelAbi {
    handoffFormat @0 :UInt32;
    entryConventions @1 :T.EntryContext;
    minVersion @2 :T.Version;
    maxVersion @3 :T.Version;
}

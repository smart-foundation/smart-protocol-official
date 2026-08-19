@0xa1b2c3d4e5f60102;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Sandbox — process sandboxing, capability control, isolation boundaries.
#
# Zero backend assumptions: no seccomp, no landlock, no namespace,
# no WASI, no gVisor, no Firecracker. Backend decides the sandboxing
# mechanism; protocol defines the policy contract.
#
# Used by: process.capnp (sandboxed spawning), init.capnp (service isolation)
# ═══════════════════════════════════════════════════════════════════════

interface SandboxService {
    # Create a new sandboxed process.
    createSandbox @0 (request :CreateSandboxRequest) -> (result :CreateSandboxResult);

    # Configure filter for an existing sandbox.
    configureFilter @1 (sandboxId :T.SandboxId, filter :SandboxFilter) -> T.VoidResult;

    # Get current sandbox policy.
    getPolicy @2 (sandboxId :T.SandboxId) -> (policy :SandboxPolicy);

    # Update sandbox policy (live update if supported).
    updatePolicy @3 (sandboxId :T.SandboxId, policy :SandboxPolicy) -> T.VoidResult;

    # List active sandboxes.
    listSandboxes @4 (pagination :T.Pagination) -> (sandboxes :List(SandboxInfo), totalCount :UInt32);

    # Get sandbox info.
    getSandboxInfo @5 (sandboxId :T.SandboxId) -> (info :SandboxInfo);

    # Terminate a sandbox and all its processes.
    terminateSandbox @6 (sandboxId :T.SandboxId, signal :T.SignalKind) -> T.VoidResult;

    # Get sandbox resource usage.
    getResourceUsage @7 (sandboxId :T.SandboxId) -> (usage :T.ResourceUsage);

    # Subscribe to sandbox events.
    subscribeSandbox @8 (sandboxId :T.SandboxId) -> (subscription :SandboxSubscription);

    # Check if a sandboxing backend is available.
    checkBackend @9 (backend :SandboxBackend) -> (available :Bool, version :Text);

    # Grant a capability to a sandbox.
    grantCapability @10 (sandboxId :T.SandboxId, capability :CapabilityGrant) -> T.VoidResult;

    # Revoke a capability from a sandbox.
    revokeCapability @11 (sandboxId :T.SandboxId, capabilityName :Text) -> T.VoidResult;

    # List capabilities granted to a sandbox.
    listCapabilities @12 (sandboxId :T.SandboxId) -> (capabilities :List(CapabilityGrant));

    # Freeze a sandbox (pause all processes).
    freeze @13 (sandboxId :T.SandboxId, reason :Text) -> T.VoidResult;

    # Thaw a sandbox (resume from freeze).
    thaw @14 (sandboxId :T.SandboxId) -> T.VoidResult;

    # Save sandbox state for migration.
    save @15 (sandboxId :T.SandboxId) -> (state :Data);

    # Restore sandbox from saved state.
    restore @16 (state :Data) -> (result :CreateSandboxResult);

    # Simulate a policy change without applying it.
    simulate @17 (sandboxId :T.SandboxId, policy :SandboxPolicy) -> (result :SimulationResult);

    # Evaluate a policy against a set of capabilities.
    evaluate @18 (policy :SandboxPolicy) -> (result :EvaluationResult);
}

interface SandboxSubscription {
    pull @0 () -> (events :List(SandboxEvent));
    cancel @1 () -> T.VoidResult;
}

# ─── Sandbox Creation ────────────────────────────────────────────────

struct CreateSandboxRequest {
    # Command and arguments to execute in the sandbox.
    command @0 :Text;
    args @1 :List(Text);

    # Environment variables.
    env @2 :T.StringMap;

    # Working directory (relative to sandbox root).
    workingDir @3 :Text;

    # Sandbox policy to apply.
    policy @4 :SandboxPolicy;

    # Backend preference (empty = auto-select best available).
    preferredBackend @5 :SandboxBackend;

    # Resource limits.
    limits @6 :ResourceLimits;

    # Capabilities to grant.
    capabilities @7 :List(CapabilityGrant);

    # Metadata for debugging/tracking.
    metadata @8 :T.StringMap;
}

struct CreateSandboxResult {
    union {
        success @0 :CreateSandboxSuccess;
        error @1 :T.Error;
    }
}

struct CreateSandboxSuccess {
    sandboxId @0 :T.SandboxId;
    processId @1 :T.ProcessId;
}

# ─── Sandbox Policy ──────────────────────────────────────────────────

struct SandboxPolicy {
    # Resource limits.
    limits @0 :ResourceLimits;

    # Filesystem access control.
    filesystemAccess @1 :FilesystemAccess;

    # Network access control.
    networkAccess @2 :NetworkAccess;

    # IPC access control.
    ipcAccess @3 :IpcAccess;

    # Isolation scope for this sandbox.
    isolation @4 :T.IsolatedScope;

    # Custom backend-specific policy.
    custom @5 :Data;
}

# ─── Sandbox Filter ──────────────────────────────────────────────────

struct SandboxFilter {
    # Default action for operations not explicitly listed.
    defaultAction @0 :FilterAction;

    # Explicit allow/deny rules (evaluated in order).
    rules @1 :List(SandboxRule);

    # Whether to log denied operations.
    logDenied @2 :Bool;
}

struct SandboxRule {
    # Operation identifier (backend-decided format).
    operation @0 :Text;

    # Action to take.
    action @1 :FilterAction;

    # Argument filters (empty = match all).
    argFilters @2 :List(ArgFilter);

    # Comment for documentation.
    comment @3 :Text;
}

struct ArgFilter {
    argIndex @0 :UInt8;
    operator @1 :ArgOperator;
    value @2 :UInt64;
    mask @3 :UInt64;
}

enum ArgOperator {
    equal @0;
    notEqual @1;
    maskedEqual @2;
    maskedNotEqual @3;
    lessThan @4;
    lessEqual @5;
    greaterThan @6;
    greaterEqual @7;
    inRange @8;
    custom @9;
}

enum FilterAction {
    allow @0;
    deny @1;
    errno @2;
    killProcess @3;
    killThread @4;
    trap @5;
    trace @6;
    custom @7;
}

# ─── Filesystem Access ───────────────────────────────────────────────

struct FilesystemAccess {
    defaultAction @0 :FsAction;
    rules @1 :List(FsRule);
    hideInaccessible @2 :Bool;
    readonlyRoot @3 :Bool;
    mounts @4 :List(MountRule);
}

enum FsAction {
    allow @0;
    deny @1;
    readonly @2;
    readwrite @3;
    exec @4;
    custom @5;
}

struct FsRule {
    path @0 :Text;
    action @1 :FsAction;
    recursive @2 :Bool;
    comment @3 :Text;
}

struct MountRule {
    source @0 :Text;
    target @1 :Text;
    readonly @2 :Bool;
    nosuid @3 :Bool;
    nodev @4 :Bool;
    noexec @5 :Bool;
    fsType @6 :Text;
    options @7 :Text;
}

# ─── Network Access ──────────────────────────────────────────────────

struct NetworkAccess {
    defaultAction @0 :NetAction;
    rules @1 :List(NetRule);
    allowLocalhost @2 :Bool;
}

enum NetAction {
    allow @0;
    deny @1;
    allowTcp @2;
    allowUdp @3;
    allowTcpUdp @4;
    custom @5;
}

struct NetRule {
    cidr @0 :Text;
    action @1 :NetAction;
    portStart @2 :UInt16;
    portEnd @3 :UInt16;
    comment @4 :Text;
}

# ─── IPC Access ──────────────────────────────────────────────────────

struct IpcAccess {
    defaultAction @0 :IpcAction;
    allowedServices @1 :List(Text);
    capabilities @2 :List(CapabilityGrant);
    allowSignals @3 :Bool;
}

enum IpcAction {
    allow @0;
    deny @1;
    allowNamed @2;
    custom @3;
}

# ─── Capability Grant ────────────────────────────────────────────────

struct CapabilityGrant {
    name @0 :Text;
    rights @1 :List(Text);
    resource @2 :Text;
}

# ─── Resource Limits ─────────────────────────────────────────────────

struct ResourceLimits {
    cpuTime @0 :T.Duration;
    memoryBytes @1 :UInt64;
    virtualMemoryBytes @2 :UInt64;
    maxProcesses @3 :UInt32;
    maxOpenFiles @4 :UInt32;
    maxFileSize @5 :UInt64;
    maxLockedMemory @6 :UInt64;
    maxMsgQueueSize @7 :UInt64;
    custom @8 :T.StringMap;
}

# ─── Sandbox Info ────────────────────────────────────────────────────

struct SandboxInfo {
    id @0 :T.SandboxId;
    command @1 :Text;
    args @2 :List(Text);
    policy @3 :SandboxPolicy;
    limits @4 :ResourceLimits;
    backend @5 :SandboxBackend;
    state @6 :SandboxState;
    createdAt @7 :T.Timestamp;
    processId @8 :T.ProcessId;
    metadata @9 :T.StringMap;
}

enum SandboxBackend {
    wasm @0;
    native @1;
    hardware @2;
    custom @3;
}

enum SandboxState {
    creating @0;
    running @1;
    paused @2;
    terminated @3;
    failed @4;
    custom @5;
}

# ─── Sandbox Events ──────────────────────────────────────────────────

struct SandboxEvent {
    sandboxId @0 :T.SandboxId;
    timestamp @1 :T.Timestamp;
    union {
        started @2 :Void;
        terminated @3 :SandboxTerminated;
        policyViolation @4 :PolicyViolation;
        resourceExhausted @5 :ResourceExhausted;
        custom @6 :Data;
    }
}

struct SandboxTerminated {
    exitStatus @0 :T.ExitStatus;
    signal @1 :T.SignalKind;
}

struct PolicyViolation {
    policyType @0 :PolicyType;
    rule @1 :Text;
    action @2 :Text;
    denied @3 :Bool;
}

enum PolicyType {
    syscall @0;
    filesystem @1;
    network @2;
    ipc @3;
    capability @4;
    resource @5;
    custom @6;
}

struct ResourceExhausted {
    resource @0 :ResourceType;
    limit @1 :UInt64;
    current @2 :UInt64;
}

enum ResourceType {
    cpuTime @0;
    memory @1;
    processes @2;
    openFiles @3;
    fileSize @4;
    lockedMemory @5;
    msgQueueSize @6;
    custom @7;
}

# ─── Simulation / Evaluation ─────────────────────────────────────────

struct SimulationResult {
    allowed @0 :Bool;
    violations @1 :List(Text);
    warnings @2 :List(Text);
}

struct EvaluationResult {
    valid @0 :Bool;
    conflicts @1 :List(Text);
    recommendations @2 :List(Text);
}

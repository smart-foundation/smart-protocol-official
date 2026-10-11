@0xa1b2c3d4e5f60102;

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ═══════════════════════════════════════════════════════════════════════
# Sandbox — process sandboxing, capability control, isolation boundaries.
#
# Zero backend assumptions: no seccomp, no landlock, no namespace,
# no WASI, no gVisor, no Firecracker, no mount(2), no rlimit. Backend
# decides the sandboxing mechanism; protocol defines the policy contract.
#
# ── THE HEADER USED TO LIE ────────────────────────────────────────────
#
# The previous version claimed "no seccomp, no landlock, no namespace"
# in its header while its body carried seccomp's return-action names
# (errno, killThread, trap, trace), seccomp's BPF argument-filter model
# (argIndex :UInt8 with positional operators), Linux mount flags
# (nosuid, nodev, noexec) and literal RLIMIT field names (maxOpenFiles,
# maxLockedMemory, maxMsgQueueSize). A non-Linux backend had to model
# POSIX semantics it does not have in order to fill required fields, and
# the file's own subtitle — "capability control" — sat above a
# permission-STRING model that DESIGN_PRINCIPLES.md:399 forbids.
#
# The correction is to express the isolation semantics abstractly and
# leave the mechanisms as backend-reported metadata:
#
#   errno/killThread/trap/trace  ->  allow / deny / fail / terminate
#   argIndex + operator table    ->  an open match map (backend-declared keys)
#   nosuid/nodev/noexec/fsType   ->  readonly (universal) + an open options map
#   RLIMIT_NOFILE/MEMLOCK/MSGQUEUE -> the four limits every backend has,
#                                     plus an open map for the rest
#   name + rights[Text] + resource -> Capability (capability.capnp)
#
# Nothing is lost: a backend that enforced a mechanism can still REPORT
# which one it used, in the open maps, without the protocol requiring a
# backend to have one.
#
# ── AUTHORITY IS THE INTERFACE REFERENCE ───────────────────────────────
#
# Sandbox authority is a Capability reference. The previous local
# `CapabilityGrant {name, rights :List(Text), resource}` was a parallel
# permission vocabulary with its own grant/revoke lifecycle, so a grant
# made here could outlive a revocation made in capability.capnp — two
# authority paths that must agree forever.
#
# The three methods that manipulate capability OBJECTS (grant/revoke/
# list) sit behind the `capabilityAdmin` accessor rather than on the
# root: holding the sandbox-creation reference is not by itself the
# authority to hand capabilities to a sandbox. That is the ai.capnp
# accessor pattern applied where the object under manipulation is a
# capability and the file is not capability.capnp.
#
# ── ZERO-COPY ─────────────────────────────────────────────────────────
#
# `save`/`restore` returned and accepted a whole sandbox's memory
# snapshot as inline `Data` — the largest possible payload in the system,
# copied through the message arena, with a message-size ceiling on the
# single heaviest operation the protocol defines. Both are T.DataHandle
# now (inline for a small state blob, a buffer reference for megabytes).
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

    # Check if a sandboxing backend is available. `version` is whatever
    # the backend calls its version — the previous contract asked for a
    # "version" of a backend "kind" with no declared scheme, so an
    # implementer had to guess what to put there. Declared: it is the
    # backend's own version string, opaque to the protocol.
    checkBackend @9 (backend :Text) -> (available :Bool, version :Text);

    # Freeze a sandbox (pause all processes).
    freeze @10 (sandboxId :T.SandboxId, reason :Text) -> T.VoidResult;

    # Thaw a sandbox (resume from freeze).
    thaw @11 (sandboxId :T.SandboxId) -> T.VoidResult;

    # Save sandbox state for migration. A handle: the previous inline
    # Data made the heaviest operation in the protocol copy a possibly
    # multi-gigabyte memory image through the message arena.
    save @12 (sandboxId :T.SandboxId) -> (state :T.DataHandle);

    # Restore sandbox from saved state. The returned capabilities are
    # the ones the state carries: a backend MUST either restore them
    # from the snapshot or report their absence in
    # CreateSandboxSuccess.restoredCapabilities, because
    # "restore-preserves" and "restore-revokes" are not the same
    # contract and consumers must be able to tell which they got.
    restore @13 (state :T.DataHandle) -> (result :CreateSandboxResult);

    # Simulate a policy change without applying it.
    simulate @14 (sandboxId :T.SandboxId, policy :SandboxPolicy) -> (result :SimulationResult);

    # Evaluate a policy against a specific sandbox's granted
    # capabilities. The previous form took no sandboxId, so it evaluated
    # a policy against nothing and no implementer could say what the
    # answer meant.
    evaluate @15 (sandboxId :T.SandboxId, policy :SandboxPolicy) -> (result :EvaluationResult);

    # Grant a capability to a sandbox. These three methods manipulate
    # Capability OBJECTS (the capability being granted is the object, not
    # an authority token for the method), and DESIGN_PRINCIPLES.md:399
    # permits per-method Capability parameters only inside
    # capability.capnp and on ai.capnp-style root accessors. So the
    # surface is split to match: the root hands out a capability-admin
    # service gated ONCE at acquisition, exactly as ai.capnp's seven
    # accessors do, and the grant/revoke path is no longer reachable by
    # merely holding the sandbox-creation reference.
    capabilityAdmin @16 (authority :Capability) -> (service :SandboxCapabilityAdmin);
}

interface SandboxSubscription {
    pull @0 () -> (events :List(SandboxEvent));
    cancel @1 () -> T.VoidResult;
}

# The capability-manipulation surface for sandboxes, handed out by
# SandboxService.capabilityAdmin. Holding THIS reference is the authority
# to grant, revoke and inspect capabilities; attenuation and revocation
# remain capability.capnp's job, so revoking a capability here revokes it
# there — one authority path, not two.
interface SandboxCapabilityAdmin {
    # Grant a capability to a sandbox. The capability being granted is
    # the OBJECT of the method, not an authority token for it — exactly
    # capability.capnp's own five methods (attenuate/transfer/revoke/
    # revokeControlled/evaluateCondition), whose parameter DESIGNS
    # PRINCIPLES.md:438-450 legalizes for that reason. Replacing the
    # reference with a bare opaque id would NOT satisfy the rule better:
    # presenting the capability is the proof of holding it, so an
    # id-keyed grant is a confused-deputy hole where any holder of this
    # service could name any capability to any sandbox.
    grant @0 (sandboxId :T.SandboxId, capability :Capability) -> T.VoidResult;

    # Revoke a capability from a sandbox, by its opaque id (R4). The id
    # identifies; it does not authorize.
    revoke @1 (sandboxId :T.SandboxId, capabilityId :T.CapabilityId) -> T.VoidResult;

    # List capabilities granted to a sandbox. Results, not parameters:
    # the resolved material rides outbound, where it cannot be used to
    # act.
    list @2 (sandboxId :T.SandboxId) -> (capabilities :List(Capability));
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

    # Backend preference (open token; empty = auto-select best
    # available). The previous enum named `native` — the least meaningful
    # word available, since two `native` backends may share no mechanism
    # and a consumer selecting it got an implementation-defined sandbox.
    preferredBackend @5 :Text;

    # Resource limits.
    limits @6 :ResourceLimits;

    # Capabilities to grant, as references.
    capabilities @7 :List(Capability);

    # Metadata for debugging/tracking.
    metadata @8 :T.StringMap;
}

struct CreateSandboxResult {
    union {
        success @0 :CreateSandboxSuccess;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct CreateSandboxSuccess {
    sandboxId @0 :T.SandboxId;
    processId @1 :T.ProcessId;
    # Which of the requested capabilities were actually granted, and
    # which the backend refused. Previously a grant either happened or
    # silently did not, and the caller could not tell.
    grantedCapabilities @2 :List(Capability);
    # On restore: which capabilities the snapshot carried. Empty when
    # the state carried none, so "restore-revokes" is visible.
    restoredCapabilities @3 :List(Capability);
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

    # Backend-reported mechanisms this policy was enforced with, as open
    # tokens. The protocol does not require any of them; this is where a
    # backend tells a consumer what it actually did.
    enforcedBy @5 :T.StringMap;

    # Custom backend-specific policy.
    custom @6 :Data;
}

# ─── Sandbox Filter ──────────────────────────────────────────────────
# An abstract deny/allow decision table. What the backend does to
# enforce it is the backend's business, and it reports that in
# SandboxPolicy.enforcedBy rather than having the protocol name it.

struct SandboxFilter {
    # Default action for operations not explicitly listed.
    defaultAction @0 :FilterAction;

    # Explicit allow/deny rules (evaluated in order).
    rules @1 :List(SandboxRule);

    # Whether to log denied operations.
    logDenied @2 :Bool;

    custom @3 :Data;
}

struct SandboxRule {
    # Operation identifier (backend-decided format: a syscall name where
    # there are syscalls, a capability name where there are not).
    operation @0 :Text;

    # Action to take.
    action @1 :FilterAction;

    # Constraints on the operation's arguments, as open key/value pairs.
    # The keys are backend-declared ("path", "arg0", "port"), so a
    # backend without positional syscall arguments can still constrain
    # the arguments it has. This replaces seccomp's BPF argument model
    # (argIndex :UInt8 with a fixed operator table), which presupposed
    # numbered syscalls and left a capability kernel unable to express a
    # rule at all.
    match @2 :T.StringMap;

    # Comment for documentation.
    comment @3 :Text;
}

# Abstract outcomes. `fail` means the operation is refused and the
# backend reports why; `terminate` means the isolated unit is torn down.
# What a backend does to achieve either is backend-reported metadata.
enum FilterAction {
    # Sentinel: an unset default action is not "allow". A filter with
    # no action declared must fail closed in the contract, not open.
    unspecified @0;
    allow @1;
    deny @2;
    fail @3;
    terminate @4;
    custom @5;
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
    unspecified @0;   # Sentinel: an unset action is not "allow"
    allow @1;
    deny @2;
    readonly @3;
    readwrite @4;
    exec @5;
    custom @6;
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
    # readonly is universal; the previous nosuid/nodev/noexec/fsType
    # quartet were literal mount(2) flags that a backend with no mount
    # concept had to parse and leave meaningless.
    readonly @2 :Bool;
    # Everything else the backend enforced, as open key/value pairs the
    # backend declares ("nosuid" -> "true", "fsType" -> "tmpfs", ...).
    options @3 :T.StringMap;
}

# ─── Network Access ──────────────────────────────────────────────────

struct NetworkAccess {
    defaultAction @0 :NetAction;
    rules @1 :List(NetRule);
    allowLocalhost @2 :Bool;
}

enum NetAction {
    unspecified @0;   # Sentinel: an unset action is not "allow"
    allow @1;
    deny @2;
    allowTcp @3;
    allowUdp @4;
    allowTcpUdp @5;
    custom @6;
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
    # Typed service ids, so an allow-list is correlatable with actual
    # service references. The previous List(Text) left two backends'
    # service-name namespaces unrelated.
    allowedServices @1 :List(T.ServiceId);
    # Capabilities this sandbox may present over IPC.
    capabilities @2 :List(Capability);
    allowSignals @3 :Bool;
}

enum IpcAction {
    unspecified @0;   # Sentinel: an unset action is not "allow"
    allow @1;
    deny @2;
    allowNamed @3;
    custom @4;
}

# ─── Resource Limits ─────────────────────────────────────────────────
# The four limits every sandbox has, plus an open map for the rest. The
# previous field list was literally the RLIMIT_* set
# (RLIMIT_NOFILE, RLIMIT_MEMLOCK, RLIMIT_MSGQUEUE), so a backend had to
# model POSIX rlimit semantics to fill fields the protocol required.

struct ResourceLimits {
    cpuTime @0 :T.Duration;
    memoryBytes @1 :UInt64;
    virtualMemoryBytes @2 :UInt64;
    maxProcesses @3 :UInt32;
    maxFileSize @4 :UInt64;
    # Backend-declared limits with open keys and values
    # ("maxOpenFiles" -> "1024", "maxLockedMemory" -> "65536", ...).
    custom @5 :T.StringMap;
}

# ─── Sandbox Info ────────────────────────────────────────────────────

struct SandboxInfo {
    id @0 :T.SandboxId;
    command @1 :Text;
    args @2 :List(Text);
    policy @3 :SandboxPolicy;
    limits @4 :ResourceLimits;
    # Backend identity as an open token.
    backend @5 :Text;
    state @6 :SandboxState;
    createdAt @7 :T.Timestamp;
    processId @8 :T.ProcessId;
    metadata @9 :T.StringMap;
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
        policyViolation @4 :SandboxPolicyViolation;
        resourceExhausted @5 :ResourceExhausted;
        custom @6 :Data;
    }
}

struct SandboxTerminated {
    exitStatus @0 :T.ExitStatus;
    signal @1 :T.SignalKind;
}

# Named SandboxPolicyViolation, not PolicyViolation: access.capnp
# declares a `PolicyViolation` with different fields, and two types by
# one name in one protocol is an import hazard.
struct SandboxPolicyViolation {
    policyType @0 :PolicyType;
    # The rule that was violated, as the backend names it.
    rule @1 :Text;
    # What the backend did about it.
    action @2 :FilterAction;
    denied @3 :Bool;
    # The underlying cause, so a consumer never string-parses to learn it.
    error @4 :T.Error;
    custom @5 :T.StringMap;
}

enum PolicyType {
    unspecified @0;   # Sentinel: an unset type is not "syscall"
    syscall @1;
    filesystem @2;
    network @3;
    ipc @4;
    capability @5;
    resource @6;
    custom @7;
}

struct ResourceExhausted {
    resource @0 :SandboxResourceType;
    limit @1 :UInt64;
    current @2 :UInt64;
}

# Mirrors the ResourceLimits fields, so a backend can always name the
# limit it hit.
enum SandboxResourceType {
    cpuTime @0;
    memory @1;
    virtualMemory @2;
    processes @3;
    fileSize @4;
    custom @5;
}

# ─── Simulation / Evaluation ─────────────────────────────────────────

struct SimulationResult {
    allowed @0 :Bool;
    # Typed violations, so a consumer can act on them rather than
    # pattern-match advice strings.
    violations @1 :List(SandboxPolicyViolation);
    # Human-readable notes. Advisory by nature; a consumer is not
    # expected to parse these.
    warnings @2 :List(Text);
}

struct EvaluationResult {
    valid @0 :Bool;
    conflicts @1 :List(SandboxPolicyViolation);
    # Whether the evaluated policy can be enforced by the current
    # backend at all — the previous recommendations were free-form
    # strings with no way to tell "unsupported" from "suboptimal".
    enforceable @2 :Bool;
    recommendations @3 :List(Text);
}

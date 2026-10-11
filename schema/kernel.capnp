@0xa1b2c3d4e5f60039;

# ═══════════════════════════════════════════════════════════════════════
# Kernel — the universal kernel boundary exposed to apps.
#
# Defines what apps observe and demand of an OS kernel. The kernel is
# always backend-agnostic: a microkernel, a monolithic kernel, an exokernel,
# a sandbox runtime or a distributed-actor scheduler can satisfy this
# contract. Backends may change; the protocol does not.
#
# This schema describes the EXTERNAL interface apps see. Internal kernel
# machinery — scheduling algorithm, page-table structures, ring isolation,
# interrupt dispatch, SMP topology, inter-processor interrupts, per-CPU
# state, kernel swapping — belongs to the backend, NOT the protocol.
#
# ── THE REVAMP ─────────────────────────────────────────────────────────
#
# The header above has always said that, and the body contradicted it.
# The pre-revamp file exposed scheduler-state introspection, CLONE_*
# fork semantics, live kernel swapping, mesh networking, container and
# unikernel taxonomies, formal-proof artifacts, and four interfaces that
# hand out raw addresses — plus six (naledzi: seven) interfaces that no
# method in the protocol returned, so nothing could call them. All of it
# is gone. What remains is implementable by a microkernel with no
# scheduler knowledge, no format knowledge and one bootstrap pointer.
#
# Specifically deleted, with the reason:
#   * `introspect` + `KernelIntrospectionTarget` — the protocol queries
#     its own scheduler state (TIMELESSNESS.md:84 rules scheduler hints
#     KEEPS OUT). A backend that wants to expose internals does so in its
#     own extension schema with its own consumers.
#   * `fork` + `ForkFlag` (CLONE_FILES/CLONE_FS/CLONE_IPC/…) — POSIX
#     process creation. `spawn` is the one portable creation path; a
#     runtime-based or capability kernel has no fork to express.
#   * `TaskState` with `zombie` — replaced by the canonical
#     `T.ExecutionState` (active/blocked/suspended/terminated), shared
#     with process.capnp. A capability kernel has no zombie and must not
#     be forced to invent one (DESIGN_PRINCIPLES.md:178).
#   * `CapOperation` / `CapRights` — a second, narrower authority
#     vocabulary beside capability.capnp's `Operation`. Naledzi already
#     made this change; the canonical `Operation` is imported here.
#   * `SmpService`, `IpiService`, `PerCpuService`, `KernelSwapService`,
#     `AbSlotService`, `MultiKernelCoordinator` (and naledzi's
#     `EventSubscriptionService`) — unreachable by R8, and machinery the
#     header excludes. Nothing could obtain them; nothing did.
#   * `issueCapability` / `publishCapability` / `enterNamespace` /
#     `capabilities` — capability issuance is capability.capnp's
#     `CapabilityService.issue`, and delegation is its `attenuate` +
#     `transfer`. The kernel was a second, unenforced issuer.
#   * `registerService` — registration is discovery.capnp's `register`
#     and the handoff's `serviceEndpoints`. `resolveService` stays: the
#     kernel must resolve what it was handed.
#   * `exec` / `replace` / `enterUserspace` — three overlapping image
#     install paths with three payload shapes. One path remains.
#   * `signal` — signal DELIVERY authority is signal.capnp's
#     `SignalService.send`, the only interface with a typed delivery
#     result. Three permission checks became one.
#   * inline `Data` payloads (`IpiEvent.payload`, `exec.manifestBytes`) —
#     R2: bulk travels as T.DataHandle.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using B = import "boot.capnp";
using import "capability.capnp".Operation;

struct TaskInfo {
    id @0 :T.ProcessId;
    parent @1 :T.ProcessId;
    name @2 :Text;
    label @3 :Text;
    # Canonical execution lifecycle, shared with process.capnp.
    state @4 :T.ExecutionState;
    priority @5 :Int8;
    # Capability references this task holds, as opaque handles. The kernel
    # maps them to its internal representation; the protocol never
    # inspects them.
    capabilities @6 :List(T.CapabilityHandle);
    children @7 :List(T.ProcessId);
    createdAt @8 :T.Timestamp;
    lastScheduled @9 :T.Timestamp;
    cpuTime @10 :T.Duration;
    memoryBytes @11 :UInt64;
    # Open metadata the backend chooses to report.
}

struct RegionSpec {
    # Requested base address (zero = backend picks).
    base @0 :UInt64;
    # Length in bytes.
    length @1 :UInt64;
    # Permissions requested.
    perms @2 :T.MemoryPerms;
    # Optional backing-store target id, opaque to the protocol.
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

# What a caller waits on. A (domain, topic) pair is an opaque match key:
# the backend owns the vocabulary, and `notify` names the same pair, so
# the two ends always agree.
struct Waitable {
    domain @0 :Text;
    topic @1 :Text;
    metadata @2 :T.StringMap;
}

# The wait names WHICH waitable fired. The pre-revamp result was a bare
# enum, so a caller learned "something in domain X fired" and had to poll
# or rely on a backend convention to learn what.
struct WaitResult {
    union {
        signalled @0 :Waitable;
        timedOut @1 :Void;
        cancelled @2 :Void;
        unknown @3 :T.UnknownEvent;
    }
}

# Typed signal kind — T.SignalKind from types.capnp directly. No local
# duplication, and no POSIX numbering anywhere in the protocol.
# `payload` is a handle: a signal may carry a small blob, and it travels
# zero-copy.
struct Signal {
    kind @0 :T.SignalKind;
    payload @1 :T.DataHandle;
    metadata @2 :T.StringMap;
}

struct SpawnRequest {
    label @0 :Text;
    # The image declaration, zero-copy. A multi-megabyte manifest must
    # not be copied into an RPC message (R2).
    declaration @1 :T.DataHandle;
    args @2 :List(Text);
    env @3 :T.StringMap;
    workingDir @4 :Text;
    # A hint, not an instruction: "this task is latency-critical" or
    # "this task is background". How the backend maps that to a
    # scheduling class is its business (DESIGN_PRINCIPLES.md:79).
    priorityHint @5 :Int8;
}

struct TaskFilter {
    name @0 :T.TaskName;
    state @1 :T.ExecutionState;
    userspace @2 :Bool = true;
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

struct TaskEvent {
    union {
        started @0 :TaskInfo;
        exited @1 :ExitedTask;
        stopped @2 :TaskInfo;
        resumed @3 :TaskInfo;
        signaled @4 :SignaledTask;
        unknown @5 :T.UnknownEvent;
    }
}

# ── The kernel contract ─────────────────────────────────────────────────
# The root of the kernel domain: like `AI` in ai.capnp it is handed to the
# caller by the host (handle 1 in every capability table — see
# boot.capnp's bootstrap-capability note), so it is deliberately not
# returned by any method.

interface KernelService {
    # Task creation and termination. `spawn` is the ONE creation path.
    spawn @0 (request :SpawnRequest) -> (task :T.ProcessId);
    exit @1 (pid :T.ProcessId, exitStatus :T.ExitStatus) -> (result :T.VoidResult);

    # Task query and observation.
    getInfo @2 (pid :T.ProcessId) -> (info :TaskInfo);
    list @3 (filter :TaskFilter, page :T.Pagination) -> (tasks :List(TaskInfo), total :UInt64);
    subscribe @4 (filter :TaskFilter) -> (subscription :TaskSubscription);

    # Address space regions (memory abstraction, backend-decided
    # granularity: page size, protection keys and cache attributes are
    # the backend's business).
    mapRegion @5 (pid :T.ProcessId, spec :RegionSpec) -> (info :RegionInfo);
    unmapRegion @6 (pid :T.ProcessId, base :UInt64) -> (result :T.VoidResult);
    protectRegion @7 (pid :T.ProcessId, base :UInt64, perms :T.MemoryPerms) -> (result :T.VoidResult);
    shareRegion @8 (pid :T.ProcessId, base :UInt64, shareWith :T.ProcessId, perms :T.MemoryPerms) -> (result :T.VoidResult);
    listRegions @9 (pid :T.ProcessId, page :T.Pagination) -> (regions :List(RegionInfo), total :UInt64);

    # Synchronization primitives (kernel-level, backend-decided).
    wait @10 (target :Waitable, timeout :T.Duration) -> (result :WaitResult);
    notify @11 (target :Waitable, sig :Signal) -> (result :T.VoidResult);

    # Declare an isolation boundary for a task. What the boundary means to
    # the backend is internal; the declaration is external.
    setQuarantine @12 (targetPid :T.ProcessId, scope :T.IsolatedScope) -> T.VoidResult;

    # The ONE image-install path: stage a declared image into a task's
    # address space, then read back the entry context the loader produced.
    # (Pre-revamp: stage/replace/exec/enterUserspace, four paths.)
    stage @13 (targetPid :T.ProcessId, image :T.UserlandImage) -> T.VoidResult;
    readEntryContext @14 (targetPid :T.ProcessId) -> (ctx :T.EntryContext);

    # Resolve a service name to its endpoint. Registration is
    # discovery.capnp's job; the kernel resolves what it was handed.
    resolveService @15 (name :Text) -> (endpoint :B.HandoffEndpoint);
}

# Observation after death, stated once so no backend invents a window:
#
#   * Every holder of a TaskSubscription receives the `exited` event for
#     a task it was subscribed to, exactly once, before the subscription
#     terminates.
#   * `getInfo` keeps answering for a terminated task, reporting
#     `T.ExecutionState.terminated` and the recorded exit status, for as
#     long as the backend retains the task. It MAY eventually answer with
#     a notFound error; consumers must handle that.
#   * `list` includes terminated tasks until the backend reclaims them.
#     A caller that wants only live work filters on state.
#
# A supervisor can therefore be written portably: it learns of a death,
# reads the exit status, and does not depend on how long a backend keeps
# the corpse.

interface TaskSubscription {
    # Bounded pull: the caller states how many events it will take, so a
    # burst of spawns cannot flood one message.
    pull @0 (maxEvents :UInt32) -> (events :List(TaskEvent));
    cancel @1 () -> T.VoidResult;
}

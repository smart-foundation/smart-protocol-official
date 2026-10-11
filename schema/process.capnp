@0xa1b2c3d4e5f60018;

# ═══════════════════════════════════════════════════════════════════════
# Process — process lifecycle, observation and memory inspection.
#
# ── WHAT WAS DELETED, AND WHY ──────────────────────────────────────────
#
#   * `ProcessCredentials { uid, gid, suid, sgid, euid, egid }` — the
#     POSIX credential model verbatim. A capability kernel has no uid;
#     it had to fabricate six numbers that mean nothing. Replaced by an
#     execution context that reports the isolation boundary and the
#     capability references the process holds.
#   * `getCgroupInfo` / `setCgroupResource` / `CgroupInfo` — a Linux
#     mechanism named in the contract. Declared limits travel as the
#     canonical `T.Quota`, which is platform-neutral and already existed.
#   * `ProcessCapability { name, granted, inherited, permitted,
#     effective }` — Linux capabilities(7) as a protocol type, i.e. a
#     second access-control model beside capability.capnp. "The
#     capability system IS the access control mechanism"
#     (DESIGN_PRINCIPLES.md:399).
#   * `ProcessState` / `ThreadState` with `zombie` and `defunct` —
#     replaced by the canonical `T.ExecutionState`, shared with the
#     kernel. An actor runtime has no zombie and must not be forced to
#     emit one.
#   * `ProcessResourceType` (cpuTime, fileDescriptors, nice,
#     coreDumpSize …) — RLIMIT_* vocabulary, replaced by T.Quota.
#   * `ProcessSandboxConfig { droppedCapabilities, keptCapabilities,
#     readOnlyPaths, maskedPaths }` — a sandbox contract that duplicates
#     sandbox.capnp, with Linux capability names as free text.
#   * `getSchedulingPolicy` / `setSchedulingPolicy` + `SchedulingPolicy`
#     (normal/batch/fifo/rr/deadline) — Linux scheduling classes.
#     TIMELESSNESS.md:84 rules scheduler machinery KEEPS OUT; a caller
#     expresses intent with the priority hint in the spawn spec.
#   * `getAffinity` / `setAffinity` / `getNumaNode` / `listNumaNodes` —
#     CPU masks and topology introspection are backend internals.
#   * `kill` — signal delivery authority is signal.capnp's
#     `SignalService.send`, the only interface with a typed delivery
#     result. Three permission checks became one.
#   * `getContainerInfo` / `getWasmInfo` — a 2020 deployment topology and
#     one runtime's internals in an eternal contract.
#   * the migration block (`getMigrationConfig` … `cancelMigration`) —
#     live migration between hosts as process-contract methods.
#   * raw `UInt64` pids and `UInt8` state codes in the supervision
#     block — typed to T.ProcessId / T.FailureReport / T.EntityState.
#
# ── THE READ-MEMORY CONTRACT ───────────────────────────────────────────
#
# `readMemory` returns a T.DataHandle and MAY return a torn view of a
# region that the target is concurrently writing: the backend decides
# between stopping the target, snapshotting, or best-effort, and reports
# which it did in `MemoryRead.consistency`. A portable debugger is
# written against that declaration, not against a hope.
#
# Authority is the interface reference: holding the `Process` reference
# (or, for inspection, an `attach`-derived one) is the authority. No
# per-method token (R3).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface Process {
    # Bounded listing and lookup.
    listProcesses @0 (filter :ProcessFilter, page :T.Pagination) -> (processes :List(ProcessInfo), total :UInt64);
    getProcess @1 (pid :T.ProcessId) -> (info :ProcessInfo);

    # Create a process. The image is an opaque reference the backend
    # resolves; the protocol names no path, no format, no loader.
    spawn @2 (spec :ProcessSpawnSpec) -> (pid :T.ProcessId);

    # Wait for a process to exit. Zero timeout returns immediately with
    # the current status (does not block); non-zero blocks until exit or
    # timeout.
    wait @3 (pid :T.ProcessId, timeout :T.Duration) -> (exitStatus :T.ExitStatus);

    getEnvironment @4 (pid :T.ProcessId) -> (env :T.StringMap);
    setEnvironment @5 (pid :T.ProcessId, env :T.StringMap) -> T.VoidResult;

    # Observation. Holding the subscription IS the authority to pull.
    subscribeProcess @6 (pid :T.ProcessId) -> (subscription :ProcessSubscription);
    # Exit observation, for callers that want the notification rather than
    # a poll loop. Same subscription shape, same authority model.
    subscribeDeath @7 (pid :T.ProcessId) -> (subscription :ExitNotificationSubscription);
    getProcessStatus @8 (pid :T.ProcessId) -> (status :ProcessStatus);

    getThreads @9 (pid :T.ProcessId, page :T.Pagination) -> (threads :List(ThreadInfo), total :UInt64);
    getMemoryMap @10 (pid :T.ProcessId, page :T.Pagination) -> (regions :List(MemoryMapEntry), total :UInt64);

    # Inspection. `attach` grants the calling process the right to read
    # and write the target's memory; holding the attached reference is
    # the authority for readMemory/writeMemory, so no token is passed.
    attach @11 (pid :T.ProcessId) -> T.VoidResult;
    detach @12 (pid :T.ProcessId) -> T.VoidResult;
    readMemory @13 (pid :T.ProcessId, address :UInt64, size :UInt64) -> (read :MemoryRead);
    writeMemory @14 (pid :T.ProcessId, address :UInt64, data :T.DataHandle) -> T.VoidResult;

    # Aggregate statistics.
    getStats @15 (user :T.UserId) -> (stats :ProcessStats);
    getAccounting @16 (pid :T.ProcessId) -> (usage :T.ResourceUsage);
    getResourceAccounting @17 (pid :T.ProcessId, duration :T.Duration) -> (window :ResourceAccountingWindow);

    # ── Process groups ──────────────────────────────────────────
    listProcessGroups @18 (page :T.Pagination) -> (groups :List(ProcessGroup), total :UInt64);
    getProcessGroup @19 (groupId :T.ProcessGroupId) -> (group :ProcessGroup);
    createProcessGroup @20 (name :Text) -> (groupId :T.ProcessGroupId);
    addToGroup @21 (groupId :T.ProcessGroupId, pid :T.ProcessId) -> T.VoidResult;
    removeFromGroup @22 (groupId :T.ProcessGroupId, pid :T.ProcessId) -> T.VoidResult;
    setForegroundGroup @23 (groupId :T.ProcessGroupId) -> T.VoidResult;

    # ── Declared limits ─────────────────────────────────────────
    # Platform-neutral quota, one contract for init, service and process.
    getResourceLimits @24 (pid :T.ProcessId) -> (limits :T.Quota);
    setResourceLimit @25 (pid :T.ProcessId, limit :T.Quota) -> T.VoidResult;

    # ── Execution context ───────────────────────────────────────
    # What the process is: its isolation boundary and the capability
    # references it holds. Replaces the POSIX credential struct.
    getExecutionContext @26 (pid :T.ProcessId) -> (context :ExecutionContext);
    setExecutionContext @27 (pid :T.ProcessId, context :ExecutionContext) -> T.VoidResult;

    # ── Process tree ────────────────────────────────────────────
    # `maxDepth` 0 = this process only; 1 = direct children; the largest
    # UInt32 = the whole tree. Depth is the caller's bound, so a deep
    # tree cannot arrive unbounded.
    getProcessTree @28 (pid :T.ProcessId, maxDepth :UInt32) -> (tree :ProcessTree);

    # ── Supervision ─────────────────────────────────────────────
    # Process-level supervision, typed throughout. Service supervision
    # (restart graphs, service policies) is init.capnp's contract.
    registerSupervisor @29 (supervisor :T.ProcessId, target :T.ProcessId) -> (handle :T.ProcessGroupId);
    reportProcessFailure @30 (pid :T.ProcessId, report :T.FailureReport) -> T.VoidResult;
    respawnProcess @31 (pid :T.ProcessId) -> (respawned :T.ProcessId);
    getProcessRespawnStatus @32 (pid :T.ProcessId) -> (status :RespawnStatus);
    exitProcess @33 (reason :T.FailureReport) -> T.VoidResult;

    # ── Inspection: breakpoints and stepping ────────────────────
    # The debugger's loop is poll-shaped by nature; these are its
    # primitives, not an OS hot path.
    setBreakpoint @34 (pid :T.ProcessId, breakpoint :Breakpoint) -> (id :T.BreakpointId);
    removeBreakpoint @35 (pid :T.ProcessId, id :T.BreakpointId) -> T.VoidResult;
    listBreakpoints @36 (pid :T.ProcessId) -> (breakpoints :List(Breakpoint));
    setWatchpoint @37 (pid :T.ProcessId, watchpoint :Watchpoint) -> (id :T.BreakpointId);
    removeWatchpoint @38 (pid :T.ProcessId, id :T.BreakpointId) -> T.VoidResult;
    listWatchpoints @39 (pid :T.ProcessId) -> (watchpoints :List(Watchpoint));
    stepProcess @40 (pid :T.ProcessId) -> T.VoidResult;
    continueProcess @41 (pid :T.ProcessId) -> T.VoidResult;
}

struct ProcessSpawnSpec {
    # Opaque image reference: an app id, a manifest name, or a
    # boot-loader-provided image handle. Backend-resolved.
    imageRef @0 :Text;
    args @1 :List(Text);
    env @2 :T.StringMap;
    workingDir @3 :Text;
    # A hint, not an instruction (DESIGN_PRINCIPLES.md:79).
    priorityHint @4 :Int8;
    # Declared isolation boundary.
    isolation @5 :T.IsolatedScope;
    # Declared quota.
    quota @6 :T.Quota;
    # Open metadata the backend understands.
    metadata @7 :T.StringMap;
}

# ── Observation ─────────────────────────────────────────────────────────

struct ProcessInfo {
    pid @0 :T.ProcessId;
    ppid @1 :T.ProcessId;
    name @2 :Text;
    command @3 :Text;
    args @4 :List(Text);
    state @5 :T.ExecutionState;
    # CPU usage as fraction 0.0-1.0 (0.5 = 50% of one core).
    cpuUsage @6 :Float32;
    # Current memory usage in bytes.
    memoryUsage @7 :UInt64;
    threads @8 :UInt32;
    startTime @9 :T.Timestamp;
    user @10 :T.UserId;
    # Groups this process belongs to.
    groups @11 :List(T.ProcessGroupId);
}

struct ProcessFilter {
    name @0 :Text;
    state @1 :T.ExecutionState;
    user @2 :T.UserId;
    # Filter by minimum CPU usage (0.0-1.0). Processes below this
    # threshold are excluded.
    minCpuUsage @3 :Float32;
    # Filter by minimum memory usage in bytes.
    minMemoryUsage @4 :UInt64;
}

struct ProcessStatus {
    pid @0 :T.ProcessId;
    name @1 :Text;
    state @2 :T.ExecutionState;
    exitStatus @3 :T.ExitStatus;
    uptime @4 :T.Duration;
    memoryBytes @5 :UInt64;
    cpuTime @6 :T.Duration;
    lastFailure @7 :T.FailureReport;
}

struct ProcessStats {
    totalProcesses @0 :UInt32;
    active @1 :UInt32;
    blocked @2 :UInt32;
    suspended @3 :UInt32;
    terminated @4 :UInt32;
    # Total CPU usage across all processes (0.0-1.0 per core, so 4.0 = 4
    # cores fully utilized).
    totalCpuUsage @5 :Float32;
    # Total memory usage in bytes across all processes.
    totalMemoryUsage @6 :UInt64;
}

struct ThreadInfo {
    id @0 :T.ThreadId;
    name @1 :Text;
    state @2 :T.ExecutionState;
    # CPU usage as fraction 0.0-1.0.
    cpuUsage @3 :Float32;
}

struct MemoryMapEntry {
    start @0 :UInt64;
    end @1 :UInt64;
    perms @2 :T.MemoryPerms;
    name @3 :Text;
    # Which image or handle backs this region, if any (opaque).
    backing @4 :Text;
    metadata @5 :T.StringMap;
}

# A read of a process's memory. `consistency` says WHICH GUARANTEE the
# backend gave, so a debugger does not have to assume one.
struct MemoryRead {
    # The bytes, zero-copy.
    data @0 :T.DataHandle;
    # Open token naming the consistency the backend provided:
    # "stopped" (target halted for the read), "snapshot" (copy taken
    # atomically at some instant), "bestEffort" (target kept running and
    # the view may be torn), or a backend's own word. An unrecognised
    # value MUST be treated as "bestEffort".
    consistency @1 :Text;
    # True when the region changed while being read.
    torn @2 :Bool;
    metadata @3 :T.StringMap;
}

struct ExecutionContext {
    pid @0 :T.ProcessId;
    # The isolation boundary this process runs in.
    isolation @1 :T.IsolatedScope;
    # Capability references this process holds, reported not checked
    # here — capability.capnp is the authority contract.
    capabilities @2 :List(T.CapabilityHandle);
    # Declared quota, if any.
    quota @3 :T.Quota;
    # Open metadata: what the backend chose to report.
    metadata @4 :T.StringMap;
}

struct ProcessGroup {
    groupId @0 :T.ProcessGroupId;
    name @1 :Text;
    processes @2 :List(T.ProcessId);
    # The session this group belongs to. NOTE: this is the process-group
    # session (a job-control concept), which is not the user session in
    # session.capnp and not the handshake session in system.capnp. The
    # types are all T.SessionId because they are all opaque handles; the
    # meanings are per-domain and no consumer may move one into another.
    sessionId @3 :T.SessionId;
    foreground @4 :Bool;
}

struct ProcessTree {
    pid @0 :T.ProcessId;
    name @1 :Text;
    state @2 :T.ExecutionState;
    children @3 :List(ProcessTree);
}

struct RespawnStatus {
    pid @0 :T.ProcessId;
    # Lifecycle state of the last respawn attempt.
    state @1 :T.EntityState;
    attempts @2 :UInt32;
    # The failure that triggered the most recent respawn.
    lastFailure @3 :T.FailureReport;
    # Whether a fallback path is currently active.
    fallbackActive @4 :Bool;
    metadata @5 :T.StringMap;
}

# ── Accounting time series ──────────────────────────────────────────────

struct ResourceAccountingEntry {
    timestamp @0 :T.Timestamp;
    cpuUsage @1 :Float32;
    memoryUsage @2 :UInt64;
    ioRead @3 :UInt64;
    ioWrite @4 :UInt64;
}

struct ResourceAccountingWindow {
    pid @0 :T.ProcessId;
    interval @1 :T.Duration;
    entries @2 :List(ResourceAccountingEntry);
    # True when the window was truncated by the backend's retention.
    truncated @3 :Bool;
}

# ── Breakpoints ─────────────────────────────────────────────────────────

struct Breakpoint {
    id @0 :T.BreakpointId;
    address @1 :UInt64;
    enabled @2 :Bool;
    # Open condition token, backend-interpreted.
    condition @3 :Text;
}

struct Watchpoint {
    id @0 :T.BreakpointId;
    address @1 :UInt64;
    size @2 :UInt32;
    read @3 :Bool;
    write @4 :Bool;
    enabled @5 :Bool;
}

# ── Events ──────────────────────────────────────────────────────────────

interface ProcessSubscription {
    # Bounded pull.
    pull @0 (maxInfos :UInt32) -> (info :ProcessInfo);
    cancel @1 () -> T.VoidResult;
}

interface ExitNotificationSubscription {
    # Bounded pull.
    pull @0 (maxNotifications :UInt32) -> (notification :ExitNotification);
    cancel @1 () -> T.VoidResult;
}

struct ExitNotification {
    pid @0 :T.ProcessId;
    exitStatus @1 :T.ExitStatus;
    signal @2 :T.SignalKind;
    coreDumpFlag @3 :Bool;
    timestamp @4 :T.Timestamp;
    duration @5 :T.Duration;
    # The failure report the process left behind, if any.
    report @6 :T.FailureReport;
}

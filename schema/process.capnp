@0xa1b2c3d4e5f60018;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Process - process lifecycle, introspection, memory access.
#
# Improvements beyond the original schema:
#   - T.SignalKind replaces raw Int32 signal numbers (no POSIX assumptions).
#   - T.ExitStatus union replaces raw Int32 exit code.
#   - T.Duration for timeoutMs (was raw UInt64).
#   - T.UserId for user identification (no POSIX UID).
#   - T.ThreadId for thread identification.
#   - Subscription cancel method added.
#   - Pagination on listProcesses, getThreads, getMemoryMap (audit-3).
#   - Custom variant on ProcessState.
#   - ThreadState enum replaces bare Text for thread state.
#   - wait() zero-timeout semantics documented (audit-3).
#   - listProcesses returns total count for pagination (audit-4).
# ═══════════════════════════════════════════════════════════════════════

interface Process {
    listProcesses @0 (filter :ProcessFilter, pagination :T.Pagination) -> (processes :List(ProcessInfo), total :UInt32);
    getProcess @1 (pid :T.ProcessId) -> (info :ProcessInfo);

    spawn @2 (command :Text, args :List(Text), env :T.StringMap, workingDir :Text) -> (pid :T.ProcessId);
    kill @3 (pid :T.ProcessId, signal :T.SignalKind) -> T.VoidResult;
    # Wait for a process to exit. If timeout is zero, returns immediately
    # with current exit status (does not block). If process has not exited
    # and timeout is non-zero, blocks until exit or timeout.
    wait @4 (pid :T.ProcessId, timeout :T.Duration) -> (exitStatus :T.ExitStatus);

    getEnvironment @5 (pid :T.ProcessId) -> (env :T.StringMap);
    setEnvironment @6 (pid :T.ProcessId, env :T.StringMap) -> T.VoidResult;

    subscribeProcess @7 (pid :T.ProcessId) -> (subscription :ProcessSubscription);

    getThreads @8 (pid :T.ProcessId, pagination :T.Pagination) -> (threads :List(ThreadInfo), total :UInt32);
    getMemoryMap @9 (pid :T.ProcessId, pagination :T.Pagination) -> (regions :List(MemoryRegion), total :UInt32);

    attach @10 (pid :T.ProcessId) -> T.VoidResult;
    detach @11 (pid :T.ProcessId) -> T.VoidResult;
    readMemory @12 (pid :T.ProcessId, address :UInt64, size :UInt64) -> (data :Data);
    writeMemory @13 (pid :T.ProcessId, address :UInt64, data :Data) -> T.VoidResult;

    # Aggregate process statistics for the system or a specific user.
    getStats @14 (user :T.UserId) -> (stats :ProcessStats);

    # ─── Process Groups (Job Control) ──────────────────────────

    # List process groups.
    listProcessGroups @15 (page :T.Pagination) -> (groups :List(ProcessGroup), total :UInt32);

    # Get process group info.
    getProcessGroup @16 (groupId :T.ProcessId) -> (group :ProcessGroup);

    # Create a new process group.
    createProcessGroup @17 (name :Text) -> (groupId :T.ProcessId);

    # Add a process to a group.
    addToGroup @18 (groupId :T.ProcessId, pid :T.ProcessId) -> T.VoidResult;

    # Remove a process from a group.
    removeFromGroup @19 (groupId :T.ProcessId, pid :T.ProcessId) -> T.VoidResult;

    # Set foreground process group (for terminal job control).
    setForegroundGroup @20 (groupId :T.ProcessId) -> T.VoidResult;

    # ─── Resource Limits ───────────────────────────────────────

    # Get resource limits for a process.
    getResourceLimits @21 (pid :T.ProcessId) -> (limits :List(ResourceLimit));

    # Set resource limits for a process.
    setResourceLimit @22 (pid :T.ProcessId, limit :ResourceLimit) -> T.VoidResult;

    # ─── Scheduling ────────────────────────────────────────────

    # Get scheduling policy for a process.
    getSchedulingPolicy @23 (pid :T.ProcessId) -> (policy :SchedulingPolicy, priority :Int32);

    # Set scheduling policy for a process.
    setSchedulingPolicy @24 (pid :T.ProcessId, policy :SchedulingPolicy, priority :Int32) -> T.VoidResult;

    # ─── Capabilities ──────────────────────────────────────────

    # Get capabilities for a process.
    getCapabilities @25 (pid :T.ProcessId) -> (capabilities :List(ProcessCapability));

    # Grant a capability to a process.
    grantCapability @26 (pid :T.ProcessId, capability :ProcessCapability) -> T.VoidResult;

    # Revoke a capability from a process.
    revokeCapability @27 (pid :T.ProcessId, capabilityName :Text) -> T.VoidResult;

    # ─── Process Accounting ─────────────────────────────────────

    # Get detailed process accounting (CPU time, I/O, page faults).
    getAccounting @28 (pid :T.ProcessId) -> (accounting :ProcessAccounting);

    # ─── Container / WASM Context ──────────────────────────────

    # Get container context for a process (if running in container).
    getContainerInfo @29 (pid :T.ProcessId) -> (info :ContainerInfo);

    # Get WASM process info (if running as WASM).
    getWasmInfo @30 (pid :T.ProcessId) -> (info :WasmProcessInfo);

    # ─── Process Sandbox ───────────────────────────────────────

    # Get sandbox configuration for a process.
    getSandboxConfig @31 (pid :T.ProcessId) -> (config :ProcessSandboxConfig);

    # Set sandbox configuration for a process.
    setSandboxConfig @32 (pid :T.ProcessId, config :ProcessSandboxConfig) -> T.VoidResult;

    # ─── Process Tree ──────────────────────────────────────────

    # Get parent-child process tree.
    getProcessTree @33 (pid :T.ProcessId, maxDepth :UInt32) -> (tree :ProcessTree);

    # ─── Audit-9: Process Tracing ─────────────────────────────
    setTraceConfig @34 (pid :T.ProcessId, config :ProcessTraceConfig) -> T.VoidResult;
    getTraceConfig @35 (pid :T.ProcessId) -> (config :ProcessTraceConfig);
    setBreakpoint @36 (pid :T.ProcessId, breakpoint :Breakpoint) -> (id :UInt64);
    removeBreakpoint @37 (pid :T.ProcessId, id :UInt64) -> T.VoidResult;
    listBreakpoints @38 (pid :T.ProcessId) -> (breakpoints :List(Breakpoint));
    setWatchpoint @39 (pid :T.ProcessId, watchpoint :Watchpoint) -> (id :UInt64);
    removeWatchpoint @40 (pid :T.ProcessId, id :UInt64) -> T.VoidResult;
    listWatchpoints @41 (pid :T.ProcessId) -> (watchpoints :List(Watchpoint));
    stepProcess @42 (pid :T.ProcessId) -> T.VoidResult;
    continueProcess @43 (pid :T.ProcessId) -> T.VoidResult;

    # ─── Audit-9: Process Exit Notification ─────────────────────
    subscribeExit @44 (pid :T.ProcessId) -> (subscription :ExitNotificationSubscription);
    getExitNotification @45 (pid :T.ProcessId) -> (notification :ExitNotification);

    # ─── Audit-9: Process Affinity and NUMA ─────────────────────
    getAffinity @46 (pid :T.ProcessId) -> (affinity :ProcessAffinity);
    setAffinity @47 (pid :T.ProcessId, affinity :ProcessAffinity) -> T.VoidResult;
    getNumaNode @48 (nodeId :UInt32) -> (info :NumaNodeInfo);
    listNumaNodes @49 (pagination :T.Pagination) -> (nodes :List(NumaNodeInfo), total :UInt32);

    # ─── Audit-9: Cgroup Integration ─────────────────────────────
    getCgroupInfo @50 (pid :T.ProcessId) -> (info :CgroupInfo);
    setCgroupResource @51 (pid :T.ProcessId, info :CgroupInfo) -> T.VoidResult;

    # ─── Audit-9: Security Context ───────────────────────────────
    getSecurityContext @52 (pid :T.ProcessId) -> (context :ProcessSecurityContext);
    setSecurityContext @53 (pid :T.ProcessId, context :ProcessSecurityContext) -> T.VoidResult;

    # ─── Audit-9: Resource Accounting Time-Series ─────────────────
    getResourceAccounting @54 (pid :T.ProcessId, duration :T.Duration)
        -> (window :ResourceAccountingWindow);

    # ─── Audit-10: Process Migration ──────────────────────────────
    getMigrationConfig @55 (pid :T.ProcessId) -> (config :ProcessMigrationConfig);
    setMigrationConfig @56 (pid :T.ProcessId, config :ProcessMigrationConfig) -> T.VoidResult;
    initiateMigration @57 (pid :T.ProcessId, targetHost :Text) -> (migrationId :UInt64);
    getMigrationStatus @58 (migrationId :UInt64) -> (status :MigrationStatus);
    cancelMigration @59 (migrationId :UInt64) -> T.VoidResult;

    # Audit-5: Process Respawn
    registerSupervisor @60 (pid :UInt64) -> (handle :UInt64);
    superviseProcess @61 (supervisorHandle :UInt64, targetPid :UInt64) -> (result :T.VoidResult);
    reportProcessFailure @62 (pid :UInt64, report :Data) -> (result :T.VoidResult);
    respawnProcess @63 (pid :UInt64) -> (result :T.VoidResult);
    getProcessRespawnStatus @64 (pid :UInt64) -> (state :UInt8, attempts :UInt32);

    # ═══ Kernel Lifecycle Primitives (audit-005 Step 1) ═════════════
    # subscribeDeath: forward DeathEvent for a pid to a channel.
    # exitProcess: clean self-exit with typed FailureReport reason.
    # getProcessStatus: query current status of a process.
    subscribeDeath @65 (pid :T.ProcessId, channelId :UInt32) -> (handle :UInt64);
    exitProcess @66 (reason :T.FailureReport) -> (result :T.VoidResult);
    getProcessStatus @67 (pid :T.ProcessId) -> (status :ProcessStatus);
}

struct ProcessStats {
    totalProcesses @0 :UInt32;
    running @1 :UInt32;
    sleeping @2 :UInt32;
    stopped @3 :UInt32;
    zombie @4 :UInt32;
    # Total CPU usage across all processes (0.0-1.0 per core, so 4.0 = 4 cores fully utilized).
    totalCpuUsage @5 :Float32;
    # Total memory usage in bytes across all processes.
    totalMemoryUsage @6 :UInt64;
}

interface ProcessSubscription {
    pull @0 () -> (info :ProcessInfo);
    cancel @1 () -> T.VoidResult;
}

interface ExitNotificationSubscription {
    pull @0 () -> (notification :ExitNotification);
    cancel @1 () -> T.VoidResult;
}

struct ProcessInfo {
    pid @0 :T.ProcessId;
    ppid @1 :T.ProcessId;
    name @2 :Text;
    command @3 :Text;
    args @4 :List(Text);
    state @5 :ProcessState;
    # CPU usage as fraction 0.0-1.0 (0.5 = 50% of one core).
    cpuUsage @6 :Float32;
    # Current memory usage in bytes.
    memoryUsage @7 :UInt64;
    threads @8 :UInt32;
    startTime @9 :T.Timestamp;
    user @10 :T.UserId;
}

enum ProcessState {
    running @0;
    sleeping @1;
    waiting @2;
    stopped @3;
    zombie @4;
    defunct @5;
    custom @6;
}

struct ProcessFilter {
    name @0 :Text;
    state @1 :ProcessState;
    user @2 :T.UserId;
    # Filter by minimum CPU usage (0.0-1.0). Processes below this threshold are excluded.
    minCpuUsage @3 :Float32;
    # Filter by minimum memory usage in bytes. Processes below this threshold are excluded.
    minMemoryUsage @4 :UInt64;
}

struct ThreadInfo {
    id @0 :T.ThreadId;
    name @1 :Text;
    state @2 :ThreadState;
    # CPU usage as fraction 0.0-1.0.
    cpuUsage @3 :Float32;
}

enum ThreadState {
    running @0;
    sleeping @1;
    waiting @2;
    stopped @3;
    custom @4;
}

struct MemoryRegion {
    start @0 :UInt64;
    end @1 :UInt64;
    perms @2 :T.MemoryPerms;
    name @3 :Text;
}

# ─── Process Groups (Job Control) ─────────────────────────────

struct ProcessGroup {
    groupId @0 :T.ProcessId;
    sessionId @1 :UInt64;
    name @2 :Text;
    processes @3 :List(T.ProcessId);
    foreground @4 :Bool;
}

# ─── Resource Limits ──────────────────────────────────────────

# ProcessResourceType (distinct from sandbox.capnp ResourceType).
enum ProcessResourceType {
    cpuTime @0;
    memorySize @1;
    fileDescriptors @2;
    processes @3;
    fileSize @4;
    coreDumpSize @5;
    nice @6;
    realTimePriority @7;
    custom @8;
}

struct ResourceLimit {
    resource @0 :ProcessResourceType;
    soft @1 :UInt64;
    hard @2 :UInt64;
}

# ─── Scheduling ───────────────────────────────────────────────

enum SchedulingPolicy {
    normal @0;
    batch @1;
    idle @2;
    fifo @3;
    rr @4;
    deadline @5;
    custom @6;
}

# ─── Capabilities ─────────────────────────────────────────────

struct ProcessCapability {
    name @0 :Text;
    granted @1 :Bool;
    inherited @2 :Bool;
    permitted @3 :Bool;
    effective @4 :Bool;
}

# ─── Process Accounting ───────────────────────────────────────

struct ProcessAccounting {
    userTime @0 :T.Duration;
    systemTime @1 :T.Duration;
    ioReadBytes @2 :UInt64;
    ioWriteBytes @3 :UInt64;
    pageFaults @4 :UInt64;
    contextSwitches @5 :UInt64;
}

# ─── Container Context ────────────────────────────────────────

struct ContainerInfo {
    containerId @0 :Text;
    isolation @1 :T.IsolatedScope;
}

# ─── WASM Process Info ────────────────────────────────────────

struct WasmProcessInfo {
    instanceId @0 :Text;
    memoryPages @1 :UInt32;
    tableSize @2 :UInt32;
    exportedFunctions @3 :List(Text);
    importedFunctions @4 :List(Text);
}

# ─── Process Sandbox Configuration ────────────────────────────

struct ProcessSandboxConfig {
    isolation @0 :T.IsolatedScope;
    droppedCapabilities @1 :List(Text);
    keptCapabilities @2 :List(Text);
    readOnlyPaths @3 :List(Text);
    maskedPaths @4 :List(Text);
}

# ─── Process Tree ─────────────────────────────────────────────

struct ProcessTree {
    pid @0 :T.ProcessId;
    name @1 :Text;
    state @2 :ProcessState;
    children @3 :List(ProcessTree);
}

# ─── Process Tracing (Audit-9) ────────────────────────────────────────
struct ProcessTraceConfig {
    enableBreakpoints @0 :Bool;
    enableWatchpoints @1 :Bool;
    traceSignals @2 :Bool;
    traceSyscalls @3 :Bool;
}

struct Breakpoint {
    id @0 :UInt64;
    address @1 :UInt64;
    enabled @2 :Bool;
    condition @3 :Text;
}

struct Watchpoint {
    id @0 :UInt64;
    address @1 :UInt64;
    size @2 :UInt32;
    read @3 :Bool;
    write @4 :Bool;
    enabled @5 :Bool;
}

# ─── Process Exit Notification (Audit-9) ─────────────────────────────
struct ExitNotification {
    pid @0 :T.ProcessId;
    exitStatus @1 :T.ExitStatus;
    signal @2 :T.SignalKind;
    coreDumpFlag @3 :Bool;
    timestamp @4 :T.Timestamp;
    duration @5 :T.Duration;
}

# ─── Process Affinity and NUMA (Audit-9) ─────────────────────────────
struct ProcessAffinity {
    pid @0 :T.ProcessId;
    cpuMask @1 :UInt64;
    numaNode @2 :UInt32;
    cpuCount @3 :UInt32;
}

struct NumaNodeInfo {
    nodeId @0 :UInt32;
    memorySize @1 :UInt64;
    availableMemory @2 :UInt64;
    distance @3 :List(UInt32);
}

# ─── Process Cgroup Integration (Audit-9) ────────────────────────────
struct CgroupInfo {
    isolation @0 :T.IsolatedScope;
    quota @1 :T.Quota;
}

# ─── Process Security Context (Audit-9) ──────────────────────────────
struct ProcessSecurityContext {
    pid @0 :T.ProcessId;
    isolation @1 :T.IsolatedScope;
    credentials @2 :ProcessCredentials;
}

struct ProcessCredentials {
    uid @0 :UInt32;
    gid @1 :UInt32;
    suid @2 :UInt32;
    sgid @3 :UInt32;
    euid @4 :UInt32;
    egid @5 :UInt32;
}

# ─── Resource Accounting Time-Series (Audit-9) ────────────────────────
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
}

# ─── Process Migration (Audit-10) ────────────────────────────────────────
# Live migration of process state between hosts.
struct ProcessMigrationConfig {
    pid @0 :T.ProcessId;
    # Whether migration is allowed.
    enabled @1 :Bool;
    # Maximum downtime tolerance during migration.
    maxDowntime @2 :T.Duration;
    # Whether to preserve memory contents (vs. re-execute).
    preserveMemory @3 :Bool;
    # Whether to preserve open network connections.
    preserveConnections @4 :Bool;
    # Pre-migration checkpoint interval.
    checkpointInterval @5 :T.Duration;
}

struct MigrationStatus {
    migrationId @0 :UInt64;
    pid @1 :T.ProcessId;
    state @2 :MigrationState;
    progress @3 :Float32;
    sourceHost @4 :Text;
    targetHost @5 :Text;
    startedAt @6 :T.Timestamp;
    completedAt @7 :T.Timestamp;
    bytesTransferred @8 :UInt64;
    totalBytes @9 :UInt64;
}

enum MigrationState {
    notMigrating @0;
    preparing @1;
    checkpointing @2;
    transferring @3;
    recovering @4;
    completed @5;
    failed @6;
    cancelled @7;
}

# ═══ Process Status (audit-005 Step 1) ═══════════════════════════════
# Returned by getProcessStatus. Provides a snapshot of a process's
# current state and lifecycle metadata.

struct ProcessStatus {
    pid         @0 :T.ProcessId;
    name        @1 :Text;
    state       @2 :ProcessState;
    exitStatus  @3 :T.ExitStatus;
    uptimeNs    @4 :UInt64;
    memoryBytes @5 :UInt64;
    cpuTimeNs   @6 :UInt64;
    lastFailure @7 :T.FailureReport;
}

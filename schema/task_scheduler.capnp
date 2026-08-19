@0xa1b2c3d4e5f60057;

# ═══════════════════════════════════════════════════════════════════════
# Task Scheduler - background work scheduling with network policy,
#                 expedited jobs, flexibility windows, and task groups.
#
# Improvements beyond the original schema (audit):
#   - Constraints.networkPolicy (wifi-only / unmetered / cellular-allowed).
#   - ScheduledTask.expedited for wake-from-sleep.
#   - ScheduledTask.flexibilityWindow for battery-economy jitter.
#   - ScheduledTask.taskGroup uses T.TaskGroupId (was raw Text).
#   - SchedulerEvent.taskThrottled (was queued but blocked).
#   - ScheduledTask.deadline for long-running tasks.
#   - ScheduledTask.priority for scheduling order.
#   - TaskFilter for paginated getPendingTasks.
#   - TaskStats per task for analytics.
#   - pause/resume for task lifecycle control.
#   - All schedule duration fields use T.Duration.
#   - TaskId promoted to T.TaskId in types.capnp (cross-schema refs).
#   - All error :Text fields replaced with T.Error.
#   - All subscription interfaces have cancel method.
#   - getPendingTasks uses T.Pagination.
#   - TaskSchedule union has custom variant for forward compat.
#   - SchedulerSubscription has cancel for clean teardown.
#   - getAppTasks returns pagination info for bounded iteration.
#   - TaskFilter.taskGroup uses T.TaskGroupId (was raw Text).
#   - Audit-6: SchedulerEvent.taskDeadlineExceeded @10 with TaskDeadlineEvent.
#   - Audit-6: deleteTask @37 for hard-deletion (distinct from cancel/pause).
#
# Improvements (audit-7):
#   - EventTrigger for event-based scheduling (file, CPU, network).
#   - TaskDependency for DAG-based workflow scheduling.
#   - TaskChain for sequential task execution.
#   - ResourceRequirements for resource-aware scheduling.
#   - DecayPolicy for automatic priority adjustment.
#   - TriggerGraph for complex trigger conditions (AND/OR).
#   - PrincipalScheduler interface for multi-scheduler coordination.
#   - updateSchedule for live rescheduling without cancel.
#   - listAllTasks for querying all tasks (not just pending).
#   - getResourceUsage for capacity planning.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# TaskId is T.TaskId from types.capnp (promoted in Batch 9).
# Local definition removed; all references now use T.TaskId.

struct Constraints {
    requiresCharging @0 :Bool;
    requiresIdle @1 :Bool;
    requiresNetwork @2 :Bool;
    requiresBattery @3 :Bool;
    minBatteryLevel @4 :UInt32;
    respectDnd @5 :Bool;
    maintenanceWindowOnly @6 :Bool;
    networkPolicy @7 :NetworkPolicy;
}

enum NetworkPolicy {
    any @0;
    unmetered @1;
    wifi @2;
    cellular @3;
    notRoaming @4;
    custom @5;
}

struct ScheduledTask {
    id @0 :T.TaskId;
    app @1 :T.AppId;
    name @2 :Text;
    createdAt @3 :T.Timestamp;
    lastRunAt @4 :T.Timestamp;
    nextRunAt @5 :T.Timestamp;
    state @6 :TaskState;
    constraints @7 :Constraints;
    schedule @8 :TaskSchedule;

    runCount @9 :UInt32;
    failCount @10 :UInt32;
    lastError @11 :T.Error;

    taskGroup @12 :T.TaskGroupId;
    expedited @13 :Bool;
    flexibilityWindow @14 :T.Duration;
    deadline @15 :T.Timestamp;
    priority @16 :UInt8;
    allowForeground @17 :Bool;
    tags @18 :List(Text);

    # ── Audit-7 additions ────────────────────────────────────
    # DAG dependencies for this task.
    dependencies @19 :List(TaskDependency);
    # Resource requirements for scheduling.
    resourceRequirements @20 :ResourceRequirements;
    # Priority decay policy.
    decayPolicy @21 :DecayPolicy;
    # Chain this task belongs to (if any).
    chainId @22 :Text;
    # Event-based trigger (if using event schedule).
    eventTrigger @23 :EventTrigger;
}

enum TaskState {
    pending @0;
    queued @1;
    running @2;
    completed @3;
    failed @4;
    cancelled @5;
    blocked @6;
    paused @7;
    custom @8;
}

struct TaskSchedule {
    union {
        oneShot @0 :OneShotSchedule;
        periodic @1 :PeriodicSchedule;
        exact @2 :ExactSchedule;
        # Event-based trigger (audit-7).
        event @4 :EventTrigger;
        # Complex trigger graph (audit-7).
        graph @5 :TriggerGraph;
        # Sequential chain execution (audit-7).
        chained @6 :TaskChain;
        custom @3 :Data;
    }
}

struct OneShotSchedule {
    delay @0 :T.Duration;
}

struct PeriodicSchedule {
    interval @0 :T.Duration;
    initialDelay @1 :T.Duration;
}

struct ExactSchedule {
    runAt @0 :T.Timestamp;
    repeat @1 :T.Duration;
}

struct TaskFilter {
    app @0 :Text;
    taskGroup @1 :T.TaskGroupId;
    states @2 :List(TaskState);
    tags @3 :List(Text);
    pagination @4 :T.Pagination;
}

struct TaskStats {
    taskId @0 :T.TaskId;
    runCount @1 :UInt32;
    failCount @2 :UInt32;
    avgDuration @3 :T.Duration;
    lastRunAt @4 :T.Timestamp;
    lastDuration @5 :T.Duration;
    successRate @6 :Float32;
    totalRunTime @7 :T.Duration;
}

struct SchedulerEvent {
    union {
        taskStarted @0 :T.TaskId;
        taskCompleted @1 :T.TaskId;
        taskFailed @2 :TaskFailure;
        taskCancelled @3 :T.TaskId;
        taskThrottled @4 :TaskThrottleEvent;
        taskPaused @5 :T.TaskId;
        taskResumed @6 :T.TaskId;
        maintenanceWindowStarted @7 :T.Timestamp;
        maintenanceWindowEnded @8 :T.Timestamp;
        # Audit-6: task deadline exceeded event. Backend emits when a task
        # exceeds ScheduledTask.deadline. Wraps the runtime that exceeded.
        taskDeadlineExceeded @10 :TaskDeadlineEvent;
        custom @9 :Data;
    }
}

struct TaskDeadlineEvent {
    taskId @0 :T.TaskId;
    deadline @1 :T.Timestamp;
    ranFor @2 :T.Duration;
}

struct TaskFailure {
    taskId @0 :T.TaskId;
    error @1 :T.Error;
}

struct TaskThrottleEvent {
    taskId @0 :T.TaskId;
    reason @1 :Text;
    queueTime @2 :T.Duration;
}

interface TaskSchedulerService {
    scheduleOneShot @0 (task :ScheduledTask) -> (taskId :T.TaskId);
    schedulePeriodic @1 (task :ScheduledTask) -> (taskId :T.TaskId);
    scheduleExact @2 (task :ScheduledTask) -> (taskId :T.TaskId);

    cancel @3 (taskId :T.TaskId) -> T.VoidResult;
    cancelAll @4 (app :T.AppId) -> T.VoidResult;

    # Audit-6: hard-delete a task. Differs from cancel (mark cancelled) and
    # pause (suspended). Removes history + counters. Cannot be undone.
    deleteTask @37 (taskId :T.TaskId, retainHistory :Bool) -> T.VoidResult;

    getTask @5 (taskId :T.TaskId) -> (task :ScheduledTask);
    getPendingTasks @6 (filter :TaskFilter) -> (tasks :List(ScheduledTask), total :UInt64);
    getAppTasks @7 (app :Text, pagination :T.Pagination) -> (tasks :List(ScheduledTask), total :UInt64);

    pauseTask @8 (taskId :T.TaskId) -> T.VoidResult;
    resumeTask @9 (taskId :T.TaskId) -> T.VoidResult;

    requestImmediate @10 (taskId :T.TaskId) -> T.VoidResult;
    getTaskStats @11 (taskId :T.TaskId) -> (stats :TaskStats);

    getStats @12 () -> (stats :SchedulerStats);

    subscribe @13 () -> (subscription :SchedulerSubscription);
    cancelSubscribe @14 (subscription :SchedulerSubscription) -> T.VoidResult;

    # ── Audit-7 additions ────────────────────────────────────

    # Update a task's schedule without cancel/reschedule cycle.
    updateSchedule @15 (taskId :T.TaskId, newSchedule :TaskSchedule) -> T.VoidResult;

    # Create a sequential task chain.
    createChain @16 (chain :TaskChain) -> (chainId :Text);

    # Get the status of a task chain.
    getChainStatus @17 (chainId :Text) -> (chain :TaskChain);

    # List all tasks (not just pending) with pagination.
    listAllTasks @18 (pagination :T.Pagination) -> (tasks :List(ScheduledTask), total :UInt64);

    # Schedule an event-triggered task.
    scheduleEventTriggered @19 (task :ScheduledTask, trigger :EventTrigger) -> (taskId :T.TaskId);

    # Get current resource usage for capacity planning.
    getResourceUsage @20 () -> (usage :ResourceUsage);

    # Cancel a running chain.
    cancelChain @21 (chainId :Text) -> T.VoidResult;

    # Audit-9: task audit trail.
    getTaskAuditTrail @22 (taskId :T.TaskId, pagination :T.Pagination) -> (entries :List(TaskAuditEntry), total :UInt64);

    # Audit-9: task versioning.
    listTaskVersions @23 (taskId :T.TaskId) -> (versions :List(TaskVersion));
    getTaskVersion @24 (taskId :T.TaskId, version :UInt32) -> (v :TaskVersion);
    rollbackTask @25 (taskId :T.TaskId, toVersion :UInt32) -> T.VoidResult;

    # Audit-9: distributed scheduling.
    registerTaskNode @26 (node :TaskNode) -> T.VoidResult;
    unregisterTaskNode @27 (nodeId :Text) -> T.VoidResult;
    listTaskNodes @28 (pagination :T.Pagination) -> (nodes :List(TaskNode), total :UInt64);
    getTaskNode @29 (nodeId :Text) -> (node :TaskNode);
    distributeTask @30 (taskId :T.TaskId, nodeId :Text) -> T.VoidResult;

    # Audit-10: task priority inheritance.
    setPriorityInheritance @31 (taskId :T.TaskId, config :PriorityInheritance) -> T.VoidResult;
    getPriorityInheritance @32 (taskId :T.TaskId) -> (config :PriorityInheritance);
    # Borrow resources from lower-priority tasks for a high-priority task.
    elevateTask @33 (taskId :T.TaskId, donorTaskIds :List(T.TaskId)) -> T.VoidResult;

    # Audit-10: energy-efficient scheduling optimization.
    setEnergyPolicy @34 (policy :EnergySchedulingPolicy) -> T.VoidResult;
    getEnergyPolicy @35 () -> (policy :EnergySchedulingPolicy);
    getScheduleEnergyEstimate @36 (tasks :List(T.TaskId)) -> (estimate :EnergyEstimate);

    # Audit-10: task duration/resource prediction.
    predictTaskDuration @38 (taskId :T.TaskId) -> (prediction :TaskDurationPrediction);
    predictTaskResources @39 (taskId :T.TaskId) -> (prediction :TaskResourcePrediction);
    trainPredictionModel @40 (historicalTaskIds :List(T.TaskId)) -> T.VoidResult;
}

struct SchedulerStats {
    totalScheduled @0 :UInt32;
    totalRunning @1 :UInt32;
    totalCompleted @2 :UInt64;
    totalFailed @3 :UInt64;
    lastMaintenanceWindow @4 :T.Timestamp;
    nextMaintenanceWindow @5 :T.Timestamp;
}

interface SchedulerSubscription {
    pull @0 () -> (events :List(SchedulerEvent));
    cancel @1 () -> T.VoidResult;
}

# ── Event Trigger (audit-7) ──────────────────────────────────

struct EventTrigger {
    # Event type identifier (e.g., "fileChanged", "cpuBelow", "networkUp").
    eventType @0 :Text;
    # Source identifier for the event.
    eventSource @1 :Text;
    # Specific conditions for this trigger.
    conditions @2 :TriggerConditions;
    # Debounce interval to prevent rapid re-triggering.
    debounce @3 :T.Duration;
}

struct TriggerConditions {
    union {
        fileChanged @0 :FileChangedTrigger;
        cpuThreshold @1 :CpuThresholdTrigger;
        networkStatus @2 :NetworkStatusTrigger;
        custom @3 :Data;
    }
}

struct FileChangedTrigger {
    path @0 :T.FilePath;
    watchType @1 :WatchType;
}

enum WatchType {
    modified @0;
    created @1;
    deleted @2;
    renamed @3;
    any @4;
    custom @5;
}

struct CpuThresholdTrigger {
    # Trigger when CPU usage drops below this percentage.
    belowPercent @0 :UInt8;
    # Must be below threshold for this duration.
    duration @1 :T.Duration;
}

struct NetworkStatusTrigger {
    connected @0 :Bool;
    # Network type filter (e.g., "wifi", "ethernet", "any").
    networkType @1 :Text;
}

# ── Task Dependency (audit-7) ────────────────────────────────

struct TaskDependency {
    # Prerequisite task ID.
    dependsOn @0 :T.TaskId;
    # Condition under which this dependency is satisfied.
    condition @1 :DependencyCondition;
    # If true, failure of the prerequisite doesn't block this task.
    optional @2 :Bool;
}

enum DependencyCondition {
    # Runs after prerequisite completes (success or failure).
    completed @0;
    # Runs only if prerequisite succeeded.
    succeeded @1;
    # Runs only if prerequisite failed.
    failed @2;
    custom @3;
}

# ── Task Chain (audit-7) ─────────────────────────────────────

struct TaskChain {
    # Unique chain identifier.
    chainId @0 :Text;
    # Human-readable chain name.
    name @1 :Text;
    # Ordered list of task IDs in the chain.
    tasks @2 :List(T.TaskId);
    # What to do when a task in the chain fails.
    onFailure @3 :ChainFailurePolicy;
    # Current chain state.
    state @4 :ChainState;
}

enum ChainFailurePolicy {
    # Stop the chain on failure.
    stop @0;
    # Skip the failed task, continue with next.
    skip @1;
    # Retry the failed task before continuing.
    retry @2;
    custom @3;
}

enum ChainState {
    pending @0;
    running @1;
    completed @2;
    failed @3;
    paused @4;
    custom @5;
}

# ── Resource Requirements (audit-7) ──────────────────────────

struct ResourceRequirements {
    # Minimum memory required (MB).
    minMemoryMb @0 :UInt32;
    # Minimum CPU percentage required.
    minCpuPercent @1 :UInt8;
    # Maximum memory this task may use (MB).
    maxMemoryMb @2 :UInt32;
    # Maximum CPU percentage this task may use.
    maxCpuPercent @3 :UInt8;
    # Whether this task requires GPU access.
    requiresGpu @4 :Bool;
    # Whether this task requires network access.
    requiresNetwork @5 :Bool;
    # Resource name for mutual exclusion (only one task at a time).
    exclusiveResource @6 :Text;
}

# ── Decay Policy (audit-7) ───────────────────────────────────

struct DecayPolicy {
    # Whether priority decay is enabled.
    enabled @0 :Bool;
    # Priority reduction per hour.
    decayRate @1 :Float32;
    # Don't decay below this priority level.
    minPriority @2 :UInt8;
    # Boost priority on failure.
    boostOnFailure @3 :Bool;
    # Amount of priority boost on failure.
    boostAmount @4 :UInt8;
}

# ── Trigger Graph (audit-7) ──────────────────────────────────

struct TriggerGraph {
    # Nodes in the trigger graph.
    nodes @0 :List(TriggerNode);
    # Edges connecting trigger nodes.
    edges @1 :List(TriggerEdge);
    # Root node ID (starting point for evaluation).
    root @2 :Text;
}

struct TriggerNode {
    # Unique node identifier.
    id @0 :Text;
    # The trigger condition for this node.
    trigger @1 :EventTrigger;
    # Whether to negate the trigger result.
    negate @2 :Bool;
}

struct TriggerEdge {
    # Source node ID.
    from @0 :Text;
    # Target node ID.
    to @1 :Text;
    # How to combine source and target triggers.
    operator @2 :TriggerOperator;
}

enum TriggerOperator {
    # Both triggers must be true.
    and @0;
    # Either trigger must be true.
    or @1;
    # Target triggers after source completes.
    sequential @2;
    custom @3;
}

# ── Resource Usage (audit-7) ─────────────────────────────────

struct ResourceUsage {
    cpuPercent @0 :UInt8;
    memoryMb @1 :UInt32;
    activeTasks @2 :UInt32;
    queuedTasks @3 :UInt32;
}

# ── Audit-9: Task Audit Trail ─────────────────────────────────────────

struct TaskAuditEntry {
    taskId @0 :T.TaskId;
    timestamp @1 :T.Timestamp;
    action @2 :TaskAuditAction;
    details @3 :Text;
}

enum TaskAuditAction {
    scheduled @0;
    started @1;
    completed @2;
    failed @3;
    cancelled @4;
    skipped @5;
    retried @6;
    custom @7;
}

# ── Audit-9: Task Versioning ───────────────────────────────────────────

struct TaskVersion {
    version @0 :UInt32;
    taskId @1 :T.TaskId;
    createdAt @2 :T.Timestamp;
    definition @3 :Data;
    changelog @4 :Text;
}

# ── Audit-9: Distributed Scheduling ─────────────────────────────────

struct TaskNode {
    nodeId @0 :Text;
    address @1 :Text;
    capacity @2 :UInt32;
    load @3 :UInt32;
    available @4 :Bool;
}

# ── Audit-10: Priority Inheritance ──────────────────────────────────────
# High-priority tasks can borrow resources from lower-priority tasks.
struct PriorityInheritance {
    enabled @0 :Bool;
    # Minimum priority of donors (only borrow from tasks below this).
    donorMinPriority @1 :UInt8;
    # Maximum amount of resources to borrow (fraction 0.0-1.0).
    maxBorrowFraction @2 :Float32;
    # Whether to return borrowed resources when donor needs them.
    preemptiveReturn @3 :Bool;
    # Timeout for borrowed resources.
    borrowTimeout @4 :T.Duration;
}

# ── Audit-10: Energy Scheduling Policy ───────────────────────────────────
# Energy-efficient schedule optimization.
struct EnergySchedulingPolicy {
    enabled @0 :Bool;
    # Target energy budget per day.
    dailyBudgetJoules @1 :UInt64;
    # Schedule batches during off-peak hours.
    offPeakBatching @2 :Bool;
    # Off-peak start hour (0-23).
    offPeakStartHour @3 :UInt8;
    # Off-peak end hour (0-23).
    offPeakEndHour @4 :UInt8;
    # Defer non-urgent tasks when on battery.
    deferOnBattery @5 :Bool;
    # Minimum battery level to run non-urgent tasks (0-100).
    minBatteryLevel @6 :UInt8;
}

struct EnergyEstimate {
    estimatedJoules @0 :UInt64;
    estimatedCo2Grams @1 :Float32;
    offPeakScore @2 :Float32;
    scheduleQuality @3 :Float32;
}

# ── Audit-10: Task Prediction ────────────────────────────────────────────
# Predict task duration and resource usage using historical data.
struct TaskDurationPrediction {
    predictedDuration @0 :T.Duration;
    confidence @1 :Float32;
    minDuration @2 :T.Duration;
    maxDuration @3 :T.Duration;
    basedOnSampleCount @4 :UInt32;
}

struct TaskResourcePrediction {
    predictedMemoryMb @0 :UInt32;
    predictedCpuPercent @1 :UInt8;
    confidence @2 :Float32;
    basedOnSampleCount @3 :UInt32;
}

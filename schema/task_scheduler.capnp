@0xa1b2c3d4e5f60057;

# ═══════════════════════════════════════════════════════════════════════
# Task scheduler — declarative background work with constraints.
#
# The scheduling core is a legitimate external contract: declare a piece
# of background work, say when it may run and under what constraints,
# cancel or pause it, and watch it happen. That is the doctrine's
# "declare resource limits" family (DESIGN_PRINCIPLES.md:70), and it is
# what this file keeps.
#
# ── THE DISTRIBUTED SCHEDULER PLATFORM, DELETED ────────────────────────
#
# The pre-revamp file grew a distributed platform around that core:
# machine-learning duration and resource prediction with a training
# method, RTOS priority inheritance with donor borrowing, an electricity
# market (joule budgets, off-peak hours, CO₂ grams), multi-node task
# distribution with a node registry, task versioning with rollback, and
# an audit trail.
#
# None of it has a consumer, and each is a policy the OS or the operator
# owns internally: TIMELESSNESS.md:84 rejects scheduler hints from the
# protocol, and a microkernel or embedded scheduler has no model store to
# train and no electricity price to consult. A 2046 scheduler that
# predicts analytically, or not at all, had to stub four methods.
#
# Deleted with them: `TaskDurationPrediction`, `TaskResourcePrediction`,
# `PriorityInheritance`, `EnergySchedulingPolicy`, `EnergyEstimate`,
# `TaskNode` + `registerTaskNode`/`unregisterTaskNode`/`listTaskNodes`/
# `getTaskNode`/`distributeTask`, `TaskVersion` + `listTaskVersions`/
# `getTaskVersion`/`rollbackTask`, `TaskAuditEntry` +
# `getTaskAuditTrail`, `TaskChain`/`ChainState`/`ChainFailurePolicy` +
# `createChain`/`getChainStatus`/`cancelChain`, and `TriggerGraph`/
# `TriggerNode`/`TriggerEdge`/`TriggerOperator`.
#
# ── THE NAME COLLISIONS, FIXED ─────────────────────────────────────────
#
#   * `TaskState` — identical name to kernel.capnp's, different members,
#     and the two `running`s mean different things (on-CPU now vs.
#     executing a job between pauses). This one is a JOB lifecycle and is
#     now named `TaskState`.
#   * `ScheduledTaskFilter` — identical name to kernel.capnp's. Now `ScheduledTaskFilter`.
#   * `ResourceUsage` — identical name to types.capnp's, disjoint shape.
#     Now `SchedulerResourceUsage`.
#
# ── THE OTHER FIXES ────────────────────────────────────────────────────
#
#   * ONE workflow algebra instead of three overlapping ones
#     (`TaskDependency`, `TaskChain`, `TriggerGraph`): the dependency DAG
#     with conditions subsumes chains, and a plain trigger subsumes the
#     graph. `TriggerGraph` and `TaskChain` are deleted.
#   * `ScheduledTaskFilter.app :Text` beside `ScheduledTask.app :T.AppId` — filter
#     by string, store by id, so a filter silently matches nothing after a
#     rename. The id is used everywhere now.
#   * `ExactSchedule.runAt :T.Timestamp` — wall-clock scheduling with no
#     monotonic fallback: a clock jump fires the job twice or never. Now a
#     monotonic anchor plus an OPTIONAL wall-clock hint, and the behaviour
#     is declared.
#   * periodic-overlap policy was undefined (skip, overlap, queue?). Now
#     `PeriodicSchedule.onOverlap`, declared.
#   * `elevateTask`/`getScheduleEnergyEstimate` took unbounded
#     `List(T.TaskId)`; every list parameter is now bounded.
#   * `SchedulerSubscription.pull` was unbounded. Now a stated bound.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

struct TaskConstraints {
    requiresCharging @0 :Bool;
    requiresIdle @1 :Bool;
    requiresNetwork @2 :Bool;
    requiresBattery @3 :Bool;
    # Minimum battery level, 0-100 (zero = no requirement).
    minBatteryLevel @4 :UInt32;
    respectDnd @5 :Bool;
    maintenanceWindowOnly @6 :Bool;
    # Network requirement as an OPEN token ("any", "unmetered", "wifi",
    # or a 2046 one) rather than a closed ladder of today's transports.
    networkPolicy @7 :Text;
    metadata @8 :T.StringMap;
}

struct ScheduledTask {
    id @0 :T.TaskId;
    # Opaque reference to the declaring entity — an app, a service, or a
    # caller-chosen token. The protocol does not resolve it.
    app @1 :T.AppId;
    name @2 :Text;
    createdAt @3 :T.Timestamp;
    lastRunAt @4 :T.Timestamp;
    # Monotonic anchor for the next run, so a clock jump cannot fire the
    # job twice or never.
    nextRunAt @5 :T.MonotonicTimestamp;
    # OPTIONAL wall-clock hint the backend chose to report. Never
    # authoritative: a consumer must not schedule against it.
    nextRunWallClock @6 :T.Timestamp;
    state @7 :TaskState;
    constraints @8 :TaskConstraints;
    schedule @9 :TaskSchedule;

    runCount @10 :UInt32;
    failCount @11 :UInt32;
    lastError @12 :T.Error;

    taskGroup @13 :T.TaskGroupId;
    # A hint, not an instruction (DESIGN_PRINCIPLES.md:79).
    expedited @14 :Bool;
    flexibilityWindow @15 :T.Duration;
    deadline @16 :T.MonotonicTimestamp;
    priority @17 :UInt8;
    allowForeground @18 :Bool;
    tags @19 :List(Text);

    # DAG dependencies for this task — the one workflow algebra.
    dependencies @20 :List(TaskDependency);
    # Resource requirements for scheduling (declared, not negotiated).
    resourceRequirements @21 :ResourceRequirements;
    # What happens when the job overruns its interval.
    overlapPolicy @22 :OverlapPolicy;
}

# The job lifecycle. Named `TaskState` because kernel.capnp's `TaskState`
# was a different concept under the same name, and codegen collides.
enum TaskState {
    unknown @0;
    pending @1;
    queued @2;
    running @3;
    completed @4;
    failed @5;
    cancelled @6;
    blocked @7;
    paused @8;
    custom @9;
}

enum OverlapPolicy {
    unknown @0;
    # Do not start a run while the previous one is still running.
    skip @1;
    # Start anyway; the backend may run several concurrently.
    allowOverlap @2;
    # Start anyway, and cancel the previous run.
    replace @3;
    custom @4;
}

struct TaskSchedule {
    union {
        oneShot @0 :OneShotSchedule;
        periodic @1 :PeriodicSchedule;
        # Monotonic anchor plus an optional wall-clock hint.
        exact @2 :ExactSchedule;
        # Event-based trigger.
        event @3 :EventTrigger;
        custom @4 :Data;
        unknown @5 :T.UnknownEvent;
    }
}

struct OneShotSchedule {
    # Delay from the moment of scheduling.
    delay @0 :T.Duration;
}

struct PeriodicSchedule {
    interval @0 :T.Duration;
    initialDelay @1 :T.Duration;
    # What happens when a run overruns the interval. Declared, so no
    # backend invents an overlap policy a battery app could not predict.
    onOverlap @2 :OverlapPolicy;
    # Stop after this many runs (zero = run forever).
    maxRuns @3 :UInt32;
}

struct ExactSchedule {
    # Monotonic anchor: the job fires at this offset from boot.
    runAtMonotonic @0 :T.MonotonicTimestamp;
    # Optional wall-clock hint. If the clock jumps, the monotonic anchor
    # governs and the job fires exactly once.
    runAtWallClock @1 :T.Timestamp;
    repeat @2 :T.Duration;
    # What the backend does when the wall clock and the monotonic clock
    # disagree by more than `clockSkewTolerance`: report, honour the
    # monotonic anchor, or skip the run. Declared, not invented.
    onClockJump @3 :ClockJumpPolicy;
    clockSkewTolerance @4 :T.Duration;
}

enum ClockJumpPolicy {
    unknown @0;
    honourMonotonic @1;
    skipRun @2;
    reschedule @3;
    custom @4;
}

struct EventTrigger {
    # Open event token (a file change, a device arrival, a network
    # transition). The vocabulary is the backend's; unknown tokens are
    # ignored by consumers.
    eventKind @0 :Text;
    # Debounce window, so a burst of events yields one run.
    debounce @1 :T.Duration;
    # Optional conditions the event must satisfy.
    conditions @2 :TriggerConditions;
}

struct TriggerConditions {
    # Open key/value the event must carry. Matching is backend-defined.
    matchMetadata @0 :T.StringMap;
    # Minimum time between runs.
    minInterval @1 :T.Duration;
}

# The one workflow algebra: a dependency edge with a declared condition.
struct TaskDependency {
    taskId @0 :T.TaskId;
    # What must hold before this task may run.
    condition @1 :DependencyCondition;
    # How long to wait for the dependency before failing the task.
    waitTimeout @2 :T.Duration;
}

enum DependencyCondition {
    unknown @0;
    # The dependency completed successfully.
    succeeded @1;
    # The dependency finished (success or failure).
    finished @2;
    # The dependency failed.
    failed @3;
    custom @4;
}

struct ResourceRequirements {
    # Declared maximum memory, in bytes (zero = none declared).
    maxMemoryBytes @0 :UInt64;
    # Declared maximum wall-clock per run.
    maxRunDuration @1 :T.Duration;
    # Whether the job needs the network (an intent, not a mechanism).
    needsNetwork @2 :Bool;
}

# The scheduler's own resource picture. Named to avoid the collision with
# types.capnp's `ResourceUsage` (which is a per-entity sample; this is the
# scheduler's capacity view).
struct SchedulerResourceUsage {
    # Fraction of capacity in use, 0.0-1.0 (zero = not measured).
    utilization @0 :Float32;
    runningTasks @1 :UInt32;
    queuedTasks @2 :UInt32;
    # Whether the backend can measure utilization at all. A backend that
    # cannot reports false rather than a fabricated number.
    measurable @3 :Bool;
    metadata @4 :T.StringMap;
}

struct ScheduledTaskFilter {
    # Typed app identity — the pre-revamp filter used Text, so filters
    # silently matched nothing after a rename.
    app @0 :T.AppId;
    taskGroup @1 :T.TaskGroupId;
    states @2 :List(TaskState);
    tags @3 :List(Text);
    pagination @4 :T.Pagination;
    metadata @5 :T.StringMap;
}

struct TaskStats {
    taskId @0 :T.TaskId;
    runCount @1 :UInt32;
    failCount @2 :UInt32;
    # Mean duration over the retained window. A backend that cannot
    # measure duration leaves this zero and says so in `measurable`.
    avgDuration @3 :T.Duration;
    measurable @4 :Bool;
    lastRunAt @5 :T.Timestamp;
    lastDuration @6 :T.Duration;
    totalRunTime @7 :T.Duration;
}

struct TaskFailure {
    taskId @0 :T.TaskId;
    error @1 :T.Error;
    at @2 :T.MonotonicTimestamp;
}

struct TaskDeadlineEvent {
    taskId @0 :T.TaskId;
    deadline @1 :T.MonotonicTimestamp;
    ranFor @2 :T.Duration;
}

struct TaskThrottleEvent {
    taskId @0 :T.TaskId;
    # Open reason token.
    reason @1 :Text;
    queueTime @2 :T.Duration;
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
        maintenanceWindowStarted @7 :T.MonotonicTimestamp;
        maintenanceWindowEnded @8 :T.MonotonicTimestamp;
        # Emitted when a job overruns its declared deadline.
        taskDeadlineExceeded @9 :TaskDeadlineEvent;
        custom @10 :Data;
        unknown @11 :T.UnknownEvent;
    }
}

struct SchedulerStats {
    totalScheduled @0 :UInt32;
    running @1 :UInt32;
    pending @2 :UInt32;
    # Mean queue wait over the retained window (zero = not measured).
    avgQueueTime @3 :T.Duration;
    measurable @4 :Bool;
}

# ── The scheduler contract ──────────────────────────────────────────────
# The root of the scheduling domain: handed to the caller by the host, so
# it is deliberately not returned by any method. `SchedulerSubscription`
# IS returned (by `subscribe`), so every interface here is reachable.
#
# Every list parameter is bounded: `T.TaskId` is caller-chosen, so an
# unbounded list would let a caller hand the scheduler 100k ids and make
# it either bound or stream. The bound is stated in the parameter.

interface TaskSchedulerService {
    scheduleOneShot @0 (task :ScheduledTask) -> (taskId :T.TaskId);
    schedulePeriodic @1 (task :ScheduledTask) -> (taskId :T.TaskId);
    # Monotonic-anchored scheduling. `ExactSchedule.onClockJump` says what
    # happens when the wall clock moves.
    scheduleExact @2 (task :ScheduledTask) -> (taskId :T.TaskId);
    scheduleEventTriggered @3 (task :ScheduledTask, trigger :EventTrigger) -> (taskId :T.TaskId);

    # Cancel marks the job cancelled and keeps its history.
    cancel @4 (taskId :T.TaskId) -> T.VoidResult;
    # Hard delete removes history and counters. Cannot be undone.
    deleteTask @5 (taskId :T.TaskId, retainHistory :Bool) -> T.VoidResult;
    cancelAll @6 (app :T.AppId) -> T.VoidResult;

    getTask @7 (taskId :T.TaskId) -> (task :ScheduledTask);
    getPendingTasks @8 (filter :ScheduledTaskFilter) -> (tasks :List(ScheduledTask), total :UInt64);
    getAppTasks @9 (app :T.AppId, pagination :T.Pagination) -> (tasks :List(ScheduledTask), total :UInt64);
    listAllTasks @10 (pagination :T.Pagination) -> (tasks :List(ScheduledTask), total :UInt64);

    pauseTask @11 (taskId :T.TaskId) -> T.VoidResult;
    resumeTask @12 (taskId :T.TaskId) -> T.VoidResult;
    requestImmediate @13 (taskId :T.TaskId) -> T.VoidResult;

    getTaskStats @14 (taskId :T.TaskId) -> (stats :TaskStats);
    getStats @15 () -> (stats :SchedulerStats);
    getResourceUsage @16 () -> (usage :SchedulerResourceUsage);

    # Update a task's schedule without a cancel/reschedule cycle.
    updateSchedule @17 (taskId :T.TaskId, newSchedule :TaskSchedule) -> T.VoidResult;

    # Live stream. Holding the subscription IS the authority to pull.
    subscribe @18 (filter :ScheduledTaskFilter) -> (subscription :SchedulerSubscription);
    cancelSubscribe @19 (subscription :SchedulerSubscription) -> T.VoidResult;
}

interface SchedulerSubscription {
    # Bounded pull: the caller states how many events it will take, so a
    # retry storm or a backlog cannot dump the whole queue into one
    # message.
    pull @0 (maxEvents :UInt32) -> (events :List(SchedulerEvent), total :UInt64);
    cancel @1 () -> T.VoidResult;
}

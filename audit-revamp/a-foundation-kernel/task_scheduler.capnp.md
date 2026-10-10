# Audit — task_scheduler.capnp (575 lines)

## Verdict
**FIX (targeted).** The scheduling core — `ScheduledTask` with typed constraints, three schedule shapes in one union, cancel/pause/resume, subscription, `deleteTask` distinguished from cancel (`task_scheduler.capnp:207-209`) — is a legitimate external contract (the doctrine's "Add quota/resource limits … KEEPS IN" family: background work with declared constraints). The Audit-7/9/10 growth then welds on a *distributed scheduler platform*: ML duration prediction, resource-borrowing priority inheritance, multi-node task distribution, energy-market scheduling. Two name collisions (`TaskState`, `TaskFilter` with `kernel.capnp`; `ResourceUsage` with `types.capnp`) and one internal inconsistency (`ScheduledTask.app :T.AppId` vs `TaskFilter.app :Text`) round out the fix list.

## Wire-breakers
None: ordinals unique (`@0..@40`), all `T.*` resolve.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R6 | `task_scheduler.capnp:104-114` `TaskState { pending, queued, running, completed, failed, cancelled, blocked, paused, custom }` vs `kernel.capnp:51-67` `TaskState` | Same type name, different members, two files — one means "kernel-visible execution state", the other "job lifecycle" | Codegen collision on any consumer importing both; and semantically, `running` means different things (on-CPU now vs. executing a job between pauses). Fix: rename the scheduler's to `JobState` or share one canonical type from `types.capnp` |
| R6 | `task_scheduler.capnp:474-479` `ResourceUsage { cpuPercent, memoryMb, activeTasks, queuedTasks }` vs `types.capnp:892-901` `ResourceUsage { cpuTime, memoryBytes, … acquiredAt }` | Same name, disjoint shapes | The `getResourceUsage @20` return value shadows the canonical resource-usage type; telemetry consumers importing both get conflicting symbols |
| R1 / 2046 test | `task_scheduler.capnp:576-...` `predictTaskDuration @38`, `predictTaskResources @39`, `trainPredictionModel @40 (historicalTaskIds)` | ML training + inference as OS-scheduler contract methods | A microkernel or embedded scheduler has no model store; a 2046 scheduler that predicts by other means (analytic, quantum-scheduled) has no ordinal. Fork risk: `TaskDurationPrediction.confidence @1` semantics are undefined (confidence in what interval?) |
| R1 / over-specification | `task_scheduler.capnp:523-533` `PriorityInheritance` (donor borrowing), `:537-551` `EnergySchedulingPolicy` (dailyJoule budget, off-peak hours, CO₂ grams `:553-558`), `:513-519` `TaskNode`/`distributeTask @30` | RTOS priority-inheritance + electricity-market scheduling + multi-node distribution as one interface | 2046 test: a device with no battery, no carbon accounting, and no peer nodes must implement `getScheduleEnergyEstimate @36`. Each knob is a policy the kernel/datacenter owns internally (TIMELESSNESS.md:84 rejects scheduler hints) |
| R7 (soft) | `task_scheduler.capnp:164-180` `SchedulerEvent` union | `custom @9 :Data` without `typeId` — the ai.capnp `UnknownEvent { typeId, payload }` shape is the standard; a bare Data custom is not self-describing | A backend forwarding a foreign event kind gives the consumer untyped bytes; a generic consumer cannot even log what it skipped |
| R4 / UX | `task_scheduler.capnp:146` `TaskFilter.app @0 :Text` vs `:70` `ScheduledTask.app @1 :T.AppId`; `:213` `getAppTasks (app :Text …)` | Filter-by-string vs store-by-id | A consumer must know app *names* to filter but *ids* to interpret results; the string is backend-assigned and unversioned. Demonstrated trap: filters silently match nothing after an app rename |
| R7 | `task_scheduler.capnp:290-293` `SchedulerSubscription.pull () -> (events :List(SchedulerEvent))` | Unbounded pull, no pagination/total (contrast `getPendingTasks` which returns total `:212`) | A retry storm or periodic backlog dumps the entire queue into one message |

## Duplicates & overlaps
- `TaskState` ↔ `kernel.capnp:51`; `TaskFilter` ↔ `kernel.capnp:217`; `ResourceUsage` ↔ `types.capnp:892`.
- Watch semantics: `FileChangedTrigger.watchType :WatchType` (`:317-329`) duplicates file-watching contracts in `files.capnp` (out of batch) — the scheduler should consume that primitive, not re-declare `modified/created/deleted/renamed/any`.
- `TaskDependency` (`:346-353`) vs `init.capnp:53` `ServiceSpec.depends :List(T.ServiceName)` vs `service.capnp:267-272` `ServiceDependency` — three dependency grammars (task DAG with conditions, service name list, typed edges).
- Chain/DAG scheduling: `TaskChain` (`:367-378`), `TriggerGraph` (`:435-442`), `TaskDependency` (`:346-353`) — three overlapping workflow mechanisms in one file; pick one (dependency DAG subsumes chains; graphs subsume both).

## Gaps & holes
- No declared behavior when a periodic task's runtime exceeds its interval (skip, overlap, queue?) — `TaskStats.totalRunTime` exists but no contract. Demonstrated fork: every backend invents overlap policy; a battery app's behavior diverges across devices.
- No maximum declared for `List(T.TaskId)` parameters (`elevateTask @33`, `getScheduleEnergyEstimate @36`, `trainPredictionModel @40` `:268`, `:273`, `:278`) — bulk lists with no pagination; and `T.TaskId` is caller-chosen, so a malicious caller can pass 100k ids and the contract must either bound or stream.
- `ExactSchedule.runAt :T.Timestamp` (`:141-143`): wall-clock scheduling with no monotonic fallback — a clock jump (NTP, timezone) makes the task fire twice or never; `T.MonotonicTimestamp` exists (`types.capnp:111`) precisely for this.

## Zero-cost / eco
- `EventTrigger.debounce @3 :T.Duration` (`:305`) — good eco thinking, keep.
- `Constraints.maintenanceWindowOnly @6` (`:55`) + `respectDnd @5` — genuine eco/waste-avoidance affordances; the right kind of constraint.
- Energy features (`:537-558`) are eco-flavored but over-specified (joule budgets, CO₂ grams, off-peak hours are policy); the eco win is already in `Constraints`. Recommend keeping the constraints and deleting the policy machinery.

## UX & implementer guidance
- The header's numbered audit log (`:7-40`) is thorough — but it teaches the audit's history, not the contract's rules; a reader cannot tell which fields are semantically load-bearing.
- `deleteTask @37 (retainHistory :Bool)` (`:209`) is well-distinguished from cancel — good doctrine (state vs. history).
- `TaskStats.successRate @6 :Float32` (`:160`): no definition (over which window? weighted?). Name the window or use a struct with counts (`runCount`/`failCount` are already in `ScheduledTask` — the same data, duplicated at `:153-162`).

## Recommended actions
1. **Rename `TaskState`→`JobState`, `TaskFilter`→`JobFilter`, `ResourceUsage`→`SchedulerResourceUsage`** (`:104`, `:145`, `:474`). Gain: kills three cross-file name collisions (kernel ×2, types ×1); cost: find/replace, free pre-release.
2. **Delete Audit-9/10 distributed + ML + energy-policy block** (`:249-279` audit trail/versioning/distribution/priority-inheritance/energy/prediction). Gain: a single-device implementable scheduler; removes ~10 speculative enums/structs; cost: none (no consumers; and these are OS-internal policies the doctrine excludes).
3. **Unify workflow mechanisms**: keep `TaskDependency` (conditions), delete `TaskChain` and `TriggerGraph` (`:367-442`, `:124-126`). Gain: one scheduling algebra; cost: two union variants + two method pairs retired.
4. **`ExactSchedule.runAt` → monotonic-relative with wall-clock hint** or document clock-jump behavior; define periodic-overlap policy; bound list parameters. Gain: closes three forks (double-fire, overlap abuse, unbounded ids); cost: one field + spec text.
5. **Unify `app` identity** (`T.AppId` everywhere, `:146`, `:213`) and define `successRate`'s window or delete the derived fields (`:153-162` duplicates `ScheduledTask` counters). Gain: removes the rename-breaks-filters trap; cost: mechanical.

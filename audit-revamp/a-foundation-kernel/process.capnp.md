# Audit — process.capnp (499 lines)

## Verdict
**FIX (targeted).** The lifecycle core is honest and largely correct: `T.SignalKind`/`T.ExitStatus`/`T.Duration`/`T.UserId` usage (the header's claims are true), subscription+cancel, pagination, documented `wait` semantics (`process.capnp:28-31`). Four defects cut against the doctrine the schema itself cites: (1) `ProcessCredentials` (`:422-429`) is the POSIX uid/gid/suid/sgid/euid/egid struct verbatim — the exact model capability-based kernels do not have, and DESIGN_PRINCIPLES.md:177 orders it replaced; (2) cgroup integration (`getCgroupInfo @50`, `setCgroupResource @51`, `CgroupInfo` `:410-413`) names a Linux mechanism in a required position; (3) `readMemory @12` returns inline `Data` (`:43`) — the batch's clearest R2 zero-copy violation on a high-volume path; (4) `ProcessState` (`:217-225`) still contains `zombie`/`defunct`, the POSIX states the doctrine's own summary slated for renaming in 2026.

## Wire-breakers
None. Ordinals unique (`@0..@67`), all `T.*` resolve.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R5 | `process.capnp:422-429` `ProcessCredentials { uid, gid, suid, sgid, euid, egid :UInt32 }` | POSIX credential model in a required position | seL4/Fuchasia-style capability kernels have no uid/gid; `getSecurityContext @52` must fabricate six numbers that mean nothing. Demonstrated swap-test failure: Linux → capability kernel breaks this method for every caller |
| R5 | `process.capnp:145-146` `getCgroupInfo`/`setCgroupResource`, `:410-413` `CgroupInfo { isolation, quota }` | Linux cgroup named in the contract | A non-Linux backend must map cgroups onto `T.Quota` (`types.capnp:1776` — which already exists and is platform-neutral). Two quota contracts, one leaky. 2046: cgroups are a 2008 mechanism |
| R5 / R1 | `process.capnp:305-311` `ProcessCapability { name, granted, inherited, permitted, effective }` | Linux `capabilities(7)` model (permitted/effective/inherited) as a protocol type | The doctrine: "The capability system IS the access control mechanism" (DESIGN_PRINCIPLES.md:399). This is a second, POSIX-shaped access-control model parallel to `capability.capnp`. An implementer must build both and keep them agreeing |
| R2 | `process.capnp:43` `readMemory (pid, address, size) -> (data :Data)` ; `:44` `writeMemory (… data :Data)` | Bulk memory payload inline in the message | Copy cost on the highest-volume path: a debugger or crash-handler dumping a 512 MB address space copies 512 MB into the RPC message; the receiver copies again to place it. `T.DataHandle` exists and is used correctly by `queue.capnp:152` — this one method ignores it |
| R1 | `process.capnp:217-225` `ProcessState { running, sleeping, waiting, stopped, zombie, defunct, custom }` | `zombie`/`defunct` are Unix lifecycle states; `defunct` is a synonym, not a state | The doctrine's own fix (universal: active/blocked/suspended/terminated — DESIGN_PRINCIPLES.md:178, TIMELESSNESS.md:77) was never applied. An actor-runtime backend must emit `zombie` for a state it does not have, or extend an eternal enum |
| R4 / UX | `process.capnp:164-168` `registerSupervisor (pid :UInt64)`, `superviseProcess (supervisorHandle :UInt64, targetPid :UInt64)`, `reportProcessFailure (pid :UInt64)`, `respawnProcess`, `getProcessRespawnStatus (state :UInt8)` | Raw `UInt64` PIDs and `UInt8` state in five methods whose siblings all use `T.ProcessId` / typed failures | Implementer trap: byte `state` codes are backend-private; `:166` `report :Data` ignores `T.FailureReport` (`types.capnp:1878`). Two pid spellings on one interface |
| R6 | `process.capnp:217-225` `ProcessState` vs `kernel.capnp:51-67` `TaskState` (newBorn..zombie) vs `:245-251` `ThreadState` | Three lifecycle enums, overlapping POSIX vocabulary, three homes | A monitoring tool must consult three schemas to answer "what state is this execution in," and each answer uses different words for `running` |
| R1 | `process.capnp:273-283` `ProcessResourceType { cpuTime, memorySize, fileDescriptors, processes, fileSize, coreDumpSize, nice, realTimePriority }` | POSIX rlimit vocabulary (`nice`, `coreDumpSize`, `fileDescriptors`) | A WASM or capability sandbox has none of these; limits must be faked. `fileDescriptors` in particular assumes an fd-based OS |

## Duplicates & overlaps
- Exit observation: `subscribeExit @44`/`getExitNotification @45` (`:135-136`) vs `kernel.capnp:235-243` `TaskEvent.exited` vs `signal.capnp:107` subscription — three exit-event paths.
- Death forwarding: `subscribeDeath @65 (channelId :UInt32)` (`:174`) vs `init.capnp:163` same name, same raw channel-id pattern.
- Supervision: `registerSupervisor @60-@64` (`:164-168`) vs `init.capnp:135-140` `registerService`/`setServicePolicy` — parallel respawn registries.
- `ProcessGroup.sessionId @1 :UInt64` (`:264`) vs `T.SessionId` (`types.capnp:6`) — a third "session" sense (process group leader session ≠ user session ≠ system handshake session).

## Gaps & holes
- `readMemory @12` has no consistency contract: can a torn read occur while the target runs? Every backend will invent an answer (stop-the-world vs. best-effort), and a debugger cannot be written portably. Demonstrated fork risk.
- `getProcessTree @33 (maxDepth :UInt32)` (`:120`): no bound on tree size, and `maxDepth` semantics (0=root only? unlimited?) undocumented.

## Zero-cost / eco
- `readMemory`/`writeMemory` inline `Data` (`:43-44`) — see R2 row; the single worst copy-forcing pair in the batch.
- `getMemoryMap @9` is paginated (good), but `MemoryRegion.name @3 :Text` (`:257`) duplicates per-region strings on every pull.
- Tracing methods (`setBreakpoint`/`stepProcess`/`continueProcess`, `:125-132`) are poll/step-shaped by nature; acceptable, they are the debugger's loop, not an OS hot path.

## UX & implementer guidance
- The header's claims (`:8-20`) are accurate and rare in this batch — say so.
- `ProcessFilter.minCpuUsage @3 :Float32` (`:232`) — unit documented at the struct (`0.0-1.0`), good; keep this pattern.
- `attach @10`/`detach @11` (`:41-42`) return `VoidResult` but never say *what attach grants* — ptrace-like authority is implied, not declared. Document the authority or gate it behind a capability accessor.

## Recommended actions
1. **Delete `ProcessCredentials`** (`:422-429`) and re-shape `ProcessSecurityContext` (`:416-420`) around `T.IsolatedScope` + capability references. Gain: process contract passes the seL4/capability-kernel swap; removes the doctrine-flagged POSIX model. Cost: POSIX-familiar reporting lost — the point of the exercise.
2. **Replace `getCgroupInfo`/`setCgroupResource` with quota reads over `T.Quota`** (already in `types.capnp:1776`) or delegate to `init.capnp` `ServiceSpec.quota`. Gain: one platform-neutral quota contract; cost: Linux-specific operators lose direct cgroup access — acceptable, nothing external consumes it.
3. **`readMemory`/`writeMemory` → `T.DataHandle`** (`:43-44`). Gain: zero-copy memory inspection; a 512 MB dump becomes a buffer reference instead of two copies. Cost: small-read ergonomics — `DataHandle.inline` already covers <1 KB payloads, so both sizes work.
4. **Unify raw `UInt64` PIDs / `UInt8` states** (`:164-168`) to `T.ProcessId` / `T.FailureReport` / `T.ProcessStatus`. Gain: removes the dual-spelling trap; cost: repurpose ordinals freely pre-release.
5. **Collapse `ProcessState` with `kernel.capnp` `TaskState` into one canonical state type in `types.capnp`** (universal names per the doctrine). Gain: one lifecycle vocabulary for tasks, processes, threads; cost: three files change together — the correct direction, and pre-release is the only cheap moment.
6. **Document `readMemory` consistency and `getProcessTree` depth semantics.** Gain: closes two fork sites; cost: comments only.

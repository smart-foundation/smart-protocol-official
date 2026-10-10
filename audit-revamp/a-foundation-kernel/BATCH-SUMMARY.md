# Batch Summary — Foundation & Kernel (19 schemas)

Audit date: 2026-10-10 · Auditor: a-foundation-kernel · Scope: abi, capability, types, kernel, boot, hal, init, service, process, session, task_scheduler, signal, discovery, queue, system, diagnostics, klog, logging, ipc-message

Verified mechanically: **zero undefined `T.*` references** across all 19 files, **zero method-ordinal collisions** within any interface. The batch's defects are doctrine and duplication defects, not compile defects — which is why they survived this long.

---

## Verdict table

| Schema | Verdict | One-line justification |
|---|---|---|
| abi | FIX (targeted) | Negotiation core exemplary; delete duplicate `BootCapability` enum and the speculative registry apparatus |
| capability | KEEP | The canonical authority contract; optional trim of the exchange/approval machinery, not a correctness fix |
| types | KEEP | Foundation resolves everything; delete dead `SubscriptionResult`/`SubscriptionData`, promote canonical `UnknownEvent` |
| kernel | FIX (targeted, large) | Core boundary correct; strip introspection/fork-flags/mesh/swap/SMP accretion, fix `TaskState` and cap duplicates |
| boot | REWRITE | Bootstrap core (one well-known cap, HandoffPointer, channels) is right; the manifest is a technology museum — 12 enums naming 2026 hardware |
| hal | FIX (targeted) | Affordance core right; cut page-table/x86-port-io block, unify three IRQ paths, dedupe types.capnp primitives |
| init | FIX (targeted) | Observable lifecycle right; two contradictory `RestartPolicy` enums, three supervision paths, raw `UInt8` codes |
| service | FIX (targeted) | Observation core right; `injectFailure` ungated (security), Audit-9 half is a cloud orchestrator, duplicates init |
| process | FIX (targeted) | Lifecycle core right; POSIX credentials/cgroups/Linux-caps in required positions, `readMemory` copies |
| session | FIX (targeted) | Lifecycle core right; device-class features (AR/watch/voice) and an ACL model violate the doctrine |
| task_scheduler | FIX (targeted) | Scheduling core right; ML prediction, priority inheritance, distributed nodes, energy policy are internal machinery |
| signal | FIX (targeted) | `T.SignalKind`/`DataHandle` right; three delivery authorities, Audit-8/10 feature stack, POSIX mapping table |
| discovery | FIX (targeted) | Registry core right; the other half is a service mesh with HTTP status codes in the "zero-assumption" file |
| queue | FIX (targeted) | Best R2 citizen (`DataHandle` payloads); Audit-9/10 broker infrastructure and the impossible `exactlyOnce` promise |
| system | FIX (targeted) | Handshake core right; 47-bool capability bitmap is a closed set already stale (no `ai`), stale comments |
| diagnostics | FIX (targeted) | Telemetry core right; 22/19/14-value taxonomies, grpc carrier contradicting its own header, six log/trace name collisions |
| klog | FIX (targeted) | Kernel-log core right; roles-ACL, three-way log duplication, missing ring-buffer overflow contract |
| logging | FIX (targeted) | The doctrine's #1 release-blocker (`LogFormat`/`LogOutput`/`LogSource`) still unexecuted since 2026-07-01 |
| ipc-message | DELETE | 9-line dead duplicate of `logging.capnp:98`; zero references repo-wide |

---

## Cross-schema findings

### Duplicate type names spanning the batch (23 pairs — codegen collisions)

| Type | Files | Nature |
|---|---|---|
| `BootCapability` | abi:259 ↔ boot:647 | **identical members, two type IDs** — worst collision in the batch |
| `RecoveryAction` | types:1922 ↔ boot:708 | same name, different vocabularies |
| `RestartPolicy` | types:1954 ↔ init:66 | same name, different vocabularies (inside one file: both used) |
| `TaskState` | kernel:51 ↔ task_scheduler:104 | enums, different members, overlapping POSIX vocabulary |
| `TaskFilter` | kernel:217 ↔ task_scheduler:145 | same name, different fields |
| `ResourceUsage` | types:892 ↔ task_scheduler:474 | disjoint shapes |
| `DeviceResource` | types:2124 ↔ hal:185 | untyped local copy of typed canonical |
| `Constraints` | capability:113 ↔ task_scheduler:48 | same name, unrelated domains |
| `LogEntry` / `LogFilter` | logging:103/138 ↔ diagnostics:502/515 | same names, different shapes (third query stack in klog) |
| `TraceSpan` / `TraceContext` | logging:338/323 ↔ diagnostics:260/277 | same names, different shapes (klog carries a third) |
| `SpanKind` / `SpanStatus` | logging:355/364 ↔ klog:343/352 | **verbatim duplicates** |
| `ExportFormat` | logging:290 ↔ klog:369 | same name, different members |
| `HealthStatus` | discovery:154 ↔ diagnostics:102 | same names, different shapes |
| `HealthSubscription` | discovery:591 ↔ diagnostics:95 | same interface name, different signatures |
| `ServiceCost` / `ServiceSla` / `ServiceDependency` | service:454/459/267 ↔ discovery:259/244/173 | three same-name pairs |
| `ServiceState` | service:223 (struct) ↔ discovery:116 (enum) | same name, different *kinds* |
| `ServiceEndpoint` | boot:1129 ↔ discovery:129 | same name, different shapes |

### Cross-cutting doctrine failures (same defect, many files)

1. **Raw-id subscriptions with parameterized pull** (two authority paths, violating the reference model): `system.capnp:22-23,36` · `klog.capnp:123,126` · `logging.capnp:33-34,56` · `diagnostics.capnp:24,48,91,96` · `queue.capnp:119-121` (transaction). One decision fixes five files.
2. **Three signal-delivery authorities**: `kernel.capnp:117` `signal` vs `process.capnp:27` `kill` vs `signal.capnp:244` `send` — three permission checks, three error models.
3. **Three service-control authorities**: `init.capnp:99-103` start/stop/restart vs `service.capnp:25-27` vs three supervision registries (`init.capnp:135`, `init.capnp:151`, `process.capnp:164`).
4. **Three lifecycle-state enums with POSIX vocabulary**: `process.capnp:217` (zombie/defunct), `kernel.capnp:51` (zombie), `process.capnp:245` (`ThreadState`) — the doctrine's universal rename (active/blocked/suspended/terminated) was never applied anywhere.
5. **Four audit-entry shapes**: `capability.capnp:414` · `session.capnp:369` · `signal.capnp:150` · (klog/diagnostics access audits).
6. **Six "group of processes" concepts**: `process.capnp:262` `ProcessGroup` · `queue.capnp:297` `ConsumerGroup` · `signal.capnp:198` `SignalGroup` · `kernel.capnp` mesh nodes · `init` supervised set · `session` `SessionAccessControl.allowedUsers`.
7. **403-forbidden permission models**: `boot.capnp:647`/`abi.capnp:259` `BootCapability` · `process.capnp:305` `ProcessCapability` (Linux caps) · `klog.capnp:441` role strings · `session.capnp:354` user ACL — four systems parallel to `capability.capnp`.
8. **Unbounded pulls without pagination**: `kernel.capnp:131` · `hal.capnp:248,256` · `init.capnp:244` · `klog.capnp:120` · `discovery.capnp:546` — each file's *other* lists are paginated; the inconsistency is per-file, the fix is per-file.
9. **Inline bulk where `T.DataHandle` exists and is used elsewhere in the same batch**: `process.capnp:43-44` (readMemory/writeMemory) · `boot.capnp:1114` (Module.data) · `hal.capnp:250` (ACPI table) · `kernel.capnp:115,577,592`.

---

## Ranked top-10 actions for the batch

1. **DELETE `ipc-message.capnp`** (whole file). Verified zero references. Gain: removes the dead duplicate log contract at the only moment deletion is free. Cost: nothing.
2. **REWRITE `boot.capnp`'s manifest core** (keep bootstrap: handle-1 cap, `HandoffPointer`, `BootBlob`, `ChannelInfo`; replace 12 technology enums with `T.DataHandle` artifacts + open tokens + typed `T.BusAddress`). Gain: a 2046 bootloader satisfies the contract unmodified — the Swap Test the doctrine claims it already passes; also kills the `BootCapability` duplicate and the banned permission model. Cost: one file of real work; no migration price (no external consumers).
3. **`kernel.capnp` Naledzi-gate cut**: delete unreachable interfaces (SMP/IPI/PerCpu/swap/AB-slots/multi-kernel), introspection, `fork`+`ForkFlag`, mesh/container/unikernel zoo; rename `TaskState`; swap `CapOperation`/`CapRights` → `capability.Operation`. Gain: every remaining method implementable by a microkernel with no scheduler/format knowledge; R8 satisfiable. Cost: ~450 lines deleted, none reachable today.
4. **Execute the doctrine's 2026 release-blocker on `logging.capnp`**: delete `LogFormat`/`LogOutput`, opaque `LogSource` (`:156-175`, `:130-134`), then converge logging+klog+diagnostics on one canonical log/trace primitive set. Gain: the flag's 2046 failures removed; three log clients become one; six codegen collisions die. Cost: focused three-file merge.
5. **Purge the enterprise-mesh accretions**: discovery (`:92-105`, `:242-376`, `:452`, `:486-501`), queue federation/replication/transactions/schema-registry (`:329-466`), service Audit-9 (`:102-195`), task_scheduler ML/energy/distribution (`:249-279`). Gain: each file implementable by a single-device OS; ~600 lines and ~25 enums of vendor/2026 vocabulary removed. Cost: features with zero consumers.
6. **`hal.capnp`: cut the kernel-internals block** (`:280-319`: physical pages, address spaces, `X86PortIo`) and unify IRQs to one event-delivering subscription. Gain: HAL passes the non-x86 and no-page-tables swap the doctrine's KEEPS-OUT list demands; interrupt-driven instead of poll-driven IRQs. Cost: one privileged-access path deferred to its own schema if ever needed.
7. **One canonical state vocabulary**: merge `ProcessState`/`TaskState`/`ThreadState` into `types.capnp` with the doctrine's universal names; retire `zombie`/`defunct`/`sleeping`. Gain: the Linux→seL4 swap the doctrine itself claims works, actually works. Cost: three files move together — correct pre-release work.
8. **`system.capnp` capability bitmap → open set** (`List(Text)` or capability ids). Gain: 2046 services (ai/tunnel/sandbox) declarable without editing an eternal struct; the current bitmap is already wrong today. Cost: boolean checks become token matches.
9. **Delete the four parallel permission models** (`BootCapability` ×2 files, `ProcessCapability`, klog roles, session ACL) in favor of `capability.capnp` references. Gain: one access-control system; closes the ungated-`injectFailure` security hole and the ACL/capability divergence fork. Cost: reporting familiarity lost by design.
10. **Close the five raw-id subscription sites** (system, klog, logging, diagnostics, queue-transaction) with subscription references. Gain: the ai.capnp reference-authority model, applied consistently; one fix pattern, five files. Cost: ordinals repurposed pre-release.

---

## What contradicts the doctrine documents themselves

1. **DESIGN_PRINCIPLES.md:502** calls `boot.capnp` "exemplary — stage-transitioning artifacts, no implementation assumptions." The file is the tree's largest collection of implementation assumptions (12 enums naming 2026 buses/bootloaders/firmware). The summary table was written against an earlier revision or never re-verified.
2. **DESIGN_PRINCIPLES.md:504** calls `kernel.capnp` exemplary for noting "internal kernel machinery is excluded" (`kernel.capnp:12-14` says so too) — while the same file exposes scheduler-state introspection (`:506`), CLONE_* fork semantics (`:203-210`), and live kernel migration (`:671-675`).
3. **DESIGN_PRINCIPLES.md:451 and TIMELESSNESS.md:451** claim TaskState "newBorn…zombie … maps to seL4's thread states" — while **DESIGN_PRINCIPLES.md:178 and TIMELESSNESS.md:77** declare zombie POSIX-specific and order the universal rename. The documents contradict each other; the schema kept the POSIX state.
4. **TIMELESSNESS.md:79** rejects product names (systemd, syslinux) and then prescribes `BootloaderKind { limine, grub, uefiDirect, custom }` — the rejection is right, the prescription is the same violation, and `boot.capnp:470-479` implemented it with nine vendors.
5. **DESIGN_PRINCIPLES.md:549** claims `system.capnp`'s "capabilities bitmap is extensible" — 47 fixed booleans is the least extensible shape possible; the tree now contains services (ai, tunnel, sandbox) with no bit.
6. **DESIGN_PRINCIPLES.md:399 / TIMELESSNESS.md:134-136** forbid permission strings/flags/RBAC — yet four schemas in this batch implement exactly those (`BootCapability` ×2, `ProcessCapability`, klog roles, session ACL).
7. **DESIGN_PRINCIPLES.md:254** designates pull-based subscription the canonical pattern — while five files in this batch use raw-id subscriptions whose `pull` takes the id as a parameter, the "two authority paths" anti-pattern the doctrine rejects at :394-396.
8. **ai.capnp:75 / R2**: the validator rejects inline `List(Float32)/List(Text)/List(UInt8)` in ai.capnp (rule E2) — the rule was never extended batch-wide, so `process.capnp:43` (readMemory copies), `boot.capnp:1114` (Module.data), `hal.capnp:250` (ACPI table), and `kernel.capnp:115` (manifestBytes) force copies the gold standard forbids.

## Batch hygiene note

No wire-breakers of the compile class exist in this batch: every `T.*` resolves and every interface's ordinals are unique. That is precisely why the doctrine audit matters here — nothing external consumes smart-protocol yet, so every defect above is still free to fix, and none of them will be caught by a compiler.

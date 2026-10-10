# Audit — klog.capnp (521 lines)

## Verdict
**FIX (targeted).** The kernel-log core is right and honest: sequence-numbered messages with typed severity, `T.SubsystemId` source (the audit-5 Rule-2 fix, `klog.capnp:46`), `T.StringDataMap` metadata, filter with `afterSequence` (gap detection, `:109`), `T.DataHandle` where bulk is plausible, and a header that correctly separates kernel/driver output from application logging (`:15-17`). The Audit-7/9 layers then duplicate `logging.capnp`'s observability stack a second time (distillation, trace spans, export, alerts, aggregation) and add an *access-control-by-roles* model (`readRole`/`writeRole` strings, `:441-450`) plus retention/archive/encrypt machinery — three more places where the batch forks log semantics. The deduplication target for the whole logging family is clear: one canonical `LogEntry`/filter/trace shape in `types.capnp`, with klog keeping only the kernel-specific sequence/buffer surface.

## Wire-breakers
None: ordinals unique (`@0..@21`), all `T.*` resolve. Stale comments claim "Subscription methods are on KLogService at methods 100-101" (`:189`) and "102-103" (`:240`) — no such ordinals exist.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R3 (permission model) | `klog.capnp:441-450` `KLogAccessPolicy { readRole :Text, writeRole :Text, allowAnonymous :Bool, ipAllowlist :List(Text) }`, `setAccessControl @14` (`:165`) | A role-based access-control model — "Do NOT define permission strings, boolean flags, or role-based access control in the protocol" (DESIGN_PRINCIPLES.md:399) | Roles are unversioned strings; every backend invents its role vocabulary, and two systems' `readRole` values are incomparable. `ipAllowlist` additionally assumes an IP network — meaningless on a local IPC-only system. The capability system already answers "who may read" |
| R1 (soft) | `klog.capnp:64-78` `KLogSeverity { debug, info, warn, error, critical, panic, custom }` vs `types.capnp:255-267` `LogLevel { trace, debug, info, warn, error, fatal, silent, crash, security, audit, custom }` | Two severity ladders; `critical`/`panic` here vs `fatal`/`crash` there | A consumer correlating kernel and app logs must translate between ladders every time; the translation is undeclared. Fork: does kernel `critical` equal app `fatal`? |
| R6 | `klog.capnp:343-350` `SpanKind`, `:352-357` `SpanStatus` — verbatim duplicates of `logging.capnp:355-362`, `:364-369`; `:318-329` `KLogTraceContext` vs `logging.capnp:323-336` `TraceContext`; `:267-278` `KLogDistillResult` vs `logging.capnp:236-245` `LogDistillResult`; `:369-384` `ExportFormat`/`ExportCompression` vs `logging.capnp:290-296` | Five duplicated type pairs across two files, with the same names, same members, different ordinals | Codegen collisions (same-named types in two schemas); a generic tool cannot treat kernel and app traces uniformly |
| R6 | `klog.capnp:180-186` `registerAlert`/`listAlerts`/`removeAlert` vs `logging.capnp:74,83` vs `diagnostics.capnp:54-56`; `klog.capnp:138` `search` vs `logging.capnp:53` `queryEntries` vs `diagnostics.capnp:51` `queryLogs`; `klog.capnp:144` `distill` vs `logging.capnp:59` `getDistilled` | Three parallel log query/alert/distill stacks | Every implementer builds (or stubs) the observability platform three times; every consumer writes three clients. The exact "duplicate interfaces" anti-pattern DESIGN_PRINCIPLES.md:207-220 catalogs — in the logging family instead of the UI family |
| R5 | `klog.capnp:441-450` `ipAllowlist`, `:460` `ipAddress :Text`, `:368-384` `ExportCompression { gzip, zstd, lz4 }`, `:373` `ExportFormat { protobuf }` | IP-network assumptions and named compression/codec technologies | 2046: a post-quantum or neural compression has no ordinal; an IPC-only system has no IP to allowlist |
| R7 (soft) | `klog.capnp:118-126` `subscribe @1 () -> (subscriptionId :UInt64)` + `pull @2 (subscriptionId :UInt64)` | Raw-id subscription (two authority paths) | ai.capnp model: return the subscription reference; holding it *is* the authority |
| R1 | `klog.capnp:230-238` `BackpressureMode { drop, buffer, block }`, `:253-265` `DistillAlgorithm { summarize, anomaly, pattern, deduplicate, aggregate }`, `:442+` enums | Closed policy/algorithm lists | `DistillAlgorithm` names today's summarization algorithms; a 2046 distillation method has no ordinal. `custom` mitigates |

## Duplicates & overlaps
- Log query: `KLogSearchRequest` (`:193-198`) vs `logging.capnp:180` `LogQuery` vs `diagnostics.capnp:515` `LogFilter`.
- Aggregation: `aggregateLogs @18` (`:177`) vs `logging.capnp:71` `aggregateLogs` — same method *name*, two contracts.
- Retention: `setRetentionPolicy @10` (`:153`) vs `logging.capnp:65` `setRetention` — two retention contracts.
- Sampling: `setSamplingRate @16` (`:171`) vs `logging.capnp:77` `setSamplingRate`.
- Archive/encrypt/access-control (`:406-463`) — no counterpart in the core contract; speculative.

## Gaps & holes
- **No ring-buffer overflow contract**: `bufferSize @3` (`:130`) reports size, but nothing declares behavior when full — drop-oldest (kernel dmesg behavior) vs drop-new vs block. `BackpressureMode` exists for the *stream* path only. Demonstrated fork: every kernel picks differently, and a boot-failure diagnostic chain silently loses the messages a 2046 crash investigator needs. This is the file's most important missing contract.
- No declared behavior for `clear @4` when authority is absent — "requires appropriate authority" (`:133`) names no mechanism.

## Zero-cost / eco
- `read @0 (filter) -> (messages :List(KLogMessage))` (`:120`) unbounded — `KLogFilter.limit @4` (`:113`) mitigates but defaults to "backend default," so a consumer without an explicit limit is unbounded. Pagination or a required limit belongs here.
- Messages carry `metadata :T.StringDataMap` (`:50`) — key→Data values; fine, but `KLogFieldValue.bytes @4 :Data` (`:93`) allows inline bulk per field with no 1 KB guidance (the queue's comment "use buffer handle for payloads >1KB" is the pattern).
- Polling: none — `subscribe`+`pull` is the right eco shape. Keep.

## UX & implementer guidance
- `sequence @0 :UInt64` "monotonically increasing, unique per backend" (`:39-40`) — good; say what wraps (never? per-boot?). Two backends' sequences are incomparable; declaring "monotonic within a boot epoch" closes it.
- `KLogMessage.severity` + `source :T.SubsystemId` (`:44-46`) — the audit-5 fix is a genuine improvement; keep the typed-ID discipline.
- The audit-lineage headers reference "audit-5/7/8/9" and claim distilled/alert/aggregate features without stating who consumes them — no consumer in the protocol does.

## Recommended actions
1. **Delete the roles ACL** (`KLogAccessPolicy` `:441-450`, `setAccessControl @14` `:165`, `getAccessAudit @15` `:168`, `KLogAccessAuditEntry` `:452-463`). Replace with capability-gated acquisition of the read/stream interfaces. Gain: removes the forbidden RBAC model and IP assumptions; one authority mechanism for logs; cost: backends lose per-role strings (the point of the exercise).
2. **Define the ring-buffer overflow contract** (drop-oldest recommended, declared, with `bufferSize` reporting overflow count). Gain: closes the highest-consequence fork in the file — silent diagnostic loss during crash chains; cost: one field + one paragraph of spec.
3. **Consolidate the log primitives**: one canonical `LogEntry`/filter/trace/distill/alert shape shared by logging, klog, diagnostics (canonical home in `types.capnp`, or logging.capnp as the app-side contract with klog importing). Delete `SpanKind`/`SpanStatus`/`KLogTraceContext`/`ExportFormat`/`ExportCompression` duplicates and the distill/alert/aggregate/search blocks from klog. Gain: one log grammar for the whole tree — kills 5+ codegen collisions; cost: a focused merge across three files, the right pre-release work.
4. **`KLogSeverity` → align to `T.LogLevel` or declare the mapping.** Gain: correlatable kernel/app logs; cost: one enum retired.
5. **Bound `read @0`** (required limit or pagination). Gain: no unbounded pulls; cost: one ordinal.
6. **Declare sequence semantics** ("monotonic within a boot epoch; resets permitted across boots") and replace raw subscription ids with references (`:123`, `:126`). Gain: closes the comparability fork + reference-authority model; cost: comments + two ordinals.

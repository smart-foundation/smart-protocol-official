# Audit — logging.capnp (369 lines)

## Verdict
**FIX (targeted) — the doctrine's own #1 release-blocker, still unexecuted.** DESIGN_PRINCIPLES.md:517, 563-565 lists this file as a 🔴 High "Immediate (Block v1.0 Release)" item since 2026-07-01: *"Fix `logging.capnp` — remove `LogFormat` and `LogOutput` enums, make `LogSource` opaque."* All three violations are still present at the exact lines predicted (`LogFormat` `:156-161`, `LogOutput` `:165-175`, `LogSource` `:130-134`), and the file's own header (`:12-15`) claims "The schema names no specific logging daemon" while `LogOutput.systemLog @2` comments name syslog/journald/Windows Event Log (`:168`). Beyond the three mandated fixes, the Audit-7/9 layers add an observability platform (SQL-like queries, AI distillation, redaction, alert rules, W3C/OpenTelemetry trace spans) that duplicates machinery in `klog.capnp` and `diagnostics.capnp` three times over. The core (`log @26`, `getEntries`, `setLevel`, subscription) is sound; the file is fixable, not a rewrite.

## Wire-breakers
None: ordinals unique (`@0..@26`), all `T.*` resolve.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R1 | `logging.capnp:156-161` `LogFormat { text, json, xml, custom }` | Output *format* enum — "Dictates output format. A logging backend may use binary, CBOR, protobuf, or custom formats" (DESIGN_PRINCIPLES.md:226) | 2046 test: a zero-copy binary log or a queryable columnar store has no ordinal; `custom @3` carries no self-description (no mimeType). Every consumer must default-around today's three formats |
| R1 | `logging.capnp:165-175` `LogOutput { stdout, stderr, systemLog, structuredLog, file, custom }` | Output *destination* enum naming syslog/journald/ELK/Loki/InfluxDB in comments (`:168`, `:171`) | "stdout/stderr/journal" is the exact row in TIMELESSNESS.md:77's rejected list. A backend that writes to a framebuffer console, an eBPF ring buffer, or a journal-less embedded sink must pick a lie; two backends map `file` differently (path? fd? rotating?) — fork by construction |
| R1 / R4 | `logging.capnp:130-134` `LogSource { file :Text, line :UInt32, function :Text }` | Structured source location — "Assumes compiled languages with source files. WASM, interpreted, and JIT languages don't have this" (DESIGN_PRINCIPLES.md:228); the doctrine's fix is `source @0 :Data` opaque | 2046 test: a notebook-style or AI-generated code path has no `file`/`line`; every such producer must falsify fields. Opacity fix was specified in 2026 and never applied |
| R6 | `logging.capnp:323-336` `TraceContext`, `:338-353` `TraceSpan`, `:355-362` `SpanKind`, `:364-369` `SpanStatus` vs `klog.capnp:318-357` (`KLogTraceContext`/`SpanKind`/`SpanStatus`) vs `diagnostics.capnp:260-315` (`TraceSpan`/`TraceContext`/`TraceStatus`) | Three distributed-tracing stacks in the batch; `SpanKind`/`SpanStatus` are *verbatim* duplicates in logging+klog; `TraceContext`/`TraceSpan` collide by *name* between logging and diagnostics with different shapes | Codegen collision + three trace grammars. A tracing-aware consumer must normalize three shapes; a kernel trace and an app trace cannot be correlated portably |
| R1 / honesty | `logging.capnp:103-126` `LogEntry` carries `level @2 :T.LogLevel` **and** `severity @13 :T.LogLevel` ("Extended severity beyond T.LogLevel") | Two severity fields, same type, no declared precedence | Implementer trap and a fork: which field wins when they differ? The comment says "beyond" but the type is identical — it *is* the same vocabulary |
| R1 (soft) | `logging.capnp:209-218` `LogFilterOperator { equals, contains, startsWith, endsWith, regex, greaterThan, lessThan }`, `:220-231` `LogSortField`/`LogSortOrder`, `:290-296` `ExportFormat { json, jsonl, csv, text }` | Query-language and export-format enums | All have `custom`; the operator set is a query grammar commitment. Lower severity — flagged |
| R3 (soft) | `logging.capnp:62` `redact (filter, patterns) -> (redactedCount :UInt64)`; `:74` `registerAlert`; `:14` distillation | Mutating log store and registering alerts, ungated | Redaction *destroys* data — a security-relevant mutation with no capability gate; the access-control answer should be `capability.capnp`, but here any caller rewrites history |
| R7 (soft) | `logging.capnp:31-33` `subscribeEntries @1 () -> (subscriptionId :UInt64)` + `pullEntries @2 (subscriptionId …)` | Raw-id subscription pattern (two authority paths: hold id vs. hold reference) | Same defect class as `system.capnp:22-23`; ai.capnp's model returns the subscription *reference*. `streamEntries @12` (`:56`) returns yet another raw `streamId :UInt64` |

## Duplicates & overlaps
- `queryEntries @11` (`:53`) vs `diagnostics.capnp:51` `queryLogs` vs `klog.capnp:138` `search @5` — three log-query contracts with three filter shapes (`LogQuery` vs `LogFilter` vs `KLogSearchRequest`).
- `getDistilled @13` (`:59`) vs `klog.capnp:144` `distill @7` — the same AI-summarization feature twice, with different structs (`LogDistillResult` vs `KLogDistillResult`).
- `LogFilter` (`:138-144`) vs `diagnostics.capnp:515-526` `LogFilter` — same name, different fields (domain/level/pattern vs minLevel/sourcePattern/timeRange).
- Alerting: `registerAlert @18` + `subscribeAlerts @21` (`:74`, `:83`) vs `klog.capnp:180` `registerAlert` vs `diagnostics.capnp:54` `createAlertRule` — three alert systems.
- The `ipc-message.capnp` file is a dead 9-line duplicate of `log @26`'s parameters (see that audit).

## Gaps & holes
- No declared severity-ordering contract for `T.LogLevel` custom values (is `custom` above `fatal`?), and `LogLevel` contains `crash`/`security`/`audit` (`types.capnp:262-266`) which are daemon categories, not severities — a real fork on any filtered stream.
- No contract for what `log @26` returns on failure: `T.VoidResult` swallows the outcome (accepted? dropped? sampled away?). "NEVER swallow errors silently" (DESIGN_PRINCIPLES.md:428) — an accepted/dropped distinction is exactly what a producer needs at volume.

## Zero-cost / eco
- `exportEntries @16 -> (data :T.DataHandle)` (`:68`) — correct.
- `setSamplingRate @19` (`:77`) — good eco affordance (declared sampling beats silent drops), keep.
- `queryEntries` returning full `List(LogEntry)` with `total` (`:53`) — bounded, fine.
- `redact @14` rewriting history server-side (`:62`) is the eco-inverse (unbounded work, unlogged); sampling is the honest lever.

## UX & implementer guidance
- Header improvement log (`:17-28`) again teaches audit history; the contract's gaps (who may redact, what happens when the ring buffer is full) go unstated.
- `log @26` sits at the *end* of the interface (`:98`), after 25 query/admin methods — the hottest path is the last ordinal; order methods by consumer frequency.
- `enrichContext @20` / `getEnrichedContext @22` attach context to an `entryId :T.EventId` (`:80`, `:86`) — mutating immutable log entries by id; the storage model is undeclared (append-only? mutable?).

## Recommended actions
1. **Execute the doctrine's mandated fix now**: delete `LogFormat` (`:156-161`) and `LogOutput` (`:165-175`); make `LogSource` opaque `source @0 :Data` or drop structured file/line/function; replace `setFormat`/`setOutput` (`:44-45`) with an open `T.StringMap` config or a `T.MimeType` declaration. Gain: the 2026-flagged 2046 failures are removed; the header's claim ("names no specific logging daemon") finally becomes true. Cost: three fields + two methods reshaped — free pre-release, and overdue by the doctrine's own schedule.
2. **Delete the observability-platform layer** (`:53-95`: queryEntries, getDistilled, redact, registerAlert, aggregateLogs, setSamplingRate keep, enrichContext, subscribeAlerts, queryWithExpression, getTraceContext, createTraceSpan) — or more precisely, keep `setSamplingRate` and delete the rest, consolidating query/distill/alert/trace into one canonical home shared with klog and diagnostics (see BATCH-SUMMARY action 4). Gain: one log contract instead of three; cost: moderate merge work, but three files converge on one shape.
3. **Resolve `level`/`severity` duality** (`:106` vs `:125`): delete one field. Gain: removes the precedence fork; cost: one field.
4. **Make `log @26` honest**: return distinct outcomes (accepted/sampled/dropped) or document the VoidResult contract. Gain: producers can reason at volume — "NEVER swallow" applied; cost: one result union.
5. **Move `log` to the first method ordinal region** and replace raw subscription ids with subscription references (`subscribeEntries`/`streamEntries`). Gain: better ordinal economics + the reference-authority model; cost: ordinals are free pre-release.

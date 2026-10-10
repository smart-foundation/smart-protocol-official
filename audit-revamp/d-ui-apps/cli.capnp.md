# Audit — cli.capnp (335 lines)

## Verdict
**REWRITE (the command model; the execution primitives survive).** The brief for this file is exact: "cli.capnp is the surface the `smart` shell speaks — it must let a CLI be generated FROM the schemas (introspection-driven), not hand-maintained per domain." The current schema cannot do that, by construction. Commands are free `Text` names (105); there is no method to **enumerate** commands; there is no binding from a command to the schema/interface/method it invokes; `getCommandInfo @7` is a hand-authored help record parallel to the schemas, not derived from them; and permission is checked per call by name (`checkPermission @11`, 38) — the per-call authority pattern the doctrine retired. Execution itself is well done: `ExecuteStreaming`, `T.DataHandle` for stdin/stdout/stderr, `T.ExitStatus`, interactive sessions, pipelines — keep all of that. What must be rewritten is the dispatch layer: a command registry derived from the schemas (command → schema/interface/method → typed args from capnp reflection), authority via reference (holding a capability for the domain), completion and job events via subscriptions rather than polls (`getJobStatus @2`, `pollPrompt @16` are both polling loops where events belong), and an output-format enum that stops naming 2000s serialization formats.

## Wire-breakers
`InteractiveSession.pid @1 :T.ProcessId` (293) — fine. No compile issues.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R7/introspection | `cli.capnp:102, 5–54` | `CommandRequest.command @0 :Text` — commands are unstructured names with no registry method; `getCommandInfo @7` is a parallel hand-written table | A CLI generated from schemas needs "list every command with its schema binding and typed arguments" — this contract makes that impossible: the generator must hand-maintain a per-domain table, the exact thing the brief forbids. Two domains that both define "list" collide in one flat namespace, and nothing a client can read says which exists |
| R3 | `cli.capnp:38` | `checkPermission @11 (command :Text) -> (result :T.BoolResult)` — authority interrogated per call by name | The doctrine's rule (TIMELESSNESS:135–162; DESIGN_PRINCIPLES:382–399): authority is the held reference, gated at acquisition. Per-call checks create the two-paths-must-agree problem; and a command name has no target/operations to check against |
| R7/eco | `cli.capnp:13, 53` | `getJobStatus @2 (jobId)` and `pollPrompt @16 (sessionId)` — status and prompts are polled | Every CLI shell runs a poll loop (waking the CPU) waiting for completion or a password prompt — where a `pull`-with-terminator subscription (the batch's canonical shape, e.g. cli.capnp:236 `StreamingOutput`) is available and terminates structurally (`done :Bool` at 251). The eco/zero-waste lens flags exactly this |
| R1 | `cli.capnp:127` | `CommandOutputFormat { raw, utf8, json, yaml, xml, custom }` — names 1990s–2000s serialization formats | This is the doctrine's `logging.capnp LogFormat` anti-pattern (DESIGN_PRINCIPLES:226) verbatim: a 2046 format (capnp-native, msgpack, neural-JSON) has no ordinal. The batch already owns the open answer — `T.MimeType` — for exactly this |
| R6 | `cli.capnp:57` | `CommandHistoryAnalytics` collides by name with `shell.capnp:1018 CommandHistoryAnalytics` (different shape) | The shell↔CLI shared vocabulary breaks at the first struct; the CLI's history and the shell's history are two incompatible types with one name |
| R6 | `cli.capnp:155` | `ResourceLimits` (155–166) is a *third* quota model beside `types.capnp:1776 Quota` and `compositor.capnp:1429 ResourceLimits` | Three limit shapes (cpu time/memory/files/fds here; cpuPercent/pids/wallClock in Quota; surfaces/GPU-memory in compositor). One quota primitive, field-optional, replaces all three |
| R4 | `cli.capnp:35, 50, 292` | `scriptId :Text`, `sessionId :Text`, alias/script/job entities addressed by free text while `T.JobId` exists | Script and session handles are lifecycle objects (create/cancel/delete) — text addressing invites collisions and string matching; typed ids are the batch's convention everywhere else |
| R1 | `cli.capnp:90` | `PipeMode { pipe, redirect, append, none }` encodes shell redirection targets | Mostly closed — but `redirect @1`/`append @2` point "to file" with no path parameter anywhere in `CommandPipelineStep` (81–88): the redirection target is implicitly unnameable. Either add the target or drop the modes |

## Duplicates & overlaps
- History/analytics vs `shell.capnp:1010 CommandHistoryEntry/CommandHistoryAnalytics` (and shell's is a different shape again).
- `ResourceLimits` vs `T.Quota`/compositor's (R6 row).
- `InteractiveInput`/`InteractivePrompt`/`InteractiveInputType` (297–335) vs `ime.capnp`/`textinput.capnp` `ImeInputType { text, password, confirm, choice, path, number }` (textinput.capnp:286) — two interactive-prompt vocabularies (the IME one is richer, this one lacks number). One prompt contract.
- Execution vs `process`/`kernel` spawn (not deep-verified — flagged): spawning a background job is a process-domain operation; the CLI service should express intent, the kernel executes.

## Gaps & holes
- **The missing registry is the gap**: no `listCommands`, no command→schema binding, no argument *types* derived from capnp (args are `List(Text)`, 107). The signature a generator needs is roughly: `listCommands (pagination) -> (commands :List(CommandSpec))` where `CommandSpec { name, domain :T.SchemaId, interface :Text, method :Text, params :T.DataHandle (schema) }`, with `execute` taking the typed params struct. Without it the CLI stays hand-maintained per domain forever.
- **No streaming stdin** symmetric with `stdout` (executeStreaming streams out; input is a one-shot `T.DataHandle` at request time). Interactive mode (`sendInput`) compensates, but the two models overlap.
- **Exit of a streaming command**: `OutputChunk.finished @2` exists (251) — good; but cancellation semantics vs kill are unstated (`cancel @1` "terminates the command" — SIGTERM? SIGKILL? `T.SignalKind` exists).

## Zero-cost / eco
- `stdin/stdout/stderr :T.DataHandle` and `OutputChunk.data :T.DataHandle` — the batch's correct zero-copy on the command's bulk paths. Keep exactly.
- `executeStreaming` with pull+cancel and a structural terminator (`finished`) — the model `cli.capnp`'s own job polling should adopt.
- Polling findings (R7 row) are the eco defects.

## UX & implementer guidance
- `getCompletions @6 (partial :Text) -> (completions :List(Text))` — flat string completion with no metadata (which domain, which argument position, whether a trailing space ends the entry); shells will each invent prefix-matching rules.
- `createScript @10 (script :CommandScript)` with `CommandScriptStep { command, args, cwd, skipOnError }` — a mini shell language in the protocol; scripts are user content and better modeled as pipeline records (like `executePipeline @13` does) with an id, or left to a shell implementation. Two scripting models in one file.
- `getCommandInfo` returns `CommandInfo` (200) whose `CommandOption.typedValue @4 :TypedOptionValue` exists (224) — the typed layer was started and never connected to the command model. The rewrite completes what this half-measure began.
- Validator E8: `EnvironmentMode.@0 = replace` (147) — an absent environment silently *replaces*; `inherit` would be the safer zero for a CLI tool.

## Recommended actions
1. **Add the schema-derived command registry** (`listCommands` + `CommandSpec` binding name → `T.SchemaId`/interface/method, with the method's parameter schema as a `T.DataHandle` taught to the generator; `execute` then takes `params :T.DataHandle` decoded by schema). Gain: the CLI is generated from the schemas — hand-maintained per-domain tables become impossible by construction; new domains gain a CLI by declaring a schema. Cost: the dispatch core is a rewrite (~2 methods + 2 structs); the execution primitives are untouched.
2. **Replace `checkPermission` with reference-gated domain capability** (the caller holds a capability for the domain it invokes; execute checks nothing per call). Gain: one authority path, consistent with ai.capnp's model; the retire-per-method rule holds. Cost: one method deleted, one capability parameter added at acquisition.
3. **`getJobStatus` → job subscription with a structural terminator** (`finished`/`exitStatus` union like `OutputChunk`/`StreamStatus`); `pollPrompt` → prompt events on the interactive session stream. Gain: CLI shells stop polling; CPU wake loops disappear; latency for completion drops to event speed. Cost: two methods reshaped into subscriptions.
4. **`CommandOutputFormat` → `T.MimeType`.** Gain: a 2046 output format needs no ordinal; matches the batch's open-value rule. Cost: one enum replaced by one field.
5. **Delete the `PipeMode` redirect/append modes (or give them a path target)** and the parallel script model (`createScript` family) in favor of recorded pipelines. Gain: no shell-language-in-protocol; one composition model (`executePipeline`). Cost: one enum trimmed, ~5 methods deleted.
6. **Unify `ResourceLimits` with `T.Quota`** and **merge the history/analytics structs with shell.capnp's** (one shape, one home — the CLI's). Gain: one quota vocabulary, one history vocabulary across the shell/CLI boundary the brief says must interop. Cost: one struct promoted, one deleted.
7. **Align the interactive prompt vocabulary with ime/textinput's** (`ImeInputType`) or share one prompt struct in types.capnp. Gain: password prompts in a CLI and in an IME behave identically (same `password` input semantics!). Cost: one enum consolidated.

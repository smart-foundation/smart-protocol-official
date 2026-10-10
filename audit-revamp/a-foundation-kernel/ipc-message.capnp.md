# Audit — ipc-message.capnp (9 lines)

## Verdict
**DELETE.** The file contains one struct, `LogParams` (`ipc-message.capnp:5-9`), a flat triple of `T.LogLevel` / `Text` / `Text` that duplicates `Logging.log @26 (severity, domain, message)` (`logging.capnp:98`) and the core fields of `LogEntry` (`logging.capnp:103-108`). A repo-wide search finds exactly one occurrence of `LogParams` — its own definition. No interface, no method, no consumer, no importer: it is a dead draft that contradicts the live logging contract on where a log line is shaped. Pre-release is the only moment deletion is free.

## Wire-breakers
None. Imports resolve; no ordinals.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R6 | `ipc-message.capnp:5` | `LogParams` duplicates the parameter list of `Logging.log` and fields of `logging.capnp:103-108` | Fork risk: a 2028 implementer seeing two "log a message" shapes in the canonical tree must guess which is normative; one of them will be wrong and the guess is unobservable until an app breaks |

## Duplicates & overlaps
- `logging.capnp:98` (`log @26`) takes exactly `(severity :T.LogLevel, domain :Text, message :Text)` — the same three fields.
- `logging.capnp:103-108` `LogEntry` carries the same triple plus id/timestamp. `ipc-message.LogParams` is a strict subset of both.
- Note the pattern: this is a *parameter struct* — an anti-pattern the rest of the batch avoided by passing fields directly.

## Gaps & holes
None to add; the gap runs the other way (this file adds nothing).

## Zero-cost / eco
`message @2 :Text` inline — trivial size, no copy cost worth flagging. Not a factor in the verdict.

## UX & implementer guidance
A file named `ipc-message.capnp` containing only a logging struct actively misleads: an implementer hunting for the IPC message contract (the thing `boot.capnp:139` `channels` and `boot.capnp:1118` `ChannelInfo` actually define) finds a 9-line logging stub instead. Names must teach the domain; this one teaches the wrong one.

## Recommended actions
1. **Delete the file.** Gain: removes a dead, contradictory duplicate of the logging contract before first release; costs nothing — zero references exist repo-wide (verified by search).

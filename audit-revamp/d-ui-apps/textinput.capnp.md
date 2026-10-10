# Audit — textinput.capnp (308 lines)

## Verdict
**MERGE-INTO-ime.capnp.** The doctrine declared this resolution (DESIGN_PRINCIPLES:211, :562; SCHEMAS.md:166 says "DEPRECATED") and it was never executed: this file is a fully live, competing text-input contract, and worse, it has *drifted* from ime.capnp — `ContextRequest`, `SurroundingText`, `InputMethodInfo`, `InputMethodState` exist in both files with different fields, so a client written against one file gets silently wrong data on the other. That drift is now the concrete damage: it is not historical duplication, it is two contracts disagreeing about what a text context *is*. Some of this file's content is better than ime's and must be absorbed, not discarded: per-surface contexts (line 23), per-context enable/disable (28–29), `commitTextHandle` DataHandle commit (49), language stack (152–154), stroke/suggestion pipelines (231–265), and interactive input requests (275–307). Nothing imports this file (verified repo-wide); nothing external consumes it. Pre-release, deletion is free.

## Wire-breakers
None. Isolated file.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R6 | `textinput.capnp:22` | The whole interface duplicates `ime.Session` (context lifecycle, enable/disable/reset, method list/switch/state, keyboard show/hide, preedit/commit, subscriptions) while both remain live | The fork is active, not hypothetical: `InputMethodState` here (147) has `composing/preeditText/languageStack` while ime.capnp:181 has `active/currentMethod/composing` — a client that switches IMEs gets a state struct missing the fields it reads. Every IME implementer must honestly implement two text-input contracts that disagree |
| R7 | `textinput.capnp:20, 51` | `subscribeEvents @15`/`pullEvents @16`/`cancelEvents @17` are three methods doing what the batch's canonical `Subscription` interface does in one | Each new event shape re-adds a pull/cancel pair to the service; the service interface grows with subscription mechanics instead of staying domain-only (the protocol's own convention elsewhere) |
| R1 | `textinput.capnp:174` | `TextInputEventType { cursorMove, selection, contentChange, activate, deactivate }` — today's editing events frozen | A future text modality (voice-driven edit, neural correction, collaborative remote edit) emits events this enum cannot name; `custom @5` exists but each backend then defines its own vocabulary with no dispatch contract |
| R2 | `textinput.capnp:235` | `StrokeData.points :List(T.Vec2i)` + `pressure :List(Float32)` inline | Handwriting input is the highest-volume pointer-adjacent stream: every stroke copies its whole point array into the message. At stylus sampling rates this allocates per stroke, forever |
| R4 | `textinput.capnp:164` | `TextInputEvent.charTimings :List(CharTiming)` — per-character latency profiling embedded in the live event | The event struct every consumer touches carries a profiling payload most consumers discard; profiling belongs on a separate diagnostic stream |

## Duplicates & overlaps
- vs `ime.capnp` (the designated canonical home): same interface, same 7 structs, drifted content — detailed in ime.capnp audit. The unique, keep-worthy parts: per-surface `createContext` (23), per-context `enable/disable/reset` (27–29), `commitTextHandle @19` (49), `InputMethodState.languageStack/activeLanguage` (152–155), `DictationRequest/Session/State` (201–227), `StrokeData`/`RecognitionResult` (231–247), `TextSuggestion`/`SuggestionSource` (251–265), `ImeInputRequest/Response/Handle` (275–307).
- `TextEncoding` (185): enum of text encodings — closed by practice (utf8/16/32), acceptable, but belongs next to the DataHandle commit it labels.
- `CharTiming` (168) overlaps diagnostics.capnp's profiling domain (not verified deep — flagged for the diagnostics batch).

## Gaps & holes
None unique. The per-context `surfaceId` (23) is the one thing ime.capnp lacks that this file got right — it must survive the merge.

## Zero-cost / eco
- `pullEvents @16 () -> (events :List(TextInputEvent))` returns the full backlog unbounded — `pullPaged @2` on the subscription exists (83) but the service-level pull remains unbounded.
- The inline stroke arrays (see R2 above) are the one genuine copy-cost item.

## UX & implementer guidance
- The header (lines 8–20) reads like the file is the improved design ("commitText @36 = T.DataHandle variant… Original @11 retained") while it is the deprecated one. An implementer following SCHEMAS.md:166 to ime.capnp and then reading this header gets contradictory signals.
- `getSuggestions @25 (contextId, pagination)` returns `total :UInt32` — the batch's inconsistent total types (UInt32 here, UInt64 elsewhere) is present in this file too; unify post-merge.

## Recommended actions
1. **Port the unique surface to ime.capnp and delete this file** (see ime.capnp action 1 for the port list). Gain: ends the active two-contract fork in text input; the drifted structs collapse to one definition each. Cost: one merge + one deletion; zero importers exist.
2. **Do not carry forward** `charTimings`, the service-level pull/cancel trio, or `TextInputEventType`'s closed set — ime's `TextInputEventKind` + stream filter with `custom` covers them.
3. If merge lands: move `TextEncoding` beside `commitTextHandle`, and keep `StrokeData`/`RecognitionResult` with strokes as `T.DataHandle`.

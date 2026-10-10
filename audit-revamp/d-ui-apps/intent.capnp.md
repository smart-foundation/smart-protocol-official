# Audit — intent.capnp (671 lines)

## Verdict
**FIX (targeted).** The dispatch core — resolve (paginated), startActivity/startService/sendBroadcast, registerHandler with typed ComponentInfo, UriPattern, typed extras — is the right universal activation contract, and the typed-extras/priority/dedup/retry additions are honest. But the file opens with the batch's most concentrated platform leak: `LaunchFlags` (82–98) is a transcription of Android's `FLAG_ACTIVITY_*` constants (newTask, singleTop, clearTop, clearTask, clearWhenTaskReset, excludeFromRecents, grantPersistableUriPermission), `IntentCategory` (102–117) is Android's Intent categories (`browserCategory` is even named "browserCategory"), and `ActivityResultCode.firstUser @2` (200) is `RESULT_FIRST_USER`. A compositor or shell that has never heard of an Android activity stack — which is every alternative implementation — must emulate task/recents semantics to comply, the exact R5 failure the Swap Test exists to catch. Around that sit: result delivery by polling (`waitForResult @4`), an access-control service built on permission strings (603–608), recording/replay machinery with no named consumer, and inline `Data` in debug traces. Fix the vocabulary, fix the polling, cut or quarantine the rest.

## Wire-breakers
None.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R5 | `intent.capnp:82–98` | `LaunchFlags { newTask, singleTop, newDocument, clearTop, clearTask, clearWhenTaskReset, excludeFromRecents, fromHistory, multipleTask, grantReadUriPermission… }` — verbatim Android activity flags | The Swap Test fails: swapping Android for a spatial shell, an embedded HMI, or a robot UI forces the contract to be re-explained — "tasks" and "recents" do not exist. Every non-Android backend maps 10 flags it does not have; clients branching on `grantPersistableUriPermission` bake 2010s Android URI-grant semantics into an eternal contract |
| R5 | `intent.capnp:102–117` | `IntentCategory { default, browsable, view, edit, pick, send, receive, main, launcher, home, preference, browserCategory, alternative }` — Android's intent-filter categories, `browserCategory` included | "home"/"launcher"/"browser" are today's shell concepts; a 2046 spatial shell has no home screen. The category list is *registration vocabulary* — an unbounded, per-platform set frozen at 2010 values |
| R5 | `intent.capnp:200` | `ActivityResultCode { canceled, ok, firstUser, custom }` — `firstUser` is Android's `RESULT_FIRST_USER` range marker | An API constant from one platform leaks into the universal result code; nothing else can produce it, so every backend ignores it forever |
| R7 | `intent.capnp:226` | `waitForResult @4 (handle :ActivityHandle) -> (result :ActivityResult)` — results are *pulled* per handle | An app waiting for an activity result polls (or blocks a call) where an event/subscription belongs — the polling cost lands on every caller, and `getResultForActivity` needs a callback the contract lacks. The batch's subscription pattern (pull + cancel on an interface) is the model |
| R3 | `intent.capnp:596–608` | `IntentAccessService` with `IntentAccessPolicy { caller, allowedActions :List(Text), deniedActions :List(Text), maxPerMinute }` — per-action string lists and a rate limit | Permission strings plus rate limits — both exist in capability.capnp (`Operation`, `RateBox`, types.capnp:127). A second access-control policy engine that must agree with the capability system forever — the doctrine's "one authority path" (TIMELESSNESS:135) |
| R2 | `intent.capnp:503, 505` | `TraceStep.input @3 :Data`, `output @4 :Data` inline — a full dispatch trace with per-step payloads | Traces of document-sized intents copy their payloads into every trace step; this is debug data that will be enabled on exactly the systems where it hurts. `T.DataHandle` is the fix the rest of the batch already applies |
| R6 | `intent.capnp:297–455` | Intent recording/replay (`recordIntent @10`, `replayIntent @11`, `getHistory @12`, `traceIntent @13`, `getMetrics @15`) and (610–671) activity recording/replay — two parallel "record and replay" machinery families | Two recording models (intent vs activity) with different step types — consumers building automation support must implement both. One consumer named for both families would collapse them; today there is none |
| R4 | `intent.capnp:299, 299` | `IntentChain.id :Text`, `IntentRecording.id :Text`, `IntentHistoryEntry.id :Text`, `recordIntent -> (recordingId :Text)` — every chain/recording/history entity addressed by free text | Text-addressed lifecycle objects (execute/cancel/delete chains by string) can't be validated or enumerated; typed ids exist for every other lifecycle entity in the batch (`T.IntentId` is even defined at types.capnp:444) |
| R1 | `intent.capnp:121` | `DispatchType` has `unspecified @0` as its zero (correct per validator E8's neutral-sentinel rule) — but `Intent.dispatchType @7 :DispatchType = unspecified` (51) makes "unspecified" a *default*: absent means "dispatcher decides" | Acceptable — noted here only to record that this file got the sentinel right where most of the batch did not; keep |

## Duplicates & overlaps
- `LaunchFlags`/`IntentCategory` overlaps `app.capnp:224 AppLaunchMode` (singleTask/singleTop repeat there) — one vocabulary leak, two files; fix together.
- Recording/replay (`IntentRecording`/`IntentReplayRequest`/`IntentReplayResult`, 361–420) vs activity replay (`ActivityRecording`/`ActivityReplayRequest`/`ActivityReplayResult`, 613–663) — byte-level parallel structures.
- `IntentMetrics` (540) / `getMetrics` vs the batch's analytics sprawl (notification, clipboard, cli, shell all have their own analytics structs) — one metrics/telemetry schema or none.
- `IntentAccessService` vs capability.capnp (R3 row).
- `waitForResult` vs `AppEvent`/subscriptions — the batch's answer to "notify me" exists everywhere else.

## Gaps & holes
- **Handler unregistration lifecycle**: `unregisterHandler @7 (componentName :T.ComponentName)` deletes by name — nothing states what happens to intents already dispatched to a dying handler (fail? queue? reroute?). Each backend will pick differently; this is the lifecycle the contract most needs and least specifies.
- **Result for chooser flows**: `DispatchMode.chooser @1` (209) says a chooser is shown — nothing defines what the chooser receives or returns (a rank list? how the user's choice comes back to the dispatcher?).
- **Broadcast ordering**: `sendBroadcast @3` has no ordering/delivery guarantee — receivers will implement different assumptions.

## Zero-cost / eco
- `resolve @0 (intent, page :T.Pagination)` — paginated correctly; good.
- `waitForResult` polling (R7 row) is the eco finding: a poll-based wait converts an event into a latency loop; every caller runs it.
- `getHistory @12` paginated; `listActivityRecordings @22` paginated; `listPolicies` paginated — the file is consistent on paging. Good.

## UX & implementer guidance
- `resolve @0` takes the pagination *before* the intent? No — after. Fine. But `resolveWithFilter @9` duplicates `IntentFilter` matching against `ComponentInfo` fields; consumers will not know which matching is authoritative (resolve's or the filter's).
- `IntentExtras.capnp @6 :Data` ("Serialized Cap'n Proto message", 148) — embedding raw capnp is acceptable but must declare a schema id or the consumer cannot decode; use `T.SchemaId` (types.capnp:452).
- `IntentCondition { field :Text, operator, value :Text }` (342–348) — stringly-typed intent-field predicates for chain preconditions; a future intent field can't be branched on without a string convention shared across backends.

## Recommended actions
1. **Replace `LaunchFlags` and `IntentCategory`** with platform-neutral vocabulary: a generic task/instance declaration (delegate to `T.AppId`-level multi-instance: `maxInstances`-style, as in app.capnp:169), open action/category tokens (`Text`, unknown-tolerated), and capability references instead of `grant*UriPermission` booleans (the grant *is* a capability). Gain: non-Android shells comply without emulation; the alternative-shell fork closes. Cost: 10 flags and 13 categories become open tokens + one launch-mode field.
2. **`waitForResult` → subscription or event**: return a subscription (`ActivityResultSubscription`) or deliver results on a registered handler's event stream. Gain: results stop being polled; every caller's wait loop disappears. Cost: one method reshaped (its ordinal preserved).
3. **Delete `IntentAccessService`**; intent access = capability verification (the caller's capability reference determines which intents it may dispatch). Gain: one authority path; rate limits via capability `RateBox`. Cost: 4 methods deleted.
4. **Typed ids for chains/recordings/history** (promote to types.capnp or use existing `T.IntentId`). Gain: lifecycle objects stop being stringly addressed. Cost: several fields retyped.
5. **Collapse the two recording/replay families into one** (`Recording` with steps that may be activities or intents), and require a named consumer for metrics/tracing beyond `T.Warning`-style diagnostics — or move to a diagnostics schema. Gain: automation consumers implement one model. Cost: ~80 lines collapse.
6. **`TraceStep.input/output` → `T.DataHandle`.** Gain: traces stop copying payloads. Cost: two retypes.
7. **Specify handler-death semantics and chooser contract** (two paragraphs). Gain: the two forks every dispatcher implementer currently resolves alone. Cost: prose.

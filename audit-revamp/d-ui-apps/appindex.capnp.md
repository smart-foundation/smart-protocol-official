# Audit — appindex.capnp (485 lines)

## Verdict
**FIX (targeted).** The index core is the best-designed part of the batch's app stack: paginated everything, a filter with typed version ranges, a typed launch-args union (131–159), a subscription with filters and coalescing (376–386), a batch get (75), and — uniquely in the batch — **`LaunchResult` with `success | error :T.Error` (172–177), the error-model pattern every other service in this batch should copy**. The defects are around that core. (1) The same inline-`Data` icon defect as app.capnp (`AppIcon.data @0 :Data`, 271) — a launcher grid copies every icon. (2) A store's backend leaked in: `submitRating @18`, `moderateRating @23`, `listPendingRatings @24`, `getRecommendations @17`, `getRecommendationReason @20`, `setSearchRankingWeights @21`/`getSearchRankingWeights @22` — ratings moderation and store ranking are a distribution service's job (package.capnp's domain), not the local index's. (3) `getApp @1 -> (app :AppInfo)` returns a struct with no not-found path — the LaunchResult file didn't apply its own lesson to the getter. Fix the icon, evict the store, add the not-found.

## Wire-breakers
None.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R2 | `appindex.capnp:271` | `AppIcon.data @0 :Data` inline (identical to `app.capnp:177`) | `listApps @0` over a 500-app catalog copies every app's icon into the response; shell/package/extension/notification all use `T.DataHandle` for this exact field. Megabytes per index read |
| R7 | `appindex.capnp:31` | `getApp @1 (appId) -> (app :AppInfo)` — no not-found path | An id from a stale subscription or a race with uninstall returns a zero `AppInfo` (name "", state `notInstalled` — which collides with a *real* state value!): the launcher shows a phantom entry. The file's own `LaunchResult` (172) shows the correct shape two screens above |
| R6 | `appindex.capnp:82, 97–100` | `submitRating`/`moderateRating`/`listPendingRatings` + `AppRating`/`RatingModerationState`/`RatingModerationDecision` — a rating-marketplace backend inside the local index | Moderation policy (who approves, what "flagged" means) is store governance; local indexes will implement five different policies, and the field names promise contract semantics that cannot be honored identically. Distribution belongs to package.capnp |
| R6 | `appindex.capnp:78, 88` | `getRecommendations`/`getRecommendationReason` + `RecommendationCategory`/`RecommendationReason` — a recommendation engine's taxonomy | "editorial", "developerReputation" are store concepts with no local meaning; two backends produce incompatible reason vocabularies, and consumers branch on them |
| R6 | `appindex.capnp:91, 94` | `setSearchRankingWeights @21` — *global mutable* ranking weights on the index | An app can rewrite the index's relevance for every other app on the system — a shared-resource mutation with no stated authority (per-method authority by caller identity; capability model has no operation for "rewrite system ranking") |
| Agnostic | `appindex.capnp:85` | `compareVersions @19 (versionA, versionB) -> (result :Int8, valid :Bool)` — pure arithmetic exposed as IPC | Both versions are already in the caller's message; the comparison is local. The round trip adds latency and a fork point (semver-prerelease ordering rules differ subtly across implementations — pre-release vs build metadata, epoch handling) where a shared local function has none |
| R1 | `appindex.capnp:301, 317, 293` | `AppCategory` (13) + `AppSource` (6) + `AppLaunchMode` — byte-identical copies of app.capnp's enums | Drift by construction: fix one file, the other silently disagrees; the shell's third taxonomy (289) already disagrees. One promotion target ends it |
| R4 | `appindex.capnp:471, 241` | `AppRating.id @0 :Text`, `AppInfo.developer/license :Text`, `matchField @2 :Text`, `highlights :List(TextRange)` | Ratings addressed by free text; "highlights" as `List(TextRange)` (a pair of UInt32s) forces clients to re-parse which field the range refers to via `matchField` — a structured `match { field, range }` is one struct |
| R7 | `appindex.capnp:75` | `batchGet @16 (appIds :List(T.AppId)) -> (apps :List(AppInfo))` — unbounded in AND out; a 2000-id request returns 2000 infos in one message | batching without pagination just moves the unboundedness; cap the input or page the output |

## Duplicates & overlaps
- `AppIcon`/`FileRef`/`AppCategory`/`AppSource`/`AppLaunchMode` vs `app.capnp` (identical) — see app audit; promote to types.capnp.
- `AppInfo` vs `app.capnp AppDetailedInfo` vs `shell.capnp ApplicationEntry` — three app-metadata structs with overlapping fields (name, icon, categories, version, source, launchMode). The index owns catalog metadata (its header says so, 10–11); `AppDetailedInfo` should *be* `AppInfo` + runtime extras, and shell's `ApplicationEntry` should delegate here.
- Ratings/recommendations vs package.capnp's distribution surface (they both now answer "what is available and what do people think") — package is the store; the index is the catalog.
- `AppState` (278) vs `app.capnp AppLifecycle` (210): two lifecycle enums with overlapping values (`running`, `suspended`, `stopping`, `stopped`) — the runtime state is app.capnp's, the install state is the index's; nothing says which is which, and both files define both.

## Gaps & holes
- **Index ↔ lifecycle ownership**: `AppIndexEvent.stateChanged` reports `AppState` (432–437) while `AppEvent.stateChanged` (app.capnp:452) reports `AppLifecycle` — the same real-world transition is observable as two different enums on two subscriptions. Whether both fire, and in what order, is unstated: a launcher must subscribe to both and reconcile.
- **Who installs?** `getDependents @15 (packageId)` reaches into package ids, but the index has no install method — launch and list fail with a not-installed state and no path to fix it. The natural delegation (index → package.install) should be stated so consumers don't hunt.

## Zero-cost / eco
- `AppIndexSubscriptionFilter.coalesceWindowMs @3 :UInt32` (385) — genuinely good: rapid state changes batch per app, the anti-thrash pattern the eco lens wants. Keep and cite it as the model.
- `pull @11` returns `List(AppIndexEvent)` unbounded — give it a `maxEvents` bound like other batch subscriptions.
- Inline icons (R2 row) are the copy-cost item; recommendations/ratings carry no bulk.

## UX & implementer guidance
- `LaunchSuccess.pid @1 :T.ProcessId` (181): a pid in a capability world is process-internal detail compensating for launch semantics that should deliver a capability or instance reference to the launched app. Useful for compatibility; note it as a smell, not a defect.
- `AppSearchResult.highlights :List(TextRange)` (194): a client receiving three ranges has no field to attribute them to without `matchField` — one missed field turns highlights into garbage. `struct Match { field :Text; range :TextRange; }` is the honest shape.
- `submitRating @18 (appId, rating :Float32, review :Text)` — unvalidated free-form user content entering the index; the moderation machinery exists *because* of this method. Removing the store domain removes the moderation too.

## Recommended actions
1. **`AppIcon.data` → `T.DataHandle`; promote `AppIcon`, `FileRef`, `AppCategory`, `AppSource`, `AppLaunchMode` to types.capnp** and have app/appindex/shell import them. Gain: icons stop copying; three drifted taxonomies become one. Cost: promotion + retypes; shell's rival taxonomy deleted.
2. **`getApp`/`batchGet` return `AppInfoResult { app } | T.Error`** (or paginate batchGet). Gain: stale ids stop producing phantom entries; the file's own LaunchResult pattern applied consistently. Cost: two signatures.
3. **Evict the store domain** (ratings, moderation, recommendations + reasons, ranking weights) into package.capnp or a store schema when a consumer files the requirement. Gain: the index becomes list/search/launch/pin/track — a surface a local backend implements identically; moderation fork disappears. Cost: ten methods + five enums removed; zero consumers exist today.
4. **Delete `compareVersions`** — version math is local to `T.Version`. Gain: removes a fork point in prerelease ordering. Cost: one method.
5. **Give `pull` a `maxEvents` bound.** Gain: subscriptions behave like the batch's other bounded pulls. Cost: one parameter.
6. **State the index↔lifecycle relationship** (which enum owns runtime state; whether both events fire; index delegates install to package). Gain: launchers stop reconciling two lifecycles by guesswork. Cost: one paragraph + possibly one enum demoted to a view.

# Audit — app.capnp (537 lines)

## Verdict
**FIX (targeted).** The lifecycle core — running-app listing with pagination, `T.ResourceUsage`, `T.ExitStatus` on close (447), `T.SignalKind` on crash (462), instances, health subscription — is contract-correct, and the file's header correctly disclaims ownership of package metadata (9–11). Three defects, all demonstrable. (1) `AppIcon.data @0 :Data` (177) is inline icon bulk — the exact R2 pattern every other schema in the batch already fixed with `T.DataHandle` (shell:315, package:176, extension:115, notification:136). A launcher grid over 200 apps copies 200 icons into one message. (2) The file runs a **second authority model alongside capability.capnp**: `AppPermission.permission @0 :Text` (382) — permission strings like "access.camera" per the file's own comment — plus `delegatePermission @19`, `checkDelegationAuth @26`, `listDelegationAuthorizations @27`. The doctrine is explicit: no permission strings, the capability system IS access control (DESIGN_PRINCIPLES:399). Two authority paths that must agree forever, exactly at the layer where disagreeing is catastrophic. (3) `getAppInfo @7`/`getAppState @8` return structs with no not-found path. Fix those; the rest is sound.

## Wire-breakers
None.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R3 | `app.capnp:380–393` | `AppPermission` declares permissions as free-text strings (`"access.camera"` per the comment at 381) with granted/required/revocable booleans | The protocol forbids permission strings (DESIGN_PRINCIPLES:399; TIMELESSNESS:135). Every backend now resolves permission semantics its own way, app-to-app delegation (`delegatePermission @19`) re-implements capability transfer/attenuation that `capability.capnp` already defines (transfer @3, attenuate @2). Two authority systems, and only one is revocable — the string one |
| R5 | `app.capnp:224–229` | `AppLaunchMode { singleInstance, multiInstance, singleTask, singleTop }` — Android Activity launch modes (singleTop/singleTask are `FLAG_ACTIVITY_*` names) | A non-Android shell (VR, embedded, a 2046 spatial shell) has no "task" or "top instance" concept; it must emulate an activity stack to comply. Same leak in `intent.capnp:82–98 LaunchFlags` and duplicated verbatim at `appindex.capnp:293` |
| R2 | `app.capnp:177` | `AppIcon.data @0 :Data` inline | An app-index/launcher grid of 200 apps ships 200 inline icon blobs (4–64 KB each) — megabytes copied per screen render, buffered whole on the receiving end. Every sibling schema already uses `T.DataHandle` for this exact field |
| R7 | `app.capnp:49, 52` | `getAppInfo @7 -> (info :AppDetailedInfo)`, `getAppState @8 -> (state :AppLifecycle)` — no not-found/error path | A queried id for an uninstalled app returns a zero-valued struct: name "", lifecycle `stopped`, indistinguishable from a stopped installed app. `getRunningApps` paginates, but single-get did not adopt the `LaunchResult` pattern `appindex.capnp:172` already established |
| R7 | `app.capnp:417–435` | `AppEvent` union ends `custom @12 :Data` — a bare Data payload, not `UnknownEvent { typeId, payload }` | A backend adding an event type the consumer cannot route — the consumer sees bytes with no type discriminator. The doctrine's forward-compat shape (TIMELESSNESS:98) exists for exactly this |
| R6 | `app.capnp:18` | `checkForUpdate @18` duplicates the package domain: `package.capnp:18–21 checkUpdate/update/downloadUpdate/getUpdateLifecycle` run the whole update lifecycle | App updates now have two homes with different models (`AppUpdateNotification` here vs `UpdateCheckResult`/`UpdateLifecycleState` there); an updater UI must merge both. Package owns distribution (its own header says so); app should reference, not reimplement |
| R1 | `app.capnp:192` | `AppCategory` (13 values) — byte-identical to `appindex.capnp:301` and a *third* rival to `shell.capnp:289 ApplicationCategory` | Three category taxonomies; an app's category must be mapped at every surface boundary; a future category has no ordinal in any of the three. One taxonomy (promoted to types.capnp, or open tokens) ends it |

## Duplicates & overlaps
- `AppCategory`/`AppLaunchMode` vs `appindex.capnp:301, 293` (identical copies) and the divergent `shell.capnp:289` taxonomy.
- `AppIcon` vs `appindex.capnp:271` (identical struct, same inline-Data defect) — one promotion target, one retype.
- `FileRef` (119) vs `appindex.capnp:161` — identical duplicates; `T.FilePath` exists in types.capnp:726, so promote `FileRef` there and both files import it.
- `checkForUpdate`/`AppUpdateNotification` vs package.capnp update lifecycle (above).
- `AppMessageType @254` vs the previously bare `type @0 :Text` (335): the file keeps BOTH (`typedType @4` alongside legacy `type @0`, 332–335) — the drift already happened here once; post-merge, keep only the typed one (nothing external consumes the legacy field).

## Gaps & holes
- **What is an AppId?** Nothing states how an `AppId` is allocated or whether it survives reinstall/upgrade — apps' identity across update cycles is the contract's most load-bearing assumption, and it is unstated. `T.AppId` is opaque; the *issuance* rule is missing, and appindex/app/package each assume a different owner of identity.
- **Cross-app messaging has no answer path**: `sendMessage @13` has `expectResponse`/`responseTimeout` in `AppMessage` (339–341) but no method to *receive* the answer — only `messageReceived` events carry the inbound copy. Request/response needs a correlation id; `replyTo` exists in ai.capnp's pattern (ai.capnp:220) and is absent here.

## Zero-cost / eco
- `getResourceUsage @12 -> T.ResourceUsage` — correct shared type, no copy.
- `AppMessagePayload.data @1 :Data`/`json @2 :Text` inline (346–349): app-to-app messages are document-sized in real systems (share-sheet payloads); a DataHandle variant is the batch's standard fix.
- Subscription is pull+cancel (412) — canonical.

## UX & implementer guidance
- `openFile @1 (resource, appId)` and `openWith @3 (resource, appId)` are the *same signature* with different names and ordinals — one of them is redundant on arrival; a client cannot tell which the backend honors.
- `RunningAppInfo.instanceId @6 :UInt32` (139) — a sentinel-zero question again: instance 0 vs "not an instance app".
- The health/delegation/crash-recovery surface (audit-8/9/10: getHealth, subscribeHealth, getPermissionDelegations, setCrashRecoveryPolicy, checkDelegationAuth, listDelegationAuthorizations) is eight methods whose only consumers would be a settings UI and a policy engine — candidates for the same "name a consumer or defer" test as shell.

## Recommended actions
1. **`AppIcon.data` → `T.DataHandle`; promote `AppIcon` and `FileRef` to types.capnp** (app and appindex import them). Gain: launcher grids stop copying icons inline; FileRef/AppIcon stop being duplicated-and-drifted twins. Cost: two moves, one retype.
2. **Delete the permission-string model**: replace `AppPermission.permission :Text` with a `Capability` reference and route grant/delegation/check through capability.capnp; drop `delegatePermission`/`checkDelegationAuth`/`listDelegationAuthorizations`/`getPermissionDelegations` or make them views over capability state. Gain: one authority path — the doctrine's hard rule; app-to-app grants inherit attenuation/revocation/audit they currently lack. Cost: eight methods change; the capability service is the honest home.
3. **`getAppInfo`/`getAppState`/`openFile` return results with not-found and error.** Gain: uninstalled apps stop looking like stopped ones. Cost: three signatures.
4. **Delete `AppLaunchMode`'s Android modes (or the enum) and fix `LaunchFlags` in intent.capnp the same way** — a generic multi-instance declaration (`maxInstances :UInt32`, already at 169) covers both without activity-stack semantics. Gain: non-Android shells comply without emulation. Cost: one enum trimmed, one struct reduced.
5. **Delete `checkForUpdate` and reference package.capnp** for the update lifecycle. Gain: one update path. Cost: one method lost; the package service's richer lifecycle replaces it.
6. **One app-category taxonomy** — promote the app/appindex copy to types.capnp, fold shell's into it, or replace all three with open tokens. Gain: category mapping at surface boundaries stops. Cost: a cross-file move plus one shell deletion.
7. **State the AppId issuance rule** (who allocates, survival across update/reinstall). Gain: the load-bearing identity assumption stops being three backends' guesses. Cost: one paragraph.

# BATCH REPORT — d-ui-apps (Wave 4)

**Scope:** the 18 schemas of `audit-revamp/d-ui-apps/`. Nothing outside them was
modified except one 4-line compatibility note recorded in §5.

**Headline numbers**

| | before | after |
|---|---|---|
| files | 18 | 16 (`surface.capnp`, `textinput.capnp` deleted) |
| lines | 10,279 | 8,787 (**−1,492, −14.5%**) |
| enums in the batch | 220 | 146 |
| `unknown`-terminated event unions | 7 of 11 | 11 of 11 |
| parallel authority models | 5 | 0 |

The batch absorbed two whole files (726 lines) and imported the working tree's
live 45-method `ShellService`, and is still 1,492 lines smaller.

---

## 1. Per-file change summary

### compositor.capnp — REWRITTEN (1550 → 1249)
The batch's model file. Three changes carry the batch.

**(a) THE UNIFIED COMMIT PATH (founder ruling).** `Surface.capnp` had drifted
into a second commit contract: `FrameSubmission` referenced its buffer by
`T.BufferId` and its fence by `SyncFence.handle :T.FenceHandle`, while
`compositor.Session.commit` referenced the buffer by `bufferIndex @2 :UInt8` and
the fence by `SyncFence.native @0 :UInt64`. Two buffer mechanisms and two fence
types for one operation, so an app could not reason about its fence across the
two paths and a compositor had to keep both semantics alive forever. There is
now ONE `SurfaceCommit { surfaceId, frameId, buffer :T.BufferId, format,
damageOption, present, fence :SyncFence, transform }`, reached by
`attachBuffer` (binds a buffer to a surface by `T.BufferId`) then `commit`.
`SyncFence` holds a `T.FenceHandle` and an explicit `none` — no raw integer for
a backend to reinterpret. surface.capnp's useful types are absorbed:
`SurfaceState`, `FrameData` (with `committedDamage :T.Region` — damage as
geometry, never pixels), `FrameMetrics`, `present.periodic`, the typed fence,
and buffer attach. surface.capnp is deleted.

**(b) The accessibility fork is closed.** The file carried its own
`AccessibilityNode`/`AccessibilityRole`/`AccessibilityState`/`AccessibilityAction`/
`AccessibilityTree` — a *reduced* copy (39 roles, no ranges, no live regions, no
reading order) of `accessibility.capnp` (70 roles, ranges, liveRegion, value,
readingOrder). A screen reader trained on one could not interpret the other.
Deleted. `updateAccessibilityTree` now binds a surface to a tree root
(`T.AccessNodeId`) and the tree itself is described and mutated through
`accessibility.capnp` — the import pattern surface.capnp:4 already used
correctly and this file ignored.

**(c) Everything else that made it a kitchen sink.** Deleted: the flat
`Compositor` interface and its 4 subscription interfaces (SCHEMAS.md:68 already
claimed "Session interface only"), with its live capabilities migrated to the
Session (`capture`, `listLayers`, `inhibitOutput`, surface ordering);
`SurfaceRole` (24 frozen UI nouns → open token, published as conformance
constants); `BackendKind` (deployment topology = how a component works);
the DRM key exchange, the plugin loader, the gesture-recognizer pipeline, the
live-region subscription (canonical home: accessibility.capnp), health
monitoring, state snapshot, remote access and resource limits (a third quota
model); `EasingType`/`InterpolationType`/`PhysicsSpring`/`Keyframe` (replaced by
the canonical `T.AnimationSpec`); the `DisplayZone` family (automotive seat
nouns); `Theme`/`ColorScheme`/`AnimationPreferences` (theme.capnp owns tokens);
`OutputInfo`/`OutputMode` kept here as the canonical output types that
windowmanager now imports. `EventStream.next` became
`pull(maxEvents)` — one event per round trip on the pointer hot path was the
most expensive pattern in the batch. `query` and `listLayers` are paginated with
totals. `commit` returns `T.VoidResult` instead of `()`: a silent success on the
hottest call in the protocol.

This file also publishes the batch's canonical service-session handshake
(`SessionRequest`/`SessionResponse`/`CapabilityRequest`/`ServiceInfo`), which
windowmanager, ime and shell import rather than re-declaring.

### windowmanager.capnp — REWRITTEN (1078 → 606)
- **Layering inversion removed** (R8): `using Shell = import "shell.capnp"`
  for one field (`LockScreenShortcut.action`) meant the WM could not compile
  without the shell, so any shell rewrite forced a WM rebuild. Now imports
  compositor only, and nothing from shell.
- **Flat `WindowManager` interface and its `*Paged` twins deleted** (55 methods).
  The unbounded Session originals (`listWindows`, `listSnapZones`,
  `listWorkspaces`, `listOutputs`) are now paginated with totals, so the paging
  fix is no longer optional.
- **R4:** `Window.pid`, `WindowFilter.processId` `UInt32` → `T.ProcessId`;
  `Window.appId` `Text` → `T.AppId`; `WindowGroup.groupId`/`destroyWindowGroup`
  now use a real `WindowGroupId` (window→group correlation was previously
  impossible without a hand-rolled client-side map); `SnapZone.id` →
  `SnapZoneId`; `SnapPreset`'s 17 frozen layout positions → open token.
- **Second capture authority removed.** The file had its own
  `CaptureRequest`/`CaptureFrame`/`CaptureSource`/`CaptureMode` beside the
  compositor's, and its `CaptureFrame.dataHandle @5 :UInt64` carried a comment
  telling consumers to *pretend* a raw integer was a `T.DataHandle`. Deleted;
  compositor owns capture.
- **Window animation** delegates to `compositor.defineAnimation` (which returns
  a server-issued id; `animateWindow` took a caller-chosen `UInt32` that
  collided with app-local numbering).
- **The domain grab is gone:** foldable/hinge state, automotive HMI, voice
  windows, mobile snap presets, input redirection, lock-screen and notification
  windows (the notification service owns its own surfaces). `FocusReason` and
  `CustomQuery` now come from compositor.
- `getWindow`/`getFocusedWindow`/`getOutput` return result unions — a missing
  window used to arrive as a default-valued `Window`.

### ime.capnp — REWRITTEN, textinput absorbed (473 + 308 → 513)
The doctrine-declared merge, executed. textinput.capnp was not a stale copy —
it had *drifted*: `ContextRequest`, `SurroundingText`, `InputMethodInfo` and
`InputMethodState` existed in both files with different fields, so a client
written against one got silently wrong data on the other. Absorbed:
per-surface contexts, per-context enable/disable/reset (the old `disable @5`/
`reset @6` took no context id, so an app could not say *which* context it was
disabling), `commitTextHandle` (`T.DataHandle` commit for pasting a document),
the language stack, dictation, strokes, suggestions and interactive input
requests. Not carried forward: `charTimings` (profiling in the live event) and
the service-level pull/cancel trio.

- **`InputModality` closed → open token (founder ruling).** The file's own
  header promised "any future input modality" and then enumerated
  `{keyboard, voice, handwriting, gesture, neural, spatial, hybrid}` — and put it
  in a *required* position (`switchInputMethodForContext`). The one file that
  promises a future modality could not express one. Modality, content type,
  purpose and keyboard type are now open tokens with published conformance
  constants. `IMECapability` (the same seven values, duplicated) collapses into
  the modality capability list.
- **The capability museum collapsed.** `getVoiceInfo`/`getHandwritingInfo`/
  `getPredictionInfo`/`SpatialKeyboardInfo` — four methods, five structs, five
  enums describing per-modality capability — became ONE `getModalityInfo`
  returning an open `ModalityInfo`. Gain: a backend with no voice engine needs
  no stub, and a modality invented tomorrow publishes its parameters as keys.
- **Strokes are buffer references.** `Stroke.points :List(T.Vec2)` +
  `pressure :List(Float32)` were inline on the highest-volume pointer-adjacent
  stream in the protocol — a copy per stroke, forever. Now two `T.DataHandle`
  arrays with a `pointCount`.
- `createContext` returns a result union; `listInputMethods` is paginated;
  `InputMethodState.currentMethod`'s zero-means-none sentinel is an explicit
  union; the five Void-returning mutations return `T.VoidResult` (the audit-3
  note claimed this was done).

### shell.capnp — REWRITTEN with naledzi `ShellService` imported (1037 → 1292)
Founder rulings: import `ShellService` (45 methods), keep `Session`
byte-compatible, delegate to notification/clipboard/settings.

`ShellService` is imported essentially verbatim — getState/start/end/execute/
interpret/confirmAndExecute, completion (3 forms), history, aliases, variables,
environment, jobs, undo, scripts, watchers, bookmarks, guided mode, undoable
registry — with its documented two-surface rationale and its deliberate
omissions (getPrompt/setPrompt, session snapshots) preserved. It is reachable
through `Session.interpreter @76 (authority :Capability) -> (service :
ShellService)`: **one** accessor, capability-gated at acquisition, matching
`ai.capnp`'s root shape. Nothing inside `ShellService` checks a permission.

`Session` keeps all 67 methods at their ordinals. What changed is whose types
they carry: `Notification`/`Urgency`, `ClipboardEntry`/`ClipboardContentType`,
`ShellSettingValue`/`ShellSetting`/`SettingFilter`, `ApplicationEntry`'s rival
`ApplicationCategory` are gone, replaced by `notification.NotificationData`,
`clipboard.ClipboardContent`/`ClipboardItem`, `settings.SettingValue`/
`SettingMapEntry`, `appindex.AppInfo`. One notification model, one clipboard
model, one settings model, one app taxonomy. `getSetting` now takes
domain+key (a domain-less key was a collision with itself). DND reads and
writes notification.capnp's single authority.

Deleted: the orphan type zoo no method referenced — AR spatial shell, car
split-screen zones, shell analytics, theming pipeline, multi-user profiles,
plugin info, session persistence, notification grouping, command-history
analytics (which also ends the `CommandHistoryAnalytics` name collision with
cli.capnp) and the shell's third accessibility-tree model. `GestureEvent`
→ `ShellGesture` (name collision with `types.capnp`), `WakeWordSubscription`
→ `ShellWakeWordSubscription` (collision with speech.capnp). The malformed
`using import "power.capnp".PowerState;# ══…` line is fixed.

### cli.capnp — SIMPLIFIED (335 → 502)
**Not redesigned.** The verifier rejected the schema-derived command registry
as overreach (the "brief" exists in no document), and every verified defect in
this file is fixable by deletion.

Imported naledzi's live registry: `listCommands @12`, `listUnavailable @13`,
`getSyntax @14` + `CommandRegistration`, `CommandPresentation`,
`AvailabilityReason`, `SyntaxReference`, `DomainInfo`. The registration is
re-specced as **schema identity** — `schemaId :T.SchemaId`, `interfaceName`,
`methodName` — so a command routes through an existing service contract and a
new domain gains commands by declaring a schema. The per-command capability
token string is gone (authority is the reference held at acquisition), and the
opaque `methodId :UInt32` with no published domain is gone.

Deleted: `checkPermission` (per-call authority by name), `getJobStatus` and
`pollPrompt` (polling loops → `subscribeJob` and `InteractiveSession.pull` with
a structural terminator), `createScript` + the `CommandScript` mini shell
language (`executePipeline` is the one composition model),
`getHistoryAnalytics` + `CommandHistoryAnalytics`, `sendInput` (moved onto
`InteractiveSession`, so the `sessionId :Text` disappears),
`PipeMode.redirect`/`append` (they named a redirection target no field could
carry), `CommandOutputFormat` → `T.MimeType`, local `ResourceLimits` →
`T.Quota`, `InteractiveInputType` → open token aligned with ime's fix. Kept
exactly: `execute`, `spawnBackground`, `killJob`, history, `executeStreaming`,
aliases, `executePipeline`, `executeInteractive`, and every `T.DataHandle` on
stdin/stdout/stderr. `EnvironmentMode.@0` flipped `replace` → `inherit` (an
absent field must not silently replace the caller's environment).

### clipboard.capnp — FIXED (265 → 238)
The live path used the handle type. `getContent`/`setContent`/`convertContent`
now carry `ClipboardContent { mimeType, data :T.DataHandle }` — the struct this
file defined and never used, while pasting a screenshot copied the whole buffer
into the message on the protocol's most copy-prone path. New `setOffer` accepts
several representations of one copy in one call (the mechanism every real
clipboard has, previously three unassociated `setContent` calls). The parallel
authority model is deleted: `grantAccess`/`revokeAccess`/`getAccessControlList`/
`getAuditLog`/`setSecurityLevel`, `ClipboardAccessControlEntry`,
`AccessGrantType`, `ClipboardAuditEntry`, `ClipboardSecurityPolicy`,
`ClipboardSecurityLevel` — a second access-control system keyed by free-text
entity ids that must agree with capability.capnp forever and is the only one of
the two that is not revocable. Also: the consent flow `requireConsent` named
but no method implemented; `inlineThreshold` (a protocol field prescribing when
an implementation should switch strategies); `StructuredContentType` (a third
content-type model, unused). `ClipboardChange.source` → `T.ClipboardSourceId`.
Single-selection documented as a deliberate limit.

### notification.capnp — FIXED (379 → 313)
`show` and `schedule` return `ShowResult { id } | T.Error` — sending can fail
(no channel, quota, invalid attestation) and the app used to hold a tombstone
id for a notification that was never posted. Every list answer carries a total
and the thread getters are paginated. Three priority vocabularies → one
(`QueuePriority` and the queue machinery it served are deleted); `aiPriority`
becomes a service-reported value ignored on write. Deleted: inter-service
notifications (a second dispatch table), delivery tracking, queue stats,
analytics, `delegate` by free-text handler id, `lightColor` (a 2010 phone
component). `AttestationVerification.error` → `T.Error`. Replace-on-existing-id
and snooze persistence stated so no backend guesses. This service is now the
one DND authority (the shell's copy reads and writes it).

### settings.capnp — FIXED (266 → 193)
`get` returns `SettingResult { value | notSet | error }` — the union's zero
member is `string`, so a missing key arrived as an empty string and every
backend invented a different sentinel. Deleted: `pullSettings` (a deprecated
second path to one change stream), roaming profiles (with a raw `deviceToken`
credential as a message parameter), encrypted settings (making the store a
crypto participant), the dependency graph, templates, the reactive
subscription, and six orphan structs — two of which were worse than dead:
`SettingCondition` hardwired `batteryAbove`/`batteryBelow`/`charging` into the
universal contract (a rack server evaluates them as nonsense), and
`TimeRangeCondition` carried a `daysOfWeek` bitmask with no published bit
assignment. Write authority stated: gated once at acquisition, the store does
not check per-key permissions. `getSettingsDiff` kept and cited as the batch's
best eco design. `SettingCategory` → open token.

### theme.capnp — FIXED (549 → 379)
Four algorithms deleted (`extractColorsFromImage`, `generateThemeFromColors`,
`checkContrastRatio`, `simulateColorBlindness`): two engines swapping produced
different palettes while the contract named no winner, and contrast ratio is
arithmetic on two colours the caller already holds. The migration subsystem
deleted (Cap'n Proto's additive field evolution is the migration story).
`pullTheme` (a manual poll beside the subscription) and `pullPaged` (paginating
a snapshot stream) deleted. `ThemeTokens` no longer nests a second full
`ThemeTokens` for the light palette — it referenced the companion by
`T.ThemeId`, halving every snapshot delivered to every subscriber — and carries
an open token map, so a display paradigm names new tokens with no ordinal.
`installTheme` declares the bundle's content type. `ThemeVariantKind` and the
three `getSystem*Preference` methods deleted (one preference owner:
accessibility.capnp). `EasingCurve` → `T.AnimationSpec` (bezier and spring
curves now expressible). `SystemColorScheme.@0` was `light` — an absent
preference silently meant light. ONE identity (`T.ThemeId`); the parallel
`id :Text` is gone.

### accessibility.capnp — FIXED (657 → 688)
WAI-ARIA out of the required position: `AriaProperties`, the four methods that
read and wrote it, and `AriaLive`/`AriaCurrent`/`AriaHasPopup`/`AriaInvalid`
deleted. The Swap Test fails on them — swapping a webview backend for an AR/VR
HMI means *emulating* ARIA semantics the backend does not possess
(`current: step`, `owns`, `hasPopup: listbox`). `NodeRelationship` survives as
the neutral relationship form with an open type token. `exportTreeJson` and
`getSelectedText` → `T.DataHandle` (the file's lazy design undone for the one
call where trees are largest). `NodePropertyChange` → `T.MetaValue` and
`batchUpdate` gains per-update results (partial success becomes visible). One
politeness scale (`rude` folded in from `AriaLive`). **Root discovery added**
(`getRoot (surface)`) — previously every backend invented it. `simulateEvent`
took an action enum for an event kind. The lazy tree, deltas, ranges,
granularity, relationships, preferences and paginated traversal are unchanged.
`AccessibilityRole` (70 values) kept — see §4.

### app.capnp — REWRITTEN (537 → 384)
The parallel authority model deleted: `AppPermission.permission :Text`
(strings like `"access.camera"`), `delegatePermission`, `checkDelegationAuth`,
`listDelegationAuthorizations`, `getPermissionDelegations` and four structs —
five methods reimplementing permission strings, app-to-app delegation and an
authorisation record that capability.capnp already defines with attenuation,
revocation and audit, and the string model is the only one of the two that is
NOT revocable. `listCapabilities` now reads the manifest's
`CapabilityRequirement { target, operations }`. Also deleted: `openFile`
(the same signature as `openWith`), `checkForUpdate` (package owns the
lifecycle), the health surface, the crash-recovery policy (a third restart
policy beside init.capnp's and types.capnp's), `AppResourceLimits` →
`T.Quota`, `AppLaunchMode` (Android activity modes; `maxInstances` is the real
declaration), the legacy `AppMessage.type` beside `typedType`.
`AppDetailedInfo` is now literally `AppInfo` + runtime extras; `AppIcon` and
`FileRef` come from appindex; cross-app messaging has a reply path
(`correlationId`); `instanceId` is an `AppInstanceRef` union rather than a
sentinel `UInt32`. **The AppId issuance rule is stated** — allocated by the
index at install, survives upgrade and reinstall of the same manifest, a
different manifest is a different app — because appindex, app and package each
assumed a different owner of identity.

### appindex.capnp — REWRITTEN (485 → 421)
One app taxonomy: `AppCategory` and `AppSource` became open tokens published
here and imported by app.capnp and shell.capnp. There were three rival category
lists, so an app's category had to be mapped at every surface boundary and a
future category had no ordinal anywhere. The store domain evicted: ratings,
moderation, recommendations, reason codes, search-ranking weights (a global
mutable shared resource with no stated authority) and `compareVersions` (pure
arithmetic exposed as IPC, with a prerelease-ordering fork in it). The index is
now list/search/launch/pin/track. `AppInfo.manifestName` points at the
bundle's `Manifest`, so an app format invented tomorrow is describable with no
change here; `listCapabilities` reports the manifest's requirements instead of
a permission-string vocabulary. `AppIcon.data` → `T.DataHandle`. `getApp`/
`batchGet` return result unions and batchGet is bounded in as well as out.
`AppState` is install state only — the two lifecycles are now disambiguated
rather than both files defining both.

### package.capnp — REWRITTEN (573 → 474)
`PackageInfo` embeds the `Manifest` and `Provenance` is deleted (it was a
byte-identical twin of `ManifestProvenance` — proof the duplication had already
drifted). `PackageType` deleted → `Manifest.shape`: a 2046 bundle kind (a model,
a policy pack) has no ordinal, and the founder's rule for apps now holds.
`install` returns `InstallResult { id } | T.Error` — install failures are the
normal case and every one used to arrive as a valid-looking id. **No plaintext
credentials:** `OciCredentials { registry, username, password :Text }` is gone;
`installBundle` takes an opaque reference, an open content type, an open
platform token and a `T.SecretKeyId` — a credential the caller is authorized to
read, never a password on the wire. Deleted: the mirror fleet and cache config
(a distribution server's topology and a cache *filesystem path* as interop), the
SLSA/in-toto/Sigstore apparatus, `signPackage`, `decryptPackage`, staged
rollout (canary percentages and rollback-on-latency are deployment ops), and
`PackageDetailInfo.scripts` (install scripts as protocol data with no execution
contract). The update lifecycle kept as observable state — the Agnostic Test's
own edge case says reject the algorithm and accept the state. `PackageEvent`
gains `unknown`; `DependencyGraph` renamed `PackageDependencyGraph` (a service
graph of the same name lives in discovery.capnp).

### extension.capnp — REWRITTEN (387 → 386)
The header's promise is now true. The WASM runtime (`loadWasmModule` and five
siblings, `WasmExtensionInfo` with `memoryPages`/`wasiVersion`/`threads`,
`WasmExtensionHost`) is replaced by `loadModule`/`unloadModule`/`getModuleInfo`
with an open `runtime :T.MimeType` and an open parameter map — a host running a
sandbox not yet invented no longer fakes WASM fields. **`ScriptAction` deleted:**
`{ script :Text, language :Text }` instructed hosts to execute arbitrary text on
install/enable/update paths — a remote-code-execution instruction published as
contract, the same class ai.capnp removed from its own `ToolRegistry.invoke`.
Hook actions are an API invocation or nothing. One capability model:
`ExtensionCapability`/`CapabilityScope` deleted and the `grantWasmCapability`
string path with them (`grantCapability`'s `T.PermissionId` was the correct
one all along). Also deleted: the bus (a third messaging model beside queue and
app messaging), the orphan `WasmExtensionHost`, the sandbox config
(`allowedApis`/`deniedApis` permission strings, `networkAccess` authority
flag), the update path (extensions are packages), the signing surface.
`ExtensionTrustLevel` → the promoted `T.TrustLevel`; hook ids server-issued;
`apis` is a typed declaration with a `T.SchemaId` so bindings are generatable;
`checkCompatibility` and `getExtensionHealth` return routable results; resource
usage states its sampling interval.

### intent.capnp — REWRITTEN (671 → 727)
Android out of the required position. `LaunchFlags` was a transcription of
`FLAG_ACTIVITY_*`; `IntentCategory` was Android's intent-filter categories
(`browserCategory` included); `ActivityResultCode.firstUser` was
`RESULT_FIRST_USER`. Replaced by `DeliveryHints` (maxInstances, visibleInRecents,
exclusive, expectsResult, and authority as capability references — a grant IS a
capability, not a boolean per permission kind) and open action/category tokens.
`waitForResult` (every caller's poll loop) → `subscribeActivity`.
`IntentAccessService` and its `IntentAccessPolicy` (allowed/denied action string
lists plus a rate limit) deleted: the caller's capability reference determines
which intents it may dispatch. Two record/replay families collapsed into one
`Recording`/`RecordingStep`. Chains, recordings, traces and history addressed by
server-issued typed ids instead of free `Text`. `TraceStep.input/output` →
`T.DataHandle`. `IntentExtra.capnp` declares its schema id. Handler death,
chooser and broadcast-ordering semantics stated where they were prose.

### manifest.capnp — FIXED (311 → 422)
`resolveByName` added — the only lookup was by an opaque `T.ManifestName`
while the file's own text said a name is unique within its issuer's namespace,
so every backend shipped its own name registry and a non-interoperable
string→id map. `ManifestEvent` gains `unknown` (validator E6 flagged the one
file held up as timeless). `validate`/`verify`/`validateDependencies` carry
`T.Error` alongside the human list. Orphans (`VersionRange`,
`DependencyWithAttestation`) and the OCI vocabulary deleted. `Semver` replaced
by `T.Version` throughout (a 16-bit major wraps at 65535) — see §5 for the one
reason the type is still exported. `Asset.sizeBytes` → UInt64.

### surface.capnp — DELETED (418 lines)
Merged into compositor.capnp (§1 compositor (a)). Zero importers in the
canonical tree.

### textinput.capnp — DELETED (308 lines)
Merged into ime.capnp (§1 ime). Zero importers in the canonical tree.

---

## 2. Cross-batch items (exact file + action)

Ordered by blast radius. Each names the file, the owner batch, and the action.

**Blocking / high**

1. **`types.capnp` (A) — `T.UnknownEvent` payload type.** `types.capnp:230`
   defines `UnknownEvent { typeId @0 :UInt64; payload @1 :Data }`. `:Data` is
   inline and therefore a copy, which is R2's exact failure for an unknown
   event whose size is unbounded by definition. Every event union in the tree
   now terminates with this type, so the choice is load-bearing. **Action:
   change `payload` to `T.DataHandle`** (compositor.capnp previously carried a
   local copy with `:T.DataHandle`; it was deleted in favour of the canonical
   type, so this is now the only lever). Note `ai.capnp:535` also uses `:Data`.
2. **`types.capnp` (A) — missing promoted ids used by this batch.**
   `windowmanager.capnp` and `intent.capnp` define local `WindowGroupId`,
   `SnapZoneId`, `IntentChainId`, `IntentTraceId`, `IntentHistoryId` because
   these are not in types.capnp. **Action: promote them**, then delete the
   local definitions (5 files, mechanical).
3. **`module.capnp` (A) — imports `manifest.capnp.Semver`.** manifest.capnp
   replaced `Semver` with `T.Version` in every one of its own fields. The type
   is still exported, marked for deletion, *solely* for this importer; this
   batch did not edit module.capnp. **Action: migrate `ModuleDesc.version` and
   `RuntimeBinding.min/maxVersion` to `T.Version` (3 field types + 1 import),
   then delete `manifest.capnp.Semver`.**

**Type-name collisions (E12) — every remaining one in this batch has exactly
one side outside the batch.** The action in each case is the same: agree which
side is canonical, or rename the non-canonical side.

| type | this batch | other batch | action |
|---|---|---|---|
| `AccessibilityRole` | accessibility.capnp | console.capnp (B) | console's copy should import accessibility's |
| `AppIcon` | appindex.capnp | auth.capnp (E) | auth should import appindex's |
| `AudioState` | shell.capnp | audio.capnp (B) | shell's is the panel view; audio's is canonical |
| `BluetoothDevice`, `BluetoothState` | shell.capnp | bluetooth.capnp (B), network.capnp (C) | shell's should import bluetooth's |
| `CaptureResult` | compositor.capnp | capture.capnp (B) | agree one home |
| `ChangesSubscription` | clipboard.capnp | database.capnp (C), secret.capnp (E) | agree one home |
| `CursorPosition` | compositor.capnp | console.capnp (B) | agree one home |
| `CustomQuery` | compositor.capnp | buffer.capnp (C) | agree one home |
| `EventFilter` | compositor.capnp | calendar.capnp (E) | agree one home |
| `EventSubscription` | accessibility.capnp | usb.capnp (B) | agree one home |
| `ExportResult` | accessibility.capnp | vcard.capnp (E) | agree one home |
| `ExtensionInfo` | extension.capnp | system.capnp (A) | agree one home |
| `FocusEvent` | compositor.capnp | audio.capnp (B) | agree one home |
| `InstallOptions` | package.capnp | update.capnp | agree one home |
| `KeyAction` | compositor.capnp | input.capnp (B) | input's is the input-domain home; compositor and ime both reference compositor's — needs one decision |
| `LifecycleAction` | extension.capnp | files.capnp (C) | agree one home |
| `MergeStrategy` | manifest.capnp | contacts.capnp (E) | agree one home |
| `SearchResult` | shell.capnp | files.capnp (C), system_search.capnp (E) | shell's universal search should aggregate system_search providers (the audit's finding; deferred here) |
| `ServiceInfo` | compositor.capnp | service.capnp (A) | agree one home |
| `SpatialPose` | compositor.capnp | input.capnp (B), location.capnp (B) | agree one home |
| `StateChange` | accessibility.capnp | discovery.capnp (A) | agree one home |
| `TextStyle` | theme.capnp | console.capnp (B) | agree one home |
| `ThemeSubscription` | theme.capnp | console.capnp (B) | agree one home |
| `UpdateCheckResult` | package.capnp | update.capnp | agree one home |
| `Session` (6 schemas) | — | — | doctrine-sanctioned (DESIGN_PRINCIPLES:213); no action |

**Semantic decisions owed by other batches**

4. **`screenlock.capnp` (B) — the ServiceSession handshake.** compositor,
   windowmanager, ime and shell now share one handshake type
   (`compositor.SessionRequest`/`CapabilityRequest`). screenlock is the fifth
   session service and should adopt it. **Action: import
   `compositor.capnp.SessionRequest` and delete screenlock's local
   request/response trio.** If the foundation batch prefers to promote the
   handshake into `types.capnp`, that is a 5-file change here and one there.
5. **`app.capnp` crash-recovery policy (A).** Deleted here because it was a
   third restart policy beside init.capnp's and types.capnp's, which the
   verifier confirms already contradict each other (A12). **Action: the
   service-lifecycle owner should expose ONE `RestartPolicy`, and app-level
   policy should be a view over it.**
6. **`package.capnp` signing / `extension.capnp` signing (A).** Both deleted
   here in favour of signature.capnp + key_management. **Action: confirm
   signature.capnp is the intended home for package and extension signing.**
7. **`sandbox.capnp` (E) — extension isolation.** extension.capnp's sandbox
   config was deleted. **Action: confirm sandbox.capnp's scope covers
   per-extension isolation, or the extension service needs to reference it.**
8. **`queue.capnp` (C) — extension messaging.** extension.capnp's bus was
   deleted as a third messaging model. **Action: confirm queue.capnp is the
   intended host; if a bus is genuinely needed it should grow from queue's
   model.**
9. **`diagnostics.capnp` (A) — observability.** notification.capnp's delivery
   tracking and queue stats, compositor's health, and app's health surface were
   deleted here as "every schema's own analytics struct". **Action: confirm
   diagnostics.capnp is the intended home, so the next schema does not
   re-invent one.**
10. **`input.capnp` (B) — input modality alignment.** The founder asked that
    this be noted for integration: ime.capnp's `InputModality`, content type,
    purpose and keyboard type are now OPEN TOKENS with published conformance
    constants, and `ImeInputRequest.type` is an open token matching cli.capnp's
    `InteractivePrompt.inputType`. batch B is opening input.capnp's event union
    the same way. **Action: align the published token spellings for modality
    (`keyboard`, `voice`, `handwriting`, `gesture`, `neural`, `spatial`,
    `hybrid`) so the two files agree at integration.**
11. **`display.capnp` (B) — `Monitor` vs `OutputInfo`.** compositor.capnp is
    now the canonical home of `OutputInfo`/`OutputMode` (windowmanager imports
    it). display.capnp's `Monitor` overlaps. **Action: agree the boundary.**
12. **`naledzi` — `surface.capnp` still compiled by the wall-lockscreen
    workspace.** The delta verifier records that `wall-protocol` has a
    vendored, stale `gen/surface_capnp.rs` and a `build.rs` pointing at an
    absent directory. The canonical file is now deleted, so that workspace
    must repoint its 20 references at compositor's types before the merge
    lands, or it will keep compiling its own frozen world.

**Observed tree state (read-only, no action taken)**

13. `runtime_search.capnp` (E) has an interface-ordinal hole
    (`Skipped ordinal @17`) as of this run — an in-flight edit by that batch.
    It is the only file in the tree that does not compile besides my own
    batch's files, which all compile.

---

## 3. Verification results

### `python3 scripts/validate.py` (read-only) — verbatim

```
Schemas parsed: 90
E1 enums in ai.capnp            : 0
E2 bulk lists in ai.capnp       : 0
E4 interfaces unreachable (all) : 0 reported
E9 hits (all schemas)        : 13
E10 hits (all schemas)        : 82
E11 hits (all schemas)        : 10
E12 hits (all schemas)        : 110
E13 hits (all schemas)        : 21
E14 hits (all schemas)        : 15

--- REPORTED (not blocking, 1842) ---

PASSED — all enforced rules clean for schema/ai.capnp
```

Exit status `0`. (Schemas parsed fell from 92 to 90: `surface.capnp` and
`textinput.capnp` deleted; `gpu.capnp` was added by batch B and
`ipc-message.capnp` deleted by batch A.)

### Per-rule counts inside this batch

| rule | count | disposition |
|---|---|---|
| E4 unreachable interfaces | 0 | clean (`ShellService` reachable via `Session.interpreter @76`) |
| E5 stream terminators | 0 | clean |
| E6 unions without unknown/custom | 0 | was 16 |
| E7 open extension point | 240 | **documented noise** — see below |
| E8 enum @0 not a neutral sentinel | 33 | **documented per O4** — see below |
| E9 platform/vendor/POSIX nouns | 0 | was 2 (`CommandResult.stdout`/`stderr`) |
| E10 bulk payload outside `T.DataHandle` | 1 | documented retention |
| E11 authority-by-string / per-method token | 0 | was 2 |
| E12 type declared in two schemas | 26 | **all cross-batch** (§2) |
| E13 ordinal sequence/order | 0 | was 7 |
| E14 unreachable interface / unreferenced type | 0 | was 1 |

**E8 (33) — per the verifier's O4 ruling, the sentinel was applied to
filter/request/optional-field enums only and the rest is documented.** Applied:
`WindowState`, `TilingAlgorithm`, `GroupLayout`, `WorkspaceDirection`
(windowmanager), `AppLifecycle`, `AppMessageType` (app), `AppState` (appindex),
`IntentPriority`, `ConditionOp`, `BatchFailureMode` (intent), `UrgencyLevel`
(notification), `LifecycleEvent`, `LifecycleWhen` (extension), `ShellMode`,
`KeyBindingProfile` (shell), `TextGranularity` (accessibility), `BundleShape`,
`MergeStrategy` (manifest), `PlacementHint`, `SurfaceLayer`,
`LayerInteractivity` (compositor) — 21 enums gained a neutral `@0`. The
remaining 33 are read/event/result enums that are always written on the wire
and can never be absent (`KeyAction`, `FocusReason`, `PackageStatus`,
`UpdatePhase`, `AppSuspendReason`, …) or `List`-typed filters where an absent
list already means "all kinds". For `EnvironmentMode` the zero member was set
to `inherit` (an absent field must not silently *replace* the caller's
environment) and for `AvailabilityReason` the zero member is `available` (an
absent reason is the intended default); neither is in the validator's sentinel
word list, so both still report.

**E7 (240) — documented noise,** as the batch summary itself concluded (§4.4)
and O4's reasoning implies: the rule fires on `struct FontSize { points }` and
on `UnknownEvent` itself. The batch's 240 are closed record wrappers (`Match`,
`CategoryCount`, `SourceCount`, `CommandArg`, `OutputChunk`, `NameChange`) and
event payload structs. Cap'n Proto's unknown-field rule already means a reader
never breaks on a new field, which is what E7 appears to guard; where a struct
must genuinely carry vendor data it already has a `T.StringMap` or a `custom`
arm.

**E10 (1) — `compositor.CursorThemeInfo.sizes :List(UInt32)`.** A cursor
theme's available pixel sizes, typically 3–10 values. Retained deliberately
under the audit's own restraint precedent (B21: "bounded in-file values …
correctly *not* flagged as bulk"); converting it to a `T.DataHandle` would
cost a buffer round trip on a list that fits in one segment.

### `capnp compile` — all 16 batch files

```
$ ./scripts/check.sh compositor.capnp windowmanager.capnp ime.capnp \
    shell.capnp cli.capnp clipboard.capnp notification.capnp settings.capnp \
    theme.capnp accessibility.capnp app.capnp appindex.capnp package.capnp \
    extension.capnp intent.capnp manifest.capnp
OK   compositor.capnp        OK   notification.capnp       OK   package.capnp
OK   windowmanager.capnp     OK   settings.capnp           OK   extension.capnp
OK   ime.capnp               OK   theme.capnp              OK   intent.capnp
OK   shell.capnp             OK   accessibility.capnp      OK   manifest.capnp
OK   cli.capnp               OK   app.capnp                OK   appindex.capnp
OK   clipboard.capnp
```

16 of 16 OK. `scripts/check.sh` was added by this batch; it runs
`capnp compile -I schema --no-standard-import -o- <file>` per schema, which
type-checks without a code generator. The consumers of the types this batch
deleted were also checked: `init.capnp` and `module.capnp` (which import
`manifest.capnp`) both still compile.

### Gain and cost, per change class

| change | gain | cost |
|---|---|---|
| surface/textinput merges | two live forks end; one commit path, one fence type, one text-input contract; ~85 lines of duplicate accessibility model gone | compositor Session +10 methods, ime +11; the wall-lockscreen workspace must repoint (cross-batch) |
| parallel authority models deleted (app, clipboard, extension, intent, settings-per-app) | one authority path with attenuation, revocation and audit | callers must hold a capability reference instead of passing a string; per-item clipboard ACLs are no longer expressible |
| permission-string vocabularies → open tokens (role, capability kind, category, source, modality, content type, keyboard type, launch flags, intent category, priority, urgency filter) | a value invented in any later year is expressible with no schema edit | a consumer that wants a closed list publishes it from the conformance constants; string matching instead of enum matching |
| polling → subscriptions (cli jobs and prompts, intent activity results) | no poll loops, no CPU wake-ups, event-speed latency | callers loop instead of single-read |
| `unknown @N :T.UnknownEvent` normalization | a consumer can route an event kind it has never seen | the canonical type's payload is inline `Data` (see §2 item 1) |
| ordinals | — | Cap'n Proto requires sequential interface ordinals, so deleting a mid-interface method renumbers the ones after it. Pre-release with zero external consumers this is free; the affected renumbers are recorded in each file's header comment |

---

## 4. Founder-decision items

Four judgement calls where I went beyond, or declined part of, the audit.

1. **`AccessibilityRole` (70 values) kept.** The audit calls it "the defensible
   enum family" and its only prescription is "an explicit open token alongside".
   I declined the alongside-token: a parallel open spelling beside a 70-value
   enum is two naming systems for one concept — the exact defect this batch
   removes from theme, appindex, ime and compositor. Cross-platform AT interop
   is the one place a shared role vocabulary is genuinely the contract, and
   `custom @69` exists. If a 2046 GUI concept needs dispatch, the honest change
   is `T.AccessNodeId`-keyed `attributes`, not a second role field.
2. **`CapabilityRequest.standard` opened to a `Text` token.** The founder asked
   that the wm/shell/ime handshakes be opened "the way compositor's
   `CapabilityRequest` already does" — i.e. adopt the union. I applied that
   *and* made the `standard` arm an open token, because a per-service closed
   capability enum (`WindowManagerCapability` at 27 values including
   `automotiveMode`, `foldableAware`, `voiceOnlyMode`) is the same R1 defect
   the ruling targets, and adopting the union alone would have left three
   rival enums in the batch. Cost: a consumer that wants a closed list reads it
   from the published conformance constants.
3. **`Session`'s method set and ordinals preserved (shell), types changed.**
   The founder's two instructions for shell.capnp are in tension: "keep
   `Session` byte-compatible with official" and "delegate shell methods that
   duplicate notification/clipboard/settings". I resolved it by keeping all 67
   methods at their ordinals and changing only whose *types* the façades carry.
   The wire format of those façades changes (a `List(Notification)` becomes a
   `List(Notification.NotificationData)`); the method set does not. The stricter
   reading — deleting the ~30 duplicated façade methods, as the audit's action 1
   proposed — was rejected as breaking the byte-compatible instruction, and is
   recorded as deferred work.
4. **`Semver` retained in manifest.capnp, marked for deletion.** `module.capnp`
   (another batch) imports it. Editing another batch's file to remove the last
   importer was out of scope, so the type stays with a prominent
   compatibility note and a one-line removal instruction in §2 item 3.
5. **compositor.capnp is the batch's shared-vocabulary home.** The handshake
   types live there and windowmanager, ime, cli and accessibility import them.
   This is a dependency-direction compromise forced by ownership (types.capnp is
   not mine); the alternative was a private copy per file, which is the failure
   mode this batch exists to remove. If the foundation batch prefers, the
   handshake and the event envelope both belong in `types.capnp` — a 5-file
   change here.

Declined from the audits, with reasons:

- **appindex `SettingValue.list` and `SettingMap` both kept** (settings audit
  action 6). `SettingMap` is the wire type for multi-entry reads and writes;
  `list`/`dict` are the recursive value forms. Removing either removes a shape,
  and the "half the union's surface" gain does not materialise.
- **compositor health, state snapshot, remote access, resource limits deleted**
  on the batch summary's own "name a consumer or cut" rule. Each had zero
  consumers and no protocol-level consumer path. Recorded here because they are
  capability-adjacent: a compositor's own state persistence, if a requirement
  ever arrives, is cheap to re-add (the ordinals are documented above).
- **`appindex.AppInfo` keeps a resolved `icon`** even though the manifest
  carries asset paths, because a launcher must render one frame without
  resolving a bundle.
- **notification `getAnalytics`, intent `getMetrics`, extension
  `getTelemetry` kept** (not flagged as doctrine violations); §2 item 9 asks
  the diagnostics owner to become the single home.

---

## 5. Deferred work

Not done here; each names the requirement that would justify it.

1. **Shell panel-state delegation** (shell audit action 1). `getAudioState`,
   `setAudioVolume`, `setAudioMute`, `getNetworkState`, `getBluetoothState`,
   `getBluetoothEnabled`, `getBrightness`, `setBrightness`, `getNightLight`,
   `setNightLight` and their local structs remain, deliberately: they are the
   panel's one-frame aggregate view and the owning services (audio, network,
   bluetooth, display) belong to other batches. Doing it means importing three
   schemas this batch does not own.
2. **Shell universal search** (shell audit). `SearchResult` is a fourth result
   type beside files.capnp's and system_search.capnp's. The audit's fix —
   aggregate the canonical search providers — is cross-batch.
3. **`ServiceInfo` vs `service.capnp`'s `ServiceInfo`** and the rest of the
   E12 table in §2.
4. **`T.UnknownEvent.payload` type** (§2 item 1) — the only place R2 is
   knowingly violated in this batch, and the lever is in another batch's file.
5. **Local opaque id promotion** (§2 item 2): `WindowGroupId`, `SnapZoneId`,
   `IntentChainId`, `IntentTraceId`, `IntentHistoryId`.
6. **`manifest.Semver` removal** (§2 item 3).
7. **Clipboard multi-selection.** Single-selection is documented as a
   deliberate limit; the open selection-name parameter is the fix when a device
   with two concurrent selections exists.
8. **Settings value model unification.** `SettingValue.list` vs `SettingMap`
   (declined — see §4).
9. **`TimeRangeCondition`/`ScheduleEntry` time-of-day.** Both are `Text`
   "HH:MM" with the format now stated in the schema. A `T.TimeOfDay` promotion
   would let a backend stop parsing.
10. **`manifest.ManifestChange.oldValue/newValue :Text`.** A diff renders
    field values as text for display because a typed union could not hold a
    `List(Dependency)` without becoming a second model of the whole struct.
11. **App crash-recovery policy** (deleted here; §2 item 5 asks the
    service-lifecycle owner to expose one `RestartPolicy`).
12. **`E7` and the remaining `E8` enums.** Documented above; the rule changes
    that would make them meaningful are validator changes, not schema changes.
13. **Space-session and A11y preference ownership.** theme.capnp reports the
    active theme; accessibility.capnp owns preferences. A future `Session`
    that wants both should read both rather than a merged type.

---

*All changes were made against the canonical tree at
`/home/lufuno/smart/smart-protocol-official/`. No other batch's schema, no
naledzi file, and no repository outside this one was modified. `scripts/check.sh`
was added as a compile-check helper; `scripts/validate.py` was run read-only.*

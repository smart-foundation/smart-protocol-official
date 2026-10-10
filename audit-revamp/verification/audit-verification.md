# Audit Verification — smart-protocol canonical tree (92 schemas)

Verifier pass over the five batch audits in `audit-revamp/{a,b,c,d,e}`. Method: read all five
BATCH-SUMMARYs and 87 per-schema reports; independently re-ran mechanical scans over
`schema/` (undefined `T.*`, per-struct/enum/interface ordinal collisions, cross-file duplicate
type names, zero-reference interfaces, inline `List(...)` payloads, unions without
`unknown`/`custom`, per-method `Capability` parameters, `UInt32`/`Text`-typed IDs, schema-ID
uniqueness); ran the repo's own `scripts/validate.py` read-only (E6=65, E7=2243, E8=793
repo-wide); opened every cited `schema/<file>:<line>` for the top findings and every
REWRITE/DELETE/MERGE verdict.

Verdict key: **CONFIRMED** (citation and claim both hold) · **REFUTED** (claim false or citation
points elsewhere) · **MISLEADING** (present but materially mischaracterized) · **OVERREACH**
(fails the founder's standard; detailed in §3).

---

## 1. Verification table

### Batch A — foundation & kernel (19 schemas)

| # | Finding (audit) | Verdict | Evidence |
|---|---|---|---|
| A1 | `ipc-mapdelete` — DELETE `ipc-message.capnp`, 9-line dead duplicate of `logging.capnp:98`, zero references | CONFIRMED | File is 9 lines (`struct LogParams`); `grep -rn ipc-message schema/*.capnp` = 0 external refs. Citation nit: the duplicated contract is `Logging.log @26 (severity, domain, message)` at `logging.capnp:97`, not `:98` |
| A2 | `BootCapability` verbatim duplicate, two type IDs (`abi.capnp:259` ↔ `boot.capnp:647`) | CONFIRMED | Both enums byte-identical: `readMemory@0 … networkAccess@8, custom@9` in both files |
| A3 | Doctrine release-blocker unexecuted: `LogFormat`/`LogOutput`/`LogSource` live at `logging.capnp:156/165/130` | CONFIRMED | All three present; `DESIGN_PRINCIPLES.md:565` orders their removal since v1.0 list |
| A4 | `system.capnp` 47-bool capability bitmap already stale (no ai/tunnel/sandbox) | CONFIRMED | `struct Capabilities` fields @0–@46 (`logging @46` last); no `ai`, `tunnel`, `sandbox`, `nfc` bit |
| A5 | `kernel.capnp:51` `TaskState` POSIX vocabulary | CONFIRMED | `newBorn/ready/running/waiting/suspended…`; `DESIGN_PRINCIPLES.md:451` itself contains the contradictory "maps to seL4" claim |
| A6 | Kernel exposes introspection despite its own exclusion header (`kernel.capnp:12-14` vs `:167`) | CONFIRMED | `introspect @29` exists at `:167`; `KernelIntrospectionRequest` at `:496` |
| A7 | `ForkFlag` CLONE_* semantics (`kernel.capnp:203-210`) | CONFIRMED | Enum comment literally says "replaces Linux CLONE_* string lists"; `fork @1` at `:114` |
| A8 | HAL kernel-internals block (`hal.capnp:280-319`) | CONFIRMED | `createAddressSpace @44…switchAddressSpace @48`, `getX86PortIo @60` |
| A9 | `process.capnp:43-44` readMemory/writeMemory inline `Data` copies | CONFIRMED | `readMemory @12 … -> (data :Data)` at `:43`; `writeMemory @13` at `:44` |
| A10 | `queue.capnp` "impossible `exactlyOnce` promise" | CONFIRMED (existence) | `exactlyOnce @2` in `DeliveryMode` at `:208`. "Impossible" is judgment, not fact; the fix (drop to atLeastOnce + documented semantics) is a legitimate trim |
| A11 | Diagnostics 22/19/14-value taxonomies + grpc carrier | CONFIRMED exactly | `DiagnosticScope` 22, `ProfileTarget` 19, `MetricCategory` 14 values; `grpcMetadata @1` at `diagnostics.capnp:718` |
| A12 | Two contradictory `RestartPolicy` (`init.capnp:66` vs `types.capnp:1954`) | CONFIRMED | Cross-file duplicate scan lists the pair; both used in-file per audit |
| A13 | Discovery carries HTTP status codes in a "zero-assumption" file | CONFIRMED | `discovery.capnp:324` "HTTP status codes that trigger retry" |
| A14 | `service.capnp` Audit-9 half is a cloud orchestrator | CONFIRMED | `deploySidecar @26`/`removeSidecar @27` at `:106-110` |
| A15 | task_scheduler ML prediction machinery | CONFIRMED | `predictTaskDuration @38`, `trainPredictionModel @40` at `:276-278` |
| A16 | Three signal-delivery authorities | CONFIRMED | `kernel.capnp:117` `signal @4`, `process.capnp:27` `kill @3`, `signal.capnp:244` `send @0` — three permission checks, three result types |
| A17 | Four parallel permission models | CONFIRMED | `BootCapability` ×2, `ProcessCapability` (process:305), klog role strings (`:441-444`), `SessionAccessControl` (`session.capnp:354-360` allowedUsers/deniedUsers) |
| A18 | `SubscriptionResult`/`SubscriptionData` dead in types.capnp | CONFIRMED | Zero references outside `types.capnp:907/916` |
| A19 | abi speculative registry apparatus | CONFIRMED | `AbiRegistryService` at `abi.capnp:439`, returned by nothing |
| A20 | Raw-id subscriptions, five files | CONFIRMED | `system.capnp:22-23,36`; `diagnostics.capnp:91,96` (`MetricsSubscription.pull @0 (subscriptionId :UInt64)`); `queue.capnp:119-121` is the same defect on a *transaction* id (`commitTransaction @46 (transactionId :UInt64)`) — the interface is discarded for a raw id. "Subscription" label is slightly off for queue; defect class holds |
| A21 | Batch hygiene: zero undefined `T.*`, zero ordinal collisions | CONFIRMED | Independent scans reproduce both zeros. Only comment-level mentions of `T.Animation` (`types.capnp:1234`) and `T.Vec2f` (`surface.capnp:27`, historical note) exist |
| A22 | "23 duplicate pairs" within batch | CONFIRMED (sampled) | Full-tree scan finds 214 cross-file duplicate names; all A-cited pairs exist (BootCapability, RecoveryAction, RestartPolicy, TaskState, TaskFilter, ResourceUsage, DeviceResource, Constraints, LogEntry/LogFilter, TraceSpan/TraceContext, SpanKind/SpanStatus, ExportFormat, HealthStatus, ServiceCost/Sla/Dependency, ServiceState, ServiceEndpoint) |
| A23 | "TIMELESSNESS.md:451 claims TaskState maps to seL4" | REFUTED (citation) | TIMELESSNESS.md has 221 lines. The contradictory claim is at `DESIGN_PRINCIPLES.md:451` (+ `:178`). Substance of the doctrine-contradiction finding survives |
| A24 | "DESIGN_PRINCIPLES.md:502 calls boot.capnp exemplary" | MISLEADING (off-by-one) | The exemplary row is at `:503`; `:502` is the capability row. Substance (boot contradicts its own rating) is evidence-backed: boot carries 24 enums naming hardware (`BootloaderKind {grub, limine…}` `:470`, `TpmVersion` `:436`, `StorageBus {nvme, ahci…}` `:258`) |

### Batch B — devices & media (19 schemas)

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| B1 | `audio.capnp:892` `submit (frames :Data)` on the driver boundary | CONFIRMED | `AudioDriverStream.submit @0 (frames :Data)` at `:892` |
| B2 | bluetooth address-type schism | CONFIRMED | `BluetoothDevice.address @0 :Text` at `:63`; every consumer method takes `address :T.DeviceAddress` (`getDevice @7`…`subscribeGatt @28`, `:510-552`). A scan result literally cannot be passed to any method |
| B3 | bluetooth ordinal collision does **not** exist (audit's disproof) | CONFIRMED | `name @1 :Text` at `:310`, `deviceAddress @2 :T.DeviceAddress` at `:312` — no collision |
| B4 | screenlock `UnlockCredential` conflict already resolved (audit's disproof) | CONFIRMED | Single definition at `screenlock.capnp:140`; `session.capnp:37` imports it (`using Screenlock`, `Screenlock.UnlockCredential`) |
| B5 | "`T.BluetoothAddress` (types.capnp:768) — dead: no schema uses it" | **REFUTED** | Used at `network.capnp:62,63,152,224,412,716,732` and `shell.capnp:457`. Batch C's own network audit cites those uses and calls them semantically wrong — see §4, contradiction X1 |
| B6 | Eight unions missing `unknown`/`custom` (framebuffer, capture, camera, media, module, usb, console) | MISLEADING (4 of 8 mischaracterized) | Real: `framebuffer.capnp:357`, `media.capnp:140`, `module.capnp:224` (+ `Source` `:127`). Wrong mechanism: `capture.capnp:160 CaptureEvent`, `camera.capnp:235 CameraEvent`, `usb.capnp:453 UsbEvent` are not unions at all — they are structs with `type @3 :XEventType` **enums**, a different and larger defect (closed event taxonomy). `console.capnp:714` already has `custom @5 :Void`. Validator E6 agrees with me, not the audit, on all four |
| B7 | camera/capture have no frame-delivery contract; `stopRecording` returns a whole recording | CONFIRMED | `camera.capnp:38` `stopRecording → (data :T.DataHandle)`; no stream-returning method exists; capture's `startStream` returns an id with no reader |
| B8 | Pagination (`T.Pagination {offset,limit}`) applied to live streams, 5 sites | CONFIRMED | `sensor.capnp:238,242`, `capture.capnp:107`, `usb.capnp:449`, `camera.capnp:99`, `capability.capnp:401` all pass `T.Pagination` to a subscription pull. Offset on an unsorted live queue is meaningless |
| B9 | `SensorType` (44 values) closed by release schedules | CONFIRMED | Enum spans `:24-70`, 44 members |
| B10 | `T.KeyCode.code :UInt32` has no published domain | CONFIRMED | `types.capnp:928-930` — comment asserts "cross-platform semantic key code" with zero published value space; used by `emulateKey @27` (input:59) and `KeyTrigger.key @0` (input:315) |
| B11 | Doctrine stale on audio (claims `Text` id; schema already typed) | CONFIRMED | `audio.capnp:235` is `id @0 :T.AudioDeviceId`; `DESIGN_PRINCIPLES.md:165,464,530` still describe Text |
| B12 | input.capnp has no key/pointer/touch event path at all | CONFIRMED | `InputEvent` union (`input.capnp:692-700`) contains only eyeTracking/brainInput/spatialInput/digitalCrown/cabinAttention/custom. `DESIGN_PRINCIPLES.md:454`'s "compositor defines… input events ✅" is false |
| B13 | `ThermalState` verbatim duplicate (`power.capnp:171` ≡ `device.capnp:368`) | CONFIRMED | Same 5 values (normal/warm/hot/critical/custom) in both |
| B14 | console.capnp hard-codes Linux tty architecture (`:618-642`) | CONFIRMED | `TtyClass {virtualConsole ("vc0..vcN"), serialConsole, remoteConsole ("SSH, IPMI")}`; session labels documented `"vc0", "ttyS0", "kmsg"` |
| B15 | nfc REWRITE (payments/loyalty/transit/EV/identity/Wi-Fi/crypto; ungated payment; plaintext Wi-Fi password) | CONFIRMED, cite imprecise | `WifiCredentials.password @1 :Text` at `:447`; `startPayment @25`/`getPaymentSession @26` are at `:509-510` — the summary's "nfc.capnp:25-26" writes method ordinals as line numbers; action-8's block range `:184-460` excludes the payment methods it also condemns |
| B16 | `console.capnp:651` `permissions :UInt32` with no bit assignment | CONFIRMED | `ConsolePermission` enum lists members with no bit map |
| B17 | `module.capnp:121` `capabilities :List(Text)` + `ModuleLifecycleHook.command` | CONFIRMED | Both present; two authority-by-string paths |
| B18 | `sensor.capnp:104` `permissionCapability :Text` dead end | CONFIRMED | Field at `:104`; no method accepts a `Capability` in the file |
| B19 | `AudioTransport` names vendor backends (`audio.capnp:768-771`) | CONFIRMED | `pulseAudio @8, alsa @9, jack @10, pipewire @11` |
| B20 | Gamepad fleet-wide pull copy cost | CONFIRMED (caveat) | `GamepadSubscription.pull @0 → (states :List(GamepadState))` (input:127) ships the whole fleet; per-device bytes (~130 B) are trivial, fleet scaling is the real cost — the audit's per-device arithmetic overstates, its conclusion stands |
| B21 | "Honest note on what NOT to do" (rejected conversions) | CONFIRMED as correct restraint | Bounded in-file GATT values, small channel-float lists, and 12-byte sensor readings are correctly *not* flagged as bulk — consistent with the founder's standard |
| B22 | Provider trio unreachable (AudioProvider/DisplayProvider/UsbHostProvider) | CONFIRMED | Independent scan: zero type references anywhere |
| B23 | "DriverRegistry/DriverLifecycle in device.capnp:492-557 is **reachable** but never returns a provider" | MISLEADING | Nothing returns those interfaces either — zero references outside the file; the only external mention is a comment at `display.capnp:852`. They are unreachable like the rest; "reachable" is wrong |

### Batch C — network & storage (19 schemas)

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| C1 | files↔filesystem canonical direction is backwards in the schemas | CONFIRMED | `filesystem.capnp:10` claims "Canonical source for SpecialPathType"; `files.capnp:28` imports it (`using FS`), `getSpecialPath @13` takes `FS.SpecialPathType` (defined at `filesystem.capnp:184`) — the canonical type lives in the file `DESIGN_PRINCIPLES.md:212` and `SCHEMAS.md:167` order deleted. C's resolution (move into files, delete filesystem) matches the doctrine |
| C2 | TAI epoch wire-breaker | CONFIRMED | `time.capnp:219 TAITimestamp.seconds` "since 1958-01-01" vs `timezone.capnp:399 TaiTimestamp.taiSeconds` "since 1970-01-01 TAI" — one-letter-case-different names, 12-year epoch gap, compile-clean cross-use |
| C3 | dns `resolve`/`srvLookup` have no error path | CONFIRMED | `dns.capnp:158 ResolveResult` is a plain struct (canonicalName/records/source/ttl/truncated/negativeCache) with no `T.Error`; SERVFAIL is unrepresentable |
| C4 | `ResolveResult` same-name-different-shape (`dns:158` vs `endpoint:763`) | CONFIRMED | endpoint's is a `success|error` union; dns's is a bare struct |
| C5 | network.capnp 18 enums / mount `FilesystemType` 45 values unused | CONFIRMED | 18 `^enum` in network; `FilesystemType` has exactly 1 occurrence (its declaration); live spelling is `fsType :Text` (mount:43,138,282,295) |
| C6 | Archive streaming API copies every chunk | CONFIRMED | `CompressStream.write @0 (data :Data)` `:93`, `DecompressStream.read @0 → (data :Data)` `:102` |
| C7 | database inline `List(Float32)` vectors | CONFIRMED | `database.capnp:613,619,628` |
| C8 | `files.capnp:35/:63` write path still inline `Data` | CONFIRMED | `writeFile @3 (… data :Data)` `:35`; `createFile @19 (… content :Data)` `:63` — while `readFile @2` was already converted to `T.DataHandle` |
| C9 | storage header contradicts its own PoolType | CONFIRMED | Header `:8-9` "no LVM, no mdadm, no ZFS…" vs `PoolType {lvm, mdraid, zfs, btrfs, storagespaces, stratis…}` |
| C10 | `clock.capnp:117 checkTimer` polling beside a subscription | CONFIRMED | `checkTimer @6 (timer) -> (fired :Bool)` |
| C11 | Unperformed types.capnp promotions (EndpointId/MountId/FilesystemId/StoragePoolId/VolumeId/SnapshotId) | CONFIRMED | Locals still defined (`endpoint:75`, `mount:127`, `storage:337,436,498`) beside the promoted `types.capnp:1086-1167` |
| C12 | `buffer.capnp:14` cites a deprecated `Buffer` interface that does not exist | CONFIRMED | Comment present; interface scan finds only `BufferService` (`:26`) |
| C13 | No duplicate schema IDs across 92 files | CONFIRMED | All 92 `@0x…` unique |
| C14 | Validator counts E6×17 / E7×~460 / E8×~176 in batch | CONFIRMED | Live run: E6 hits in batch = buffer 8, archive 2, storage 2, dns 1, endpoint 1, web 1, clock 1, timezone 1 = 17 exactly |
| C15 | `TlsVersion` ×2 "incompatible" | CONFIRMED (scope note) | `endpoint.capnp:670` vs `types.capnp:1564`; *plus* `socket.capnp TlsSession` and nothing in web — three homes for TLS, which C's own per-file audits correctly state |

### Batch D — ui & apps (18 schemas)

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| D1 | DELETE `surface.capnp` into compositor; DELETE `textinput.capnp` into ime (doctrine-declared) | CONFIRMED | `DESIGN_PRINCIPLES.md:211,214` order both; `SCHEMAS.md` Deprecated section confirms; both files alive with zero importers |
| D2 | clipboard hot path inline `Data` while defining `T.DataHandle` type unused | CONFIRMED | `getContent @0 (mimeType) -> (data :Data)` / `setContent @1 (… data :Data)` (`:21/24`; audit cites the comment lines 20/23) |
| D3 | `AppIcon.data :Data` inline in app + appindex | CONFIRMED | `app.capnp:177`, `appindex.capnp:271`; four sibling files already use `T.DataHandle` |
| D4 | Android Intent vocabulary leaked | CONFIRMED | `intent.capnp:82-98 LaunchFlags` (FLAG_ACTIVITY_*: newTask/singleTop/clearTop/grantReadUriPermission…), `firstUser` `:200`, `AppLaunchMode` `:224` |
| D5 | `OciCredentials.password :Text` | CONFIRMED | `package.capnp:453` (registry/username/password triple) |
| D6 | SCHEMAS.md names a dozen types that do not exist | CONFIRMED | Verified nonexistent: ClipboardService, NotificationService, SettingsService, ThemeService, PackageService, ExtensionService, AppEntry, Command, CompositorSession, ImeSession, InputMethod, Layer; `AppInfo` exists but in `appindex.capnp:241`, not app.capnp as `SCHEMAS.md:125` claims |
| D7 | "Session interface only" claims false; flat `Compositor`/`WindowManager` alive | CONFIRMED | `Compositor` `:187`, `WindowManager` `:214`; SCHEMAS.md:68-69 and :57 claim otherwise |
| D8 | `Window.pid @15 :UInt32` remains at `windowmanager.capnp:316` | CONFIRMED | Also `WindowFilter.processId @6 :UInt32` `:362` |
| D9 | Accessibility tree forked 70/39/third-model | CONFIRMED exactly | accessibility 70 roles, compositor 39 roles (counted), shell `ShellAccessibilityTree` `:1026-1037` |
| D10 | E6 ×16 in batch | CONFIRMED | Validator run: appindex 1, compositor 8, ime 1, intent 1, manifest 1, package 1, windowmanager 3 = 16 |
| D11 | `notification.capnp:30 show` swallows failure | CONFIRMED | `show @0 (…) -> (id :T.NotificationId)` — no error variant |
| D12 | `settings.capnp:28 get` cannot say "not found" | CONFIRMED | `get @0 (domain, key) -> (value :SettingValue)` |
| D13 | E8 neutral-sentinel counts | CONFIRMED | Validator E8 repo-wide 793; D's per-batch ~160 consistent with file breakdown |
| D14 | "The Session handshake exists in **five** incompatible shapes" | MISLEADING | Seven files carry the trio: compositor, shell, windowmanager, ime, screenlock **plus `buffer.capnp:29-47` (the oldest instance) and `font.capnp:53-70`**. Batch B's font audit independently found the font/screenlock pair; D never reconciled the count |
| D15 | cli REWRITE premise — "the brief for this file is exact: … a CLI generated FROM the schemas (introspection-driven)" | UNVERIFIABLE | No repository document states this requirement. `SCHEMAS.md:147` describes the file as "Command execution, shell access, custom commands". The brief appears only inside the audit itself — see §3, O3 |

### Batch E — security & intelligence (17 schemas)

| # | Finding | Verdict | Evidence |
|---|---|---|---|
| E1 | crypto.capnp closed algorithm enums | CONFIRMED (count corrected) | 10 enums / 135 values by scan (audit says "eight enums, ~130 values"); FIPS-203/204/205 additions at `:521,591-604` evidence the amendment loop |
| E2 | signature↔crypto ordinal divergence (`ed25519@0` vs `@12`; `sha256@0` vs `@1`) | CONFIRMED, example value off | `signature.capnp:98` ed25519@0 ✓, `crypto.capnp:628` ed25519@12 ✓; `crypto.capnp:264` sha256@1 ✓, `signature.capnp:114` sha256@0 ✓. The illustrative "`5` = mlDsa44 vs ecdsaSha256" is wrong on the crypto side (`@5` is `rsaPssSha512`) — the divergence itself is real |
| E3 | `KeyId` identity split is the batch's only already-broken item | CONFIRMED | `key_management.capnp:27` local `KeyId {id @0 :UInt64}` vs `types.capnp:1041` promoted; `content.capnp:261 encryptContent(keyId :T.KeyId)` cannot accept key_management's output |
| E4 | `auth.capnp:40` `refreshToken` by enumerable id, no proof of possession | CONFIRMED | `refreshToken @7 (tokenId :T.AuthTokenId) -> (…)` at `:40` |
| E5 | `secret.capnp` entire interface ungated | CONFIRMED | Zero occurrences of `authority`/`Capability` in the file; `getSecret @1` returns raw `Data` |
| E6 | sandbox header/body contradiction | CONFIRMED | Header `:8-10` "no seccomp, no landlock, no namespace" vs `FilterAction {deny, errno, killThread, trap, trace}` `:188-198`, `ArgFilter {argIndex, operator, value, mask}` `:169-174`, `MountRule {nosuid, nodev, noexec}` `:226-232`, `ResourceLimits` = the RLIMIT_* set `:288-298` |
| E7 | system_search resultId type break | CONFIRMED | `SearchResult.resultId @12 :Text` `:181` vs `executeResult @7 (resultId :T.SearchProviderId)` `:46`; also `getResultPreview @19`, `SearchHandler.execute @1`, `explainResults @11 (List(Text))`, `deduplicateResults` `List(Text)` |
| E8 | Six files contain no union at all | CONFIRMED | speech/translation/calendar/system_search/secret = 0 unions; contacts = 0 (only a comment at `:388`) |
| E9 | runtime_search `RuntimeKind` platform freeze against its own header | CONFIRMED | `:203-220` unixDaemon/windowsService/jsRuntime/pythonRuntime/luaRuntime vs header `:11-13` "Backend-agnostic… any other mechanism" |
| E10 | runtime_search local `Capability` name collision | CONFIRMED | `runtime_search.capnp:238` vs `capability.capnp:22`, different shapes |
| E11 | ai.capnp local defects (ToolOutcome struct-not-union, unbounded handshake, AISubscription without maxBytes) | CONFIRMED | `ToolOutcome {success @1 :Bool, error @3 :T.Error}` `:344-350`; `handshake @0 → List(ModelDescriptor)` `:573-575`; `AISubscription.pull @0 ()` `:553` vs `ArtifactStream.pull (maxBytes)` `:277` — genuine internal inconsistency |
| E12 | `content.capnp:262 decryptContent` returns nothing | CONFIRMED | `decryptContent @28 (contentId) -> T.VoidResult` — decrypts with no way to read the plaintext |
| E13 | `contacts.capnp:101 shareContact` ungated PII share | CONFIRMED | `shareContact @22 (contactId, targetUserId :T.UserId) -> T.VoidResult` |
| E14 | `LockoutKind` byte-identical duplicate auth↔biometric | CONFIRMED | Cross-file duplicate scan lists the pair |
| E15 | vcard `getSupportedVersions` returns a standard that does not exist | CONFIRMED | `v50 @4` at `:95`; vCard 4.0 (RFC 6351) is the latest published version |
| E16 | "runtime_search duplicates system_search's `VectorQuery`/similarity vocabulary" | **REFUTED** | runtime_search.capnp contains no `VectorQuery` and no `SimilarityMetric` (grep: zero). The claimed conceptual duplication does not exist |
| E17 | "`speech.capnp:12` says SearchAction.id uses T.EventId" | MISLEADING | The stale comment is at `system_search.capnp:12`; `speech.capnp:12` is about VoiceGender. E's own system_search audit (`:35`) cites it correctly — the summary contradicts its own per-file report |
| E18 | Action 6 "**Result-side** payloads to T.DataHandle … `signature.capnp:131,152,156,168,176`" | MISLEADING | Those five signature lines are the verify methods' **request-side** `payload :Data` parameters, not results. The crypto cites (`:47,258,429,536,552,690,737`) are genuinely result-side. "Restores symmetry" is inverted for signature |

### Doctrine-contradiction escalations (all batches)

| Claim | Verdict | Evidence |
|---|---|---|
| A: DESIGN_PRINCIPLES rates boot/kernel exemplary while their bodies violate the ratings | CONFIRMED (override with evidence) | 24 hardware enums in boot; `introspect @29` + `ForkFlag` in kernel. Ratings at `:503/504` are stale |
| E: DESIGN_PRINCIPLES:540/544 rate auth/secret "Clean contract" while containing the batch's worst defects | CONFIRMED (override with evidence) | refreshToken-by-id; zero gating in secret |
| B: DESIGN_PRINCIPLES:452-454/480-482 Swap-Test "✅" marks are false for audio and input | CONFIRMED | `AudioTransport` vendors + unreachable stream path; no key/pointer event contract |
| B/D: TIMELESSNESS:98 `unknown @N` is MUST but unenforced; DESIGN_PRINCIPLES:342's weaker "unknown **or** custom" lets `custom :Void` pass | CONFIRMED | 65 E6 hits repo-wide; `console.capnp:714 custom @5 :Void` |
| B: DESIGN_PRINCIPLES:340 "deprecate, don't delete" costs more than it buys pre-release | CONFIRMED (as reasoning) | Zero external consumers; dead variants persist in screenlock/display/driver-state/input filters |
| D: SCHEMAS.md describes a tree that does not exist | CONFIRMED | See D6/D7 |
| C: types.capnp promotion comments are "documentation, not history" | CONFIRMED | See C11 |
| A: doctrine self-contradiction on TaskState (`:451` vs `:178`) | CONFIRMED with citation fix | See A23 |

---

## 2. Missed by the audits

Findings from my independent scans that **no** audit reports. (Batch-scoped scans each found their own slice; the gaps below are tree-wide.)

### 2.1 Duplicate type names across schemas — 23 collisions no audit mentions
Full-tree scan: **214 names defined in more than one file**. The five batch summaries report their own subsets (A: 23 pairs; B/C/D/E tables) but never reconcile; the following 23 appear in no audit at all:

| Type | Locations | Divergence |
|---|---|---|
| `VerifyRequest` | capability.capnp:283 ↔ crypto.capnp:668 | capability verification vs signature verification — unrelated domains, same name |
| `NegotiationResult` | audio.capnp:705 ↔ capability.capnp:340 | both unions; different members (AudioFormat vs List(Capability)) |
| `WakeWordSubscription` | shell.capnp:780 ↔ speech.capnp:510 | same interface name, different pull signatures (`Bool,Float32` vs event,done) |
| `CapabilityChange` | runtime_search.capnp:384 ↔ system.capnp:106 | list-diff vs name/oldValue/newValue |
| `CursorPosition` | compositor.capnp:497 ↔ console.capnp:125 | pixel x/y+shape vs column/row |
| `ChainState` | intent.capnp:321 ↔ task_scheduler.capnp:390 | enums sharing @0/@1, diverging at @2 (paused vs completed) |
| `DependencyGraph` | discovery.capnp:505 ↔ package.capnp:242 | service graph vs package graph |
| `QueueStats` | notification.capnp:372 ↔ queue.capnp:190 | disjoint fields |
| `ExtensionInfo` | extension.capnp:108 ↔ system.capnp:97 | same id type, divergent at @2+ |
| `GestureSubscription` | compositor.capnp:309 ↔ input.capnp:130 | not inspected by either owning batch |
| `FocusEvent` | audio.capnp:369 ↔ compositor.capnp:1132 | cross-batch (B↔D) |
| `AudioState` | audio.capnp:216 ↔ shell.capnp:402 | cross-batch |
| `MergeStrategy` | contacts.capnp:439 ↔ manifest.capnp:291 | cross-batch (E↔D) |
| `StateChange` | accessibility.capnp:272 ↔ discovery.capnp:573 | cross-batch |
| `StylusTool` | compositor.capnp:1102 ↔ input.capnp:264 | cross-batch |
| `SurfaceInfo` | compositor.capnp:787 ↔ surface.capnp:217 | — |
| `TextPurpose` | ime.capnp:146 ↔ textinput.capnp:119 | drifted twins |
| `VersionConstraint` | discovery.capnp:466 ↔ runtime_search.capnp:136 | cross-batch (A↔E) |
| `AppFilter` | app.capnp:397 ↔ appindex.capnp:223 | — |
| `AccessibilityAction` / `AccessibilityState` | accessibility ↔ compositor | part of the accessibility fork D3 found; the type-level collisions were not listed |
| `EventFilter` | calendar.capnp:365 ↔ compositor.capnp:840 | cross-batch |
| `FocusChangedEvent` | accessibility.capnp:316 ↔ windowmanager.capnp:748 | — |

Also unreconciled aggregate counts: `HealthStatus` is defined in **six** files (audio:1212, diagnostics:102, discovery:146, endpoint:171, filesystem:204, tunnel:291); A found 2 and C found 3 — neither found all six. `UnknownEvent` exists in both `ai.capnp:533` and `compositor.capnp:918` with no canonical home in types.capnp, despite A's action "promote canonical UnknownEvent" assuming one.

### 2.2 Unreachable interfaces no audit flags
Zero-reference scan over 305 interfaces (batch-level claims verified: AudioProvider/DisplayProvider/UsbHostProvider, telephony's seven, ConsoleRecording, ServiceSupervisor/RuntimeRegistry, WasmExtensionHost, kernel's six — all confirmed). Not flagged by anyone:

- **`font.capnp:51 interface FontSession`** — the entire session contract is unreachable; the flat `Font` (`:195-204`) returns no session, and nothing else does. B's font audit recommends "deprecate `Font` in favour of `FontSession`" without noticing no client can ever obtain a `FontSession`. The recommended migration target is uncallable.
- **`console.capnp:672 interface ConsoleMultiplexer`** — hands out sessions and arbitrates focus; returned by nothing. B flagged only its sibling `ConsoleRecording`.
- **`clock.capnp:275 interface AlarmService`** — 8 alarm CRUD methods, unreachable (even `ClockService` does not return it). C's clock audit plans to make this "the canonical alarm home" without noting no consumer path exists.
- `DriverRegistry`/`DriverLifecycle` are **also** unreachable (B calls them "reachable"; only a comment at `display.capnp:852` mentions them).

### 2.3 Event unions missing `unknown` that no per-file audit flags
Validator E6 (65 repo-wide) vs audit coverage: every hit in C's and D's batches is covered; A's batch contributes `boot.capnp:692 BootEvent`, `kernel.capnp:235 TaskEvent`, `init.capnp:183 InitEvent` — kernel and init are covered per-file, **`BootEvent` is covered by no audit** (boot's audit discusses BootEvent only for failover semantics). B's batch: `input.capnp:205 DeviceEvent` is covered; `module.capnp:127 Source` is praised in the per-file audit and never checked for the variant; `print.capnp:208 PrintRange` is discussed only for unbounded `pages`.

### 2.4 ID typing — the tree-wide class the audits only sampled
- **195 fields named `*Id`/`*ID` are typed `Text`**; audits cover ~10 (E §2.5's list, D's appId/pid). Un-flagged with real identity consequence: `abi.capnp:117,167 sessionId :Text` (in the ABI negotiation schema itself), `windowmanager.capnp:303,356 appId :Text` (window→app identity), `web.capnp:401,510,517 sessionId :Text` (three Text session namespaces in one file), `boot.capnp:214 deviceId :Text`, `network.capnp:494 bundleId :Text`.
- **46 fields named `*Id` are typed `UInt32`**; audits cover `windowmanager pid` (D8) and `app instanceId` (D). Un-flagged: `queue.capnp:322 partitionId`, `database.capnp:714 shardId`, `device.capnp:159,285 groupId`, `boot.capnp:273,274,290 controllerId/namespaceId/targetId`, `console.capnp:457,468 displayId`, `speech.capnp:212,239 speakerId`. (Legitimately small/hardware-local: `NumaDomain.domainId`, `CpuId.id`, touch/hat indices — do not flag those.)

### 2.5 Inline bulk payloads
310 `List(Float32)/List(UInt8)/List(Text)/List(Bool)` field sites repo-wide. Audits covered the material ones (audio:892, camera:38, capture:34, console:406, display:243, input:234-236, sensor:375, font:386, media:202, nfc:553, database:613/619/628, files:35/63, archive:93/102, web:128/190, network:500). Remaining sites are small vocabulary lists (uuids, categories, aliases) — correctly not bulk. One un-flagged oddity: `boot.capnp:511 dns :List(Text)` — DNS server addresses as bare `Text` where `T.IpAddress` exists.

### 2.6 Doctrine drift the audits did not report
- `DESIGN_PRINCIPLES.md:396` / `TIMELESSNESS.md:167` claim the per-method `Capability` pattern survives in "5 methods repo-wide, all inside capability.capnp". Actual count inside capability.capnp: **7** (attenuate, transfer, revoke, revokeControlled, evaluateCondition, compose, requestTransferApproval). Minor, but the doctrine undercounts the very pattern it retired.
- Per-method `Capability` parameters outside capability.capnp exist **only** on ai.capnp's seven root accessors — confirming the reference model is intact tree-wide (supports B/D/E's authority findings as *parallel-model* violations, not per-method-token violations, exactly as D's C9 states).

---

## 3. Overreach list

Findings that fail the founder's standard (no concrete failure / contrived scenario / complexity-add / contradicts ai.capnp's deliberate pattern / overrides an exemplary rating without evidence). The five exemplary-rating overrides (boot, kernel, auth, secret, audio) all carried evidence and are **not** here.

**O1 — B top-10 #5: "Repair the authority model across 12 schemas … an accessor layer per service (~8 methods each)."**
Contradicts ai.capnp's deliberate pattern and inflates cost ~8×. The gold standard gates with **one accessor per service** (`models @2`, `inference @3`, … `subscribe @8` — ai.capnp:578-584); the doctrine template (DESIGN_PRINCIPLES:368-374) is the same shape. "~8 methods each × 12 schemas ≈ 96 new methods" is the largest additive proposal in the corpus, against a standard whose stated goal is simplification. The correct call for most of the 12 sites (sensor `permissionCapability`, module `capabilities :List(Text)`, device `DevicePolicy`, nfc payments) is **delete the parallel model**, then gate at the existing root with one accessor. Verdict: keep the deletion half; reject the "~8 methods per service" figure and shape.

**O2 — C top-10 #3: "promote one `TransportProfile`/`TlsConfig` pair to `types.capnp` + a normative paragraph."**
Complexity-add where deletion suffices, and the gain is a hypothetical. C's own evidence is three *duplicate* types (`TlsVersion` in endpoint:670 **and** types:1564; `ConnectionPoolConfig` ×2; socket's `TlsSession` vs endpoint's `TlsConfig` vs nothing in web) — all fixable by delete-or-align with no new type. The "five things a 2046 client must be told" is a real concern but names no consumer that exists and no failure that occurs; promoting a new struct family into the eternal foundation file is exactly the speculative-machinery failure C itself warns against two paragraphs later ("not a new transport schema"). Verdict: execute the deletion half (collapse the three TLS homes, delete the loser `ConnectionPoolConfig`); defer any `TransportProfile` promotion until a named consumer exists.

**O3 — D cli REWRITE: schema-derived command registry (`listCommands` + `CommandSpec` binding name → schema/interface/method; params as `T.DataHandle` "taught from capnp reflection").**
The necessity rests on a quoted "brief" that exists in no repository document (`SCHEMAS.md:147` describes the file as "Command execution, shell access, custom commands"; no doc mentions introspection-driven generation). Meanwhile the audit's *verified* defects — `checkPermission @11` per-call authority, `getJobStatus @2`/`pollPrompt @16` polling, `CommandOutputFormat` naming 2000s formats, `PipeMode` redirect/append with no target, `createScript` shell-language-in-protocol, `ResourceLimits` third quota model — are **all fixable by deletion**, cutting the file's surface rather than adding a reflection layer. Verdict: delete the verified defects; treat the registry as an unrequested feature until the founder confirms the requirement.

**O4 — D top-10 #10: "give every non-neutral enum `@0` a neutral sentinel … in this batch's ~160 cases."**
Blanket scope without concrete failure for the majority. E8 fires on every enum whose `@0` is a paradigm value, but the defect only exists where an **absent field** defaults — i.e. filter/request structs. For event and result enums (always written on the wire) the sentinel is pure noise, and D itself demonstrates the noise problem by rejecting sibling rule E7 as over-broad (~1,900 report lines) without applying the same scoping to E8's ~800. Verdict: apply the sentinel to filter/request/optional-field enums only; document the rest.

**O5 — B §2.1(a) + E action #10(b): new machinery where the gold-standard pattern is a parameter.**
B's fix for pagination-on-live-streams is "fix once in types.capnp by adding a max-count pull parameter (**or a `T.StreamPage {maxCount, sequence}`**)" — but the audit itself states "the correct primitive already exists in ai.capnp:277 (`pull (maxBytes :UInt32)`)". ai.capnp's deliberate answer is a plain parameter, not a new shared type; introducing `T.StreamPage` into the eternal foundation contradicts the minimal pattern the audit cites as its own precedent. Similarly, E's ai.capnp action proposes **bounding** `handshake`'s model list, which contradicts ai.capnp's explicit reasoning at :565-570 ("handshake publishes known models so that discovery is possible before any capability is held — otherwise acquire-to-discover would deadlock"). The right fix for both is the parameter/shape change with no new type: `pull (maxCount :UInt32)`, and `handshake → List(ModelId)` instead of `List(ModelDescriptor)`.

---

## 4. Cross-batch contradictions

**X1 — `T.BluetoothAddress`: "dead, adopt it" (B) vs "misused, rename it" (C).**
B §2.2: "`T.BluetoothAddress` (types.capnp:768) — dead: no schema uses it… bluetooth.capnp should adopt it." C's network audit (`:18`, action `:55`): the type is used at `network.capnp:224,152,716,732` and those uses are **wrong** ("A WiFi AP MAC is not a Bluetooth address… rename to `T.MacAddress`, alias the old name"). Both cannot be executed as written: B's fix spreads a type C says is semantically false; and B's premise ("dead") is factually refuted by C's own citations. The reconciliation neither batch attempted: `types.capnp:768` is a *promotion that half-happened* — network/shell adopted it for MAC-shaped values while bluetooth.capnp kept `Text`. Correct resolution: one `T.MacAddress` (or BluetoothAddress renamed + aliased), adopted by all three files including bluetooth.

**X2 — `HealthStatus` count: 2 (A) vs 3 (C) vs 6 (actual).**
A's duplicate table lists the discovery↔diagnostics pair; C's action 4 says "HealthStatus ×3 (two incompatible)". Full-tree scan: **six** definitions (audio:1212, diagnostics:102, discovery:146, endpoint:171, filesystem:204, tunnel:291). Neither batch reconciled the set; no audit holds the complete picture.

**X3 — Session handshake count: 5 (D) vs 7 (actual), with B holding the missing two.**
D's C1 says five shapes and names compositor/shell/windowmanager/ime/screenlock. `buffer.capnp:29-47` (the oldest instance, the doctrine's own template at :258) and `font.capnp:53-70` also carry the trio. B's font audit found the font/screenlock pair independently. D's conclusion (unify on compositor's open `CapabilityRequest`) survives; its census does not.

**X4 — E-batch internal: E summary vs E per-file on the stale header comment.**
E §4.12 says "`speech.capnp:12` says SearchAction.id uses T.EventId"; E's own `system_search.capnp.md:35` correctly locates the comment at `system_search.capnp:12` (and `speech.capnp:12` is about VoiceGender). The batch summary is wrong; the per-file report is right.

**X5 — B internal: "DriverRegistry/DriverLifecycle is reachable" (summary §2.5) vs the evidence.**
The summary treats them as the reachable half of the provider framework; the interface scan shows nothing returns them (only a comment at `display.capnp:852`). B's proposed fix (a root accessor) is unaffected; the premise is not.

**X6 — Transport-gap ownership.** Only batch C raises the missing normative transport profile. Batches A/D/E flagged capability-transport-adjacent defects (raw-id subscriptions, handshake shapes) without connecting them to C's framing; no batch disagrees, but no one owns the tree-wide view. Not a contradiction — a coverage gap noted for the merge owner.

---

## 5. Search schema verdict

**Verdict: KEEP-SPLIT — the split is principled; each half needs restructuring, not merger.**

### Did the E-batch examine the split?
**No.** Neither `runtime_search.capnp.md` nor `system_search.capnp.md` nor the E BATCH-SUMMARY evaluates whether the two files should be one. Each audit's only cross-reference is a duplicate-spotting aside, and one of them is factually wrong: runtime_search's audit claims the file "duplicates [system_search's] `VectorQuery`/similarity vocabulary conceptually" — runtime_search.capnp contains **no** `VectorQuery` and **no** `SimilarityMetric` (verified by grep; those types exist only in system_search, content, and database). E's own §2.6 observes "five search surfaces with no shared query/result type" and stops there. No audit file, interface-count, or consumer analysis of the split exists anywhere in the 87 reports.

### Is the split principled? Yes — on three independent tests
1. **Articulated, distinct semantics.** `runtime_search.capnp:7-13` states the boundary deliberately: system_search "catalogs *what is stored*", runtime_search "catalogs *what is currently providing*". These are different facts with different truth conditions: content is durable and indexed; runtime instances are ephemeral, heartbeat-ed (`lastSeenAt`, `TtlPolicy`, `HealthCheck`) and state-machined (`RuntimeState`). A unified contract would have to reconcile stable-index semantics with live-stream semantics on every shared field.
2. **Distinct consumers.** system_search is the user/shell-facing content surface (providers register `SearchHandler`s; results carry icons, thumbnails, actions, MIME types). runtime_search is the service-manager-facing dependency surface (`getDependencies`, `getDependents`, `checkVersionCompatibility`). Different callers, different authority, different lifetimes.
3. **Distinct data models, no shared surface.** The two files share no imports (each imports only types.capnp) and no type names except the genuine cross-collisions (`LogEntry`/`LogFilter`/`TraceSpan` — which are duplicates of *logging/klog/diagnostics*, not of each other; `ServiceSla`/`ServiceDependency` — duplicates of *discovery/service*).

### Why not UNIFY?
Merging produces one file with a 47-method interface (26 + 23, minus shared) whose two halves disagree on the meaning of "query" and "result", and forces the live-stream half to inherit content-index machinery (facets, bookmarks, trending) it has no use for. That is complexity, the opposite of the standard. The doctrine's own precedent for domain-scoped siblings is explicit — `DESIGN_PRINCIPLES.md:213`: six `Session` interfaces are "acceptable IF each represents a distinct service domain"; the same test passes here on the evidence above. Nor is UNIFY-WITH-RESTRUCTURE distinct in substance: the two files are already one interface each, so merging files buys nothing unless the shared primitives move — which is a restructuring *inside* the split, not a merger.

### What the split does need (optimization, no capability cut)
- **runtime_search**: cut the drifted Audit-9/10 service-mesh control plane — `getCostModel`/`setCostModel`, `migrateService`/`getMigrationStatus`, the `ServiceCatalogEntry`/`ServiceSla`/`ServiceOwnership`/`ApiDocumentation`/`ChangelogEntry` catalog, `getServiceLogs`/`getServiceMetrics`/`getTrace` (a fourth observability stack after logging/klog/diagnostics), `registerLifecycleHook` — none of which has a consumer in the protocol. Delete the local `Capability`/`CapabilityPermission`/`PermissionDomain`/`PermissionAccess` permission model (collides with `capability.capnp:22` by name) in favor of canonical `Capability`. This is deletion, and it is what makes the file a discovery contract again.
- **system_search**: fix the result-identity break (one typed `resultId` used by `executeResult`/`getResultPreview`/`SearchHandler.execute`/`explainResults`/`deduplicateResults`); make `VectorQuery.embedding` a `T.DataHandle` (the one remaining bulk copy, in the file whose header advertises the migration); pick one pagination model.
- **Tree-wide**: promote the shared search primitives (query envelope, result envelope, subscription) to `types.capnp` so the split stays principled instead of drifting into same-name-different-shape — which has already happened once (`SearchQuery`: files.capnp:428 vs system_search.capnp:137; `SearchResult` in three files). One promotion, and the 2046 divergence class closes without a merger.

**Argument against the alternative, stated plainly:** UNIFY would cut no capability and add none — it would simply relocate two coherent contracts into one incoherent file, and the strongest evidence for the split is that both files' headers already declare it, the consumers are disjoint, and the accretions each has collected are the actual defects — defects that survive any file boundary and vanish only under deletion.

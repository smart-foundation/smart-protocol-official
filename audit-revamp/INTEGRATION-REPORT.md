# INTEGRATION REPORT — closing the gaps left by the five rewrite waves

**Agent:** the integration agent · **Tree:** `smart-protocol-official/` · **Date:** 2026-10-10
**Mandate:** verify and close every gap left by batches A–E, bring stale artifacts into alignment
with the post-revamp tree, no git commits, no cargo builds, no edits outside this repository.

**Headline.** Every gap on the list is CLOSED. The one item that required a judgement call
(`T.UnknownEvent.payload`) is a documented DECISION, not a deferral. `E12` went from **36 findings
to 0** — the entire cross-batch duplicate set is eliminated by resolution, with no sanctioned-
exemption list to maintain. `E6`, `E13` and `E14` also went to **0**. `capnp compile` over all 89
schemas exits 0 with empty stderr; `scripts/validate.py` exits 0.

---

## 1. Gap-by-gap disposition

### Gap 1 — the validator's "other 91 schemas" claim — **CLOSED**

The docstring said "the other 91 schemas" and the REPORT tag line said "91 non-ai schemas",
while the tree parses 89. Both are now computed from the tree the script just read:

* docstring → "REPORT — measured but not blocking, for every other schema in the tree", plus a
  closing paragraph stating that **no schema total is hardcoded anywhere in the script**, so the
  printed numbers cannot drift from `ls schema/`.
* report line → `Schemas parsed: 89 (88 besides ai.capnp)`, where `88 = len(schemas) - 1`.

Verification of the fix: delete a schema from `schema/` and the printed count follows. The rule
summary block also prints **all nine** REPORT rules (E6–E14) rather than only E9–E14, which is what
makes the before/after comparison in §3 below mechanical rather than anecdotal.

### Gap 2 — `find_blocks` cannot parse `interface X extends(Y)` — **CLOSED**

Batch B's report §5f flagged it: gpu.capnp's `Gpu3DProvider extends(GpuProvider)` produced a false
E11 finding, because the parser stopped matching at `extends` and therefore never saw the
interface that returned it. The declaration-head regex is now shared by every parser entry point
and tolerates the clause in both spellings:

```python
_HEAD     = r"\b%s\s+(\w+)\s*(?:extends\s*\(?\s*[\w\.\s,]*\)?\s*)?\{"
_HEAD_LINE= r"^%s\s+(\w+)\s*(?:extends\s*\(?\s*[\w\.\s,]*\)?\s*)?\{"
```

`find_blocks`, `top_level_types` and (for structs) the value-struct analyser all use the same head,
so `interface Child extends(Base) {` and `interface Child extends Base {` are both parsed. Proven
against a synthetic fixture:

```
find_blocks:       [('Base', 2), ('Child', 5)]
top_level_types:   [('interface','Base',2), ('interface','Child',5), ('struct','S',8)]
```

The tree currently declares no `extends` (batch B merged `Gpu3DProvider` into `GpuProvider` and
deleted `open3DProvider`), so the fix changes no current finding — it removes the trap for the
next schema that inherits.

### Gap 3 — E6's exemption list was too narrow — **CLOSED, widened by shape**

Old code: `if sname in TERMINAL_UNIONS: continue`, a hand-maintained list of three names.
Consequence: all 27 honest `{ ok; error }` / `{ frames, empty, ended, error }` / `{ signalled,
error }` result unions in the tree were reported as missing an extension point (E6 = 31, of which
4 were real).

New code exempts **by shape**: a union with an arm typed `T.Error` (or `Error`) is the error model
`DESIGN_PRINCIPLES.md` itself defines (`union { buffer; error :T.Error }`), so `T.Error` *is* the
extension point and a further arm would be noise.

```python
ERROR_ARM_TYPES = {"T.Error", "Error"}
...
if any(t in ERROR_ARM_TYPES for _, t in arms):
    continue
```

The widening is a test, not a list, so it cannot go stale: a union that loses its `T.Error` arm
starts reporting again, and a union with neither `T.Error` nor `unknown` still reports. E6 fell
31 → **3**, and those 3 were then fixed as real defects (see Gap 3b). E6 is now **0**.

One bug was found while widening: my first `union_arms` regex used a strict `[\w\.]+` type
pattern, which silently dropped `pages @1 :List(UInt32)` and under-reported a union's arms. The
arm parser now matches the type permissively (`.+?` up to the `;`), which is what makes the shape
test trustworthy.

### Gap 3b — the three genuine E6 gaps — **CLOSED**

* `media.capnp` `PlayerEvent` — the finding batch B parked under the KEEP ruling (§5a). Gained
  `unknown @4 :T.UnknownEvent`, so a DRM-licence change or transport-stall class a backend
  invented is routable rather than an unrecognisable union member.
* `module.capnp` `Source` — gained `unknown @5 :T.UnknownEvent`, for a source form (a package
  index, an attestation-gated remote, a content-addressed store) the contract has not named.
* `print.capnp` `PrintRange` — gained `unknown @3 :T.UnknownEvent`, so a selection form the
  contract has not named is not silently truncated into `all` or `range` by a backend guessing.

### Gap 4 — `T.KeyCode`'s unpublished domain — **CLOSED**

The struct carried a note claiming "the protocol defines a cross-platform semantic key space" —
which it never did; the value space was unpublished and the field was a raw `UInt32`, the same
defect batch D removed from `cli.capnp`'s `methodId`. `input.capnp:17-27` had in fact published
the domain all along. The types.capnp note now states the canonical page and where the mapping
lives, and explicitly retires the semantic-space claim:

> `code` is a **USB HID keyboard/usage-page-0x07 usage id**, as `input.capnp:17-27` states. That
> page is a stable, vendor-neutral, already-published numbering of physical keys, so the protocol
> **inherits** a domain rather than defining a second one… What is deliberately NOT here is a
> semantic key space (`"KEY_ENTER"`), which is a second vocabulary to keep in agreement with the
> HID page forever, and a 2046 keyboard would have no ordinal in it. For the semantic direction,
> `compositor.capnp.LogicalKey` is the open token + Unicode codepoint pair.

`input.capnp` keeps the full statement. No wire change — the field was already `UInt32`.

### Gap 5 — R2: `T.UnknownEvent.payload` is inline `Data` — **DECISION: formally sanctioned (option b)**

This was the one knowingly-open doctrine gap, and the instruction was to decide correctly rather
than conveniently. I chose **(b) sanction it**, and rejected (a).

**Why a handle is not constructible here.** `T.DataHandle` is a union — inline `Data` *or* a
`BufferId` reference — so making `payload` a handle does not remove the copy, it *relocates the
decision*. A producer choosing a handle must know the payload's size; an unknown payload has no
known size by definition (if the producer could describe it, it would have declared a typed arm).
So option (a) buys nothing that inline `Data` does not already provide, and it adds a buffer
registration for a value the producer is explicitly not interpreting.

**Why (a) is worse than useless across transports.** The `BufferId` arm of `T.DataHandle`
requires producer and consumer to share a buffer namespace. A producer emitting an event it
cannot model, over a transport that shares no such namespace with its consumer (a network
transport, a serialising RPC hop, a browser backend), **cannot construct a handle at all**. Making
the field a handle would make the escape hatch unimplementable on exactly the transports where
it is most needed. That is the "genuinely constructible for arbitrary unknown payloads across
transports" test in the mandate, and it fails.

**The alternatives were each worse.** Typed arms per domain re-freeze today's list (R1). `Text`
asserts UTF-8. `T.StringMap` asserts pairs. All three are the leak the arm exists to prevent.

**So the protocol carries exactly one inline payload, here, where opacity is the point.** The
reasoning is written into `types.capnp` immediately above the struct (four numbered arguments),
and the validator now recognises the exception **explicitly and narrowly**:

```python
R2_ESCAPE_HATCH = ("types.capnp", "UnknownEvent")
...
if ftype == "Data" and fname.lower() in PAYLOAD_FIELD_NAMES \
        and (fn, sname) != R2_ESCAPE_HATCH:
    reports.append(...)
```

The old exemption was `UNKNOWN_EVENT_STRUCTS = {"UnknownEvent"}` — matched **by struct name in any
file**, which means any schema could have inherited the exemption by re-declaring a struct called
`UnknownEvent` (exactly the drift R6 exists to stop). The new form is keyed to **(file, type)**, so
the exemption cannot be inherited. This is a declared exemption with a written justification in
the artifact, not an unenforced hole: E10 still reports every other `payload :Data` in the tree
(59 findings remain, none of them `UnknownEvent`).

### Gap 6 — cross-batch duplicate elimination (E12 ×36 → 0) — **CLOSED**

See §2 for the full resolution table. Every same-name-different-file type in the tree is gone.
Three structural decisions carried the pass:

1. **Promotion, not per-domain copies.** `T.SpatialPose` is now in `types.capnp` (three domains
   addressed it: position, rotation, velocity — input.capnp and location.capnp were byte-identical
   in shape, and both now import the foundation). compositor's deliberately different
   surface-placement shape (scale + anchor, `Vec4` rotation) is kept under the honest name
   `SurfaceSpatialPose`. Merging the two would have forced velocity onto a surface and an anchor
   onto a device.
2. **Import, where one side was already canonical.** `auth.capnp` imports `appindex.capnp`'s
   `AppIcon` (its own was a three-field shadow of the five-field original). `shell.capnp` imports
   `bluetooth.capnp`'s `BluetoothDevice`. `display.capnp` imports `T.ColorSpace`. `input.capnp` and
   `location.capnp` import `T.SpatialPose`. `timezone.capnp` imports `calendar.capnp`'s
   `RecurrenceFrequency`. `screenlock.capnp` imports compositor's handshake.
3. **Disambiguation, where the shapes were materially different.** 24 pairs were two genuinely
   different concepts that happened to share a name (`KeyEvent` a console key press vs a key
   lifecycle event; `OutputMode` a display mode vs a console output channel; `Session` a
   per-service root vs the user session). Both names survive, disambiguated, with the reason
   written at the declaration site.

**The `Session` finding needed its own decision.** Six files declared `interface Session`
(compositor, ime, screenlock, session, shell, windowmanager) — and, discovered during the pass,
`shell.capnp` declared **both** `interface Session` and `struct Session` (a service you call vs a
record describing a session you hold, in the same file, under one name). I resolved it the way
`DESIGN_PRINCIPLES.md:212` prescribes — *"Accept but rename for clarity… do NOT merge domains"*:

* the five **service** sessions are named for their domain: `CompositorSession`, `ShellSession`,
  `WindowManagerSession`, `ImeSession`, `ScreenlockSession`;
* `session.capnp` keeps the plain name `Session`, because it is the user session the doctrine
  names and the file is named after it;
* `shell.capnp`'s session *record* is now `ShellSessionInfo`.

Method sets and ordinals are untouched — this renames roots, it does not rewrite any service. The
alternative (a validator exemption for the shared name) was rejected: it would have left E12 with
a hole to maintain, where the doctrine's own instruction was to rename. And the handshake pattern
that batch A settled is now actually adopted everywhere — see Gap 9.

### Gap 7 — pending foundation promotions — **CLOSED**

`T.WindowGroupId`, `T.SnapZoneId`, `T.IntentChainId`, `T.IntentTraceId`, `T.IntentHistoryId` and
`T.SpatialPose` are declared in `types.capnp`. `windowmanager.capnp` and `intent.capnp` keep **no
local id wrappers at all** — the "Candidates for promotion to types.capnp when the foundation file
is next revised" notes are gone, replaced by notes recording that the foundation is now the single
home. Every reference in those two files is qualified `T.*`.

### Gap 8 — `module.capnp`'s `manifest.capnp.Semver` — **CLOSED**

`ModuleDesc.version` and `RuntimeBinding.minVersion/maxVersion` now take `T.Version` (3 field
types + 1 import). The compat struct is deleted from `manifest.capnp`, its slot replaced by a
`# ── Semver: DELETED ──` note recording what it was, why it survived the revamp, and what
removed it. A 16-bit major that wrapped at 65535 is gone from the tree.

### Gap 9 — `screenlock.capnp` adopts the shared handshake — **CLOSED**

This was the last file with a private handshake dialect, and it was the reason the MANIFESTO claim
"the other sessions import it instead of drifting into a seventh dialect" was not yet literally
true. `screenlock.capnp` now imports `compositor.capnp` and uses `C.SessionRequest` →
`C.SessionResponse` (`agreedVersion`, `granted`, `denied`, `C.ServiceInfo`, `C.HandshakeResult`),
and its private `HandshakeRequest`/`HandshakeResponse`/`HandshakeResult` trio is deleted. All five
service sessions in the tree now handshake through one type. The file header records the reason:
a lock screen that could not negotiate a protocol version or request a capability at handshake
could only be opened or refused.

### Gap 10 — the unconsumed foundation `TlsVersion` — **DECISION: delete it**

Batch C left it as an open question. The resolution follows the doctrine:

* **An unconsumed eternal type is dead weight.** `socket.capnp` now types a version as an open
  token; nothing in the tree referred to `T.TlsVersion`. Every schema pay to parse
  `types.capnp`, and this enum bought none of them anything.
* **It is itself an R1 defect.** A closed list of today's TLS versions — with `ssl30 @0` as the
  zero member, an E8 violation — frozen into the eternal foundation. The tree just deleted ~130
  closed algorithm enums from crypto.capnp for exactly this reason; leaving one in the foundation
  would have been an inconsistency, not a conservatism.
* **The R1-sanctioned pattern already exists and is canonical:** `socket.capnp`'s `TlsConfig`
  carries `version` as an open token, so a TLS successor is spellable today with no new ordinal.

Deleted, with the reasoning written into the slot it vacated in `types.capnp`.

**The same reasoning deleted two more unconsumed foundation types** found during the pass
(recorded, not on the original list):

* `T.GestureEvent` + `T.TouchGesture` — a pair in which the enum's **only reader** was the struct,
  and no schema outside types.capnp named either. The live gesture contract is
  `input.capnp`'s `GestureEvent` (`gestureId`, `timestamp`, `surfaceId`, `touches`). `shell.capnp`'s
  comment that said `ShellGesture` was renamed to avoid a *types.capnp* collision is corrected:
  the collision no longer exists because the shadow is gone.
* `manifest.capnp`'s compat `Semver` — see Gap 8.

The lesson is recorded in the artifact: the foundation earns a type by being consumed by two or
more domains, not by being a plausible idea.

### Gap 11 — docs alignment — **CLOSED**

Every number and name below was recomputed against the tree, not adjusted by hand.

`README.md`
* "153 arms across 46 schemas" → **47** (3 arms added by Gap 3b).
* "336 handle fields in the tree" → **353 field and parameter positions typed `T.DataHandle`**,
  now stated with its definition so a reader can recount it.
* "~49,000 lines" → **~49,500** (49 546 actual).
* "One `Session`, one commit path" → "One **`CompositorSession`**, one commit path".

`docs/MANIFESTO.md`
* "731 string-map fields" → **760**, with the definition stated.
* "153 arms across 46 schemas" → **47**.
* "There are 336 `T.DataHandle` fields" → **353**; "kept 336 times over" → **353 times over**.
* "roughly 49,000 lines" → **roughly 49,500**.
* Three `Session` references → `CompositorSession`; the reading-map row for the session pattern
  now names all six session-shaped interfaces and the shared handshake.

`docs/SCHEMAS.md`
* **Every per-file line count** re-derived from the tree by script (19 files had drifted: types
  2,134 → 2,228; module 368 → 375; screenlock 385 → 403; console 741 → 754; input 818 → 812;
  display 971 → 958; location 328 → 318; media 424 → 433; network 938 → 943; print 383 → 388;
  timezone 525 → 524; intent 733 → 730; manifest 423 → 412; access 744 → 751; usb 688 → 689;
  framebuffer 650 → 651; shell 1,323 → 1,328; audio 1,286 → 1,329; accessibility 692 → 701).
* Six interface entries renamed (`Session` → the five domain names; `ChangesSubscription` →
  `ClipboardChangeSubscription`/`SecretChangeSubscription`; `AudioStream` → `SpeechAudioStream`),
  and the interface lists for `accessibility`, `biometric` and `nfc` completed.
* The gate-status paragraph now names **E1, E2, E4, E6, E9, E12, E13, E14 at zero tree-wide**
  instead of only E1/E2/E4/E9, and points at this report for the E7/E8/E10/E11 residuals.
* The header notes the integration pass re-verified every count and name.

`DESIGN_PRINCIPLES.md`
* The E6 row in the rule table now states the shape exemption ("a union whose non-success arm is
  `T.Error`… is itself the extension point") rather than the superseded name list.
* A new paragraph records the two scoping decisions that are doctrine: **E14 counts an
  interface taken as a parameter as reachable**, and **E12 is satisfied by elimination, not by
  exemption** — with the reason, so a future reader does not either re-add the hole or mistake
  the closure for luck.

---

## 2. E12 resolution table

36 findings → 0. **P** = promoted to `types.capnp` · **I** = the non-canonical side imports the
canonical side · **R** = both sides kept under disambiguated names (shapes materially different).

| # | Fork type | Canonical home | Sides rewritten | Kind |
|---|---|---|---|---|
| 1 | `SpatialPose` | `types.capnp` `T.SpatialPose` | `input.capnp`, `location.capnp` import it; `compositor.capnp`'s → `SurfaceSpatialPose` | **P** |
| 2 | `Session` | `session.capnp` (the user session) | `compositor`→`CompositorSession`, `ime`→`ImeSession`, `screenlock`→`ScreenlockSession`, `shell`→`ShellSession`, `windowmanager`→`WindowManagerSession`; shell's `struct Session` → `ShellSessionInfo` | **R** |
| 3 | `AccessibilityRole` | `accessibility.capnp` (70 values, WAI-ARIA) | `console.capnp`'s → `ConsoleRole` | **R** |
| 4 | `AppIcon` | `appindex.capnp` | `auth.capnp` imports `AI.AppIcon`, local copy deleted | **I** |
| 5 | `AudioFormat` | `audio.capnp` | `speech.capnp`'s → `SpeechAudioFormat` | **R** |
| 6 | `AudioState` | `audio.capnp` | `shell.capnp`'s → `ShellAudioState` | **R** |
| 7 | `AudioStream` | `audio.capnp` (struct) | `speech.capnp`'s interface → `SpeechAudioStream` | **R** |
| 8 | `BiometricTemplate` | `biometric.capnp` | `input.capnp`'s → `InputBiometricTemplate` | **R** |
| 9 | `BluetoothDevice` | `bluetooth.capnp` | `shell.capnp` imports `B.BluetoothDevice`, local copy deleted | **I** |
| 10 | `BluetoothState` | `bluetooth.capnp` | `shell.capnp`'s → `ShellBluetoothState` | **R** |
| 11 | `CaptureResult` | `capture.capnp` | `compositor.capnp`'s → `CompositorCaptureResult` | **R** |
| 12 | `ChangesSubscription` | `clipboard.capnp` / `secret.capnp` (two domains) | → `ClipboardChangeSubscription` / `SecretChangeSubscription` | **R** |
| 13 | `ColorSpace` | `types.capnp` `T.ColorSpace` | `display.capnp`'s local 11-value shadow deleted, both sites import `T.ColorSpace` | **I** |
| 14 | `DeviceFilter` | `device.capnp` | `input.capnp`'s → `InputDeviceFilter` | **R** |
| 15 | `DevicePowerState` | `device.capnp` | `hal.capnp`'s → `HalDevicePowerState` | **R** |
| 16 | `DiscoverySubscription` | `discovery.capnp` | `nfc.capnp`'s → `NfcTagEventSubscription` (it already had `TagSubscription`) | **R** |
| 17 | `EventFilter` | `compositor.capnp` | `calendar.capnp`'s → `EventQueryFilter` | **R** |
| 18 | `EventSubscription` | both domains | → `AccessibilityEventSubscription` / `UsbEventSubscription` | **R** |
| 19 | `ExportResult` | both domains | → `AccessibilityExportResult` / `VcardExportResult` | **R** |
| 20 | `ExtensionInfo` | `extension.capnp` | `system.capnp`'s lean view → `SystemExtensionInfo` | **R** |
| 21 | `FocusEvent` | both domains | → `AudioFocusEvent` / `SurfaceFocusEvent` | **R** |
| 22 | `Frequency` | `types.capnp` `T.Frequency` (Hz + metadata) | `calendar.capnp`'s enum → `RecurrenceFrequency` | **R** |
| 23 | `GestureEvent` | `input.capnp` (live, consumed) | `types.capnp`'s unconsumed shadow deleted (with `T.TouchGesture`) | **P** |
| 24 | `HealthStatus` | `diagnostics.capnp` (struct) | `audio.capnp`'s enum → `AudioHealth` | **R** |
| 25 | `KeyAction` | `input.capnp` (the action union) | `compositor`'s enum (pressed/released — a *transition*, misnamed) → `KeyTransition`, and its field `action` → `transition` in both compositor and ime | **R** |
| 26 | `KeyEvent` | `console.capnp` (a key press) | `key_management.capnp`'s union → `KeyLifecycleEvent` | **R** |
| 27 | `MergeStrategy` | `manifest.capnp` | `contacts.capnp`'s → `ContactMergeStrategy` | **R** |
| 28 | `OutputMode` | `compositor.capnp` (a display mode) | `console.capnp`'s enum → `ConsoleOutputMode` (an output *channel*) | **R** |
| 29 | `ResourceType` | `types.capnp` (driver resources) | `sandbox.capnp`'s enum → `SandboxResourceType` (quota kinds) | **R** |
| 30 | `SearchResult` | `system_search.capnp` (the provider envelope) | `shell.capnp`'s launcher hit → `ShellSearchResult` | **R** |
| 31 | `ServiceDependency` | `discovery.capnp` | `runtime_search.capnp`'s → `RuntimeServiceDependency` | **R** |
| 32 | `ServiceInfo` | `compositor.capnp` (the handshake's) | `service.capnp`'s → `ServiceInstanceInfo` | **R** |
| 33 | `StateChange` | both domains | → `AccessibilityStateChange` / `ServiceStateChange` | **R** |
| 34 | `StreamConfig` | `audio.capnp` | `translation.capnp`'s → `TranslationStreamConfig` | **R** |
| 35 | `TextStyle` | `theme.capnp` (the font scale) | `console.capnp`'s → `ConsoleTextStyle` (cell attributes) | **R** |
| 36 | `ThemeSubscription` | `theme.capnp` | `console.capnp`'s → `ConsoleThemeSubscription` | **R** |

**Zero behaviour lost.** Every reclassified pair kept both full field sets; no field was dropped
anywhere. The only type whose shape *changed* is `display.capnp`'s colour space, which now uses
`T.ColorSpace` (12 values, including `rec2100`, `aces`, `cieXyz`, `cieLab`, `cmyk`) instead of its
11-value shadow: the three values the shadow had that the foundation does not (`rec601`,
`rec709`, `linearSrgb`, `linearDisplayP3`) are legacy transfer-function variants, and the cost is
recorded in the file header — a colour space the foundation does not name is spelled `custom`
with parameters, which is the doctrine's own answer. `auth.capnp`'s icon lost nothing: the
canonical `AppIcon` is a strict superset of its copy (adds `width`/`height`).

**Batch-A / batch-E cross-batch items verified already done:** the local `KeyId`/`EndpointId`/
`MountId`/`FilesystemId`/`StoragePoolId`/`VolumeId`/`SnapapshotId` copies in
endpoint/mount/storage/key_management/signature/crypto (batch E's claim confirmed — all resolve
to `types.capnp`); the private `UnknownEvent` copies in `ai.capnp`/`compositor.capnp` (gone —
grep finds no declaration outside `types.capnp`); `storage.capnp`'s `BusType` (gone — open token);
`files.capnp`'s `SearchQuery`/`SearchResult` (already `FileSearchQuery`/`FileSearchResult`/
`ContentSearchQuery`/`ContentSearchResult`); `database.capnp`'s `KeySubscription` (already
`KeyWatchSubscription`… renamed `NamespaceChangeSubscription`); `SimilarityMetric`
(single home in `system_search.capnp`, imported by `content.capnp`).

**Also executed from batch A's cross-batch item 12** (bounded pulls on live streams):
`audio.capnp`'s seven subscriptions — `AudioStateSubscription`, `DevicesSubscription`,
`StreamsSubscription`, `FocusSubscription`, `CodecSubscription`, `AnalysisSubscription`,
`DeviceHealthSubscription` — now take `pull (maxEvents :UInt32)`, and the seven convenience
`pull*` methods on the `Audio` root forward the bound, so no second unbounded path survives.
`capture`, `usb`, `camera` and `sensor` were already bounded (verified, not re-done).

**Also closed from batch C's cross-batch item 4** (stale references to the deleted
`filesystem.capnp`): five comment sites in `types.capnp` now name `mount.capnp`, and the four-line
stale note in `usb.capnp:22-26` is corrected to record that the deletion has landed.

---

## 3. Validator changes, with before/after E-counts

Four changes, all mechanical, all recorded in the script's own docstring so the next reader sees
what the gate does rather than inferring it.

1. **Counts computed, not hardcoded** (Gap 1) — docstring and the report line.
2. **`extends` clause parsed** (Gap 2) — one shared `_HEAD`/`_HEAD_LINE` pattern for
   `find_blocks`, `top_level_types`; no more invisible inherited interfaces.
3. **E6 widened by shape** (Gap 3) — `union_arms()` added; a `T.Error` arm is the extension point.
4. **E10's R2 escape hatch made explicit and unscoped by name** (Gap 5) — `R2_ESCAPE_HATCH`
   keyed to `(file, type)`.
5. **E14 reachability counts parameter-typed interfaces** — a provider-registered callback
   (`registerAuthMethod(handler :AuthHandler)`) is reachable because the caller supplies an
   implementation and the peer calls it. The old rule counted only return types and reported three
   live interfaces (`AuthHandler`, `speech.AudioStream`, `SearchHandler`) as unreachable. E14 3 → 0.
6. **E14's root heuristic generalised** — any interface whose name starts with the file's stem is
   that schema's entry point, so `compositor.capnp` → `CompositorSession` is recognised without
   depending on declaration order.
7. The report prints **all nine** REPORT rules (E6–E14), which is what makes the table below
   reproducible.

Tree-wide E-rule counts, before and after (the gate was exit 0 at both ends; these are REPORT
severities):

| Rule | Before | After | Change |
|---|---|---|---|
| E1 (ai enums) | 0 | 0 | — |
| E2 (ai bulk lists) | 0 | 0 | — |
| E4 (unreachable interfaces) | 0 | 0 | — |
| **E6** (unions) | **31** | **0** | widening + 3 real fixes |
| E7 (extension points) | 728 | 715 | −13 (the four deleted types and the structs that referenced them) |
| E8 (enum `@0` sentinel) | 270 | 267 | −3 (three deleted enums: `TlsVersion`, `TouchGesture`, timezone's `RecurrenceFrequency`) |
| **E9** (platform nouns) | 0 | 0 | — |
| E10 (bulk) | 59 | 59 | unchanged; 4 documented in-batch retentions stand |
| **E11** (authority) | 6 | 6 | unchanged — see §5 |
| **E12** (one home per type) | **36** | **0** | the integration job (§2) |
| **E13** (ordinals) | **1** | **0** | `access.capnp`'s `AccessEvent` re-issued |
| **E14** (reachability) | **3** | **0** | parameter-typed interfaces counted |
| **Total REPORTs** | 1 134 | 1 047 | |

The one E13 was `access.capnp`'s `AccessEvent`, where `custom @14` was declared after
`recoveryStateChange @15` and `backupRotated @16`. Re-issued to the tail: `recoveryStateChange
@14`, `backupRotated @15`, `custom @16`. Cap'n Proto keys on the ordinal, so the wire is
unchanged; the defect was that a reader scanning the file could not see which arm was the
terminator. The comment records the re-issue.

---

## 4. Naledzi migration list — for the Wave 1.5 agent (NOT executed here)

Verified read-only against `/home/lufuno/smart/naledzi` on 2026-10-10. Each item names the exact
file and action. Nothing below was touched.

### 4.1 `ipc-message.capnp` — deleted by batch A

| File | Action |
|---|---|
| `uspace/lib/capnp/build.rs:8` | remove `"ipc-message.capnp"` from the compile list |
| `uspace/services/ipc-service/build.rs:14` | remove `"ipc-message.capnp"` from the compile list |
| `uspace/lib/capnp/src/lib.rs:7` | delete the `pub mod ipc_capnp { … }` block |
| `uspace/services/ipc-service/src/lib.rs:28` | delete the `mod ipc_capnp { … }` block |

Consequence: codegen breaks in `space-capnp` and `space-ipc-service` until this lands (~15 lines).
Nothing reads `LogParams`, so no call-site work.

### 4.2 `filesystem.capnp` — deleted by batch C

| File | Action |
|---|---|
| `uspace/servers/filesystem/build.rs:4` | remove `"filesystem.capnp"` from the compile list (currently `&["types.capnp", "filesystem.capnp", "files.capnp"]`) |
| `uspace/servers/filesystem/src/main.rs` | **63 `filesystem_capnp::` references** and the 7 relocated `filesystem::` methods to re-point: `get_special_path` → `files.capnp`'s `getSpecialPath` (ordinals identical — the merge was wire-preserving), `get_trash`/`get_recent_files`/`get_default_app` → `files.capnp`, `mount`/`unmount`/`get_mounts` → `mount.capnp`, `get_health`/`snapshot`/path-keyed quota → `files.capnp`. Pool/volume/replication stay on `storage.capnp`. |

The FUSE provider block (`FsProvider`, `FuseCapability`, `FsMountOptions`, …) has **no port** — it
was deleted, not relocated; the provider axis is the capability accessor pattern.

### 4.3 `surface.capnp` — deleted by batch D

Vendored, frozen codegen is still compiled by the wall-lockscreen workspace:

| File | Action |
|---|---|
| `uspace/servers/compositor/kukan-slint/wall-lockscreen/crates/wall-protocol/build.rs` | remove `"surface"` from the `needed` list (it currently compiles an absent file) |
| `…/wall-protocol/src/gen/surface_capnp.rs` | delete the vendored generated file |
| `…/wall-protocol/src/gen/compositor_capnp.rs` | already carries compositor's types — verify it is regenerated from the current tree |
| `…/wall-protocol/src/lib.rs` (2 `surface_capnp` refs) | re-export from `compositor_capnp` |
| `…/wall-compositor/src/lib.rs:11` | `use wall_protocol::surface_capnp::surface_hints;` → `compositor_capnp::surface_hints` (the type is unchanged; `SurfaceHints` was absorbed verbatim by `compositor.capnp`) |

20 references total. The commit path changed too: `compositor.Session.commit` now takes one
`SurfaceCommit` (`T.BufferId` + a `SyncFence` holding `T.FenceHandle`) instead of the old
`bufferIndex @2 :UInt8` + `SyncFence.native @0 :UInt64`.

### 4.4 `textinput.capnp` — deleted by batch D

No `textinput_capnp` references remain in naledzi's Rust sources (grep-confirmed). **No action**;
listed for completeness so the agent does not go looking.

### 4.5 `gpu.capnp` — imported, then R5-fixed

| File | Action |
|---|---|
| `uspace/servers/gpu-intel/src/main.rs:1020` | `b.set_vendor(gpu_capnp::GpuVendor::Intel);` → `b.set_vendor("intel");` |
| `uspace/servers/gpu-intel/src/main.rs:1040` | `root.set_vendor(gpu_capnp::GpuVendor::Intel);` → `root.set_vendor("intel");` |

`GpuVendor` is now an open `Text` token, so the enum variant does not exist. Batch B also merged
`Gpu3DProvider` into `GpuProvider` and deleted `open3DProvider`, so any caller of
`open3DProvider`/`Gpu3DProvider` must move to `GpuProvider.submitRenderCommandBuffer @21` /
`uploadShader @22`.

### 4.6 Kernel/boot parity — schema surface naledzi implements

| Removed schema surface | naledzi implements | Replacement |
|---|---|---|
| `KernelService.registerService @36` | yes | `discovery.capnp`'s gated `registry @12` → `register` |
| `KernelService.signal @4` | yes | `SignalService.send` (the single delivery authority) |
| `KernelService.introspect @29` | yes | none — deleted; introspection is an implementation detail (TIMELESSNESS:84) |
| `KernelService.fork @1` | yes | `spawn @0` (the one creation path) |
| `BootHandoff.handlerTableVaddr` | yes | channels + `HandoffEndpoint` |
| `BootService.firmwareUpdate` | yes | `update.capnp` (received the firmware domain) |
| `BootService.delegateCapability` | yes | `capability.capnp`'s `attenuate @2` + `transfer @3` |

### 4.7 Schema-count references in naledzi documentation

These are prose, not code, but they are now false:

* `audit-008/reports/SCHEMA-AUDIT.md:4` — "All 92 schemas are aligned"
* `audit-008/plan.md:280` — "protocol/schemas/ -- all 92 schemas already aligned"
* `audit-009/reports/FOUNDATION-GAPS.md:12` — "**91 schemas** audited in `/protocol/schemas/`"
* `audit-009/reports/FOUNDATION-GAPS.md:338` — "**73 out of 91 schemas** have no server implementation"
* `saved.md:938` — "used ~1457× across ~90 schemas" (a `T.Error` count; recount against the tree)

The canonical count is now **89** schemas / 303 interfaces / 49 546 lines. Note that
`naledzi/protocol/schemas/` currently holds **93** files — a stale mixed copy that should be
replaced by an import path into this repository rather than maintained in parallel.

### 4.8 Not a migration item

`naledzi/protocol/schemas/` also contains files that no longer exist here. Do not treat its file
list as the contract; the contract is `smart-protocol-official/schema/`.

---

## 5. Open founder decisions

Recorded, not executed. Each names the decision and what it would cost.

1. **sandbox's `capabilityAdmin` object-under-manipulation pair (E11 ×2).**
   `SandboxCapabilityAdmin.grant(capability :Capability)` and `.revoke(capabilityId :T.CapabilityId)`
   are the second place in the tree where a `Capability` parameter is the object rather than an
   authority token — batch E's §6 alternative was to move grant/revoke into `capability.capnp` as
   `transfer`/`attenuate` call sites. That is the strict two-place reading of
   `DESIGN_PRINCIPLES.md:438-450`. The current shape keeps possession-as-proof that an id-keyed
   grant would lose. **Founder's call**, and it is the only remaining E11 pair.
2. **`role :Text` as an authority declaration (E11 ×4).** `contacts.capnp:219`
   `OrganizationName.role`, `content.capnp:341` `ContentRef.role`, `vcard.capnp:365`
   `VCardContact.role`, `vcard.capnp:507` `VCardOrganization.role`. All four are a *person's* job
   role (vCard ROLE / org role / a named content role), not an access-control declaration — the
   validator's field-name heuristic cannot tell them apart. The honest fix is either a false-
   positive list (as `AUTHORITY_FALSE_POSITIVES` already does for `Uri.authority`) or renaming the
   fields to something the authority vocabulary does not shadow (`jobTitle`, `personRole`).
   Batch E rejected renaming as dishonest. **Founder's call.**
3. **MFA/lockout consolidation into `access.capnp`** (batch E §3 item 5): three MFA challenge
   shapes and four lockout structs across `auth`/`access`/`biometric`. `access.capnp` is the KEEP
   file and owns the state machine; consolidating changes auth's and biometric's method
   signatures.
4. **crypto's enum-promotion alternative and `T.HashOutput`** (batch E §5 item 1 and §3 item 6):
   the open-token model is executed and awaiting ratification; `T.HashOutput` encodes `algorithm`
   as a `UInt16` ordinal of the enums crypto.capnp deleted, so adopting it would re-freeze
   algorithm identity. Foundation action: delete it, or re-declare it over open tokens.
5. **`T.TimeRange`'s unit** (batch C §3 item 3): `UInt64` milliseconds while `T.Timestamp` is
   nanoseconds, used by `timezone.capnp`. The field comment names the unit, so it is not a trap
   today; either align to nanoseconds or rename to state the unit. Not executed — a wire change
   for `timezone.capnp`.
6. **`T.LogLevel` still contains `crash`/`security`/`audit`** (batch A cross-batch item 14):
   daemon categories masquerading as severities, left because changing it is a wire change for
   five other files.
7. **`T.DmaHandle.direction :UInt8`** (batch A §5 item 3) — the last raw site; hal.capnp uses its
   own `DmaDirection` everywhere else.
8. **E7 (715) and E8 (267) residuals.** Both are documented REPORT debt with an over-broadth
   ruling behind them (verifier O4): E7 fires on closed record wrappers where Cap'n Proto's
   unknown-field rule already does the job, and E8 fires on event/result enums that are always
   written on the wire. Neither is a defect; both are noise the gate tolerates and enumerates.
9. **`display.capnp`'s `Monitor` vs compositor's `OutputInfo`** (batch D §2 item 11): an overlap,
   not a duplicate — two names for overlapping display facts. A boundary statement is owed.
10. **E10's 59 remaining findings**, of which four are documented in-batch retentions
    (`buffer.capnp`'s `TensorBufferInfo.shape`/`.strides`; `timezone.capnp`'s
    `TimezoneBusinessHours.workdays` and `RecurrenceRule.byDay`/`.byMonth`/`.byMonthDay`) — small
    dimension and vocabulary lists where the audit itself declines to force a handle. The rest are
    the same class (audio `sampleRates`/`channelPeaks`, sensor readings, gamepad state floats,
    print `pages`, font codepoints, access's credential pattern mask and MFA challenge payloads).

---

## 6. Verification output (verbatim)

### 6.1 `capnp compile -o- schema/*.capnp`

```
$ cd /home/lufuno/smart/smart-protocol-official && capnp compile -o- schema/*.capnp > /tmp/compile.out 2>/tmp/compile.err
exit=0
stderr bytes: 0
stdout bytes: 6123728
```

89 schemas, exit 0, no diagnostics on stderr.

### 6.2 `python3 scripts/validate.py`

```
$ python3 scripts/validate.py
Schemas parsed: 89 (88 besides ai.capnp)
E1 enums in ai.capnp            : 0
E2 bulk lists in ai.capnp       : 0
E4 interfaces unreachable (all) : 0 reported
E6 hits (all schemas)        : 0
E7 hits (all schemas)        : 715
E8 hits (all schemas)        : 267
E9 hits (all schemas)        : 0
E10 hits (all schemas)        : 59
E11 hits (all schemas)        : 6
E12 hits (all schemas)        : 0
E13 hits (all schemas)        : 0
E14 hits (all schemas)        : 0

--- REPORTED (not blocking, 1047) ---
  E10 access.capnp:337 CredentialValue.pattern :List(UInt8) — a list of machine words is a copied payload; bulk belongs in T.DataHandle
  … (1 047 lines, enumerated in full by the script)
PASSED — all enforced rules clean for schema/ai.capnp
```

exit code: **0**. Before this pass: `Schemas parsed: 89` · E6 31 · E7 728 · E8 270 · E10 59 ·
E11 6 · **E12 36** · **E13 1** · **E14 3** · 1 134 reported · exit 0.

### 6.3 Grep-check: same-name declarations across files

```
$ python3 - <<'PYEOF'
import re, os, collections
decls = collections.defaultdict(list)
for fn in sorted(os.listdir("schema")):
    if not fn.endswith(".capnp"): continue
    src = open("schema/"+fn).read()
    for m in re.finditer(r"^(struct|enum|interface)\s+(\w+)\s*(?:extends\s*\(?\s*[\w\.\s,]*\)?\s*)?\{", src, re.M):
        decls[m.group(2)].append((fn, src[:m.start()].count("\n")+1, m.group(1)))
dups = {k:v for k,v in decls.items() if len(v)>1}
print("names declared more than once:", len(dups))
PYEOF
names declared more than once: 0
  (none)
```

### 6.4 Grep-check: dangling imports

```
$ python3 - <<'PYEOF'
import re, os
files = {f for f in os.listdir("schema") if f.endswith(".capnp")}
bad=[]
for fn in sorted(files):
    for m in re.finditer(r'^using\s+(?:\w+\s*=\s*)?"([\w\-]+\.capnp)"', open("schema/"+fn).read(), re.M):
        if m.group(1) not in files: bad.append((fn, m.group(1)))
print("dangling imports:", bad if bad else "none")
print("total files:", len(files))
PYEOF
dangling imports: none
total files: 89
```

### 6.5 Doc claims re-verified against the tree

```
schemas: 89            interfaces: 303            total lines: 49 546
unknown arms: 153 in 47 schemas
T.DataHandle field/parameter positions: 353
StringMap field/parameter positions: 760
capability-gated root accessors: 34 in 24 schemas
per-file line counts in docs/SCHEMAS.md: 0 mismatches
```

---

*No commits were made. No file outside `smart-protocol-official/` was modified. `naledzi` was
read only, to write §4 precisely.*

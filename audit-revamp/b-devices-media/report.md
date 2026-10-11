# BATCH B REPORT — Devices & Media (19 schemas + gpu import)

Wave 2 rewriter, canonical tree `smart-protocol-official/`. Batch: device, display,
framebuffer, input, audio, camera, capture, sensor, usb, bluetooth, nfc, power,
location, media, font, print, console, screenlock, module — plus the `gpu.capnp`
import from `naledzi/protocol/schemas/gpu.capnp`.

Doctrine applied: `DESIGN_PRINCIPLES.md`, `docs/TIMELESSNESS.md`, gold standard
`schema/ai.capnp`, and the landed foundation (`types.capnp`, `capability.capnp`,
read as they now exist). Verdicts from
`audit-revamp/verification/audit-verification.md` (confirmed findings only; the five
OVERREACH items rejected) and `audit-revamp/verification/naledzi-delta-reconciliation.md`.

---

## 1. State found on entry + what I completed

**Pre-release carve-out is live:** nothing external consumes these schemas, so ordinals
were reissued freely and DELETE was preferred over deprecate-and-keep throughout.

### 1.1 What the timed-out attempt had already done (inventoried, verified — not re-done)

The previous attempt rewrote **16 of the 20 files** and imported `gpu.capnp`, but timed
out **before writing this report** (`report.md` did not exist on entry — confirmed).
Filesystem mtimes plus full reads showed:

- **Already imported & audited:** `gpu.capnp` (15,615 B naledzi original → rewritten to
  a vendor-agnostic contract; its three enums `GpuVendor`/`ShaderStage`/`BufferUsage`
  already converted to open `Text` tokens with documented vocab; its unreachable
  `GpuProvider` already given a `GpuService` root).
- **Already rewritten, verified correct:** input (KeyboardEvent + `InputEvent`
  closed-modality union with `keyboard @0 … custom @7 :Data` and a `pointer @1` arm),
  console (`writeBytes @46`/`pushInput @47` imported; `vc0`/`ttyS0`/`kmsg`/`TtyClass`/
  virtual-serial-remote console lexicon + `ConsolePermission`/`permissions :UInt32`
  deleted; capability-gated `openMultiplexer @48`), display (all 7 `Monitor` honesty
  fields + HONESTY RULE block), audio (`submit @0 (frames :T.DataHandle)`;
  `AudioTransport`→open `Text`), bluetooth (address schism fixed:
  `BluetoothDevice.address @0 :T.DeviceAddress` + `addressText @19 :Text`), sensor
  (`SensorInfo.type @3 :Text` open token; `SequenceToken`/`maxCount` bounded pull),
  camera+capture (frame-delivery contract), device (`getDriverRegistry @33` makes the
  driver framework reachable), module (`LoadSpec.capabilities @2 :List(Capability)`,
  command-exec hooks deleted), nfc (payments/loyalty/… trimmed, `openController @10`
  gated, `WifiCredentials.password` deleted), usb (`openHostProvider @19` /
  `openDeviceAdmin @20`), location (`attestGeoFence … key :T.KeyId`, no inline private
  key), font, framebuffer.
- **Left untouched (KEEP verdict, verify only):** `media.capnp`, `power.capnp`,
  `print.capnp`, `screenlock.capnp` (Aug-19 originals). `location.capnp` is also KEEP
  but carried its one mandated `privateKey`→handle fix.

### 1.2 What was unfinished — and what I completed

1. **`gpu.capnp` (E11 false-positive + redundant interface).** `interface Gpu3DProvider
   extends(GpuProvider)` tripped validator E11 (`GpuService.open3DProvider` returning
   it) because `find_blocks` cannot parse the `extends` clause. More importantly, the
   raw `submitCommandBuffer` path already confers arbitrary GPU work, so a second
   gated interface bought no privilege boundary. **Merged** the two 3D methods
   (`submitRenderCommandBuffer @21`, `uploadShader @22`) into `GpuProvider`, deleted
   `Gpu3DProvider` + `open3DProvider` — one accessor per service (ai.capnp precedent,
   verifier O1). E11 clear.
2. **`capture.capnp` (half-finished R3 gating + the B7 recording hole).** Sensitive
   capture methods sat **both** ungated on `CaptureService` **and** gated on
   `CaptureController`, and `CaptureService.stopRecording @4 -> (data :T.DataHandle)`
   still materialised a whole recording. **Finished:** `CaptureService` is now pure
   discovery + readback (`openCapture`) + one gated accessor (`openController`); all
   pixel-acquiring/persisting/sharing operations moved onto `CaptureController`;
   `stopRecording -> T.VoidResult` (read back via `FrameStream`); deleted the
   `CapturePermission`/`getCapturePermission`/`setCapturePermission` parallel model
   (verifier O1 deletion-half; a duration cap is a grant `constraint`, capability.capnp's
   job).
3. **Within-batch E12 duplicates (R6, one canonical home).** All resolved:
   - Unify true duplicates: `ThermalState` (device now `P.ThermalState`, its verbatim
     copy deleted → power is canonical, B13); `WatermarkRequest`/`WatermarkPosition`
     (camera uses capture's `C.WatermarkRequest`).
   - Domain-rename forks (verified zero cross-file references first): 
     `DeviceSubscription` (input→`InputDeviceSubscription`, bluetooth→`BluetoothDeviceSubscription`;
     device keeps `DeviceSubscription`), `DeviceKind` (input→`InputDeviceKind`),
     `ConnectionEvent`/`ConnectionSubscription` (bluetooth→`Bluetooth*`, display→`Display*`),
     `StateSubscription` (audio→`AudioStateSubscription`, bluetooth→`BluetoothStateSubscription`),
     `DisplayMode` (framebuffer→`FramebufferDisplayMode`), `IccProfile` (display→`DisplayIccProfile`).
4. **`display.capnp` E13.** The 7 imported honesty fields were declared mid-struct,
   out of ordinal order. Reordered to the struct tail (wire-neutral — Cap'n Proto keys
   on `@N`, not declaration order) with comments preserving the valid/qualified
   relationship. E13 clear.

---

## 2. Per-file change summary (rule/finding)

| file | action | change | justifying rule / finding |
|---|---|---|---|
| gpu | IMPORTED + audited | landed vendor-agnostic (enums→open tokens, DataHandle payloads, DataHandle bulk, opaque ids, `GpuService` root). **This pass:** merged 3D into `GpuProvider`, deleted `Gpu3DProvider`/`open3DProvider`. | IMPERATIVE-IMPORT (naledzi-delta); R1/R2/R5/R8 audit; E11 false-positive from `extends`. |
| capture | FIXED (finished) | frame-delivery contract (already present, kept); **finished** R3 gating, B7 `stopRecording`, deleted `CapturePermission`. | R3/§2.3/O1 deletion-half; B7 frame-delivery hole. |
| device | FIXED | driver framework reachable (`getDriverRegistry @33`); `ThermalState`→`P.ThermalState`. | R8/B22/B23/§2.2; R6/B13. |
| display | FIXED | 7 `Monitor` honesty fields + HONESTY RULE (verified); `IccProfile`→`DisplayIccProfile`; E13 field reorder. | delta import; R6; E13. |
| framebuffer | FIXED | `FramebufferEvent` unknown (verified); `DisplayMode`→`FramebufferDisplayMode`; SharedMemoryRegion pixels kept. | R7/B6/R6/E10-model. |
| input | FIXED | `KeyboardEvent` + closed-modality `InputEvent` union + `pointer` arm (verified); E12 domain renames. | B12; naledzi-delta input ruling (naledzi wins); R1. |
| audio | FIXED (verified) | `submit @0 (frames :T.DataHandle)`; `AudioTransport`→open `Text`; `StateSubscription`→`AudioStateSubscription`. | B1;B19/R5;R6. |
| camera | FIXED | frame-delivery via `C.FrameStream`; `stopRecording -> VoidResult` (verified); `WatermarkRequest`→`C.`. | B7 frame-delivery hole; R6. |
| sensor | FIXED (verified) | `SensorInfo.type @3 :Text` open token; `SequenceToken`/bounded `pull(maxCount, cursor)`; dead `permissionCapability` removed. | B9/R1; B8 offset-into-live-stream; R3. |
| usb | FIXED (verified) | `openHostProvider @19`/`openDeviceAdmin @20` gate the ungated methods; firmware now carries version/hash/signature. | R8/B22; §2.3. |
| bluetooth | FIXED | address schism closed (`T.DeviceAddress` + `addressText`); subscription/event renames. | B2; R6. |
| nfc | REWRITTEN | payments/loyalty/transit/EV/identity/WiFi/crypto trimmed or gated; password deleted; `openController @10`. | B15; R3/R5. |
| module | FIXED (verified) | `LoadSpec.capabilities @2 :List(Capability)`; command-exec lifecycle hooks deleted. | B17; R3. |
| console | FIXED (verified) | `writeBytes @46`/`pushInput @47` imported; Linux tty PC-isms deleted; `ConsolePermission`/`permissions :UInt32`→capability; `openMultiplexer @48`. | delta console import; B14/B16; R3/R8. |
| font | FIXED (verified) | `FontWidth`/`FontStretch` split, weight unified, `Font` deprecated-path, session-scoped setters. | font audit. |
| location | FIXED (verified) | `attestGeoFence … key :T.KeyId` (private key no longer inline). | R3/mandate. |
| power | KEPT (verify only) | `ThermalState` now the single canonical home (referenced by device). Ungated `shutdown`/`reboot` noted, not touched. | KEEP ruling. |
| media | KEPT (verify only) | `PlayerEvent` missing `unknown` + error-less paths — CONFIRMED but deferred (see §5). | KEEP ruling; B6/top-10#7. |
| print | KEPT (verify only) | `PrintRange.pages` unbounded, `PrintTransport` vendor-ish nouns, Float32 money noted. | KEEP ruling; audit. |
| screenlock | KEPT (verify only) | UnlockCredential conflict already resolved (session imports screenlock's); ungated lock-policy setters noted. | KEEP ruling; B4. |

---

## 3. Cross-batch items (exact file + recommended action; NOT fixed here — other batches own the other side)

- **gpu R5 driver migration (naledzi, not schema):** `uspace/servers/gpu-intel/src/
  main.rs:1020,1040` uses `gpu_capnp::GpuVendor::Intel`. The canonical file's R5 fix
  turned `GpuVendor` into a `Text` token, so the driver must become
  `set_vendor("intel")`. One-line change in the naledzi build consumer.
- **E12 forks with a non-B batch on the other side** (my R6 renames cleared only the
  wholly-in-batch pairs). Each needs the owning batch (or a types.capnp promotion) to
  converge:
  - `KeyAction` compositor.capnp:1041 ↔ input.capnp:352
  - `DeviceFilter` device.capnp:148 / input.capnp:207 ↔ storage.capnp:779 (3-way)
  - `SpatialPose` compositor.capnp:737 / input.capnp:595 ↔ location.capnp:226 (3-way — recommend types home or compositor-canonical)
  - `BiometricTemplate` biometric.capnp:244 ↔ input.capnp:387
  - `EventSubscription` accessibility.capnp:219 ↔ usb.capnp:503
  - `RetentionPolicy` backup.capnp:227 / files.capnp:720 ↔ capture.capnp:416 (3-way)
  - `DiscoverySubscription` discovery.capnp:330 ↔ nfc.capnp:413
  - `AccessibilityRole` accessibility.capnp:487 ↔ console.capnp:598
  - `OutputMode` compositor.capnp:816 ↔ console.capnp:176
  - `KeyValue` database.capnp:268 ↔ framebuffer.capnp:106
  - `Session` (6 files incl. screenlock.capnp:37) — doctrine accepts per-domain sessions; recommend rename-for-clarity per DESIGN_PRINCIPLES.md:213.
- **`UnlockCredential` home — DECIDED: `screenlock.capnp` is canonical.** Verifier B4
  confirms a single definition at screenlock.capnp:140 consumed by session.capnp. This
  is already the state; no change. (Foundation/verifier tension noted and resolved in
  favour of the credential domain.)
- **`BatteryState`/`MountOptions`/`Language`/`ModifierState`**: per audit §2.2, Language/
  ModifierState/SignalKind already resolved in types.capnp and `BatteryState` is
  canonical in power.capnp — no action. `MountOptions` remains a triplicate in
  batch C (filesystem/mount/files) — batch C's item.

---

## 4. Verification results

**`scripts/validate.py` (read-only), final snapshot — verbatim output:**

```
Schemas parsed: 89
E1 enums in ai.capnp            : 0
E2 bulk lists in ai.capnp       : 0
E4 interfaces unreachable (all) : 0 reported
E9 hits (all schemas)        : 7
E10 hits (all schemas)       : 71
E11 hits (all schemas)       : 6
E12 hits (all schemas)       : 67
E13 hits (all schemas)       : 8
PASSED — all enforced rules clean for schema/ai.capnp
```

The E9–E13 totals are **tree-wide and live**: other wave agents are concurrently editing
/deleting siblings (foundation/kernel, network/storage, security/intelligence all show
recent mtimes), so those totals drift between runs and are not attributable to batch B.
Scoped to my 20 files:

- **E9 = 0, E11 = 0, E13 = 0, E14 = 0** in every batch file (platform nouns, authority
  model, ordinal order, reachability all clean). The prior E11 was gpu's `extends`
  artifact (fixed); the prior E13 was display's imported-field ordering (fixed).
- **E12 within-batch = 0** (ThermalState/Watermark/DeviceKind/DeviceSubscription/
  Connection*/StateSubscription/DisplayMode/IccProfile all resolved); the remaining E12
  lines touching my files are cross-batch (§3).
- **E10 (71 victims reported tree-wide):** the `X.payload :Data` hits are the
  doctrine-correct opaque unknown-event carriers (the accepted template, cf.
  TIMELESSNESS.md:127); the remaining are small/bounded lists the audit's "honest note
  on what NOT to do" explicitly declines to convert (audio `sampleRates`/`channelPeaks`,
  sensor 12-byte readings + calibration coeffs, gamepad state floats, power
  `balancingCells`, print `pages`, font codepoints). Per B21/O4, leaving these is
  correct; forcing them onto `T.DataHandle` would add a mapping step and no copying
  saving.
- **E6 (31 in-batch):** almost all are `{ok, error}` / `{frames, empty, ended, error}`
  RESULT unions whose `error` arm IS the extension point (ai.capnp's own pattern).
  These are a too-narrow E6-exemption false-positive (see foundation note §5f).
- **E7 (291) / E8 (158) in-batch:** the two broad REPORT rules; E8 sentinel scope was
  intentionally limited to filter/request/optional-field enums per verifier O4. Not
  re-litigated here.

**Compile check:** `capnp compile` succeeds on all 20 batch files (gpu + 19).

---

## 5. Founder-decision items

a. **media `PlayerEvent` R7 gap (deferred, recommend follow-up).** Verifier B6 and
   top-10 #7 both confirm `media.capnp`'s event unions lack `unknown` and read/analytics
   paths swallow failures. media is under the KEEP "no churn" ruling, so I left it; this
   is the one confirmed finding deliberately parked and should be closed in a follow-up
   (add `unknown @N :T.UnknownEvent` + `T.Error` result arms). ~10 lines.

b. **console `writeBytes @46 (data :Data)` unbounded.** naledzi-delta mandated importing
   it verbatim (it is the TUI/SSH hot path and lives in the shipped console server). The
   delta verifier also notes the unbounded-write family is now 3. Backpressure/chunking
   is deferred; converting to `T.DataHandle` would diverge from the "import verbatim"
   ruling and chain buffers for marginal small-terminal writes.

c. **capture Audit-9 machinery relocated, not trimmed.** With R3 gating finished, the
   scheduling/session/analysis/annotation/comparison/pipeline surface moved onto the
   gated `CaptureController` rather than `CaptureService`. capture.capnp has **zero**
   naledzi consumers today (grep-confirmed), so it is dead surface; a future pass could
   delete the most speculative halves. I preserved them (gate-only) to avoid over-cutting
   beyond the confirmed mandate.

d. **`Monitor.edid @32 :Data` inline vs `getEdidData @63 :T.DataHandle`** — two EDID
   channels. The inline field is a bounded (~128-512 B) convenience kept from the verbatim
   import; recommend documenting that `getEdidData` is the canonical read and `edid` a
   snapshot, or converging on one. Minor.

e. **nfc NDEF/APDU payloads** (`NdefRecord.payload`, `ApduCommand.data`,
   `ApduResponse.data` :Data) can carry multi-KB NDEF records — genuine (if modest)
   R2 candidates. The REWRITE prioritised scope/authority; converting these to
   `T.DataHandle` is deferred.

f. **Foundation/validator notes (batch A owns the validator).** (i) `find_blocks`
   cannot parse `interface X extends(Y) {`, so any interface inheritance spins up a false
   E11/E13 — worth teaching it the `extends` clause or documenting the no-inheritance
   convention. (ii) the E6 exemption list is only `{VoidResult, BoolResult, DataHandle}`,
   so every `{ok, error}` result union is flagged though the `error` arm is the extension
   point — consider exempting any union whose non-success arm is `T.Error`. Both are
   REPORT-only and do not affect the green gate.

g. **`T.KeyCode.code :UInt32` has no published domain (B10).** This lives in
   `types.capnp` (foundation) and is used by `input.emulateKey @27`/`KeyTrigger.key`;
   the fix is a published value-space mapping documented in the header, not an enum.
   Foundation item.

---

## 6. Deferred work

- media `PlayerEvent` unknown + error paths (§5a) — highest-value single KEEP file gap.
- print `PrintRange.pages` bound + `PrintTransport` open tokens + Float32 money →
  `T.FiatAmount`; screenlock ungated lock-policy setters; power ungated `shutdown`/
  `reboot` (consult `T.InhibitHandle`) — all per KEEP ruling, no churn now.
- Cross-batch E12 unifications (§3) once owning batches land.
- nfc payload envelopes + console write backpressure (§5b/e).
- E7/E8 residue: struct extension points and the residual enum `@0` sentinels on
  non-filter enums (O4 scope).
- gpu-intel driver `set_vendor("intel")` migration on the naledzi side (§3).

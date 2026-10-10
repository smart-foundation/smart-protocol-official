# BATCH SUMMARY — Devices & Media (schemas 1-19)

Audit of `device, display, framebuffer, input, audio, camera, capture, sensor, usb, bluetooth, nfc, power, location, media, font, print, console, screenlock, module` against `DESIGN_PRINCIPLES.md`, `docs/TIMELESSNESS.md`, `schema/ai.capnp` (gold standard), `schema/types.capnp` and `schema/capability.capnp`.

**Method note.** No builds were run (per instructions). Wire-breakers were verified by (a) reading every assigned schema in full, and (b) a mechanical scan of all 19 files for repeated field/method ordinals within the same struct/enum/interface (comments excluded) — **zero ordinal collisions were found**, including the reported `AuracastBroadcast.name @1` vs `deviceAddress @1`, which **does not exist** in the current revision (`name` is @1, `deviceAddress` is @2 — bluetooth.capnp:310, 312). Undefined references were verified by grep across the whole schema set (e.g. `DisplayModeFlags`, referenced only from a comment at display.capnp:873). No schema was modified.

---

## 1. Verdict table (all 19)

| schema | verdict | one-line justification |
|---|---|---|
| device | FIX (targeted) | Exemplary core (opaque typed ids, pagination, open `properties` bag) damaged by an Audit-8 graft that duplicated thermal/power/handoff/notification/mesh contracts and introduced three UInt32 id spaces. |
| display | FIX (targeted) | Well-built monitor contract, but three parallel vocabularies (colour space, refresh rate, DPMS), `writeConsoleText → ()` swallowing errors, and `testChanges` with an implicit shared pending configuration. |
| framebuffer | FIX (targeted) | The batch's model zero-copy design (`SharedMemoryRegion` pixels) with a structurally empty atomic contract (`testAtomic @4 ()`, `commitAtomic @5 ()` — no input) and a missing `unknown` on `FramebufferEvent`. |
| input | FIX (targeted) | Strong extended-modality block, but `T.KeyCode.code :UInt32` has no published domain and **the key/pointer event path does not exist at all**. |
| audio | FIX (targeted) | The batch's worst R2 trap (`submit (frames :Data)` on the driver boundary) plus `alsa`/`pulseAudio`/`pipewire` in `AudioTransport` and a 32-value `CodecFamily`. Highest-value file in the batch. |
| camera | FIX (targeted) | Right payload discipline, but **no frame-delivery contract** and `stopRecording` returns an entire recording as one `DataHandle`; `PhotoFormat.raw` vs `RawColorSpace` conflation. |
| capture | FIX (targeted) | Correct one-shot `T.DataHandle` captures, but `startStream` returns an id with no reader, permission flags instead of capabilities, and an unbounded `pull` alongside a paginated one. |
| sensor | FIX (targeted) | Right batching/idle machinery, but `SensorType` (44 values) is closed by release schedules, **six Audit-7 data types are unreachable**, and `pull(pagination)` offsets into a live stream. |
| usb | FIX (targeted) | Honest header and correct `T.DataHandle` descriptor handling, undermined by a filesystem.capnp dependency landmine, `maxSpeed :UsbSpeed` that cannot state USB4 speeds, and an unreachable host-controller API. |
| bluetooth | FIX (targeted) | **The address-type schism** (`T.DeviceAddress` UInt64 in every method vs `Text` MAC in the descriptor) makes scan results unusable; profile/codec enums are closed by SIG release schedules. |
| nfc | REWRITE (scope) | An NFC transport schema that became payments + loyalty + transit + EV-charging + identity + Wi-Fi-share + crypto, with an ungated payment path and a plaintext Wi-Fi password field. |
| power | KEEP (targeted) | The best schema in the batch (typed physical quantities, no bulk payloads); only a verbatim `ThermalState` duplicate, five power-state vocabularies, and an ungated `shutdown` need fixing. |
| location | KEEP (targeted) | Small, unit-documented, exemplary altitude/WGS84 handling; `privateKey :Data` in a request and an unreadable `T.LocationSourceId` are the two real defects. |
| media | KEEP (targeted) | Correct `T.DataHandle` artwork; the only missing `unknown` union in the batch's event set, five error-less failure paths, and a dead transcode-progress contract. |
| font | FIX (targeted) | `FontWidth` ≡ `FontStretch` verbatim, `FontStyle.weight :UInt16` vs `FontDescriptor.weight :FontWeight`, a legacy `Font` interface never deprecated, and global unscoped settings on a per-session service. |
| print | KEEP (targeted) | Passes R2 outright (`T.DataHandle` source and ICC data); `PrintTransport` vendor nouns, `PageSize`'s dual coordinate systems and Float32 money are the real defects. |
| console | FIX (targeted) | A timeless Audit-7 half (voice/braille/spatial/haptic consoles) contradicted by a v0.0.2 half that hard-codes Linux's `vc0..vcN`/`ttyS0`/SSH/IPMI console architecture; `permissions :UInt32` has no bit assignment. |
| screenlock | KEEP (targeted) | The flagged `UnlockCredential` conflict is **already resolved** (single definition, imported by session.capnp); the residual duplicates are lock/unlock + idle vs session.capnp. |
| module | FIX (targeted, trim) | Sound loader core undermined by `capabilities :List(Text)` (permission strings), a `command :List(Text)` execution hook, and marketplace/feature-flag/tenancy product machinery. |

**Summary counts:** KEEP (targeted) 3 · KEEP-with-fixes 2 · FIX (targeted) 13 · REWRITE 1 · MERGE/DELETE 0.
**Wire-breakers (compile-level):** none anywhere. All findings are semantic, wire-*behavioural*, or doctrine-level.

---

## 2. Cross-schema findings

### 2.1 The same defect repeated across files (fix once, benefit N)

**(a) Pagination applied to a live stream — silently drops data.** `T.Pagination {offset, limit}` (types.capnp:248) is an offset into a *stable list*. Used on live subscriptions:
- `sensor.capnp:238, 242` — `SensorSubscription.pull (pagination)`, `BatchSubscription.pull (pagination)`
- `capture.capnp:107` — `pullPaginated @2 (pagination)`
- `usb.capnp:449` — `pullPaged @2 (pagination)`
- `camera.capnp:99` — `pullPaginated @2 (pagination)`
- `capability.capnp:401` — `pullPaginated @2 (pagination)` (the origin of the pattern)

The bound is wanted; the offset is meaningless on a stream that has no stable ordering. A 2046 consumer that passes `offset=5` either loses the first 5 readings or gets 5 that were already delivered. The correct primitive already exists in ai.capnp:277 (`pull (maxBytes :UInt32)`). **Fix once in types.capnp** by adding a max-count pull parameter (or a `T.StreamPage {maxCount, sequence}`) and repointing these nine sites. This is the single cheapest batch-wide repair.

**(b) Unbounded `pull` alongside a paginated one, on the same interface.** `capture.capnp:104` + `107`, `usb.capnp:443` + `449`, `camera.capnp:96` + `99`, `capability.capnp:398` + `401`: two pull paths, one of which grows the server's queue without limit and returns an arbitrarily large message. Prefer one bounded pull with `T.SubscriptionResult` (types.capnp:907) semantics.

**(c) Unions missing `unknown`/`UnknownEvent`.** `framebuffer.capnp:357` (`FramebufferEvent`), `capture.capnp:160` (`CaptureEvent`), `camera.capnp:235` (`CameraEvent`), `media.capnp:140` (`PlayerEvent` — the only one in the batch's event set with *no* variant at all), `module.capnp:224` (`ModuleEvent`), `usb.capnp:453` (`UsbEvent`), `console.capnp:714` (`custom @5 :Void` — no typeId/payload). Conversely, `ai.capnp:533-536`, `screenlock.capnp:209-212` and `font.capnp:553-556` have the exact right shape — those three are the template. TIMELESSNESS.md:98 makes this mandatory and the validator's E-rules (E1 enums, E2 bulk, E3 capability) **do not cover it**, which is why 8 schemas drifted.

**(d) "Dual subscription path" — `pull` on the service *and* `pull` on the subscription.** device.capnp:208, display.capnp:81, input.capnp:23/28/34/40/44/77/89, audio.capnp:50/54/58/81/152/184, location.capnp:65, sensor.capnp:174, console.capnp (next/cancel variant). DESIGN_PRINCIPLES.md:254 blesses this as "convenience" but never states whether both paths read the *same queue*; a 2046 implementer must either duplicate the queue or make one path silently return empty. One sentence in the template would remove it.

**(e) Raw `UInt32` bitmasks with an adjacent enum that defines no bit assignment.** `console.capnp:651` (+ `ConsolePermission` 654), `usb.capnp:404` (`workaroundFlags`), `framebuffer.capnp`/`display.capnp` `AdaptiveSyncCaps.variant @1 :UInt8`. Each has a vocabulary struct/enum sitting next to it that fails to say what the bits mean. Fix: `List(Enum)`.

**(f) Global, session-unscoped setters.** font.capnp:33/35/30/32 (hinting, accessibility, cache, fallback chain) on a service whose handshake says "One session per application"; location.capnp:74/92/95 (accuracy, privacy, zone) globally; device.capnp:272 (policy); input.capnp:106 (coordination). Each is last-writer-wins across all clients, on shared hardware. The `FontSession` handshake structure is the right idea; the setters were never scoped to it.

**(g) `unknown` vs `custom` sibling variants.** framebuffer.capnp (EotfTransfer, FramebufferColorSpace, SyncMode, SubpixelLayout, BlendFactor, FramebufferKind, PassthroughMode), display.capnp (DpmsState, HdrStandard, PqMode, FoldState, ColorSpace, …), device.capnp, print.capnp, console.capnp: many enums carry **both** `other @n` and `custom @n` with no rule. ai.capnp's answer (ai.capnp:43-47) is a single rule: *unknown values are ignored, never rejected*.

### 2.2 Duplicates that span schemas (verified with line cites)

| Concept | Duplications (file:line) | Canonical home |
|---|---|---|
| **Thermal state** | power.capnp:171 ≡ device.capnp:368 (**verbatim, 5 identical values**) | power.capnp |
| **Power state** | power.capnp:7 `PowerState` · power.capnp:272 `SleepState` · types.capnp:2140 `T.PowerSleepState` · device.capnp:360 `PowerMode` · console.capnp:568 `ConsolePowerMode` · framebuffer.capnp:558 `DpmsState` ≡ display.capnp:359 `DpmsState` | types.capnp (`T.PowerSleepState` + a lifecycle enum) |
| **Colour space** | types.capnp:845 `T.ColorSpace` · display.capnp:383 `ColorSpace` · framebuffer.capnp:395 `FramebufferColorSpace` · print.capnp:302 `PrintColorSpace` | types.capnp |
| **Rendering intent** | display.capnp:550 · framebuffer.capnp:524 · print.capnp:312 | types.capnp |
| **Refresh rate** | display.capnp:114/115/216 + `DisplayMode.refreshRatex100` · framebuffer.capnp:187/419-421/535 · display.capnp:355-356 · display.capnp:652-653 · `T.Frequency` (types.capnp:788) — **6 encodings** | `T.Frequency` |
| **Rotation** | `T.SurfaceTransform` (types.capnp:318) · `T.BufferTransform` (types.capnp:331) · framebuffer.capnp:567 `DisplayRotation` · print.capnp:221 `Orientation` · display.capnp:99 `setRotation` uses `T.SurfaceTransform` | `T.SurfaceTransform` |
| **Gesture** | types.capnp:358 `T.TouchGesture` · input.capnp:381 `GestureKind` (25 values) · display.capnp:799 `GestureType` | types.capnp |
| **Channel layout** | audio.capnp:426 `ChannelMode` + audio.capnp:779 `ChannelLayout` + 4 `Text` fields (audio.capnp:329/244/854/854) · bluetooth.capnp:263 `AudioChannelMode` — **6 representations** | audio.capnp:779 |
| **Device / input capability** | input.capnp:164 `DeviceKind` (25) · input.capnp:665 `InputCapability` (17) · input.capnp:199 `requireCapabilities :List(Text)` | input.capnp (one enum) |
| **Biometric modality** | sensor.capnp:404 · input.capnp:349 · biometric.capnp (owner) | biometric.capnp |
| **Watermark** | capture.capnp:203-217 ≡ camera.capnp:291-305 (**verbatim struct + enum**) | capture.capnp (or types.capnp) |
| **Calibration** | camera.capnp:418 `CalibrationStatus` (enum) · display.capnp:690 `CalibrationStatus` (**same name, struct**) · sensor.capnp:306 `SensorCalibration` · display.capnp:200 `startCalibration` · print.capnp: none | types.capnp |
| **ICC profile** | display.capnp:536 `IccProfile` · print.capnp:345 `IccProfile` (**same name, different id type and colour enum**) | types.capnp |
| **Battery level** | power.capnp:88 `percentage :UInt32` (0-100) · device.capnp:353 `batteryLevel :Float32` (0-1, `-1.0`=unknown) · input.capnp:157 `batteryPercent :UInt16` (0-100, `0xFFFF`=unknown) | power.capnp (`BatteryState`) |
| **Geolocation** | `T.GeoCoordinate` (types.capnp:1441) · camera.capnp:494-496 · capture.capnp:465-466 · display.capnp:704-705 · display.capnp:660 (`T.Vec2`) · location.capnp:247-248/253 | types.capnp |
| **Money** | print.capnp:283-284 & 323-324 · nfc.capnp:241-244, 300-302, 193-196 · `T.FiatAmount` exists (types.capnp:1372) | types.capnp |
| **Firmware** | device.capnp:404 `DeviceFirmwareInfo` · usb.capnp:81 `queryFirmwareVersion → Text` · camera.capnp:518 `firmwareVersion :Text` · `T.FirmwareId`/`T.Version` | types.capnp (`T.Version`) |
| **USB Power Delivery** | power.capnp:50/290 `negotiateUsbPd`/`UsbPdContract` · usb.capnp:45/209 `getPowerDelivery`/`UsbPowerDelivery` · usb.capnp:74 `initiatePdNegotiation` | usb.capnp |
| **Wireless charging** | power.capnp:14/304 · nfc.capnp:24/214 | power.capnp |
| **`MountOptions`** (prior offender) | filesystem.capnp:166 · mount.capnp:163 · filesystem.capnp:583 `FsMountOptions` — **still a live triplicate**; usb.capnp:32 imports filesystem.capnp's copy | mount.capnp (and filesystem.capnp is slated for deletion per DESIGN_PRINCIPLES.md:213) |
| **`IpAddress`** (prior offender) | types.capnp:745 · dns.capnp:616 — **still duplicated** | types.capnp |
| **`Language`, `ModifierState`, `SignalKind`, `BatteryState`** (prior offenders) | **resolved**: single canonical definitions (types.capnp:678, 170, 512; power.capnp:85) | types.capnp / power.capnp — no action |
| **`T.BluetoothAddress`** | types.capnp:768 — **dead**: no schema uses it, while bluetooth.capnp uses `Text` for the same value | bluetooth.capnp should adopt it |
| **`Session` interfaces** | session.capnp:35 · screenlock.capnp:37 (**identical name**) + compositor/shell/ime/buffer/windowmanager (DESIGN_PRINCIPLES.md:213) → now **eight** | keep per-domain, but rename for clarity |

### 2.3 The capability gap is the batch's dominant structural fault

DESIGN_PRINCIPLES.md:399 — "Do NOT define permission strings, boolean flags, or role-based access control in the protocol. The capability system IS the access control mechanism" — and ai.capnp:578-584 (gated accessors, ungated discovery) are violated across 12 of 19 schemas, always in the same shape (authority by name string, boolean flag, or absent gate):

- `sensor.capnp:104` `permissionCapability :Text` — a capability *name* in a discovery struct, with no method that accepts a `Capability` (a dead end).
- `module.capnp:121` `LoadSpec.capabilities :List(Text)` — the authority granted to a loaded module, as strings.
- `capture.capnp:353-365` `CapturePermission {screenAllowed, windowAllowed, audioAllowed, allowedSources}` — and `setCapturePermission @26` lets a client set *another app's* permission.
- `audio.capnp:1030-1041` `MicPolicy {blockedApps, trustedApps}`.
- `device.capnp:445` `DevicePolicy {allowedActions, deniedActions}`; `device.capnp:233` `notifyDevice`, `:267` `updateFirmware`, `:272` `setDevicePolicy` ungated.
- `input.capnp:325` `KeyAction.runCommand :Text` and `module.capnp:364` `ModuleLifecycleHook.command :List(Text)` — two unauthenticated command-execution paths (ai.capnp:324-327 removed exactly this from `ToolRegistry.invoke`).
- `location.capnp:101` `attestGeoFence (… privateKey :Data)` — a private key in a request body.
- `nfc.capnp:25-26` `startPayment`/`getPaymentSession` ungated, plus `WifiCredentials.password :Text` (nfc.capnp:447) and `PaymentSession.token :Data` (nfc.capnp:246) as secrets with no authority gate.
- `usb.capnp:39/68/82` `authorizeDevice`/`setDeviceQuirks`/`updateFirmware` ungated; `usb.capnp:82` firmware flashing with **no version, hash or signature field**.
- `camera.capnp:32-92` no consent model at all, while audio.capnp has mic consent and capture.capnp has capture permission — three incompatible consent models, and the camera (the most sensitive) has none.
- `screenlock.capnp:62` `unlock` and the lock-policy setters ungated.
- `power.capnp:34-37` `shutdown`/`reboot` ungated, with the protocol's `T.InhibitHandle` concept never consulted.

### 2.4 Zero-copy failures (R2) — the batch's highest-volume data

| file:line | payload | copy cost it forces |
|---|---|---|
| **audio.capnp:892** | `AudioDriverStream.submit (frames :Data)` — the driver boundary | 48 kHz stereo s16 = 192 KB/s per stream; a 10 ms buffer = 1,920 bytes → **100 submits/s/stream**, each copying into the message arena and again into the driver ring. The dominant CPU and idle-power cost of audio. Fix: `T.DataHandle` (the file's own `HrtfData.impulseData @817` already does this). |
| **camera.capnp:38** | `stopRecording → (data :T.DataHandle)` | A 4K60 30-min clip ≈ 22 GB returned as one unit, with no partial read. |
| **capture.capnp:34** | same, on recordings | The capture service must buffer an entire recording until the client pulls. |
| **console.capnp:406/546** | `playback → List(InputEvent)` unbounded | A whole session replayed in one message. |
| **console.capnp:359** | `writeText (text :Text)` unbounded | A 10 MB `cat` copied per call. |
| **display.capnp:243** | `writeConsoleText (text :Text) -> ()` | Unbounded text, and the result swallows every failure. |
| **input.capnp:236-238** | `GamepadState.values :List(Float32)`, `buttonsBool :List(Bool)`, `hats :List(Int32)` | ~28 values + 3 lists copied per pull per device at 250 Hz (≈7,000 copies/s/controller), with the *entire* gamepad fleet shipped per pull. The file's own comment ("Zero-cost: inline structs, no heap", input.capapnp:426) is the inverse of the truth for messages. |
| **sensor.capnp:375** | `SpectrometerData.spectralData :List(Float32)` | 2048 bins × 4 B = 8 KB per reading, at up to 100 Hz ≈ **800 KB/s inline** — and the type is unreachable, so today it arrives as an untyped list. |
| **font.capnp:386-391** | `OpenTypeInfo.tables/scriptTags/featureTags :List(Text)` embedded in every `FontFaceEntry` | Thousands of tag strings copied per font-match query. |
| **media.capnp:202-203** | `lyrics.lines :List(LyricLine)`, `chapters :List(Chapter)` inside `MediaMetadata` | Re-shipped on every `getMetadata`/`listPlayers`; grows with content length (an audiobook has hundreds of chapters). |
| **nfc.capnp:553-554** | `encryptPeerMessage (data :Data) → (encryptedData :Data)` | Whole payload in and whole ciphertext out, with no algorithm field. |
| **print.capnp:190** | **correct** — `PrintRequest.source :T.DataHandle` | — (no finding) |
| **framebuffer.capnp:63/103** | **correct** — `SharedMemoryRegion` for pixels | — (the batch's model) |
| **audio.capnp:817, display.capnp:539, camera.capnp:36, font.capnp:779, print.capnp:349** | **correct** — `T.DataHandle` / ICC / photo / subset / profile | — |

**Polling-forcing patterns (eco/zero-waste):** audio.capnp:46-47/67-68 (metering and device analysis have no subscription — a level meter polls 30-60 Hz forever); sensor.capnp:11-13 (`getGnssFix`/`getAirQuality`/`getFallDetection` are id-less singletons that may wake the GNSS radio per poll); location.capnp:63/107 (no coalescing or distance threshold on the location subscription); print.capnp:12/27 (job and consumable status polled); power.capnp:11/15/17/20/21/27 (charging, grid, PoE, fuel-gauge, cell-balancing, thermal-risk polled); camera.capnp:19/21/23/27/29/32 (six per-camera getters that keep the camera pipeline warm); device.capnp:10/27/32 (history, resource usage, policy polled). Every one of these is repairable with the schema's *own* existing subscription pattern — no new machinery.

**Idle-power:** no coalescing rule on any of the batch's ~30 subscription interfaces; display.capnp's four per-output subscriptions and power.capnp's `BatterySubscription` (1 %-granularity) can wake a client hundreds of times per charge cycle.

### 2.5 Reachability (R8): the driver-provider framework has no entry point anywhere

Verified by grep: nothing in the protocol returns any of these interfaces.
- `audio.capnp:835` `interface AudioProvider` (+ `AudioDriverStream` :888, `AudioProviderCaps`, `StreamConfig`, `StreamDirection`, `LatencyClass`)
- `display.capnp:839` `interface DisplayProvider` (+ `ConnectionSubscription`, `ConnectionEvent`, `ModeSpec`, `DisplayMetadata`, `ConnectionStatus`)
- `usb.capnp:496` `interface UsbHostProvider` (+ 8 more types: `UsbTopoNode`, `UsbHubInfo`, `UsbTransferDirection`, `UsbTransferCompletion`, `VoidOpResult`, `UsbTopologySubscription`, `UsbTopologyEvent`, `UsbSpeedChange`)

So the entire "v0.0.2 provider" contract (audio, display, usb) is dead: a driver author following the schema implements ~40 types that no client can call, while the `DriverRegistry`/`DriverLifecycle` framework in device.capnp:492-557 is reachable but never returns a provider. **One fix benefits all three schemas**: a root accessor (`getProvider (authority :Capability, class :T.DriverClass) -> …`).

Also unreachable *types* (no method references them): `sensor.capnp:319/341/372/380/388/364` (`SpatialSensor`, `GestureSensor`, `SpectrometerData`, `GasSensorData`, `RadiationSensorData`, `ContextSnapshot`), `capture.capnp:234/252/432/457` (`CaptureStream`, `CaptureDeduplication`, `CompressionOptions`, `CaptureDeviceMetadata`), `power.capnp:262/272/339` (`IgnitionState`, `SleepState`, `SolarInfo`), `media.capnp:258` (`LiveStream`), `font.capnp:685` (`VariationSettings`), `bluetooth.capnp:414` (`PairingEvent`), `camera.capnp:344` (`CaptureTrigger`), `usb.capnp:359` (`ThunderboltTunnel` referenced only by `Usb4Router.tunnels`, itself only in the unreachable provider).

### 2.6 Contradictions with the doctrine documents themselves

1. **DESIGN_PRINCIPLES.md:165, :464 and :530 are stale.** They claim `AudioDevice.id` is `:Text` and "should be opaque UInt64 or Data", and list audio.capnp as "Acceptable (No Changes Needed): Device ID should be UInt64 but Text is acceptable." The current schema already uses `T.AudioDeviceId` (audio.capnp:235). The fix has landed; the doctrine was never updated — and while the verdict table calls audio.capnp clean, this audit finds ~21 enums and the batch's single worst zero-copy trap in it.
2. **DESIGN_PRINCIPLES.md:452-454 (the Swap Test) fails on its own evidence for audio and input.** The PipeWire→Rust-server swap is marked ✅ with "the protocol sees endpoints and streams" — but `AudioTransport` names `pulseAudio`, `alsa` and `pipewire` (audio.capnp:768-771, which TIMELESSNESS.md:25 explicitly rejects as an implementation detail), and the stream path is `AudioDriverStream`, which nothing returns. The X11→Wayland→compositor swap is marked ✅ with "compositor.capnp defines surfaces, commits, input events" — but input.capnp has **no key or pointer event contract at all** (input.capnp:88-89 carries only eye-tracking/brain/spatial/crown/cabin events), so a compositor cannot be built against the protocol.
3. **DESIGN_PRINCIPLES.md:480-482 and TIMELESSNESS.md's Principle 4 claim "App needs to discover hardware — ✅ `hal.capnp`, `device.capnp` — No gap."** The actual discovery path for drivers is unreachable (§2.5), and hotplug semantics (ordering vs `list`, whether a device that appears and disappears between pulls yields both events) are undefined. A "no gap" verdict where the primary path is unbuildable.
4. **TIMELESSNESS.md:98 mandates `unknown @N :UnknownEvent` on every union**, and DESIGN_PRINCIPLES.md:342 restates it — but the validator rules described in ai.capnp's header (E1 zero enums, E2 bulk payloads, E3 capability) **do not enforce it**, which is exactly why 8 unions in this batch lack it (framebuffer, capture, camera, media, module, usb, console, plus `console.capnp:714`'s useless `custom :Void`).
5. **DESIGN_PRINCIPLES.md:342 says "Every union type should have an `unknown` or `custom` variant"** — a weaker requirement than TIMELESSNESS's, satisfied by a `custom :Void` that carries no typeId or payload (console.capnp:721). The two doctrine documents disagree; the stricter one is correct.
6. **DESIGN_PRINCIPLES.md:254-255 blesses the dual subscription pattern** ("`pull @3 (subscription :…)` — Pull events from a subscription (convenience — canonical pull is on subscription interface)") without stating that both paths must read the same queue, then flags the stream-based variant as a defect. Nine schemas implement both; the "convenience" is the more common defect because it silently permits two divergent event streams.
7. **The doctrine has no verdict for 11 of the 19 schemas in this batch** (camera, capture, sensor, usb, bluetooth, nfc, font, print, console, screenlock, media, location, module are absent from Appendix 6 entirely), and its "Acceptable / No Changes Needed" table marks display, input, power and audio as clean — this audit finds real defects in all four, and power (the cleanest file here) still carries a verbatim duplicate enum.
8. **DESIGN_PRINCIPLES.md:340 says "Never delete [deprecated methods]. Ordinal preserved for wire compatibility."** Applied pre-release, this is what keeps two dead variants in `UnlockResult` (screenlock.capnp:165, 167) alongside their typed replacements, two refresh-rate setters in display.capnp (115, 216), two ranking schemes in `DriverState`, and three capability-filter fields in input.capnp (199-202). With nothing external consuming the protocol, the deprecation-don't-delete rule costs more than it buys.
9. **DESIGN_PRINCIPLES.md:213 says of the seven `Session` interfaces "This is acceptable IF each represents a distinct service domain"** — screenlock.capnp:37 adds an eighth with an identical name, and DESIGN_PRINCIPLES.md:213 floats "a universal `ServiceSession` base" that is now clearly warranted: `HandshakeRequest/HandshakeResponse/HandshakeResult` are duplicated verbatim in at least screenlock.capnp:39-54 and font.capnp:53-70.
10. **TIMELESSNESS.md:25 rejects "Open PulseAudio stream" as implementation** — and then DESIGN_PRINCIPLES.md:454 uses audio.capnp as the success case for the PipeWire swap. The doctrine contradicts itself on the file it cites as exemplary.

---

## 3. Top-10 ranked actions (gain first, then cost)

| # | Action | Gain | Cost |
|---|---|---|---|
| **1** | **audio.capnp:892 — `submit (frames :Data)` → `T.DataHandle`.** | Removes the copy on the batch's hottest path (192 KB/s per stream, 100 allocations/s per stream) and the dominant idle-power cost of audio playback. The file's own `HrtfData` and ai.capnp:74-75 are the precedent; `DataHandle.inline` keeps sub-1 KB frames cheap. | One field type; drivers resolve a buffer handle. Strictly less copying, no added machinery. |
| **2** | **Give camera and capture a frame-delivery contract** (camera.capnp:42-43/72-74, capture.capnp:50-52): `openStream → stream` with `pull (maxBytes) → frame` (`pixels :T.DataHandle`, `sequence`, `cancel`). | Closes the batch's biggest hole: today a headless consumer (AR, OCR, `getUserMedia`) cannot get a frame and every backend invents a side channel (V4L2 vs AVFoundation already disagree). Two independent backends would interoperate for the first time. | ~14 lines + 3-4 ordinals. The best gain-per-line in the batch. |
| **3** | **Fix the bluetooth address-type schism** (bluetooth.capnp:510-552 vs :63): make `BluetoothDevice` expose a `T.DeviceAddress` (or adopt `T.BluetoothAddress`) and document the resolver. | Today a scan result cannot be passed to *any* method — `getDevice`, `pair`, `connectProfile`, all GATT calls. This is a total contract break of the primary use case, not a style issue. | One field + one documented mapping. |
| **4** | **Fix pagination on live streams** (sensor.capnp:238/242, capture.capnp:107, usb.capnp:449, camera.capnp:99, capability.capnp:401): replace the offset with a max-count pull. | Stops silently dropping readings on every sensor stream and stops unbounded server-side queue growth. Nine sites, one root cause, one primitive in types.capnp. | One parameter type; repoint nine sites. |
| **5** | **Repair the authority model across 12 schemas** (§2.3): `Capability`-gated accessors per ai.capnp:578-584 — `sensor.capnp:104`, `module.capnp:121`, `capture.capnp:353`, `audio.capnp:1030`, `device.capnp:445`, `power.capnp:37`, `nfc.capnp:25`, `usb.capnp:39`, `camera.capnp:32`, `screenlock.capnp:62`, `input.capnp:325`, `module.capnp:364`. | One authority path instead of permission strings, app allow/deny lists and unauthenticated command execution; removes two remote-code-execution paths and a private-key-in-request defect. | An accessor layer per service (~8 methods each). This is the batch's largest but highest-leverage change. |
| **6** | **Collapse the duplicate vocabularies** (§2.2): `ThermalState` (power≡device, verbatim), `DpmsState` (display≡framebuffer, verbatim), colour space ×4 → `T.ColorSpace`, refresh rate ×6 → `T.Frequency`, rotation ×4 → `T.SurfaceTransform`, gesture ×3 → `T.TouchGesture`, `WatermarkRequest` (camera≡capture), `MountOptions` (×3), `IpAddress` (×2). | One authoritative answer to "what state is this in / how bright / what rotation", and fewer ordinals frozen per concept. Most fixes are type-reference changes, ordinal-neutral for consumers. | 15-20 type-reference edits; pre-release, no wire to break. |
| **7** | **Add the missing `unknown` variants** (framebuffer.capnp:357, capture.capnp:160, camera.capnp:235, media.capnp:140, module.capnp:224, usb.capnp:453, console.capnp:714) and `T.Error` on the failure paths (print.capnp:57, media.capnp:15/64/73/76, camera.capnp:36, console.capnp:243). | Backends can add events and report failures without overloading existing variants; TIMELESSNESS.md:98 becomes true. ai.capnp:533/screenlock.capnp:209/font.capnp:553 are the exact templates. | ~10 one-line edits. Nearly free. |
| **8** | **Trim scope**: delete nfc.capnp's payments/loyalty/transit/EV/identity/Wi-Fi/crypto block (nfc.capnp:184-460) and its `encryptPeerMessage`/`decryptPeerMessage`; delete module.capnp's marketplace/feature-flag/tenancy block; delete the unreachable provider types in audio/display/usb. | Removes ~250 lines of institution-shaped frozen enums, two unauthenticated command paths, a plaintext-password field and ~40 dead types; a 2046 payment/credential/loyalty service can be built *on* the transport instead of being predicted by it. | Application concerns need homes (a payments schema, a credentials schema) — which is where they belong. |
| **9** | **Replace `SensorType` (44 values) with an open token** (sensor.capnp:24-70), keeping `units`/`axisLabels` as the machine-readable part; add per-reading unit and timestamps. | A 2046 sensor class is expressible today with no schema change — the batch's defining requirement. Evidence it is needed: 14 values were appended in one revision. | One type change + a documented token convention. |
| **10** | **Publish the `T.KeyCode` domain** (types.capnp:928) and purge the Linux console nouns from console.capnp:618-642. | Removes the batch's worst implementer trap (a key code with no published value space, used by `emulateKey` and every key binding) and makes console.capnp's "no platform-specific terminal emulator assumed" claim true. | A decision documented in a header; publish the mapping, do not freeze it into an enum (R1). |

**Honest note on what NOT to do.** Three proposed changes were rejected as cost-exceeding-gain and are recorded so nobody re-litigates them: (1) pushing bounded inline GATT values (`bluetooth.capnp:456, 670`, ≤517 bytes) behind `T.DataHandle` — it adds a mapping step for no copying saving; (2) converting small per-channel float lists (`audio.capnp:954-956, 601`, bounded by channel count) to buffer references — they are not bulk; (3) converting `LatencyClass`, `SoundCategory`, `MicSourceType`, `CameraFeature`, `DepthFormat` and `MediaType` to open tokens — each has a `custom` escape, and replacing them would remove the only capability comparison a consumer currently has. Likewise `sensor.capnp:123 `values :List(Float32)` is flagged for its *interpretation* gap, not its copy cost: 12 bytes per reading is not a bulk payload, and claiming otherwise would be noise.

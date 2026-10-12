# Schema Index

Complete index of the smart-protocol tree: **89 schemas, 303 interfaces** (verified mechanically against `schema/` on 2026-10-10, and re-verified in the integration pass of the same day — every file listed here exists, every interface name below is declared in that file, and every line count is the file's current line count).

The tree changed shape in the 2026-10-10 revamp. Four files were **deleted**, and this document replaces a catalog that still described them: `ipc-message.capnp` (a 9-line dead duplicate), `filesystem.capnp` (absorbed by `files.capnp` / `mount.capnp`), `surface.capnp` (absorbed by `compositor.capnp`), `textinput.capnp` (absorbed by `ime.capnp`). One file was **imported** from the reference OS: `gpu.capnp`. The pre-revamp `ramfs.capnp` no longer exists. Every count below reflects the current tree — 18 + 20 + 18 + 16 + 17 files across the five revamp batches = 89.

Gate status at the same run: `python3 scripts/validate.py` — parsed 89 schemas, exit 0, `PASSED`. E1 (zero enums in `ai.capnp`), E2 (no bulk lists in `ai.capnp`), E4 (all interfaces reachable), E6 (every union carries an extension point), E9 (no platform/vendor/POSIX nouns in required positions), E12 (one canonical home per type name), E13 (sequential, in-order ordinals) and E14 (every interface reachable, no unreferenced type) are all zero **tree-wide**. The remaining E7/E8/E10/E11 REPORT residuals are enumerated rule by rule in `audit-revamp/INTEGRATION-REPORT.md`.

---

## Foundation (3)

The base every other schema imports: the shared vocabulary, the authority algebra, and the startup handshake for versions. `types.capnp` declares no interface — it is the type layer (2,228 lines: opaque id wrappers, geometry, time, `T.DataHandle`, `T.UnknownEvent`, `T.ExecutionState`, `T.StringMap`). `capability.capnp` is the authority algebra; `abi.capnp` is what two parties say at startup before either commits to a call.

- **`types.capnp`** (2,134 lines, no interface) — the canonical vocabulary: every opaque id wrapper (`T.ProcessId`, `T.BufferId`, `T.KeyId`, …), `T.Timestamp`/`T.Duration`, `T.StringMap`, the zero-copy payload union `T.DataHandle` (inline `Data` or `BufferId` reference), the canonical `T.UnknownEvent { typeId, payload }`, and the universal lifecycle `T.ExecutionState` (unknown/active/blocked/suspended/terminated/custom).
- **`capability.capnp`** (479) — `CapabilityService`, `CapabilitySubscription`. The second half of the authority model: `issue @0`, and the entire delegation path — `attenuate @2`, `transfer @3`, `revoke @4`, `revokeControlled @8`, `evaluateCondition @11` — plus the closed `Operation` algebra (read…revoke, custom) and `DelegationChain`. This is the only file where a `Capability` parameter is the object under manipulation rather than an authority token.
- **`abi.capnp`** (310) — `AbiService`, `AbiSubscription`. ABI declaration, compatibility reporting and negotiation at startup: which schemas two parties both speak, at which versions, before either commits to a call.

---

## Kernel path (16)

What a system needs from power-on to a running service plane: the handoff, the kernel boundary, hardware affordances, service lifecycle and observation, and the shared machine services (discovery, queues, signals, scheduling, logs, diagnostics). These are the schemas the revamp cut hardest — the kernel file went from 881 to 248 lines because everything that described *how* a kernel works was deleted.

- **`boot.capnp`** (727) — `BootService`, `BootSubscription`. The founder's design directive as a schema: one well-known pointer (a 24-byte `HandoffPointer` at a fixed address) resolving to a declarative `BootManifest` — memory regions with open kind tokens, kernel menu, channels, images, args as a string map, framebuffer as a handle. No physical-address arithmetic, no page tables, no handler table. The kernel places `KernelService` at capability handle 1 — the only hardcoded capability in the system.
- **`kernel.capnp`** (248) — `KernelService`, `TaskSubscription`. The universal kernel boundary apps observe: `spawn @0`, memory regions, `stage @13`, `resolveService @15`, waitable-domain waits. No fork, no scheduler introspection, no kernel swapping — those are backend internals.
- **`hal.capnp`** (502) — `HalService`, `BusDiscoveryService`, `DmaMapService`, `IrqSubscription`. Hardware affordances for driver-apps: claim a device, describe hardware (open format token + `T.DataHandle`), subscribe to IRQ *firings*, map DMA. What the driver may ask for; never how the backend implements it.
- **`init.capnp`** (251) — `InitService`, `InitSubscription`. Userspace bootstrap and observable service lifecycle: bring services up in an order, with what authority grant. The dependency-resolution algorithm is init's business; the protocol sees lifecycle.
- **`service.capnp`** (275) — `Service`, `ServiceControl`, `ServiceStateSubscription`, `ServiceEventSubscription`. Runtime observation of services declared in init: what is running, in what state, with what health. Every mutation sits behind the capability-gated `control @13` accessor.
- **`process.capnp`** (359) — `Process`, `ProcessSubscription`, `ExitNotificationSubscription`. Process lifecycle, observation and memory inspection: an execution context (isolation + capability references + quota) instead of a POSIX credential block; memory reads as handles with a declared consistency guarantee.
- **`session.capnp`** (264) — `Session`, `SessionEventSubscription`. The user session: lock, unlock, identity, idle, persistence. The reference implementation of the protocol's service-session handshake pattern.
- **`task_scheduler.capnp`** (379) — `TaskSchedulerService`, `SchedulerSubscription`. Declarative background work: declare a job, say when it may run and under what constraints, watch it happen. Monotonic anchors with a declared clock-jump policy, not wall-clock triggers.
- **`signal.capnp`** (266) — `SignalService`, `SignalSubscription`. The single typed signal delivery authority: `T.SignalKind` (no POSIX numbers), handle payloads, masks, rate limits, and a typed delivery result.
- **`discovery.capnp`** (360) — `Discovery`, `DiscoveryRegistry`, `DiscoverySubscription`. Service registration and lookup with zero backend assumptions: ungated lookup, registration gated once at acquisition (`registry @12`), runtime health reported with honest `sinceValid` flags.
- **`queue.capnp`** (374) — `Queue`, `QueueSubscription`. Message queues: `T.DataHandle` payloads, at-most-once / at-least-once with deduplication keys (the impossible `exactlyOnce` was deleted), dead-letter routing, declared flow control.
- **`system.capnp`** (143) — `System`, `CapabilitiesSubscription`. The core system service: handshake, the capability token set (open tokens with a `partial` honesty flag, replacing a 47-boolean frozen catalog), extensions, lifecycle.
- **`diagnostics.capnp`** (351) — `DiagnosticsService`, `MetricsSubscription`. Health, metrics, crash dumps and profiles — with `ReportBounds` so a short answer is never mistaken for a complete one, and dumps as `T.DataHandle`.
- **`logging.capnp`** (225) — `Logging`, `LogSubscription`. The canonical log contract: `LogEntry`, `LogFilter`, trace contexts and spans live here and are imported by klog and diagnostics. Where a message goes is the backend's business — there is no `LogOutput` enum.
- **`klog.capnp`** (105) — `KernelLogService`, `KernelLogSubscription`. The kernel's scribe, named honestly: read, subscribe, buffer status (including `droppedOldest`, so a consumer can detect the gap that hides the crash it is investigating). Returns the canonical `LogEntry`.
- **`module.capnp`** (375) — `ModuleService`, `ModuleSubscription`. The lifecycle and shape of anything loadable at runtime — kernel modules, plug-ins, drivers, codecs — with load-time authority declared as capability references.

---

## Devices & media (19)

Everything that touches physical hardware or moves pixels and sound: device topology, displays, input, audio, cameras, sensors, radios, power, fonts, print, consoles, lock screens, GPUs. Most of these headers say the same thing in their own words — "zero backend assumptions; the backend decides the pipeline; the protocol defines the contract" — and the revamp made the bodies honor it.

- **`device.capnp`** (620) — `DeviceService`, `DeviceSubscription`, `DriverRegistry`, `DriverSubscription`, `DriverLifecycle`. The backend-decided device tree: what exists, which driver owns it, how to talk to it — with the driver framework reachable via `getDriverRegistry @33` and attach lifecycle owned here, not free-text driver names.
- **`display.capnp`** (958) — `Display`, `BrightnessSubscription`, `MonitorSubscription`, `DisplayProvider`. Video outputs, modes, HDR, night-light, color profiles, adaptive sync. No Wayland, X11 or DRM/KMS named; `Monitor` carries honesty fields so a qualified answer reads as qualified.
- **`framebuffer.capnp`** (651) — `FramebufferService`, `FramebufferSubscription`. Pixel-addressable surfaces for drivers and the kernel: the framebuffer is a handle, pixels live in shared memory regions.
- **`input.capnp`** (812) — `Input`, `InputDeviceSubscription`, `GestureSubscription`, `GamepadSubscription`, … Per-device state, layouts, modifiers, idle, emulation, rumble, surface grabs, gestures. The event union is closed over modalities with a `custom` arm, so a future modality is expressible.
- **`audio.capnp`** (1,329) — `Audio`, `AudioProvider`, `AudioDriverStream`. Devices, streams, focus, spatial, codecs, routing, effects. `submit @0` takes a `T.DataHandle` — frames are buffer references, not copies.
- **`camera.capnp`** (622) — `CameraService`, `CameraEventSubscription`. Photo/video capture, preview, analysis — delivering frames through capture.capnp's canonical `FrameStream`, so a camera frame and a screen-capture frame are one shape.
- **`capture.capnp`** (595) — `CaptureService`, `CaptureController`, `FrameStream`. Screen/window/output capture. Pure discovery and readback on the ungated surface; every pixel-acquiring, persisting or sharing operation sits on the gated `CaptureController`.
- **`sensor.capnp`** (560) — `SensorService`, `SensorSubscription`, `BatchSubscription`. Physical sensor discovery and streaming with bounded pulls — no offset-into-a-live-stream arithmetic.
- **`usb.capnp`** (689) — `UsbService`, `UsbHostProvider`, `UsbDeviceAdmin`, `UsbAuthentication`. Enumeration, control and events without assuming a host controller backend; the raw admin surfaces are behind gated accessors.
- **`bluetooth.capnp`** (722) — `BluetoothService`, `ScanSubscription`, `GattSubscription`, `AuracastService`, … BR/EDR + LE, pairing, GATT, profiles. One address vocabulary (`T.DeviceAddress` plus a text form), not three.
- **`nfc.capnp`** (441) — `NfcService`, `NfcController`, `TagSubscription`, `NfcTagEventSubscription`, `HceSubscription`, `BeamSubscription`. The radio transport and nothing else: tags in range, NDEF payloads as handles, APDU exchange, host card emulation behind a gated controller.
- **`power.capnp`** (489) — `Power`, `BatterySubscription`, `PowerTelemetrySubscription`. Battery, thermal state (its canonical home), sleep states, power profiles — observables, not power-management instructions.
- **`location.capnp`** (318) — `Locations`, `LocationSubscription`. Position, heading, speed — backend-agnostic across GPS, Wi-Fi positioning, beacons or a method not yet invented. Geofence attestation keys are `T.KeyId` handles.
- **`media.capnp`** (433) — `Media`, `PlayerSubscription`, `TranscodeSubscription`. Playback control, metadata, playlists, live interaction, transcode — the transport-control surface, not a media engine.
- **`font.capnp`** (888) — `FontSession`, `Font`, `FontEventStream`. Font discovery, matching, loading, metrics, lifecycle — no FreeType or CoreText named.
- **`print.capnp`** (388) — `Print`, `PrintersSubscription`. Printer discovery, job submission and management back-ends decide.
- **`console.capnp`** (754) — `ConsoleService`, `ConsoleMultiplexer`, `ConsoleInputSubscription`, `ConsoleOutputSubscription`. Terminal I/O with no termcap/VT100 lexicon; the TUI hot path (`writeBytes @46`, `pushInput @47`) is imported verbatim from the reference OS.
- **`screenlock.capnp`** (403) — `ScreenlockSession`, `LockEventStream`. The lock screen and idle lifecycle — and the canonical home of `UnlockCredential`, which `session.capnp` imports.
- **`gpu.capnp`** (549) — `GpuService`, `GpuProvider`, `GpuEventSubscription`. Vendor-agnostic graphics acceleration, imported from the reference OS's live tree: no Vulkan/Metal/D3D named, vendor is an open token, buffers are handles.

---

## Network & storage (18)

Connectivity and persistence: the socket contract (which is also the canonical home of channel security), the transport-agnostic address, HTTP/WebSocket, tunnels, telephony, files, block storage, databases, backup, archives, mounts, buffers, clocks, time, timezones and updates. The revamp collapsed three TLS homes into one (`socket.capnp`) and destroyed a transport museum that named fourteen variants.

- **`network.capnp`** (1043) — `Network`, `NicProvider`, `AddressAssignmentSubscription`, … Per-interface state, connect/disconnect, Wi-Fi, cellular, VPN — credentials as secret-key references, slicing as typed ids, transports as open tokens (a 2046 radio is a string), host-global networking and radio control (a disabled host reports why, not silence), and the configuration the command surface proved missing (MTU, known networks, routes, system proxy).
- **`dns.capnp`** (575) — `DnsService`, `ResolverHealthSubscription`. Name resolution that can finally *fail*: `ResolveResult` is a union carrying `T.Error`, so SERVFAIL and NXDOMAIN are distinguishable. No resolver library named.
- **`socket.capnp`** (546) — `SocketService`, `SocketEventSubscription`. The connection contract and the canonical TLS home: open version/cipher tokens, content-typed trust anchors, pins, and a normative `wss://` paragraph — a backend that cannot verify MUST fail rather than silently downgrade.
- **`endpoint.capnp`** (254) — `EndpointService`. The transport-agnostic address: `scheme :Text` plus a math-closed address union, carrying security, limits and pool configuration. A 2046 transport is a string and gets the same structure the 2026 ones had.
- **`web.capnp`** (540) — `WebService`, `HttpStream`, `WebSocketConnection`, `ReadableStreamReader`. HTTP fetch, WebSocket, URL primitives — `fetch` returns a union that can fail; binary payloads are handles.
- **`tunnel.capnp`** (319) — `TunnelService`, `TunnelSubscription`. A universal bidirectional async channel over any transport — in-process, kernel IPC, Unix socket, TCP, wasm postMessage — with typed frames and a neutral default flow policy.
- **`telephony.capnp`** (753) — `TelephonyService`, `LineManager`, `CallRecordingService`, `VoicemailService`. Cellular, calls, SMS/MMS/RCS. The seven orphan feature interfaces were resolved per feature: real ones wired behind gated accessors, 2020s product features deleted.
- **`files.capnp`** (832) — `Files`, `FileService`, `FileEventSubscription`. The canonical file contract: paths in, content out, handles as pure references. Three permission models collapsed into the capability system; reads and writes are both `T.DataHandle`.
- **`storage.capnp`** (1,281) — `StorageService`, `BlockProvider`, `StorageProgressSubscription`. Block devices, pools, volumes, snapshots — pool types and buses are open tokens reported, never prescribed. A 40 TB scrub reports progress on a subscription, not an RPC loop.
- **`database.capnp`** (838) — `Database`, `ChangeStreamSubscription`. Key-value with namespacing, batching and change feeds. Vectors are content (`T.DataHandle`), a query is content (`T.MimeType` + handle), and the CDC feed resumes from a monotonic sequence.
- **`backup.capnp`** (473) — `BackupService`, `BackupProgressSubscription`. Backup/restore lifecycle with paginated manifests, a caller-chosen resume token the backend honours, and verified checksums.
- **`archive.capnp`** (740) — `ArchiveService`, `CompressStream`, `DecompressStream`. Archive creation and extraction: container and compression as independent open tokens, and streaming pairs that actually stream (both directions are `T.DataHandle`).
- **`mount.capnp`** (515) — `MountService`, `MountSubscription`, `AutoMountEventSubscription`. The canonical mount contract — it absorbed the mount half of the deleted `filesystem.capnp`; one intent-named options struct instead of the old Linux-flag pair.
- **`buffer.capnp`** (665) — `BufferService`, `BufferSubscription`. Typed shared-memory buffers: the substrate that makes every other schema's `T.DataHandle` real. DMA tokens are opaque bytes, not per-process fd numbers.
- **`clock.capnp`** (377) — `ClockService`, `AlarmService`, `TimerSubscription`. Time sources and timer primitives — the canonical alarm home, with anchored fire times instead of sentinel-day fields.
- **`time.capnp`** (131) — `Time`. Wall-clock reading, calendar arithmetic and timestamp trust. The 1958-epoch TAI wire-breaker is gone; the single TAI representation lives in `timezone.capnp` on the Unix epoch.
- **`timezone.capnp`** (524) — `TimezoneService`, `TimezoneSubscription`. IANA timezone operations, DST transitions, UTC offsets — and the one `convertToTai`/`convertFromTai` pair.
- **`update.capnp`** (706) — `UpdateService`, `UpdateEventSubscription`. OS/package/firmware update orchestration — it received the firmware domain transferred from boot.capnp; images are content, verification is a declared hash, slots are a list plus an active index.

---

## UI & apps (16)

The stack above the kernel: presentation, text input, the desktop session, and the application lifecycle around it. The revamp ended the era of parallel models here — one commit path, one text-input contract, one clipboard, one notification service, one settings store, one app taxonomy.

- **`compositor.capnp`** (1,252) — `CompositorSession`, `EventStream`. Display composition and the ONE surface commit path: `attachBuffer` binds a `T.BufferId`, `commit` carries a typed `SyncFence`, damage is geometry. The batch's shared-vocabulary home — windowmanager, ime and shell import its handshake types. It absorbed the deleted `surface.capnp`.
- **`windowmanager.capnp`** (606) — `WindowManagerSession`, `WindowManagerEventStream`. Window lifecycle, workspaces, layout, snapping — imports compositor only, never the shell, so a shell rewrite cannot force a WM rebuild.
- **`ime.capnp`** (519) — `ImeSession`, `TextInputEventStream`. The one text-input contract — it absorbed the drifted `textinput.capnp` twin. Modality, content type and keyboard type are open tokens with published conformance constants.
- **`shell.capnp`** (1,328) — `ShellSession`, `ShellService`, `ShellEventStream`. The desktop session surface, and the command interpreter: `ShellService` is imported verbatim from the reference OS (45 methods, reachable through one capability-gated accessor). Notification, clipboard and settings façades delegate to their canonical services.
- **`cli.capnp`** (506) — `CliService`, `InteractiveSession`, `JobSubscription`. Command execution and introspection: sync, background, streaming, pipeline, interactive — with stdin/stdout/stderr as handles. Commands register by schema identity (`T.SchemaId` + interface + method), so the command surface can be generated from the schemas.
- **`clipboard.capnp`** (238) — `Clipboard`, `ClipboardChangeSubscription`. The one clipboard service: content as mime type + `T.DataHandle` (a screenshot paste is no longer a copy), multi-representation offers, one change stream. The parallel ACL model is deleted — capabilities are the access control.
- **`notification.capnp`** (313) — `Notifications`, `NotificationsSubscription`. The one notification service and the DND authority: `show` returns a result that can fail, threads paginate, the shell delegates here.
- **`settings.capnp`** (193) — `Settings`, `SettingsSubscription`. The one settings store: domain+key, a recursive value model, optimistic concurrency, delta reads. A missing key returns `notSet`, not an empty string.
- **`theme.capnp`** (379) — `Theme`, `ThemeSubscription`. Visual token sets, dark/light, motion, typography — tokens as an open map, so a display paradigm names new tokens with no ordinal. No theming engine assumed.
- **`accessibility.capnp`** (701) — `AccessibilityService`, `TreeSubscription`, `AccessibilityEventSubscription`. The contract between UI toolkits and assistive tech: lazy trees, deltas, ranges, relationships, paginated traversal — WAI-ARIA is not welded into required fields.
- **`app.capnp`** (385) — `AppService`, `AppSubscription`. The runtime view of applications: what is running, in what state, using what. The permission-string delegation model is deleted; lifecycle and catalog are split from appindex.
- **`appindex.capnp`** (424) — `AppIndexService`, `AppIndexSubscription`. The catalog: list, search, launch, pin, track — one open app taxonomy, and the stated `AppId` issuance rule (survives upgrade, a different manifest is a different app).
- **`package.capnp`** (478) — `Package`, `PackageSubscription`, `UpdateDownloadSubscription`. Install, uninstall, update, verify — `install` returns a result that can fail; bundle credentials are references to secrets, never passwords on the wire.
- **`extension.capnp`** (388) — `Extension`, `ExtensionSubscription`. Plug-in lifecycle with an open runtime token (`T.MimeType`) instead of WASM-shaped fields, and hook actions that are API invocations — not arbitrary script text to execute.
- **`intent.capnp`** (730) — `IntentService`, `ActivityResultSubscription`. The universal activation contract: resolve, dispatch (activity/service/broadcast), replay, history. Android vocabulary replaced by open action/category tokens and delivery hints.
- **`manifest.capnp`** (412) — `ManifestService`, `ManifestSubscription`. Bundle self-description for anything installed, dispatched or distributed — one shape for apps, services, devices, plug-ins and snapshots.

---

## Security & intelligence (17)

Identity, secrecy, cryptography — and the intelligence contracts. Two files anchor the group: `crypto.capnp`, where ~130 frozen algorithm values became open tokens with published conformance spellings (the amendment loop that kept correcting itself for FIPS updates is closed), and `ai.capnp`, the gold standard the rest of the tree is measured against.

- **`ai.capnp`** (644) — `AI`, `ModelService`, `InferenceService`, `ToolRegistry`, `AgentService`, `KnowledgeBaseService`, `ConversationService`, `ArtifactStream`. The universal intelligence contract. **Zero enums** (validator E1, a hard gate): no architecture, vendor, format, tokenizer or topology is named, because anything named ages into a lie. One `Artifact` (mime type + `T.DataHandle`) carries every modality; discovery is ungated, every service reference is gated once at acquisition.
- **`speech.capnp`** (561) — `Speech`, `VoiceStudio`, `SpeechAudioStream`, `ListenResultStream`. STT and TTS with outcome unions that can fail, emotion/style/encoding as open tokens, audio as handles.
- **`translation.capnp`** (486) — `Translation`, `TranslationStreamSession`, `BatchProgressSubscription`. Text translation with a functional streaming session, typed language tags, and batches whose progress is observable.
- **`contacts.capnp`** (534) — `Contacts`, `ContactPrivacy`, `ContactsSubscription`. Address book management: PII egress (`shareContact`) now requires a consent record behind a gated privacy accessor; photos and import/export are handles.
- **`calendar.capnp`** (590) — `CalendarService`, `EventsSubscription`. Events, reminders, free/busy, recurrence — with declared precedence (structured fields authoritative, `rrule` advisory) and delegation through `capability.capnp`, not five booleans.
- **`content.capnp`** (636) — `ContentService`, `ContentSubscription`. Cross-app data sharing with relationships and versioning; `decryptContent` is read-through (returns plaintext as a per-caller handle), and the file's parallel permission model is deleted.
- **`system_search.capnp`** (521) — `SystemSearch`, `SearchResultsStream`, `ProvidersSubscription`. Universal search across providers — the hot payload (`VectorQuery.embedding`) is a handle, and one `SearchResultId` is used on the field and every consumer.
- **`runtime_search.capnp`** (461) — `RuntimeSearchService`, `RuntimeSearchSubscription`. The runtime counterpart: what is currently *providing* (services, runtimes, endpoints). The drifted service-mesh control plane was cut; runtimes are open tokens.
- **`vcard.capnp`** (628) — `VCardService`. The vCard converter (RFC 6350) for contacts interoperability — capability reporting is honest (no phantom v5.0), and 1998 TYPE vocabularies go through the open parameters mechanism.
- **`auth.capnp`** (445) — `Auth`, `AuthService`, `AuthSubscription`. Authentication and token lifecycle — `refreshToken` now requires proof of possession, so a stolen token id can no longer mint fresh tokens indefinitely.
- **`biometric.capnp`** (517) — `BiometricService`, `EnrollSubscription`, `BiometricAuthSubscription`, `BiometricEventSubscription`. Biometric hardware: modality and sensor taxonomies are open tokens, templates and hardware have separate typed identities, outcomes carry payloads.
- **`access.capnp`** (751) — `AccessService`, `AccessSubscription`. The device-unlocking surface: lock, MFA state machine, lockout, recovery — backend-agnostic by design (TPM, enclave, smart card, keychain).
- **`crypto.capnp`** (845) — `CryptoService`, `EncryptStream`, `DecryptStream`, `HashStream`, `HmacStream`. The canonical algorithm vocabulary: open tokens + `T.StringMap` parameters with today's spellings published as conformance constants. All bulk is `T.DataHandle`; digests/tags/nonces stay inline with the reasoning stated. `KeyUse` is the one kept enum — closed by public-key mathematics.
- **`key_management.capnp`** (385) — `KeyManagement`, `KeyManagementService`, `KeySubscription`. Key lifecycle — the whole store behind `store @0 (authority :Capability)`, one `T.KeyId` identity, declared rotation grace semantics.
- **`signature.capnp`** (387) — `SignatureService`, `TrustSubscription`. Signing and verification — every verify path takes `T.DataHandle` (verifying a 50 MB artifact no longer copies it), and the divergent-ordinal algorithm enums are gone in favour of crypto's open vocabulary.
- **`secret.capnp`** (335) — `Secret`, `SecretStore`, `SecretChangeSubscription`. Secret storage with namespace isolation — the entire surface gated at acquisition, values as handles, overlay overrides as structured entries rather than greppable text.
- **`sandbox.capnp`** (514) — `SandboxService`, `SandboxCapabilityAdmin`. Process isolation with the platform body abstracted: seccomp/landlock/rlimit names became abstract outcomes with backend-reported `enforcedBy`; snapshots are handles; capability administration sits behind its own gated accessor.

---

## Deleted in the 2026-10-10 revamp (not in the tree, listed so old references resolve)

| File | Where its surface lives now |
|---|---|
| `ipc-message.capnp` | A 9-line dead duplicate of `logging.capnp`'s parameter triple. Deleted; nothing imported it. |
| `filesystem.capnp` | Special paths, trash and recent files → `files.capnp`; the mount surface → `mount.capnp`; pools/volumes stayed in `storage.capnp`. The FUSE provider block (returned by nothing, authority by raw id) was deleted, not relocated. |
| `surface.capnp` | `compositor.capnp` — the unified commit path (`SurfaceCommit`: one buffer mechanism, one fence type) and its absorbed types (`SurfaceState`, `FrameData`, `FrameMetrics`). |
| `textinput.capnp` | `ime.capnp` — the two files had drifted into incompatible twins; the merged file is the one text-input contract. |

---

*This index is generated from the tree, not from memory: 89 files in `schema/`, 303 `interface` declarations, and every name above verified against the schema it names. When the tree changes, this document is regenerated — never hand-edited.*

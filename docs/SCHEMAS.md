# Schema catalog

The complete tree: **89 schemas, 303 interfaces, 49,655 lines**. Every number in
this document is produced by `python3 scripts/docstats.py` from the files it
describes; every interface count is parsed from the file beside it. Regenerate
the counts before editing this page.

The catalog is organised by the job a schema does, not by the order in which it
was written. Six groups; the first three are the machine, the last three are
what runs on it.

| Group | Files | Interfaces | Lines |
|---|---|---|---|
| [Foundation](#foundation-3) | 3 | 4 | 3,017 |
| [Kernel path](#kernel-path-16) | 16 | 39 | 5,204 |
| [Devices & media](#devices--media-19) | 19 | 93 | 12,221 |
| [Network & storage](#network--storage-18) | 18 | 68 | 11,121 |
| [UI & apps](#ui--apps-16) | 16 | 39 | 8,852 |
| [Security & intelligence](#security--intelligence-17) | 17 | 60 | 9,240 |

Read a schema by its header, not its name. Every file opens with the argument
for its own existence: what boundary it defines, what it deliberately omits,
what was deleted and why. That convention is enforced by review, and it is why
the tree can be read in an afternoon.

---

## Foundation (3)

The shared vocabulary and the two schemas that make everything else
interoperable. Every one of the other 88 files imports `types.capnp`; 24 schemas take a
`Capability` on a root accessor; two parties announce what they speak through
`abi.capnp` before either commits to a call.

| Schema | Lines | Ifaces | Purpose |
|---|---|---|---|
| `types.capnp` | 2,228 | 0 | The canonical vocabulary: opaque id wrappers, geometry, time, `T.DataHandle`, `T.StringMap`, `T.Error`, `T.UnknownEvent`, `T.ExecutionState`. Declares no interface by design. |
| `capability.capnp` | 479 | 2 | Authority: issue, verify, attenuate, transfer, revoke, revoke-and-cascade, delegation chains, audit. The only file where a `Capability` is the object under manipulation. |
| `abi.capnp` | 310 | 2 | What two parties declare at startup: which schemas they speak, at which versions, and how they report an intersection. |

**`types.capnp` is the whole contract in one file.** If you read only one schema,
read this one: it defines what an identifier is (opaque, typed, never
arithmetic), what a payload is (`T.DataHandle`: inline `Data` or a `BufferId`
reference), what failure is (`T.Error` with a code, a message, a retry flag and
open metadata), and what an unknown value is (`T.UnknownEvent` carrying a
producer-assigned `typeId` and an opaque payload).

---

## Kernel path (16)

Power-on to a running service plane: the handoff, the kernel boundary, hardware
affordances, service lifecycle and observation, and the shared machine services
every other component relies on. This group was cut hardest by the 2026-10-10
revamp, because it is where implementation detail most easily masquerades as
contract.

| Schema | Lines | Ifaces | Purpose |
|---|---|---|---|
| `boot.capnp` | 727 | 2 | The handoff: a 24-byte `HandoffPointer` resolving to a declarative `BootManifest`. No page tables, no address arithmetic, no format knowledge. |
| `kernel.capnp` | 248 | 2 | The universal kernel boundary: spawn, memory regions, waitables, signalling, staging, service resolution. What a kernel must offer; nothing about how. |
| `hal.capnp` | 502 | 5 | Hardware affordances for driver processes: claim a device, describe it in an open format token, subscribe to IRQ firings, map DMA. |
| `init.capnp` | 251 | 2 | Userspace bootstrap: start, stop, restart, respawn, supervise, phase advance, shutdown. The ordering algorithm is init's business. |
| `service.capnp` | 275 | 4 | Runtime observation of services: state, health, events. Every mutation behind a capability-gated accessor. |
| `process.capnp` | 359 | 3 | Process lifecycle and inspection: an execution context (isolation, capabilities, quota), not a POSIX credential block. |
| `session.capnp` | 264 | 2 | The user session: lock, unlock, identity, idle, persistence. The reference implementation of the session handshake pattern. |
| `task_scheduler.capnp` | 379 | 2 | Declarative background work: declare a job and its constraints, observe it run. Monotonic anchors with a declared clock-jump policy. |
| `signal.capnp` | 266 | 2 | Typed signal delivery: `T.SignalKind`, handle payloads, masks, rate limits, typed delivery results. No POSIX numbers. |
| `discovery.capnp` | 360 | 3 | Service registration and lookup: ungated lookup, registration gated once, runtime health with honest `sinceValid` flags. |
| `queue.capnp` | 374 | 2 | Message queues: `T.DataHandle` payloads, at-most-once and at-least-once with deduplication keys, dead-letter routing, declared flow control. |
| `system.capnp` | 143 | 2 | The core system service: handshake, the capability token set with a `partial` honesty flag, extensions, lifecycle. |
| `diagnostics.capnp` | 351 | 2 | Health, metrics, crash dumps and profiles, with `ReportBounds` so a short answer is never mistaken for a complete one. |
| `logging.capnp` | 225 | 2 | The canonical log contract: entries, filters, trace contexts, spans. Where a message is written is the backend's business. |
| `klog.capnp` | 105 | 2 | The kernel's own log, including `droppedOldest` so a consumer can see the gap that hides the crash it is investigating. |
| `module.capnp` | 375 | 2 | The lifecycle of anything loadable at runtime — modules, plug-ins, drivers, codecs — with load-time authority as capability references. |

The three anchors here are `boot.capnp` (the smallest possible handoff),
`kernel.capnp` (the boundary that swaps), and `discovery.capnp` (the plane that
lets services find each other without a bus daemon or a policy file).

---

## Devices & media (19)

Everything that touches physical hardware or moves pixels and sound. The
recurring rule in these headers: *the backend decides the pipeline; the protocol
defines the contract.* No display server, audio server, GPU API or bus is named
in a required position.

| Schema | Lines | Ifaces | Purpose |
|---|---|---|---|
| `device.capnp` | 620 | 6 | The device tree: what exists, which driver owns it, how to reach it. Driver framework and attach lifecycle owned here. |
| `display.capnp` | 958 | 9 | Video outputs, modes, HDR, brightness, colour profiles, adaptive sync, stylus input, power budgeting. |
| `framebuffer.capnp` | 651 | 2 | Pixel-addressable surfaces for drivers and the kernel: the framebuffer is a handle, pixels live in shared regions. |
| `input.capnp` | 812 | 8 | Per-device state, layouts, modifiers, idle, emulation, rumble, grabs, gestures, gamepads. One event union with a `custom` arm. |
| `audio.capnp` | 1,329 | 10 | Devices, streams, focus, spatial audio, codecs, routing, effects. Frames are `T.DataHandle`, never copies. |
| `camera.capnp` | 622 | 2 | Capture, preview and analysis, delivering frames through `capture.capnp`'s canonical `FrameStream`. |
| `capture.capnp` | 595 | 4 | Screen, window and output capture. Discovery is ungated; every pixel-acquiring or sharing operation sits on the gated controller. |
| `sensor.capnp` | 560 | 4 | Sensor discovery and streaming with bounded pulls, including batched delivery. |
| `usb.capnp` | 689 | 6 | Enumeration, control, topology and authentication without assuming a host-controller backend. |
| `bluetooth.capnp` | 722 | 8 | BR/EDR and LE, pairing, bonds, GATT, profiles, Auracast. One address vocabulary, not three. |
| `nfc.capnp` | 441 | 6 | The radio transport: tags in range, NDEF payloads as handles, APDU exchange, host card emulation behind a gate. |
| `power.capnp` | 489 | 3 | Battery, thermal state (its canonical home), sleep states, power profiles — observables, not instructions. |
| `location.capnp` | 318 | 2 | Position, heading, speed, geofencing — agnostic across satellite, network and beacon positioning. |
| `media.capnp` | 433 | 5 | Playback control, metadata, playlists, live interaction, transcode. The control surface, not the engine. |
| `font.capnp` | 888 | 3 | Font discovery, matching, loading, metrics and lifecycle. No rasteriser named. |
| `print.capnp` | 388 | 2 | Printer discovery, job submission and management; the rendering pipeline is the backend's. |
| `console.capnp` | 754 | 8 | Terminal I/O with no terminal-capability lexicon; the multiplexer and byte hot path imported from the reference OS. |
| `screenlock.capnp` | 403 | 2 | Lock screen and idle lifecycle, and the canonical home of `UnlockCredential`. |
| `gpu.capnp` | 549 | 3 | Vendor-agnostic acceleration: no Vulkan, Metal or D3D named; vendor is an open token; buffers are handles. |

Device classes are named by *capability*, not by bus: a device declares an open
format token and describes itself through `T.DataHandle`. A device class
invented in 2046 claims its hardware without a schema edit.

---

## Network & storage (18)

Connectivity and persistence. This group absorbed three collapses: three TLS
homes became one (`socket.capnp`), a fourteen-variant transport enum became an
open token, and the deleted `filesystem.capnp` split correctly between
`files.capnp` and `mount.capnp`.

| Schema | Lines | Ifaces | Purpose |
|---|---|---|---|
| `network.capnp` | 1,052 | 8 | Per-interface state, connect/disconnect, Wi-Fi, cellular, VPN, hotspot, routing, MTU, known networks, system proxy. Transports are open tokens. |
| `dns.capnp` | 575 | 4 | Name resolution whose result union can fail, so SERVFAIL and NXDOMAIN are distinguishable. Resolver health is observable. |
| `socket.capnp` | 546 | 2 | The connection contract and the canonical TLS home: open version and cipher tokens, content-typed trust anchors, pins, mandatory verification. |
| `endpoint.capnp` | 254 | 1 | The transport-agnostic address: `scheme :Text` plus an address union, carrying security, limits and pool configuration. |
| `web.capnp` | 540 | 5 | HTTP fetch, streaming, WebSocket, URL primitives. A fetch returns a union that can fail; payloads are handles. |
| `tunnel.capnp` | 319 | 2 | A bidirectional typed channel over any transport, with a neutral default flow policy. |
| `telephony.capnp` | 753 | 10 | Cellular, calls, SMS/MMS/RCS, line management, recording, voicemail, call screening. |
| `files.capnp` | 832 | 4 | The canonical file contract: paths in, content out, handles as references, one permission model. |
| `storage.capnp` | 1,281 | 6 | Block devices, pools, volumes, snapshots, scrubbing. Pool types and bus kinds are reported, never prescribed. |
| `database.capnp` | 838 | 4 | Key-value with namespaces, batching, change feeds, a resumable sequence, and content as handles. |
| `backup.capnp` | 473 | 2 | Backup and restore with paginated manifests, a caller-chosen resume token, and verified checksums. |
| `archive.capnp` | 740 | 4 | Creation and extraction where container and compression are independent open tokens, and both directions stream. |
| `mount.capnp` | 515 | 4 | The canonical mount contract, with one intent-named options struct instead of a flag pair. |
| `buffer.capnp` | 665 | 2 | Typed shared-memory buffers — the substrate that makes every other schema's `T.DataHandle` real. |
| `clock.capnp` | 377 | 3 | Time sources, timers and alarms, with anchored fire times and explicit jump semantics. |
| `time.capnp` | 131 | 1 | Wall-clock reading, calendar arithmetic and timestamp trust. |
| `timezone.capnp` | 524 | 4 | Timezone operations, DST transitions, offsets, leap seconds, and the single TAI conversion pair. |
| `update.capnp` | 706 | 2 | OS, package and firmware update orchestration: images as content, verification as a declared hash, slots as a list plus an active index. |

---

## UI & apps (16)

Presentation, text input, the desktop session and the application lifecycle
around it. The revamp ended the era of parallel models: one compositor, one
text-input contract, one clipboard, one settings store, one notification
service, one manifest shape.

| Schema | Lines | Ifaces | Purpose |
|---|---|---|---|
| `compositor.capnp` | 1,252 | 2 | The single commit path: buffer by `T.BufferId`, fence by typed handle, damage as geometry. Owns the shared `SessionRequest` handshake used tree-wide. |
| `windowmanager.capnp` | 606 | 2 | Window lifecycle, workspaces, layout, snapping. Imports compositor only — never the shell. |
| `ime.capnp` | 519 | 2 | The one text-input contract: modality, content type and keyboard type as open tokens with published conformance constants. |
| `shell.capnp` | 1,328 | 5 | The desktop session surface and the command interpreter: `ShellService` (45 methods) imported verbatim from the reference OS. |
| `cli.capnp` | 506 | 4 | Command execution and introspection — sync, background, streaming, pipeline, interactive — with stdio as handles and commands registered by schema identity. |
| `clipboard.capnp` | 238 | 2 | One clipboard: content as mime type plus handle, multi-representation offers, one change stream, capabilities as access control. |
| `notification.capnp` | 313 | 2 | The one notification service and the do-not-disturb authority; `show` can fail; threads paginate. |
| `settings.capnp` | 193 | 2 | The one settings store: domain plus key, recursive values, optimistic concurrency, delta reads, `notSet` instead of empty string. |
| `theme.capnp` | 379 | 2 | Visual token sets — colour, motion, typography — as an open map, so a new design paradigm names new tokens with no new ordinal. |
| `accessibility.capnp` | 701 | 3 | The contract between UI toolkits and assistive technology: lazy trees, deltas, ranges, relationships, paginated traversal. |
| `app.capnp` | 385 | 2 | The runtime view of applications: what is running, in what state, using what. Lifecycle only; the catalog lives in `appindex.capnp`. |
| `appindex.capnp` | 424 | 2 | The catalog: list, search, launch, pin, track, with one open taxonomy and a stated `AppId` issuance rule. |
| `package.capnp` | 478 | 3 | Install, uninstall, update, verify. `install` can fail; bundle credentials are references to secrets, never passwords on the wire. |
| `extension.capnp` | 388 | 2 | Plug-in lifecycle with an open runtime token, and hook actions as API invocations rather than script text. |
| `intent.capnp` | 730 | 2 | Universal activation: resolve, dispatch to activity/service/broadcast, replay, history. Open action and category tokens. |
| `manifest.capnp` | 412 | 2 | One self-description shape for anything installed, dispatched or distributed — apps, services, devices, plug-ins, snapshots. |

---

## Security & intelligence (17)

Identity, secrecy, cryptography and intelligence. Two files anchor the group:
`crypto.capnp`, where roughly 130 frozen algorithm values became open tokens
with published conformance spellings, and `ai.capnp`, the gold standard the rest
of the tree is measured against.

| Schema | Lines | Ifaces | Purpose |
|---|---|---|---|
| `ai.capnp` | 644 | 9 | The universal intelligence contract. **Zero enums** (E1, hard gate). One `Artifact` for every modality; discovery ungated, every service gated once at acquisition. |
| `speech.capnp` | 561 | 7 | Speech recognition and synthesis with outcome unions that can fail, open style tokens, audio as handles, streaming sessions. |
| `translation.capnp` | 486 | 3 | Text translation with a streaming session, typed language tags, observable batch progress. |
| `contacts.capnp` | 534 | 4 | Address book management; PII egress requires a consent record behind a gated privacy accessor; photos are handles. |
| `calendar.capnp` | 590 | 2 | Events, reminders, free/busy, recurrence with declared precedence, delegation through `capability.capnp`. |
| `content.capnp` | 636 | 2 | Cross-application data sharing with relationships and versioning; decryption is read-through to a per-caller handle. |
| `system_search.capnp` | 521 | 4 | Universal search across providers; embeddings travel as handles; one result identity. |
| `runtime_search.capnp` | 461 | 2 | What is currently providing: services, runtimes, endpoints. Runtimes are open tokens. |
| `vcard.capnp` | 628 | 1 | vCard conversion for contacts interoperability, with honest capability reporting. |
| `auth.capnp` | 445 | 4 | Authentication and token lifecycle; refresh requires proof of possession. |
| `biometric.capnp` | 517 | 4 | Biometric enrolment and verification: open modality tokens, separate typed identities for template and hardware, outcomes with payloads. |
| `access.capnp` | 751 | 2 | The device-unlocking surface: lock, MFA state machine, lockout, recovery. Backend-agnostic by design. |
| `crypto.capnp` | 845 | 5 | The canonical algorithm vocabulary as open tokens with published conformance constants; bulk as handles, digests inline, one genuinely closed enum (`KeyUse`). |
| `key_management.capnp` | 385 | 3 | Key lifecycle: the whole store behind `store @0 (authority :Capability)`, one key identity, declared rotation grace. |
| `signature.capnp` | 387 | 2 | Signing and verification; every verify path takes a handle, so a large artefact is never copied to be checked. |
| `secret.capnp` | 335 | 3 | Secret storage with namespace isolation, the entire surface gated at acquisition, values as handles. |
| `sandbox.capnp` | 514 | 3 | Process isolation with platform mechanisms abstracted into outcomes with backend-reported `enforcedBy`, snapshots as handles, capability administration behind its own gate. |

---

## Deleted in the 2026-10-10 revamp

Listed so that old references resolve. Each was deleted because it was either a
duplicate with a second home or a contract that described one implementation.

| File | Where its surface lives now |
|---|---|
| `ipc-message.capnp` | A 9-line dead duplicate of `logging.capnp`'s parameter triple. Nothing imported it. |
| `filesystem.capnp` | Special paths, trash and recent files → `files.capnp`; the mount surface → `mount.capnp`; pools and volumes stayed in `storage.capnp`. The FUSE provider block was deleted, not relocated. |
| `surface.capnp` | `compositor.capnp` — the unified commit path and its absorbed types (`SurfaceState`, `FrameData`, `FrameMetrics`). |
| `textinput.capnp` | `ime.capnp` — the two had drifted into incompatible twins; the merged file is the one text-input contract. |

---

## How to read a schema

Every `.capnp` file in `schema/` has the same shape, and the shape is the
point:

1. **The schema ID and a header.** The header states what boundary the file
   defines, who consumes it, what is deliberately opaque, what was deleted and
   why. It is an argument, not a description.
2. **Imports.** `T` from `types.capnp` in every file; domain imports where a
   type has one canonical home.
3. **Types, then events, then interfaces.** Value structs first, event unions
   next, service interfaces last.
4. **Ordinals in order.** Methods are declared sequentially; new capabilities
   take fresh ordinals at the end.
5. **The gate.** `python3 scripts/validate.py` — a schema that adds a finding
   must justify it in its own header.

*Generated from the tree, not from memory. When `schema/` changes, this page is
regenerated with `python3 scripts/docstats.py`.*

# Smart Protocol

**A timeless, universal system contract. Zero-copy. Language-agnostic. Platform-agnostic. AI-first.**

---

## What Is Smart Protocol?

Smart Protocol is the **first universal system contract** — a complete, coherent protocol covering every domain a system needs, expressed in Cap'n Proto schemas. It is not a library, not a daemon, not an OS. It is the **contract** that makes everything else interoperate.

### The Eight Properties Nobody Else Has All Of

| Property | What It Means |
|----------|---------------|
| **Language-agnostic** | Rust, C, C++, Python, JavaScript, Java, Go, Swift, bash, TOML — any language with a Cap'n Proto compiler |
| **Platform-agnostic** | Linux, Windows, macOS, SpaceOS, bare metal, WebAssembly, remote — same schemas, different backends |
| **Shape-agnostic** | Library, CLI, config file (TOML/JSON), script (`.smart`), IPC (Unix socket), network (TCP/WebSocket) — all speak the same protocol |
| **Complete** | 89 capability domains covering audio, display, input, network, storage, processes, AI, security, UI, and more |
| **A contract** | Cap'n Proto schemas with forward-compatible evolution — never breaks, ordinals are permanent |
| **AI-first** | Same protocol for humans and machines — AI agents use the exact same interfaces as CLI and apps |
| **Zero-cost** | Cap'n Proto zero-copy serialization, library-first backends (no daemons), no runtime diffing |
| **Vertically integrated** | Kernel → services → UI → AI — every layer speaks the protocol, every layer replaceable |

---

## The Six Shapes

```
┌─────────────────────────────────────────────────────────────┐
│                    Smart Protocol                           │
├──────────────┬──────────────┬──────────────┬────────────────┤
│   LIBRARY    │     CLI      │     IPC      │     CONFIG     │
│   link &     │   `smart`    │   capnp over │   TOML/JSON    │
│   call       │   command    │   shared mem │   `smart apply`│
├──────────────┼──────────────┼──────────────┼────────────────┤
│   NETWORK    │    SCRIPT    │              │                │
│   TCP/WS     │   `.smart`   │              │                │
│   remote     │   script     │              │                │
└──────────────┴──────────────┴──────────────┴────────────────┘
```

Every shape is **equal** — no shape is primary. An AI agent using the network shape has the same power as a human using the CLI.

---

## Core Design Principles (Non-Negotiable)

### 1. The Agnostic/Timeless Test
> **"Is this an EXTERNAL contract (how components interoperate) or an INTERNAL implementation (how a component works)?"**
- External → in the protocol
- Internal → inside the component, NEVER in the schema

### 2. The Opacity Principle
> **Push types as far left (opaque) as possible.**
- `UInt64` / `Data` / `Text` when consumers don't inspect structure
- Structured only when fields MUST be read/written for interop

### 3. The Swap Test
> **Can you swap Linux ↔ seL4 ↔ custom kernel ↔ WebAssembly runtime without changing the protocol?**
- If no → the schema leaks implementation

### 4. No Platform Nouns in Required Enums
- No `systemd`, `syslog`, `inode`, `zombie`, `cgroup`, `seccomp`, `cr3`, `HHDM`, `Limine`, `x86_64`
- Use abstract terms: `BootloaderKind { limine, grub, uefiDirect, custom }`, `TierClass { kernel, platform, system, application, sandbox, custom }`

### 5. Capability System IS the Access Control
- No permission strings, no RBAC, no boolean flags
- Methods that need authority take `Capability` parameter

### 6. Zero-Cost, No Runtime Diffing
- Cap'n Proto zero-copy: messages read directly from wire
- No serialization/deserialization step
- Compiler is the only authority — monomorphization, not vtables

---

## The 89 Capability Domains

### Foundation (3)
- `types.capnp` — Foundation: IDs, geometry, time, errors, **Quota, ContainmentScope, UserlandImage, EntryContext, BinaryFormat, StateOutcome**
- `capability.capnp` — Capability issuance, verification, attenuation, revocation, delegation
- `abi.capnp` — ABI versioning, compatibility negotiation

### Kernel & Boot (4)
- `kernel.capnp` — ENTIRE kernel API — spawn, exec, memory, capabilities, service registry. **No hardware methods.**
- `boot.capnp` — Boot handoff: HandoffPointer → BootHandoff → BootstrapInfo. Virtual addresses only.
- `hal.capnp` — Hardware affordances (MMIO, IRQ, DMA, PCI). **Arch-specific I/O in X86PortIo sub-interface.**
- `init.capnp` — Pure service orchestrator. No Kubernetes, containers, cgroups. Just ServiceSpec lifecycle.

### System Services (12)
- `system.capnp` — Entry point, capability discovery, handshake
- `service.capnp` — Service lifecycle, health, resources, TierClass
- `process.capnp` — Processes, Quota, ContainmentScope, universal states
- `session.capnp` — Login, lock, idle, user identity
- `discovery.capnp` — Service registry, heartbeat, changeFeed, scopeBoundary
- `logging.capnp` — Structured logs, opaque formats, UInt64 subscriptions
- `diagnostics.capnp` — Metrics, health, tracing, GPU, resource forecasting
- `klog.capnp` — Kernel log access, retention, encryption, alerting
- `time.capnp` — Clocks, timers, alarms, world clocks
- `queue.capnp` — Inter-app messaging
- `signal.capnp` — Typed signal/event system
- `task_scheduler.capnp` — Scheduling policies, priorities

### Hardware & Devices (10)
- `device.capnp` — Backend-decided device tree, opaque IDs
- `display.capnp` — Monitors, brightness, HDR, color, wireless
- `audio.capnp` — Devices, streams, **timeless OS features**: sound events, analysis, mic privacy, loudness safety, routing intelligence, device health, multi-zone
- `input.capnp` — Keyboard, mouse, touch, gamepad, force feedback
- `camera.capnp` — Photo, video, preview, AI analysis
- `usb.capnp` — USB device enumeration, PD, Thunderbolt
- `bluetooth.capnp` — Bluetooth devices, audio, mesh
- `nfc.capnp` — NFC tags, card emulation, peer-to-peer
- `sensor.capnp` — Sensors, telemetry
- `framebuffer.capnp` — Raw framebuffer access

### UI & Compositing (6)
- `compositor.capnp` — **Session interface only** — layers, cursor, DnD, input routing
- `windowmanager.capnp` — **Session interface only** — windows, workspaces, tiling, snapping
- `ime.capnp` — **Canonical text input** — Session, preedit, commit, virtual keyboard
- `clipboard.capnp` — Canonical clipboard service
- `notification.capnp` — Canonical notification service
- `settings.capnp` — Canonical settings service

### Data & Storage (8)
- `files.capnp` — **File I/O + mount/unmount + trash** (filesystem merged in)
- `storage.capnp` — Block devices, pools, volumes, snapshots, deduplication, compression
- `database.capnp` — Key-value, graph, vector, CRDT — no engine assumptions
- `backup.capnp` — Backup/restore
- `archive.capnp` — Compression, encryption, content-addressed
- `mount.capnp` — Mount orchestration, overlay, auto-mount, network mounts
- `ramfs.capnp` — Filesystem capability domain (ramfs, ext4, fatfs, ntfs, lcpfs backends)
- `filesystem.capnp` — **DEPRECATED** — merged into files.capnp

### Network & Communication (7)
- `network.capnp` — WiFi, ethernet, cellular, interfaces, DNS, DHCP, VPN, firewall
- `dns.capnp` — DNS resolution, DNSSEC, zone management
- `web.capnp` — HTTP, WebSocket, URL resolution
- `socket.capnp` — Connection API — TCP/UDP/Unix, proxy, TLS
- `tunnel.capnp` — Universal channels, transport-agnostic
- `endpoint.capnp` — Service endpoints, generic EndpointAddress
- `telephony.capnp` — Calls, SMS, modem

### Security & Identity (8)
- `auth.capnp` — Authentication, privilege escalation
- `access.capnp` — Access control, recovery
- `biometric.capnp` — Biometric enrollment, verification
- `secret.capnp` — Keyring, secrets, SecretRef
- `crypto.capnp` — Hashing, HMAC, KDF, AEAD, signatures, PQC
- `key_management.capnp` — Key lifecycle, generation, rotation, revocation
- `signature.capnp` — Signing, verification, policies
- `vcard.capnp` — Contact cards, parsing, export

### Apps & Intelligence (11)
- `app.capnp` — App lifecycle, intents, data sharing
- `appindex.capnp` — App discovery, launch, pinning
- `package.capnp` — Package management, repos, updates
- `extension.capnp` — Extension registration, capabilities, sandboxing
- `ai.capnp` — **AI/ML inference, model management, agent coordination, tensor ops, RAG, tool use**
- `speech.capnp` — STT, TTS
- `translation.capnp` — Text translation
- `contacts.capnp` — Address book
- `calendar.capnp` — Events, reminders, recurrence
- `content.capnp` — Encrypted content envelopes, key rotation
- `system_search.capnp` — Global search, provider registration

### Time & System (5)
- `timezone.capnp` — Timezone query, conversion, DST
- `update.capnp` — System updates, staged rollout, verification
- `power.capnp` — Battery, profiles, suspend, charging
- `print.capnp` — Printer discovery, print jobs
- `cli.capnp` — Command execution, shell access, custom commands

### Accessibility & Media (4)
- `accessibility.capnp` — Accessibility tree, roles, states
- `media.capnp` — Playback control (MPRIS-style)
- `capture.capnp` — Screenshots, screen recording
- `theme.capnp` — Semantic tokens, dark/light, accent

---

## What's NOT in the Protocol (By Design)

| Excluded | Reason |
|----------|--------|
| Scheduler algorithms | Internal to kernel |
| Page table structure | Internal to kernel |
| Filesystem implementations (ext4, btrfs, ZFS) | Backend concern |
| Network packet formats | Internal to network stack |
| Init dependency resolution algorithm | Internal to init |
| Cryptographic signing details | Backend concern (capability.proof is opaque) |
| Log output destinations (stdout, journal, file) | Backend concern |
| POSIX permission bits | Capability-based systems don't use them |

---

## Quick Start

```bash
# 1. Compile schemas (generates Rust types in gen/)
./scripts/regenerate.sh

# 2. Verify all schemas compile
./scripts/validate.sh

# 3. Use in Rust
# Cargo.toml:
# smart-protocol = { path = "../smart-protocol-official" }
# 
# In code:
use smart_protocol::types_capnp::*;
use smart_protocol::audio_capnp::*;
use smart_protocol::ai_capnp::*;

# 4. Use from CLI (requires smart-lib + smart CLI crates)
smart audio volume 75
smart apply my-setup.toml
smart --host 192.168.1.5 display brightness 80
```

---

## Schema Evolution Rules

1. **Ordinal stability** — Once published, an ordinal is permanent. Never reuse or reorder.
2. **Additive only** — New methods, types, enum variants, fields → minor version.
3. **Breaking = new schema ID** — Removing methods, changing signatures, changing field types → major version.
4. **Deprecate, don't delete** — `# Deprecated: use newMethod instead. Ordinal preserved.`
5. **Forward compatibility** — Every union MUST have `unknown @N :UnknownEvent { typeId: UInt64, payload: Data }`
6. **ABI negotiation** — Use `abi.capnp` to declare supported versions at startup.

---

## License

MIT OR Apache-2.0 (your choice)

---

## The Philosophy

> **We don't build for today's hardware. We don't build for today's OS. We don't build for today's languages.**
> 
> We build a contract that will still make sense in 20 years on hardware that doesn't exist yet, running an OS that hasn't been written, in a language that hasn't been invented — because the schema IS the API, and the wire IS the syscall.
> 
> **The protocol is the only thing that must never change. Everything else is replaceable.**
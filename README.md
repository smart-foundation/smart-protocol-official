# Smart Protocol

**A universal, zero-copy, language-agnostic system contract. The first protocol that makes OS boundaries transparent — for humans and AI alike.**

---

## What Makes This Different

| Traditional Approach | Smart Protocol |
|----------------------|----------------|
| Daemons (systemd, D-Bus, PulseAudio, etc.) | **Library-first, no daemons** |
| POSIX/Linux-specific syscalls | **Cap'n Proto IS the syscall** — no ioctl, no FFI |
| Linux/Windows/macOS separate APIs | **One contract, all platforms** (Linux, Windows, macOS, SpaceOS, bare metal, WASM) |
| Human CLIs vs Machine APIs | **Same protocol for humans AND AI agents** |
| C/C++ only, or language-specific bindings | **10+ languages** (Rust, C, C++, Python, JS, Go, Swift, bash, TOML, `.smart` scripts) |
| Config files, scripts, APIs all separate | **6 unified shapes** — library, CLI, config, script, IPC, network |
| Version hell, breaking changes | **Forward-compatible forever** — ordinals are permanent, unions have `unknown` |
| Daemons, context switches, copies | **Zero-copy, zero-cost** — Cap'n Proto zero-copy, monomorphized, no vtables |

---

## The Six Shapes — All Equal, All Speaking the Same Language

```
┌─────────────────────────────────────────────────────────────────┐
│                      Smart Protocol                             │
├──────────────┬──────────────┬──────────────┬───────────────────┤
│   LIBRARY    │     CLI      │     IPC      │     CONFIG        │
│   link &     │   `smart`    │   capnp over │   TOML/JSON       │
│   call       │   command    │   shared mem │   `smart apply`   │
├──────────────┼──────────────┼──────────────┼───────────────────┤
│   NETWORK    │    SCRIPT    │              │                   │
│   TCP/WS     │   `.smart`   │              │                   │
│   remote     │   script     │              │                   │
└──────────────┴──────────────┴──────────────┴───────────────────┘
```

**Every shape is equal.** An AI agent calling over TCP has the same power as a human typing `smart audio volume 75`.

---

## The 89 Capability Domains — Complete System Coverage

### Foundation (3)
`types.capnp` `capability.capnp` `abi.capnp` — Foundation types, capability system, ABI negotiation

### Kernel & Boot (4)
`kernel.capnp` `boot.capnp` `hal.capnp` `init.capnp` — **Entire kernel API**, boot handoff, hardware affordances, pure service orchestrator

### System Services (12)
`system` `service` `process` `session` `discovery` `logging` `diagnostics` `klog` `time` `queue` `signal` `task_scheduler`

### Hardware & Devices (10)
`device` `display` `audio` `input` `camera` `usb` `bluetooth` `nfc` `sensor` `framebuffer`

### UI & Compositing (6)
`compositor` `windowmanager` `ime` `clipboard` `notification` `settings` — **Session interfaces only**, no flat duplicates

### Data & Storage (7)
`files` `storage` `database` `backup` `archive` `mount` `ramfs`

### Network & Communication (7)
`network` `dns` `web` `socket` `tunnel` `endpoint` `telephony`

### Security & Identity (8)
`auth` `access` `biometric` `secret` `crypto` `key_management` `signature` `vcard`

### Apps & Intelligence (11)
`app` `appindex` `package` `extension` **`ai`** `speech` `translation` `contacts` `calendar` `content` `system_search`

### Time & System (5)
`timezone` `update` `power` `print` `cli`

### Accessibility & Media (4)
`accessibility` `media` `capture` `theme`

**Plus:** `ai.capnp` — **NEW** — AI/ML inference, model management, agent coordination, RAG, tool use

---

## Crates

| Crate | Purpose | Required |
|-------|---------|----------|
| `smart-protocol` | Cap'n Proto schemas + generated types + SmartBackend trait | Yes |
| `smart-lib` | Platform backends (Linux, Windows, macOS, etc.) | Optional |
| `smart` | CLI binary | Optional |

---

## Protocol Shapes

Smart Protocol exists in 6 shapes, all speaking the same language:

```bash
# Library (Rust)
let state = smart_lib::audio::get_state()?;
smart_lib::audio::set_volume(0.75)?;

# C - link libsmart
smart_audio_get_state(&state);
smart_audio_set_volume(0.75);

# CLI
$ smart audio volume 75
$ smart power battery --json
$ smart window list --json | jq '.[0].title'

# IPC over Unix socket
$ smart --socket /run/smart.sock audio volume

# Config file
$ smart apply my-setup.toml

# Network (TCP)
$ smart --host 192.168.1.5 audio volume 50

# Script
$ smart run morning-routine.smart
```

---

## SmartBackend Trait

The `SmartBackend` trait in `smart-protocol` defines the interface:

```rust
pub trait SmartBackend {
    fn audio_get_state(&self) -> Result<AudioState, SmartError>;
    fn audio_set_volume(&self, device: &str, volume: f32) -> Result<(), SmartError>;
    fn display_get_monitors(&self) -> Result<Vec<Monitor>, SmartError>;
    // ... 459 methods across 47 domains
}
```

---

## Platform Detection

Smart-lib automatically detects:
- **Session type**: X11 vs Wayland
- **Hardware type**: Laptop (battery) vs Desktop (wall power)
- **Package managers**: apt, pacman, dnf, zypper, apk, xbps, yay, pkg, flatpak, snap, brew, nix-env, emerge, eopkg, swupd, bpkg, nala

---

## Error Handling

All errors flow through `SmartError`:

```rust
pub enum SmartError {
    NotFound,
    PermissionDenied,
    Failed(String),
    Unavailable,
    NotSupported,
    MissingTool { tool, package, install_hint },
    // ... more variants
}
```

---

## Quick Start

```bash
# Build
git clone https://github.com/smart-foundation/smart-protocol-official
cd smart-protocol-official
./scripts/regenerate.sh        # Generates Rust bindings in gen/
./scripts/validate.sh          # Validates all 92 schemas

# Use in Rust
# Cargo.toml:
# smart-protocol = { path = "../smart-protocol-official" }

use smart_protocol::types_capnp::*;
use smart_protocol::audio_capnp::*;
use smart_protocol::ai_capnp::*;

# From CLI (requires smart-lib + smart CLI crates)
smart audio volume 75
smart apply my-setup.toml
smart --host 192.168.1.5 display brightness 80

# AI agent usage — same protocol, same interfaces
# AI uses InferenceService.complete() exactly like CLI uses audio.set_volume()
```

---

## Schema Evolution — Never Breaks

1. **Ordinal stability** — Once published, an ordinal is permanent
2. **Additive only** — New methods/types/fields → minor version
3. **Breaking = new schema ID** — New `@0x...` for major changes
4. **Deprecate, don't delete** — `# Deprecated: use X instead. Ordinal preserved.`
5. **Forward compatibility** — Every union has `unknown @N :UnknownEvent { typeId: UInt64, payload: Data }`
6. **ABI negotiation** — `abi.capnp` declares supported versions at startup

---

## Architecture

```
Layer 7: Applications      → Gallery, Panel, Terminal, File Manager, AI Agent
Layer 6: SmartUI           → 13 crates, DSL, reactive, rendering
Layer 5: smart-superset    → Platform backends (fonts, files, audio, etc.)
Layer 4: smart-protocol    → 89 schemas, universal contract
Layer 3: SpaceOS services  → Compositor, WM, Shell (all speak protocol)
Layer 2: SpaceOS kernel    → HelenOS fork, capabilities, IPC
Layer 1: Hardware          → Framebuffer, input devices, storage
```

**We control EVERY layer. We can optimize EVERY layer. We can change ANY layer without breaking others.**

---

## The Philosophy

### The Agnostic/Timeless Test
> **"Is this an EXTERNAL contract (how components interoperate) or an INTERNAL implementation (how a component works)?"**

If it's internal — it stays OUT of the protocol.

### The Opacity Principle
Push types left (opaque) when consumers don't inspect structure:
- `ProcessId { id: UInt64 }` ✓ — not PID, not TCB, just a reference
- `FileHandle { handle: UInt64 }` ✓ — not path, not mode, just a capability

### The Swap Test
**Can you swap Linux → seL4 → custom kernel → WASM runtime without changing the protocol?**
- If no → the schema leaks implementation

---

## Status

- **92 schemas** — All compile, all validated
- **Zero platform leaks** — No POSIX, Linux, x86 nouns in required enums
- **AI-first** — `ai.capnp` for inference, agents, RAG, tools
- **Vertical integration** — Kernel to AI, all one protocol

---

## The Philosophy

> **We don't build for today's hardware. We don't build for today's OS. We don't build for today's languages.**
> 
> We build a contract that will still make sense in 20 years on hardware that doesn't exist yet, running an OS that hasn't been written, in a language that hasn't been invented — because the schema IS the API, and the wire IS the syscall.
> 
> **The protocol is the only thing that must never change. Everything else is replaceable.**

---

## License

MIT OR Apache-2.0 (your choice)
# Timelessness Design Rationale

This document explains the design principles that make Smart Protocol timeless — able to survive hardware, OS, and language changes for decades.

---

## The Core Philosophy

> **The protocol is the only thing that must never change. Everything else is replaceable.**

Smart Protocol is not a library, not a daemon, not an OS. It is the **contract** that makes everything else interoperate.

---

## The Agnostic/Timeless Test

Every proposed addition must pass this test:

> **"Is this an EXTERNAL contract (how components interoperate) or an INTERNAL implementation (how a component works)?"**

| External Contract (KEEP) | Internal Implementation (REJECT) |
|--------------------------|----------------------------------|
| "Resolve this hostname" | "Use systemd-resolved" |
| "Allocate 512MB for this service" | "Create cgroup with memory.max=512M" |
| "Send audio to this device" | "Open PulseAudio stream" |
| "Allocate GPU memory" | "Call ioctl DRM_IOCTL_GEM_CREATE" |

**Rule:** If it describes HOW a component works internally, it belongs inside the component. If it describes WHAT two components exchange to interop, it belongs in the protocol.

---

## The Opacity Principle

**Push types as far left (opaque) as possible.**

```
FULLY OPAQUE                                              FULLY STRUCTURED
   │                                                              │
   ▼                                                              ▼
UInt64    Data    Text        Enum       Struct with    Struct with
 (id)      (bytes) (string)    (finite)    fixed fields   variable fields
                                                 (List, union)
   │         │         │          │              │              │
   ▼         ▼         ▼          ▼              ▼              ▼
ProcessId  CapId    DeviceName  OpenMode    Rect, Vec2    StringMap
WindowId   proof    LayoutId    ErrorCode   BatteryState  Meta
BufferId                                          AudioFormat
```

**Rule of thumb:** Only make types structured when consumers MUST read/write specific fields to interoperate. Otherwise, use opaque `UInt64`, `Data`, or `Text`.

---

## The Swap Test

**Can you swap implementations without changing the protocol?**

| Swap | Protocol Still Works? | Evidence |
|------|----------------------|----------|
| Linux kernel → seL4 microkernel | ✅ Yes | `kernel.capnp` defines spawn, signal, memory regions. seL4 has capabilities natively. |
| PipeWire → custom Rust audio server | ✅ Yes | `audio.capnp` defines devices, streams, volume. |
| ext4 → distributed filesystem (Ceph) | ✅ Yes | `files.capnp` defines open/read/write/stat. |
| X11 → Wayland → custom compositor | ✅ Yes | `compositor.capnp` defines surfaces, commits, input events. |
| systemd → runit → s6 | ✅ Yes | `init.capnp` defines service lifecycle (start/stop/restart/state). |

**If a swap breaks the protocol, the protocol leaks implementation.**

---

## What We Explicitly Reject

### Platform-Specific Types
| Rejected | Reason | Replacement |
|----------|--------|-------------|
| `inode`, `device` (files) | Filesystem internals | Opaque `FileHandle` + `FileInfo` query |
| `zombie`, `defunct` (process) | POSIX-specific | Universal: `active`, `blocked`, `suspended`, `terminated` |
| `stdout`, `stderr`, `journal` (logging) | Backend-specific | Opaque `Data` target |
| `cr3`, `HHDM` (kernel) | x86-specific | `pageTableRoot`, `bootstrapPointer` |
| `systemd`, `syslinux` (boot) | Product names | `BootloaderKind { limine, grub, uefiDirect, custom }` |

### Implementation Details
| Rejected | Reason |
|----------|--------|
| Scheduler algorithm hints | Kernel internal |
| Page size, TLB entries | Hardware internal |
| Network packet framing | Transport internal |
| Cryptographic signing details | Backend concern (capability.proof is opaque) |
| Init dependency resolution algorithm | Init internal |

---

## Schema Evolution Rules (Guarantees Timelessness)

1. **Ordinal stability** — Once published, an ordinal is permanent. Never reuse or reorder.
2. **Additive only** — New methods, types, enum variants, fields → minor version.
3. **Breaking = new schema ID** — Removing methods, changing signatures, changing field types → major version (new `@0x...`).
4. **Deprecate, don't delete** — `# Deprecated: use newMethod instead. Ordinal preserved for wire compatibility.`
5. **Forward compatibility** — Every union MUST have `unknown @N :UnknownEvent { typeId: UInt64, payload: Data }`
6. **ABI negotiation** — Use `abi.capnp` to declare supported versions at startup.

---

## The Six Shapes Equality

No shape is primary. All six are equal:

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

An AI agent using the network shape has the same power as a human using the CLI.

---

## Zero-Cost, No Runtime Diffing

- **Cap'n Proto zero-copy**: Messages read directly from wire. No serialization/deserialization step.
- **No runtime diffing**: No virtual DOM, no tree diffing. Retained mode: explicit mutations only.
- **Compiler is the only authority**: Monomorphization, not vtables.
- **No heap in hot path**: Pre-allocated arenas, slot-indexed lookup.

---

## Capability System IS the Access Control

- No permission strings, no RBAC, no boolean flags
- Methods that need authority take `Capability` parameter
- Verification is backend concern; protocol only specifies contract

```capnp
interface MyService {
    doSensitiveThing @0 (cap :Capability, request :SensitiveRequest) 
                     -> (result :SensitiveResult);
}
```

---

## Schema Structure Template

Every schema follows this structure:

```capnp
@0x<unique_hex_id>;

# ════════════════════════════════════════════════════════════════════════
# <ServiceName> - <one-line description>
#
# 1. What this service IS (the contract, not the implementation)
# 2. Who consumes it (apps, other services, the kernel)
# 3. What is deliberately left opaque (implementation freedom)
# 4. How it relates to other services
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ── Types ─────────────────────────────────────────────────────────────
# IDs first, then data structs, then enums, then events.

# ── Interface ─────────────────────────────────────────────────────────
interface <ServiceName> {
    # Session-based services start with handshake:
    # handshake @0 (...) -> (...);

    # Methods organized by concern, ordinals assigned sequentially.
}

# ── Events ────────────────────────────────────────────────────────────
# Event types and subscription interface (pull-based, UInt64 subscription IDs).

# ── Capabilities ──────────────────────────────────────────────────────
# What authority this service requires/grants.
```

---

## Summary

**Smart Protocol is timeless because:**
1. It only defines **external contracts**, never internal implementations
2. It uses **opaque types** wherever possible
3. It passes the **Swap Test** for every major component
4. It **rejects platform nouns** from required enums
4. It has **strict evolution rules** that guarantee forward compatibility
5. It treats **all six shapes equally** — no privileged access path
6. It has **zero-cost serialization** with no runtime diffing

**The protocol is the only thing that must never change. Everything else is replaceable.**
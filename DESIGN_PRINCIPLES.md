# smart-protocol Design Principles

> Version 1.0 · Established 2026-07-01
> Amended 2026-10-10 — pre-release carve-out for schema evolution, the
> authority-reference precedent, and the validator's tree-wide gate (E1–E14).
> Purpose: Governs all schema design, evolution, and review for smart-protocol.

---

## Table of Contents

1. [The Agnostic/Timeless Test](#1-the-agnostictimeless-test)
2. [The Opacity Principle](#2-the-opacity-principle)
3. [Anti-Patterns Found in Existing Schemas](#3-anti-patterns-found-in-existing-schemas)
4. [Schema Template](#4-schema-template)
5. [The Swap Test](#5-the-swap-test)
6. [Appendix: Schema-by-Schema Verdicts](#6-appendix-schema-by-schema-verdicts)

---

## 1. The Agnostic/Timeless Test

Every proposed addition to smart-protocol must pass this test before it is accepted.

### The Question

**"Is this an EXTERNAL contract (how components interoperate) or an INTERNAL implementation (how a component works)?"**

If it is an external contract, it belongs in the protocol. If it is an internal implementation, it belongs inside the component.

### Decision Framework

```
                    ┌─────────────────────────────────────┐
                    │  Does this describe HOW a component  │
                    │  implements its behavior internally?  │
                    └──────────────┬──────────────────────┘
                                   │
                          ┌────────┴────────┐
                          │                 │
                         YES                NO
                          │                 │
                          ▼                 ▼
                  ┌──────────────┐  ┌──────────────────────┐
                  │  KEEPS OUT   │  │  Does this describe  │
                  │  (not in     │  │  WHAT two components  │
                  │   protocol)  │  │  exchange to interop? │
                  └──────────────┘  └──────────┬───────────┘
                                               │
                                      ┌────────┴────────┐
                                      │                 │
                                     YES                NO
                                      │                 │
                                      ▼                 ▼
                              ┌──────────────┐  ┌──────────────────┐
                              │  KEEPS IN    │  │  Am I sure?       │
                              │  (protocol   │  │  Re-evaluate with │
                              │   contract)  │  │  the Swap Test.   │
                              └──────────────┘  └──────────────────┘
```

### Clear Examples

| Proposal | Verdict | Reasoning |
|----------|---------|-----------|
| "Add a scheduler interface" | **KEEPS OUT** | Whether the kernel uses CFS, deadline scheduling, actor model, or dataflow is internal. The protocol defines what tasks exist and their state, not how they are scheduled. |
| "Add page table management" | **KEEPS OUT** | Page table structure is a kernel-internal memory management detail. The protocol exposes memory regions and permissions, not PT hierarchy. |
| "Add DNS resolution service" | **KEEPS IN** | Any component needing network access must resolve hostnames. This is an external contract: "resolve this name, get an address." How the resolver works (cached, forwarded, distributed) is internal. |
| "Add socket API" | **KEEPS IN** | Creating network connections is a cross-cutting concern. How the kernel implements sockets (TCP stack, io_uring, capability-based) is internal. The contract is: "open a connection to this endpoint." |
| "Add interrupt dispatch" | **KEEPS OUT** | How the kernel routes interrupts to handlers is internal. HAL describes the affordances (subscribe to IRQ vector), not the dispatch mechanism. |
| "Add process group/session management" | **KEEPS IN** | Grouping processes for signal delivery and lifecycle control is an external contract. How the kernel tracks process groups internally is irrelevant. |
| "Add quota/resource limits" | **KEEPS IN** | Declaring "this service gets 512MB max" is an external contract between the resource consumer and the resource provider. How enforcement happens is internal. |
| "Add audit logging service" | **KEEPS IN** | Recording who did what to which resource is a cross-cutting concern that multiple components need. Where logs are stored is internal. |
| "Add CFS scheduler tuning knobs" | **KEEPS OUT** | This is Linux-specific and kernel-internal. |
| "Add inotify watch limits" | **KEEPS OUT** | inotify is a Linux implementation detail. The protocol defines file watching as a contract. |

### Edge Cases and Resolution

**Edge Case 1: "Should we expose thread scheduling priority?"**

The protocol should define *what priority means to the caller* (e.g., "this task is latency-critical" vs "this task is background"), NOT how the kernel maps that to scheduling classes. The current `priorityHint @6 :Int8` in `SpawnRequest` is correct: it is a hint, not an instruction.

Resolution: Accept if it describes intent. Reject if it describes mechanism.

**Edge Case 2: "Should we define memory page sizes?"**

No. Page size is kernel-internal. The protocol defines "map this region with these permissions" and the kernel picks page sizes, alignment, and backing.

Resolution: Reject. Memory region specs describe intent (base, length, perms), not implementation (page size, TLB entries, cache lines).

**Edge Case 3: "Should we define network packet formats?"**

No. Packet framing is internal to the network stack. The protocol defines "send this data to this endpoint" and "receive data from this endpoint."

Resolution: Reject. The contract is the message, not the wire format.

**Edge Case 4: "Should we define how capabilities are cryptographically signed?"**

No. The protocol defines what a capability grants (operations, target, constraints). How it is signed, stored, and verified is backend-specific. The `proof @3 :Data` field in `Capability.Audit` is deliberately opaque.

Resolution: Accept the contract. Reject the mechanism.

**Edge Case 5: "Should we define how the init system resolves dependencies?"**

No. Whether init uses a dependency graph, a declarative order, or parallel boot with retry is internal. The protocol defines what services exist, their state, and lifecycle events.

Resolution: Reject the algorithm. Accept the observable state.

### The Litmus Test Questions

Before adding anything to smart-protocol, answer these:

1. **Can two completely different implementations satisfy this contract?** If no, it is too specific.
2. **Does a consumer need this to interoperate with a provider?** If no, it is not a protocol concern.
3. **Is this describing data that crosses a trust boundary?** If no, it belongs inside the component.
4. **Will this still make sense in 10 years on different hardware?** If no, it is an implementation detail.
5. **Would swapping the underlying implementation break the contract?** If yes, the contract leaks implementation.

---

## 2. The Opacity Principle

### The Rule

**A type should be opaque (UInt64, Data, Text) when its internal representation varies across implementations and consumers never need to inspect its structure.**

**A type should be structured (struct with named fields) when consumers must read or write specific fields to interoperate.**

### The Decision Tree

```
                    ┌─────────────────────────────────────┐
                    │  Do consumers need to inspect the   │
                    │  internal structure of this value?   │
                    └──────────────┬──────────────────────┘
                                   │
                          ┌────────┴────────┐
                          │                 │
                         YES                NO
                          │                 │
                          ▼                 ▼
                  ┌──────────────┐  ┌──────────────────────┐
                  │  STRUCTURED  │  │  Could the internal  │
                  │  (named      │  │  representation vary  │
                  │   fields)    │  │  across backends?     │
                  └──────────────┘  └──────────┬───────────┘
                                               │
                                      ┌────────┴────────┐
                                      │                 │
                                     YES                NO
                                      │                 │
                                      ▼                 ▼
                              ┌──────────────┐  ┌──────────────┐
                              │  OPAQUE      │  │  STRUCTURED  │
                              │  (UInt64,    │  │  (fixed      │
                              │   Data,Text) │  │   fields)    │
                              └──────────────┘  └──────────────┘
```

### Application to 10 Existing Types

| Type | Current Form | Verdict | Rationale |
|------|-------------|---------|-----------|
| **ProcessId** | `struct { id @0 :UInt64; }` | ✅ **Correct (opaque)** | Different kernels have different process models. A UInt64 is sufficient for consumers to reference a process. The struct wrapper adds type safety without leaking internals. |
| **FileHandle** | `struct { handle @0 :UInt64; path @1 :Text; mode @2 :OpenMode; }` | ⚠️ **Partially wrong** | The `handle` field is correct (opaque). But `path` and `mode` leak implementation details: a capability-based system may not have path-based handles; a microkernel may not expose mode at handle creation. **Fix:** Keep handle opaque. Move path/mode to a separate `FileInfo` query. |
| **Capability.id** | `@0 :Data` | ✅ **Correct (opaque)** | Content-addressed identifier. Backend decides format (ed25519, HMAC, UUID). Consumers never parse it. |
| **AudioDevice.id** | `@0 :Text` | ⚠️ **Should be opaque UInt64 or Data** | Text IDs are fragile (strings change across versions). An opaque numeric or byte identifier is more robust. The `name` field already serves human-readable identification. |
| **InputDevice.id** | `@0 :UInt64` | ✅ **Correct (opaque)** | Referenced by number, never inspected. |
| **TunnelHandle** | `struct { id @0 :UInt64; subject @1 :Text; }` | ⚠️ **Subject should be separate** | The `id` is correctly opaque. But `subject` leaks routing internals. The subject is part of the tunnel specification, not the handle. A handle should be a pure reference. **Fix:** Remove `subject` from handle; it belongs in `TunnelSpec` and `TunnelInfo`. |
| **WindowId** | `struct { id @0 :UInt64; }` | ✅ **Correct (opaque)** | Window identity is backend-specific. Consumers only need to reference windows. |
| **BufferId** | `struct { id @0 :UInt64; }` | ✅ **Correct (opaque)** | Buffer identity is backend-specific. |
| **NotificationId** | `struct { id @0 :UInt64; }` | ✅ **Correct (opaque)** | |
| **NodeId** | `struct { id @0 :UInt64; }` | ✅ **Correct (opaque)** | Node identity in a distributed system is inherently opaque. |

### Additional Types to Fix

| Type | Current Form | Issue | Fix |
|------|-------------|-------|-----|
| **FilePermissions** | `struct { owner @0 :UInt8; group @1 :UInt8; other @2 :UInt8; }` | POSIX-specific. Capability-based systems don't have owner/group/other. | Replace with `Data` (opaque capability tokens) or a `List(Permission)` enum (read, write, execute, administer). |
| **ProcessState** | `enum { running, sleeping, waiting, stopped, zombie, defunct }` | POSIX-specific. A capability-based kernel has no "zombie" state. An actor system has no "sleeping" state. | Keep the enum but rename states to be universal: `active`, `blocked`, `suspended`, `terminated`. Remove POSIX-isms. **DONE 2026-10-10:** one canonical `T.ExecutionState` in types.capnp, shared by kernel.capnp, process.capnp and the lifecycle schemas. |
| **UserInfo.id** | `@0 :UInt32` | Too small for distributed systems. Unix uid is 32-bit. | Use `UInt64` or opaque type. |
| **DiskUsage** | `struct { total, used, free, percentUsed, mountPoint, filesystem }` | `mountPoint` and `filesystem` are implementation details. | Keep total/used/free. Move mountPoint/filesystem to a separate `MountInfo` query. |
| **LogSource** | `struct { file, line, function }` | Implementation-specific (assumes compiled languages). | Make opaque: `source @0 :Data` (backend-decided format). |

### The Opacity Spectrum

Types fall on a spectrum from fully opaque to fully structured:

```
FULLY OPAQUE                                              FULLY STRUCTURED
   │                                                              │
   ▼                                                              ▼
UInt64    Data    Text        Enum       Struct with    Struct with
(id)      (bytes) (string)    (有限集)    fixed fields   variable fields
                                                      (List, union)
   │         │         │          │              │              │
   ▼         ▼         ▼          ▼              ▼              ▼
ProcessId  CapId    DeviceName  OpenMode    Rect, Vec2    StringMap
WindowId   proof    LayoutId    ErrorCode   BatteryState  Meta
BufferId                                          AudioFormat
```

**Rule of thumb:** Push types as far left (opaque) as possible. Only move right (structured) when consumers demonstrably need to read specific fields for interoperability.

---

## 3. Anti-Patterns Found in Existing Schemas

### Category A: Duplicate/Conflicting Interfaces

| Schemas | Conflict | Severity | Resolution |
|---------|----------|----------|------------|
| `ime.capnp` (Session) vs `textinput.capnp` (TextInput) | Both define IME context management, input method listing, preedit/commit. `ime.capnp` is the newer Session-based design. `textinput.capnp` is the older flat design. | 🔴 High | **DONE 2026-10-10:** `textinput.capnp` deleted; unique pieces absorbed into `ime.capnp`. |
| `files.capnp` (Files) vs `filesystem.capnp` (Filesystem) | Both define `getSpecialPath`, file operations. `files.capnp` is comprehensive (30 methods). `filesystem.capnp` adds mount/unmount and trash. | 🔴 High | **DONE 2026-10-10:** `filesystem.capnp` deleted; mount/unmount and trash merged into `files.capnp`. |
| `session.capnp` (Session) vs `compositor.capnp` (Session) vs `shell.capnp` (Session) vs `ime.capnp` (Session) vs `buffer.capnp` (BufferSession) vs `windowmanager.capnp` (Session) | Six different `Session` interfaces across schemas. Each is a service-specific handshake. This is acceptable IF each represents a distinct service domain. | 🟡 Medium | **Accept but rename for clarity.** Each `Session` is scoped to its service domain. Consider whether a universal `ServiceSession` pattern could unify the handshake. But do NOT merge domains (compositor ≠ shell ≠ IME). |
| `surface.capnp` (Surface) vs `compositor.capnp` (Session surface management) | `surface.capnp` defines a standalone Surface interface. `compositor.capnp` Session also manages surfaces. Overlapping responsibilities. | 🔴 High | **DONE 2026-10-10:** `surface.capnp` deleted; surface management lives in `compositor.capnp` Session. |
| `buffer.capnp` (Buffer) vs `buffer.capnp` (BufferSession) | Two interfaces in the same file. `Buffer` is the older flat design. `BufferSession` is the newer handshake design. | 🟡 Medium | **Deprecate `Buffer`.** Keep `BufferSession`. Same pattern as compositor (old flat interface coexists with new Session interface during transition). |
| `compositor.capnp` (Compositor) vs `compositor.capnp` (Session) | Two compositor interfaces in the same file. `Compositor` is the older flat design. `Session` is the newer handshake design. | 🟡 Medium | **Deprecate `Compositor`.** Keep `Session`. |
| `windowmanager.capnp` (WindowManager) vs `windowmanager.capnp` (Session) | Same pattern: old flat + new Session. | 🟡 Medium | **Deprecate `WindowManager`.** Keep `Session`. |
| `notification.capnp` (Notifications) vs `shell.capnp` Shell Notification methods | `notification.capnp` defines a standalone Notifications interface. `shell.capnp` also has notification management (lines 55-67). | 🟡 Medium | **Clarify ownership.** `notification.capnp` should be the canonical notification service. `shell.capnp` should delegate to it, not duplicate it. Shell's notification methods should be thin wrappers or removed. |
| `clipboard.capnp` (Clipboard) vs `shell.capnp` Shell Clipboard methods | Same pattern as notifications. | 🟡 Medium | **Same resolution.** `clipboard.capnp` is canonical. Shell delegates. |
| `settings.capnp` (Settings) vs `shell.capnp` Shell Settings methods | Same pattern. | 🟡 Medium | **Same resolution.** |

### Category B: Over-Specification (Dictating HOW, not WHAT)

| Schema | Line(s) | Issue | Severity | Fix |
|--------|---------|-------|----------|-----|
| `logging.capnp` | `LogFormat` enum (text, json, xml) | Dictates output format. A logging backend may use binary, CBOR, protobuf, or custom formats. | 🔴 High | **DONE 2026-10-10:** `LogFormat`/`LogOutput` deleted, `LogSource` opaque. |
| `logging.capnp` | `LogOutput` enum (stdout, stderr, syslog, journal, file) | Dictates output destination. Backend-specific. | 🔴 High | **DONE 2026-10-10:** `LogOutput` deleted. |
| `logging.capnp` | `LogSource` struct (file, line, function) | Assumes compiled languages with source files. WASM, interpreted, and JIT languages don't have this. | 🟡 Medium | **DONE 2026-10-10:** `LogSource` made opaque (`source @0 :Data`). |
| `files.capnp` | `FilePermissions` struct (owner/group/other as UInt8) | POSIX-specific permission model. Capability-based systems don't use this. | 🔴 High | **DONE 2026-10-10:** `FilePermissions` removed; permissions are capability-gated, not POSIX modes. |
| `files.capnp` | `ExtendedMetadata.inode @15 :UInt64` | inode is a filesystem implementation detail. Distributed filesystems don't have inodes. | 🟡 Medium | **DONE 2026-10-10:** no `inode`/`device` fields; backend internals live in `metadata @16 :T.StringMap`. |
| `files.capnp` | `ExtendedMetadata.device @16 :UInt64` | Device number is Linux-specific. | 🟡 Medium | **DONE 2026-10-10:** removed. |
| `process.capnp` | `ProcessState` enum (running, sleeping, waiting, stopped, zombie, defunct) | POSIX-specific states. "zombie" and "defunct" are Unix process lifecycle details. | 🟡 Medium | **DONE 2026-10-10:** `T.ExecutionState` canonical, shared tree-wide. |
| `process.capnp` | `ThreadInfo.state @2 :Text` | Thread states are backend-defined but exposing as raw Text is too vague. | 🟢 Low | Define a `ThreadState` enum with universal states. |
| `session.capnp` | `UserInfo.id @0 :UInt32` | Unix uid is 32-bit. Distributed systems need larger. | 🟢 Low | **DONE 2026-10-10:** `id @0 :T.UserId` (not a POSIX uid). |
| `session.capnp` | `UserInfo.shell @4 :Text` | Assumes Unix shell concept. | 🟢 Low | **DONE 2026-10-10:** no `shell` field in `UserInfo`. |
| `windowmanager.capnp` | `Window.pid @15 :UInt32` | Too small for distributed systems. Also, not all window systems have PIDs. | 🟡 Medium | **DONE 2026-10-10:** `processId @15 :T.ProcessId`. |
| `windowmanager.capnp` | `WindowFilter.processId @6 :UInt32` | Same issue. | 🟡 Medium | **DONE 2026-10-10:** `processId @6 :T.ProcessId`. |

### Category C: Under-Specification (Missing Contracts)

| Missing Contract | Why It Matters | Priority |
|-----------------|----------------|----------|
| **DNS resolution service** | Any component doing networking needs hostname resolution. Without a protocol-level contract, each implementation reinvents this. | 🔴 High |
| **Socket/connection API** | TCP/UDP/network connections are fundamental. The protocol defines `network.capnp` for interface management but not for creating connections. | 🔴 High |
| **Process group/session management** | Grouping processes for signal delivery and lifecycle control is essential for service management. | 🟡 Medium |
| **Resource quota/limits** | Declaring resource constraints (CPU, memory, file descriptors) is a cross-cutting contract between consumers and providers. | 🟡 Medium |
| **Audit logging** | Recording security-relevant events is a cross-cutting concern. Multiple services need to emit audit events. | 🟡 Medium |
| **Time synchronization** | `time.capnp` exists but doesn't address NTP/PTP synchronization contracts. | 🟢 Low |

### Category D: Structural Inconsistencies

| Pattern | Where It Appears | Issue | Fix |
|---------|-----------------|-------|-----|
| **Subscription: pull-based interface** | Most schemas (audio, display, power, etc.) | `interface XSubscription { pull @0 () -> ...; }` | ✅ This is the canonical pattern. Keep it. |
| **Subscription: stream-based interface** | compositor, ime, shell | `interface XEventStream { next @0 () -> ...; cancel @1 (); }` | ⚠️ Two subscription patterns coexist. Standardize on pull-based for consistency, or document when stream-based is preferred (e.g., for ordered event delivery with cancellation). |
| **Error handling: VoidResult** | Most schemas | `T.VoidResult` union with success/error | ✅ Canonical. Keep it. |
| **Error handling: custom results** | buffer.capnp, compositor.capnp | `BufferResult`, `DragStartResult` with custom success variants | ⚠️ Acceptable when the success case carries data. But ensure error cases always use `T.Error`. |
| **Handshake pattern** | compositor, shell, ime, buffer, windowmanager | `handshake @0 (...) -> (...)` as first method | ✅ Good pattern for session-based services. Ensure all new session-based services follow this. |
| **No handshake** | audio, display, input, network, etc. | Flat interface, no session establishment | ⚠️ Acceptable for stateless services. But document why a service doesn't need a handshake. |
| **Query pattern** | compositor, shell, windowmanager | `query @N (...) -> (...)` with union-based dispatch | ✅ Good for extensible interrogation. Ensure query types have a `custom` variant for forward compatibility. |
| **No query pattern** | Most other schemas | No way to interrogate service capabilities | 🟡 Consider adding a query method to services that have complex capability surfaces. |

---

## 4. Schema Template

### The gate: scripts/validate.py

Every rule in this document that can be checked mechanically is checked, and the
check is the gate. `scripts/validate.py` parses the schemas with a real parser
(it strips comments first, so a phrase in prose is not a violation) and enforces:

| Rule | What it enforces |
|------|------------------|
| E1 | `ai.capnp` declares zero enums. |
| E2 | `ai.capnp` has no bulk lists — payload is `T.DataHandle`. |
| E3 | `Capability` appears only on `interface AI` accessors. |
| E4 | Every interface is reachable. |
| E5 | Every stream's `pull` returns a structural terminator. |
| E6 | Every union has an `unknown`/`custom` variant, EXCEPT a union whose non-success arm is `T.Error` — the error model this document defines below is itself the extension point, so a further arm would be noise. The three terminal result unions are named. |
| E7 | Every struct has an open extension point (value structs exempt). |
| E8 | Every enum's `@0` is a neutral sentinel (not applied where a default is harmless — see audit-verification O4). |
| E9 | No platform, vendor or POSIX noun in a required position (R5). |
| E10 | No bulk payload outside `T.DataHandle` (R2). |
| E11 | Authority is the reference — no per-method token, no authority-by-string (R3). |
| E12 | One canonical home per type name (R6). |
| E13 | Interface method ordinals are sequential and declared in order. |
| E14 | Every interface is reachable and no declared type is unreferenced (R8). |

E1–E5 are ERROR for `ai.capnp` and REPORT elsewhere; E6–E14 are REPORT for the
other schemas, so the tree stays green while other waves land. The target is zero
in every rule, for every schema. A schema that adds a finding must justify it in
its own header.

Two rule E5/E7 scoping decisions are doctrine, not oversight: event subscriptions
are terminated by `cancel` (a terminator field would contradict the protocol's own
subscription convention), and value structs — `AckHandle`, `TimeBox`, `Rect`,
`Timestamp` — are complete by construction, so forcing an extension point onto
them would bloat every message for no gain.

Two further scoping decisions, both doctrine: **reachability (E14)** counts an
interface taken as a *parameter* as reachable — a provider-registered callback
(`registerAuthMethod(handler :AuthHandler)`) is reachable because the caller
supplies an implementation and the peer calls it; and **one canonical home (E12)**
is satisfied by ELIMINATION, not by exemption — the 2026-10-10 integration pass
resolved every same-name-different-file type by giving one side the canonical
name and having the other side import it (or, where the two shapes were
materially different, by disambiguating both names), so the rule has zero
findings with no sanctioned-exception list to maintain.
### Canonical Schema Structure

Every smart-protocol schema should follow this structure:

```capnp
@0x<unique_hex_id>;

# ═══════════════════════════════════════════════════════════════════════
# <ServiceName> - <one-line description of what this contract governs>
#
# <2-5 sentences explaining:
#   1. What this service IS (the contract, not the implementation)
#   2. Who consumes it (apps, other services, the kernel)
#   3. What is deliberately left opaque (implementation freedom)
#   4. How it relates to other services>
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ── Types ─────────────────────────────────────────────────────────────
# All types used by this service's interfaces.
# Organized: IDs first, then data structs, then enums, then events.

# ── Interface ─────────────────────────────────────────────────────────
# The primary interface (or Session interface for session-based services).

interface <ServiceName> {
    # Session-based services start with handshake:
    # handshake @0 (...) -> (...);

    # Methods organized by concern, ordinals assigned sequentially.
}

# ── Events ────────────────────────────────────────────────────────────
# Event types and subscription interface.

# ── Capabilities ──────────────────────────────────────────────────────
# What authority this service requires/grants.
```

### What Goes IN a Schema

| Element | Purpose | Example |
|---------|---------|---------|
| **Interfaces** | Define the contract surface | `interface Process { ... }` |
| **Types** | Define data structures that cross trust boundaries | `struct ProcessInfo { ... }` |
| **Enums** | Define finite sets of states/categories | `enum ProcessState { ... }` |
| **Events** | Define what state changes are observable | `struct ProcessEvent { union { ... } }` |
| **Subscriptions** | Define how consumers observe changes | `interface ProcessSubscription { pull @0 () -> ...; }` |
| **Capabilities** | Define what authority is needed/granted | `enum ProcessCapability { ... }` |
| **Doc comments** | Explain WHY, not WHAT | `# Backend decides scheduling; protocol sees only state.` |

### What Does NOT Go in a Schema

| Element | Why Not | Where It Belongs |
|---------|---------|-----------------|
| **Algorithm hints** | "Use round-robin scheduling" | Inside the kernel |
| **Performance tuning** | "Set thread stack size to 2MB" | Inside the component |
| **Platform assumptions** | "inode", "syslog", "zombie" | Use universal terms |
| **Wire format details** | "Use little-endian encoding" | Inside the transport |
| **Internal state machines** | "Transition from INIT to RUNNING" | Inside the component |
| **Optimization parameters** | "Use 4KB pages" | Inside the kernel |
| **Implementation-specific enums** | `LogOutput { stdout, stderr, journal }` | Use opaque `Text` targets |

### How to Version Interfaces

1. **Ordinal stability:** Once a method is published, its ordinal number is permanent. Never reuse or reorder ordinals.

   **PRE-RELEASE CARVE-OUT (added 2026-10-10).** "Published" means released to someone outside this repository. Nothing external consumes these schemas yet, so no ordinal is yet a promise: until the first external release, ordinals, types and interfaces may be renumbered, reordered and deleted outright, and DELETE is preferred over deprecate-and-keep. The revamp exercised this across the foundation/kernel batch. From first release onward, rules 1–4 bind in full, and breaking a published schema requires a new schema ID.

2. **Additive changes:** New methods, new types, new enum variants, new fields in structs → increment **minor** version.

3. **Breaking changes:** Removing methods, changing signatures, changing field types → increment **major** version (requires new schema ID).

4. **Deprecation:** Mark old methods with a comment `# Deprecated: use newMethod instead. Ordinal preserved for wire compatibility.` Never delete them. (Pre-release: delete — see the carve-out. A deprecated variant that survives this wave becomes the next schema's example.)

5. **Forward compatibility:** Every union type should have a `unknown` or `custom` variant with opaque `Data` payload. This allows backends to extend without breaking consumers.

   Scoped: the terminator binds EVENT and SPECIFICATION unions, where a producer must forward a kind it did not foresee. `T.VoidResult`/`T.BoolResult` (their non-success arm is `T.Error`) and `T.DataHandle` (closed by construction) are exempt.

   ```capnp
   struct CompositorEvent {
       union {
           knownEvent @0 :KnownEvent;
           # ... existing variants ...
           unknown @N :UnknownEvent;  # Always last
       }
   }
   
   struct UnknownEvent {
       typeId  @0 :UInt64;
       payload @1 :Data;
   }
   ```

6. **ABI negotiation:** Use `abi.capnp` to declare which schema versions an implementation supports. Consumers negotiate at startup.

### How to Handle Capability Integration

Every service should accept capabilities as part of its authority model:

```capnp
using import "capability.capnp".Capability;

interface MyRoot {
    # Ungated: discovery is open to everyone.
    discover @0 () -> (descriptor :MyDescriptor);

    # Gated once, at acquisition.
    sensitive @1 (authority :Capability) -> (service :MyService);
}

interface MyService {
    # Holding `service` IS the authority. No per-method token.
    doSensitiveThing @0 (request :SensitiveRequest) -> (result :SensitiveResult);
}
```

**Rules:**
- Authority is the **interface reference**, not a per-method parameter. In Cap'n Proto
  RPC a capability is a reference: holding it conveys authority to call it.
- Privileged services are obtained through an accessor that takes a `Capability`, and
  their methods then take no authority token.
- Ungate discovery: keep "what exists and what can it do" readable without authority,
  so a caller can learn before it can act.
- The capability's `target` field identifies the resource; its `operations` field
  determines what is permitted.
- Attenuation and revocation are `capability.capnp`'s job, not re-specified per service.
- Capability verification is a backend concern; the protocol only specifies the contract.

**Why not a per-method parameter?** It duplicates authority the reference already carries,
leaving two authority paths that must agree forever. `schema/ai.capnp`
implements the reference model (validator rule E3), and it is the precedent that
governs every service method in the protocol.

**The precedent, stated precisely (this paragraph supersedes the older "the per-method
`Capability` pattern survives" reading of this section):** a `Capability` parameter is
legal in exactly two places —

1. on a root accessor that RETURNS a service, where taking the capability is how the
   caller is granted the reference (`AI.models @2 (authority :Capability) ->
   (service :ModelService)`); and
2. inside `capability.capnp` itself, on the five methods that act ON the capability the
   parameter names (`attenuate @2`, `transfer @3`, `revoke @4`, `revokeControlled @8`,
   `evaluateCondition @11`). There the parameter is the object under manipulation, not an
   authority token.

Everywhere else a per-method authority parameter is a second authority path and is a
defect. The revamp deleted all of them: free-text `authority` headers, `requiredCaps :
List(Text)`, role strings, ACLs, per-command capability parameters and permission
enums. `scripts/validate.py` rule E11 enforces the two-Place shape tree-wide.

**Do NOT** define permission strings, boolean flags, or role-based access control in the protocol. The capability system IS the access control mechanism.

### How to Handle Errors

The protocol uses a unified error model defined in `types.capnp`:

```capnp
struct VoidResult {
    union {
        success @0 :Void;
        error @1 :Error;
    }
}

struct Error {
    code @0 :ErrorCode;
    message @1 :Text;       # Human-readable description
    context @2 :Text;       # What was being attempted
    retryable @3 :Bool;     # Whether retry makes sense
}
```

**Rules:**
1. All methods that can fail MUST return a result union containing `Error`.
2. Methods that always succeed return `Void` (not `VoidResult`).
3. Use the most specific `ErrorCode` from the standard set.
4. `message` MUST be human-readable and include enough context for debugging.
5. `context` SHOULD describe what operation was attempted.
6. `retryable` SHOULD be `true` for transient failures (timeout, temporary unavailable).
7. NEVER swallow errors silently. Every error path MUST be explicit.
8. Custom error types are permitted for domain-specific errors, but MUST include a standard `ErrorCode` for routing.

```capnp
# Acceptable custom error:
struct BufferResult {
    union {
        buffer @0 :BufferInformation;
        error  @1 :T.Error;  # Standard error, not custom
    }
}
```

---

## 5. The Swap Test

For each design principle, validate by swapping component implementations. If the protocol still works, the principle holds.

### Principle 1: The Protocol is Implementation-Agnostic

| Swap | Protocol Still Works? | Evidence |
|------|----------------------|----------|
| **Linux kernel → seL4 microkernel** | ✅ Yes *(corrected 2026-10-10)* | `kernel.capnp` defines spawn, signal, memory regions, and seL4 has capabilities natively but exposes the same interface. The earlier claim that `TaskState` (newBorn, ready, running, waiting, stopped, terminated, zombie) "maps to seL4's thread states" was FALSE — seL4 has no zombie state, which is why the schema carried it: the enum was POSIX vocabulary. The canonical `T.ExecutionState` (active/blocked/suspended/terminated) is the set that actually swaps. Memory regions map to seL4's untyped memory. |
| **PipeWire → custom Rust audio server** | ✅ Yes | `audio.capnp` defines devices, streams, volume. A custom server exposes the same concepts. PipeWire's graph model is internal; the protocol sees endpoints and streams. |
| **ext4 → distributed filesystem (Ceph, GlusterFS)** | ✅ Yes | `files.capnp` defines open/read/write/stat. The filesystem type is opaque in `DiskUsage.filesystem`. Inodes are implementation-specific. The protocol sees paths and content. |
| **X11 → Wayland → custom compositor** | ✅ Yes | `compositor.capnp` defines surfaces, commits, input events. The backend's display protocol (X11, Wayland, custom) is internal. The Session interface is the contract. |
| **systemd → runit → s6** | ✅ Yes | `init.capnp` defines service lifecycle (start, stop, restart, state). Whether the init system uses cgroups, process supervision trees, or dependency graphs is internal. The protocol sees service state and lifecycle events. |

### Principle 2: Types Are Opaque Where Appropriate

| Swap | Protocol Still Works? | Evidence |
|------|----------------------|----------|
| **ProcessId as UInt64 on Linux → seL4 TCB IDs** | ✅ Yes | Both map to UInt64. The protocol doesn't care whether it's a PID or a thread control block. |
| **FileHandle as opaque UInt64 on ext4 → capability-based handle on seL4** | ✅ Yes | The handle is opaque. The backend decides what it represents. Consumers only pass it back. |
| **Capability.id as opaque Data on local system → distributed token** | ✅ Yes | A local system might use a pointer. A distributed system might use a JWT. Both are opaque `Data`. The protocol doesn't inspect them. |
| **AudioDevice.id as UInt64 on PipeWire → UUID on custom server** | ✅ Yes | Both map to an opaque identifier. The protocol doesn't care about the format. |

### Principle 3: No Implementation-Specific Types

| Swap | Protocol Still Works? | Evidence |
|------|----------------------|----------|
| **FilePermissions as POSIX mode bits → capability-based access** | ✅ If fixed | Current POSIX-specific `owner/group/other` model breaks capability systems. **Fix required:** Replace with opaque permissions or universal permission enum. |
| **ProcessState with "zombie" → seL4 with no zombie state** | ✅ If fixed | seL4 doesn't have zombies. **Fix required:** Rename to universal states. |
| **LogOutput with "journal" → custom logging backend** | ✅ If fixed | A custom backend doesn't use journald. **Fix required:** Replace with opaque output target. |

### Principle 4: Contracts Are Complete (No Gaps)

| Scenario | Protocol Coverage? | Gap? |
|----------|-------------------|------|
| App needs to resolve a hostname | ❌ No DNS service | **Gap.** Add DNS resolution contract. |
| App needs to open a TCP connection | ❌ No socket API | **Gap.** Add connection contract. |
| App needs to query device topology | ✅ `device.capnp` | No gap. |
| App needs to manage capabilities | ✅ `capability.capnp` | No gap. |
| App needs to discover hardware | ✅ `hal.capnp`, `device.capnp` | No gap. |
| Service needs to declare resource limits | ❌ No quota contract | **Gap.** Add resource limits contract. |

### Principle 5: Events Are Forward-Compatible

| Scenario | Protocol Handles It? | Evidence |
|----------|---------------------|----------|
| Backend adds a new event type unknown to consumer | ✅ Yes | Every event union has `unknown @N :UnknownEvent` with `typeId` and opaque `Data`. Consumer skips unknown events. |
| Backend adds a new field to a struct | ✅ Yes | Cap'n Proto handles unknown fields gracefully. Old consumers ignore new fields. |
| Backend removes a field from a struct | ⚠️ Risky | Cap'n Proto preserves old fields but semantics may break. **Rule:** Never remove fields. Deprecate with comments. |
| Two backends implement different subsets of an interface | ✅ Yes | ABI negotiation via `abi.capnp` declares which methods are supported. |

---

## 6. Appendix: Schema-by-Schema Verdicts

### Schemas That Are Exemplary (Follow All Principles)

| Schema | Why |
|--------|-----|
| `capability.capnp` | Opaque id, textual targets, backend-agnostic operations. Perfect. |
| `boot.capnp` | *(Amended 2026-10-10)* The pre-revamp body was the tree's largest collection of frozen technology — 24 hardware enums, ACPI/SMBIOS/DMI/UART structs, an `hhdmOffset` and a raw handler table. It has been rewritten to a trivial loader contract: one well-known pointer, a declarative manifest, open tokens. Exemplary again, and this time it is true. |
| `kernel.capnp` | *(Amended 2026-10-10)* The body contradicted its own header: scheduler introspection, CLONE_* fork flags, live kernel swapping, six unreachable interfaces. All deleted. The header's claim now matches the file. |
| `init.capnp` | Observable lifecycle, no dependency resolution algorithm specified. |
| `tunnel.capnp` | Universal channel, transport-agnostic. |
| `manifest.capnp` | Self-description, timeless. |
| `abi.capnp` | Versioning and compatibility negotiation. *(Amended 2026-10-10)* The registry/endorsement apparatus and the duplicate `BootCapability` enum are deleted; the negotiation core remains and was always the model. |
| `hal.capnp` | Describes affordances, not implementations. *(Amended 2026-10-10)* The page-table/x86-port-I/O block, the POSIX fd, the duplicate primitives and the three IRQ paths are gone. |
| `device.capnp` | Backend-decided device tree. |
| `database.capnp` | Clean key-value contract, no storage engine assumptions. |
| `logging.capnp` | *(Amended 2026-10-10)* The canonical log contract. The 2026-07-01 release-blocker (`LogFormat`, `LogOutput`, structured `LogSource`) is executed; the observability-platform layer is deleted. |

### Schemas That Need Fixes

| Schema | Issue | Priority |
|--------|-------|----------|
| `logging.capnp` | Over-specifies format and output targets | 🔴 High — **DONE 2026-10-10:** `LogFormat`/`LogOutput` deleted, `LogSource` opaque. |
| `files.capnp` | POSIX-specific permissions and metadata | 🔴 High — **DONE 2026-10-10:** `FilePermissions` removed; `inode`/`device` removed. |
| `textinput.capnp` | Duplicates `ime.capnp` | 🔴 High — **DONE 2026-10-10:** file deleted, absorbed into `ime.capnp`. |
| `filesystem.capnp` | Duplicates `files.capnp` | 🔴 High — **DONE 2026-10-10:** file deleted, merged into `files.capnp`. |
| `surface.capnp` | Duplicates compositor surface management | 🔴 High — **DONE 2026-10-10:** file deleted, merged into `compositor.capnp`. |
| `process.capnp` | POSIX-specific process states | 🟡 Medium — **DONE 2026-10-10** (see `T.ExecutionState`). |
| `session.capnp` | Unix-specific UserInfo | 🟢 Low — **DONE 2026-10-10:** `T.UserId`, no `shell` field. |
| `windowmanager.capnp` | Window.pid uses UInt32 | 🟡 Medium — **DONE 2026-10-10:** `T.ProcessId`. |

### Schemas That Are Acceptable (No Changes Needed)

| Schema | Notes |
|--------|-------|
| `audio.capnp` | Clean contract. Device ID should be UInt64 but Text is acceptable. |
| `compositor.capnp` | Excellent Session design. Old Compositor interface is deprecated but preserved. |
| `buffer.capnp` | Good Session design. Old Buffer interface deprecated. |
| `windowmanager.capnp` | Good Session design. Old WindowManager deprecated. |
| `ime.capnp` | Good Session design. Replaces textinput.capnp. |
| `shell.capnp` | Good Session design. Should delegate to canonical services for notifications/clipboard/settings. |
| `network.capnp` | Clean contract. Missing socket API is a gap. |
| `display.capnp` | Clean contract. |
| `input.capnp` | Clean contract. |
| `power.capnp` | Clean contract. |
| `auth.capnp` | Clean contract. |
| `notification.capnp` | Clean contract. Canonical notification service. |
| `clipboard.capnp` | Clean contract. Canonical clipboard service. |
| `settings.capnp` | Clean contract. Canonical settings service. |
| `secret.capnp` | Clean contract. |
| `time.capnp` | Clean contract. |
| `speech.capnp` | Clean contract. |
| `web.capnp` | Clean contract. Missing DNS resolution is a gap. |
| `app.capnp` | Clean contract. |
| `system.capnp` | *(Amended 2026-10-10)* Clean contract. The "capabilities bitmap is extensible" claim was wrong: it was 47 fixed booleans naming today's schema catalog, already missing `ai`, `tunnel` and `sandbox`. It is now an open token set. |
| `manifest.capnp` | Clean contract. |
| `abi.capnp` | Clean contract. |
| `tunnel.capnp` | Clean contract. |
| `hal.capnp` | Clean contract. |
| `device.capnp` | Clean contract. |

---

## Summary of Actionable Items

### Immediate (Block v1.0 Release)

1. **Deprecate `textinput.capnp`** — consolidate into `ime.capnp`. **DONE 2026-10-10** (deleted).
2. **Deprecate `filesystem.capnp`** — merge mount/unmount into `files.capnp`. **DONE 2026-10-10** (deleted).
3. **Deprecate `surface.capnp`** — merge into compositor Session. **DONE 2026-10-10** (deleted).
4. **Fix `logging.capnp`** — remove `LogFormat` and `LogOutput` enums, make `LogSource` opaque. **DONE 2026-10-10.**
5. **Fix `files.capnp` `FilePermissions`** — replace POSIX model with universal permissions. **DONE 2026-10-10**.
6. **Fix `process.capnp` `ProcessState`** — rename to universal states. **DONE 2026-10-10.**

### Short-term (Before v1.1)

7. **Add DNS resolution service** — `dns.capnp`.
8. **Add socket/connection API** — `connection.capnp` or extend `network.capnp`.
9. **Add resource quota service** — `quota.capnp`.
10. **Standardize subscription pattern** — choose pull-based or stream-based, apply consistently.
11. **Fix `FileHandle`** — remove path/mode, keep opaque handle.
12. **Fix `TunnelHandle`** — remove subject, keep opaque id.

### Long-term (v2.0+)

13. **Add process group/session management.**
14. **Add audit logging service.**
15. **Unify Session handshake pattern** — consider a universal `ServiceSession` base.
16. **Review all `UInt32` IDs** — ensure they are `UInt64` for forward compatibility.

---

*This document is the canonical reference for smart-protocol schema design. All schema reviews, new proposals, and audit findings should be evaluated against these principles.*

Next in the chain: `docs/TIMELESSNESS.md` (timelessness rationale), then `docs/MANIFESTO.md` (the thesis). See also `README.md`.

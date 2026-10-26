# Smart Protocol — design principles

> Version 2.0 · Established 2026-07-01 · Rewritten 2026-10-23
> Status: governing document. It decides what a schema may contain, how it may
> evolve, and how a reviewer judges a change.

A contract outlives the products built on it by design, so its design rules have
to be stricter than a product's. This document is those rules. It is organised
around the two tests that decide every line of schema, the anti-patterns those
tests exist to catch, the template a schema follows, and the machine that checks
what a reviewer cannot.

---

## Table of contents

1. [The Agnostic / Timeless Test](#1-the-agnostic--timeless-test)
2. [The Opacity Principle](#2-the-opacity-principle)
3. [The anti-pattern catalogue](#3-the-anti-pattern-catalogue)
4. [The schema template](#4-the-schema-template)
5. [The Swap Test](#5-the-swap-test)
6. [How a change is judged](#6-how-a-change-is-judged)

---

## 1. The Agnostic / Timeless Test

Every proposed addition must answer one question before it is argued on merit:

> **Is this an EXTERNAL contract — what two components exchange in order to
> interoperate — or an INTERNAL implementation — how a component works?**

External goes in the protocol. Internal stays inside the component.

### Decision procedure

```
Does it describe HOW a component implements its behaviour?
        │
        ├── yes ──▶  KEEP OUT. It is the component's business.
        │
        └── no ──▶  Does it describe WHAT two components exchange to interop?
                        │
                        ├── yes ──▶  KEEP IN. It is a contract.
                        │
                        └── no ──▶  Re-evaluate with the Swap Test (§5).
                                    If you cannot name the two parties and
                                    what each must do with it, it is not a
                                    contract yet.
```

### Clear examples

| Proposal | Verdict | Why |
|---|---|---|
| "Resolve this hostname and return the result or a typed error" | Contract | It names an exchange, not a resolver library |
| "Use systemd-resolved and its D-Bus interface" | Implementation | It names a specific process and its internal protocol |
| "Declare that this service receives 512 MB" | Contract | The grant crosses a boundary |
| "Create a cgroup with `memory.max=512M`" | Implementation | Linux's mechanism, not the contract's meaning |
| "Send these audio frames to this device" | Contract | Two parties, an observable exchange |
| "Open a PulseAudio stream with this sample spec" | Implementation | A specific server's API |
| "Allocate GPU memory of this size and return a handle" | Contract | Affordance, not mechanism |
| "Call `DRM_IOCTL_GEM_CREATE`" | Implementation | A kernel driver's ioctl number |

### Edge cases

**"But the contract has to say *something* about it."** Then say the smallest
thing that both parties must agree on, and stop. "This operation may take an
unbounded time and can be cancelled" is a contract. "Cancel within 100 ms" is a
performance target for one backend.

**"But every implementation will need this."** Then every implementation is
doing something the contract has not expressed yet — but check first whether the
need is for agreement or for convenience. Convenience fields accumulate in
schemas and never leave.

**"But without it, the consumer cannot optimise."** Optimisation is the
backend's business. If a consumer must adapt to a provider's internals to be
fast, the boundary is in the wrong place.

**"It is only a hint."** Hints are still fields, fields are still ordinals, and
ordinals are permanent. A hint that everyone ignores is dead weight; a hint that
one backend honours is implementation leakage with a schema ID.

### The five litmus questions

Answer all five in the pull request:

1. Can two completely different implementations satisfy this?
2. Does a consumer need this in order to interoperate with a provider?
3. Does this data cross a trust boundary?
4. Will this still make sense on different hardware in ten years?
5. If the implementation is swapped, does the contract still hold?

Any "no" means the proposal belongs inside a component.

### Timelessness, the second axis

The Agnostic Test asks *where* something belongs. Timelessness asks *how it
should be expressed* once it does belong. The rule is negative:

> You cannot enumerate the future. You can forbid what may never appear.

Concretely, in this tree:

- no vendor, platform or POSIX noun in a required position (E9);
- no enum in `ai.capnp`, and no enum whose `@0` is a paradigm value (E1, E8);
- technology-specific values as open tokens, never as closed lists;
- every union extensible (E6);
- bulk through `T.DataHandle` (E2, E10).

The full argument, including worked examples from the revamp, is in
[`docs/TIMELESSNESS.md`](docs/TIMELESSNESS.md).

---

## 2. The Opacity Principle

> Push every type as far toward opaque as the contract can afford.

```
OPAQUE ─────────────────────────────────────────────▶ STRUCTURED
UInt64    Data      Text       Enum      Struct with    Struct with
 (id)     (bytes)   (string)  (closed)   fixed fields   variable fields
   │        │          │          │            │              │
ProcessId  CapId    DeviceName  ErrorCode   Rect, Vec2    StringMap
BufferId   proof    LayoutId    Severity    BatteryState  metadata
WindowId            Tag                      AudioFormat
```

### The rule

Make a type structured **only when a consumer must read or write specific
fields in order to interoperate.** Otherwise use an opaque value — an integer
identity, a byte string, or text — and let the backend decide what it means.

Every field you structure is a promise about how a component works. Every such
promise is implementation leaking into a contract that must outlive it.

### Decision procedure

```
Must the peer understand the internal layout to interoperate?
        │
        ├── no ──▶  OPAQUE.
        │            Is it an identity?        → a typed id wrapper
        │            Is it bytes of unknown shape? → Data / T.DataHandle
        │            Is it a name or a token?  → Text
        │
        └── yes ─▶  STRUCTURED, and no further than necessary.
                     Is the value set closed by mathematics or protocol? → enum
                     Otherwise                                            → open token
```

### What opacity buys

| Opaque type | What the backend may change without a schema edit |
|---|---|
| `T.ProcessId`, `T.BufferId`, `T.KeyId`, `T.ServiceId` | Width, allocation strategy, backing store |
| `T.DataHandle` | Whether a payload is inline or a shared buffer |
| `T.Capability.id` | The entire capability representation |
| `T.StringMap` values | Anything named but not yet enumerated |
| `T.MimeType` | Every format that exists or will exist |

### Where the tree applies it

- **Identifiers** are wrapper structs, never bare integers in a public
  signature, so no consumer can do arithmetic on a process id.
- **Handles** are opaque. Nothing in the protocol parses a `BufferId`, and DMA
  tokens in `buffer.capnp` are opaque bytes rather than per-process numbers.
- **Payloads** are `T.DataHandle`. 421 positions in the tree use it.
- **Vocabularies** are tokens. `ServiceDescriptor.category`, a transport, a
  device format, a media type and a model's architecture are all open strings
  with published conformance spellings, so a 2046 value is spellable today.
- **Lifecycle** is one vocabulary, `T.ExecutionState` — including the states a
  POSIX system would describe in its own words.

### The failure mode opacity prevents

A structured field is a public commitment to a private detail. Once published,
the detail cannot change: not the width, not the encoding, not the semantics.
An opaque handle can be re-implemented entirely — a different allocator, a
different backing store, a different machine — and the wire does not move.

---

## 3. The anti-pattern catalogue

These are the shapes that have actually appeared in this tree, been caught, and
been deleted. They are listed because a rule is easier to apply when you can
recognise its violation.

### A. The parallel authority model

**Symptom.** A role string, an ACL, a permission enum, a per-method capability
token, a free-text `authority` field, a capability id accepted as a parameter.

**Why it fails.** Authority is already carried by the capability reference.
A parallel model must agree with it forever, and the parallel model keyed by
text can never be revoked. Two permission paths are worse than one, even when
they agree today.

**Fixed by.** Ungated discovery plus one gated accessor that returns a service.
Delegation only through `capability.capnp`.

**Seen in.** Clipboard, app layer, secret store, sandbox administration (still
open — see `docs/VERIFICATION.md` E11).

### B. The technology museum

**Symptom.** Named storage buses, firmware tables, wire transports, codecs,
compression formats, model architectures, vendors, kernels, display servers.

**Why it fails.** Each name is a permanent commitment to a technology that may
not exist in twenty years. The enum that froze 27 compression codecs is the
canonical example.

**Fixed by.** An open token, plus published conformance constants for today's
spellings, plus the tolerance rule (unknown values are ignored, never rejected).

### C. Bulk in the message

**Symptom.** `List(Float32)`, `List(UInt8)`, inline `Data` in a payload position.

**Why it fails.** Cap'n Proto's zero-copy guarantee applies to the serialised
message. A list in a field is copied into the message, which is a cost the
contract has no right to impose and an assumption that the payload is small.

**Fixed by.** `T.DataHandle` — inline `Data` for small payloads, a `BufferId`
reference for large ones.

### D. The duplicate home

**Symptom.** The same type name declared in two schemas; the same concept
described by two interfaces.

**Why it fails.** Two homes drift. The tree had 36 such duplicates before the
revamp collapsed them.

**Fixed by.** One canonical home, the other side imports. Where the two shapes
are materially different, both names are disambiguated — never kept as twins.

### E. The frozen default

**Symptom.** An enum whose `@0` is a paradigm value (`trace`, `always`, `srgb`,
`usd`, `terminate`).

**Why it fails.** An unset field silently asserts that value. "Unset" must be
sayable.

**Fixed by.** A neutral sentinel at `@0` (`unknown`, `none`, `unspecified`), or
deletion of the enum in favour of an open token.

### F. The unreachable interface

**Symptom.** An interface no method returns or accepts.

**Why it fails.** Nothing can call it, so it is not a contract — it is a
description of an implementation's internal structure that has been promoted
into the protocol.

**Fixed by.** Delete it, or make it reachable through an accessor.

### G. The silent failure

**Symptom.** A method that can fail returns an empty struct, a zero, or a
plausible default.

**Why it fails.** The consumer cannot distinguish "none" from "failed", which
makes every downstream decision unsound.

**Fixed by.** A result union carrying `T.Error`. Unsupported operations return
`Unavailable` with a reason, never a fabricated value.

### H. The raw handler table

**Symptom.** Services writing function pointers into slots by index; raw
subscription ids; offsets into a live stream.

**Why it fails.** It bakes a specific dispatch mechanism and a specific
lifetime model into the contract.

**Fixed by.** Channels and `ServiceEndpoint` for dispatch; a subscription
reference with a bounded `pull` for streaming.

---

## 4. The schema template

### 4.1 Structure

Every `.capnp` file in `schema/` follows this shape. The order matters: a reader
should be able to decide whether to keep reading from the first thirty lines.

```capnp
@0x<unique_schema_id>;

# ═══════════════════════════════════════════════════════════════════════
# <Domain> — <what boundary this file defines>
#
# THE CONTRACT
#   What two components exchange here, and why the boundary is where it is.
#
# DELIBERATELY OPAQUE
#   What the backend decides and the protocol never inspects.
#
# DELETED / NOT HERE
#   What this file used to contain, why it was removed, and what replaced it.
#
# AUTHORITY
#   Where the one gate at acquisition is, and what sits behind it.
#
# TIMELESSNESS
#   Which values are open tokens, which are enums, and why each enum is closed.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ── Identity ──────────────────────────────────────────────────────────
# Typed opaque ids first.

# ── Value types ───────────────────────────────────────────────────────
# Fixed-shape descriptors: geometry, status, capability description.

# ── Events ────────────────────────────────────────────────────────────
# Event unions, each terminating in `unknown @N :T.UnknownEvent`.

# ── Interfaces ────────────────────────────────────────────────────────
# The ungated discovery surface, then the gated accessor(s), then the
# services they return, then subscriptions.

# ── Subscriptions ─────────────────────────────────────────────────────
# bounded pull + cancel.
```

### 4.2 What belongs in a schema

| Element | Purpose |
|---|---|
| Interfaces | The contract surface |
| Value types | Data both sides must read field by field |
| Events | Observable state changes, each extensible |
| Subscriptions | Bounded observation (`pull`, `cancel`) |
| Capability references | Authority, gated once at acquisition |
| Doc comments | The argument: why this boundary, what is opaque, what was deleted |

### 4.3 What does not belong

| Element | Where it belongs instead |
|---|---|
| Algorithm hints ("round-robin", "LRU") | Inside the component |
| Performance targets ("2 MB stack", "within 100 ms") | Inside the component's documentation |
| Platform assumptions (`inode`, `syslog`, `zombie`, `cgroup`) | Universal terms, or nowhere |
| Wire-format details (endianness, framing) | The transport |
| Internal state machines | The component |
| Vendor, product, format or architecture names in required positions | Open tokens |
| Permission strings, roles, ACLs, per-method tokens | `capability.capnp` |
| Resource-tuning parameters (page size, ring depth) | The backend |

### 4.4 Evolution rules

1. **Ordinal stability.** Once published, a method's ordinal is permanent. New
   capabilities take fresh ordinals and never displace old ones.
2. **Additive by default.** New methods, types and fields are minor changes.
3. **Breaking means a new ID.** Removing a method, changing a signature or
   changing a field type is a new schema ID. A retired ID is never reused —
   `ai.capnp` carries `@0xa1b2c3d4e5f60109` precisely because the retired
   `...0061` was never implemented and must not be inherited by a wrong draft.
4. **Deprecation.** Post-release, mark with a comment and preserve the ordinal.
   Pre-release, delete.
5. **Forward compatibility.** Every event and specification union terminates in
   an `unknown` arm carrying `T.UnknownEvent { typeId, payload }`. `T.VoidResult`
   and `T.BoolResult` are exempt: their non-success arm is `T.Error`, which is
   itself the extension point.
6. **ABI negotiation.** `abi.capnp` lets two parties declare what they speak and
   agree on the intersection before either commits to a call.

**The pre-release carve-out.** "Published" means released to someone outside
this repository. Nothing external consumes these schemas yet, so until the first
external release ordinals, types and interfaces may be renumbered, reordered and
deleted outright — and **deletion is preferred to deprecation**. From first
release, rules 1–4 bind in full. The carve-out is stated rather than assumed,
and it expires at a stated event rather than a stated date.

### 4.5 Capability integration

The shape is identical in every schema, and it is the precedent that governs
every service method in the protocol:

```capnp
using import "capability.capnp".Capability;

interface MyRoot {
    # Ungated: discovery must never deadlock on authority.
    discover @0 () -> (descriptor :MyDescriptor);

    # Gated once, at acquisition.
    sensitive @1 (authority :Capability) -> (service :MyService);
}

interface MyService {
    # Holding `service` IS the authority. No per-method token.
    read  @0 (id :MyId) -> (data :T.DataHandle);
    write @1 (id :MyId, data :T.DataHandle) -> T.VoidResult;
}
```

**A `Capability` parameter is legal in exactly two places:**

1. on a root accessor that **returns a service** — taking the capability is how
   the caller is granted the reference; and
2. inside `capability.capnp`, on the methods that act **on** the capability the
   parameter names (`attenuate @2`, `transfer @3`, `revoke @4`,
   `revokeControlled @8`, `evaluateCondition @11`).

Everywhere else it is a second authority path and a defect. E3 and E11 enforce
this.

Authority rules:

- **Ungate discovery.** A caller must be able to learn what exists before it can
  act; discovery that deadlocks on a capability never runs.
- **Gate once.** The accessor takes the capability; nothing behind it does.
- **Put the algebra in one place.** Attenuation, transfer, revocation and
  evaluation live in `capability.capnp` and nowhere else.
- **Verification is the backend's job.** The protocol specifies what a
  capability *is*, not how a backend checks it.

35 accessors in the tree have this shape.

### 4.6 The error model

```capnp
struct VoidResult {
    union {
        success @0 :Void;
        error   @1 :T.Error;
    }
}

struct Error {
    code      @0 :ErrorCode;
    message   @1 :Text;       # human-readable, enough for debugging
    context   @2 :Text;       # what was being attempted
    retryable @3 :Bool;       # whether retrying can plausibly succeed
    metadata  @4 :StringMap;  # structured detail, open vocabulary
}
```

Rules:

1. Anything that can fail returns a union carrying `T.Error`.
2. A method that cannot fail returns `T.VoidResult` or plain `Void` — be
   consistent within an interface.
3. Use the most specific `ErrorCode`.
4. `message` is for humans and must include enough context to debug.
5. `retryable` is true only for transient failures.
6. Never swallow an error. Every failure path is explicit.
7. Domain-specific detail goes in `metadata`, not in a new error type per
   domain.

The honesty rule extends the model: an operation that is not implemented returns
`Unavailable` with a reason. A fabricated success is the one unforgivable defect.

---

## 5. The Swap Test

> Replace the implementation of a component. If the contract still holds, the
> principle held. If a swap breaks the contract, the contract leaked
> implementation, and the leak is a bug.

### Five applications

1. **Kernel-agnostic.** Linux → seL4 → a purpose-built microkernel. The protocol
   still defines spawn, memory regions, waitables and service resolution.
2. **Type opacity.** A `ProcessId` that is a 32-bit index in one kernel and an
   opaque 128-bit token in another. The wire does not change.
3. **No implementation-specific types.** The protocol never declares a type that
   belongs to one backend (`LogOutput { stdout, stderr, journal }` is the classic
   mistake).
4. **Completeness.** A contract with a gap forces the consumer to reach past it
   into implementation. Gaps are bugs even when nothing is wrong yet.
5. **Forward compatibility.** A consumer written today must survive an event,
   token or capability invented later.

### The historical evidence

| Swap | Result |
|---|---|
| Linux kernel → seL4 / a Rust microkernel | Contract holds: `kernel.capnp` defines the boundary, not the scheduler |
| PipeWire → a custom audio server | Contract holds: `audio.capnp` defines devices, streams, focus |
| ext4 → a distributed filesystem | Contract holds: `files.capnp` defines open/read/write/stat semantics |
| X11 → Wayland → a future compositor | Contract holds: `compositor.capnp` defines commit, fences and damage |
| systemd → runit → s6 | Contract holds: `init.capnp` defines lifecycle, not dependency algebra |
| a 2026 bootloader → a 2046 one | Contract holds: 24 bytes and a declarative manifest |

### Running the test on your own work

The test is not rhetorical. Delete your implementation, write another, and point
the same consumer at it. If the consumer needs a change, you either leaked
implementation into it or found a genuine gap in the schema. Both are worth
knowing, and only one of them is your bug.

---

## 6. How a change is judged

### The gate

Every rule in this document that can be checked mechanically is checked by
`scripts/validate.py`, which parses the schemas with a real parser — comments
stripped first, so a phrase in prose is not evidence.

| Rule | Enforces |
|---|---|
| E1 | `ai.capnp` declares zero enums |
| E2 | `ai.capnp` has no bulk lists — payload is `T.DataHandle` |
| E3 | `Capability` appears only on `AI` accessors |
| E4 | Every interface is reachable |
| E5 | Every stream's `pull` returns a structural terminator |
| E6 | Every union has an `unknown`/`custom` arm |
| E7 | Every struct has an open extension point (value structs exempt) |
| E8 | Every enum's `@0` is a neutral sentinel |
| E9 | No platform, vendor or POSIX noun in a required position |
| E10 | No bulk payload outside `T.DataHandle` |
| E11 | Authority is the reference — no per-method token, no authority-as-string |
| E12 | One canonical home per type name |
| E13 | Interface method ordinals sequential and declared in order |
| E14 | Every interface reachable; no declared type unreferenced |
| E15 | Agent tool authority is per-tool, explicit and deny-by-default; descriptors do not export authority snapshots |

`docs/VERIFICATION.md` states the current result of each rule, the severity
model, and every residual finding by name.

### Scoping decisions that are doctrine, not oversight

- **E5** — subscriptions are terminated by `cancel`; a terminator *field* would
  contradict the subscription convention.
- **E6** — `T.VoidResult` and `T.BoolResult` are exempt because `T.Error` is
  their extension point. `T.DataHandle` is closed by construction.
- **E7** — value structs (`Rect`, `Vec2`, `T.Timestamp`, `AckHandle`) are
  complete by construction; forcing an extension point onto them would bloat
  every message for no gain.
- **E14** — an interface accepted as a *parameter* counts as reachable, because
  a registered callback is supplied by the caller and invoked by the peer.
- **E15** — agents receive only the explicitly supplied per-tool executor
  references, never a global registry that accepts an arbitrary tool ID at
  invocation time. An empty allowlist means no tools. A descriptive agent record
  is not an authority registry; capability state remains owned by the capability
  service. The validator checks this schema shape, while implementations must
  still prove matching bindings, fail-closed behavior and revocation enforcement.
- **E12** — satisfied by elimination, not exemption. There is no sanctioned
  duplicates list.

### The review order

1. Does the gate pass?
2. Does the header argue for the change, or merely describe it?
3. Is anything named that will not exist in ten years?
4. Is there a second home, a second authority path, or a second way to carry the
   same data?
5. Does an existing interface already answer this? Most proposals are answered
   already.
6. If this were deleted tomorrow, would anyone notice? If not, delete it now —
   that is what the pre-release carve-out is for.

### What review cannot do, and what the gate must

A reviewer's memory is not a measurement. The gate exists so that the mechanical
promises — ordinals, one home per type, no frozen default, no second permission
grammar, no bulk in a message — are checked on every change by a machine that
does not get tired.

What the gate cannot check is judgement: whether a boundary is in the right
place, whether a type should be opaque, whether an interface earns its
existence. Those remain review questions, and they are the reason this document
exists.

---

## Appendix — the reading order

| To see | Read |
|---|---|
| The doctrine implemented | `schema/ai.capnp` — zero enums, one `Artifact`, ungated discovery, gated acquisition |
| Authority end to end | `schema/capability.capnp` |
| The smallest handoff | `schema/boot.capnp` |
| The boundary that swaps | `schema/kernel.capnp` — 248 lines, and what is not in them |
| Opacity applied | `schema/types.capnp` |
| The session pattern, once | `schema/session.capnp` and `compositor.capnp`'s `SessionRequest` |
| The whole tree | [`docs/SCHEMAS.md`](docs/SCHEMAS.md) |
| The argument | [`docs/VISION.md`](docs/VISION.md), [`docs/MANIFESTO.md`](docs/MANIFESTO.md) |
| The constraints | [`docs/TIMELESSNESS.md`](docs/TIMELESSNESS.md) |
| The evidence | [`docs/VERIFICATION.md`](docs/VERIFICATION.md), `audit-revamp/` |

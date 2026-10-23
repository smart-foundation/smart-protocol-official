# Glossary

The vocabulary of this repository, defined once so it can be used precisely
everywhere. Where a term is also a general computing term, the definition here
is the one this contract means.

---

## The core distinction

**Contract** — what two components exchange in order to interoperate. Lives in
`schema/`. Does not care how either side is built.

**Implementation (backend)** — a program that satisfies one or more interfaces
from the contract. Lives outside this repository. Disposable by design.

**Reference implementation** — the Naledzi microkernel, which boots and speaks
this contract. It is a consumer and a source: its live contracts were imported
into the canonical schemas, and it is not privileged by them.

---

## Types and data

**Schema** — one `.capnp` file in `schema/`. 89 exist. Each opens with an
argument for its own existence: the boundary it defines, what is opaque, what
was deleted and why.

**Schema ID** — the `@0x…` identifier at the top of a file. Immutable. A
breaking change means a new ID; a retired ID is never reused.

**Ordinal** — the `@N` number on a field, method or enum value. In Cap'n Proto
it is the wire position. Once published, it is permanent.

**Interface** — a Cap'n Proto `interface`: a set of methods addressed by a
capability. In this contract, an interface *is* a capability.

**Struct** — a value with named fields. Two kinds matter:
- **Data struct** — describes something a peer must read; gets an open
  extension point (`metadata :T.StringMap`).
- **Value struct** — complete by construction (`Rect`, `Vec2`, `T.Timestamp`);
  exempt from that requirement (E7 scoping).

**Union** — a tagged value with exactly one active arm. Every event and
specification union terminates in an `unknown` arm.

**Unknown arm** — the final arm of a union, typed `T.UnknownEvent { typeId,
payload }`, which lets a producer forward a kind the contract never foresaw.

**Open token** — a `Text` value whose meaningful spellings are published as
conformance constants but whose set is not closed. A value nobody recognises is
ignored, never rejected.

**Conformance constant** — a published spelling of an open token (`"text/plain"`,
`"aes-256-gcm"`), so producers agree today without freezing the vocabulary
forever.

**Opaque** — deliberately not parsed by the protocol. `ProcessId`, `BufferId`,
`Capability.id`, `DeviceAddress` and DMA tokens are opaque.

---

## Data movement

**`T.DataHandle`** — the only way to carry bulk. A union: inline `Data` for small
payloads, a `T.BufferId` reference for large ones.

**`T.BufferId`** — an opaque reference to a shared-memory buffer
(`buffer.capnp`). Never a pointer, never an offset, never inspected.

**Zero-copy** — the property that a payload crossing a boundary is not copied
into the message. Only `T.DataHandle` preserves it; a `List` or inline `Data` is
always copied.

---

## Authority

**Capability** — a reference that conveys the authority to call what it
references. Holding it *is* permission; there is no separate token.

**Gated** — reached through an accessor that takes a `Capability` and returns a
service. 35 accessors in the tree have this shape.

**Ungated** — callable without acquiring authority. Discovery, handshakes and
descriptors are ungated so that a caller can learn before it acts.

**Accessor** — a method on a root interface that takes a `Capability` and
returns a service capability. The one legal place for a `Capability` parameter
outside `capability.capnp`.

**Attenuation** — weakening a capability (fewer operations, tighter constraints)
and handing the narrower reference on.

**Delegation** — attenuation plus transfer. Lives in `capability.capnp` and
nowhere else.

**Delegation chain** — the recorded parentage of derivative capabilities, so
revoking a root revokes its derivatives (`revokeControlled`).

**Second authority grammar** — any parallel permission model: role strings,
ACLs, per-method tokens, permission enums, free-text authority fields. A defect
(E11).

---

## System structure

**Handoff** — the bootloader-to-kernel transfer: a 24-byte `HandoffPointer` at a
well-known address resolving to a `BootManifest`. The bootloader's entire job.

**Boot manifest** — the declarative description a bootloader hands over: memory
regions, images, kernel menu, channels, arguments, optional framebuffer.

**Handle 1** — `KernelService` at capability handle 1. The only hardcoded
capability in the system; the kernel places it before entering userspace.

**Kernel boundary** — the 248 lines of `kernel.capnp`: what a kernel must offer,
and nothing about how.

**Init** — the userspace process that reads service manifests and starts the
service plane in dependency order (`init.capnp`).

**Service plane** — the running set of services, discoverable through
`discovery.capnp`.

**Service descriptor** — a service's self-description: id, name, open category
token, version, state, endpoints, metadata, required capabilities.

**Endpoint** — a transport token plus an address in that transport's own
vocabulary. The contract does not name transports.

**Session** — a long-lived interactive capability acquired through a `handshake`
taking `compositor.SessionRequest`. Used by the user session and by the five
service sessions (compositor, shell, window manager, IME, screenlock).

---

## Streaming

**Subscription** — a capability with `pull(maxEvents)` and `cancel()`. No raw
ids, no offsets into a live stream.

**Bounded pull** — the consumer sets the pace; the producer cannot outrun it.

**Terminator** — the structural end of a stream. Subscriptions are terminated by
`cancel`; result unions by their error arm.

---

## Design and governance

**Agnostic Test** — is this an external contract or an internal implementation?
External belongs here; internal belongs inside the component.

**Opacity Principle** — push types as far toward opaque as the contract can
afford. Structure a type only when a peer must read or write specific fields.

**Swap Test** — replace an implementation. If the contract breaks, the contract
leaked implementation and the leak is a bug.

**Pre-release carve-out** — until the first external release, ordinals and types
may be renumbered and deleted, and deletion is preferred to deprecation. From
first release, ordinal permanence binds in full.

**Gate** — `scripts/validate.py`, rules E1–E14, run on every change. Exit 0 or
the change does not land.

**Residual** — a finding reported by the gate under a rule that is measured but
not yet gating. Every residual is published in `VERIFICATION.md`; an unlisted
residual is a lie with a schema ID.

**ERROR / REPORT** — the gate's two severities. ERROR fails the build; REPORT
counts and publishes.

**Frozen default** — an enum whose `@0` is a paradigm value rather than a neutral
sentinel, so an unset field silently asserts a paradigm (E8).

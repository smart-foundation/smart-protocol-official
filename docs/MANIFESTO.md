# The Smart Protocol manifesto

> The protocol is the only thing that must never change. Everything else is replaceable.

---

## I. The wager

Computing has spent fifty years confusing its products with its progress.

The products are what we remember — the machines, the applications, the companies, the interfaces we learned. But every one of them was built inside a structure that was already there, and the structure is what made the era possible. The web was not a browser. The internet was not a network operating system. Relational data was not a database vendor. Each of those was a contract, and each contract outlived every product that fought over it.

This is not a law of nature. It is an outcome of incentives. A product is optimised for its owner; a contract is optimised for the next person who wants to participate. Given enough time, the thing that makes participation cheap beats the thing that makes participation profitable, because the former has more participants.

Smart Protocol is founded on that observation and takes it seriously: **if the contract is the durable artifact, then writing the contract deliberately is the highest-leverage act available in systems software.** Not a product that might become a platform. Not a platform that might become an ecosystem. The layer underneath, specified first, owned by nobody.

---

## II. The era this is written for

Every system contract encodes an assumption about who is on the other side.

The syscall table assumes a program. The permission model assumes a person. The session assumes a seat at a keyboard. The display protocol assumes a window. Each assumption was correct for its era and becomes a constraint in the next one.

The assumption that is now failing is the person. Not because people stop using computers, but because the *caller* of a system is increasingly not one. An agent composes operations at machine speed, holds attenuated authority it was granted rather than earned from an account database, and may execute somewhere the human never goes. A contract designed for a human at a terminal treats that caller as an exception: a service account, a bot flag, a privileged API, a back door.

Smart Protocol rejects the premise that either caller is the default.

The six shapes of the contract — library, CLI, IPC, file, network, script — are equal by construction. A human typing a command and an agent calling over a network hold the same references, pass the same handles and hit the same gates. There is no human API and machine API that must be kept in sync, because there is one API and the contract cannot tell who is calling.

That equality is not a courtesy to agents. It is what makes the system auditable: authority is visible in the references a process holds, whoever holds them.

---

## III. The mechanism: refusal

A contract that lists everything it permits has already conceded. Any list is today's list; it becomes a lie on a schedule. So this contract is written the other way around — as a set of refusals, each enforced by a machine.

### It refuses to name today's technology

No vendor in a required position. No platform noun. No POSIX artefact dressed as a type. The validator's E9 rule bans the vocabulary outright: `systemd`, `cgroup`, `stdout`, `inode`, `grub`, `pulseaudio`, `kubernetes`, `x86`, `arm64` and their relatives do not appear in a required field anywhere in the tree.

No frozen paradigm either. `ai.capnp` contains **zero enums**, and E1 fails the build on the first one — because an enum value in Cap'n Proto is a permanent ordinal, and a permanent ordinal for `transformer`, `gguf` or `q4km` is a contract asserting that the future will look like the present. Where a technology-specific value must cross the boundary it travels as a `T.MimeType` or a `T.StringMap` key, which any backend can extend without an edit to the schema.

### It refuses to prescribe an algorithm

No scheduler policy, no eviction strategy, no compressor, no dependency
resolver, no transport. "Declare that this job may run when the machine is
idle" is a contract; "use a weighted fair queue" is an implementation. The
backend tunes, the backend chooses, and the contract asks only what crosses the
boundary.

### It refuses to sit in the way of data

Cap'n Proto's zero-copy applies to the serialised message, not to transport. Anything placed in a field — a `List(Float32)`, a `Text`, an inline `Data` — is copied into the message and cannot be zero-copy. Only `T.DataHandle` escapes that: an inline `Data` for small payloads, a `BufferId` reference for large ones.

So every bulk payload in the tree is a `T.DataHandle`. The validator enforces it (E2 in `ai.capnp`, E10 tree-wide). 421 positions in the schemas carry it. A frame, an embedding, a container image, a crash dump or a model's response travels as a reference to a buffer, never as a copy of one.

### It refuses a second permission system

In Cap'n Proto RPC, a capability *is* a reference: holding it conveys the authority to call it. So authority is expressed by which reference you hold, gated exactly once at acquisition. Discovery is ungated — a system that deadlocks before it can discover anything never runs. Everything that consumes a resource or mutates state sits behind an accessor that takes a `Capability` and returns a service. Nothing behind that accessor takes a token. Not a smaller token. No token.

The revamp deleted every second authority grammar that had grown in the tree: role strings, ACLs, per-method capability parameters, free-text authority headers, permission enums, per-command tokens. Each duplicated authority the reference already carried, producing two paths that had to agree forever — and the parallel path keyed by free text could never be revoked.

Delegation lives in exactly one file. `capability.capnp` issues, attenuates, transfers and revokes. Weakening a capability and handing the narrower reference on is the only way to delegate, and a `DelegationChain` records parentage so that revoking a root takes its derivatives with it. A second delegation grammar is a second authority system, and a second authority system is a hole with a schema ID.

### It refuses to guess at what a handle contains

`ProcessId`, `BufferId`, `DeviceAddress`, `Capability.id` are opaque. The backend decides the backing; the protocol never parses it. Lifecycle is one canonical vocabulary, `T.ExecutionState`, shared by every component that has a lifecycle — including the ones a POSIX system would describe with its own vocabulary of zombies and signals.

Opacity is not laziness. Every structured field is a commitment about how a component works, and every such commitment is a small piece of implementation leaked into a contract that is supposed to outlive it.

### It refuses to break a consumer for being old

Every event union terminates in an `unknown` arm carrying the canonical `T.UnknownEvent { typeId, payload }` — 154 arms across 49 schemas. A producer can forward an event kind it did not foresee; a consumer that does not understand it routes it without breaking. Unrecognised media types, capability names and metadata keys are **ignored, never rejected**.

This is what makes new capability addable without a schema version bump: the protocol does not grant a new capability permission to exist, it simply refuses to be broken by it.

### It refuses to make an implementation irreplaceable

The Swap Test is the audit that closes the argument. Take any component — kernel, compositor, audio server, filesystem, init system, AI backend — and replace it with a different implementation of the same schema. If the rest of the system notices, the contract leaked implementation and the leak is a bug.

The tests are not hypothetical. They are the reason the kernel schema is 248 lines: everything in it that described *how* a kernel works — scheduler introspection, fork flags, kernel swapping — was removed because a second kernel could not have satisfied it.

---

## IV. The test every detail must pass

Two questions decide every line in `schema/`.

**The Agnostic Test.** Is this an *external contract* — what two components exchange in order to interoperate — or an *internal implementation* — how a component works? External goes in the protocol. Internal stays inside the component. "Resolve this hostname" is a contract. "Use systemd-resolved" is an implementation. "Declare that this service receives 512 MB" is a contract. "Create a cgroup with `memory.max`" is an implementation.

**The Swap Test.** If this implementation is replaced by another, does the contract still hold? If not, the contract has captured something it had no right to capture.

The tests are deliberately boring, because they have to be applied thousands of times by people who are tired. In practice they have a body count. The 2026-10-10 revamp cut the kernel schema from 881 lines to 248, the boot schema from 1,166 to 727, and the service schema by 40%, on these two questions alone. Everything removed was something one implementation needed and no contract should promise.

The doctrine in full — the tests, the opacity principle, the anti-pattern catalogue, the schema template and the rule table — is [`../DESIGN_PRINCIPLES.md`](../DESIGN_PRINCIPLES.md).

---

## V. Permanence is a procedure, not a promise

A contract is only as durable as its evolution rules, so they are written down and enforced.

1. **Ordinal stability.** Once published, a method's ordinal is permanent. New capabilities take fresh ordinals and never displace old ones.
2. **Additive by default.** New methods, types and fields are minor versions. A breaking change is a new schema ID; the retired ID is never reused.
3. **ABI negotiation.** `abi.capnp` lets two parties declare what they speak and agree on the intersection before either commits to a call.
4. **Forward compatibility.** Every union has an unknown arm; every open vocabulary tolerates a value it has not seen.
5. **One gate.** E1–E14 run on every change, and a schema that introduces a finding must justify it in its own header, by name and reason.
6. **Pre-release honesty.** Nothing external consumes these schemas yet, so this tree is still allowed to delete rather than deprecate. From first release, the permanent rules bind in full — and that boundary is stated rather than blurred.

The rules are not aspirations. Each has a machine behind it, and the machine is in the repository.

---

## VI. What we owe the implementer

An implementer who reads three schemas has the whole grammar. In return for that afternoon, the contract owes them something specific:

- **Ordinals that never move.** Code written against a schema keeps meaning what it meant.
- **Unknown arms that never break.** A future producer does not crash a present consumer.
- **A gate they can run.** The same checks that govern this repository govern their contribution, publicly.
- **A swap test they can pass.** Any implementation of the schema is as valid as any other, including one that did not exist when the schema was written.

What is asked in return is equally specific: hold your handles opaque, declare what you accept in open tokens, gate once at acquisition, route every failure through `T.Error`, and never freeze a noun into a required position.

---

## VII. The posture

We are not asking for permission and we are not running a funnel.

There is no partner programme, no certification, no conformance tax, no vendor lock, and no roadmap that depends on someone else's approval. The schemas are MIT OR Apache-2.0. The gate is in the repository. The reference implementation exists and speaks the contract. The products this company ships will speak it because they are built on it.

That is the whole adoption strategy: **make the contract correct, make the gate honest, and make at least one implementation undeniable.**

A contract that needs its owners to win is not a contract. It is a product with better branding. The measure of success here is not that Smart Protocol is the only system contract. It is that a system contract exists, that it is written well enough to outlive all of us, and that everything built on it is free to be replaced by something better.

The moat era is ending. The stage is what lasts.

---

*smart-protocol — 89 schemas, 303 interfaces, one wire format, zero frozen nouns. The gate is green. Implement against it.*

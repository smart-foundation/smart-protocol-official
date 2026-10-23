# Vision — what Smart Protocol is for

> This document states the endgame plainly. It separates three things that are
> usually blurred together: what exists now, what follows mechanically from
> what exists, and what is ambition. Sections are labelled accordingly.

---

## I. The claim

Every era of computing is remembered by its contract, never by its products.

The products of an era compete inside a structure they did not build. They win for a decade, they are replaced, and the structure outlives them. TCP/IP outlived the network operating systems that fought it. HTTP outlived every browser that carried it. SQL outlived every database company that implemented it. CSS outlived every rendering engine. POSIX outlived every workstation vendor, and the shell outlived every terminal.

The pattern is not nostalgia. It is mechanical: a product is optimised for its owner's advantage, and a contract is optimised for everyone else's ability to participate. An era's durable artifact is always the thing that made participation cheap.

Smart Protocol is an attempt to write that artifact deliberately, for the era we are entering, instead of waiting for it to accrete.

---

## II. Why now

Three shifts make this the moment a system contract can be written rather than inherited.

**The caller changed.** For fifty years the contract between a computer and its user assumed a human at a terminal, with a human's reaction time, a human's patience and a human's legal identity. That assumption is embedded in every layer: in the syscall table, in the permission model, in the way a session is defined, in the fact that a "user" is a scalar. Agents break the assumption. An agent calls thousands of times a second, composes capabilities it was never given directly, and may run on a different machine than the one whose data it touches. A system contract written for the post-app era cannot privilege either caller. It must be indifferent to which one is on the other side.

**The components multiplied.** A modern system is a bootloader, a kernel, a hundred drivers, a display server, an audio server, a network stack, a filesystem, a package manager, an init system, a security daemon, a compositor, a shell and now at least one intelligence service. Each was specified separately, by a different community, with a different idea of what a handle is. The cost is not inelegance. It is that replacing any one of them requires replacing its neighbours.

**The wire became free.** Zero-copy serialisation and capability-based RPC are no longer research. The technology to pass a reference to a buffer across a process, a machine or a trust boundary — without copying it and without inventing a permission system to protect it — exists and is boring. The bottleneck is no longer machinery. It is agreement.

---

## III. What the world looks like if this succeeds

*Ambition, stated as consequence. Each item follows from the contract as it stands; none of them is a promise about a ship date.*

### 1. Components become a market, not a stack

Today, choosing a kernel chooses an ecosystem. Choosing a display server chooses an application model. Choosing a filesystem chooses an operating system. Those couplings are not technical necessities; they are the absence of a contract.

With one, they dissolve. A kernel is an implementation of `kernel.capnp`. A compositor is an implementation of `compositor.capnp`. An audio server is an implementation of `audio.capnp`. They compete on quality — latency, throughput, security, footprint — and not on lock-in, because none of them owns the boundary. A user replaces a component the way they replace a text editor: on merit, one at a time, without reinstalling the machine.

The economic consequence is larger than the technical one. Competitive pressure moves from "which stack do I trap you in" to "which implementation is better". That is the difference between an industry that improves and an industry that entrenches.

### 2. An operating system becomes a weekend, not a decade

The barrier to writing an OS has never been skill. It is the mountain of incidental specification that sits between power-on and the first useful service: firmware tables, memory maps, page-table formats, interrupt controller quirks, device-tree dialects, boot protocol revisions. None of that is the interesting part of an operating system, and all of it must be right before the interesting part can begin.

The contract moves the incidental part into a schema. A bootloader hands over a declarative manifest: memory regions with open kind tokens, the kernel menu, channels, images, arguments, an optional framebuffer as a handle. No physical-address arithmetic. No page tables. No format knowledge. The kernel boundary is 248 lines that say what a kernel must offer, and nothing about how.

That does not make operating systems easy. It makes them *startable*, by a person with an idea about scheduling, isolation or determinism who currently cannot reach the first line of it. The number of serious OS experiments in the world is small for one reason: the entry cost is not intellectual, it is clerical.

### 3. Intelligence becomes a service, not a platform

The current shape of AI in computing is a vendor inside the system: a privileged API, a proprietary format, a model family named in the configuration, and a permission model bolted on afterwards. Every one of those is a lock-in waiting to happen, and every one of them is a schema decision.

`ai.capnp` makes the opposite decision, and enforces it: zero enums, no architecture, no vendor, no format, no tokenizer, no topology. Every modality travels as one `Artifact` — a mime type plus a `T.DataHandle` — so text, images, audio, video, vectors, PDFs, symbolic terms and formats that do not exist yet are one shape. An agent is not handed a magic API. It is handed a capability, exactly as a filesystem is.

The consequence is that the intelligence layer can be replaced without replacing the system, and a paradigm invented in ten years can be plugged in without a schema edit. The system does not know what kind of mind it is talking to, so any kind of mind can answer.

### 4. Capability becomes portable across devices and boundaries

Authority in this contract is a reference, and references can be attenuated, transferred and revoked. That is a permission model that survives leaving the machine: a capability granted to an agent on a laptop can be handed — narrowed — to a service in a datacenter, and the revocation still cascades.

This is the technical precondition for a computing model in which a person's authority follows them across phone, workstation, vehicle, clinic and orbit, instead of being re-derived by each system from a local account database. The same contract runs bare metal and in a datacenter because it prescribes nothing a small machine cannot do.

### 5. Software outlives its vendor

Ordinals are permanent. Types have one canonical home. Every union terminates in an unknown arm. A publisher can forward an event kind that the consumer has never heard of, and the consumer routes it without breaking. A new method is a fresh ordinal; a break is a new schema ID.

These are small mechanical rules with one large consequence: the code written against this contract has a reason to still work in twenty years. Not because anyone promised it, but because the format of the promise is machine-checked and the gate is in the repository.

### 6. The interface is generated from the contract

The command surface of a system is usually hand-written, and therefore usually lags the system it describes. Here it is derived. `cli.capnp` registers commands by schema identity — a schema ID, an interface name, a method name — so a command routes through a service contract that already exists, and a new domain gains its commands by declaring a schema. The same holds for packaging: anything installed, dispatched or distributed describes itself through one manifest shape.

A contract built to be read by machines from the first line can generate its own front doors.

---

## IV. What must be true for this to win

A vision without falsifiable conditions is marketing. These are the conditions.

1. **The gate must stay honest.** Every rule is enforced on every change, and every residual is published. A contract that hides a defect in prose has already lost.
2. **A second implementation must exist.** One implementation is a product. Two are a contract. The moment a second kernel, or a second compositor, satisfies the same schema and a consumer cannot tell, the claim stops being a design argument.
3. **The reference products must speak it.** The contract is free; the products that ship must earn their place on it. That is the entire adoption strategy: not a funnel, but a proof.
4. **Implementation must stay cheap.** The moment satisfying the contract costs more than ignoring it, the contract dies. Every rule that adds cost must buy a freedom worth more than the cost — which is why the audit history in `audit-revamp/` is about deletion.

---

## V. What is built, what follows, what is ambition

| | State |
|---|---|
| The contract: 89 schemas, 303 interfaces, one wire format | **Built.** Compiles clean; gate green. |
| The gate: E1–E14 over a real parser | **Built.** Runs on every change. |
| The reference OS: the Naledzi microkernel | **Running.** Boots, speaks the contract, feeds the schemas. |
| CLI and library backends | **In progress.** |
| A second independent kernel or compositor | **Not yet.** This is the next falsifiable milestone. |
| An ecosystem of interchangeable implementations | **Ambition.** Follows from the above, not from this document. |

The discipline that keeps this honest is stated once, in the repository, and applies to this document as much as any other: **no claim ships that the gate cannot prove, and a number that is not counted is not a number.** Where the vision runs ahead of the artifact, it says so — here, and in [`VERIFICATION.md`](VERIFICATION.md), which publishes what the tree does not yet satisfy.

---

## VI. The posture

The contract is not a startup's product with better branding. It is an artifact that either earns its permanence by being the best available statement of a system boundary, or does not.

So: no partner programme, no certification tax, no vendor lock, no adoption funnel. MIT OR Apache-2.0, your choice. The gate is in the repository, your choice to run. The reference implementation exists, your choice to study.

What is asked of an implementer is small and non-negotiable: hold your handles opaque, declare what you accept in open tokens, gate once at acquisition, route every failure through the error model, and never freeze a noun into a required position.

What the contract owes in return is permanence: ordinals that do not move, unknown arms that do not break, and a swap test you can run against any backend anyone ever writes for it.

The moat era is ending. The next era needs its stage.

---

*Next: [`ARCHITECTURE.md`](ARCHITECTURE.md) for how the pieces fit; [`MANIFESTO.md`](MANIFESTO.md) for the argument; [`TIMELESSNESS.md`](TIMELESSNESS.md) for why the constraints are shaped the way they are.*

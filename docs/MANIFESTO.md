# smart-protocol — the manifesto

> The protocol is the only thing that must never change. Everything else is replaceable.
>
> — the first line of doctrine, and the entire argument in miniature.

---

## I. The thesis

Every computing era is remembered by its contracts, not its products.

The applications and operating systems of each era were fought-over moats — walled gardens whose owners won for a decade and then lost to the next garden. But the durable value of every era never lived in the moat. It lived in the contract. TCP/IP outlived every network operating system that fought it. HTTP outlived every browser that carried it. SQL outlived every database company that implemented it. CSS outlived every rendering engine. POSIX outlived every workstation vendor. The products were theater. The contracts were the stage, and the stage survived the theater.

Smart-protocol is the system contract for the post-app era. Not an application platform. Not an operating system. The layer everything else is built on: 89 Cap'n Proto schemas defining how every component of a computer — kernel, bootloader, hardware abstraction, drivers, filesystems, display, security, intelligence — talks to every other component. From the kernel's first instruction to an agent's last tool call, there is one wire format, one authority model, one evolution rule.

The post-app era has a mechanical meaning, not a fashionable one. When the caller of a system is as likely to be an agent as a person, the contract cannot privilege either. So this protocol does not: the six shapes — library, CLI, IPC, file, network, script — are equal by construction, because the contract does not know which shape is calling. A human typing a command and an agent calling over the network hold the same references, pass the same handles, and hit the same gates. The CLI is not a human concession and the network is not a machine back door. They are the same contract, reached from different doors.

The claim is simple and it is load-bearing: a contract this clean makes implementations disposable. Swap the kernel, the compositor, the audio server, the AI backend, the filesystem, the init system — userspace does not notice, because userspace never spoke to an implementation. It spoke to the contract. Everything else in computing is argued over. This is the part that is agreed.

What this document does not claim is equally deliberate. This repository is the contract, the doctrine and the gate — not a finished runtime. The reference OS that boots and speaks it exists and feeds the schemas; the CLI and library backends are being built; the ambitions below are labelled as ambitions because an unlabelled ambition is a lie with a deadline. The unforgivable sin in a contract repository is a claim the artifact cannot back, and every sentence here is meant to survive a diff.

---

## II. The doctrine

Six rules. Each one is a mechanism, not an adjective. Each one is enforced by a machine you can run: `scripts/validate.py`, rules E1–E14, exit code 0 or the change does not land.

### 1. The contract is the design. Implementations are disposable.

The Agnostic Test decides everything: *is this an external contract — what two components exchange to interop — or an internal implementation — how a component works?* External goes in the protocol. Internal stays inside the component. "Resolve this hostname" is a contract. "Use systemd-resolved" is an implementation. "Declare that this service gets 512 MB" is a contract. "Create a cgroup with memory.max" is an implementation. The protocol asks what, never how.

This is not a philosophy of restraint. It is a deletion criterion with a body count. The 2026-10-10 revamp of this tree cut the kernel schema from 881 lines to 248 by removing scheduler introspection, CLONE_* fork flags, live kernel swapping, mesh networking, container and unikernel taxonomies, and six interfaces that no method in the entire protocol returned — nothing could call them, so nothing did. It cut the boot schema from 1,166 lines to 727 by demolishing a technology museum: named storage buses, firmware tables, partition-table enums, UART parity settings, ACPI/SMBIOS/DMI table layouts, a raw function-pointer handler table, an HHDM offset. It cut the service schema by 40% by deleting a cloud orchestrator nobody could reach.

What survived is implementable by a microkernel with no scheduler knowledge, no format knowledge and one bootstrap pointer — which is the point. A contract thin enough for any backend to satisfy is a contract no backend can capture. The thinner the contract, the cheaper the next implementation, and the more implementations exist, the more the contract is proven.

The inventory of what the protocol never contains is as important as what it holds. Algorithm hints — the scheduler picks. Performance tuning knobs — the component tunes. Platform assumptions — the word for a Linux fd is not in this tree. Wire format details — the transport owns the wire. Internal state machines — a backend's boot phases are its own. Implementation-specific enums — where a log message goes is the backend's business, not a field in an eternal contract. Every one of those exclusions is a backend's freedom to exist, and the validator's E9 rule watches the door.

### 2. Timelessness is a negative constraint.

You cannot enumerate the future. Any list you write is today's list, and it ages into a lie — a 2026 contract that freezes `transformer`, `onnx`, `gguf` and `q4km` into required fields has asserted that today's AI will still be today's AI. You cannot enumerate what will exist in twenty years. You *can* forbid what may never appear.

So timelessness here is subtraction, not prophecy. The gold standard, `schema/ai.capnp`, contains **zero enums** — not as taste, as a hard gate: validator rule E1 fails on the first one. Every open value in the tree is a token, not a list: a technology that does not exist yet is spellable today with no schema edit and no new ordinal. A modality invented in 2046, a transport invented in 2046, a boot stage invented in 2046 — each is a string the backend declares, and an unrecognized token is ignored, never rejected. `T.MimeType` carries the technology-specific values, `T.StringMap` carries the named-but-unbounded ones — 760 field and parameter positions across the tree, counted from the schemas — and `T.DataHandle` carries anything with bytes.

The crypto schema is the amendment loop made visible: it carried roughly 130 algorithm values in 8 closed enums, in a file that had already corrected itself once for the FIPS 203/204/205 renames — a contract that must be edited every time a standards body renames a construction is a contract that admits it was never timeless. It now speaks open tokens with today's spellings published as conformance constants, and a construction invented next year is requestable with no schema change. The enum that froze 27 compression codecs including `imploded` and `shrunk`, the enum that froze fourteen transport variants by name, the enum that froze today's TLS versions into the foundation — the same mistake with different victims, and the tree no longer contains it in a required position.

Ordinal permanence is the second half. Once published, a method's ordinal is a promise held forever; new capabilities take fresh ordinals and never displace old ones. And every event union terminates in an `unknown` arm carrying the canonical `T.UnknownEvent { typeId, payload }` — 153 arms across 47 schemas — so a producer can forward a kind it did not foresee and a consumer can route it without breaking. Nothing is forbidden; nothing is frozen. The contract accepts what it cannot name.

The other half of subtraction is tolerance. An unrecognized media type, capability name, contributor token, status token or metadata key MUST be ignored, never rejected — a consumer that does not understand a value skips it, and one that does, acts on it. That is what makes new capabilities addable without a schema change: the protocol does not grant them permission to exist, it simply refuses to be broken by them. A closed list can only be extended by its author; an open token can be spoken by anyone, and a strict reader loses nothing it understood.

### 3. Authority is capability. The reference *is* the permission.

In Cap'n Proto RPC a capability is a reference: holding it conveys the authority to call it. So authority in this protocol is expressed by which reference you hold, gated exactly once at acquisition. The shape is everywhere: an ungated discovery surface — learn what exists before you can act, because discovery that deadlocks on a capability is discovery that never runs — and a gated accessor that takes a `Capability` and returns a service. Every method behind that accessor takes no token. Not a smaller token. No token.

The revamp deleted every second authority grammar in the tree: role strings, ACLs, per-method capability parameters, free-text `authority` headers, permission enums, per-command capability tokens. Each one duplicated authority the reference already carried, producing two paths that had to agree forever — and every future method could get one wrong. A parallel model keyed by free-text ids that must agree with the capability system forever is the only one of the two that is not revocable; it was deleted everywhere it hid, from the clipboard to the app layer to the secret store.

Delegation lives in exactly one place: `capability.capnp`'s `attenuate @2`, `transfer @3`, `revoke @4`, `revokeControlled @8`. Weaken a capability — fewer operations, tighter constraints — and hand the reference over. The `DelegationChain` records parentage so a revoked root takes its derivatives with it. There is no delegation method anywhere else, because a second delegation grammar is a second authority system, and a second authority system is a hole with a schema id.

The only hardcoded capability in the system is handle 1: before the kernel enters userspace it places `KernelService` in every process's capability table. Everything else is issued dynamically by `CapabilityService.issue` and delegated through the algebra above. One hardcoded capability in an entire operating system contract. That is the whole security model, stated as an inventory.

The census backs the claim: 24 of the 89 schemas declare a capability-gated root accessor — the AI service, the secret store, the key store, the discovery registry, the sandbox capability admin, the shell interpreter, the file service, and their peers — and in every one of them, the methods behind the gate take no token. Validator rule E11 reads the shape tree-wide, and rule E3 holds the gold standard to it as a hard error. There is exactly one file where a `Capability` parameter is the object under manipulation, and it is `capability.capnp` itself.

### 4. Zero-cost is a rule, not a slogan.

Cap'n Proto's zero-copy applies to the message, not to the transport. Anything you put in a field — a `List(Float32)`, a `Text`, an inline `Data` — is copied into that message. Only a buffer reference escapes. So the rule is mechanical: **`T.DataHandle`, or it is a copy.**

`T.DataHandle` is a union — inline `Data` for small payloads, a `BufferId` reference for large ones — so a small secret stays cheap and a multi-gigabyte memory image never touches the arena. The validator enforces the discipline: E10 rejects bulk payloads outside `T.DataHandle`, E2 rejects bulk lists in the gold standard outright. There are 353 `T.DataHandle` field and parameter positions in this tree.

The rule is not theoretical, and the revamp found where it was being broken in practice. A top-100 vector search copied 1.6 MB of embeddings per query as a float list; it is now a handle with a published media-type convention. A signature verification of a 50 MB artifact copied all 50 MB into the message; every verify path is now a handle. A streaming compression pair — added, its own header said, "for large archives with backpressure" — copied every chunk into the message arena and defeated its own purpose; both directions are now handles. Strokes on the highest-volume pointer-adjacent stream in the protocol carried inline point and pressure lists, a copy per stroke forever; they are two handle arrays with a count. The streaming pairs that claimed backpressure now actually stream.

### 5. Opacity: handles are not parsed.

A type is opaque when consumers never need to inspect its structure, and structured when they must read fields to interoperate. The protocol pushes as far left as the contract allows — and it pushes, everywhere, because every parse of a handle is a dependency on a backend's private business.

`ProcessId` is a number in a wrapper so the type system catches your mistakes — not so anyone reads inside. `Capability.id` is opaque bytes: locally a pointer, in a distributed system a signed token, and the protocol never asks which, because the answer is the backend's business. A file handle is a pure reference — it no longer carries a path or a mode it once forced a distributed backend to fabricate. A DMA buffer carries an opaque token, not a POSIX fd, because an fd is a per-process table index: the number is meaningless in the receiving process, and a browser or Windows backend has no fd at all.

Lifecycle is one canonical set — `T.ExecutionState` with `unknown`, `active`, `blocked`, `suspended`, `terminated` — replacing three rival vocabularies, one of which contained `zombie`: a POSIX afterlife that a capability kernel has no zombie and must not be forced to invent. Trust levels, log levels, page flags and signal kinds each got one canonical home in `types.capnp`, and the rival spellings other files had declared were folded onto it or deleted. An opaque handle is a promise never to parse it. Every id wrapper, every `DataHandle`, every backend-declared token is that promise, kept 353 times over.

### 6. The Swap Test.

For every principle there is a swap, and the swap is the proof. Linux kernel to seL4 microkernel: the same `KernelService` contract, because it defines spawn, signal, memory regions and service resolution — never a scheduler or a page table. PipeWire to a custom Rust audio server: the same `Audio` contract, because the graph model is internal and the protocol sees endpoints and streams. ext4 to a distributed filesystem: the same `Files` contract, because inodes are not on the wire. X11 to Wayland to a compositor not yet invented: the same `CompositorSession`, because surfaces commit by buffer handle and damage is geometry, not pixels. systemd to runit to s6: the same `InitService`, because the protocol sees observable lifecycle, never the dependency-resolution algorithm.

If a swap breaks the protocol, the protocol leaked implementation. That sentence is a test, and the revamp ran it as a deletion criterion — every family that failed it (fork flags, interrupt plumbing, the page-table API, the kernel zoo, the observability platforms, the broker infrastructure, the POSIX permission bits, the credential sextuple) is gone from the tree, and the tree is smaller and stronger for it. A swap that would break the wire is not a swap; it is a redesign deferred to your users.

### The receipt

The doctrine is not a mood. Between August and October 2026 this tree went from 92 schemas to 89, and the deletion is all in one direction. Four files were removed: `ipc-message.capnp`, a nine-line dead duplicate; `filesystem.capnp`, absorbed into `files.capnp` and `mount.capnp`; `surface.capnp`, absorbed into `compositor.capnp`; `textinput.capnp`, absorbed into `ime.capnp` after the two had drifted into incompatible twins. One file was imported from the working OS: `gpu.capnp`. The foundation batch cut its own scope by 31% while adding extension points; the network and storage batch by 12%; the UI and apps batch by 14.5%, and it absorbed two whole files and is still smaller. The platform-noun count tree-wide (validator rule E9) went to zero. The validator grew from five rules to fourteen. Every schema compiles, the gate is green, and the evidence for every claim above sits in `audit-revamp/`, batch by batch, with the verification records — including the found mistakes, the reverted scope, and the items deliberately left for a decision, all named.

### The five questions

Before anything joins the protocol it answers five questions, and any "no" or "yes" in the wrong place ends the conversation:

1. **Can two completely different implementations satisfy this contract?** If no, it is too specific.
2. **Does a consumer need this to interoperate with a provider?** If no, it is not a protocol concern.
3. **Is this describing data that crosses a trust boundary?** If no, it belongs inside the component.
4. **Will this still make sense in ten years, on different hardware?** If no, it is an implementation detail.
5. **Would swapping the underlying implementation break the contract?** If yes, the contract leaks implementation.

Five questions, and the entire tree is downstream of them.

---

## III. What is on the wire

One wire format: Cap'n Proto, from the kernel's bootstrap pointer to an agent's tool call. No serialization step, no runtime diffing, no virtual DOM, no vtables in the hot path. Messages are read where they lie.

Six shapes of the same contract, and no shape is primary:

```
LIBRARY              CLI                 IPC                 FILE
link & call          `smart` command     capnp over          declarative
                                        shared memory       config

NETWORK              SCRIPT
TCP / WebSocket      `.smart` script
remote
```

**library** (link and call), **CLI** (the `smart` command), **IPC** (Cap'n Proto over shared memory), **file** (declarative configuration), **network** (TCP/WebSocket, remote), **script** (`.smart`). The shapes are equal because the contract does not know which shape is calling — an agent calling over TCP has exactly the power of a human typing a command, and the reference implementation's userspace already speaks Cap'n Proto over shared memory with a doorbell.

The surface: 89 schemas, 303 interfaces, roughly 49,500 lines — kernel, boot, HAL, devices, storage, network, UI, security, intelligence. Every schema carries its header as an argument: what the contract is, who consumes it, what is deliberately opaque, and what was deleted and why. The documentation is inside the artifact, where it cannot drift.

The anatomy is the same in every file, and it is readable in a minute. A schema id, then the argument, then the imports, then types ids-first, then interfaces, then events, then the conformance constants that publish today's spellings without making them contract. If a schema ever surprises you, its header has already told you why it looks that way — the revamp wrote the reasons down inside the files themselves, so the next reader does not have to recover them from a diff. That is also why this document can be short: the tree defends itself.

Three conventions are worth naming because they hold tree-wide. **The error model:** anything that can fail returns a union carrying `T.Error` — routable, with a code, a human-readable message and a retryable flag — because a missing file that arrives as a zeroed struct is a bug that ships. **The subscription model:** every live stream is a reference with a bounded `pull` — no raw subscription ids to cancel against a table, no offset-into-a-live-stream arithmetic, no producer that can outrun its consumer. **The session model:** session-based services open with a handshake at ordinal 0, and the shape is documented once, in `session.capnp`, so the other sessions import it instead of drifting into a seventh dialect.

And every claim in this document is gated. `scripts/validate.py` parses the schemas with a real parser — comments stripped first, so prose is not evidence — and enforces fourteen rules: zero enums and zero bulk lists in the gold standard, no platform/vendor/POSIX noun in a required position anywhere in the tree (E9 is zero tree-wide as this is written), no bulk payload outside `T.DataHandle`, no per-method authority token, one canonical home per type name, sequential ordinals, every interface reachable, every union terminated. The tree is green as it stands. The residuals are enumerated, not hidden.

---

## IV. What it makes possible

Six things, in ascending order of how little of them exist yet. The first is running. The rest are what a contract buys you once the first one is true.

**A microkernel you can swap without touching userspace.** Done, not hypothetical: the Naledzi microkernel boots and speaks this contract — `KernelService` at capability handle 1, userspace services exchanging Cap'n Proto messages over shared memory, init spawning from the boot manifest it was handed. Its live `ShellService` (45 methods, counted mechanically) is imported verbatim into `shell.capnp`; its vendor-agnostic GPU contract is imported as `gpu.capnp`; its console byte path and boot configuration plane are imported as-is. The working OS and the canonical contract are now the same artifact, which is what "the contract is the design" looks like when it is true. A second kernel — monolithic, exokernel, actor runtime — implements the same 248 lines and userspace cannot tell the difference.

**A bootloader whose only job is 24 typed bytes at one well-known pointer.** `HandoffPointer` — magic, address, size — resolves to a Cap'n Proto message carrying a declarative `BootManifest`: memory regions with open kind tokens, the kernel menu, channels, images, args as a string map, an optional framebuffer as a handle. No physical-address arithmetic. No page-table concepts. No format knowledge, no memory math, no handler table of function pointers — the old-paradigm orchestration, where services wrote dispatch pointers into a table by slot index, was deleted outright. The founder's directive is now the schema: a person writing an operating system can write this bootloader in an afternoon, without learning the machine.

**A compositor not yet invented.** Surfaces commit by buffer handle; fences are typed handles; damage is geometry, never pixels; surface roles are open tokens published as conformance constants rather than frozen nouns. An AR compositor, a display server on hardware that does not exist, a headless layout engine — each satisfies the same `CompositorSession` by implementing handle passing, not by being named into an enum. Nothing to emulate, because nothing was assumed. The swap from X11 to Wayland to the next thing costs one backend, not one contract revision.

**An AI backend of any paradigm.** `ai.capnp` names no architecture, no vendor, no format, no tokenizer, no model family, no topology. A diffusion engine, a neuro-symbolic solver, a state-space model, a non-neural reasoner, or something not yet conceived — each is a `ModelDescriptor`, and what it *is* appears only as opaque reported metadata, never as a prescribed field. One universal `Artifact` (mime type plus `T.DataHandle`) carries text, images, audio, vectors, PDFs, symbolic terms and formats not yet invented — the previous revision declared vision and audio capabilities while every payload field was `Text`, so those models could not be called at all. The protocol never asks what kind of intelligence you are, so any kind can answer. An agent is not handed a privileged magic API; it is handed a capability, exactly like any other participant.

**A fleet of embedded, aerospace and medical devices speaking one contract.** The handoff is trivial, the nouns are open, the ids are opaque, the wire format does not care whether the CPU is in a phone or a patient monitor. The same schema runs bare metal and in a datacenter, because it prescribes nothing a small machine cannot do and forbids nothing a future one will invent. A device class invented in 2046 claims its device, describes its hardware with an open format token, and streams its frames as handles — no schema edit, because no schema edit was ever required to name it.

**The shell generated from the schemas themselves.** `cli.capnp` registers commands by schema identity — `T.SchemaId`, interface name, method name — so a command routes through an existing service contract and a new domain gains its commands by declaring a schema. The command surface of the system can be generated from the contract itself, because the contract was built to be read by machines from the first line. The manifest schema does the same for bundles: anything installed, dispatched or distributed declares itself through one shape, so an app format invented tomorrow is describable with no change to the catalog that reads it.

---

## V. The posture

We do not need adopters to be right. We are setting a trend, and every product the company ships will speak this contract. That is the whole adoption strategy: the contract is free to implement, the reference implementations exist, and the products that matter to us speak it because we built them to. The era's durable artifact is the contract, and we are writing it. An implementer who reads this repository gets the full grammar in an afternoon — three schemas deep, they have the whole model.

So we will not behave like a company that needs permission. There is no partner program, no certification tax, no vendor lock, no adoption funnel. The schemas are MIT OR Apache-2.0, your choice; the gate is in the repository, your choice to run; the reference OS exists, your choice to study it. A contract that needs its owners to win is not a contract, it is a product with better branding. The trend we are setting is simpler than adoption: implementations that speak one grammar, so that the next era's durable artifact gets written by whoever writes it best.

Which is why the credibility pledge is absolute:

**No claim ships that the validator cannot prove.** E1 through E14 run on every change; the gate is green or the change does not land. A schema that adds a finding must justify it in its own header, by name, with the reason. The residuals in this tree are enumerated in the audit reports, line by line — not because residuals are shameful, but because an unlisted residual is a lie with a schema id.

**When reality changes, the docs are regenerated from the schemas, never hand-authored.** The catalog is downstream of the artifact. The counts are mechanical. The interface names are parsed, not remembered. The README butchers nothing because the README is downstream of the artifact.

To the implementer, the terms are equally plain. Build against the contract, not around it: hold your handles opaque, declare what you accept in open tokens, gate once at acquisition, route every failure through the error model, and never freeze a noun. In return, the contract owes you permanence — ordinals that never move, unknown arms that never break, and a swap test you can run against any backend you or anyone else ever writes for it.

The moat era is ending. Contracts outlive their gardens — TCP/IP, HTTP, SQL, CSS, POSIX — and the post-app era needs its system contract the way every era needed its stage. This is that contract. The implementations are ours to lose. The contract is yours to build on.

---

*smart-protocol — 89 schemas, 303 interfaces, one wire format, zero frozen nouns. The gate is green. Implement against it.*

---

## Start here

- Front door: `README.md` (overview, quick start, gate).
- Doctrine: `DESIGN_PRINCIPLES.md`.
- Timelessness rationale: `docs/TIMELESSNESS.md`.
- Implement a backend: `docs/implementer.md` (minimum viable implementation, 5-step process, per-language notes).
- Run the gate: `python3 scripts/validate.py` (must exit 0).

Previous in the chain: `docs/TIMELESSNESS.md`. Next: `docs/implementer.md`.

---

## Appendix — the reading map

For the reader who wants the argument in file form. Each of these is a single schema; each is readable in minutes; together they are the whole design.

| To see | Read |
|---|---|
| The doctrine in miniature | `schema/ai.capnp` — zero enums, one `Artifact`, discovery ungated, seven gated accessors |
| Authority end to end | `schema/capability.capnp` — issue, attenuate, transfer, revoke, delegation chains |
| The smallest possible handoff | `schema/boot.capnp` — 24 bytes, one manifest, one hardcoded capability |
| A kernel boundary that swaps | `schema/kernel.capnp` — 248 lines, and what is *not* in them |
| The opacity principle applied | `schema/types.capnp` — id wrappers, `T.DataHandle`, `T.ExecutionState` |
| The session pattern, documented once | `schema/session.capnp` — the handshake pattern written down for every session-shaped interface in the tree: one user session (`Session`, here) and five service sessions (`CompositorSession`, `ShellSession`, `WindowManagerSession`, `ImeSession`, `ScreenlockSession`), all of which handshake through compositor's shared `SessionRequest` |
| The canonical vault | `schema/key_management.capnp` — the whole store behind one accessor |
| The subscription discipline | any `*Subscription` interface — bounded `pull`, no raw ids, no offsets into live streams |
| The revocation that cascades | `schema/sandbox.capnp` — `capabilityAdmin`, and why holding the sandbox is not the authority to arm it |
| The shell as a contract | `schema/shell.capnp` — 45 interpreter methods imported from a running OS |

The full catalog, all 89 schemas by domain, is `docs/SCHEMAS.md`. The doctrine in full is `DESIGN_PRINCIPLES.md`; the timelessness argument in full is `docs/TIMELESSNESS.md`; the revamp evidence is `audit-revamp/`. The front door is `README.md`.

And nothing in this document asks to be taken on faith. Count the schemas (`ls schema/`), count the interfaces (`grep -c '^interface' schema/*.capnp`), read the header of any file, run the gate (`python3 scripts/validate.py`), compile the tree (`capnp compile -o- schema/*.capnp`). The claims were checked against those commands when this was written; if a future edit to the tree makes one of them false, the claim is wrong and the document is downstream — regenerate it.

Implement against it.

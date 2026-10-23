# Smart Protocol

**One contract for every component of a computer — from the first instruction to an agent's last tool call.**

Smart Protocol is the open system contract for the post-app era: **89 Cap'n Proto schemas** that define how a kernel, bootloader, driver, filesystem, display server, network stack, security system, language runtime and intelligence service talk to one another. Implement the contract and your component interoperates with every other implementation of every other component — without a coordination meeting, without a version negotiation by email, and without either side knowing what the other is built from.

The contract is the design. Implementations are disposable. That single sentence is the whole architecture: it is why a compositor that does not exist yet can be written against a schema that predates it, why a kernel written in 2046 satisfies a schema written today, and why the products built on this layer are free to be replaced by better ones without taking the system down with them.

---

## The short version

Every computing era leaves behind one durable artifact, and it is never a product. TCP/IP outlived the network operating systems that fought it. HTTP outlived every browser that carried it. SQL outlived every database company that implemented it. POSIX outlived every workstation vendor. The applications were theater; the contract was the stage.

The next era has a property no earlier one had: **the caller of a system is as likely to be an agent as a person.** When that is true, a contract that privileges a human at a keyboard is already obsolete. Smart Protocol is built on the opposite premise — that a human at a CLI and an agent calling over a network hold the same references, pass the same payloads and hit the same gates, because the contract does not know which of them is calling.

That makes three things possible that are not possible today:

**Every component becomes replaceable.** Swap the kernel, the compositor, the audio server, the filesystem, the init system or the AI backend, and userspace does not notice — because userspace never spoke to an implementation. It spoke to the contract. A second kernel implements 248 lines of schema and no application can tell the difference.

**An operating system becomes an afternoon.** A bootloader's entire obligation is 24 typed bytes at one well-known address: a Cap'n Proto manifest describing the memory, the kernel menu, the channels and the arguments. No page tables. No physical-address arithmetic. No format knowledge. Everything after that is a schema implemented behind a capability reference.

**Intelligence becomes a service like any other.** `ai.capnp` names no architecture, no vendor, no model format and no tokenizer — not as a courtesy, but as a hard gate enforced by the validator. A diffusion engine, a state-space model, a neuro-symbolic solver or a paradigm not yet conceived is a `ModelDescriptor` behind a capability, exactly as a filesystem is.

The full argument is in [`docs/VISION.md`](docs/VISION.md). The doctrine is in [`DESIGN_PRINCIPLES.md`](DESIGN_PRINCIPLES.md).

---

## What this repository is — and is not

| It is | It is not |
|---|---|
| A contract: the interfaces two components exchange | A library, a framework or an SDK |
| A specification with a machine-checked gate | A standards body or a committee |
| The layer every implementation is interchangeable across | An operating system |
| MIT OR Apache-2.0, free to implement | A product with a licence fee or a certification tax |

There are no adopters to recruit, because a contract does not need permission to be correct. There is no partner programme and no vendor lock. The schema is the offer: read it, implement it, and your component joins a system that assumes nothing about how you built it.

---

## The mechanism: seven refusals

A contract's power is what it forbids, not what it enumerates. Every refusal below is a freedom for a backend that does not exist yet. Where a rule exists, `scripts/validate.py` enforces it; where none does, review does — and the gap is stated rather than hidden.

| The contract refuses | Because | Rule |
|---|---|---|
| To name a vendor, platform or POSIX noun in a required position | The word for a Linux fd is not a system-contract word | E9 |
| To prescribe an algorithm or a schedule | The backend chooses how it works; the contract says what crosses the boundary | — |
| To freeze today's technology into an enum | An enum is a permanent commitment to a paradigm that will age | E1, E8 |
| To carry bulk data inside a message | A copy is a cost the contract has no right to impose | E2, E10 |
| To accept a second authority grammar | Two permission paths must agree forever, and one is never revocable | E11 |
| To inspect an opaque handle | `ProcessId`, `BufferId` and `Capability.id` are the backend's business | — |
| To ship a union without an `unknown` arm | A producer must be able to forward a kind the contract never foresaw | E6 |

Holding a capability *is* the permission. Discovery is ungated so that nothing deadlocks before it can act; every state-changing accessor takes a `Capability` once, at acquisition, and nothing behind it takes a token. Attenuation, transfer and revocation exist in exactly one file. Authority amplifies nowhere else.

---

## How a system runs on it

```
  bootloader            kernel                 userspace
  ──────────            ──────                 ─────────
  24 bytes     ──▶   BootManifest    ──▶   init  ──▶  services
  at a fixed         (Cap'n Proto)          │
  address                                   ├─ Discovery.register
                                            ├─ CapabilityService.issue
                                            └─ every domain schema,
                                               behind a capability
```

The bootloader places one `HandoffPointer` — magic, address, size — and its job is done. The kernel reads a declarative `BootManifest` and places `KernelService` at capability handle 1, the only hardcoded capability in the system. Init brings up the service plane in dependency order. From that moment the system is a graph of capability references, and every edge in the graph is a schema in this repository.

`docs/ARCHITECTURE.md` walks the whole path, interface by interface.

---

## Six shapes, none primary

```
LIBRARY          CLI                IPC                 FILE
link & call      `smart` command    capnp over          declarative config
                                    shared memory       `smart apply`

NETWORK          SCRIPT
TCP / WebSocket  `.smart` script
remote
```

The six shapes are equal by construction because the contract cannot tell them apart. A shell command is not a human concession bolted onto a machine API, and the network is not a back door around the UI. They are the same method ordinals, the same types, the same capability references, reached through different doors.

---

## What it replaces

This is not a proposal in the abstract. It is a concrete replacement for surfaces that exist today and that each solve one boundary for one platform.

| Legacy surface | Replacement | The mechanism that changes |
|---|---|---|
| The POSIX syscall table | `kernel.capnp`, `process.capnp`, `signal.capnp` | Typed contracts instead of numbered calls: no uid/gid model, no `zombie` state, no inherited file-descriptor table |
| D-Bus service sprawl | `discovery.capnp` + `capability.capnp` | One registry; authority is the reference you hold, not a bus name plus a policy file |
| Wayland / X11 wire protocols | `compositor.capnp` | One commit path: buffer by `T.BufferId`, fence by typed handle, damage as geometry |
| gRPC / protobuf service sprawl | One wire format, six shapes | Zero-copy payloads and capabilities in the RPC layer; an agent on the network has exactly the power of a human at the CLI |
| Vendor AI glue | `ai.capnp` | Zero enums; one `Artifact` for every modality; any paradigm plugs in without a schema edit |
| Per-service permission models | `capability.capnp` | Issue, attenuate, transfer and revoke in exactly one file |

The point is not that those systems were badly designed. It is that each of them specified one boundary for one platform, and a computer is a system of boundaries.

---

## Measured status

Every number below is counted from the tree by `scripts/docstats.py`; every rule result is produced by `scripts/validate.py`. Neither is written by hand, and both can be run in the checkout you are reading.

| Property | Today |
|---|---|
| Schemas | 89 |
| Lines of schema | 49,655 |
| Interfaces | 303 |
| Methods | 3,154 |
| Structs / enums | 2,565 / 461 |
| Bulk payload positions typed `T.DataHandle` | 421 |
| Open-vocabulary positions typed `T.StringMap` | 744 |
| Forward-compatible `unknown` arms carrying `T.UnknownEvent` | 154, across 49 schemas |
| Capability-gated accessors | 35 |
| Compile (`capnp compile`, 89/89) | clean |
| Validator gate | exit 0 |

The gate's enforced rules — E1 (zero enums in `ai.capnp`), E2 (no bulk in `ai.capnp`), E4 and E14 (every interface reachable), E6 (every union extensible), E9 (no platform nouns in required positions), E13 (sequential ordinals) — are all at zero tree-wide. The tree is pre-release, and the remaining REPORT residuals are published rather than hidden: E7 716, E8 267, E10 59, E11 6, E12 1. [`docs/VERIFICATION.md`](docs/VERIFICATION.md) explains what each one means, why the gate still exits 0, and how the count is driven to zero.

**Running today:** the contract, the validator, the generator scripts, and the reference implementation — the **Naledzi microkernel** — which boots and speaks this contract: `KernelService` at capability handle 1, services exchanging Cap'n Proto over shared memory, init spawning from the boot manifest it was handed. The working OS is not a port target; it feeds the canonical schemas. Its `ShellService` (45 methods) was imported into `shell.capnp`, its vendor-agnostic GPU contract became `gpu.capnp`, and its console byte path and boot configuration plane were imported as-is.

**In progress:** the CLI and library backends. They are named here as in-progress because an unlabelled ambition is a lie with a deadline.

---

## Read it in three files

1. **[`schema/ai.capnp`](schema/ai.capnp)** — the doctrine in miniature. Zero enums, one `Artifact` carrying any modality through `T.DataHandle`, discovery ungated, every operation behind a gated accessor.
2. **[`schema/capability.capnp`](schema/capability.capnp)** — authority. Issue, attenuate, transfer, revoke, delegation chains. Nothing else in the tree implements permission.
3. **[`schema/boot.capnp`](schema/boot.capnp)** — the handoff. Twenty-four bytes resolving to a declarative manifest.

Then run the gate:

```bash
python3 scripts/docstats.py    # the inventory above, counted from schema/
python3 scripts/validate.py    # E1–E14; must exit 0
```

---

## Repository map

```
schema/                   the contract — 89 .capnp files, each header an argument
scripts/validate.py       the E1–E14 gate, with a real parser (comments stripped)
scripts/docstats.py       the counter behind every number in these documents
scripts/check.sh          per-file compile check
scripts/regenerate.sh     Rust binding generation
docs/                     VISION, ARCHITECTURE, MANIFESTO, TIMELESSNESS, SCHEMAS,
                          VERIFICATION, implementer, CONTRIBUTING, GLOSSARY, FAQ
DESIGN_PRINCIPLES.md      the constitution: tests, anti-patterns, rule table
BINDING_CONVENTIONS.md    what a language binding author must get right
audit-revamp/             the 2026-10-10 rewrite, batch by batch, with evidence
```

Start at [`docs/README.md`](docs/README.md) for a reading path by role.

---

## Build on it

The contract is free to implement — that is the point of a contract. You need one thing to start: place 24 typed bytes at one well-known address, read the manifest, take the kernel, call `KernelService` at capability handle 1. Everything after that is a schema you implement behind a capability reference.

Bring your own kernel — microkernel, monolithic, exokernel, unikernel, actor runtime. Bring your own compositor, filesystem, audio server and AI backend. The contract asks only three things: exchange what the schemas declare, keep your handles opaque, and never freeze today's nouns into tomorrow's wire.

If you can satisfy `ai.capnp`, your intelligence system is future-proof. If you can satisfy `boot.capnp`, your afternoon handoff is an operating system.

See [`docs/implementer.md`](docs/implementer.md) for the five-step implementation path and per-language notes.

---

## License

MIT OR Apache-2.0, at your option.

# Smart Protocol

**The system contract for the post-app era.**

Smart-protocol is 89 Cap'n Proto schemas that define how every component of a computer — kernel, bootloader, drivers, filesystems, display, security, AI — talks to every other component, so that any two implementations of any component interoperate without coordination, forever. The contract is the design; the implementations are disposable. Authority is a reference you hold, gated once at acquisition. Bulk data is a buffer handle, never a copy. And nothing on the wire names today's technology — which is why a backend built in 2046 satisfies the same schema unmodified. One wire format from the kernel's first instruction to an agent's last tool call; six shapes of the same contract (library, CLI, IPC, file, network, script), none of them primary.

---

## What is in this repository

```
schema/      89 .capnp schemas — the contract itself, with the doctrine in every header
scripts/     validate.py (the E1–E14 gate), check.sh (per-file compile), regenerate.sh
docs/        SCHEMAS.md (the catalog), TIMELESSNESS.md, MANIFESTO.md
DESIGN_PRINCIPLES.md   the doctrine, with the validator's rule table
audit-revamp/ the 2026-10-10 revamp: five batch reports, the verification evidence,
              and INTEGRATION-REPORT.md (the pass that closed every gap the five left)
```

Everything here is checkable. The counts are mechanical, the interface names are parsed, and the gate runs on every change.

## Why it exists

Applications and operating systems are moats. The durable value of every computing era lives in its contracts — TCP/IP, HTTP, SQL, CSS, POSIX outlived every product that fought them. This repository is the contract layer for the era after apps: the stage everything else is built on. It is not a library, not a daemon, not an OS. It is the agreement that makes all of those replaceable.

The mechanism of that agreement is refusal. The protocol refuses to name a vendor, refuses to prescribe an algorithm, refuses to inspect a handle, refuses to carry bulk in a message, refuses a second authority path, refuses an enum where a token will do. Each refusal is a backend's freedom to exist without asking permission — and each is checked by a machine, not by a reviewer's memory.

## The doctrine

Six rules, each a mechanism, each enforced by `scripts/validate.py` (rules E1–E14):

1. **The contract is the design; implementations are disposable.** The Agnostic Test: external contract (what components exchange) goes in the protocol; internal implementation (how a component works) stays inside it. The revamp deleted a kernel schema from 881 lines to 248 on this criterion alone — scheduler introspection, fork flags, kernel swapping and six interfaces nothing could call, all gone.
2. **Timelessness is a negative constraint.** You cannot enumerate the future; you can forbid what may never appear. Zero enums in `ai.capnp` (a hard gate, E1). Open tokens instead of lists. Ordinal permanence. Every event union terminates in `unknown @N :T.UnknownEvent` — 153 arms across 47 schemas.
3. **Authority is capability.** Holding a reference *is* permission. One gate at acquisition: a `Capability` parameter on a root accessor that returns a service; nothing but plain requests behind it. Attenuation, transfer and revocation live in exactly one file — `capability.capnp`. The revamp deleted every second authority grammar: role strings, ACLs, per-method tokens, authority-as-text. The only hardcoded capability in the system is handle 1, `KernelService`, placed by the kernel before entering userspace.
4. **Zero-cost is a rule, not a slogan.** `T.DataHandle` or it is a copy: the union is inline `Data` for small payloads, a `BufferId` reference for large. Validator rules E2/E10 reject bulk payloads outside it. 353 field and parameter positions in the tree are typed `T.DataHandle`, and that number is counted from the schemas, not remembered.
5. **Opacity.** Handles are not parsed. `ProcessId`, `BufferId`, `Capability.id` are opaque; the backend decides the backing, the protocol never inspects it. Lifecycle is one canonical set (`T.ExecutionState`) — no POSIX afterlife anywhere.
6. **The Swap Test.** Swap the kernel, compositor, audio server, filesystem or init system and the protocol still runs. If a swap breaks the protocol, the protocol leaked implementation — and the leak is a bug.

## What it replaces

| Legacy surface | Replacement | Mechanism |
|---|---|---|
| POSIX syscall surface | `kernel.capnp` / `process.capnp` / `signal.capnp` | Typed contracts: `spawn`, `resolveService`, typed signal kinds — no POSIX numbers, no uid/gid model, no `zombie` state. E9 (platform nouns) is 0 tree-wide. |
| D-Bus service sprawl | `discovery.capnp` + `capability.capnp` | One registry gated at acquisition; authority is the reference you hold, not a bus name plus a policy file. |
| Wayland/X11 wire protocols | `compositor.capnp` | One `CompositorSession`, one commit path: buffer by `T.BufferId`, fence by a typed handle, damage as geometry. The backend's display protocol is internal. |
| gRPC/protobuf sprawl | One wire format | Cap'n Proto everywhere, zero-copy, six equal shapes. An agent calling over the network has exactly the power of a human at the CLI. |
| Vendor AI glue | `ai.capnp` | Zero enums; no architecture, vendor or format named; one `Artifact` (mime type + `T.DataHandle`) carries every modality. Any paradigm plugs in without a schema edit. |

## Six shapes, none primary

```
LIBRARY          CLI               IPC               FILE
link & call      `smart` command   capnp over        declarative config
                                  shared memory     `smart apply`

NETWORK          SCRIPT
TCP/WebSocket    `.smart` script
remote
```

A human typing a command and an agent calling over the network hold the same references, pass the same handles, and hit the same gates. The shapes are equal because the contract does not know which shape is calling.

## Current state — honestly

- **89 schemas**, 303 interfaces, ~49,500 lines. All compile (`capnp compile`, 89/89). The validator gate is green: `python3 scripts/validate.py` exits 0, with E1, E2, E4, E6, E9, E12, E13 and E14 at zero tree-wide — including E12, one canonical home per type name, which the 2026-10-10 integration pass closed by resolving all 36 cross-file duplicates. The remaining E7/E8/E10/E11 REPORT residuals are enumerated rule by rule in `audit-revamp/INTEGRATION-REPORT.md`.
- **Reference implementation: the Naledzi microkernel.** A working Rust microkernel that boots and speaks this contract — `KernelService` at capability handle 1, userspace services exchanging Cap'n Proto messages over shared memory. This is not a port plan; the live working tree feeds the canonical schemas: its `ShellService` (45 methods) is imported verbatim into `shell.capnp`, its vendor-agnostic GPU contract is `gpu.capnp`, its console byte path and boot configuration plane are imported as-is.
- **In progress:** the CLI and library backends. This repository is the contract, the doctrine, and the gate — the runtimes that speak it are being built, and every product the company ships will speak this contract.
- **The 2026-10-10 revamp** rewrote all 89 schemas against the doctrine: four files deleted or absorbed (`ipc-message`, `filesystem`, `surface`, `textinput`), one imported (`gpu`), every technology museum demolished, every second authority grammar removed. The evidence is in `audit-revamp/`, batch by batch, with the verification records and the integration report that closed what they left open.

## How the contract stays forever

1. **Ordinal stability** — once published, a method's ordinal is permanent; new capabilities take fresh ordinals.
2. **Additive only** — new methods, types and fields are minor versions. Breaking means a new schema ID.
3. **The pre-release carve-out** — nothing external consumes these schemas yet, so ordinals may still be renumbered and deletion preferred over deprecation. From first release, the permanent rules bind in full.
4. **Forward compatibility** — every event union ends in `unknown @N :T.UnknownEvent { typeId, payload }`, so a producer can forward a kind it did not foresee and a consumer routes it without breaking.
5. **ABI negotiation** — `abi.capnp` lets two parties declare what they speak and agree on the intersection before either commits to a call.
6. **The gate** — E1–E14 run on every change. A schema that adds a finding must justify it in its own header. The gate is green or the change does not land.

## The gate: what is mechanically enforced

`scripts/validate.py` parses the schemas with a real parser — comments stripped first, so a phrase in prose is not evidence — and enforces:

| Rule | Enforces |
|---|---|
| E1 | `ai.capnp` declares zero enums |
| E2 | `ai.capnp` has no bulk lists — payload is `T.DataHandle` |
| E3 | `Capability` appears only on `AI` accessors |
| E4 | Every interface is reachable |
| E5 | Every stream's `pull` returns a structural terminator |
| E6 | Every union has an `unknown`/`custom` variant |
| E7 | Every struct has an open extension point (value structs exempt) |
| E8 | Every enum's `@0` is a neutral sentinel |
| E9 | No platform, vendor or POSIX noun in a required position |
| E10 | No bulk payload outside `T.DataHandle` |
| E11 | Authority is the reference — no per-method token, no authority-by-string |
| E12 | One canonical home per type name |
| E13 | Interface method ordinals sequential and declared in order |
| E14 | Every interface reachable; no declared type unreferenced |

E1–E5 are hard ERRORs for the gold standard and REPORT elsewhere; E6–E14 are measured tree-wide. Current run: 89 schemas parsed, exit 0, E1/E2/E4/E9 at zero across the whole tree.

## What a schema looks like

Every schema opens with its argument, not its advertisement — what the contract is, who consumes it, what is deliberately opaque, what was deleted and why. The shape is identical tree-wide:

```capnp
interface AI {                                                     # schema/ai.capnp
    handshake @0 () -> (info :T.Version,
                        contentTypes :List(T.MimeType),
                        models :List(ModelDescriptor));            # ungated
    discover  @1 (model :ModelId) -> (descriptor :ModelDescriptor);

    models    @2 (authority :Capability) -> (service :ModelService);   # gated once
    inference @3 (authority :Capability) -> (service :InferenceService);
}
```

That is the whole authority model, and it is the same in every schema: ungated discovery, one gate at acquisition, plain requests behind it.

## Quick start — the mental model

Read three files, in this order, and you have the whole design:

1. **`schema/ai.capnp`** — the doctrine in miniature. Zero enums; every bulk payload a `T.DataHandle`; discovery ungated, everything else gated once at acquisition. If a schema in this tree ever confuses you, this file is the answer to "what would the contract do?"
2. **`schema/capability.capnp`** — authority. Issuance, attenuation, transfer, revocation, delegation chains. Nothing else in the tree implements permission, because nothing else needs to.
3. **`schema/boot.capnp`** — the handoff. A 24-byte pointer at a well-known address resolves to a declarative Cap'n Proto manifest. No memory math, no format knowledge, no handler tables. This is how small a system contract can be.

Then:

```bash
python3 scripts/validate.py        # the gate: E1–E14 over all 89 schemas
```

The subscription pattern is worth one look as well: every live stream is a reference with a bounded `pull` — no raw subscription ids, no offset-into-a-live-stream arithmetic, no producer that can outrun its consumer. And the error model: anything that can fail returns a union carrying `T.Error`, so a missing file, a failed fetch and a locked SIM are routable, not silent.

The doctrine documents (`DESIGN_PRINCIPLES.md`, `docs/TIMELESSNESS.md`), the full schema catalog (`docs/SCHEMAS.md`) and the argument for what this is (`docs/MANIFESTO.md`) sit alongside. Validator green. Every claim in this README is checkable against the files.

## Build your own OS on this

The contract is free to implement. That is the point of a contract.

You need exactly one thing to start: place 24 typed bytes at one well-known address. The bootloader's entire job is a Cap'n Proto message describing what it handed you — memory regions, the kernel menu, channels, arguments. No HHDM, no page tables, no format knowledge. Read the manifest, take the kernel, call `KernelService` at capability handle 1. Everything after that — services, filesystems, display, security, intelligence — is a schema you implement behind a capability reference, and any two implementations swap without userspace noticing.

Bring your own kernel: microkernel, monolithic, exokernel, runtime. Bring your own compositor, your own filesystem, your own AI backend. The contract asks only that you exchange what the schemas declare, keep your handles opaque, and never freeze today's nouns into tomorrow's wire. If you can satisfy `ai.capnp`, your intelligence system is future-proof; if you can satisfy `boot.capnp`, your afternoon handoff is an operating system.

The stage is built. Bring your theater.

---

## License

MIT OR Apache-2.0 (your choice)

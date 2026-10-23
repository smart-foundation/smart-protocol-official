# Contributing to Smart Protocol

This repository is the contract. Implementation code lives elsewhere; a change here changes the system contract and must pass the doctrine in `README.md` and `DESIGN_PRINCIPLES.md`.

## How to propose a schema change

1. Read `DESIGN_PRINCIPLES.md` §1 (Agnostic/Timeless Test), §5 (Swap Test), and §4 (Schema Template).
2. Decide whether the proposal is external contract (what components exchange) or internal implementation (how a component works). Only external contract belongs here.
3. Draft the schema edit in `schema/<name>.capnp`, following the canonical template in §4 of `DESIGN_PRINCIPLES.md`.
4. Run `python3 scripts/validate.py` and `bash scripts/check.sh schema/<name>.capnp`.
5. Open a pull request. The PR must state which Agnostic Test and Swap Test questions were answered and how.

Do not edit `scripts/validate.py` to silence a finding. A schema that adds a finding must justify it in its own header.

## The Agnostic Test

From `DESIGN_PRINCIPLES.md` §1: "Is this an EXTERNAL contract (how components interoperate) or an INTERNAL implementation (how a component works)?"

External contract belongs in the protocol. Internal implementation belongs inside the component. Litmus questions:

1. Can two completely different implementations satisfy this contract? If no, it is too specific.
2. Does a consumer need this to interoperate with a provider? If no, it is not a protocol concern.
3. Is this describing data that crosses a trust boundary? If no, it belongs inside the component.
4. Will this still make sense in 10 years on different hardware? If no, it is an implementation detail.
5. Would swapping the underlying implementation break the contract? If yes, the contract leaks implementation.

## The Swap Test

From `DESIGN_PRINCIPLES.md` §5: swap the implementation of a component. If the protocol still works, the principle holds. If a swap breaks the protocol, the protocol leaked implementation and the leak is a bug. Examples in that document: Linux kernel -> seL4, PipeWire -> custom Rust audio server, ext4 -> Ceph/GlusterFS, X11 -> Wayland -> custom compositor, systemd -> runit -> s6.

## What a schema MUST contain

From `DESIGN_PRINCIPLES.md` §4:

| Element | Purpose | Example |
|---|---|---|
| Interfaces | Define the contract surface | `interface Process { ... }` |
| Types | Data structures crossing trust boundaries | `struct ProcessInfo { ... }` |
| Enums | Finite sets of states/categories | `enum ProcessState { ... }` |
| Events | Observable state changes | `struct ProcessEvent { union { ... } }` |
| Subscriptions | How consumers observe changes | `interface ProcessSubscription { pull @0 () -> ...; }` |
| Capabilities | Authority needed or granted | `enum ProcessCapability { ... }` |
| Doc comments | Explain WHY, not WHAT | `# Backend decides scheduling; protocol sees only state.` |

## What a schema must NOT contain

From `DESIGN_PRINCIPLES.md` §3 and §4:

| Element | Why not | Where it belongs |
|---|---|---|
| Algorithm hints | "Use round-robin scheduling" | Inside the component |
| Performance tuning | "Set thread stack size to 2MB" | Inside the component |
| Platform assumptions | "inode", "syslog", "zombie" | Use universal terms |
| Wire format details | "Use little-endian encoding" | Inside the transport |
| Internal state machines | "Transition from INIT to RUNNING" | Inside the component |
| Optimization parameters | "Use 4KB pages" | Inside the kernel |
| Implementation-specific enums | `LogOutput { stdout, stderr, journal }` | Use opaque `Text` targets |
| Permission strings / roles / ACLs | Second authority path | `capability.capnp` |

## Schema template

From `DESIGN_PRINCIPLES.md` §4:

```capnp
@0x<unique_hex_id>;

# =====================================================================
# <ServiceName> - <one-line description of what this contract governs>
#
# <2-5 sentences explaining:
#   1. What this service IS (the contract, not the implementation)
#   2. Who consumes it (apps, other services, the kernel)
#   3. What is deliberately left opaque (implementation freedom)
#   4. How it relates to other services>
# =====================================================================

using T = import "types.capnp";
using import "capability.capnp".Capability;

# --- Types -----------------------------------------------------------
# All types used by this service's interfaces.

# --- Interface -------------------------------------------------------
# The primary interface (or Session interface for session-based services).

interface <ServiceName> {
    # Session-based services start with handshake:
    # handshake @0 (...) -> (...);

    # Methods organized by concern, ordinals assigned sequentially.
}

# --- Events ----------------------------------------------------------

# --- Capabilities ----------------------------------------------------
# What authority this service requires/grants.
```

## The validator gate

Run:

```bash
python3 scripts/validate.py   # parses all 89 schemas in schema/
```

It parses all schemas in `schema/` with a real parser (comments are stripped first, so prose never counts as evidence) and enforces E1-E14:

| Rule | Enforces |
|---|---|
| E1 | `ai.capnp` declares zero enums. |
| E2 | `ai.capnp` has no bulk lists -- payload is `T.DataHandle`. |
| E3 | `Capability` appears only on `interface AI` accessors (gated once at acquisition). |
| E4 | Every interface in `ai.capnp` is reachable from the root. |
| E5 | Every stream's `pull`/`next` returns a structural terminator. |
| E6 | Every union has an `unknown`/`custom` variant (terminal result unions and error-shaped unions exempt). |
| E7 | Every struct has an open extension point (value structs, id wrappers, and `Artifact` exempt). |
| E8 | Every enum's `@0` is a neutral sentinel (e.g. `unknown`, `none`, `unset`). |
| E9 | No platform, vendor, or POSIX noun in a required position. |
| E10 | No bulk payload outside `T.DataHandle`. |
| E11 | Authority is the reference: no per-method `Capability` token (except `capability.capnp`'s five object-manipulation methods and root accessors returning a service), no authority-by-string fields. |
| E12 | One canonical home per type name. |
| E13 | Interface method ordinals sequential and declared in order; struct fields ascending. |
| E14 | Every interface reachable; no declared type unreferenced. |

E1-E5 are ERROR for `ai.capnp` and REPORT elsewhere. E6-E14 are REPORT for all schemas. The gate exits non-zero only on ERROR. Run `bash scripts/check.sh schema/<file>.capnp` (or with multiple files) to compile-check changed schemas with `capnp compile`.

## Pre-release carve-out

From `README.md` and `DESIGN_PRINCIPLES.md` §4: nothing external consumes these schemas yet, so no ordinal is yet a promise. Until the first external release, ordinals, types, and interfaces may be renumbered, reordered, and deleted outright, and deletion is preferred over deprecation. From first release onward, ordinal stability, additive-only changes, and deprecation bind in full; breaking a published schema requires a new schema ID.

## Versioning

From `DESIGN_PRINCIPLES.md` §4:

1. Ordinal stability: once published, a method's ordinal is permanent; new capabilities take fresh ordinals.
2. Additive changes: new methods, types, enum variants, fields -> minor version.
3. Breaking changes: removing methods, changing signatures or field types -> major version (new schema ID).
4. Deprecation: mark old methods with `# Deprecated: use newMethod instead. Ordinal preserved for wire compatibility.` Never delete them. (Pre-release: delete -- see carve-out.)
5. Forward compatibility: every event/specification union terminates in `unknown @N :T.UnknownEvent { typeId, payload }`. Terminal result unions (`T.VoidResult`, `T.BoolResult`) and `T.DataHandle` are exempt.
6. ABI negotiation: use `abi.capnp` so two parties declare what they speak and agree on the intersection before either commits to a call.

## Capability integration

From `DESIGN_PRINCIPLES.md` §4:

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

Rules:

- Authority is the interface reference, not a per-method parameter. Holding the reference conveys authority.
- A `Capability` parameter is legal in exactly two places: on a root accessor that returns a service, and inside `capability.capnp` on the five methods that act on the capability it names (`attenuate @2`, `transfer @3`, `revoke @4`, `revokeControlled @8`, `evaluateCondition @11`).
- Ungate discovery: "what exists and what can it do" must be readable without authority.
- Attenuation, transfer, and revocation are `capability.capnp`'s job; do not re-specify them per service.
- Do not define permission strings, boolean flags, or role-based access control in the protocol. The capability system is the access control mechanism.
- Capability verification is a backend concern; the protocol only specifies the contract.

## Error model

From `DESIGN_PRINCIPLES.md` §4: all methods that can fail return a result union containing `T.Error`. Methods that always succeed return `Void`. Use the most specific `ErrorCode`. `message` must be human-readable with enough context; `context` should describe the operation attempted; `retryable` true for transient failures. Never swallow errors silently. Custom error types are permitted but must include a standard `ErrorCode` for routing.

```capnp
struct VoidResult {
    union {
        success @0 :Void;
        error @1 :Error;
    }
}
```

## PR checklist

- [ ] Change is external contract, not internal implementation (Agnostic Test).
- [ ] Swap Test passes for the affected component.
- [ ] `python3 scripts/validate.py` exits 0.
- [ ] `bash scripts/check.sh` passes for every changed schema.
- [ ] New findings (if any) are justified in the schema header.
- [ ] Ordinals are additive; no reuse or reordering of published ordinals (or carve-out applies).
- [ ] Event/specification unions terminate in `unknown @N :T.UnknownEvent`.
- [ ] No platform, vendor, or POSIX nouns in required positions.
- [ ] Bulk payloads use `T.DataHandle`.
- [ ] Capability integration follows the two-place rule.
- [ ] Error paths return `T.Error`.

# Timelessness

> How do you write a contract today that a machine built in twenty years can
> satisfy without being edited?

This document is the long answer. It is about one constraint, why it is a
constraint rather than a hope, and where it has already changed the tree.

---

## I. The problem with predicting the future

Every protocol is a bet about what will exist.

The bet is rarely stated. It is made implicitly, one field at a time: a list of
supported codecs, an enum of compression algorithms, a boolean for whether a
display is stereoscopic, a field for the number of CPU cores. Each of those
reads as a description of the present. Each is a prediction about the future,
and each is a permanent one — because in Cap'n Proto a field's ordinal is fixed
for the life of the schema ID, so a field cannot be removed, and an enum value
cannot be renumbered.

The failure mode is not dramatic. It is a slow accumulation of small lies:

- a `Compression` enum with 27 values, including codecs that no longer exist;
- a `Transport` enum with fourteen named variants, none of whose numbers can
  ever be reused when the fifteenth arrives;
- a crypto schema that must be edited every time a standards body renames a
  construction — a contract that admits, by its own changelog, that it was never
  timeless;
- a `LogLevel` enum whose `@0` is `trace`, so an absent field silently means
  the noisiest possible verbosity;
- an AI schema that names `transformer`, `onnx`, `gguf` and `q4km`, freezing
  one decade of machine learning into the foundation of an operating system.

None of these is a bug in the ordinary sense. Each is the most natural thing
to write at the moment it was written. That is the point: **the natural
encoding of today is the anti-pattern of a contract.**

You cannot fix this by trying harder to predict. Prediction has a bounded
shelf life and no verification. The only durable move is to stop predicting.

---

## II. Timelessness is a negative constraint

> You cannot enumerate what will exist in a hundred years, because any list is
> today's list. You *can* specify what must never appear.

This inverts the usual design process. Instead of asking *what should the
contract support?* — a question that can only be answered for the present — ask
*what must the contract never contain?* That question has answers that stay
true: no vendor names, no algorithm choices, no required field whose value is a
fad, no assumption about the shape of a machine.

The constraints are then expressed in the vocabulary the contract uses for
everything else:

| A value that is technology-specific | travels as | `T.MimeType`, an open media-type vocabulary |
| A value that is named but unbounded | travels as | `T.StringMap`, an open key/value vocabulary |
| A payload of any size or shape | travels as | `T.DataHandle`, a buffer reference |
| An event kind the producer invents | travels as | an `unknown` arm carrying `T.UnknownEvent` |
| A capability the backend invents | travels as | a capability reference, gated once |

Three files do most of this work, and every schema imports them:
`types.capnp` defines the open vocabularies (744 `T.StringMap` positions and
421 `T.DataHandle` positions tree-wide), `capability.capnp` defines authority,
and `abi.capnp` defines what two parties say to each other before either
commits to a call.

This is subtraction, not prophecy. Nothing in the tree claims to know what will
exist. The tree only refuses to forbid it.

---

## III. The four mechanisms

Timelessness in this repository is not an attitude; it is four mechanical
properties, each with a rule number.

### 1. No frozen paradigms — E1, E8

`schema/ai.capnp` declares **zero enums**, and validator rule E1 fails the build
on the first one. That is the gold standard stated as a gate rather than a
guideline, because the temptation to add "just one" enum of architectures is
continuous and entirely reasonable.

Enums are not banned everywhere — a finite vocabulary that is genuinely closed
(an error severity, a byte order, a transport state) is legitimate. What is
banned is a `@0` that means a paradigm (E8: every enum's first value must be a
neutral sentinel such as `unknown`, `none` or `unspecified`), and any enum whose
values are the names of today's products.

The replacement pattern is uniform:

```
enum   Architecture { transformer @0; diffusion @1; ... }      ← never
struct ModelDescriptor { ...; metadata :T.StringMap; }         ← always
```

A backend reports what it is. The contract does not ask what kind of thing it is
expected to be.

### 2. Ordinal permanence — E13

Once published, a method's ordinal is permanent. New capabilities take fresh
ordinals; nothing is ever renumbered or reused. E13 enforces that interface
ordinals are sequential and declared in order, so that the wire layout is a
readable property of the file rather than an archaeological one.

The corollary is that deletion is preferred to deprecation while the tree is
pre-release, and that a breaking change is a new schema ID rather than a new
version of the old one. `ai.capnp` is at `@0xa1b2c3d4e5f60109` precisely
because the retired ID `@0xa1b2c3d4e5f60061` was never implemented and the
retired ID is deliberately not reused. An ID bound forever should not be
inherited by a draft that was wrong.

### 3. Forward-compatible unions — E6

Every union terminates in an `unknown` arm. Where the union carries an event,
the arm is the canonical `T.UnknownEvent { typeId, payload }` — 154 of them
across 49 schemas.

```
union {
    started @0 :StartInfo;
    stopped @1 :StopInfo;
    unknown @2 :T.UnknownEvent;   # a kind the producer invented
}
```

A producer can forward an event it did not foresee; a consumer routes it
without breaking. This is the mechanism by which a system built in 2026 can
receive an event kind defined in 2046 and *not fail*. It may not understand the
event — but the contract's obligation is to carry it intact, not to comprehend
it.

### 4. Tolerance, not validation

An unrecognised media type, capability name, contributor token, status token or
metadata key **MUST be ignored, never rejected.** A consumer that does not
understand a value skips it; a consumer that does, acts on it.

This is stated once in the doctrine and repeated in the header of every schema
that has an open vocabulary, because it is the half of extensibility that is
easy to forget. Open vocabularies only help if readers are permissive: a strict
reader turns every future extension into a compatibility incident.

---

## IV. Zero cost is a timelessness property

It is tempting to treat `T.DataHandle` as a performance concern. It is not, or
not only. It is a correctness constraint about what a contract is allowed to
assume.

Cap'n Proto's zero-copy guarantee applies to the serialised message. A field of
type `List(Float32)`, `Text` or inline `Data` is copied into the message that
contains it. That copy is a hidden assumption: it assumes the payload is small,
that the consumer is local, that the producer can afford the memcpy. Every one
of those assumptions is about today's hardware and today's topology.

So there is exactly one way to carry bulk, and it is a reference:

```
union DataHandle {
    inline @0 :Data;        # small payloads
    buffer @1 :T.BufferId;  # large payloads: a reference, never a copy
}
```

E2 enforces it in `ai.capnp` as a hard error; E10 measures it tree-wide. A
4096-dimensional embedding, a video frame, a container image or a model's
response travels as a handle. The contract never decides how much data is too
much, because that decision belongs to the backend and to the moment.

The same logic governs the small things. A timestamp is a struct with an
explicit clock and unit rather than a bare integer, because "seconds since an
epoch" is an assumption about a calendar, a planet and a species. A duration is
explicit about monotonicity. An identifier is an opaque wrapper type rather
than a `UInt64`, so a consumer cannot accidentally do arithmetic on a process
ID and so a backend can change its width without a schema edit.

---

## V. What the tree gave up, and what it bought

The 2026-10-10 revamp applied these rules to every schema in the tree. The
ledger is worth reading as evidence rather than as history.

| Removed | Where it was | What it bought |
|---|---|---|
| Scheduler introspection, `CLONE_*` fork flags, live kernel swap | `kernel.capnp` | A kernel boundary of 248 lines that a microkernel, a monolithic kernel or an exokernel can each satisfy |
| Named storage buses, firmware table layouts, partition enums, UART parity, an ACPI/SMBIOS/DMI surface, an HHDM offset, a raw handler table | `boot.capnp` | A boot handoff of 24 typed bytes and a declarative manifest — no physical-address arithmetic, no format knowledge |
| ~130 algorithm values in 8 closed crypto enums | `crypto.capnp` | Open tokens with today's spellings published as conformance constants; a construction standardised next year needs no schema edit |
| A 27-value compression enum, a 14-value transport enum, frozen TLS versions | several | Codecs and transports that do not exist yet are spellable today |
| Role strings, ACLs, per-method capability parameters, permission enums, free-text authority headers | nine files | One authority model: the reference you hold, gated once |
| A frozen 47-boolean capability catalogue | `system.capnp` | An open token set with an explicit `partial` honesty flag |
| Four whole files (`ipc-message`, `filesystem`, `surface`, `textinput`) | tree | Types with one canonical home (E12) instead of two that must agree forever |

The pattern in every row is the same: something that described *how a
particular implementation worked* was removed, and the contract became smaller,
cheaper to implement, and larger in the number of implementations it admits.

That is the trade timelessness makes. It does not make the contract more
capable. It makes the contract **less wrong, for longer**.

---

## VI. What timelessness is not

It is worth being explicit about the boundaries, because "timeless" is a word
that attracts mysticism.

**It is not a claim of infinite life.** A contract can be defeated by a change
in the structure of computing itself — a move away from addressable memory, a
move to a computational substrate where a "buffer reference" is meaningless.
The claim is narrower and checkable: nothing in this tree is invalidated by a
new vendor, a new algorithm, a new format, a new architecture, or a new
paradigm within the same structure.

**It is not absence of change.** Schemas gain methods and types. The rules
govern *how* they change: additively, at fresh ordinals, with unknown arms and
open vocabularies so that the change does not break a peer that has not been
updated.

**It is not vagueness.** An opaque handle is not an unspecified field; it is a
field whose backing is deliberately the backend's business. The contract is
precise about what crosses the boundary and silent about what does not.

**It is not free.** Every refusal is a burden on the backend: you must report
`metadata` instead of naming a model family; you must open a buffer instead of
passing a pointer; you must tolerate a value you do not understand. The burden
is deliberate. It is the price of a component that can be replaced.

---

## VII. How you check it

Timelessness is not verified by reading this document. It is verified by
running the check, and by reading the one schema where the rules are enforced as
hard errors.

```bash
python3 scripts/docstats.py    # the open-vocabulary counts, from the tree
python3 scripts/validate.py    # E1, E2, E8, E13 and the rest
capnp compile -I schema -o- schema/*.capnp
```

Then read `schema/ai.capnp` — the gold standard, where the doctrine is not
described but implemented: zero enums, one `Artifact` for every modality, every
bulk payload a handle, discovery ungated and every operation behind a gated
accessor.

If a future edit makes a claim in this document false, the claim is wrong and
the document is downstream of the artifact. Regenerate it.

---

*Next: [`implementer.md`](implementer.md) for what this means when you build a backend; [`VERIFICATION.md`](VERIFICATION.md) for what the gate measures and what it does not.*

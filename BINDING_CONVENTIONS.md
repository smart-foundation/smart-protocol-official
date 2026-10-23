# Binding conventions

> For the person writing a language binding — the layer that turns `.capnp`
> schemas into types a program can hold, call and pass.

The schemas are the source of truth. A generated binding is a disposable
artefact: regenerate it from the tree in `schema/`, never hand-edit it, and never
commit it (`gen/` is git-ignored for exactly this reason). Nothing in this
document overrides a schema; where the two disagree, the schema is right and
this document is a bug.

---

## 1. What the generated surface must expose

| Cap'n Proto declaration | Binding surface |
|---|---|
| `struct` | A value type with accessors, one per field |
| `struct { union { … } }` | A tagged value; the active arm is inspectable |
| `enum` | A native enumeration, with an explicit `unknown`/`_` fallback |
| `const` | A compile-time constant (no ordinal, no wire presence) |
| `interface` | A **capability type**: a client-side proxy and a server-side trait |
| Method returning an interface | A capability handle, not a value to serialise |
| `List(T)` | A sequence view; do not copy when the transport allows a view |
| `T.DataHandle` | A payload abstraction: inline bytes or a buffer reference |
| `T.Error` | A native error type preserving `code`, `message`, `context`, `retryable`, `metadata` |

A binding's job is to make the contract *usable* without making it *larger*. If
your binding adds a concept the schema does not have — a role, a permission, a
subscription registry, a copy of a payload — the binding has invented a second
contract.

---

## 2. Naming

### 2.1 Cap'n Proto's own rules

- Type, interface, method and field names are `camelCase` in the schema.
- Enum variants are `camelCase`. They cannot contain underscores, spaces or
  leading digits, so a name that would need one is spelled compactly.

This is a language constraint, not a style choice. Where a compact spelling is
ambiguous to a human, resolve it in the binding, not in the schema:

| Schema variant | What it means | Suggested binding alias |
|---|---|---|
| `surround51` | 5.1 surround | `SURROUND_5_1` |
| `surround71` | 7.1 surround | `SURROUND_7_1` |
| `tarGz` | tar + gzip | `TAR_GZ` |
| `tarZst` | tar + zstd | `TAR_ZST` |
| `v21` | vCard 2.1 | `V2_1` |

Publish aliases as constants in your binding:
`pub const SURROUND_5_1: ChannelLayout = ChannelLayout::surround51;`. Consumers
should never have to memorise the compaction.

### 2.2 Per-language casing

Generate accessors in the host language's idiom — `snake_case` methods in Rust
and Python, `PascalCase`/`camelCase` in Go, `PascalCase` in C++ — while keeping
the **wire name** identical. The byte layout is what interoperates; the
accessor name is a local convenience.

### 2.3 Do not flatten namespaces

Some names appear in more than one schema or in both a struct and an enum
position. Generate into per-schema namespaces (or qualify on import) so that a
consumer never has to guess which `State` it is holding. A flat namespace will
collide, and the collision will be discovered by a consumer, not by a test.

---

## 3. Unions

Cap'n Proto has no file-scope union type. Every union is a field set inside a
struct:

```capnp
struct FrameData {
    union {
        inline  @0 :Data;
        buffer  @1 :T.BufferId;
        unknown @2 :T.UnknownEvent;
    }
}
```

**Binding rule:** `FrameData` is one value with a discriminant. Expose
`which()` (or the host language's equivalent) and one accessor per arm. Do not
generate three unrelated types.

**Unknown arms are not errors.** An arm you do not recognise is carried intact
and skipped, never rejected — the unknown-tolerance rule applies at the binding
layer as much as at the service layer.

---

## 4. Interfaces are capabilities

In Cap'n Proto RPC an interface value is a reference. Holding it is the
authority to call it. Your binding must preserve that:

- **Client side:** an interface field or return value is a proxy object. Calls
  on it are RPC calls. Releasing it releases authority.
- **Server side:** implement the generated server trait (Rust), interface (Go),
  or servant class (C++). You receive a capability reference as an argument; you
  do not receive a token to check.
- **Passing:** passing an interface to a method *transfers a capability
  reference*. It is not a struct copy and it is not a name lookup.

If a binding hides this behind a string id, a service-name registry, or a
permission check, it has replaced the protocol's authority model with a weaker
one.

### Subscriptions

Every `*Subscription` is an `interface`, so it is a capability with two methods:

```capnp
interface ProcessSubscription {
    pull   @0 (maxEvents :UInt32) -> (events :List(ProcessEvent));
    cancel @1 () -> T.VoidResult;
}
```

**Binding rule:** expose it as a live proxy with `pull()` and `cancel()`. Never
model it as an iterator that silently buffers, and never model it as a raw id
plus an offset into a live stream — the schema deliberately has neither.

`pull` is bounded by `maxEvents`. The consumer sets the pace; the producer
cannot outrun it. A binding that fetches in the background has broken that
guarantee, however convenient it feels.

---

## 5. `T.DataHandle` and buffers

```capnp
struct DataHandle {
    union {
        inline @0 :Data;      # small payloads, serialised in the message
        buffer @1 :T.BufferId; # large payloads, a reference
    }
}
```

**Binding rule:** a `DataHandle` is a payload, not a `Vec<u8>` you may eagerly
materialise. Materialise only when the consumer asks for bytes. A binding that
converts every handle to a copy at the boundary has undone the contract's
zero-copy guarantee for every consumer downstream, invisibly.

`T.BufferId` is opaque. Do not expose its width, do not parse it, do not
reconstruct it from a pointer. Ask the buffer service (`buffer.capnp`) for
what you need.

---

## 6. Errors

```capnp
struct VoidResult {
    union {
        success @0 :Void;
        error   @1 :T.Error;
    }
}
```

**Binding rule:** map `T.Error` to the host language's error type without losing
information:

| Field | Must survive as |
|---|---|
| `code` | A typed discriminator (so callers can branch, not string-match) |
| `message` | Human-readable text |
| `context` | What was being attempted |
| `retryable` | A predicate, not a guess |
| `metadata` | Key/value detail |

Do not turn a result union into an exception where the language supports
results, and do not turn it into a nullable return. A null cannot say *why*.

---

## 7. Open tokens

Many fields are `Text`, `T.MimeType` or `T.StringMap` keys with published
conformance values. These are **not enums**. Two rules:

1. **Do not generate a closed enum** from a documented list of constants. That
   would freeze today's spellings into every consumer — the exact mistake the
   schemas removed.
2. **Accept what you do not recognise.** An unrecognised token is ignored, never
   rejected, and never causes a parse failure.

Conformance constants in a schema (the `const` declarations in `ai.capnp`, for
example) are a convenience for producers, not a closed set for consumers.

---

## 8. `const` declarations

A `const` has no ordinal and occupies no wire space. It compiles to a value in
the generated code (or, in dynamic bindings, an accessible symbol). Do not treat
it as a field; do not allocate it in a message.

---

## 9. Generation policy

- **Generate from the tree, at build time.** `scripts/regenerate.sh` drives
  `capnp compile -o rust:gen/`; `gen/` is git-ignored. Other languages follow
  the same pattern with their own plugin.
- **Pin the compiler.** Cap'n Proto's wire format is stable, but generated code
  is not source-compatible across major compiler versions. The reference
  implementation pins `capnp 0.27.x` (Rust) against a system compiler of 1.4.0.
- **One schema, one module.** Keep generated modules aligned with schema files
  so imports (`using T = import "types.capnp"`) mirror module dependencies.
- **Never vendor generated code into the contract repository.**

---

## 10. Checklist for a conforming binding

- [ ] Interfaces are capability proxies/traits, not serialisable structs
- [ ] Subscriptions are live capabilities with bounded `pull` and `cancel`
- [ ] `T.DataHandle` is lazy; no eager copy at the boundary
- [ ] `T.BufferId` exposed as opaque
- [ ] `T.Error` preserves code, message, context, retryable and metadata
- [ ] Union access exposes the discriminant and does not reject unknown arms
- [ ] Open tokens accept unknown values
- [ ] Per-schema namespaces; no flat-namespace collisions
- [ ] Compiler version pinned; generated code reproducible from `schema/`
- [ ] No additional permission, role or registry concept invented

---

*A binding that is smaller than the schema is doing its job. A binding that is
larger than the schema has become a second contract, and the second contract is
the one that will drift.*

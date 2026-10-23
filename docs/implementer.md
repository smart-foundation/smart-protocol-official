# Implementing a backend

> The contract is the design. Your implementation is disposable — including, one
> day, in favour of one that does not exist yet.

This guide is for the person writing a component that speaks Smart Protocol: a
filesystem, a compositor, an audio server, an init system, an AI backend, a
kernel. It assumes you have read [`ARCHITECTURE.md`](ARCHITECTURE.md) and at
least skimmed `schema/types.capnp`.

---

## 1. What counts as an implementation

A conforming component:

- **serves one or more interfaces** from `schema/` over Cap'n Proto RPC;
- **publishes a `ServiceDescriptor`** with `DiscoveryRegistry.register`, reached
  through the capability-gated `Discovery.registry`;
- **publishes capabilities** — opaque `id`, textual `target`, granted
  `operations`, optional constraints and expiry — and delegates only through
  `capability.capnp`;
- **carries bulk through `T.DataHandle`**, never as an inline list;
- **routes failure** through a result union carrying `T.Error`;
- **degrades honestly**: `REAL`, `DEGRADED` or `Unavailable` with a measured
  reason, never a fabricated value;
- **holds no authority state beyond the references it was given**. If your
  service keeps a table of who is allowed to do what, you have built a second
  permission system.

Everything else — your storage engine, your scheduling policy, your threading
model, your language, your process model — is yours and is invisible to the
contract.

---

## 2. The five steps

### Step 1 — read four schemas

In this order:

1. **`types.capnp`** — `T.DataHandle`, `T.Error`, `T.UnknownEvent`,
   `T.ExecutionState`, `T.StringMap`, the opaque id wrappers, `T.Timestamp` and
   `T.Duration`.
2. **`capability.capnp`** — issue, attenuate, transfer, revoke. Authority is
   the reference; nothing else in the tree implements permission.
3. **`discovery.capnp`** — `ServiceDescriptor`, `ServiceHealth`, and the
   ungated-discovery / gated-registration split.
4. **Your domain schema** — note the method ordinals, the result unions, and
   whether a root accessor takes a `Capability`.

Read the header of your domain schema first, not its declarations. The header
states the boundary, what is opaque, and what was deleted.

### Step 2 — implement the server interface

Cap'n Proto's code generator emits a server trait (Rust), interface (Go), or
servant class (C++) per `interface`. Implement every method.

Three rules apply to every method:

- **Ordinals are positional.** Do not reorder, do not invent. Your generated
  code already maps them.
- **Anything that can fail returns a union carrying `T.Error`.** Use
  `code`, `message`, `context`, `retryable` and `metadata`; do not return an
  empty struct to mean failure.
- **No authority token in a method signature.** If the schema has one, the
  schema is wrong — report it, do not implement around it.

### Step 3 — publish a discovery descriptor

Build a `ServiceDescriptor`:

| Field | What to put in it |
|---|---|
| `id` | A `T.ServiceId` your host assigned; not a name you invented in a string |
| `name` | Human-readable, stable |
| `category` | An **open token** — `storage`, `display`, a token you invent |
| `version` | `T.Version` |
| `state` | Declared lifecycle state |
| `endpoints` | Transport token plus an address **in that transport's vocabulary** |
| `requiredCapabilityIds` | What you need, not what you grant |
| `metadata` | `T.StringMap` — put backend-specific detail here, not in required fields |
| `expireAt` | Set it if the service is transient |

Register through `DiscoveryRegistry`, which you obtain from
`Discovery.registry(authority)`. Registration is gated; lookup is not. Publish
`ServiceHealth` as it changes — `reason` and `sinceValid` are what let a
consumer distinguish "degraded since ten seconds ago" from "degraded for a
week".

### Step 4 — publish capabilities

```
Capability {
  id        : opaque bytes decided by your backend
  target    : textual description of the resource
  operations: the granted subset of the Operation algebra
  constraints / expiry / audit
}
```

Issue, attenuate, transfer, revoke — all through `capability.capnp`. Delegation
is attenuation plus transfer: drop operations, tighten constraints, hand over
the narrower reference. Never add a role string, an ACL, a per-method token or
a free-text authority field. A second authority grammar must agree with the
first forever, and the text one can never be revoked.

### Step 5 — prove it against the contract

```bash
capnp compile -I schema -o- schema/*.capnp      # the tree still compiles
python3 scripts/validate.py                     # the gate still exits 0
bash scripts/check.sh schema/<your>.capnp       # your file, on its own
```

Then the tests no static check can replace:

1. **Serve one interface and call it from a client in a different process.**
   This proves the transport, not just the types.
2. **Pass a large payload.** Send a 64 MiB buffer as a handle and confirm no
   copy occurred at the boundary.
3. **Call an unsupported operation.** Confirm it returns `Unavailable` with a
   reason, not a plausible-looking empty result.
4. **Swap a peer.** Replace your client with a mock that speaks the same
   schema. Your server must not notice.
5. **Run the swap test on yourself.** Delete your implementation and point a
   consumer at another one. If the consumer breaks, your contract use leaked
   implementation.

---

## 3. The honesty model

Every backend reports what it can actually do, per operation:

| State | Meaning | Requirement |
|---|---|---|
| `REAL` | Implemented and working as specified | — |
| `DEGRADED` | Works with a named, measured limitation | State the limitation and its cause |
| `Unavailable` | Not implemented on this platform or backend | Return `T.Error` with a reason |

**A fabricated value is the one unforgivable defect.** Returning an empty list
when the backend cannot enumerate, a zero when it cannot measure, or a success
when it did nothing are all worse than failing, because they are undetectable
by the consumer.

`ServiceHealth` and `T.Error` exist so that degradation is visible in-band.
Use them.

---

## 4. Language notes

The contract is language-neutral; only the generated glue differs. The reference
implementation pins Cap'n Proto 0.27.x on the Rust side (`capnp 0.27.2`,
`capnpc 0.27.0`), and `scripts/regenerate.sh` drives `capnp compile -o rust:`
into `gen/`, which is git-ignored. Generated bindings are never committed.

### Rust

`capnp` + `capnpc` in `build.rs`; implement the generated `Server` traits; serve
through `capnp_rpc::RpcSystem` over Unix socket, TCP, or an in-process
two-party transport. Capabilities are `capnp_rpc` references, which maps
directly onto the protocol's authority model.

### Go

`capnp-go` with `capnpc-go`; implement the generated interfaces; serve with the
RPC package over a `net.Conn` or an in-process pipe. Watch reference lifetimes:
Go's GC does not know about capability tables.

### C / C++

`capnpc-c++` for headers; derive servant classes from the generated `Server`
interfaces; dispatch through `capnp::RpcSystem` or a custom transport. Manage
capability lifetimes explicitly and keep buffer ownership clear across the
boundary.

### Python

`pycapnp` for prototypes, tooling and test harnesses: `capnp.load()` the schema,
subclass the generated interfaces, serve with `TwoPartyServer`. Suitable for
proving a contract; usually not for a production data path.

---

## 5. The transport

The contract does not name one. `ServiceEndpoint.transport` is an open token and
`address` is in that transport's own vocabulary, so `capnp`, `unix`, `tcp`,
`websocket`, `shared-memory` and a transport invented in 2046 are all
expressible with no schema edit.

Capability transfer semantics are transport-dependent and must be documented by
whoever defines the transport. The contract guarantees the *shape* of a
capability; the transport guarantees how it moves.

---

## 6. Common mistakes

| Mistake | Why it fails the swap test |
|---|---|
| Storing `uid`/`gid` and checking them per call | You have rebuilt a parallel authority system; a capability transfer will not reach it |
| Naming a technology in a required field (`pulseaudio`, `onnx`, `wayland`) | The next implementation cannot satisfy the schema; E9 fails the build |
| Passing an inline `List(Float32)` because "it's small" | The contract has no small-payload assumption; the copy is a cost you imposed |
| Returning an empty struct on error | The consumer cannot distinguish "none" from "failed" |
| Adding a `custom`/`unknown` arm but rejecting unknown input | Forward compatibility is tolerance, not just a slot |
| Reordering method ordinals while "cleaning up" | Ordinals are permanent; wire layouts do not survive tidying |
| Keeping a service registry of your own | Discovery is the registry; a second one drifts immediately |
| Treating `T.BufferId` as a pointer you can inspect | The buffer's backing is the provider's business |

---

## 7. Conformance checklist

- [ ] Every method in the interface implemented
- [ ] No authority token in any method signature
- [ ] All bulk payloads `T.DataHandle`
- [ ] Every failure path returns `T.Error` with a code and reason
- [ ] Unknown enum/union/token values tolerated, never rejected
- [ ] `ServiceDescriptor` registered and `ServiceHealth` published
- [ ] Capabilities issued and delegated only via `capability.capnp`
- [ ] Handles opaque; no arithmetic on ids
- [ ] Interoperability proven against a second client process
- [ ] `python3 scripts/validate.py` exits 0

---

## 8. Independence

The final test is not that your implementation works. It is that it does not
matter.

Delete it. Write another, in a different language, by a different person. Point
the same consumer at it. If the consumer works identically, the contract held.
If it breaks, the protocol leaked implementation through your backend, and the
leak is a bug in the backend — or, occasionally, in the schema, which is why
this repository exists to be corrected.

That is the whole value proposition: **your work is replaceable, and that is
what makes it safe to build.**

---

*Next: [`CONTRIBUTING.md`](CONTRIBUTING.md) if you are proposing a schema change; [`VERIFICATION.md`](VERIFICATION.md) for what the gate will check.*

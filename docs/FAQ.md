# Questions and objections

The questions this repository actually receives, answered directly. Where an
answer is limited by what exists today, it says so.

---

## "Isn't this just Cap'n Proto?"

No. Cap'n Proto is a serialisation format and an RPC system: it defines how a
struct becomes bytes and how a capability travels between processes. It says
nothing about what a kernel must offer, what a session is, how authority is
attenuated, or what an AI service may be.

Smart Protocol is the layer above: 89 schemas defining which interfaces exist,
what crosses each boundary, and what must never be named. Cap'n Proto is the
transport and encoding this contract chose; a different encoding would change
`BINDING_CONVENTIONS.md`, not the architecture.

The choice is defended in one sentence: **zero-copy serialisation plus
capabilities-as-references is the only widely available primitive that makes
"authority is the reference" true at the wire level.** In a model where a call
carries a token, authority must be reconstructed by every service; here it is
the reference itself.

## "Why not protobuf/gRPC, or JSON?"

Because both copy. A protobuf message owns its bytes, so every payload crossing
a boundary is materialised on each side. That is survivable for a request
object; it is not survivable for a frame, a model embedding, a container image
or a crash dump, all of which this contract must carry.

JSON has the additional problem of being a text encoding with no capability
concept at all: it cannot express "holding this handle is the permission."

Cap'n Proto was chosen for three properties the contract depends on:
zero-copy messages, capability references in the RPC layer, and a strict
ordinal-based evolution model that makes permanence mechanical.

## "Is there a working implementation?"

Yes, partially — and this is the most important honesty boundary in the
repository.

- **The contract**: complete. 89 schemas, 303 interfaces, compiles clean.
- **The gate**: complete and running.
- **The reference OS**: the Naledzi microkernel boots and speaks the contract —
  `KernelService` at handle 1, userspace services exchanging Cap'n Proto over
  shared memory, init spawning from the boot manifest. Several of its live
  contracts were imported into the schemas verbatim.
- **The CLI and library backends**: in progress.
- **A second independent implementation** (a second kernel or compositor):
  not yet. That is the next falsifiable milestone, and the one that turns the
  design argument into a demonstrated fact.

## "Why 89 schemas instead of a small core?"

Because a contract that omits a domain does not prevent that domain from
inventing its own contract. The point of covering files, display, audio,
network, security and intelligence is that those boundaries get specified once,
in one grammar, instead of eleven times by eleven communities.

The schemas are not one monolith: 88 of them import `types.capnp` and little
else, and an implementer can serve one domain without implementing the other 88.
A filesystem does not need to know what a compositor is. What they share is
vocabulary and authority, not coupling.

The tree is also deliberately thin per boundary. `kernel.capnp` is 248 lines;
`boot.capnp` is a 24-byte pointer and a manifest. The breadth is in the number
of boundaries specified, not in the size of each one.

## "How is this different from D-Bus / Wayland / Fuchsia / systemd?"

Each of those specified one boundary for one platform and one era, and each is
good at it.

- **D-Bus** is a message bus with names and a policy layer. Here there is no bus
  daemon in the authority path: discovery is a service, and authority is the
  reference, not a name plus a policy file.
- **Wayland** defines a display protocol generated from XML. `compositor.capnp`
  defines the same kind of boundary without naming a display server, and makes
  it one of 89 boundaries sharing vocabulary and authority.
- **Fuchsia** is a capability-based OS with its own FIDL contracts. This
  repository is the contract layer, not the OS: any kernel, including one
  shaped like Fuchsia's, can implement it.
- **systemd** is an init and service manager whose interfaces are specific to
  Linux. `init.capnp` specifies lifecycle and authority, not dependency
  algebra.

The difference is not that those systems are wrong. It is that none of them
claims to be the contract the whole machine is assembled from, and none of them
is designed to be satisfied by a second, unrelated implementation.

## "Why capability-based security rather than ACLs?"

Because an ACL has to be consulted on every call, by every service, against a
store that must be reachable, consistent and trusted — and because the mapping
from an identity to a permission is a second source of truth that must agree
with the reference forever.

A capability makes the authority and the object identical: if you can call it,
you were given it. Attenuation is then subtraction on the reference, and
revocation is a property of the reference graph rather than a table update.

The practical difference appears when authority leaves the machine. An attenuated
capability can be handed to an agent on another node with the revocation still
cascading. An ACL entry has to be replicated and believed.

## "How do you evolve a contract without breaking it?"

Five mechanisms, all mechanical:

1. **Ordinal permanence** — published ordinals never move or get reused.
2. **Additive changes only** — a break means a new schema ID.
3. **Unknown arms** — every union can carry a kind it did not foresee.
4. **Open tokens** — a new technology is a new string, not a new ordinal.
5. **ABI negotiation** — `abi.capnp` lets peers agree on an intersection before
   either calls.

The pre-release carve-out is stated explicitly: until the first external
release, the tree may delete and renumber. After that, the permanent rules bind.

## "Isn't this over-engineering? Most systems work fine."

Most systems work fine until you try to replace one of their parts. The cost of
a missing contract is not paid at design time; it is paid every time a component
has to be rewritten because its neighbours were built against its internals.

The honest framing: this is not free. Every refusal is a burden on the backend.
The claim is that the burden is smaller than the alternative, and that the
alternative — every implementation defining its own boundary — is how the
industry ends up with eleven incompatible ways to talk to an audio device.

## "What stops this from becoming a standards committee?"

There is no committee, no membership, no certification and no conformance tax.
The contract is MIT OR Apache-2.0. The gate is in the repository. The reference
implementation exists.

The governance model is editorial, not political: the artifact either is the
best available statement of a system boundary or it is not, and anyone can fork
it. That is a weaker guarantee than a foundation and a stronger one than a
vendor's roadmap, because it does not depend on anyone's permission.

## "What is the business model?"

The contract is free to implement, deliberately. The commercial bet is that the
products built on a shared contract are better products than the ones built on
captive boundaries — and that whoever writes the layer everyone builds on has a
durable position without needing to own the implementations.

There is no licence fee, no certification, no partner programme. Every product
the company ships speaks this contract because it is built on it, not because a
customer was locked into it.

## "How do I know the documentation isn't lying?"

Run the commands. Every quantitative claim in these documents is produced by
`scripts/docstats.py` or `scripts/validate.py`, both in the repository:

```bash
python3 scripts/docstats.py
python3 scripts/validate.py
capnp compile -I schema -o- schema/*.capnp
```

The gate currently exits 0 with 1,049 REPORT residuals, all four categories of
which are listed by name in [`VERIFICATION.md`](VERIFICATION.md). That document
exists precisely so that "the gate is green" cannot mean "the problems are
hidden".

If a document and a command disagree, the command is right. Documentation is
downstream of the artifact.

## "Can I implement just one schema?"

Yes. That is the normal way to start. Serve one domain — `Files`, `Discovery`,
`Compositor` — register a `ServiceDescriptor`, publish capabilities, and you
have a conforming component. You do not need the other 88 schemas to be
implemented anywhere.

The only dependencies are `types.capnp` for vocabulary and
`capability.capnp` if you grant or attenuate authority. A minimal service is
genuinely small.

## "Which schema should I read first?"

`schema/ai.capnp`. It is the doctrine in miniature: zero enums, one `Artifact`
for every modality, discovery ungated, every operation behind a gated accessor,
every bulk payload a handle. If you understand that file, you understand the
contract's posture.

Then `schema/capability.capnp` for authority, and `schema/boot.capnp` to see how
small a system boundary can be.

## "What would make you admit this failed?"

Three falsifiable conditions:

1. A second implementation cannot be written without changing the schema — the
   contract captured implementation.
2. Implementing it costs more than ignoring it, for a realistic component — the
   burden exceeds the freedom.
3. Twenty years pass and nothing needs replacing — the contract was solving a
   problem that had stopped existing.

None of those is unfalsifiable, and the third is the one a successful contract
should quietly hope for.

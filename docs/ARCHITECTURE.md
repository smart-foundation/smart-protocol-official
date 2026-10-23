# Architecture — how a system is assembled from the contract

> A specification describes interfaces. An architecture describes the order in
> which they are used. This document walks a cold machine to a running service
> plane, naming the schema at each step.

---

## The five layers

```
  1  HANDOFF        boot.capnp           24 bytes → BootManifest
  2  KERNEL         kernel.capnp         KernelService at capability handle 1
  3  BOOTSTRAP      init.capnp           services brought up in dependency order
  4  SERVICE PLANE  discovery.capnp      descriptors, health, endpoints
     AUTHORITY      capability.capnp     issue, attenuate, transfer, revoke
  5  DOMAINS        the other 84 files   files, display, audio, network, ai, …
```

Everything below layer 5 is implementation. Everything above layer 1 is a
backend. The contract occupies exactly the boundaries between them, and the
boundaries are the only place where two independent efforts must agree.

---

## 1 · Handoff: 24 bytes and a manifest

The bootloader's entire obligation is a `HandoffPointer` at one well-known
address:

```
struct HandoffPointer {
    magic        @0 :UInt64;      # "SMART_PR"
    handoffAddr  @1 :UInt64;      # virtual address, pre-mapped by the kernel
    handoffBytes @2 :UInt64;
}
```

The pointer resolves to a `BootHandoff` message carrying a `BootManifest`. The
manifest is **declarative**: memory regions with opaque kind and flag tokens,
images as opaque regions, the kernel-selection menu, channels, an optional
framebuffer as a handle, and arguments as a `T.StringMap`.

What is deliberately absent is as important as what is present:

- **no physical-address arithmetic** — a region reports its base, it never asks
  the bootloader to compute one;
- **no page tables, no HHDM offset** — address translation is the kernel's
  business and it happens after the handoff;
- **no format knowledge** — nothing in the manifest says how an image is
  compressed or what a disk partition table looks like;
- **no handler table** — services do not write function pointers into slots by
  index; channels and `ServiceEndpoint` replace that pattern entirely;
- **no hardware catalogue** — buses and devices belong to `hal.capnp` and
  `device.capnp`, not to the boot path.

The result is a boot contract that a person can satisfy in an afternoon without
learning the machine, and that a bootloader written in 2046 satisfies unmodified.

---

## 2 · Kernel: one hardcoded capability, then none

Before entering userspace, the kernel places `KernelService` at **capability
handle 1**. This is the only hardcoded capability in the entire system, and it
exists because a process must have something to call before it can be granted
anything.

`kernel.capnp` is deliberately short — 248 lines. It defines what a kernel
must offer, not how it works:

| Concern | Contract |
|---|---|
| Execution | `spawn`, `exit`, `stage`, `readEntryContext` |
| Observation | `getInfo`, `list`, `subscribe`, `TaskSubscription.pull` |
| Memory | `mapRegion`, `unmapRegion`, `protectRegion`, `shareRegion`, `listRegions` |
| Synchronisation | `wait`, `notify` over an explicit `Waitable` |
| Isolation | `setQuarantine` with a typed `IsolatedScope` |
| Service lookup | `resolveService` |

Absent: fork flags, scheduler introspection, live kernel swapping, a POSIX
credential block. Those are things a kernel does, not things the contract
promises about one.

A second kernel — monolithic, exokernel, unikernel, actor runtime — implements
the same 248 lines, and no application can tell which one it is talking to.
That is the Swap Test at its sharpest boundary.

---

## 3 · Bootstrap: init, in dependency order

`init.capnp` brings up the service plane. `InitService.start` takes a
`ServiceSpec` and returns the task it created; the rest is lifecycle —
`stop`, `restart`, `respawn`, `supervise`, phase advance, shutdown.

The manifest schema (`manifest.capnp`) is what a service declares about itself:
identity, the interfaces it serves, the capabilities it requires, its
dependencies. Init resolves the order. The protocol sees lifecycle and
authority; the resolution algorithm is init's business.

Every mutation here is gated. Reading what is running is open; starting,
stopping or reconfiguring a service takes a capability acquired once.

---

## 4 · The service plane

Two schemas hold the plane together, and they do different jobs.

### Discovery describes *what is there*

`Discovery.lookup`, `get`, `resolve`, `subscribe`, `getRuntimeHealth`,
`listQuarantined` — all ungated, because discovery that deadlocks on a
capability is discovery that never runs. Registration is not:

```
interface Discovery {
    lookup  @0 (filter :DiscoveryFilter) -> (services :List(ServiceDescriptor), total :UInt64);
    get     @1 (serviceId :T.ServiceId)  -> (descriptor :ServiceDescriptor);
    resolve @2 (name :Text)              -> (descriptor :ServiceDescriptor, present :Bool);
    subscribe @3 (filter :DiscoveryFilter) -> (subscription :DiscoverySubscription);
    getRuntimeHealth @4 (serviceId :T.ServiceId) -> (health :ServiceHealth);
    ...
    registry @12 (authority :Capability) -> (service :DiscoveryRegistry);   # gated once
}
```

A `ServiceDescriptor` carries an open category token, a version, an open
transport token with an address in that transport's own vocabulary, metadata as
a `T.StringMap`, and the capability ids the service requires. `ServiceHealth`
carries `state`, `reason`, `sinceValid` and probe results, so a degraded
service is visible as degraded rather than silently trusted.

### Capability defines *what you may do*

```
interface CapabilityService {
    issue       @0 (request :IssueRequest) -> (issued :Capability);
    verify      @1 (request :VerifyRequest) -> (result :T.BoolResult);
    attenuate   @2 (parent :Capability, drops :List(Operation), tighter :Constraints) -> (result :T.BoolResult);
    transfer    @3 (cap :Capability, recipient :Text) -> (result :T.BoolResult);
    revoke      @4 (cap :Capability) -> (result :T.BoolResult);
    revokeControlled @8 (cap :Capability, cascade :RevocationCascade) -> (result :T.BoolResult);
    ...
}
```

Delegation is attenuation plus transfer: drop operations, tighten constraints,
hand over the narrower reference. `DelegationChain` records parentage so that
revoking a root takes its derivatives with it. No other schema defines a
delegation method, a role, an ACL, or a per-method token.

---

## 5 · The session pattern

Long-lived interactive components share one handshake. A session is acquired
through an ungated `handshake` that takes a `compositor.SessionRequest` and
returns a `SessionResponse` carrying the granted capabilities and limits.

This pattern is written down once (`session.capnp`, `compositor.capnp`) and
reused by every session-shaped interface: `CompositorSession`, `ShellSession`,
`WindowManagerSession`, `ImeSession`, `ScreenlockSession`. A new display
protocol, a new input method, a new shell — each implements the same handshake
and becomes interchangeable without a contract revision.

Behind the handshake, work is expressed as a reference plus a commit:

- a surface's pixels are a `T.BufferId`, never a copy of a framebuffer;
- a fence is a typed handle, not a sleep;
- damage is geometry, not a pixel diff;
- every live stream is a subscription reference with a bounded `pull`.

---

## 6 · The three shapes of every call

Three patterns recur across all 89 files. Once you have read them in one
schema, you have read them in all of them.

### Ungated discovery, gated acquisition

Nothing that merely *describes* the system requires authority. Everything that
*consumes* it is reached through an accessor that takes a `Capability` and
returns a service. 35 accessors in the tree have this shape.

### Bounded pull, never an offset into a live stream

A subscription is a reference with `pull(maxEvents)` and `cancel()`. There are
no raw subscription ids and no arithmetic over a stream that is still moving.
The consumer sets the pace; the producer cannot outrun it.

### A result union that can fail

Anything that can fail returns a union carrying `T.Error`:

```
struct Error {
    code      @0 :ErrorCode;
    message   @1 :Text;
    context   @2 :Text;
    retryable @3 :Bool;
    metadata  @4 :StringMap;
}
```

A missing file, a failed fetch, a locked SIM and an unavailable capability are
all routable, none is silent. The doctrine's honesty rule — `REAL`, `DEGRADED`
or `Unavailable`, never a fabricated value — is only implementable because the
error model is in the type layer rather than in each backend's imagination.

---

## 7 · The domain map

The remaining 84 schemas are the domains. They are catalogued in
[`SCHEMAS.md`](SCHEMAS.md); the map is:

| Domain | Files | What it covers |
|---|---|---|
| Foundation | 3 | Types, authority, ABI negotiation |
| Kernel path | 16 | Boot, kernel, HAL, init, services, processes, sessions, scheduling, signals, discovery, queues, logs, diagnostics, modules |
| Devices & media | 19 | Device tree, display, framebuffer, input, audio, camera, capture, sensors, USB, Bluetooth, NFC, power, location, fonts, print, console, screenlock, GPU |
| Network & storage | 18 | Network, DNS, sockets, endpoints, web, tunnels, files, mounts, storage, backup, archive, databases, package, update, time, timezone, buffer, clock |
| UI & apps | 16 | Compositor, window manager, shell, CLI, input methods, accessibility, themes, notifications, app index, intents, manifests, extensions, settings, clipboard, content |
| Security & intelligence | 17 | Capability, access, auth, crypto, keys, secrets, signatures, biometrics, sandboxing, AI, speech, translation, search, contacts, calendar, vCards |

---

## 8 · What an implementation must supply

The contract does not ship a runtime. A conforming system supplies:

1. **A bootloader** that writes 24 bytes and a manifest.
2. **A kernel** that reads the manifest and places `KernelService` at handle 1.
3. **An init** that reads service manifests and starts them in order.
4. **A service registry** answering discovery.
5. **A capability authority** implementing issue/attenuate/transfer/revoke.
6. **Any number of domain services**, each answering its schema's interfaces.

Items 1–5 are the same for every system built on this contract. Item 6 is where
implementations differ, compete, and are replaced.

[`implementer.md`](implementer.md) is the build guide for all six.

---

*Next: [`SCHEMAS.md`](SCHEMAS.md) for the catalog; [`implementer.md`](implementer.md) to start building.*

# Audit — endpoint.capnp (919 lines)

## Verdict
**REWRITE (guided redesign).** This file is the epicenter of two of the batch's worst problems. First, `EndpointAddress` (:79-141) is a 14-variant catalog of every transport known to 2026 — each with its own structured fields — which is the same "today's list frozen into an eternal contract" error `ai.capnp:16-21` was written to eliminate. Second, it puts POSIX identity in required positions: `UnixEndpoint` carries octal `permissions`, `uid`, `gid` (:348-352), Linux-only abstract sockets, hypervisor VSOCK constants, and an `IpcMechanism` enum naming dbus/grpc/binder/mach/fidl (:232-256). A 2046 implementer gets exactly one outlet — `custom @13 :CustomEndpoint{scheme, data}` — which carries none of the security/pooling/health structure the named variants carry, so every consumer's transport-aware logic silently degrades for anything new.

## Wire-breakers
None (compiles clean). Name collisions: `EndpointId` (:75 vs `types.capnp:1086` — the local one is dead, the promoted one canonical), `HealthStatus` (:171), `TlsVersion` (:670 vs `types.capnp:1564` — endpoint's lacks `ssl30`, so the two enums are incompatible readings of the same concept), `ResolveResult` (:763 vs `dns.capnp:158`), `ServiceCategory` (:896 vs `discovery.capnp:44`), `ConnectionPoolConfig` (:181 vs `database.capnp:525` — different fields), `ProxyConfig`/`ProxyType` (:732/:751), `AddressFamily` (:788 vs `network.capnp:866`), `TransportPreference` (:854 vs `network.capnp:909` `TransportProtocol` vs `socket.capnp:265` `SocketKind`).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R5 | `endpoint.capnp:348-352` | `UnixEndpoint.permissions :UInt32` (octal), `uid @4 :UInt32`, `gid @5 :UInt32` | DESIGN_PRINCIPLES.md:177 names this exact shape as POSIX: "capability-based systems don't have owner/group/other". A capability backend must fabricate uid/gid; a browser runtime has neither. This is `files.capnp`'s `FilePermissions` defect re-imported through the transport layer |
| R5 | `endpoint.capnp:560-569` | `AbstractUnixEndpoint` — the file's own comment (:554-558) says "Linux-specific: abstract namespace sockets exist in the kernel namespace but not on the filesystem" | The schema documents a required-position construct that exists on one OS. A consumer cannot tell portability from the type |
| R5 | `endpoint.capnp:374-390` | `VsockEndpoint` + `const vmaddrCidAny = 4294967295; const vmaddrCidHost = 2` | Hypervisor-specific transport with vendor constants frozen as struct consts; irrelevant to 99% of deployments, eternal in the contract |
| R5 | `endpoint.capnp:525`, `:595` | `NamedpipeEndpoint` ("`\\.\pipe\my-pipe` on Windows") and `SharedmemEndpoint` ("POSIX shm_open name or Windows name") | Platform nouns in the required address vocabulary |
| R1 | `endpoint.capnp:232-256` | `IpcMechanism` = capnp/dbus/grpc/binder/alpc/mach/fidl | Seven vendor transport names; the task brief calls this out by name. A 2046 IPC mechanism has only `custom`. Worse, `IpcEndpoint.objectPath @3`/`busAddress @4` (:220-223) are D-Bus-shaped fields every non-D-Bus mechanism must leave empty and every consumer must guess the meaning of |
| R1 | `endpoint.capnp:79-141` | The whole union: 14 transport variants each with structured options | The 2046-test failure: a new transport arrives, gets `custom :Data`, and loses connection pooling, health, load balancing, pins — all of which consumers rely on for the named transports. The union also cannot be validated by a consumer: is an `inproc` endpoint "reachable"? `checkReachable @3` (:45) is undefined for in-process endpoints |
| R1/R5 | `endpoint.capnp:487-520` | `MmapEndpoint` with `MmapProtection` (readExecute/readWriteExecute) and `MmapSharing` (MAP_PRIVATE/MAP_SHARED/copyOnWrite) | `mmap` is an implementation mechanism, not an address. A remote backend has no mmap — the variant is unimplementable off-box, and modeling it as an address invites consumers to treat remote endpoints as mappable memory |
| R4 | `endpoint.capnp:134` | `spiffeId @17 :Text` | A 2020 CNCF identity system named in a required-optional field; identity should be the capability system's job (`capability.capnp`), which the file already half-acknowledges with `capability :T.CapabilityHandle` at :226 |
| R7 | `endpoint.capnp:39` | `parse @1 (text) -> (address :EndpointAddress)` — no error path | A malformed string must return *something*; the schema is silent on sentinel values. `ResolveResult` (:763) has an error union, so the vocabulary exists — `parse` just doesn't use it. Fork risk: backends return empty custom vs. a default variant |
| R7 | `endpoint.capnp:58-61`, `:864-875` | `migrateConnection(from, to) -> ConnectionMigration` has no handle to migrate — it names two addresses and returns a report about migrating nothing | No stream/session reference in the request, so "migration" is unanchored: a consumer cannot chain it to an actual connection. Also `ConnectionMigration.success @2` + the result struct duplicate what a `T.VoidResult` already says |

Validator counts: E7 ×11, E8 ×11, E6 ×1 (`ResolveResult` union lacks unknown/custom).

## Duplicates & overlaps
- `TlsConfig`/`TlsVersion`/`VerifyMode`/`RevocationCheck` (:629-688) vs `socket.capnp` `TlsSession` and nothing at all in `web.capnp` — the batch's TLS triplication.
- `HealthStatus` (:171) vs `tunnel.capnp:291` (identical) vs `filesystem.capnp:204` (different).
- `ConnectionPoolConfig` (:181) vs `database.capnp:525` — different field sets (maxSize/healthCheck vs min/maxConnections).
- `ProxyConfig`/`ProxyType` (:732/:751) vs `socket.capnp:162/:177` and `web.capnp:272/:289` — three families.
- `ServiceCategory` (:896-919) claims "(from discovery.capnp)" — a copy of `discovery.capnp:44` that will drift.
- `SctpSettings` (:841) vs `socket.capnp` `SctpOptions` (:468).
- Local `EndpointId` (:75) vs canonical `T.EndpointId` (`types.capnp:1086`, which says "replace local definition" — never done).

## Gaps & holes
- **This file is where the transport-profile gap must be closed** (see `BATCH-SUMMARY.md`): it already catalogs transports, resolves them, health-checks them, pins their certificates, and pools their connections — everything a profile needs except the profile's own normative statement. What every consumer must be told and cannot learn: the security level of the channel carrying the interface reference, the framing/message-size convention, flow-control/backpressure behavior, and connection lifecycle ownership.
- `registerScheme @5` (:51) accepts an `EndpointHandler` interface but nothing defines handler lifetime, revocation, or trust — an arbitrary callback becomes part of the address vocabulary with no authority model.

## Zero-cost / eco
- No bulk payload in this file (addresses and configs are small) — no R2 findings. The cost here is not copies; it is the structural cost that every transport-aware consumer must special-case 14 variants and can say nothing true about the 15th.

## UX & implementer guidance
- `EndpointHealth.status :HealthStatus` (:158) and `LoadBalancingHint.healthy :Bool` (:151) — health as both enum and bool in one file; two representations of the same question.
- `TcpEndpoint.noDelay @4 = true` — socket tuning (Nagle) in an address struct; address = *where*, options = *how*. The mixing is why consumers must read all 12 fields to know what a connection will do.
- `TransportPreference` (:854) says "preferred" but nothing states who decides when preference is unavailable.

## Recommended actions
1. **Collapse `EndpointAddress` to an open vocabulary**: `scheme :Text` + a *small* math-closed address union (`network {host :T.IpAddress, port :T.Port}`, `named :Text`, `opaque :Data`) + shared `security`, `limits`, `pool` fields. Keep a comment mapping today's spellings (`"tcp"`, `"unix"`, `"quic"`) onto the scheme tokens as conventions, not enum values. Gain: a 2046 transport is a string with the same security/pooling/health machinery; the uid/gid/abstract/VSOCK/mmap defects disappear with the variants that required them. Cost: consumers switch on a string instead of a union — they gain unknown-tolerance (the `ai.capnp` trade), and the named-transport special-casing they lose was exactly what made new transports second-class.
2. **Delete the POSIX identity fields and platform variants** (`uid`/`gid`/`permissions` :351-352/:348, `AbstractUnixEndpoint`, VSOCK consts, mmap/namedpipe/sharedmem variants) — or reduce each to `named`/`opaque` with a documented scheme token. Gain: capability, browser, and distributed backends can implement the contract without fabricating uid/gid. Cost: backend-specific details move into backend metadata — the only place they were ever meaningful.
3. **Promote one `TlsConfig` to `types.capnp`** and have socket/endpoint/web reference it (batch action 3 in the summary). Gain: transport security defined once, everywhere including web. Cost: one promotion, three reference edits.
4. **Give `parse @1` an error path** (return `ResolveResult`-style union, the type already exists at :763). Gain: malformed input becomes an honest error instead of a sentinel. Cost: one method signature.
5. **Replace the local `EndpointId` with `T.EndpointId`** (:75) — the promotion was already decided in `types.capnp:1086`. Gain: completes a documented-but-unperformed cleanup. Cost: zero.

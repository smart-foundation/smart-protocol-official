# Implementing Smart Protocol

A smart-protocol implementation is a program that serves the contract's Cap'n Proto interfaces. The contract is the design; the implementation is disposable. Any two implementations of the same interface interoperate without coordination.

## What an implementation is

- It speaks Cap'n Proto RPC over the contract's transports.
- It serves one or more domain interfaces from `schema/` (e.g. `Files`, `Discovery`, `AI`).
- It answers discovery by publishing a `ServiceDescriptor` (`discovery.capnp`).
- It publishes capabilities (`capability.capnp`) describing what it grants.
- It degrades honestly: unsupported operations return `Unavailable` with a reason instead of a fabricated value.

## Minimum viable implementation

Serve one domain, answer discovery, publish capabilities:

1. Implement the domain's primary interface (e.g. `Files` in `schema/files.capnp`).
2. Register a `ServiceDescriptor` with `DiscoveryRegistry.register` (gated by a `Capability`), or have the host inject the service.
3. Publish a `Capability` whose `target` names the resource and whose `operations` list what is granted.
4. Return `T.VoidResult`/domain results using `T.Error` on failure.

## The 5-step process

### 1. Read the schema

Start with `schema/types.capnp` (`T.DataHandle`, `T.UnknownEvent`, `T.ExecutionState`, `T.Error`), then `schema/capability.capnp`, then `schema/discovery.capnp`, then the domain schema you are implementing. Note method ordinals, parameter types, result unions, and event unions.

### 2. Implement the Server trait

Each language's Cap'n Proto tooling generates a server trait/interface from the schema. Implement every method. Methods that can fail return a result union containing `T.Error`; methods that always succeed return `Void`. Hold no authority state beyond the reference the caller holds.

### 3. Publish a discovery descriptor

Build a `ServiceDescriptor` (`discovery.capnp`): `id`, `name`, open `category` token, `version`, `state`, `endpoints` (transport token + address), `metadata`, `requiredCapabilityIds`. Register it through `DiscoveryRegistry` (obtained via `Discovery.registry(authority)`). Keep `expireAt` set for transient services.

### 4. Publish capabilities

Issue a `Capability` (`capability.capnp`): opaque `id` (backend-decided bytes), textual `target`, `operations`, optional `constraints`, `audit`, optional `expiry`. Attenuate and revoke through `capability.capnp` only (`attenuate`, `transfer`, `revoke`, `revokeControlled`, `evaluateCondition`). Do not invent a second authority grammar.

### 5. Test against the contract

- Compile every schema you depend on: `capnp compile -I schema -o <lang> schema/<file>.capnp`.
- Run `python3 scripts/validate.py` (must exit 0).
- Run `bash scripts/check.sh` on changed schemas.
- Exercise each method against a reference or mock peer speaking the same schema.
- Verify honest degradation: unsupported operations return `Unavailable`/error with a measured reason, never a fabricated value.

## Language-specific notes

The contract is language-neutral; only the generated glue differs. The repository pins Cap'n Proto 0.27.x on the Rust side (`capnp 0.27.2`, `capnpc 0.27.0`) and the system `capnp` binary is 1.4.0. Match your toolchain to the same wire format.

### Rust

Use `capnp` + `capnpc` (0.27.x). `build.rs` invokes `capnpc` to generate modules from schemas. Implement the generated `Server` trait for each interface. Serve over `capnp_rpc::RpcSystem` on a transport (Unix socket, TCP, or in-process). Use `capnp::message::Builder` for requests and `capnp_rpc` capabilities for service references.

### Go

Use `capnp-go` (`zombiezen.com/go/capnproto2` or the maintained fork) and its `capnpc-go` plugin. Generate bindings with `capnp compile -o go:...`. Implement the generated Go interfaces and serve via `capnp.NewServer` / `rpc` over a `net.Conn` or in-process transport.

### C / C++

Use `capnpc-c++` (shipped with Cap'n Proto). Generate headers with `capnp compile -o c++:...`. Implement servant classes deriving from the generated `Server` interfaces and dispatch via `capnp::RpcSystem` (C++ RPC) or a custom transport. Manage memory and capability lifetimes explicitly.

### Python

Use `pycapnp`. Generate/load schemas with `capnp.load('schema/<file>.capnp')`. Implement server classes subclassing the generated interfaces and serve over `capnp.TwoPartyServer` or an in-process transport. Suitable for prototyping and tooling; production services usually use a compiled language.

## The wire

Cap'n Proto RPC over any transport. Common transports: in-process (direct call), shared memory (zero-copy frames), Unix socket, TCP. The contract does not name a transport: `ServiceEndpoint.transport` is an open token (e.g. `capnp`, `rest`, `grpc`, or a future one) and `address` is in that transport's own vocabulary. An agent calling over the network holds the same references and passes the same handles as a human at the CLI.

Capability transfer semantics are transport-dependent and must be documented per transport; the contract itself is transport-agnostic.

## The honesty model

Every backend publishes what it can actually do (`caps()` in the smart-lib-ng convention) and reports `REAL`, `DEGRADED`, or `Unavailable` per operation:

- `REAL`: the operation is implemented and works as specified.
- `DEGRADED`: it works with a named, measured limitation (state the degraded capability and reason).
- `Unavailable`: it is not implemented on this platform/backend; return an error (`T.Error`) with a reason, never a fabricated success value.

A fabricated value is the one unforgivable defect. Runtime health in `discovery.capnp` (`ServiceHealth`) carries `state`, `reason`, `sinceValid`, fault counts, and probe results so consumers can see degradation rather than trust it.

## The independence proof

Delete your implementation and write another. The CLI and other consumers must work identically, because they speak only the contract: same method ordinals, same types, same capability references, same `T.DataHandle` payloads. If a consumer breaks when the backend changes, the protocol leaked implementation and the leak is a bug. This is the Swap Test applied to implementations.

## Cross-platform

Portable (the contract): schema IDs, ordinals, types, enums' neutral sentinels, capability references, `T.DataHandle`, event unions with `unknown`, ABI negotiation via `abi.capnp`.

Platform-specific (the backend): storage engine, kernel, scheduler, display server, audio server, transport choice, permission mapping from host credentials (uid/caps/entitlements) into capability handles. These live behind the trait boundary and must not appear in required positions in schemas (E9).

## References

- `README.md` (doctrine and six rules)
- `DESIGN_PRINCIPLES.md` (Agnostic/Timeless Test, Opacity Principle, Swap Test, schema template)
- `docs/SCHEMAS.md` (catalog of all 89 schemas)
- `docs/TIMELESSNESS.md` (timelessness rationale)
- `scripts/validate.py` (the E1-E14 gate)

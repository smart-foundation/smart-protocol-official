# Audit — socket.capnp (487 lines)

## Verdict
**FIX (targeted).** The core service is honest and largely correct: `send`/`receive` already use `T.DataHandle`, errors are `T.Error`, subscriptions have cancel, deadlines exist. The defects are at the edges: POSIX socket nouns in flags and addresses, a congestion-control algorithm enum that TIMELESSNESS explicitly rejects, a receive path with no "would block" signal that forces polling, and a pcap sink that assumes a filesystem.

## Wire-breakers
None (compiles clean). Name collisions: `ProxyType` (`socket.capnp:177` vs `web.capnp:289` vs `endpoint.capnp:751` — three different value sets), `ProxyRoute`/`ProxyConfig` (:162 vs `endpoint.capnp:732` vs `web.capnp:272`), `ConnectionState` (:274 vs `VpnState` in network — conceptually duplicated lifecycle), `CompressionAlgorithm` (:201 — fourth copy in the batch).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R5 | `socket.capnp:75-78`, `:51` | `UnixAddress` with `abstract @0 :Data` | The abstract namespace exists on exactly one OS. A consumer cannot know from the type whether "abstract" is portable or Linux-only; a portability bug class is baked into the address union |
| R5 | `socket.capnp:238-243` | `SocketFlags { nonBlock, cloexec, shared, exclusive }` | `cloexec` is a POSIX fd flag (`O_CLOEXEC` is exec semantics, not socket semantics); `shared`/`exclusive` are POSIX file-lock flags. The file's own comment (:11) claims "generic, not POSIX" — three of the four are POSIX-named |
| R1 | `socket.capnp:420-427` | `CongestionAlgorithm` = cubic/bbr/reno/vegas/bic | TIMELESSNESS.md:84 rejects algorithm hints ("Scheduler algorithm hints — Kernel internal"); transport congestion control is the same class. A 2046 stack's algorithm has no value, and the enum invites consumers to configure stack internals |
| R1 | `socket.capnp:201-208` | `CompressionAlgorithm` = gzip/zstd/lz4/snappy | Fourth copy in the batch (`files.capnp:626`, `backup.capnp:353`, `archive.capnp:288`), and the four disagree on value sets (`none` present in some, `snappy` only here) — a consumer translating a socket option into a file option must map by hand. A 2046 codec has no value anywhere |
| R1 | `socket.capnp:177-186` | `ProxyType` = socks4/socks5/socks5h/httpConnect/httpsConnect/transparent | Vendor/transport names, three vocabularies across the batch (see above) |
| R1 | `socket.capnp:150-158` | `TrafficClass` = bestEffort/controlledLoad/guaranteed/networkControl | IETF DiffServ class names frozen; QoS class assignment is backend/topology-specific |
| R5 | `socket.capnp:350`, `:459` | `startPcapCapture(filePath :Text)` / `PcapSession.filePath` | Capture writes to a filesystem path — a browser runtime or filesystem-less backend cannot honor the type at all. Should be an `ArchiveDestination`-style union (path/buffer/handle) or a `T.DataHandle` sink |
| R7 | `socket.capnp:306-307` | `receive @7 (handle, maxLength :UInt32) -> (data :T.DataHandle)` — no "would block", no empty-vs-closed distinction, while `pendingConnect @10` exists for the connect case | A non-blocking consumer must poll `getInfo`/`receive` in a loop, or block on an RPC call it cannot time out. The event subscription (`SocketEventSubscription`) covers state changes but not readability. Fork risk: each backend picks a different empty-data convention |
| R4 | `socket.capnp:408` | `TlsSession.peerCertificate @3 :Data` | A certificate chain inline in a session descriptor; should be `T.DataHandle` (small in practice — flagged for consistency, not cost) |

Validator counts: E7 ×14, E8 ×5, E6 ×0.

## Duplicates & overlaps
- `CompressionAlgorithm` — four copies (socket/files/backup/archive + a fifth in `capture.capnp`).
- `ProxyType`/`ProxyConfig`/`ProxyRoute` — three families across socket/web/endpoint with different fields and different values.
- TLS: `TlsSession` (:400) here, `TlsConfig`+`TlsVersion` in `endpoint.capnp:629-675`, and **no TLS expressibility at all** in `web.capnp` — three homes for transport security in the batch.
- `SocketKind` (:265) vs `network.capnp:909` `TransportProtocol` vs `endpoint.capnp:854` `TransportPreference` — three transport vocabularies.
- `SctpOptions` (:468) vs `endpoint.capnp:841` `SctpSettings` — same concept, two structs.

## Gaps & holes
- **No transport profile**: socket.capnp is the closest thing to one, but it never states message-size/framing limits, trust configuration at connect (`wrapTls` takes only `serverName`), or who owns idle-connection lifetime. See `BATCH-SUMMARY.md`.
- `getSessionTicketStore @32` (:358) returns an unbounded ticket list keyed by `serverName :Text` — tickets are unbounded by server count.
- `setSctpOptions`/`getSctpOptions` (:364-365) exist but SCTP itself is only a `SocketKind` value — no way to negotiate SCTP support at capability discovery.

## Zero-cost / eco
- `send @5`/`sendTo @6`/`receive @7`/`receiveFrom @8` use `T.DataHandle` — correct, the model case.
- The polling shape described above (`receive` with no readiness signal) is the eco finding: it pushes consumers into busy-poll loops on the highest-frequency call in the schema.
- No unbounded `List` other than the ticket store.

## UX & implementer guidance
- `shutdown @16` + `shutdownEmergency @17` + `close @18` + `closeGracefully @21` — four teardown ordinals with overlapping intent; the file doesn't say which is canonical for a normal close. An implementer must guess whether `close` flushes.
- `multiplex @14 :Bool` (:106) — socket-level multiplexing is a transport-management feature; an implementation with capability-based channels has no meaning for it.
- `SocketFlags` mixes lifecycle flags (nonBlock) with POSIX fd inheritance (cloexec) and lock flags (shared/exclusive) in one struct — three unrelated concerns.

## Recommended actions
1. **Add a readiness/empty signal to `receive`**: either a `wouldBlock :Bool` result field or extend `SocketEvent` with a `readable` variant. Gain: the highest-frequency call stops forcing busy-poll; eco + a real correctness story for non-blocking consumers. Cost: one result field — additive, free pre-release.
2. **Open `CongestionAlgorithm`, `CompressionAlgorithm`, `ProxyType`, `TrafficClass` to `Text` tokens** (or single shared batch-wide enums for the closed ones). Gain: 2046 values expressible; the algorithm hint disappears per TIMELESSNESS:84. Cost: consumers stop configuring stack internals — which is the point.
3. **Make pcap capture sink-neutral**: accept `ArchiveDestination`-style path/buffer/handle instead of `filePath :Text`. Gain: capture works on filesystem-less backends. Cost: one union added to two methods.
4. **Fix `SocketFlags`**: drop `cloexec`/`shared`/`exclusive` (or rename to mechanism-free intent, e.g. `durable`/`soleUse`). Gain: stops naming POSIX in a "generic" struct. Cost: three fields repurposed pre-release.
5. **Unify the TLS surface** (batch action with endpoint/web): one `TlsConfig` in `types.capnp`, referenced by socket/endpoint/web. Gain: three homes become one; a consumer learning TLS once applies it everywhere. Cost: a types.capnp promotion plus three reference edits.

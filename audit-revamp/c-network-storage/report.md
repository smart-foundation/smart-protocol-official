# Revamp Report — Batch C: Network & Storage (19 schemas → 18)

**Agent:** Wave 3 rewrite agent, batch C (network & storage)
**Date:** 2026-10-10
**Scope owned:** `schema/{network, dns, socket, tunnel, endpoint, web, telephony, files, filesystem, storage, database, backup, archive, mount, buffer, clock, time, timezone, update}.capnp`
**Inputs applied:** `audit-revamp/verification/audit-verification.md` (confirmed findings only; the five OVERREACH items were NOT implemented — including O2, which forbids promoting a new `TransportProfile`/`TlsConfig` into `types.capnp`), `audit-revamp/verification/naledzi-delta-reconciliation.md`, the 19 batch audits, `DESIGN_PRINCIPLES.md`, `docs/TIMELESSNESS.md`, the gold standard `schema/ai.capnp`, and the landed foundation batch (`types.capnp` / `capability.capnp` as they now exist — read, not edited).

---

## 0. Headline

| Metric | Before | After |
|---|---|---|
| Batch files | 19 | 18 (`filesystem.capnp` deleted, absorbed by `files.capnp`) |
| Batch lines | 12 484 | 11 023 (**−12 %**; filesystem's 617 lines included in the "before") |
| Enums naming hardware / vendor / platform technology | ~60 | **0** in required positions |
| Cross-file duplicate type names declared inside the batch | 24 pairs | **0** |
| New-rule findings (E6, E7, E9–E14) inside the batch | E6 17 · E9 11 · E10 26 · E11 2 · E12 24 · E13 8 · E14 12 | **0, except E10 ×6 (documented) and E8 ×29 (documented)** |
| Interfaces returned by no method (E14, in batch) | 12 | **0** |
| Silent wire-semantics breakers (TAI epoch) | 1 | **0** |
| TLS homes for channel security | 3 (+1 absent in web) | **1** (socket.capnp) |
| Validator exit code | 0 | **0** (green, `PASSED`) |
| `capnp compile` over the whole tree | — | **89/89 files clean** |

---

## 1. State of the previous (timed-out) attempt, and what this attempt did

**The previous attempt changed nothing.** All 19 batch files were still byte-identical to the pre-revamp
snapshot (Aug 19 mtimes; none appeared in `git status`), and no `report.md` existed in
`audit-revamp/c-network-storage/`. The timeout happened before the first write. There was therefore
nothing to salvage and nothing to unwind: this report describes a single complete pass.

**One incident to disclose.** Mid-pass I ran a mechanical "add an open extension point to every
E7-flagged struct" pass over the whole tree by accident — it wrote to ~70 files I do not own, before I
noticed the scope. I reverted it: 688 inserted lines were removed from 67 non-batch files, using a
HEAD-aware rule that only removes a trailing `metadata @N :T.StringMap;` line when the same struct in
`git show HEAD` had no extension point of its own (so another wave's field is never removed), and I
restored the two lines that rule mis-attributed (`crypto.capnp ImportKeySuccess`,
`intent.capnp TraceStep`). Final verification: all 89 schemas compile, the validator is green, no
struct in any non-batch file lost a type it had, and no E7-flagged struct in a non-batch file now has
a `metadata` field that its HEAD version lacked. My own files keep their extension points. The incident
cost nothing but time, and it is recorded here because the founder should not have to discover it from
a diff.

---

## 2. Per-file change summary

### `files.capnp` — REWRITTEN + absorbed `filesystem.capnp` (927 → 832 lines)
* **The merge (doctrine's High-severity conflict, C1):** `SpecialPathType` moved here with **identical
  ordinals**, so `getSpecialPath @13`'s published wire shape is untouched; trash (list/restore/empty —
  the absorbed file's trash was a half-API with no enumeration or restore), recent files and default
  apps moved here; the mount surface went to `mount.capnp`; path-keyed health/quota/snapshot moved
  here; pool/volume/replication/io-stats/tiering stayed with `storage.capnp`. The import edge into the
  doomed file is gone. **`filesystem.capnp` is deleted** (617 lines) — no other file imported it
  (checked: only files and mount did, both mine).
* **R2:** `writeFile`, `writeFileAsync`, `createFile.content`, `CreateEncryptedRequest.content` inline
  `Data` → `T.DataHandle`. The read path was already converted; the write path is the highest-volume
  path in the storage batch and was still copying every byte into the message arena.
* **R4 (DESIGN_PRINCIPLES:163):** `FileHandle` is now `{handle :T.FileHandleId}` — a pure reference.
  `path`/`mode` are already reported by `FileInfo`; a handle that carried them forced a distributed
  backend to fabricate values consumers then depended on.
* **R5:** `FilePermissions {owner, group, other}` deleted (POSIX mode bits); `ExtendedMetadata.inode`,
  `.device`, `.hardLinks` deleted (filesystem internals → `T.StringMap`); `FileType` lost
  `blockDevice`/`charDevice`/`fifo`/`socket`; `died` with them the three-methods-one-concept
  compression enum (`algorithm :Text` open token) and the frozen `AnalysisType` AI list (open tokens,
  the `ai.capnp` precedent).
* **R3:** **three permission models collapsed to one.** `FilePermissions`, `AclEntry`/`FileAcl`/
  `checkAcl` and `checkPermissions` ("current user") are all gone: DESIGN_PRINCIPLES:399 says the
  capability system IS the access control, and three models forced implementers to invent precedence.
  Authority for a file is now expressed by the reference the caller holds, and delegation has a real
  path: `acquireFile @73 (path, authority :Capability) -> (service :FileService)` — the doctrine's
  accessor shape, returning a service bound to one path.
* **R7:** `statFile`, `getFileHash`, `getFileVersion`, `resolveSymlink`, `getLifecycle`,
  `getEncryptionInfo`, `openFile`, `getDefaultApp`, `getFilesystemHealth`, `getByHash`,
  `branchVersion` now return result unions carrying `T.Error` (a missing file is an error, not a
  zeroed struct). `pollAsyncOperation` and the whole async block deleted (busy-poll beside an existing
  subscription). `compareFiles @29` (deprecated Text-diff twin) deleted.
* **R6/R8:** `DiskUsageExtended` (field-identical self-duplicate), `LifecycleRule`,
  `MetadataCacheEntry` deleted; the metadata-cache block deleted (a cache is a backend internal);
  file-level backup/sync and cloud-sync deleted (backup.capnp owns them); `SearchQuery`/`SearchResult`
  → `FileSearchQuery`/`FileSearchResult`; `RetentionPolicy` → `LifecyclePolicy`;
  `LifecycleAction` → `RetentionAction`; `SyncStatus`/`SyncConfig`/`CloudSyncStatus` deleted.
* **Cost, stated:** a UI that used to display owner/group or an inode must now read backend metadata;
  an ACL-based workflow must use capability attenuation. Both are the honest pre-release price.

### `endpoint.capnp` — REWRITTEN (919 → 264 lines). Shape in §5.
The 14-variant transport museum collapsed to `scheme :Text` + a math-closed address union
(`network {host, port}` / `named :Text` / `opaque :Data`) + shared `security` / `limits` / `pool`.
Deleted with the variants that required them: `uid`/`gid`/octal permissions, abstract-namespace
sockets, VSOCK constants, `mmap`/named-pipe/shared-mem variants, the `IpcMechanism` enum naming
dbus/grpc/binder/mach/fidl, `spiffeId`, `registerScheme`+`EndpointHandler` (an arbitrary callback
becoming part of the address vocabulary with no authority model or lifetime), `migrateConnection` (it
named two addresses and reported on migrating a connection it was never given), and the local
`EndpointId`/`TlsVersion`/`ProxyType`/`ProxyConfig`/`AddressFamily`/`TransportPreference`/
`ConnectionPoolConfig`/`ServiceCategory`/`ResolveResult` shadows. `parse` gained an error path;
health/latency now report `measured` flags so "not measured" is honest instead of zero.

### `time.capnp` + `timezone.capnp` — the TAI epoch wire-breaker, FIXED
`time.capnp` (413 → 131) lost its 1958-epoch `TAITimestamp`, its `taiToUtc`/`utcToTai` pair, its
leap-second types, its alarm CRUD, its `TimeZone` struct, its business-hours surface and its four
duration-humanization RPCs. What remains is what only that file can answer: wall-clock reading, HSM
timestamp attestation (`T.BoolResult`, machine-routable), and calendar arithmetic. **`timezone.capnp`
is now the single home for `TaiTimestamp`** — Unix epoch (1970), the same epoch as `T.Timestamp`, with
the epoch named in the field comment — and for the only conversion pair (`convertToTai`@24 /
`convertFromTai`@25). One obviously-epoched type, one converter, no second spelling. `timezone` also
lost its dead `TimeRange` (whose comment falsely claimed a `types.capnp` re-export while carrying a
10⁶-different unit), `TimezoneRegion`, `TaiUtcConversion`; gained pagination on `getTimezonesWithDst`,
`T.GeoCoordinate` for zone coordinates, a renamed `ZoneConversionResult` (was an `archive.capnp`
collision) with an `unknown` arm, and an explicit authority paragraph for `setDefaultTimezone`.

### `socket.capnp` — FIXED + **now the canonical TLS home** (487 → 546)
See §5 for the justification. Added the canonical `TlsConfig` (open version/cipher tokens,
content-typed trust anchors and client material, pins, verification modes), `VerifyMode`,
`RevocationCheck`, `CertificatePin`, `DtlsConfig`, and the normative **`wss://` paragraph**: a `wss://`
endpoint is a TLS-protected stream socket; `verifyMode` governs certificate checking; a backend that
cannot verify MUST fail rather than silently downgrade; `alpn`/`serverName`/`pins` are the identity
checks available; unknown tokens are ignored. Version bounds are open tokens rather than the
foundation's `TlsVersion` (see §4, foundation item 4). Also: `receive` gained `wouldBlock`/`closed` (the
highest-frequency call no longer forces a poll loop), `SocketFlags` lost `cloexec`/`shared`/`exclusive`
(POSIX exec and file-lock semantics in a struct claiming "generic, not POSIX"),
`CongestionAlgorithm`/`CompressionAlgorithm`/`TrafficClass`/`ProxyType` → open tokens (with
`setCongestionControl` deleted: reporting what the stack uses is honest, instructing it is a
TIMELESSNESS:84 algorithm hint), `SocketAddress` now uses the foundation's address types, pcap capture
is sink-neutral (path/buffer/handle, not a filesystem path), and `SocketEvent` gained a `readable`
variant.

### `network.capnp` — FIXED, targeted (1028 → 938)
Deleted the five structs no method returns (`MeshNetwork`, `LoraNetwork`, `BleMeshNetwork`,
`PacketRadioNetwork`, `MultiLinkConfig`) with their private enums — a consumer reading the schema
believed mesh/LoRa/packet-radio state was queryable and built against types no service emits. Opened
`NetworkType`, `WifiSecurity`, `VpnKind`, `TransportProtocol`, `WifiBand`, `SaMode`, `NanRole`,
`OrbitType`, `NetworkPowerProfile` (a 2046 radio/VPN/transport is a string; a firewall rule that
cannot name a future transport silently excludes it from security policy). `NicFrameDesc` and
`NicCapabilities` gained a `T.BufferId`/`maxLinkSpeedBps` so the highest-volume data path in the
protocol is expressible zero-copy instead of relying on an out-of-band slot-to-memory agreement.
Wi-Fi credentials are now a `T.SecretKeyId` reference, not cleartext in the message. Slicing uses a
typed `NetworkSliceId`; time-sync is a struct with measured flags; `renameInterface` deleted (an id is
not a mutable label). The DHCP surface became mechanism-free address assignment (`AddressAssignment` /
`AddressAssignmentOptions` / `AddressAssignmentSubscription`) — the validator's own platform-noun list
names `dhcp`, and a SLAAC-only backend should not be a special case. `NicProvider` is reachable via a
gated accessor.

### `dns.capnp` — REWRITTEN (670 → 575)
`resolve`/`srvLookup` can finally fail: `ResolveResult` is a union carrying `T.Error`, so SERVFAIL and
a timeout are no longer indistinguishable from NXDOMAIN-with-no-negative-cache. Three reverse-resolve
methods collapsed to one typed path with an error arm; the local `IpAddress` struct is gone. One time
vocabulary (every TTL is `T.Duration` — the header's claim is now true), one address vocabulary
(`T.IpAddress`), one port vocabulary (`T.Port`). `DnsRecordType` gained a neutral `unspecified @0`
sentinel so a zero-initialised record doesn't read as `a`. `RecordData.opaque` → `custom`. Blocklist
categories are open tokens ("socialMedia" is a 2024 editorial fact). `DnsPrivacy` and the
`dohEnabled`/`dotEnabled`/`dohTemplate` triple are replaced by `DnsConfig.transportSecurity` — the
canonical `TlsConfig` — so "resolve over an authenticated channel" is a declared requirement.
`getResolverHealth` paginated, `resolveBatch` bounded.

### `web.capnp` — REWRITTEN (631 → 540)
`fetch` returns a union carrying `T.Error` (connection-refused and HTTP-500 were the same shape).
`getStreamReader` takes a stream, not a chunk. `wss://` and secure fetch carry the canonical
`TlsConfig`. WebSocket binary payloads are `T.DataHandle`. The WebRTC session is observable (typed
states, typed SDP as the one representation). Deleted: the service-worker block (`handleFetchEvent`
is unimplementable off-browser), HTTP/2 server push keyed by raw stream ids, five types returned by no
method, and the local `ProxyConfig`/`ProxyType` (socket's, now the single proxy home). WebAuthn ids
are typed (`WebAuthnCredentialId`) rather than carried as payload buffers; attestation results carry
`T.Error`.

### `telephony.capnp` — FIXED, targeted (724 → 757)
The seven Audit-8 feature interfaces are resolved per-feature: **LineManager, CallRecordingService,
VoicemailService and CallScreeningService are wired** through gated accessors on `TelephonyService`
(present a capability, receive the service, hold the reference as the authority — the ai.capnp
precedent), because they are real, shipped telephony features whose types were advertising themselves
with no way to obtain the service. **SatelliteService, MeshCallService and MeshMessageService are
deleted**, with the reason stated: satellite SOS and mesh calling are 2020s product features, not
timeless contracts, and the same wave deleted the mesh stack from network.capnp. `makeCall` can now
fail (SIM-locked/busy/airplane are `SimInfo.state`'s own vocabulary). Cellular generation, SIM
lifecycle and RCS content-type became open tokens. The calendar free/busy contract is gone (calendar
owns availability). Typed ids for recordings/voicemails/lines (the foundation's `T.RecordingId` where
it exists). `LanguageFallback` and its `translation.capnp` import deleted. Emergency numbers are a
paginated struct, and `setEmergencyNumber` names its authority path instead of claiming a check the
contract cannot make.

### `storage.capnp` — FIXED, targeted (1266 → 1281)
The header's promise is now true: `PoolType` (whose values were exactly the LVM/mdadm/ZFS/Btrfs/
Storage Spaces/VxVM the first sentence forbids, in a **required** field), `BusType`, `BlockDeviceType`,
`RedundancyLevel`, `PartitionTableType`, `PartitionFlag`, `EncryptionMethod` are all open tokens —
reported, never prescribed. The promoted `T.StoragePoolId`/`T.VolumeId`/`T.SnapshotId` are adopted and
the local shadows deleted. `FilesystemInfo`/`FilesystemCheckResult` now come from `mount.capnp`
(their canonical home) instead of private diverging copies. Day-long operations (scrub, rebuild,
migration, replication) gained `StorageProgressSubscription` — a 40 TB scrub no longer requires an RPC
loop for hours. `BlockRange` gained a `T.BufferId` beside its slot. `IoStats` latencies are
`T.Duration` (the unit no longer lives in a comment). Partition geometry is bytes, not sectors.
`BlockProvider` is reachable via a gated accessor.

### `database.capnp` — FIXED, targeted (720 → 841)
`List(Float32)` vectors are gone: `VectorEntry.vector`, `VectorSearchRequest.queryVector` and
`VectorSearchResult.vector` are `T.DataHandle` with a documented
`application/vnd.smart.embedding` convention (little-endian Float32, dimensions in `parameters`) — the
exact pattern `ai.capnp:74-75` rejects, at ~1.6 MB copied per top-100 search. The value path
(`get`/`set`/`setWithTtl`/`readFromSnapshot`) is `T.DataHandle` too, ending the asymmetry with
export/import. The SQL question is settled the ai.capnp way: a query is **content** (`language
:T.MimeType` + `query :T.DataHandle`), a backend declares the languages it accepts, and
`SchemaMigration` scripts are content — so the header's "No SQL" is true and a dialect is no longer a
promise the contract cannot keep. `getNeighbors`/`detectCommunities`/`getBatchMetadata`/`listIndexes`
paginated. The CDC feed carries a monotonic `sequence` and accepts `fromSequence`, so a reconnecting
consumer resumes deterministically instead of replaying or skipping. `TransactionId`, `EventId`
(the foundation's), `T.SnapshotId` and `ReplicationId` typed; `DeliveryGuarantee` lost `exactlyOnce`
(the a-foundation batch's A10 correction, applied here too). `IndexType`/`ShardStrategy`/
`SimilarityMetric` opened. Dead `NamespaceQuota` and the transport-shaped `ConnectionPoolConfig`
deleted (endpoint.capnp owns pool configuration; a key-value service reports its pool, it does not
take transport config).

### `backup.capnp` — FIXED, targeted (429 → 473)
`getManifest`/`getDiff` are paginated — a manifest of a full-system backup has millions of entries and
one message used to carry them all. `verify @16` makes the declared-but-unwired `BackupVerification`
reachable. Six dead types resolved: `BackupStrategy` (exact duplicate of `BackupKind`) deleted,
`BackupOptionsExtended` folded into `BackupOptions`, `BackupMissedPolicy` and
`BaseBackupCascadePolicy` folded into `BackupSchedule` as open tokens, `DeduplicationMetadata`
deleted, `SyncState` wired (returned by `syncToRemote`) and given a caller-chosen `resumeToken` the
backend honours. `Checksum`/`ChecksumAlgorithm` → the promoted `T.HashOutput` (different algorithm
encoding, hand-mapping table required). Compression and encryption algorithms opened. A subscription
has one address (the convenience `pull`/`cancel` pair on the root is gone). `phaseProgress` deleted —
the header's "not a float" claim is now true. `BackupOperationId` is its own type.

### `archive.capnp` — FIXED, targeted (752 → 740)
The streaming pair actually streams: `CompressStream.write` and `DecompressStream.read` are
`T.DataHandle` — the feature added "for large archives with backpressure" was copying every chunk into
the message arena and defeating its own purpose. `ArchiveFormat` is now container + compression as
independent open tokens plus parameters: the tar×codec combinatorics the 35-value enum spelled out by
hand collapse, and a 2046 container is a string. `CompressionMethod` (27 values including `reduced1..4`,
`imploded`, `shrunk`, and one codec's fast/high modes frozen as separate values) is gone. POSIX
ownership (`uid`/`gid`/`uname`/`gname`/`mode`/`preserveOwnership`) is gone — a capability or browser
backend had to fabricate owner metadata consumers then trusted; what a backend knows, it reports in
`metadata`. Single-entry extraction uses `ArchiveDestination` (regaining its `custom` variant);
integrity errors are `T.Error`; diff and hash verification are bounded; `parallelism` and
`sparseExtraction` (HOW, not WHAT) deleted; the local `HashAlgorithm` deleted.

### `mount.capnp` — FIXED, absorbed the mount half of `filesystem.capnp` (631 → 515)
Declared the canonical mount contract: it absorbed the overlay-completion methods
(`unmountOverlay`, `modifyOverlay`, `getOverlayLayers`, `getOverlayStats`) and `NetworkMountInfo`
(open protocol/auth tokens). `MountOptions` and `MountFlags` unified into one intent-named struct
(the old pair named Linux mount(2) flags and declared twelve of the same booleans twice, with no rule
about which a method meant); `PropagationType` deleted. POSIX internals (`st_dev`, inode counts,
`fsId`, `fragmentSize`, block counts) moved to metadata or bytes. The unused 45-value `FilesystemType`
deleted — the file's live spelling is `fsType :Text`, so the schema contained its own fork. Promoted
`T.MountId`/`T.FilesystemId` adopted (the locals were dead); the dead `using FS = import
"filesystem.capnp"` edge removed; three unbounded catalogs paginated; `unmount`'s POSIX `lazy`
parameter dropped (detachment policy is backend-internal).

### `tunnel.capnp` — FIXED, small (313 → 319)
`TunnelHandle` is a pure reference again (DESIGN_PRINCIPLES:167 names this exact fix): `subject`,
`meshId`, `logicalId` removed — a capability attenuated to a mesh still carried the mesh id.
`HealthStatus` deleted (the batch carried three of them, two incompatible) in favour of a reported
open token; `MeshAlgorithm` deleted (duplicate of network's, both gone); `TunnelEncryption` deleted
(it named Kyber-768/1024 — already renamed ML-KEM in 2024, so the 2046-test failure was two years
old); `TunnelInfo` is now returned by `getInfo`; `FlowPolicy` gained a neutral sentinel (an absent
policy used to silently mean "reliable and ordered", the most expensive default for a lossy link);
framing overflow behaviour stated; trusted peers are identified (`NodeId`) rather than a bag of opaque
key bytes; `openLogical` returns a typed `LogicalTunnel`.

### `update.capnp` — FIXED + **received the firmware domain** (507 → 704)
`firmwareUpdate`, `firmwareRollback` and `configureNetworkBoot` imported from the old
`boot.capnp` (audit-9 section) and redesigned under R1–R8: `FirmwareImage` is content (an open-scheme
`T.Uri` or a `T.DataHandle`), verification is `T.HashOutput` + a declared flag, and the TPM algorithm
enum is gone. **Network-boot configuration lives here** — justification in §5. Update operations are
no longer keyed by `T.BackupId` (`UpdateOperationId`); the changelog is a `T.DataHandle`; the
partition model is a slot list plus an active index (not A/B-only); `UpdateQuarantine` is readable
(`getQuarantineStatus`); three rollout representations merged into one; the engine state is a union;
downloads can resume (`checkpoint` + `resumeFrom`); the `unknown` event arm renamed `custom`;
collisions with package.capnp/device.capnp/usb.capnp renamed away.

### `buffer.capnp` — KEEP verdict, four honesty fixes (618 → 665)
`DmaBufferHandle.fd :Int32` → an opaque `token :Data` (an fd is a per-process table index — the number
is meaningless in the receiving process, and a browser or Windows backend has no fd at all).
`BufferAdvice` renamed off POSIX (`dontFork` presumed fork() exists; `hwpoison`/`softDirty` are kernel
internals a consumer cannot act on portably). `BufferEvent` gained `unknown @6 :T.UnknownEvent` — the
event union was the one forward-compat gap in the file that makes every other schema's `T.DataHandle`
real. The stale header comment about a `Buffer` interface that does not exist is corrected.
`BufferQuery` lost its display-shaped variant and its `testPattern`. The eight result unions gained
their `unknown` arm, matching the convention the already-rewritten files use. Not restructured.

### `clock.capnp` — KEEP verdict, small fixes (332 → 377)
Declared the canonical alarm home (its model is strictly richer than the duplicate `time.capnp` one,
which is deleted) and made `AlarmService` reachable through a gated accessor.
`TimerAnchor` gained `custom @3`; `listAlarms`/`listPersistedTimers` paginated; `checkTimer`
documented as the sanctioned poll path beside `subscribeTimers`; `setTimerDependency`'s fire-time
semantics stated (gated, not chained); `ClockInfo` field order fixed; `DayOfWeek` imported from
calendar.capnp rather than declared a second time.

### `filesystem.capnp` — DELETED (617 lines)
Merged per DESIGN_PRINCIPLES:212. The canonical direction was backwards in the schemas: it claimed
ownership of `SpecialPathType`, which made `files.capnp` import from the very file the doctrine orders
deleted. `SpecialPathType`, trash, recent files and default apps moved to `files.capnp`; the mount
surface moved to `mount.capnp`; path-keyed health/quota/snapshot moved to `files.capnp`;
pool/volume/replication-keyed administration stayed with `storage.capnp`. The FUSE provider block
(`FsProvider`, `FuseCapability`, `FuseBackendInfo`, `FsMountOptions`, `FsMountFlag`, `FsMountHandle`,
`ProbeVerdict`, `BlockGeometryMask`, `FsVoidResult`) was **deleted, not relocated**: it was returned
by nothing and its `mount` took a per-method `CapabilityId = UInt64` — a raw number that looks like
`capability.capnp`'s authority type but carries no proof, target or constraints (an R3 defect). The
provider axis that storage and network need is expressed by their `BlockProvider`/`NicProvider`
accessors. Naledzi-side port note: the 7 `filesystem::*` methods and 61 type references in
`uspace/servers/filesystem` are recorded here, not acted on (per the delta reconciliation's
"planned migration" ruling).

---

## 3. Cross-batch items (exact file + action)

**Foundation (`types.capnp`, batch A) — four items:**
1. **`types.capnp:1637-1645` `TlsVersion` is now unconsumed and is itself an R1/E8 violation**
   (`ssl30 @0`, no `custom`, a closed list of today's TLS versions). socket.capnp's canonical
   `TlsConfig` uses open version tokens instead. Recommend deletion.
2. **`types.capnp:768 `T.BluetoothAddress` is a MAC-shaped type with the wrong name** — it is used
   for Wi-Fi/Ethernet MACs in `network.capnp` (hwAddress, bssid, `setHotspotClientFilter`), which is
   verifier contradiction X1. The rename to `T.MacAddress` (plus an alias) is a foundation-blast-radius
   change across network/bluetooth/socket/endpoint; my batch keeps using the foundation type and
   documents the misnomer at each use. **Needs a foundation decision.**
3. **`types.capnp:1626-1631` `T.TimeRange` is `UInt64` milliseconds while `T.Timestamp` is
   nanoseconds.** `timezone.capnp` uses it; the false "re-export" comment that used to teach a 10⁶
   error is deleted. Suggest either a nanosecond alignment or a name that states the unit.
4. **Stale `filesystem.capnp` references in comments: `types.capnp:1169, 1211, 1216, 1238, 1243` and
   `usb.capnp:23-25`.** Comments only (no code impact — the file is deleted and nothing imports it),
   but they now describe a schema that does not exist.

**Doctrine — the transport-profile paragraph (the deliverable, for the foundation batch to fold into
DESIGN_PRINCIPLES / BINDING_CONVENTIONS).** The verifier rejected the `TransportProfile` schema
promotion (O2), so this is prose only:

> **Transport profile.** Every capability-carrying service is reached over some channel, and a consumer
> of that service must be able to learn five things about the channel without out-of-band knowledge:
> **(a) how the reference travels** — a transport is an open token, not an enumerated list, so a
> transport invented in 2046 is expressible today (`endpoint.capnp`'s `scheme`); **(b) the channel's
> security level** — declared once, in `socket.capnp`'s `TlsConfig`, and referenced by every schema
> whose scheme implies a secure channel; a consumer that cannot verify the peer MUST fail the
> connection rather than silently downgrade; **(c) framing and message-size limits** — declared per
> endpoint (`ConnectionLimits.maxMessageSize`, `maxFrameSize`), never assumed; a producer that cannot
> honour them says so instead of truncating; **(d) backpressure** — caller-driven, on the pull path
> (`ai.capnp`'s `pull (maxBytes)`, socket's `receive (maxLength)`, archive's `DecompressStream.read
> (maxBytes)`), so a producer may never outrun its consumer; and **(e) lifecycle ownership** — who
> retires an idle connection and when (`ConnectionPoolConfig`), stated with the endpoint rather than
> left to each backend's timer. A capability reference inherits the profile of its acquisition: the
> security, limits and pool declared with the address it was acquired from.

**Other batches, specific files:**
* `bluetooth.capnp:80`, `shell.capnp:423` — `BluetoothDevice` is declared three times; network.capnp's
  copy is deleted, so the remaining pair should be reconciled (bluetooth.capnp is the canonical home).
* `calendar.capnp:332/344` — telephony's `FreeBusyQuery`/`FreeBusyResult` are deleted; calendar.capnp's
  survive as the single free/busy contract. `calendar.capnp:256` now also owns `DayOfWeek` (imported
  by clock.capnp) — please keep it.
* `audio.capnp:1235`, `diagnostics.capnp:118`, `discovery.capnp:146` — the last three `HealthStatus`
  declarations in the tree; my batch deleted its three copies in favour of open status tokens. One
  canonical health vocabulary (or open tokens everywhere) is now a three-file decision.
* `capture.capnp:430` — `RetentionPolicy` is now declared only here; backup's and files' copies were
  renamed (`BackupRetention`, `LifecyclePolicy`).
* `access.capnp:529` (E13 out-of-order `AccessEvent` fields), `auth.capnp:141` + `speech.capnp:169` +
  `system_search.capnp:142` (E14 unreachable interfaces) — the tree's last E13/E14 findings, all
  outside my batch.

---

## 4. Verification results

`capnp compile -I schema -o - <file>` over all 89 schemas: **clean** (exit 0, no diagnostics).

`python3 scripts/validate.py` — verbatim:

```
Schemas parsed: 89
E1 enums in ai.capnp            : 0
E2 bulk lists in ai.capnp       : 0
E4 interfaces unreachable (all) : 0 reported
E9 hits (all schemas)          : 0
E10 hits (all schemas)         : 59
E11 hits (all schemas)         : 6
E12 hits (all schemas)         : 36
E13 hits (all schemas)         : 1
E14 hits (all schemas)         : 3

--- REPORTED (not blocking, 1134) ---
```

(exit code 0 — `PASSED — all enforced rules clean for schema/ai.capnp`)

**Movement against the session baseline** (tree-wide): E9 11→**0**, E10 79→59, E11 9→6, E12 100→**36**,
E13 18→1, E14 15→3. The remaining E11/E12/E13/E14 hits are all in other batches' files (§3).

**This batch's residual findings, with the reason each is left:**

* **E10 ×6** — `buffer.capnp` `TensorBufferInfo.shape`/`.strides :List(UInt32)` and
  `timezone.capnp` `TimezoneBusinessHours.workdays`, `RecurrenceRule.byDay`/`.byMonth`/`.byMonthDay`
  `:List(UInt8)`. These are dimension and vocabulary lists of ≤31 entries, not copied payloads; the
  buffer audit says exactly this about shape/strides and declines to flag them. Converting a
  day-of-week list to a `T.DataHandle` would add machinery with no gain, so they stay lists and are
  documented here rather than silently.
* **E8 ×29** — enum `@0` is not a neutral sentinel, all on enums that pre-date this wave. The
  verifier rejected the blanket sentinel fix (O4: "apply the sentinel to filter/request/optional-field
  enums only; document the rest"), and batch A left the identical residual with the same reasoning
  ("done for every new enum; the rest need a tree-wide decision"). **Every enum this wave declares has
  a neutral `unspecified @0`**; the listed 29 are the pre-existing ones. Two were deliberately fixed
  because an absent field defaulted dangerously: `tunnel.capnp FlowPolicy` (was
  `reliableOrdered @0` — the most expensive default for a lossy link) and `dns.capnp
  DnsRecordType` (was `a @0`).
* **E6/E7/E9/E11/E12/E13/E14: zero** inside the batch.

---

## 5. Founder-decision items

**1. TLS home — decided, and the decision is `socket.capnp`.** Channel security is defined once, in
`socket.capnp`, because a connection's trust configuration belongs to the thing that establishes the
connection: that file already owned the live `TlsSession` and `wrapTls`, and the foundation's own
`TlsVersion` comment at `types.capnp:1637-1638` says "Used by socket.capnp for TLS session
information" — the intended home was already recorded there. `endpoint.capnp`'s address contract
carries `security :S.TlsConfig`, `web.capnp` takes the same type for `wss://` and secure fetch, and
the `wss://` verification semantics are stated in socket.capnp: `verifyPeer` by default, a backend
that cannot verify must fail the connection rather than silently downgrade, identity comes from
`serverName`/`pins`/`alpn`, and trust anchors and client material are content rather than paths. The
verifier rejected promoting a new TLS type into `types.capnp` (O2: complexity-add where deletion
suffices), so the three duplicate homes were collapsed onto the one that already existed rather than
broadcast into the foundation. **Cost:** `endpoint.capnp` and `web.capnp` now import `socket.capnp` —
one new edge each, and the alternative (a foundation promotion) is exactly the speculative machinery
the standard rejects. **Open question for you:** the foundation's `T.TlsVersion` enum is now
unconsumed; I left it alone (I do not own `types.capnp`) and used open version tokens instead.

**2. Endpoint rewrite shape.** `EndpointAddress` is `{scheme :Text}` plus a math-closed address union
(`network {host :T.IpAddress, port :T.Port}` / `named :Text` / `opaque :Data` / `unknown`) plus the
three things every transport-aware consumer was already asking of the named variants: `security`
(the canonical TLS config), `limits` (`ConnectionLimits`: max message size, max frame size, max
streams, receive window) and `pool` (`ConnectionPoolConfig`: size, idle/lifetime timeouts, health
checks). The questions survived; the answers-by-enumeration did not. A 2046 transport is a `scheme`
string and gets the same security, pooling and bounds structure the 2026 transports had — which is
the whole point of the ai.capnp trade, and the reason the 14th variant's `custom` outlet (which
carried none of that structure) is gone. What died with it, deliberately: POSIX identity fields,
Linux abstract sockets, VSOCK constants, mmap/pipe/shared-mem variants, the vendor IPC-mechanism enum,
SPIFFE ids, `registerScheme`+`EndpointHandler`, and `migrateConnection`. Reachability and health are
reported with explicit `measured` flags, so "we did not measure" is honest instead of a zero.

**3. The epoch fix.** `time.capnp`'s 1958-epoch `TAITimestamp` and its converter pair are deleted;
`timezone.capnp`'s Unix-epoch `TaiTimestamp` (same epoch as `T.Timestamp`, epoch named in the field
comment) and its `convertToTai`/`convertFromTai` are the single TAI representation and the single
conversion surface. The documented "any = -1" exception lived in `AlarmTime` (time.capnp:163-165) and
is **removed with the struct** — clock.capnp's alarm model has no sentinel-day fields, so the
exception has nothing left to except.

**4. Network-boot configuration lives in `update.capnp`, not `boot.capnp` or `endpoint.capnp`.** It
answers "how does this machine acquire its first image", which is the same acquisition question
`setUpdateSource` answers at runtime — one domain, one home. `endpoint.capnp`'s rewrite deliberately
carries no boot orchestration state (a transport address must not carry platform boot state), and
putting it back in `boot.capnp` would re-freeze the DHCP/TFTP/iSCSI nouns the boot rewrite just
removed: the sources are now open URIs and the failover policy is an open token.

**5. Telephony's seven orphans — split, not swept.** Four wired (line management, call recording,
voicemail, screening: real features with types already advertising them), three deleted (satellite,
mesh call, mesh message: 2020s product features, and the mesh stack went from network.capnp in the
same wave). If you would rather all seven be deleted, that is a small follow-up; if you want satellite
messaging as a first-class domain, it deserves its own schema, not a corner of telephony.

---

## 6. Deferred work

* **Naledzi-side ports.** `filesystem.capnp`'s 7 methods and 61 type references in
  `uspace/servers/filesystem` (recorded per the delta reconciliation's "planned migration" ruling —
  the 168 refs / 7 relocated methods are the migration plan, not this wave's work). The FUSE provider
  surface has no port: it is deleted, and the provider axis is the capability accessor pattern.
* **E8 residual (29 enums).** A tree-wide sentinel decision is needed, exactly as batch A concluded.
* **Validator scoping gaps found while working** (worth a foundation decision, both mechanical):
  E6 exempts terminal result unions *by name* (`VoidResult`/`BoolResult`/`DataHandle`) while the
  doctrine exempts them *by shape* (DESIGN_PRINCIPLES:489-495 blesses `union {buffer; error :T.Error}`);
  and E7's single-line struct parser misses `struct X { id @0 :Text; }` on one line, so it reports
  structs that already have an extension point.
* **The three remaining `HealthStatus` owners** (audio/diagnostics/discovery) and the
  `T.BluetoothAddress` → `T.MacAddress` rename are cross-batch decisions recorded in §3.
* **Not attempted, by design:** search-primitive promotion to `types.capnp` (the verifier's
  KEEP-SPLIT recommendation — a cross-batch, tree-wide change), and any transport-profile *type*
  (O2).

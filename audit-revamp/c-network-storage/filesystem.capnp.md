# Audit — filesystem.capnp (617 lines)

## Verdict
**MERGE-INTO-files.capnp.** The doctrine already decided this (DESIGN_PRINCIPLES.md:212: "**Merge into files.capnp.** Add mount/unmount and trash operations to the Files interface. Delete filesystem.capnp") — and the schema's current state argues against itself: `filesystem.capnp:10` claims canonical ownership of `SpecialPathType`, which makes `files.capnp:28` import from the very file the doctrine deletes. **Resolved direction: `files.capnp` is canonical** (per the doctrine); `SpecialPathType` moves there and the import edge reverses/disappears. Beyond that, the file duplicates ~10 types with `mount.capnp` with *different* content in the most important ones, and carries FUSE/9P/Linux-mount-flag vocabulary its own header claims to reject.

## Wire-breakers
Critical structural wire risk: deleting this file breaks `files.capnp:50` (`FS.SpecialPathType`) unless `SpecialPathType` is moved into `files.capnp` first — a merge-order dependency the wave plan must respect. Name collisions: `MountOptions` (:166 vs `mount.capnp:163` — **different fields**, see below), `MountEvent` (:397 struct vs `mount.capnp:306` union — same name, same concept, incompatible shapes), `MountOperation` (:404 vs `:345` — different values), `HealthStatus` (:204 vs `tunnel.capnp:291`/`endpoint.capnp:171`), `AutoMountRule` (:367 vs `mount.capnp:465`), `OverlayMountRequest`(:247)/`OverlayIndexMode`(:239) vs `:448`/`:440`, `NetworkFsAuth` (:307 vs `mount.capnp:496`), `FilesystemCheckResult` (also `storage.capnp:608`), `StorageTier` (:348 vs `storage.capnp:1016`), `FilesystemQuota` (:224 vs `database.capnp:435` `NamespaceQuota` vs `types.capnp:1776` `Quota` — three quota types).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R6 | `filesystem.capnp:10` | Claims "Canonical source for SpecialPathType — imported by files.capnp" — contradicting DESIGN_PRINCIPLES.md:212 | The canonical type would live inside the deleted schema. Two consumers reading the two headers reach opposite conclusions about which file is authoritative |
| R6 | `filesystem.capnp:166-170` vs `mount.capnp:163-194` | Two `MountOptions` with **different fields**: filesystem's is `{readOnly, fsType, options}`; mount's is 14 POSIX booleans + `propagation` + `fsSpecific` + `custom` | A consumer that sets `nosuid` through one service's options gets silently different semantics (none) through the other. Setting `fsType` on mount's options has no representation. The two structs disagree about what an "option" is — a fork with two published shapes |
| R6 | `filesystem.capnp:172-181` vs `mount.capnp:131-161` | `MountInfo` vs `MountPoint`: different fields (device/fsType/options vs source/fsUuid/fsLabel/ids/flags) | Two mount-info contracts; a mount UI written against one cannot renders mounts from the other without field-by-field remapping |
| R6 | `filesystem.capnp:397-402` vs `mount.capnp:306-317` | `MountEvent` as a flat struct vs as an event union | Same name, same concept, one can express `optionsChanged`/`statsChanged`/`error` events and the other cannot. An event consumer compiled against one cannot consume the other |
| R5 | `filesystem.capnp:273-284`, `:286-293` | `FuseCapability` (readdirPlus, fallocate, bmap, writebackCaching) and `FuseBackendInfo.protocol @1 :Text` ("FUSE", "9P", "virtiofs") | Linux FUSE ABI details frozen into enums; `bmap` is a legacy FUSE call. A userland-FS backend from another ecosystem describes itself with a vocabulary of another OS's kernel module API |
| R5 | `filesystem.capnp:594-600` | `FsMountFlag` = noAtime/noExec/noSuid/sync | Linux mount(2) flag names; the macro `custom @4` is a valueless enum variant |
| R5 | `filesystem.capnp:297-305` | `NetworkFsProtocol` = nfs/cifs/smb/webdav/nineP/fuseSshfs — with `nineP` and `fuseSshfs` coexisting as separate spellings of the same protocol | Vendor/product nouns; "fuseSshfs" is a *stacking* of two technologies. A 2046 network FS has only `other @6` |
| R5 | `filesystem.capnp:524-528` | Header comment: "inode ops go through the Files interface" | Inode is a filesystem internal (DESIGN_PRINCIPLES.md:230) named in the file's own narrative |
| R3 | `filesystem.capnp:537`, `:547` | `FsProvider.mount @2 (blockProvider :CapabilityId, ...)` with `using CapabilityId = UInt64` | A **per-method authority token** — the pattern DESIGN_PRINCIPLES.md:383-399 rejects ("authority is the interface reference, not a per-method parameter"). Worse, the local `CapabilityId = UInt64` alias *looks like* `capability.capnp`'s authority type but is a raw number with no proof, target, or constraints. The authority should be the `BlockProvider` reference itself (`storage.capnp:1187` already models it as an interface) |
| R7 | `filesystem.capnp:50`, `:139`, `:100` | `snapshot @10 -> (snapshotId :Text)`, `startReplication @31 -> (replicationId :Text)`, `disableAutoMount @22 (ruleId :Text)` | String ids where typed ids exist (`T.SnapshotId` `types.capnp:1167` — promoted specifically "for filesystem.capnp: snapshot-aware mount operations", never adopted) |
| R7 | `filesystem.capnp:103` | `listAutoMountRules @23 () -> (rules :List(AutoMountRule))` unbounded | Rule catalogs grow; one message must carry them all |
| R8 | `filesystem.capnp:530-544` | `FsProvider` returned by no method in the repo | Driver providers may be host-injected (the E4 rationale), but unlike `storage.capnp`'s `BlockProvider` this one takes a *capability-shaped number* per call, so its acquisition model is both undocumented and wrong-shaped |

Validator counts: E7 ×21, E8 ×11, E6 ×0.

## Duplicates & overlaps
- See wire-breakers: 10+ shared types with `mount.capnp`, several with *conflicting* content (MountOptions, MountInfo, MountEvent, MountOperation) — the more damaging kind of duplicate, because it compiles.
- `StorageTier` + `TieredStorageInfo` (:356) vs `storage.capnp:1016`/`:1030` — tiering modeled twice.
- `FilesystemQuota`/`NamespaceQuota`/`Quota` — three quota types across three files.
- `getSpecialPath @0` (:28) exists in both files and both must remain valid across the merge.

## Gaps & holes
- Trash semantics: `getTrash @1`/`emptyTrash @2` (:30-31) with no enumeration, restore, per-entry size, or event contract — a consumer can trash files (via `Files.removeFile`) but cannot list or restore them without implementing filesystem.capnp's own half-API.
- `getHealth @9` (:45) — a `fsck`-style health check with no scheduling, no history, no event subscription despite the file's own I/O-stats subscription existing at :150.

## Zero-cost / eco
- No bulk payloads (paths and options only). `DefaultAppInfo.icon :T.DataHandle` (:163) — correct.
- No polling patterns; `MountEventSubscription`/`FilesystemIoStatsSubscription` are pull+cancel.
- `getOverlayStats`/`getDedupStats`/`getCompressionStats`/`getReplicationStatus` — all one-shot getters for long-running state; no streaming needed, acceptable.

## UX & implementer guidance
- `cloneFilesystem @11 (source :Text, destination :Text)` (:53) — copies an entire filesystem addressed by path with no size estimate, progress, or result; a consumer cannot learn if it succeeded beyond `T.VoidResult`.
- `resolveContentHash @18 (algorithm :Text, hash :Data)` (:82) — text algorithm where `files.capnp` uses `HashAlgorithm`/`T.HashOutput` :649/:545 — two content-addressing conventions in the merged pair.
- Snapshot creation by `(path, name)` (:50) with no conflict rule if the name exists; `alreadyExists` exists in `T.ErrorCode` (`types.capnp:214`) but nothing says it's used.

## Recommended actions
1. **Execute the merge (BATCH-SUMMARY action 1)**: move `SpecialPathType` → `files.capnp` with identical ordinals; move trash/recent-files/default-apps into `Files`; move the mount surface (`mount`, `unmount`, `remount`, `getMounts`, overlay, auto-mount) into `mount.capnp` — **deleting** the conflicting duplicates rather than aligning them, keeping mount.capnp's richer forms; move `FsProvider`'s legitimate content (probe/mount contract) to storage.capnp's `BlockProvider` axis with the correct authority shape (interface reference, not `CapabilityId = UInt64`). Gain: one canonical file contract, one mount contract, no doomed import edge. Cost: one file deleted, ~8 types relocated, all pre-release.
2. **Reverse the canonical claim** in `files.capnp`'s header (:11) in the same commit, so the documentation matches the doctrine before the merge lands.
3. **Retire the POSIX vocabulary** (`FsMountFlag`, `NetworkFsProtocol`, `FuseCapability`) — whatever survives the merge should carry its protocol identity as `Text` (as `FuseBackendInfo.protocol` already partially does) rather than a frozen enum. Gain: stops naming Linux ABI details; cost: consumers switch on strings with unknown-tolerance.
4. **Complete the trash contract** (list/restore/events) or explicitly scope it out. Gain: either removes a half-API or finishes it; cost: a few methods, or one honest comment.

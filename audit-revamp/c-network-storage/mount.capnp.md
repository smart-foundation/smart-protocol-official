# Audit — mount.capnp (631 lines)

## Verdict
**FIX (targeted).** This is the *better* of the two mount schemas (typed `T.MountId`/`T.FilesystemId`, event union with `custom`, paginated listings) — so when it de-duplicates against `filesystem.capnp` (which is being merged away), keep **this** file's shapes and delete the other's. Its own defects: a POSIX mount-flag catalog expressed twice (`MountOptions` 14 booleans + `MountFlags` 12 booleans re-declaring them), `st_dev`/inode/statfs internals in required fields, a 45-value unused filesystem-name enum, and local ID structs that `types.capnp` already says to replace.

## Wire-breakers
No compile errors. `mount.capnp:4` imports `filesystem.capnp` (`using FS`) but **never references `FS`** — a dead edge into the schema slated for deletion (harmless when it's deleted, misleading until then). `MountId`/`FilesystemId` (:126-127) vs `types.capnp:1100`/`:1114` — promoted versions exist, locals remain (the types.capnp comments say "replace local definition" — never done). Collisions with `filesystem.capnp`: `MountOptions` (:163 vs :166 — **different fields**), `MountOperation` (:345 vs :404 — different values), `AutoMountRule` (:465 vs :367), `OverlayMountRequest`/`OverlayIndexMode` (:448/:440 vs :247/:239 — identical copies), `NetworkFsAuth` (:496 vs :307), `FilesystemCheckResult` (:355 vs `storage.capnp:608`), `FilesystemInfo` (:228 vs `storage.capnp:585` — different shapes).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R6 | `mount.capnp:163-194` vs `:207-224` | `MountOptions` (14 booleans + `propagation` + `fsSpecific` + `custom`) and `MountFlags` (12 of the same booleans again) — the same vocabulary declared **twice in one file** | Two structs, overlapping fields, no rule about which a method means (`MountPoint.options :MountOptions` :140, `MountPoint.flags :MountFlags` :154, `FilesystemInfo.flags :MountFlags` :251, `MountFilter.flags :MountFlags` :299). A consumer setting an option and reading the flag must know the mapping — which the schema never states |
| R5 | `mount.capnp:163-194`, `:196-204` | `MountOptions` names Linux mount(2) flags: `nosuid`, `nodev`, `noexec`, `sync`, `noatime`, `relatime`, `dirsync`, `mand`, `bind`, `rbind`, `move`; `PropagationType` = private/shared/slave/unbindable (+ r-variants) | Mount propagation and suid suppression are Linux kernel semantics. A distributed FS, browser storage, or capability backend implements none of them and must emit all-false. The header (:13-14) claims "no /proc/mounts, no libmount, no FindVolume, no GetVolumeInformation" — accurate about tooling, silent about the kernel-noun vocabulary it actually carries |
| R5 | `mount.capnp:151-152`, `:156`, `:243-247`, `:249` | `MountPoint.totalInodes`/`usedInodes`; `deviceId @13 :UInt64` ("Device ID (st_dev from stat)"); `FilesystemInfo.totalBlocks`/`freeBlocks`/`fragmentSize`/`fsId @10` ("from statfs") | Inode counts, `st_dev`, and statfs internals are POSIX filesystem internals (DESIGN_PRINCIPLES.md:230 flags inode by name). The comments cite the syscalls, making the leak explicit |
| R1 | `mount.capnp:367-431` | `FilesystemType` — 45 vendor nouns (ext2/3/4, xfs, btrfs, f2fs, bcachefs, reiserfs, zfs, nfs, cifs, smb, afs, ceph, glusterfs, lustre, pvfs2, ntfs, fat, exfat, refs, apfs, hfs, iso9660, udf, squashfs, tmpfs, devtmpfs, proc, sysfs, devpts, overlay, virtiofs, v9fs, romfs, cramfs, erofs, jffs2, yaffs) — **and it is used by nothing**: `MountPoint.fsType @3 :Text`, `FilesystemInfo.type @1 :Text` | The most damning duplicate in the batch: an enum and a Text field for the same concept in the same file, and the enum is unreferenced. Implementers see both and must guess which wins — the schema contains its own fork. 2046 failure: any new filesystem has no enum value *and* no typed path |
| R6 | `mount.capnp:126-127` | Local `MountId`/`FilesystemId` while `types.capnp:1100`/`:1114` exist (with comments naming this file) | Unperformed promotion, third instance in the batch (endpoint/storage do the same) |
| R6 | `mount.capnp:448-461`, `:440-446`, `:465-479` | `OverlayMountRequest`, `OverlayIndexMode`, `AutoMountRule` duplicated with `filesystem.capnp:247`/`:239`/`:367` | Same concept, two shapes; when filesystem merges away, this file's copies are canonical — but today a consumer of either service gets different structs |
| R1 | `mount.capnp:260-272` | `FilesystemFeature` = journal/extents/compress/encrypt/snapshots/quotas/acl/xattr/reflink/dedup | Today's feature list; a 2046 filesystem capability has no value (`custom @10`) |
| R7 | `mount.capnp:78`, `:68`, `:92` | `listMountNamespaces @16`, `listAutoMountRules @14`, `listAutoMountPolicies @20` — unbounded | Three catalogs that grow (rules × devices × namespaces), all inline in one message; the file's own `listMounts @0` is paginated |
| R7 | `mount.capnp:43` | `detectFilesystem @8 -> (fsType :Text, label :Text, uuid :Text)` — three parallel unstructured strings | A triple-encoded result; `uuid` as bare `Text` while `T.Uuid` exists (`types.capnp:1391`) |

Validator counts: E7 ×16, E8 ×7, E6 ×0.

## Duplicates & overlaps
- `AutoMountTrigger` (:522) vs `filesystem.capnp`'s rule model — the same feature triggered differently (rule vs policy); the file carries both `AutoMountRule` and `AutoMountPolicy` (:531) for one concept.
- `NetworkMountCredentials` (:483-494) unused, `NetworkFsAuth` duplicated with filesystem.
- `MountStats` (:601) vs `filesystem.capnp` `FilesystemIoStats` (:504) vs `storage.capnp` `IoStats` (:693) — three stats types for storage mounts.
- `MountOperation` vs `filesystem.capnp:404`; `AutoMountEventType` vs `filesystem.capnp`'s event filter vocabulary.

## Gaps & holes
- **Two unmount contracts in the batch**: `mount.capnp unmount @4 (mountId, force, lazy)` vs `filesystem.capnp unmount @7 (path)` — keyed by id vs by path, with different flags. After the merge one survives; the batch must say which, or consumers hold both and guess. (`lazy` is also a POSIX `umount -l` concept.)
- No event for capacity thresholds or device failure on a mount (the event union covers lifecycle only) — `StorageEvent.deviceFailed` (`storage.capnp:750`) exists but nothing links a failed device to its mounts.
- Mount namespace semantics (`listMountNamespaces` :78) are listed but nothing states how a namespace is selected, created, or scoped to a capability.

## Zero-cost / eco
- No bulk payloads (paths, options, stats). No polling pattern (three pull+cancel subscriptions). No R2 findings.
- The two duplicated option/flag structs (R6 row) are the cost: a consumer must read 26 boolean fields across two structs to know what a mount will do.

## UX & implementer guidance
- `unmount(mountId, force, lazy)` — a three-parameter destructive op where `force` + `lazy` together mean "detach now, clean up later"; POSIX `umount` semantics leaked into parameter names.
- `resizeFilesystem @22 (mountId, newSizeBytes, grow, force)` (:100) — "force shrink even if data loss risk" (:595) is a destructive hint with no warning surface beyond the parameter name.
- `mountDeviceMapper @25`/`getDeviceMapperInfo @26` (:113-116) — dm-crypt/dm-thin/dm-linear named in comments and free-form `dmType :Text` in requests: half-open (good) but the methods persist a Linux device-mapper concept in the interface.

## Recommended actions
1. **Resolve the filesystem.capnp duplication toward this file**: when filesystem merges away (BATCH-SUMMARY action 1), mount.capnp's `MountOptions`, `MountPoint`, event union, and auto-mount forms are canonical — state that in the header so the surviving shapes are unambiguous. Gain: one mount contract, decided by the schema rather than by which service a consumer happened to hold. Cost: none beyond the merge itself.
2. **Delete `FilesystemType` or wire it to the two `fsType :Text` fields** (open token is preferred: filesystem identity is backend vocabulary, and the `metadata :T.StringMap` fields already exist for backend detail). Gain: removes an unused 45-value catalog and the enum/Text ambiguity in one stroke. Cost: nothing (unused) or a typed choice for consumers who wanted it.
3. **Unify `MountOptions` and `MountFlags` into one** (options as the settable set; flags as the reported/effective set can reuse it). Gain: removes an intra-file duplicate vocabulary of 26 booleans. Cost: one struct deletion + reference edits.
4. **Move POSIX internals to metadata** (`deviceId (st_dev)`, inode counts, `fsId`, `fragmentSize`, and the Linux flag names → `T.StringMap` metadata or an opaque options token). Gain: non-Linux backends stop emitting fake values; consumers stop routing on `st_dev`. Cost: consumers reading these fields switch to metadata — after release they'd have read lies on non-POSIX backends anyway.
5. **Adopt the promoted typed IDs** (:126-127) and delete the locals. Gain: completes a documented decision (third instance in the batch). Cost: mechanical.
6. **Paginate the three unbounded catalogs** (`listMountNamespaces`, `listAutoMountRules`, `listAutoMountPolicies`). Gain: bounded memory, matches the file's own `listMounts`. Cost: three `T.Pagination` params.

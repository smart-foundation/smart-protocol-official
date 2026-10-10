# Audit — storage.capnp (1266 lines)

## Verdict
**FIX (targeted, heavy).** The *interface* is disciplined — 51 methods, everything paginated, `T.VoidResult`, `T.DataHandle` for pool export/import, `custom` on event unions. The *type layer* is the vendor-noun problem in its purest form: the file's header promises "Zero backend assumptions: no LVM, no mdadm, no ZFS, no Btrfs, no Storage Spaces, no VxVM" (:8-9) and then declares a `PoolType` enum whose values are exactly LVM, md RAID, ZFS, Btrfs, Storage Spaces, VxVM (:379-405). A required field that the file's own first sentence forbids is the headline finding; the `BusType` shadow of `types.capnp` is the wire-breaker grade one.

## Wire-breakers
No compile errors (no duplicate ordinals, no undefined `T.*`). Type-shadowing collision: `storage.capnp:274-291` `BusType` vs `types.capnp:1685-1701` `BusType` — two enums with the same name and **different value sets** (storage: scsi/ata/nvme/usb/spdk/nbd...; types: pci/pcie/usb/i2c/spi...). Any file importing both gets an ambiguous reference; a consumer that picks the wrong one compiles where the other was meant. More name collisions: `StoragePoolId`/`VolumeId`/`SnapshotId` (:337/:436/:498) vs `types.capnp:1141/:1154/:1167` (the promoted versions), `FilesystemCheckResult` (:608 vs `mount.capnp:355` — byte-identical), `FilesystemInfo` (:585 vs `mount.capnp:228` — different shapes), `StorageTier` (:1016 vs `filesystem.capnp:348`), `CacheMode` (:836 vs `buffer.capnp:253` vs `hal.capnp:55` — three), `MigrationState` (:980 vs `process.capnp:475`/`runtime_search.capnp:576`), `ReplicationStatus` (:1068 vs `content.capnp:697`/`database.capnp:668`).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R1 | `storage.capnp:379-405` | `PoolType` = lvm/mdraid/zfs/btrfs/storagespaces/stratis/vdo/bcache/ceph/gluster/ontap/vvm/illumosZfs/vmfs/nvmeof — in `CreatePoolRequest.type @1`, a **required** field | The header at :8-9 explicitly forbids these names; a consumer reading the header will pass values the header promised cannot exist. 2046 failure: a backend pooling NVMe-over-fabric or purely logical storage must choose between a lie enum value and `custom @16`; consumers' `PoolType` switches (pool creation, feature detection, monitoring) silently exclude it |
| R1 | `storage.capnp:274-291` | `BusType` shadows types.capnp with vendor/tool nouns: spdk, nbd, rbd (Ceph RBD), aoe, iscsi | Same as above, plus the shadow collision. A fabric bus in 2046 has no value in either enum |
| R1 | `storage.capnp:407-417` | `RedundancyLevel` = mirror/raid5/raid6/raid10/raidz1/raidz2/raidz3 | raidz1/2/3 are ZFS spellings of what math calls "1/2/3 parity drives" — the vendor name adds zero information and the enum pretends they're a different species |
| R1 | `storage.capnp:890-896` | `EncryptionMethod` = luks1/luks2/bitlocker/filevault | Four products, two OS families. A 2046 full-disk encryption scheme (or a capability-native sealed volume) has no value |
| R1 | `storage.capnp:256-272` | `BlockDeviceType` = crypt/lvm/md/zfs/btrfs (dm-crypt, LVM LV, md RAID, ZFS zvol, btrfs subvolume) — device-mapper internals | A network-backed virtual disk or an object-store-backed volume is unclassifiable except `custom` |
| R1 | `storage.capnp:293-301`, `:324-333` | `PartitionTableType` includes `sgI`/`sun` (vendor nouns); `PartitionFlag` = boot/esp/lvm/raid/swap | Vendor flags; a container-image storage backend partitions nothing |
| R5 | `storage.capnp:213`, `:241`, `:304-311` | `BlockDevice.name @1 :Text` ("Kernel/sysfs name"), `scheduler @15 :Text` ("Current I/O scheduler"), `Partition.start/size` in sectors | sysfs noun; scheduler selection is kernel-internal (TIMELESSNESS.md:84 rejects scheduler hints); sector geometry is a device detail consumers should not route on |
| R6 | `storage.capnp:337`, `:436`, `:498` | Local `StoragePoolId`/`VolumeId`/`SnapshotId` despite `types.capnp:1132-1167` documenting the promotion ("storage.capnp: StoragePoolId (replace local definition)") | The promotion was decided and never performed — same unperformed-promotion pattern as `mount.capnp:126` and `endpoint.capnp:75` |
| R6 | `storage.capnp:608-614`, `:585-597` | `FilesystemCheckResult` and `FilesystemInfo` duplicated identically/divergently with `mount.capnp:355`/`:228` | Two check-result contracts and two fs-info contracts; a consumer of the mount service cannot pass results to the storage service |
| R7 | `storage.capnp:82`, `:88`, `:105`, `:139` | Scrub, rebuild, migration, replicate are **poll-by-getter** long operations (`getScrubProgress @23`, `getRebuildProgress @28`, `getMigrationProgress @37`, `getReplicationStatus @41`) while `subscribeIoStats @43` shows the streaming pattern | A scrub of a 40 TB pool runs for days; progress is available only by polling. `backup.capnp` models this correctly (`BackupProgressSubscription`). Eco cost: polling loops for day-long operations; fork risk: each backend picks a poll interval and the protocol is silent |
| R7 | `storage.capnp:685-690`, `:812-818` | `IoStatsTarget` and `CacheTierRequest` unions have no unknown/custom (validator E6) | A new stats target (volume snapshot, remote replica) cannot be named in the union; consumers' exhaustive switch breaks |
| R2 | `storage.capnp:1234-1241` | `BlockRange.bufferSlot @2 :UInt32` — block I/O references a ring *slot index*, with no buffer identity (same hole as `network.capnp`'s `NicFrameDesc`) | The zero-copy block path depends on an out-of-band slot→buffer agreement the schema never states; each backend invents it |
| R7 | `storage.capnp:76` | `getSmartTestResults @19` unbounded | A device accumulates test history without bound |

Validator counts: E7 ×43, E8 ×9, E6 ×2.

## Duplicates & overlaps
- `BusType`, `FilesystemCheckResult`, `FilesystemInfo`, `StorageTier`, `CacheMode`, `MigrationState`, `ReplicationStatus` (above).
- SMART: `SmartData`/`SmartAttribute`/`SmartTestResult` (:618-681) — a coherent ATA-native model, fine on its own terms, but nothing else in the batch reuses it.
- `EncryptVolumeRequest`/`EncryptionStatus` (:877/:1091) vs `filesystem.capnp` `FilesystemEncryptionInfo` vs `backup.capnp` `EncryptionInfo` vs `files.capnp` `EncryptedFileInfo` — **four** encryption-info types in the batch.

## Gaps & holes
- No progress subscription for the day-long operations (scrub/rebuild/migrate/partition/encrypt) — the `backup.capnp` pattern is available in-batch.
- `exportPool @33`/`importPool @34` (:126-129) move a pool as a `T.DataHandle` with no integrity, encryption, or size-estimate contract (backup.capnp's `Checksum`/`EncryptionInfo` exist for exactly this).
- No statement of what `StorageService` authority is (which capability-gated reference you must hold) — the provider interfaces (BlockProvider) compound this.

## Zero-cost / eco
- `exportPool`/`importPool` correctly use `T.DataHandle`; block I/O is slot-referenced (though see the missing buffer identity).
- The five poll-by-getter long operations are the eco finding: a consumer monitoring a scrub polls an RPC in a loop for hours.
- `BlockProvider.submit @3 (ops :List(BlockIoOp))` — batched submit (good); but there is no completion *notification* interface, so consumers poll for completion (submit-and-poll instead of submit-and-wake).

## UX & implementer guidance
- The header (8-15) reads as a promise the enum layer immediately breaks; that mismatch is worse than either alone, because it teaches implementers not to trust schema headers.
- `Partition.size @1` in sectors + `sizeBytes @3` (:309-311) — two size fields with different units and no default rule.
- `IoStats` latency fields (:715-720) are `UInt32` microseconds with the unit only in a comment, while `T.Duration` is nanoseconds elsewhere in the file — the unit-in-comment pattern repeats.
- `DeviceFilter.rotational @5 :Bool` (:785) — absent silently means "any", `custom` handling undocumented.

## Recommended actions
1. **Open `PoolType`, `BusType`, `EncryptionMethod`, `BlockDeviceType`, `PartitionTableType`, `PartitionFlag`** to `Text` tokens (or `T.StringMap` parameter blocks), keeping only math-closed sets. Gain: the header's promise becomes true; a 2046 pool/bus/encryption is a string with unknown-tolerance instead of a lie or a fork. Cost: consumers lose exhaustive enum matching — but with `custom` variants they never had it safely.
2. **Adopt the promoted typed IDs** (`T.StoragePoolId`/`T.VolumeId`/`T.SnapshotId`, :337/:436/:498) and delete the locals. Gain: completes a documented decision, removes three shadow types. Cost: mechanical.
3. **Add progress subscriptions for the long operations** (`subscribeScrub`, `subscribeRebuild`, `subscribeMigration`, `subscribeReplication` — one `StorageProgressSubscription` shape mirroring `backup.capnp:274`), keeping the one-shot getters as deprecated-on-arrival. Gain: day-long operations stop forcing polling loops; backends stop inventing progress semantics. Cost: four methods + one subscription interface — real machinery that removes a real loop.
4. **Unify the four encryption-info types** onto one (`T.HashOutput`/`T.KeyId` + `Text` algorithm + optional `T.StringMap`), used by files/filesystem/storage/backup. Gain: one encryption vocabulary in the storage batch. Cost: three type deletions and reference updates.
5. **Give block/buffer references an identity** (`BlockRange`/`BlockIoOp` carry a `T.BufferId` alongside the slot). Gain: the block path's zero-copy mechanism becomes expressible. Cost: one field.
6. **Align `IoStats` latency units** to `T.Duration`. Gain: removes comment-only units. Cost: field type change (wire break, acceptable pre-release).

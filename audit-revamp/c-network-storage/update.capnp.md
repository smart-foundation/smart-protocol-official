# Audit — update.capnp (507 lines)

## Verdict
**FIX (targeted, small).** The best-behaved large schema in the batch after buffer/clock: scheme-agnostic header ("OSTree, package managers, A/B partitions, container image deltas... never the mechanism"), honest `T.Error` in every result, pagination with totals, `T.DataHandle` for deltas and signatures, and its event union already carries the doctrine's exact `unknown @11 :UnknownEvent {typeId, payload}` shape. Three targeted items: update operations are identified as `T.BackupId` (a type-safety break), the changelog is inline `Text` where the file's own comment concedes it must be a handle, and the A/B partition model is baked in as fixed slot A/B fields while the header promises backend-agnosticism. One dead type (`UpdateQuarantine`).

## Wire-breakers
No compile errors. Semantic type collision: `T.BackupId` (`types.capnp:31`) used as the update **operation id** (`cancelOperation @8` :45, `subscribe @9` :48, `pull @10` :49, `cancel @11` :50, plus `CreateBackupSuccess`/`RestoreBackupSuccess.operationId :T.BackupId`). Update operations and backups are unrelated things sharing one typed id — passing a backup id to `cancelOperation` silently targets the wrong operation family. (`T.UpgradeId` exists at `types.capnp:38` and is used for *updates*, just not for operations.) Name collisions: `UpdateCheckResult` (:147 vs `package.capnp:305`), `InstallOptions` (:156 vs `package.capnp:212`), `DeviceGroup` (:408 vs `device.capnp:283`), `InstallProgress`/`UpdateInfo` overlap with package's install surface.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R7 | `update.capnp:45`, `:48-50` | Update operations are keyed by `T.BackupId` | See wire-breakers. An update id and a backup id are interchangeable at compile time and unrelated at runtime; there is no compile guard against crossing them |
| R2 | `update.capnp:175` | `UpdateInfo.changelog @5 :Text` — the file's own comment (:176-179) says "For large changelogs (>1KB), consumers should treat the Text as a reference and fetch the full content via a DataHandle when needed" | Treating a `Text` as a reference is precisely what R2 forbids — there is no mechanism to resolve the reference, so every consumer copies the changelog on every `listAvailable` (unbounded list × unbounded text). The file names the fix and defers it; pre-release is the free moment |
| R5 | `update.capnp:313-352`, `:102`, `:105` | `PartitionState { slotA, slotB, activeSlot }` + `setNextBoot @25`/`markSlotGood @26` | A/B slot pairing is an Android/firmware boot mechanism; the header (:7-8) promises "OSTree, package managers, A/B partitions, container image deltas" — but only A/B partitions have a state struct. A container-image or snapshot-based backend must fake slotA/slotB. 2046 failure: a system with 4 slots, or no partitions, cannot be described |
| R8 | `update.capnp:428-438` | `UpdateQuarantine` is returned by no method (`quarantineUpdate @27`/:111 write it; `getRolloutStatus @34` doesn't include it) | The quarantine feature is half-wired: you can quarantine and release but never read the state. Backends invent the missing getter with their own shape |
| R7 | `update.capnp:96`, `:81` | `getGroupDevices @23` and `getUpdateDependencies @18` unbounded | Fleet groups grow to `UInt32` device ids; one message carries them all |
| R1 | `update.capnp:199-208` | `UpdateCategory` = security/bugfix/feature/driver/firmware/osKernel/runtime | Taxonomy names today's software stack ("runtime" vs "osKernel" is a 2020s distinction); `custom @7` valueless. (`UpdateSeverity` :191 and `AutoUpdatePolicy` :222 are defensibly closed) |
| R6 | `update.capnp:355-366`, `:499-507` | `DeltaPatch`/`SignedUpdatePackage`/`VerifyChain` vs `package.capnp`'s install/verify surface (the file's own comment at :74 acknowledges "false positive: update_verification.capnp belongs here" — but the *duplication with package.capnp* is unexamined) | Two update/install contracts in the tree; a consumer must know which the backend honors |

Validator counts: E7 ×23, E8 ×6, E6 ×0.

## Duplicates & overlaps
- `UpdateCheckResult`/`InstallOptions`/`DeviceGroup`/install-progress vs `package.capnp` (cross-batch, flagged for the package schema's owner).
- `RolloutStatus`/`RolloutState` (:476/:485) vs `StagedRollout` (:296) vs `RolloutStep` (:416) — three rollout representations in one file with overlapping fields (percentage vs steps vs percentage-per-step).
- `PartitionHealth` (:335) vs `storage.capnp`'s health enums; `SyncStatus` (backup) etc. covered in their files.
- `VerifyChain.root :T.KeyFingerprint` (:371) — good use of the promoted type; `signatures :List(T.DataHandle)` (:379) — correct (bulk in handles).

## Gaps & holes
- **Resumable download/install**: `downloadProgress` events (:265) carry `bytesDone`/`bytesTotal` but there is no checkpoint or idempotency token — an interrupted download restarts from zero in every backend. `InstallOptions.requestToken :Data` (:164) is the right idiom and exists, but is unrelated to resume. Demonstrated fork risk: each backend invents its own resume cursor.
- `getPostUpdateHealth @17` (:78) returns a point-in-time struct with no subscription or history — "should we roll back" is the highest-stakes question and it's one-shot.
- No A/B-*independent* rollback contract: `rollback @6` is package-keyed; for slot-based systems the rollback target is the slot (`markSlotGood`/`setNextBoot` imply it) and the two models are not reconciled.

## Zero-cost / eco
- Correct where it matters: `DeltaPatch.deltaData :T.DataHandle` (:363), `VerifyChain.signatures :List(T.DataHandle)` (:379), `SignedUpdatePackage.signature :T.DataHandle` (:506).
- `UpdateInfo.changelog :Text` inline (the R2 row).
- `getGroupDevices`/`getUpdateDependencies` unbounded (the R7 row).
- No polling pattern (`UpdateEventSubscription` is pull+cancel*and* pullPaged, :232-241 — the model case).

## UX & implementer guidance
- `UpdateEvent.unknown @11` (:261) — named `unknown`, not `custom`; the file's comment (:256-260) explains the wire-compat reason honestly. The *name* still misleads readers into thinking an unexpected event arrived rather than a forward-compat slot. Pre-release, the rename to `custom` is free and should be considered.
- `getState @0` returns four independent booleans (`checking`, `downloading`, `updating` :138-140) with no exclusivity rule — `checking=true, downloading=true` is representable and undefined. A single state union (or documented exclusivity) is clearer.
- `installAll @5` "honoring current AutoUpdatePolicy" (:44) — policy vs. explicit call precedence is undocumented (does `installAll` on `manual` policy install or refuse?).

## Recommended actions
1. **Introduce a correct operation id**: use `T.UpgradeId` or a new promoted `UpdateOperationId` for `cancelOperation`/`subscribe`/`pull`/`cancel` (and for `CreateBackupSuccess`/`RestoreBackupSuccess.operationId` in backup.capnp, its sibling instance). Gain: stops update/backup id crossover — a compile-clean runtime bug class. Cost: a handful of reference edits; zero wire damage pre-release.
2. **Convert `changelog` to `T.DataHandle`** (:175). Gain: large changelogs stop copying on every listing; the file's own comment endorses the direction. Cost: one field type change.
3. **Generalize the partition model beyond A/B**: `slots :List(PartitionInfo)` + `activeSlot :UInt8` (replacing fixed `slotA`/`slotB`), or move slot state behind a storage/boot interface. Gain: the header's backend-agnostic promise becomes true; 4-slot and slotless systems are expressible. Cost: two fields become a list — wire-affecting, free pre-release.
4. **Wire `UpdateQuarantine` to a getter** (`getQuarantineStatus @36 (packageId) -> (quarantine :UpdateQuarantine)`). Gain: the feature becomes complete; backends stop inventing the read path. Cost: one method.
5. **Paginate `getGroupDevices`/`getUpdateDependencies`**. Gain: bounded fleet queries. Cost: two params.
6. **Add a resume token to download progress** (`DownloadProgress` gains `checkpoint :Data`, and install accepts `resumeFrom :Data`). Gain: interrupted downloads resume deterministically instead of restarting — a demonstrated fork risk (every backend invents a cursor today). Cost: one field + one option.

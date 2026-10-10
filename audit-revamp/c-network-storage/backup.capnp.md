# Audit — backup.capnp (429 lines)

## Verdict
**FIX (targeted).** The core is one of the better-executed schemas in the batch: multi-phase progress (not a bare float), `T.Error` in progress and result unions, `done :Bool` terminators, paginated listing, conflict/encryption as first-class metadata, remote targets as opaque URIs. The defects: Audit-8/9/10 added **six types with no methods** (`BackupVerification`, `BackupOptionsExtended`, `BackupMissedPolicy`, `SyncState`, `DeduplicationMetadata`, `BaseBackupCascadePolicy`), `BackupStrategy` duplicates `BackupKind` exactly, and the two big read methods (`getManifest`, `getDiff`) return unbounded entry lists in a single message.

## Wire-breakers
No compile errors. Name collisions: `SyncStatus` (:398 enum vs `files.capnp:868` **struct** — enum/struct name collision), `RetentionPolicy` (:227 union vs `files.capnp:720` struct), `CompressionAlgorithm` (:353 — fourth copy), `Checksum`/`ChecksumAlgorithm` (:88-100) vs `T.HashOutput` (`types.capnp:1179`), `EncryptionAlgorithm` (:108) vs `archive.capnp:660` `ArchiveEncryptionAlgorithm` vs `storage.capnp:890` `EncryptionMethod`, `HashAlgorithm` (via Checksum).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R7 | `backup.capnp:62`, `:305` | `getManifest @15 -> BackupManifest` whose `entries @1 :List(BackupManifestEntry)` is **unbounded** | A manifest of a full-system backup has millions of entries (path Text + checksum each). One message carries them all — tens of MB inline, no pagination parameter, in the same batch where `storage.capnp` and `files.capnp` both paginate listings. A 2046 full-disk backup is exactly the case this breaks on |
| R7 | `backup.capnp:59`, `:294-298` | `getDiff @14 -> BackupDiff { added, removed, modified }` — three unbounded `List(BackupManifestEntry)` | A diff between two system backups is unbounded for the same reason. No pagination, no truncation flag |
| R8 | `backup.capnp:327-338`, `:341-350`, `:373-378`, `:381-396`, `:407-414`, `:424-428` | `BackupVerification`, `BackupOptionsExtended`, `BackupMissedPolicy`, `SyncState`, `DeduplicationMetadata`, `BaseBackupCascadePolicy` — returned/accepted by no method | Six features advertised in type with no API: verification, extended options, missed-run policy, sync progress, dedup metadata, cascade policy. A consumer cannot call any of them; each backend implements its own variant — six forks |
| R6 | `backup.capnp:363-370` | `BackupStrategy` = full/incremental/differential/mirror/snapshot/custom — **the same six values as `BackupKind @157-164`** | An internal duplicate created by Audit-8 and used by nothing. Two names for one concept; nothing tells an implementer which is authoritative |
| R6 | `backup.capnp:88-100` | `Checksum { algorithm :ChecksumAlgorithm, hash :Data }` vs `T.HashOutput { algorithm :UInt16, bytes :Data }` (`types.capnp:1179`) — with a **different algorithm encoding** (enum vs UInt16 ordinals) | Two hash shapes with incompatible algorithm representation; translating one to the other requires a hand-maintained mapping table. `T.HashOutput` was promoted precisely for this |
| R6 | `backup.capnp:227-234` | `RetentionPolicy` union (countBased/ageBased/spaceBased/custom) vs `files.capnp:720` `RetentionPolicy` **struct** (path/action/period/minAge/enabled) | Same name, incompatible shapes, both reachable (`BackupSchedule.retention` vs `Files.setLifecycle`) — a consumer compiled against one gets a compile error, not a type error, when handed the other |
| R7 | `backup.capnp:48-50` | `subscribe @9 (operationId :T.BackupId)` + `cancel @11 (subscription :BackupProgressSubscription)` | The subscription takes an operation id *and* returns a reference — two ways to address one subscription. Same pattern flagged in the a-foundation batch for `system.capnp` |
| R7 | `backup.capnp:172` | `BackupProgress.phaseProgress :Float32` (0.0-1.0) | A single float for phase progress contradicts the file's own header praise ("Progress is multi-phase, not a float", :13) — the *intra-phase* progress is exactly the float it rejects |

Validator counts: E7 ×17, E8 ×10, E6 ×0.

## Duplicates & overlaps
- `BackupStrategy`≡`BackupKind`, `Checksum` vs `T.HashOutput`, `RetentionPolicy` vs `files.capnp`, `SyncStatus` vs `files.capnp`, `CompressionAlgorithm` (4×), `EncryptionInfo`/`EncryptionAlgorithm` (4-way overlap).
- `RemoteTarget.credentialsId @2 :T.KeyId` (:286) — a storage `KeyId` used to point at a *remote credential*; conflation of key-management and credential vocabulary.
- `BackupInfo.packages @6 :List(T.PackageId)` (:74) — the only tie to the package/update systems, and it's unidirectional and unexplained (a system backup's package list with no restore semantics).

## Gaps & holes
- **Resumable transfer**: `DownloadProgress`/`getDiff`/`syncToRemote` have no checkpoint or idempotency token — an interrupted sync restarts from zero in every backend, and clients cannot ask "where do I resume?". `InstallOptions.requestToken :Data` (`update.capnp:164`) shows the idiom exists in-batch.
- No verification surface: `BackupVerification` exists (dead) and `BackupPhase.verifying @5` (:200) exists, but no method runs verification and returns it — integrity checking is unreachable.
- Scheduling: `BackupSchedule` has no timezone/catch-up policy (`BackupMissedPolicy` is the dead type that would have carried it) — a missed backup window has no defined behavior.

## Zero-cost / eco
- No bulk payloads in the interface (metadata and progress only); no `Data`/`DataHandle` bulk path to review. No polling patterns (`BackupProgressSubscription` is the model).
- The unbounded manifest/diff lists (above) are the memory pressure finding: allocation scales with backup size in one message.

## UX & implementer guidance
- `getEstimatedSize @7` returns `(sizeBytes, itemEstimate)` (:41-42) — a tuple where a small struct with documented semantics would say whether `itemEstimate` is a count of files or entries.
- `RetentionPolicy.countBased @0 :UInt32` — "keep N" at UInt32 saturates at 4B backups; the enum's other members are fine, this one is 1990s.
- `restoreBackup @3 -> RestoreBackupResult` with `progress :BackupProgressSubscription` (:269) — good pattern; but `createBackup` returns the same subscription for a create operation, and the *restore* operation's id is a `T.BackupId` (`operationId` :268) — an update-style operation id reusing a backup id.

## Recommended actions
1. **Wire or delete the six dead types**: `verify @16 (backupId) -> (result :BackupVerification)` makes the most sense as the single addition (verification is a real, demanded feature with a dead type waiting); delete `BackupStrategy` (keep `BackupKind`), fold `BackupMissedPolicy` into `BackupSchedule` (one field), and either wire `SyncState`/`DeduplicationMetadata`/`BaseBackupCascadePolicy` to their features or delete them. Gain: features either become callable or stop advertising. Cost: one method plus deletions — net smaller.
2. **Paginate `getManifest` and `getDiff`** (`page :T.Pagination` + `total :UInt64`, matching the file's own `listBackups @0` pattern). Gain: a 1M-entry manifest stops being one message; bounded memory. Cost: two signatures.
3. **Adopt `T.HashOutput`** for `Checksum` (delete the local type) and unify the batch's four encryption-algorithm vocabularies on one (see BATCH-SUMMARY action 4). Gain: one hash shape, one encryption vocabulary. Cost: type deletions with reference updates.
4. **Add a resume checkpoint** to `SyncState`/`syncToRemote` (`resumeToken :Data`, caller-chosen, honored by the backend). Gain: interrupted syncs resume instead of restarting — a demonstrated fork risk (every backend invents its own cursor today). Cost: one field.
5. **Drop `phaseProgress :Float32` or replace with byte/item counters** (the struct already has `bytesProcessed`/`itemsProcessed` :179-183). Gain: the header's "not a float" claim becomes true. Cost: one field.

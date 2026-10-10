# Audit — files.capnp (927 lines)

## Verdict
**FIX (targeted) — and it must absorb `filesystem.capnp` in the same wave.** The read side is exemplary: `readFile` returns `T.DataHandle`, listings are paginated, `T.FileHandleId` is used, subscriptions have cancel. The write side was never converted (`writeFile`, `createFile` take inline `Data`), and the exact three defects DESIGN_PRINCIPLES.md names — `FileHandle.path/mode` (:163), `FilePermissions` owner/group/other (:177), `inode`/`device` (:230-231) — are all still present. The file also carries three overlapping permission models and a self-duplicated `DiskUsageExtended`.

## Wire-breakers
None (compiles clean). Import-edge wire risk: `files.capnp:28` imports `filesystem.capnp` solely for `FS.SpecialPathType` (:50) — the schema slated for deletion, per the doctrine. Any consumer's build depends on a file that cannot survive; see BATCH-SUMMARY action 1. Name collisions: `SearchQuery` (:428 vs `system_search.capnp:137`), `SearchResult` (:436 vs `shell.capnp:482`/`system_search.capnp:162`), `RetentionPolicy` (:720 struct vs `backup.capnp:227` union), `SyncStatus` (:868 struct vs `backup.capnp:398` enum), `HashAlgorithm` (:649 vs `archive.capnp:7`/`crypto.capnp:263`/`signature.capnp:114`), `CompressionAlgorithm` (:626), `LifecycleAction` (:711 vs `extension.capnp:322`).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R4 | `files.capnp:332-337` | `FileHandle { handle :T.FileHandleId, path @1 :Text, mode @2 :OpenMode }` | DESIGN_PRINCIPLES.md:163 names this exact struct: "path and mode leak implementation details; a capability-based system may not have path-based handles; a microkernel may not expose mode at handle creation. Fix: keep handle opaque, move path/mode to a separate FileInfo query." Still unfixed. A distributed backend must fabricate path/mode values consumers then depend on — the handle stops being a pure reference |
| R5 | `files.capnp:373-377` | `FilePermissions { owner :UInt8, group :UInt8, other :UInt8 }` | DESIGN_PRINCIPLES.md:177/229: "POSIX-specific. Capability-based systems don't have owner/group/other." Every non-POSIX backend lies (0,0,0), and consumers display/write those lies |
| R5 | `files.capnp:476-478` | `ExtendedMetadata.inode @15 :UInt64`, `device @16 :UInt64`, `hardLinks @17 :UInt32` | DESIGN_PRINCIPLES.md:230-231 flags inode/device as filesystem internals. A distributed FS has no inode; two backends' inode numbers coincide by accident and consumers get false identity |
| R5 | `files.capnp:348-360` | `FileType` includes `blockDevice`, `charDevice`, `fifo`, `socket` | Device-node types from POSIX's "everything is a file" model. An object store or browser backend has none of them; `custom @9` is valueless |
| R3 | `files.capnp:205`, `:280-281`, `:373-377`, `:880-909` | **Three permission models in one file**: `FilePermissions` (owner/group/other), `AclEntry`/`FileAcl`/`checkAcl`, and `checkPermissions @62` ("current user") | DESIGN_PRINCIPLES.md:399: "Do NOT define permission strings, boolean flags, or role-based access control in the protocol. The capability system IS the access control mechanism." Three models force implementers to define precedence — which wins when ACL and mode disagree? — a fork the protocol created |
| R2 | `files.capnp:35`, `:63`, `:156` | `writeFile @3 (data :Data)`, `createFile @19 (content :Data)`, `writeFileAsync (data :Data)` | The bulk write path is inline while the read path (`readFile @2 :T.DataHandle`) was converted. Copy cost: writing a 100 MB file through `createFile` copies 100 MB into the message arena (allocation + copy + message growth). The highest-volume path in this schema forces the one cost the doctrine forbids |
| R7 | `files.capnp:42`, `:104`, `:211`, `:67` | `statFile @7 -> (info :FileInfo)`, `getFileVersion @35`, `getFileHash @64 -> (hash :T.HashOutput)`, `resolveSymlink @23` — no error paths | A stat of a missing file must return a sentinel `FileInfo` (empty path? zero size? zero timestamps?). Backends fork on the sentinel — one returns empty, another returns a zeroed struct with `permissions` zeroed, a third throws. `fileExists @8` exists separately but makes the natural caller pattern a racy TOCTOU (exists-then-open, non-atomic) |
| R7 | `files.capnp:159` | `pollAsyncOperation @50` | A busy-poll for async I/O completion, in a file that already has event subscriptions (`FileAuditSubscription` :768, `watchDirectory` :52). The event machinery exists; this method invites polling loops |
| R6 | `files.capnp:492-503` | `DiskUsageExtended` is field-identical to `DiskUsage` (:445-456) and referenced by nothing | A "backward-compatible" copy that duplicates itself; two spellings of one type with no migration path |
| R6 | `files.capnp:256-259`, `:834-839` | `backupFile`/`restoreBackup` + local `BackupConfig`/`BackupTarget` duplicate `backup.capnp`'s `BackupService.createBackup`/`restoreBackup` | File-level backup and system backup are two contracts with overlapping scope; a consumer must guess which one the backend actually implements |
| R6 | `files.capnp:858-876`, `:599-606` | `SyncConfig`/`SyncStatus` + `CloudSyncStatus` overlap `backup.capnp` `SyncState`/`SyncStatus` and cloud sync | Three sync surfaces with three state vocabularies |
| R6 | `files.capnp:11`, `:49-50` | Header says "SpecialPathType imported from filesystem.capnp (canonical source)" | Contradicts DESIGN_PRINCIPLES.md:212 ("Merge into files.capnp... Delete filesystem.capnp") — see BATCH-SUMMARY action 1 |
| R1 | `files.capnp:775-781` | `AnalysisType` = ocr/imageRecognition/documentClassification/sentiment — `ai.capnp` exists and models these as reported metadata (`CapabilityDescriptor.name` :134) | A frozen AI feature list in the files contract; the batch's own gold standard has the open shape |
| R8 | `files.capnp:733`, `:913` | `LifecycleRule` and `MetadataCacheEntry` returned by no method | Dead types; `getLifecycle`/`setLifecycle` use `RetentionPolicy`, the rule catalog goes nowhere |

Validator counts: E7 ×45, E8 ×19, E6 ×0.

## Duplicates & overlaps
- `FileType` vs `archive.capnp`'s `isDirectory`/`isSymlink` bools and `storage.capnp`'s device model — file typing done three ways in the batch.
- `HashAlgorithm`×4, `CompressionAlgorithm`×4, `BackupConfig`/`BackupTarget`, `SyncConfig`/`SyncStatus` (above).
- `getFileType @63` returns `mimeType :Text` (:208) while `FileInfo.mimeType @7 :Text` (:370) and `T.MimeType` (`types.capnp:777`) exist — bare Text where the typed MIME was promoted for exactly this purpose.
- `FileAuditEntry`/`FileAuditFilter` (:752-766) vs `capability.capnp`'s whole audit-trail section and `database.capnp`'s `AuditLogEntry` — audit modeled three times in the batch.

## Gaps & holes
- **Capability delegation for files**: there is no way to hand a `FileHandle` to another process with attenuated authority. `buffer.capnp` has `exportBufferToProcess @32` (:605); files has nothing. Every backend invents delegation out-of-band — a demonstrated fork risk on the batch's most-shared resource type.
- No normative path-grammar: `Text` paths with no statement of separators, escaping, or how special paths compose with relative ones (`getSpecialPath` + `T.FilePath` at `types.capnp:726` exist but nothing says the two compose).
- `compareFiles`/`compareFilesV2` return `diff :Text`/`diff :T.DataHandle` (:82-85) without saying what a diff *is* (format, granularity) — backends fork on the encoding.

## Zero-cost / eco
- `writeFile`/`createFile`/`writeFileAsync` inline `Data` — the headline copy cost (see R2 row).
- `pollAsyncOperation` busy-poll pattern (see R7 row).
- Unbounded lists: `listBranches @74` (:251), `listSyncConfigs @79` (:270); the primary listings (`listDirectory`, `searchFiles`, `walkTree`, `getFileVersions`, `getFileActivity`) are correctly paginated.

## UX & implementer guidance
- The three permission models (above) are the primary implementer trap: `getPermissions`/`setPermissions`/`checkPermissions`/`setFileAcl`/`getFileAcl`/`checkAcl` — six methods, three models, no precedence rule.
- `decryptFile @43 (path, keyId :T.KeyId)` (:134) takes a key reference but no capability — decryption authority is a bare key id; `capability.capnp`'s `target`/`operations` model is the intended mechanism.
- `getEncryptionInfo`/`EncryptedFileInfo.iv :Data` (:577) — an initialization vector stored as queryable metadata; consumers could mistake it for the ciphertext.

## Recommended actions
1. **Absorb `filesystem.capnp`**: move `SpecialPathType` into this file (identical enum ordinals, `getSpecialPath @13` unchanged), fold in trash/recent-files/default-apps, hand the mount surface to `mount.capnp`, then delete `filesystem.capnp`. Gain: resolves the documented doctrine conflict and kills the import edge into a doomed schema. Cost: one type move plus a file deletion — all pre-release, and the wire shape of `getSpecialPath @13` is untouched.
2. **Convert the write path to `T.DataHandle`** (`writeFile`, `writeFileAsync`, `createFile.content`, `CreateEncryptedRequest.content`). Gain: writes stop duplicating every byte into the message — the single largest copy cost in the storage batch. Cost: a type change on four parameters; acceptable now, breaking after release.
3. **Fix the three doctrine-named defects**: strip `path`/`mode` from `FileHandle` (they are already in `FileInfo`), replace `FilePermissions.owner/group/other` with an opaque `Data` token or `List(AclPermission)`-style universal set, and move `inode`/`device`/`hardLinks` into backend metadata (`T.StringMap`). Gain: capability, distributed, and browser backends implement the contract without lying; three DESIGN_PRINCIPLES items close. Cost: consumers that read ownership/inode must switch to the opaque/metadata path — after release these consumers would have broken anyway on a non-POSIX backend.
4. **Collapse the permission models** onto one: keep ACL entries (`AclEntry`/`AclPermission`) as the structured form, make `FilePermissions` an opaque token or delete it, and route `checkPermissions`/`checkAcl` through the capability system. Gain: one authority story per DESIGN_PRINCIPLES:399; cost: two methods repurposed or retired.
5. **Add error paths to the info getters** (`statFile`, `getFileHash`, `getFileVersion`, `resolveSymlink`): return `union { info @0 :X; error @1 :T.Error; }` (or `T.VoidResult`-style wrappers). Gain: honest failures, one sentinel convention instead of N. Cost: four signatures.
6. **Add file capability delegation** (`delegate @86 (handle, authority :Capability) -> (granted :FileHandle)` gated once; attenuation stays in `capability.capnp`). Gain: the batch's most-shared resource becomes delegatable per the doctrine instead of per-implementation. Cost: one accessor-shaped method; small machinery removing a large ambiguity.
7. **Delete the dead types** (`DiskUsageExtended`, `LifecycleRule`, `MetadataCacheEntry`), switch `mimeType :Text` → `T.MimeType`, and pick one home for backup/sync (delegate to `backup.capnp` for system-level backup, keep file-level copy/move only). Gain: removes self-duplication and cross-file overlap. Cost: zero to small.

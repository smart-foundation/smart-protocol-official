# Audit — archive.capnp (752 lines)

## Verdict
**FIX (targeted).** The streaming pair (`compressStream`/`decompressStream`) is the right idea, but both endpoints take and return inline `Data` — the streaming API copies every chunk, defeating its own purpose. `ArchiveFormat` is a 35-value product catalog and `CompressionMethod` a 27-value one, in a file whose header claims "no libarchive, no 7-Zip, no libzip, no tar". The entry model carries POSIX ownership (`uid`/`gid`/`mode`/`uname`/`gname`) and an "extract with privilege" option. Otherwise: honest errors, paginated listing, typed hashes.

## Wire-breakers
No compile errors. `HashAlgorithm` (:7) vs `files.capnp:649`/`crypto.capnp:263`/`signature.capnp:114` — four copies with different value sets (archive's has `xxh64`, files' has `blake3`, crypto's has more). `ArchiveEncryptionAlgorithm` (:660) vs `backup.capnp:108` `EncryptionAlgorithm` vs `storage.capnp:890` `EncryptionMethod`. `ArchiveSource`/`ArchiveDestination` don't collide but see the internal inconsistency below.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R2 | `archive.capnp:93`, `:102` | `CompressStream.write @0 (data :Data)` and `DecompressStream.read @0 -> (data :Data, done :Bool)` | The streaming API — added specifically "for large archives with backpressure" (:55-59) — copies every chunk inline. A 4 GB archive streams as 4 GB of chunk copies through the message arena; the backpressure design is defeated by the payload type. `T.DataHandle` on both endpoints is the whole fix |
| R1 | `archive.capnp:135-222` | `ArchiveFormat` = zip/tar/tarGz/tarBz2/tarXz/tarZst/tarLz4/tarLzma/sevenz/rar/rar5/cpio/cpioGz/ar/deb/rpm/iso/squashfs/dmg/appimage/xar/cab/lzip/zstd/lz4/lha/arj/zoo/arc/warc/snap/flatpak/erofs/wim | The `tar×codec` variants (:141-146) expose the combinatorics: container × compression is a matrix the enum enumerates by hand; every new codec adds six ordinals forever. This is the deleted `ModelFormat` class of error (`ai.capnp:16-21`) verbatim — "a list is today's list and it ages into a lie". A 2046 container has no value |
| R1 | `archive.capnp:288-316` | `CompressionMethod` = 27 values incl. `reduced1..4` (1990s ZIP), `imploded`, `shrunk`, plus `zstdFast`/`zstdHigh` (mode artifacts of one codec frozen as separate values) | Same frozen-catalog failure; and encoding one codec's *modes* as distinct values means every parameterized codec multiplies the enum |
| R5 | `archive.capnp:249-261`, `:345` | `ArchiveEntry.mode :UInt32` ("Unix mode bits"), `uid @8`, `gid @9`, `uname`, `gname`; `ExtractRequest.preserveOwnership` "requires privilege" | A capability-system archive has no uid; extraction "preserving ownership" is meaningless off-POSIX, and the schema requires lying (zeros). 2046 failure: cross-ecosystem archives lose or fabricate owner metadata with no honest encoding |
| R6 | `archive.capnp:387-391` | `ExtractEntryRequest`'s destination union `{path @4, buffer @5, handle @6}` re-invents `ArchiveDestination` `{path, buffer, handle, custom}` (:451-458) — minus the `custom` variant | Two spellings of one concept in one file; the *wrong* one (without `custom`) is attached to the single-entry extraction method |
| R7 | `archive.capnp:380`, `:398` | Two unions lack unknown/custom (validator E6): `ExtractEntryRequest`'s destination and `ExtractEntryResult` | A future destination kind (write back into another archive? stream to a consumer?) cannot be named in the union |
| R7 | `archive.capnp:727-732` | `ArchiveDiffResult.entriesAdded/Removed/Modified` — three unbounded `List(ArchiveEntry)` | A diff of two large archives is unbounded; `BackupDiff` in the sibling schema (also flagged) has the same shape |
| R7 | `archive.capnp:501` | `IntegrityError.error :Text` where the file's other errors use `T.Error` (`ExtractError.error @1 :T.Error` :377, `CompressError` :470) | Two error conventions in one feature family |
| R1 | `archive.capnp:660-670` | `ArchiveEncryptionAlgorithm` = aes128/aes256/zipCrypto/tripleDes/blowfish/twofish/chacha20/none | `zipCrypto` is a named weakness, `tripleDes`/`blowfish` are deprecated; a 2046 cipher has no value. (Compare `tunnel.capnp`'s Kyber problem — the same naming-generation failure) |

Validator counts: E7 ×18, E8 ×7, E6 ×2.

## Duplicates & overlaps
- `HashAlgorithm` ×4, `ArchiveEncryptionAlgorithm` ×4-way (the batch's encryption-vocabulary problem, BATCH-SUMMARY action 4).
- `ArchiveDestination` vs `ExtractEntryRequest`'s inline union (above).
- `OperationProgress`/`OperationPhase` (:626-654) vs `backup.capnp` `BackupProgress`/`BackupPhase` — two progress contracts in the batch; backup's is the better-documented one.
- `ArchiveSource.data @1 :Data` (:120) — flagged honestly in-file as in-memory-small-archives; fine.

## Gaps & holes
- **Resumable/streaming extraction with partial state**: `extract @1` has `operationId @13 :Text` (:358) for progress, but no resume contract — an interrupted extraction of a 4 GB archive restarts; nothing says whether completed entries are skipped.
- No entry-level random-access contract despite `ArchiveEntry.offset @17 :UInt64` (:279) being described as "for random access" — no method accepts an offset; the field promises a capability no method uses.
- Password handling: `password :Data` on five request structs (:324, :337, :383, ...) — a secret in the message on every call (same class as `network.capnp`'s wifi password).

## Zero-cost / eco
- The streaming endpoints' inline `Data` (headline R2 row): the streaming API is the eco feature and it is copy-bound.
- `listEntries @0` and `readSplitArchive @15` are paginated (:331/:704); `diffArchives` and `verifyEntryHashes` are not (above).
- No polling pattern.

## UX & implementer guidance
- The header (:18-20) names seven products to reject, then the enum names 35 formats — the same self-contradiction as `storage.capnp`, and equally corrosive to header trust.
- `ExtractRequest.sparseExtraction @15` (:362) — a filesystem implementation detail exposed as a protocol request flag (sparse writes depend on the target FS).
- `CompressRequest.parallelism @14 :UInt32` (:360) — "0 = auto, 1 = single-threaded" is an implementation hint; harmless, but it is exactly the "HOW not WHAT" class the Agnostic test rejects.
- `splitArchive`/`readSplitArchive` pair on `SplitNaming` (:605) — naming conventions ("archive.part000" etc.) are protocol-level format choices; backends should agree, so this one is defensible.

## Recommended actions
1. **Convert the streaming endpoints to `T.DataHandle`** (`CompressStream.write`, `DecompressStream.read`, and the two request structs' payload fields where large). Gain: the backpressure streaming design actually achieves zero-copy; a 4 GB archive stops copying. Cost: two method signatures — the single highest-value fix in this file.
2. **Split `ArchiveFormat` into container + compression** (or express both as `T.MimeType`-style content types with parameters): container ∈ {zip, tar, cpio, ar, other} as an open token, compression ∈ open token, with the combination carried by parameters. Gain: the tar×codec combinatorics collapse; new formats/codecs are strings. Cost: consumers build a (container, codec) pair instead of picking one value — more honest and smaller forever.
3. **Remove POSIX ownership from entries** (`uid`/`gid`/`uname`/`gname` → backend metadata `T.StringMap`; keep `mode` only if redefined as an opaque permissions token or drop with `preserveOwnership`). Gain: archives from capability systems extract honestly. Cost: POSIX archival fidelity moves to backend metadata (where it survives for backends that have it).
4. **Use `ArchiveDestination` in `ExtractEntryRequest`** (replacing the local union, regaining `custom`). Gain: one destination vocabulary, and the E6 flag closes. Cost: one field change.
5. **Paginate the diff and verify results** (`diffArchives` result, `HashVerificationResult.mismatches`). Gain: bounded memory on largest-archive operations. Cost: two signatures.
6. **Align `IntegrityError` to `T.Error`**. Gain: one error convention. Cost: one field.

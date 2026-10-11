@0xa1b2c3d4e5f60105;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Archive — archive extraction and creation.
#
# Zero backend assumptions: no libarchive, no 7-Zip, no libzip,
# no tar, no gzip, no xz, no bzip2, no zstd. Backend provides
# archive operations; protocol defines the contract.
#
# Common app need — every app reimplements this.
#
# Used by: package.capnp (package extraction), files.capnp (archive browsing)
#
# Fixes this revision makes:
#   - The streaming pair actually streams. `CompressStream.write` and
#     `DecompressStream.read` took and returned inline `Data`, so the
#     feature added "for large archives with backpressure" copied every
#     chunk into the message arena and defeated its own purpose. Both
#     endpoints are `T.DataHandle` now.
#   - Format is two open tokens, not 35 enumerated products. The old
#     `ArchiveFormat` spelled out tar×codec combinatorics by hand
#     (tarGz, tarBz2, tarXz, tarZst, tarLz4, tarLzma, ...), so every new
#     codec added six ordinals forever and a 2046 container had no value.
#     Container and compression are now independent strings plus
#     parameters.
#   - `CompressionMethod` (27 values, including 1990s ZIP curiosities
#     like `reduced1..4`, `imploded` and `shrunk`, and one codec's fast/
#     high modes frozen as separate values) is gone: compression is the
#     same open token as in the format.
#   - POSIX ownership is gone from entries. `uid`, `gid`, `uname`,
#     `gname`, `mode` and `preserveOwnership` required a capability or
#     browser backend to fabricate owner metadata consumers then
#     trusted; what a backend genuinely knows, it reports in `metadata`.
#   - Single-entry extraction uses the same destination vocabulary as
#     everything else (regaining its `custom` variant).
#   - Errors are T.Error everywhere in the integrity feature.
#   - Diff and hash-verification results are bounded: a diff of two
#     large archives used to be three unbounded lists in one message.
#   - Implementation hints (`parallelism`, `sparseExtraction`) are gone:
#     they describe HOW, not WHAT (the Agnostic test).
# ═══════════════════════════════════════════════════════════════════════

# Container and compression are independent open tokens. The
# combination carries its own parameters, so "tar + zstd at level 19"
# is data rather than an invented enum value.
struct ArchiveFormat {
    # Container token: "zip", "tar", "cpio", "ar", "7z", "iso", ...
    container @0 :Text;
    # Compression token: "gzip", "zstd", "xz", "bzip2", "lz4", "none", ...
    compression @1 :Text;
    # Codec parameters as backend-declared data (level, mode, dictionary).
    parameters @2 :T.StringMap;
}

interface ArchiveService {
    # List entries in an archive.
    listEntries @0 (request :ListEntriesRequest) -> (entries :List(ArchiveEntry), totalCount :UInt64);

    # Extract entire archive to a directory.
    extract @1 (request :ExtractRequest) -> (result :ExtractResult);

    # Extract a single entry from an archive.
    extractEntry @2 (request :ExtractEntryRequest) -> (result :ExtractEntryResult);

    # Create an archive from files/directories.
    compress @3 (request :CompressRequest) -> (result :CompressResult);

    # Add files to existing archive.
    addToArchive @4 (request :AddToArchiveRequest) -> T.VoidResult;

    # Delete entries from archive.
    deleteFromArchive @5 (request :DeleteFromArchiveRequest) -> T.VoidResult;

    # Test archive integrity.
    testIntegrity @6 (archive :ArchiveSource, format :ArchiveFormat) -> (result :IntegrityResult);

    # Get archive metadata.
    getMetadata @7 (archive :ArchiveSource, format :ArchiveFormat) -> (result :ArchiveMetadataResult);

    # Convert archive format.
    convert @8 (request :ConvertRequest) -> (result :ConvertResult);

    # Stream-compress data (for large archives with backpressure).
    compressStream @9 (request :CompressStreamRequest) -> (stream :CompressStream);

    # Stream-decompress data (for large archives with backpressure).
    decompressStream @10 (request :DecompressStreamRequest) -> (stream :DecompressStream);

    # Merge multiple archives into one.
    mergeArchives @11 (request :MergeArchivesRequest) -> (result :MergeArchivesResult);

    # Split a large archive into volumes.
    splitArchive @12 (request :SplitArchiveRequest) -> (result :SplitArchiveResult);

    # Subscribe to archive operation progress.
    subscribeProgress @13 (operationId :ArchiveOperationId) -> (subscription :ProgressSubscription);

    # Repair a partially corrupted archive.
    repairArchive @14 (request :RepairArchiveRequest) -> (result :RepairArchiveResult);

    # Read a split archive from a directory of parts.
    readSplitArchive @15 (request :ReadSplitArchiveRequest) -> (entries :List(ArchiveEntry), totalCount :UInt64);

    # Stream hash verification for entry contents.
    verifyEntryHashes @16 (request :StreamingHashRequest) -> (result :HashVerificationResult);

    # Compute diff between two archives (bounded — see the result type).
    diffArchives @17 (request :ArchiveDiffRequest, page :T.Pagination) -> (result :ArchiveDiffResult);
}

interface CompressStream {
    # Feed data into the stream compressor, as a handle: the backpressure
    # design is only zero-copy if the payload is.
    write @0 (data :T.DataHandle) -> T.VoidResult;
    # Signal end of input and flush remaining compressed data.
    finish @1 () -> (result :CompressResult);
    # Cancel the stream operation.
    cancel @2 () -> T.VoidResult;
}

interface DecompressStream {
    # Read decompressed data from the stream.
    read @0 (maxBytes :UInt32) -> (result :DecompressStreamResult);
    # Cancel the stream operation.
    cancel @1 () -> T.VoidResult;
}

struct DecompressStreamResult {
    union {
        chunk @0 :StreamChunk;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct StreamChunk {
    data @0 :T.DataHandle;
    # Whether this is the last chunk.
    done @1 :Bool;
    metadata @2 :T.StringMap;
}

interface ProgressSubscription {
    pull @0 () -> (progress :OperationProgress);
    cancel @1 () -> T.VoidResult;
}

# An operation is not a backup or an update: it gets its own typed id.
struct ArchiveOperationId { id @0 :UInt64; }

# ─── Archive Source ──────────────────────────────────────────────────

struct ArchiveSource {
    union {
        # Local file path.
        path @0 :Text;

        # In-memory data (for small archives), as a handle.
        data @1 :T.DataHandle;

        # Buffer reference (for large archives).
        buffer @2 :T.BufferId;

        # Stream/handle (backend-specific).
        handle @3 :T.FileHandleId;

        # Custom source (URL, cloud storage, etc.).
        custom @4 :Data;
    }
}

# ─── Archive Entry ───────────────────────────────────────────────────

struct ArchiveEntry {
    # Path within archive (relative, "/"-separated).
    path @0 :Text;

    # Entry size in bytes (uncompressed).
    size @1 :UInt64;

    # Compressed size in bytes (0 if unknown or stored).
    compressedSize @2 :UInt64;

    # Whether this is a directory.
    isDirectory @3 :Bool;

    # Whether this is a symlink.
    isSymlink @4 :Bool;

    # Symlink target (if isSymlink).
    symlinkTarget @5 :Text;

    # Last modified timestamp.
    lastModified @6 :T.Timestamp;

    # Compression method used for this entry, as an open token.
    compression @7 :Text;

    # CRC32 checksum (for containers that carry one).
    crc32 @8 :UInt32;

    # SHA256 hash (if computed/verified).
    sha256 @9 :Data;

    # Whether entry is encrypted.
    encrypted @10 :Bool;

    # Encryption algorithm as an open token (if encrypted).
    encryptionAlgorithm @11 :Text;

    # Entry offset in archive (for random access).
    offset @12 :UInt64;

    # Extended attributes and backend-declared ownership/permission
    # detail. POSIX owner ids and mode bits lived here as required
    # fields; they are backend metadata now, which is the only place a
    # capability or browser backend can report them honestly.
    metadata @13 :T.StringMap;
}

# ─── Requests ────────────────────────────────────────────────────────

struct ListEntriesRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;
    # Password for encrypted archives: the caller's inline secret, as
    # content. A backend that must never see it takes a key reference
    # instead.
    password @2 :T.DataHandle;
    # Path prefix filter (only entries under this path).
    prefix @3 :Text;
    # Include/exclude patterns (glob-style).
    includePatterns @4 :List(Text);
    excludePatterns @5 :List(Text);
    # Pagination for large archives.
    pagination @6 :T.Pagination;
    metadata @7 :T.StringMap;
}

struct ExtractRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;
    password @2 :T.DataHandle;
    # Destination directory (must exist).
    destination @3 :Text;
    # Preserve timestamps.
    preserveTimestamps @4 :Bool = true;
    # Overwrite existing files.
    overwrite @5 :Bool = true;
    # Skip existing files.
    skipExisting @6 :Bool = false;
    # Path prefix filter.
    prefix @7 :Text;
    # Include/exclude patterns.
    includePatterns @8 :List(Text);
    excludePatterns @9 :List(Text);
    # Strip leading path components (like tar --strip-components).
    stripComponents @10 :UInt32;
    # Operation id for progress tracking.
    operationId @11 :ArchiveOperationId;
    metadata @12 :T.StringMap;
}

# Ownership and permission fidelity is deliberately absent: preserving a
# uid/gid an archive happens to carry is a POSIX operation that a
# capability backend cannot perform and should not fake. What a backend
# knows, it reports in `ArchiveEntry.metadata`.

struct ExtractResult {
    success @0 :Bool;
    extractedCount @1 :UInt64;
    failedCount @2 :UInt64;
    errors @3 :List(ExtractError);
    # Total bytes extracted.
    bytesExtracted @4 :UInt64;
    duration @5 :T.Duration;
    metadata @6 :T.StringMap;
}

struct ExtractError {
    path @0 :Text;
    error @1 :T.Error;
    metadata @2 :T.StringMap;
}

struct ExtractEntryRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;
    password @2 :T.DataHandle;
    # Entry path within archive.
    entryPath @3 :Text;
    # Output destination — the same vocabulary as every other
    # destination in this file (and it has a `custom` variant, which the
    # previous inline union lacked).
    destination @4 :ArchiveDestination;
    # Offset within entry (for partial extraction).
    offset @5 :UInt64;
    # Length to extract (0 = rest of entry).
    length @6 :UInt64;
    metadata @7 :T.StringMap;
}

struct ExtractEntryResult {
    union {
        success @0 :ExtractEntrySuccess;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct ExtractEntrySuccess {
    bytesWritten @0 :UInt64;
    entry @1 :ArchiveEntry;
    metadata @2 :T.StringMap;
}

struct CompressRequest {
    # Source files/directories to archive.
    sources @0 :List(CompressSource);
    # Destination archive.
    destination @1 :ArchiveDestination;
    format @2 :ArchiveFormat;
    # Default compression level (1-9, 0 = backend default); the level is
    # also expressible as a format parameter.
    compressionLevel @3 :UInt8 = 6;
    password @4 :T.DataHandle;
    # Encryption algorithm as an open token.
    encryptionAlgorithm @5 :Text;
    # Preserve timestamps.
    preserveTimestamps @6 :Bool = true;
    # Follow symlinks (store target, not link).
    followSymlinks @7 :Bool = false;
    # Preserve hardlinks (maintain link relationships).
    preserveHardlinks @8 :Bool = true;
    # Include hidden files.
    includeHidden @9 :Bool = true;
    # Exclude patterns.
    excludePatterns @10 :List(Text);
    # Operation id for progress tracking.
    operationId @11 :ArchiveOperationId;
    # Archive comment.
    comment @12 :Text;
    metadata @13 :T.StringMap;
}

struct CompressSource {
    # Source path on filesystem.
    path @0 :Text;
    # Path within archive (relative).
    archivePath @1 :Text;
    # Whether to recurse into directories.
    recursive @2 :Bool = true;
    metadata @3 :T.StringMap;
}

struct ArchiveDestination {
    union {
        path @0 :Text;
        buffer @1 :T.BufferId;
        handle @2 :T.FileHandleId;
        custom @3 :Data;
    }
}

struct CompressResult {
    success @0 :Bool;
    archiveSize @1 :UInt64;
    entryCount @2 :UInt64;
    duration @3 :T.Duration;
    errors @4 :List(CompressError);
    metadata @5 :T.StringMap;
}

struct CompressError {
    sourcePath @0 :Text;
    error @1 :T.Error;
    metadata @2 :T.StringMap;
}

struct AddToArchiveRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;
    password @2 :T.DataHandle;
    sources @3 :List(CompressSource);
    # Whether to update existing entries.
    update @4 :Bool = false;
    # Whether to only add newer files.
    freshen @5 :Bool = false;
    metadata @6 :T.StringMap;
}

struct DeleteFromArchiveRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;
    password @2 :T.DataHandle;
    # Entry paths to delete.
    entryPaths @3 :List(Text);
    metadata @4 :T.StringMap;
}

struct IntegrityResult {
    union {
        result @0 :IntegrityOutcome;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct IntegrityOutcome {
    valid @0 :Bool;
    errors @1 :List(IntegrityError);
    checkedEntries @2 :UInt64;
    duration @3 :T.Duration;
    metadata @4 :T.StringMap;
}

struct IntegrityError {
    path @0 :Text;
    error @1 :T.Error;
    errorType @2 :IntegrityErrorType;
    metadata @3 :T.StringMap;
}

enum IntegrityErrorType {
    unspecified @0;
    crcMismatch @1;
    sizeMismatch @2;
    compressionError @3;
    encryptionError @4;
    missingEntry @5;
    extraEntry @6;
    corruptedHeader @7;
    custom @8;
}

struct ArchiveMetadataResult {
    union {
        metadata @0 :ArchiveMetadata;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct ArchiveMetadata {
    format @0 :ArchiveFormat;
    formatVersion @1 :Text;
    comment @2 :Text;
    # Tool that created the archive, as reported data.
    createdBy @3 :Text;
    createdAt @4 :T.Timestamp;
    entryCount @5 :UInt64;
    totalSize @6 :UInt64;
    compressedSize @7 :UInt64;
    encrypted @8 :Bool;
    # Encryption algorithm as an open token.
    encryptionAlgorithm @9 :Text;
    # Format-specific metadata.
    custom @10 :T.StringMap;
}

struct ConvertRequest {
    source @0 :ArchiveSource;
    sourceFormat @1 :ArchiveFormat;
    sourcePassword @2 :T.DataHandle;
    destination @3 :ArchiveDestination;
    targetFormat @4 :ArchiveFormat;
    targetPassword @5 :T.DataHandle;
    targetCompressionLevel @6 :UInt8 = 6;
    operationId @7 :ArchiveOperationId;
    metadata @8 :T.StringMap;
}

struct ConvertResult {
    union {
        result @0 :ConvertOutcome;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct ConvertOutcome {
    success @0 :Bool;
    sourceSize @1 :UInt64;
    targetSize @2 :UInt64;
    entryCount @3 :UInt64;
    duration @4 :T.Duration;
}

# ─── Streaming Operations ─────────────────────────────────────────

struct CompressStreamRequest {
    format @0 :ArchiveFormat;
    compressionLevel @1 :UInt8 = 6;
    password @2 :T.DataHandle;
    # Encryption algorithm as an open token.
    encryptionAlgorithm @3 :Text;
    operationId @4 :ArchiveOperationId;
    metadata @5 :T.StringMap;
}

struct DecompressStreamRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;
    password @2 :T.DataHandle;
    entryPath @3 :Text;  # Empty = first entry or stream of entries
    operationId @4 :ArchiveOperationId;
    metadata @5 :T.StringMap;
}

# ─── Merge ────────────────────────────────────────────────────────

struct MergeArchivesRequest {
    sources @0 :List(ArchiveSource);
    sourceFormats @1 :List(ArchiveFormat);
    destination @2 :ArchiveDestination;
    targetFormat @3 :ArchiveFormat;
    targetCompressionLevel @4 :UInt8 = 6;
    # Deduplicate entries by path (keep latest).
    deduplicate @5 :Bool = true;
    password @6 :T.DataHandle;
    operationId @7 :ArchiveOperationId;
    metadata @8 :T.StringMap;
}

struct MergeArchivesResult {
    union {
        result @0 :MergeOutcome;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct MergeOutcome {
    success @0 :Bool;
    totalEntries @1 :UInt64;
    duplicateEntries @2 :UInt64;
    outputSize @3 :UInt64;
    duration @4 :T.Duration;
    errors @5 :List(T.Error);
    metadata @6 :T.StringMap;
}

# ─── Split ────────────────────────────────────────────────────────

struct SplitArchiveRequest {
    source @0 :ArchiveSource;
    sourceFormat @1 :ArchiveFormat;
    password @2 :T.DataHandle;
    destination @3 :Text;  # Directory to write split parts
    partSize @4 :UInt64;   # Size per part in bytes
    naming @5 :SplitNaming;
    operationId @6 :ArchiveOperationId;
    metadata @7 :T.StringMap;
}

enum SplitNaming {
    unspecified @0;
    sequential @1;    # archive.part000, archive.part001, ...
    numbered @2;      # archive.000, archive.001, ...
    custom @3;
}

struct SplitArchiveResult {
    union {
        result @0 :SplitOutcome;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct SplitOutcome {
    success @0 :Bool;
    parts @1 :List(SplitPart);
    totalSize @2 :UInt64;
    duration @3 :T.Duration;
    metadata @4 :T.StringMap;
}

struct SplitPart {
    path @0 :Text;
    size @1 :UInt64;
    partNumber @2 :UInt32;
    metadata @3 :T.StringMap;
}

# ─── Operation Progress ──────────────────────────────────────────────

struct OperationProgress {
    operationId @0 :ArchiveOperationId;
    phase @1 :OperationPhase;
    currentFile @2 :Text;
    filesProcessed @3 :UInt64;
    totalFiles @4 :UInt64;
    bytesProcessed @5 :UInt64;
    totalBytes @6 :UInt64;
    elapsed @7 :T.Duration;
    estimatedRemaining @8 :T.Duration;
    errors @9 :List(T.Error);
    done @10 :Bool;
    metadata @11 :T.StringMap;
}

enum OperationPhase {
    unspecified @0;
    initializing @1;
    scanning @2;
    extracting @3;
    compressing @4;
    encrypting @5;
    decrypting @6;
    verifying @7;
    finalizing @8;
    complete @9;
    failed @10;
    repairing @11;
    custom @12;
}

# ─── Archive Repair ───────────────────────────────────────────

struct RepairArchiveRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;
    password @2 :T.DataHandle;
    # Destination for repaired archive.
    destination @3 :ArchiveDestination;
    # Whether to attempt recovery of corrupted entries.
    recoverEntries @4 :Bool = true;
    operationId @5 :ArchiveOperationId;
    metadata @6 :T.StringMap;
}

struct RepairArchiveResult {
    union {
        result @0 :RepairOutcome;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct RepairOutcome {
    success @0 :Bool;
    repairedEntries @1 :UInt64;
    unrecoverableEntries @2 :UInt64;
    errors @3 :List(T.Error);
    outputSize @4 :UInt64;
    duration @5 :T.Duration;
    metadata @6 :T.StringMap;
}

# ─── Multi-Volume Reading ─────────────────────────────────────

struct ReadSplitArchiveRequest {
    # Directory containing split parts.
    directory @0 :Text;
    # Naming pattern (used to find parts).
    naming @1 :SplitNaming;
    # Password for encrypted archives.
    password @2 :T.DataHandle;
    # Pagination for large archives.
    pagination @3 :T.Pagination;
    metadata @4 :T.StringMap;
}

# ─── Archive Streaming Hash Verification ─────────────────────

struct StreamingHashRequest {
    # Hash algorithm as an open token ("sha256", "blake3", ...).
    algorithm @0 :Text;
    # Entries to verify.
    entryPaths @1 :List(Text);
    metadata @2 :T.StringMap;
}

struct HashVerificationResult {
    union {
        page @0 :HashVerificationPage;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct HashVerificationPage {
    verified @0 :Bool;
    entriesChecked @1 :UInt64;
    entriesMatched @2 :UInt64;
    # Bounded list of mismatches; `totalMismatches` says how many there
    # were, so a fully-corrupted archive cannot be one enormous message.
    mismatches @3 :List(HashMismatch);
    totalMismatches @4 :UInt64;
    metadata @5 :T.StringMap;
}

struct HashMismatch {
    path @0 :Text;
    expectedHash @1 :Data;
    actualHash @2 :Data;
}

# ─── Archive Diff ─────────────────────────────────────────────

struct ArchiveDiffRequest {
    sourceA @0 :ArchiveSource;
    formatA @1 :ArchiveFormat;
    passwordA @2 :T.DataHandle;
    sourceB @3 :ArchiveSource;
    formatB @4 :ArchiveFormat;
    passwordB @5 :T.DataHandle;
    metadata @6 :T.StringMap;
}

struct ArchiveDiffResult {
    union {
        page @0 :ArchiveDiffPage;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct ArchiveDiffPage {
    entriesAdded @0 :List(ArchiveEntry);
    entriesRemoved @1 :List(ArchiveEntry);
    entriesModified @2 :List(ModifiedEntry);
    identicalEntries @3 :UInt64;
    # Totals for each list, so a diff of two large archives is bounded.
    totalAdded @4 :UInt64;
    totalRemoved @5 :UInt64;
    totalModified @6 :UInt64;
    metadata @7 :T.StringMap;
}

struct ModifiedEntry {
    path @0 :Text;
    sizeA @1 :UInt64;
    sizeB @2 :UInt64;
    hashA @3 :Data;
    hashB @4 :Data;
}

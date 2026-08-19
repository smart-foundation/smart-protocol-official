@0xa1b2c3d4e5f60105;

using T = import "types.capnp";

# ─── Archive Hash Algorithm ───────────────────────────────────

enum HashAlgorithm {
    sha256 @0;
    sha512 @1;
    blake3 @2;
    xxh64 @3;
    custom @4;
}

# ═══════════════════════════════════════════════════════════════════════
# Archive — archive extraction and creation (zip, tar, 7z, etc.).
#
# Zero backend assumptions: no libarchive, no 7-Zip, no libzip,
# no tar, no gzip, no xz, no bzip2, no zstd. Backend provides
# archive operations; protocol defines the contract.
#
# Common app need — every app reimplements this.
#
# Used by: package.capnp (package extraction), files.capnp (archive browsing)
# ═══════════════════════════════════════════════════════════════════════

interface ArchiveService {
    # List entries in an archive.
    listEntries @0 (request :ListEntriesRequest) -> (entries :List(ArchiveEntry), totalCount :UInt32);

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
    testIntegrity @6 (archive :ArchiveSource) -> (result :IntegrityResult);

    # Get archive metadata.
    getMetadata @7 (archive :ArchiveSource) -> (metadata :ArchiveMetadata);

    # Convert archive format.
    convert @8 (request :ConvertRequest) -> (result :ConvertResult);

    # Stream-compress data (for large archives with backpressure).
    compressStream @10 (request :CompressStreamRequest) -> (stream :CompressStream);

    # Stream-decompress data (for large archives with backpressure).
    decompressStream @11 (request :DecompressStreamRequest) -> (stream :DecompressStream);

    # Merge multiple archives into one.
    mergeArchives @12 (request :MergeArchivesRequest) -> (result :MergeArchivesResult);

    # Split a large archive into volumes.
    splitArchive @13 (request :SplitArchiveRequest) -> (result :SplitArchiveResult);

    # Subscribe to archive operation progress.
    subscribeProgress @9 (operationId :Text) -> (subscription :ProgressSubscription);

    # ─── Archive Repair ────────────────────────────────────────

    # Repair a partially corrupted archive.
    repairArchive @14 (request :RepairArchiveRequest) -> (result :RepairArchiveResult);

    # ─── Multi-Volume Reading ──────────────────────────────────

    # Read a split archive from a directory of parts.
    readSplitArchive @15 (request :ReadSplitArchiveRequest) -> (entries :List(ArchiveEntry), totalCount :UInt32);

    # ─── Archive Streaming Hash Verification ───────────────────

    # Stream hash verification for entry contents.
    verifyEntryHashes @16 (request :StreamingHashRequest) -> (result :HashVerificationResult);

    # ─── Archive Diff ─────────────────────────────────────────

    # Compute diff between two archives.
    diffArchives @17 (request :ArchiveDiffRequest) -> (result :ArchiveDiffResult);
}

interface CompressStream {
    # Feed data into the stream compressor.
    write @0 (data :Data) -> T.VoidResult;
    # Signal end of input and flush remaining compressed data.
    finish @1 () -> (result :CompressResult);
    # Cancel the stream operation.
    cancel @2 () -> T.VoidResult;
}

interface DecompressStream {
    # Read decompressed data from the stream.
    read @0 (maxBytes :UInt32) -> (data :Data, done :Bool);
    # Cancel the stream operation.
    cancel @1 () -> T.VoidResult;
}

interface ProgressSubscription {
    pull @0 () -> (progress :OperationProgress);
    cancel @1 () -> T.VoidResult;
}

# ─── Archive Source ──────────────────────────────────────────────────

struct ArchiveSource {
    union {
        # Local file path.
        path @0 :Text;

        # In-memory data (for small archives).
        data @1 :Data;

        # Buffer reference (for large archives).
        buffer @2 :T.BufferId;

        # Stream/handle (backend-specific).
        handle @3 :T.FileHandleId;

        # Custom source (URL, cloud storage, etc.).
        custom @4 :Data;
    }
}

# ─── Archive Formats ─────────────────────────────────────────────────

enum ArchiveFormat {
    # Zip
    zip @0;

    # Tar variants
    tar @1;
    tarGz @2;       # was: tar_gz (.tar.gz / .tgz)
    tarBz2 @3;      # was: tar_bz2 (.tar.bz2 / .tbz2)
    tarXz @4;       # was: tar_xz (.tar.xz / .txz)
    tarZst @5;      # was: tar_zst (.tar.zst / .tzst)
    tarLz4 @6;      # was: tar_lz4 (.tar.lz4)
    tarLzma @7;     # was: tar_lzma (.tar.lzma)

    # 7-Zip
    sevenz @8;

    # RAR
    rar @9;
    rar5 @10;         # RAR version 5+

    # CPIO
    cpio @11;
    cpioGz @12;     # was: cpio_gz

    # AR/Debian
    ar @13;
    deb @14;

    # RPM
    rpm @15;

    # ISO
    iso @16;

    # SquashFS
    squashfs @17;

    # Apple Disk Image
    dmg @18;

    # AppImage
    appimage @19;

    # XAR (Apple/IBM archive format, used by .pkg, .xar)
    xar @20;

    # Microsoft Cabinet
    cab @21;

    # Lzip (LZMA-based)
    lzip @22;

    # Zstandard (standalone, not tar+zstd)
    zstd @23;

    # LZ4 (standalone, not tar+lz4)
    lz4 @24;

    # LHA/LZH
    lha @25;

    # ARJ
    arj @26;

    # Zoo
    zoo @27;

    # ARC
    arc @28;

    # WARC (Web ARChive)
    warc @29;

    # Snap package (Ubuntu)
    snap @30;

    # Flatpak bundle
    flatpak @31;

    # EROFS (Enhanced Read-Only File System)
    erofs @32;

    # WIM (Windows Imaging Format)
    wim @33;

    # Custom
    custom @34;
}

# ─── Archive Entry ───────────────────────────────────────────────────

struct ArchiveEntry {
    # Path within archive (relative, POSIX-style with /).
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

    # File permissions (Unix mode bits, 0 if not applicable).
    mode @7 :UInt32;

    # User ID (0 if not applicable).
    uid @8 :UInt32;

    # Group ID (0 if not applicable).
    gid @9 :UInt32;

    # User name (if stored).
    uname @10 :Text;

    # Group name (if stored).
    gname @11 :Text;

    # Compression method used for this entry.
    compression @12 :CompressionMethod;

    # CRC32 checksum (for zip).
    crc32 @13 :UInt32;

    # SHA256 hash (if computed/verified).
    sha256 @14 :Data;

    # Whether entry is encrypted.
    encrypted @15 :Bool;

    # Encryption algorithm (if encrypted).
    encryptionAlgorithm @16 :Text;

    # Entry offset in archive (for random access).
    offset @17 :UInt64;

    # Extended attributes.
    xattrs @18 :T.StringMap;

    # Backend-specific metadata.
    metadata @19 :T.StringMap;
}

enum CompressionMethod {
    stored @0;           # No compression
    deflate @1;          # Zip deflate
    deflate64 @2;        # Zip deflate64
    bzip2 @3;            # bzip2
    lzma @4;             # LZMA / xz
    lzma2 @5;            # LZMA2
    zstd @6;             # Zstandard
    lz4 @7;              # LZ4
    ppmd @8;             # PPMd
    brotli @9;           # Brotli
    shrunk @10;          # Old compress
    reduced1 @11;        # was: reduced_1
    reduced2 @12;        # was: reduced_2
    reduced3 @13;        # was: reduced_3
    reduced4 @14;        # was: reduced_4
    imploded @15;
    tokenized @16;
    wavpack @17;
    lzip @18;            # Lzip LZMA variant
    xz @19;              # XZ Utils
    lz5 @20;             # LZ5 (LZ4 predecessor)
    lzham @21;           # LZHAM (LZMA-like, high ratio)
    zpaq @22;            # ZPAQ (high compression)
    zstdFast @23;        # was: zstd_fast (Zstandard fast mode)
    zstdHigh @24;        # was: zstd_high (Zstandard high compression)
    flzma @25;           # Fast LZMA
    custom @26;
}

# ─── Requests ────────────────────────────────────────────────────────

struct ListEntriesRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;  # Empty = auto-detect
    # Password for encrypted archives.
    password @2 :Data;
    # Path prefix filter (only entries under this path).
    prefix @3 :Text;
    # Include/exclude patterns (glob-style).
    includePatterns @4 :List(Text);
    excludePatterns @5 :List(Text);
    # Pagination for large archives.
    pagination @6 :T.Pagination;
}

struct ExtractRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;
    password @2 :Data;
    # Destination directory (must exist).
    destination @3 :Text;
    # Preserve file permissions.
    preservePermissions @4 :Bool = true;
    # Preserve timestamps.
    preserveTimestamps @5 :Bool = true;
    # Preserve ownership (requires privilege).
    preserveOwnership @6 :Bool = false;
    # Overwrite existing files.
    overwrite @7 :Bool = true;
    # Skip existing files.
    skipExisting @8 :Bool = false;
    # Path prefix filter.
    prefix @9 :Text;
    # Include/exclude patterns.
    includePatterns @10 :List(Text);
    excludePatterns @11 :List(Text);
    # Strip leading path components (like tar --strip-components).
    stripComponents @12 :UInt32;
    # Operation ID for progress tracking.
    operationId @13 :Text;
    # Parallel extraction hint (0 = auto, 1 = single-threaded).
    parallelism @14 :UInt32 = 0;
    # Enable sparse file extraction (for disk images).
    sparseExtraction @15 :Bool = false;
}

struct ExtractResult {
    success @0 :Bool;
    extractedCount @1 :UInt32;
    failedCount @2 :UInt32;
    errors @3 :List(ExtractError);
    # Total bytes extracted.
    bytesExtracted @4 :UInt64;
    duration @5 :T.Duration;
}

struct ExtractError {
    path @0 :Text;
    error @1 :T.Error;
}

struct ExtractEntryRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;
    password @2 :Data;
    # Entry path within archive.
    entryPath @3 :Text;
    # Output destination.
    union {
        path @4 :Text;           # Write to file
        buffer @5 :T.BufferId;   # Write to buffer
        handle @6 :T.FileHandleId;  # Write to open handle
    }
    # Offset within entry (for partial extraction).
    offset @7 :UInt64;
    # Length to extract (0 = rest of entry).
    length @8 :UInt64;
}

struct ExtractEntryResult {
    union {
        success @0 :ExtractEntrySuccess;
        error @1 :T.Error;
    }
}

struct ExtractEntrySuccess {
    bytesWritten @0 :UInt64;
    entry @1 :ArchiveEntry;
}

struct CompressRequest {
    # Source files/directories to archive.
    sources @0 :List(CompressSource);
    # Destination archive.
    destination @1 :ArchiveDestination;
    format @2 :ArchiveFormat;
    # Default compression level (1-9, 0 = default).
    compressionLevel @3 :UInt8 = 6;
    # Per-format compression method override.
    compressionMethod @4 :CompressionMethod;
    # Password for encryption.
    password @5 :Data;
    # Encryption algorithm.
    encryptionAlgorithm @6 :ArchiveEncryptionAlgorithm;  # Typed enum (was bare Text)
    # Preserve file permissions.
    preservePermissions @7 :Bool = true;
    # Preserve timestamps.
    preserveTimestamps @8 :Bool = true;
    # Follow symlinks (store target, not link).
    followSymlinks @9 :Bool = false;
    # Preserve hardlinks (maintain link relationships).
    preserveHardlinks @14 :Bool = true;
    # Include hidden files.
    includeHidden @10 :Bool = true;
    # Exclude patterns.
    excludePatterns @11 :List(Text);
    # Operation ID for progress tracking.
    operationId @12 :Text;
    # Archive comment.
    comment @13 :Text;
}

struct CompressSource {
    # Source path on filesystem.
    path @0 :Text;
    # Path within archive (relative).
    archivePath @1 :Text;
    # Whether to recurse into directories.
    recursive @2 :Bool = true;
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
    entryCount @2 :UInt32;
    duration @3 :T.Duration;
    errors @4 :List(CompressError);
}

struct CompressError {
    sourcePath @0 :Text;
    error @1 :T.Error;
}

struct AddToArchiveRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;
    password @2 :Data;
    sources @3 :List(CompressSource);
    # Whether to update existing entries.
    update @4 :Bool = false;
    # Whether to only add newer files.
    freshen @5 :Bool = false;
}

struct DeleteFromArchiveRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;
    password @2 :Data;
    # Entry paths to delete.
    entryPaths @3 :List(Text);
}

struct IntegrityResult {
    valid @0 :Bool;
    errors @1 :List(IntegrityError);
    checkedEntries @2 :UInt32;
    duration @3 :T.Duration;
}

struct IntegrityError {
    path @0 :Text;
    error @1 :Text;
    errorType @2 :IntegrityErrorType;
}

enum IntegrityErrorType {
    crcMismatch @0;
    sizeMismatch @1;
    compressionError @2;
    encryptionError @3;
    missingEntry @4;
    extraEntry @5;
    corruptedHeader @6;
    custom @7;
}

struct ArchiveMetadata {
    format @0 :ArchiveFormat;
    formatVersion @1 :Text;
    comment @2 :Text;
    createdBy @3 :Text;          # Tool that created the archive
    createdAt @4 :T.Timestamp;
    entryCount @5 :UInt32;
    totalSize @6 :UInt64;
    compressedSize @7 :UInt64;
    encrypted @8 :Bool;
    encryptionAlgorithm @9 :Text;
    # Format-specific metadata.
    custom @10 :T.StringMap;
}

struct ConvertRequest {
    source @0 :ArchiveSource;
    sourceFormat @1 :ArchiveFormat;
    sourcePassword @2 :Data;
    destination @3 :ArchiveDestination;
    targetFormat @4 :ArchiveFormat;
    targetPassword @5 :Data;
    targetCompressionLevel @6 :UInt8 = 6;
    targetCompressionMethod @7 :CompressionMethod;
    operationId @8 :Text;
}

struct ConvertResult {
    success @0 :Bool;
    sourceSize @1 :UInt64;
    targetSize @2 :UInt64;
    entryCount @3 :UInt32;
    duration @4 :T.Duration;
}

# ─── Streaming Operations ─────────────────────────────────────────

struct CompressStreamRequest {
    format @0 :ArchiveFormat;
    compressionLevel @1 :UInt8 = 6;
    compressionMethod @2 :CompressionMethod;
    password @3 :Data;
    encryptionAlgorithm @4 :Text;
    operationId @5 :Text;
}

struct DecompressStreamRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;
    password @2 :Data;
    entryPath @3 :Text;  # Empty = first entry or stream of entries
    operationId @4 :Text;
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
    password @6 :Data;
    operationId @7 :Text;
}

struct MergeArchivesResult {
    success @0 :Bool;
    totalEntries @1 :UInt32;
    duplicateEntries @2 :UInt32;
    outputSize @3 :UInt64;
    duration @4 :T.Duration;
    errors @5 :List(T.Error);
}

# ─── Split ────────────────────────────────────────────────────────

struct SplitArchiveRequest {
    source @0 :ArchiveSource;
    sourceFormat @1 :ArchiveFormat;
    password @2 :Data;
    destination @3 :Text;  # Directory to write split parts
    partSize @4 :UInt64;   # Size per part in bytes
    naming @5 :SplitNaming;
    operationId @6 :Text;
}

enum SplitNaming {
    sequential @0;    # archive.part000, archive.part001, ...
    numbered @1;      # archive.000, archive.001, ...
    custom @2;
}

struct SplitArchiveResult {
    success @0 :Bool;
    parts @1 :List(SplitPart);
    totalSize @2 :UInt64;
    duration @3 :T.Duration;
}

struct SplitPart {
    path @0 :Text;
    size @1 :UInt64;
    partNumber @2 :UInt32;
}

# ─── Operation Progress ──────────────────────────────────────────────

struct OperationProgress {
    operationId @0 :Text;
    phase @1 :OperationPhase;
    progress @2 :Float32;  # 0.0 - 1.0
    currentFile @3 :Text;
    filesProcessed @4 :UInt32;
    totalFiles @5 :UInt32;
    bytesProcessed @6 :UInt64;
    totalBytes @7 :UInt64;
    elapsed @8 :T.Duration;
    estimatedRemaining @9 :T.Duration;
    errors @10 :List(Text);
    done @11 :Bool;
}

enum OperationPhase {
    initializing @0;
    scanning @1;
    extracting @2;
    compressing @3;
    encrypting @4;
    decrypting @5;
    verifying @6;
    finalizing @7;
    complete @8;
    failed @9;
    repairing @10;
    custom @11;
}

# ─── Typed Encryption Algorithm ───────────────────────────────
# Replaces bare Text in CompressRequest.encryptionAlgorithm.
# Provides type safety for archive encryption.

enum ArchiveEncryptionAlgorithm {
    aes128 @0;        # AES-128
    aes256 @1;        # AES-256
    zipCrypto @2;     # ZipCrypto (weak, legacy)
    tripleDes @3;     # 3DES
    blowfish @4;      # Blowfish
    twofish @5;       # Twofish
    chacha20 @6;      # ChaCha20-Poly1305
    none @7;          # No encryption
    custom @8;
}

# ─── Archive Repair ───────────────────────────────────────────

struct RepairArchiveRequest {
    archive @0 :ArchiveSource;
    format @1 :ArchiveFormat;
    password @2 :Data;
    # Destination for repaired archive.
    destination @3 :ArchiveDestination;
    # Whether to attempt recovery of corrupted entries.
    recoverEntries @4 :Bool = true;
    operationId @5 :Text;
}

struct RepairArchiveResult {
    success @0 :Bool;
    repairedEntries @1 :UInt32;
    unrecoverableEntries @2 :UInt32;
    errors @3 :List(T.Error);
    outputSize @4 :UInt64;
    duration @5 :T.Duration;
}

# ─── Multi-Volume Reading ─────────────────────────────────────

struct ReadSplitArchiveRequest {
    # Directory containing split parts.
    directory @0 :Text;
    # Naming pattern (used to find parts).
    naming @1 :SplitNaming;
    # Password for encrypted archives.
    password @2 :Data;
    # Pagination for large archives.
    pagination @3 :T.Pagination;
}

# ─── Archive Streaming Hash Verification ───────────────────────

struct StreamingHashRequest {
    # Hash algorithm for verification.
    algorithm @0 :HashAlgorithm;
    # Entries to verify.
    entryPaths @1 :List(Text);
}

# ─── Archive Diff ─────────────────────────────────────────────

struct ArchiveDiffRequest {
    sourceA @0 :ArchiveSource;
    formatA @1 :ArchiveFormat;
    passwordA @2 :Data;
    sourceB @3 :ArchiveSource;
    formatB @4 :ArchiveFormat;
    passwordB @5 :Data;
}

struct ArchiveDiffResult {
    entriesAdded @0 :List(ArchiveEntry);
    entriesRemoved @1 :List(ArchiveEntry);
    entriesModified @2 :List(ModifiedEntry);
    identicalEntries @3 :UInt32;
}

struct ModifiedEntry {
    path @0 :Text;
    sizeA @1 :UInt64;
    sizeB @2 :UInt64;
    hashA @3 :Data;
    hashB @4 :Data;
}

struct HashVerificationResult {
    verified @0 :Bool;
    entriesChecked @1 :UInt32;
    entriesMatched @2 :UInt32;
    mismatches @3 :List(HashMismatch);
}

struct HashMismatch {
    path @0 :Text;
    expectedHash @1 :Data;
    actualHash @2 :Data;
}
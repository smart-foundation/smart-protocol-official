@0xa1b2c3d4e5f60003;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Buffer - typed shared-memory buffers for zero-copy data transfer
#
# Provides shared memory allocation, pixel-typed buffers, and ring
# buffers for streaming data. The canonical interface is BufferService
# with a handshake-based session model.
#
# All handles are UInt64 (opaque, backend-assigned). All sizes use T.Size.
# All timestamps use T.Timestamp. All errors use T.Error.
# NOTE: the older flat `Buffer` interface no longer exists — the session
# model (`BufferService` + handshake) replaced it, and this comment is the
# last trace of a migration that is over.
#
# Audit-8 enhancements:
#   - BufferType: gpu, tensor, audio, compressed variants.
#   - BufferSecurity: per-buffer access control, encryption.
#   - BufferCompression: lossless/lossy/adaptive compression.
#   - BufferSync: producer-consumer synchronization primitives.
#   - BufferPool: pre-allocated buffer pools for high-frequency scenarios.
#   - BufferFormatInfo: format capability queries.
#   - BufferService: createPool, convertFormat, zeroBuffer methods.
# ═══════════════════════════════════════════════════════════════════════

interface BufferService {

    # ── Session / handshake ──
    struct HandshakeRequest {
        applicationId @0 :T.AppId;
        version       @1 :T.Version;
        annotations   @2 :List(T.Meta);
        extensions    @3 :T.StringMap;
    }

    struct HandshakeResponse {
        sessionId @0 :T.SessionId;
        result    @1 :HandshakeResult;
        limits    @2 :BufferLimits;
        extensions @3 :T.StringMap;
    }

    enum HandshakeResult {
        accepted @0;
        rejected @1;
        custom @2;
    }

    handshake @0 (request :HandshakeRequest)
              -> (response :HandshakeResponse);

    # ── Shared memory regions ──
    allocateSharedMemory @1 (size :UInt64, name :Text)
                           -> (result :SharedMemoryResult);
    releaseSharedMemory  @2 (handle :UInt64) -> T.VoidResult;
    resizeSharedMemory   @3 (handle :UInt64, newSize :UInt64)
                           -> (result :SharedMemoryResult);

    # ── Pixel-typed buffers ──
    createBuffer  @4 (request :BufferRequest)
                    -> (result :BufferResult);
    destroyBuffer @5 (handle :UInt64) -> T.VoidResult;

    # ── Ring buffers (for streaming) ──
    createRingBuffer  @6 (request :RingBufferRequest)
                        -> (result :RingBufferResult);
    destroyRingBuffer @7 (handle :UInt64) -> T.VoidResult;

    # ── Read-back ──
    getBufferInfo @8 (handle :UInt64) -> (result :BufferInfoResult);

    # ── Queries (extensible) ──
    query @9 (query :BufferQuery) -> (result :BufferQueryResult);

    # ── Subscription for buffer events ──
    subscribe @10 () -> (subscription :BufferSubscription);
    pull @11 (subscription :BufferSubscription) -> (events :List(BufferEvent));
    cancel @12 (subscription :BufferSubscription) -> T.VoidResult;

    # ── Audit-8: Buffer pool management ──
    createPool @13 (request :BufferPoolRequest) -> (result :BufferPoolResult);
    destroyPool @14 (poolId :UInt64) -> T.VoidResult;
    getPoolInfo @15 (poolId :UInt64) -> (info :BufferPoolInfo);
    allocateFromPool @16 (poolId :UInt64) -> (result :BufferResult);
    returnToPool @17 (poolId :UInt64, handle :UInt64) -> T.VoidResult;

    # ── Audit-8: Buffer operations ──
    convertFormat @18 (handle :UInt64, targetFormat :T.PixelFormat) -> (result :BufferResult);
    zeroBuffer @19 (handle :UInt64) -> T.VoidResult;
    queryFormatSupport @20 (format :T.PixelFormat) -> (info :BufferFormatInfo);

    # ── Audit-9: GPU and Tensor buffer info ──
    getGpuBufferInfo @21 (handle :UInt64) -> (info :GpuBufferInfo);
    getTensorBufferInfo @22 (handle :UInt64) -> (info :TensorBufferInfo);
    getBufferStatistics @23 (poolId :UInt64) -> (stats :BufferStatistics);

    # ── Audit-9: Cross-device DMA sharing ──
    exportDmaBuffer @24 (handle :UInt64) -> (info :DmaBufferInfo);
    importDmaBuffer @25 (dmaHandle :DmaBufferHandle) -> (handle :UInt64);
    listDmaExports @26 (pagination :T.Pagination) -> (exports :List(DmaBufferInfo), total :UInt64);

    # ── Audit-9: Buffer migration/eviction ──
    migrateBuffer @27 (request :BufferMigrationRequest) -> (result :BufferMigrationResult);
    evictBuffer @28 (handle :UInt64) -> T.VoidResult;

    # ── Audit-9: Buffer conversion pipeline ──
    createConversionPipeline @29 (pipeline :ConversionPipeline) -> (pipelineId :UInt64);
    runConversionPipeline @30 (pipelineId :UInt64, inputHandle :UInt64) -> (result :BufferResult);
    destroyConversionPipeline @31 (pipelineId :UInt64) -> T.VoidResult;

    # ── Audit-9: Cross-process buffer sharing ──
    exportBufferToProcess @32 (request :BufferExportRequest) -> (result :BufferExportResult);
    importBufferFromProcess @33 (exportedHandle :UInt64) -> (handle :UInt64);

    # ── Audit-10: Buffer prefetch/hint ──
    prefetchBuffer @34 (handle :UInt64, hint :BufferAccessHint) -> T.VoidResult;
    adviseBuffer @35 (handles :List(UInt64), advice :BufferAdvice) -> T.VoidResult;

    # ── Audit-10: Buffer overcommit ──
    setOvercommitConfig @36 (config :BufferOvercommitConfig) -> T.VoidResult;
    getOvercommitConfig @37 () -> (config :BufferOvercommitConfig);

    # ── Audit-10: Multi-GPU peer-to-peer transfer ──
    initiatePeerTransfer @38 (handle :UInt64, targetDevice :UInt32) -> (transferId :UInt64);
    queryPeerTransferStatus @39 (transferId :UInt64) -> (status :PeerTransferStatus);
    waitPeerTransfer @40 (transferId :UInt64, timeout :T.Duration) -> T.VoidResult;
}

# ── Buffer Access Hint (Audit-10) ────────────────────────────────────────
# Hints to the operating system about upcoming buffer access patterns.
# Used to prefetch pages and configure page caching policy.
struct BufferAccessHint {
    # Temporal locality: how soon the buffer will be accessed.
    temporalLocality @0 :TemporalLocality;
    # Expected access pattern.
    accessPattern @1 :AccessPattern;
    # Expected first access time offset from now.
    firstAccessOffset @2 :T.Duration;
    # Expected access count.
    accessCount @3 :UInt32;
}

enum TemporalLocality {
    none @0;         # Will not be accessed soon
    low @1;          # Will be accessed eventually
    medium @2;       # Will be accessed soon
    high @3;         # Will be accessed immediately
}

enum AccessPattern {
    sequential @0;   # Sequential read or write
    random @1;        # Random access
    writeOnce @2;     # Written once, read many times
    readOnce @3;      # Read once, not reused
}

# Access INTENT, not madvise names: a capability runtime has no
# MADV_SEQUENTIAL, and `dontFork` presumed fork() exists. The spellings
# below are what the advice MEANS, so a backend maps them onto whatever
# it has.
enum BufferAdvice {
    unspecified @0;     # No specific advice
    sequential @1;      # Expect sequential access
    random @2;          # Expect random access
    willNeed @3;        # Will need this buffer soon
    doneWith @4;        # Will not need this buffer
    remove @5;          # This region is no longer needed
    merge @6;           # Hint to merge with adjacent mappings
    unmerge @7;         # Hint to unmerge from adjacent mappings
    # The remaining Linux memory-management vocabulary (dontFork,
    # hwpoison, softDirty) is gone: it describes kernel internals a
    # consumer cannot act on portably.
    custom @8;
}

# ── Buffer Overcommit (Audit-10) ─────────────────────────────────────────
# Configure buffer memory overcommit behavior for memory-constrained
# environments. Overcommit allows allocating more buffer memory than
# physically available.
struct BufferOvercommitConfig {
    enabled @0 :Bool;
    # Maximum ratio of allocated bytes to available physical memory.
    # E.g., 1.5 = allocate up to 150% of available memory.
    maxOvercommitRatio @1 :Float32;
    # Hard limit on total allocated bytes (0 = no limit).
    hardLimitBytes @2 :UInt64;
    # What to do when overcommit limit is reached.
    onLimitReached @3 :OvercommitAction;
}

enum OvercommitAction {
    fail @0;            # Return error on allocation
    evict @1;           # Evict existing buffers first
    block @2;           # Block until memory available
}

# ── Peer Transfer Status (Audit-10) ─────────────────────────────────────
# Tracks the status of a peer-to-peer GPU buffer transfer.
struct PeerTransferStatus {
    transferId @0 :UInt64;
    sourceDevice @1 :UInt32;
    targetDevice @2 :UInt32;
    bytesTransferred @3 :UInt64;
    totalBytes @4 :UInt64;
    state @5 :TransferState;
    startedAt @6 :T.Timestamp;
    completedAt @7 :T.Timestamp;
}

enum TransferState {
    pending @0;
    inProgress @1;
    completed @2;
    failed @3;
    cancelled @4;
}

# ── Limits (advertised once at handshake) ──
struct BufferLimits {
    maxSize @0 :T.Size;
    maxBuffers @1 :UInt32;
    strideAlignment @2 :UInt32;
    maxRegions @3 :UInt32;
    maxTotalBytes @4 :UInt64;
    maxDimension @5 :UInt32;
}

# ── Buffer variants (extensible) ──
enum BufferType {
    simple @0;
    ring @1;
    sharedMemory @2;
    custom @3;
    # Audit-8 additions:
    gpu @4;
    tensor @5;
    audio @6;
    compressed @7;
}

# ── Region (an allocated span of memory) ──
struct SharedMemoryResult {
    union {
        sharedMemory @0 :SharedMemoryRegion;
        error        @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct SharedMemoryRegion {
    handle @0 :UInt64;
    size   @1 :UInt64;
    offset @2 :UInt64;
    name   @3 :Text;
    # Optional alignment requirement when mapping.
    alignment @4 :UInt32;
    # Optional cache-coherence hint.
    cache @5 :CacheMode;
    metadata @6 :T.StringMap;
}

enum CacheMode {
    defaultCached @0;
    writeBack @1;
    writeThrough @2;
    uncacheable @3;
    custom @4;
}

# ── Pixel-typed buffer request/result ──
struct BufferRequest {
    sharedMemoryHandle @0 :UInt64;
    offset             @1 :UInt64;
    width              @2 :UInt32;
    height             @3 :UInt32;
    stride             @4 :UInt32;
    format             @5 :T.PixelFormat;
    # Audit-8: compression preference for this buffer.
    compression        @6 :BufferCompression;
    # Audit-8: security requirements for this buffer.
    security           @7 :BufferSecurity;
    metadata @8 :T.StringMap;
}

struct BufferResult {
    union {
        buffer @0 :BufferInformation;
        error  @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct BufferInformation {
    handle             @0 :UInt64;
    sharedMemoryHandle @1 :UInt64;
    offset             @2 :UInt64;
    width              @3 :UInt32;
    height             @4 :UInt32;
    stride             @5 :UInt32;
    format             @6 :T.PixelFormat;
    sizeInBytes        @7 :UInt64;
    type               @8 :BufferType;
    # Server-side time this buffer was created.
    createdAt          @9 :T.Timestamp;
    # Last access (writer) — useful for cache eviction.
    lastWriteAt        @10 :T.Timestamp;
    # Buffer age since last write.
    idleDuration       @11 :T.Duration;
    # Audit-8: access control for this buffer.
    security           @12 :BufferSecurity;
    # Audit-8: compression applied to this buffer.
    compression        @13 :BufferCompression;
    # Audit-8: synchronization primitive for producer-consumer.
    sync               @14 :BufferSync;
    metadata @15 :T.StringMap;
}

# ── Ring buffers ──
struct RingBufferRequest {
    sharedMemoryHandle @0 :UInt64;
    bufferCount        @1 :UInt8;
    width              @2 :UInt32;
    height             @3 :UInt32;
    stride             @4 :UInt32;
    format             @5 :T.PixelFormat;
    # Semantics for which end writes / reads.
    mode               @6 :RingMode;
}

enum RingMode {
    producerProducer @0;
    producerConsumer @1;
    consumerConsumer @2;
    custom @3;
}

struct RingBufferResult {
    union {
        ringBuffer @0 :RingBufferInformation;
        error      @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct RingBufferInformation {
    handle             @0 :UInt64;
    sharedMemoryHandle @1 :UInt64;
    bufferSize         @2 :UInt64;
    totalSize          @3 :UInt64;
    bufferCount        @4 :UInt8;
    buffers            @5 :List(BufferInformation);
    mode               @6 :RingMode;
    # Current fill level (0.0 - 1.0).
    fillLevel          @7 :Float32;
    metadata @8 :T.StringMap;
}

# ── Queries ──
struct BufferInfoResult {
    union {
        info  @0 :BufferInformation;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

# Queries answerable by ANY backend. The previous union mixed three
# addressing regimes: global questions, buffer-id questions, and a
# display-shaped `formats :T.OutputId` (a headless backend could not
# answer its own query), plus a `testPattern` whose result type said
# nothing about the contract. Both are gone.
struct BufferQuery {
    union {
        sharedMemoryUsage @0 :Void;
        maxBuffers        @1 :Void;
        custom            @2 :CustomBufferQuery;
        ringFill          @3 :UInt64;
    }
}

struct CustomBufferQuery {
    name       @0 :Text;
    parameters @1 :List(T.Meta);
    metadata @2 :T.StringMap;
}

struct BufferQueryResult {
    union {
        sharedMemoryUsage @0 :SharedMemoryUsage;
        maxBuffers        @1 :UInt8;
        formats           @2 :List(T.PixelFormat);
        custom            @3 :List(T.Meta);
        notSupported      @4 :Void;
        ringFill          @5 :SharedMemoryUsage;
        testPattern       @6 :T.PixelFormat;
    }
}

struct SharedMemoryUsage {
    allocatedBytes @0 :UInt64;
    usedBytes      @1 :UInt64;
    regionCount    @2 :UInt32;
}

# ── Events ──
interface BufferSubscription {
    # Deprecated: use pullPaginated for bounded results.
    pull @0 () -> (events :List(BufferEvent));
    cancel @1 () -> T.VoidResult;
    # Paginated pull — returns at most `limit` events starting from `offset`.
    pullPaginated @2 (pagination :T.Pagination) -> (result :BufferPullResult);
}

struct BufferPullResult {
    events    @0 :List(BufferEvent);
    totalCount @1 :UInt32;
    metadata @2 :T.StringMap;
}

struct BufferEvent {
    union {
        bufferCreated @0 :BufferInformation;
        bufferDestroyed @1 :UInt64;
        bufferResized @2 :BufferResizeEvent;
        sharedMemoryAllocated @3 :SharedMemoryRegion;
        sharedMemoryReleased @4 :UInt64;
        error @5 :T.Error;
        # The forward-compatibility slot every other event union in the
        # protocol carries. Without it, a backend cannot emit a future
        # buffer event without a schema change, and consumers'
        # exhaustive switches are a fork waiting to happen.
        unknown @6 :T.UnknownEvent;
    }
}

struct BufferResizeEvent {
    handle @0 :UInt64;
    previousSize @1 :T.Size;
    currentSize @2 :T.Size;
}

# ════════════════════════════════════════════════════════════════════════
# Audit-8 additions: buffer security, compression, synchronization,
# pool management, and format conversion.
# Audit-9 additions: GPU buffer info, tensor buffer info.
# ════════════════════════════════════════════════════════════════════════

# ── Buffer Security ────────────────────────────────────────────────────
# Access control for buffer contents. Determines who can read/write
# a buffer. Essential for DRM, secure video, and sensitive data.
struct BufferSecurity {
    readable @0 :Bool;
    writable @1 :Bool;
    encrypted @2 :Bool;
    secureAlloc @3 :Bool;
    # Audit-9: encryption key identifier for at-rest encryption.
    encryptionKeyId @4 :Text;
    # Audit-9: encryption algorithm (e.g., "AES-256-GCM", "ChaCha20-Poly1305").
    encryptionAlgorithm @5 :Text;
    metadata @6 :T.StringMap;
}

# ── Buffer Compression ─────────────────────────────────────────────────
# Compression applied to buffer content. Mobile GPUs use AFBC/UBWC;
# storage compression reduces memory pressure.
enum BufferCompression {
    none @0;
    lossless @1;
    lossy @2;
    adaptive @3;
    custom @4;
}

# ── Buffer Synchronization ─────────────────────────────────────────────
# Producer-consumer synchronization primitive. Prevents reading
# a buffer while it is being written (torn reads).
struct BufferSync {
    producerFence @0 :UInt64;
    consumerFence @1 :UInt64;
    signaled @2 :Bool;
}

# ── Buffer Pool ────────────────────────────────────────────────────────
# Pre-allocated buffer pool for high-frequency allocation scenarios
# (video decode, camera preview). Eliminates per-frame allocation overhead.
struct BufferPoolRequest {
    bufferWidth @0 :UInt32;
    bufferHeight @1 :UInt32;
    format @2 :T.PixelFormat;
    count @3 :UInt8;
    type @4 :BufferType;
    name @5 :Text;
    metadata @6 :T.StringMap;
}

struct BufferPoolResult {
    union {
        pool @0 :BufferPoolInfo;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct BufferPoolInfo {
    poolId @0 :UInt64;
    name @1 :Text;
    bufferCount @2 :UInt8;
    freeCount @3 :UInt8;
    buffers @4 :List(BufferInformation);
    metadata @5 :T.StringMap;
}

# ── Buffer Format Info ─────────────────────────────────────────────────
# Describes supported formats with capabilities (compression, tiling,
# swizzle). Enables format negotiation before buffer allocation.
struct BufferFormatInfo {
    format @0 :T.PixelFormat;
    supported @1 :Bool;
    compression @2 :List(BufferCompression);
    maxDimension @3 :UInt32;
    strideAlignment @4 :UInt32;
}

# ── GPU Buffer Info (Audit-9) ──────────────────────────────────────────
# GPU-specific metadata for BufferType.gpu. Describes GPU-local
# allocation, memory heap, and cross-device sharing capabilities.
struct GpuBufferInfo {
    # GPU device ID that owns this buffer.
    deviceId @0 :UInt32;
    # GPU memory heap (e.g., "device", "host", "shared").
    heap @1 :Text;
    # Size of GPU-local allocation in bytes.
    gpuAllocSize @2 :UInt64;
    # Whether this buffer is CPU-accessible.
    cpuAccessible @3 :Bool;
    # Cache-coherency domain.
    coherencyDomain @4 :Text;
    # Supported access flags (read, write, execute).
    accessFlags @5 :UInt32;
    metadata @6 :T.StringMap;
}

# ── Tensor Buffer Info (Audit-9) ───────────────────────────────────────
# Tensor-specific metadata for BufferType.tensor. Describes shape,
# dtype, strides, and layout for AI/ML tensor buffers.
struct TensorBufferInfo {
    # Element datatype (e.g., "float32", "int8", "float16").
    dtype @0 :Text;
    # Number of dimensions.
    ndim @1 :UInt32;
    # Per-dimension size.
    shape @2 :List(UInt32);
    # Per-dimension stride in elements.
    strides @3 :List(UInt32);
    # Memory layout (e.g., "row-major", "channel-first", "channel-last").
    layout @4 :Text;
    # Whether this tensor is a view into another buffer.
    isView @5 :Bool;
    metadata @6 :T.StringMap;
}

# ── Buffer Statistics (Audit-9) ───────────────────────────────────────
# Allocation history and fragmentation metrics for a buffer pool
# or the entire buffer service. Used for capacity planning.
struct BufferStatistics {
    totalAllocations @0 :UInt64;
    totalBytesAllocated @1 :UInt64;
    currentBytesUsed @2 :UInt64;
    peakBytesUsed @3 :UInt64;
    allocationFailures @4 :UInt64;
    fragmentationPercent @5 :Float32;
    poolUtilization @6 :Float32;
}

# ── Cross-Device DMA Sharing (Audit-9) ─────────────────────────────────
# DMA-BUF-compatible buffer sharing across hardware blocks.
# Enables zero-copy buffer passing between camera, display, GPU, and
# video decoder without CPU intervention.
struct DmaBufferHandle {
    # Opaque, backend-decoded DMA handle token.
    #
    # This used to be `fd :Int32`. A file descriptor is a per-process
    # table index: the NUMBER is meaningless in the receiving process
    # (dma-buf sharing passes the descriptor itself, not the integer),
    # and a browser or Windows backend has no fd at all. The token lets
    # each backend carry the handle the way its platform does; the
    # passing mechanism is a backend detail, which is where it belongs.
    token @0 :Data;
    # Size of the DMA buffer in bytes.
    size @1 :UInt64;
    # Open-flag tokens for this export (e.g., "read", "write").
    flags @2 :List(Text);
    metadata @3 :T.StringMap;
}

struct DmaBufferInfo {
    handle @0 :UInt64;
    dmaHandle @1 :DmaBufferHandle;
    # Hardware blocks that can import this buffer.
    exportableTo @2 :List(Text);
    # Cache-coherency mode.
    cacheMode @3 :CacheMode;
    # allocation timestamp for lifetime tracking.
    createdAt @4 :T.Timestamp;
    metadata @5 :T.StringMap;
}

# ── Buffer Migration (Audit-9) ─────────────────────────────────────────
# Move buffers between memory regions (e.g., system RAM to GPU VRAM)
# or evict them under memory pressure.
struct BufferMigrationRequest {
    handle @0 :UInt64;
    # Target memory region (e.g., "system", "gpu-vram", "dmabuf").
    targetRegion @1 :Text;
    # Whether to copy (false) or move (true) the buffer.
    copyOnly @2 :Bool;
    metadata @3 :T.StringMap;
}

struct BufferMigrationResult {
    union {
        success @0 :BufferInformation;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

# ── Buffer Conversion Pipeline (Audit-9) ───────────────────────────────
# Chain multiple format conversions for complex transcoding pipelines.
struct ConversionStep {
    # Source format for this step.
    sourceFormat @0 :T.PixelFormat;
    # Target format for this step.
    targetFormat @1 :T.PixelFormat;
    # Hardware accelerator to use (e.g., "gpu", "vdpau", "vaapi").
    accelerator @2 :Text;
    metadata @3 :T.StringMap;
}

struct ConversionPipeline {
    steps @0 :List(ConversionStep);
    # Whether to perform conversions in-place (reduces memory usage).
    inPlace @1 :Bool;
    metadata @2 :T.StringMap;
}

# ── Cross-Process Buffer Sharing (Audit-9) ─────────────────────────────
# Export a buffer handle to another process for zero-copy IPC.
struct BufferExportRequest {
    handle @0 :UInt64;
    targetProcessId @1 :T.ProcessId;
    # Access permissions for the receiving process.
    readable @2 :Bool;
    writable @3 :Bool;
}

struct BufferExportResult {
    union {
        exportedHandle @0 :UInt64;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

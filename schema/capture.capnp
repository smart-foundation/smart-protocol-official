@0xa1b2c3d4e5f60014;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Capture - screen, window, output capture with streaming and archival.
#
# Improvements beyond the original schema:
#   - CaptureId typed ID for all capture references.
#   - OutputId/WindowId/AppId typed for source identification.
#   - T.Pagination on listCaptures, getSources.
#   - Subscription cancel method added.
#   - T.Duration for capture duration.
#   - T.DataHandle for captured data (may exceed 1KB).
#   - Custom variant on CaptureEventType for forward compatibility.
#
# Audit-8 enhancements:
#   - CaptureRegion: typed region for partial screen capture.
#   - AudioCaptureConfig: audio capture alongside video.
#   - WatermarkRequest: programmatic watermarking during capture.
#   - CaptureScheduleRequest: scheduled/time-lapse capture.
#   - CaptureStream: continuous streaming handle.
#   - CaptureThumbnail: low-resolution preview.
#   - CaptureDeduplication: duplicate detection strategy.
#   - RetentionPolicy: auto-deletion and archival rules.
# ═══════════════════════════════════════════════════════════════════════

interface CaptureService {
    captureOutput @0 (outputId :T.OutputId, format :CaptureFormat) -> (captureId :T.CaptureId, data :T.DataHandle);
    captureWindow @1 (windowId :T.WindowId, format :CaptureFormat) -> (captureId :T.CaptureId, data :T.DataHandle);
    captureScreen @2 (format :CaptureFormat) -> (captureId :T.CaptureId, data :T.DataHandle);

    startRecording @3 (source :CaptureSourceRef, format :CaptureFormat) -> (captureId :T.CaptureId);
    stopRecording @4 (captureId :T.CaptureId) -> (data :T.DataHandle);
    pauseRecording @5 (captureId :T.CaptureId) -> T.VoidResult;
    resumeRecording @6 (captureId :T.CaptureId) -> T.VoidResult;

    listCaptures @7 (pagination :T.Pagination) -> (captures :List(CaptureInfo), totalCount :UInt32);
    getCapture @8 (captureId :T.CaptureId) -> (info :CaptureInfo);

    getSources @9 (pagination :T.Pagination) -> (sources :List(CaptureSourceRef), totalCount :UInt32);

    subscribeEvents @10 () -> (subscription :CaptureEventSubscription);

    # -- Audit-8: Region capture --
    captureRegion @11 (outputId :T.OutputId, region :CaptureRegion, format :CaptureFormat)
                  -> (captureId :T.CaptureId, data :T.DataHandle);

    # -- Audit-8: Continuous streaming --
    startStream @12 (source :CaptureSourceRef, format :CaptureFormat)
                -> (streamId :T.CaptureId);
    stopStream @13 (streamId :T.CaptureId) -> T.VoidResult;

    # -- Audit-8: Scheduled capture --
    scheduleCapture @14 (request :CaptureScheduleRequest) -> (scheduleId :UInt64);
    cancelSchedule @15 (scheduleId :UInt64) -> T.VoidResult;

    # -- Audit-8: Archive capture --
    archiveCapture @16 (captureId :T.CaptureId, policy :RetentionPolicy) -> T.VoidResult;

    # -- Audit-9: Capture pipeline --
    createPipeline @17 (pipeline :CapturePipeline) -> (pipelineId :UInt64);
    applyPipeline @18 (captureId :T.CaptureId, pipelineId :UInt64) -> (processed :T.CaptureId);
    listPipelines @19 (pagination :T.Pagination) -> (pipelines :List(CapturePipeline), total :UInt32);

    # -- Audit-9: Capture session management --
    createSession @20 (name :Text, sources :List(CaptureSourceRef), format :CaptureFormat)
                  -> (session :CaptureSession);
    stopSession @21 (sessionId :UInt64) -> T.VoidResult;
    pauseSession @22 (sessionId :UInt64) -> T.VoidResult;
    resumeSession @23 (sessionId :UInt64) -> T.VoidResult;
    listSessions @24 (pagination :T.Pagination) -> (sessions :List(CaptureSession), total :UInt32);

    # -- Audit-9: Capture content analysis --
    analyzeCapture @25 (captureId :T.CaptureId) -> (analysis :CaptureAnalysis);

    # -- Audit-9: Capture permission model --
    setCapturePermission @26 (permission :CapturePermission) -> T.VoidResult;
    getCapturePermission @27 (appId :T.AppId) -> (permission :CapturePermission);

    # -- Audit-9: Capture sharing --
    shareCapture @28 (request :CaptureShareRequest) -> (shareLink :T.Uri);

    # -- Audit-9: Capture annotation --
    addAnnotation @29 (annotation :CaptureAnnotation) -> (annotationId :UInt64);
    listAnnotations @30 (captureId :T.CaptureId) -> (annotations :List(CaptureAnnotation));
    removeAnnotation @31 (annotationId :UInt64) -> T.VoidResult;

    # -- Audit-9: Capture comparison --
    compareCaptures @32 (captureIdA :T.CaptureId, captureIdB :T.CaptureId)
                    -> (comparison :CaptureComparison);

    # -- Audit-9: Batch capture --
    batchCapture @33 (sources :List(CaptureSourceRef), format :CaptureFormat)
                 -> (captureIds :List(T.CaptureId));

    # -- Audit-9: Format negotiation --
    negotiateFormat @34 (source :CaptureSourceRef, desired :CaptureFormat)
                    -> (result :FormatNegotiationResult);
}

interface CaptureEventSubscription {
    # Deprecated: use pullPaginated for bounded results.
    pull @0 () -> (events :List(CaptureEvent));
    cancel @1 () -> T.VoidResult;
    # Paginated pull — returns at most `limit` events starting from `offset`.
    pullPaginated @2 (pagination :T.Pagination) -> (result :CaptureEventPullResult);
}

struct CaptureEventPullResult {
    events    @0 :List(CaptureEvent);
    totalCount @1 :UInt32;
}

struct CaptureFormat {
    format @0 :T.PixelFormat;
    width @1 :UInt32;
    height @2 :UInt32;
    frameRate @3 :T.FrameRate;
    quality @4 :UInt8;          # 0-100, backend maps to internal quality scale
    # Audit-8: region of interest for partial capture.
    region @5 :CaptureRegion;
    # Audit-8: audio capture configuration.
    audio @6 :AudioCaptureConfig;
    # Audit-8: watermark to apply during capture.
    watermark @7 :WatermarkRequest;
    # Audit-8: whether to include cursor in capture.
    cursor @8 :Bool;
}

# Typed union replacing the old enum + raw sourceId pattern.
# Carries both the source type and the specific entity identifier.
struct CaptureSourceRef {
    union {
        screen @0 :Void;              # Default/full screen capture
        window @1 :T.WindowId;        # Specific window by ID
        output @2 :T.OutputId;        # Specific output/display by ID
        application @3 :T.AppId;      # Specific application by ID
        custom @4 :Text;              # Backend-specific source reference
        # Audit-8 additions:
        region @5 :CaptureRegion;     # Capture a specific rectangle/region
        process @6 :Text;             # Capture by process name/identifier
    }
}

struct CaptureInfo {
    id @0 :T.CaptureId;
    source @1 :CaptureSourceRef;  # What was captured (type + entity ID)
    format @2 :CaptureFormat;
    active @3 :Bool;
    startedAt @4 :T.Timestamp;
    duration @5 :T.Duration;      # How long the capture has been active
    # Audit-8 additions:
    region @6 :CaptureRegion;     # Region that was captured
    audioCaptured @7 :Bool;       # Whether audio was captured alongside video
    encrypted @8 :Bool;           # Whether capture is encrypted
    thumbnail @9 :CaptureThumbnail;  # Low-resolution preview
}

struct CaptureEvent {
    id @0 :T.EventId;
    timestamp @1 :T.Timestamp;
    captureId @2 :T.CaptureId;
    type @3 :CaptureEventType;
}

enum CaptureEventType {
    started @0;
    stopped @1;
    paused @2;
    resumed @3;
    error @4;
    custom @5;
}

# ════════════════════════════════════════════════════════════════════════
# Audit-8 additions: region capture, audio capture, watermarking,
# scheduling, streaming, thumbnails, deduplication, archival.
# ════════════════════════════════════════════════════════════════════════

# ── Capture Region ─────────────────────────────────────────────────────
# Typed region for partial screen/window capture. Replaces full-screen
# capture with precise rectangle specification.
struct CaptureRegion {
    x @0 :UInt32;
    y @1 :UInt32;
    width @2 :UInt32;
    height @3 :UInt32;
}

# ── Audio Capture Config ───────────────────────────────────────────────
# Configuration for audio capture alongside video. Sample rate, channel
# count, and codec selection for captured audio.
struct AudioCaptureConfig {
    sampleRate @0 :UInt32;
    channels @1 :UInt8;
    codec @2 :Text;
}

# ── Watermark Request ──────────────────────────────────────────────────
# Programmatic watermarking during capture. Supports text and image
# watermarks with position and opacity control.
struct WatermarkRequest {
    text @0 :Text;
    imageUri @1 :Text;
    position @2 :WatermarkPosition;
    opacity @3 :Float32;
}

enum WatermarkPosition {
    topLeft @0;
    topRight @1;
    bottomLeft @2;
    bottomRight @3;
    center @4;
    custom @5;
}

# ── Capture Schedule ───────────────────────────────────────────────────
# Scheduled capture configuration for time-lapse, periodic monitoring,
# or delayed capture.
struct CaptureScheduleRequest {
    source @0 :CaptureSourceRef;
    format @1 :CaptureFormat;
    interval @2 :T.Duration;
    maxCaptures @3 :UInt32;
    startTime @4 :T.Timestamp;
    endTime @5 :T.Timestamp;
}

# ── Capture Stream ─────────────────────────────────────────────────────
# Continuous streaming handle for real-time capture delivery.
# Returned by startStream; consumers read from the stream handle.
struct CaptureStream {
    streamId @0 :T.CaptureId;
    source @1 :CaptureSourceRef;
    format @2 :CaptureFormat;
    startedAt @3 :T.Timestamp;
}

# ── Capture Thumbnail ──────────────────────────────────────────────────
# Low-resolution preview of a capture. Used for rapid visual browsing
# without loading full-resolution capture data.
struct CaptureThumbnail {
    width @0 :UInt32;
    height @1 :UInt32;
    data @2 :T.DataHandle;
}

# ── Capture Deduplication ──────────────────────────────────────────────
# Strategy for detecting duplicate captures to save storage.
enum CaptureDeduplication {
    none @0;
    hash @1;
    perceptual @2;
    custom @3;
}

# ── Retention Policy ───────────────────────────────────────────────────
# Rules for auto-deletion and archival of captures. Governs storage
# lifecycle to prevent unbounded growth.
struct RetentionPolicy {
    maxAge @0 :T.Duration;
    maxCount @1 :UInt32;
    maxSizeBytes @2 :UInt64;
    archiveAfter @3 :T.Duration;
}

# ════════════════════════════════════════════════════════════════════════
# Audit-9 additions: capture pipeline, session management, content
# analysis, permission model, sharing, annotation, comparison,
# compression options, device metadata, batch operations, format
# negotiation.
# ════════════════════════════════════════════════════════════════════════

# ── Capture Pipeline ───────────────────────────────────────────────────
# Defines a processing pipeline for captured content. Each stage
# applies a transformation (filter, encode, watermark, compress)
# in sequence before final delivery.
struct CapturePipeline {
    # Unique pipeline identifier.
    pipelineId @0 :UInt64;
    # Human-readable name for this pipeline.
    name @1 :Text;
    # Ordered list of processing stages.
    stages @2 :List(PipelineStage);
    # Whether this pipeline is enabled.
    enabled @3 :Bool;
}

struct PipelineStage {
    # Order in the pipeline (lower = earlier).
    order @0 :UInt32;
    # Stage type identifier (e.g., "filter", "encode", "watermark").
    type @1 :Text;
    # Stage-specific parameters.
    parameters @2 :T.StringMap;
    # Whether this stage is enabled.
    enabled @3 :Bool;
}

# ── Capture Session ────────────────────────────────────────────────────
# Manages multiple concurrent captures as a single session. Enables
# atomic start/stop/pause of grouped captures.
struct CaptureSession {
    sessionId @0 :UInt64;
    name @1 :Text;
    # Capture IDs belonging to this session.
    captureIds @2 :List(T.CaptureId);
    startedAt @3 :T.Timestamp;
    active @4 :Bool;
}

# ── Capture Content Analysis ───────────────────────────────────────────
# On-device analysis of captured content. Provides OCR text extraction,
# object detection, and face detection results for captured images.
struct CaptureAnalysis {
    captureId @0 :T.CaptureId;
    # Extracted text from OCR.
    ocrText @1 :Text;
    # Detected objects in the capture.
    objects @2 :List(CapturedObject);
    # Detected faces in the capture.
    faces @3 :List(CapturedFace);
    # Scene classification label.
    sceneLabel @4 :Text;
    # Confidence of the scene classification.
    sceneConfidence @5 :Float32;
}

struct CapturedObject {
    label @0 :Text;
    confidence @1 :Float32;
    x @2 :UInt32;
    y @3 :UInt32;
    width @4 :UInt32;
    height @5 :UInt32;
}

struct CapturedFace {
    faceId @0 :UInt32;
    x @1 :UInt32;
    y @2 :UInt32;
    width @3 :UInt32;
    height @4 :UInt32;
    confidence @5 :Float32;
}

# ── Capture Permission Model ───────────────────────────────────────────
# Structured permission for controlling who can capture what.
# Defines capture access at source, output, and time granularity.
struct CapturePermission {
    # App requesting capture permission.
    appId @0 :T.AppId;
    # Sources this app is allowed to capture from.
    allowedSources @1 :List(CaptureSourceRef);
    # Maximum capture duration allowed.
    maxDuration @2 :T.Duration;
    # Whether audio capture is permitted.
    audioAllowed @3 :Bool;
    # Whether screen capture is permitted.
    screenAllowed @4 :Bool;
    # Whether window capture is permitted.
    windowAllowed @5 :Bool;
}

# ── Capture Sharing ────────────────────────────────────────────────────
# Share captured content with other apps or devices. Provides
# structured sharing with target selection and format control.
struct CaptureShareRequest {
    captureId @0 :T.CaptureId;
    # Target device or app to share with.
    targetDeviceId @1 :T.DeviceId;
    # Target app to share with (alternative to device).
    targetAppId @2 :T.AppId;
    # Desired format for shared content.
    format @3 :T.PixelFormat;
    # Whether to include metadata in the share.
    includeMetadata @4 :Bool;
}

# ── Capture Annotation ─────────────────────────────────────────────────
# Annotation overlay on captured content. Supports text labels,
# drawings, highlights, and arrows for markup workflows.
struct CaptureAnnotation {
    annotationId @0 :UInt64;
    captureId @1 :T.CaptureId;
    type @2 :AnnotationType;
    # Position on the capture (normalized 0.0–1.0).
    x @3 :Float32;
    y @4 :Float32;
    # Width/height (normalized 0.0–1.0, for rectangles/arrows).
    width @5 :Float32;
    height @6 :Float32;
    # Text content (for text annotations).
    text @7 :Text;
    # Color of the annotation.
    color @8 :T.Color;
    # Author of the annotation.
    author @9 :T.AppId;
    createdAt @10 :T.Timestamp;
}

enum AnnotationType {
    text @0;
    arrow @1;
    rectangle @2;
    circle @3;
    highlight @4;
    freehand @5;
    blur @6;
    custom @7;
}

# ── Capture Comparison ─────────────────────────────────────────────────
# Compare two captures for similarity or diff. Useful for detecting
# changes between screenshots or verifying content integrity.
struct CaptureComparison {
    captureIdA @0 :T.CaptureId;
    captureIdB @1 :T.CaptureId;
    # Similarity score (0.0 = completely different, 1.0 = identical).
    similarity @2 :Float32;
    # Whether the captures are pixel-identical.
    identical @3 :Bool;
    # Regions that differ (for partial diffs).
    diffRegions @4 :List(CaptureRegion);
}

# ── Compression Options ────────────────────────────────────────────────
# Fine-grained compression control for captured content. Separates
# compression level, quality, and algorithm from the format field.
struct CompressionOptions {
    algorithm @0 :CompressionAlgorithm;
    # Quality level (0–100, higher = better quality, larger file).
    quality @1 :UInt8;
    # Whether to use lossless compression.
    lossless @2 :Bool;
    # Target file size in bytes (0 = no target, use quality).
    targetSizeBytes @3 :UInt64;
}

enum CompressionAlgorithm {
    auto @0;
    zlib @1;
    lz4 @2;
    zstd @3;
    brotli @4;
    jpeg @5;
    png @6;
    webp @7;
    custom @8;
}

# ── Capture Device Metadata ────────────────────────────────────────────
# Tag captures with device information, location, and user context.
# Enables organizing and filtering captures by provenance.
struct CaptureDeviceMetadata {
    # Device name/identifier.
    deviceName @0 :Text;
    # User who initiated the capture.
    userId @1 :T.UserId;
    # Application that performed the capture.
    appId @2 :T.AppId;
    # GPS location at capture time.
    latitude @3 :Float64;
    longitude @4 :Float64;
    # Capture timestamp.
    capturedAt @5 :T.Timestamp;
}

# ── Format Negotiation Result ──────────────────────────────────────────
# Result of format negotiation. Indicates whether the requested
# format was accepted, rejected, or adapted.
struct FormatNegotiationResult {
    union {
        # Format fully accepted.
        accepted @0 :CaptureFormat;
        # Format rejected — use default.
        rejected @1 :T.Error;
        # Format accepted with modifications.
        adapted @2 :CaptureFormat;
        custom @3 :Data;
    }
}

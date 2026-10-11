@0xa1b2c3d4e5f60014;

using T = import "types.capnp";
using import "capability.capnp".Capability;

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
#
# Audit-8 enhancements:
#   - CaptureRegion: typed region for partial capture.
#   - AudioCaptureConfig: audio capture alongside video.
#   - WatermarkRequest: programmatic watermarking during capture.
#   - CaptureScheduleRequest: scheduled/time-lapse capture.
#   - FrameStream: the canonical bounded frame-delivery contract
#     (pull(maxFrames)/cancel, monotonic sequence, honest end-of-stream),
#     the single home shared with camera.capnp.
#   - CaptureThumbnail: low-resolution preview.
#   - RetentionPolicy: auto-deletion and archival rules.
#
# Revamp (pre-release — nothing external consumes this contract):
#   - FRAME DELIVERY closes the hole: `startStream`/`openCapture` return a
#     readable `FrameStream`, and `stopRecording` NO LONGER materialises a
#     whole recording (~22 GB at 4K60/30min) as one result. Live pulls
#     carry a monotonic `sequence`, never an offset into the stream.
#   - AUTHORITY (R3): every operation that acquires, persists or shares
#     another application's pixels moved behind the single gated
#     `CaptureController` (obtained once via `openController`); discovery
#     stays ungated. The old `CapturePermission` boolean/allow-list model
#     and `setCapturePermission` are deleted.
# ═══════════════════════════════════════════════════════════════════════

interface CaptureService {
    # ── Ungated discovery (ai.capnp:57-60) ──
    # What exists and what a source can do stays readable without any
    # authority, so a caller can learn before it holds a grant. None of
    # these acquires or persists another application's pixels.
    getSources @0 (pagination :T.Pagination) -> (sources :List(CaptureSourceRef), totalCount :UInt32);
    listCaptures @1 (pagination :T.Pagination) -> (captures :List(CaptureInfo), totalCount :UInt32);
    getCapture @2 (captureId :T.CaptureId) -> (info :CaptureInfo);
    negotiateFormat @3 (source :CaptureSourceRef, desired :CaptureFormat) -> (result :FormatNegotiationResult);
    subscribeEvents @4 () -> (subscription :CaptureEventSubscription);

    # ── Read back a stored artifact in bounded pulls ──
    # One read path for live and stored, so a ~22 GB recording is never
    # materialised as one result; the caller sizes its own memory. The
    # authority is the captureId the caller already holds.
    openCapture @5 (captureId :T.CaptureId) -> (stream :FrameStream, format :CaptureFormat, startedAt :T.Timestamp);

    # ── The ONE gated accessor (R3) ──
    # Capturing another application's window, persisting pixels, or
    # handing them to someone is the sensitive half. It is reached ONLY
    # through this capability-gated accessor — never from a reference a
    # caller holds by default. The old shape leaked both ways: capture
    # methods hung ungated on this root, AND a parallel permission model
    # (CapturePermission) let any client set another app's rights.
    openController @6 (authority :Capability) -> (controller :CaptureController);
}

# ═══════════════════════════════════════════════════════════════════════
# CaptureController — the capability-gated capture half.
#
# Obtained once, from `CaptureService.openController (authority)`.
# Holding this reference IS the authority to capture; none of its
# methods takes a capability token, because a per-method parameter
# would duplicate the authority the reference already carries and leave
# two paths that must agree forever (DESIGN_PRINCIPLES.md:394).
#
# What moved here is exactly what used to be ungated: the methods that
# acquire pixels belonging to another application, that persist them,
# or that hand them to someone else. Discovery (`getSources`,
# `listCaptures`, `negotiateFormat`) and reading a capture the caller
# already holds a right to stay ungated on CaptureService, so a caller
# can learn what exists before it holds any authority (ai.capnp:57-60).
# ═══════════════════════════════════════════════════════════════════════
interface CaptureController {
    # Holding this reference IS the authority to capture; none of these
    # methods takes a capability token, because a per-method parameter
    # would duplicate the authority the reference already carries and leave
    # two paths that must agree forever (DESIGN_PRINCIPLES.md:394). EVERY
    # operation that acquires, persists, or hands off another application's
    # pixels lives here — the previous revision left them ungated on
    # CaptureService AND kept a parallel permission model beside them.

    # ── One-shot captures ──
    captureOutput @0 (outputId :T.OutputId, format :CaptureFormat) -> (result :CaptureResult);
    captureWindow @1 (windowId :T.WindowId, format :CaptureFormat) -> (result :CaptureResult);
    captureScreen @2 (format :CaptureFormat) -> (result :CaptureResult);
    captureRegion @3 (outputId :T.OutputId, region :CaptureRegion, format :CaptureFormat) -> (result :CaptureResult);
    batchCapture @4 (sources :List(CaptureSourceRef), format :CaptureFormat) -> (result :BatchCaptureResult);

    # ── Recording ──
    # A recording is NOT returned by stopRecording. A 4K60 30-minute clip
    # is ~22 GB, and returning it as one result is a message no client can
    # accept; it is read back through `CaptureService.openCapture` in
    # bounded pulls instead.
    startRecording @5 (source :CaptureSourceRef, format :CaptureFormat) -> (captureId :T.CaptureId);
    stopRecording @6 (captureId :T.CaptureId) -> T.VoidResult;
    pauseRecording @7 (captureId :T.CaptureId) -> T.VoidResult;
    resumeRecording @8 (captureId :T.CaptureId) -> T.VoidResult;

    # ── Continuous streaming ──
    # Returns a readable stream, not an id. See FRAME DELIVERY above.
    startStream @9 (source :CaptureSourceRef, format :CaptureFormat)
                -> (stream :FrameStream, format :CaptureFormat, startedAt :T.Timestamp);
    stopStream @10 (streamId :T.CaptureId) -> T.VoidResult;

    # ── Scheduled / archival ──
    scheduleCapture @11 (request :CaptureScheduleRequest) -> (scheduleId :UInt64);
    cancelSchedule @12 (scheduleId :UInt64) -> T.VoidResult;
    archiveCapture @13 (captureId :T.CaptureId, policy :RetentionPolicy) -> T.VoidResult;

    # ── Pipeline ──
    createPipeline @14 (pipeline :CapturePipeline) -> (pipelineId :UInt64);
    applyPipeline @15 (captureId :T.CaptureId, pipelineId :UInt64) -> (processed :T.CaptureId);
    listPipelines @16 (pagination :T.Pagination) -> (pipelines :List(CapturePipeline), total :UInt32);

    # ── Session ──
    createSession @17 (name :Text, sources :List(CaptureSourceRef), format :CaptureFormat) -> (session :CaptureSession);
    stopSession @18 (sessionId :UInt64) -> T.VoidResult;
    pauseSession @19 (sessionId :UInt64) -> T.VoidResult;
    resumeSession @20 (sessionId :UInt64) -> T.VoidResult;
    listSessions @21 (pagination :T.Pagination) -> (sessions :List(CaptureSession), total :UInt32);

    # ── Analysis / annotation / comparison ──
    analyzeCapture @22 (captureId :T.CaptureId) -> (analysis :CaptureAnalysis);
    addAnnotation @23 (annotation :CaptureAnnotation) -> (annotationId :UInt64);
    listAnnotations @24 (captureId :T.CaptureId) -> (annotations :List(CaptureAnnotation));
    removeAnnotation @25 (annotationId :UInt64) -> T.VoidResult;
    compareCaptures @26 (captureIdA :T.CaptureId, captureIdB :T.CaptureId) -> (comparison :CaptureComparison);

    # ── Sharing ──
    shareCapture @27 (request :CaptureShareRequest) -> (result :CaptureShareResult);
}

struct CaptureResult {
    union {
        ok @0 :CaptureData;
        error @1 :T.Error;
    }
}

# The one-shot captures. A failed capture (a window that vanished, an
# occluded output, out of storage) previously returned an empty
# DataHandle indistinguishable from a zero-length image.
struct CaptureData {
    captureId @0 :T.CaptureId;
    data @1 :T.DataHandle;
    metadata @2 :T.StringMap;
}

struct BatchCaptureResult {
    union {
        ok @0 :List(T.CaptureId);
        error @1 :T.Error;
    }
}

struct CaptureShareResult {
    union {
        ok @0 :T.Uri;
        error @1 :T.Error;
    }
}

# One pull path, bounded by the caller's request, with an honest
# end-of-stream. The previous `pullPaginated @2 (pagination)` offset
# into a live event queue, where an offset means nothing; and the
# unbounded `pull @0` beside it let a server's queue grow without
# limit while a slow consumer's next pull shipped everything at once.
interface CaptureEventSubscription {
    pull @0 (maxEvents :UInt32) -> (events :List(CaptureEvent));
    cancel @1 () -> T.VoidResult;
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

# An event, as a union. The previous shape was a struct with a
# `type :CaptureEventType` enum, which had two defects:
#
#   1. `error @4` carried no payload, so a failed capture produced an
#      event that said "something failed" and nothing about what.
#   2. The enum was the only forward-compat route, so a backend adding
#      a frameCaptured or recordingSurvivedCleanup event had to overload
#      `stopped` — and a consumer that did not know the new meaning
#      could not tell what it skipped.
#
# The ai.capnp:533-550 shape fixes both: known events are arms, the
# error arm carries T.Error, and anything not yet invented rides in
# `unknown` and is ignored rather than rejected (ai.capnp:43-47).
struct CaptureEvent {
    id @0 :T.EventId;
    timestamp @1 :T.Timestamp;
    captureId @2 :T.CaptureId;
    union {
        started @3 :Void;
        stopped @4 :Void;
        paused @5 :Void;
        resumed @6 :Void;
        error @7 :T.Error;
        unknown @8 :UnknownCaptureEvent;
    }
}

# Unknown values are ignored, never rejected (ai.capnp:43-47).
struct UnknownCaptureEvent {
    typeId @0 :UInt64;
    payload @1 :Data;
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

# ═══════════════════════════════════════════════════════════════════════
# FRAME DELIVERY — the canonical contract for continuous capture.
#
# WHY THIS EXISTS: the previous revision's `startStream` returned a
# T.CaptureId and NO METHOD ANYWHERE READ IT. A continuous capture could
# be started and stopped but never read, so a headless consumer (an AR
# overlay, an OCR pass, a getUserMedia client) had no way to obtain a
# frame and every backend filled the hole with its own side channel —
# V4L2 and AVFoundation already disagree on buffer semantics, and the
# protocol forced implementers to keep both. `stopRecording` had the
# mirror-image defect: it materialised an entire recording as one
# result, which at 4K60 for 30 minutes is ~22 GB that no client can
# accept as a unit, with no partial read, no segment and no resume.
#
# THE CONTRACT — five properties, all of them load-bearing:
#
#   1. HANDLES, NEVER INLINE BYTES. `pixels` is a T.DataHandle. A 4K
#      frame is ~25 MB; as an inline field every frame is copied into
#      the message arena and out again, which is exactly what Cap'n
#      Proto's zero-copy exists to prevent (ai.capnp:74-75).
#
#   2. BOUNDED BY EXPLICIT REQUEST. `pull (maxFrames)` — the caller
#      states how much it will accept. A slow consumer therefore cannot
#      grow the producer's queue without limit, and a fast producer
#      cannot materialise an unbounded message. ai.capnp:277's
#      `pull (maxBytes)` is the same decision.
#
#   3. SEQUENCE, NEVER OFFSET. Every frame carries a monotonically
#      increasing `sequence` starting at 1. There is deliberately no
#      offset parameter: `T.Pagination.offset` is an index into a
#      STABLE list, and a live stream has no stable ordering, so
#      `pull (offset=5)` either drops the first 5 readings or re-delivers
#      five already consumed ones — silently, with no way for the caller
#      to tell. The sequence number replaces it exactly: a gap between
#      the last sequence the caller saw and the first sequence in this
#      pull measures precisely how many frames were lost, so loss is
#      visible instead of silent. (This is the fix for the offset-into-
#      live-stream defect found at nine sites across the protocol.)
#
#   4. HONEST END OF STREAM. `pull` distinguishes "nothing has arrived
#      yet" (`empty`), "the producer closed this stream and no more
#      frames will ever arrive" (`ended`), and "the producer failed"
#      (`error`, carrying T.Error). A dead camera and a quiet camera
#      are different facts, and the previous bare-list return made them
#      the same fact.
#
#   5. CANCEL. `cancel` stops delivery, releases the producer's buffers
#      and makes the stream's termination observable to the producer.
#
# One contract serves both a LIVE stream (frames flow as captured) and a
# STORED artifact (a recording, a batch result, a pipeline output) read
# back through `openCapture` — because an artifact is a stored frame
# sequence, and having one read path instead of two removes the second
# authority for the same bytes.
# ═══════════════════════════════════════════════════════════════════════

struct Frame {
    pixels @0 :T.DataHandle;
    # Monotonic, per-stream, starts at 1. A consumer records the last
    # sequence it processed; a gap in the next pull is measured loss,
    # not a silent skip.
    sequence @1 :UInt64;
    # When the frame was captured by the hardware, NOT when it was
    # delivered. A consumer computing latency needs the difference, and
    # a wall-clock timestamp here would survive a clock adjustment.
    capturedAt @2 :T.MonotonicTimestamp;
    metadata @3 :T.StringMap;
}

struct FramePullResult {
    union {
        frames @0 :List(Frame);
        empty @1 :Void;
        ended @2 :Void;
        error @3 :T.Error;
    }
}

interface FrameStream {
    pull @0 (maxFrames :UInt32) -> (result :FramePullResult);
    cancel @1 () -> T.VoidResult;
}

# startStream returns the stream and the agreed format as named results,
# because the negotiated format is part of the contract: the previous
# revision left a stream's format as a request with no outcome, so two
# independently written backends could not interoperate without being
# tested against each other by hand. A format the source cannot produce
# is a failed call, not a silent downgrade.

# ── Capture Thumbnail ──────────────────────────────────────────────────
# Low-resolution preview of a capture. Used for rapid visual browsing
# without loading full-resolution capture data.
struct CaptureThumbnail {
    width @0 :UInt32;
    height @1 :UInt32;
    data @2 :T.DataHandle;
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

# ── Capture Authority Model ────────────────────────────────────────────
# DELETED (R3, O1-deletion-half). The previous `CapturePermission
# { appId, allowedSources, maxDuration, audioAllowed, screenAllowed,
# windowAllowed }` — boolean permission flags plus an app allow-list, and
# a `setCapturePermission` that let any client set ANOTHER app's rights —
# is exactly the parallel permission model DESIGN_PRINCIPLES.md:399
# forbids ("Do NOT define permission strings, boolean flags, or role-based
# access control; the capability system IS the access control mechanism").
# Authority is now the `CaptureController` reference, granted once through
# `CaptureService.openController (authority)`. A grant names what it
# permits through capability.capnp's own `operations` and `constraints`
# (a duration cap is a constraint on the grant, not a re-specified field),
# and attenuation/revocation are capability.capnp's job — not duplicated
# per service here.

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

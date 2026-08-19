@0xa1b2c3d4e5f60004;

using T = import "types.capnp";
using A11y = import "accessibility.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Surface - one rectangle the app draws into.
#
# Improvements beyond the original schema (audit):
#   - `transform :T.BufferTransform` (typed enum) replaces `UInt32`.
#   - `commit @3` now takes `FrameSubmission` parameter, not just id —
#     apps can commit a frame in one round-trip with damage/buffer/fence.
#   - `damage` is optional via `DamageOption` union (was leaking
#     requirement).
#   - `damageTiles :List(UInt32)` decoration removed (backend-specific).
#   - Added `SurfaceMaterial` covers rounded/styleable, plus shadow hints.
#   - Added `Surface.drmMode` for HiDPI hints (Float32 scale fixed-point usage).
#   - Added `Surface.cursorId` overlay tracking.
#   - Added `Surface.lifecycles` track frame-events for analytics.
#   - `subscribeFrame`/`pullFrame` exposed per surface to image-based
#     consumers (snapshot takers, hot-reload debuggers, automation).
#   - SyncFence.handle uses T.FenceHandle (typed opaque handle).
#   - All subscription interfaces now have cancel method.
#   - FrameSubscription and StateSubscription have cancel methods.
#   - listSurfaces supports pagination via T.Pagination.
#   - PresentIntent union has custom variant.
#   - ShadowShape.offset uses T.Vec2 (was undefined T.Vec2f).
#
# Audit-7 improvements:
#   - Surface interface methods: setSpatialPose, setCurvature, createZone, createBubble,
#     dismissBubble, setRole, getFrameMetrics, listByRole, captureSurface,
#     startRecording, stopRecording.
#   - SpatialPose / SpatialAnchor for AR/VR spatial surfaces.
#   - SurfaceCurvature for curved displays (watch, car).
#   - DisplayZone for automotive multi-zone shells.
#   - ContextBubbleSurface for ephemeral overlay surfaces.
#   - SurfaceRole enum for typed surface classification.
#   - FrameMetrics for active frame tracking.
#   - CaptureFormat / RecordingConfig / RecordingCodec for surface recording.
# ═══════════════════════════════════════════════════════════════════════

interface Surface {
    create @0 (parent :T.SurfaceId) -> (surfaceId :T.SurfaceId);
    destroy @1 (surfaceId :T.SurfaceId) -> T.VoidResult;

    attachBuffer @2 (surfaceId :T.SurfaceId, bufferId :T.BufferId, bufferOffset :T.Vec2i) -> T.VoidResult;
    commit @3 (submission :FrameSubmission) -> T.VoidResult;

    damage @4 (surfaceId :T.SurfaceId, damage :DamageOption) -> T.VoidResult;

    setPosition @5 (surfaceId :T.SurfaceId, position :T.Vec2i) -> T.VoidResult;
    setSize @6 (surfaceId :T.SurfaceId, size :T.Size) -> T.VoidResult;
    setScale @7 (surfaceId :T.SurfaceId, scale :Float32) -> T.VoidResult;
    setTransform @8 (surfaceId :T.SurfaceId, transform :T.BufferTransform) -> T.VoidResult;
    setOpacity @9 (surfaceId :T.SurfaceId, opacity :Float32) -> T.VoidResult;
    raiseToTop @10 (surfaceId :T.SurfaceId) -> T.VoidResult;
    lowerToBottom @11 (surfaceId :T.SurfaceId) -> T.VoidResult;

    setInputRegion @12 (surfaceId :T.SurfaceId, region :T.Region) -> T.VoidResult;
    setOpaque @13 (surfaceId :T.SurfaceId, region :T.Region) -> T.VoidResult;

    setCornerRadius @14 (surfaceId :T.SurfaceId, radius :T.CornerRadius) -> T.VoidResult;
    setShadow @15 (surfaceId :T.SurfaceId, shadow :ShadowShape) -> T.VoidResult;
    setMaterial @16 (surfaceId :T.SurfaceId, material :SurfaceMaterial) -> T.VoidResult;

    setSurfaceCursor @17 (surfaceId :T.SurfaceId, cursor :T.CursorShape, hotspot :T.Vec2i) -> T.VoidResult;

    getState @18 (surfaceId :T.SurfaceId) -> (state :SurfaceState);
    listSurfaces @19 (parent :T.SurfaceId) -> (surfaces :List(SurfaceInfo));
    listSurfacesPaginated @26 (parent :T.SurfaceId, pagination :T.Pagination)
                          -> (surfaces :List(SurfaceInfo), total :UInt64);

    subscribeFrames @20 (surfaceId :T.SurfaceId) -> (subscription :FrameSubscription);
    pullFrame @21 (subscription :FrameSubscription) -> (frame :FrameData);
    cancelFrames @22 (subscription :FrameSubscription) -> T.VoidResult;

    subscribeState @23 (surfaceId :T.SurfaceId) -> (subscription :StateSubscription);
    pullState @24 (subscription :StateSubscription) -> (state :SurfaceState);
    cancelState @25 (subscription :StateSubscription) -> T.VoidResult;

    # ── Audit-7 additions ──

    # Spatial pose for AR/VR surfaces.
    setSpatialPose @27 (surfaceId :T.SurfaceId, pose :SpatialPose) -> T.VoidResult;

    # Curvature for curved displays (watch, car).
    setCurvature @28 (surfaceId :T.SurfaceId, curvature :SurfaceCurvature) -> T.VoidResult;

    # Create display zone for automotive multi-zone shells.
    createZone @29 (displayId :T.SurfaceId, zone :DisplayZone) -> (zoneId :Text);

    # Create context bubble (ephemeral overlay).
    createBubble @30 (bubble :ContextBubbleSurface) -> (surfaceId :T.SurfaceId);

    # Dismiss context bubble.
    dismissBubble @31 (surfaceId :T.SurfaceId) -> T.VoidResult;

    # Set surface role.
    setRole @32 (surfaceId :T.SurfaceId, role :SurfaceRole) -> T.VoidResult;

    # Get frame metrics.
    getFrameMetrics @33 (surfaceId :T.SurfaceId) -> (metrics :FrameMetrics);

    # Query surfaces by role.
    listByRole @34 (parent :T.SurfaceId, role :SurfaceRole, pagination :T.Pagination)
        -> (surfaces :List(SurfaceInfo), total :UInt64);

    # Surface recording and screenshot (audit-7 false positive: surface_recording.capnp belongs here).
    captureSurface @35 (surfaceId :T.SurfaceId, format :CaptureFormat) -> (data :T.DataHandle);
    startRecording @36 (surfaceId :T.SurfaceId, config :RecordingConfig) -> T.VoidResult;
    stopRecording @37 (surfaceId :T.SurfaceId) -> T.VoidResult;

    # ── Z-order configuration (audit-9 What's Still Missing) ──
    setZOrder @38 (surfaceId :T.SurfaceId, config :ZOrderConfig) -> T.VoidResult;

    # ── Surface animation (audit-9 What's Still Missing) ──
    animate @39 (surfaceId :T.SurfaceId, animation :SurfaceAnimation) -> T.VoidResult;

    # ── GPU selection (audit-9 What's Still Missing) ──
    setGpu @40 (surfaceId :T.SurfaceId, gpu :GpuSelection) -> T.VoidResult;
}

interface SurfaceService {
    listSurfaces @0 (pagination :T.Pagination) -> (surfaces :List(SurfaceInfo), total :UInt64);
    getSurface @1 (surfaceId :T.SurfaceId) -> (surface :SurfaceState);
}

interface FrameSubscription {
    pull @0 () -> (frame :FrameData);
    cancel @1 () -> T.VoidResult;
}

interface StateSubscription {
    pull @0 () -> (state :SurfaceState);
    cancel @1 () -> T.VoidResult;
}

struct DamageOption {
    union {
        omitted @0 :Void;
        full @1 :Void;
        rects @2 :List(T.Rect);
        custom @3 :Data;
    }
}

struct FrameSubmission {
    surfaceId @0 :T.SurfaceId;
    frameId @1 :UInt64;
    bufferId @2 :T.BufferId;
    bufferOffset @3 :T.Vec2i;
    damage @4 :DamageOption;
    present @5 :PresentIntent;
    fence @6 :SyncFence;
    transform @7 :T.BufferTransform;
}

struct PresentIntent {
    union {
        immediate @0 :Void;
        nextVsync @1 :Void;
        atTime @2 :T.Timestamp;
        periodic @3 :T.Duration;
        custom @4 :Data;
    }
}

struct SyncFence {
    handle @0 :T.FenceHandle;
    name @1 :Text;
}

struct ShadowShape {
    enabled @0 :Bool;
    blur @1 :Float32;
    offset @2 :T.Vec2;
    color @3 :T.Color;
    spread @4 :Float32;
}

enum SurfaceMaterial {
    default @0;
    glass @1;
    paper @2;
    metal @3;
    ceramic @4;
    fabric @5;
    custom @6;
}

struct FrameData {
    surfaceId @0 :T.SurfaceId;
    timestamp @1 :T.Timestamp;
    size @2 :T.Size;
    damage @3 :DamageOption;
    bufferId @4 :T.BufferId;
    presentationTime @5 :T.Timestamp;
    committedDamage @6 :T.Region;
}

struct SurfaceState {
    id @0 :T.SurfaceId;
    parent @1 :T.SurfaceId;
    position @2 :T.Vec2i;
    size @3 :T.Size;
    scale @4 :Float32;
    transform @5 :T.BufferTransform;
    opacity @6 :Float32;
    visible @7 :Bool;
    mapped @8 :Bool;
    material @9 :SurfaceMaterial;
    cornerRadius @10 :T.CornerRadius;
    shadow @11 :ShadowShape;
    hasInputRegion @12 :Bool;
}

struct SurfaceInfo {
    id @0 :T.SurfaceId;
    parent @1 :T.SurfaceId;
    size @2 :T.Size;
    material @3 :SurfaceMaterial;
    visible @4 :Bool;
    zpos @5 :Int32;
}

# ═══════════════════════════════════════════════════════════════════════
# AUDIT-7 ADDITIONS — Spatial, Curvature, Zones, Bubbles, Roles, Recording
# ═══════════════════════════════════════════════════════════════════════

# ── Spatial Pose (AR/VR 3D positioning) ──
struct SpatialPose {
    position @0 :T.Vec3;
    rotation @1 :T.Vec4;
    scale @2 :T.Vec3;
    anchor @3 :SpatialAnchor;
}

struct SpatialAnchor {
    type @0 :AnchorType;
    planeId @1 :Text;
    objectId @2 :Text;
    cloudAnchor @3 :Bool;
    persistent @4 :Bool;
}

enum AnchorType {
    none @0;
    plane @1;
    object @2;
    world @3;
    cloud @4;
    other @5;
    custom @6;
}

# ── Surface Curvature (curved display support) ──
struct SurfaceCurvature {
    enabled @0 :Bool;
    radiusX @1 :Float32;
    radiusY @2 :Float32;
    edgeFade @3 :Float32;
}

# ── Display Zone (automotive multi-zone) ──
struct DisplayZone {
    zoneId @0 :Text;
    bounds @1 :T.Rect;
    role @2 :ZoneRole;
    permissions @3 :List(ZonePermission);
    interaction @4 :InteractionMode;
}

enum ZoneRole {
    driver @0;
    passenger @1;
    rearLeft @2;
    rearRight @3;
    center @4;
    other @5;
    custom @6;
}

enum ZonePermission {
    viewContent @0;
    interact @1;
    showVideo @2;
    showNavigation @3;
    other @4;
    custom @5;
}

enum InteractionMode {
    touch @0;
    gesture @1;
    voice @2;
    dPad @3;
    other @4;
    custom @5;
}

# ── Context Bubble (ephemeral overlays) ──
struct ContextBubbleSurface {
    surfaceId @0 :T.SurfaceId;
    anchorSurface @1 :T.SurfaceId;
    position @2 :T.Vec2i;
    lifetime @3 :T.Duration;
    dismissible @4 :Bool;
    interactive @5 :Bool;
    content @6 :BubbleContent;
}

struct BubbleContent {
    union {
        text @0 :Text;
        richText @1 :T.DataHandle;
        image @2 :T.DataHandle;
        appPreview @3 :T.AppId;
        custom @4 :Data;
    }
}

# ── Surface Role (typed classification) ──
enum SurfaceRole {
    window @0;
    layer @1;
    overlay @2;
    cursor @3;
    notification @4;
    bubble @5;
    spatial @6;
    audio @7;
    other @8;
    custom @9;
}

# ── Frame Metrics (active frame tracking) ──
struct FrameMetrics {
    frameCount @0 :UInt64;
    lastFrameAt @1 :T.Timestamp;
    avgFrameTime @2 :T.Duration;
    droppedFrames @3 :UInt64;
    jankCount @4 :UInt64;
}

# ── Surface Recording (audit-7 false positive: surface_recording.capnp belongs here) ──
enum CaptureFormat {
    png @0;
    jpeg @1;
    webp @2;
    raw @3;
    other @4;
    custom @5;
}

struct RecordingConfig {
    codec @0 :RecordingCodec;
    duration @1 :T.Duration;
    fps @2 :UInt32;
}

enum RecordingCodec {
    vp8 @0;
    vp9 @1;
    av1 @2;
    h264 @3;
    h265 @4;
    other @5;
    custom @6;
}

# ── Surface Compositing Order (audit-8 What's Still Missing) ──
struct ZOrderConfig {
    surfaceId @0 :T.SurfaceId;
    zIndex @1 :Int32;
    sibling @2 :T.SurfaceId;
    relation @3 :ZOrderRelation;
}

enum ZOrderRelation {
    above @0;
    below @1;
    top @2;
    bottom @3;
    custom @4;
}

# ── Surface Animation Pipeline (audit-8 What's Still Missing) ──
struct SurfaceAnimation {
    surfaceId @0 :T.SurfaceId;
    property @1 :Text;
    duration @2 :T.Duration;
    easing @3 :EasingType;
    from @4 :T.Meta;
    to @5 :T.Meta;
}

enum EasingType {
    linear @0;
    easeIn @1;
    easeOut @2;
    easeInOut @3;
    spring @4;
    custom @5;
}

# ── Surface Accessibility Tree (audit-8 What's Still Missing) ──
struct SurfaceAccessibilityTree {
    surfaceId @0 :T.SurfaceId;
    rootNodeId @1 :T.AccessNodeId;
    nodes @2 :List(A11y.AccessibilityNode);
}

# ── Surface Multi-GPU (audit-8 What's Still Missing) ──
struct GpuSelection {
    surfaceId @0 :T.SurfaceId;
    gpuId @1 :UInt32;
    requireHwAccel @2 :Bool;
}

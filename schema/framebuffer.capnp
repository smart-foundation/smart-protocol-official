@0xa1b2c3d4e5f60058;

# ════════════════════════════════════════════════════════════════════════
# Framebuffer - pixel-addressable display surface for drivers/kernel.
#
# Lets drivers carry a framebuffer that the graphics stack imports
# wholesale. The framebuffer is backend-decided (DRM/KMS, FBDev,
# HMD compositor, headless virtual), but it always speaks this shape.
#
# Apps don't directly program framebuffers (that's compositor's job).
# But drivers, kernels, and compositor backends must carry them
# across the IPC boundary meaningfully. This is the type for that.
#
# Improvements applied (per audit_analysis.md rules):
#   - All raw UInt64 → typed IDs (T.FramebufferId)
#   - All enums have custom variant for forward compatibility
#   - AtomicRejection.target is now typed enum (was bare Text)
#   - FramebufferDisplayMode flags is now typed DisplayFlag enum (was raw UInt32)
#   - alpha prop is now typed Alpha capability bits struct
#   - T.Pagination for list operations
#   - T.Error for failure paths
#   - cancel() on subscription interfaces
#   - T.Duration for any rates/intervals
#   - PixelFormat uses T.PixelFormat from types.capnp
#
# Improvements (audit-3):
#   - AtomicRejection gains typedId :AtomicTargetId for unambiguous typed references (Rule 2).
#   - AtomicTargetId union replaces bare UInt64 target identification.
#
# Audit-7 improvements:
#   - FramebufferCaps: gpuPassthrough, subpixelLayout, adaptiveSync, virtual, maxBlendPlanes.
#   - HdrInfo struct for HDR metadata (EOTF, color space, luminance).
#   - EotfTransfer enum for electro-optical transfer functions.
#   - FramebufferColorSpace enum for display color spaces.
#   - SyncMode / SyncInfo for scanout synchronization.
#   - FramebufferKind / VirtualFramebufferInfo for virtual framebuffers.
#   - GpuPassthroughInfo / PassthroughMode for GPU virtualization.
#   - SubpixelLayout / AntiAliasingInfo for ClearType/FreeType.
#   - PlaneBlending / BlendFunction / BlendFactor for multi-plane blending.
#   - ColorManagement / ColorManagementIntent for ICC/LUT pipelines.
#   - FramebufferService methods: getHdrInfo, setColorManagement, getSyncInfo,
#     setSyncMode, getVirtualInfo, getGpuInfo, getAntiAliasingInfo, getPlaneBlending.
# ════════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "buffer.capnp".SharedMemoryRegion;

struct Framebuffer {
    # Stable identifier (backend-decided).
    id @0 :T.FramebufferId;

    # Pixel format (see types.capnp::PixelFormat).
    format @1 :T.PixelFormat;

    # Pixel resolution.
    width @2 :UInt32;
    height @3 :UInt32;

    # Bytes per row (≥ width * bytesPerPixel; backend may pad).
    stride @4 :UInt32;

    # Underlying physical/shared region to map.
    region @5 :SharedMemoryRegion;

    # Per-pixel byte count that the backend stores:
    # 4 = 32bpp (rgba/xrgb), 2 = 16bpp (rgb565), 1 = 8bpp (gray/clut).
    bytesPerPixel @6 :UInt8;

    # Optional color lookup table for indexed/8bpp modes.
    clut @7 :List(ColorEntry);

    # When present, drivers use it to recreate the cursor image.
    cursors @8 :List(CursorPlane);

    # Backend-specific typed properties (CRTC id, connector info, EDID).
    # Using a typed list avoids DRM-vs-other vendor coupling.
    properties @9 :List(KeyValue);

    # Friendly name for debugging ("panel-A", "HDMI-A-1", "headless-virtio").
    # Backend-decided, but no specific vendor format enforced.
    name @10 :Text;

    # Vendor identifier string (org/who manufactured this FB).
    vendor @11 :Text;

    # Whether this framebuffer is currently active (vs detached/allocated).
    active @12 :Bool;
}

struct ColorEntry {
    index @0 :UInt16;
    red   @1 :UInt8;
    green @2 :UInt8;
    blue  @3 :UInt8;
    alpha @4 :UInt8;
}

struct CursorPlane {
    width  @0 :UInt32;
    height @1 :UInt32;
    hotspotX @2 :UInt32;
    hotspotY @3 :UInt32;
    pixelRegion @4 :SharedMemoryRegion;
}

struct KeyValue {
    key @0 :Text;
    value @1 :Text;
}

struct Plane {
    id @0 :T.PlaneId;

    # Z-order position relative to other planes on the same CRTC.
    zpos @1 :Int32;

    # Where on the CRTC this plane is placed (in framebuffer pixels).
    rect @2 :T.Rect;

    # Where this plane reads from.
    srcRect @3 :T.Rect;

    # Format the plane reads.
    format @4 :T.PixelFormat;

    # Source CRTC or framebuffer.
    sourceId @5 :T.FramebufferId;

    # Color-keying hint (rarely needed).
    colorKey @6 :Int32;

    # Alpha blend mode.
    alphaMode @7 :AlphaMode;

    # Rotation applied to this plane.
    transform @8 :T.BufferTransform;
}

enum AlphaMode {
    # Pixel alpha is ignored, plane is fully opaque.
    opaque @0;
    # Pixel alpha determines blending per-pixel.
    blend @1;
    # Constant alpha (Plane.alpha) determines plane-wide blending.
    constant @2;
    # Source-over compositing with constant alpha.
    premultiplied @3;
    custom @4;
}

struct Crtc {
    id @0 :T.CrtcId;

    # Active framebuffer.
    framebufferId @1 :T.FramebufferId;

    # Per-CRTC transform.
    transform @2 :T.SurfaceTransform;

    # Mode currently active.
    mode @3 :FramebufferDisplayMode;

    # Plane stack for this CRTC.
    planeIds @4 :List(T.PlaneId);

    # Hardware cursor index (if any).
    cursorPlaneId @5 :T.PlaneId;

    # Whether this CRTC is currently enabled.
    enabled @6 :Bool;
}

struct FramebufferDisplayMode {
    # Pixel clock in Hz × 1000 (so 60000 = 60 MHz).
    pixelClockMilliHz @0 :UInt64;
    # Horizontal: visible + front porch + sync + back porch.
    hActive @1 :UInt32;
    hSyncStart @2 :UInt32;
    hSyncEnd @3 :UInt32;
    hTotal @4 :UInt32;
    # Same for vertical.
    vActive @5 :UInt32;
    vSyncStart @6 :UInt32;
    vSyncEnd @7 :UInt32;
    vTotal @8 :UInt32;
    # Refresh rate in Hz × 1000 (so 60.001 Hz → 60001).
    refreshRateMilli @9 :UInt32;
    # Pixels may be sampled in parallel.
    bpp @10 :UInt32;
    # Typed mode flags.
    flags @11 :List(DisplayFlag);

    # Whether this is the preferred mode (EDID-preferred).
    preferred @12 :Bool;
}

enum DisplayFlag {
    hSyncPositivePolarity @0;
    vSyncPositivePolarity @1;
    interlaced @2;
    doublescan @3;
    interlacedHalvedVBlank @4;
    layered @5;
    custom @6;
}

# Capabilities on a framebuffer device.
struct FramebufferCaps {
    # Buffer formats the hardware can scan out from.
    formats @0 :List(T.PixelFormat);
    # Whether this framebuffer supports cursor planes.
    cursor @1 :Bool;
    # Whether double-buffered (i.e., page-flip is supported).
    doubleBuffer @2 :Bool;
    # Maximum alpha precision in bits (0 = no alpha).
    maxAlphaBits @3 :UInt8;
    # Whether z-positioning is hardware-routed.
    zpos @4 :Bool;
    # Whether this supports HDR scanout.
    hdr @5 :Bool;
    # Maximum number of overlay planes.
    maxPlanes @6 :UInt32;
    # Whether atomic-test can be performed.
    atomicTest @7 :Bool;
    # Maximum number of framebuffers allocatable concurrently.
    maxFramebuffers @8 :UInt32;

    # Audit-7 additions:
    # Whether GPU passthrough is supported.
    gpuPassthrough @9 :Bool;
    # Sub-pixel layout for anti-aliasing.
    subpixelLayout @10 :SubpixelLayout;
    # Whether adaptive sync is supported.
    adaptiveSync @11 :Bool;
    # Whether virtual framebuffers are supported.
    virtual @12 :Bool;
    # Maximum number of blend planes.
    maxBlendPlanes @13 :UInt32;
}

# Atomic-test result for a configuration.
struct AtomicTestResult {
    accepted @0 :Bool;
    # Rejected CRTCs/FBs/planes, with reason.
    rejections @1 :List(AtomicRejection);
}

# Why one entry was rejected. The previous shape carried THREE references
# to the same resource (a kind enum, a bare UInt64, and a typed union)
# with a comment telling consumers to prefer one of them — three
# spellings of one reference where one would do, and an implementer trap
# for the other two.
struct AtomicRejection {
    typedId @0 :AtomicTargetId;
    reason @1 :T.Error;
}

# What to stage. This is the input the atomic methods never had: the
# complete set of property changes to validate together, addressed by the
# AtomicTargetId union that already existed but was only ever used in a
# rejection — i.e. the typed-target machinery was forward-compat
# scaffolding for an operation that could not be performed.
#
# Each entry is one proposed change to one resource. `properties` carries
# the change itself as an open key/value map so that a 2046 property
# needs no ordinal.
struct AtomicEntry {
    target @0 :AtomicTargetId;
    # The proposed property values. A backend that does not recognise a
    # key ignores it rather than rejecting the whole configuration
    # (ai.capnp:43-47).
    properties @1 :T.StringMap;
}

struct AtomicRequest {
    entries @0 :List(AtomicEntry);
    # Whether the commit may tear (present before the new configuration
    # is fully active). False is the safe default and is what a
    # compositor needs.
    allowTearing @1 :Bool = false;
    # Test-only: validate the configuration without applying anything.
    test @2 :Bool = false;
    metadata @3 :T.StringMap;
}

# Typed target reference — replaces bare UInt64 for forward compatibility.
struct AtomicTargetId {
    union {
        framebuffer @0 :T.FramebufferId;
        plane @1 :T.PlaneId;
        crtc @2 :T.CrtcId;
        custom @3 :Data;
    }
}

enum AtomicTargetKind {
    crtc @0;
    plane @1;
    framebuffer @2;
    mode @3;
    format @4;
    custom @5;
}

# Framebuffer service interfaces.
interface FramebufferService {
    # Discover framebuffers.
    list @0 (pagination :T.Pagination) -> (framebuffers :List(Framebuffer), total :UInt64);

    # Inspect one framebuffer.
    get @1 (framebufferId :T.FramebufferId) -> (framebuffer :Framebuffer);

    # Inspect a CRTC.
    getCrtc @2 (crtcId :T.CrtcId) -> (crtc :Crtc);

    # Advertise capabilities.
    capabilities @3 () -> (caps :FramebufferCaps);

    # Test an atomic configuration without committing it.
    #
    # THE PREVIOUS SHAPE TOOK NO PARAMETERS AT ALL — both atomic methods
    # were `() -> (...)`, while the only configuration channel in the
    # entire interface was a set of per-framebuffer setters. So a backend
    # could not stage a mode set, validate it and commit it: it had to
    # call six setters and hope. The whole point of an atomic test is to
    # say "would THIS work" before doing it, and "this" could not be
    # expressed. (Both methods were `()`, so adding a parameter is
    # ordinal-neutral.)
    testAtomic @4 (request :AtomicRequest) -> (result :AtomicTestResult);

    # Commit an atomic configuration. Always interleaved with `testAtomic`.
    commitAtomic @5 (request :AtomicRequest) -> (result :T.VoidResult);

    # Subscribe to hotplug events.
    subscribe @6 () -> (subscription :FramebufferSubscription);

    # Get plane by ID.
    getPlane @7 (planeId :T.PlaneId) -> (plane :Plane);

    # List all planes.
    listPlanes @8 (pagination :T.Pagination) -> (planes :List(Plane), total :UInt64);

    # ── Audit-7 additions ──
    # Get HDR capabilities for a framebuffer.
    getHdrInfo @9 (framebufferId :T.FramebufferId) -> (hdrInfo :HdrInfo);

    # Set color management configuration.
    setColorManagement @10 (framebufferId :T.FramebufferId, config :ColorManagement) -> T.VoidResult;

    # Get scanout sync info.
    getSyncInfo @11 (framebufferId :T.FramebufferId) -> (syncInfo :SyncInfo);

    # Set scanout sync mode.
    setSyncMode @12 (framebufferId :T.FramebufferId, mode :SyncMode) -> T.VoidResult;

    # Get virtual framebuffer info.
    getVirtualInfo @13 (framebufferId :T.FramebufferId) -> (virtualInfo :VirtualFramebufferInfo);

    # Get GPU passthrough info.
    getGpuInfo @14 (framebufferId :T.FramebufferId) -> (gpuInfo :GpuPassthroughInfo);

    # Get anti-aliasing info.
    getAntiAliasingInfo @15 (framebufferId :T.FramebufferId) -> (aaInfo :AntiAliasingInfo);

    # Get blend configuration for a plane.
    getPlaneBlending @16 (planeId :T.PlaneId) -> (blending :PlaneBlending);

    # ── Frame timing and latency (audit-9 What's Still Missing) ──
    getFrameTiming @17 (framebufferId :T.FramebufferId) -> (timing :FrameTimingInfo);

    # ── Display topology management (audit-9 What's Still Missing) ──
    getDisplayTopology @18 () -> (topology :DisplayTopology);
    connectDisplay @19 (outputId :T.OutputId) -> T.VoidResult;
    disconnectDisplay @20 (outputId :T.OutputId) -> T.VoidResult;

    # ── Display power management (audit-9 What's Still Missing) ──
    # T.PowerSleepState, not a local DpmsState: display power state is
    # one concept with one vocabulary (types.capnp:2140), and the local
    # copy was a verbatim duplicate of display.capnp's.
    setDpmsState @21 (framebufferId :T.FramebufferId, state :T.PowerSleepState) -> T.VoidResult;

    # ── Display rotation (audit-9 What's Still Missing) ──
    setRotation @22 (framebufferId :T.FramebufferId, rotation :DisplayRotation) -> T.VoidResult;

    # ── Display scaling (audit-9 What's Still Missing) ──
    setScaling @23 (framebufferId :T.FramebufferId, scaling :DisplayScaling) -> T.VoidResult;

    # ── HDR10+ dynamic metadata (audit-9 What's Still Missing) ──
    setHdr10Plus @24 (framebufferId :T.FramebufferId, metadata :Hdr10PlusMetadata) -> T.VoidResult;
}

interface FramebufferSubscription {
    pull @0 () -> (events :List(FramebufferEvent));
    cancel @1 () -> T.VoidResult;
}

# Unknown values are ignored, never rejected (ai.capnp:43-47). Without
# this arm a backend adding a modeset, HDR-metadata or frame-timing
# event has to overload `changed` — and the file's own header claimed
# every enum had a forward-compat variant while this union had none.
struct UnknownFramebufferEvent {
    typeId @0 :UInt64;
    payload @1 :Data;
}

struct FramebufferEvent {
    timestamp @0 :T.Timestamp;
    union {
        added @1 :Framebuffer;
        removed @2 :T.FramebufferId;
        changed @3 :Framebuffer;
        crtcChanged @4 :Crtc;
        planeChanged @5 :Plane;
        atomicRejected @6 :AtomicRejection;
        unknown @7 :UnknownFramebufferEvent;
    }
}

# ══════════════════════════════════════════════════════════════════════
# AUDIT-7 ADDITIONS — HDR, Sync, Virtual, GPU, Subpixel, Blending, Color
# ══════════════════════════════════════════════════════════════════════

# ── HDR Color Management (audit-7 false positive: hdr_color_management.capnp belongs here) ──

struct HdrInfo {
    eotf @0 :EotfTransfer;
    colorSpace @1 :FramebufferColorSpace;
    maxLuminance @2 :UInt32;
    minLuminance @3 :UInt32;
    maxFrameAverage @4 :UInt32;
    maxContent @5 :UInt32;
}

enum EotfTransfer {
    srgb @0;
    pq @1;
    hlg @2;
    linear @3;
    gamma22 @4;
    gamma26 @5;
    other @6;
    custom @7;
}

enum FramebufferColorSpace {
    srgb @0;
    displayP3 @1;
    dciP3 @2;
    rec2020 @3;
    aces @4;
    adobeRgb @5;
    other @6;
    custom @7;
}

# ── Scanout Synchronization (audit-7 false positive: display_sync.capnp belongs here) ──

enum SyncMode {
    none @0;
    vsync @1;
    adaptive @2;
    gsync @3;
    other @4;
    custom @5;
}

struct SyncInfo {
    mode @0 :SyncMode;
    refreshRate @1 :UInt32;
    minRefreshRate @2 :UInt32;
    maxRefreshRate @3 :UInt32;
    vblank @4 :T.Duration;
}

# ── Virtual Framebuffer (audit-7 false positive: virtual_framebuffer.capnp belongs here) ──

enum FramebufferKind {
    physical @0;
    virtual @1;
    gpu @2;
    network @3;
    other @4;
    custom @5;
}

struct VirtualFramebufferInfo {
    backend @0 :Text;
    maxWidth @1 :UInt32;
    maxHeight @2 :UInt32;
    maxFps @3 :UInt32;
    compression @4 :Bool;
    encryption @5 :Bool;
}

# ── GPU Passthrough (audit-7 false positive: gpu_passthrough.capnp belongs here) ──

struct GpuPassthroughInfo {
    vendor @0 :Text;
    deviceId @1 :UInt32;
    passthroughMode @2 :PassthroughMode;
    # Opaque, backend-decided passthrough locator. VFIO is a Linux
    # kernel API: a microkernel GPU service, macOS, or an embedded RTOS
    # has no "group" to report, and must previously invent a number for
    # a required field. The locator is now whatever the backend needs it
    # to be, with no platform named in the contract.
    passthroughLocator @3 :Data;
    memorySize @4 :UInt64;
}

enum PassthroughMode {
    full @0;
    mediated @1;
    virtual @2;
    other @3;
    custom @4;
}

# ── Sub-pixel Layout (audit-7) ──

enum SubpixelLayout {
    unknown @0;
    rgb @1;
    bgr @2;
    vrgb @3;
    vbgr @4;
    none @5;
    other @6;
    custom @7;
}

struct AntiAliasingInfo {
    subpixel @0 :SubpixelLayout;
    gamma @1 :Float32;
    filter @2 :Text;
    antialias @3 :Bool;
    lcdFilter @4 :Bool;
}

# ── Multi-plane Blending (audit-7) ──

struct PlaneBlending {
    planeId @0 :T.PlaneId;
    function @1 :BlendFunction;
    srcFactor @2 :BlendFactor;
    dstFactor @3 :BlendFactor;
    srcAlphaFactor @4 :BlendFactor;
    dstAlphaFactor @5 :BlendFactor;
}

enum BlendFunction {
    none @0;
    additive @1;
    premultiplied @2;
    separate @3;
    other @4;
    custom @5;
}

enum BlendFactor {
    zero @0;
    one @1;
    srcColor @2;
    dstColor @3;
    srcAlpha @4;
    dstAlpha @5;
    other @6;
    custom @7;
}

# ── Color Management Pipeline (audit-7) ──

struct ColorManagement {
    profile @0 :Text;
    lut @1 :T.DataHandle;
    gamut @2 :FramebufferColorSpace;
    intent @3 :ColorManagementIntent;
}

enum ColorManagementIntent {
    perceptual @0;
    relativeColorimetric @1;
    saturation @2;
    absoluteColorimetric @3;
    other @4;
    custom @5;
}

# ── Frame Timing and Latency (audit-8 What's Still Missing) ──
struct FrameTimingInfo {
    refreshRate @0 :UInt32;
    minLatency @1 :T.Duration;
    maxLatency @2 :T.Duration;
    avgLatency @3 :T.Duration;
    frameTime @4 :T.Duration;
    droppedFrames @5 :UInt64;
}

# ── Display Topology (audit-8 What's Still Missing) ──
struct DisplayTopology {
    displays @0 :List(DisplayNode);
    maxWidth @1 :UInt32;
    maxHeight @2 :UInt32;
}

struct DisplayNode {
    outputId @0 :T.OutputId;
    position @1 :T.Vec2i;
    parentId @2 :T.OutputId;
    children @3 :List(T.OutputId);
}

# ── Display Power Management (audit-8 What's Still Missing) ──
enum DpmsState {
    on @0;
    standby @1;
    suspend @2;
    off @3;
    custom @4;
}

# ── Display Rotation (audit-8 What's Still Missing) ──
enum DisplayRotation {
    rotation0 @0;
    rotation90 @1;
    rotation180 @2;
    rotation270 @3;
    custom @4;
}

# ── Display Scaling (audit-8 What's Still Missing) ──
struct DisplayScaling {
    scaleFactor @0 :Float32;
    fractional @1 :Bool;
   hidpi @2 :Bool;
}

# ── HDR10+ Dynamic Metadata (audit-9 What's Still Missing) ──
struct Hdr10PlusMetadata {
    sceneId @0 :UInt32;
    maxscl @1 :List(UInt32);
    distributionMaxrgbPercentile @2 :List(HdrPercentile);
    kneePointX @3 :UInt16;
    kneePointY @4 :UInt16;
    bezierCurveAnchor @5 :List(UInt16);
    toneMappingFlag @6 :Bool;
}

struct HdrPercentile {
    percentage @0 :Float32;
    value @1 :UInt32;
}
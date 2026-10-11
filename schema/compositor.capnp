@0xa1b2c3d4e5f60005;

# ══════════════════════════════════════════════════════════════════════
# Compositor — display composition and the ONE surface commit path.
#
# WHAT THIS IS
#   The compositor is the component that owns presentation: outputs,
#   surfaces, the frame lifecycle, the cursor, drag-and-drop, input
#   routing and screen capture. Every app talks to it through ONE
#   interface, `Session`, obtained by handshake. There is no second
#   compositor contract and no standalone surface contract: surface.capnp
#   was merged into this file (its `FrameSubmission`/`SurfaceCommit`
#   fork and its `SyncFence.native :UInt64` are gone) and deleted.
#
# WHO CONSUMES IT
#   Apps (create a surface, commit frames, read events), the window
#   manager (reorders and places surfaces), the shell (panels, bubbles).
#
# WHAT IS DELIBERATELY OPAQUE
#   Buffer identity (`T.BufferId`), fences (`T.FenceHandle`), surface
#   roles and capability kinds (open tokens). The backend decides how a
#   surface is backed, how a fence is signalled, and which capability
#   vocabularies it recognises. Nothing here names a display server, a
#   rendering API or a display protocol.
#
# THE COMMIT PATH (one path, typed end to end)
#   `attachBuffer` binds a buffer to a surface by `T.BufferId`.
#   `commit` then submits `SurfaceCommit`, which references that same
#   `T.BufferId`, carries damage as geometry, presents on a
#   `PresentIntent`, and waits on a `SyncFence` that holds a
#   `T.FenceHandle`. Buffer identity, fence identity and damage are
#   opaque/typed everywhere; there is no `UInt8` buffer index and no
#   `UInt64` "native" fence handle to reinterpret per backend.
#
# HOW IT RELATES TO OTHER SERVICES
#   accessibility.capnp owns the accessibility tree (this file only binds
#   a surface to a tree root). theme.capnp owns theme tokens (this file
#   only relays them). windowmanager.capnp places windows on these
#   outputs and imports this file's output types and session handshake.
#   shell.capnp aggregates; it does not re-describe surfaces.
#
# This file publishes the batch's canonical service-session handshake
# (`SessionRequest`/`SessionResponse`/`CapabilityRequest`); windowmanager,
# ime and shell import it rather than declaring rival shapes. Event unions
# terminate with the protocol's canonical `T.UnknownEvent`.
# ══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using Theme = import "theme.capnp";

# ══════════════════════════════════════════════════════════════════════
# SERVICE SESSION HANDSHAKE
#
# One pattern for every session-based service in the protocol: compositor,
# windowmanager, ime, shell. A capability kind invented in any later year
# is expressible on the day it is invented, because the request is a union
# whose `standard` arm is an OPEN TOKEN, not a frozen enum — the wm/shell/ime
# handshakes used to freeze their capability sets as closed enums, which
# made a future capability unrequestable without a schema edit.
#
# Authority: the granted references ARE the authority. Nothing in this
# file re-implements access control, and no method checks a permission
# string.
# ══════════════════════════════════════════════════════════════════════

struct SessionRequest {
    applicationId   @0 :T.AppId;
    applicationName @1 :Text;
    version         @2 :T.Version;
    protocolVersion @3 :T.Version;
    capabilities    @4 :List(CapabilityRequest);
    metadata        @5 :List(T.Meta);
}

struct SessionResponse {
    sessionId     @0 :T.SessionId;
    agreedVersion @1 :T.Version;
    granted       @2 :List(GrantedCapability);
    denied        @3 :List(DeniedCapability);
    service       @4 :ServiceInfo;
    result        @5 :HandshakeResult;
    metadata @6 :T.StringMap;
}

enum HandshakeResult {
    accepted             @0;
    acceptedDegraded     @1;
    rejectedNoCapacity   @2;
    rejectedUnauthorized @3;
    rejectedBadVersion   @4;
    other                @5;
    custom               @6;
}

# What a session-based service publishes about itself. `capabilities` is
# an open vocabulary — see the conformance tokens at the end of this file.
struct ServiceInfo {
    name         @0 :Text;
    version      @1 :T.Version;
    capabilities @2 :List(Text);
    metadata     @3 :List(T.Meta);
}

struct CapabilityRequest {
    union {
        # Open token. A capability the backend recognises is granted; one
        # it does not is denied with a reason, never silently ignored.
        standard @0 :Text;
        # Global hotkey registration, which needs a binding, not just a name.
        hotkeys  @1 :List(HotkeyRequest);
        # A capability with parameters the schema does not model.
        custom   @2 :CustomCapability;
        unknown  @3 :Void;
    }
}

struct HotkeyRequest {
    key         @0 :LogicalKey;
    modifiers   @1 :T.ModifierState;
    description @2 :Text;
}

struct CustomCapability {
    name       @0 :Text;
    parameters @1 :List(T.Meta);
}

struct GrantedCapability {
    capability @0 :CapabilityRequest;
    # Typed capability handle (opaque; backend-issued).
    capabilityHandle @1 :T.CapabilityHandle;
}

struct DeniedCapability {
    capability @0 :CapabilityRequest;
    reason     @1 :DenialReason;
    message    @2 :Text;
}

enum DenialReason {
    notSupported      @0;
    notAuthorized     @1;
    resourceExhausted @2;
    requiresConsent   @3;
    servicePolicy     @4;
    other             @5;
    custom            @6;
}

# ══════════════════════════════════════════════════════════════════════
# SESSION — the one compositor contract
#
# Ordinal policy. Cap'n Proto requires interface ordinals to be sequential
# with no holes, so removing a method renumbers the ones after it. Pre-release
# this is free, and the mapping below is recorded so an implementer holding an
# older draft never has to guess:
#
#   unchanged  @0–@23   (handshake … updateAccessibilityTree)
#   @24        defineAnimation          was @25
#   @25        setSpatialPose           was @26
#   @26        createSpatialAnchor      was @27
#   @27        destroySpatialAnchor     was @28
#   @28–@37    buffer/frame/capture/layer/inhibit surface, merged from the
#             deleted surface.capnp and the deleted flat `Compositor`
#             interface (attachBuffer, getSurfaceState, getFrameMetrics,
#             capture, listLayers, setSurfaceOrder, raiseSurface,
#             lowerSurface, inhibitOutput, uninhibitOutput)
#   deleted    createDisplayZone, setSurfaceAccessControl, getHealthCheck,
#             saveState/restoreState, setRemoteAccess,
#             get/setResourceLimits, add/removeKeyframe, playAnimation,
#             acquireDrmKeys/releaseDrmKeys, subscribeLiveRegionChanges,
#             getGestureResult, loadPlugin/unloadPlugin, and the whole
#             legacy flat `Compositor` interface with its four subscription
#             interfaces
# ══════════════════════════════════════════════════════════════════════

interface CompositorSession {

    struct HandshakeRequest {
        applicationId   @0 :T.AppId;
        applicationName @1 :Text;
        version         @2 :T.Version;
        protocolVersion @3 :T.Version;
        capabilities    @4 :List(CapabilityRequest);
        metadata        @5 :List(T.Meta);
    }

    struct HandshakeResponse {
        sessionId     @0 :T.SessionId;
        agreedVersion @1 :T.Version;
        granted       @2 :List(GrantedCapability);
        denied        @3 :List(DeniedCapability);
        compositor    @4 :ServiceInfo;
        result        @5 :HandshakeResult;
    }

    handshake @0 (request :HandshakeRequest)
               -> (response :HandshakeResponse);

    goodbye @1 (reason :GoodbyeReason) -> ();

    # ── Surface Management ────────────────────────────────────

    createSurface  @2 (request :SurfaceRequest)
                    -> (response :SurfaceResponse);

    destroySurface @3 (surface :T.SurfaceId)
                    -> (result :T.VoidResult);

    updateSurface  @4 (surface :T.SurfaceId, update :SurfaceUpdate)
                    -> (result :T.VoidResult);

    # ── Hot Path ──────────────────────────────────────────────

    commit @5 (commit :SurfaceCommit) -> (result :T.VoidResult);

    # ── Escape Hatch ──────────────────────────────────────────

    setSurfaceHints @6 (surface :T.SurfaceId, hints :SurfaceHints)
                     -> (result :T.VoidResult);

    # ── Cursor ────────────────────────────────────────────────

    setCursor          @7  (surface :T.SurfaceId, cursor :Cursor)
                           -> (result :T.VoidResult);
    resetCursor        @8  (surface :T.SurfaceId) -> (result :T.VoidResult);
    warpCursor         @9  (x :Int32, y :Int32) -> (result :T.VoidResult);
    warpCursorGlobal   @10 (x :Int32, y :Int32) -> (result :T.VoidResult);
    getCursorPosition  @11 () -> (state :CursorPosition);
    confineCursor      @12 (request :CursorConfinement)
                           -> (result :T.VoidResult);
    releaseCursor      @13 () -> (result :T.VoidResult);
    hideCursor         @14 () -> (result :T.VoidResult);
    showCursor         @15 () -> (result :T.VoidResult);
    getCursorTheme     @16 () -> (theme :CursorTheme);
    setCursorTheme     @17 (theme :CursorTheme) -> (result :T.VoidResult);
    listCursorThemes   @18 (pagination :T.Pagination)
                           -> (themes :List(CursorThemeInfo), total :UInt64);

    # ── Drag and Drop ─────────────────────────────────────────

    startDrag          @19 (request :DragStartRequest)
                           -> (result :DragStartResult);
    cancelDrag         @20 (session :T.DragSessionId) -> (result :T.VoidResult);

    # ── Query ─────────────────────────────────────────────────

    query @21 (query :Query, pagination :T.Pagination) -> (result :CompositorQueryResult);

    # ── Events ────────────────────────────────────────────────

    subscribe @22 (filter :EventFilter) -> (stream :EventStream);

    # ── Accessibility binding ─────────────────────────────────
    # The tree itself lives in accessibility.capnp. This binds a surface to
    # the root of its tree so a backend can route events to the right app.

    updateAccessibilityTree @23 (surface :T.SurfaceId, root :T.AccessNodeId)
                              -> T.VoidResult;

    # ── Animation ─────────────────────────────────────────────
    # Uses the canonical T.AnimationSpec. There is no keyframe interface:
    # keyframe interpolation is a rendering-engine concern, and
    # T.AnimationSpec already carries the curve and its parameters.

    defineAnimation @24 (request :AnimationDefinitionRequest)
                     -> (animationId :UInt64);

    # ── Spatial ───────────────────────────────────────────────

    setSpatialPose @25 (surface :T.SurfaceId, pose :SurfaceSpatialPose) -> T.VoidResult;
    createSpatialAnchor @26 (surface :T.SurfaceId, anchor :SpatialAnchor)
                         -> (anchorId :UInt64);
    destroySpatialAnchor @27 (anchorId :UInt64) -> T.VoidResult;

    # ── Buffers and frame state (merged from surface.capnp) ───

    attachBuffer @28 (surface :T.SurfaceId, buffer :T.BufferId,
                      offset :T.Vec2i) -> T.VoidResult;

    getSurfaceState @29 (surface :T.SurfaceId) -> (state :SurfaceState);

    getFrameMetrics @30 (surface :T.SurfaceId) -> (metrics :FrameMetrics);

    # ── Capture (merged from surface.capnp and the legacy flat interface) ──
    # One capture authority for the whole protocol. `format` is an open
    # content type: a 2035 codec needs no ordinal.

    capture @31 (request :CaptureRequest) -> (result :CompositorCaptureResult);

    # ── Layers and stacking (merged from the legacy flat interface) ──

    listLayers @32 (output :T.OutputId, pagination :T.Pagination)
               -> (layers :List(LayerInfo), total :UInt64);

    setSurfaceOrder @33 (surface :T.SurfaceId, order :SurfaceOrder)
                     -> (result :T.VoidResult);

    raiseSurface  @34 (surface :T.SurfaceId) -> (result :T.VoidResult);
    lowerSurface  @35 (surface :T.SurfaceId) -> (result :T.VoidResult);

    # ── Output power inhibition (merged from the legacy flat interface) ──

    inhibitOutput @36 (output :T.OutputId, reason :Text)
                   -> (handle :T.InhibitHandle);
    uninhibitOutput @37 (handle :T.InhibitHandle) -> (result :T.VoidResult);
}

# ── CompositorSession types ─────────────────────────────────────────────

struct CompositorInfo {
    name         @0 :Text;
    version      @1 :T.Version;
    capabilities @2 :List(Text);
    metadata     @3 :List(T.Meta);
}

enum GoodbyeReason {
    normal    @0;
    error     @1;
    restart   @2;
    other     @3;
    custom    @4;
}

# ── Surface ───────────────────────────────────────────────────

struct SurfaceRequest {
    # Open token. A surface kind is backend/WM policy, not interop: a
    # compositor for a paradigm with no "dialog" and no "dock" has no
    # ordinal to use. Conformance tokens are published at the end of this
    # file; an unrecognised role is treated as `other`.
    kind     @0 :Text;
    geometry @1 :GeometryHint;
    parent   @2 :T.SurfaceId;
    metadata @3 :List(T.Meta);
}

struct GeometryHint {
    rect      @0 :T.Rect;
    minSize   @1 :T.Vec2;
    maxSize   @2 :T.Vec2;
    placement @3 :PlacementHint;
    output    @4 :T.OutputId;
    scale     @5 :Float32;
}

enum PlacementHint {
    # Absent means the backend decides; it must never silently mean a
    # specific paradigm value.
    unspecified @0;
    compositorChooses @1;
    centered @2;
    underPointer @3;
    nearParent @4;
    cascadeFromParent @5;
    custom @6;
    other @7;
}

struct SurfaceResponse {
    surfaceId   @0 :T.SurfaceId;
    actualRect  @1 :T.Rect;
    bufferCount @2 :UInt8;
    result      @3 :SurfaceResult;
}

enum SurfaceResult {
    created            @0;
    createdDegraded    @1;
    rejected           @2;
    rejectedCapability @3;
    other              @4;
    custom             @5;
}

struct SurfaceUpdate {
    union {
        title       @0 :Text;
        appId       @1 :T.AppId;
        icon        @2 :IconData;
        metadata    @3 :List(T.Meta);
        geometry    @4 :GeometryHint;
        # Backend-specific update, as open key/value data.
        custom      @5 :T.StringMap;
        unknown     @6 :Void;
    }
}

struct IconData {
    union {
        named   @0 :Text;
        pixels  @1 :T.DataHandle;
        unknown @2 :Void;
    }
    size @3 :T.Vec2;
}

# ── Surface Hints ─────────────────────────────────────────────
# Declarations by the app; the compositor decides how to honour them.
# The rendering directives that used to live in surface.capnp
# (material vocabulary, blur radius, GPU selection) are gone: styling
# belongs to theme tokens and renderer choice belongs to the backend.

struct SurfaceHints {
    skipDecorations @0 :Bool;
    skipEffects     @1 :Bool;
    skipAnimations  @2 :Bool;
    privateContent  @3 :Bool;
    performanceMode @4 :Bool;
    exclusiveInput  @5 :Bool;
    exclusiveZone   @6 :Int32;
    anchor          @7 :AnchorEdges;
    layer           @8 :SurfaceLayer;
    interactivity   @9 :LayerInteractivity;
    inputRegion     @10 :T.Region;
    opaqueRegion    @11 :T.Region;
    cornerRadius    @12 :T.CornerRadius;
    shadow          @13 :ShadowShape;
    metadata        @14 :List(T.Meta);
}

struct AnchorEdges {
    top    @0 :Bool;
    bottom @1 :Bool;
    left   @2 :Bool;
    right  @3 :Bool;
}

enum SurfaceLayer {
    # Absent means the backend decides; it must never silently mean a
    # specific paradigm value.
    unspecified @0;
    background @1;
    bottom @2;
    top @3;
    overlay @4;
    other @5;
    custom @6;
}

enum LayerInteractivity {
    # Absent means the backend decides; it must never silently mean a
    # specific paradigm value.
    unspecified @0;
    none @1;
    onDemand @2;
    exclusive @3;
    other @4;
    custom @5;
}

# A shadow is DECLARED (it exists, its colour and offset); how it is
# rendered — blur radius, spread, shader — is the backend's business.
struct ShadowShape {
    enabled @0 :Bool;
    offset  @1 :T.Vec2;
    color   @2 :T.Color;
}

struct SurfaceOrder {
    union {
        raise   @0 :Void;
        lower   @1 :Void;
        above   @2 :T.SurfaceId;
        below   @3 :T.SurfaceId;
        unknown @4 :Void;
    }
}

struct LayerInfo {
    id       @0 :T.LayerId;
    name     @1 :Text;
    zBase    @2 :Int32;
    output   @3 :T.OutputId;
    surfaces @4 :List(T.SurfaceId);
}

# ── Surface state (merged from surface.capnp) ─────────────────

struct SurfaceState {
    id            @0 :T.SurfaceId;
    parent        @1 :T.SurfaceId;
    position      @2 :T.Vec2i;
    size          @3 :T.Size;
    scale         @4 :Float32;
    transform     @5 :T.BufferTransform;
    opacity       @6 :Float32;
    visible       @7 :Bool;
    mapped        @8 :Bool;
    hasInputRegion @9 :Bool;
    zIndex        @10 :Int32;
}

struct SurfaceInfo {
    surfaceId @0 :T.SurfaceId;
    kind      @1 :Text;
    rect      @2 :T.Rect;
    visible   @3 :Bool;
    focused   @4 :Bool;
    output    @5 :T.OutputId;
    metadata  @6 :List(T.Meta);
}

# ── Cursor ────────────────────────────────────────────────────

struct Cursor {
    union {
        named    @0 :T.CursorShape;
        surface  @1 :CursorImage;
        hidden   @2 :Void;
        unknown  @3 :Void;
    }
    hotspot @4 :T.Vec2i;
}

struct CursorImage {
    width  @0 :UInt32;
    height @1 :UInt32;
    hotX   @2 :Int32;
    hotY   @3 :Int32;
    pixels @4 :T.DataHandle;
    format @5 :T.PixelFormat;
    scale  @6 :Float32;
}

struct CursorPosition {
    x        @0 :Int32;
    y        @1 :Int32;
    shape    @2 :T.CursorShape;
    visible  @3 :Bool;
    confined @4 :Bool;
    surface  @5 :T.SurfaceId;
}

struct CursorConfinement {
    union {
        region  @0 :T.Rect;
        surface @1 :T.SurfaceId;
        output  @2 :T.OutputId;
        lock    @3 :Void;
        unknown @4 :Void;
    }
}

struct CursorTheme {
    name  @0 :Text;
    size  @1 :UInt32;
    scale @2 :Float32;
}

struct CursorThemeInfo {
    name        @0 :Text;
    description @1 :Text;
    sizes       @2 :List(UInt32);
}

# ══════════════════════════════════════════════════════════════════════
# THE COMMIT PATH
#
# One struct, typed end to end. `buffer` is the same `T.BufferId` that
# `attachBuffer` bound to the surface — there is no per-surface index and
# no re-interpretation of a number. `fence` holds a `T.FenceHandle`, never
# a raw "native" integer. `damage` is geometry.
# ══════════════════════════════════════════════════════════════════════

struct SurfaceCommit {
    surfaceId @0 :T.SurfaceId;
    frameId   @1 :UInt64;
    buffer    @2 :T.BufferId;
    format    @3 :T.PixelFormat;
    # Optional damage hint. If absent, the compositor tracks dirty state.
    damageOption @4 :DamageOption;
    present      @5 :PresentIntent;
    fence        @6 :SyncFence;
    transform    @7 :T.BufferTransform;
}

struct DamageOption {
    union {
        # No explicit damage hint from the app; compositor infers.
        omitted @0 :Void;
        # Full surface considered damaged (simplest, slowest).
        full    @1 :Void;
        # Specific rectangles carry damage.
        rects   @2 :List(T.Rect);
        # Backend extension: opaque damage blob, as content.
        custom  @3 :T.MimeType;
        unknown @4 :Void;
    }
}

struct PresentIntent {
    union {
        immediate @0 :Void;
        nextVsync @1 :Void;
        atTime    @2 :T.Timestamp;
        periodic  @3 :T.Duration;
        unknown   @4 :Void;
    }
}

struct SyncFence {
    union {
        handle  @0 :T.FenceHandle;
        none    @1 :Void;
        unknown @2 :Void;
    }
}

struct FrameSignal {
    surfaceId       @0 :T.SurfaceId;
    frameId         @1 :UInt64;
    nextPresentTime @2 :T.Timestamp;
    framePeriod     @3 :T.Duration;
    lastPresentTime @4 :T.Timestamp;
    onTime          @5 :Bool;
    dropped         @6 :UInt32;
}

# Frame metrics (merged from surface.capnp). `committedDamage` is
# geometry, never pixels.
struct FrameData {
    surfaceId       @0 :T.SurfaceId;
    frameId         @1 :UInt64;
    timestamp       @2 :T.Timestamp;
    size            @3 :T.Size;
    buffer          @4 :T.BufferId;
    presentationTime @5 :T.Timestamp;
    committedDamage @6 :T.Region;
}

struct FrameMetrics {
    frameCount    @0 :UInt64;
    lastFrameAt   @1 :T.Timestamp;
    avgFrameTime  @2 :T.Duration;
    droppedFrames @3 :UInt64;
    jankCount     @4 :UInt64;
}

# ── Drag and Drop ─────────────────────────────────────────────

struct DragOffer {
    mimeTypes @0 :List(T.MimeType);
    data      @1 :List(DragData);
    actions   @2 :List(DragAction);
}

struct DragData {
    mimeType @0 :T.MimeType;
    payload  @1 :T.DataHandle;
}

struct DragSession {
    id     @0 :T.DragSessionId;
    source @1 :T.SurfaceId;
    target @2 :T.SurfaceId;
    action    @3 :DragAction;
}

enum DragAction {
    none  @0;
    copy  @1;
    move  @2;
    link  @3;
    ask   @4;
    other @5;
    custom @6;
}

struct DragStartRequest {
    surface   @0 :T.SurfaceId;
    offer     @1 :DragOffer;
    actions   @2 :List(DragAction);
    thumbnail @3 :T.DataHandle;
    hotspot   @4 :T.Vec2i;
    metadata  @5 :List(T.Meta);
}

struct DragStartResult {
    union {
        session @0 :T.DragSessionId;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

# ── Capture ───────────────────────────────────────────────────
# One capture authority in the protocol. The requested form is an open
# content type, so a future image or video encoding needs no ordinal.

struct CaptureRequest {
    union {
        output  @0 :T.OutputId;
        surface @1 :T.SurfaceId;
        region  @2 :OutputRegion;
        unknown @3 :Void;
    }
    format @4 :T.MimeType;
}

struct OutputRegion {
    output @0 :T.OutputId;
    rect   @1 :T.Rect;
}

struct CompositorCaptureResult {
    union {
        frame   @0 :CaptureFrame;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct CaptureFrame {
    width     @0 :UInt32;
    height    @1 :UInt32;
    stride    @2 :UInt32;
    format    @3 :T.PixelFormat;
    timestamp @4 :T.Timestamp;
    pixels    @5 :T.DataHandle;
    metadata @6 :T.StringMap;
}

# ── Animation ─────────────────────────────────────────────────

struct AnimationDefinitionRequest {
    surface @0 :T.SurfaceId;
    property @1 :Text;
    spec @2 :T.AnimationSpec;
    # From/to values are open key/value pairs: any animatable property is
    # expressible without a new field.
    from @3 :T.StringMap;
    to   @4 :T.StringMap;
}

# ── Spatial ───────────────────────────────────────────────────

struct SurfaceSpatialPose {
    position @0 :T.Vec3;
    rotation @1 :T.Vec4;
    scale    @2 :T.Vec3;
    anchor   @3 :SpatialAnchor;
}

struct SpatialAnchor {
    union {
        # A backend-issued opaque anchor reference.
        reference @0 :UInt64;
        none      @1 :Void;
        unknown   @2 :Void;
    }
    # Whether this anchor survives a session (backend-reported).
    persistent @3 :Bool;
}

# ══════════════════════════════════════════════════════════════════════
# QUERY
# Every list answer is bounded: the caller passes a page and receives a
# total, so "500 of 3,400" is answerable and an empty list is
# distinguishable from a failed one (see `notSupported`).
# ══════════════════════════════════════════════════════════════════════

struct Query {
    union {
        allOutputs             @0 :Void;
        outputInfo             @1 :T.OutputId;
        mySurfaces             @2 :Void;
        surfaceInfo            @3 :T.SurfaceId;
        focusedSurface         @4 :Void;
        compositorCapabilities @5 :Void;
        compositorStats        @6 :Void;
        custom                 @7 :CustomQuery;
        unknown                @8 :Void;
    }
}

struct CustomQuery {
    name       @0 :Text;
    parameters @1 :List(T.Meta);
}

struct CompositorQueryResult {
    union {
        outputs      @0 :List(OutputInfo);
        outputInfo   @1 :OutputInfo;
        surfaces     @2 :List(SurfaceInfo);
        surfaceInfo  @3 :SurfaceInfo;
        capabilities @4 :List(Text);
        stats        @5 :CompositorStats;
        custom       @6 :List(T.Meta);
        notSupported @7 :Void;
        unknown      @8 :Void;
    }
    # Total number of items the query would return unpaged. Zero for
    # single-item and non-list answers.
    total @9 :UInt64;
}

# ── Outputs (canonical home; windowmanager imports these) ─────

struct OutputInfo {
    outputId                  @0 :T.OutputId;
    name                      @1 :Text;
    description               @2 :Text;
    physicalMillimetersWidth  @3 :UInt32;
    physicalMillimetersHeight @4 :UInt32;
    resolution                @5 :T.Vec2i;
    refreshRate               @6 :T.FrameRate;
    position                  @7 :T.Vec2i;
    scale                     @8 :Float32;
    primary                   @9 :Bool;
    connected                 @10 :Bool;
    enabled                   @11 :Bool;
    modes                     @12 :List(OutputMode);
}

struct OutputMode {
    width       @0 :UInt32;
    height      @1 :UInt32;
    refreshRate @2 :T.FrameRate;
    preferred   @3 :Bool;
}

struct CompositorStats {
    activeSessions @0 :UInt32;
    activeSurfaces @1 :UInt32;
    activeOutputs  @2 :UInt32;
    cpuTime        @3 :T.Duration;
    gpuTime        @4 :T.Duration;
    frameTime      @5 :T.Duration;
    droppedFrames  @6 :UInt64;
    uptime         @7 :T.Duration;
    memoryBytes    @8 :UInt64;
}

# ══════════════════════════════════════════════════════════════════════
# EVENTS
# One stream, pull-based, bounded by the caller. `unknown` carries a typed
# discriminator so a consumer can route an event kind it has never seen.
# ══════════════════════════════════════════════════════════════════════

interface EventStream {
    pull   @0 (maxEvents :UInt32) -> (events :List(CompositorEvent));
    cancel @1 () -> T.VoidResult;
}

struct EventFilter {
    surfaceIds @0 :List(T.SurfaceId);
    eventKinds @1 :List(EventKind);
}

enum EventKind {
    surfaceEvents     @0;
    frameEvents       @1;
    inputEvents       @2;
    focusEvents       @3;
    outputEvents      @4;
    compositorEvents  @5;
    dragEvents        @6;
    themeEvents       @7;
    accessibilityEvents @8;
    other             @9;
    custom            @10;
}

struct CompositorEvent {
    union {
    surfaceCreated         @0  :SurfaceInfo;
    surfaceDestroyed       @1  :T.SurfaceId;
    surfaceGeometryChanged @2  :SurfaceGeometryEvent;
    surfaceStateChanged    @3  :SurfaceStateEvent;
    surfaceOrderChanged    @4  :SurfaceOrderEvent;

    frameReady             @5  :FrameSignal;
    framePresented         @6  :FrameSignal;

    pointerEnter           @7  :PointerEnterEvent;
    pointerLeave           @8  :PointerLeaveEvent;
    pointerMove            @9  :PointerMoveEvent;
    pointerButton          @10 :PointerButtonEvent;
    pointerScroll          @11 :PointerScrollEvent;
    keyboardKey            @12 :KeyboardKeyEvent;
    keyboardModifiers      @13 :KeyboardModifiersEvent;
    touchDown              @14 :TouchDownEvent;
    touchUp                @15 :TouchUpEvent;
    touchMove              @16 :TouchMoveEvent;

    stylusDown             @17 :StylusEvent;
    stylusUp               @18 :StylusEvent;
    stylusMove             @19 :StylusEvent;
    stylusButton           @20 :StylusButtonEvent;

    gestureSwipeBegin      @21 :GestureSwipeEvent;
    gestureSwipeUpdate     @22 :GestureSwipeEvent;
    gestureSwipeEnd        @23 :GestureSwipeEvent;
    gesturePinchBegin      @24 :GesturePinchEvent;
    gesturePinchUpdate     @25 :GesturePinchEvent;
    gesturePinchEnd        @26 :GesturePinchEvent;

    focusGained            @27 :SurfaceFocusEvent;
    focusLost              @28 :SurfaceFocusEvent;

    outputAdded            @29 :OutputInfo;
    outputRemoved          @30 :T.OutputId;
    outputChanged          @31 :OutputInfo;

    compositorReady        @32 :CompositorInfo;
    compositorShutdown     @33 :ShutdownEvent;

    cursorChanged          @34 :CursorChangedEvent;

    dragEntered            @35 :DragEnteredEvent;
    dragMoved              @36 :DragMovedEvent;
    dragDropped            @37 :DragDroppedEvent;
    dragFinished           @38 :DragFinishedEvent;
    dragCancelled          @39 :Void;

    themeChanged           @40 :ThemeChangedEvent;

    accessibilityTreeChanged @41 :AccessibilityTreeChangedEvent;

    unknown                @42 :T.UnknownEvent;
    }
}

# ── Event details ─────────────────────────────────────────────

struct SurfaceGeometryEvent {
    surfaceId @0 :T.SurfaceId;
    oldRect   @1 :T.Rect;
    newRect   @2 :T.Rect;
}

struct SurfaceStateEvent {
    surfaceId @0 :T.SurfaceId;
    visible   @1 :Bool;
    focused   @2 :Bool;
}

struct SurfaceOrderEvent {
    surfaceId @0 :T.SurfaceId;
    order     @1 :SurfaceOrder;
    metadata @2 :T.StringMap;
}

struct PointerEnterEvent {
    surfaceId @0 :T.SurfaceId;
    x         @1 :Float32;
    y         @2 :Float32;
    timestamp @3 :T.Timestamp;
}

struct PointerLeaveEvent {
    surfaceId @0 :T.SurfaceId;
    timestamp @1 :T.Timestamp;
}

struct PointerMoveEvent {
    surfaceId @0 :T.SurfaceId;
    x         @1 :Float32;
    y         @2 :Float32;
    deltaX    @3 :Float32;
    deltaY    @4 :Float32;
    timestamp @5 :T.Timestamp;
    buttons   @6 :ButtonState;
}

struct PointerButtonEvent {
    surfaceId  @0 :T.SurfaceId;
    x          @1 :Float32;
    y          @2 :Float32;
    button     @3 :PointerButton;
    action     @4 :ButtonAction;
    timestamp  @5 :T.Timestamp;
    clickCount @6 :UInt8;
}

enum PointerButton {
    left    @0;
    right   @1;
    middle  @2;
    back    @3;
    forward @4;
    other   @5;
    custom  @6;
}

enum ButtonAction {
    pressed  @0;
    released @1;
    other    @2;
    custom   @3;
}

struct ButtonState {
    left    @0 :Bool;
    right   @1 :Bool;
    middle  @2 :Bool;
    back    @3 :Bool;
    forward @4 :Bool;
}

struct PointerScrollEvent {
    surfaceId  @0 :T.SurfaceId;
    x          @1 :Float32;
    y          @2 :Float32;
    deltaX     @3 :Float32;
    deltaY     @4 :Float32;
    discreteX  @5 :Int32;
    discreteY  @6 :Int32;
    source     @7 :ScrollSource;
    stopX      @8 :Bool;
    stopY      @9 :Bool;
    timestamp @10 :T.Timestamp;
}

enum ScrollSource {
    wheel      @0;
    finger     @1;
    continuous @2;
    other      @3;
    custom     @4;
}

struct KeyboardKeyEvent {
    surfaceId @0 :T.SurfaceId;
    # The logical key. `name` is an open token and `codepoint` is Unicode:
    # neither asserts a particular keyboard layout or key-numbering scheme.
    key       @1 :LogicalKey;
    scancode  @2 :UInt32;
    transition @3 :KeyTransition;
    modifiers @4 :T.ModifierState;
    timestamp @5 :T.Timestamp;
    text      @6 :Text;
    repeated  @7 :Bool;
}

struct LogicalKey {
    name      @0 :Text;
    codepoint @1 :UInt32;
}

enum KeyTransition {
    pressed  @0;
    released @1;
    other    @2;
    custom   @3;
}

struct KeyboardModifiersEvent {
    surfaceId @0 :T.SurfaceId;
    modifiers @1 :T.ModifierState;
    timestamp @2 :T.Timestamp;
}

struct TouchDownEvent {
    surfaceId @0 :T.SurfaceId;
    touchId   @1 :UInt32;
    x         @2 :Float32;
    y         @3 :Float32;
    pressure  @4 :Float32;
    majorAxis @5 :Float32;
    minorAxis @6 :Float32;
    timestamp @7 :T.Timestamp;
}

struct TouchUpEvent {
    surfaceId @0 :T.SurfaceId;
    touchId   @1 :UInt32;
    timestamp @2 :T.Timestamp;
}

struct TouchMoveEvent {
    surfaceId @0 :T.SurfaceId;
    touchId   @1 :UInt32;
    x         @2 :Float32;
    y         @3 :Float32;
    pressure  @4 :Float32;
    majorAxis @5 :Float32;
    minorAxis @6 :Float32;
    timestamp @7 :T.Timestamp;
}

struct StylusEvent {
    surfaceId @0 :T.SurfaceId;
    toolId    @1 :UInt32;
    x         @2 :Float32;
    y         @3 :Float32;
    pressure  @4 :Float32;
    tiltX     @5 :Float32;
    tiltY     @6 :Float32;
    rotation  @7 :Float32;
    distance  @8 :Float32;
    toolType  @9 :Text;
    timestamp @10 :T.Timestamp;
}

struct StylusButtonEvent {
    surfaceId @0 :T.SurfaceId;
    toolId    @1 :UInt32;
    button    @2 :UInt32;
    pressed   @3 :Bool;
    timestamp @4 :T.Timestamp;
}

struct GestureSwipeEvent {
    surfaceId @0 :T.SurfaceId;
    fingers   @1 :UInt32;
    dx        @2 :Float32;
    dy        @3 :Float32;
    cancelled @4 :Bool;
    timestamp @5 :T.Timestamp;
}

struct GesturePinchEvent {
    surfaceId @0 :T.SurfaceId;
    fingers   @1 :UInt32;
    dx        @2 :Float32;
    dy        @3 :Float32;
    scale     @4 :Float32;
    rotation  @5 :Float32;
    cancelled @6 :Bool;
    timestamp @7 :T.Timestamp;
}

struct SurfaceFocusEvent {
    surfaceId @0 :T.SurfaceId;
    reason    @1 :FocusReason;
    timestamp @2 :T.Timestamp;
}

enum FocusReason {
    userClick     @0;
    programmatic  @1;
    tabNavigation @2;
    touchscreen   @3;
    unknown       @4;
    other         @5;
    custom        @6;
}

struct ShutdownEvent {
    reason      @0 :ShutdownReason;
    gracePeriod @1 :T.Duration;
    message     @2 :Text;
}

enum ShutdownReason {
    compositorExit    @0;
    systemShutdown    @1;
    systemRestart     @2;
    compositorRestart @3;
    other             @4;
    custom            @5;
}

struct CursorChangedEvent {
    surfaceId @0 :T.SurfaceId;
    cursor    @1 :Cursor;
    timestamp @2 :T.Timestamp;
}

# ── Drag and drop events ──────────────────────────────────────

struct DragEnteredEvent {
    sessionId @0 :T.DragSessionId;
    surfaceId @1 :T.SurfaceId;
    position  @2 :T.Vec2;
    offer     @3 :DragOffer;
}

struct DragMovedEvent {
    sessionId @0 :T.DragSessionId;
    surfaceId @1 :T.SurfaceId;
    position  @2 :T.Vec2;
    action    @3 :DragAction;
}

struct DragDroppedEvent {
    sessionId @0 :T.DragSessionId;
    surfaceId @1 :T.SurfaceId;
    position  @2 :T.Vec2;
    offer     @3 :DragOffer;
    action    @4 :DragAction;
}

struct DragFinishedEvent {
    sessionId @0 :T.DragSessionId;
    action    @1 :DragAction;
}

# ── Theme and accessibility events ────────────────────────────
# Both relay the canonical contracts; neither re-declares a model.

struct ThemeChangedEvent {
    tokens @0 :Theme.ThemeTokens;
}

struct AccessibilityTreeChangedEvent {
    surfaceId @0 :T.SurfaceId;
    root      @1 :T.AccessNodeId;
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Nothing above depends on any value in this section. They are published so
# that today's tools have a discoverable spelling for surface kinds and
# capability kinds; an unrecognised value MUST be ignored, never rejected.
# They are Text and never enums: an enum here would be an eternal
# commitment to today's spelling.
# ══════════════════════════════════════════════════════════════════════

const kindWindow           :Text = "window";
const kindDialog           :Text = "dialog";
const kindTooltip          :Text = "tooltip";
const kindPopup            :Text = "popup";
const kindMenu             :Text = "menu";
const kindNotification     :Text = "notification";
const kindPanel            :Text = "panel";
const kindWallpaper        :Text = "wallpaper";
const kindOverlay          :Text = "overlay";
const kindSplash           :Text = "splash";
const kindScreensaver      :Text = "screensaver";
const kindKiosk            :Text = "kiosk";
const kindDock             :Text = "dock";
const kindOnScreenDisplay  :Text = "osd";
const kindVirtualKeyboard  :Text = "virtualKeyboard";
const kindOther            :Text = "other";

const capCreateWindow      :Text = "createWindow";
const capCreatePopup       :Text = "createPopup";
const capCreateOverlay     :Text = "createOverlay";
const capCreatePanel       :Text = "createPanel";
const capCreateWallpaper   :Text = "createWallpaper";
const capCaptureOwn        :Text = "captureOwn";
const capCaptureOutput     :Text = "captureOutput";
const capCaptureAll        :Text = "captureAll";
const capCapturePrivate    :Text = "capturePrivate";
const capReceiveInput      :Text = "receiveInput";
const capExclusiveInput    :Text = "exclusiveInput";
const capGlobalHotkeys     :Text = "globalHotkeys";
const capQueryOutputs      :Text = "queryOutputs";
const capConfigureOutput   :Text = "configureOutput";
const capSetCursor         :Text = "setCursor";
const capConfineCursor     :Text = "confineCursor";
const capWarpCursor        :Text = "warpCursor";
const capSetCursorTheme    :Text = "setCursorTheme";
const capStartDrag         :Text = "startDrag";
const capReadTheme         :Text = "readTheme";
const capReadAccessibility :Text = "readAccessibility";

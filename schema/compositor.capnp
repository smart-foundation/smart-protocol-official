@0xa1b2c3d4e5f60005;

# ══════════════════════════════════════════════════════════════════════
# Compositor — display composition, surface management, input routing,
# drag-and-drop, accessibility, and theming. Backend-agnostic: works
# with Wayland, X11, macOS CoreGraphics, or custom compositors.
#
# Improvements:
#   - Session.HandshakeRequest.applicationId uses T.AppId.
#   - SurfaceUpdate.appId uses T.AppId.
#   - ShutdownEvent.gracePeriodMs → T.Duration (backend-agnostic time).
#   - DndEvent.action uses typed DragAction enum.
#   - All Data payloads >1KB use T.DataHandle (DragData, thumbnails,
#     icons, cursor images, unknown events).
#   - CompositorStats time fields use T.Duration.
#   - AccessibilityAction.id uses T.AccessNodeId.
#   - listLayers accepts T.Pagination.
#   - All subscription interfaces have cancel methods.
#   - All enums have other/custom variants for forward compatibility.
#
# Audit-7 improvements:
#   - SurfaceRole extended: gameLoop, voiceOnly, spatialAnchor, splitZone, floatingPin.
#   - HdrMetadata struct for HDR color management.
#   - SpatialPose / SpatialAnchor for AR/VR spatial surfaces.
#   - DisplayZone for multi-display orchestration.
#   - AnimationDefinition for animation pipeline.
#   - SurfaceAccessControl for per-surface security.
#   - CompositorHealth for health monitoring.
#   - StateSnapshot for state persistence.
#   - RemoteAccessConfig for remote compositor access.
#   - ResourceLimits for GPU/surface resource management.
#   - Session methods: updateAccessibilityTree, createDisplayZone, defineAnimation,
#     setSpatialPose, createSpatialAnchor, setSurfaceAccessControl, getHealthCheck,
#     saveState, restoreState, setRemoteAccess, getResourceLimits, setResourceLimits.
# ══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ══════════════════════════════════════════════════════════════════════
# SESSION (new interface, ordinal 13)
# Every app starts here. One session per app.
# ══════════════════════════════════════════════════════════════════════

interface Session {

    struct HandshakeRequest {
        applicationId   @0 :T.AppId;
        applicationName @1 :Text;
        version         @2 :T.Version;
        protocolVersion @3 :T.Version;
        capabilities    @4 :List(CapabilityRequest);
        metadata        @5 :List(T.Meta);
    }

    struct HandshakeResponse {
        sessionId      @0 :T.SessionId;
        agreedVersion  @1 :T.Version;
        granted        @2 :List(GrantedCapability);
        denied         @3 :List(DeniedCapability);
        compositor     @4 :CompositorInfo;
        result         @5 :HandshakeResult;
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

    commit         @5 (commit :SurfaceCommit) -> ();

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
    listCursorThemes   @18 (pagination :T.Pagination) -> (themes :List(CursorThemeInfo), totalCount :UInt32);

    # ── Drag and Drop ─────────────────────────────────────────

    startDrag          @19 (request :DragStartRequest)
                           -> (result :DragStartResult);
    cancelDrag         @20 (session :T.DragSessionId) -> (result :T.VoidResult);

    # ── Query ─────────────────────────────────────────────────

    query           @21 (query :Query) -> (result :QueryResult);

    # ── Events ────────────────────────────────────────────────

    subscribe       @22 (filter :EventFilter)
                    -> (stream :EventStream);

    # ── Accessibility tree propagation (audit-7) ──
    updateAccessibilityTree @23 (surface :T.SurfaceId, tree :AccessibilityTree) -> T.VoidResult;

    # ── Multi-display zone coordination (audit-7) ──
    createDisplayZone @24 (request :DisplayZoneRequest) -> (zone :DisplayZone);

    # ── Animation pipeline (audit-7) ──
    defineAnimation @25 (request :AnimationDefinitionRequest) -> (animationId :UInt64);

    # ── Spatial surface management (audit-7 false positive: compositor_spatial.capnp belongs here) ──
    setSpatialPose @26 (surface :T.SurfaceId, pose :SpatialPose) -> T.VoidResult;
    createSpatialAnchor @27 (surface :T.SurfaceId, anchor :SpatialAnchor) -> T.VoidResult;
    destroySpatialAnchor @28 (anchorId :Text) -> T.VoidResult;

    # ── Surface security (audit-7) ──
    setSurfaceAccessControl @29 (surface :T.SurfaceId, control :SurfaceAccessControl) -> T.VoidResult;

    # ── Compositor health (audit-7) ──
    getHealthCheck @30 () -> (health :CompositorHealth);

    # ── Compositor state persistence (audit-7) ──
    saveState @31 () -> (snapshot :StateSnapshot);
    restoreState @32 (snapshot :StateSnapshot) -> T.VoidResult;

    # ── Remote compositor access (audit-7) ──
    setRemoteAccess @33 (config :RemoteAccessConfig) -> T.VoidResult;

    # ── Compositor resource management (audit-7) ──
    getResourceLimits @34 () -> (limits :ResourceLimits);
    setResourceLimits @35 (limits :ResourceLimits) -> T.VoidResult;

    # ── Animation engine keyframe methods (audit-9 What's Still Missing) ──
    addKeyframe @36 (animationId :UInt64, keyframe :Keyframe) -> T.VoidResult;
    removeKeyframe @37 (animationId :UInt64, keyframeIndex :UInt32) -> T.VoidResult;
    playAnimation @38 (animationId :UInt64) -> T.VoidResult;

    # ── DRM session management (audit-9 What's Still Missing) ──
    acquireDrmKeys @39 (surface :T.SurfaceId, drmInfo :DrmInfo) -> (keyHandle :UInt64);
    releaseDrmKeys @40 (keyHandle :UInt64) -> T.VoidResult;

    # ── Live region accessibility events (audit-9 What's Still Missing) ──
    subscribeLiveRegionChanges @41 (filter :LiveRegionFilter) -> (subscription :LiveRegionSubscription);

    # ── Gesture recognition results (audit-9 What's Still Missing) ──
    getGestureResult @42 (sessionId :T.DragSessionId) -> (result :GestureResult);

    # ── Plugin loading/unloading (audit-9 What's Still Missing) ──
    loadPlugin @43 (pluginId :Text) -> (plugin :PluginInfo);
    unloadPlugin @44 (pluginId :Text) -> T.VoidResult;
}

# ══════════════════════════════════════════════════════════════════════
# EXISTING COMPOSITOR INTERFACE
# Ordinals 0-25 preserved exactly as-is.
# ══════════════════════════════════════════════════════════════════════

interface Compositor {
    createLayer @0 (outputId :T.OutputId) -> (layerId :UInt64);
    destroyLayer @1 (layerId :UInt64) -> T.VoidResult;
    reorderLayers @2 (outputId :T.OutputId, layers :List(UInt64)) -> T.VoidResult;
    addSurface @3 (layerId :UInt64, surfaceId :T.SurfaceId) -> T.VoidResult;
    removeSurface @4 (layerId :UInt64, surfaceId :T.SurfaceId) -> T.VoidResult;

    setCursor @5 (surfaceId :T.SurfaceId, hotspot :T.Vec2i) -> T.VoidResult;
    hideCursor @6 () -> T.VoidResult;
    showCursor @7 () -> T.VoidResult;
    warpCursor @8 (position :T.Vec2i) -> T.VoidResult;
    confineCursor @9 (region :T.Region) -> T.VoidResult;
    getCursorState @10 () -> (state :CursorState);

    startDrag @11 (surfaceId :T.SurfaceId, icon :T.SurfaceId, source :Text) -> (sessionId :T.DragSessionId);
    cancelDrag @12 (sessionId :T.DragSessionId) -> T.VoidResult;
    subscribeDnd @13 () -> (subscription :DndSubscription);

    setInputFocus @14 (surfaceId :T.SurfaceId) -> T.VoidResult;
    subscribeInput @15 () -> (subscription :InputSubscription);

    requestFrameCallback @16 (callback :UInt64) -> T.VoidResult;

    inhibitScreensaver @17 (clientId :T.ClientId, reason :Text) -> (handle :T.InhibitHandle);
    uninhibit @18 (handle :T.InhibitHandle) -> T.VoidResult;

    captureOutput @19 (outputId :T.OutputId, format :T.PixelFormat) -> (captureId :T.CaptureId);

    setCursorShape @20 (shape :T.CursorShape) -> T.VoidResult;

    listLayers @21 (outputId :T.OutputId, pagination :T.Pagination) -> (layers :List(LayerInfo), totalCount :UInt32);

    subscribeGestures @22 () -> (subscription :GestureSubscription);
}

interface DndSubscription {
    pull @0 () -> (event :DndEvent);

    # Explicitly cancel this subscription and release resources.
    cancel @1 () -> T.VoidResult;
}

interface InputSubscription {
    pull @0 () -> (event :InputEvent);

    # Explicitly cancel this subscription and release resources.
    cancel @1 () -> T.VoidResult;
}

struct CursorState {
    surfaceId @0 :T.SurfaceId;
    hotspot @1 :T.Vec2i;
    position @2 :T.Vec2i;
    visible @3 :Bool;
}

struct DndEvent {
    sessionId @0 :T.DragSessionId;
    action @1 :DragAction;
    position @2 :T.Vec2i;
    mimeTypes @3 :List(Text);
}

struct InputEvent {
    type @0 :InputEventType;
    timestamp @1 :T.Timestamp;
    keyboard @2 :KeyboardEvent;
    pointer @3 :PointerEvent;
    touch @4 :TouchEvent;
    scroll @5 :ScrollEvent;
}

enum InputEventType {
    keyboard @0;
    pointer @1;
    touch @2;
    gamepad @3;
    scroll @4;
    other @5;
    custom @6;
}

struct KeyboardEvent {
    key @0 :UInt32;
    scancode @1 :UInt32;
    mods @2 :T.ModifierState;
    pressed @3 :Bool;
}

struct PointerEvent {
    button @0 :UInt32;
    position @1 :T.Vec2i;
    delta @2 :T.Vec2i;
    buttons @3 :UInt32;
    mods @4 :T.ModifierState;
}

struct TouchEvent {
    slot @0 :Int32;
    position @1 :T.Vec2i;
    pressure @2 :Float32;
    touched @3 :Bool;
}

struct ScrollEvent {
    position @0 :T.Vec2i;
    scrollX @1 :Float32;
    scrollY @2 :Float32;
    discreteX @3 :Int32;
    discreteY @4 :Int32;
    mods @5 :T.ModifierState;
}

struct LayerInfo {
    id @0 :UInt64;                    # Deprecated: use layerId. Kept for ordinal stability.
    name @1 :Text;
    zBase @2 :Int32;
    surfaces @3 :List(T.SurfaceId);
    # Typed layer identifier (preferred over raw id field above).
    layerId @4 :T.LayerId;
}

interface GestureSubscription {
    pull @0 () -> (event :T.GestureEvent);

    # Explicitly cancel this subscription and release resources.
    cancel @1 () -> T.VoidResult;
}

# ── Session Types (moved from inside Session interface) ──────

struct CompositorInfo {
    name            @0 :Text;
    version         @1 :T.Version;
    protocolVersion @2 :T.Version;
    capabilities    @3 :List(CapabilityKind);
    backend         @4 :BackendKind;
    metadata        @5 :List(T.Meta);
}

enum BackendKind {
    native   @0;
    nested   @1;
    remote   @2;
    headless @3;
    embedded @4;
    unknown  @5;
    custom   @6;
}

enum GoodbyeReason {
    normal    @0;
    error     @1;
    restart   @2;
    other     @3;
    custom    @4;
}

# ── Surface ──────────────────────────────────────────────────

struct SurfaceRequest {
    role     @0 :SurfaceRole;
    geometry @1 :GeometryHint;
    parent   @2 :T.SurfaceId;
    metadata @3 :List(T.Meta);
}

enum SurfaceRole {
    window         @0;
    dialog         @1;
    tooltip        @2;
    popup          @3;
    menu           @4;
    notification   @5;
    panel          @6;
    wallpaper      @7;
    overlay        @8;
    splash         @9;
    screensaver    @10;
    spatial        @11;
    kiosk          @12;
    dock           @13;
    osd            @14;
    virtualKeyboard @15;
    accessibility  @16;
    custom         @17;
    other          @18;
    # Audit-7 additions: multi-device surface classes
    gameLoop       @19;
    voiceOnly      @20;
    spatialAnchor  @21;
    splitZone      @22;
    floatingPin    @23;
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
    compositorChooses @0;
    centered          @1;
    underPointer      @2;
    nearParent        @3;
    cascadeFromParent @4;
    custom            @5;
    other             @6;
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
        title    @0 :Text;
        appId    @1 :T.AppId;
        icon     @2 :IconData;
        metadata @3 :List(T.Meta);
        accessibilityTree @4 :AccessibilityTree;
    }
}

struct IconData {
    union {
        named  @0 :Text;
        pixels @1 :T.DataHandle;
    }
    size @2 :T.Vec2;
}

# ── Surface Hints ────────────────────────────────────────────

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
    metadata       @10 :List(T.Meta);
}

struct AnchorEdges {
    top    @0 :Bool;
    bottom @1 :Bool;
    left   @2 :Bool;
    right  @3 :Bool;
}

enum SurfaceLayer {
    background @0;
    bottom     @1;
    top        @2;
    overlay    @3;
    other      @4;
    custom     @5;
}

enum LayerInteractivity {
    none      @0;
    onDemand  @1;
    exclusive @2;
    other     @3;
    custom    @4;
}

# ── Cursor ───────────────────────────────────────────────────

struct Cursor {
    union {
        named    @0 :T.CursorShape;
        surface  @1 :CursorImage;
        hidden   @2 :Void;
    }
    hotspot @3 :T.Vec2i;
}

struct CursorImage {
    width  @0 :UInt32;
    height @1 :UInt32;
    hotX   @2 :Int32;
    hotY   @3 :Int32;
    # Inline for small cursors; use buffer reference for large/high-res cursors.
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

# ── Commit ───────────────────────────────────────────────────

struct SurfaceCommit {
    surfaceId   @0 :T.SurfaceId;
    frameId     @1 :UInt64;
    bufferIndex @2 :UInt8;
    format      @3 :T.PixelFormat;
    # Optional damage hint. If absent, compositor tracks dirty-state itself.
    # Apps that track their own damaged regions pass them; apps that can't
    # simply omit the field (compositor still optimizes via implicit damage).
    damageOption @4 :DamageOption;
    present     @5 :PresentIntent;
    fence       @6 :SyncFence;
    transform   @7 :T.BufferTransform;
}

struct DamageOption {
    union {
        # No explicit damage hint from the app; compositor infers from state.
        omitted @0 :Void;
        # Full surface considered damaged (simplest, slowest).
        full    @1 :Void;
        # Specific rectangles carry damage.
        rects   @2 :List(T.Rect);
        # Backend-extension: opaque damage blob (engine-specific).
        custom  @3 :Data;
    }
}

struct DamageRegion {
    union {
        full  @0 :Void;
        rects @1 :List(T.Rect);
        none  @2 :Void;
    }
}

struct PresentIntent {
    union {
        immediate @0 :Void;
        nextVsync @1 :Void;
        atTime    @2 :T.Timestamp;
    }
}

struct SyncFence {
    union {
        native @0 :UInt64;
        none   @1 :Void;
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

# ── Drag and Drop ────────────────────────────────────────────

struct DragOffer {
    mimeTypes @0 :List(Text);
    data      @1 :List(DragData);
    actions   @2 :List(DragAction);
}

struct DragData {
    mimeType @0 :Text;
    # Inline for small payloads; use buffer reference for large drag data.
    payload  @1 :T.DataHandle;
}

struct DragSession {
    id     @0 :T.DragSessionId;
    source @1 :T.SurfaceId;
    target @2 :T.SurfaceId;
    action @3 :DragAction;
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
    surface    @0 :T.SurfaceId;
    offer      @1 :DragOffer;
    actions    @2 :List(DragAction);
    # Inline for small thumbnails; use buffer reference for large previews.
    thumbnail  @3 :T.DataHandle;
    hotspot    @4 :T.Vec2i;
    metadata   @5 :List(T.Meta);
}

struct DragStartResult {
    union {
        session @0 :T.DragSessionId;
        error   @1 :T.Error;
    }
}

# ── Theme ────────────────────────────────────────────────────

struct Theme {
    colorScheme    @0 :ColorScheme;
    accentColor    @1 :T.Color;
    fontScale      @2 :Float32;
    cursorSize     @3 :UInt32;
    cursorTheme    @4 :Text;
    iconTheme      @5 :Text;
    animations     @6 :AnimationPreferences;
    reducedMotion  @7 :Bool;
    highContrast   @8 :Bool;
    metadata       @9 :List(T.Meta);
}

enum ColorScheme {
    light  @0;
    dark   @1;
    system @2;
    other  @3;
    custom @4;
}

struct AnimationPreferences {
    enabled     @0 :Bool;
    speedScale  @1 :Float32;
    reduceMotion @2 :Bool;
}

# ── Accessibility ────────────────────────────────────────────

struct AccessibilityNode {
    id          @0 :T.AccessNodeId;
    role        @1 :AccessibilityRole;
    name        @2 :Text;
    description @3 :Text;
    value       @4 :Text;
    state       @5 :AccessibilityState;
    bounds      @6 :T.Rect;
    children    @7 :List(T.AccessNodeId);
    actions     @8 :List(AccessibilityAction);
    metadata    @9 :List(T.Meta);
}

enum AccessibilityRole {
    window        @0;
    panel         @1;
    button        @2;
    link          @3;
    menuItem      @4;
    radioButton   @5;
    checkBox      @6;
    text          @7;
    textField     @8;
    comboBox      @9;
    slider        @10;
    image         @11;
    separator     @12;
    progressBar   @13;
    scrollBar     @14;
    tree          @15;
    treeItem      @16;
    list          @17;
    listItem      @18;
    table         @19;
    tableRow      @20;
    tableCell     @21;
    tab           @22;
    tabPanel      @23;
    menu          @24;
    toolBar       @25;
    statusBar     @26;
    alert         @27;
    dialog        @28;
    titleBar      @29;
    application   @30;
    group         @31;
    heading       @32;
    label         @33;
    tooltip       @34;
    popUp         @35;
    notification  @36;
    custom        @37;
    other         @38;
}

struct AccessibilityState {
    enabled       @0 :Bool;
    focused       @1 :Bool;
    selected      @2 :Bool;
    checked       @3 :Bool;
    expanded      @4 :Bool;
    collapsed     @5 :Bool;
    invisible     @6 :Bool;
    modal         @7 :Bool;
    multiline     @8 :Bool;
    required      @9 :Bool;
    editable      @10 :Bool;
    draggable     @11 :Bool;
    droppable     @12 :Bool;
    protected     @13 :Bool;
    busy          @14 :Bool;
}

struct AccessibilityAction {
    id    @0 :T.AccessNodeId;
    name  @1 :Text;
    description @2 :Text;
}

struct AccessibilityTree {
    root   @0 :T.AccessNodeId;
    nodes  @1 :List(AccessibilityNode);
}

# ── Query ────────────────────────────────────────────────────

struct Query {
    union {
        allOutputs             @0 :Void;
        outputInfo             @1 :T.OutputId;
        mySurfaces             @2 :Void;
        surfaceInfo            @3 :T.SurfaceId;
        focusedSurface         @4 :Void;
        compositorCapabilities @5 :Void;
        supportedFeatures      @6 :Void;
        compositorStats        @7 :Void;
        custom                 @8 :CustomQuery;
    }
}

struct CustomQuery {
    name       @0 :Text;
    parameters @1 :List(T.Meta);
}

struct QueryResult {
    union {
        outputs        @0 :List(OutputInfo);
        outputInfo     @1 :OutputInfo;
        surfaces       @2 :List(SurfaceInfo);
        surfaceInfo    @3 :SurfaceInfo;
        capabilities   @4 :List(CapabilityKind);
        features       @5 :List(Text);
        stats          @6 :CompositorStats;
        custom         @7 :List(T.Meta);
        notSupported   @8 :Void;
    }
}

struct SurfaceInfo {
    surfaceId    @0 :T.SurfaceId;
    kind         @1 :SurfaceRole;
    rect         @2 :T.Rect;
    visible      @3 :Bool;
    focused      @4 :Bool;
    output       @5 :T.OutputId;
    metadata     @6 :List(T.Meta);
}

struct OutputInfo {
    outputId                   @0 :T.OutputId;
    name                       @1 :Text;
    description                @2 :Text;
    physicalMillimetersWidth   @3 :UInt32;
    physicalMillimetersHeight  @4 :UInt32;
    resolution                 @5 :T.Vec2i;
    refreshRate                @6 :T.FrameRate;
    position                   @7 :T.Vec2i;
    scale                      @8 :Float32;
    primary                    @9 :Bool;
    connected                 @10 :Bool;
    modes                     @11 :List(OutputMode);
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
    cpuTime        @2 :T.Duration;
    gpuTime        @3 :T.Duration;
    frameTime      @4 :T.Duration;
    droppedFrames  @5 :UInt64;
    uptime         @6 :T.Duration;
    memoryBytes    @7 :UInt64;
}

# ══════════════════════════════════════════════════════════════════════
# EVENTS
# All events through one stream. Forward compatible forever.
# ══════════════════════════════════════════════════════════════════════

interface EventStream {
    next   @0 () -> (event :CompositorEvent);
    cancel @1 () -> T.VoidResult;
}

struct EventFilter {
    surfaceIds @0 :List(T.SurfaceId);
    eventKinds @1 :List(EventKind);
}

enum EventKind {
    surfaceEvents    @0;
    frameEvents      @1;
    inputEvents      @2;
    focusEvents      @3;
    outputEvents     @4;
    compositorEvents @5;
    dragEvents       @6;
    themeEvents      @7;
    accessibilityEvents @8;
    other            @9;
    custom           @10;
}

struct CompositorEvent {
    union {
    surfaceCreated         @0  :SurfaceInfo;
    surfaceDestroyed       @1  :T.SurfaceId;
    surfaceGeometryChanged @2  :SurfaceGeometryEvent;
    surfaceStateChanged    @3  :SurfaceStateEvent;

    frameReady             @4  :FrameSignal;
    framePresented         @5  :FrameSignal;

    pointerEnter           @6  :PointerEnterEvent;
    pointerLeave           @7  :PointerLeaveEvent;
    pointerMove            @8  :PointerMoveEvent;
    pointerButton          @9  :PointerButtonEvent;
    pointerScroll          @10 :PointerScrollEvent;
    keyboardKey            @11 :KeyboardKeyEvent;
    keyboardModifiers      @12 :KeyboardModifiersEvent;
    touchDown              @13 :TouchDownEvent;
    touchUp                @14 :TouchUpEvent;
    touchMove              @15 :TouchMoveEvent;

    stylusDown             @16 :StylusEvent;
    stylusUp               @17 :StylusEvent;
    stylusMove             @18 :StylusEvent;
    stylusButton           @19 :StylusButtonEvent;

    gestureSwipeBegin      @20 :GestureSwipeEvent;
    gestureSwipeUpdate     @21 :GestureSwipeEvent;
    gestureSwipeEnd        @22 :GestureSwipeEvent;
    gesturePinchBegin      @23 :GesturePinchEvent;
    gesturePinchUpdate     @24 :GesturePinchEvent;
    gesturePinchEnd        @25 :GesturePinchEvent;

    focusGained            @26 :FocusEvent;
    focusLost              @27 :FocusEvent;

    outputAdded            @28 :OutputInfo;
    outputRemoved          @29 :T.OutputId;
    outputChanged          @30 :OutputInfo;

    compositorReady        @31 :CompositorInfo;
    compositorShutdown     @32 :ShutdownEvent;

    cursorChanged          @33 :CursorChangedEvent;

    dragEntered            @34 :DragEnteredEvent;
    dragMoved              @35 :DragMovedEvent;
    dragDropped            @36 :DragDroppedEvent;
    dragFinished           @37 :DragFinishedEvent;
    dragCancelled          @38 :Void;

    themeChanged           @39 :ThemeChangedEvent;

    accessibilityTreeChanged @40 :AccessibilityTreeChangedEvent;

    unknown                @41 :UnknownEvent;
    }
}

struct UnknownEvent {
    typeId  @0 :UInt64;
    # Inline for small payloads; use buffer reference for large unknown events.
    payload @1 :T.DataHandle;
}

# ── Event Details ─────────────────────────────────────────────

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
    key       @1 :LogicalKey;
    scancode  @2 :UInt32;
    action    @3 :KeyAction;
    modifiers @4 :T.ModifierState;
    timestamp @5 :T.Timestamp;
    text      @6 :Text;
    repeated  @7 :Bool;
}

struct LogicalKey {
    name      @0 :Text;
    codepoint @1 :UInt32;
}

enum KeyAction {
    pressed  @0;
    released @1;
    other    @2;
    custom   @3;
}

# ModifierState removed in Batch 10 (Audit-4).
# All references now use T.ModifierState from types.capnp.
# The local definition lacked scrollLock and used 'meta' instead of 'super'.
# Ordinals 0-5 of the deleted struct are now permanently reserved
# and must never be reused for a new struct in this file.

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
    toolType  @9 :StylusTool;
    timestamp @10 :T.Timestamp;
}

struct StylusButtonEvent {
    surfaceId @0 :T.SurfaceId;
    toolId    @1 :UInt32;
    button    @2 :UInt32;
    pressed   @3 :Bool;
    timestamp @4 :T.Timestamp;
}

enum StylusTool {
    pen      @0;
    eraser   @1;
    brush    @2;
    pencil   @3;
    airbrush @4;
    other    @5;
    custom   @6;
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

struct FocusEvent {
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
    reason        @0 :ShutdownReason;
    gracePeriod   @1 :T.Duration;
    message       @2 :Text;
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

# ── Drag and Drop Events ──────────────────────────────────────

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

# ── Theme Events ──────────────────────────────────────────────

struct ThemeChangedEvent {
    theme @0 :Theme;
}

# ── Accessibility Events ──────────────────────────────────────

struct AccessibilityTreeChangedEvent {
    surfaceId @0 :T.SurfaceId;
    tree      @1 :AccessibilityTree;
}

# ══════════════════════════════════════════════════════════════════════
# CAPABILITIES
# Kernel-enforced. Not permission strings. Not booleans.
# ══════════════════════════════════════════════════════════════════════

enum CapabilityKind {
    createWindow      @0;
    createPopup       @1;
    createOverlay     @2;
    createPanel       @3;
    createWallpaper   @4;
    createSpatial     @5;
    captureOwn        @6;
    captureOutput     @7;
    captureAll        @8;
    capturePrivate    @9;
    receiveInput     @10;
    exclusiveInput   @11;
    globalHotkeys    @12;
    queryOutputs     @13;
    configureOutput  @14;
    setCursor        @15;
    confineCursor    @16;
    lockCursor       @17;
    warpCursor       @18;
    setCursorTheme   @19;
    startDrag        @20;
    readTheme        @21;
    readAccessibility @22;
    custom           @23;
    other            @24;
}

struct CapabilityRequest {
    union {
        standard @0 :CapabilityKind;
        hotkeys  @1 :List(HotkeyRequest);
        custom   @2 :CustomCapability;
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
    handle    @1 :UInt64;               # Deprecated: use capabilityHandle. Kept for ordinal stability.
    # Typed capability handle (preferred over raw handle field above).
    capabilityHandle @2 :T.CapabilityHandle;
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
    compositorPolicy  @4;
    other             @5;
    custom            @6;
}

# ══════════════════════════════════════════════════════════════════════
# AUDIT-7 ADDITIONS — Spatial, Animation, Health, Security
# ══════════════════════════════════════════════════════════════════════

# ── HDR Metadata (audit-7) ──
struct HdrMetadata {
    colorSpace @0 :Text;
    maxLuminance @1 :UInt32;
    minLuminance @2 :UInt32;
    maxFrameAverage @3 :UInt32;
    maxContent @4 :UInt32;
}

# ── Spatial Pose (audit-7: compositor_spatial.capnp belongs here) ──
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

# ── Display Zone (audit-7) ──
struct DisplayZoneRequest {
    outputId @0 :T.OutputId;
    zoneId @1 :Text;
    bounds @2 :T.Rect;
    role @3 :ZoneRole;
    permissions @4 :List(ZonePermission);
    interaction @5 :InteractionMode;
}

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

# ── Animation Definition (audit-7: compositor_animation.capnp belongs here) ──
struct AnimationDefinitionRequest {
    surface @0 :T.SurfaceId;
    property @1 :Text;
    spec @2 :T.AnimationSpec;
    from @3 :T.Meta;
    to @4 :T.Meta;
}

# ── Surface Access Control (audit-7) ──
struct SurfaceAccessControl {
    allowedProcesses @0 :List(T.AppId);
    requireConsent @1 :Bool;
    secureContent @2 :Bool;
}

# ── Compositor Health (audit-7) ──
struct CompositorHealth {
    healthy @0 :Bool;
    cpuUsage @1 :Float32;
    gpuUsage @2 :Float32;
    memoryBytes @3 :UInt64;
    lastFrameTime @4 :T.Duration;
    droppedFrames @5 :UInt64;
    issues @6 :List(HealthIssue);
}

struct HealthIssue {
    severity @0 :IssueSeverity;
    message @1 :Text;
    timestamp @2 :T.Timestamp;
}

enum IssueSeverity {
    info @0;
    warning @1;
    error @2;
    critical @3;
    custom @4;
}

# ── State Snapshot (audit-7) ──
struct StateSnapshot {
    timestamp @0 :T.Timestamp;
    surfaces @1 :List(SurfaceInfo);
    outputs @2 :List(OutputInfo);
    theme @3 :Theme;
    metadata @4 :List(T.Meta);
}

# ── Remote Access (audit-7) ──
struct RemoteAccessConfig {
    enabled @0 :Bool;
    requireAuth @1 :Bool;
    maxConnections @2 :UInt32;
}

# ── Resource Limits (audit-7) ──
struct ResourceLimits {
    maxSurfaces @0 :UInt32;
    maxGpuMemoryBytes @1 :UInt64;
    maxFramebuffers @2 :UInt32;
}

# ── Animation Engine (audit-8 What's Still Missing) ──
struct Keyframe {
    time @0 :Float32;
    value @1 :T.Meta;
    easing @2 :EasingType;
    interpolation @3 :InterpolationType;
}

enum EasingType {
    linear @0;
    easeIn @1;
    easeOut @2;
    easeInOut @3;
    spring @4;
    custom @5;
}

enum InterpolationType {
    none @0;
    linear @1;
    bezier @2;
    spline @3;
    custom @4;
}

struct PhysicsSpring {
    stiffness @0 :Float32;
    damping @1 :Float32;
    mass @2 :Float32;
    initialVelocity @3 :Float32;
}

# ── Surface Content Protection (audit-8 What's Still Missing) ──
struct DrmInfo {
    contentType @0 :DrmContentType;
    protected @1 :Bool;
    keyId @2 :Text;
}

enum DrmContentType {
    undefined @0;
    clear @1;
    drmL1 @2;
    drmL2 @3;
    drmL3 @4;
    custom @5;
}

# ── Accessibility Live Regions (audit-8 What's Still Missing) ──
struct LiveRegionInfo {
    surfaceId @0 :T.SurfaceId;
    politeness @1 :LiveRegionPoliteness;
    label @2 :Text;
}

enum LiveRegionPoliteness {
    polite @0;
    assertive @1;
    custom @2;
}

# ── Gesture Recognition Pipeline (audit-8 What's Still Missing) ──
struct GesturePipeline {
    recognizerType @0 :GestureRecognizerType;
    minPoints @1 :UInt32;
    maxPoints @2 :UInt32;
    historySize @3 :UInt32;
}

enum GestureRecognizerType {
    none @0;
    tap @1;
    doubleTap @2;
    longPress @3;
    pan @4;
    pinch @5;
    rotation @6;
    swipe @7;
    custom @8;
}

# ── Compositor Plugin System (audit-8 What's Still Missing) ──
struct PluginInfo {
    id @0 :Text;
    name @1 :Text;
    version @2 :T.Version;
    capabilities @3 :List(Text);
    enabled @4 :Bool;
}

# ── Live Region Filter / Subscription (audit-9 What's Still Missing) ──
struct LiveRegionFilter {
    surfaceIds @0 :List(T.SurfaceId);
    politeness @1 :List(LiveRegionPoliteness);
}

interface LiveRegionSubscription {
    pull @0 () -> (event :LiveRegionEvent);
    cancel @1 () -> T.VoidResult;
}

struct LiveRegionEvent {
    surfaceId @0 :T.SurfaceId;
    politeness @1 :LiveRegionPoliteness;
    label @2 :Text;
    timestamp @3 :T.Timestamp;
}

# ── Gesture Recognition Result (audit-9 What's Still Missing) ──
struct GestureResult {
    recognized @0 :Bool;
    gestureType @1 :GestureRecognizerType;
    confidence @2 :Float32;
    data @3 :T.Meta;
    timestamp @4 :T.Timestamp;
}

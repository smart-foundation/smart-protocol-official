@0xa1b2c3d4e5f60006;

using T = import "types.capnp";
using Shell = import "shell.capnp";

# ══════════════════════════════════════════════════════════════════════
# Window Manager — window lifecycle, workspace management, layout, capture.
#
# Audit-7 improvements:
#   - Session methods: enterSplitScreen, exitSplitScreen, enterPip, exitPip,
#     getWindowThumbnail, listWindowThumbnails, animateWindow, cancelAnimation,
#     createWindowGroup, destroyWindowGroup.
#   - WindowManagerCapability extended: splitScreenWindows, pipWindows,
#     freeformWindows, spatialWindows, automotiveMode, voiceOnlyMode,
#     animationPipeline, foldableAware.
#   - SplitScreenRequest / PipRequest for mobile multi-window.
#   - FoldableState / FoldState for foldable device awareness.
#   - SpatialWindowState / OcclusionMode for AR/VR spatial windows.
#   - AutomotiveHMI / AutomotiveDisplayRole / DistractionLevel for car clusters.
#   - VoiceWindowState / VoiceWindowMode for voice-first interfaces.
#   - WindowAnimation / AnimationType / AnimationState for animation pipeline.
#   - WindowThumbnail for task switcher / recent apps.
#   - MobileSnapZone / MobileSnapEdge for mobile snap zones.
#   - WindowGroup / GroupLayout for cross-output window grouping.
# ══════════════════════════════════════════════════════════════════════

interface Session {

    struct HandshakeRequest {
        applicationId @0 :Text;
        version       @1 :T.Version;
        capabilities  @2 :List(WindowManagerCapability);
        metadata      @3 :List(T.Meta);
    }

    struct HandshakeResponse {
        sessionId @0 :T.SessionId;
        wm        @1 :WindowManagerInfo;
        granted   @2 :List(WindowManagerCapability);
        denied    @3 :List(WindowManagerCapability);
        result    @4 :HandshakeResult;
    }

    enum HandshakeResult {
        accepted         @0;
        acceptedDegraded @1;
        rejected         @2;
        custom           @3;
    }

    struct WindowManagerInfo {
        name         @0 :Text;
        version      @1 :T.Version;
        layoutEngine @2 :LayoutEngine;
        capabilities @3 :List(WindowManagerCapability);
        metadata     @4 :List(T.Meta);
    }

    enum LayoutEngine {
        floating @0;
        tiling   @1;
        tabbed   @2;
        stacking @3;
        spatial  @4;
        custom   @5;
    }

    handshake @0 (request :HandshakeRequest)
               -> (response :HandshakeResponse);

    # -- Windows --

    listWindows     @1  (filter :WindowFilter)
                     -> (windows :List(Window));

    # Paginated variant of listWindows for large window counts.
    # The original listWindows (ordinal @1) returns unbounded results
    # for wire-format compatibility. This method adds pagination support.
    listWindowsPaged @37 (filter :WindowFilter, pagination :T.Pagination)
                     -> (windows :List(Window), total :UInt64);

    getWindow       @2  (id :T.WindowId)
                     -> (window :Window);

    getFocusedWindow @3 () -> (window :Window);

    # -- Window Control --

    focusWindow     @4  (id :T.WindowId) -> (result :T.VoidResult);
    closeWindow     @5  (id :T.WindowId) -> (result :T.VoidResult);
    moveWindow      @6  (id :T.WindowId, x :Int32, y :Int32)
                     -> (result :T.VoidResult);
    resizeWindow    @7  (id :T.WindowId, width :UInt32, height :UInt32)
                     -> (result :T.VoidResult);
    moveResizeWindow @8 (id :T.WindowId, rect :T.Rect)
                     -> (result :T.VoidResult);
    minimizeWindow  @9  (id :T.WindowId) -> (result :T.VoidResult);
    restoreWindow   @10 (id :T.WindowId) -> (result :T.VoidResult);
    maximizeWindow  @11 (id :T.WindowId) -> (result :T.VoidResult);
    toggleFullscreen @12 (id :T.WindowId, on :Bool)
                     -> (result :T.VoidResult);
    setAlwaysOnTop  @13 (id :T.WindowId, on :Bool)
                     -> (result :T.VoidResult);
    setSticky       @14 (id :T.WindowId, on :Bool)
                     -> (result :T.VoidResult);

    # -- Snapping --

    snapWindow      @15 (id :T.WindowId, zone :SnapZone)
                     -> (result :T.VoidResult);
    listSnapZones   @16 (output :T.OutputId)
                     -> (zones :List(SnapZone));

    # Paginated variant of listSnapZones.
    listSnapZonesPaged @38 (output :T.OutputId, pagination :T.Pagination)
                        -> (zones :List(SnapZone), total :UInt64);
    getUsableArea   @17 (output :T.OutputId) -> (area :T.Rect);

    # -- Layout --

    tileWindows     @18 (request :TileRequest)
                     -> (result :T.VoidResult);
    setFocusPolicy  @19 (policy :FocusPolicyRequest)
                     -> (result :T.VoidResult);

    # -- Workspaces --

    listWorkspaces       @20 () -> (workspaces :List(WorkspaceInfo));

    # Paginated variant of listWorkspaces.
    listWorkspacesPaged  @39 (pagination :T.Pagination)
                         -> (workspaces :List(WorkspaceInfo), total :UInt64);
    getWorkspace         @21 (output :T.OutputId) -> (workspace :WorkspaceInfo);
    switchWorkspace      @22 (id :T.WorkspaceId) -> (result :T.VoidResult);
    switchWorkspaceRelative @23 (direction :WorkspaceDirection)
                            -> (result :T.VoidResult);
    createWorkspace      @24 (name :Text) -> (id :T.WorkspaceId);
    deleteWorkspace      @25 (id :T.WorkspaceId) -> (result :T.VoidResult);
    moveWindowToWorkspace @26 (windowId :T.WindowId,
                               workspaceId :T.WorkspaceId)
                           -> (result :T.VoidResult);
    moveWindowToOutput   @27 (windowId :T.WindowId,
                              outputId :T.OutputId)
                          -> (result :T.VoidResult);

    # -- Overview --

    showOverview    @28 () -> (result :T.VoidResult);
    hideOverview    @29 () -> (result :T.VoidResult);
    showDesktop     @30 () -> (result :T.VoidResult);

    # -- Capture --

    capture         @31 (request :CaptureRequest)
                     -> (response :CaptureResponse);
    stopCapture     @32 (id :T.CaptureId) -> (result :T.VoidResult);

    # -- Outputs --

    listOutputs     @33 () -> (outputs :List(OutputInformation));

    # Paginated variant of listOutputs.
    listOutputsPaged @40 (pagination :T.Pagination)
                     -> (outputs :List(OutputInformation), total :UInt64);
    getOutput       @34 (id :T.OutputId) -> (output :OutputInformation);

    # -- Events --

    subscribe       @35 (filter :WindowManagerEventFilter)
                     -> (stream :WindowManagerEventStream);

    # -- Query --

    query           @36 (query :WindowManagerQuery) -> (result :WindowManagerQueryResult);

    # -- Audit-7 additions: Mobile multi-window --

    enterSplitScreen @41 (request :SplitScreenRequest) -> (result :T.VoidResult);
    exitSplitScreen @42 (windowId :T.WindowId) -> (result :T.VoidResult);
    enterPip @43 (request :PipRequest) -> (result :T.VoidResult);
    exitPip @44 (windowId :T.WindowId) -> (result :T.VoidResult);

    # -- Audit-7 additions: Window thumbnails --
    getWindowThumbnail @45 (windowId :T.WindowId) -> (thumbnail :WindowThumbnail);
    listWindowThumbnails @46 (pagination :T.Pagination) -> (thumbnails :List(WindowThumbnail), total :UInt64);

    # -- Audit-7 additions: Window animation --
    animateWindow @47 (animation :WindowAnimation) -> T.VoidResult;
    cancelAnimation @48 (animationId :UInt32) -> (result :T.VoidResult);

    # -- Audit-7 additions: Window groups --
    createWindowGroup @49 (group :WindowGroup) -> T.VoidResult;
    destroyWindowGroup @50 (groupId :UInt32) -> (result :T.VoidResult);

    # ── Audit-9 additions: Input redirection (audit-9 What's Still Missing) ──
    setInputRedirection @51 (windowId :T.WindowId, redirection :InputRedirection) -> T.VoidResult;

    # ── Audit-9 additions: Lock screen windows (audit-9 What's Still Missing) ──
    createLockScreenWindow @52 (config :LockScreenWindow) -> (windowId :T.WindowId);

    # ── Audit-9 additions: Notification windows (audit-9 What's Still Missing) ──
    createNotificationWindow @53 (config :NotificationWindow) -> (windowId :T.WindowId);

    # ── Audit-9 additions: Mobile presets (audit-9 What's Still Missing) ──
    addMobilePreset @54 (preset :MobilePreset) -> T.VoidResult;
    getMobilePreset @55 (presetId :Text) -> (preset :MobilePreset);
}

# ══════════════════════════════════════════════════════════════════════
# EXISTING COMPOSITOR INTERFACE
# Ordinals 0-43 preserved exactly as-is.
# ══════════════════════════════════════════════════════════════════════

interface WindowManager {
    listWindows @0 (filter :WindowFilter) -> (windows :List(Window));

    # Paginated variant of listWindows for the legacy WindowManager interface.
    listWindowsPaged @44 (filter :WindowFilter, pagination :T.Pagination)
                     -> (windows :List(Window), total :UInt64);
    getWindow @1 (windowId :T.WindowId) -> (window :Window);
    getFocusedWindow @2 () -> (windowId :T.WindowId);

    focus @3 (windowId :T.WindowId) -> T.VoidResult;
    close @4 (windowId :T.WindowId) -> T.VoidResult;
    minimize @5 (windowId :T.WindowId) -> T.VoidResult;
    restore @6 (windowId :T.WindowId) -> T.VoidResult;
    maximize @7 (windowId :T.WindowId) -> T.VoidResult;
    unmaximize @8 (windowId :T.WindowId) -> T.VoidResult;
    fullscreen @9 (windowId :T.WindowId, enable :Bool) -> T.VoidResult;
    setDecorations @10 (windowId :T.WindowId, enabled :Bool) -> T.VoidResult;
    setAlwaysOnTop @11 (windowId :T.WindowId, enable :Bool) -> T.VoidResult;
    setMinimized @12 (windowId :T.WindowId, minimized :Bool) -> T.VoidResult;

    moveWindow @13 (windowId :T.WindowId, x :Int32, y :Int32) -> T.VoidResult;
    resizeWindow @14 (windowId :T.WindowId, width :UInt32, height :UInt32) -> T.VoidResult;
    setOpacity @15 (windowId :T.WindowId, opacity :Float32) -> T.VoidResult;
    setShadow @16 (windowId :T.WindowId, enabled :Bool) -> T.VoidResult;
    setBorder @17 (windowId :T.WindowId, enabled :Bool) -> T.VoidResult;
    setTitle @18 (windowId :T.WindowId, title :Text) -> T.VoidResult;
    setMinSize @19 (windowId :T.WindowId, width :UInt32, height :UInt32) -> T.VoidResult;
    setMaxSize @20 (windowId :T.WindowId, width :UInt32, height :UInt32) -> T.VoidResult;
    requestAttention @21 (windowId :T.WindowId) -> T.VoidResult;
    groupWindows @22 (windowIds :List(T.WindowId)) -> T.VoidResult;
    ungroupWindows @23 (windowId :T.WindowId) -> T.VoidResult;
    enablePin @24 (windowId :T.WindowId, enable :Bool) -> T.VoidResult;

    snapWindow @25 (windowId :T.WindowId, zone :SnapZone) -> T.VoidResult;
    listSnapZones @26 () -> (zones :List(SnapZone));

    # Paginated variant of listSnapZones for the legacy WindowManager interface.
    listSnapZonesPaged @45 (pagination :T.Pagination)
                       -> (zones :List(SnapZone), total :UInt64);
    getUsableArea @27 () -> (area :T.Rect);

    tileWindows @28 (requests :List(TileRequest)) -> T.VoidResult;

    setFocusPolicy @29 (policy :FocusPolicy) -> T.VoidResult;

    listWorkspaces @30 () -> (workspaces :List(WorkspaceInfo));

    # Paginated variant of listWorkspaces for the legacy WindowManager interface.
    listWorkspacesPaged @46 (pagination :T.Pagination)
                        -> (workspaces :List(WorkspaceInfo), total :UInt64);
    switchWorkspace @31 (workspaceId :T.WorkspaceId) -> T.VoidResult;
    createWorkspace @32 (name :Text) -> (workspaceId :T.WorkspaceId);
    deleteWorkspace @33 (workspaceId :T.WorkspaceId) -> T.VoidResult;

    showOverview @34 () -> T.VoidResult;
    hideOverview @35 () -> T.VoidResult;
    showDesktop @36 () -> T.VoidResult;

    capture @37 (windowId :T.WindowId) -> (captureId :T.CaptureId);
    stopCapture @38 (captureId :T.CaptureId) -> T.VoidResult;

    listOutputs @39 () -> (outputs :List(OutputInfo));

    # Paginated variant of listOutputs for the legacy WindowManager interface.
    listOutputsPaged @47 (pagination :T.Pagination)
                     -> (outputs :List(OutputInfo), total :UInt64);

    subscribeEvents @40 () -> (subscription :EventSubscription);
    pullEvents @41 (subscription :EventSubscription) -> (events :List(WmEvent));

    query @42 (query :Text, params :List(T.Meta)) -> (result :Text);

    # Paginated query variant using the Session-style typed query union.
    # The legacy query (ordinal @42) accepts raw Text for backward
    # compatibility. This method provides a typed, paginated alternative.
    queryPaged @48 (query :WindowManagerQuery, pagination :T.Pagination)
               -> (result :WindowManagerQueryResult);

    setCornerRadius @43 (windowId :T.WindowId, radius :T.CornerRadius) -> T.VoidResult;
}

# ══════════════════════════════════════════════════════════════════════
# EXISTING TYPES
# Ordinals 1-13 preserved exactly as-is.
# ══════════════════════════════════════════════════════════════════════

struct Window {
    id @0 :T.WindowId;
    title @1 :Text;
    appId @2 :Text;
    surfaceId @3 :T.SurfaceId;
    rect @4 :T.Rect;
    state @5 :WindowState;
    workspace @6 :T.WorkspaceId;
    monitor @7 :T.OutputId;
    decorated @8 :Bool;
    alwaysOnTop @9 :Bool;
    opacity @10 :Float32;
    shadow @11 :Bool;
    border @12 :Bool;
    minSize @13 :T.Size;
    maxSize @14 :T.Size;
    pid @15 :UInt32;
    windowClass @16 :Text;
    leaderId @17 :T.WindowId;
    groupId @18 :T.WindowId;
    isPinned @19 :Bool;
    windowType @20 :WindowType;
    # New fields matching matrix-mimo completeness
    layer @21 :T.WindowLayer;
    focused @22 :Bool;
    minimized @23 :Bool;
    maximized @24 :Bool;
    fullscreen @25 :Bool;
    sticky @26 :Bool;
    urgent @27 :Bool;
    canClose @28 :Bool;
    canMinimize @29 :Bool;
    canMaximize @30 :Bool;
    canFullscreen @31 :Bool;
    canResize @32 :Bool;
    canMove @33 :Bool;
    parent @34 :T.WindowId;
    children @35 :List(T.WindowId);
    createdAt @36 :T.Timestamp;
    focusedAt @37 :T.Timestamp;
    lastActiveAt @38 :T.Timestamp;
    # 3D pose is a superset for 2D window managers; 2D WMs ignore z.
    pose @39 :T.Vec3;
    metadata @40 :List(T.Meta);
}

enum WindowState {
    normal @0;
    minimized @1;
    maximized @2;
    fullscreen @3;
    hidden @4;
    custom @5;
}

struct WindowFilter {
    appId @0 :Text;
    workspace @1 :T.WorkspaceId;
    monitor @2 :T.OutputId;
    state @3 :WindowState;
    layer @4 :T.WindowLayer;
    focused @5 :T.BoolFilter;
    processId @6 :UInt32;
}

# -- SnapZone (existing ordinals preserved, new field added) --

struct SnapZone {
    id @0 :UInt32;
    preset @1 :SnapPreset;
    rect @2 :T.Rect;
    grid @3 :GridSnap;
}

enum SnapPreset {
    topLeft @0;
    top @1;
    topRight @2;
    left @3;
    center @4;
    right @5;
    bottomLeft @6;
    bottom @7;
    bottomRight @8;
    custom @9;
    grid @10;
    maximize @11;
    thirdLeft @12;
    thirdCenter @13;
    thirdRight @14;
    twoThirdsLeft @15;
    twoThirdsRight @16;
}

struct GridSnap {
    columns @0 :UInt8;
    rows @1 :UInt8;
    column @2 :UInt8;
    row @3 :UInt8;
    columnSpan @4 :UInt8;
    rowSpan @5 :UInt8;
}

# -- TileRequest (expanded) --

struct TileRequest {
    windowId @0 :T.WindowId;
    rect @1 :T.Rect;
    windows @2 :List(T.WindowId);
    algorithm @3 :TilingAlgorithm;
    area @4 :T.Rect;
    gaps @5 :Gaps;
}

enum TilingAlgorithm {
    horizontal @0;
    vertical @1;
    grid @2;
    spiral @3;
    master @4;
    custom @5;
}

struct Gaps {
    outer @0 :UInt32;
    inner @1 :UInt32;
}

# -- FocusPolicy (existing enum preserved) --

enum FocusPolicy {
    clickToFocus @0;
    focusFollowsMouse @1;
    sloppy @2;
    custom @3;
}

# New union-based focus policy for Session interface
struct FocusPolicyRequest {
    union {
        click         @0 :Void;
        followPointer @1 :Void;
        sloppy        @2 :SloppyFocus;
        manual        @3 :Void;
        custom        @4 :Data;
    }
}

struct SloppyFocus {
    focusDelay @0 :T.Duration;
    raiseOnFocus @1 :Bool;
}

# -- WorkspaceInfo (expanded) --

struct WorkspaceInfo {
    id @0 :T.WorkspaceId;
    name @1 :Text;
    active @2 :Bool;
    output @3 :T.OutputId;
    windowCount @4 :UInt32;
    row @5 :UInt16;
    column @6 :UInt16;
    # 3D pose is a superset for 2D window managers; 2D WMs ignore z.
    pose @7 :T.Vec3;
    metadata @8 :List(T.Meta);
}

enum WorkspaceDirection {
    left  @0;
    right @1;
    up    @2;
    down  @3;
    prev  @4;
    next  @5;
    custom @6;
}

# -- OutputInfo (expanded) --

struct OutputInfo {
    id @0 :T.OutputId;
    name @1 :Text;
    rect @2 :T.Rect;
    description @3 :Text;
    physicalMillimetersWidth @4 :UInt32;
    physicalMillimetersHeight @5 :UInt32;
    refreshRate @6 :T.FrameRate;
    position @7 :T.Vec2i;
    scale @8 :Float32;
    primary @9 :Bool;
    connected @10 :Bool;
    modes @11 :List(OutputMode);
}

struct OutputMode {
    width @0 :UInt32;
    height @1 :UInt32;
    refreshRate @2 :T.FrameRate;
    preferred @3 :Bool;
}

struct OutputInformation {
    outputId @0 :T.OutputId;
    name @1 :Text;
    description @2 :Text;
    physicalMillimetersWidth @3 :UInt32;
    physicalMillimetersHeight @4 :UInt32;
    resolution @5 :T.Vec2i;
    refreshRate @6 :T.FrameRate;
    position @7 :T.Vec2i;
    scale @8 :Float32;
    primary @9 :Bool;
    connected @10 :Bool;
}

# ══════════════════════════════════════════════════════════════════════
# CAPTURE
# ══════════════════════════════════════════════════════════════════════

struct CaptureRequest {
    source @0 :CaptureSource;
    format @1 :CaptureFormat;
    mode @2 :CaptureMode;
    captureId @3 :T.CaptureId;
}

struct CaptureSource {
    union {
        output @0 :T.OutputId;
        outputRegion @1 :OutputRegion;
        allOutputs @2 :Void;
        window @3 :T.WindowId;
        workspace @4 :T.WorkspaceId;
        cursor @5 :Void;
    }
}

struct OutputRegion {
    output @0 :T.OutputId;
    rect @1 :T.Rect;
}

struct CaptureFormat {
    pixelFormats @0 :List(T.PixelFormat);
    maxWidth @1 :UInt32;
    maxHeight @2 :UInt32;
    includeCursor @3 :Bool;
    composited @4 :Bool;
}

struct CaptureMode {
    union {
        single @0 :Void;
        stream @1 :StreamCapture;
        mirror @2 :Void;
    }
}

struct StreamCapture {
    targetFramesPerSecond @0 :T.FrameRate;
}

struct CaptureResponse {
    captureId @0 :T.CaptureId;
    result @1 :CaptureResult;
}

struct CaptureResult {
    union {
        frame @0 :CaptureFrame;
        streamStarted @1 :T.CaptureId;
        mirrorSurface @2 :T.SurfaceId;
        error @3 :CaptureError;
    }
}

struct CaptureFrame {
    width @0 :UInt32;
    height @1 :UInt32;
    stride @2 :UInt32;
    format @3 :T.PixelFormat;
    timestamp @4 :T.Timestamp;
    # CRITICAL — Wire-format constraint (Audit-5, Audit-6).
    # dataHandle ordinal @5 was UInt64 (opaque buffer handle) from the
    # original schema. Changing to T.DataHandle would break wire format
    # for all existing consumers. Consumers MUST treat this UInt64 as a
    # T.DataHandle-compatible buffer reference: the value is an opaque
    # token that the compositor backend interprets. Do NOT cast to or
    # from other UInt64 fields. Will be addressed in a future schema
    # version bump when wire-format compatibility can be broken.
    dataHandle @5 :UInt64;
}

enum CaptureError {
    noCapability @0;
    sourceNotFound @1;
    sourcePrivate @2;
    tooMany @3;
    unsupported @4;
    custom @5;
}

# ══════════════════════════════════════════════════════════════════════
# EXISTING EVENTS
# Ordinals 10-13 preserved exactly as-is.
# ══════════════════════════════════════════════════════════════════════

interface EventSubscription {
    pull @0 () -> (events :List(WmEvent));
    cancel @1 () -> T.VoidResult;

    # Paginated event retrieval. Returns at most `pagination.limit` events
    # starting at `pagination.offset`. Caller should repeat with increasing
    # offset until all events are consumed.
    pullPaged @2 (pagination :T.Pagination)
              -> (events :List(WmEvent), total :UInt64);
}

struct WmEvent {
    id @0 :T.EventId;
    timestamp @1 :T.Timestamp;
    type @2 :WmEventType;
    window @3 :T.WindowId;
    workspace @4 :T.WorkspaceId;
    output @5 :T.OutputId;
}

enum WmEventType {
    windowOpen @0;
    windowClose @1;
    windowMove @2;
    windowResize @3;
    windowFocus @4;
    windowMinimize @5;
    windowMaximize @6;
    windowFullscreen @7;
    workspaceCreate @8;
    workspaceDelete @9;
    workspaceSwitch @10;
    outputConnect @11;
    outputDisconnect @12;
    custom @13;
}

enum WindowType {
    normal @0;
    dialog @1;
    splash @2;
    tooltip @3;
    popup @4;
    dock @5;
    toolbar @6;
    menu @7;
    utility @8;
    dropdown @9;
    popupMenu @10;
    tooltipMenu @11;
    notification @12;
    criticalNotification @13;
    onscreenDisplay @14;
    custom @15;
}

# ══════════════════════════════════════════════════════════════════════
# NEW EVENTS — Session-style typed events
# ══════════════════════════════════════════════════════════════════════

interface WindowManagerEventStream {
    next @0 () -> (event :WindowManagerEvent);
    cancel @1 () -> T.VoidResult;
}

struct WindowManagerEventFilter {
    windowIds @0 :List(T.WindowId);
    workspaceIds @1 :List(T.WorkspaceId);
    outputIds @2 :List(T.OutputId);
    kinds @3 :List(WindowManagerEventKind);
}

enum WindowManagerEventKind {
    windowEvents @0;
    workspaceEvents @1;
    outputEvents @2;
    focusEvents @3;
    captureEvents @4;
    custom @5;
}

struct WindowManagerEvent {
    union {
    windowOpened @0  :Window;
    windowClosed @1  :T.WindowId;
    windowMoved @2  :WindowMovedEvent;
    windowResized @3  :WindowResizedEvent;
    windowMinimized @4  :T.WindowId;
    windowRestored @5  :T.WindowId;
    windowMaximized @6  :T.WindowId;
    windowFullscreen @7  :WindowFullscreenEvent;
    windowUrgent @8  :T.WindowId;
    windowTitleChanged @9  :WindowTitleEvent;

    focusChanged @10 :FocusChangedEvent;

    workspaceCreated @11 :WorkspaceInfo;
    workspaceDestroyed @12 :T.WorkspaceId;
    workspaceSwitched @13 :WorkspaceSwitchedEvent;
    windowChangedWorkspace @14 :WindowWorkspaceEvent;

    outputAdded @15 :OutputInformation;
    outputRemoved @16 :T.OutputId;
    outputChanged @17 :OutputInformation;

    captureFrameReady @18 :CaptureFrameReadyEvent;
    captureEnded @19 :T.CaptureId;

    unknown @20 :UnknownWindowManagerEvent;
    }
}

struct UnknownWindowManagerEvent {
    typeId @0 :UInt64;
    payload @1 :Data;
}

struct WindowMovedEvent {
    windowId @0 :T.WindowId;
    oldRect @1 :T.Rect;
    newRect @2 :T.Rect;
}

struct WindowResizedEvent {
    windowId @0 :T.WindowId;
    oldSize @1 :T.Vec2i;
    newSize @2 :T.Vec2i;
}

struct WindowFullscreenEvent {
    windowId @0 :T.WindowId;
    fullscreen @1 :Bool;
    output @2 :T.OutputId;
}

struct WindowTitleEvent {
    windowId @0 :T.WindowId;
    title @1 :Text;
}

struct FocusChangedEvent {
    oldWindow @0 :T.WindowId;
    newWindow @1 :T.WindowId;
    reason @2 :FocusReason;
}

enum FocusReason {
    userClick @0;
    programmatic @1;
    tabNavigation @2;
    touchscreen @3;
    windowManagerPolicy @4;
    unknown @5;
    custom @6;
}

struct WorkspaceSwitchedEvent {
    fromWorkspace @0 :T.WorkspaceId;
    toWorkspace @1 :T.WorkspaceId;
    output @2 :T.OutputId;
}

struct WindowWorkspaceEvent {
    windowId @0 :T.WindowId;
    fromWorkspace @1 :T.WorkspaceId;
    toWorkspace @2 :T.WorkspaceId;
}

struct CaptureFrameReadyEvent {
    captureId @0 :T.CaptureId;
    frame @1 :CaptureFrame;
}

# ══════════════════════════════════════════════════════════════════════
# QUERY
# ══════════════════════════════════════════════════════════════════════

struct WindowManagerQuery {
    union {
        windowAt @0 :T.Vec2;
        windowsForApp @1 :Text;
        windowStack @2 :T.WorkspaceId;
        snapZones @3 :T.OutputId;
        usableArea @4 :T.OutputId;
        allOutputs @5 :Void;
        wmCapabilities @6 :Void;
        custom @7 :CustomQuery;
    }
}

struct CustomQuery {
    name @0 :Text;
    parameters @1 :List(T.Meta);
}

struct WindowManagerQueryResult {
    union {
        window @0 :Window;
        windows @1 :List(Window);
        snapZones @2 :List(SnapZone);
        area @3 :T.Rect;
        outputs @4 :List(OutputInformation);
        capabilities @5 :List(WindowManagerCapability);
        custom @6 :List(T.Meta);
        notFound @7 :Void;
    }
}

# ══════════════════════════════════════════════════════════════════════
# CAPABILITIES
# ══════════════════════════════════════════════════════════════════════

enum WindowManagerCapability {
    moveWindows @0;
    resizeWindows @1;
    closeWindows @2;
    minimizeWindows @3;
    maximizeWindows @4;
    fullscreenWindows @5;
    setAlwaysOnTop @6;
    setSticky @7;
    manageWorkspaces @8;
    createWorkspaces @9;
    deleteWorkspaces @10;
    configureLayout @11;
    setFocusPolicy @12;
    showOverview @13;
    readAllWindows @14;
    captureScreen @15;
    captureWindow @16;
    capturePrivate @17;
    aiAssist @18;
    # Audit-7 additions:
    splitScreenWindows @19;
    pipWindows @20;
    freeformWindows @21;
    spatialWindows @22;
    automotiveMode @23;
    voiceOnlyMode @24;
    animationPipeline @25;
    foldableAware @26;
    custom @27;
}

# ══════════════════════════════════════════════════════════════════════
# AUDIT-7 ADDITIONS — Mobile, Foldable, Spatial, Automotive, Voice, Animation
# ══════════════════════════════════════════════════════════════════════

# ── Mobile Multi-Window ──
struct SplitScreenRequest {
    windowA @0 :T.WindowId;
    windowB @1 :T.WindowId;
    dividerPosition @2 :Float32;
    ratio @3 :Float32;
}

struct PipRequest {
    windowId @0 :T.WindowId;
    position @1 :T.Vec2i;
    size @2 :T.Size;
}

# ── Foldable State ──
struct FoldableState {
    state @0 :FoldState;
    hingeAngle @1 :Float32;
    displayWidth @2 :UInt32;
    displayHeight @3 :UInt32;
    continuityToken @4 :Text;
}

enum FoldState {
    open @0;
    closed @1;
    halfClosed @2;
    flex @3;
    other @4;
    custom @5;
}

# ── Spatial Window ──
struct SpatialWindowState {
    pose3D @0 :T.Rect3D;
    depth @1 :Float32;
    occlusionMode @2 :OcclusionMode;
    anchorId @3 :Text;
    handTrackingEnabled @4 :Bool;
}

enum OcclusionMode {
    none @0;
    selfOcclude @1;
    fullOcclude @2;
    other @3;
    custom @4;
}

# ── Automotive HMI ──
struct AutomotiveHMI {
    displayRole @0 :AutomotiveDisplayRole;
    nightMode @1 :Bool;
    driverFocused @2 :Bool;
    distractionLevel @3 :DistractionLevel;
}

enum AutomotiveDisplayRole {
    instrumentCluster @0;
    centerStack @1;
    rearSeat @2;
    headUpDisplay @3;
    other @4;
    custom @5;
}

enum DistractionLevel {
    low @0;
    medium @1;
    high @2;
    blocked @3;
    other @4;
    custom @5;
}

# ── Voice Window ──
struct VoiceWindowState {
    conversationId @0 :Text;
    turnIndex @1 :UInt32;
    state @2 :VoiceWindowMode;
    multimodal @3 :Bool;
}

enum VoiceWindowMode {
    listening @0;
    processing @1;
    speaking @2;
    idle @3;
    other @4;
    custom @5;
}

# ── Window Animation (audit-7 false positive: window_animation.capnp belongs here) ──
struct WindowAnimation {
    animationId @0 :UInt32;
    windowId @1 :T.WindowId;
    type @2 :AnimationType;
    spec @3 :T.AnimationSpec;
    progress @4 :Float32;
    state @5 :AnimationState;
}

enum AnimationType {
    open @0;
    close @1;
    minimize @2;
    maximize @3;
    fullscreen @4;
    split @5;
    pip @6;
    custom @7;
}

enum AnimationState {
    pending @0;
    playing @1;
    paused @2;
    completed @3;
    cancelled @4;
    custom @5;
}

# ── Window Thumbnail ──
struct WindowThumbnail {
    windowId @0 :T.WindowId;
    thumbnailData @1 :T.DataHandle;
    lastActive @2 :T.Timestamp;
    title @3 :Text;
    appIcon @4 :T.DataHandle;
}

# ── Mobile Snap Zone ──
struct MobileSnapZone {
    edge @0 :MobileSnapEdge;
    splitRatio @1 :Float32;
    animation @2 :T.AnimationSpec;
}

enum MobileSnapEdge {
    left @0;
    right @1;
    topLeft @2;
    topRight @3;
    bottomLeft @4;
    bottomRight @5;
    other @6;
    custom @7;
}

# ── Window Group ──
struct WindowGroup {
    groupId @0 :UInt32;
    windows @1 :List(T.WindowId);
    layout @2 :GroupLayout;
    primaryWindow @3 :T.WindowId;
}

enum GroupLayout {
    tabbed @0;
    split @1;
    deck @2;
    spatial @3;
    other @4;
    custom @5;
}

# ── Window Input Redirection (audit-8 What's Still Missing) ──
struct InputRedirection {
    windowId @0 :T.WindowId;
    inputTypes @1 :List(InputRedirectionType);
    priority @2 :UInt8;
}

enum InputRedirectionType {
    virtualKeyboard @0;
    stylus @1;
    gameController @2;
    touch @3;
    custom @4;
}

# ── Lock Screen Windows (audit-8 What's Still Missing) ──
struct LockScreenWindow {
    windowId @0 :T.WindowId;
    shortcuts @1 :List(LockScreenShortcut);
    emergency @2 :Bool;
}

struct LockScreenShortcut {
    id @0 :Text;
    label @1 :Text;
    action @2 :Shell.ShellAction;
}

# ── Notification Window Management (audit-8 What's Still Missing) ──
struct NotificationWindow {
    windowId @0 :T.WindowId;
    notificationId @1 :T.NotificationId;
    style @2 :NotificationWindowStyle;
}

enum NotificationWindowStyle {
    headsUp @0;
    expanded @1;
    collapsed @2;
    custom @3;
}

# ── Window Snappable Mobile Presets (audit-8 What's Still Missing) ──
struct MobilePreset {
    id @0 :Text;
    name @1 :Text;
    corner @2 :MobileCorner;
    splitRatio @3 :Float32;
}

enum MobileCorner {
    topLeft @0;
    topRight @1;
    bottomLeft @2;
    bottomRight @3;
    custom @4;
}

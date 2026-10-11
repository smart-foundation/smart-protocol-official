@0xa1b2c3d4e5f60006;

# ══════════════════════════════════════════════════════════════════════
# Window Manager — window lifecycle, workspace management, layout, snapping.
#
# WHAT THIS IS
#   The service that places and orders windows on the outputs the compositor
#   owns. It answers "where is this window, which workspace is it on, what
#   does the stack look like" — it does not composite, and it does not own a
#   second copy of any other service's contract.
#
# WHO CONSUMES IT
#   Shells (panels, overview, task switcher), apps that place their own
#   windows, automation.
#
# WHAT IS DELIBERATELY OPAQUE
#   Process identity (`T.ProcessId`), app identity (`T.AppId`), window-group
#   and snap-zone identity (server-issued typed IDs), and the capability
#   vocabulary (open tokens). No window system is named; no foldable hinge,
#   no vehicle display role, no voice-window state machine appears in a
#   required position.
#
# WHAT MOVED ELSEWHERE (and why this file is smaller than it was)
#   - Screen capture now lives ONLY in compositor.capnp. Two capture
#     authorities with two frame types was a fork with no correct answer,
#     and this file's copy carried a `dataHandle @5 :UInt64` that the schema
#     itself told consumers to pretend was a `T.DataHandle`.
#   - Window animation now lives ONLY in compositor.capnp (`defineAnimation`,
#     which returns a server-issued id).
#   - The session handshake, the capability request, the output types and the
#     unknown-event envelope are imported from compositor.capnp. This file no
#     longer declares rival versions of any of them.
#   - The layering inversion is gone: this file no longer imports shell.capnp.
#
# Ordinal note: Cap'n Proto requires sequential interface ordinals, so
# deleting the legacy flat `WindowManager` interface and the capture/animation
# blocks renumbered the WindowManagerSession. Pre-release this is free; the mapping is
# recorded in the section comment below.
# ══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using C = import "compositor.capnp";

# ── Identity ──────────────────────────────────────────────────
# Window-group and snap-zone identity is server-issued and opaque, and it
# was promoted to types.capnp in the 2026-10-10 integration pass (batch D's
# cross-batch item 2): `T.WindowGroupId` and `T.SnapZoneId`. This file
# keeps no local id wrappers, so a consumer correlating windows to groups
# imports one type rather than reading a second definition out of the
# window manager's schema.

# ══════════════════════════════════════════════════════════════════════
# SESSION
#
# Ordinals are sequential and hole-free by construction. The prior draft's
# @0–@55 mapped as: handshake @0, listWindows @1, getWindow @2,
# getFocusedWindow @3, focusWindow @4, closeWindow @5, moveWindow @6,
# resizeWindow @7, moveResizeWindow @8, minimizeWindow @9, restoreWindow @10,
# maximizeWindow @11, toggleFullscreen @12, setAlwaysOnTop @13, setSticky @14,
# snapWindow @15, listSnapZones @16, getUsableArea @17, tileWindows @18,
# setFocusPolicy @19, listWorkspaces @20, getWorkspace @21, switchWorkspace @22,
# switchWorkspaceRelative @23, createWorkspace @24, deleteWorkspace @25,
# moveWindowToWorkspace @26, moveWindowToOutput @27, showOverview @28,
# hideOverview @29, showDesktop @30, subscribe @35, query @36. Deleted
# outright: capture @31/@32 and the whole capture model, listOutputs @33
# (re-issued paginated), getOutput @34, the animation family @47/@48, the
# lock-screen @52, notification-window @53 and mobile-preset @54/@55 surfaces,
# and the entire flat `WindowManager` interface with its `*Paged` twins.
# ══════════════════════════════════════════════════════════════════════

interface WindowManagerSession {

    struct HandshakeRequest {
        applicationId   @0 :T.AppId;
        applicationName @1 :Text;
        version         @2 :T.Version;
        protocolVersion @3 :T.Version;
        capabilities    @4 :List(C.CapabilityRequest);
        metadata        @5 :List(T.Meta);
    }

    struct HandshakeResponse {
        sessionId     @0 :T.SessionId;
        agreedVersion @1 :T.Version;
        granted       @2 :List(C.GrantedCapability);
        denied        @3 :List(C.DeniedCapability);
        windowManager @4 :C.ServiceInfo;
        result        @5 :C.HandshakeResult;
    }

    handshake @0 (request :HandshakeRequest)
               -> (response :HandshakeResponse);

    # -- Windows --

    listWindows @1 (filter :WindowFilter, pagination :T.Pagination)
                 -> (windows :List(Window), total :UInt64);

    getWindow @2 (id :T.WindowId) -> (result :WindowResult);

    getFocusedWindow @3 () -> (result :WindowResult);

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
    listSnapZones   @16 (output :T.OutputId, pagination :T.Pagination)
                     -> (zones :List(SnapZone), total :UInt64);
    getUsableArea   @17 (output :T.OutputId) -> (area :T.Rect);

    # -- Layout --

    tileWindows     @18 (request :TileRequest)
                     -> (result :T.VoidResult);
    setFocusPolicy  @19 (policy :FocusPolicyRequest)
                     -> (result :T.VoidResult);

    # -- Workspaces --

    listWorkspaces       @20 (pagination :T.Pagination)
                          -> (workspaces :List(WorkspaceInfo), total :UInt64);
    getWorkspace         @21 (id :T.WorkspaceId) -> (result :WorkspaceResult);
    switchWorkspace      @22 (id :T.WorkspaceId) -> (result :T.VoidResult);
    switchWorkspaceRelative @23 (direction :WorkspaceDirection)
                             -> (result :T.VoidResult);
    createWorkspace      @24 (name :Text) -> (result :WorkspaceResult);
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

    # -- Outputs (types imported from compositor.capnp) --

    listOutputs     @31 (pagination :T.Pagination)
                     -> (outputs :List(C.OutputInfo), total :UInt64);
    getOutput       @32 (id :T.OutputId) -> (result :OutputResult);

    # -- Events --

    subscribe       @33 (filter :WindowManagerEventFilter)
                     -> (stream :WindowManagerEventStream);

    # -- Query --

    query           @34 (query :WindowManagerQuery, pagination :T.Pagination)
                     -> (result :WindowManagerQueryResult);

    # -- Multi-window layout --

    enterSplitScreen @35 (request :SplitScreenRequest) -> (result :T.VoidResult);
    exitSplitScreen  @36 (windowId :T.WindowId) -> (result :T.VoidResult);
    enterPip         @37 (request :PipRequest) -> (result :T.VoidResult);
    exitPip          @38 (windowId :T.WindowId) -> (result :T.VoidResult);

    # -- Thumbnails (task switcher) --

    getWindowThumbnail @39 (windowId :T.WindowId) -> (thumbnail :WindowThumbnail);
    listWindowThumbnails @40 (pagination :T.Pagination)
                          -> (thumbnails :List(WindowThumbnail), total :UInt64);

    # -- Groups --

    createWindowGroup @41 (group :WindowGroup) -> (result :WindowGroupResult);
    destroyWindowGroup @42 (groupId :T.WindowGroupId) -> (result :T.VoidResult);
}

# ── Window ────────────────────────────────────────────────────

struct Window {
    id @0 :T.WindowId;
    title @1 :Text;
    appId @2 :T.AppId;
    surfaceId @3 :T.SurfaceId;
    rect @4 :T.Rect;
    state @5 :WindowState;
    workspace @6 :T.WorkspaceId;
    output @7 :T.OutputId;
    decorated @8 :Bool;
    alwaysOnTop @9 :Bool;
    opacity @10 :Float32;
    shadow @11 :Bool;
    border @12 :Bool;
    minSize @13 :T.Size;
    maxSize @14 :T.Size;
    # Opaque process reference. A window system with no per-window process
    # (a tiler managing its own surfaces, a remote desktop) simply leaves it
    # unset — there is no sentinel number to invent.
    processId @15 :T.ProcessId;
    windowClass @16 :Text;
    leaderId @17 :T.WindowId;
    groupId @18 :T.WindowGroupId;
    isPinned @19 :Bool;
    # Open token. See the conformance tokens at the end of this file.
    windowType @20 :Text;
    layer @21 :T.WindowLayer;
    focused @22 :Bool;
    sticky @23 :Bool;
    urgent @24 :Bool;
    canClose @25 :Bool;
    canMinimize @26 :Bool;
    canMaximize @27 :Bool;
    canFullscreen @28 :Bool;
    canResize @29 :Bool;
    canMove @30 :Bool;
    parent @31 :T.WindowId;
    children @32 :List(T.WindowId);
    createdAt @33 :T.Timestamp;
    focusedAt @34 :T.Timestamp;
    lastActiveAt @35 :T.Timestamp;
    # 3D pose is a superset for 2D window managers; 2D WMs ignore z.
    pose @36 :T.Vec3;
    metadata @37 :List(T.Meta);
}

enum WindowState {
    # Absent means the backend decides; it must never silently mean a
    # specific paradigm value.
    any @0;
    normal @1;
    minimized @2;
    maximized @3;
    fullscreen @4;
    hidden @5;
    custom @6;
}

struct WindowResult {
    union {
        window  @0 :Window;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct WindowFilter {
    appId @0 :T.AppId;
    workspace @1 :T.WorkspaceId;
    output @2 :T.OutputId;
    state @3 :WindowState;
    layer @4 :T.WindowLayer;
    focused @5 :T.BoolFilter;
    processId @6 :T.ProcessId;
    windowType @7 :Text;
}

# -- SnapZone --

# A snap zone is a rect plus an optional server-issued id. The preset
# vocabulary is a WM policy surface, so `preset` is an open token rather than
# a frozen list of layout positions; `grid` carries the structured case.
struct SnapZone {
    id     @0 :T.SnapZoneId;
    preset @1 :Text;
    rect   @2 :T.Rect;
    grid   @3 :GridSnap;
}

struct GridSnap {
    columns   @0 :UInt8;
    rows      @1 :UInt8;
    column    @2 :UInt8;
    row       @3 :UInt8;
    columnSpan @4 :UInt8;
    rowSpan   @5 :UInt8;
}

# -- Tiling --

struct TileRequest {
    windowId @0 :T.WindowId;
    rect @1 :T.Rect;
    windows @2 :List(T.WindowId);
    algorithm @3 :TilingAlgorithm;
    area @4 :T.Rect;
    gaps @5 :Gaps;
}

enum TilingAlgorithm {
    # Absent means the backend decides; it must never silently mean a
    # specific paradigm value.
    unspecified @0;
    horizontal @1;
    vertical @2;
    grid @3;
    spiral @4;
    master @5;
    custom @6;
}

struct Gaps {
    outer @0 :UInt32;
    inner @1 :UInt32;
}

# -- Focus policy --

struct FocusPolicyRequest {
    union {
        click         @0 :Void;
        followPointer @1 :Void;
        sloppy        @2 :SloppyFocus;
        manual        @3 :Void;
        custom        @4 :T.StringMap;
        unknown       @5 :Void;
    }
}

struct SloppyFocus {
    focusDelay @0 :T.Duration;
    raiseOnFocus @1 :Bool;
}

# -- Workspaces --

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
    # Absent means the backend decides; it must never silently mean a
    # specific paradigm value.
    unspecified @0;
    left @1;
    right @2;
    up @3;
    down @4;
    prev @5;
    next @6;
    custom @7;
}

struct WorkspaceResult {
    union {
        workspace @0 :WorkspaceInfo;
        error     @1 :T.Error;
        unknown   @2 :Void;
    }
}

struct OutputResult {
    union {
        output  @0 :C.OutputInfo;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

# -- Multi-window layout --

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

# -- Thumbnails --

struct WindowThumbnail {
    windowId @0 :T.WindowId;
    thumbnailData @1 :T.DataHandle;
    lastActive @2 :T.Timestamp;
    title @3 :Text;
    appIcon @4 :T.DataHandle;
}

# -- Groups --

struct WindowGroup {
    groupId @0 :T.WindowGroupId;
    windows @1 :List(T.WindowId);
    layout @2 :GroupLayout;
    primaryWindow @3 :T.WindowId;
}

enum GroupLayout {
    # Absent means the backend decides; it must never silently mean a
    # specific paradigm value.
    unspecified @0;
    tabbed @1;
    split @2;
    deck @3;
    spatial @4;
    other @5;
    custom @6;
}

struct WindowGroupResult {
    union {
        group   @0 :WindowGroup;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

# ══════════════════════════════════════════════════════════════════════
# EVENTS
# ══════════════════════════════════════════════════════════════════════

interface WindowManagerEventStream {
    pull   @0 (maxEvents :UInt32) -> (events :List(WindowManagerEvent));
    cancel @1 () -> T.VoidResult;
}

struct WindowManagerEventFilter {
    windowIds @0 :List(T.WindowId);
    workspaceIds @1 :List(T.WorkspaceId);
    outputIds @2 :List(T.OutputId);
    kinds @3 :List(WindowManagerEventKind);
}

enum WindowManagerEventKind {
    windowEvents    @0;
    workspaceEvents @1;
    outputEvents    @2;
    focusEvents     @3;
    custom          @4;
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

    focusChanged @10 :WindowFocusChangedEvent;

    workspaceCreated @11 :WorkspaceInfo;
    workspaceDestroyed @12 :T.WorkspaceId;
    workspaceSwitched @13 :WorkspaceSwitchedEvent;
    windowChangedWorkspace @14 :WindowWorkspaceEvent;

    outputAdded @15 :C.OutputInfo;
    outputRemoved @16 :T.OutputId;
    outputChanged @17 :C.OutputInfo;

    groupCreated @18 :WindowGroup;
    groupDestroyed @19 :T.WindowGroupId;

    unknown @20 :T.UnknownEvent;
    }
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

struct WindowFocusChangedEvent {
    oldWindow @0 :T.WindowId;
    newWindow @1 :T.WindowId;
    reason @2 :C.FocusReason;
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

# ══════════════════════════════════════════════════════════════════════
# QUERY
# Every list answer is bounded and carries a total.
# ══════════════════════════════════════════════════════════════════════

struct WindowManagerQuery {
    union {
        windowAt @0 :T.Vec2;
        windowsForApp @1 :T.AppId;
        windowStack @2 :T.WorkspaceId;
        snapZones @3 :T.OutputId;
        usableArea @4 :T.OutputId;
        allOutputs @5 :Void;
        windowManagerCapabilities @6 :Void;
        custom @7 :C.CustomQuery;
        unknown @8 :Void;
    }
}

struct WindowManagerQueryResult {
    union {
        window @0 :Window;
        windows @1 :List(Window);
        snapZones @2 :List(SnapZone);
        area @3 :T.Rect;
        outputs @4 :List(C.OutputInfo);
        capabilities @5 :List(Text);
        custom @6 :List(T.Meta);
        notFound @7 :Void;
        unknown @8 :Void;
    }
    total @9 :UInt64;
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# An unrecognised value MUST be ignored, never rejected. They are Text and
# deliberately not enums: an enum here would be an eternal commitment to
# today's spelling of a window-manager concept.
# ══════════════════════════════════════════════════════════════════════

const typeNormal              :Text = "normal";
const typeDialog              :Text = "dialog";
const typeSplash              :Text = "splash";
const typeTooltip             :Text = "tooltip";
const typePopup               :Text = "popup";
const typeDock                :Text = "dock";
const typeToolbar             :Text = "toolbar";
const typeMenu                :Text = "menu";
const typeUtility             :Text = "utility";
const typeDropdown            :Text = "dropdown";
const typePopupMenu           :Text = "popupMenu";
const typeTooltipMenu         :Text = "tooltipMenu";
const typeNotification        :Text = "notification";
const typeCriticalNotification :Text = "criticalNotification";
const typeOnScreenDisplay     :Text = "onScreenDisplay";
const typeOther               :Text = "other";

const presetTopLeft       :Text = "topLeft";
const presetTop           :Text = "top";
const presetTopRight      :Text = "topRight";
const presetLeft          :Text = "left";
const presetCenter        :Text = "center";
const presetRight         :Text = "right";
const presetBottomLeft    :Text = "bottomLeft";
const presetBottom        :Text = "bottom";
const presetBottomRight   :Text = "bottomRight";
const presetMaximize      :Text = "maximize";
const presetGrid          :Text = "grid";
const presetThirds        :Text = "thirds";

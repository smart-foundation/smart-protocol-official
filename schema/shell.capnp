@0xa1b2c3d4e5f60031;

# ══════════════════════════════════════════════════════════════════════
# Shell — desktop session surface: launcher, tray, portals, session control,
#         and the command interpreter.
#
# TWO surfaces, deliberately, and they answer different questions:
#
#   ShellSession      (@0–@76) — WHAT IS ON SCREEN AND WHAT STATE THE SESSION IS
#               IN. Launcher apps, notifications, clipboard, tray,
#               audio/network/power/display state, search, settings,
#               portals, session control, events, and — at @76 — the
#               acquisition point for the interpreter. A compositor asks this.
#
#   ShellService (@0–@44) — HOW INPUT BECOMES EXECUTION. Execute, complete,
#               history, aliases, variables, environment, jobs, undo,
#               scripts, watchers, bookmarks, guided mode, natural-language
#               interpretation. A REPL asks this.
#
# Merging them would produce one 113-method interface with no single audience,
# which is the shape every schema in this repo has drifted toward.
#
# ── DELEGATION, NOT DUPLICATION ────────────────────────────────────────
#
# The shell ORCHESTRATES; the canonical services OWN their data. Every
# façade below takes and returns the canonical service's types, so there is
# exactly one notification model, one clipboard model, one settings model and
# one app taxonomy in the protocol:
#
#   notifications  ->  notification.capnp  (channels, threads, attestation)
#   clipboard      ->  clipboard.capnp     (history, pinning)
#   settings       ->  settings.capnp      (domain+key, structured values)
#   apps/catalog   ->  appindex.capnp      (one taxonomy, one icon type)
#
# The shell's METHOD SET and ORDINALS are preserved from the official draft:
# every method that existed is still here, at its ordinal, and nothing was
# renumbered. What changed is WHOSE TYPES the façades carry — shell-local
# rival models (`Notification`, `Urgency`, `ClipboardEntry`,
# `ClipboardContentType`, `ShellSettingValue`, `ShellSetting`,
# `ApplicationCategory`) are gone, so there is one model per domain instead of
# two that drift.
#
# WHICH METHOD OWNS WHAT (stated so no implementer has to guess)
#   shell owns: the tray, portals (file/colour pickers, open-uri), the
#     launcher's own runtime view of an app, session control, and the
#     interpreter surface.
#   notification.capnp owns: notification content, channels, DND.
#   clipboard.capnp owns: clipboard content, history, pins.
#   settings.capnp owns: every setting value.
#   appindex.capnp owns: app catalog metadata, categories, icons.
#   compositor.capnp owns: the session handshake, surfaces, capture.
#   power.capnp owns: power state (imported, not copied).
#
# WHAT WAS DELETED AND WHY
#   The orphan type zoo that no method referenced: AR spatial shell, car
#   split-screen zones, shell analytics, theming pipeline, multi-user
#   profiles, plugin info, session persistence, notification grouping,
#   command-history analytics, and the shell's own accessibility tree. Each
#   was a contract for a feature with no caller; each would have been
#   implemented differently by every backend. The gesture type was renamed
#   `ShellGesture` to end its name collision with `types.capnp`.
#
# WHAT WAS NOT CHANGED, AND WHY
#   The panel-state getters (`getAudioState`, `setAudioVolume`,
#   `getNetworkState`, `getBluetoothState`, `getBrightness`, `setBrightness`,
#   `getNightLight`) are RETAINED, together with their local state structs.
#   They are the shell panel's one-frame aggregate view, and the services that
#   own live audio/network/bluetooth/display state belong to other batches.
#   The audit asked for these to be stripped to pure delegation; that is
#   recorded as deferred work rather than done here, because doing it would
#   mean importing three schemas this batch does not own.
# ══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "power.capnp".PowerState;
using C = import "compositor.capnp";
using N = import "notification.capnp";
using CB = import "clipboard.capnp";
using S = import "settings.capnp";
using AI = import "appindex.capnp";
# bluetooth.capnp owns the device and adapter vocabulary; the shell panel reports it, it does not re-declare it.
using B = import "bluetooth.capnp";
using import "capability.capnp".Capability;

interface ShellSession {

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
        shell         @4 :C.ServiceInfo;
        result        @5 :C.HandshakeResult;
    }

    handshake @0 (request :HandshakeRequest)
               -> (response :HandshakeResponse);

    # -- Launcher --

    listApps    @1  (filter :AI.AppFilter)
                 -> (apps :List(ApplicationEntry));
    findApps    @2  (query :Text)
                 -> (apps :List(ApplicationEntry));
    startApp    @3  (applicationId :T.AppId, arguments :List(Text))
                 -> (result :T.VoidResult);
    stopApp     @4  (applicationId :T.AppId)
                 -> (result :T.VoidResult);

    # -- Notifications (façade over notification.capnp) --

    listNotifications       @5  () -> (notifications :List(N.NotificationData));
    dismissNotification     @6  (id :T.NotificationId)
                              -> (result :T.VoidResult);
    dismissAllNotifications @7  () -> (result :T.VoidResult);
    invokeNotification      @8  (id :T.NotificationId, actionKey :Text)
                              -> (result :T.VoidResult);
    # Do Not Disturb is owned by notification.capnp (channels carry
    # importance and bypassDnd). These read and write that one authority.
    getDoNotDisturb         @9  () -> (enabled :Bool);
    setDoNotDisturb         @10 (enabled :Bool) -> (result :T.VoidResult);
    snoozeNotification      @11 (id :T.NotificationId, duration :T.Duration)
                              -> (result :T.VoidResult);
    sendNotification        @12 (notification :N.NotificationData)
                              -> (result :N.ShowResult);

    # -- Clipboard (façade over clipboard.capnp) --

    getClipboard        @13 () -> (content :CB.ClipboardContent);
    getClipboardHistory @14 (pagination :T.Pagination)
                         -> (items :List(CB.ClipboardItem), total :UInt64);
    setClipboard        @15 (content :CB.ClipboardContent)
                         -> (result :T.VoidResult);
    clearClipboard      @16 () -> (result :T.VoidResult);
    pinClipboard        @17 (id :T.ClipboardId) -> (result :T.VoidResult);
    unpinClipboard      @18 (id :T.ClipboardId) -> (result :T.VoidResult);
    deleteClipboard     @19 (id :T.ClipboardId) -> (result :T.VoidResult);

    # -- System Tray (shell-owned; nothing else models it) --

    listTrayIcons       @20 () -> (icons :List(TrayIcon));
    activateTrayIcon    @21 (id :T.TrayIconId) -> (result :T.VoidResult);

    # -- System State (the shell panel's aggregated view) --

    getAudioState       @22 () -> (state :ShellAudioState);
    setAudioVolume      @23 (sink :Text, level :UInt8) -> (result :T.VoidResult);
    setAudioMute        @24 (sink :Text, muted :Bool) -> (result :T.VoidResult);
    getNetworkState     @25 () -> (state :NetworkState);
    # PowerState is imported from power.capnp (canonical source).
    getPowerState       @26 () -> (state :PowerState);
    setPowerProfile     @27 (profile :Text) -> (result :T.VoidResult);
    getBluetoothState   @28 () -> (state :ShellBluetoothState);
    setBluetoothEnabled @29 (enabled :Bool) -> (result :T.VoidResult);

    # -- Display --

    getBrightness       @30 () -> (level :UInt8);
    setBrightness       @31 (level :UInt8) -> (result :T.VoidResult);
    # Night light temperature in Mirek (1000000 / color_temperature_kelvin).
    # Lower values = warmer (more orange), higher = cooler (more blue).
    getNightLight       @32 () -> (active :Bool, temperatureMirek :UInt16);
    setNightLight       @33 (active :Bool, temperatureMirek :UInt16)
                          -> (result :T.VoidResult);

    # -- Search --

    search              @34 (query :Text, pagination :T.Pagination)
                          -> (results :List(ShellSearchResult), total :UInt64);

    # -- ShellSession Management --

    logoutSession       @35 () -> (result :T.VoidResult);
    shutdownSession     @36 () -> (result :T.VoidResult);
    rebootSession       @37 () -> (result :T.VoidResult);
    suspendSession      @38 () -> (result :T.VoidResult);
    hibernateSession    @39 () -> (result :T.VoidResult);
    lockSession         @40 () -> (result :T.VoidResult);
    canShutdownSession  @41 () -> (can :Bool);
    canRebootSession    @42 () -> (can :Bool);
    canSuspendSession   @43 () -> (can :Bool);
    inhibitSleep        @44 (reason :Text) -> (handle :T.InhibitHandle);
    uninhibitSleep      @45 (handle :T.InhibitHandle) -> (result :T.VoidResult);

    # -- Portals (shell-owned) --

    openFilePicker      @46 (filter :FilePickerFilter, allowMultiple :Bool)
                          -> (files :List(PickedFile));
    saveFilePicker      @47 (suggestedName :Text, filter :FilePickerFilter)
                          -> (result :PickerResult);
    openColorPicker     @48 (initialColor :T.Color) -> (result :PickerResult);
    openUri             @49 (uri :T.Uri) -> (result :T.VoidResult);

    # -- Settings (façade over settings.capnp) --
    # Domain+key, because a domain-less key is a key collision with itself:
    # the shell's old model could not address the same setting the store
    # exposes.

    getSetting          @50 (domain :Text, key :Text)
                          -> (result :S.SettingResult);
    setSetting          @51 (domain :Text, key :Text, value :S.SettingValue)
                          -> (result :T.VoidResult);
    listSettings        @52 (domain :Text, pagination :T.Pagination)
                          -> (entries :List(S.SettingMapEntry), total :UInt64);

    # -- Events --

    subscribe           @53 (filter :ShellEventFilter)
                          -> (stream :ShellEventStream);

    # -- Query --

    query               @54 (query :ShellQuery) -> (result :ShellQueryResult);

    # -- Paginated Launcher --

    listAppsPaginated   @55 (filter :AI.AppFilter, pagination :T.Pagination)
                          -> (apps :List(ApplicationEntry), total :UInt64);
    findAppsPaginated   @56 (query :Text, pagination :T.Pagination)
                          -> (apps :List(ApplicationEntry), total :UInt64);

    # -- Paginated Notifications --

    listNotificationsPaginated @57 (pagination :T.Pagination)
                          -> (notifications :List(N.NotificationData), total :UInt64);

    # -- Paginated Clipboard History --

    getClipboardHistoryPaginated @58 (pagination :T.Pagination)
                          -> (items :List(CB.ClipboardItem), total :UInt64);

    # -- Paginated Tray --

    listTrayIconsPaginated @59 (pagination :T.Pagination)
                          -> (icons :List(TrayIcon), total :UInt64);

    # -- Paginated Search --

    searchPaginated @60 (query :Text, pagination :T.Pagination)
                          -> (results :List(ShellSearchResult), total :UInt64);

    # -- Paginated Settings --

    listSettingsPaginated @61 (filter :SettingsPageFilter, pagination :T.Pagination)
                          -> (entries :List(S.SettingMapEntry), total :UInt64);

    # ─── Multi-Modal ShellSession ───────────────────────────────────

    # Get current session mode.
    getSessionMode @62 () -> (mode :Text);

    # Set session mode (text, voice, gesture, multiModal, brief).
    setSessionMode @63 (mode :Text) -> (result :T.VoidResult);

    # ─── AI-First Completion ───────────────────────────────────

    # Get AI-powered semantic completions.
    getAiCompletion @64 (request :AiCompletionRequest)
                     -> (results :List(AiCompletionResult));

    # ─── Cross-Device Handoff ──────────────────────────────────

    # Handoff shell state to another device.
    handoff @65 (request :HandoffRequest) -> (result :HandoffResult);

    # ─── Voice Shell ───────────────────────────────────────────

    # Process a spoken command (screenless devices).
    processVoiceCommand @66 (audio :T.DataHandle, language :T.Language)
                         -> (result :VoiceShellResult);

    # Stream intermediate voice results.
    processVoiceCommandStream @67 (audio :T.DataHandle, language :T.Language)
                               -> (stream :VoiceShellResultStream);

    # Subscribe to wake word detection.
    subscribeWakeWord @68 () -> (subscription :ShellWakeWordSubscription);

    # ─── Gesture Navigation ────────────────────────────────────

    # Process a gesture command (AR/VR/watch/car).
    processGesture @69 (event :ShellGesture) -> (result :ShellAction);

    # ─── Brief Mode ────────────────────────────────────────────

    # Execute a command in brief mode (returns description, not stream).
    executeBrief @70 (command :Text) -> (result :BriefResult);

    # ─── Accessibility ─────────────────────────────────────────
    # The authoritative preference set is accessibility.capnp's
    # AccessibilityPreferences; this is the shell's cached view of it.

    # Get current accessibility mode.
    getAccessibilityMode @71 () -> (mode :AccessibilityMode);

    # Set accessibility mode.
    setAccessibilityMode @72 (mode :AccessibilityMode)
                          -> (result :T.VoidResult);

    # ─── Context Bubbles ───────────────────────────────────────

    # Show a context bubble (hover tooltip, quick action).
    showContextBubble @73 (bubble :ContextBubble) -> T.VoidResult;

    # Dismiss a context bubble.
    dismissContextBubble @74 (bubbleId :UInt64) -> T.VoidResult;

    # ─── Batch Event Pull ──────────────────────────────────────

    # Pull multiple events at once (reduces IPC overhead).
    pullBatch @75 (stream :ShellEventStream, maxEvents :UInt32)
               -> (events :List(ShellEvent));

    # ─── Command interpreter ──────────────────────────────────
    # The second surface, acquired once. Holding `service` IS the authority to
    # run commands: nothing inside `ShellService` checks a permission, and
    # there is no per-command capability token to keep in sync. Discovery of
    # what commands exist stays open through `cli.capnp`'s registry.

    interpreter @76 (authority :Capability) -> (service :ShellService);
}

# ══════════════════════════════════════════════════════════════════════
# LAUNCHER
# ══════════════════════════════════════════════════════════════════════

# The launcher's own runtime view: the catalog record plus what the shell
# knows because it started it. Everything descriptive comes from
# appindex.capnp, so an app's category, icon and version have ONE home.
struct ApplicationEntry {
    info        @0 :AI.AppInfo;
    executable  @1 :Text;
    terminal    @2 :Bool;
    running     @3 :Bool;
    processIds  @4 :List(T.ProcessId);
    windowIds   @5 :List(T.WindowId);
    desktopId   @6 :Text;
}

# ══════════════════════════════════════════════════════════════════════
# NOTIFICATIONS
# Content, channels, DND and threading live in notification.capnp. This
# file carries no notification model of its own.
# ══════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════
# CLIPBOARD
# Content, history and pinning live in clipboard.capnp. This file carries
# no clipboard model of its own.
# ══════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════
# SYSTEM TRAY
# ══════════════════════════════════════════════════════════════════════

struct TrayIcon {
    id      @0 :T.TrayIconId;
    title   @1 :Text;
    iconName @2 :Text;
    status  @3 :Text;
    tooltip @4 :Text;
    menu    @5 :List(TrayMenuItem);
}

struct TrayMenuItem {
    key      @0 :Text;
    label    @1 :Text;
    icon     @2 :Text;
    enabled  @3 :Bool;
    toggle   @4 :Bool;
    checked  @5 :Bool;
    children @6 :List(TrayMenuItem);
}

# ══════════════════════════════════════════════════════════════════════
# SYSTEM STATE
# The panel's aggregated snapshot. Reading live values and subscribing to
# changes belongs to the owning services (audio, network, bluetooth,
# display, power); these getters exist so a panel can render one frame.
# ══════════════════════════════════════════════════════════════════════

struct ShellAudioState {
    sinks   @0 :List(AudioSink);
    sources @1 :List(AudioSource);
}

struct AudioSink {
    id     @0 :T.AudioDeviceId;
    name   @1 :Text;
    volume @2 :UInt8;
    muted  @3 :Bool;
    icon   @4 :Text;
}

struct AudioSource {
    id     @0 :T.AudioDeviceId;
    name   @1 :Text;
    volume @2 :UInt8;
    muted  @3 :Bool;
    icon   @4 :Text;
}

struct NetworkState {
    connected @0 :Bool;
    type      @1 :Text;
    ssid      @2 :Text;
    signal    @3 :UInt8;
    ipAddress @4 :T.IpAddress;
}

struct ShellBluetoothState {
    enabled @0 :Bool;
    devices @1 :List(B.BluetoothDevice);
}


# ══════════════════════════════════════════════════════════════════════
# SEARCH
# ══════════════════════════════════════════════════════════════════════

struct ShellSearchResult {
    id          @0 :Text;
    name        @1 :Text;
    description @2 :Text;
    icon        @3 :T.DataHandle;
    kind        @4 :Text;
    action      @5 :ShellAction;
    score       @6 :Float32;
}

# ══════════════════════════════════════════════════════════════════════
# PORTALS
# ══════════════════════════════════════════════════════════════════════

struct FilePickerFilter {
    name       @0 :Text;
    extensions @1 :List(Text);
    mimeTypes  @2 :List(T.MimeType);
}

struct PickedFile {
    path     @0 :T.FilePath;
    name     @1 :Text;
    mimeType @2 :T.MimeType;
    size     @3 :UInt64;
}

# A portal is user-driven and cancellable; cancellation is a first-class
# outcome, not an empty list.
struct PickerResult {
    union {
        files     @0 :List(PickedFile);
        path      @1 :T.FilePath;
        color     @2 :T.Color;
        cancelled @3 :Void;
        error     @4 :T.Error;
        unknown   @5 :Void;
    }
}

# ══════════════════════════════════════════════════════════════════════
# SETTINGS page filter (values live in settings.capnp)
# ══════════════════════════════════════════════════════════════════════

struct SettingsPageFilter {
    domain @0 :Text;
    prefix @1 :Text;
    sinceVersion @2 :UInt64;
    metadata @3 :T.StringMap;
}

# ══════════════════════════════════════════════════════════════════════
# EVENTS
# ══════════════════════════════════════════════════════════════════════

interface ShellEventStream {
    pull   @0 (maxEvents :UInt32) -> (events :List(ShellEvent));
    cancel @1 () -> T.VoidResult;
}

struct ShellEventFilter {
    kinds @0 :List(ShellEventKind);
}

enum ShellEventKind {
    launcherEvents     @0;
    notificationEvents @1;
    clipboardEvents    @2;
    trayEvents         @3;
    audioEvents        @4;
    networkEvents      @5;
    powerEvents        @6;
    searchEvents       @7;
    sessionEvents      @8;
    bluetoothEvents    @9;
    settingsEvents    @10;
    custom            @11;
}

struct ShellEvent {
    union {
    appStarted             @0  :ApplicationEntry;
    appStopped             @1  :ApplicationEntry;
    appRegistered          @2  :ApplicationEntry;
    appUnregistered        @3  :T.AppId;

    notificationReceived   @4  :N.NotificationData;
    notificationDismissed  @5  :T.NotificationId;
    allNotificationsDismissed @6 :Void;
    doNotDisturbChanged    @7  :Bool;

    clipboardChanged       @8  :CB.ClipboardItem;
    clipboardCleared       @9  :Void;

    trayIconAdded          @10 :TrayIcon;
    trayIconRemoved        @11 :T.TrayIconId;
    trayIconChanged        @12 :TrayIcon;

    audioStateChanged      @13 :ShellAudioState;
    networkStateChanged    @14 :NetworkState;
    powerStateChanged      @15 :PowerState;
    bluetoothStateChanged  @16 :ShellBluetoothState;

    searchResults          @17 :List(ShellSearchResult);

    sessionLocking         @18 :Void;
    sessionLocked          @19 :Void;
    sessionUnlocked        @20 :Void;
    shutdownImminent       @21 :T.Duration;

    settingChanged         @22 :S.SettingChange;

    unknown                @23 :T.UnknownEvent;
    }
}

# ══════════════════════════════════════════════════════════════════════
# QUERY
# ══════════════════════════════════════════════════════════════════════

struct ShellQuery {
    union {
        appById           @0 :T.AppId;
        appsByCategory    @1 :Text;
        runningApps       @2 :Void;
        favoriteApps      @3 :Void;
        shellCapabilities @4 :Void;
        custom            @5 :C.CustomQuery;
        unknown           @6 :Void;
    }
}

struct ShellQueryResult {
    union {
        app          @0 :ApplicationEntry;
        apps         @1 :List(ApplicationEntry);
        capabilities @2 :List(Text);
        custom       @3 :List(T.Meta);
        notFound     @4 :Void;
        unknown      @5 :Void;
    }
}

# ══════════════════════════════════════════════════════════════════════
# MULTI-MODAL SESSION, COMPLETION, HANDOFF, VOICE, GESTURE, BRIEF
# ══════════════════════════════════════════════════════════════════════

# Input modality — an open token. "Which device am I talking to" is answered
# with today's spellings published as conformance constants below; a future
# modality needs no ordinal.
const modeText       :Text = "text";
const modeVoice      :Text = "voice";
const modeGesture    :Text = "gesture";
const modeMultiModal :Text = "multiModal";
const modeBrief      :Text = "brief";

struct AiCompletionRequest {
    partialInput @0 :Text;
    context      @1 :AiCompletionContext;
    maxResults   @2 :UInt32;
}

struct AiCompletionContext {
    recentCommands @0 :List(Text);
    currentApp     @1 :T.AppId;
    timeOfDay      @2 :T.Timestamp;
    mode           @3 :Text;
}

struct AiCompletionResult {
    suggestion    @0 :Text;
    description   @1 :Text;
    confidence    @2 :Float32;
    action        @3 :ShellAction;
    source        @4 :Text;
}

struct ShellAction {
    union {
        appLaunch    @0 :T.AppId;
        shellCommand @1 :Text;
        uriOpen      @2 :T.Uri;
        settingChange @3 :S.SettingChange;
        custom       @4 :T.StringMap;
        unknown      @5 :Void;
    }
}

struct HandoffRequest {
    sourceDevice  @0 :Text;
    targetDevice  @1 :Text;
    sessionId     @2 :T.SessionId;
    transferData  @3 :HandoffData;
}

struct HandoffData {
    runningApps   @0 :List(T.AppId);
    clipboard     @1 :CB.ClipboardItem;
    searchContext @2 :Text;
    settingsDomain @3 :Text;
}

struct HandoffResult {
    union {
        accepted  @0 :Void;
        rejected  @1 :T.Error;
        unknown   @2 :Void;
    }
}

struct VoiceShellResult {
    recognizedText @0 :Text;
    confidence     @1 :Float32;
    action         @2 :ShellAction;
    spokenResponse @3 :Text;
    audioResponse  @4 :T.DataHandle;
}

interface VoiceShellResultStream {
    pull @0 () -> (result :VoiceShellResult, done :Bool);
    cancel @1 () -> T.VoidResult;
}

interface ShellWakeWordSubscription {
    pull @0 () -> (detected :Bool, confidence :Float32);
    cancel @1 () -> T.VoidResult;
}

# Renamed from `GestureEvent`, which collided with input.capnp's
# `GestureEvent` and with a `types.capnp` shadow of it (both the shadow and
# the collision are gone — the foundation copy was deleted in the
# 2026-10-10 integration pass as an unconsumed eternal type, leaving
# input.capnp's live shape as the one gesture event in the tree). This one
# names a shell navigation command; the shared type names a raw input gesture.
struct ShellGesture {
    command     @0 :Text;
    position    @1 :T.Vec2;
    velocity    @2 :T.Vec2;
    timestamp   @3 :T.Timestamp;
    source      @4 :Text;
    metadata @5 :T.StringMap;
}

struct BriefResult {
    summary     @0 :Text;
    icon        @1 :T.DataHandle;
    action      @2 :ShellAction;
    confidence  @3 :Float32;
}

struct AccessibilityMode {
    screenReader     @0 :Bool;
    highContrast     @1 :Bool;
    largeText        @2 :Bool;
    magnification    @3 :Float32;
    captions         @4 :Bool;
    reducedMotion    @5 :Bool;
    stickyKeys       @6 :Bool;
}

struct ContextBubble {
    id            @0 :UInt64;
    anchorSurface @1 :T.SurfaceId;
    position      @2 :T.Vec2i;
    content       @3 :BubbleContent;
    lifetime      @4 :T.Duration;
    interactive   @5 :Bool;
}

struct BubbleContent {
    union {
        text        @0 :Text;
        richText    @1 :T.DataHandle;
        image       @2 :T.DataHandle;
        appPreview  @3 :T.AppId;
        custom      @4 :T.StringMap;
        unknown     @5 :Void;
    }
}

# ══════════════════════════════════════════════════════════════════════
# SHELL SERVICE — the command interpreter surface
#
# Imported from the working tree's live design. It is a SECOND interface,
# not a second draft: `Session` answers "what is on screen and what state is
# the session in", `ShellService` answers "run this and tell me what
# happened".
#
# Two mode axes, deliberately distinct:
#   ShellSession.getSessionMode  (@62/@63) — INPUT MODALITY. How the user
#       communicates: text, voice, gesture, combined. "Which device am I?"
#   ShellConfig.mode        (below) — EXECUTION MODE. How the interpreter
#       runs: interactive, script, batch, guided. "How is this input run?"
#
# DELIBERATELY OMITTED from the interpreter surface, because `Session`
# already owns them and two answers to one question is a fork:
#   getPrompt/setPrompt — a prompt is a setting; ShellSession.getSetting reads it.
#   saveSnapshot/restoreSnapshot/listSnapshots/deleteSnapshots — ShellSession owns
#       session state; nothing in the protocol persists interpreter state.
#   clipboard/notification/Bluetooth/voice/wake-word/gesture methods — those
#       are ShellSession concerns.
#
# ONE DEVIATION from the imported design, recorded deliberately: `format` is
# a `T.MimeType` rather than a local `OutputFormat` enum. A closed enum of
# serialization formats is the doctrine's `logging.capnp LogFormat`
# anti-pattern; an open content type lets a 2046 format be produced with no
# schema change. Everything else is imported as designed.
# ══════════════════════════════════════════════════════════════════════

interface ShellService {
    # Get current interpreter state.
    getState @0 () -> (state :ShellState);

    # Start a new interpreter session.
    start @1 (config :ShellConfig) -> (session :ShellSessionInfo);

    # End the current interpreter session.
    end @2 (sessionId :T.SessionId) -> T.VoidResult;

    # Execute a command (from interactive or script mode).
    execute @3 (input :CommandInput) -> (result :ShellCommandResult);

    # Execute a natural language request (AI-assisted interpretation).
    interpret @4 (request :NaturalLanguageRequest) -> (interpreted :InterpretedCommand);

    # Confirm and execute an interpreted command.
    confirmAndExecute @5 (interpreted :InterpretedCommand, confirm :Bool) -> (result :ShellCommandResult);

    # ── Completion ──────────────────────────────────────────────────────

    # Get completions for partial input.
    complete @6 (input :Text, cursorPosition :UInt32) -> (completions :List(Completion));

    # Get completions for a selector path.
    completeSelector @7 (selector :Text) -> (completions :List(SelectorCompletion));

    # Get completions for a specific domain.
    completeDomain @8 (domain :Text, partial :Text) -> (completions :List(DomainCompletion));

    # ── History ─────────────────────────────────────────────────────────
    #
    # Distinct from ShellSession's analytics surface, which answers "which
    # commands do I use most often". This answers "what did I run, in what
    # order, and what happened" — per-invocation detail the analytics type
    # deliberately drops.

    getHistory @9 (filter :HistoryFilter, pagination :T.Pagination)
               -> (entries :List(HistoryEntry), total :UInt64);

    searchHistory @10 (pattern :Text, pagination :T.Pagination)
                  -> (entries :List(HistoryEntry), total :UInt64);

    clearHistory @11 () -> T.VoidResult;

    pinHistoryEntry @12 (entryId :UInt64) -> T.VoidResult;

    # ── Aliases ─────────────────────────────────────────────────────────

    setAlias @13 (name :Text, expansion :Text) -> T.VoidResult;
    removeAlias @14 (name :Text) -> T.VoidResult;
    listAliases @15 () -> (aliases :List(Alias));

    # ── Variables ───────────────────────────────────────────────────────

    setVariable @16 (name :Text, value :Text) -> T.VoidResult;
    # Returns `exists` rather than an error for an unset variable: "not set"
    # is an answer, not a fault.
    getVariable @17 (name :Text) -> (value :Text, exists :Bool);
    listVariables @18 () -> (variables :List(ShellVariable));

    # ── Environment ─────────────────────────────────────────────────────
    # Same `exists` convention as getVariable.

    getEnv @19 (name :Text) -> (value :Text, exists :Bool);
    setEnv @20 (name :Text, value :Text) -> T.VoidResult;
    listEnv @21 () -> (env :List(EnvVariable));

    # ── Jobs ────────────────────────────────────────────────────────────

    listJobs @22 () -> (jobs :List(Job));
    fg @23 (jobId :UInt64) -> T.VoidResult;
    bg @24 (jobId :UInt64) -> T.VoidResult;
    cancelJob @25 (jobId :UInt64) -> T.VoidResult;
    waitForJob @26 (jobId :UInt64, timeout :T.Duration) -> (result :ShellCommandResult);

    # ── Undo ────────────────────────────────────────────────────────────

    undo @27 () -> (result :UndoResult);
    redo @28 () -> (result :UndoResult);
    getUndoStack @29 () -> (stack :List(UndoEntry));

    # ── Script Mode ─────────────────────────────────────────────────────

    runScript @30 (path :Text, args :List(Text)) -> (result :ShellCommandResult);
    validateScript @31 (path :Text) -> (result :ScriptValidationResult);
    getScriptContext @32 () -> (context :ScriptContext);

    # ── Watchers ────────────────────────────────────────────────────────

    listWatchers @33 () -> (watchers :List(WatcherInfo));
    cancelWatcher @34 (watcherId :UInt64) -> T.VoidResult;

    # ── Bookmarks ───────────────────────────────────────────────────────

    bookmark @35 (command :Text, label :Text) -> T.VoidResult;
    listBookmarks @36 () -> (bookmarks :List(Bookmark));
    runBookmark @37 (bookmarkId :UInt64) -> (result :ShellCommandResult);
    removeBookmark @38 (bookmarkId :UInt64) -> T.VoidResult;

    # ── Guided Mode (for non-technical users) ───────────────────────────

    enterGuidedMode @39 (domain :Text) -> (guide :GuidedSession);
    guideNext @40 (sessionId :UInt64) -> (step :GuidedStep);
    guideInput @41 (sessionId :UInt64, input :Text) -> (result :GuidedStepResult);
    exitGuidedMode @42 (sessionId :UInt64) -> T.VoidResult;

    # ── Undoable Operations Registry ────────────────────────────────────

    registerUndoable @43 (operation :UndoableOperation) -> T.VoidResult;
    isUndoable @44 (command :Text) -> (undoable :Bool, description :Text);
}

# ── Interpreter state and configuration ────────────────────────────────

# Execution mode. NOT the same axis as ShellSession's input modality — see the
# file header.
enum ShellMode {
    # Absent means the backend decides; it must never silently mean a
    # specific paradigm value.
    unspecified @0;
    interactive @1;
    guided @2;
    script @3;
    batch @4;
    remote @5;
    voice @6;
    minimal @7;
    custom @8;
}

struct ShellState {
    sessionId @0 :T.SessionId;
    mode @1 :ShellMode;
    # Absolute path of the working directory. Always absolute, never "~/x" —
    # the shell resolves the tilde, and reporting the unresolved form would
    # make a client display a path that does not exist.
    currentDirectory @2 :T.FilePath;
    # Exit status of the last command. T.ExitStatus, not a raw Int32.
    lastExitStatus @3 :T.ExitStatus;
    lastCommand @4 :Text;
    activeJobs @5 :UInt32;
    activeWatchers @6 :UInt32;
    uptime @7 :T.Duration;
    commandCount @8 :UInt64;
    undoStackSize @9 :UInt32;
    # User this session runs as. T.UserId, not Text — the untyped version
    # invited callers to pass a username where a numeric id was expected.
    userId @10 :T.UserId;
    aiAssistEnabled @11 :Bool;
    theme @12 :ShellTheme;
    metadata @13 :T.StringMap;
}

struct ShellConfig {
    mode @0 :ShellMode;
    theme @1 :ShellTheme;
    historySize @2 :UInt32;
    # Initial prompt configuration. At runtime the prompt is a shell setting
    # and is read/written through ShellSession.getSetting/setSetting (@50/@51).
    prompt @3 :PromptConfig;
    aiAssistEnabled @4 :Bool;
    # Ask confirmation for destructive operations.
    confirmDestructive @5 :Bool;
    autoCorrect @6 :Bool;
    smartSuggestions @7 :Bool;
    verboseErrors @8 :Bool;
    colorOutput @9 :Bool;
    compactMode @10 :Bool;
    # Maximum undo levels (0 = unlimited).
    maxUndoLevels @11 :UInt32;
    keybindings @12 :KeyBindingProfile;
    defaultFormat @13 :T.MimeType;
    metadata @14 :T.StringMap;
}

# The interpreter session RECORD — the state a `ShellService.start` hands
# back. Named `ShellSessionInfo` because this file also declares
# `interface ShellSession` (the launcher/panel session service), and the two
# shared the bare name `Session` until the 2026-10-10 integration pass:
# one is a service you call, the other is a record describing a session you
# hold. Same-file name collisions are the defect E12 exists to stop, and a
# name that has to be disambiguated by which declaration you happen to be
# looking at is not disambiguated.
struct ShellSessionInfo {
    sessionId @0 :T.SessionId;
    config @1 :ShellConfig;
    startedAt @2 :T.Timestamp;
    # Capabilities the session was actually granted, after handshake
    # attenuation. NOT what the shell supports — a session that was refused
    # clipboard still runs, and claiming otherwise is the same
    # supported-vs-granted confusion that makes a capability list a lie.
    granted @3 :List(C.GrantedCapability);
    # Capabilities the handshake refused, with the reason.
    denied @4 :List(C.DeniedCapability);
    metadata @5 :T.StringMap;
}

# ── Execution ──────────────────────────────────────────────────

struct CommandInput {
    text @0 :Text;
    # Whether this came from an interactive session (affects confirmation
    # prompts and history recording, not execution).
    interactive @1 :Bool;
    # Suppress confirmation prompts. A script setting, not a caller override.
    force @2 :Bool;
    format @3 :T.MimeType;
    # Piped stdin for this command.
    pipeInput @4 :T.DataHandle;
    # Zero duration means no timeout. A caller wanting "never time out" and
    # a caller who forgot to set it are indistinguishable here, which is why
    # this is spelled out rather than left to convention.
    timeout @5 :T.Duration;
    metadata @6 :T.StringMap;
}

# Named ShellCommandResult, not CommandResult: cli.capnp already owns
# CommandResult for the execution service. Two types, one name, different
# owners is how a client ends up reading the wrong one.
struct ShellCommandResult {
    # Structured exit status. Not a raw Int32.
    exitStatus @0 :T.ExitStatus;
    # Human-readable output.
    output @1 :Text;
    # Structured data output, in the format `format` named. Empty when the
    # command produced no structured output — which is most of them.
    data @2 :T.DataHandle;
    # Error message, populated when exitStatus is a failure.
    error @3 :T.Error;
    # Suggested fix, when the shell has one. Empty means it does not; a
    # generic "try --help" here would be noise on every failure.
    suggestion @4 :Text;
    duration @5 :T.Duration;
    # Whether this command can be undone.
    undoable @6 :Bool;
    # The command that reverses it. Empty when `undoable` is false.
    undoCommand @7 :Text;
    # Non-fatal warnings.
    warnings @8 :List(T.Warning);
    # Output was truncated to fit. Always paired with totalItems so a client
    # can say "showing 100 of 4000" instead of silently showing a prefix.
    truncated @9 :Bool;
    totalItems @10 :UInt32;
    metadata @11 :T.StringMap;
}

# ── Natural language ──────────────────────────────────────────────────

struct NaturalLanguageRequest {
    text @0 :Text;
    context @1 :InterpretContext;
    # Execute without asking when confidence is at or above
    # confidenceThreshold. Both false and a zero threshold must be handled:
    # zero here means "never auto-execute", not "no threshold".
    autoExecute @2 :Bool;
    confidenceThreshold @3 :Float32;
    metadata @4 :T.StringMap;
}

struct InterpretContext {
    currentDirectory @0 :T.FilePath;
    recentCommands @1 :List(Text);
    # What the user is currently working with.
    currentDomain @2 :Text;
    availableApps @3 :List(T.AppId);
    # Brief system-state summary for the interpreter's benefit.
    systemState @4 :Text;
    metadata @5 :T.StringMap;
}

struct InterpretedCommand {
    commands @0 :List(Text);
    # Confidence in [0,1]. This is the interpreter's own estimate and is
    # explicitly not a probability; a client must not present it as one.
    confidence @1 :Float32;
    # What will happen, in words.
    explanation @2 :Text;
    destructive @3 :Bool;
    domains @4 :List(Text);
    requiresConfirmation @5 :Bool;
    # Alternatives offered when confidence is low. Empty is meaningful: the
    # interpreter had exactly one reading.
    alternatives @6 :List(InterpretedCommand);
    # How to reverse this, when it is reversible. Empty when it is not.
    undoDescription @7 :Text;
    metadata @8 :T.StringMap;
}

# ── Completion ──────────────────────────────────────────────────

struct Completion {
    text @0 :Text;
    description @1 :Text;
    kind @2 :Text;
    # Whether this completion takes a value after it.
    requiresValue @3 :Bool;
    valueExample @4 :Text;
    # Relevance for sorting. Higher sorts first; the shell decides the scale,
    # so only relative order is meaningful.
    relevance @5 :Float32;
    metadata @6 :T.StringMap;
}

struct SelectorCompletion {
    path @0 :Text;
    # Current value, when readable. `currentValueValid` false means the
    # selector exists but could not be read — different from "it is empty",
    # which is a real value a client should show.
    currentValue @1 :Text;
    currentValueValid @2 :Bool;
    valueType @3 :Text;
    description @4 :Text;
    metadata @5 :T.StringMap;
}

struct DomainCompletion {
    command @0 :Text;
    description @1 :Text;
    syntax @2 :Text;
    examples @3 :List(Text);
    metadata @4 :T.StringMap;
}

# ── History ───────────────────────────────────────────────────

struct HistoryEntry {
    id @0 :UInt64;
    command @1 :Text;
    timestamp @2 :T.Timestamp;
    exitStatus @3 :T.ExitStatus;
    duration @4 :T.Duration;
    directory @5 :T.FilePath;
    pinned @6 :Bool;
    tags @7 :List(Text);
    metadata @8 :T.StringMap;
}

struct HistoryFilter {
    # Substring match. Empty matches everything — stated because a caller
    # passing "" and a caller forgetting the field are otherwise
    # indistinguishable.
    pattern @0 :Text;
    # Exit status to filter by. `filterByStatus` false means "any status",
    # which is why this is not a magic sentinel value.
    exitStatus @1 :T.ExitStatus;
    filterByStatus @2 :Bool;
    directory @3 :T.FilePath;
    since @4 :T.Timestamp;
    tags @5 :List(Text);
    pinnedOnly @6 :Bool;
    metadata @7 :T.StringMap;
}

# ── Aliases, variables, environment ───────────────────────────

struct Alias {
    name @0 :Text;
    expansion @1 :Text;
    useCount @2 :UInt64;
    createdAt @3 :T.Timestamp;
    metadata @4 :T.StringMap;
}

struct ShellVariable {
    name @0 :Text;
    value @1 :Text;
    exported @2 :Bool;
    readOnly @3 :Bool;
    # Where this value came from: "user", "script", "default", or a specific
    # file path. Free text because it names sources this schema does not
    # enumerate, and an enum here would be a second authority on a concept
    # (setting provenance) that settings.capnp's SettingSource already owns.
    source @4 :Text;
    metadata @5 :T.StringMap;
}

struct EnvVariable {
    name @0 :Text;
    value @1 :Text;
    # "system", "shell", or an application name.
    source @2 :Text;
    metadata @3 :T.StringMap;
}

# ── Jobs ──────────────────────────────────────────────────────

struct Job {
    id @0 :UInt64;
    command @1 :Text;
    # The process behind this job. A shell-internal job has no process, so
    # `pidValid` is false and `pid` is meaningless — a shell that can run a
    # job without a pid cannot invent one.
    pid @2 :T.ProcessId;
    state @3 :Text;
    startedAt @4 :T.Timestamp;
    hasOutput @5 :Bool;
    pidValid @6 :Bool;
    # Last N lines. Empty with hasOutput true means output exists but no
    # preview was captured, which is different from "no output".
    outputPreview @7 :Text;
    metadata @8 :T.StringMap;
}

# ── Undo ──────────────────────────────────────────────────────

struct UndoResult {
    union {
        success @0 :UndoSuccess;
        failed  @1 :T.Error;
        unknown @2 :Void;
    }
}

struct UndoSuccess {
    # What was undone or redone.
    description @0 :Text;
    # The command that was undone.
    command @1 :Text;
    metadata @2 :T.StringMap;
}

struct UndoEntry {
    id @0 :UInt64;
    command @1 :Text;
    description @2 :Text;
    timestamp @3 :T.Timestamp;
    domain @4 :Text;
    # Whether this can be undone. An entry that reached the undo stack but is
    # not reversible is normal — `undo` skips it and says so.
    undoable @5 :Bool;
    reverseCommand @6 :Text;
    metadata @7 :T.StringMap;
}

struct UndoableOperation {
    command @0 :Text;
    description @1 :Text;
    domain @2 :Text;
    undoCommand @3 :Text;
    # Some operations are only reversible within a window.
    expiresAt @4 :T.Timestamp;
    metadata @5 :T.StringMap;
}

# ── Watchers, bookmarks, scripts ──────────────────────────────

struct WatcherInfo {
    id @0 :UInt64;
    domain @1 :Text;
    command @2 :Text;
    startedAt @3 :T.Timestamp;
    eventCount @4 :UInt64;
    lastEvent @5 :T.Timestamp;
    # Whether the watcher has already expired by its own condition. Distinct
    # from cancelled, which means something stopped it deliberately.
    expired @6 :Bool;
    metadata @7 :T.StringMap;
}

struct Bookmark {
    id @0 :UInt64;
    label @1 :Text;
    command @2 :Text;
    createdAt @3 :T.Timestamp;
    useCount @4 :UInt64;
    tags @5 :List(Text);
    metadata @6 :T.StringMap;
}

# Errors are routable, not prose: a script editor can jump to a line and
# show a severity, which a `List(Text)` cannot express.
struct ScriptValidationResult {
    union {
        ok      @0 :Void;
        errors  @1 :List(ScriptError);
        unknown @2 :Void;
    }
}

struct ScriptError {
    line @0 :UInt32;
    column @1 :UInt32;
    message @2 :Text;
    severity @3 :Text;
    metadata @4 :T.StringMap;
}

struct ScriptContext {
    path @0 :T.FilePath;
    line @1 :UInt32;
    variables @2 :List(ShellVariable);
    # Nested script call stack, innermost last.
    callStack @3 :List(T.FilePath);
    metadata @4 :T.StringMap;
}

# ── Theme ─────────────────────────────────────────────────────
#
# shell.capnp's own theming pipeline described the SESSION's theme handling.
# These describe the interpreter's own output styling — a narrower thing,
# and deliberately so.

enum KeyBindingProfile {
    # Absent means the backend decides; it must never silently mean a
    # specific paradigm value.
    unspecified @0;
    emacs @1;
    vi @2;
    custom @3;
}

struct ShellTheme {
    name @0 :Text;
    accent @1 :Text;
    successColor @2 :Text;
    errorColor @3 :Text;
    warningColor @4 :Text;
    infoColor @5 :Text;
    mutedColor @6 :Text;
    unicode @7 :Bool;
    emoji @8 :Bool;
    tableStyle @9 :Text;
    metadata @10 :T.StringMap;
}

# ── Prompt (session-start value only; see ShellService's note) ──

struct PromptConfig {
    # Template with ${user}, ${hostname}, ${cwd}, ${git_branch},
    # ${exit_code}, ${battery}, ${time}, ${job_count}, ${depth}.
    template @0 :Text;
    rightTemplate @1 :Text;
    # Prompt character. Empty means "the shell's default", NOT "no prompt" —
    # a shell that shows nothing is a distinct state and needs its own value.
    char @2 :Text;
    errorChar @3 :Text;
    showGit @4 :Bool;
    showBattery @5 :Bool;
    showTime @6 :Bool;
    showJobs @7 :Bool;
    showDuration @8 :Bool;
    # Minimum duration before the prompt shows one.
    durationThreshold @9 :Float32;
    # Multi-line prompt; each entry is one template.
    lines @10 :List(Text);
    metadata @11 :T.StringMap;
}

# ── Guided mode ───────────────────────────────────────────────

struct GuidedSession {
    sessionId @0 :UInt64;
    domain @1 :Text;
    description @2 :Text;
    totalSteps @3 :UInt32;
    currentStep @4 :UInt32;
    metadata @5 :T.StringMap;
}

struct GuidedStep {
    stepNumber @0 :UInt32;
    title @1 :Text;
    description @2 :Text;
    inputType @3 :Text;
    options @4 :List(GuidedOption);
    example @5 :Text;
    optional @6 :Bool;
    defaultValue @7 :Text;
    # Validation pattern, when this step validates its input. Empty means
    # the step accepts anything.
    validation @8 :Text;
    metadata @9 :T.StringMap;
}

struct GuidedOption {
    value @0 :Text;
    label @1 :Text;
    description @2 :Text;
    metadata @3 :T.StringMap;
}

struct GuidedStepResult {
    union {
        step    @0 :GuidedStep;
        done    @1 :Void;
        error   @2 :T.Error;
        unknown @3 :Void;
    }
}

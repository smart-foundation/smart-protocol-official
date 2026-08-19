@0xa1b2c3d4e5f60031;

using T = import "types.capnp";
using import "power.capnp".PowerState;# ══════════════════════════════════════════════════════════════════════
# Shell — desktop shell session (launcher, notifications, clipboard,
#         system tray, audio, network, power, display, search, settings,
#         portals, events).
#
# This schema is the high-level shell integration layer. It aggregates
# capabilities that a desktop shell session needs. power.capnp is
# canonical for PowerState; this schema imports it.
#
# Improvements beyond the original schema:
#   - PowerState imported from power.capnp (was duplicated).
#   - applicationId uses T.AppId (was raw Text).
#   - processIds uses List(T.ProcessId) (was List(UInt32)).
#   - snoozeNotification duration uses T.Duration (was raw UInt64 ms).
#   - TrayIcon.id uses T.TrayIconId (was raw Text).
#   - activateTrayIcon uses T.TrayIconId (was raw Text).
#   - nightLight temperature documented as Mirek (1000000/K).
#   - timeRemaining uses T.Duration (was raw UInt32 seconds).
#   - shutdownImminent uses T.Duration (was raw UInt32 seconds).
#   - All enums have custom/other variants for forward compatibility.
#   - ShellEventStream already has cancel method.
#   - notificationImageData uses T.DataHandle for large payloads.
#   - PickedFile.path uses T.FilePath (was raw Text).
#   - saveFilePicker returns T.FilePath (was raw Text).
#   - ShellSettingValue union has custom variant for forward compat.
#   - Paginated list methods added for launcher, notifications, clipboard.
#   - BluetoothDevice.address uses T.BluetoothAddress (was raw Text).
#   - SearchResult.icon uses T.DataHandle (was raw Text).
#   - ShellEventStream.next renamed to pull (canonical subscription pattern).
# ══════════════════════════════════════════════════════════════════════

interface Session {

    struct HandshakeRequest {
        applicationId @0 :T.AppId;
        version       @1 :T.Version;
        capabilities  @2 :List(ShellCapability);
        metadata      @3 :List(T.Meta);
    }

    struct HandshakeResponse {
        sessionId @0 :T.SessionId;
        shell     @1 :ShellInfo;
        granted   @2 :List(ShellCapability);
        denied    @3 :List(ShellCapability);
        result    @4 :HandshakeResult;
    }

    enum HandshakeResult {
        accepted         @0;
        acceptedDegraded @1;
        rejected         @2;
        custom           @3;
    }

    struct ShellInfo {
        name         @0 :Text;
        version      @1 :T.Version;
        capabilities @2 :List(ShellCapability);
        metadata     @3 :List(T.Meta);
    }

    handshake @0 (request :HandshakeRequest)
               -> (response :HandshakeResponse);

    # -- Launcher --

    listApps    @1  (filter :ApplicationFilter)
                 -> (apps :List(ApplicationEntry));
    findApps    @2  (query :Text)
                 -> (apps :List(ApplicationEntry));
    startApp    @3  (applicationId :T.AppId, arguments :List(Text))
                 -> (result :T.VoidResult);
    stopApp     @4  (applicationId :T.AppId)
                 -> (result :T.VoidResult);

    # -- Notifications --

    listNotifications       @5  () -> (notifications :List(Notification));
    dismissNotification     @6  (id :T.NotificationId)
                              -> (result :T.VoidResult);
    dismissAllNotifications @7  () -> (result :T.VoidResult);
    invokeNotification      @8  (id :T.NotificationId, actionKey :Text)
                              -> (result :T.VoidResult);
    getDoNotDisturb         @9  () -> (enabled :Bool);
    setDoNotDisturb         @10 (enabled :Bool) -> (result :T.VoidResult);
    snoozeNotification      @11 (id :T.NotificationId, duration :T.Duration)
                              -> (result :T.VoidResult);
    sendNotification        @12 (notification :Notification)
                              -> (id :T.NotificationId);

    # -- Clipboard --

    getClipboard        @13 () -> (entry :ClipboardEntry);
    getClipboardHistory @14 (limit :UInt32) -> (entries :List(ClipboardEntry));
    setClipboard        @15 (entry :ClipboardEntry) -> (result :T.VoidResult);
    clearClipboard      @16 () -> (result :T.VoidResult);
    pinClipboard        @17 (id :T.ClipboardId) -> (result :T.VoidResult);
    unpinClipboard      @18 (id :T.ClipboardId) -> (result :T.VoidResult);
    deleteClipboard     @19 (id :T.ClipboardId) -> (result :T.VoidResult);

    # -- System Tray --

    listTrayIcons       @20 () -> (icons :List(TrayIcon));
    activateTrayIcon    @21 (id :T.TrayIconId) -> (result :T.VoidResult);

    # -- System State --

    getAudioState       @22 () -> (state :AudioState);
    setAudioVolume      @23 (sink :Text, level :UInt8) -> (result :T.VoidResult);
    setAudioMute        @24 (sink :Text, muted :Bool) -> (result :T.VoidResult);
    getNetworkState     @25 () -> (state :NetworkState);
    getPowerState       @26 () -> (state :PowerState);
    setPowerProfile     @27 (profile :PowerProfile) -> (result :T.VoidResult);
    getBluetoothState   @28 () -> (state :BluetoothState);
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

    search              @34 (query :Text, maxResults :UInt32)
                          -> (results :List(SearchResult));

    # -- Session Management --

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

    # -- Portals --

    openFilePicker      @46 (filter :FilePickerFilter, allowMultiple :Bool)
                          -> (files :List(PickedFile));
    saveFilePicker      @47 (suggestedName :Text, filter :FilePickerFilter)
                          -> (path :T.FilePath);
    openColorPicker     @48 (initialColor :T.Color) -> (color :T.Color);
    openUri             @49 (uri :Text) -> (result :T.VoidResult);

    # -- Settings --

    getSetting          @50 (key :Text) -> (value :ShellSettingValue);
    setSetting          @51 (key :Text, value :ShellSettingValue) -> (result :T.VoidResult);
    listSettings        @52 (filter :SettingFilter) -> (settings :List(ShellSetting));

    # -- Events --

    subscribe           @53 (filter :ShellEventFilter)
                          -> (stream :ShellEventStream);

    # -- Query --

    query               @54 (query :ShellQuery) -> (result :ShellQueryResult);

    # -- Paginated Launcher --

    listAppsPaginated   @55 (filter :ApplicationFilter, pagination :T.Pagination)
                          -> (apps :List(ApplicationEntry), total :UInt64);
    findAppsPaginated   @56 (query :Text, pagination :T.Pagination)
                          -> (apps :List(ApplicationEntry), total :UInt64);

    # -- Paginated Notifications --

    listNotificationsPaginated @57 (pagination :T.Pagination)
                          -> (notifications :List(Notification), total :UInt64);

    # -- Paginated Clipboard History --

    getClipboardHistoryPaginated @58 (pagination :T.Pagination)
                          -> (entries :List(ClipboardEntry), total :UInt64);

    # -- Paginated Tray --

    listTrayIconsPaginated @59 (pagination :T.Pagination)
                          -> (icons :List(TrayIcon), total :UInt64);

    # -- Paginated Search --

    searchPaginated @60 (query :Text, pagination :T.Pagination)
                          -> (results :List(SearchResult), total :UInt64);

    # -- Paginated Settings --

    listSettingsPaginated @61 (filter :SettingFilter, pagination :T.Pagination)
                          -> (settings :List(ShellSetting), total :UInt64);

    # ─── Multi-Modal Session ───────────────────────────────────

    # Get current session mode.
    getSessionMode @62 () -> (mode :ShellSessionMode);

    # Set session mode (text, voice, gesture, multiModal, brief).
    setSessionMode @63 (mode :ShellSessionMode) -> (result :T.VoidResult);

    # ─── AI-First Completion ───────────────────────────────────

    # Get AI-powered semantic completions.
    getAiCompletion @64 (request :AiCompletionRequest) -> (results :List(AiCompletionResult));

    # ─── Cross-Device Handoff ──────────────────────────────────

    # Handoff shell state to another device.
    handoff @65 (request :HandoffRequest) -> (result :HandoffResult);

    # ─── Voice Shell ───────────────────────────────────────────

    # Process a spoken command (screenless devices).
    processVoiceCommand @66 (audio :T.DataHandle, language :T.Language) -> (result :VoiceShellResult);

    # Stream intermediate voice results.
    processVoiceCommandStream @67 (audio :T.DataHandle, language :T.Language) -> (stream :VoiceShellResultStream);

    # Subscribe to wake word detection.
    subscribeWakeWord @68 () -> (subscription :WakeWordSubscription);

    # ─── Gesture Navigation ────────────────────────────────────

    # Process a gesture command (AR/VR/watch/car).
    processGesture @69 (event :GestureEvent) -> (result :ShellAction);

    # ─── Brief Mode ────────────────────────────────────────────

    # Execute a command in brief mode (returns description, not stream).
    executeBrief @70 (command :Text) -> (result :BriefResult);

    # ─── Accessibility ─────────────────────────────────────────

    # Get current accessibility mode.
    getAccessibilityMode @71 () -> (mode :AccessibilityMode);

    # Set accessibility mode.
    setAccessibilityMode @72 (mode :AccessibilityMode) -> (result :T.VoidResult);

    # ─── Context Bubbles ───────────────────────────────────────

    # Show a context bubble (hover tooltip, quick action).
    showContextBubble @73 (bubble :ContextBubble) -> T.VoidResult;

    # Dismiss a context bubble.
    dismissContextBubble @74 (bubbleId :Text) -> T.VoidResult;

    # ─── Batch Event Pull ──────────────────────────────────────

    # Pull multiple events at once (reduces IPC overhead).
    pullBatch @75 (stream :ShellEventStream, maxEvents :UInt32) -> (events :List(ShellEvent));
}

# ══════════════════════════════════════════════════════════════════════
# APP REGISTRY
# ══════════════════════════════════════════════════════════════════════

struct ApplicationEntry {
    applicationId @0  :T.AppId;
    name          @1  :Text;
    description   @2  :Text;
    icon          @3  :T.DataHandle;
    category      @4  :ApplicationCategory;
    keywords      @5  :List(Text);
    executable    @6  :Text;
    terminal      @7  :Bool;
    running       @8  :Bool;
    processIds    @9  :List(T.ProcessId);
    windowIds     @10 :List(T.WindowId);
    favorite      @11 :Bool;
    lastLaunched  @12 :T.Timestamp;
    desktopFile   @13 :Text;
    metadata      @14 :List(T.Meta);
}

enum ApplicationCategory {
    utility      @0;
    development  @1;
    office       @2;
    graphics     @3;
    audioVideo   @4;
    network      @5;
    system       @6;
    game         @7;
    other        @8;
    custom       @9;
}

struct ApplicationFilter {
    category @0 :ApplicationCategory;
    running  @1 :T.BoolFilter;
    favorite @2 :T.BoolFilter;
}

# ══════════════════════════════════════════════════════════════════════
# NOTIFICATIONS
# ══════════════════════════════════════════════════════════════════════

struct Notification {
    id             @0  :T.NotificationId;
    applicationName @1  :Text;
    applicationIcon @2  :T.DataHandle;
    summary        @3  :Text;
    body           @4  :Text;
    urgency        @5  :Urgency;
    timestamp      @6  :T.Timestamp;
    category       @7  :Text;
    transient      @8  :Bool;
    imageData      @9  :T.DataHandle;
    actions        @10 :List(NotificationAction);
    dismissable    @11 :Bool;
}

struct NotificationAction {
    key   @0 :Text;
    label @1 :Text;
}

enum Urgency {
    low      @0;
    normal   @1;
    critical @2;
    custom   @3;
}

# ══════════════════════════════════════════════════════════════════════
# CLIPBOARD
# ══════════════════════════════════════════════════════════════════════

struct ClipboardEntry {
    id              @0 :T.ClipboardId;
    contentType     @1 :ClipboardContentType;
    text            @2 :Text;
    imageData       @3 :T.DataHandle;
    richText        @4 :T.DataHandle;
    binary          @5 :T.DataHandle;
    mimeType        @6 :Text;
    uriList         @7 :List(Text);
    sourceApplication @8 :Text;
    timestamp       @9 :T.Timestamp;
    pinned          @10 :Bool;
}

enum ClipboardContentType {
    text     @0;
    uri      @1;
    uriList  @2;
    image    @3;
    richText @4;
    binary   @5;
    empty    @6;
    custom   @7;
}

# ══════════════════════════════════════════════════════════════════════
# SYSTEM TRAY
# ══════════════════════════════════════════════════════════════════════

struct TrayIcon {
    id      @0 :T.TrayIconId;
    title   @1 :Text;
    iconName @2 :Text;
    status  @3 :TrayStatus;
    tooltip @4 :Text;
    menu    @5 :List(TrayMenuItem);
}

enum TrayStatus {
    active         @0;
    passive        @1;
    needsAttention @2;
    custom         @3;
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
# ══════════════════════════════════════════════════════════════════════

struct AudioState {
    sinks   @0 :List(AudioSink);
    sources @1 :List(AudioSource);
}

struct AudioSink {
    name   @0 :Text;
    # Volume level 0-100.
    volume @1 :UInt8;
    muted  @2 :Bool;
    icon   @3 :Text;
}

struct AudioSource {
    name   @0 :Text;
    # Volume level 0-100.
    volume @1 :UInt8;
    muted  @2 :Bool;
    icon   @3 :Text;
}

struct NetworkState {
    connected @0 :Bool;
    type      @1 :NetworkType;
    ssid      @2 :Text;
    # Signal strength 0-100.
    signal    @3 :UInt8;
    ipAddress @4 :Text;
}

enum NetworkType {
    none     @0;
    wifi     @1;
    ethernet @2;
    cellular @3;
    vpn      @4;
    custom   @5;
}

# PowerState imported from power.capnp (canonical source).
# Use import "power.capnp".PowerState directly.

enum PowerProfile {
    performance @0;
    balanced    @1;
    powerSaver  @2;
    custom      @3;
}

struct BluetoothState {
    enabled @0 :Bool;
    devices @1 :List(BluetoothDevice);
}

struct BluetoothDevice {
    address   @0 :T.BluetoothAddress;
    name      @1 :Text;
    connected @2 :Bool;
    type      @3 :BluetoothDeviceType;
    # Battery level 0-100.
    battery   @4 :UInt8;
    paired    @5 :Bool;
}

enum BluetoothDeviceType {
    unknown    @0;
    headphones @1;
    headset    @2;
    keyboard   @3;
    mouse      @4;
    controller @5;
    phone      @6;
    other      @7;
    custom     @8;
}

# ══════════════════════════════════════════════════════════════════════
# SEARCH
# ══════════════════════════════════════════════════════════════════════

struct SearchResult {
    name        @0 :Text;
    description @1 :Text;
    icon        @2 :T.DataHandle;
    kind        @3 :SearchResultKind;
    action      @4 :Text;
    score       @5 :Float32;
}

enum SearchResultKind {
    app     @0;
    file    @1;
    setting @2;
    contact @3;
    action  @4;
    other   @5;
    custom  @6;
}

# ══════════════════════════════════════════════════════════════════════
# PORTALS
# ══════════════════════════════════════════════════════════════════════

struct FilePickerFilter {
    name       @0 :Text;
    extensions @1 :List(Text);
    mimeTypes  @2 :List(Text);
}

struct PickedFile {
    path     @0 :T.FilePath;
    name     @1 :Text;
    mimeType @2 :Text;
    size     @3 :UInt64;
}

# ══════════════════════════════════════════════════════════════════════
# SETTINGS (Shell-local subset — canonical settings are in settings.capnp)
# ══════════════════════════════════════════════════════════════════════

struct ShellSettingValue {
    union {
        text    @0 :Text;
        integer @1 :Int64;
        real    @2 :Float64;
        boolean @3 :Bool;
        custom  @4 :Data;
    }
}

struct ShellSetting {
    key      @0 :Text;
    value    @1 :ShellSettingValue;
    source   @2 :SettingSource;
    metadata @3 :List(T.Meta);
}

enum SettingSource {
    system      @0;
    user        @1;
    application @2;
    systemDefault @3;
    custom      @4;
}

struct SettingFilter {
    source @0 :SettingSource;
    prefix @1 :Text;
}

# ══════════════════════════════════════════════════════════════════════
# EVENTS
# ══════════════════════════════════════════════════════════════════════

interface ShellEventStream {
    pull   @0 () -> (event :ShellEvent);
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

    notificationReceived   @4  :Notification;
    notificationDismissed  @5  :T.NotificationId;
    allNotificationsDismissed @6 :Void;
    doNotDisturbChanged    @7  :Bool;

    clipboardChanged       @8  :ClipboardEntry;
    clipboardCleared       @9  :Void;

    trayIconAdded          @10 :TrayIcon;
    trayIconRemoved        @11 :T.TrayIconId;
    trayIconChanged        @12 :TrayIcon;

    audioStateChanged      @13 :AudioState;
    networkStateChanged    @14 :NetworkState;
    powerStateChanged      @15 :PowerState;
    bluetoothStateChanged  @16 :BluetoothState;

    searchResults          @17 :List(SearchResult);

    sessionLocking         @18 :Void;
    sessionLocked          @19 :Void;
    sessionUnlocked        @20 :Void;
    shutdownImminent       @21 :T.Duration;

    settingChanged         @22 :ShellSetting;

    custom                 @23 :UnknownShellEvent;
    }
}

struct UnknownShellEvent {
    typeId  @0 :UInt64;
    payload @1 :Data;
}

# ══════════════════════════════════════════════════════════════════════
# QUERY
# ══════════════════════════════════════════════════════════════════════

struct ShellQuery {
    union {
        appById           @0 :T.AppId;
        appsByCategory    @1 :ApplicationCategory;
        runningApps       @2 :Void;
        favoriteApps      @3 :Void;
        shellCapabilities @4 :Void;
        custom            @5 :CustomQuery;
    }
}

struct CustomQuery {
    name       @0 :Text;
    parameters @1 :List(T.Meta);
}

struct ShellQueryResult {
    union {
        app          @0 :ApplicationEntry;
        apps         @1 :List(ApplicationEntry);
        capabilities @2 :List(ShellCapability);
        custom       @3 :List(T.Meta);
        notFound     @4 :Void;
    }
}

# ══════════════════════════════════════════════════════════════════════
# CAPABILITIES
# ══════════════════════════════════════════════════════════════════════

enum ShellCapability {
    manageLauncher       @0;
    manageNotifications  @1;
    manageClipboard      @2;
    manageTray           @3;
    readAudioState       @4;
    controlAudio         @5;
    readNetworkState     @6;
    readPowerState       @7;
    controlPowerProfile  @8;
    controlBrightness    @9;
    controlNightLight   @10;
    searchUniversal     @11;
    controlSession      @12;
    controlBluetooth    @13;
    usePortals          @14;
    manageSettings      @15;
    voiceShell          @16;
    gestureNavigation   @17;
    aiCompletion        @18;
    crossDeviceHandoff  @19;
    contextBubbles      @20;
    accessibility       @21;
    custom              @22;
}

# ══════════════════════════════════════════════════════════════
# MULTI-MODAL SESSION
# ══════════════════════════════════════════════════════════════

enum ShellSessionMode {
    text         @0;  # traditional keyboard/terminal
    voice        @1;  # voice-only, screenless
    gesture      @2;  # gesture-only, AR/VR/watch
    multiModal   @3;  # combined voice+text+gesture
    brief        @4;  # one-shot, description-only
    custom       @5;
}

# ══════════════════════════════════════════════════════════════
# AI-FIRST COMPLETION
# ══════════════════════════════════════════════════════════════

struct AiCompletionRequest {
    partialInput @0 :Text;
    context      @1 :AiCompletionContext;
    maxResults   @2 :UInt32;
}

struct AiCompletionContext {
    recentCommands @0 :List(Text);
    currentApp     @1 :T.AppId;
    timeOfDay      @2 :T.Timestamp;
    location       @3 :Text;
    mode           @4 :ShellSessionMode;
}

struct AiCompletionResult {
    suggestion    @0 :Text;
    description   @1 :Text;
    confidence    @2 :Float32;
    action        @3 :ShellAction;
    source        @4 :AiCompletionSource;
}

enum AiCompletionSource {
    history       @0;
    semantic      @1;
    contextual    @2;
    predictive    @3;
    custom        @4;
}

struct ShellAction {
    union {
        appLaunch    @0 :T.AppId;
        shellCommand @1 :Text;
        uriOpen      @2 :T.Uri;
        settingChange @3 :ShellSetting;
        custom       @4 :Data;
    }
}

# ══════════════════════════════════════════════════════════════
# CROSS-DEVICE HANDOFF
# ══════════════════════════════════════════════════════════════

struct HandoffRequest {
    sourceDevice  @0 :Text;
    targetDevice  @1 :Text;
    sessionId     @2 :T.SessionId;
    transferData  @3 :HandoffData;
}

struct HandoffData {
    runningApps   @0 :List(T.AppId);
    clipboard     @1 :ClipboardEntry;
    searchContext @2 :Text;
    shellState    @3 :List(ShellSetting);
}

struct HandoffResult {
    accepted    @0 :Bool;
    reason      @1 :Text;
    migratedAt  @2 :T.Timestamp;
}

# ══════════════════════════════════════════════════════════════
# VOICE SHELL
# ══════════════════════════════════════════════════════════════

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

interface WakeWordSubscription {
    pull @0 () -> (detected :Bool, confidence :Float32);
    cancel @1 () -> T.VoidResult;
}

# ══════════════════════════════════════════════════════════════
# GESTURE NAVIGATION
# ══════════════════════════════════════════════════════════════

enum GestureCommand {
    swipeLeft      @0;
    swipeRight     @1;
    swipeUp        @2;
    swipeDown      @3;
    pinchIn        @4;
    pinchOut       @5;
    tap            @6;
    doubleTap      @7;
    longPress      @8;
    rotate         @9;
    point          @10;
    grab           @11;
    custom         @12;
}

struct GestureEvent {
    command     @0 :GestureCommand;
    position    @1 :T.Vec2;
    velocity    @2 :T.Vec2;
    timestamp   @3 :T.Timestamp;
    source      @4 :GestureSource;
}

enum GestureSource {
    touchscreen @0;
    trackpad    @1;
    handTracking @2;
    eyeTracking @3;
    controller  @4;
    custom      @5;
}

# ══════════════════════════════════════════════════════════════
# BRIEF MODE
# ══════════════════════════════════════════════════════════════

struct BriefResult {
    summary     @0 :Text;
    icon        @1 :T.DataHandle;
    action      @2 :ShellAction;
    confidence  @3 :Float32;
}

# ══════════════════════════════════════════════════════════════
# ACCESSIBILITY
# ══════════════════════════════════════════════════════════════

struct AccessibilityMode {
    screenReader     @0 :Bool;
    highContrast     @1 :Bool;
    largeText        @2 :Bool;
    magnification    @3 :Float32;
    captions         @4 :Bool;
    reducedMotion    @5 :Bool;
    stickyKeys       @6 :Bool;
    custom           @7 :Data;
}

# ══════════════════════════════════════════════════════════════
# CONTEXT BUBBLES
# ══════════════════════════════════════════════════════════════

struct ContextBubble {
    id          @0 :Text;
    anchorSurface @1 :T.SurfaceId;
    position    @2 :T.Vec2i;
    content     @3 :BubbleContent;
    lifetime    @4 :T.Duration;
    interactive @5 :Bool;
}

struct BubbleContent {
    union {
        text        @0 :Text;
        richText    @1 :T.DataHandle;
        image       @2 :T.DataHandle;
        appPreview  @3 :T.AppId;
        custom      @4 :Data;
    }
}

# ── Shell Plugin System (audit-8 What's Still Missing) ──
struct ShellPluginInfo {
    id @0 :Text;
    name @1 :Text;
    version @2 :T.Version;
    capabilities @3 :List(Text);
    enabled @4 :Bool;
}

# ── Shell Analytics / Usage Tracking (audit-8 What's Still Missing) ──
struct ShellAnalytics {
    appsLaunched @0 :UInt64;
    commandsExecuted @1 :UInt64;
    searchQueries @2 :UInt64;
    sessionDuration @3 :T.Duration;
    topApps @4 :List(T.AppId);
}

# ── Shell Theming Pipeline (audit-8 What's Still Missing) ──
struct ShellThemingPipeline {
    themeSource @0 :ThemeSource;
    dynamicColor @1 :Bool;
    customTheme @2 :Text;
}

enum ThemeSource {
    system @0;
    wallpaper @1;
    manual @2;
    custom @3;
}

# ── Multi-User Shell (audit-8 What's Still Missing) ──
struct MultiUserConfig {
    activeUser @0 :T.UserId;
    users @1 :List(UserProfile);
    switchAllowed @2 :Bool;
}

struct UserProfile {
    userId @0 :T.UserId;
    name @1 :Text;
    icon @2 :T.DataHandle;
    isCurrent @3 :Bool;
}

# ── AR Spatial Shell (audit-9 What's Still Missing) ──
struct ArSpatialShell {
    shellId @0 :Text;
    position @1 :T.Vec3;
    rotation @2 :T.Vec4;
    anchorType @3 :ArAnchorType;
    elements @4 :List(ArShellElement);
}

enum ArAnchorType {
    world @0;
    plane @1;
    object @2;
    face @3;
    other @4;
    custom @5;
}

struct ArShellElement {
    elementId @0 :Text;
    type @1 :ArElementType;
    position @2 :T.Vec3;
    scale @3 :T.Vec3;
    visible @4 :Bool;
}

enum ArElementType {
    panel @0;
    button @1;
    text @2;
    image @3;
    model @4;
    other @5;
    custom @6;
}

# ── Car Split-Screen Zones (audit-9 What's Still Missing) ──
struct CarSplitScreenConfig {
    zones @0 :List(CarScreenZone);
    driverZone @1 :Text;
    passengerZones @2 :List(Text);
}

struct CarScreenZone {
    zoneId @0 :Text;
    role @1 :CarZoneRole;
    bounds @2 :T.Rect;
    contentTypes @3 :List(CarContentType);
    maxApps @4 :UInt8;
}

enum CarZoneRole {
    driver @0;
    frontPassenger @1;
    rearLeft @2;
    rearRight @3;
    rearCenter @4;
    other @5;
    custom @6;
}

enum CarContentType {
    navigation @0;
    media @1;
    phone @2;
    climate @3;
    vehicle @4;
    other @5;
    custom @6;
}

# ── Shell Session Persistence (audit-9 What's Still Missing) ──
struct ShellSessionState {
    sessionId @0 :T.SessionId;
    savedAt @1 :T.Timestamp;
    runningApps @2 :List(T.AppId);
    clipboard @3 :ClipboardEntry;
    settings @4 :List(ShellSetting);
    openWindows @5 :List(T.WindowId);
    workspaces @6 :List(T.WorkspaceId);
}

# ── Shell Notification Grouping (audit-9 What's Still Missing) ──
struct NotificationGroup {
    groupId @0 :Text;
    notifications @1 :List(Notification);
    summary @2 :Text;
    count @3 :UInt32;
    lastUpdated @4 :T.Timestamp;
    conversationThread @5 :Bool;
}

# ── Shell Command History with Analytics (audit-9 What's Still Missing) ──
struct CommandHistoryEntry {
    command @0 :Text;
    timestamp @1 :T.Timestamp;
    frequency @2 :UInt64;
    lastUsed @3 :T.Timestamp;
    frecency @4 :Float32;
}

struct CommandHistoryAnalytics {
    totalCommands @0 :UInt64;
    uniqueCommands @1 :UInt64;
    topCommands @2 :List(CommandHistoryEntry);
    sessionDuration @3 :T.Duration;
}

# ── Shell Accessibility Tree Exposure (audit-9 What's Still Missing) ──
struct ShellAccessibilityTree {
    tree @0 :ShellAccessibilityNode;
    generatedAt @1 :T.Timestamp;
}

struct ShellAccessibilityNode {
    id @0 :Text;
    role @1 :Text;
    name @2 :Text;
    description @3 :Text;
    children @4 :List(ShellAccessibilityNode);
}

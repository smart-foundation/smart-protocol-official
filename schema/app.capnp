@0xa1b2c3d4e5f6001b;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# App - application lifecycle and information
#
# Manages running apps: query, open resources, focus, minimize, close,
# and subscribe to lifecycle events. This schema owns lifecycle; package
# metadata lives in package.capnp. The two schemas reference each other
# via T.AppId and T.PackageId.
#
# All file/resource references use typed unions, not raw filesystem paths.
# Exit status uses T.ExitStatus, not raw integers.
#
# Audit-7 enhancements (zero-cost, info-density):
#   - AppSuspendReason/AppResumeReason: typed lifecycle triggers
#   - AppInstance: multi-instance tracking
#   - AppCommunication: cross-app messaging
#   - AppResourceLimits: resource constraints per app
#   - AppPermission: per-app permission listing
#   - RunningAppInfo enriched with lifecycle details
# ═══════════════════════════════════════════════════════════════════════

interface AppService {
    # List running apps with optional filter.
    getRunningApps @0 (filter :AppFilter, pagination :T.Pagination)
                   -> (apps :List(RunningAppInfo), totalCount :UInt32);

    # Open a file/resource in an app.
    openFile @1 (resource :FileRef, appId :T.AppId) -> T.VoidResult;

    # Open a URL/deep-link.
    openUrl @2 (url :T.Uri) -> T.VoidResult;

    # Open a file with a specific app.
    openWith @3 (resource :FileRef, appId :T.AppId) -> T.VoidResult;

    # Set focus to an app.
    setActive @4 (appId :T.AppId) -> T.VoidResult;

    # Minimize an app.
    minimizeApp @5 (appId :T.AppId) -> T.VoidResult;

    # Close an app.
    closeApp @6 (appId :T.AppId) -> T.VoidResult;

    # Get detailed info for an app.
    getAppInfo @7 (appId :T.AppId) -> (info :AppDetailedInfo);

    # Get lifecycle state of an app.
    getAppState @8 (appId :T.AppId) -> (state :AppLifecycle);

    # Subscribe to app lifecycle events.
    subscribe @9 () -> (subscription :AppSubscription);
    pull @10 (subscription :AppSubscription) -> (events :List(AppEvent));
    cancel @11 (subscription :AppSubscription) -> T.VoidResult;

    # Get resource usage for a running app.
    getResourceUsage @12 (appId :T.AppId) -> (usage :T.ResourceUsage);

    # Audit-7: send a message to another app (cross-app communication).
    sendMessage @13 (appId :T.AppId, message :AppMessage) -> T.VoidResult;

    # Audit-7: list instances of a multi-instance app.
    listInstances @14 (appId :T.AppId, pagination :T.Pagination)
                  -> (instances :List(AppInstance), totalCount :UInt32);

    # Audit-7: set resource limits for an app.
    setResourceLimits @15 (appId :T.AppId, limits :AppResourceLimits) -> T.VoidResult;

    # Audit-7: get resource limits for an app.
    getResourceLimits @16 (appId :T.AppId) -> (limits :AppResourceLimits);

    # Audit-7: list permissions declared by an app.
    listPermissions @17 (appId :T.AppId, pagination :T.Pagination)
                    -> (permissions :List(AppPermission), totalCount :UInt32);

    # Audit-8: check for app updates (false positive: app_update.capnp belongs here).
    checkForUpdate @18 (appId :T.AppId) -> (notification :AppUpdateNotification);

    # Audit-8: delegate a permission from one app to another (e.g., app A grants camera access to app B).
    delegatePermission @19 (fromAppId :T.AppId, toAppId :T.AppId, permission :Text) -> T.VoidResult;

    # Audit-8: get app health status (periodic health checks beyond crash events).
    getHealth @20 (appId :T.AppId) -> (health :AppHealth);

    # Audit-8: restart an app (full restart, not hot-reload).
    restartApp @21 (appId :T.AppId) -> T.VoidResult;

    # Audit-9: subscribe to app health change events.
    subscribeHealth @22 () -> (subscription :HealthSubscription);

    # Audit-9: get permission delegation history for an app.
    getPermissionDelegations @23 (appId :T.AppId, pagination :T.Pagination)
                                 -> (delegations :List(PermissionDelegationEntry), totalCount :UInt32);

    # Audit-9: configure crash recovery policy for an app.
    setCrashRecoveryPolicy @24 (appId :T.AppId, policy :CrashRecoveryPolicy) -> T.VoidResult;
    getCrashRecoveryPolicy @25 (appId :T.AppId) -> (policy :CrashRecoveryPolicy);

    # Audit-10: check whether a delegation from fromAppId to toAppId is authorized.
    checkDelegationAuth @26 (fromAppId :T.AppId, toAppId :T.AppId, permission :Text)
                        -> (authorized :Bool, reason :Text);

    # Audit-10: list active delegation authorizations for an app.
    listDelegationAuthorizations @27 (appId :T.AppId, pagination :T.Pagination)
                                  -> (authorizations :List(PermissionDelegationAuthorization), totalCount :UInt32);
}

# Audit-9: subscription for app health change events.
interface HealthSubscription {
    pull @0 () -> (events :List(AppHealthEvent));
    cancel @1 () -> T.VoidResult;
}

# ── Resource References ───────────────────────────────────────────────

struct FileRef {
    union {
        path @0 :Text;
        uri @1 :Text;
        fileId @2 :T.FileId;
        custom @3 :Data;
    }
}

# ── Running App ───────────────────────────────────────────────────────

struct RunningAppInfo {
    appId @0 :T.AppId;
    windowId @1 :T.WindowId;
    name @2 :Text;
    pid @3 :T.ProcessId;
    resourceUsage @4 :T.ResourceUsage;
    # Audit-7 additions:
    lifecycle @5 :AppLifecycle;
    # Which instance this is (for multi-instance apps).
    instanceId @6 :UInt32;
    # When the app was launched.
    launchedAt @7 :T.Timestamp;
    # Whether the app is in the foreground.
    foreground @8 :Bool;
    # Current focus state.
    focused @9 :Bool;
}

# ── Detailed App Info ─────────────────────────────────────────────────

struct AppDetailedInfo {
    appId @0 :T.AppId;
    packageId @1 :T.PackageId;
    name @2 :Text;
    version @3 :T.Version;
    description @4 :Text;
    icon @5 :AppIcon;
    categories @6 :List(AppCategory);
    source @7 :AppSource;
    installed @8 :Bool;
    running @9 :Bool;
    # Audit-7 additions:
    # Launch mode (single-instance, multi-instance, single-task).
    launchMode @10 :AppLaunchMode;
    # Whether the app supports being suspended.
    supportsSuspend @11 :Bool;
    # Whether the app supports receiving messages.
    supportsMessaging @12 :Bool;
    # Maximum number of instances (0 = unlimited).
    maxInstances @13 :UInt32;
    # SDK version the app was built against.
    sdkVersion @14 :T.Version;
    # Audit-9: crash recovery policy for this app.
    crashRecoveryPolicy @15 :CrashRecoveryPolicy;
}

struct AppIcon {
    data @0 :Data;
    mimeType @1 :Text;
    width @2 :UInt32;
    height @3 :UInt32;
}

enum AppSource {
    builtin @0;
    store @1;
    sideloaded @2;
    web @3;
    unknown @4;
    custom @5;
}

enum AppCategory {
    system @0;
    productivity @1;
    games @2;
    media @3;
    development @4;
    utilities @5;
    accessibility @6;
    communication @7;
    education @8;
    health @9;
    finance @10;
    social @11;
    custom @12;
}

# ── App Lifecycle ─────────────────────────────────────────────────────

enum AppLifecycle {
    stopped @0;
    starting @1;
    running @2;
    paused @3;
    stopping @4;
    crashed @5;
    # Audit-7 additions:
    suspended @6;       # App is suspended (resource-constrained)
    background @7;      # App is running but not in foreground
    custom @8;
}

# Audit-7: launch mode for multi-instance behavior.
enum AppLaunchMode {
    singleInstance @0;   # Only one instance allowed
    multiInstance @1;    # Multiple instances allowed
    singleTask @2;       # One task, reuse existing instance
    singleTop @3;        # Reuse top instance if same task
    custom @4;
}

# Audit-7: suspend reason.
enum AppSuspendReason {
    userRequest @0;       # User explicitly suspended the app
    memoryPressure @1;    # System needs memory
    idle @2;              # App idle for too long
    policy @3;            # Policy-based suspension
    background @4;        # Moved to background
    custom @5;
}

# Audit-7: resume reason.
enum AppResumeReason {
    userRequest @0;       # User explicitly resumed
    notification @1;      # Incoming notification
    timer @2;             # Timer fired
    pushMessage @3;       # Push message received
    backgroundTask @4;    # Background task completion
    custom @5;
}

# Audit-8: typed message categories for cross-app communication.
# Replaces bare Text in AppMessage.type with a structured enum.
enum AppMessageType {
    query @0;             # Request information from another app
    command @1;           # Request an action from another app
    event @2;             # Notify about a state change
    share @3;             # Share data/content with another app
    deeplink @4;          # Trigger a deep-link in another app
    custom @5;
}

# Audit-8: app crash recovery options.
enum CrashRecoveryPolicy {
    none @0;              # No automatic recovery
    restart @1;           # Restart the app automatically
    restartWithBackoff @2; # Restart with exponential backoff
    notifyUser @3;        # Notify user and wait for action
    custom @4;
}

# Audit-8: app update notification.
struct AppUpdateNotification {
    appId @0 :T.AppId;
    currentVersion @1 :T.Version;
    availableVersion @2 :T.Version;
    # Whether the update is critical (security or stability).
    critical @3 :Bool;
    # Human-readable changelog summary.
    changelog @4 :Text;
    # When the update became available.
    availableAt @5 :T.Timestamp;
}

# Audit-8: app health status for monitoring beyond crash events.
struct AppHealth {
    # Whether the app is responsive.
    responsive @0 :Bool;
    # Last health check timestamp.
    lastCheck @1 :T.Timestamp;
    # Error rate (0.0-1.0) over the monitoring window.
    errorRate @2 :Float32;
    # Memory usage trend (increasing, stable, decreasing).
    memoryTrend @3 :MemoryTrend;
    # Whether the app is healthy overall.
    healthy @4 :Bool;
    # Optional health message.
    message @5 :Text;
}

# Audit-8: memory usage trend for health monitoring.
enum MemoryTrend {
    stable @0;
    increasing @1;
    decreasing @2;
    spike @3;
    custom @4;
}

# ── App Instance (multi-instance) ────────────────────────────────────

# Audit-7 addition: tracks individual instances of multi-instance apps.
struct AppInstance {
    appId @0 :T.AppId;
    instanceId @1 :UInt32;
    pid @2 :T.ProcessId;
    windowId @3 :T.WindowId;
    # When this instance was launched.
    launchedAt @4 :T.Timestamp;
    # Current lifecycle state.
    lifecycle @5 :AppLifecycle;
    # Resource usage for this instance.
    resourceUsage @6 :T.ResourceUsage;
    # Human-readable label (e.g. "Window 1", "Document 2").
    label @7 :Text;
}

# ── Cross-App Communication ──────────────────────────────────────────

# Audit-7 addition: typed message for cross-app communication.
struct AppMessage {
    # Audit-10: typed message type (typed union replacing bare Text).
    typedType @4 :AppMessageType;
    # Legacy message type (for backward compatibility with consumers expecting Text).
    type @0 :Text;
    # Message payload.
    payload @1 :AppMessagePayload;
    # Whether a response is expected.
    expectResponse @2 :Bool;
    # Timeout for response (zero = fire-and-forget).
    responseTimeout @3 :T.Duration;
}

struct AppMessagePayload {
    union {
        text @0 :Text;
        data @1 :Data;
        json @2 :Text;
        custom @3 :Data;
    }
}

# ── Resource Limits ──────────────────────────────────────────────────

# Audit-7 addition: resource constraints per app. Allows setting and
# querying limits on CPU, memory, network, and storage usage.
struct AppResourceLimits {
    # Maximum memory bytes (0 = unlimited).
    maxMemoryBytes @0 :UInt64;
    # Maximum CPU time per second (0 = unlimited).
    maxCpuTimeMs @1 :UInt32;
    # Maximum network bytes per second (0 = unlimited).
    maxNetworkBytesPerSec @2 :UInt64;
    # Maximum storage bytes (0 = unlimited).
    maxStorageBytes @3 :UInt64;
    # Maximum number of open file descriptors (0 = unlimited).
    maxOpenFiles @4 :UInt32;
    # Maximum number of child processes (0 = unlimited).
    maxChildProcesses @5 :UInt32;
    # Whether the app can run in the background.
    allowBackground @6 :Bool;
    # Whether the app can access the network.
    allowNetwork @7 :Bool;
}

# ── App Permission ────────────────────────────────────────────────────

# Audit-7 addition: per-app permission listing. Apps declare what
# permissions they need; the system grants or denies them.
struct AppPermission {
    # Permission identifier (e.g. "access.camera", "access.microphone").
    permission @0 :Text;
    # Human-readable name.
    name @1 :Text;
    # Description of why the permission is needed.
    description @2 :Text;
    # Whether the permission is currently granted.
    granted @3 :Bool;
    # Whether the permission is required (app won't work without it).
    required @4 :Bool;
    # Whether the user can revoke this permission.
    revocable @5 :Bool;
}

# ── Filter ────────────────────────────────────────────────────────────

struct AppFilter {
    name @0 :Text;
    category @1 :AppCategory;
    installed @2 :T.BoolFilter;
    running @3 :T.BoolFilter;
    minMemoryBytes @4 :UInt64;
    maxMemoryBytes @5 :UInt64;
    # Audit-7 additions:
    source @6 :AppSource;
    foreground @7 :T.BoolFilter;
    lifecycle @8 :AppLifecycle;
}

# ── Events ────────────────────────────────────────────────────────────

interface AppSubscription {
    pull @0 () -> (events :List(AppEvent));
    cancel @1 () -> T.VoidResult;
}

struct AppEvent {
    union {
        launched @0 :AppLaunchedEvent;
        closed @1 :AppClosedEvent;
        stateChanged @2 :AppStateChangedEvent;
        crashed @3 :AppCrashEvent;
        # Audit-7 additions:
        suspended @4 :AppSuspendEvent;
        resumed @5 :AppResumeEvent;
        messageReceived @6 :AppMessageEvent;
        instanceCreated @7 :AppInstanceEvent;
        instanceDestroyed @8 :AppInstanceEvent;
        # Audit-8 additions:
        updateAvailable @9 :AppUpdateNotification;
        healthChanged @10 :AppHealthEvent;
        permissionDelegated @11 :AppPermissionDelegatedEvent;
        custom @12 :Data;
    }
}

struct AppLaunchedEvent {
    appId @0 :T.AppId;
    pid @1 :T.ProcessId;
    timestamp @2 :T.Timestamp;
    # Audit-7: instance ID for multi-instance apps.
    instanceId @3 :UInt32;
}

struct AppClosedEvent {
    appId @0 :T.AppId;
    exitStatus @1 :T.ExitStatus;
    timestamp @2 :T.Timestamp;
    instanceId @3 :UInt32;
}

struct AppStateChangedEvent {
    appId @0 :T.AppId;
    previous @1 :AppLifecycle;
    current @2 :AppLifecycle;
    timestamp @3 :T.Timestamp;
}

struct AppCrashEvent {
    appId @0 :T.AppId;
    reason @1 :Text;
    signal @2 :T.SignalKind;
    timestamp @3 :T.Timestamp;
}

# Audit-7 addition: suspend event.
struct AppSuspendEvent {
    appId @0 :T.AppId;
    reason @1 :AppSuspendReason;
    timestamp @2 :T.Timestamp;
}

# Audit-7 addition: resume event.
struct AppResumeEvent {
    appId @0 :T.AppId;
    reason @1 :AppResumeReason;
    timestamp @2 :T.Timestamp;
}

# Audit-7 addition: message received event.
struct AppMessageEvent {
    fromAppId @0 :T.AppId;
    toAppId @1 :T.AppId;
    message @2 :AppMessage;
    timestamp @3 :T.Timestamp;
}

# Audit-7 addition: instance created/destroyed event.
struct AppInstanceEvent {
    appId @0 :T.AppId;
    instanceId @1 :UInt32;
    timestamp @2 :T.Timestamp;
}

# Audit-8 addition: health status changed event.
struct AppHealthEvent {
    appId @0 :T.AppId;
    previous @1 :AppHealth;
    current @2 :AppHealth;
    timestamp @3 :T.Timestamp;
}

# Audit-8 addition: permission delegated event.
struct AppPermissionDelegatedEvent {
    fromAppId @0 :T.AppId;
    toAppId @1 :T.AppId;
    permission @2 :Text;
    timestamp @3 :T.Timestamp;
}

# Audit-9: permission delegation audit trail entry.
struct PermissionDelegationEntry {
    id @0 :Text;
    fromAppId @1 :T.AppId;
    toAppId @2 :T.AppId;
    permission @3 :Text;
    timestamp @4 :T.Timestamp;
    granted @5 :Bool;
}

# Audit-10: permission delegation authorization record.
struct PermissionDelegationAuthorization {
    id @0 :Text;
    fromAppId @1 :T.AppId;
    toAppId @2 :T.AppId;
    permission @3 :Text;
    # When this authorization was created.
    createdAt @4 :T.Timestamp;
    # When this authorization expires (null = no expiry).
    expiresAt @5 :T.Timestamp;
    # Maximum number of times this delegation can be used (0 = unlimited).
    maxUses @6 :UInt32;
    # Number of times this delegation has been used so far.
    usedCount @7 :UInt32;
    # Whether this authorization is currently active.
    active @8 :Bool;
}

@0xa1b2c3d4e5f6001b;

# ═══════════════════════════════════════════════════════════════════════
# App - application lifecycle and information.
#
# WHAT THIS IS
#   The runtime view of applications: what is running, what state it is in,
#   what it is using, and how to talk to it. This schema owns LIFECYCLE;
#   catalog metadata lives in appindex.capnp and bundle self-description
#   lives in manifest.capnp.
#
# THE PARALLEL AUTHORITY MODEL IS DELETED
#   This file used to run a second authority system beside capability.capnp:
#   `AppPermission.permission :Text` — free strings like "access.camera" —
#   plus `delegatePermission`, `checkDelegationAuth`, `listDelegationAuthorizations`
#   and `getPermissionDelegations`. That is five methods and four structs
#   implementing permission strings, app-to-app delegation and an
#   authorisation record, all of which capability.capnp already defines with
#   attenuation, revocation and audit — and the string model is the only one
#   of the two that is NOT revocable. Two authority systems that must agree
#   forever, exactly at the layer where disagreeing is catastrophic.
#   Deleted. What an app DECLARES it needs is read from its Manifest as
#   `CapabilityRequirement { target, operations }` — the model manifest.capnp
#   already got right — and whether it may use it is a capability decision.
#
# WHAT ELSE WAS DELETED
#   - `openFile` — the same signature as `openWith`, so a client could not
#     tell which one the backend honoured. `openWith` stays.
#   - `checkForUpdate` and `AppUpdateNotification`: package.capnp already
#     runs the whole update lifecycle with a richer model, and app updates
#     had two homes with different shapes.
#   - The health surface (`getHealth`, `subscribeHealth`, `AppHealth`,
#     `MemoryTrend`, `AppHealthEvent`): resource monitoring is
#     `T.ResourceUsage` plus a diagnostics service. Health-as-bool-plus-prose
#     invited every backend to define "healthy" differently.
#   - The crash-recovery surface (`setCrashRecoveryPolicy`,
#     `getCrashRecoveryPolicy`, `CrashRecoveryPolicy`): a THIRD restart
#     policy beside init.capnp's and types.capnp's, which already contradict
#     each other. App restart policy belongs with the service-lifecycle
#     owner, not with the running-app listing. Recorded in the batch report.
#   - `AppResourceLimits`: replaced by `T.Quota`, the protocol's one quota
#     primitive. Its `allowBackground`/`allowNetwork` booleans were authority
#     flags, which is a capability decision and never a struct field.
#   - `AppLaunchMode` (singleInstance/multiInstance/singleTask/singleTop):
#     Android Activity launch modes. `singleTask` and `singleTop` are
#     `FLAG_ACTIVITY_*` names, and a non-Android shell has no "task" or "top
#     instance" to emulate. `maxInstances` covers the real question.
#   - The legacy `AppMessage.type :Text` beside `typedType :AppMessageType`:
#     the drift already happened once in this struct, and nothing external
#     consumes the legacy field.
#
# WHAT WAS FIXED
#   - `getAppInfo`, `getAppState` and the app listing return results with
#     not-found and error. A queried id for an uninstalled app used to arrive
#     as a zero-valued struct — name "", lifecycle `stopped` — indistinguishable
#     from a stopped installed app.
#   - `AppIcon` and `FileRef` now come from appindex.capnp: one definition,
#     one `T.DataHandle` icon, instead of identical-and-drifted twins.
#   - `AppMessagePayload.data` is a buffer reference: a share-sheet payload is
#     document-sized.
#   - Cross-app messaging has a REPLY PATH. `AppMessage.correlationId` is
#     caller-chosen and echoed on the response, which arrives as a
#     `messageReceived` event. `expectResponse`/`responseTimeout` existed with
#     no way to receive the answer.
#   - `instanceId` is a `AppInstanceRef` union, not a `UInt32` with a
#     sentinel: instance 0 and "not an instance app" were the same number.
#
# WHAT IS DELIBERATELY OPAQUE
#   App identity (`T.AppId`), process identity (`T.ProcessId`), and the AppId
#   issuance rule. THE ISSUANCE RULE, stated so no backend guesses: app
#   identity is allocated by the appindex at install time and SURVIVES
#   upgrade and reinstall of the same manifest; a different manifest is a
#   different app. appindex, app and package now assume one owner of
#   identity instead of one each.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using AI = import "appindex.capnp";
using M = import "manifest.capnp";

interface AppService {
    # List running apps with optional filter.
    getRunningApps @0 (filter :RunningAppFilter, pagination :T.Pagination)
                   -> (apps :List(RunningAppInfo), total :UInt64);

    # Open a file/resource in a specific app.
    openWith @1 (resource :AI.FileRef, appId :T.AppId) -> T.VoidResult;

    # Open a URL/deep-link.
    openUrl @2 (url :T.Uri) -> T.VoidResult;

    # Set focus to an app.
    setActive @3 (appId :T.AppId) -> T.VoidResult;

    # Minimize an app.
    minimizeApp @4 (appId :T.AppId) -> T.VoidResult;

    # Close an app.
    closeApp @5 (appId :T.AppId) -> T.VoidResult;

    # Get the catalog record plus runtime extras for an app.
    getAppInfo @6 (appId :T.AppId) -> (result :AppDetailsResult);

    # Get lifecycle state of an app.
    getAppState @7 (appId :T.AppId) -> (result :LifecycleResult);

    # Subscribe to app lifecycle events.
    subscribe @8 () -> (subscription :AppSubscription);
    pull @9 (maxEvents :UInt32) -> (events :List(AppEvent));
    cancel @10 (subscription :AppSubscription) -> T.VoidResult;

    # Get resource usage for a running app.
    getResourceUsage @11 (appId :T.AppId) -> (usage :T.ResourceUsage);

    # Send a message to another app (cross-app communication).
    sendMessage @12 (appId :T.AppId, message :AppMessage) -> T.VoidResult;

    # List instances of a multi-instance app.
    listInstances @13 (appId :T.AppId, pagination :T.Pagination)
                  -> (instances :List(AppInstance), total :UInt64);

    # Resource limits for an app. T.Quota is the protocol's one quota
    # primitive, and declaring "this app gets 512MB max" is a real external
    # contract between the app and the resource provider.
    setResourceLimits @14 (appId :T.AppId, limits :T.Quota) -> T.VoidResult;
    getResourceLimits @15 (appId :T.AppId) -> (limits :T.Quota);

    # The capabilities this app declares, read from its Manifest. Declaring
    # is not granting: whether it may use one is a capability decision.
    listCapabilities @16 (appId :T.AppId, pagination :T.Pagination)
                     -> (requirements :List(M.CapabilityRequirement), total :UInt64);

    # Restart an app (full restart, not hot-reload).
    restartApp @17 (appId :T.AppId) -> T.VoidResult;
}

# ── Results ───────────────────────────────────────────────────

struct AppDetailsResult {
    union {
        info    @0 :AppDetailedInfo;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct LifecycleResult {
    union {
        lifecycle @0 :AppLifecycle;
        error     @1 :T.Error;
        unknown   @2 :Void;
    }
}

# ── Running App ───────────────────────────────────────────────

struct RunningAppInfo {
    appId @0 :T.AppId;
    windowId @1 :T.WindowId;
    # The catalog record, so name/icon/version have one home.
    info @2 :AI.AppInfo;
    # Opaque process reference. A window system with no per-window process
    # leaves it unset; there is no sentinel number to invent.
    pid @3 :T.ProcessId;
    resourceUsage @4 :T.ResourceUsage;
    lifecycle @5 :AppLifecycle;
    instance @6 :AI.AppInstanceRef;
    # When the app was launched.
    launchedAt @7 :T.Timestamp;
    # Whether the app is in the foreground.
    foreground @8 :Bool;
    # Current focus state.
    focused @9 :Bool;
}

# ── Detailed App Info ─────────────────────────────────────────
# The catalog record plus runtime extras — "AppDetailedInfo IS AppInfo" was
# the audit's shape and it is now literal.

struct AppDetailedInfo {
    # Everything descriptive comes from the index.
    info @0 :AI.AppInfo;
    running @1 :Bool;
    lifecycle @2 :AppLifecycle;
    pid @3 :T.ProcessId;
    resourceUsage @4 :T.ResourceUsage;
    # Whether the app supports being suspended.
    supportsSuspend @5 :Bool;
    # Whether the app supports receiving messages.
    supportsMessaging @6 :Bool;
    # Maximum number of instances (0 = unlimited). This, not an activity
    # launch mode, is the real declaration.
    maxInstances @7 :UInt32;
    # SDK version the app was built against.
    sdkVersion @8 :T.Version;
}

# ── App Lifecycle ─────────────────────────────────────────────
# RUNTIME state. Install state is appindex.capnp's `AppState`.

enum AppLifecycle {
    # Absent means the backend decides; it must never mean a
    # specific paradigm value.
    any @0;
    stopped @1;
    starting @2;
    running @3;
    paused @4;
    stopping @5;
    crashed @6;
    suspended @7;
    background @8;
    custom @9;
}

# ── App Instance (multi-instance) ────────────────────────────

struct AppInstance {
    appId @0 :T.AppId;
    # Server-issued by this service; never 0, so it cannot be confused with
    # "not an instance".
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

# ── Cross-App Communication ──────────────────────────────────

# Typed message categories for cross-app communication.
enum AppMessageType {
    # Absent means the backend decides; it must never mean a
    # specific paradigm value.
    unspecified @0;
    query @1;     # Request information from another app
    command @2;   # Request an action from another app
    event @3;     # Notify about a state change
    share @4;     # Share data/content with another app
    deeplink @5;  # Trigger a deep-link in another app
    custom @6;
}

struct AppMessage {
    typedType @0 :AppMessageType;
    # Message payload.
    payload @1 :AppMessagePayload;
    # Whether a response is expected.
    expectResponse @2 :Bool;
    # Timeout for response (zero = fire-and-forget).
    responseTimeout @3 :T.Duration;
    # Caller-chosen correlation key. A response arrives as a
    # `messageReceived` event whose `correlationId` echoes this value. It
    # exists because `expectResponse` used to have no way to be answered.
    correlationId @4 :Text;
}

struct AppMessagePayload {
    union {
        text @0 :Text;
        # Document-sized share-sheet payloads travel as buffer references.
        data @1 :T.DataHandle;
        json @2 :Text;
        custom @3 :T.StringMap;
        unknown @4 :Void;
    }
}

# ── Filter ────────────────────────────────────────────────────

struct RunningAppFilter {
    name @0 :Text;
    # Open tokens — the one app taxonomy, published in appindex.capnp.
    category @1 :Text;
    installed @2 :T.BoolFilter;
    running @3 :T.BoolFilter;
    minMemoryBytes @4 :UInt64;
    maxMemoryBytes @5 :UInt64;
    source @6 :Text;
    foreground @7 :T.BoolFilter;
    # Runtime lifecycle only. Install state is appindex.capnp's `AppState`.
    lifecycle @8 :AppLifecycle;
    metadata @9 :T.StringMap;
}

# ── Events ────────────────────────────────────────────────────

interface AppSubscription {
    pull @0 (maxEvents :UInt32) -> (events :List(AppEvent));
    cancel @1 () -> T.VoidResult;
}

struct AppEvent {
    union {
        launched @0 :AppLaunchedEvent;
        closed @1 :AppClosedEvent;
        stateChanged @2 :AppStateChangedEvent;
        crashed @3 :AppCrashEvent;
        suspended @4 :AppSuspendEvent;
        resumed @5 :AppResumeEvent;
        messageReceived @6 :AppMessageEvent;
        instanceCreated @7 :AppInstanceEvent;
        instanceDestroyed @8 :AppInstanceEvent;
        unknown @9 :T.UnknownEvent;
    }
}

struct AppLaunchedEvent {
    appId @0 :T.AppId;
    pid @1 :T.ProcessId;
    timestamp @2 :T.Timestamp;
    instance @3 :AI.AppInstanceRef;
}

struct AppClosedEvent {
    appId @0 :T.AppId;
    exitStatus @1 :T.ExitStatus;
    timestamp @2 :T.Timestamp;
    instance @3 :AI.AppInstanceRef;
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

struct AppSuspendEvent {
    appId @0 :T.AppId;
    reason @1 :AppSuspendReason;
    timestamp @2 :T.Timestamp;
}

struct AppResumeEvent {
    appId @0 :T.AppId;
    reason @1 :AppResumeReason;
    timestamp @2 :T.Timestamp;
}

struct AppMessageEvent {
    fromAppId @0 :T.AppId;
    toAppId @1 :T.AppId;
    message @2 :AppMessage;
    timestamp @3 :T.Timestamp;
}

struct AppInstanceEvent {
    appId @0 :T.AppId;
    instance @1 :AI.AppInstanceRef;
    timestamp @2 :T.Timestamp;
}

# Lifecycle trigger reasons. Open tokens would be over-engineering here: each
# is a small, genuinely closed set of causes with `custom` for the rest.
enum AppSuspendReason {
    userRequest @0;
    memoryPressure @1;
    idle @2;
    policy @3;
    background @4;
    custom @5;
}

enum AppResumeReason {
    userRequest @0;
    notification @1;
    timer @2;
    pushMessage @3;
    backgroundTask @4;
    custom @5;
}

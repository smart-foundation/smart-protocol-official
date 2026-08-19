@0xa1b2c3d4e5f6001c;

# ═══════════════════════════════════════════════════════════════════════
# Extension — plugin lifecycle management.
#
# Zero-backend-assumption IPC contract for dynamic extensions/plugins.
# No browser extension API, Electron, or platform-specific plugin system
# assumed. The backend decides the extension host; the protocol defines
# the contract.
#
# Improvements (audit):
#   - ExtensionId typed (was bare Text).
#   - ExtensionInfo.icon → T.DataHandle for zero-copy large payloads.
#   - ExtensionInfo.permissions typed as T.PermissionId list (was Text).
#   - callExtensionApi returns T.DataHandle (was bare Data).
#   - Extension has subscription for lifecycle events.
#   - ExtensionEvent union has custom variant for forward compatibility.
#   - listExtensionsPage for paginated extension listing.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface Extension {
    listExtensions @0 () -> (extensions :List(ExtensionInfo));
    getExtension @1 (extensionId :T.ExtensionId) -> (info :ExtensionInfo);

    enable @2 (extensionId :T.ExtensionId) -> T.VoidResult;
    disable @3 (extensionId :T.ExtensionId) -> T.VoidResult;
    reload @4 (extensionId :T.ExtensionId) -> T.VoidResult;
    uninstall @5 (extensionId :T.ExtensionId) -> T.VoidResult;

    getExtensionSettings @6 (extensionId :T.ExtensionId) -> (settings :T.StringMap);
    setExtensionSetting @7 (extensionId :T.ExtensionId, key :Text, value :Text) -> T.VoidResult;

    callExtensionApi @8 (extensionId :T.ExtensionId, method :Text, params :T.DataHandle) -> (result :T.DataHandle);

    # Subscribe to extension lifecycle events.
    subscribe @9 (filter :ExtensionEventFilter) -> (subscription :ExtensionSubscription);

    # Paginated extension listing — use instead of listExtensions for large sets.
    listExtensionsPage @10 (pagination :T.Pagination) -> (extensions :List(ExtensionInfo), total :UInt64);

    # Audit-8: grant a capability to an extension.
    grantCapability @11 (extensionId :T.ExtensionId, capabilityId :T.PermissionId) -> T.VoidResult;

    # Audit-8: revoke a capability from an extension.
    revokeCapability @12 (extensionId :T.ExtensionId, capabilityId :T.PermissionId) -> T.VoidResult;

    # Audit-8: check if an extension has a specific capability.
    checkCapability @13 (extensionId :T.ExtensionId, capabilityId :T.PermissionId) -> (hasCapability :Bool);

    # Audit-8: resolve extension dependencies.
    resolveDependencies @14 (extensionId :T.ExtensionId) -> (resolved :Bool, missing :List(T.ExtensionId));

    # Audit-8: check extension compatibility.
    checkCompatibility @15 (extensionId :T.ExtensionId) -> (compatible :Bool, issues :List(Text));

    # Audit-8: set extension sandbox config.
    setSandboxConfig @16 (extensionId :T.ExtensionId, config :ExtensionSandboxConfig) -> T.VoidResult;

    # Audit-8: get extension sandbox config.
    getSandboxConfig @17 (extensionId :T.ExtensionId) -> (config :ExtensionSandboxConfig);

    # Audit-8: get extension resource usage.
    getResourceUsage @18 (extensionId :T.ExtensionId) -> (usage :ExtensionResourceUsage);

    # Audit-8: get extension telemetry.
    getTelemetry @19 (extensionId :T.ExtensionId) -> (telemetry :ExtensionTelemetry);

    # Audit-8: check for extension update.
    checkExtensionUpdate @20 (extensionId :T.ExtensionId) -> (update :ExtensionUpdateInfo);

    # Audit-8: rollback extension to a previous version.
    rollbackExtension @21 (extensionId :T.ExtensionId, toVersion :T.Version) -> T.VoidResult;

    # Audit-8: hot-reload extension without restart.
    hotReload @22 (extensionId :T.ExtensionId) -> T.VoidResult;

    # Audit-8: list extensions by trust level.
    listExtensionsByTrust @23 (trustLevel :ExtensionTrustLevel, pagination :T.Pagination)
                         -> (extensions :List(ExtensionInfo), total :UInt64);

    # Audit-8: get extension health.
    getExtensionHealth @24 (extensionId :T.ExtensionId) -> (healthy :Bool, message :Text);

    # Audit-9: WASM extension runtime.
    loadWasmModule @25 (extensionId :T.ExtensionId, module :T.DataHandle) -> (info :WasmExtensionInfo);
    unloadWasmModule @26 (extensionId :T.ExtensionId) -> T.VoidResult;
    getWasmInfo @27 (extensionId :T.ExtensionId) -> (info :WasmExtensionInfo);
    listWasmCapabilities @28 (extensionId :T.ExtensionId) -> (capabilities :List(WasmCapability));
    grantWasmCapability @29 (extensionId :T.ExtensionId, capability :Text) -> T.VoidResult;
    revokeWasmCapability @30 (extensionId :T.ExtensionId, capability :Text) -> T.VoidResult;

    # Audit-10: extension lifecycle hooks.
    registerLifecycleHook @31 (extensionId :T.ExtensionId, hook :ExtensionLifecycleHook) -> T.VoidResult;
    unregisterLifecycleHook @32 (extensionId :T.ExtensionId, hookId :UInt64) -> T.VoidResult;
    listLifecycleHooks @33 (extensionId :T.ExtensionId) -> (hooks :List(ExtensionLifecycleHook));

    # Audit-10: extension signing for trust verification.
    signExtension @34 (extensionId :T.ExtensionId) -> (signature :ExtensionSignature);
    verifyExtension @35 (extensionId :T.ExtensionId, signature :ExtensionSignature) -> (valid :Bool);
    getExtensionSignature @36 (extensionId :T.ExtensionId) -> (signature :ExtensionSignature);

    # Audit-10: extension communication bus for cross-extension messaging.
    getExtensionBus @37 () -> (bus :ExtensionBus);
}

struct ExtensionInfo {
    id @0 :T.ExtensionId;
    name @1 :Text;
    description @2 :Text;
    version @3 :T.Version;
    author @4 :Text;
    # Icon as inline small data or buffer reference for large icons.
    icon @5 :T.DataHandle;
    # Typed permission IDs (references permission declarations).
    permissions @6 :List(T.PermissionId);
    enabled @7 :Bool;
    running @8 :Bool;
    # API method names exposed by this extension.
    apis @9 :List(Text);
    # Audit-8 additions:
    # Trust level for this extension.
    trustLevel @10 :ExtensionTrustLevel;
    # Structured capability declarations.
    capabilities @11 :List(ExtensionCapability);
    # Declared dependencies on other extensions.
    dependencies @12 :List(ExtensionDependency);
    # Repository URL for updates.
    repositoryUrl @13 :Text;
    # License identifier.
    license @14 :Text;
    # Average user rating (0.0-5.0).
    averageRating @15 :Float32;
    # Number of installs.
    installCount @16 :UInt64;
}

struct ExtensionEventFilter {
    # Filter by specific extension IDs (empty = all).
    extensionIds @0 :List(T.ExtensionId);
    # Filter by event kinds.
    kinds @1 :List(ExtensionEventKind);
}

enum ExtensionEventKind {
    enabled @0;
    disabled @1;
    reloaded @2;
    uninstalled @3;
    settingsChanged @4;
    other @5;
    # Backend-specific extension event kind.
    custom @6;
}

interface ExtensionSubscription {
    pull @0 () -> (events :List(ExtensionEvent));
    # Explicit cancellation — stops the event stream and releases resources.
    cancel @1 () -> T.VoidResult;
}

struct ExtensionEvent {
    timestamp @0 :T.Timestamp;
    extensionId @1 :T.ExtensionId;
    union {
        enabled @2 :Void;
        disabled @3 :Void;
        reloaded @4 :Void;
        uninstalled @5 :Void;
        settingsChanged @6 :SettingsChangedEvent;
        error @7 :T.Error;
        # Backend-specific extension event type.
        custom @8 :Data;
    }
}

struct SettingsChangedEvent {
    key @0 :Text;
    oldValue @1 :Text;
    newValue @2 :Text;
}

# Audit-8: extension trust level.
enum ExtensionTrustLevel {
    system @0;
    platform @1;
    user @2;
    sandboxed @3;
    untrusted @4;
    custom @5;
}

# Audit-8: extension capability declaration.
struct ExtensionCapability {
    id @0 :T.PermissionId;
    name @1 :Text;
    description @2 :Text;
    scope @3 :CapabilityScope;
    required @4 :Bool;
}

# Audit-8: capability scope.
enum CapabilityScope {
    extension @0;
    system @1;
    network @2;
    filesystem @3;
    custom @4;
}

# Audit-8: extension dependency.
struct ExtensionDependency {
    extensionId @0 :T.ExtensionId;
    dependsOn @1 :T.ExtensionId;
    versionConstraint @2 :Text;
    required @3 :Bool;
}

# Audit-8: extension sandbox configuration.
struct ExtensionSandboxConfig {
    extensionId @0 :T.ExtensionId;
    allowedApis @1 :List(Text);
    deniedApis @2 :List(Text);
    memoryLimitBytes @3 :UInt64;
    cpuTimeLimitMs @4 :UInt64;
    networkAccess @5 :Bool;
}

# Audit-8: extension resource usage.
struct ExtensionResourceUsage {
    extensionId @0 :T.ExtensionId;
    memoryBytes @1 :UInt64;
    cpuTimeMs @2 :UInt64;
    networkRxBytes @3 :UInt64;
    networkTxBytes @4 :UInt64;
    timestamp @5 :T.Timestamp;
}

# Audit-8: extension telemetry.
struct ExtensionTelemetry {
    extensionId @0 :T.ExtensionId;
    apiCalls @1 :UInt64;
    errors @2 :UInt64;
    avgLatency @3 :T.Duration;
    lastActive @4 :T.Timestamp;
}

# Audit-8: extension update info.
struct ExtensionUpdateInfo {
    extensionId @0 :T.ExtensionId;
    currentVersion @1 :T.Version;
    availableVersion @2 :T.Version;
    changelog @3 :Text;
    sizeBytes @4 :UInt64;
}

# ── Audit-9: WASM Extension Runtime ─────────────────────────────────
# WASM-based extension runtime with capability-based security.
# Provides module loading, WASI capabilities, and memory management
# for WASM-based extensions.
struct WasmExtensionInfo {
    extensionId @0 :T.ExtensionId;
    # WASM module bytecode size.
    moduleSize @1 :UInt64;
    # Number of memory pages (64KB each).
    memoryPages @2 :UInt32;
    # Maximum memory pages allowed.
    maxMemoryPages @3 :UInt32;
    # Number of exported functions.
    exportedFunctions @4 :UInt32;
    # WASI version (e.g., "preview1", "preview2").
    wasiVersion @5 :Text;
    # Whether the module uses threads (SharedArrayBuffer).
    threads @6 :Bool;
}

struct WasmCapability {
    name @0 :Text;
    granted @1 :Bool;
}

interface WasmExtensionHost {
    loadWasmModule @0 (extensionId :T.ExtensionId, module :T.DataHandle) -> (info :WasmExtensionInfo);
    unloadWasmModule @1 (extensionId :T.ExtensionId) -> T.VoidResult;
    getWasmInfo @2 (extensionId :T.ExtensionId) -> (info :WasmExtensionInfo);
    listWasmCapabilities @3 (extensionId :T.ExtensionId) -> (capabilities :List(WasmCapability));
    grantWasmCapability @4 (extensionId :T.ExtensionId, capability :Text) -> T.VoidResult;
    revokeWasmCapability @5 (extensionId :T.ExtensionId, capability :Text) -> T.VoidResult;
}

# ── Audit-10: Extension Lifecycle Hooks ─────────────────────────────────
# Pre/post hooks for extension lifecycle events.
struct ExtensionLifecycleHook {
    hookId @0 :UInt64;
    event @1 :LifecycleEvent;
    when @2 :LifecycleWhen;
    action @3 :LifecycleAction;
    enabled @4 :Bool;
}

enum LifecycleEvent {
    beforeInstall @0;
    afterInstall @1;
    beforeEnable @2;
    afterEnable @3;
    beforeDisable @4;
    afterDisable @5;
    beforeUninstall @6;
    afterUninstall @7;
    beforeUpdate @8;
    afterUpdate @9;
    onError @10;
}

enum LifecycleWhen {
    before @0;    # Run before the event
    after @1;     # Run after the event
    around @2;    # Run around the event (can intercept/modify)
}

struct LifecycleAction {
    union {
        invokeApi @0 :ApiInvocation;
        runScript @1 :ScriptAction;
        custom @2 :Data;
    }
}

struct ApiInvocation {
    targetApi @0 :Text;
    method @1 :Text;
    arguments @2 :List(T.Meta);
}

struct ScriptAction {
    script @0 :Text;
    language @1 :Text;
}

# ── Audit-10: Extension Signing ─────────────────────────────────────────
# Cryptographic signing of extensions for trust verification.
struct ExtensionSignature {
    extensionId @0 :T.ExtensionId;
    version @1 :T.Version;
    signature @2 :T.DataHandle;
    algorithm @3 :Text;
    certificateChain @4 :List(T.DataHandle);
    signedAt @5 :T.Timestamp;
    expiresAt @6 :T.Timestamp;
    signerId @7 :Text;
}

# ── Audit-10: Extension Communication Bus ───────────────────────────────
# Message bus for cross-extension coordination.
interface ExtensionBus {
    # Post a message to a channel.
    postMessage @0 (channel :Text, message :T.DataHandle, targetExtensions :List(T.ExtensionId)) -> T.VoidResult;

    # Subscribe to a channel.
    subscribe @1 (channel :Text) -> (subscription :ExtensionBusSubscription);

    # Unsubscribe from a channel.
    unsubscribe @2 (channel :Text, subscription :ExtensionBusSubscription) -> T.VoidResult;

    # List available channels.
    listChannels @3 () -> (channels :List(ExtensionBusChannel));
}

interface ExtensionBusSubscription {
    pull @0 () -> (messages :List(ExtensionBusMessage));
    cancel @1 () -> T.VoidResult;
}

struct ExtensionBusMessage {
    senderId @0 :T.ExtensionId;
    channel @1 :Text;
    payload @2 :T.DataHandle;
    timestamp @3 :T.Timestamp;
    correlationId @4 :Text;
}

struct ExtensionBusChannel {
    name @0 :Text;
    subscribers @1 :UInt32;
    messageCount @2 :UInt64;
}

@0xa1b2c3d4e5f6001c;

# ═══════════════════════════════════════════════════════════════════════
# Extension — extension (plug-in) lifecycle management.
#
# WHAT THIS IS
#   Zero-backend-assumption IPC for dynamic extensions: list, inspect,
#   enable, disable, reload, uninstall, call an API, and load a module.
#
# THE HEADER'S PROMISE IS NOW TRUE
#   The old header said "the backend decides the extension host; the protocol
#   defines the contract" — and then froze ONE host technology into five
#   required methods. `loadWasmModule`/`unloadWasmModule`/`getWasmInfo`/
#   `listWasmCapabilities`/`grantWasmCapability`/`revokeWasmCapability`, plus
#   `WasmExtensionInfo` with `memoryPages` (64KB granularity), `wasiVersion`
#   ("preview1"/"preview2"), and `threads`, made WASM the required execution
#   model. A 2046 host running a native capability-isolated sandbox, Lua, or
#   a VM not yet invented has no WASM to report and had to fake the fields.
#   There is now ONE module surface — `loadModule`/`unloadModule`/
#   `getModuleInfo` — whose `runtime` is an open content type and whose
#   metadata is an open map. Wasm is one runtime among any number.
#
# NO SCRIPTED CODE EXECUTION AS CONTRACT
#   `ScriptAction { script :Text, language :Text }` was a lifecycle-hook
#   action that instructed hosts to run arbitrary text on install, enable and
#   update paths. That is a remote-code-execution instruction published as
#   protocol — the same class of hole ai.capnp's header calls out for its own
#   previous revision's `ToolRegistry.invoke`. Hook actions are now either an
#   API invocation or backend-internal policy the contract does not name.
#
# ONE CAPABILITY MODEL
#   `grantCapability` took a typed `T.PermissionId` while
#   `grantWasmCapability` took a `capability :Text` — the same concept, typed
#   in one method and a string in another, in one file. The string path is
#   deleted. `ExtensionCapability { id, scope }` — a second capability model
#   beside capability.capnp's `Capability { target, operations, constraints }`
#   — is deleted too: it could not express target, operations, expiry or
#   attenuation, so authority decided in it was invisible to the canonical
#   one. What an extension declares comes from its Manifest as
#   `CapabilityRequirement`; what it is granted is capability.capnp's
#   business.
#
# WHAT ELSE WAS DELETED
#   - The bus (`getExtensionBus`, `ExtensionBus`, `ExtensionBusSubscription`,
#     `ExtensionBusMessage`, `ExtensionBusChannel`): a third messaging model
#     beside queue.capnp's durable queue and app.capnp's app messaging, with
#     its own subscription shape. If a bus is genuinely needed it grows out of
#     queue's model, not beside it.
#   - `WasmExtensionHost`: five duplicate wasm methods in an interface that
#     nothing returned. Unreachable interfaces are dead schema.
#   - The sandbox configuration (`setSandboxConfig`, `getSandboxConfig`,
#     `ExtensionSandboxConfig`): `allowedApis`/`deniedApis` were permission
#     string lists and `networkAccess` was an authority flag — a parallel
#     model. An extension's isolation is the host's enforceable property,
#     declared through capability operations and constraints.
#   - The update path (`checkExtensionUpdate`, `rollbackExtension`,
#     `hotReload`): extensions are packages, and package.capnp already runs
#     the whole lifecycle. Two update paths with different models is a fork.
#   - The signing surface (`signExtension`, `verifyExtension`,
#     `getExtensionSignature`, `ExtensionSignature`): signing is
#     signature.capnp's operation and the key is key_management's, so this
#     was a third home for one action. Trust is reported as `T.TrustLevel`.
#
# WHAT WAS FIXED
#   - Lifecycle hook ids are SERVER-ISSUED. Two extensions registering hook
#     id 1 used to collide invisibly.
#   - `checkCompatibility` returns `T.Error`-carrying detail instead of
#     `(compatible :Bool, issues :List(Text))` — a consumer could not route on
#     prose.
#   - `getExtensionHealth` returns structured warnings instead of
#     `(healthy :Bool, message :Text)`.
#   - `ExtensionResourceUsage` states its sampling interval, so a caller
#     stops guessing the cadence — and stops polling because it cannot tell.
#   - `apis` is a typed declaration with a schema id, so an extension's
#     methods are discoverable and generatable rather than a list of bare
#     names.
#   - `listExtensions` is paginated, so the unbounded original and its paged
#     twin no longer both invite use.
#   - `ExtensionTrustLevel` (an identical value set) is replaced by the
#     promoted `T.TrustLevel`.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using M = import "manifest.capnp";

interface Extension {
    # All listing is paginated: an unbounded original beside a paged twin is
    # an invitation to use the wrong one.
    listExtensions @0 (pagination :T.Pagination)
                    -> (extensions :List(ExtensionInfo), total :UInt64);
    getExtension @1 (extensionId :T.ExtensionId) -> (result :ExtensionInfoResult);

    enable @2 (extensionId :T.ExtensionId) -> T.VoidResult;
    disable @3 (extensionId :T.ExtensionId) -> T.VoidResult;
    reload @4 (extensionId :T.ExtensionId) -> T.VoidResult;
    uninstall @5 (extensionId :T.ExtensionId) -> T.VoidResult;

    getExtensionSettings @6 (extensionId :T.ExtensionId) -> (settings :T.StringMap);
    setExtensionSetting @7 (extensionId :T.ExtensionId, key :Text, value :Text)
                          -> T.VoidResult;

    # An open RPC: `method` is a token the extension publishes through `apis`,
    # and both parameters and results are opaque content. Nothing here
    # presupposes a calling convention or a serialization format.
    callExtensionApi @8 (extensionId :T.ExtensionId, method :Text,
                         params :T.DataHandle) -> (result :T.DataHandle);

    # Subscribe to extension lifecycle events.
    subscribe @9 (filter :ExtensionEventFilter) -> (subscription :ExtensionSubscription);

    listExtensionsPage @10 (pagination :T.Pagination)
                        -> (extensions :List(ExtensionInfo), total :UInt64);

    # Grant a capability to an extension. `T.PermissionId` is typed; the
    # string spelling that used to sit beside it is gone.
    grantCapability @11 (extensionId :T.ExtensionId, capabilityId :T.PermissionId)
                      -> T.VoidResult;

    revokeCapability @12 (extensionId :T.ExtensionId, capabilityId :T.PermissionId)
                       -> T.VoidResult;

    checkCapability @13 (extensionId :T.ExtensionId, capabilityId :T.PermissionId)
                     -> (result :CapabilityCheck);

    resolveDependencies @14 (extensionId :T.ExtensionId)
                         -> (result :DependencyResolution);

    checkCompatibility @15 (extensionId :T.ExtensionId)
                        -> (result :CompatibilityResult);

    getResourceUsage @16 (extensionId :T.ExtensionId)
                      -> (usage :ExtensionResourceUsage);

    getTelemetry @17 (extensionId :T.ExtensionId) -> (telemetry :ExtensionTelemetry);

    # List extensions by trust level. Uses the promoted T.TrustLevel.
    listExtensionsByTrust @18 (trustLevel :T.TrustLevel, pagination :T.Pagination)
                           -> (extensions :List(ExtensionInfo), total :UInt64);

    getExtensionHealth @19 (extensionId :T.ExtensionId) -> (health :ExtensionHealth);

    # ── Module loading (runtime-open) ───────────────────────────
    # `runtime` is an open content type: WASM is one value, and a runtime
    # not yet invented is another, with no schema change.

    loadModule @20 (extensionId :T.ExtensionId, module :T.DataHandle,
                    runtime :T.MimeType) -> (info :ModuleInfo);
    unloadModule @21 (extensionId :T.ExtensionId) -> T.VoidResult;
    getModuleInfo @22 (extensionId :T.ExtensionId) -> (info :ModuleInfo);

    # ── Lifecycle hooks ────────────────────────────────────────

    # Returns a SERVER-ISSUED hook id. Caller-chosen ids collided invisibly
    # between extensions.
    registerLifecycleHook @23 (extensionId :T.ExtensionId, hook :ExtensionLifecycleHook)
                           -> (hookId :UInt64);
    unregisterLifecycleHook @24 (extensionId :T.ExtensionId, hookId :UInt64)
                             -> T.VoidResult;
    listLifecycleHooks @25 (extensionId :T.ExtensionId)
                        -> (hooks :List(ExtensionLifecycleHook));
}

# ── Results ───────────────────────────────────────────────────

struct ExtensionInfoResult {
    union {
        info    @0 :ExtensionInfo;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct CapabilityCheck {
    union {
        granted @0 :Void;
        denied  @1 :T.Error;
        unknown @2 :Void;
    }
}

struct DependencyResolution {
    union {
        resolved @0 :Void;
        missing  @1 :List(T.ExtensionId);
        error    @2 :T.Error;
        unknown  @3 :Void;
    }
}

struct CompatibilityResult {
    union {
        compatible @0 :Void;
        # Routable issues, not prose: a consumer can act on a code.
        issues     @1 :List(T.Error);
        unknown    @2 :Void;
    }
}

struct ExtensionHealth {
    healthy @0 :Bool;
    # Structured advisories, not a free-text message.
    issues  @1 :List(T.Warning);
    checkedAt @2 :T.Timestamp;
    metadata @3 :T.StringMap;
}

# ── Extension Info ────────────────────────────────────────────

struct ExtensionInfo {
    id @0 :T.ExtensionId;
    name @1 :Text;
    description @2 :Text;
    version @3 :T.Version;
    author @4 :Text;
    # Icon as inline small data or buffer reference for large icons.
    icon @5 :T.DataHandle;
    # Typed permission IDs — not permission strings.
    permissions @6 :List(T.PermissionId);
    # The bundle's self-description, which carries the capability
    # requirements as target+operations.
    manifestName @7 :T.ManifestName;
    enabled @8 :Bool;
    running @9 :Bool;
    # Declared APIs. Each names its schema, so a CLI and language bindings
    # are generatable from the declaration rather than from a bare name.
    apis @10 :List(ApiDeclaration);
    # Reported, not decided here.
    trustLevel @11 :T.TrustLevel;
    # Declared dependencies on other extensions.
    dependencies @12 :List(ExtensionDependency);
    # Repository URL for updates.
    repositoryUrl @13 :Text;
    # License identifier.
    license @14 :Text;
}

struct ApiDeclaration {
    name @0 :Text;
    # The schema this API is declared in, so a client can read its shape.
    schemaId @1 :T.SchemaId;
    description @2 :Text;
    metadata @3 :T.StringMap;
}

struct ExtensionEventFilter {
    extensionIds @0 :List(T.ExtensionId);
    kinds @1 :List(ExtensionEventKind);
}

enum ExtensionEventKind {
    enabled @0;
    disabled @1;
    reloaded @2;
    uninstalled @3;
    settingsChanged @4;
    moduleLoaded @5;
    moduleUnloaded @6;
    other @7;
    custom @8;
}

interface ExtensionSubscription {
    pull @0 (maxEvents :UInt32) -> (events :List(ExtensionEvent));
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
        moduleLoaded @7 :ModuleInfo;
        moduleUnloaded @8 :Void;
        error @9 :T.Error;
        unknown @10 :T.UnknownEvent;
    }
}

struct SettingsChangedEvent {
    key @0 :Text;
    oldValue @1 :Text;
    newValue @2 :Text;
}

struct ExtensionDependency {
    extensionId @0 :T.ExtensionId;
    dependsOn @1 :T.ExtensionId;
    versionConstraint @2 :Text;
    required @3 :Bool;
}

# ── Module (runtime-open) ────────────────────────────────────

# What a loaded module IS. `runtime` is the open content type it was loaded
# as; everything a runtime would report about itself is an open key, so a
# runtime invented tomorrow needs no ordinal.
struct ModuleInfo {
    extensionId @0 :T.ExtensionId;
    runtime     @1 :T.MimeType;
    # Module bytecode size.
    moduleSize  @2 :UInt64;
    # Runtime-reported facts: memory pages, WASI version, thread count,
    # whatever a future runtime reports. Backend keys; unknown keys ignored.
    parameters  @3 :T.StringMap;
    loadedAt    @4 :T.Timestamp;
}

# ── Resource usage and telemetry ─────────────────────────────

struct ExtensionResourceUsage {
    extensionId @0 :T.ExtensionId;
    memoryBytes @1 :UInt64;
    cpuTime @2 :T.Duration;
    networkRxBytes @3 :UInt64;
    networkTxBytes @4 :UInt64;
    timestamp @5 :T.Timestamp;
    # The window these counters cover. Stated so a caller stops guessing the
    # cadence — and stops polling because it cannot tell.
    sampledOver @6 :T.Duration;
}

struct ExtensionTelemetry {
    extensionId @0 :T.ExtensionId;
    apiCalls @1 :UInt64;
    errors @2 :UInt64;
    avgLatency @3 :T.Duration;
    lastActive @4 :T.Timestamp;
}

# ── Lifecycle hooks ──────────────────────────────────────────

# Pre/post hooks for extension lifecycle events. A hook's action is an API
# invocation or nothing: there is no script action, because a contract that
# instructs a host to run arbitrary text is a remote-code-execution
# instruction.
struct ExtensionLifecycleHook {
    hookId @0 :UInt64;
    event @1 :LifecycleEvent;
    when @2 :LifecycleWhen;
    action @3 :LifecycleAction;
    enabled @4 :Bool;
}

enum LifecycleEvent {
    # Absent means the backend decides; it must never mean a
    # specific paradigm value.
    unspecified @0;
    beforeInstall @1;
    afterInstall @2;
    beforeEnable @3;
    afterEnable @4;
    beforeDisable @5;
    afterDisable @6;
    beforeUninstall @7;
    afterUninstall @8;
    beforeUpdate @9;
    afterUpdate @10;
    onError @11;
}

enum LifecycleWhen {
    # Absent means the backend decides; it must never mean a
    # specific paradigm value.
    unspecified @0;
    before @1;    # Run before the event
    after @2;     # Run after the event
    around @3;    # Run around the event (can intercept/modify)
}

struct LifecycleAction {
    union {
        invokeApi @0 :ApiInvocation;
        # Backend-internal policy the contract does not name: an opaque
        # token the host interprets.
        custom @1 :T.StringMap;
        unknown @2 :Void;
    }
}

struct ApiInvocation {
    targetApi @0 :Text;
    method @1 :Text;
    arguments @2 :T.StringMap;
}

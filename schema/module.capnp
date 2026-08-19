@0xa1b2c3d4e5f6003e;

# ═══════════════════════════════════════════════════════════════════════
# Module - loadable extensions and plug-in contract
#
# Apps and kernels alike load extensions: kernel modules, plug-ins,
# device drivers, codecs, fonts. Module describes the lifecycle and
# shape of any extension loadable at runtime.
#
# The protocol is timeless; implementations include kernel modules,
# userspace plug-ins, firmware blobs, anything attachable.
#
# Improvements beyond the original schema:
#   - ModuleId typed ID replaces bare Text names.
#   - T.Duration for cpuTime and wallClock limits.
#   - DataHandle for payload blobs that may exceed 1KB.
#   - T.Error for structured failure reasons.
#   - Subscription cancel method added.
#   - Pagination on list.
#   - Custom variant on Kind and LoadState enums.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "manifest.capnp".Manifest;
using import "manifest.capnp".Semver;

struct ModuleDesc {
    # Identifier of the module.
    id @0 :T.ModuleId;
    # Human-readable display name.
    displayName @1 :Text;
    # Module kind (kernel extension, codec, plug-in, ...).
    kind @2 :Kind;
    # Backend-decided payload (clean-disk image, wasm, parsed AST ...).
    # Use buffer handle for payloads >1KB.
    payloadBlob @3 :T.DataHandle;
    # Manifest describing the module's stated capabilities.
    manifest @4 :Manifest;
    # Whether the module is required to load.
    required @5 :Bool = false;
    # Optional metadata for caching or display.
    description @6 :Text;
    # Audit-8 additions:
    # Semantic version for the module.
    version @7 :Semver;
    # Runtime binding (which runtime version this module requires).
    runtimeBinding @8 :RuntimeBinding;
    # Module dependencies.
    dependencies @9 :List(T.ModuleId);
}

enum Kind {
    unknown @0;
    kernelExtension @1;
    deviceDriver @2;
    fileSystem @3;
    networkProtocol @4;
    audioCodec @5;
    videoCodec @6;
    font @7;
    uiPlugin @8;
    appExtension @9;
    servicePlugin @10;
    securityPolicy @11;
    traceSink @12;
    debugger @13;
    languageRuntime @14;
    # Audit-8 additions:
    # WebAssembly module.
    wasm @15;
    # Stackable overlay module.
    layer @16;
    # Module that grants specific capabilities.
    capabilityModule @17;
    custom @18;
}

struct ModuleState {
    # Identifier of the module.
    id @0 :T.ModuleId;
    state @1 :LoadState;
    loadedAt @2 :T.Timestamp;
    # Memory budget in bytes.
    memoryBytes @3 :UInt64;
    # CPU time consumed.
    cpuTime @4 :T.Duration;
    # Bus/event counters.
    counters @5 :List(Counter);
    # Audit-8 additions:
    # Health status.
    health @6 :ModuleHealth;
    # Actual granted capabilities.
    grantedCapabilities @7 :List(T.CapabilityId);
}

enum LoadState {
    uninitialized @0;
    loading @1;
    loaded @2;
    active @3;
    paused @4;
    unloading @5;
    unloaded @6;
    failed @7;
    blacklisted @8;
    custom @9;
}

struct Counter {
    name @0 :Text;
    value @1 :UInt64;
}

struct LoadSpec {
    # Loads from this location / blob.
    source @0 :Source;
    # Whether to verify signature.
    verifySignature @1 :Bool = true;
    # Pre-allocated capability grant to give to the module.
    capabilities @2 :List(Text);
    # Limits applied at load time.
    limits @3 :LoadLimits;
    # Audit-8: sandbox configuration for untrusted modules.
    sandbox @4 :ModuleSandboxConfig;
}

struct Source {
    union {
        builtin @0 :Text;
        blob @1 :T.DataHandle;
        url @2 :T.Uri;
        # Manifest name reference (resolved by the module service).
        manifest @3 :T.ManifestName;
        # Audit-8: WebAssembly module source.
        wasm @4 :WasmModuleSource;
    }
}

struct LoadLimits {
    memoryBytes @0 :UInt64;
    # Maximum CPU time budget per second of wall clock, in nanoseconds.
    # E.g., 100000000 (100ms) means the module can use 10% of one CPU core.
    cpuBudgetNsPerSec @1 :UInt64;
    openFiles @2 :UInt32;
    maxThreads @3 :UInt32;
    # Maximum wall-clock time for the load operation.
    wallClock @4 :T.Duration;
    exclusiveDevices @5 :Bool = true;
}

struct LoadResult {
    state @0 :ModuleState;
    warnings @1 :List(T.Warning);
}

interface ModuleService {
    # Load a module by descriptor.
    load @0 (spec :LoadSpec) -> (result :LoadResult);
    # Unload.
    unload @1 (moduleId :T.ModuleId) -> (result :T.VoidResult);
    # Pause / resume.
    pause @2 (moduleId :T.ModuleId) -> (result :T.VoidResult);
    resume @3 (moduleId :T.ModuleId) -> (result :T.VoidResult);
    # Query state.
    get @4 (moduleId :T.ModuleId) -> (state :ModuleState);
    list @5 (pagination :T.Pagination) -> (states :List(ModuleState));
    # Subscribe to module tree changes.
    subscribe @6 () -> (subscription :ModuleSubscription);

    # Audit-8: hot-reload a module without unload.
    reload @7 (moduleId :T.ModuleId, newSource :Source) -> (result :LoadResult);

    # Audit-8: compose multiple modules into a bundle.
    compose @8 (modules :List(T.ModuleId)) -> (composed :T.ModuleId);

    # Audit-8: get module health status.
    getHealth @9 (moduleId :T.ModuleId) -> (health :ModuleHealth);

    # Audit-8: test a module before loading.
    testModule @10 (moduleId :T.ModuleId) -> (passed :Bool, results :List(ModuleTestResult));

    # Audit-8: migrate a module to a different kind.
    migrateModule @11 (moduleId :T.ModuleId, targetKind :Kind) -> (migrated :T.ModuleId);

    # Audit-9: search for modules in a marketplace/repository.
    searchMarketplace @12 (query :ModuleMarketplaceQuery) -> (results :List(ModuleMarketplaceResult), total :UInt32);

    # Audit-9: install a module from the marketplace.
    installFromMarketplace @13 (moduleId :Text, version :T.Version) -> (result :LoadResult);

    # Audit-9: profile CPU/memory usage of a module.
    profileModule @14 (moduleId :T.ModuleId, duration :T.Duration) -> (profile :ModuleProfile);

    # Audit-9: set a lifecycle hook for a module.
    setLifecycleHook @15 (moduleId :T.ModuleId, hook :ModuleLifecycleHook) -> (hookId :Text);

    # Audit-9: remove a lifecycle hook.
    removeLifecycleHook @16 (moduleId :T.ModuleId, hookId :Text) -> T.VoidResult;

    # Audit-9: replay module events from a saved event log.
    replayEvents @17 (moduleId :T.ModuleId, fromIndex :UInt64) -> T.VoidResult;

    # Audit-9: get the event log for a module.
    getEventLog @18 (moduleId :T.ModuleId, pagination :T.Pagination) -> (events :List(ModuleEventEntry), total :UInt32);

    # Audit-9: set a feature flag for a module.
    setFeatureFlag @19 (moduleId :T.ModuleId, flag :ModuleFeatureFlag) -> T.VoidResult;

    # Audit-9: get feature flags for a module.
    getFeatureFlags @20 (moduleId :T.ModuleId) -> (flags :List(ModuleFeatureFlag));

    # Audit-9: set multi-tenancy configuration for a module.
    setTenancyConfig @21 (moduleId :T.ModuleId, config :ModuleTenancyConfig) -> T.VoidResult;

    # Audit-9: get multi-tenancy configuration for a module.
    getTenancyConfig @22 (moduleId :T.ModuleId) -> (config :ModuleTenancyConfig);
}

interface ModuleSubscription {
    pull @0 () -> (events :List(ModuleEvent));
    cancel @1 () -> T.VoidResult;
}

struct ModuleEvent {
    union {
        loaded @0 :ModuleState;
        unloaded @1 :T.ModuleId;
        stateChanged @2 :ModuleState;
        failed @3 :ModuleFailure;
    }
}

struct ModuleFailure {
    id @0 :T.ModuleId;
    reason @1 :T.Error;
    attempts @2 :UInt32;
}

# Audit-8: module health status.
struct ModuleHealth {
    healthy @0 :Bool;
    lastCheck @1 :T.Timestamp;
    message @2 :Text;
}

# Audit-8: module sandbox configuration.
struct ModuleSandboxConfig {
    networkAccess @0 :Bool;
    filesystemAccess @1 :Bool;
    maxMemoryBytes @2 :UInt64;
    maxCpuTimeMs @3 :UInt64;
}

# Audit-8: runtime binding for module version compatibility.
struct RuntimeBinding {
    runtimeName @0 :Text;
    minVersion @1 :Semver;
    maxVersion @2 :Semver;
}

# Audit-8: WebAssembly module source.
struct WasmModuleSource {
    bytes @0 :T.DataHandle;
    imports @1 :List(Text);
    exports @2 :List(Text);
}

# Audit-8: module test result.
struct ModuleTestResult {
    name @0 :Text;
    passed @1 :Bool;
    message @2 :Text;
    duration @3 :T.Duration;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-9: Module marketplace, profiling, lifecycle hooks, event sourcing,
# feature flags, and multi-tenancy.
# ═══════════════════════════════════════════════════════════════════════

# ── Module Marketplace ────────────────────────────────────────

struct ModuleMarketplaceQuery {
    # Search text (name, description, author).
    search @0 :Text;
    # Filter by module kind.
    kind @1 :Kind;
    # Filter by author.
    author @2 :Text;
    # Filter by tag/keyword.
    tag @3 :Text;
    # Sort order.
    sortBy @4 :ModuleSortField;
}

enum ModuleSortField {
    name @0;
    version @1;
    downloads @2;
    rating @3;
    updated @4;
    custom @5;
}

struct ModuleMarketplaceResult {
    # Module ID in the marketplace.
    moduleId @0 :Text;
    # Display name.
    name @1 :Text;
    # Description.
    description @2 :Text;
    # Author.
    author @3 :Text;
    # Latest version.
    version @4 :T.Version;
    # Module kind.
    kind @5 :Kind;
    # Download count.
    downloads @6 :UInt64;
    # Rating (0.0-5.0).
    rating @7 :Float32;
    # When last updated.
    updatedAt @8 :T.Timestamp;
}

# ── Module Profiling ──────────────────────────────────────────

struct ModuleProfile {
    # Module being profiled.
    moduleId @0 :T.ModuleId;
    # Profiling duration.
    duration @1 :T.Duration;
    # CPU time consumed.
    cpuTime @2 :T.Duration;
    # Peak memory usage in bytes.
    peakMemoryBytes @3 :UInt64;
    # Average memory usage in bytes.
    avgMemoryBytes @4 :UInt64;
    # Number of function calls.
    callCount @5 :UInt64;
    # Top functions by time.
    topFunctions @6 :List(ModuleFunctionProfile);
}

struct ModuleFunctionProfile {
    # Function name.
    name @0 :Text;
    # Time spent in this function.
    time @1 :T.Duration;
    # Number of calls.
    calls @2 :UInt64;
    # Memory allocated by this function.
    memoryBytes @3 :UInt64;
}

# ── Module Lifecycle Hooks ────────────────────────────────────

struct ModuleLifecycleHook {
    # Hook name.
    name @0 :Text;
    # When the hook fires.
    phase @1 :ModuleHookPhase;
    # Command or script to execute.
    command @2 :List(Text);
    # Timeout for the hook.
    timeout @3 :T.Duration;
}

enum ModuleHookPhase {
    preLoad @0;
    postLoad @1;
    preUnload @2;
    postUnload @3;
    preReload @4;
    postReload @5;
    custom @6;
}

# ── Module Event Sourcing ─────────────────────────────────────

struct ModuleEventEntry {
    # Sequence index in the event log.
    index @0 :UInt64;
    # Event type.
    type @1 :Text;
    # Event payload (serialized).
    payload @2 :Data;
    # Timestamp of the event.
    timestamp @3 :T.Timestamp;
}

# ── Module Feature Flags ──────────────────────────────────────

struct ModuleFeatureFlag {
    # Flag name.
    name @0 :Text;
    # Whether the flag is enabled.
    enabled @1 :Bool;
    # Percentage of users to enable for (0-100, 100 = all).
    percentage @2 :UInt32;
    # Human-readable description.
    description @3 :Text;
}

# ── Module Multi-Tenancy ──────────────────────────────────────

struct ModuleTenancyConfig {
    # Whether multi-tenancy is enabled.
    enabled @0 :Bool;
    # Maximum number of tenants.
    maxTenants @1 :UInt32;
    # Whether tenants have isolated state.
    isolatedState @2 :Bool;
    # Whether tenants have isolated memory.
    isolatedMemory @3 :Bool;
    # Resource limits per tenant.
    perTenantLimits @4 :LoadLimits;
}

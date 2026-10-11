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
#
# Revamp removals (each names the rule it violated):
#   - `LoadSpec.capabilities :List(Text)` -> capability REFERENCES.
#     Permission strings as the authority mechanism (R3,
#     DESIGN_PRINCIPLES.md:399); a Text cannot carry operations,
#     constraints or expiry, so every host invented its own meaning and
#     no two hosts agreed. It also disagreed with
#     ModuleState.grantedCapabilities, which reported by id.
#   - `ModuleLifecycleHook.command :List(Text)` / setLifecycleHook /
#     removeLifecycleHook — DELETED. An arbitrary command line the host
#     would execute with no capability anywhere in the file: the
#     unauthenticated remote-code-execution path ai.capnp:324-327
#     removed from its own ToolRegistry.
#   - `LoadLimits.exclusiveDevices` default flipped true -> false: a
#     capability granted silently on every load.
#   - The marketplace, feature-flag and multi-tenancy blocks — DELETED.
#     Product decisions, not module/host contract (R1).
#   - `ModuleProfile.topFunctions` — DELETED. Presupposes a symbol
#     table, which WASM/interpreted/JIT modules do not have
#     (DESIGN_PRINCIPLES.md:228).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "capability.capnp".Capability;
using import "manifest.capnp".Manifest;

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
    # Semantic version for the module. `T.Version`, not a second version type:
    # a 16-bit major wraps at 65535 and three files comparing versions with
    # three structs is the one-home-per-type failure this tree removes.
    version @7 :T.Version;
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
    # Actual granted capabilities, as references — the same type
    # LoadSpec.capabilities prepares, so load and state agree.
    grantedCapabilities @7 :List(Capability);
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

# ── AUTHORITY IS A REFERENCE, NOT A NAME ─────────────────────────────────
#
# `capabilities @2 :List(Text)` was the authority a module was loaded
# with, expressed as a list of names. DESIGN_PRINCIPLES.md:399 forbids
# exactly this ("Do NOT define permission strings ... The capability
# system IS the access control mechanism"): a `Text` cannot carry
# operations, constraints, expiry or attenuation — all of which
# capability.capnp:22-53 already models — so every host had to invent
# what `"filesystem:read"` meant, and no two hosts agreed. It also
# disagreed with `ModuleState.grantedCapabilities`, which reported
# authority by T.CapabilityId, so the load path and the state path
# described the same grant two different ways.
#
# Both are now capability references. Nothing is invented: the type
# already exists and already carries the semantics.
struct LoadSpec {
    # Loads from this location / blob.
    source @0 :Source;
    # Whether to verify signature.
    verifySignature @1 :Bool = true;
    # Pre-allocated capability grants to give to the module, as
    # CAPABILITY REFERENCES.
    capabilities @2 :List(Capability);
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
        # Forward compatibility for a source form the contract has not
        # named — a package index, an attestation-gated remote, a
        # content-addressed store. Without this arm a new form reaches an
        # old consumer as an unrecognisable member with no way to route it.
        unknown @5 :T.UnknownEvent;
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
    # Exclusive device access. Was a default-true Bool, i.e. a capability
    # granted silently on every load — one module's default overriding
    # every other module's access with no reference to attenuate. It is
    # now an explicit, revocable grant in LoadSpec.capabilities.
    exclusiveDevices @5 :Bool = false;
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

    # Audit-9: profile CPU/memory usage of a module.
    profileModule @12 (moduleId :T.ModuleId, duration :T.Duration) -> (profile :ModuleProfile);

    # Audit-9: replay module events from a saved event log.
    replayEvents @13 (moduleId :T.ModuleId, fromIndex :UInt64) -> (result :T.VoidResult);

    # Audit-9: get the event log for a module.
    getEventLog @14 (moduleId :T.ModuleId, pagination :T.Pagination) -> (events :List(ModuleEventEntry), total :UInt32);
}

interface ModuleSubscription {
    pull @0 () -> (events :List(ModuleEvent));
    cancel @1 () -> T.VoidResult;
}

# A union with an `unknown` arm. The previous shape had no forward-compat
# variant, so a backend adding "a module crashed its host and was
# quarantined" or "a dependency failed to resolve" had to overload
# `stateChanged` (ai.capnp:533-550 is the template).
struct ModuleEvent {
    union {
        loaded @0 :ModuleState;
        unloaded @1 :T.ModuleId;
        stateChanged @2 :ModuleState;
        failed @3 :ModuleFailure;
        unknown @4 :UnknownModuleEvent;
    }
}

struct UnknownModuleEvent {
    typeId @0 :UInt64;
    payload @1 :Data;
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
    minVersion @1 :T.Version;
    maxVersion @2 :T.Version;
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

# ── Module Event Sourcing ─────────────────────────────────────

struct ModuleEventEntry {
    # Sequence index in the event log.
    index @0 :UInt64;
    # Event type.
    type @1 :Text;
    # Event payload (serialized). Opaque, so event-log replay does not
    # force a schema per event type.
    payload @2 :Data;
    # Timestamp of the event.
    timestamp @3 :T.Timestamp;
}

# ── Module Profile ────────────────────────────────────────────
#
# `topFunctions :List(ModuleFunctionProfile)` was DELETED. Per-function
# profiling presupposes a compiled language with a symbol table, which
# DESIGN_PRINCIPLES.md:228 already rejects for exactly this reason
# ("WASM, interpreted, and JIT languages don't have this"): a
# transpiled, JIT-compiled or interpreted module has no stable function
# names, so the field was unanswerable — and it was also the one list in
# the file that grows without bound with module complexity.
struct ModuleProfile {
    # Identifier of the module profiled.
    moduleId @0 :T.ModuleId;
    # Duration the profile covers.
    duration @1 :T.Duration;
    # Memory used over the profile window, in bytes.
    memoryBytes @2 :UInt64;
    # CPU time consumed.
    cpuTime @3 :T.Duration;
    # Number of events processed.
    eventCount @4 :UInt64;
}

# ── Module Marketplace / Feature Flags / Multi-Tenancy — DELETED ─────────
#
# Three blocks removed from this file, all the same class of defect:
# they are PRODUCT decisions, not the contract between a module and its
# host. The Agnostic/Timeless Test's litmus #2 (DESIGN_PRINCIPLES.md:110)
# is "does a consumer need this to interoperate with a provider?" — and
# no consumer needs a download count, a star rating, an A/B rollout
# percentage or a tenant cap in order to load a module.
#
#   * `ModuleMarketplaceQuery/Result` with download counts and ratings,
#     plus `searchMarketplace` / `installFromMarketplace`: repository
#     search is package.capnp's job, and `installFromMarketplace` also
#     bypassed the signature verification that `LoadSpec.verifySignature`
#     exists to provide on the load path.
#   * `ModuleFeatureFlag` with a percentage-of-users rollout: an
#     internal product mechanism (the class DESIGN_PRINCIPLES.md:64
#     rejects — "Add CFS scheduler tuning knobs | KEEPS OUT"). A 2046
#     module with no user population has no percentage.
#   * `ModuleTenancyConfig` with maxTenants/isolatedState/isolatedMemory:
#     a hosting-product concern with no interoperability content.
#
# A 2046 loader that is not marketplace-shaped (a firmware image, a
# signed in-tree module, a peer fetch) had no representation before; it
# has one now.

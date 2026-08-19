@0xa1b2c3d4e5f6003b;

# ═══════════════════════════════════════════════════════════════════════
# Init - userspace bootstrap and lifecycle
#
# After kernel hand-off, init takes the stage. Init decides which services
# to bring up first, in what dependency order, with what authority grant.
# Init's contract is observable: apps learn lifecycle from it.
#
# Improvements (audit-3):
#   - listServices paginated with T.Pagination (Rule 9).
#   - Service-level pull marked deprecated — prefer subscription.pull() (Rule 7).
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "manifest.capnp".Manifest;
using import "manifest.capnp".ManifestService;

struct InitState {
    phase @0 :Phase;
    startedAt @1 :T.Timestamp;
    lastTransition @2 :T.Timestamp;
    activeServices @3 :List(T.ProcessId);
    pendingStart @4 :List(T.ServiceName);
    failedStarts @5 :List(StartupFailure);
}

enum Phase {
    fresh @0;
    preServices @1;
    earlyServices @2;
    coreServices @3;
    userServices @4;
    sessions @5;
    user @6;
    shutdown @7;
    offline @8;
    custom @9;
}

struct StartupFailure {
    serviceName @0 :T.ServiceName;
    reason @1 :T.Error;
    attempts @2 :UInt32;
    fatal @3 :Bool;
    timestamp @4 :T.Timestamp;
}

struct ServiceSpec {
    # Manifest name to dispatch.
    manifest @0 :T.ManifestName;
    # Optional dependency list (other service manifests).
    depends @1 :List(T.ServiceName);
    # Whether the service is critical (init retries).
    critical @2 :Bool;
    # Auto-restart policy.
    onFailure @3 :RestartPolicy;
    # User-scope visibility (visible from login session contexts).
    userVisible @4 :Bool = true;
    # Optional authority header for the service.
    authority @5 :Text;
    isolation @6 :T.IsolatedScope;
    quota @7 :T.Quota;
}

enum RestartPolicy {
    none @0;
    onFailure @1;
    always @2;
    onSuccessAfterFailure @3;
    custom @4;
}

struct LifecycleHook {
    name @0 :Text;
    whenPhase @1 :Phase;
    request @2 :LifecycleRequest;
}

struct LifecycleRequest {
    type @0 :RequestType;
    target @1 :T.ServiceName;
    payload @2 :Data;
}

enum RequestType {
    start @0;
    stop @1;
    restart @2;
    suspend @3;
    resume @4;
    freeze @5;
    thaw @6;
    custom @7;
}

interface InitService {
    # Start a service by name (or already-present descriptor).
    start @0 (spec :ServiceSpec) -> (task :T.ProcessId);
    # Stop a service.
    stop @1 (name :T.ServiceName, killTimeout :T.Duration) -> (result :T.VoidResult);
    # Restart a service.
    restart @2 (name :T.ServiceName) -> (result :T.VoidResult);
    # List declared service specs.
    listServices @3 (page :T.Pagination) -> (specs :List(ServiceSpec));
    # Get current init state.
    state @4 () -> (state :InitState);
    # Install a hook that fires on phase transitions.
    installHook @5 (hook :LifecycleHook) -> (id :T.HookId);
    # Remove an installed hook.
    removeHook @6 (id :T.HookId) -> (result :T.VoidResult);
    # Subscribe to lifecycle events.
    subscribe @7 () -> (subscription :InitSubscription);
    # Deprecated: use subscription.pull() instead. Kept for backward compatibility.
    pull @8 (subscription :InitSubscription) -> (events :List(InitEvent));
    # Resolve a service to its process id.
    resolveService @9 (name :T.ServiceName) -> (task :T.ProcessId);
    # Provide the manifest service for app manifest queries.
    manifests @10 () -> (service :ManifestService);
    # Trigger a transition to next phase.
    advancePhase @11 (next :Phase) -> (result :T.VoidResult);
    # Trigger a shutdown (clean or immediate).
    shutdown @12 (clean :Bool) -> (result :T.VoidResult);

    # Respawn a service after crash.
    respawn @13 (name :T.ServiceName) -> T.VoidResult;

    # Set isolation scope for init.
    setQuarantine @14 (scope :T.IsolatedScope) -> T.VoidResult;

    # List isolation boundaries.
    listIsolation @15 (page :T.Pagination) -> (scopes :List(T.IsolatedScope), total :UInt32);

    # Audit-5: Service Supervisor (Respawn)
    registerService @16 (name :Text, channelIndex :UInt16, critical :Bool, respawnPolicy :UInt8) -> (handle :UInt64);
    unregisterService @17 (handle :UInt64) -> (result :T.VoidResult);
    serviceHeartbeat @18 (handle :UInt64) -> (result :T.VoidResult);
    respawnService @19 (handle :UInt64, report :Data) -> (result :T.VoidResult);
    listSupervisedServices @20 () -> (services :List(SupervisedService));
    setServicePolicy @21 (handle :UInt64, policy :UInt8) -> (result :T.VoidResult);
}

# ═══════════════════════════════════════════════════════════════════════
# ServiceSupervisor — compile-time restart graph + typed fallback
#
# init implements this interface. Services register/unregister
# through it. On service death, init's supervisor decides restart
# based on the compile-time RESTART_GRAPH (from services.toml).
# ═══════════════════════════════════════════════════════════════════════

interface ServiceSupervisor {
    # Register a service for supervision. Returns a handle.
    register @0 (service :SupervisedService) -> (handle :UInt64);
    # Unregister a previously registered service.
    unregister @1 (handle :UInt64) -> (result :T.VoidResult);
    # Force-respawn a service by handle (used by HAL device respawn).
    respawn @2 (handle :UInt64, report :T.FailureReport) -> (result :T.VoidResult);
    # List all currently supervised services.
    list @3 () -> (services :List(SupervisedService));
    # Change the restart policy for a supervised service.
    setPolicy @4 (handle :UInt64, policy :T.RestartPolicy) -> (result :T.VoidResult);
    # Subscribe to death events for a specific service.
    subscribeDeath @5 (handle :UInt64, channelId :UInt32) -> (subscriptionHandle :UInt64);
}

# ═══════════════════════════════════════════════════════════════════════
# RuntimeRegistry — append new service providers at runtime
#
# Runtime registration appends to a bounded (compile-time) array.
# No new code paths — the event loop handles registered services
# identically to baked-in services from services.toml.
# ═══════════════════════════════════════════════════════════════════════

interface RuntimeRegistry {
    # Register a new contract provider at runtime.
    register @0 (name :Text, path :Text, policy :T.RestartPolicy) -> (handle :UInt64);
    # Unregister a runtime-registered provider.
    unregister @1 (handle :UInt64) -> (result :T.VoidResult);
    # List all runtime-registered providers.
    list @2 () -> (services :List(SupervisedService));
}

struct InitEvent {
    union {
        phaseChanged @0 :InitState;
        serviceStarted @1 :StartedService;
        serviceStopped @2 :StoppedService;
        hookFired @3 :LifecycleHook;
        hookFailed @4 :HookFailure;
    }
}

struct StartedService {
    name @0 :T.ServiceName;
    task @1 :T.ProcessId;
    at @2 :T.Timestamp;
}

struct StoppedService {
    name @0 :T.ServiceName;
    task @1 :T.ProcessId;
    exitStatus @2 :T.ExitStatus;
    reason @3 :T.Error;
}

struct HookFailure {
    hookId @0 :T.HookId;
    reason @1 :T.Error;
}

# ── Supervised Service ──────────────────────────────────────
# Status of a service under init supervision (restart graph).
# The spec defines: name, path, policy, state. Additional fields
# are backward-compatible extensions.

struct SupervisedService {
    # Service name (matches services.toml key).
    name @0 :Text;
    # Path to the service binary.
    path @1 :Text;
    # Restart policy (from services.toml / compile-time table).
    policy @2 :T.RestartPolicy;
    # Current lifecycle state.
    state @3 :UInt8;
    # Supervisor-assigned opaque handle (legacy field, kept for wire compat).
    handle @4 :UInt64;
    # Channel index in the boot manifest.
    channelIndex @5 :UInt16;
    # Whether the service is critical (init restarts it).
    critical @6 :Bool;
    # Number of respawn attempts since last healthy run.
    attemptCount @7 :UInt32;
    # Whether a fallback function is active.
    fallbackActive @8 :Bool;
    # Process ID of the running service instance.
    pid @9 :UInt64;
    # Uptime since last start in nanoseconds.
    uptimeNs @10 :UInt64;
    # Serialized failure report from last crash (if any).
    lastFailure @11 :Data;
}

interface InitSubscription {
    pull @0 () -> (events :List(InitEvent));
    cancel @1 () -> T.VoidResult;
}

@0xa1b2c3d4e5f6003b;

# ═══════════════════════════════════════════════════════════════════════
# Init — userspace bootstrap and observable service lifecycle.
#
# After the kernel handoff, init takes the stage. Init decides which
# services to bring up first, in what dependency order, with what
# authority grant. Init's contract is OBSERVABLE: apps learn lifecycle
# from it. How init resolves a dependency graph, in what order it
# parallelises, and what it does on failure are its business
# (DESIGN_PRINCIPLES.md:103, TIMELESSNESS.md:88).
#
# ── WHAT WAS DELETED, AND WHY ──────────────────────────────────────────
#
#   * the local `RestartPolicy` enum (`none`, `onFailure`,
#     `onSuccessAfterFailure`) — a second, contradictory restart grammar
#     beside the canonical `T.RestartPolicy` (`always`, `onFailure`,
#     `never`) that the same file used in `ServiceSupervisor.setPolicy`.
#     Two vocabularies in one schema is a fork baked in: a backend had to
#     decide what `onSuccessAfterFailure` maps to when the canonical enum
#     says there are three policies. `T.RestartPolicy` is now the only
#     one; the `onSuccessAfterFailure` refinement is expressible as
#     `always` plus a lifecycle hook.
#   * `ServiceSupervisor` and `RuntimeRegistry` as separate interfaces —
#     no method in the protocol returned either (R8), so nothing could
#     obtain them. Supervision is now part of `InitService`, keyed by
#     service id: one identity, one path.
#   * `ServiceSpec.authority :Text` — a free-text "authority header" is
#     the per-method authority token the doctrine abolished. The
#     authority a service gets is the reference init hands it.
#   * raw `UInt8` policy and state codes and raw `UInt64` pids —
#     `T.RestartPolicy`, `T.ProcessId`, `T.EntityState`,
#     `T.FailureReport` all exist and were used by the file's other half.
#   * `SupervisedService.handle :UInt64` and `channelIndex :UInt16` —
#     a second identity for a service the file already names, and a boot
#     manifest internal.
#   * `subscribeDeath` — death observation is process.capnp's
#     `subscribeDeath` over an ExitNotificationSubscription.
#
# Service CONTROL (start/stop/restart) lives HERE and only here.
# service.capnp is the observation contract and no longer duplicates it;
# discovery.capnp is the registration contract. Three service-control
# authorities became one.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using import "manifest.capnp".ManifestService;

struct InitState {
    phase @0 :Phase;
    startedAt @1 :T.Timestamp;
    lastTransition @2 :T.Timestamp;
    # Processes init currently owns.
    activeServices @3 :List(T.ProcessId);
    # Services declared but not yet started.
    pendingStart @4 :List(T.ServiceId);
    # Failures recorded during this boot, in order.
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
    serviceId @0 :T.ServiceId;
    reason @1 :T.Error;
    attempts @2 :UInt32;
    fatal @3 :Bool;
    timestamp @4 :T.Timestamp;
}

struct ServiceSpec {
    # Manifest to dispatch.
    manifest @0 :T.ManifestName;
    # Optional dependency list (other services).
    depends @1 :List(T.ServiceId);
    # Whether the service is critical (init retries).
    critical @2 :Bool;
    # Restart policy, canonical.
    onFailure @3 :T.RestartPolicy;
    # User-scope visibility (visible from login session contexts).
    userVisible @4 :Bool = true;
    # Declared isolation boundary.
    isolation @5 :T.IsolatedScope;
    # Declared quota.
    quota @6 :T.Quota;
    # Open metadata the backend understands.
}

struct LifecycleHook {
    name @0 :Text;
    whenPhase @1 :Phase;
    request @2 :LifecycleRequest;
}

struct LifecycleRequest {
    type @0 :RequestType;
    target @1 :T.ServiceId;
    # Hook payload, zero-copy.
    payload @2 :T.DataHandle;
    metadata @3 :T.StringMap;
}

enum RequestType {
    unknown @0;
    start @1;
    stop @2;
    restart @3;
    suspend @4;
    resume @5;
    freeze @6;
    thaw @7;
    custom @8;
}

# ── The init contract ───────────────────────────────────────────────────
# The root of the service-lifecycle domain: handed to the caller by the
# host, so it is deliberately not returned by any method.

interface InitService {
    # Start a service by spec.
    start @0 (spec :ServiceSpec) -> (task :T.ProcessId);
    # Stop a service. `killTimeout` is how long init waits for a clean
    # exit before escalating (zero = backend default).
    stop @1 (name :T.ServiceId, killTimeout :T.Duration) -> (result :T.VoidResult);
    # Restart a service.
    restart @2 (name :T.ServiceId) -> (result :T.VoidResult);
    # List declared service specs.
    listServices @3 (page :T.Pagination) -> (specs :List(ServiceSpec), total :UInt64);
    # Get current init state.
    state @4 () -> (state :InitState);
    # Install a hook that fires on phase transitions.
    installHook @5 (hook :LifecycleHook) -> (id :T.HookId);
    # Remove an installed hook.
    removeHook @6 (id :T.HookId) -> (result :T.VoidResult);
    # Subscribe to lifecycle events. Holding the subscription IS the
    # authority to pull.
    subscribe @7 () -> (subscription :InitSubscription);
    # Resolve a service to its process id (zero = not running).
    resolveService @8 (name :T.ServiceId) -> (task :T.ProcessId);
    # Provide the manifest service for app manifest queries.
    manifests @9 () -> (service :ManifestService);
    # Trigger a transition to the next phase.
    advancePhase @10 (next :Phase) -> (result :T.VoidResult);
    # Trigger a shutdown (clean or immediate).
    shutdown @11 (clean :Bool) -> (result :T.VoidResult);
    # Respawn a service after a crash.
    respawn @12 (name :T.ServiceId) -> T.VoidResult;
    # Set isolation scope for init.
    setQuarantine @13 (scope :T.IsolatedScope) -> T.VoidResult;
    # List declared isolation boundaries.
    listIsolation @14 (page :T.Pagination) -> (scopes :List(T.IsolatedScope), total :UInt32);

    # ── Supervision, keyed by service id ───────────────────────
    # The pre-revamp ServiceSupervisor/RuntimeRegistry interfaces were
    # unreachable; supervision is part of this contract now.
    #
    # A heartbeat that does not arrive within the service's policy window
    # is treated as a failure and counted against the restart policy.
    # A service that has never heartbeaten is not failed for it —
    # `lastHeartbeatAt` stays zero and the backend reports so.
    supervise @15 (name :T.ServiceId, policy :T.RestartPolicy) -> T.VoidResult;
    stopSupervising @16 (name :T.ServiceId) -> T.VoidResult;
    heartbeat @17 (name :T.ServiceId) -> T.VoidResult;
    respawnSupervised @18 (name :T.ServiceId, report :T.FailureReport) -> (result :T.VoidResult);
    setServicePolicy @19 (name :T.ServiceId, policy :T.RestartPolicy) -> (result :T.VoidResult);
    listSupervised @20 (page :T.Pagination) -> (services :List(SupervisedService), total :UInt64);
}

struct InitEvent {
    union {
        phaseChanged @0 :InitState;
        serviceStarted @1 :StartedService;
        serviceStopped @2 :StoppedService;
        hookFired @3 :LifecycleHook;
        hookFailed @4 :HookFailure;
        # A supervised service was respawned or gave up.
        supervisionChanged @5 :SupervisionChange;
        unknown @6 :T.UnknownEvent;
    }
}

struct StartedService {
    serviceId @0 :T.ServiceId;
    task @1 :T.ProcessId;
    at @2 :T.Timestamp;
}

struct StoppedService {
    serviceId @0 :T.ServiceId;
    task @1 :T.ProcessId;
    exitStatus @2 :T.ExitStatus;
    reason @3 :T.Error;
}

struct HookFailure {
    hookId @0 :T.HookId;
    reason @1 :T.Error;
}

struct SupervisionChange {
    serviceId @0 :T.ServiceId;
    state @1 :T.EntityState;
    attempts @2 :UInt32;
    # Why the supervisor acted, as an open token.
    reason @3 :Text;
    metadata @4 :T.StringMap;
}

interface InitSubscription {
    # Bounded pull: the caller states how many events it will take.
    pull @0 (maxEvents :UInt32) -> (events :List(InitEvent), total :UInt64);
    cancel @1 () -> T.VoidResult;
}

# ── Supervised service ──────────────────────────────────────────────────
# Status of a service under init supervision. `state` is the canonical
# T.EntityState; the pre-revamp raw UInt8 code is gone.

struct SupervisedService {
    serviceId @0 :T.ServiceId;
    # Restart policy in force.
    policy @1 :T.RestartPolicy;
    # Current lifecycle state.
    state @2 :T.EntityState;
    # Whether the service is critical (init restarts it).
    critical @3 :Bool;
    # Respawn attempts since the last healthy run.
    attemptCount @4 :UInt32;
    # Whether a fallback path is currently active.
    fallbackActive @5 :Bool;
    # Process id of the running instance (zero = not running).
    pid @6 :T.ProcessId;
    # Uptime since last start.
    uptime @7 :T.Duration;
    # The failure that triggered the most recent respawn, if any.
    lastFailure @8 :T.FailureReport;
    # When the last heartbeat arrived (zero = never).
    lastHeartbeatAt @9 :T.Timestamp;
    metadata @10 :T.StringMap;
}

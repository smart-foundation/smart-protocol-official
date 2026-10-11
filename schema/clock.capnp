@0xa1b2c3d4e5f60040;

# ═══════════════════════════════════════════════════════════════════════
# Clock — time sources and timer primitives.
#
# Improvements beyond the original schema (audit):
#   - TimerSpec.clockDomain clarifies anchor (monotonic vs realtime).
#   - TimerEvent.count changed to UInt64 (UInt32 overflows at 4B).
#   - cancelTimer returns VoidResult (typed error, not ad-hoc reason text).
#   - resetTimer returns the updated TimerHandle.
#   - ClockInfo.bootTime for uptime-based correlation.
#   - TimerSubscription now has cancel method for explicit teardown.
#   - CancelResult uses T.VoidResult for consistency.
#
# Revamp verdict: KEEP — this file is the canonical home for timers and
# alarms (its alarm model is strictly richer than the duplicate time.capnp
# carried, which is now deleted). Four small honesty fixes:
#   - `AlarmService` is reachable: it is returned by a gated accessor on
#     ClockService, per the ai.capnp precedent (present a capability,
#     receive the service, hold the reference as the authority).
#   - `TimerAnchor` carries a `custom` variant, closing the one E6 gap:
#     an absent anchor must not silently mean "absolute".
#   - `listAlarms` and `listPersistedTimers` are paginated.
#   - `checkTimer` is documented as the sanctioned poll path beside
#     `subscribeTimers`, so a backend is not free to optimize only for
#     the poller.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using Cal = import "calendar.capnp";
using import "capability.capnp".Capability;

struct ClockInfo {
    monotonic @0 :T.Timestamp;
    realtime @1 :T.Timestamp;
    resolution @2 :T.Duration;
    # Backend-provided clock source name (e.g., "tsc", "hpet") as an
    # open token.
    sourceName @3 :Text;
    # Time since last boot (monotonic base for uptime correlation).
    bootTime @4 :T.Timestamp;
    # Audit-7: NTP/PTP synchronization status.
    sync @5 :ClockSyncInfo;
    # Audit-7: tamper detection status.
    security @6 :ClockSecurityInfo;
    # Audit-7: available clock domains.
    domains @7 :List(ClockDomainInfo);
    metadata @8 :T.StringMap;
}

# Audit-7: clock domain information.
struct ClockDomainInfo {
    # The clock domain.
    domain @0 :ClockDomain;
    # Human-readable name.
    name @1 :Text;
    # Timer resolution for this domain.
    resolution @2 :T.Duration;
    # Whether this domain is available.
    available @3 :Bool;
    metadata @4 :T.StringMap;
}

# Audit-7: NTP/PTP synchronization status.
struct ClockSyncInfo {
    # Whether the clock is currently synchronized.
    synced @0 :Bool;
    # Sync source name (e.g., "ntp.pool.org", "ptp-local").
    source @1 :Text;
    # NTP stratum (1 = directly connected to reference, higher = less accurate).
    stratum @2 :UInt32;
    # When the last synchronization occurred.
    lastSync @3 :T.Timestamp;
    # Current offset from reference time.
    offset @4 :T.Duration;
    metadata @5 :T.StringMap;
}

# Audit-7: clock security information.
struct ClockSecurityInfo {
    # Whether tampering has been detected.
    tampered @0 :Bool;
    # Whether a hardware-secured time source is available.
    secureSource @1 :Bool;
    # Whether hardware RNG is available for time jitter.
    hardwareRng @2 :Bool;
}

struct TimerSpec {
    # Anchor timestamp. Meaning of zero: relative from now.
    anchor @0 :T.Timestamp;
    # Interval for periodic timers. Zero = one-shot.
    interval @1 :T.Duration;
    coalesceMissed @2 :Bool = true;
    label @3 :Text;
    # Which clock the anchor is expressed in.
    clockDomain @4 :ClockDomain = realtime;
    # Audit-7: explicit anchor type (absolute, relative, zero).
    anchorType @5 :TimerAnchor;
    # Audit-7: timer group membership (for bulk operations).
    group @6 :Text;
    # Audit-7: timer priority (higher = fires first).
    priority @7 :UInt32;
    metadata @8 :T.StringMap;
}

# Audit-7: explicit timer anchor type replacing implicit T.Timestamp.
struct TimerAnchor {
    union {
        # Anchor at an absolute timestamp.
        absolute @0 :T.Timestamp;
        # Anchor relative to now (duration from now).
        relative @1 :T.Duration;
        # Anchor at zero (from now, equivalent to old behavior).
        zero @2 :Void;
        # Forward-compatibility slot for an anchor semantics this schema
        # does not name. Without it, an old consumer reading a producer's
        # new anchor kind would fire at epoch-0 or never.
        custom @3 :Data;
    }
}

enum ClockDomain {
    # Anchor is wall-clock time.
    realtime @0;
    # Anchor is relative to monotonic boot base.
    monotonic @1;
    custom @2;
}

interface ClockService {
    info @0 () -> (info :ClockInfo);
    monotonicNow @1 () -> (time :T.Timestamp);
    realtimeNow @2 () -> (time :T.Timestamp);

    createTimer @3 (spec :TimerSpec) -> (timer :TimerHandle);

    cancelTimer @4 (timer :TimerHandle) -> T.VoidResult;
    resetTimer @5 (timer :TimerHandle, spec :TimerSpec) -> (timer :TimerHandle);

    # Point check: did this timer fire? The sanctioned poll path, and
    # the only one — a consumer that needs a stream of firings uses
    # `subscribeTimers` (@7), which is pull + cancel. Backends may
    # optimize for either; they may not support only the poller and
    # leave the subscription unimplemented.
    checkTimer @6 (timer :TimerHandle) -> (fired :Bool);

    subscribeTimers @7 (filter :TimerFilter) -> (subscription :TimerSubscription);

    sleep @8 (duration :T.Duration) -> T.VoidResult;

    # Audit-7: query available clock domains.
    listClockDomains @9 () -> (domains :List(ClockDomainInfo));

    # Audit-7: cancellable sleep with handle.
    sleepCancellable @10 (duration :T.Duration) -> (handle :SleepHandle);

    # Audit-7: get NTP/PTP synchronization status.
    getClockSync @11 () -> (sync :ClockSyncInfo);

    # Audit-7: measure clock drift between two domains.
    getClockDrift @12 (domain1 :ClockDomain, domain2 :ClockDomain) -> (drift :ClockDriftInfo);

    # Audit-10: create a virtual clock for testing.
    createVirtualClock @13 (config :VirtualClockConfig) -> (clock :VirtualClockHandle);

    # Audit-10: advance a virtual clock by a duration.
    advanceVirtualClock @14 (clock :VirtualClockHandle, duration :T.Duration) -> (time :T.Timestamp);

    # Audit-10: get clock quality metrics for a clock source.
    getClockQuality @15 (sourceName :Text) -> (quality :ClockQualityMetrics);

    # Audit-10: persist a timer so it survives process exit.
    persistTimer @16 (timer :TimerHandle, persistence :TimerPersistence) -> T.VoidResult;

    # Audit-10: list persisted timers (survived process exit).
    listPersistedTimers @17 (pagination :T.Pagination) -> (timers :List(TimerHandle), totalCount :UInt64);

    # Audit-10: set dependency ordering between timers.
    #
    # SEMANTICS, stated: the dependent timer does not fire while
    # `dependsOn` has not fired at least once since the dependent was
    # armed — it is GATED, not chained. Firing `dependsOn` does not arm
    # the dependent, and cancelling `dependsOn` leaves the dependent
    # waiting (it is not cancelled). Without this sentence every
    # implementer picks a different rule.
    setTimerDependency @18 (timer :TimerHandle, dependsOn :TimerHandle) -> T.VoidResult;

    # ── Alarms ──
    # The canonical alarm home (time.capnp's duplicate alarm store is
    # deleted). Present a capability to acquire the service; holding the
    # returned reference IS the authority to schedule an alarm — there is
    # no per-method token inside AlarmService.
    alarms @19 (authority :Capability) -> (service :AlarmService);
}

# Audit-7: cancellable sleep handle.
struct SleepHandle {
    # Opaque handle for cancelling the sleep.
    id @0 :UInt64;
}

# Audit-7: clock drift measurement.
struct ClockDriftInfo {
    # Measured drift between two clock domains.
    drift @0 :T.Duration;
    # When the drift was measured.
    measuredAt @1 :T.Timestamp;
    # Accuracy of the drift measurement.
    accuracy @2 :T.Duration;
}

struct TimerHandle {
    id @0 :T.TimerId;
    label @1 :Text;
    metadata @2 :T.StringMap;
}

struct TimerFilter {
    labels @0 :List(Text);
    metadata @1 :T.StringMap;
}

interface TimerSubscription {
    # Deprecated: use pullPaginated for bounded results.
    pull @0 () -> (events :List(TimerEvent));

    # Explicitly cancel this subscription and release resources.
    cancel @1 () -> T.VoidResult;

    # Paginated pull — returns at most `limit` events starting from `offset`.
    pullPaginated @2 (pagination :T.Pagination) -> (result :TimerPullResult);
}

struct TimerPullResult {
    events    @0 :List(TimerEvent);
    totalCount @1 :UInt32;
    metadata @2 :T.StringMap;
}

struct TimerEvent {
    timer @0 :TimerHandle;
    firedAt @1 :T.Timestamp;
    # How many times this timer fired since last pull (UInt64 to avoid overflow).
    count @2 :UInt64;
    metadata @3 :T.StringMap;
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-9: Alarm Scheduling (clock_alarm)
# Holiday-aware, recurring alarms with snooze and skip logic.
# ═══════════════════════════════════════════════════════════════════════

struct Alarm {
    id @0 :T.AlarmId;
    label @1 :Text;
    fireTime @2 :T.Timestamp;
    # Recurrence rule (null = one-shot alarm).
    recurrence @3 :AlarmRecurrence;
    # Holiday-aware behavior.
    holidayBehavior @4 :HolidayBehavior;
    # How long to snooze before re-firing.
    snoozeDuration @5 :T.Duration;
    # Whether the alarm is enabled.
    enabled @6 :Bool;
    metadata @7 :T.StringMap;
}

struct AlarmRecurrence {
    union {
        # Daily at fireTime.
        daily @0 :Void;
        # Weekly on specific days of week.
        weekly @1 :WeeklyRecurrence;
        # Monthly on a specific day.
        monthly @2 :MonthlyRecurrence;
        # Custom cron-like expression.
        cron @3 :Text;
        custom @4 :Data;
    }
}

struct WeeklyRecurrence {
    # The canonical day-of-week type lives in calendar.capnp; this file
    # no longer declares a second one.
    daysOfWeek @0 :List(Cal.DayOfWeek);
}

struct MonthlyRecurrence {
    dayOfMonth @0 :UInt8;
}


struct HolidayBehavior {
    # What to do when alarm falls on a holiday.
    mode @0 :HolidayMode;
    # Alternative time to fire if mode is adjust.
    adjustedTime @1 :T.Timestamp;
    # List of holiday calendar IDs to check.
    holidayCalendars @2 :List(Text);
    metadata @3 :T.StringMap;
}

enum HolidayMode {
    # Fire normally even on holidays.
    fire @0;
    # Skip the alarm on holidays.
    skip @1;
    # Adjust to a different time on holidays.
    adjust @2;
    # Snooze until next non-holiday.
    snooze @3;
    custom @4;
}

interface AlarmService {
    createAlarm @0 (alarm :Alarm) -> (id :T.AlarmId);
    updateAlarm @1 (alarm :Alarm) -> T.VoidResult;
    deleteAlarm @2 (id :T.AlarmId) -> T.VoidResult;
    getAlarm @3 (id :T.AlarmId) -> (alarm :Alarm);
    listAlarms @4 (pagination :T.Pagination) -> (alarms :List(Alarm), totalCount :UInt64);
    snoozeAlarm @5 (id :T.AlarmId, duration :T.Duration) -> T.VoidResult;
    dismissAlarm @6 (id :T.AlarmId) -> T.VoidResult;
    getNextAlarm @7 () -> (alarm :Alarm);
}

# ═══════════════════════════════════════════════════════════════════════
# Audit-10: Virtual Clocks, Timer Persistence, Timer Dependencies
# ═══════════════════════════════════════════════════════════════════════

# Audit-10: virtual clock configuration for testing.
struct VirtualClockConfig {
    # Initial time for the virtual clock.
    initialTime @0 :T.Timestamp;
    # Clock domain for the virtual clock.
    domain @1 :ClockDomain;
    # Rate multiplier (1.0 = real-time, 2.0 = double speed, 0.0 = paused).
    rate @2 :Float32;
    # Name for debugging.
    name @3 :Text;
    metadata @4 :T.StringMap;
}

# Audit-10: virtual clock handle.
struct VirtualClockHandle {
    id @0 :UInt64;
    name @1 :Text;
    metadata @2 :T.StringMap;
}

# Audit-10: clock quality metrics per source.
struct ClockQualityMetrics {
    # Clock source name.
    sourceName @0 :Text;
    # Accuracy (maximum expected error).
    accuracy @1 :T.Duration;
    # Stability (jitter/variance).
    stability @2 :T.Duration;
    # Reliability (0.0-1.0, proportion of successful syncs).
    reliability @3 :Float32;
    # When these metrics were last measured.
    measuredAt @4 :T.Timestamp;
    # Number of samples used.
    sampleCount @5 :UInt32;
    metadata @6 :T.StringMap;
}

# Audit-10: timer persistence configuration.
struct TimerPersistence {
    # Name for the persisted timer.
    name @0 :Text;
    # Whether to re-fire on process restart.
    reFireOnRestart @1 :Bool;
    # Maximum number of re-fires (0 = unlimited).
    maxReFires @2 :UInt32;
    metadata @3 :T.StringMap;
}

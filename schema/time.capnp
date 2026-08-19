@0xa1b2c3d4e5f6001e;

using T = import "types.capnp";

interface Time {
    getDateTime @0 () -> (dateTime :DateTime);
    getTimeZone @1 () -> (timeZone :TimeZone);
    setTimeZone @2 (zoneId :Text) -> T.VoidResult;

    getAlarm @3 (alarmId :T.AlarmId) -> (alarm :Alarm);
    setAlarm @4 (alarm :Alarm) -> (alarmId :T.AlarmId);
    cancelAlarm @5 (alarmId :T.AlarmId) -> T.VoidResult;
    listAlarms @6 (pagination :T.Pagination) -> (alarms :List(Alarm), total :UInt64);

    subscribeTimer @7 (interval :T.Duration) -> (subscription :TimerSubscription);
    pullTimer @8 (subscription :TimerSubscription) -> (timestamp :T.Timestamp);
    cancelTimer @9 (subscription :TimerSubscription) -> T.VoidResult;

    getUpcoming @10 (duration :T.Duration) -> (events :List(TimeEvent));

    # Paginated version of getUpcoming for large time ranges.
    # The original getUpcoming (ordinal @10) returns unbounded results
    # for wire-format compatibility. This method adds pagination support
    # for callers that need bounded result sets.
    getUpcomingPaged @11 (duration :T.Duration, pagination :T.Pagination)
                     -> (events :List(TimeEvent), total :UInt64);

    # Audit-8: Get leap second table for UTC-SI conversion.
    getLeapSecondTable @12 () -> (table :LeapSecondTable);

    # Audit-8: Convert TAI timestamp to UTC using leap second table.
    taiToUtc @13 (tai :TAITimestamp) -> (utc :T.Timestamp);

    # Audit-8: Convert UTC timestamp to TAI.
    utcToTai @14 (utc :T.Timestamp) -> (tai :TAITimestamp);

    # Audit-8: Get current monotonic time (immune to clock adjustments).
    getMonotonicTime @15 () -> (timestamp :T.MonotonicTimestamp);

    # Audit-8: Get clock source quality metrics.
    getClockSource @16 () -> (source :ClockSource);

    # Audit-8: Get business hours for a timezone.
    getBusinessHours @17 (timezoneId :Text) -> (hours :BusinessHours);

    # Audit-8: Get next business day given a date.
    getNextBusinessDay @18 (date :T.Date, timezoneId :Text) -> (nextDay :T.Date);

    # Audit-8: Format duration as human-readable string.
    formatDuration @19 (duration :T.Duration, locale :Text) -> (formatted :Text);

    # Audit-8: Parse human-readable duration string.
    parseDuration @20 (text :Text) -> (duration :T.Duration);

    # Audit-8: Get alarm snooze policy.
    getAlarmSnoozePolicy @21 (alarmId :T.AlarmId) -> (policy :AlarmSnoozePolicy);

    # Audit-8: Set alarm snooze policy.
    setAlarmSnoozePolicy @22 (alarmId :T.AlarmId, policy :AlarmSnoozePolicy) -> T.VoidResult;

    # Audit-9: business hour convenience methods.
    isBusinessHour @23 (time :T.Timestamp, timezoneId :Text) -> (isOpen :Bool);
    nextBusinessHour @24 (time :T.Timestamp, timezoneId :Text) -> (nextOpen :T.Timestamp);

    # Audit-9: leap second subscription.
    subscribeLeapSecond @25 () -> (subscription :LeapSecondSubscription);

    # Audit-9: HSM timestamp verification.
    verifyHsmTimestamp @26 (hsm :HSMTimestamp) -> (verified :Bool, message :Text);

    # Audit-9: relative alarm (e.g., "remind me in 2 hours from when I finish this task").
    setRelativeAlarm @27 (baseEvent :Text, delay :T.Duration) -> (alarmId :T.AlarmId);

    # Audit-9: calendar system conversion.
    convertCalendar @28 (date :HistoricalDate, fromSystem :CalendarSystem, toSystem :CalendarSystem) -> (converted :HistoricalDate);

    # Audit-9: duration humanization with context.
    humanizeDuration @29 (duration :T.Duration, locale :Text, context :DurationContext) -> (humanized :Text);

    # Audit-10: duration humanization with approximations.
    humanizeDurationApprox @30 (duration :T.Duration, locale :Text, context :DurationContext, precision :ApproximationPrecision) -> (humanized :Text);

    # Audit-10: calendar arithmetic.
    addCalendarUnits @31 (date :HistoricalDate, units :List(CalendarUnit)) -> (result :HistoricalDate);
    subtractCalendarUnits @32 (date :HistoricalDate, units :List(CalendarUnit)) -> (result :HistoricalDate);
    diffCalendarDates @33 (date1 :HistoricalDate, date2 :HistoricalDate) -> (diff :CalendarDiff);
}

enum DurationContext {
    relativePast @0;   # "3 days ago"
    relativeFuture @1; # "in about 2 hours"
    absolute @2;      # "3 days, 2 hours"
    custom @3;
}

struct RelativeAlarm {
    alarmId @0 :T.AlarmId;
    baseEvent @1 :Text;
    delay @2 :T.Duration;
    message @3 :Text;
    createdAt @4 :T.Timestamp;
}

interface TimerSubscription {
    pull @0 () -> (timestamp :T.Timestamp);
    cancel @1 () -> T.VoidResult;
}

interface LeapSecondSubscription {
    pull @0 () -> (announcement :LeapSecondAnnouncement);
    cancel @1 () -> T.VoidResult;
}

struct LeapSecondAnnouncement {
    scheduledDate @0 :T.Date;
    offset @1 :UInt16;
    positive @2 :Bool;
    timestamp @3 :T.Timestamp;
}

struct DateTime {
    year @0 :Int32;
    month @1 :UInt8;
    day @2 :UInt8;
    hour @3 :UInt8;
    minute @4 :UInt8;
    second @5 :UInt8;
    millisecond @6 :UInt16;
    weekday @7 :UInt8;
    yearday @8 :UInt16;
    timezone @9 :Text;
    utcOffsetSeconds @10 :Int32;
}

struct TimeZone {
    id @0 :Text;
    displayName @1 :Text;
    abbr @2 :Text;
    utcOffsetSeconds @3 :Int32;
    isDst @4 :Bool;
}

struct Alarm {
    id @0 :T.AlarmId;
    time @1 :AlarmTime;
    message @2 :Text;
    # Sound identifier. Implementations should use a URI or typed
    # SoundId for cross-schema references, but the protocol accepts
    # free-text for maximum flexibility across backends.
    sound @3 :Text;
    enabled @4 :Bool;
    repeats @5 :Bool;
    snoozes @6 :UInt32;
    action @7 :AlarmAction;
    # Audit-9: timezone-aware alarm configuration.
    timezoneAware @8 :TimezoneAwareAlarm;
}

struct AlarmTime {
    hour @0 :UInt8;
    minute @1 :UInt8;
    second @2 :UInt8;
    # -1 means "any" (match all values for this field).
    # A union (specific / any) would be clearer but would break
    # wire format. Documented here for implementers.
    dayOfMonth @3 :Int32;
    month @4 :Int32;
}

enum AlarmAction {
    notification @0;
    sound @1;
    snooze @2;
    powerOn @3;
    custom @4;
}

struct TimeEvent {
    timestamp @0 :T.Timestamp;
    type @1 :TimeEventType;
    # Free-text payload. Implementations should treat this as an opaque
    # string; no structured data schema is enforced by the protocol.
    data @2 :Text;
}

enum TimeEventType {
    second @0;
    minute @1;
    hour @2;
    day @3;
    week @4;
    alarm @5;
    timer @6;
    custom @7;
}

# ── Leap Second Support ───────────────────────────────────────────────

struct LeapSecondTable {
    # List of known leap seconds.
    entries @0 :List(LeapSecondEntry);
    # When this table was last updated.
    lastUpdated @1 :T.Timestamp;
    # Current TAI-UTC offset in seconds (currently 37 as of 2024).
    currentOffset @2 :UInt16;
}

struct LeapSecondEntry {
    # Date when the leap second was applied.
    date @0 :T.Date;
    # Cumulative TAI-UTC offset after this leap second.
    offset @1 :UInt16;
    # Whether this was a positive or negative leap second.
    positive @2 :Bool;
}

# ── TAI Timestamp ─────────────────────────────────────────────────────

struct TAITimestamp {
    # TAI seconds since epoch (1958-01-01).
    seconds @0 :UInt64;
    # Subsecond precision in nanoseconds.
    subsecondNanoseconds @1 :UInt32;
}

# ── Monotonic Clock ───────────────────────────────────────────────────

struct MonotonicClockInfo {
    # Current monotonic timestamp (immune to clock adjustments).
    timestamp @0 :T.MonotonicTimestamp;
    # Resolution of the monotonic clock (nanoseconds).
    resolution @1 :UInt32;
    # Whether the monotonic clock is available.
    available @2 :Bool;
}

# ── Clock Source ───────────────────────────────────────────────────────

struct ClockSource {
    # Name of the clock source (e.g., "NTP", "PTP", "GPS").
    name @0 :Text;
    # Type of clock source.
    type @1 :ClockSourceType;
    # Stratum level (for NTP: 0=atomic, 1=primary, etc.).
    stratum @2 :UInt32;
    # Current offset from true time.
    offset @3 :T.Duration;
    # Jitter (variation in offset).
    jitter @4 :T.Duration;
    # Whether the clock source is currently synchronized.
    synchronized @5 :Bool;
}

enum ClockSourceType {
    ntp      @0;   # Network Time Protocol
    ptp      @1;   # Precision Time Protocol (IEEE 1588)
    gps      @2;   # GPS time
    galileo  @3;   # Galileo navigation system
    atomic   @4;   # Local atomic clock
    custom   @5;   # Backend-specific clock source
}

# ── Business Hours ────────────────────────────────────────────────────

struct BusinessHours {
    # Timezone these business hours apply to.
    timezoneId @0 :Text;
    # Hours per business day.
    hoursPerDay @1 :UInt8;
    # Workdays (1=Monday, 7=Sunday). Empty = all days.
    workdays @2 :List(UInt8);
    # Holidays (dates to skip).
    holidays @3 :List(T.Date);
    # Working hours start (hour 0-23).
    workStartHour @4 :UInt8;
    # Working hours end (hour 0-23).
    workEndHour @5 :UInt8;
}

# ── Alarm Snooze Policy ───────────────────────────────────────────────

struct AlarmSnoozePolicy {
    # Interval between snoozes.
    interval @0 :T.Duration;
    # Maximum number of snoozes allowed. 0 = unlimited.
    maxSnoozes @1 :UInt32;
    # Auto-dismiss after this duration (0 = never).
    autoDismissAfter @2 :T.Duration;
}

# ── Calendar System ───────────────────────────────────────────────────

enum CalendarSystem {
    gregorian @0;   # Gregorian calendar (default)
    julian    @1;   # Julian calendar
    islamic   @2;   # Islamic (Hijri) calendar
    hebrew    @3;   # Hebrew calendar
    chinese   @4;   # Chinese calendar
    ethiopian @5;   # Ethiopian calendar
    custom    @6;   # Backend-specific calendar
}

# ── Historical Date ───────────────────────────────────────────────────

struct HistoricalDate {
    # Year (negative = BCE, 0 = none, positive = CE).
    year @0 :Int64;
    # Month (1-12, 0 = unknown).
    month @1 :UInt8;
    # Day (1-31, 0 = unknown).
    day @2 :UInt8;
    # Calendar system used.
    calendar @3 :CalendarSystem;
}

# ── HSM-Signed Timestamp ──────────────────────────────────────────────

struct HSMTimestamp {
    # The timestamp value.
    timestamp @0 :T.Timestamp;
    # Hardware security module signature over the timestamp.
    signature @1 :T.DataHandle;
    # Certificate chain for the HSM.
    certificateChain @2 :T.DataHandle;
    # HSM identifier.
    hardwareId @3 :Text;
    # Whether the timestamp has been verified.
    verified @4 :Bool;
}

# ── Timezone-Aware Alarm ──────────────────────────────────────────────

struct TimezoneAwareAlarm {
    # Base alarm configuration.
    baseAlarm @0 :Alarm;
    # Timezone ID for the alarm.
    timezoneId @1 :Text;
    # How to resolve the alarm across DST transitions.
    resolvePolicy @2 :DstResolvePolicy;
    # Whether the alarm is recurring.
    recurring @3 :Bool;
    # Recurrence pattern (if recurring).
    recurrence @4 :RecurrencePattern;
}

enum DstResolvePolicy {
    nearest @0;   # Use the nearest valid time
    skip    @1;   # Skip if time doesn't exist
    adjust  @2;   # Adjust to the next valid time
    custom  @3;   # Backend-specific resolution
}

struct RecurrencePattern {
    # Recurrence type.
    type @0 :RecurrenceType;
    # Interval (e.g., every 2 weeks).
    interval @1 :UInt32;
    # Days of week (1=Monday, 7=Sunday). Empty = every day.
    daysOfWeek @2 :List(UInt8);
    # Day of month (1-31, 0 = not used).
    dayOfMonth @3 :UInt8;
    # Month of year (1-12, 0 = not used).
    monthOfYear @4 :UInt8;
    # Whether to skip holidays.
    skipHolidays @5 :Bool;
}

enum RecurrenceType {
    daily   @0;
    weekly  @1;
    monthly @2;
    yearly  @3;
    custom  @4;
}

# ── Audit-10: Approximation Precision ───────────────────────────────────
# Controls how "in about X" style approximations are used in humanized durations.
enum ApproximationPrecision {
    exact @0;        # "3 hours, 12 minutes" — no approximation
    low @1;          # "about 3 hours"
    medium @2;       # "a few hours"
    high @3;         # "several hours"
    auto @4;         # Backend decides based on locale conventions
}

# ── Audit-10: Calendar Arithmetic ──────────────────────────────────────
# Add or subtract calendar units from a date.
struct CalendarUnit {
    kind @0 :CalendarUnitKind;
    amount @1 :Int32;
}

enum CalendarUnitKind {
    days @0;
    weeks @1;
    months @2;
    years @3;
    decades @4;
    centuries @5;
    custom @6;
}

# ── Audit-10: Calendar Date Difference ─────────────────────────────────
# Result of subtracting two calendar dates.
struct CalendarDiff {
    years @0 :Int32;
    months @1 :Int32;
    days @2 :Int32;
    # Total days in the difference (for precision).
    totalDays @3 :Int64;
    # Whether the result is negative (date1 < date2).
    negative @4 :Bool;
}

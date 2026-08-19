@0xa1b2c3d4e5f60100;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Timezone — IANA timezone database operations, DST transitions,
# UTC offset queries, and timestamp conversion between zones.
#
# Zero backend assumptions: no POSIX TZ env, no system zoneinfo
# dependencies. Backend provides IANA tzdb or equivalent.
#
# Used by: calendar.capnp (timezone fields), time.capnp (clock mgmt)
# ═══════════════════════════════════════════════════════════════════════

interface TimezoneService {
    # List all available IANA timezone IDs.
    listTimezones @0 (pagination :T.Pagination) -> (timezones :List(TimezoneInfo), totalCount :UInt32);

    # Get detailed information for a specific timezone.
    getTimezoneInfo @1 (timezoneId :Text) -> (info :TimezoneInfo);

    # Convert a timestamp from one timezone to another.
    # sourceZone and targetZone are IANA timezone IDs.
    # If sourceZone is empty, timestamp is treated as UTC.
    convertTimestamp @2 (timestamp :T.Timestamp, sourceZone :Text, targetZone :Text) -> (result :ConvertResult);

    # Get DST transitions for a timezone within a time range.
    getDstTransitions @3 (timezoneId :Text, range :T.TimeRange) -> (transitions :List(DstTransition));

    # Get current UTC offset for a timezone at a specific timestamp.
    getUtcOffset @4 (timezoneId :Text, at :T.Timestamp) -> (offset :UtcOffset);

    # Get the system's default timezone.
    getDefaultTimezone @5 () -> (timezoneId :Text);

    # Set the system's default timezone (requires privilege).
    setDefaultTimezone @6 (timezoneId :Text) -> T.VoidResult;

    # Search timezones by partial match (e.g., "America/New", "Europe/").
    searchTimezones @7 (query :Text, pagination :T.Pagination) -> (timezones :List(TimezoneInfo), totalCount :UInt32);

    # Subscribe to timezone database updates (tzdb updates, system timezone changes).
    subscribeTimezones @8 () -> (subscription :TimezoneSubscription);

    # Get all timezones that have DST transitions within a given range.
    getTimezonesWithDst @9 (range :T.TimeRange) -> (timezones :List(TimezoneInfo));

    # Get the next N DST transitions for a timezone (for scheduling).
    getNextDstTransitions @10 (timezoneId :Text, count :UInt32) -> (transitions :List(DstTransition));

    # Check if a given timestamp falls in a DST gap (nonexistent time).
    isDstGap @11 (timezoneId :Text, at :T.Timestamp) -> (isGap :Bool, resolvedAt :T.Timestamp);

    # Check if a given timestamp is ambiguous (DST overlap).
    isDstOverlap @12 (timezoneId :Text, at :T.Timestamp) -> (isOverlap :Bool, possibleOffsets :List(UtcOffset));

    # Audit-8: Get leap second database for a timezone.
    # False positive: leap_seconds.capnp belongs here as a feature.
    getLeapSeconds @13 (timezoneId :Text) -> (leapSeconds :List(TimezoneLeapSecond));

    # Audit-8: Create a custom fixed-offset timezone (e.g., UTC+5:45).
    createFixedOffsetTimezone @14 (offsetSeconds :Int32, abbreviation :Text)
        -> (timezoneId :Text);

    # Audit-8: Get abbreviation info for a timezone at a specific time.
    getAbbreviationInfo @15 (timezoneId :Text, at :T.Timestamp)
        -> (info :AbbreviationInfo);

    # Audit-8: Get business hours for a timezone.
    getBusinessHours @16 (timezoneId :Text) -> (hours :TimezoneBusinessHours);

    # Audit-8: Get timezone closest to geographic coordinates.
    getTimezoneForCoordinates @17 (latitude :Float64, longitude :Float64)
        -> (timezoneId :Text, distanceKm :Float32);

    # Audit-8: Get historical UTC offset at a specific date.
    getHistoricalOffset @18 (timezoneId :Text, date :T.Date)
        -> (offset :UtcOffset);

    # Audit-8: List timezones by country code.
    listTimezonesByCountry @19 (countryCode :Text, pagination :T.Pagination)
        -> (timezones :List(TimezoneInfo), totalCount :UInt32);

    # Audit-8: Compare two timezones at a timestamp.
    compareTimezones @20 (timezoneA :Text, timezoneB :Text, at :T.Timestamp)
        -> (result :TimezoneComparison);

    # Audit-8: Resolve a recurring event across DST transitions.
    resolveRecurringEvent @21 (timezoneId :Text, eventHour :UInt8, eventMinute :UInt8,
        dayOfWeek :UInt8, startDate :T.Date, endDate :T.Date)
        -> (occurrences :List(ResolvedEvent));

    # Audit-8: Get the current timezone database version.
    getTzdbVersion @22 () -> (version :Text);

    # Audit-9: Subscribe to leap second announcements.
    subscribeLeapSecondAnnouncements @23 () -> (subscription :LeapSecondSubscription);

    # Audit-9: Convert UTC timestamp to TAI (International Atomic Time).
    convertToTai @24 (utcTimestamp :T.Timestamp) -> (taiTimestamp :TaiTimestamp);

    # Audit-9: Convert TAI timestamp to UTC.
    convertFromTai @25 (taiTimestamp :TaiTimestamp) -> (utcTimestamp :T.Timestamp);

    # Audit-9: List timezones by geographic region (e.g., "Europe", "Americas", "Asia").
    listTimezonesByRegion @26 (region :Text, pagination :T.Pagination)
        -> (timezones :List(TimezoneInfo), totalCount :UInt32);

    # Audit-9: Get ranked list of closest timezones to coordinates.
    getRankedTimezones @27 (latitude :Float64, longitude :Float64, count :UInt32)
        -> (ranked :List(RankedTimezone));

    # Audit-10: Resolve a recurring event using a full iCalendar RRULE.
    resolveRecurringEventRRULE @28 (timezoneId :Text, rule :RecurrenceRule,
        startDate :T.Date, exceptions :List(RecurrenceException), maxOccurrences :UInt32)
        -> (occurrences :List(ResolvedRRuleEvent));

    # Audit-10: Subscribe to timezone database update notifications.
    subscribeTzdbUpdates @29 () -> (subscription :TzdbUpdateSubscription);
}

interface TimezoneSubscription {
    pull @0 () -> (updates :List(TimezoneUpdate));
    cancel @1 () -> T.VoidResult;
}

# ─── Timezone Info ──────────────────────────────────────────────────

struct TimezoneInfo {
    # IANA timezone database identifier (e.g., "America/New_York", "Europe/London").
    id @0 :Text;

    # Human-readable display name (e.g., "Eastern Time (US & Canada)").
    displayName @1 :Text;

    # Standard timezone abbreviation (e.g., "EST", "CET").
    standardAbbr @2 :Text;

    # Daylight saving timezone abbreviation (e.g., "EDT", "CEST").
    daylightAbbr @3 :Text;

    # Current UTC offset in seconds (includes DST if currently in effect).
    currentUtcOffsetSeconds @4 :Int32;

    # Standard UTC offset in seconds (without DST).
    standardUtcOffsetSeconds @5 :Int32;

    # Daylight saving UTC offset in seconds (0 if no DST).
    daylightUtcOffsetSeconds @6 :Int32;

    # Whether DST is currently in effect.
    isDstActive @7 :Bool;

    # Next DST transition timestamp (0 if none scheduled or unknown).
    nextDstTransition @8 :T.Timestamp;

    # Whether this timezone observes DST.
    observesDst @9 :Bool;

    # Country code (ISO 3166-1 alpha-2) for the primary country.
    countryCode @10 :Text;

    # Geographic coordinates of the timezone's reference location.
    coordinates @11 :T.Vec2;

    # Historical aliases (e.g., "US/Eastern" → "America/New_York").
    aliases @12 :List(Text);

    # Whether this is a fixed-offset timezone (no DST, e.g., "Etc/UTC", "Etc/GMT+5").
    isFixedOffset @13 :Bool;

    # Historical UTC offset changes (for timezones with multiple offset changes).
    historicalOffsets @14 :List(HistoricalOffset);

    # Whether this timezone has leap seconds.
    hasLeapSeconds @15 :Bool;

    # Backend-specific metadata (tzdb version, source, etc.).
    metadata @16 :T.StringMap;
}

struct HistoricalOffset {
    # Timestamp when this offset became effective.
    effectiveAt @0 :T.Timestamp;
    # UTC offset in seconds.
    offsetSeconds @1 :Int32;
    # Abbreviation for this offset.
    abbreviation @2 :Text;
    # Whether DST was in effect.
    isDst @3 :Bool;
}

# ─── UTC Offset ──────────────────────────────────────────────────────

struct UtcOffset {
    # Offset from UTC in seconds. Positive = east of UTC.
    offsetSeconds @0 :Int32;

    # Whether this offset includes DST.
    isDst @1 :Bool;

    # Timezone abbreviation for this offset (e.g., "EST", "EDT").
    abbreviation @2 :Text;

    # Timestamp when this offset becomes effective.
    effectiveFrom @3 :T.Timestamp;

    # Timestamp when this offset ceases (0 = indefinite).
    effectiveUntil @4 :T.Timestamp;
}

# ─── DST Transition ──────────────────────────────────────────────────

struct DstTransition {
    # Timestamp when the transition occurs.
    at @0 :T.Timestamp;

    # UTC offset before the transition (seconds).
    offsetBeforeSeconds @1 :Int32;

    # UTC offset after the transition (seconds).
    offsetAfterSeconds @2 :Int32;

    # Abbreviation before transition (e.g., "EST").
    abbrBefore @3 :Text;

    # Abbreviation after transition (e.g., "EDT").
    abbrAfter @4 :Text;

    # Whether transition is to DST (true) or from DST (false).
    isDstStart @5 :Bool;

    # Transition type.
    type @6 :DstTransitionType;
}

enum DstTransitionType {
    standardToDaylight @0;   # Standard → DST (spring forward)
    daylightToStandard @1;   # DST → Standard (fall back)
    offsetChange @2;         # Permanent offset change (no DST)
    abbreviationChange @3;   # Only abbreviation changed
    custom @4;
}

# ─── Timestamp Conversion Result ─────────────────────────────────────

struct ConvertResult {
    union {
        success @0 :ConvertSuccess;
        error @1 :T.Error;
    }
}

struct ConvertSuccess {
    # Converted timestamp in target timezone.
    timestamp @0 :T.Timestamp;

    # Target timezone info at the converted time.
    targetZoneInfo @1 :TimezoneInfo;

    # Source timezone info at the original time.
    sourceZoneInfo @2 :TimezoneInfo;
}

# ─── Timezone Update Events ──────────────────────────────────────────

struct TimezoneUpdate {
    union {
        # Timezone database updated (new tzdata version).
        databaseUpdated @0 :DatabaseUpdate;

        # System default timezone changed.
        defaultChanged @1 :DefaultChange;

        # Specific timezone definition changed.
        definitionChanged @2 :DefinitionChange;

        # Custom backend notification.
        custom @3 :Data;
    }
}

struct DatabaseUpdate {
    version @0 :Text;           # e.g., "2024a", "2024b"
    previousVersion @1 :Text;
    changedZones @2 :List(Text);  # IANA IDs that changed
    timestamp @3 :T.Timestamp;
}

struct DefaultChange {
    oldTimezone @0 :Text;
    newTimezone @1 :Text;
    timestamp @2 :T.Timestamp;
}

struct DefinitionChange {
    timezoneId @0 :Text;
    changedFields @1 :List(Text);  # Which fields changed
    timestamp @2 :T.Timestamp;
}

# ─── Time Range Helper ──────────────────────────────────────────────

# (Re-exported from types.capnp conceptually; defined here for self-containment)
struct TimeRange {
    start @0 :T.Timestamp;
    end @1 :T.Timestamp;
}

# ─── Leap Second ─────────────────────────────────────────────────────

struct TimezoneLeapSecond {
    # Date when the leap second was applied.
    date @0 :T.Date;
    # Cumulative TAI-UTC offset after this leap second.
    offset @1 :UInt16;
    # Whether this was a positive (1s added) or negative leap second.
    positive @2 :Bool;
    # Timezone this leap second applies to (empty = all).
    timezoneId @3 :Text;
}

# ─── Abbreviation Info ───────────────────────────────────────────────

struct AbbreviationInfo {
    # The abbreviation (e.g., "EST", "CEST").
    abbreviation @0 :Text;
    # Full name of the abbreviation (e.g., "Eastern Standard Time").
    fullName @1 :Text;
    # UTC offset in seconds for this abbreviation.
    offsetSeconds @2 :Int32;
    # Whether this abbreviation is currently in effect.
    active @3 :Bool;
    # Whether this abbreviation represents DST.
    isDst @4 :Bool;
}

# ─── Business Hours ──────────────────────────────────────────────────

struct TimezoneBusinessHours {
    # Timezone these business hours apply to.
    timezoneId @0 :Text;
    # Hours per business day.
    hoursPerDay @1 :UInt8;
    # Workdays (1=Monday, 7=Sunday). Empty = all days.
    workdays @2 :List(UInt8);
    # Working hours start (hour 0-23).
    workStartHour @3 :UInt8;
    # Working hours end (hour 0-23).
    workEndHour @4 :UInt8;
}

# ─── Timezone Comparison ─────────────────────────────────────────────

struct TimezoneComparison {
    # Whether the two timezones have the same UTC offset at the timestamp.
    sameOffset @0 :Bool;
    # Whether both timezones observe DST.
    bothObserveDst @1 :Bool;
    # Offset difference in seconds.
    offsetDifferenceSeconds @2 :Int32;
    # Whether the timezones are in the same country.
    sameCountry @3 :Bool;
}

# ─── Resolved Event ──────────────────────────────────────────────────

struct ResolvedEvent {
    # UTC timestamp of the event occurrence.
    utcTimestamp @0 :T.Timestamp;
    # Local timestamp in the timezone.
    localTimestamp @1 :T.Timestamp;
    # Whether DST was in effect at this occurrence.
    dstActive @2 :Bool;
    # UTC offset at this occurrence.
    offsetSeconds @3 :Int32;
}

# ─── Leap Second Subscription (audit-9) ────────────────────

interface LeapSecondSubscription {
    pull @0 () -> (announcements :List(LeapSecondAnnouncement));
    cancel @1 () -> T.VoidResult;
}

struct LeapSecondAnnouncement {
    # When the leap second will be applied.
    effectiveAt @0 :T.Timestamp;
    # Cumulative TAI-UTC offset after this leap second.
    offset @1 :UInt16;
    # Positive = insertion, negative = deletion.
    positive @2 :Bool;
    # Published by (IERS, NIST, etc.).
    publishedBy @3 :Text;
}

# ─── TAI-UTC Conversion (audit-9) ───────────────────────────

struct TaiTimestamp {
    # TAI seconds since Unix epoch (1970-01-01 00:00:00 TAI).
    taiSeconds @0 :UInt64;
    # Nanoseconds within the second.
    nanoseconds @1 :UInt32;
}

struct TaiUtcConversion {
    taiTimestamp @0 :TaiTimestamp;
    utcTimestamp @1 :T.Timestamp;
    # Current TAI-UTC offset in seconds.
    currentOffset @2 :UInt16;
    # Whether a leap second is pending.
    leapSecondPending @3 :Bool;
}

# ─── Timezone Region (audit-9) ─────────────────────────────

enum TimezoneRegion {
    africa @0;
    americas @1;
    asia @2;
    europe @3;
    oceania @4;
    antarctica @5;
    custom @6;
}

# ─── Ranked Timezone (audit-9) ─────────────────────────────

struct RankedTimezone {
    timezoneId @0 :Text;
    distanceKm @1 :Float32;
    rank @2 :UInt32;
}

# ─── RRULE Recurring Event (audit-10) ──────────────────────

enum RecurrenceFrequency {
    daily @0;
    weekly @1;
    monthly @2;
    yearly @3;
    custom @4;
}

struct RecurrenceRule {
    frequency @0 :RecurrenceFrequency;
    # Interval between occurrences (e.g., every 2 weeks).
    interval @1 :UInt32;
    # Day of week (1=Monday, 7=Sunday). Empty = all days.
    byDay @2 :List(UInt8);
    # Day of month (1-31). Empty = all days.
    byMonthDay @3 :List(UInt8);
    # Month (1-12). Empty = all months.
    byMonth @4 :List(UInt8);
    # Count of occurrences (0 = until untilDate).
    count @5 :UInt32;
    # End date for recurrence (0 = no end).
    untilDate @6 :T.Date;
}

struct RecurrenceException {
    # Original date of the occurrence.
    originalDate @0 :T.Date;
    # New date if rescheduled, empty if deleted.
    newDate @1 :T.Date;
    # Whether this occurrence is cancelled.
    cancelled @2 :Bool;
}

struct ResolvedRRuleEvent {
    # UTC timestamp of the occurrence.
    utcTimestamp @0 :T.Timestamp;
    # Local timestamp in the timezone.
    localTimestamp @1 :T.Timestamp;
    # Whether DST was in effect.
    dstActive @2 :Bool;
    # UTC offset at this occurrence.
    offsetSeconds @3 :Int32;
    # Whether this is an exception to the rule.
    isException @4 :Bool;
}

# ─── Tzdb Update Subscription (audit-10) ───────────────────

interface TzdbUpdateSubscription {
    pull @0 () -> (updates :List(TzdbUpdate));
    cancel @1 () -> T.VoidResult;
}

struct TzdbUpdate {
    # New tzdb version.
    newVersion @0 :Text;
    # Previous tzdb version.
    oldVersion @1 :Text;
    # Number of zones changed.
    zonesChanged @2 :UInt32;
    # Timestamp of the update.
    timestamp @3 :T.Timestamp;
    # IANA zone IDs that changed.
    changedZoneIds @4 :List(Text);
}
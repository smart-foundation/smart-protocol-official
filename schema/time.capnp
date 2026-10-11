@0xa1b2c3d4e5f6001e;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Time — wall-clock reading, calendar arithmetic, and timestamp trust.
#
# This file used to carry the batch's only compile-clean wire-semantics
# breaker: a `TAITimestamp` of TAI seconds since 1958 with a name one
# letter-case away from timezone.capnp's `TaiTimestamp` of TAI seconds
# since 1970. Both are bare UInt64 seconds, so nothing caught a consumer
# passing one to the other's converter — a silent ~120-year corruption.
#
# The epoch is now declared in ONE place. `TaiTimestamp` lives in
# timezone.capnp and is Unix-epoch (1970), the same epoch as T.Timestamp;
# the UTC↔TAI conversion surface is timezone.capnp's `convertToTai` /
# `convertFromTai`, and this file no longer declares a TAI type or a
# converter at all. One obviously-epoched type, one converter, no second
# spelling to confuse it with.
#
# What moved out of this file, and why:
#   - alarms, timers, monotonic clocks, clock-source quality: clock.capnp
#     owns them (its alarm model is strictly richer — recurrence and
#     holiday behaviour), and two alarm stores with two struct shapes is
#     exactly the fork this rule exists to prevent.
#   - timezone descriptors, the default-zone setting, leap-second tables
#     and business hours: timezone.capnp owns them.
#   - duration humanization and formatting: locale-bound utilities are
#     not an RPC contract; a consumer formats in its own locale.
#   - "upcoming time events": an aggregation over two other services'
#     data with no home of its own.
#
# What remains is what only this contract can answer: what time is it, in
# which calendar, and is this timestamp attested.
# ═══════════════════════════════════════════════════════════════════════

interface Time {
    # Current wall-clock reading in the system's zone. The zone itself is
    # owned by timezone.capnp; `timezone` and `utcOffsetSeconds` here are
    # the backend's report of what it applied.
    getDateTime @0 () -> (dateTime :DateTime);

    # Verify an HSM-attested timestamp. `T.BoolResult` so the outcome is
    # machine-routable (a code and a retry flag) instead of a bare bool
    # plus a text nobody can branch on.
    verifyHsmTimestamp @1 (hsm :HSMTimestamp) -> (result :T.BoolResult);

    # ── Calendar arithmetic ──
    # Calendar systems are a small, closed set with a `custom` outlet for
    # a calendar this schema does not name; the set is load-bearing for
    # conversion, so it is declared rather than tokenized.

    convertCalendar @2 (date :HistoricalDate, fromSystem :CalendarSystem, toSystem :CalendarSystem)
                    -> (converted :HistoricalDate);
    addCalendarUnits @3 (date :HistoricalDate, units :List(CalendarUnit)) -> (result :HistoricalDate);
    subtractCalendarUnits @4 (date :HistoricalDate, units :List(CalendarUnit)) -> (result :HistoricalDate);
    diffCalendarDates @5 (date1 :HistoricalDate, date2 :HistoricalDate) -> (diff :CalendarDiff);
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
    # Zone reported by the backend (open token; the zone catalog and the
    # default-zone setting live in timezone.capnp).
    timezone @9 :Text;
    utcOffsetSeconds @10 :Int32;
    metadata @11 :T.StringMap;
}

# ── HSM-Signed Timestamp ──────────────────────────────────────────────

struct HSMTimestamp {
    timestamp @0 :T.Timestamp;
    signature @1 :T.DataHandle;
    certificateChain @2 :T.DataHandle;
    hardwareId @3 :Text;
    metadata @4 :T.StringMap;
}

# ── Calendar Systems ──────────────────────────────────────────────────

enum CalendarSystem {
    unknown @0;
    gregorian @1;
    julian @2;
    islamic @3;
    hebrew @4;
    chinese @5;
    ethiopian @6;
    custom @7;
}

struct HistoricalDate {
    year @0 :Int64;
    month @1 :UInt8;
    day @2 :UInt8;
    calendar @3 :CalendarSystem;
    metadata @4 :T.StringMap;
}

# ── Calendar Arithmetic ───────────────────────────────────────────────

struct CalendarUnit {
    kind @0 :CalendarUnitKind;
    amount @1 :Int32;
}

enum CalendarUnitKind {
    unknown @0;
    days @1;
    weeks @2;
    months @3;
    years @4;
    custom @5;
}

struct CalendarDiff {
    years @0 :Int32;
    months @1 :Int32;
    days @2 :Int32;
    totalDays @3 :Int64;
    negative @4 :Bool;
    metadata @5 :T.StringMap;
}

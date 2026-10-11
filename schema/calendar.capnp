@0xa1b2c3d4e5f6002a;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Calendar — event management, scheduling, free/busy, recurrence.
#
# The zero-cost posture is correct and is kept: EventAttachment.data is
# a T.DataHandle, import/export are T.DataHandle, the hot paths are
# paginated, and the event subscription has a pull-paginated variant.
#
# ── RECURRENCE PRECEDENCE WAS UNDECLARED ──────────────────────────────
#
# `Recurrence` carried TWO representations of one fact — the structured
# fields (frequency, interval, count, until, daysOfWeek, dayOfMonth,
# monthOfYear) and a raw RFC 5545 `rrule` string — with no precedence
# rule. The classic fork: two backends expand the same recurring event
# differently depending on which field they honour, a backend that fills
# `rrule` but not `frequency` produces an event whose series is invisible
# to any consumer that only reads the structured fields, and every
# consumer has to re-implement "which wins".
#
# Declared now: the STRUCTURED fields are authoritative. `rrule` is an
# opaque backend hint for a rule the structured fields cannot express,
# and a backend MUST report that it used it by setting
# `structuredFieldsIncomplete`. A consumer that reads only the structured
# fields therefore never sees a different series than the backend
# expands. `Recurrence` also gains a timezone, because a daily 09:00
# event crossing a DST boundary had no declared expansion.
#
# ── DELEGATION WAS FIVE BOOLEANS ───────────────────────────────────────
#
# `DelegatePermissions` (canRead/canWrite/canCreate/canDelete/canShare)
# was RBAC, which DESIGN_PRINCIPLES.md:399 forbids, in parallel with
# capability.capnp. Delegation semantics had to be implemented twice and
# the two systems could disagree about who may read a delegated calendar
# — a delegation granted here could outlive a capability revoked there.
# The booleans AND the delegateCalendar/revokeDelegation methods are both
# deleted: delegation is capability.capnp's `attenuate @2` + `transfer`,
# so it joins the one authority model and gains revocation that booleans
# never had.
#
# ── VENDOR NAMES AND CALENDAR SYSTEMS ──────────────────────────────────
#
# `CalendarSubscription` named `google` and `exchange` in a required
# position, so a CalDAV-compatible server (Radicale, Fastmail, a
# self-hosted Baïkal) and any 2046 service had only `custom` carrying
# nothing. `CalendarType` named six calendar systems as permanent
# ordinals — the Chinese, Japanese, Coptic, Ethiopian and Hindu
# calendars all had nowhere to go. Both are open tokens now.
#
# ── THREE NAMES FOR ONE FIELD ──────────────────────────────────────────
#
# `FreeBusyPrivacy` held free/busy/tentative/outOfOffice — which are
# STATUSES — and was assigned to a field named `status`. It is
# `FreeBusyStatus` now, and the value-identical duplicate in
# contacts.capnp is deleted (this file owns availability).
#
# ── STRINGLY-TYPED TIME OF DAY ─────────────────────────────────────────
#
# `DayWorkingHours.startTime`/`endTime` were "HH:MM" strings: "09:00"
# means something different on either side of a DST transition, and two
# backends resolved the same string to different instants. They are
# T.Duration offsets from local midnight now — an existing type, so no
# new foundation primitive is needed.
#
# Improvements (audit-7/9), unchanged:
#   - EventLocation, VideoConference, EventAttachment.
#   - FreeBusyQuery/FreeBusyResult for privacy-preserving availability.
#   - HolidayCalendar; EventQueryFilter with dateRange/attendee/hasRecurrence.
#   - Calendar sync with incremental sync and conflict resolution.
#   - Working hours, event conflict detection, event versioning.
#   - Analytics, reminder escalation, theme config, response history.
# ═══════════════════════════════════════════════════════════════════════

interface CalendarService {
    listCalendars @0 (pagination :T.Pagination) -> (calendars :List(CalendarInfo), totalCount :UInt32);
    getCalendar @1 (calendarId :T.CalendarId) -> (calendar :CalendarInfo);

    # `range` is a start/end pair of T.Timestamp. The local TimeRange
    # struct was the third copy in the batch (contacts and calendar each
    # had one, types.capnp's promoted T.TimeRange uses UInt64
    # milliseconds — a different semantics), so the pair is spelled
    # explicitly rather than through a colliding type.
    listEvents @2 (calendarId :T.CalendarId, start :T.Timestamp, end :T.Timestamp,
                   filter :EventQueryFilter, pagination :T.Pagination)
               -> (events :List(Event), totalCount :UInt32);
    getEvent @3 (eventId :T.EventId) -> (event :Event);
    getToday @4 (pagination :T.Pagination) -> (events :List(Event), totalCount :UInt32);
    getUpcoming @5 (duration :T.Duration, pagination :T.Pagination) -> (events :List(Event), totalCount :UInt32);

    createEvent @6 (event :Event) -> (eventId :T.EventId);
    updateEvent @7 (eventId :T.EventId, event :Event) -> T.VoidResult;
    deleteEvent @8 (eventId :T.EventId) -> T.VoidResult;
    respondToEvent @9 (eventId :T.EventId, response :AttendeeStatus, comment :Text) -> T.VoidResult;

    subscribeEvents @10 (calendarId :T.CalendarId) -> (subscription :EventsSubscription);

    getReminders @11 (eventId :T.EventId, pagination :T.Pagination) -> (reminders :List(Reminder), totalCount :UInt32);
    addReminder @12 (eventId :T.EventId, reminder :Reminder) -> T.VoidResult;
    removeReminder @13 (eventId :T.EventId, reminderId :T.ReminderId) -> T.VoidResult;

    # ── Audit-7 additions ────────────────────────────────────

    # Privacy-preserving free/busy query. This is the canonical
    # availability contract for the batch; contacts.capnp's duplicate
    # getFreeBusy is deleted.
    queryFreeBusy @14 (query :FreeBusyQuery) -> (result :FreeBusyResult);

    # Check if a new event conflicts with existing events.
    detectConflicts @15 (event :Event) -> (conflicts :List(Event));

    # Full-text search across events, attendees, locations.
    searchEvents @16 (query :Text, pagination :T.Pagination) -> (events :List(Event));

    # Import events from iCal/CSV format.
    importEvents @17 (calendarId :T.CalendarId, format :Text, data :T.DataHandle)
        -> (imported :UInt32, warnings :List(T.Warning));

    # Export events to iCal/CSV format.
    exportEvents @18 (calendarId :T.CalendarId, start :T.Timestamp, end :T.Timestamp, format :Text)
        -> (data :T.DataHandle);

    # Edit all future events in a recurring series. Declared interaction
    # with already-modified instances: an instance listed in
    # `Recurrence.modifiedInstances` is left untouched unless its
    # eventId is named explicitly, so "this and future" cannot silently
    # overwrite a per-instance exception.
    updateEventSeries @19 (eventId :T.EventId, event :Event, scope :SeriesEditScope) -> T.VoidResult;

    # ── Calendar sync ──
    getSyncToken @20 (calendarId :T.CalendarId) -> (token :Text);
    syncChanges @21 (calendarId :T.CalendarId, syncToken :Text) -> (result :CalendarSyncResult);
    resolveConflict @22 (calendarId :T.CalendarId, conflictId :Text, resolution :ConflictResolution) -> T.VoidResult;

    # ── Working hours ──
    getWorkingHours @23 (calendarId :T.CalendarId) -> (hours :WorkingHours);
    setWorkingHours @24 (calendarId :T.CalendarId, hours :WorkingHours) -> T.VoidResult;

    # ── Audit-9 additions ──────────────────────────────────────
    getCalendarAnalytics @25 (calendarId :T.CalendarId, start :T.Timestamp, end :T.Timestamp)
        -> (analytics :CalendarAnalytics);
    getReminderEscalation @26 (eventId :T.EventId, reminderId :T.ReminderId) -> (escalation :ReminderEscalation);
    setReminderEscalation @27 (eventId :T.EventId, escalation :ReminderEscalation) -> T.VoidResult;
    getCalendarTheme @28 (calendarId :T.CalendarId) -> (config :CalendarThemeConfig);
    setCalendarTheme @29 (calendarId :T.CalendarId, config :CalendarThemeConfig) -> T.VoidResult;
    getAttendeeResponseHistory @30 (eventId :T.EventId) -> (history :List(AttendeeResponseHistory));
    getFormatCapabilities @31 () -> (formats :List(FormatCapability));
}

interface EventsSubscription {
    # Deprecated: use pullPaginated for bounded results.
    pull @0 () -> (events :List(Event));
    cancel @1 () -> T.VoidResult;
    # Paginated pull — returns at most `limit` events starting from `offset`.
    pullPaginated @2 (pagination :T.Pagination) -> (result :EventsPullResult);
}

struct EventsPullResult {
    events    @0 :List(Event);
    totalCount @1 :UInt32;
}

# ── Calendar Info ─────────────────────────────────────────────

struct CalendarInfo {
    id @0 :T.CalendarId;
    name @1 :Text;
    description @2 :Text;
    color @3 :T.Color;
    timezone @4 :Text;        # IANA timezone database name (e.g., "America/New_York")
    readOnly @5 :Bool;
    visible @6 :Bool;
    # ── Audit-7 additions ────────────────────────────────────
    # Calendar system, as an open token (see the conformance consts).
    calendarType @7 :Text;
    # Feed type, as an open token: a CalDAV-compatible server, a hosted
    # service, or a 2046 mechanism. `google` and `exchange` were 2026
    # facts frozen into required positions.
    subscription @8 :Text;
    isHoliday @9 :Bool;
    holidayRegion @10 :Text;
}

# ── Event ─────────────────────────────────────────────────────

struct Event {
    id @0 :T.EventId;
    calendarId @1 :T.CalendarId;
    title @2 :Text;
    description @3 :Text;
    location @4 :Text;
    start @5 :T.Timestamp;
    end @6 :T.Timestamp;
    timezone @7 :Text;        # IANA timezone database name
    allDay @8 :Bool;
    recurrence @9 :Recurrence;
    reminders @10 :List(Reminder);
    attendees @11 :List(Attendee);
    organizer @12 :Attendee;
    status @13 :EventStatus;
    transparency @14 :Transparency;
    created @15 :T.Timestamp;
    modified @16 :T.Timestamp;
    # ── Audit-7 additions ────────────────────────────────────
    attachments @17 :List(EventAttachment);
    videoConference @18 :VideoConference;
    locationStructured @19 :EventLocation;
    freeBusyPrivacy @20 :FreeBusyStatus;
    version @21 :UInt32;
}

# ── Recurrence ────────────────────────────────────────────────
# PRECEDENCE, declared: the STRUCTURED fields are authoritative. `rrule`
# is an opaque backend hint for a rule the structured fields cannot
# express; a backend that used it MUST set
# `structuredFieldsIncomplete` so a consumer reading only the structured
# fields knows the series it sees may be incomplete. This closes the fork
# where two backends expanded the same series differently depending on
# which field they honoured.

struct Recurrence {
    frequency @0 :RecurrenceFrequency;
    interval @1 :UInt32;       # Count of frequency units (e.g., 2 = every 2 weeks)
    count @2 :UInt32;          # Total occurrences (0 = unlimited)
    until @3 :T.Timestamp;     # End date (zero = use count or unlimited)
    daysOfWeek @4 :List(DayOfWeek);
    dayOfMonth @5 :UInt32;     # 1-31 (0 = not set)
    monthOfYear @6 :UInt32;    # 1-12  (0 = not set)
    # Backend-specific rule, as an open token.
    custom @7 :Text;
    # RFC 5545 RRULE string for a rule the structured fields cannot
    # express. Advisory only; see the precedence rule above.
    rrule @8 :Text;
    # Dates excluded from recurrence.
    exceptions @9 :List(T.Timestamp);
    # Modified instances that differ from the series.
    modifiedInstances @10 :List(Event);
    # True when the backend relied on `rrule` and could not project it
    # into the structured fields above.
    structuredFieldsIncomplete @11 :Bool;
    # Timezone the series expands in. Previously absent, so a daily
    # 09:00 event crossing a DST boundary had no declared expansion.
    timezone @12 :Text;
}

enum RecurrenceFrequency {
    unspecified @0;   # Sentinel: an unset value is not the @0 paradigm
    daily @1;
    weekly @2;
    monthly @3;
    yearly @4;
    custom @5;
}

enum DayOfWeek {
    sunday @0;
    monday @1;
    tuesday @2;
    wednesday @3;
    thursday @4;
    friday @5;
    saturday @6;
    custom @7;
}

# ── Reminder ──────────────────────────────────────────────────

struct Reminder {
    id @0 :T.ReminderId;
    # Method, as an open token (see the conformance consts).
    method @1 :Text;
    before @2 :T.Duration;     # How long before the event to trigger
    acknowledged @3 :Bool;
}

# ── Attendee ─────────────────────────────────────────────────

struct Attendee {
    id @0 :T.AttendeeId;
    name @1 :Text;
    email @2 :Text;
    status @3 :AttendeeStatus;
    role @4 :AttendeeRole;
}

enum AttendeeStatus {
    unspecified @0;   # Sentinel: an unset value is not the @0 paradigm
    pending @1;
    accepted @2;
    declined @3;
    tentative @4;
    delegated @5;
    custom @6;
}

# `duplicate` was an iCalendar bookkeeping detail leaked into the wire —
# not a role any consumer can act on. It is retired rather than renamed.
enum AttendeeRole {
    unspecified @0;   # Sentinel: an unset value is not the @0 paradigm
    chair @1;
    required @2;
    optional @3;
    nonParticipant @4;
    custom @5;
}

enum EventStatus {
    unspecified @0;   # Sentinel: an unset value is not the @0 paradigm
    confirmed @1;
    tentative @2;
    cancelled @3;
    custom @4;
}

enum Transparency {
    unspecified @0;   # Sentinel: an unset value is not the @0 paradigm
    opaque @1;
    transparent @2;
    custom @3;
}

# ── Free/Busy ─────────────────────────────────────────────────
# Named FreeBusyStatus, not FreeBusyPrivacy: the values are statuses,
# and the old name was assigned to a field called `status` — three names
# for one concept in three lines.

enum FreeBusyStatus {
    unspecified @0;   # Sentinel: an unset value is not the @0 paradigm
    free @1;
    busy @2;
    tentative @3;
    outOfOffice @4;
    custom @5;
}

struct FreeBusyQuery {
    # Contact or user IDs to query.
    contactIds @0 :List(T.ContactId);
    # Time range to query, as an explicit timestamp pair (no colliding
    # local TimeRange).
    start @1 :T.Timestamp;
    end @2 :T.Timestamp;
    # Calendar IDs to include (empty = all calendars).
    calendarIds @3 :List(T.CalendarId);
    parameters @4 :T.StringMap;
}

struct FreeBusyResult {
    entries @0 :List(FreeBusyEntry);
}

struct FreeBusyEntry {
    contactId @0 :T.ContactId;
    status @1 :FreeBusyStatus;
    start @2 :T.Timestamp;
    end @3 :T.Timestamp;
    # Whether event details are hidden. Declared what "hidden" means:
    # the entry still carries contactId, start and end, so a "hidden"
    # event is still a busy-slot disclosure by construction — a consumer
    # MUST NOT treat detailsHidden as confidentiality of the slot.
    detailsHidden @4 :Bool;
}

# ── Structured Location ──────────────────────────────────────

struct EventLocation {
    address @0 :Text;
    latitude @1 :Float64;
    longitude @2 :Float64;
    virtualUrl @3 :T.Uri;
    room @4 :Text;
    parameters @5 :T.StringMap;
}

# ── Video Conference ─────────────────────────────────────────

struct VideoConference {
    url @0 :T.Uri;
    dialIn @1 :Text;
    pin @2 :Text;
    # Provider, as an open token. The previous examples ("zoom",
    # "teams", "meet") were vendor names in a doc comment feeding an
    # open field — a comment that becomes an enum.
    provider @3 :Text;
    parameters @4 :T.StringMap;
}

# ── Event Attachment ─────────────────────────────────────────

struct EventAttachment {
    name @0 :Text;
    mimeType @1 :T.MimeType;
    data @2 :T.DataHandle;
    uri @3 :T.Uri;
}

# ── Event Filter ─────────────────────────────────────────────

struct EventQueryFilter {
    title @0 :Text;
    location @1 :Text;
    status @2 :EventStatus;
    # ── Audit-7 additions ────────────────────────────────────
    start @3 :T.Timestamp;
    end @4 :T.Timestamp;
    attendee @5 :Text;
    hasRecurrence @6 :Bool;
    parameters @7 :T.StringMap;
}

# ── Holiday Calendar ────────────────────────────────────────

struct HolidayCalendar {
    name @0 :Text;
    # Region/country code (e.g., "US", "ZA").
    region @1 :Text;
    year @2 :UInt32;
    customHolidays @3 :List(Holiday);
}

struct Holiday {
    name @0 :Text;
    date @1 :T.Date;
    recurring @2 :Bool;
}

# ── Calendar Sync ───────────────────────────────────────────

struct CalendarSyncResult {
    newSyncToken @0 :Text;
    changed @1 :List(Event);
    deleted @2 :List(T.EventId);
    hasMore @3 :Bool;
    conflicts @4 :List(SyncConflict);
}

struct SyncConflict {
    conflictId @0 :Text;
    eventId @1 :T.EventId;
    localVersion @2 :Event;
    remoteVersion @3 :Event;
    detectedAt @4 :T.Timestamp;
}

enum ConflictResolution {
    unspecified @0;   # Sentinel: an unset value is not the @0 paradigm
    keepLocal @1;
    keepRemote @2;
    merge @3;
    custom @4;
}

# ── Series Edit Scope ───────────────────────────────────────

enum SeriesEditScope {
    unspecified @0;   # Sentinel: an unset value is not the @0 paradigm
    thisInstance @1;
    thisAndFuture @2;
    allInstances @3;
    custom @4;
}

# ── Working Hours ────────────────────────────────────────────

struct WorkingHours {
    # Working hours per day of week (index 0 = Sunday).
    days @0 :List(DayWorkingHours);
    # Timezone for working hours.
    timezone @1 :Text;
}

struct DayWorkingHours {
    day @0 :DayOfWeek;
    isWorkingDay @1 :Bool;
    # Start time as a T.Duration offset from LOCAL MIDNIGHT, not an
    # "HH:MM" string: "09:00" meant something different on either side
    # of a DST transition and two backends resolved the same string to
    # different instants.
    startTime @2 :T.Duration;
    endTime @3 :T.Duration;
}

# ── Delegation ───────────────────────────────────────────────
# `DelegatePermissions` (five booleans) and the delegateCalendar /
# revokeDelegation methods are both deleted. Delegation is capability.capnp's
# `attenuate @2` followed by `transfer`: the delegator weakens a Capability
# whose `target` names this calendar and hands the reference over, so
# delegation joins the one authority model and gains revocation and
# attenuation that booleans never had. capability.capnp's own header
# records the rule — "There is no delegation method in boot.capnp,
# kernel.capnp or anywhere else — that was a second, unenforced authority
# grammar." Revoking the delegation is capability.capnp's `revoke @4`, so a
# delegation can no longer outlive the capability it was made from.

# ════════════════════════════════════════════════════════════════════════
# Audit-9 additions: calendar analytics, reminder escalation, color/theme
# integration, attendee response history, and format negotiation.
# ════════════════════════════════════════════════════════════════════════

struct CalendarAnalytics {
    calendarId @0 :T.CalendarId;
    totalEvents @1 :UInt32;
    totalMeetingMinutes @2 :UInt32;
    averageEventsPerDay @3 :Float32;
    busiestDayOfWeek @4 :DayOfWeek;
    busiestHourOfDay @5 :UInt32;
    meetingLoadScore @6 :Float32;
    freeTimePercentage @7 :Float32;
    start @8 :T.Timestamp;
    end @9 :T.Timestamp;
}

# ── Reminder Escalation ────────────────────────────────────────────────

struct ReminderEscalation {
    reminderId @0 :T.ReminderId;
    levels @1 :List(EscalationLevel);
    maxCycles @2 :UInt32;
}

struct EscalationLevel {
    order @0 :UInt32;
    delayAfterPrevious @1 :T.Duration;
    # Method, as an open token (see the reminder-method consts).
    method @2 :Text;
    # Recipients, as typed user ids — the previous List(Text) mixed
    # "user IDs or addresses" in one list, so two namespaces in one field.
    recipients @3 :List(T.UserId);
    # Addresses for recipients that are not local users.
    recipientAddresses @4 :List(Text);
}

# ── Calendar Color/Theme Integration ───────────────────────────────────

struct CalendarThemeConfig {
    calendarId @0 :T.CalendarId;
    primaryColor @1 :T.Color;
    accentColor @2 :T.Color;
    useSystemTheme @3 :Bool;
    opacity @4 :Float32;
}

# ── Attendee Response History ──────────────────────────────────────────

struct AttendeeResponseHistory {
    attendeeId @0 :T.AttendeeId;
    eventId @1 :T.EventId;
    responses @2 :List(AttendeeResponseEntry);
}

struct AttendeeResponseEntry {
    previousStatus @0 :AttendeeStatus;
    newStatus @1 :AttendeeStatus;
    respondedAt @2 :T.Timestamp;
    comment @3 :Text;
}

# ── Format Negotiation ─────────────────────────────────────────────────

struct FormatCapability {
    formatId @0 :Text;
    name @1 :Text;
    mimeType @2 :T.MimeType;
    supportsImport @3 :Bool;
    supportsExport @4 :Bool;
    maxEventsPerBatch @5 :UInt32;
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Today's spellings for the open tokens above. Nothing requires them; an
# unrecognized token MUST be ignored rather than rejected.
# ══════════════════════════════════════════════════════════════════════

const calendarTypeGregorian :Text = "gregorian";
const calendarTypeLunar     :Text = "lunar";
const calendarTypeHebrew    :Text = "hebrew";
const calendarTypeIslamic   :Text = "islamic";
const calendarTypePersian   :Text = "persian";
const calendarTypeBuddhist  :Text = "buddhist";

const subscriptionIcal   :Text = "ical";
const subscriptionCaldav :Text = "caldav";

const reminderMethodAlert :Text = "alert";
const reminderMethodEmail :Text = "email";
const reminderMethodSms   :Text = "sms";
const reminderMethodPopup :Text = "popup";

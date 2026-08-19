@0xa1b2c3d4e5f6002a;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Calendar — event management, scheduling, free/busy, recurrence.
#
# Improvements (audit-7):
#   - Recurrence.rrule for RFC 5545 complex recurrence rules.
#   - EventLocation struct for structured locations (address, coords, virtual).
#   - VideoConference struct for meeting URLs, dial-in, provider metadata.
#   - EventAttachment struct for typed event attachments.
#   - FreeBusyQuery/FreeBusyResult for privacy-preserving availability.
#   - CalendarType enum for multi-calendar systems (Gregorian, Lunar, etc.).
#   - CalendarSubscription enum for feed types (iCal, CalDAV, etc.).
#   - HolidayCalendar struct for holiday calendars.
#   - EventFilter expanded with dateRange, attendee, hasRecurrence.
#   - Calendar sync protocol (false positive from calendar_sync.capnp):
#     CalendarSyncService with incremental sync, conflict resolution.
#   - Working hours model, event conflict detection, event versioning.
# ═══════════════════════════════════════════════════════════════════════

interface CalendarService {
    listCalendars @0 (pagination :T.Pagination) -> (calendars :List(CalendarInfo), totalCount :UInt32);
    getCalendar @1 (calendarId :T.CalendarId) -> (calendar :CalendarInfo);

    listEvents @2 (calendarId :T.CalendarId, range :TimeRange, filter :EventFilter, pagination :T.Pagination) -> (events :List(Event), totalCount :UInt32);
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

    # Privacy-preserving free/busy query.
    queryFreeBusy @14 (query :FreeBusyQuery) -> (result :FreeBusyResult);

    # Check if a new event conflicts with existing events.
    detectConflicts @15 (event :Event) -> (conflicts :List(Event));

    # Full-text search across events, attendees, locations.
    searchEvents @16 (query :Text, pagination :T.Pagination) -> (events :List(Event));

    # Import events from iCal/CSV format.
    importEvents @17 (calendarId :T.CalendarId, format :Text, data :T.DataHandle) -> (imported :UInt32, warnings :List(T.Warning));

    # Export events to iCal/CSV format.
    exportEvents @18 (calendarId :T.CalendarId, range :TimeRange, format :Text) -> (data :T.DataHandle);

    # Edit all future events in a recurring series.
    updateEventSeries @19 (eventId :T.EventId, event :Event, scope :SeriesEditScope) -> T.VoidResult;

    # ── Calendar sync (false positive: calendar_sync.capnp) ──
    # Get the sync token for incremental sync.
    getSyncToken @20 (calendarId :T.CalendarId) -> (token :Text);

    # Fetch changes since a sync token (incremental sync).
    syncChanges @21 (calendarId :T.CalendarId, syncToken :Text) -> (result :CalendarSyncResult);

    # Resolve a sync conflict.
    resolveConflict @22 (calendarId :T.CalendarId, conflictId :Text, resolution :ConflictResolution) -> T.VoidResult;

    # ── Working hours (audit-7) ──────────────────────────────
    # Get working hours for a calendar.
    getWorkingHours @23 (calendarId :T.CalendarId) -> (hours :WorkingHours);

    # Set working hours for a calendar.
    setWorkingHours @24 (calendarId :T.CalendarId, hours :WorkingHours) -> T.VoidResult;

    # ── Delegation (audit-7) ─────────────────────────────────
    # Delegate calendar management to another user.
    delegateCalendar @25 (calendarId :T.CalendarId, delegateId :T.UserId, permissions :DelegatePermissions) -> T.VoidResult;

    # Revoke calendar delegation.
    revokeDelegation @26 (calendarId :T.CalendarId, delegateId :T.UserId) -> T.VoidResult;

    # ── Audit-9 additions ──────────────────────────────────────

    # Get calendar analytics (meeting load, time tracking).
    getCalendarAnalytics @27 (calendarId :T.CalendarId, range :TimeRange) -> (analytics :CalendarAnalytics);

    # Get reminder escalation chain for an event.
    getReminderEscalation @28 (eventId :T.EventId, reminderId :T.ReminderId) -> (escalation :ReminderEscalation);

    # Set reminder escalation chain for an event.
    setReminderEscalation @29 (eventId :T.EventId, escalation :ReminderEscalation) -> T.VoidResult;

    # Get color/theme config for a calendar.
    getCalendarTheme @30 (calendarId :T.CalendarId) -> (config :CalendarThemeConfig);

    # Set color/theme config for a calendar.
    setCalendarTheme @31 (calendarId :T.CalendarId, config :CalendarThemeConfig) -> T.VoidResult;

    # Get attendee response history for an event.
    getAttendeeResponseHistory @32 (eventId :T.EventId) -> (history :List(AttendeeResponseHistory));

    # Get supported import/export format capabilities.
    getFormatCapabilities @33 () -> (formats :List(FormatCapability));
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
    calendarType @7 :CalendarType;
    subscription @8 :CalendarSubscription;
    isHoliday @9 :Bool;
    holidayRegion @10 :Text;
}

enum CalendarType {
    gregorian @0;
    lunar @1;
    hebrew @2;
    islamic @3;
    persian @4;
    buddhist @5;
    custom @6;
}

enum CalendarSubscription {
    ical @0;
    caldav @1;
    google @2;
    exchange @3;
    custom @4;
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
    freeBusyPrivacy @20 :FreeBusyPrivacy;
    # Version number for conflict detection (audit-7).
    version @21 :UInt32;
}

# ── Recurrence ────────────────────────────────────────────────

struct Recurrence {
    frequency @0 :Frequency;
    interval @1 :UInt32;       # Count of frequency units (e.g., 2 = every 2 weeks)
    count @2 :UInt32;          # Total occurrences (0 = unlimited)
    until @3 :T.Timestamp;     # End date (zero = use count or unlimited)
    daysOfWeek @4 :List(DayOfWeek);
    dayOfMonth @5 :UInt32;     # 1-31 (0 = not set)
    monthOfYear @6 :UInt32;    # 1-12  (0 = not set)
    custom @7 :Text;           # Backend-specific recurrence rule
    # RFC 5545 RRULE string for complex recurrence (audit-7).
    rrule @8 :Text;
    # Dates excluded from recurrence (audit-7).
    exceptions @9 :List(T.Timestamp);
    # Modified instances that differ from the series (audit-7).
    modifiedInstances @10 :List(Event);
}

enum Frequency {
    daily @0;
    weekly @1;
    monthly @2;
    yearly @3;
    custom @4;
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
    method @1 :ReminderMethod;
    before @2 :T.Duration;     # How long before the event to trigger
    acknowledged @3 :Bool;
}

enum ReminderMethod {
    alert @0;
    email @1;
    sms @2;
    popup @3;
    custom @4;
}

# ── Attendee ──────────────────────────────────────────────────

struct Attendee {
    id @0 :T.AttendeeId;
    name @1 :Text;
    email @2 :Text;
    status @3 :AttendeeStatus;
    role @4 :AttendeeRole;
}

enum AttendeeStatus {
    pending @0;
    accepted @1;
    declined @2;
    tentative @3;
    delegated @4;
    custom @5;
}

enum AttendeeRole {
    chair @0;
    required @1;
    optional @2;
    nonParticipant @3;
    duplicate @4;
    custom @5;
}

enum EventStatus {
    confirmed @0;
    tentative @1;
    cancelled @2;
    custom @3;
}

enum Transparency {
    opaque @0;
    transparent @1;
    custom @2;
}

# ── Free/Busy (audit-7) ───────────────────────────────────────

enum FreeBusyPrivacy {
    free @0;
    busy @1;
    tentative @2;
    outOfOffice @3;
    custom @4;
}

struct FreeBusyQuery {
    # Contact or user IDs to query.
    contactIds @0 :List(T.ContactId);
    # Time range to query.
    range @1 :TimeRange;
    # Calendar IDs to include (empty = all calendars).
    calendarIds @2 :List(T.CalendarId);
}

struct FreeBusyResult {
    entries @0 :List(FreeBusyEntry);
}

struct FreeBusyEntry {
    contactId @0 :T.ContactId;
    status @1 :FreeBusyPrivacy;
    start @2 :T.Timestamp;
    end @3 :T.Timestamp;
    # Whether event details are hidden (privacy).
    detailsHidden @4 :Bool;
}

# ── Structured Location (audit-7) ─────────────────────────────

struct EventLocation {
    # Human-readable address.
    address @0 :Text;
    # Geographic coordinates.
    latitude @1 :Float64;
    longitude @2 :Float64;
    # Virtual meeting URL.
    virtualUrl @3 :T.Uri;
    # Room or venue name.
    room @4 :Text;
}

# ── Video Conference (audit-7) ────────────────────────────────

struct VideoConference {
    # Meeting URL.
    url @0 :T.Uri;
    # Dial-in phone number.
    dialIn @1 :Text;
    # Conference PIN.
    pin @2 :Text;
    # Provider name (e.g., "zoom", "teams", "meet").
    provider @3 :Text;
}

# ── Event Attachment (audit-7) ────────────────────────────────

struct EventAttachment {
    # Attachment name/title.
    name @0 :Text;
    # MIME type.
    mimeType @1 :Text;
    # Attachment data (inline or buffer).
    data @2 :T.DataHandle;
    # Attachment URI (for external references).
    uri @3 :T.Uri;
}

# ── Time Range ────────────────────────────────────────────────

struct TimeRange {
    start @0 :T.Timestamp;
    end @1 :T.Timestamp;
}

# ── Event Filter ──────────────────────────────────────────────

struct EventFilter {
    title @0 :Text;
    location @1 :Text;
    status @2 :EventStatus;
    # ── Audit-7 additions ────────────────────────────────────
    dateRange @3 :TimeRange;
    attendee @4 :Text;
    hasRecurrence @5 :Bool;
}

# ── Holiday Calendar (audit-7) ────────────────────────────────

struct HolidayCalendar {
    # Holiday set name.
    name @0 :Text;
    # Region/country code (e.g., "US", "ZA").
    region @1 :Text;
    # Year this calendar applies to.
    year @2 :UInt32;
    # Custom holidays defined by the user.
    customHolidays @3 :List(Holiday);
}

struct Holiday {
    name @0 :Text;
    date @1 :T.Date;
    # Whether this is a recurring annual holiday.
    recurring @2 :Bool;
}

# ── Calendar Sync (false positive: calendar_sync.capnp) ───────

struct CalendarSyncResult {
    # New sync token to use for next sync.
    newSyncToken @0 :Text;
    # Events added or modified since last sync.
    changed @1 :List(Event);
    # Event IDs deleted since last sync.
    deleted @2 :List(T.EventId);
    # Whether there are more changes to fetch.
    hasMore @3 :Bool;
    # Sync conflicts that need resolution.
    conflicts @4 :List(SyncConflict);
}

struct SyncConflict {
    # Unique conflict identifier.
    conflictId @0 :Text;
    # The event with the conflict.
    eventId @1 :T.EventId;
    # Local version of the event.
    localVersion @2 :Event;
    # Remote version of the event.
    remoteVersion @3 :Event;
    # Timestamp when conflict was detected.
    detectedAt @4 :T.Timestamp;
}

enum ConflictResolution {
    keepLocal @0;
    keepRemote @1;
    merge @2;
    custom @3;
}

# ── Series Edit Scope (audit-7) ───────────────────────────────

enum SeriesEditScope {
    thisInstance @0;
    thisAndFuture @1;
    allInstances @2;
    custom @3;
}

# ── Working Hours (audit-7) ───────────────────────────────────

struct WorkingHours {
    # Working hours per day of week (index 0 = Sunday).
    days @0 :List(DayWorkingHours);
    # Timezone for working hours.
    timezone @1 :Text;
}

struct DayWorkingHours {
    day @0 :DayOfWeek;
    # Whether this is a working day.
    isWorkingDay @1 :Bool;
    # Start time (HH:MM format, e.g., "09:00").
    startTime @2 :Text;
    # End time (HH:MM format, e.g., "17:00").
    endTime @3 :Text;
}

# ── Delegation (audit-7) ──────────────────────────────────────

struct DelegatePermissions {
    canRead @0 :Bool;
    canWrite @1 :Bool;
    canCreate @2 :Bool;
    canDelete @3 :Bool;
    canShare @4 :Bool;
}

# ════════════════════════════════════════════════════════════════════════
# Audit-9 additions: calendar analytics, reminder escalation, color/theme
# integration, attendee response history, and format negotiation.
# ════════════════════════════════════════════════════════════════════════

# ── Calendar Analytics ──────────────────────────────────────────────────
# Aggregated analytics for calendar usage. Provides meeting load
# analysis and time tracking for schedule optimization.
struct CalendarAnalytics {
    calendarId @0 :T.CalendarId;
    totalEvents @1 :UInt32;
    totalMeetingMinutes @2 :UInt32;
    averageEventsPerDay @3 :Float32;
    busiestDayOfWeek @4 :DayOfWeek;
    busiestHourOfDay @5 :UInt32;
    meetingLoadScore @6 :Float32;
    freeTimePercentage @7 :Float32;
    analyzedRange @8 :TimeRange;
}

# ── Reminder Escalation ────────────────────────────────────────────────
# Escalation chain for reminders. When a reminder is not acknowledged
# within the specified interval, the next escalation level triggers.
# Enables progressive notification (alert → email → SMS → phone call).
struct ReminderEscalation {
    reminderId @0 :T.ReminderId;
    levels @1 :List(EscalationLevel);
    # Maximum number of escalation cycles before stopping.
    maxCycles @2 :UInt32;
}

struct EscalationLevel {
    # Order in the escalation chain (0 = first).
    order @0 :UInt32;
    # Delay before this level triggers after the previous level.
    delayAfterPrevious @1 :T.Duration;
    # Notification method for this level.
    method @2 :ReminderMethod;
    # Recipients for this escalation level (user IDs or addresses).
    recipients @3 :List(Text);
}

# ── Calendar Color/Theme Integration ───────────────────────────────────
# Links a calendar to a theme color configuration. Enables per-calendar
# color coding in calendar UIs with system theme awareness.
struct CalendarThemeConfig {
    calendarId @0 :T.CalendarId;
    # Primary color for this calendar's events.
    primaryColor @1 :T.Color;
    # Accent color for this calendar's events.
    accentColor @2 :T.Color;
    # Whether to use the system theme's color scheme.
    useSystemTheme @3 :Bool;
    # Opacity for event rendering (0.0 = transparent, 1.0 = opaque).
    opacity @4 :Float32;
}

# ── Attendee Response History ──────────────────────────────────────────
# Detailed response tracking for event attendees. Records each
# status change with timestamp for compliance and audit.
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
# Supported import/export format capabilities. Enables clients to
# discover which formats the backend supports before calling
# importEvents or exportEvents.
struct FormatCapability {
    formatId @0 :Text;
    name @1 :Text;
    mimeType @2 :Text;
    supportsImport @3 :Bool;
    supportsExport @4 :Bool;
    maxEventsPerBatch @5 :UInt32;
}

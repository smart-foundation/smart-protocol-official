# Audit — calendar.capnp (552 lines)

## Verdict
**FIX (targeted).** A well-structured file with a correct zero-cost posture (`EventAttachment.data @2 :T.DataHandle`, `:351`; import/export as `T.DataHandle`, `:55`, `:58`), pagination on the hot paths (`:24`, `:27`, `:29`, `:30`), and a pull-paginated subscription (`:116`). Four defects: a vendor-named subscription enum, a recurrence struct that carries two competing representations with no precedence rule, a privacy enum used as a status, and a five-boolean delegation model that duplicates `capability.capnp` wholesale.

## Wire-breakers
None. Method ordinals @0–@33 unique (`:23-109`); `Event` @0–@21, `CalendarInfo` @0–@10, `Recurrence` @0–@10 all collision-free; every `T.*` reference resolves.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R5/R1 | `calendar.capnp:151-157` `CalendarSubscription` (ical/caldav/**google**/**exchange**/custom) | Two values are vendor product names | A 2046 implementation talking to a CalDAV-compatible server (Radicale, Fastmail, a self-hosted Baïkal) has no value; `custom @4` carries nothing, so `CalendarInfo.subscription @8` (`:136`) cannot report what the calendar actually is, and a consumer cannot branch on or display it. `ical`/`caldav` are protocols and would survive; `google`/`exchange` assert that 2026's vendors still exist |
| R7 | `calendar.capnp:190-205` `Recurrence` | Two representations of one fact with no precedence rule: structured (`frequency @0`, `interval @1`, `count @2`, `until @3`, `daysOfWeek @4`, `dayOfMonth @5`, `monthOfYear @6`) **and** a raw RFC 5545 `rrule @8 :Text` | The classic fork: two backends expand the same recurring event differently depending on which field they honour, and a consumer has no way to know which is authoritative. A backend that fills `rrule` but not `frequency` produces an event whose series is invisible to any consumer that only reads the structured fields. Every consumer must re-implement "which wins" |
| R3 | `calendar.capnp:460-466` `DelegatePermissions` (canRead/canWrite/canCreate/canDelete/canShare) used by `delegateCalendar @25` (`:82`) | Five booleans implementing RBAC — explicitly forbidden ("Do NOT define permission strings, boolean flags, or role-based access control", `DESIGN_PRINCIPLES.md:399`) | A second authority system parallel to `capability.capnp` (which already has `attenuate @2`, `revoke @4`, `revokeControlled @9`). Delegation semantics must be implemented twice, and the two systems can disagree about who may read a delegated calendar — a delegation granted here can outlive a capability revoked there |
| R1 | `calendar.capnp:141-149` `CalendarType` (gregorian/lunar/hebrew/islamic/persian/buddhist/custom) | Names calendar systems in a closed list | A 2046 implementation of the Chinese, Japanese, Coptic, Ethiopian or Hindu calendar has `custom @6` carrying nothing, so `CalendarInfo.calendarType @7` (`:135`) is unreportable. The calendar systems that exist are not closed by mathematics, and this list is six of them |
| R4 | `calendar.capnp:286-292` `FreeBusyPrivacy` used as `FreeBusyEntry.status @1` (`:309`) | The enum's values (free/busy/tentative/outOfOffice) are *statuses*, but the type is named *privacy*, and it is assigned to a field named `status` | Three names for one concept in three lines. A consumer reading `entry.status :FreeBusyPrivacy` must go to the enum to discover it is not about privacy. `contacts.capnp:403` spells the identical value set `FreeBusyStatus` — the correct name already exists |
| R7 | `calendar.capnp:452-455` `DayWorkingHours.startTime/endTime :Text` "HH:MM" | Stringly-typed time-of-day with no offset or DST binding | "09:00" means something different on either side of a DST transition; two backends will resolve the same string to different instants. No `T.*` type covers time-of-day, which is the real gap being papered over |

## Duplicates & overlaps
- `FreeBusyPrivacy` (`:286-292`) ≡ `contacts.capnp:403-409` `FreeBusyStatus`; `queryFreeBusy @14` (`:46`) ≡ `contacts.capnp:86` `getFreeBusy @18`.
- `ConflictResolution` (`:423-428`) is identical to `vcard.capnp:667-672` — same name, same values, two files.
- Local `TimeRange` (`:358-361`) is the third copy, contradicting `types.capnp:1553-1556`.
- `searchEvents @16` (`:52`) overlaps `system_search.capnp`'s whole contract (which already indexes contacts, calendar, documents).
- `Event.reminders @10 :List(Reminder)` and the escalation machinery (`:492-508`) duplicate `notification.capnp`'s alarm/notification path.

## Gaps & holes
- **Recurrence across DST and time zones.** `Event.timezone @7 :Text` (`:169`) exists, but `Recurrence` has no timezone field, so a daily 09:00 event that crosses a DST boundary has no declared expansion. Every backend invents one, and consumers cannot predict. This is the highest-value gap in the file and it is a direct consequence of the two-representation problem above.
- `updateEventSeries @19 (scope :SeriesEditScope)` (`:61`) has `modifiedInstances @10 :List(Event)` on `Recurrence` (`:204`) but no contract for how a series edit interacts with already-modified instances.
- `delegateCalendar`/`revokeDelegation` (`:82`, `:85`) grant by `T.UserId` with no record of *who granted* — `CallerIdentity` exists in `access.capnp:97-104` and is not used.
- `respondToEvent @9 (response :AttendeeStatus, comment :Text)` (`:35`) has no RSVP lifecycle contract (is `delegated @4` terminal? can a tentative response be withdrawn?).

## Zero-cost & eco
Pass: `EventAttachment.data @2 :T.DataHandle` (`:351`), import/export as `T.DataHandle` (`:55`, `:58`), all list methods paginated with `totalCount`. `Recurrence.modifiedInstances @10 :List(Event)` (`:204`) is the one unbounded nested list — a series with hundreds of exceptions copies them all into every event.

## UX & implementer guidance
- `FreeBusyEntry.detailsHidden @4 :Bool` (`:313`) is the right privacy control, but nothing says *what* is hidden — the entry still carries `contactId`, `start` and `end`, so a "hidden" event is still a busy-slot disclosure by construction.
- `VideoConference.provider @3 :Text` with examples "zoom", "teams", "meet" (`:340`) — vendor names in a doc comment feeding an open field. Acceptable as an open value, but the examples will be copied as an enum by the next implementer.
- `AttendeeRole.duplicate @4` (`:268`) is not a role any consumer can act on; it is an iCalendar bookkeeping detail leaked into the wire.
- `EscalationLevel.recipients @3 :List(Text)` (`:507`) is documented as "user IDs or addresses", mixing two namespaces in one list.

## Recommended actions
1. **Declare `Recurrence` precedence: either the structured fields are authoritative and `rrule` is an opaque backend hint, or `rrule` is authoritative and the structured fields are a projection — and say which in the schema.** Gain: the series-expansion fork disappears; cost: one comment, and backends must honour it. This is the cheapest high-value fix in the file.
2. **Replace `CalendarSubscription`'s `google`/`exchange` with open `Text` tokens.** Gain: any CalDAV-compatible or future service becomes reportable; cost: consumers switch on strings.
3. **Replace `DelegatePermissions` with a `Capability`-derived grant** (hand `delegateCalendar` an attenuated capability whose `target` is the calendar). Gain: delegation joins the one authority model; cost: the method grows a capability parameter and the five booleans are removed.
4. **Rename `FreeBusyPrivacy` → `FreeBusyStatus` and use the canonical one across contacts/calendar.** Gain: three names become one; cost: a type rename plus removal of the contacts duplicate (see the contacts report).
5. **Give `Recurrence` a timezone field (or state that it inherits `Event.timezone`).** Gain: DST-crossing series becomes predictable; cost: one field.
6. **Replace `DayWorkingHours.startTime/endTime :Text` with a typed time-of-day.** Gain: HH:MM stops being an unvalidated string; cost: one new primitive in `types.capnp` — only worth it if calendar and `timezone.capnp` both need it.

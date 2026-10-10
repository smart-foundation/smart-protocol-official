# Audit — time.capnp (413 lines)

## Verdict
**FIX (targeted).** This file contains the batch's only **compile-clean wire-semantics breaker**: two structs named `TAITimestamp`/`TaiTimestamp` with epochs 12 years apart (`time.capnp:219` = TAI seconds since 1958; `timezone.capnp:399` = TAI seconds since 1970). Both are bare `UInt64` seconds, so nothing catches a consumer passing one to the other. Beyond that: the alarm CRUD duplicates `clock.capnp`'s (inferior this time), its `TimeZone` struct duplicates `timezone.capnp`'s richer `TimezoneInfo`, and its leap-second types duplicate that file's with different fields.

## Wire-breakers
- **`TAITimestamp` (`time.capnp:219-224`, "TAI seconds since epoch (1958-01-01)") vs `TaiTimestamp` (`timezone.capnp:399-404`, "TAI seconds since Unix epoch (1970-01-01)")**: epochs differ by 3784320410 s (Jan 1958 → Jan 1970) plus the leap-second offset. A consumer passing one struct to the other's converter (`taiToUtc @13` here vs `convertFromTai @25` there) gets a timestamp ~120 years wrong. **No compile error**: both are `UInt64` seconds with one-letter-case-different names. This is a silent data-corruption class bug, not a lint.
- `Alarm` (:143) vs `clock.capnp:207` — same name, incompatible fields; both live.
- `TimeRange` in this file? No — but the file's consumers pass `types.capnp` TimeRange (`UInt64` ms) and `timezone.capnp` TimeRange (`T.Timestamp`) freely; see BATCH-SUMMARY.
- `LeapSecondAnnouncement` (:114 vs `timezone.capnp:386`, different fields), `LeapSecondSubscription` (:109 vs `:381`), `TimerSubscription` (:104 vs `clock.capnp:179`, and the two carry different payloads: bare `T.Timestamp` vs `TimerEvent` with timer identity).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R6 | `time.capnp:219-224` vs `timezone.capnp:399-404` | Two TAI timestamp structs, different epochs, near-identical names | See wire-breakers. One of them must yield; the epoch that matches `T.Timestamp` semantics (Unix epoch, the timezone.capnp one) is the natural survivor |
| R6 | `time.capnp:10-13` | Alarm CRUD (`getAlarm`/`setAlarm`/`cancelAlarm`/`listAlarms`) with its own `Alarm`/`AlarmTime`/`AlarmAction`/`AlarmSnoozePolicy` vs `clock.capnp:207-284`'s richer alarm model | Two alarm stores; this file's version lacks `recurrence` and `holidayBehavior` that clock's has, while having `action`/`sound`/`timezoneAware` clock's lacks. A 2028 implementer must merge both field sets by hand or pick one and lose features |
| R6 | `time.capnp:135-141` | `TimeZone { id, displayName, abbr, utcOffsetSeconds, isDst }` returned by `getTimeZone @1`, vs `timezone.capnp:129-180`'s 17-field `TimezoneInfo` | Two timezone descriptors; `setTimeZone @2` takes a zone id that must resolve against a database this file doesn't reference. A consumer rendering a zone picker uses one; converting a timestamp uses the other — no rule which is canonical |
| R6 | `time.capnp:114-119`, `:199-215` vs `timezone.capnp:386-395`, `:312-321` | `LeapSecondAnnouncement`, `LeapSecondSubscription`, `LeapSecondTable`, `LeapSecondEntry` vs timezone's `LeapSecondAnnouncement`**s**, `LeapSecondSubscription`, `TimezoneLeapSecond` | The leap-second contract exists twice with different field sets (`scheduledDate`+`timestamp` vs `effectiveAt`+`publishedBy`). Two backends, two announcement shapes |
| R6 | `time.capnp:265-278` vs `timezone.capnp:340-351` | `BusinessHours` vs `TimezoneBusinessHours` — near-identical, different field sets (time adds `holidays`) | Two business-hours types in one batch |
| R1 | `time.capnp:254-261` | `ClockSourceType` = ntp/ptp/gps/galileo/atomic | Technology names in a required position; a 2046 time source (terrestrial optical, quantum) has no value. (`network.capnp:146` and `clock.capnp:47` model the same state without the enum — inconsistent within the batch) |
| R1 | `time.capnp:293-301` | `CalendarSystem` = gregorian/julian/islamic/hebrew/chinese/ethiopian | Culture-closed set (defensible; `custom @6` present). Flagged and cleared — but note `HistoricalDate.calendar @3 :CalendarSystem` makes the enum load-bearing for every conversion |
| R7 | `time.capnp:72`, `:96-102` | `setRelativeAlarm @27 (baseEvent :Text, ...)` and `RelativeAlarm` (unused) — "remind me in 2 hours from when I finish this task" | `baseEvent :Text` references an event concept no schema defines; the struct is returned by nothing. Half-specified feature: backends each invent their own event vocabulary |
| R7 | `time.capnp:166-168` | `AlarmTime.dayOfMonth :Int32`/`month :Int32` with "-1 means any", documented in-file (:163-165) as a wire-compat compromise | A sentinel-value contract; the comment is honest and the constraint real (frozen ordinals), so this is a **deferred** fix, not a violation — flagged so the rewrite wave remembers it |
| R7 | `time.capnp:69` | `verifyHsmTimestamp @26 -> (verified :Bool, message :Text)` | A bool+text instead of `T.BoolResult`; `message` carries no code and no `retryable` |
| R8 | `time.capnp:228-235`, `:96-102` | `MonotonicClockInfo` and `RelativeAlarm` unused | Dead types |

Validator counts: E7 ×20, E8 ×9, E6 ×0.

## Duplicates & overlaps
- All the R6 rows: alarm (clock), timezone descriptor (timezone.capnp), leap seconds (timezone.capnp ×3 types), business hours (timezone.capnp), recurrence (timezone.capnp's RRULE), DST policy (`DstResolvePolicy` :346 vs timezone's `isDstGap`/`isDstOverlap` methods — two DST-resolution contracts).
- `TAITimestamp` conversion methods (:32-35) vs timezone's `convertToTai`/`convertFromTai` (:100-103) — two conversion APIs for one table.

## Gaps & holes
- No timezone-change *event* on `Time` (the service that owns `setTimeZone @2`): `timezone.capnp:8` `subscribeTimezones` exists, so the event lives in the other file — a consumer watching "the system timezone changed" must hold the timezone service, not the time service.
- `getLeapSecondTable @12` (:29) returns a table with no pagination (leap seconds are ~27 and bounded — defensible) and `currentOffset :UInt16` (:205) is a live field that will go stale on the next insertion with no update contract.

## Zero-cost / eco
- No bulk payloads. `HSMTimestamp.signature`/`certificateChain` are `T.DataHandle` (:322-323) — correct.
- `getUpcoming @10` (:19) unbounded, documented, with `getUpcomingPaged @11` alongside — the sanctioned deprecation pattern (deprecate the unbounded one, per capability.capnp:397-402). Flagged as pending, not broken.

## UX & implementer guidance
- `getUpcoming @10 (duration)` returns "events" whose `type @1 :TimeEventType` includes `alarm`/`timer` (:186-195) — events owned by `clock.capnp` surfaces; the "upcoming" query silently spans two services' data.
- `formatDuration @19`/`humanizeDuration @29`/:30 (:50/:78/:81) — humanization as an RPC on the time service is a locale-bound utility; two methods (`humanize` and `humanizeApprox`) differ only by precision. The split is defensible; note that locales arrive as bare `Text` with no locale vocabulary.
- `convertCalendar @28` (:75) takes `fromSystem :CalendarSystem`/`toSystem :CalendarSystem` — correct shape, but the two systems are enum values from the *frozen* calendar list; a culture's calendar not in the enum has only `custom`.

## Recommended actions
1. **Unify the TAI epoch**: delete this file's `TAITimestamp` in favor of `timezone.capnp`'s `TaiTimestamp` (Unix-epoch, matching `T.Timestamp`), retarget `taiToUtc`/`utcToTai` @13/@14 to it, and fold the conversion surface into `timezone.capnp`'s `convertToTai`/`convertFromTai`. Gain: eliminates a silent 120-year data-corruption class that no compiler catches. Cost: one method pair retargeted — and it is a wire-semantics change, which is exactly why it must happen pre-release.
2. **Make `clock.capnp` the canonical alarm home** (see clock audit action 1); deprecate this file's alarm methods with comments. Gain: richer model survives; two stores become one. Cost: four deprecation comments.
3. **Delegate timezone data**: `getTimeZone @1` should return `TimezoneService`'s `TimezoneInfo` (or this file should hold a reference to the timezone service); delete the local `TimeZone` struct. Gain: one timezone descriptor. Cost: one field type change.
4. **Consolidate leap seconds and business hours into `timezone.capnp`** (it already owns `subscribeLeapSecondAnnouncements` and `getLeapSeconds`); retarget this file's `@12`/`:199-215` types there or delete them. Gain: one leap-second contract, one business-hours type. Cost: one method retargeted plus type deletions.
5. **Fix `verifyHsmTimestamp`** to return `T.BoolResult` (or a struct with `T.Error`). Gain: honest, machine-routable failure. Cost: one signature.
6. **Delete the dead types** (`MonotonicClockInfo`, `RelativeAlarm`) or wire `setRelativeAlarm` to a defined base-event contract. Gain: removes two half-features. Cost: zero to one comment.

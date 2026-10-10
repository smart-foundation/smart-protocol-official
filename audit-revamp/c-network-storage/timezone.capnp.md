# Audit — timezone.capnp (500 lines)

## Verdict
**FIX (targeted).** This is a well-built catalog service — paginated everywhere it matters, DST gap/overlap as first-class queries, RRULE support, tzdb update subscriptions. Three targeted items: it co-owns the **TAI epoch conflict** with `time.capnp` (its Unix-epoch `TaiTimestamp` is the correct survivor), its local `TimeRange` carries a comment claiming a re-export from `types.capnp` that does not exist and has an incompatible unit, and its leap-second/business-hours types duplicate `time.capnp`'s. Also the one privileged method (`setDefaultTimezone @6`) has no capability gating narrative.

## Wire-breakers
- **TAI pair** (see `time.capnp` audit): this file's `TaiTimestamp` (:399-404, seconds since 1970) is the semantically correct one; the fix is to adopt it in `time.capnp` and delete the other. This file's conversion methods (`convertToTai @24`, `convertFromTai @25`, :100-103) should become the single conversion surface.
- **`TimeRange` (:305-308)**: the comment at :304 says "Re-exported from types.capnp conceptually; defined here for self-containment" — it is *not* a re-export and not the same type. `types.capnp:1553` `TimeRange` is `{start :UInt64, end :UInt64}` in **Unix milliseconds**; this one is `{start :T.Timestamp, end :T.Timestamp}` nanoseconds. A consumer who believes the comment and substitutes `T.TimeRange` compiles cleanly with values 10^6 off.
- `ConvertResult` (:247) vs `archive.capnp:543` `ConvertResult` — same name (both success/error unions), different meanings entirely.
- `LeapSecondAnnouncement` (:386) vs `time.capnp:114` (different fields), `LeapSecondSubscription` (:381 vs time.capnp:109), `TimezoneLeapSecond` (:312) vs `time.capnp`'s `LeapSecondEntry` (:208) — leap-second modeled four ways across two files.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R6 | `timezone.capnp:304-308` | `TimeRange` with a false re-export comment | See wire-breakers. The comment actively causes the bug it appears to prevent |
| R6 | `timezone.capnp:386-395`, `:312-321`, `:340-351` | `LeapSecondAnnouncement`, `TimezoneLeapSecond`, `TimezoneBusinessHours` duplicate `time.capnp`'s `LeapSecondAnnouncement`/`LeapSecondEntry`/`BusinessHours` with different fields | Two leap-second contracts (this file's version has `publishedBy` — better — and time's has `scheduledDate`); a consumer of both must carry both shapes. This file should win; time.capnp's copies should be deleted after the deprecation cycle |
| R3 | `timezone.capnp:37` | `setDefaultTimezone @6` — "requires privilege" in a comment, with no gating accessor and no capability parameter | The whole service is one reference, so "requires privilege" is unenforceable at the contract level. Every backend invents its own check outside the protocol. The doctrine's shape (DESIGN_PRINCIPLES.md:364-380: ungated discovery + gated accessor returning the service) is the fix |
| R7 | `timezone.capnp:247-252` | `ConvertResult` union lacks unknown/custom (validator E6) | A future conversion outcome (ambiguous offset? leap-second-in-range?) has no variant; and the name collides with archive.capnp's |
| R7 | `timezone.capnp:46` | `getTimezonesWithDst @9 -> List(TimezoneInfo)` unbounded | Returns a potentially large list of full `TimezoneInfo` structs (17 fields each) in one message — the one unbounded list in the file |
| R1 | `timezone.capnp:9-10` | Header claims "no POSIX TZ env, no system zoneinfo dependencies" while the entire model is IANA tzdb (`id`, `aliases`, `getTzdbVersion @22`, `DatabaseUpdate`) | Mild overclaim: tzdb is the only universal calendar data in existence, so the *dependency on the data* is right — the phrasing promises an independence no implementation has. The honest statement: "takes tzdb (or an equivalent) as input; the protocol does not mandate its delivery mechanism" |
| R1 | `timezone.capnp:417-425` | `TimezoneRegion` enum — unused (the by-region methods take `region :Text`, :106) | Another enum/Text split; the enum is dead (also `TaiUtcConversion` :406-413 unused; `RankedTimezone` used only by `getRankedTimezones` :110 — fine) |
| R4 | `timezone.capnp:164` | `TimezoneInfo.coordinates @11 :T.Vec2` (`Float32`) | Float32 lat/long degrades the coordinate→zone queries (`getTimezoneForCoordinates` :73) near zone edges; `T.GeoCoordinate` (`types.capnp:1441`, `Float64`) exists |

Validator counts: E7 ×22, E8 ×3, E6 ×1.

## Duplicates & overlaps
- Leap-second trio and business hours vs `time.capnp` (above).
- `ConvertResult` vs `archive.capnp`.
- `RecurrenceFrequency` (:437) vs `time.capnp`'s `RecurrenceType` (:368) — same five values, two names; and `RecurrenceRule` (:445) vs time's `RecurrencePattern` (:353) vs clock's `AlarmRecurrence` — recurrence modeled three ways in the batch.
- `ResolvedEvent` (:368) vs `ResolvedRRuleEvent` (:470) — two shapes for one concept in one file (the RRULE one adds `isException`).

## Gaps & holes
- No `setDefaultTimezone` event other than through `subscribeTimezones` — fine — but nothing states what a *default changed* event means for already-issued timestamps (the `DefaultChange` event :290 exists, semantics undefined).
- `resolveRecurringEventRRULE @28` (:114) accepts `exceptions :List(RecurrenceException)` and `maxOccurrences` — bounded correctly — but there is no `count`/`until` semantics statement for `RecurrenceRule.count @5`/`untilDate @6` (:456-458) relative to the method's own `maxOccurrences` (which wins?).

## Zero-cost / eco
- No bulk payloads. All list results are `TimezoneInfo`-sized and paginated except `getTimezonesWithDst` (above). No polling patterns (three pull+cancel subscriptions). No findings.

## UX & implementer guidance
- `listTimezonesByRegion @26 (region :Text)` (:106) and `TimezoneRegion` (:417) — the Text vs enum split means "region" has two vocabularies and the dead one is the typed one.
- `getTzdbVersion @22 () -> (version :Text)` (:94) — version as free text ("2024a" style); `DatabaseUpdate.version` (:284) matches, so it is at least self-consistent.
- `getHistoricalOffset @18` returns `UtcOffset` (with `effectiveFrom`/`effectiveUntil` timestamps) for a *date* query — the returned offset's timestamps are informational; the file doesn't say whether to trust `at` or the returned `effectiveFrom`.

## Recommended actions
1. **Win the TAI conflict**: adopt this file's `TaiTimestamp` in `time.capnp` (retarget `taiToUtc`/`utcToTai`), and delete this file's unused `TaiUtcConversion` (:406-413). Gain: one TAI convention, the silent-corruption class closes. Cost: one method retarget in time.capnp.
2. **Fix the `TimeRange` comment and the type**: either delete the local `TimeRange` and use `T.TimeRange` *after* types.capnp's is aligned (BATCH-SUMMARY action 4), or rename the local one (`TimeWindow`) and drop the false re-export claim. Gain: removes a comment that actively causes a 10^6 unit bug. Cost: one type rename or a types.capnp alignment.
3. **Consolidate leap seconds and business hours here** (delete `time.capnp`'s copies after deprecation; this file's versions are richer — `publishedBy`, and the subscription already exists here). Gain: one contract each. Cost: type deletions in time.capnp.
4. **Gate `setDefaultTimezone`** per the doctrine: split into ungated `getDefaultTimezone @5` and a gated acquisition (or document that holding this reference is the authority, obtained through the capability system). Gain: the privilege claim becomes contract-enforced instead of comment-declared. Cost: one accessor-shaped method or a comment that names the authority path.
5. **Delete the dead types** (`TimezoneRegion`, `TaiUtcConversion`) and add a `custom`/`unknown` variant to `ConvertResult` (rename to avoid the archive collision — e.g. `ZoneConversionResult`). Gain: closes E6 and a name collision. Cost: zero plus one variant.

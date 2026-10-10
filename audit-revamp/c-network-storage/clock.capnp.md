# Audit — clock.capnp (332 lines)

## Verdict
**KEEP.** The core is exemplary for this batch: `T.Duration` everywhere, `TimerAnchor` as an explicit union (:88-97), `ClockDomainInfo` for capability discovery, `T.VoidResult` for cancellations, pull+cancel+`pullPaginated` subscriptions, virtual clocks for testability. The only structural item is that its `Alarm`/`AlarmService` block (:207-284) duplicates `time.capnp`'s alarm CRUD with a *different* struct — and since this file's version is the richer one (recurrence + holiday awareness), the right resolution is to make this the canonical alarm home and deprecate time.capnp's four alarm methods. Minor: one union missing its `unknown/custom` variant, and `checkTimer` invites polling next to a subscription that already exists.

## Wire-breakers
No compile errors. `Alarm` (:207) vs `time.capnp:143` `Alarm` — same name, different fields (clock's: `recurrence`, `holidayBehavior`, `snoozeDuration`; time's: `time`, `message`, `sound`, `action`, `repeats`, `snoozes`, `timezoneAware`). Both are returned by their own services' getters, so both are live — a consumer handling "an alarm" must carry both shapes. `DayOfWeek` (:243) vs `calendar.capnp:215`.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R7 | `clock.capnp:88-97` | `TimerAnchor` union (`absolute`/`relative`/`zero`) has no unknown/custom (validator E6) | A future anchor semantics (e.g. "fire after N events") has no variant; absent anchorType silently means `absolute`, so an old consumer reading a producer's *relative* intent fires at epoch-0 or never |
| R7 | `clock.capnp:117` | `checkTimer @6 (timer) -> (fired :Bool)` — a polling API next to `subscribeTimers @7` (:119) in the same interface | The eco finding: the subscription exists (pull+cancel, `TimerPullResult` paginated), but `checkTimer` invites the classic busy-poll loop for timer state. The file offers both with no guidance on which — backends optimize for the poller |
| R7 | `clock.capnp:280` | `AlarmService.listAlarms @4 () -> (alarms :List(Alarm))` unbounded; `listPersistedTimers @17` (:148) unbounded | Alarm/timer catalogs grow without bound; one message carries them all, inconsistent with `T.Pagination` used elsewhere in the file (:187) |
| R6 | `clock.capnp:207-284` | The whole alarm block duplicates `time.capnp:143-176` + its four alarm methods (@3-@6) with incompatible structs | Two alarm stores, two shapes. `T.AlarmId` was promoted to `types.capnp:1001` "for cross-schema alarm references (notification, calendar)" — but with two CRUD surfaces, a 2028 implementer wiring calendar alarms must guess which service stores them and which shape applies |
| R1 | `clock.capnp:263-273` | `HolidayMode` = fire/skip/adjust/snooze | Mostly math-closed (what an alarm can do at a holiday); defensible. `CalendarSystem`-adjacent policy — flagged and cleared |
| R7 | `clock.capnp:25`, `:51` | `ClockInfo.sourceName :Text` comment names "tsc/hpet/CLOCK_MONOTONIC"; `ClockSyncInfo.source :Text` names "ntp.pool.org" | Open Text — correct choice; flagged only because `time.capnp` and `network.capnp` model the same sync state as a third, differently-shaped type |

Validator counts: E7 ×19, E8 ×3, E6 ×1.

## Duplicates & overlaps
- Alarm CRUD vs `time.capnp` (above) — the one real duplicate.
- Time-sync vs `network.capnp:146` `getTimeSync` (tuple) and `time.capnp:239-261` `ClockSource` — three representations, three shapes.
- `TimerEvent` (timer handle + firedAt + count) vs `time.capnp`'s `TimerSubscription.pull -> timestamp` (a bare `T.Timestamp`) — two timer-event contracts; time's carries no timer identity at all, so a consumer of *that* subscription cannot tell which timer fired.
- `DayOfWeek` vs calendar; `AlarmRecurrence.cron @3 :Text` (:230) vs `timezone.capnp` `RecurrenceRule` — recurrence modeled three ways in the batch (clock's weekly/monthly, time's `RecurrencePattern`, timezone's full RRULE).

## Gaps & holes
- Timer dependence: `setTimerDependency @18` (:151) sets "depends on" ordering but nothing states what a dependency *means* at firing time (chain? gate?) — a one-line contract is missing and backends will invent it.
- `persistTimer @16` (:145) promises timers "survive process exit" but names no storage, no ownership on restart, no conflict rule if the name exists.
- `sleep @8` (:121) has no cancellation; `sleepCancellable @10` (:127) has it — fine, but the file doesn't say which is preferred.

## Zero-cost / eco
- No bulk payloads; no inline lists except the two unbounded catalogs (above).
- `checkTimer` polling (above) is the only eco item. Subscriptions themselves are pull+cancel — canonical.

## UX & implementer guidance
- `ClockSyncInfo.stratum @2 :UInt32` (:53) — NTP stratum as a live field; a PTP-synced clock has no stratum (documented as "1 = directly connected", NTP semantics only).
- `TimerSpec.priority @7 :UInt32` (:84) — "higher = fires first" is a scheduler hint (TIMELESSNESS.md:84 class); harmless at 332 lines but the pattern to watch.
- `getClockQuality @15 (sourceName :Text)` (:142) — keyed by the same free-text source names the comments invent; a backend with no named sources can't be queried.

## Recommended actions
1. **Make this file the canonical alarm home**: keep `Alarm`/`AlarmService` here (it has recurrence + holiday behavior; `time.capnp`'s alarm struct has neither) and deprecate `time.capnp`'s `getAlarm`/`setAlarm`/`cancelAlarm`/`listAlarms` (@3-@6) with comments pointing here — ordinals preserved per TIMELESSNESS.md:97. Gain: one alarm contract, the richer one survives; the calendar/notification cross-references finally resolve. Cost: four deprecated methods in time.capnp (comments only) — no wire break.
2. **Add a `custom`/`unknown` variant to `TimerAnchor`.** Gain: closes the repo's own E6/TIMELESSNESS:98 rule; gain is real but small. Cost: one variant.
3. **Deprecate `checkTimer` in favor of `subscribeTimers`** (or document when polling is the sanctioned path). Gain: removes the busy-poll invitation on the file's own admission. Cost: one comment, or one ordinal retired.
4. **Paginate `AlarmService.listAlarms` and `listPersistedTimers`** (`page :T.Pagination`, `total :UInt64`). Gain: bounded catalogs, consistent with the file's own subscriptions. Cost: two params.
5. **State what `setTimerDependency` means at fire time** (one sentence: gated vs. chained). Gain: removes a contract hole every implementer currently fills differently. Cost: one line.

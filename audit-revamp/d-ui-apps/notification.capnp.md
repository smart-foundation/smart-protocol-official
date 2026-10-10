# Audit — notification.capnp (379 lines)

## Wire & verdict first: this is the batch's canonical notification service (doctrine:541) and its type model is right — channels, threads, attestation, actions, pagination on reads. Three targeted fixes: the sender can claim success on a failed send, `getActive`/`getHistory` answer with a bounded list but no total, and the audit-9/10 stack (inter-service notifications, delivery tracking, priority queue, analytics) is a notification *server's* internal machinery exposed as contract with no consumer protocol behind it. Fix type-level honesty first, then decide the machinery's fate.

## Verdict
**FIX (targeted).** `NotificationData` (132–173) is the correct canonical shape — `T.ChannelId`, `T.SoundId`, `T.DataHandle` for every image, `attestation`, channels with importance/DND bypass. Keep it and make shell delegate to it. The defects are at the method boundary.

## Wire-breakers
None.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R7 | `notification.capnp:30` | `show @0 (notification :NotificationData) -> (id :T.NotificationId)` — sending can fail (app lacks channel, quota, attestation invalid) yet the caller receives an id as if posted | An app "posts" a notification that was rejected and shows the user nothing; the ids it holds are tombstones. Every other capability-bearing domain in the batch returns `T.Error` on failure — `appindex.LaunchResult` (appindex.capnp:172) is the in-batch exemplar |
| R7 | `notification.capnp:34, 47` | `getActive @3 (pagination)` and `getHistory @8 (filter, pagination)` return `List(NotificationData)` with no `totalCount` | A notification-center UI cannot render "12 of 40" or know when to stop paging — it must page until empty on every open. Every other paginated method in the protocol returns a total |
| R7 | `notification.capnp:77, 80` | `getNotificationThread @17`/`getChildNotifications @18` return unbounded lists | A chatty thread (a messaging app's group) returns the entire chain; thread depth is unbounded by construction |
| R1 | `notification.capnp:356` | `QueuePriority { low, normal, high, critical }` — a fourth priority vocabulary alongside `UrgencyLevel` (188) and `aiPriority @16 :Float32` | Three priority systems in one file (urgency for display, queue priority for delivery, an AI float score) with no stated relationship; an implementer must guess how `UrgencyLevel.critical` interacts with `QueuePriority.low` |
| R6 | `notification.capnp:98, 103` | `sendInterServiceNotification @22` + `getDeliveryTracking @23`/`subscribeDeliveryTracking @24` create a *second* notification path for system services with its own source/target/eventType/payload model (316–322) | System services now have two ways to emit notifications with different metadata (no channels, no actions on the inter-service path); a receiver must implement both dispatch tables |
| R5 | `notification.capnp:252` | `NotificationChannel.lightColor :UInt32` — "notification LED (0 = no light)" hardcodes a hardware component that existed on 2010 phones | A 2046 display-only or audio-only device has no LED; the field is harmless as data but the contract presumes the component's existence in its comment semantics |
| R4 | `notification.capnp:53, 114` | `delegate @10 (handlerId :Text)`, `reprioritizeNotification @26` — routing and queue control addressed by free `Text` | Two services can claim the same handler string; delegation targets are unverifiable and unrevocable through the capability path — authority by naming, not by reference |

## Duplicates & overlaps
- vs `shell.capnp`: shell holds its own `Notification`/`NotificationAction`/`Urgency` (312–337) and six direct methods (82–93) — the doctrine's "delegate, don't duplicate" (218) is unresolved; shell's model *lacks* channels, so shell-posted notifications escape channel routing. Resolution: delete shell's copy, shell calls this service.
- `NotificationChannel.id` + `channel @21 :T.ChannelId` correctly use the promoted `T.ChannelId` — no duplication, this is the canonical home.
- `NotificationSource`/`NotificationSource.isSystemService` (309–314): system-service-ness is a trust label — belongs to `T.TrustLevel` (types.capnp:550) rather than a new boolean.

## Gaps & holes
- **DND semantics are split**: shell owns `getDoNotDisturb`/`setDoNotDisturb` (shell.capnp:88–89), this file owns per-channel `bypassDnd`. Neither says which wins when both exist — a genuine fork, resolvable by making this service the DND authority.
- **Replacement/update semantics of a live notification**: nothing states what `show` does when an app posts an id it already holds (replace? error? duplicate?). Each backend will pick differently; an app updating a progress notification cannot rely on either behavior.
- **Snooze semantics**: `snooze @7 (duration)` re-shows after a duration, but who persists it while the service restarts is undefined.

## Zero-cost / eco
- `NotificationsSubscription.pull @0 () -> (notifications :List(NotificationData))` — unbounded batch per pull with no `maxEvents`/pagination: not a copy-cost issue at normal rates, but a burst (say 50 app updates) returns all in one message with no caller-driven bound. Add a limit parameter.
- All payload graphics are `T.DataHandle` — correct.
- `aiPriority @16 :Float32`: an AI score inside the send struct forces every backend to either run a scorer or fake the field — compute-on-arrival is fine, but the field's presence in the *send* path invites fiction. Recommend: reported by the service on read, not accepted on write.

## UX & implementer guidance
- `verifyAttestation @21 -> AttestationVerification { valid, signer, timestamp, error :Text }` — error as `Text`, not `T.Error` (the protocol's error type); consumers cannot route on it.
- `delegate @10 (handlerId :Text)`: no way to enumerate handlers, so delegation targets are undiscoverable — implementers will hardcode strings.
- The audit-10 machinery (`getQueueStats`, `reprioritizeNotification`, `getDeliveryTracking`) exposes server internals (queue depth, wait times) as contract: harmless to read, but each is a method every implementation must at least stub, and two implementations will stub them differently — the fork cost the doctrine warns about.

## Recommended actions
1. **`show` returns a result union** (`id` + `T.Error`); same for `schedule @9`. Gain: rejected notifications stop being invisible success; apps can retry honestly (`retryable` set). Cost: two signatures — matches the batch's `LaunchResult` exemplar.
2. **`getActive`/`getHistory`/`getNotificationThread`/`getChildNotifications` gain `totalCount`** (and pagination on the thread getters). Gain: notification-center UIs stop guessing page ends. Cost: four return shapes.
3. **Delete shell's copy (shell.capnp:82–93, 312–337)** so this is the only notification contract, and make the DND authority explicit here (channels own DND; shell reads). Gain: one data model, one DND rule. Cost: shell loses ~8 methods it should not have had.
4. **Delete or quarantine the audit-10 machinery** (`sendInterServiceNotification`, `getDeliveryTracking`/subscription, queue stats/reprioritize/listQueued) unless a consumer is named. Gain: the contract shrinks to show/dismiss/list/subscribe/snooze/schedule/delegate/channels/history — a surface an implementer can complete honestly. Cost: inter-service delivery observability moves to a diagnostics service; acceptable.
5. **Collapse the three priority vocabularies**: `QueuePriority` folds into `UrgencyLevel`; `aiPriority` becomes read-only reported data. Gain: one ranking concept, no inter-vocabulary guessing. Cost: two fields removed from write paths.
6. **Resolve the "replace vs duplicate" question for `show` with an existing id** (one sentence in the contract + the behavior). Gain: progress notifications behave identically on every backend. Cost: one documented rule.

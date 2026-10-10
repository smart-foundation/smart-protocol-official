# Audit — contacts.capnp (617 lines)

## Verdict
**FIX (targeted).** On the axis most schemas in this batch fail, contacts is exemplary: `Contact.photo @5 :T.DataHandle` (`:169`), `exportContacts @19`/`importContacts @20` as `T.DataHandle` (`:90`, `:93`), typed sub-entry IDs (`T.EmailEntryId`/`T.PhoneEntryId`/`T.AddressEntryId` at `:243`, `:260`, `:280`) after the `types.capnp:623-631` promotion, `T.Date` for birthdays (`:174`), pagination on every list. One security hole dominates: `shareContact` shares a person's data with an arbitrary user with no authority gate and no consent check, in a file that also defines its own consent machinery. Plus 15 open-vocabulary enums and a local `TimeRange` that contradicts `T.TimeRange`.

## Wire-breakers
None. Ordinals @0–@35 are unique on the `Contacts` interface (`:45-146`); `Contact` fields run @0–@21 without collision; `ContactFilter` @0–@8; all `T.*` references resolve, including the three promoted sub-entry ids.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R3 | `contacts.capnp:101` `shareContact @22 (contactId :T.ContactId, targetUserId :T.UserId)` | Shares a contact's personal data to an arbitrary user with no capability, no consent check, no authority | Any holder of the `Contacts` reference can leak any contact to any user id. The file defines `ContactConsent`/`ConsentScope` (`:597-617`) for exactly this, and this method bypasses it. Cost: the privacy machinery the schema advertises is not wired to the one method that needs it, so every backend must invent the gate |
| R3 (soft) | `contacts.capnp:45` (whole interface) | No capability gating and no `using import "capability.capnp"` | Presence (`getPresence @12`), history (`getContactHistory @21`), and relationships (`getRelations @17`) are personal data exposed ungated. The doctrine's model gates once at acquisition (`ai.capnp:578-584`) |
| R1 | `contacts.capnp:610-617` `ConsentScope` (storage/sharing/analytics/marketing/all/custom) | A legal vocabulary frozen into a closed list | A 2046 jurisdiction needs "profiling", "automatedDecision", "crossBorderTransfer"; `custom @5` cannot say which, so compliance tooling cannot branch. `recordConsent @28`/`revokeConsent @29` (`:122`, `:125`) become unable to express a lawful refusal |
| R1 | `contacts.capnp:266-274` `PhoneType` (mobile/home/work/fax/**pager**/other/custom) | Names a dead technology as a permanent ordinal | Low severity on its own, but it is the proof that this enum set is a 1990s snapshot: `pager` is already obsolete and nothing replaces it. The open value is a `Text` token — the `type` fields on `EmailEntry`/`PhoneEntry` exist only to be filtered and displayed |
| R7 | `contacts.capnp:149` `ContactsSubscription.pull @0 () -> (contacts :List(Contact))`; `:156` `PresenceSubscription.pull` | Unbounded pull, no pagination, no terminator (contrast the paginated methods at `:46-49`) | A long-lived presence subscription with many contacts exhausts consumer memory. `cancel @1` exists (`:152`) but nothing tells the consumer the stream ended cleanly |
| R7 | `contacts.capnp:65`, `:86`, `:105`, `:108` — `getPresence`, `getFreeBusy`, `batchUpdate`, `batchDelete` | Unbounded id lists as input | Bulk operations on 10k contacts exceed the message limit with no chunked contract |

## Duplicates & overlaps
- **`TimeRange` declared three times with conflicting semantics**: `contacts.capnp:501-504` (`start`/`end` :T.Timestamp), `calendar.capnp:358-361` (identical shape), and `types.capnp:1553-1556` `T.TimeRange` (`start`/`end` :UInt64, documented as "Unix timestamp in milliseconds"). The canonical type exists and is unusable because its semantics differ; two local copies then diverge by drift. `getFreeBusy @18` uses the local one.
- **`getFreeBusy @18 (contactIds, range) -> (infos :List(FreeBusyInfo))`** duplicates **`calendar.capnp:46` `queryFreeBusy @14 (query :FreeBusyQuery)`**, which takes `contactIds + range + calendarIds`. Two contracts for the same fact, with different request shapes and different result types (`FreeBusyInfo` vs `FreeBusyEntry`). A consumer cannot tell which is authoritative.
- `FreeBusyStatus` (`:403-409`) is value-identical to `calendar.capnp:286-292` `FreeBusyPrivacy` — one concept, two names, two files.
- `SearchMode` (`:529-535`) duplicates `content.capnp:540-546` `SearchMode` and the concept underlies `system_search`'s query modes.
- `getContactHistory` (`:97`) overlaps `content.capnp`'s undo/audit-trail machinery (`:257`, `:300`) and `capability.capnp`'s `AuditEntry` (`:414`).

## Gaps & holes
- No contract for **conflict resolution on `updateContact`**: there is no version/etag field on `Contact` (contrast `ContentItem.version @14 :UInt64`, `content.capnp:94`), so two writers silently overwrite each other. Demonstrated fork risk: last-write-wins vs merge is decided per backend.
- **Deletion semantics**: `deleteContact @7` is permanent while `content.capnp` has a trash/restore workflow. Whether deleted contacts are recoverable is undefined, which matters directly to the GDPR machinery the file adds.
- `getSuggestions @27 (context :Text)` (`:118`) — "smart contact suggestions" whose entire input is a bare `Text`. Two backends will produce unrelated results and no consumer can know why. The context vocabulary is undeclared.

## Zero-cost / eco
Pass, and worth recording as the pattern to copy: photo as `T.DataHandle` (`:169`), import/export as `T.DataHandle` (`:90`, `:93`), pagination on all five list methods. Residual costs are the unbounded subscription pulls and bulk id lists above.

## UX & implementer guidance
- `ContactRankingType` (`:558-565`) mixes machine metrics with a human judgement: `mostContacted` vs `frequent` and `recentlyContacted` vs `recent` are redundant pairs, and `vip` is not a computable metric. An implementer must guess whether "frequent" differs from "mostContacted", and a consumer cannot compare scores across backends.
- `ContactFilter.groups @2 :List(T.GroupId)` documents OR semantics clearly (`:511`) — this is the kind of comment the rest of the tree needs.
- `ContactFilter.type @4 :ContactType` is a single value while `tags @5` is a list; a filter cannot express "person or organization".
- `ContactLifecycleStatus` (`:221-226`) — `stale` has no declared staleness threshold, so `stale` means something different in every backend.
- `DuplicateCandidate.matchedFields @3 :List(Text)` (`:454`) uses free-form field names ("email", "phone") that duplicate the `ContactFieldType` enum (`:466-471`) with a wider vocabulary — two spellings for one idea.

## Recommended actions
1. **Gate `shareContact` (and presence/history/relations) behind a capability accessor, and require a matching `ContactConsent` record for the target contact.** Gain: the file's own privacy machinery becomes binding instead of decorative; the single method that leaks personal data stops being ungated. Cost: one accessor method plus one check inside `shareContact`.
2. **Delete the local `TimeRange` and use `T.Timestamp` pairs directly** (or fix `T.TimeRange`'s semantics in `types.capnp:1553`). Gain: three spellings become one; cost: a signature change on `getFreeBusy`.
3. **Resolve the free/busy duplication: `calendar.queryFreeBusy` is the canonical contract; contacts should expose a calendar-scoped forwarder or nothing.** Gain: one contract for availability; cost: `getFreeBusy` is removed or becomes a thin wrapper.
4. **Open `ConsentScope` to a `Text` token.** Gain: lawful refusal is expressible in any jurisdiction; cost: consumers lose compile-time checking on a vocabulary that was never closed.
5. **Paginate the two subscription pulls.** Gain: bounded memory on long-lived subscriptions; cost: one `pullPage` method (the pattern already exists at `runtime_search.capnp:531` and `calendar.capnp:116`).
6. **Add a `version` field to `Contact` for optimistic concurrency.** Gain: two writers stop silently overwriting; cost: one new field.

# Audit — telephony.capnp (724 lines)

## Verdict
**FIX (targeted).** The core call/SMS/MMS/CRUD surface is honest — typed IDs (promoted in Batch 9), `T.DataHandle` for MMS parts and recordings, paginated logs, `T.Error` in `MmsResult`. The Audit-8 additions are the problem: **seven service interfaces** (Satellite, MeshCall, MeshMessage, LineManager, CallRecording, Voicemail, CallScreening at :404, :435, :459, :500, :537, :575, :680) are returned by no method anywhere in the repo — the features were added as whole services with no accessor. Plus a cellular-generation enum, a duplicated calendar free/busy contract, and a needless coupling to `translation.capnp`.

## Wire-breakers
None (compiles clean). `NetworkType` (:97) collides with `network.capnp:257` and `shell.capnp:432` under the same name with three different meanings (cellular generation vs link type). `FreeBusyQuery`/`FreeBusyResult` (:481/:492) collide with `calendar.capnp:294/:303`. `TimeRange` (:487) is a *third* incompatible shape — `types.capnp:1553` is `UInt64` milliseconds, `telephony.capnp:487` is `T.Timestamp`.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R8 | `telephony.capnp:404`, `:435`, `:459`, `:500`, `:537`, `:575`, `:680` | `SatelliteService`, `MeshCallService`, `MeshMessageService`, `LineManager`, `CallRecordingService`, `VoicemailService`, `CallScreeningService` — returned by no method in the repo, and unlike the driver-provider pattern they are not host-injected services | A consumer reading telephony.capnp sees call recording and visual voicemail advertised with no way to obtain the service. Every backend invents a root name for each — seven forks. (The repo's E4 rationale at `scripts/validate.py:172-179` excuses roots, but doesn't excuse *features of an existing service* being unreachable) |
| R8 | `telephony.capnp:530-534` | `LanguageFallback` (with `Trans.Translation`) is referenced by no method | The multi-language IVR feature has types and no API |
| R7 | `telephony.capnp:288`, `:291` | `makeCall @3 -> (callId :T.CallId)`, `getActiveCalls @6 -> (calls :List(CallInfo))` — no error paths | A call that cannot be placed (SIM locked — `SimState.networkLocked @3` exists! — network busy, airplane mode) has no representation. `sendSms @7` returns `T.VoidResult`, so the file knows the pattern; the call path doesn't follow it. Fork risk: backends report failure as an empty call list or a synthetic `CallState.disconnected` |
| R6 | `telephony.capnp:481-497` | `FreeBusyQuery`/`TimeRange`/`FreeBusyResult` re-implement `calendar.capnp:294-312` | Two free/busy contracts in the tree. A consumer booking a call must know which one the backend honors; the shapes differ (telephony's has `phoneNumber`, calendar's has attendees) |
| R6 | `telephony.capnp:487-490` | Local `TimeRange` with `T.Timestamp` fields, while `types.capnp:1553` `TimeRange` is `UInt64` ms | Fifth copy of the name in the tree; seconds copy with an incompatible unit. A consumer substituting the types.capnp version (as both files' comments invite) passes milliseconds-as-nanoseconds |
| R1 | `telephony.capnp:97-111` | `NetworkType` = gprs/edge/umts/hsdpa/hsupa/hspa/hspaPlus/lte/nr5G | A generation catalog; 6G has no value, 2G values are already dead. `custom @12` is valueless |
| R1 | `telephony.capnp:67-77` | `SimState` = absent/pinRequired/pukRequired/networkLocked/ready/notReady/permDisabled/cardIOError | A physical-SIM lifecycle. An eSIM, soft-SIM, or non-cellular backend (satellite messaging, mesh) must map its states onto card-reader semantics or lie |
| R1 | `telephony.capnp:249-259` | `RcsContentType` = text/image/video/audio/fileTransfer/geolocation/typingIndicator/readReceipt | An RCS feature catalog — the "today's list" pattern again; the next RCS release's content type has no value |
| R4 | `telephony.capnp:413`, `:467`, `:538`, `:586` | Opaque `Data` id namespaces: `SatelliteMessage.messageId`, `MeshMessage.messageId`/`sender`, `CallRecording.recordingId`, `Voicemail.voicemailId` | Four untyped `Data` ID namespaces in one file — passing a recording id where a message id is expected compiles. `T.TelephonyMessageId` exists (:178, :228, :374) and is used elsewhere in the same file, so the inconsistency is local and fixable |
| R6 | `telephony.capnp:4` | `using Trans = import "translation.capnp"` — used *only* by the dead `LanguageFallback` | A cross-schema edge to another batch's file that serves dead code; when translation.capnp is consolidated, telephony carries a needless dependency |

Validator counts: E7 ×27, E8 ×12, E6 ×0.

## Duplicates & overlaps
- `NetworkType` (3 schemas, 3 meanings), `FreeBusyQuery`/`FreeBusyResult` (calendar), `TimeRange` (5 schemas, 2 shapes).
- `CallQuality` (:610) vs `network.capnp:421` `QualityMetrics` vs `speech.capnp:479` — quality-of-call modeled three times; also `VideoQuality` (:696) is a fourth.
- `RecordAudioFormat` (:568) vs `audio.capnp`/`speech.capnp` `AudioFormat` — a fourth audio-format type.
- `SpamScore`/`E2eEncryption`/`CarrierSettings` — audit-9 additions each reachable only through `CallScreeningService`/getters that are themselves on the orphan interfaces or absent.

## Gaps & holes
- **No accessor pattern at all**: there is no `Telephony`-root accessor returning the seven orphan services. The doctrine's shape (README of ai.capnp: ungated discovery + gated accessor, DESIGN_PRINCIPLES.md:364-380) fits exactly: `Telephony` should gain accessors (`satellite @55`, `recording @56`, ...) taking a `Capability`.
- Resumable MMS: `MmsRetrievalStatus.deferred @3` (:212) acknowledges retrieval can be incomplete, but `downloadMms @26`/:35 is all-or-nothing with no partial-state contract.
- `getEmergencyNumbers @54` (:368) returns two unbounded parallel `List(Text)` (`numbers` + `priorityList`) — the parallel-list encoding is an implementer trap (index correspondence unstated).

## Zero-cost / eco
- Correct where it matters: `MmsPart.data :T.DataHandle` (:196), `getRecordingData :T.DataHandle` (:543), `playVoicemail :T.DataHandle` (:579).
- `IncomingSmsEvent.body :Text` (:162) — SMS bodies are ≤160 segments; inline is correct.
- `CallSubscription.pull` paginated (:378); `SmsSubscription`/`MmsSubscription` pull unbounded event lists but events are bounded in practice.
- No polling pattern.

## UX & implementer guidance
- `getSignalStrength @8 -> (strength :Int32, level :UInt32)` (:313) — dBm and a normalized 0-4 level as a bare tuple; the unit is documented only in the struct comment at :83.
- `hangUp @5`/`answerCall @4`/`holdCall @36` return `T.VoidResult` (good) but `makeCall` doesn't (see R7) — inconsistent within one feature.
- `EmergencyNumber` handling: `setEmergencyNumber @43 (number :Text)` (:347) lets any caller redefine an emergency number with no capability gate — the schema's only authority-sensitive setter with no gating narrative.

## Recommended actions
1. **Add a root accessor pattern**: on `TelephonyService` (or a new `Telephony` root), add gated accessors returning the seven orphan services (`satellite @55 (authority :Capability) -> (service :SatelliteService)` etc.), gated once at acquisition, no per-method tokens. Gain: seven features become reachable exactly once, per the doctrine's reference model; the fork risk disappears. Cost: seven method ordinals — additive, free pre-release.
2. **Add an error union to `makeCall`/`getActiveCalls`** (or document that failure is reported exclusively via `CallSubscription` events — one of the two, chosen and stated). Gain: call failure becomes honest; `SimState` already models the locked-SIM case. Cost: one signature change.
3. **Delete `LanguageFallback` and the `translation.capnp` import** (:4, :530-534) or wire it to an IVR method. Gain: removes a dead cross-schema dependency. Cost: zero.
4. **Unify `FreeBusy*` with `calendar.capnp`** — telephony should call the calendar service, not re-declare its types; and delete the local `TimeRange` in favor of one canonical shape (see BATCH-SUMMARY action 4). Gain: one free/busy contract, one TimeRange. Cost: a cross-schema reference plus deleting ~15 lines.
5. **Open `NetworkType`/`SimState`/`RcsContentType`** to `Text` tokens (or keep `NetworkType` as a genuinely math-free generation enum — then it must be Text). Gain: 6G/eSIM/RCS-2028 are expressible. Cost: consumers switch on strings with unknown-tolerance.
6. **Type the four `Data` IDs** (`recordingId`, `voicemailId`, satellite/mesh message ids) as promoted typed IDs (reuse `T.TelephonyMessageId`, add `RecordingId`/`VoicemailId` to types.capnp in the same wave). Gain: id-swap bugs become compile errors. Cost: four struct fields plus two types.capnp additions.

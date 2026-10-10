# Audit — session.capnp (461 lines)

## Verdict
**FIX (targeted).** The core (lock/unlock/state/idle/subscribe, `:35-52`) is exemplary and shows the audit process working: `T.UserId` (not POSIX uid), `Screenlock.UnlockCredential` imported rather than duplicated (`:37`), `T.Duration` throughout, deprecated `pullEvents` marked (`:44-46`), paginated subscription pull (`:136`). The Audit-7/9 additions then welded device-class *features* into the contract: AR/VR spatial sessions, watch glance sessions, voice-only sessions, cross-device handoff, session recording, plus an ACL model (`SessionAccessControl` allowed/denied users, `:354-365`) that duplicates the capability system the doctrine reserves as *the* access control. Targeted fix: strip device-class feature structs and the ACL; keep the lifecycle.

## Wire-breakers
None. `Screenlock.UnlockCredential` verified at `screenlock.capnp:140`.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R3 (permission model) | `session.capnp:354-365` `SessionAccessControl { allowedUsers, deniedUsers, public, maxParticipants, requireApproval }`, `:21` `getSessionAccessControl`, `:22` `setSessionAccessControl` | An allow/deny user-list ACL — "Do NOT define permission strings, boolean flags, or role-based access control in the protocol. The capability system IS the access control mechanism" (DESIGN_PRINCIPLES.md:399) | Two access-control systems must agree forever; a user granted via capability but denied via ACL has undefined authority. Every future session feature must be threaded through both |
| R1 / 2046 test | `session.capnp:244-257` `SpatialSessionInfo`, `:261-270` `WatchGlanceSession`, `:274-285` `VoiceSessionInfo`, `:297-308` `SessionRecording`, `:184-216` `HandoffRequest`/`SessionHandoff`, `:220-240` `MultiDeviceSession` | Today's device classes (watch/AR/voice/cross-device-continuity) frozen into the eternal contract | 2046 test: a brain-computer interface, a room-scale holographic session, or a session with no user at all (an agent's) has no fields. Worse, *every* backend must stub `getSpatialInfo @12`/`getWatchInfo @13`/`getVoiceInfo @14` even when no such device exists — required-position device taxonomy |
| R1 (soft) | `session.capnp:287-293` `SpeechRecognitionState`, `:165-180` `SessionEventType` (12 values incl. conflictDetected/expired/accessChanged appended *after* `custom @9`) | Closed event set; audit-9 variants added beyond the `custom` terminator | A backend event kind invented in 2030 must extend an eternal enum. The append-after-`custom` pattern (`:176-179`) breaks the "custom is last" convention that signals "the list ended here on purpose" |
| R6 | `session.capnp:316` `trustLevel @1 :UInt32 (0-100)` vs `types.capnp:550-561` `TrustLevel` enum | A hand-rolled 0-100 trust scale duplicating the canonical enum | Two trust vocabularies; `types.capnp` defines `system/platform/installer/user/untrusted` while this file invents an unlabeled integer scale. Consumers cannot compare trust across schemas |
| R4 | `session.capnp:194-207` `SessionHandoff { id :Text, … progress :UInt32 }`, `:111` `applyTemplate (templateId :Text)`, `:348` `persistSignalGroup`-style Text ids | `Text` identities where typed IDs exist (`T.SessionId`, `T.TemplateId` `types.capnp:1542`) | Text IDs are fragile across versions (DESIGN_PRINCIPLES.md:165 makes exactly this point about AudioDevice.id). Cross-device handoff riding on free-text ids is a wire-break waiting for a rename |

## Duplicates & overlaps
- Exit/lock events: `SessionEventType.lock/unlock` (`:165-166`) vs `screenlock.capnp` events (out of batch, noted) and `signal.capnp` subscription — the same observation reachable three ways.
- `SessionAuditEntry` (`:369-384`) vs `capability.capnp:414-433` `AuditEntry` — two audit-entry shapes; vs `signal.capnp:150` `SignalAuditEntry` — a third.
- `SessionExpirationPolicy` (`:388-399`) partially duplicates `capability.capnp:126-129` `TimeBox` (expiry semantics) and `Constraints`.
- `getTemplates`/`applyTemplate` (`:111-114`) — session templates duplicate `manifest.capnp`-style self-description (out of batch).

## Gaps & holes
- No contract for *who may lock/unlock*: `lock @0`/`unlock @1` (`:36-37`) are ungated on the interface, and `unlock` takes a `Screenlock.UnlockCredential` — which is the right authority carrier — but the interface itself is unauthenticated until unlock succeeds. Defensible; but note there is no declared behavior for unlock failure (is the session destroyed? how many attempts?). Every backend invents the attempt policy. Demonstrated fork.
- `saveSession @18 -> (handle :T.DataHandle)` / `restoreSession @19` (`:85-88`): no declared format, versioning, or compatibility contract for the saved blob. Two backends' blobs are non-interchangeable and nothing says whether that is guaranteed. A 2046 restore path is exactly where "invent behavior" happens.

## Zero-cost / eco
`saveSession` returning `T.DataHandle` (`:85`) is the correct choice; `HandoffRequest.state @1 :Data` (`:188`) is an inline serialized session — a session with large window state copies on every handoff; `T.DataHandle` belongs there too. `getSessionAuditTrail` is paginated (`:102`) — good.

## UX & implementer guidance
- The header's improvement log (`:13-32`) is accurate — a model for other files. But it documents *fixes* while the body's audit-7 section reintroduces the same classes of problem (device-class features, raw scales).
- `getIdleState @8 () -> (idle :Bool, duration :T.Duration)` (`:52`) overlaps `idleTime @3 () -> (idleTime :T.Duration)` (`:40`) — two methods, one fact; a consumer must guess whether `idle` is derivable.
- `SessionSecurityContext.mfaRequired`/`biometricVerified`/`attested` (`:312-322`: five booleans + riskScore) — security posture as unlabeled booleans; there is no declared meaning of `attested` (attested by whom, to what root?).

## Recommended actions
1. **Delete the device-class feature structs** (`:184-240` handoff/multi-device, `:244-293` spatial/watch/voice, `:295-308` recording) and their six accessor methods (`startHandoff`, `acceptHandoff`, `getMultiDeviceSession`, `getSpatialInfo`, `getWatchInfo`, `getVoiceInfo`, `startRecording`, `stopRecording`). Gain: a session contract correct for devices not yet invented (a session needs lock/unlock/idle/identity — none of which is device-shaped); cost: features with no consumers (device-specific work belongs in device-specific schemas, composed at the shell).
2. **Delete `SessionAccessControl` + its two methods** (`:354-365`, `:96-99`): express multi-participant authority via `capability.capnp`. Gain: one access-control system, per doctrine; cost: ACL-familiar reporting lost — the capability model replaces it by design.
3. **`trustLevel :UInt32` → `T.TrustLevel`**, Text ids → typed IDs (`SessionHandoff.id`, `templateId`). Gain: kills the duplicate trust scale and fragile string identities; cost: mechanical.
4. **Specify `HandoffRequest.state` as `T.DataHandle`** (`:188`) and define a minimal compatibility rule for `saveSession`/`restoreSession` blobs (version field + ignore-unknown). Gain: zero-copy handoff + a restore path that survives schema growth; cost: one field + one paragraph.
5. **Define unlock-failure semantics** (attempts, backoff, session disposition). Gain: closes the fork where every backend invents its own lockout policy; cost: spec text only.

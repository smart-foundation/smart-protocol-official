# Audit — access.capnp (744 lines)

## Verdict
**KEEP.** This is the best-modelled file in the batch and the only one that gets error handling systematically right: `UnlockOutcome` is a union with `denied @4 :T.Error` (`:410-427`), `MfaVerifyResult` (`:479-490`) and `RecoveryResult` (`:687-695`) are unions, `AccessEvent` carries `custom @14 :Data` (`:550`), every list method is paginated (`:610`, `:617`, `:629`, `:653`), and the header states the lock state machine explicitly (`:12-17`). It is also a *victim* of the batch's worst duplication — `auth.capnp` and `biometric.capnp` each re-declare MFA, lockout, and credential enrollment against it. Keep the file; fix its three local defects and let the other two delegate to it.

## Wire-breakers
None. Method ordinals @0–@32 unique (`:588-669`); `AccessEvent` union @1–@16 with `custom @14`; `AccessState` @0–@9; all `T.*` references resolve.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R5 | `access.capnp:345` `CredentialValue.smartCard @4 :Data`, comment: "PKCS#11 / PIV token identifier" | PKCS#11 and PIV named in a required position (the R5 rule names PKCS#* explicitly) | The field is opaque `Data`, so nothing breaks mechanically — but the doc tells implementers to expect a PKCS#11/PIV identifier, and a backend using a secure enclave, a FIDO2 token, or a 2046 smart-card API has no declared alternative spelling. Implementers will either misuse `custom @6 :Data` or emit a PKCS#11 identifier they do not have |
| R4 | `access.capnp:98` `CallerIdentity.userId @0 :Text` | A bare `Text` user identifier in a file that otherwise uses typed ids everywhere (`T.AccessCredentialId`, `T.MfaChallengeId`, `T.MfaEnrollmentId`, `T.AccessBackendId`) while `T.UserId` exists (`types.capnp:487`) | `CallerIdentity` is the audit-relevant identity (`:97-104`, used by `AccessSession`, `SessionDescriptor`), and it is the one identifier that consumers will correlate with other schemas — as a string, against `T.UserId` numerics elsewhere. Two spellings of identity in one security record |
| R8 | `access.capnp:647` `listRecoveryMethods @25 () -> (methods :List(RecoveryMethod))` | Returns the enum's own value set, which is fully determined by the schema | Either it means "all six variants" (useless — the consumer can read the enum) or "the enabled ones" (which should be named `getSupportedRecoveryMethods` and is a real query). An implementer cannot tell which, and a consumer cannot tell the difference between the two answers. `listBackends @16` (`:622`) is the model this method should follow |
| R7 (soft) | `access.capnp:742` `AccessSubscription.pull @0 () -> (events :List(AccessEvent))` | Unbounded pull with `cancel` but no pagination | Low volume in practice, but the pattern exists (`pullPaginated` at `calendar.capnp:116`, `runtime_search.capnp:531`) and this subscription will carry every failed-attempt event when `includeTelemetry` is set (`:562`) |

## Duplicates & overlaps
- **MFA**: `MfaChallenge` (`:465-476`) vs `auth.capnp:271-276` `MfaChallenge` — same name, different fields; `requestMfaChallenge @11`/`verifyMfaChallenge @12` (`:615-616`) vs `auth.capnp:46-47` `startMfa @11`/`verifyMfa @12`. This file holds the better contract (it has `issuedAt` and a proper `MfaVerifyResult` union); `auth.capnp` should delegate.
- **Lockout**: `LockoutInfo` (`:397-406`) vs `biometric.capnp:110-119` `LockoutInfo` (same name, different fields) vs `auth.capnp:302-307` `LockoutStatus`. `LockoutKind` is duplicated verbatim at `auth.capnp:309-315` and `biometric.capnp:121-127`.
- **Credential enrollment**: `enrollCredential @9` (`:611`) vs `auth.capnp:50` `enrollCredential @13`; `RecoveryCode`/`BackupCredential` (`:236-270`) have no counterpart in `auth.capnp` — which is itself the gap recorded in the auth report.
- **Session/authority**: `AccessSession` (`:200-219`) and `SessionDescriptor` (`:81-95`) restate each other (`sessionId`, `unlockedAt`, `sessionValidFor`, `method`, `mfaUsed`, `callerIdentity`, `scope`) — two structs for one fact inside one file, with `UnlockSuccess.session @4 :AccessSession` (`:439`) picking one.
- **Delegation**: `DelegatePermissions`-style booleans appear in `calendar.capnp:460-466`; this file's `revokeSession @20` is the capability-shaped version.

## Gaps & holes
- **An unlock session is not a capability.** `AccessSession`/`UnlockSuccess` is a session-authority concept that cannot be converted into a `Capability`, so a service that needs "is the device unlocked?" has nothing to hold — it must poll `getState @0` (`:590`) or `isLocked @3` (`:599`), which are the two polling-shaped methods in the file. Demonstrated fork risk: every consumer that gates on unlock invents its own polling interval and cache policy, because the protocol offers no holdable authority for the fact. The cheap fix is a documented `Capability` target convention (e.g. `device/unlock`) issued on unlock — no new machinery, one target string, and downstream services can hold and attenuate it like anything else.
- **Backend-switch mid-session**: `setActiveBackend @17` (`:623`) can invalidate every enrolled credential (an `AccessBackend.supportedMethods @2 :List(LockMethod)` list at `:701` tells you which), but nothing declares what happens to active `AccessSession`s or enrolled `Credential`s on a switch.
- `revokeSession @20 (sessionId :UInt64)` (`:632`) uses a raw `UInt64` while `types.capnp:6` has `SessionId { id @0 :UInt64 }` — internally consistent, but the one id in the file that should cross to other schemas is the one left untyped.
- `save`/`restore` of the credential store do not exist here (they do in `sandbox.capnp:62-65`), so device migration has no access-side contract.

## Zero-cost & eco
No bulk payloads; `RemoteAttestation.evidence @0 :Data` (`:120`) is small and correctly opaque with a backend-decided `format @1 :Text` (`:122`). Pagination is thorough. Residual: `listCredentials @8` and `listSessions @19` are paginated but `generateRecoveryCodes @29 (count :UInt32)` (`:659`) returns `List(RecoveryCode)` with no bound — a caller asking for 100k codes gets 100k codes in one message, each carrying a `Data` code value.

## UX & implementer guidance
- `CredentialStrength` (`:36-43`) asserts specific entropy thresholds (28/47/71/72 bits). These are 2026's conventions and a 2046 threat model will not agree with them; the bucket names will be read as normative by implementers.
- `AccessErrorCode` (`:131-161`, 29 values) is the right instinct — far better than string parsing, and the file says so at `:128-130`. It is a closed list of failure modes, so a new backend failure mode lands in `custom @28`; acceptable, since `T.Error` remains the routing mechanism.
- `LockoutPolicy.wipeAfter @3 :UInt32` (`:365`) — "wipe credentials after N failed attempts" is destructive, has no confirmation contract, and no event declares it happened with which credentials were lost (`credentialRevoked @11`, `:542`, is the closest and carries a full `Credential`).
- `BackendTrustLevel` (`:710-717`) and `TrustLevel` (`types.capnp:550-561`) are two trust scales in the same batch with different value sets; a consumer comparing them must translate.
- The header (`:18-27`) accurately describes the Audit-7 additions; the one claim it makes that the body does not deliver is that this schema "defines the device unlocking surface" while `auth.capnp` and `biometric.capnp` each define a competing unlock surface.

## Recommended actions
1. **Keep the file and its wire shape; declare it the canonical owner of lock/unlock/MFA/lockout/credential-enrollment and have `auth.capnp` and `biometric.capnp` delegate.** Gain: two competing MFA flows and four lockout structs collapse to one each — the largest structural saving available in this batch; cost: two other files' method signatures change (both are pre-release and permitted to change).
2. **Issue a `Capability` on unlock (or document the `device/unlock` target convention) and have `AccessSession` reference it.** Gain: "is the device unlocked" becomes a holdable, attenuatable authority instead of a poll (`getState @0`, `isLocked @3`), and downstream services stop inventing cache policies; cost: one target-string convention plus one field.
3. **Fix `CallerIdentity.userId` to `T.UserId`, and `revokeSession`'s parameter to `T.SessionId`.** Gain: the audit-relevant identity becomes correlatable across schemas; cost: two field types, no ordinal changes.
4. **Generalise the `smartCard` comment at `:345` to "opaque token identifier (backend-decided)".** Gain: stops telling implementers to expect PKCS#11; cost: one line.
5. **Rename or redefine `listRecoveryMethods`** — either `getSupportedRecoveryMethods` with declared semantics, or delete it. Gain: a method whose result is the enum's value set stops being an implementer trap; cost: one signature or one deletion.
6. **Declare what happens to sessions and credentials on `setActiveBackend`.** Gain: backend switching stops silently invalidating every credential with no event; cost: one comment plus an event variant.

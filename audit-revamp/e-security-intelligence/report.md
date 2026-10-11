# Wave 5 rewrite report — e-security-intelligence (17 schemas)

**Agent:** Wave 5 rewrite agent · **Tree:** `smart-protocol-official/schema/` · **Date:** 2026-10-10
**Inputs applied:** `verification/audit-verification.md` (confirmed findings only; OVERREACH O1–O5
rejected), `verification/naledzi-delta-reconciliation.md`, this batch's 17 per-schema audits +
BATCH-SUMMARY, `DESIGN_PRINCIPLES.md`, `docs/TIMELESSNESS.md`, gold standard `ai.capnp`.

## Verdict table

| # | File | Verdict | One-line justification |
|---|---|---|---|
| 1 | ai.capnp | FIXED (targeted) | Stays the standard: 0 enums, no inline bulk, one gated root. `AISubscription.pull` bounded (`maxEvents`, ai.capnp's own discipline), `ToolOutcome` is a union, `handshake` left ungated with its deadlock reasoning intact. |
| 2 | speech.capnp | REWRITTEN | `SpeechOutcome` union carries `T.Error`+`custom` (file had zero unions); emotion/style vocabularies and `encoding` opened (`T.MimeType`); `VoiceType` sentinel added (this session). |
| 3 | translation.capnp | REWRITTEN | `TranslationStreamSession` is a pullable interface; `batchId` is now the value `translateBatch` returns; `TranslationOutcome` union; `DedupStrategy` sentinel (this session). |
| 4 | contacts.capnp | REWRITTEN | `shareContact` moved behind the `privacy` accessor (consent record required); pagination on every list method; 4 request/filter enum sentinels (this session). |
| 5 | calendar.capnp | REWRITTEN | `Recurrence` precedence declared (structured fields authoritative, `rrule` advisory + `structuredFieldsIncomplete`); `DelegatePermissions` booleans deleted in favour of capability.capnp attenuate/transfer; 8 request/filter/status enum sentinels (this session). |
| 6 | content.capnp | REWRITTEN | `decryptContent` read-through declared (`-> (item :ContentItem)`); the ContentPermission/AccessRule/AccessPolicy/delegation-chain permission model deleted; zero enums remain. |
| 7 | system_search.capnp | REWRITTEN | Result identity typed (`SearchResultId`) — one type on the field and every consuming method; `VectorQuery.embedding` is `T.DataHandle`; one pagination model (query-side `T.Pagination`); `SearchOutcome` union; 2 request-enum sentinels (this session). |
| 8 | runtime_search.capnp | REWRITTEN | Service-mesh control plane cut (15 methods, 20 types: cost models, migration, catalog, logs/metrics/traces, hooks); local `Capability`/`PermissionDomain`/`PermissionAccess` deleted; `RuntimeKind` → open tokens; `RuntimeSort` sentinel (this session). |
| 9 | vcard.capnp | REWRITTEN | `v50` slot deleted (standard that does not exist); imports calendar's `ConflictResolution`; 4 result unions gain `unknown` arms, 5 declaration/spec enum sentinels (this session). |
| 10 | auth.capnp | REWRITTEN | `refreshToken` requires proof of possession (see §2); `PermissionRequest/Grant/Check` deleted; secrets are `Data`; `T.ScopeId` throughout; `TokenType` sentinel (this session). |
| 11 | biometric.capnp | REWRITTEN | Platform modality/sensor enums → open tokens; `T.BiometricTemplateId` for templates, `T.BiometricId` for hardware; signing algorithm open token; 2 request-enum sentinels (this session). |
| 12 | access.capnp | KEPT | Verified only: the batch's systematic error model (unions with `T.Error`), correct lock/MFA/lockout ownership. Untouched on disk. |
| 13 | crypto.capnp | REWRITTEN | All ~130 algorithm values in 8 closed enums → open tokens + `T.StringMap` + CONFORMANCE TOKENS consts (the ruled fix); FIPS-203/204/205 amendment loop closed; 3 result unions gain `unknown`, `KeyUse` sentinel (this session). |
| 14 | key_management.capnp | REWRITTEN | Local `KeyId` deleted → `T.KeyId`; whole store gated at `store @0 (authority :Capability)`; `KeyUse`-style vocabularies opened; rotation grace semantics declared; 5 result unions gain `unknown`, 2 sentinels, `KeySubscription.pull` bounded by `maxCount` (this session). |
| 15 | signature.capnp | REWRITTEN | Local algorithm enums deleted — imports crypto's open vocabulary (divergent-ordinal wire hazard closed); every verify/batch payload is `T.DataHandle`; `RevocationList` dead surface deleted; this session: fixed a compile break (`Crypto.UnknownEvent` → `T.UnknownEvent`), renamed `SignRequest` → `SignatureRequest` (R6 collision with crypto), `PolicyEffect` sentinel. |
| 16 | secret.capnp | REWRITTEN | Entire surface gated at acquisition: `store @0 (authority :Capability)`, ungated discovery only; values are `T.DataHandle`; overlay overrides are `List(SecretOverride)` (were `Text` map values); KDF/wrap/compare paths delegate to crypto.capnp. |
| 17 | sandbox.capnp | REWRITTEN | seccomp/landlock/rlimit body abstracted (allow/deny/fail/terminate, open match/options maps, backend-reported `enforcedBy`); snapshot `Data` → `T.DataHandle`; local `CapabilityGrant` deleted; this session: grant/revoke/list moved behind a `capabilityAdmin` accessor (ai.capnp pattern), 5 sentinels, `CreateSandboxResult` unknown arm. |

## 1. The dead attempt — honest state note

The previous attempt died on an output limit mid-batch. Inventory (checked via `git diff` vs the
committed tree, plus compile/validate probes):

- **16 of 17 files were already rewritten** (all except `access.capnp`, which the verdict keeps).
  The rewrites were substantively complete and of good quality: crypto's token migration, the
  search-primitive restructuring, auth's proof-of-possession, secret's gating and sandbox's
  abstraction had all landed, each with a header documenting its own reasoning.
- **What was actually missing was the finishing layer**, which this session supplied file by file:
  1. **A compile break:** `signature.capnp` referenced `Crypto.UnknownEvent`, a type crypto.capnp
     never declared — the file did not compile at all. Fixed to the canonical `T.UnknownEvent`
     (types.capnp:242).
  2. **An R6 collision:** crypto's primitive `SignRequest` and signature's envelope
     `SignRequest` (different shapes) shared one name. Signature's renamed `SignatureRequest`.
  3. **R7 gaps:** 13 result unions across crypto, key_management, sandbox and vcard lacked the
     `unknown` arm. All appended at fresh ordinals.
  4. **O4-scoped E8 sentinels:** 28 request/filter/spec enums across 11 files silently defaulted
     to a paradigm value (`allow`, `active`, `cosine`, `v21`, `bearer`, …). Sentinels inserted at
     `@0`; the 7 event/result enums are documented instead (see §6).
  5. **One R3 violation:** sandbox's `grantCapability`/`revokeCapability` took per-method
     Capability parameters on the root; split behind a `capabilityAdmin` accessor (methods
     re-issued 0‑15 sequentially, E13-clean).
  6. **One validator-named inconsistency:** `KeySubscription.pull` kept `T.Pagination`+`total`
     on a live event queue while its own comment condemned it; reissued as `pull (maxCount :UInt32)`
     per ai.capnp's bounded-stream discipline.

## 2. Per-file change summary

**ai.capnp — FIXED (targeted), the standard kept.** Verified against the verifier's confirmed
findings (E11): `AISubscription.pull @0 (maxEvents :UInt32)` bounds the ungated subscription pull
using ai.capnp's own `ArtifactStream.pull (maxBytes)` pattern — no new type (OVERREACH O5
rejected). `handshake @0 ()` remains ungated and still returns `List(ModelDescriptor)`; the
deadlock reasoning at :587‑597 (discovery must precede any capability) is untouched, as ruled.
`ToolOutcome` is a union with `success/unknown/error`; `AgentService.send` returns
`AgentSendResult`; `AgentDeclaration.tools @1 :List(ToolId)` exists. The 19-enum version was not
resurrected. **Gain:** the gold standard no longer models the defects it elsewhere names.
**Cost:** consumers of `AISubscription.pull` pass a bound.

**speech.capnp — REWRITTEN.** The file had zero unions, so `listen`/`translate` could not fail.
One `SpeechOutcome` union now carries `T.Error` and a `custom :Data` opaque escape beside the
existing result structs (field ordinals of every payload struct unchanged — mechanical, no
re-issuance). The two emotion enums (`EmotionalStyle`, `SpeechEmotion`) and `AudioEncoding`
became open tokens with published consts; `encoding` is `T.MimeType`; the dead
`using Translation` import is gone; `AudioStream.pull` returns handles. **Gain:** a 2046 emotion,
voice or codec is nameable and STT/TTS failures are representable. **Cost:** consumers compare
strings on a vocabulary that was never closed anyway.

**translation.capnp — REWRITTEN.** `startStream` returned `TranslationStream { sessionId :Text }`
— a struct nothing could pull from; the session is now `TranslationStreamSession`, returned by
`translateStream`/`subscribeTranslationStream`. `subscribeBatchProgress` took a `batchId` no
method produced; `translateBatch` now returns it. `TranslationOutcome` union (the old bare
`translatedText` conflated "untranslated" with "failed"). Language tags use `T.Language`.
**Gain:** streaming translation is actually drivable and batch progress is observable.
**Cost:** one interface where a struct was.

**contacts.capnp — REWRITTEN.** `shareContact` copied a person's record to any `T.UserId` with no
gate; it now lives on `ContactPrivacy`, obtained through `privacy @21 (authority :Capability)`,
and requires a consent record. Pagination (`T.Pagination`) on list/search/starred/groups/
duplicates/recent/suggestions/history. The 15 open-vocabulary enums were closed in the original;
request/filter ones (`ContactLifecycleStatus`, `GroupRuleOperator`, `MergeStrategy`,
`ContactFieldType`) now carry sentinels (this session). **Gain:** ungated PII egress closed;
`ContactHistoryAction` documented as an event enum. **Cost:** two signatures changed.

**calendar.capnp — REWRITTEN.** `Recurrence` carried structured fields AND an RFC 5545 `rrule`
with no precedence — two backends expanded the same series differently. Precedence is now
declared: structured fields authoritative, `rrule` advisory, `structuredFieldsIncomplete` tells a
consumer when it is relying on the hint; a timezone was added (daily 09:00 across DST was
undeclared). `DelegatePermissions` (five booleans) and `delegateCalendar`/`revokeDelegation` are
deleted — delegation is capability.capnp's `attenuate`+`transfer`, so a delegation can no longer
outlive the capability it was made from. Vendor subscription enum (`google`/`exchange`) opened;
8 sentinels added (this session); `DayOfWeek` documented (always-written list element).
**Gain:** one recurrence expansion, one authority path. **Cost:** delegation consumers move to
capability.capnp.

**content.capnp — REWRITTEN.** `decryptContent` returned `T.VoidResult` — it decrypted with no
way to read the plaintext. It is now read-through: `-> (item :ContentItem)`, replacing `mimeData`
with a handle to plaintext for that caller only, stored ciphertext untouched; a backend that
cannot do that refuses with `T.Error(unsupported)`. The file's own permission model
(`ContentPermission`, `AccessRule`/`AccessPolicy` with expiry/scope, its own delegation chain
with `maxDepth`) is deleted in favour of capability.capnp. Zero enums remain; zero inline bulk.
**Gain:** decrypt is wire-compatible across backends; a second authorization system is gone.
**Cost:** consumers read a handle.

**system_search.capnp — REWRITTEN.** Result identity was broken by type: `SearchResult.resultId`
was `Text` while every consumer (`executeResult`, `getResultPreview`, `SearchHandler.execute`)
took `T.SearchProviderId` — no correct value could be passed; `explainResults`/
`deduplicateResults` used a third spelling. One `SearchResultId` is now used everywhere. The hot
payload `VectorQuery.embedding` (6 KB per 1536-dim query, ×N providers in federated search)
became `T.DataHandle`. The query's `limit`/`offset` and the method's `T.Pagination` result had no
declared precedence; the query now carries the one `T.Pagination`. `SearchResultType`'s 12-value
enum → open token (facet counts key on the same token). `SearchOutcome` union carries `T.Error`.
**Gain:** results are actionable, semantic search stops copying, one pagination model.
**Cost:** callers pass a typed id where they passed text.

**runtime_search.capnp — REWRITTEN.** The drifted service-mesh control plane is cut: cost models,
live migration, catalog (SLAs/ownership/on-call/API docs/changelog), a fourth observability stack
(logs/metrics/traces), lifecycle hooks — 15 methods and 20 types with zero consumers. The local
permission model (`Capability` colliding by name with capability.capnp's, `PermissionDomain` 15
values, `PermissionAccess` 7) is deleted; an instance's authority is a canonical `Capability`.
`RuntimeKind` (unixDaemon/windowsService/jsRuntime/pythonRuntime/luaRuntime) → open tokens, so a
seL4-class, BEAM, GraalVM or 2046 runtime is discoverable and countable in the stats map. The
split with system_search is kept (verifier verdict: principled, disjoint consumers).
**Gain:** a discovery contract again, one authority vocabulary. **Cost:** none — the cut surface
had no consumers.

**vcard.capnp — REWRITTEN.** `getSupportedVersions` returned `v50`, a standard that does not
exist (vCard 4.0/RFC 6351 is the latest); the slot is deleted and the method reports what the
backend actually supports. The 1998 TYPE vocabulary frozen into enums is superseded by the open
`parameters` mechanism sitting two structs away. `ConflictResolution` imports calendar's (was a
byte-identical duplicate). Result unions gain `unknown` arms; 5 declaration/spec enums gain
sentinels (this session). Kept as a separate file (external-standard converter, not merged into
contacts). **Gain:** honest capability reporting, no phantom standard. **Cost:** consumers read
open parameters.

**auth.capnp — REWRITTEN (the batch's most severe fix).** `refreshToken @2
(tokenId :T.AuthTokenId, proof :T.DataHandle)`: refreshing by enumerable UInt64 id alone let a
stolen token id mint fresh tokens indefinitely. Proof of possession is now mandatory — the caller
presents the token value (or a signed challenge) as an opaque handle, which the backend
validates; the id alone is no longer sufficient, so the session-extension path is closed. The
secret is never a bare id and never inline `Text`. Also: `PermissionRequest`/`PermissionGrant`/
`checkPermission` deleted (the forbidden second authorization system); `Credentials.password/pin`
are `Data`; `T.ScopeId` throughout; `revokeAllTokens`' blast radius declared (the CALLER's tokens,
this scope — previously "all" with three possible implementations); `enrollCredential` sits behind
the `session` accessor. **Gain:** an unauthenticated token-extension path is closed; one
authorization system tree-wide. **Cost:** callers must hold the token value — which they already
have.

**biometric.capnp — REWRITTEN.** Platform-noun purge: modality and sensor taxonomies are open
tokens (a 2046 modality is requestable), `SensorLocation`/`SensorSubtype` axes declared,
`SigningAlgorithm` (a third crypto vocabulary) is an open token from crypto.capnp. One id for two
namespaces fixed: hardware keeps `T.BiometricId`, every template reference is
`T.BiometricTemplateId` (the promoted type that sat unused). `BiometricAuthOutcome` carries a
payload (failed vs error were indistinguishable); `verifyToken` returns an outcome, not a bare
Bool. The byte-identical `LockoutKind` duplicate with auth is renamed `BiometricLockoutKind`
(the remaining unification is a founder decision, §5). 2 request-enum sentinels added.
**Gain:** non-2026 modalities and sensors stop being unrepresentable. **Cost:** string comparisons
on tokens.

**access.capnp — KEPT, verified only.** Untouched on disk. Verified it remains the batch's only
systematic error model (every outcome is a union with `T.Error`) and the right owner of
lock/MFA/lockout/recovery. Pre-existing REPORTs carried forward untouched: `AccessEvent` fields
out of ordinal order (`backupRotated@16` then `custom@14`, E13), `CredentialValue.pattern
:List(UInt8)` and `MfaChallenge.payload :Data` (E10). Fixing the first is a one-line ordinal
re-issue; left alone because this file's verdict is KEEP and no external consumer exists.

**crypto.capnp — REWRITTEN (the ruled action).** ~130 algorithm values in 8 closed enums, in
required positions, in a file that had already amended itself once for FIPS 203/204/205 — the
amendment loop proven. Every algorithm field is now an open token plus `T.StringMap` parameters,
with today's spellings published as CONFORMANCE TOKENS consts (ai.capnp's pattern); the
`AlgorithmSpec`/`PostQuantumSpec` family union collapsed into one open `AlgorithmSpec`;
`getSupportedAlgorithms` reports the same spellings. Interop comes from published tokens +
opaque handles, not frozen lists. All bulk (ciphertexts, plaintexts, key material, wrapped keys,
shared secrets, random output, certificate blobs) is `T.DataHandle`; construction-bounded values
(digests, tags, nonces) stay inline with the reasoning stated. `KeyUse` is the one enum kept —
closed by public-key mathematics (sign/encrypt/agree/wrap/any) — now with a sentinel.
**Gain:** new constructions are requestable with no schema change and no new ordinal; two backends
can interoperate on an algorithm invented after the list froze. **Cost:** consumers switch on
published strings.

**key_management.capnp — REWRITTEN.** The identity split is fixed: local `KeyId` deleted,
`T.KeyId` used at all ~20 sites, so `content.capnp`/`backup.capnp` call sites finally type-check
(the batch's only already-broken item). The whole store is gated: `store @0 (authority :
Capability)` with `target`/`operations` narrowing — `syncExport`, `escrowKey`, `restoreKey` and
`exportKey` are no longer reachable by any holder of the service reference. `KeyAlgorithmFamily`
and the export-format enum are opened (crypto's tokens). Rotation semantics declared: during
`gracePeriod` the old key remains usable for DECRYPT/VERIFY only, re-encryption ownership
stated; escrow shares are bound to a key id (a backend MUST refuse shares that reconstruct a
different key). **This session:** 5 result unions gain `unknown` arms; `KeyPurpose`/`KeyStatus`
sentinels; `KeySubscription.pull (maxCount :UInt32)` replaces the pagination-on-events shape its
own comment condemned; `cancel @1` retained. **Gain:** one key identity, one authority path.
**Cost:** none.

**signature.capnp — REWRITTEN.** The latent wire-break is closed: the same-named
`SignatureAlgorithm`/`HashAlgorithm` at divergent ordinals (`ed25519` @0 vs @12, `sha256` @0 vs
@1) are gone — this file declares no algorithm enums and speaks crypto.capnp's open tokens, so a
divergent ordinal cannot exist. Request/result asymmetry fixed: every verify path
(`verify`, `verifyMulti`, `verifyThreshold`, `verifyWithRevocation`, `batchVerify`) takes
`T.DataHandle`, matching the always-correct sign path — verifying a 50 MB artifact no longer
copies it, and `batchVerify` no longer copies N payloads into one message. Keys are
`T.KeyFingerprint` (self-describing; the length heuristic is gone). `RevocationList`/its
subscription — returned by no method anywhere — deleted; `verifyWithRevocation` consults the
trust store this service maintains. The same-name `VerifyRequest` collision with capability.capnp
was already resolved by naming (`SignatureVerifyRequest`). **This session:** the compile break
(`Crypto.UnknownEvent` → `T.UnknownEvent`) and the `SignRequest` → `SignatureRequest` rename.
**Gain:** the batch's worst latent wire hazard is closed; verification is zero-copy. **Cost:**
verify callers read handles.

**secret.capnp — REWRITTEN.** The fully ungated surface is gated at acquisition: `store @0
(authority :Capability)` returns `SecretStore`, whose `target` names the namespace it governs;
only template discovery (metadata about shapes, never secrets) stays ungated. Secret values are
`T.DataHandle` — a small secret stays inline, a key or certificate bundle becomes a buffer
reference — returned in an outcome union so "missing key" is distinguishable from "empty value".
`SecretOverlay.overrides` carries `List(SecretOverride)` handles instead of `T.StringMap` Text
values (greppable, trivially logged). Version history is paginated; rollback behaviour declared;
the duplicate KDF/wrap/compare paths delegate to crypto.capnp.
**Gain:** total access to every secret is closed. **Cost:** one acquisition step.

**sandbox.capnp — REWRITTEN.** The header no longer lies: seccomp's action names
(errno/killThread/trap/trace) became abstract outcomes (allow/deny/fail/terminate) with the
mechanism backend-reported in `enforcedBy`; the BPF argument-filter model became an open
`match :T.StringMap`; mount flags became `readonly` + an open options map; the RLIMIT_* field
list became the four universal limits plus an open map. The snapshot save/restore (the heaviest
operation in the protocol, a multi-gigabyte memory image through the arena) is `T.DataHandle`
both ways, with restore's capability semantics declared. The local `CapabilityGrant` permission
model is deleted. **This session:** grant/revoke/list moved behind `capabilityAdmin @16
(authority :Capability) -> (service :SandboxCapabilityAdmin)` — holding the sandbox-creation
reference is no longer by itself the authority to hand capabilities to a sandbox; 5 request/
filter/policy-enum sentinels; `CreateSandboxResult` unknown arm. **Gain:** a non-Linux backend
stops faking POSIX semantics in required fields; one authority path. **Cost:** capability
manipulation needs the admin reference.

## 3. Cross-batch items (exact file + action)

1. **Search primitives → `types.capnp` (foundation batch A owns the file).** Promote one query
   envelope, one result envelope, one subscription shape. Current collisions:
   `SearchQuery` files.capnp:428 ↔ system_search.capnp:204; `SearchResult` shell.capnp:436 ↔
   system_search.capnp:245; `SimilarityMetric` database.capnp:643 ↔ system_search.capnp:291.
   system_search.capnp's header (bottom) records the exact types to move. system_search and
   runtime_search are otherwise clean of each other (the split stays, verifier-verdicted).
2. **`KeySubscription`:** database.capnp:416 (struct) ↔ key_management.capnp:375 (interface).
   Rename database's to `KeyWatchSubscription` (different concept, different kind).
3. **`MergeStrategy`:** contacts.capnp:365 ↔ manifest.capnp:399 (batch D). Contact-merge and
   manifest-merge semantics differ; rename one or promote.
4. **`EventFilter`:** calendar.capnp:401 ↔ compositor.capnp:846 (batch D). Rename calendar's to
   `EventQueryFilter` or promote to types.capnp.
5. **MFA/lockout unification (founder decision, §5):** `access.capnp` owns the state machine and
   the recovery flow; auth.capnp and biometric.capnp should delegate. Requires access.capnp to
   host the shared `MfaChallenge`/`LockoutInfo`/`LockoutKind` forms and auth/biometric method
   signatures to change — not executed under the KEEP verdict.
6. **`T.HashOutput` (types.capnp:1179):** encodes `algorithm` as a UInt16 ordinal of the enums
   crypto.capnp deleted; adopting it would re-freeze algorithm identity. crypto.capnp documents
   the refusal at its HashResult. Foundation action: delete the type and its stale cross-schema
   note, or re-declare it over open tokens.
7. **`T.MacAddress` vs `T.BluetoothAddress` (verifier X1):** needs one canonical name adopted by
   bluetooth.capnp (batch B), network.capnp and shell.capnp (batches B/C).

## 4. Verification results

Compile check (`capnp compile -I schema -o- <file>`) for all 17 files, verbatim:

```
[ai] OK
[speech] OK
[translation] OK
[contacts] OK
[calendar] OK
[content] OK
[system_search] OK
[runtime_search] OK
[vcard] OK
[auth] OK
[biometric] OK
[access] OK
[crypto] OK
[key_management] OK
[signature] OK
[secret] OK
[sandbox] OK
```

`python3 scripts/validate.py` (read-only, final run), verbatim:

```
Schemas parsed: 89
E1 enums in ai.capnp            : 0
E2 bulk lists in ai.capnp       : 0
E4 interfaces unreachable (all) : 0 reported
E9 hits (all schemas)        : 7
E10 hits (all schemas)        : 74
E11 hits (all schemas)        : 6
E12 hits (all schemas)        : 73
E13 hits (all schemas)        : 16
E14 hits (all schemas)        : 13

exit=0 — PASSED — all enforced rules clean for schema/ai.capnp
```

Per-rule state of this batch's 17 files after the rewrite:

| Rule | Batch state |
|---|---|
| E6 (unions carry unknown/custom) | **0 hits** — every union in all 17 files terminates correctly (13 arms added this session) |
| E9 (platform/vendor nouns) | **0 hits** — all purged to open tokens/backend metadata |
| E12 (one home per type) | **0 intra-batch collisions**; 5 cross-batch pairs listed in §3 |
| E13 (ordinals) | 0 hits in batch files (access.capnp's pre-existing `AccessEvent` disorder is the one KEEP-file carry-over) |
| E8 (neutral @0) | 7 remaining, all event/result enums (O4's "document the rest"): DayOfWeek, ContactHistoryAction, SecretChangeType, SandboxState, ResourceType, TrendDirection, EnrollStep |
| E7 (extension points) | 184 REPORTs remain in batch files (1 650 tree-wide) — documented debt, see §6 |
| E10 (bulk) | 3 remain, all `Data`/`List(UInt8)` positions carrying small bounded material (MFA challenge payloads ×2, credential pattern) — see §6 |
| E11 (authority) | 4 are the `role :Text` false positive (vCard ROLE / org role / content role — a person's job role, not an authority declaration); 2 are sandbox's documented object-under-manipulation pair |
| E14 (reachability) | 3 remain: `AuthHandler`, `AudioStream`, `SearchHandler` — provider-registered callbacks passed as parameters; the same shape as live batch-B/C files (EndpointHandler, FsProvider, NicProvider, BlockProvider) |

## 5. Founder-decision items

1. **Crypto/signature vocabulary home — executed as ruled, ratification requested.** crypto.capnp
   is the canonical vocabulary home: open tokens + CONFORMANCE TOKENS consts, zero algorithm
   enums, and signature/biometric/key_management/secret all import that spelling (the
   divergent-ordinal wire hazard is structurally impossible now). The alternative — one shared
   enum family in types.capnp — was rejected because it re-freezes today's algorithm list in the
   eternal foundation file. Decision to ratify: **open-token model over enum promotion**, and the
   related `T.HashOutput` disposition (§3 item 6).
2. **MFA/lockout consolidation into access.capnp** (§3 item 5) — three MFA challenge shapes and
   four lockout structs across auth/access/biometric. Not executed: access.capnp is KEEP and the
   consolidation changes auth's and biometric's method signatures. If ratified, access.capnp
   hosts the canonical `MfaChallenge`/`LockoutInfo`/`LockoutKind` and the other two import.
3. **ai.capnp's `handshake` bound** — left ungated by design per the verifier's rejection of
   OVERREACH item 5 (bounding it against the deadlock reasoning). If discovery volume ever
   matters, the fix is `handshake → List(ModelId)` + descriptor lookup through `discover @1`,
   which keeps discovery pre-capability — a future option, not a defect.

## 6. Deferred work

- **E7 extension points (184 in batch / 1 650 tree-wide):** deliberately not applied. The
  verifier's OVERREACH O4 ruling rejects blanket sentinel/extension application, and
  validate.py's own E7 scoping (value-like structs exempt) already removed the noise class.
  Where an audit mandated a specific extension point it was added (e.g. signature's
  `SignatureRequest`/`PolicyAllowed`/`PolicyDenied`).
- **7 event/result enum sentinels** (E8 list in §4) — documented, not fixed: these enums are
  always written on the wire (events, progress reports), so an absent field cannot silently mean
  the @0 paradigm.
- **3 E10 small-material positions:** MFA challenge payloads (auth.capnp:289, access.capnp:465)
  are bounded challenge material like a tag or nonce — inline is correct by crypto.capnp's own
  stated rule; `CredentialValue.pattern :List(UInt8)` (access.capnp:337) is a bounded pattern
  mask. Renaming the fields to dodge the name heuristic was rejected as dishonest.
- **access.capnp `AccessEvent` E13** — one-line ordinal re-issue, held by the KEEP verdict.
- **sandbox `capabilityAdmin` design** — if the founder prefers the strict two-place reading of
  DESIGN_PRINCIPLES:438-450 with no exceptions, the alternative is moving grant/revoke of
  sandbox-held capabilities into capability.capnp (cross-batch, batch A) as transfer/attenuate
  call sites; the current shape keeps possession-as-proof that an id-keyed grant would lose.

*End of report. All changes verified compiling and validator-clean on disk; no commits made.*

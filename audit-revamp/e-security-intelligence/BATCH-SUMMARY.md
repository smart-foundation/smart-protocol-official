# BATCH SUMMARY — e-security-intelligence (17 schemas, 7 899 lines)

Cross-schema findings, a ranked action list, and per-schema verdicts. Every finding cites a
file:line; per-schema detail is in the individual reports.

---

## 1. Verdict table

| Schema | Verdict | One-line justification |
|---|---|---|
| `ai.capnp` | **FIX (targeted)** | Its header claims are verifiable and true (zero enums, zero inline bulk lists, every union forward-compatible, one root, zero-copy payloads); four local defects and one agent-permission hole remain |
| `speech.capnp` | **FIX (targeted)** | Zero-cost migration is genuine and correct; zero unions means no method can report failure, and two emotion enums + `AudioEncoding` freeze today's technology |
| `translation.capnp` | **FIX (targeted)** | `startStream` returns a non-interface struct and `subscribeBatchProgress` is keyed on an id no method produces; language-tag format is undeclared across three conventions |
| `contacts.capnp` | **FIX (targeted)** | Exemplary zero-cost posture and typed sub-entry ids; `shareContact` leaks personal data ungated, and 15 open-vocabulary enums are closed |
| `calendar.capnp` | **FIX (targeted)** | Sound structure and correct handles; vendor-named subscription enum, a `Recurrence` carrying two competing representations with no precedence, and boolean RBAC delegation |
| `content.capnp` | **FIX (targeted)** | The batch's best zero-cost discipline (embeddings, ciphertexts, previews all handles); re-implements access control wholesale and has a `decryptContent` with no output |
| `system_search.capnp` | **FIX (targeted)** | Icons/thumbs migrated to handles but the query embedding stayed inline `Data`, and the result id has a different type on the field than on the methods that consume it |
| `runtime_search.capnp` | **FIX (targeted)** | Best subscription-migration pattern in the tree and the batch's worst platform freeze (`unixDaemon`/`windowsService`/`pythonRuntime`), plus a third permission model and a `Capability` name collision |
| `vcard.capnp` | **FIX (targeted)** | A legitimate external-standard converter that should be kept (not merged into contacts); a 1998 TYPE vocabulary frozen into two enums while the open `parameters` mechanism sits two structs away |
| `auth.capnp` | **FIX (targeted)** | `DESIGN_PRINCIPLES.md:540` calls it "clean" — it contains the batch's worst security defect (`refreshToken` by id with no proof of possession) and a forbidden second authorization system |
| `biometric.capnp` | **FIX (targeted)** | Clean zero-cost profile; a third crypto-algorithm vocabulary in a required position, platform-specific modality/sensor enums, and one id type for both sensors and templates |
| `access.capnp` | **KEEP** | The batch's only systematic error model (unions with `T.Error` on every outcome) and the right owner of lock/MFA/lockout — a victim of duplication, not a cause |
| `crypto.capnp` | **REWRITE** | ~130 technology-named algorithm values in eight closed enums, in a file already amended once for post-quantum standards; the rewrite keeps the methods and opens every algorithm field |
| `key_management.capnp` | **FIX (targeted)** | A genuine identity split: local `KeyId` vs `T.KeyId` breaks at the call site against `content`/`backup`, and rotation's grace-window semantics are undeclared |
| `signature.capnp` | **FIX (targeted)** | Sign path is handle-based and correct; verify path is inline-copy, and its two algorithm enums share names with `crypto.capnp`'s at divergent ordinals (batch's worst latent wire hazard) |
| `secret.capnp` | **FIX (targeted)** | Entire interface ungated (total access to every secret) with duplicates of `crypto.capnp`'s KDF/wrap/compare paths and Linux/PKCS#11 mechanism names in required positions |
| `sandbox.capnp` | **FIX (targeted)** | Header claims "no seccomp, no landlock, no namespace" and the body contains seccomp actions, mount flags and RLIMIT names; a whole sandbox snapshot is returned as inline `Data` |

---

## 2. Cross-schema duplicates (the batch's dominant theme)

### 2.1 Permission/authority models — six parallel systems
| Model | Where |
|---|---|
| `Capability` + `Operation` (canonical) | `capability.capnp:22-124` |
| `ContentPermission` + `AccessRule`/`AccessPolicy` + delegation chain | `content.capnp:173-200`, `:224-227`, `:295-297` |
| `PermissionRequest`/`PermissionGrant`/`checkPermission` | `auth.capnp:25`, `:196-217` |
| `Capability` (local) + `PermissionDomain`/`PermissionAccess` | `runtime_search.capnp:238-286` |
| `CapabilityGrant {name, rights :List(Text), resource}` | `sandbox.capnp:280-284`, `:47-53` |
| `DelegatePermissions` (five booleans) | `calendar.capnp:460-466` |
| `ServiceAuth` (none/mtls/token/apiKey) | `runtime_search.capnp:178-188` |

`DESIGN_PRINCIPLES.md:399` forbids every one of these except the first. The cost is the one
the doctrine names: authority paths that must agree forever, where a grant made in one
system can outlive a revocation in another.

### 2.2 Crypto vocabularies — five spellings, with divergent ordinals
| Concept | Spellings |
|---|---|
| Signature algorithm | `crypto.capnp:610-635` (17, `ed25519`@12) · `signature.capnp:98-110` (9, `ed25519`@**0**) · `biometric.capnp:231-241` (9) |
| Hash algorithm | `crypto.capnp:263-296` (21, `sha256`@**1**) · `signature.capnp:114-125` (9, `sha256`@**0**) |
| Key format | `crypto.capnp:742-751` · `key_management.capnp:63-72` · `vcard.capnp:519-524` |
| Algorithm family | `key_management.capnp:49-61` · `crypto.capnp`'s eight enums |
| KDF request | `crypto.capnp:385-414` · `secret.capnp:229-240` (**same name, different fields**) |

The ordinal divergence is the most serious consequence: a bare algorithm ordinal crossing
the `signature`↔`crypto` boundary is silently reinterpreted (`5` = `mlDsa44` in one,
`ecdsaSha256` in the other).

### 2.3 MFA, lockout, and credential enrollment — three times each
| Concept | Spellings |
|---|---|
| MFA challenge | `auth.capnp:271-276` (`type :AuthMethodType`, no `issuedAt`) · `access.capnp:465-476` (`method :MfaMethod`, has `issuedAt`) — **same name, different fields** |
| MFA flow | `auth.capnp:46-47` `startMfa`/`verifyMfa` · `access.capnp:615-616` `requestMfaChallenge`/`verifyMfaChallenge` |
| Lockout | `auth.capnp:302-307` `LockoutStatus` · `access.capnp:397-406` `LockoutInfo` · `biometric.capnp:110-119` `LockoutInfo` (**same name, different fields**) |
| `LockoutKind` enum | `auth.capnp:309-315` and `biometric.capnp:121-127` — **byte-identical duplicates in two files** |
| Credential enrollment | `auth.capnp:50`, `:280-298` · `access.capnp:611` (+ recovery: `access.capnp:236-270`) |
| Auth result / subscription | `biometric.capnp:217`, `:355` (`AuthResult` enum, `AuthSubscription`) · `auth.capnp:125`, `:319` (`AuthResult` union, `AuthSubscription`) — **same names, different shapes** |

### 2.4 Same-name/different-shape type pairs (each is an import hazard)
| Pair | Locations |
|---|---|
| `MfaChallenge` | `auth.capnp:271-276` vs `access.capnp:465-476` |
| `LockoutInfo` | `access.capnp:397-406` vs `biometric.capnp:110-119` |
| `PolicyViolation` | `access.capnp:184-193` vs `sandbox.capnp:350-355` |
| `DeriveKeyRequest` | `crypto.capnp:385-414` vs `secret.capnp:229-240` |
| `RotationPolicy` | `key_management.capnp:123-132` vs `secret.capnp:162-171` |
| `AlignmentResult` | `translation.capnp:309-316` vs `speech.capnp:351-358` |
| `ConflictResolution` | `calendar.capnp:423-428` vs `vcard.capnp:667-672` (identical values) |
| `Certificate` / `CertificateInfo` | `signature.capnp:68-85` vs `crypto.capnp:823-838` |
| `Capability` | `capability.capnp:22-53` vs `runtime_search.capnp:238-248` |
| `TimeRange` | `contacts.capnp:501-504` and `calendar.capnp:358-361` vs `types.capnp:1553-1556` (`UInt64` ms — different semantics) |
| `FreeBusyStatus` / `FreeBusyPrivacy` | `contacts.capnp:403-409` vs `calendar.capnp:286-292` (identical values, and the calendar one is used as a *status*) |
| `SimilarityMetric` / `DistanceMetric` | `system_search.capnp:205-211` vs `content.capnp:389-395` |
| `SearchMode` | `contacts.capnp:529-535` vs `content.capnp:540-546` |

### 2.5 Identity splits — documented migrations that never happened
| Type | Documented in `types.capnp` | Actual state |
|---|---|---|
| `KeyId` | `:1036` "key_management.capnp: KeyId (replace local definition)" | **local `KeyId` still declared at `key_management.capnp:27`**; `T.KeyId` used by `content.capnp:261`, `content.capnp:534`, `backup.capnp` — call sites do not type-check across the two |
| `KeyFingerprint` | `:1058-1059` "signature.capnp: Signature.keyId, Certificate.issuerKeyId" | **unused; both fields are plain `Data`** (`signature.capnp:34`, `:80`) |
| `HashOutput` | `:1171-1173` "crypto.capnp HashResult.hash" | **unused; `crypto.capnp:307` returns raw `Data`** |
| `BiometricTemplateId` | `:439` | unused by `biometric.capnp`, which uses `T.BiometricId` for both sensors and templates |
| `DeviceId` | `:412` | `system_search.capnp:84` uses `List(Text)`; `key_management.capnp:297` uses `Text` |
| `UserId` | `:487` | `access.capnp:98` uses `Text` for the audit-relevant caller identity |
| `SessionId` | `:6` | `access.capnp:632` uses raw `UInt64` |

### 2.6 Feature overlap across the batch
- **Free/busy**: `contacts.capnp:86` `getFreeBusy` vs `calendar.capnp:46` `queryFreeBusy` — two contracts for one fact with different request shapes.
- **Search**: `system_search.capnp` (content), `runtime_search.capnp` (services), `content.capnp:237` `semanticSearch`, `contacts.capnp:139` `searchContactsRanked`, `calendar.capnp:52` `searchEvents` — five search surfaces with no shared query/result type.
- **vCard/contacts**: `vcard.capnp:348-406` `VCardContact` models `contacts.capnp:162-198` `Contact` a second time, with the field mapping undeclared while both files own import/export.
- **Translation**: `translation.capnp` and `speech.capnp:64` `translate` both translate text, with colliding `AlignmentResult`/`alignText` names.
- **Attestation**: three concepts — `key_management.capnp:99` (DataHandle), `signature.capnp:306-317` (typed struct with vendor-named formats), `runtime_search.capnp:192-199` (requirement flag).
- **Audit entries**: `capability.capnp:414-433`, `content.capnp:624-635`, `secret.capnp:188-201` — three audit-entry structs.

### 2.7 Error-model gap as a batch-wide pattern
**six of the seventeen files contain no union at all** (`speech`, `translation`, `contacts`,
`calendar`, `system_search`, `secret`), which means no method in them can return a `T.Error`
— `listen`, `translate`, `getContact`, `listEvents`, `search`, `getSecret` all return bare
structs or booleans. `access.capnp` (and, notably, `ai.capnp`) prove the union pattern is
compatible with this codebase. This is the single largest *systemic* defect in the batch.

### 2.8 Reachability (R8)
- Dead imports: `speech.capnp:4` (`using Translation` — never referenced).
- Dead types: `crypto.capnp:499-505` `RandomRequest`; `secret.capnp:244-257` `SecretCompliancePolicy`; `signature.capnp:261-272` `MultiSignRequest`; `signature.capnp:289-302` `ThresholdSignRequest`.
- Unreachable interfaces: `signature.capnp:351` `RevocationList` (and its `RevocationSubscription`).
- Unreachable-by-contract: `translation.capnp:99` `subscribeBatchProgress` keyed on a `batchId` no method produces; `translation.capnp:151` `TranslationStream` (a struct where an interface is needed).
- Methods whose result is the schema's own enum: `access.capnp:647` `listRecoveryMethods`; `vcard.capnp:44` `getSupportedVersions` (returns `v50`, a standard that does not exist).

---

## 3. Ranked top-10 action list for the batch

1. **`crypto.capnp`: open every algorithm field (8 enums → open tokens + `T.StringMap` parameters), with today's names published as `const` conformance tokens as `ai.capnp:600-622` does.** Gain: new cryptographic constructions become requestable and interoperable with **no schema change and no new ordinal**, closing an amendment loop the file has already entered once (the FIPS 203/204/205 additions at `:521`, `:591-604`); two backends can finally interoperate on an algorithm outside today's list. Cost: consumers switch on strings; `AlgorithmSpec`/`PostQuantumSpec` collapse into the same open form. *The single highest-value action in the batch.*
2. **Eliminate the duplicate crypto vocabularies** (signature/biometric/key_management/secret → one open spelling). Gain: closes the divergent-ordinal wire hazard (`signature.capnp:98` vs `crypto.capnp:610`) and four parallel vocabularies. Cost: four files' field types change — several need changing anyway.
3. **Fix the `KeyId` identity split** (`key_management.capnp:27` local vs `types.capnp:1041` promoted). Gain: one key identity across `key_management`/`content`/`backup`; removes a call-site type error that exists today. Cost: one deletion plus renames, no ordinal movement. **This is the only item that fixes something already broken.**
4. **`auth.capnp:40`: require proof of possession for `refreshToken`.** Gain: closes an unauthenticated session-extension path (a `UInt64` token id is enumerable and mints fresh tokens indefinitely). Cost: callers hold the token value, which they already have.
5. **Collapse the six permission models onto `capability.capnp`** (`content.AccessRule`, `auth.PermissionGrant`, `runtime_search.Capability/PermissionDomain`, `sandbox.CapabilityGrant`, `calendar.DelegatePermissions`). Gain: one authority path tree-wide; attenuation/revocation/delegation become available to every subsystem that currently lacks them; deletes the "grant outlives revocation" class of bug. Cost: five files' method signatures change — all pre-release.
6. **Result-side payloads to `T.DataHandle`**: `crypto.capnp:536`, `:552`, `:223`, `:258`, `:690`, `:429`, `:737`, `:47`; `signature.capnp:131`, `:152`, `:156`, `:168`, `:176`; `system_search.capnp:196`; `sandbox.capnp:62`. Gain: encrypt/decrypt round-trips, signature verification, semantic search, and sandbox migration stop copying bulk data; note the request sides already use handles, so this restores symmetry. Cost: callers read handles.
7. **Add result unions carrying `T.Error` to the six union-free files** (`speech`, `translation`, `contacts`, `calendar`, `system_search`, `secret`). Gain: failures stop being encoded as empty structs and empty strings; the fork where every backend invents a failure convention disappears. Cost: ~8 wrapper types per file, mechanical.
8. **Platform purge**: `runtime_search.capnp:203-220` `RuntimeKind` (`unixDaemon`/`windowsService`/`jsRuntime`/`pythonRuntime`/`luaRuntime`), `signature.capnp:319-325` `AttestationFormat` (`androidKeyStore`/`appleSecEnclave`), `secret.capnp:222` (`memfd`), `:209` (PKCS#11), `sandbox.capnp:189-198`/`:226-235`/`:288-298` (errno/trap/trace/killThread, nosuid/nodev/noexec, RLIMIT_*), `biometric.capnp:19-32`/`:71-84` (modality, sensor), `calendar.capnp:151-157` (`google`/`exchange`), `access.capnp:345` (PKCS#11/PIV). Gain: non-Linux, non-Apple, non-2026 platforms and backends stop having to fake mechanisms they do not have — the R5 test, applied. Cost: consumers switch on open strings in ~8 enums.
9. **Unify MFA/lockout/credential-enrollment**: `access.capnp` is the natural owner (it has the state machine, the recovery flow, and the only union-based error model); `auth.capnp` and `biometric.capnp` delegate. Gain: two MFA flows → one, four lockout structs → one, two identical `LockoutKind` enums → one. Cost: two files' signatures change.
10. **`ai.capnp` targeted fixes**: `ToolOutcome` union (`:344-350`), `AgentService.send` result union (`:413`), bounded ungated discovery (`handshake` returns `List(ModelId)`, `:573-575`), `AISubscription` backpressure (`:553`), and `tools :List(ToolId)` on `AgentDeclaration` (`:366-376`). Gain: the gold standard stops modelling the defects it elsewhere names (unbounded pulls, swallowed failures) and the agent tool-permission lifecycle becomes expressible; cost: four new constructs and one field.

---

## 4. Contradictions with the doctrine documents and schema headers

These are places where a document or a header asserts something its body does not deliver.
They are recorded here rather than in the per-schema reports because the contradiction is
with the *claim*, not the code.

1. **`DESIGN_PRINCIPLES.md:540, 544` rates `auth.capnp` and `secret.capnp` "Clean contract".** `auth.capnp:40` refreshes tokens from an enumerable id with no proof of possession and `:196-217` implements the exact permission model `:399` forbids; `secret.capnp:18-114` leaves the entire secret store ungated. The Appendix's verdicts for this batch are stale and actively misleading as a review input.
2. **`DESIGN_PRINCIPLES.md:463`** cites "A distributed system might use a JWT" as evidence that `Capability.id` being opaque `Data` is sound — while `auth.capnp:143-156` introduces `AuthToken { value :Data, type :TokenType.bearer/capability, claims }`, i.e. a first-class JWT-shaped token with its own verification path (`introspectToken @18`, `:61`) beside `CapabilityService.verify` (`capability.capnp:159`).
3. **`crypto.capnp:12-13`** claims "Deduplicates crypto bits from auth.capnp, biometric.capnp, signature.capnp, key_management.capnp" — and each of those four files still carries its own crypto vocabulary.
4. **`key_management.capnp:19-20`** claims "No algorithm-specific assumptions (RSA, ECC, AES — backend decides)" while `KeyAlgorithmFamily` (`:49-61`) names three post-quantum families permanently and `KeyExportFormat` (`:63-72`) names `mlKemSeed`/`mlDsaBytes`.
5. **`sandbox.capnp:8-10`** claims "no seccomp, no landlock, no namespace, no WASI, no gVisor, no Firecracker" while the body contains seccomp's action names (`:189-198`), its argument-filter model (`:155-174`), Linux mount flags (`:226-235`) and RLIMIT field names (`:288-298`).
6. **`runtime_search.capnp:11-13`** claims "Backend-agnostic: works with WASM runtimes, microservices, plugin systems, dynamic linkers, or any other mechanism" while `RuntimeKind` (`:203-220`) freezes `unixDaemon`, `windowsService`, `jsRuntime`, `pythonRuntime`, `luaRuntime`, `containerized`, `unikernel`.
7. **`system_search.capnp:9-11`** advertises the `T.DataHandle` migration for icons and thumbnails while the query embedding — the file's hot payload — stayed inline `Data` (`:196`).
8. **`speech.capnp:12-13`** claims "VoiceGender has custom variant for forward compatibility. VoiceType has custom variant for forward compatibility." Both are true formally, but `custom` carries no identity, so a 2046 value is representable only as an opaque slot — exactly the failure the R1 rule names.
9. **`vcard.capnp:8-9`** claims "contacts.capnp currently has no vCard support", which was true when written; `contacts.capnp:19-20` now has import/export, so the comment denies the file's central unresolved overlap.
10. **`types.capnp`'s own cross-schema impact notes are now false in three cases**: `KeyId` (`:1036`), `KeyFingerprint` (`:1058-1059`) and `HashOutput` (`:1171-1173`) each name a consumer schema that never adopted them — while the promotions that *were* performed (`EmailEntryId`/`PhoneEntryId`/`AddressEntryId`, `ScopeId`, `ActionId`, `CapabilityId`, `SearchBookmarkId`) worked. The comment block is a load-bearing promise the loader could not keep.
11. **`TIMELESSNESS.md:79`** rejects `systemd`/`syslinux` as "Product names" and offers `BootloaderKind { limine, grub, uefiDirect, custom }` as the replacement — two vendor names in its own example of rejecting vendor names. `boot.capnp:470-482` implements it literally (`grub @0`, `grub2 @1`, `limine @7`).
12. **`speech.capnp:12`** says "SearchAction.id uses T.EventId" — that line actually describes `system_search.capnp`, whose body uses `T.ActionId` (`system_search.capnp:187`). The header comment sits in the wrong file and describes the pre-migration state; it is the clearest example of header drift in the batch.

### What is genuinely exemplary and should not be "fixed"
- `ai.capnp`'s CONFORMANCE TOKENS section (`:587-622`) — the correct remedy for every closed-enum problem above, and the only place in the tree that models it.
- `access.capnp`'s outcome unions (`:410-427`, `:479-490`, `:687-695`) and `ai.capnp`'s `StreamStatus`/`ExecutionMode`/`AIEvent` (`:256-264`, `:195-203`, `:538-550`) — every union carries `unknown`/`custom`/`T.Error`.
- `runtime_search.capnp:525-532`'s `pullPage`-with-deprecated-unbounded-`pull`, `calendar.capnp:112-117`'s identical pattern, and `signature.capnp:134-139`'s deprecated-convenience + paginated pair — the correct migration shape for the batch's unbounded pulls.
- `contacts.capnp` and `content.capnp`'s zero-cost payload discipline (`contacts.capnp:169`, `content.capnp:88`, `:383`, `:531`, `:660`) — the standard the rest of the batch should reach.
- `capability.capnp` remains exemplary after the revamp rules, as stated; the finding against it (two call paths for the subscription, `:178`) is soft and does not change that verdict.

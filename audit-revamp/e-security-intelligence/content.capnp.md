# Audit — content.capnp (756 lines)

## Verdict
**FIX (targeted).** The zero-cost posture is right and thorough: `mimeData @11 :T.DataHandle` (`:88`), `ContentEmbedding.vector @0 :T.DataHandle` (`:383`), `ContentPreview.data @2 :T.DataHandle` (`:660`), `ContentEncryptedEnvelope.ciphertext @0 :T.DataHandle` (`:531`). This is one of the few files that never forces a copy for bulk data. The dominant defect is that it re-implements access control — an `AccessPolicy`/`AccessRule` ACL with its own permission enum, grant/revoke lifecycle, and delegation chain — in parallel with `capability.capnp`, which the doctrine declares to be *the* access control mechanism. Add a 21-value technology enum sitting next to a `mimeType` field, and a `decryptContent` method with no output.

## Wire-breakers
None. Method ordinals @0–@61 unique (`:204-333`); `ContentItem` @0–@27, `ContentFilter` @0–@14, `ContentEvent` union @2–@11 all collision-free; every `T.*` reference resolves, including `T.KeyId` (types.capnp:1041) and `T.HashOutput` (types.capnp:1179).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R1 | `content.capnp:46-70` `ContentType` (21 values: unknown/image/video/audio/text/document/contact/calendar/bookmark/file/url/event/task/other/custom/**embedding/model/dataset/code/archive/threeDmodel**) | An open taxonomy frozen into a closed enum — and `ContentItem.mimeType @2 :Text` (`:77`) sits in the same struct carrying the same information, with `T.MimeType` available | The Audit-8 additions (embedding/model/dataset/threeDmodel) are today's AI-era artifacts. A 2046 content type — a spatial scene, a neural weight set, a DNA record — lands in `custom @14` which carries nothing, so `ContentFilter.type @0` (`:150`) cannot select it and no consumer can branch on it. Two backends will disagree about what `ContentType.model` means, because the enum names no format |
| R3 | `content.capnp:173-200` `ContentPermission` + `AccessPolicy`/`AccessRule`; methods `grantAccess @11`, `revokeAccess @12`, `checkAccess @13`, `getAccessPolicy @14`, `delegateAccess @43`, `revokeDelegation @44`, `getDelegationChain @45` (`:224-227`, `:295-297`) | A complete second access-control system: its own permission vocabulary, its own grant/revoke lifecycle, its own delegation chain with `maxDepth` | `DESIGN_PRINCIPLES.md:399` forbids exactly this. Cost: two systems that must agree forever — a content grant made here can outlive or contradict a capability revoked in `capability.capnp`, and every consumer must learn two access models |
| R7 | `content.capnp:262` `decryptContent @28 (contentId) -> T.VoidResult` | A method with no output | Where does the plaintext go? Does `get @9` then return decrypted `mimeData`? Is the shared item mutated in place (affecting every other consumer)? The schema does not say, so every implementer must invent, and the two choices are not wire-compatible |
| R3/R6 | `content.capnp:261`, `:263` `encryptContent @27`, `rotateEncryptionKey @29` | Content owns key rotation, parallel to `KeyManagementService.rotateKey @3` (`key_management.capnp:266`) | There is no contract relating them: after `rotateEncryptionKey`, `ContentEncryptedEnvelope.keyId @1` (`:532`) points at a key whose status only `key_management` knows. Two backends will handle the pending envelope differently — one re-encrypts eagerly, one leaves a dangling reference |
| R4 | `content.capnp:560` `ContentBranch.branchId @0 :Text`; `:752` `ContentTranslation.provider @4 :Text` with examples "ai-deepl", "ai-google" | Unstructured Text id in a file that types every other id; vendor names in a doc comment | `branchId` is compared as a string across `createBranch @35`/`mergeBranch @37` (`:281`, `:283`), and two backends' branch namespaces are unrelated. The provider examples will be copied into another closed enum |
| R7 | `content.capnp:257`, `:251`, `:292`, `:297`, `:331` — `getUndoHistory @25`, `getProvenance @23`, `getLineage @42`, `getDelegationChain @45`, `getTranslations @60` | Five unbounded list returns with no pagination (contrast the 10 paginated methods in the same file) | A content item with 10k undo entries or a deep lineage graph copies all of them on every call |

## Duplicates & overlaps
- `DistanceMetric` (`:389-395`) ≡ `system_search.capnp:205-211` `SimilarityMetric` (identical five values, two enums, same concept).
- `SearchMode` (`:540-546`) ≡ `contacts.capnp:529-535` `SearchMode`.
- `AccessPolicy`/`AccessRule`/delegation ≡ `capability.capnp:22-124` (the canonical authority model) and `sandbox.capnp:280-284` `CapabilityGrant`.
- `RateLimitConfig` (`:640-650`) duplicates `capability.capnp:130-136` `RateBox`.
- `ContentUndoEntry` (`:501-508`) vs `capability.capnp:414-433` `AuditEntry` vs `secret.capnp:188-201` `AccessAuditEntry` — three audit-entry structs with overlapping fields.
- `ContentProvenance` (`:400-407`) vs `AiProvenance` (`:370-377`) vs `ContentLineage` (`:591-600`) — three provenance concepts in one file with no declared relationship.

## Gaps & holes
- **Decrypt destination** (above) — the file's most consequential hole.
- `getQualityScore @57` (`:323`) returns a "quality score" whose components (readability/completeness/freshness) are defined only in comments. Two backends score incomparably and a consumer cannot know. Either declare the formula or declare it backend-specific — currently it is neither.
- `getRecommendations @58` (`:326-327`) is a black box with `reason :Text` free-form. Same problem.
- `eraseContent @24 (reason :Text)` (`:254`) vs `ContentTombstone.legalBasis @3 :Text` (`:523`) — two free-text fields for what is legally a single obligation; no vocabulary means no compliance checking is possible.

## Zero-cost & eco
Pass, with the note that it is the *only* file in the batch alongside `contacts` that migrated both embeddings and ciphertexts to handles. Two residual issues: `getContentGraph @19` (`:241-242`) takes a `depth :UInt32` with no bound, so a deep graph copies the transitive closure; and `ContentItem.undoHistory @25 :List(ContentUndoEntry)` (`:109`) is an unbounded inline list on a struct that is itself returned by `query @8` — every search hit carries its entire edit history.

## UX & implementer guidance
- `ContentItem.version @14 :UInt64` (`:94`) is documented as an optimistic-concurrency guard, but `update @2 (contentId, item) -> T.VoidResult` (`:208`) never checks it and there is no result variant for a version conflict. The field is decorative: two writers can still silently overwrite. Either `update` returns a conflict union or the field is misleading.
- `ContentEvent` union (`:344-358`) has `custom @8 :Data` but no `unknown @N :UnknownEvent { typeId, payload :Data }` — the pattern `ai.capnp:533-536` and `calendar.capnp`-style forward compat demand.
- `ContentVisibility` (`:114-122`) and `ContentPermission` (`:173-183`) overlap in meaning (is `public` a visibility or a permission?) with no declared relationship — a consumer must guess which one gates what.
- `AiProvenance.seed @5 :UInt64` (`:376`) documents reproducibility for a model id expressed as free `Text` (`:371`) — reproducible only within one backend.

## Recommended actions
1. **Replace `AccessPolicy`/`AccessRule`/`ContentPermission`/grant/revoke/delegate with `Capability`.** The `Capability.target` for content already exists as a convention (textual target, `capability.capnp:31`); attenuation and revocation are already there. Gain: one access model tree-wide, and a deleted class of "the two systems disagree" bugs; cost: six method signatures change, and content-specific conveniences (`checkAccess @13`) become `CapabilityService.verify`.
2. **Define the decrypt contract: either `decryptContent` returns a new `ContentItem`/`ContentId`, or the schema declares that `mimeData` is replaced in place and states the visibility of that change.** Gain: two backends stop being wire-incompatible on the read path; cost: one signature or one paragraph.
3. **Delete `ContentType` in favour of `T.MimeType`** (the `mimeType` field already exists three lines away). Gain: an open content vocabulary and one fewer place for a 2046 taxonomy to be missing; cost: `ContentFilter.type` becomes a mime prefix, which it effectively already is.
4. **Paginate the five unbounded history/lineage/provenance lists.** Gain: bounded reads; cost: five signatures, each of which already has the `T.Pagination` pattern to copy.
5. **Make `update` honour `ContentItem.version`.** Gain: the optimistic-concurrency field stops being decorative; cost: a conflict variant on the result union.
6. **Repoint `encryptContent`/`rotateEncryptionKey` at `KeyManagementService.rotateKey`.** Gain: key lifecycle has one owner; cost: a cross-schema dependency content.capnp does not currently have (`T.KeyId` is already imported, so the type exists).

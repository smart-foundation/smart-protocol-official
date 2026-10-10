# Audit — key_management.capnp (308 lines)

## Verdict
**FIX (targeted).** The smallest file in the batch and structurally sound — result unions with `T.Error` on every operation (`:183-222`), pagination on `listKeys` (`:171-179`, `:271`), `T.DataHandle` for exported and attestation material (`:205`, `:99`). But it carries a genuine **identity split that breaks at the call site**: it declares its own `struct KeyId` while `T.KeyId` exists in `types.capnp`, and `types.capnp:1036` explicitly documents the migration that was never performed. Two other schemas (`content.capnp`, `backup.capnp`) already speak the promoted type. That is a compile/wire break today, not a style issue.

## Wire-breakers
Method ordinals @0–@15 unique (`:261-301`); struct ordinals collision-free. The identity split:
- `key_management.capnp:27` declares `struct KeyId { id @0 :UInt64; }` locally, and the file uses the bare name `KeyId` throughout (`:158`, `:165`, `:167`, `:172`, `:193`, `:229-231`, `:237-239`, `:243-249`, `:263-300`), while `T.KeyId` (`types.capnp:1041`) is the same shape under a different declaration. `content.capnp:261` `encryptContent(keyId :T.KeyId)`, `content.capnp:534` `ContentEncryptedEnvelope.keyId @1 :T.KeyId`, and `backup.capnp`'s `EncryptionInfo.keyId` all speak the promoted type.
- Consequence: a consumer that obtains a `T.KeyId` from content or backup and calls `KeyManagementService.getKey @5 (keyId :KeyId)` (`:270`) has two nominally distinct struct types with identical layout — a schema-level type error at the call site, or, in a hand-rolled binding that treats them as interchangeable, a silent crossing of two id namespaces.
- `ThresholdKey.shares @2 :List(KeyId)` (`:141`) and `deriveKey(..., derivedFrom :KeyId)` keep the local spelling alive inside this file.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R6 | `key_management.capnp:27` local `KeyId` vs `types.capnp:1041` `T.KeyId` (whose comment at `:1036` says "key_management.capnp: KeyId (replace local definition)") | One identity, two declarations; the documented migration was never performed | See Wire-breakers. Any file bridging content/backup (promoted) and this service (local) does not compile, and a permissive binding crosses the two id spaces silently |
| R6 | `key_management.capnp:63-72` `KeyExportFormat` (raw/pkcs8/spki/jwk/**mlKemSeed**/**mlDsaBytes**/custom) vs `crypto.capnp:742-751` `KeyFormat` (pkcs8/spki/pkcs12/jwk/pem/der/openssh/custom) | Two key-format vocabularies with different value sets | `KeyImportRequest.format @1 :KeyExportFormat` (`:146`) cannot name PEM or DER at all, so a backend holding a PEM key must pre-decode it outside the protocol. Two backends will map "raw" differently, since this file's comment says "Raw key bytes (encrypted)" (`:64`) while `crypto.capnp` has no `raw` at all |
| R1 | `key_management.capnp:49-61` `KeyAlgorithmFamily` (symmetric/asymmetric/hash/kdf/mac/mlKem/mlDsa/slhDsa/hybridPq/custom), `:68-71` `mlKemSeed`/`mlDsaBytes` | A third crypto vocabulary, and post-quantum family names in required positions, in a file whose header claims "No algorithm-specific assumptions (RSA, ECC, AES — backend decides)" (`:19-20`) | The header is contradicted by the body: three post-quantum families are named permanently, and `KeyGenerationRequest` (`:106-120`) requires *both* `algorithmFamily` and a free-text `algorithmDetails @2 :Text` (`:109`) — so two backends can disagree about which family an algorithm belongs to while the real spec lives in the Text |
| R7 | `key_management.capnp:123-132` `RotationPolicy` and `rotateKey @3` (`:266`) | Rotation policy declares `gracePeriod @2 :T.Duration` but `rotateKey` never says whether the old key remains usable during it, or who is expected to re-encrypt data | This is *the* key-rotation contract and it is silent on the one question every implementer must answer: does a rotated key keep working through the grace window? Two backends will answer differently, and a consumer that encrypts under the "old" key during the window may be producing data the new key cannot read |
| R3 | `key_management.capnp:297` `syncExport @14 (deviceId :Text) -> (encryptedBundle :T.DataHandle)`; `:290-294` `escrowKey @12`/`restoreKey @13` | Bulk key export to an arbitrary device and escrow/reconstruction, all ungated | Any holder of the service reference exports the key set for a device named by a free-form string. There is no capability gate and no declared encryption target beyond "for a specific target device" |
| R4 | `key_management.capnp:297` `deviceId :Text` | Unstructured device identifier in a tree with `T.DeviceId` | Two backends' device-id namespaces are unrelated; `syncImport @15` (`:300`) then imports a bundle encrypted for an unknown recipient |
| R7 | `key_management.capnp:254-257` `KeySubscription.pull @0 () -> (events, pagination, total)` — **no `cancel`** | The only subscription in the batch without a teardown method (compare `ai.capnp:555`, `secret.capnp:119`, `sandbox.capnp:76`, `signature.capnp:243`) | A long-lived key subscription cannot be explicitly released; the implementer must invent a lifetime rule (GC? timeout?) and the consumer cannot request teardown. `pull` also returns `pagination`/`total` for events the caller did not paginate — the same shape confusion seen in `translation.capnp` |

## Duplicates & overlaps
- `RotationPolicy` (`:123-132`) vs `secret.capnp:162-171` `RotationPolicy` — **same name, different fields** (`rotateAfter`/`rotateAfterOperations`/`gracePeriod`/`notifyBefore` vs `interval`/`onCompromise`/`maxAge`/`notifyBefore`). A file importing both has two types by one name.
- `DeriveKeyRequest` is imported here by reference only through `crypto.capnp`'s copy, but this file owns `deriveKey @11` (`:286-287`) with no `algorithm` parameter at all — a derivation with an undeclared algorithm.
- `KeyExportFormat` ↔ `crypto.capnp:742-751` `KeyFormat` ↔ `vcard.capnp:519-524` `KeyType`.
- `KeyAlgorithmFamily` ↔ `crypto.capnp`'s eight algorithm enums ↔ `biometric.capnp:231-241` `SigningAlgorithm`.
- `attestation @17 :T.DataHandle` (`:99`) ↔ `signature.capnp:306-317` `AttestationData` (typed struct) and `runtime_search.capnp:192-199` `AttestationRequirement` — three attestation concepts.

## Gaps & holes
- **Rotation semantics** (above): the grace window is undeclared, and there is no contract for re-keying dependent data (`content.capnp:263` `rotateEncryptionKey` reaches into this file with no shared rule).
- `escrowKey @12 (recoveryShares :List(T.DataHandle))` / `restoreKey @13 (shares :List(T.DataHandle)) -> (result :KeyGenerationResult)` (`:290-294`) — the restored key is identified only by the returned metadata; nothing binds the shares to a key id, and the `ThresholdKey` M-of-N config at `:135-142` is not referenced by either method. Two backends will reconstruct different keys from the same share set.
- `revokeKey @4 (keyId, reason :Text)` (`:267`) has no cascade contract: whether derived keys (`derivedFrom @14`, `:93`) and dependents (`revokedBy @15`, `:95`) are transitively revoked is unstated — and `revokedBy` is a single `KeyId`, so transitive revocation has no representation.
- `verifyAttestation @10 -> (attested :Bool, issuer :Text)` (`:283`) — attestation validity as a bare bool with a free-text issuer.

## Zero-cost & eco
Pass: `attestation @17 :T.DataHandle` (`:99`), `KeyExportData.keyData @0 :T.DataHandle` (`:205`). The one eco defect is `syncExport @14`'s unbounded encrypted bundle, which is at least a `T.DataHandle` on the return side.

## UX & implementer guidance
- The header (`:17-22`) states its design principles accurately — "Key material never crosses the protocol boundary" (`:21-22`) is honoured, except that `KeyExportRequest.format @1` can be `raw` (`:64`), which is precisely raw key bytes (encrypted, per the comment, but the encryption is undeclared).
- `KeyMetadata.status @5 :KeyStatus` (`:82`) and the separate timestamp fields `rotatedAt`/`revokedAt`/`expiresAt` (`:85-87`) are redundant with each other, with "0 = not yet" conventions that must be implemented three times.
- `maxOperations @7 :UInt64` (`:115`) auto-revokes a key after N operations, but `getUsage @9 -> (usage :KeyUsage)` (`:280`) is the only way to observe the count, and the revocation itself raises no event (`KeyEvent` has no `usageExhausted` variant, `:226-237`).
- `KeyFilter.purposes @0`/`statuses @1` are correctly `List(...)` with "empty = all" documented (`:171-173`) — a good pattern.

## Recommended actions
1. **Delete the local `KeyId` and use `T.KeyId` everywhere in the file.** Gain: one key identity across `key_management`, `content`, and `backup`; removes a call-site type error; the `types.capnp:1036` comment becomes true. Cost: one deletion plus a rename at ~20 sites, no ordinal movement.
2. **Declare rotation semantics: what the old key may do during `gracePeriod`, and who re-encrypts.** Gain: closes the fork on the file's central question; cost: one comment (plus an event variant if backends should announce the transition).
3. **Unify `KeyExportFormat` with `crypto.capnp`'s `KeyFormat` into one open format token**, and drop `mlKemSeed`/`mlDsaBytes`. Gain: a key held as PEM/DER becomes importable, and post-quantum names stop being permanent; cost: a type change plus a rename.
4. **Delete `KeyAlgorithmFamily` (or reduce it to the open `algorithmDetails` token).** Gain: removes a third crypto vocabulary and a contradiction of the file's own header; cost: `KeyGenerationRequest`/`KeyImportRequest`/`KeyFilter` lose one field each.
5. **Add `cancel @1` to `KeySubscription`, and drop the meaningless `pagination`/`total` from its `pull`.** Gain: the subscription becomes releasable and its result stops implying a pagination the caller does not control; cost: one method and two result fields.
6. **Gate `syncExport`/`escrowKey`/`restoreKey` behind a capability, and bind escrow shares to a key id.** Gain: bulk key export and escrow stop being ungated, and `restoreKey` stops reconstructing an unidentified key; cost: an authority parameter plus a field.

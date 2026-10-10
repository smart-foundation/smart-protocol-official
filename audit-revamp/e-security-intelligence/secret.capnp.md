# Audit — secret.capnp (305 lines)

## Verdict
**FIX (targeted).** `DESIGN_PRINCIPLES.md:544` judges this a "Clean contract" — again, that verdict does not survive contact with the body. The whole interface is ungated, so holding the reference is total access to every secret in every namespace, including an `injectSecret` that writes a secret into an arbitrary process. The file also duplicates `crypto.capnp`'s KDF contract and key-wrapping path, carries a same-named `RotationPolicy` with different fields from `key_management.capnp`, and names Linux and PKCS#11 mechanisms in required positions. Positive: `listSecrets`/`getAccessAudit` are paginated and `ChangesSubscription` has both pagination and `cancel`.

## Wire-breakers
Method ordinals @0–@26 unique (`:18-114`); struct ordinals collision-free; all `T.*` references resolve. Two same-name/different-shape collisions with other files in the batch:
- `secret.capnp:229-240` `DeriveKeyRequest` (algorithm :Text, password :Data, salt :Data, iterations, keyLength) vs `crypto.capnp:385-414` `DeriveKeyRequest` (algorithm :KdfAlgorithm, password :T.DataHandle, salt, keyLength, iterations, memoryKib, parallelism, scryptN/r/p, bcryptCost, info, custom). Two types by one name; a file importing both has two `DeriveKeyRequest`s, and `Secret.deriveKey @16` (`:68`) and `CryptoService.deriveKey @4` (`crypto.capnp:39`) are two KDF contracts with incompatible parameter sets.
- `secret.capnp:162-171` `RotationPolicy` (interval/onCompromise/maxAge/notifyBefore) vs `key_management.capnp:123-132` `RotationPolicy` (rotateAfter/rotateAfterOperations/gracePeriod/notifyBefore).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R3 | `secret.capnp:18-114` (whole interface) | No capability gating and no accessor — `getSecret @1` (`:21`) returns any secret's value, `injectSecret @19` (`:79-80`) writes a secret into an arbitrary process by `T.ProcessId`, `splitSecret @17`/`reconstructSecret @18` (`:71`, `:76`) reconstruct any secret from shards, `clearNamespace @5` (`:31`) wipes a namespace | Holding the `Secret` reference is total access to every secret in every namespace. Compare `ai.capnp:578-584` (gated at acquisition) and `DESIGN_PRINCIPLES.md:385-380` (privileged services obtained through an accessor). A compromised `Secret` reference is total compromise, and there is no attenuation or revocation path available *through this schema* |
| R5 | `secret.capnp:222` `SecretInjection.method @1 :Text` with examples "env", "file", **"memfd"**; `:209` `HsmBacking.providerType @1 :Text` with examples "**PKCS#11**", "TPM", "Secure Enclave" | Linux syscall and PKCS#11 mechanism names in required positions (R5 names PKCS#* explicitly) | `memfd` is Linux's `memfd_create`; a backend with no memfd (a capability kernel, WASI, a BSD) cannot express equivalent injection. `providerType` naming PKCS#11 tells implementers to expect a PKCS#11-shaped HSM, and a non-PKCS#11 enclave has no declared spelling |
| R2 | `secret.capnp:21` `getSecret @1 -> (value :Data)`, `:76` `reconstructSecret`, `:98` `generateSecret`, `:103` `compareSecrets (secret1 :Data, secret2 :Data)`, `:109`/`:113` `wrapSecret`/`unwrapSecret` | Every secret value is an inline copy on every read path | Secrets are usually small, so this is a smaller cost than `crypto.capnp`'s — but a private key, a certificate bundle, a provisioning token, or an exported vault is bulk payload and is copied on every `getSecret`. `compareSecrets` compounds it: two secrets are copied into the message in order to be compared "in constant time" |
| R6 | `secret.capnp:68` `deriveKey @16` + `:229-240` `DeriveKeyRequest`; `:108-113` `wrapSecret`/`unwrapSecret`; `:103` `compareSecrets` | Three duplicates of `crypto.capnp` (`deriveKey @4`, `wrapKey @14`/`unwrapKey @15`, `constantTimeCompare @18`) | A backend must implement KDF and key-wrapping twice, with two different parameter sets and two different algorithm types (`Text` here, an enum there). Two backends deriving the "same" key can produce different outputs |
| R7 | `secret.capnp:36` `getVersions @8` unbounded; `:183` `SecretOverlay.overrides @3 :T.StringMap` | Version history unpaginated; secret values carried as `Text` map values | A secret rotated 10 000 times returns all versions in one message. And `overrides` puts secret *values* into a `T.StringMap`, where they are `Text` — copied, greppable, and trivially logged by any debugging path that dumps a map. There is no opacity marker on the value |
| R8 | `secret.capnp:244-257` `SecretCompliancePolicy` — **never used by any method** | A dead compliance-policy struct sitting beside two methods that could have consumed it (`setRotationPolicy @12` exists; there is no `setCompliancePolicy`) | An implementer will wire it somewhere, and two backends will wire it differently. There is no declared reporting requirement, so the field set (`requireHsm`, `requireAudit`) is unobservable |

## Duplicates & overlaps
- `DeriveKeyRequest` ↔ `crypto.capnp:385-414` (same name, different fields).
- `RotationPolicy` ↔ `key_management.capnp:123-132` (same name, different fields).
- `wrapSecret`/`unwrapSecret` ↔ `crypto.capnp:77-80` `wrapKey`/`unwrapKey` ↔ `key_management.capnp:290-294` escrow.
- `compareSecrets` ↔ `crypto.capnp:101` `constantTimeCompare` (identical semantics, duplicate).
- `deriveKey` ↔ `crypto.capnp:39` `deriveKey` ↔ `key_management.capnp:286` `deriveKey @11`.
- `AccessAuditEntry` (`:188-201`) ↔ `capability.capnp:414-433` `AuditEntry` ↔ `content.capnp:624-635` `ContentAuditEntry` — three audit-entry structs with overlapping fields.
- `HsmBacking` (`:205-214`) ↔ `key_management.capnp:91` `hsmBacked` flag ↔ `biometric`'s hardware model.
- `SecretGenerateRequest` generating certificates (`:302-304`) duplicates `crypto.capnp`'s certificate operations with no typed result.

## Gaps & holes
- **No authorization model at all** (above). Adjacent and equally important: no contract for which app owns a namespace. `AccessAuditEntry.actor @4 :Text` (`:198`) is free-form, so "who read this secret" is answered with a string that two backends will spell differently, and there is no way to correlate it with `T.AppId`/`T.UserId`.
- `splitSecret @17 (totalShards, requiredShards) -> (shards :List(Data))` (`:71-73`) declares a threshold but has no verification contract: `reconstructSecret @18 (shards :List(Data)) -> (secret :Data)` (`:76`) does not state what happens with too few shards, with shards from different secrets, or with wrong shards. The three failure modes are all plausible and all undefined.
- `rollbackVersion @10` (`:44`) has no declared behaviour when the target version has a different size/format than the current one (the `SecretVersion.hash @4 :Data` at `:157` is the only integrity signal).
- `injectSecret @19` has no contract for the lifetime of the injected copy: whether the process keeps it after the injection call, or whether revoking the secret revokes the injected copy.

## Zero-cost & eco
Every value path is inline `Data` (see R2). `listSecrets @0` carries a `sizeBytes @5 :UInt64` field (`:129`) — a genuinely good design that lets a caller assess size without fetching, and worth noting as the pattern other secret/credential stores should copy.

## UX & implementer guidance
- `getSecret @1` and `getVersion @9` return `(value :Data)` with no result union, so a missing key is indistinguishable from an empty value — `hasSecret @2` (`:22`) exists for existence checks, but the "not found" case on the getter has no typed representation.
- `getAccessAudit @14` is paginated and `exportAccessAudit @15 (format :Text) -> (data :T.DataHandle)` is a handle — both correct, and the `format` is open (`"siem"`-style, `:64`) which is right.
- `ChangesSubscription.pull @0 (pagination)` returns `(changes, total)` (`:117`) with a `cancel @1` — the correct subscription shape, and better than `key_management.capnp:255` which lacks the `cancel`.
- `SecretOverlay.environmentId @0 :Text` with examples "dev"/"staging"/"production" (`:177`) imports deployment topology into a protocol contract; two backends will disagree about which environments exist.
- `SecretTemplateField.validationPattern @4 :Text` (`:284`) is a regex in a `Text` field — `T.Regex` exists (`types.capnp:1481-1484`) and would have made the pattern self-describing.

## Recommended actions
1. **Gate the interface: split it into an ungated discovery root and a gated `Secret` service obtained with a `Capability` whose target names the namespace.** Gain: a stolen reference stops being total compromise; attenuation and revocation become available through the authority model instead of being absent; cost: one root interface and one capability parameter (the exact shape `ai.capnp:572-585` already demonstrates).
2. **Delete the KDF, wrapping, and comparison paths from this file and delegate to `crypto.capnp`.** Gain: one KDF contract with one parameter set; two backends stop deriving different keys from the same inputs; cost: `deriveKey`/`wrapSecret`/`unwrapSecret`/`compareSecrets` are removed in favour of four `CryptoService` calls.
3. **Generalise the two R5 comments** (`method` at `:222`, `providerType` at `:209`) to open, non-mechanism-naming descriptions. Gain: stops telling implementers to expect `memfd`/`PKCS#11 #`; cost: two lines.
4. **Use `T.DataHandle` for values larger than the small-secret case, or at minimum split a handle/inline union like `T.DataHandle` already does.** Gain: private keys and certificate bundles stop being copied on every read; cost: callers read a handle — the same change `crypto.capnp` needs.
5. **Declare what `injectSecret`'s process receives and how long it lives, and gate it.** Gain: an out-of-band injection window stops being a per-backend security hole; cost: one comment plus a capability check.
6. **Reconcile `RotationPolicy` naming across `secret` and `key_management`** (one type, one field set, or two clearly-named types). Gain: the same-name/different-shape trap disappears; cost: a rename in one file.
7. **Delete `SecretCompliancePolicy` or add a method that consumes it.** Gain: no dead struct for implementers to wire inconsistently; cost: one deletion or one method.

@0xa1b2c3d4e5f60028;

using T = import "types.capnp";
using import "capability.capnp".Capability;

# ══════════════════════════════════════════════════════════════════════
# Secret — secret/credential storage with namespace isolation.
#
# ── THE WHOLE SURFACE WAS UNGATED ─────────────────────────────────────
#
# The previous version exposed every operation to any holder of the
# reference: `getSecret` returned any secret's value, `injectSecret`
# wrote a secret into an arbitrary process, `splitSecret`/
# `reconstructSecret` reconstructed any secret from shards,
# `clearNamespace` wiped a namespace, and `syncExport`-grade bulk export
# was a free-text device string away. A compromised reference was total
# compromise, and there was no attenuation or revocation path available
# through this schema at all.
#
# The surface is now obtained once, through an accessor that takes a
# Capability whose `target` names the namespace it governs. Holding the
# returned reference IS the authority over that namespace; no method
# below takes an authority token. That is the ai.capnp pattern, and it is
# what makes attenuation and revocation (capability.capnp's `attenuate`,
# `revoke`, `revokeControlled`) actually reachable for secrets.
#
# Template discovery stays ungated: a template describes the SHAPE of a
# secret, never its value, and a caller must be able to learn what a
# secret store expects before it holds any authority.
#
# ── ONE CRYPTO CONTRACT ───────────────────────────────────────────────
#
# This file carried its own KDF (`deriveKey` + a `DeriveKeyRequest` with
# the same name and different fields as crypto.capnp's), its own key
# wrapping (`wrapSecret`/`unwrapSecret`) and its own constant-time
# comparison (`compareSecrets`) — three duplicates of crypto.capnp, with
# two different parameter sets and two different algorithm types. A
# backend therefore had to implement KDF and wrapping twice, and two
# backends could derive different keys from the same inputs. All three
# now delegate to crypto.capnp, which is the canonical crypto vocabulary
# home and whose open tokens this file's algorithms share.
#
# ── VALUES ARE HANDLES ────────────────────────────────────────────────
#
# Every secret value path was inline `Data`, so a private key, a
# certificate bundle, a provisioning token or an exported vault was
# copied on every read — and `SecretOverlay.overrides` carried secret
# VALUES in a T.StringMap, i.e. as greppable Text, trivially logged by
# any debugging path that dumps a map. Values are T.DataHandle now,
# which keeps small secrets inline and only large ones in a buffer.
# ══════════════════════════════════════════════════════════════════════

# ── Root: ungated discovery, gated store ──────────────────────────────

interface Secret {
    # Gated once, at acquisition. `target` names the namespace (or the
    # whole store); `operations` narrows what the holder may do.
    store @0 (authority :Capability) -> (service :SecretStore);

    # Ungated: what shapes this store can hold. A template is metadata
    # about a secret's structure, never the secret.
    listSecretTemplates @1 () -> (templates :List(SecretTemplate));
}

interface SecretStore {
    listSecrets @0 (namespace :T.SecretNamespaceId, pagination :T.Pagination)
                -> (secrets :List(SecretEntry), total :UInt32);
    # T.DataHandle: small secrets stay inline, a key or certificate
    # bundle becomes a buffer reference instead of a copy. The result is
    # an outcome union so a missing key is distinguishable from an empty
    # value — previously both were an empty Data field.
    getSecret   @1 (key :T.SecretKeyId, namespace :T.SecretNamespaceId)
                -> (result :SecretValueResult);
    hasSecret   @2 (key :T.SecretKeyId, namespace :T.SecretNamespaceId) -> (exists :Bool);

    # Batch existence check: verify multiple secrets exist without fetching values.
    hasSecrets @3 (keys :List(T.SecretKeyId), namespace :T.SecretNamespaceId)
               -> (results :List(Bool));

    setSecret      @4 (key :T.SecretKeyId, value :T.DataHandle, namespace :T.SecretNamespaceId, metadata :T.StringMap)
                   -> T.VoidResult;
    deleteSecret   @5 (key :T.SecretKeyId, namespace :T.SecretNamespaceId) -> T.VoidResult;
    clearNamespace @6 (namespace :T.SecretNamespaceId) -> T.VoidResult;

    subscribeChanges @7 (namespace :T.SecretNamespaceId) -> (subscription :SecretChangeSubscription);

    # Audit-8: Get secret version history. Paginated: the previous
    # unbounded return put a 10 000-rotation history in one message.
    getVersions @8 (key :T.SecretKeyId, namespace :T.SecretNamespaceId, pagination :T.Pagination)
        -> (versions :List(SecretVersion), total :UInt32);

    # Audit-8: Get a specific secret version.
    getVersion @9 (key :T.SecretKeyId, namespace :T.SecretNamespaceId, version :UInt32)
        -> (result :SecretValueResult);

    # Audit-8: Rollback to a previous secret version. Declared behaviour,
    # because "roll back to a version of a different size/format" was
    # undefined: the backend MUST refuse with T.Error(invalidArgument)
    # when the target version's size or format differs from the current
    # one, and MUST leave the current version intact when it refuses.
    rollbackVersion @10 (key :T.SecretKeyId, namespace :T.SecretNamespaceId, version :UInt32)
        -> T.VoidResult;

    # Audit-8: Get rotation policy for a secret.
    getRotationPolicy @11 (key :T.SecretKeyId, namespace :T.SecretNamespaceId)
        -> (policy :SecretRotationPolicy);

    # Audit-8: Set rotation policy for a secret.
    setRotationPolicy @12 (key :T.SecretKeyId, namespace :T.SecretNamespaceId, policy :SecretRotationPolicy)
        -> T.VoidResult;

    # Audit-8: Apply secret overlay (environment-specific overrides).
    applyOverlay @13 (namespace :T.SecretNamespaceId, overlay :SecretOverlay)
        -> T.VoidResult;

    # Audit-8: Get secret access audit log.
    getAccessAudit @14 (namespace :T.SecretNamespaceId, pagination :T.Pagination)
        -> (entries :List(AccessAuditEntry), total :UInt64);

    # Audit-8: Export access audit log for compliance.
    exportAccessAudit @15 (namespace :T.SecretNamespaceId, format :Text)
        -> (data :T.DataHandle);

    # Audit-8: Split a secret using Shamir's Secret Sharing. The three
    # failure modes of `reconstructSecret` (too few shards, shards from
    # different secrets, wrong shards) were previously undefined; each
    # is now a declared error rather than a per-backend guess.
    splitSecret @16 (key :T.SecretKeyId, namespace :T.SecretNamespaceId,
        totalShards :UInt32, requiredShards :UInt32)
        -> (shards :List(T.DataHandle));

    # Audit-8: Reconstruct a secret from shards.
    reconstructSecret @17 (shards :List(T.DataHandle)) -> (result :SecretValueResult);

    # Audit-8: Inject a secret into a process. `method` is an open token
    # describing what the backend did, NOT a mechanism name: the previous
    # examples ("env", "file", "memfd") told implementers to expect
    # Linux's memfd_create, and a backend with no memfd (a capability
    # kernel, WASI, a BSD) had no declared alternative spelling.
    #
    # Declared lifetime: the injected copy is a SNAPSHOT taken at call
    # time. It is not revoked when the secret is, and the caller cannot
    # observe it afterwards. A backend that can revoke injected copies
    # reports that capability in `custom`.
    injectSecret @18 (key :T.SecretKeyId, namespace :T.SecretNamespaceId,
        injection :SecretInjection) -> T.VoidResult;

    # Audit-8: Get HSM backing status for a secret.
    getHsmBacking @19 (key :T.SecretKeyId, namespace :T.SecretNamespaceId)
        -> (backing :HsmBacking);

    # Audit-9: Create a secret from a template (generates structured fields).
    createFromTemplate @20 (templateId :Text, namespace :T.SecretNamespaceId, fields :T.StringMap)
        -> (key :T.SecretKeyId);

    # Audit-9: Generate a random secret from a template.
    generateSecret @21 (request :SecretGenerateRequest) -> (value :T.DataHandle, metadata :T.StringMap);
}

interface SecretChangeSubscription {
    pull   @0 (pagination :T.Pagination) -> (changes :List(SecretChange), total :UInt32);
    cancel @1 () -> T.VoidResult;
}

# A secret value read back from the store. The union exists so a caller
# can tell "no such secret" from "an empty secret" — the previous bare
# `Data` return could not, and `hasSecret` existed only because of that.
struct SecretValueResult {
    union {
        value @0 :T.DataHandle;
        error @1 :T.Error;
        custom @2 :Data;
    }
}

struct SecretEntry {
    key       @0 :T.SecretKeyId;
    namespace @1 :T.SecretNamespaceId;
    created   @2 :T.Timestamp;
    modified  @3 :T.Timestamp;
    metadata  @4 :T.StringMap;
    # Size of the secret value in bytes. Enables callers to assess
    # secret size without fetching the value itself.
    sizeBytes @5 :UInt64;
}

struct SecretChange {
    type      @0 :SecretChangeType;
    key       @1 :T.SecretKeyId;
    namespace @2 :T.SecretNamespaceId;
}

enum SecretChangeType {
    created @0;
    updated @1;
    deleted @2;
    custom  @3;
}

# ── Audit-8: Secret Version ───────────────────────────────────────────

struct SecretVersion {
    version @0 :UInt32;
    createdAt @1 :T.Timestamp;
    expiresAt @2 :T.Timestamp;
    active @3 :Bool;
    hash @4 :Data;
}

# ── Audit-8: Rotation Policy ──────────────────────────────────────────
# Named SecretRotationPolicy, not RotationPolicy: key_management.capnp
# declares a `RotationPolicy` with a different field set
# (rotateAfterOperations/gracePeriod vs interval/maxAge), and two
# same-named types with different shapes in one protocol is an import
# hazard. The field sets differ because they govern different things —
# a key's lifecycle versus a secret's — so the honest fix is two clear
# names, not one merged shape.
struct SecretRotationPolicy {
    # Rotate after this duration (0 = no time-based rotation).
    interval @0 :T.Duration;
    # Whether to rotate immediately on compromise.
    onCompromise @1 :Bool;
    # Maximum age before forced rotation (0 = unlimited).
    maxAge @2 :T.Duration;
    # Notify before expiration (0 = no notification).
    notifyBefore @3 :T.Duration;
    # Whether the previous version remains readable during the grace
    # window after rotation. Declared because it was previously
    # unstated: a backend that kept it and one that dropped it produced
    # different readers after every rotation.
    keepPreviousVersion @4 :Bool;
    custom @5 :T.StringMap;
}

# ── Audit-8: Secret Overlay ───────────────────────────────────────────

struct SecretOverlay {
    # Environment identifier (open token, e.g. "dev", "staging").
    environmentId @0 :Text;
    priority @1 :UInt32;
    # Merge strategy (open token, e.g. "replace", "merge", "append").
    mergeStrategy @2 :Text;
    # Overrides carry VALUES as handles, not as T.StringMap Text: a
    # secret value typed as Text was copied into the message, greppable,
    # and trivially captured by any debug path that dumps a map.
    overrides @3 :List(SecretOverride);
}

struct SecretOverride {
    key @0 :T.SecretKeyId;
    value @1 :T.DataHandle;
    expiresAt @2 :T.Timestamp;
    metadata @3 :T.StringMap;
}

# ── Audit-8: Access Audit Entry ───────────────────────────────────────

struct AccessAuditEntry {
    timestamp @0 :T.Timestamp;
    keyId @1 :T.SecretKeyId;
    namespace @2 :T.SecretNamespaceId;
    # Action performed, as an open token ("read", "write", "delete").
    action @3 :Text;
    # Who performed the access. Typed, so "who read this secret" is
    # correlatable with T.UserId/T.AppId elsewhere instead of being a
    # free-form string two backends spell differently.
    actor @4 :T.UserId;
    # Source address, when the access came from off-device.
    sourceAddress @5 :Text;
    custom @6 :T.StringMap;
}

# ── Audit-8: HSM Backing ──────────────────────────────────────────────

struct HsmBacking {
    supported @0 :Bool;
    # What kind of backing this is, as the BACKEND describes it. The
    # previous examples ("PKCS#11", "TPM", "Secure Enclave") told
    # implementers to expect a PKCS#11-shaped HSM; a non-PKCS#11 enclave
    # had no declared spelling. R5 names PKCS#* explicitly for this
    # reason.
    providerType @1 :Text;
    keyId @2 :Text;
    # Algorithm, as an open token shared with crypto.capnp.
    algorithm @3 :Text;
}

# ── Audit-8: Secret Injection ─────────────────────────────────────────

struct SecretInjection {
    processId @0 :T.ProcessId;
    # What the backend did, as an open token — NOT a mechanism name.
    method @1 :Text;
    # Target path (for file injection) or env var name.
    path @2 :Text;
}

# ── Audit-9: Secret Template ───────────────────────────────────────────
struct SecretTemplate {
    templateId @0 :Text;
    name @1 :Text;
    description @2 :Text;
    fields @3 :List(SecretTemplateField);
    defaults @4 :SecretGenerateRequest;
}

struct SecretTemplateField {
    name @0 :Text;
    # Open token, e.g. "text", "password", "url", "email".
    type @1 :Text;
    required @2 :Bool;
    defaultValue @3 :T.DataHandle;
    # Validation pattern, as a T.Regex so it is self-describing rather
    # than a bare Text whose dialect every backend guesses.
    validationPattern @4 :T.Regex;
    sensitive @5 :Bool;
}

# ── Audit-9: Secret Generation Request ─────────────────────────────────
struct SecretGenerateRequest {
    # Generation algorithm, open token: "random", "diceware", "uuid", ...
    algorithm @0 :Text;
    # Desired length in characters/bits (interpretation depends on algorithm).
    length @1 :UInt32;
    characterSet @2 :Text;
    wordCount @3 :UInt32;
    wordList @4 :Text;
    certificateSubject @5 :Text;
    certificateValidity @6 :T.Duration;
    # Certificate generation goes through crypto.capnp's certificate
    # operations; the previous local path duplicated them with no typed
    # result.
    certificateAlgorithm @7 :Text;
    parameters @8 :T.StringMap;
}

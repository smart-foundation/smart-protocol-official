@0xa1b2c3d4e5f60055;

# ═══════════════════════════════════════════════════════════════════════
# Content — cross-app data sharing with relationships and versioning.
#
# Zero-backend-assumption IPC contract for content publication, querying,
# and lifecycle management. No filesystem, database, or transport assumptions.
#
# The zero-cost posture is right and thorough, and is kept: mimeData,
# ContentEmbedding.vector, ContentPreview.data and
# ContentEncryptedEnvelope.ciphertext are all T.DataHandle. This is one
# of the few files that never forces a copy for bulk data.
#
# ── THE SECOND ACCESS-CONTROL SYSTEM IS DELETED ────────────────────────
#
# This file carried a complete parallel authorization system:
# `ContentPermission` (its own permission vocabulary), `AccessPolicy`/
# `AccessRule` (its own grants with expiry and scope), its own
# grant/revoke lifecycle (grantAccess/revokeAccess/checkAccess/
# getAccessPolicy) and its own delegation chain with maxDepth
# (delegateAccess/revokeDelegation/getDelegationChain).
#
# DESIGN_PRINCIPLES.md:399 forbids exactly this: "Do NOT define
# permission strings, boolean flags, or role-based access control in the
# protocol. The capability system IS the access control mechanism." The
# cost was concrete — a content grant made here could outlive or
# contradict a capability revoked in capability.capnp, and every consumer
# had to learn two access models and reconcile them.
#
# Authority over a content item is now a Capability whose `target` names
# the item and whose `operations` narrow what the holder may do.
# Attenuation and revocation are capability.capnp's `attenuate @2` /
# `revoke @4` / `revokeControlled @9`; checking one is
# `CapabilityService.verify`. All seven local methods and all four local
# types are deleted rather than reimplemented.
#
# ── DECRYPT HAD NOWHERE TO PUT THE PLAINTEXT ───────────────────────────
#
# `decryptContent` returned T.VoidResult. Where does the plaintext go?
# Does `get` then return decrypted `mimeData`? Is the shared item
# mutated in place, affecting every other consumer? The schema did not
# say, so every implementer had to invent, and the two choices were not
# wire-compatible. Declared now: decryptContent READS THROUGH, replacing
# `mimeData` with a handle to the plaintext for the caller's connection
# only, and leaving the stored ciphertext untouched. A backend that
# cannot do that MUST refuse with T.Error(unsupported) rather than
# silently doing something else.
#
# ── AN OPEN TAXONOMY, NOT A 21-VALUE ENUM ──────────────────────────────
#
# `ContentType` froze today's content kinds — including the Audit-8
# additions embedding/model/dataset/threeDmodel, which are today's
# AI-era artifacts — while `ContentItem.mimeType` sat three lines away
# carrying the same information with T.MimeType available. A 2046 content
# kind (a spatial scene, a neural weight set, a DNA record) landed in
# `custom` carrying nothing, so `ContentFilter.type` could not select it.
# `type` is now a mime prefix filter, and the enum is deleted.
#
# ── PAGINATION ON THE UNBOUNDED READS ──────────────────────────────────
#
# Five list returns had none (undo history, provenance, lineage,
# translations, dependencies), so a content item with 10k undo entries or
# a deep lineage graph copied all of them on every call. `undoHistory`
# also rode inline on `ContentItem`, so every search hit carried its
# entire edit history; it is now fetched on demand.
#
# Improvements (audit-8/9), unchanged:
#   - All IDs typed; ContentFilter uses T.Pagination.
#   - ContentItem.mimeData → T.DataHandle; expiresAt; trashed soft delete.
#   - publishMany, trash/restore/emptyTrash, ContentRef relationships.
#   - ContentItem.version as an optimistic-concurrency guard — now
#     actually honoured by `update`, which was previously decorative.
#   - ContentSubscription has cancel.
#   - AiProvenance, ContentEmbedding, ContentProvenance, ContentAccessibility,
#     ContentReaction, ContentGeoLocation, ContentLicense, ContentTag,
#     ContentUndoEntry, ContentTombstone, ContentEncryptedEnvelope.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using Search = import "system_search.capnp";

# ContentEmbedding.distanceMetric uses system_search's SimilarityMetric:
# content.capnp's own DistanceMetric was value-identical to it, so one
# home (system_search, which owns the query vocabulary) replaces two.

# ── Filter ───────────────────────────────────────────────────────────────
# `mimeTypePrefix` replaces the closed ContentType enum: a prefix match
# over T.MimeType selects what the enum used to, and a 2046 content kind
# is selectable the day a provider emits it.

struct ContentFilter {
    mimeTypePrefix @0 :Text;
    publisher @1 :T.AppId;
    createdAfter @2 :T.Timestamp;
    modifiedAfter @3 :T.Timestamp;
    # Pagination for unbounded result sets.
    page @4 :T.Pagination;
    query @5 :Text;
    # Only return items with these tags.
    tags @6 :List(Text);
    # Include trashed items in results.
    includeTrashed @7 :Bool;
    # Audit-8 additions:
    geoBounds @8 :GeoBounds;
    embeddingQuery @9 :ContentEmbedding;
    hasAiProvenance @10 :Bool;
    hasEmbedding @11 :Bool;
    licenseType @12 :Text;
    # Search strategy hint, as an open token (system_search's
    # vocabulary), so contacts.capnp and this file spell it one way.
    searchMode @13 :Text;
    parameters @14 :T.StringMap;
}

# ── Service ───────────────────────────────────────────────────────────────

interface ContentService {
    publish @0 (item :ContentItem) -> (contentId :T.ContentId);
    publishMany @1 (items :List(ContentItem)) -> (contentIds :List(T.ContentId));

    # Honours ContentItem.version: a mismatch returns the conflict arm
    # rather than silently overwriting. The field used to be decorative
    # — two writers could still clobber each other.
    update @2 (contentId :T.ContentId, item :ContentItem) -> (result :UpdateResult);

    unpublish @3 (contentId :T.ContentId) -> T.VoidResult;
    delete @4 (contentId :T.ContentId) -> T.VoidResult;

    trash @5 (contentId :T.ContentId) -> T.VoidResult;
    restore @6 (contentId :T.ContentId) -> T.VoidResult;
    emptyTrash @7 () -> T.VoidResult;

    # Paginated query — replaces unbounded List return.
    query @8 (filter :ContentFilter) -> (items :List(ContentItem), total :UInt64);

    get @9 (contentId :T.ContentId) -> (item :ContentItem);

    subscribe @10 (filter :ContentFilter) -> (subscription :ContentSubscription);

    # Add/remove relationships.
    addRelationship @11 (contentId :T.ContentId, ref :ContentRef) -> T.VoidResult;
    removeRelationship @12 (contentId :T.ContentId, targetId :T.ContentId) -> T.VoidResult;

    # Query all items related to a given item (paginated).
    getRelationships @13 (contentId :T.ContentId, page :T.Pagination) -> (refs :List(ContentRef), total :UInt32);

    # -- Semantic search --
    semanticSearch @14 (embedding :ContentEmbedding, page :T.Pagination)
        -> (items :List(ContentItem), total :UInt64);

    # -- Content graph --
    getContentGraph @15 (contentId :T.ContentId, depth :UInt32, page :T.Pagination)
        -> (refs :List(ContentRef), total :UInt32);

    # -- Reactions --
    reactToContent @16 (contentId :T.ContentId, reaction :ContentReaction) -> T.VoidResult;
    getReactions @17 (contentId :T.ContentId, page :T.Pagination)
        -> (reactions :List(ContentReaction), total :UInt32);

    # -- Provenance (paginated) --
    addProvenance @18 (contentId :T.ContentId, entry :ContentProvenance) -> T.VoidResult;
    getProvenance @19 (contentId :T.ContentId, page :T.Pagination)
        -> (provenance :List(ContentProvenance), total :UInt32);

    # -- GDPR erasure --
    eraseContent @20 (contentId :T.ContentId, reason :Text) -> T.VoidResult;

    # -- Undo history (paginated; no longer inline on ContentItem) --
    getUndoHistory @21 (contentId :T.ContentId, page :T.Pagination)
        -> (history :List(ContentUndoEntry), total :UInt32);
    undoContent @22 (contentId :T.ContentId, entryIndex :UInt32) -> T.VoidResult;

    # -- Encryption management --
    # Key lifecycle belongs to key_management.capnp (rotateKey @3); this
    # file records which key an envelope used and re-wraps the envelope.
    # `decryptContent` is read-through: it replaces `mimeData` with a
    # handle to the plaintext FOR THIS CALLER ONLY and leaves the stored
    # ciphertext untouched. A backend that cannot do that refuses with
    # T.Error(unsupported) rather than doing something else — the
    # previous T.VoidResult left the destination undeclared, so two
    # backends were wire-incompatible on the read path.
    encryptContent @23 (contentId :T.ContentId, keyId :T.KeyId) -> T.VoidResult;
    decryptContent @24 (contentId :T.ContentId) -> (item :ContentItem);
    rotateEncryptionKey @25 (contentId :T.ContentId, newKeyId :T.KeyId) -> T.VoidResult;

    # -- Geolocation --
    geotagContent @26 (contentId :T.ContentId, geo :ContentGeoLocation) -> T.VoidResult;
    getByGeoLocation @27 (geo :ContentGeoLocation, radiusMeters :Float32, page :T.Pagination)
        -> (items :List(ContentItem), total :UInt64);

    # -- AI tagging --
    aiTagContent @28 (contentId :T.ContentId) -> (tags :List(ContentTag));

    # -- Accessibility --
    getAccessibilityReport @29 (contentId :T.ContentId) -> (report :ContentAccessibility);

    # -- Batch publish --
    batchPublish @30 (items :List(ContentItem), provenance :ContentProvenance)
        -> (contentIds :List(T.ContentId));

    # -- Branch versioning --
    createBranch @31 (contentId :T.ContentId, name :Text) -> (branch :ContentBranch);
    listBranches @32 (contentId :T.ContentId) -> (branches :List(ContentBranch));
    mergeBranch @33 (contentId :T.ContentId, sourceBranch :Text, targetBranch :Text) -> T.VoidResult;

    # -- Content composition --
    createComposite @34 (composite :ContentComposite) -> (compositeId :T.ContentId);
    getComposite @35 (compositeId :T.ContentId) -> (composite :ContentComposite);
    updateComposite @36 (compositeId :T.ContentId, components :List(ContentRef)) -> T.VoidResult;

    # -- Content lineage (paginated) --
    addLineage @37 (contentId :T.ContentId, lineage :ContentLineage) -> T.VoidResult;
    getLineage @38 (contentId :T.ContentId, page :T.Pagination)
        -> (lineage :List(ContentLineage), total :UInt32);

    # -- Audit trail --
    getAuditTrail @39 (contentId :T.ContentId, page :T.Pagination) -> (entries :List(ContentAuditEntry), total :UInt32);

    # -- Rate limiting --
    setRateLimit @40 (config :RateLimitConfig) -> T.VoidResult;
    getRateLimit @41 (appId :T.AppId) -> (config :RateLimitConfig);

    # -- Preview generation --
    generatePreview @42 (contentId :T.ContentId, previewType :Text) -> (preview :ContentPreview);
    getPreview @43 (contentId :T.ContentId) -> (preview :ContentPreview);

    # -- Dependency tracking (paginated) --
    getDependencies @44 (contentId :T.ContentId, page :T.Pagination)
        -> (dependency :ContentDependency, total :UInt32);
    addDependency @45 (contentId :T.ContentId, dependsOnId :T.ContentId) -> T.VoidResult;
    removeDependency @46 (contentId :T.ContentId, dependsOnId :T.ContentId) -> T.VoidResult;

    # -- Expiration scheduling --
    scheduleExpiration @47 (schedule :ExpirationSchedule) -> T.VoidResult;
    cancelExpiration @48 (contentIds :List(T.ContentId)) -> T.VoidResult;

    # -- Replication status --
    getReplicationStatus @49 (contentId :T.ContentId) -> (status :ReplicationStatus);

    # -- Quality scoring (backend-declared; see the score struct) --
    getQualityScore @50 (contentId :T.ContentId) -> (score :QualityScore);

    # -- Recommendations --
    getRecommendations @51 (contentId :T.ContentId, page :T.Pagination)
        -> (recommendations :List(ContentRecommendation), total :UInt32);

    # -- Multi-language support --
    addTranslation @52 (contentId :T.ContentId, translation :ContentTranslation) -> T.VoidResult;
    getTranslations @53 (contentId :T.ContentId, page :T.Pagination)
        -> (translations :List(ContentTranslation), total :UInt32);
    getTranslatedContent @54 (contentId :T.ContentId, targetLanguage :T.Language) -> (item :ContentItem);
}

interface ContentSubscription {
    pull @0 () -> (events :List(ContentEvent));
    # Explicit cancellation — stops the event stream and releases resources.
    cancel @1 () -> T.VoidResult;
}

# Update is a conflict-or-success outcome, so the version guard is real
# rather than decorative.
struct UpdateResult {
    union {
        updated @0 :ContentItem;
        # The item as it currently stands, so a caller can rebase.
        conflict @1 :ContentItem;
        error @2 :T.Error;
        custom @3 :Data;
    }
}

struct ContentEvent {
    timestamp @0 :T.Timestamp;
    contentId @1 :T.ContentId;
    union {
        published @2 :ContentItem;
        updated @3 :ContentItem;
        removed @4 :T.ContentId;
        trashed @5 :T.ContentId;
        restored @6 :T.ContentId;
        encrypted @7 :T.KeyId;
        erased @8 :T.ContentId;
        custom @9 :Data;
    }
}

# ════════════════════════════════════════════════════════════════════════
# Audit-8 additions: AI provenance, vector embeddings, content
# provenance, accessibility, reactions, geolocation, licensing,
# undo history, tombstones (GDPR), encrypted envelopes, tags,
# search modes, geo-bounds, and content encryption management.
# ════════════════════════════════════════════════════════════════════════

# ── Content Item ──────────────────────────────────────────────────────────

struct ContentItem {
    id @0 :T.ContentId;
    # MIME prefix filter, replacing the closed 21-value ContentType
    # enum: a 2046 content kind is nameable, and the filter becomes what
    # it effectively already was.
    mimeType @1 :T.MimeType;
    title @2 :Text;
    summary @3 :Text;
    uri @4 :Text;
    size @5 :UInt64;
    createdAt @6 :T.Timestamp;
    modifiedAt @7 :T.Timestamp;
    publisher @8 :T.AppId;
    metadata @9 :T.StringMap;

    # Inline or buffered payload. Empty for items where uri is authoritative.
    mimeData @10 :T.DataHandle;
    # When to auto-delete this item (wall clock).
    expiresAt @11 :T.Timestamp;
    # Soft-delete flag: trashed items are hidden but restorable.
    trashed @12 :Bool;
    # Optimistic-concurrency version (increment on each update). HONOURED
    # by `update`, which returns the conflict arm on a mismatch.
    version @13 :UInt64;
    # Relationships to other content items.
    relationships @14 :List(ContentRef);
    # Visibility scope, as an open token.
    visibility @15 :Text;
    # Tags for organization (typed with provenance).
    tags @16 :List(ContentTag);
    # Audit-8 additions:
    aiProvenance @17 :AiProvenance;
    embedding @18 :ContentEmbedding;
    provenance @19 :ContentProvenance;
    accessibility @20 :ContentAccessibility;
    reactions @21 :List(ContentReaction);
    geoLocation @22 :ContentGeoLocation;
    license @23 :ContentLicense;
    # undoHistory is no longer inline here: a struct returned by `query`
    # was carrying its entire edit history on every hit. Fetch it with
    # getUndoHistory, which is paginated.
    tombstone @24 :ContentTombstone;
    encryptedEnvelope @25 :ContentEncryptedEnvelope;
}

struct ContentRef {
    targetId @0 :T.ContentId;
    # Role, as an open token (see the ref-role conformance consts).
    role @1 :Text;
    order @2 :UInt32;
}

# ── AI Provenance ──────────────────────────────────────────────────────

struct AiProvenance {
    modelId @0 :Text;
    modelVersion @1 :T.Version;
    promptHash @2 :Data;
    confidence @3 :Float32;
    generatedAt @4 :T.Timestamp;
    seed @5 :UInt64;
    metadata @6 :T.StringMap;
}

# ── Content Embedding ──────────────────────────────────────────────────
struct ContentEmbedding {
    vector @0 :T.DataHandle;
    dimensions @1 :UInt32;
    model @2 :Text;
    # One home for the metric vocabulary: system_search's SimilarityMetric.
    distanceMetric @3 :Search.SimilarityMetric;
    parameters @4 :T.StringMap;
}

# ── Content Provenance ─────────────────────────────────────────────────
struct ContentProvenance {
    createdAt @0 :T.Timestamp;
    createdBy @1 :T.AppId;
    modifiedBy @2 :List(T.AppId);
    importedFrom @3 :Text;
    # License, as an open token (e.g., "cc-by-4.0", "proprietary").
    license @4 :Text;
    sourceHash @5 :Data;
    metadata @6 :T.StringMap;
}

# ── Content Accessibility ──────────────────────────────────────────────
struct ContentAccessibility {
    altText @0 :Text;
    captions @1 :List(CaptionEntry);
    transcript @2 :Text;
    readingOrder @3 :UInt32;
    language @4 :T.Language;
    parameters @5 :T.StringMap;
}

struct CaptionEntry {
    text @0 :Text;
    startTime @1 :T.Duration;
    endTime @2 :T.Duration;
    language @3 :T.Language;
}

# ── Content Reaction ───────────────────────────────────────────────────
struct ContentReaction {
    appId @0 :T.AppId;
    # Reaction type, as an open token (see the reaction consts).
    type @1 :Text;
    emoji @2 :Text;
    timestamp @3 :T.Timestamp;
}

# ── Content Geo-Location ───────────────────────────────────────────────
struct ContentGeoLocation {
    latitude @0 :Float64;
    longitude @1 :Float64;
    altitude @2 :Float32;
    accuracy @3 :Float32;
    placeName @4 :Text;
}

struct GeoBounds {
    minLatitude @0 :Float64;
    maxLatitude @1 :Float64;
    minLongitude @2 :Float64;
    maxLongitude @3 :Float64;
}

# ── Content License ────────────────────────────────────────────────────
struct ContentLicense {
    # License, as an open token — closed by nothing: a 2046 licence, a
    # jurisdiction-specific public-sector licence and every CC variant
    # are all nameable.
    type @0 :Text;
    variant @1 :Text;
    url @2 :T.Uri;
    holder @3 :Text;
}

# ── Content Tag ────────────────────────────────────────────────────────
struct ContentTag {
    text @0 :Text;
    confidence @1 :Float32;
    # Source, as an open token (see the tag-source consts).
    source @2 :Text;
    tagId @3 :T.TagId;
}

# ── Content Undo Entry ─────────────────────────────────────────────────
struct ContentUndoEntry {
    timestamp @0 :T.Timestamp;
    # Action, as an open token (see the undo-action consts).
    action @1 :Text;
    field @2 :Text;
    oldValue @3 :Text;
    newValue @4 :Text;
    actor @5 :T.AppId;
}

# ── Content Tombstone ──────────────────────────────────────────────────
# `reason` and `legalBasis` are two views of ONE obligation, so they draw
# on one open vocabulary: a compliance tool can read both and a consumer
# never has to guess whether "deleted" meant a legal duty or a user action.
struct ContentTombstone {
    erasedAt @0 :T.Timestamp;
    reason @1 :Text;
    erasedBy @2 :T.AppId;
    legalBasis @3 :Text;
}

# ── Content Encrypted Envelope ─────────────────────────────────────────
struct ContentEncryptedEnvelope {
    ciphertext @0 :T.DataHandle;
    keyId @1 :T.KeyId;
    # Algorithm, as an open token shared with crypto.capnp.
    algorithm @2 :Text;
    iv @3 :Data;
    parameters @4 :T.StringMap;
}

# ── Content Branch ─────────────────────────────────────────────────────
struct ContentBranch {
    branchId @0 :Text;
    contentId @1 :T.ContentId;
    name @2 :Text;
    parentBranch @3 :Text;
    headVersion @4 :UInt64;
    dirty @5 :Bool;
    createdAt @6 :T.Timestamp;
    createdBy @7 :T.AppId;
}

# ── Content Composite ──────────────────────────────────────────────────
struct ContentComposite {
    compositeId @0 :T.ContentId;
    components @1 :List(ContentRef);
    template @2 :Text;
    autoUpdate @3 :Bool;
}

# ── Content Lineage ────────────────────────────────────────────────────
struct ContentLineage {
    contentId @0 :T.ContentId;
    sourceId @1 :T.ContentId;
    # Derivation type, as an open token (e.g., "translation", "remix").
    derivationType @2 :Text;
    derivedBy @3 :T.AppId;
    derivedAt @4 :T.Timestamp;
}

# ── Content Audit Entry ────────────────────────────────────────────────
struct ContentAuditEntry {
    contentId @0 :T.ContentId;
    # Action, as an open token.
    action @1 :Text;
    actor @2 :T.AppId;
    timestamp @3 :T.Timestamp;
    target @4 :Text;
    sourceAddress @5 :Text;
    success @6 :Bool;
}

# ── Rate Limit Configuration ───────────────────────────────────────────
struct RateLimitConfig {
    appId @0 :T.AppId;
    maxPublishPerMinute @1 :UInt32;
    maxUpdatePerMinute @2 :UInt32;
    maxBulkPerMinute @3 :UInt32;
    burstAllowance @4 :UInt32;
    parameters @5 :T.StringMap;
}

# ── Content Preview ────────────────────────────────────────────────────
struct ContentPreview {
    contentId @0 :T.ContentId;
    # Preview type, as an open token (e.g., "thumbnail", "summary").
    type @1 :Text;
    data @2 :T.DataHandle;
    mimeType @3 :T.MimeType;
    generatedAt @4 :T.Timestamp;
}

# ── Content Dependency ─────────────────────────────────────────────────
struct ContentDependency {
    contentId @0 :T.ContentId;
    dependsOn @1 :List(T.ContentId);
    dependedOnBy @2 :List(T.ContentId);
    cascadeChanges @3 :Bool;
}

# ── Expiration Schedule ────────────────────────────────────────────────
struct ExpirationSchedule {
    contentIds @0 :List(T.ContentId);
    expiresAt @1 :T.Timestamp;
    # Action, as an open token ("delete", "archive", "notify").
    action @2 :Text;
    notifyBefore @3 :T.Duration;
}

# ── Replication Status ─────────────────────────────────────────────────
struct ReplicationStatus {
    contentId @0 :T.ContentId;
    replicaCount @1 :UInt32;
    inSync @2 :Bool;
    lastReplicated @3 :T.Timestamp;
    regions @4 :List(Text);
}

# ── Quality Score ──────────────────────────────────────────────────────
# The components are DECLARED backend-specific: readability follows no
# published formula, so the score is only comparable within one backend.
# Previously the formulas existed only in comments and two backends
# scored incomparably with no way for a consumer to know.
struct QualityScore {
    contentId @0 :T.ContentId;
    overall @1 :Float32;
    readability @2 :Float32;
    completeness @3 :Float32;
    freshness @4 :Float32;
    scoredAt @5 :T.Timestamp;
    # Which formula produced the components, as an open token, so a
    # consumer can tell whether two scores are comparable.
    formula @6 :Text;
}

# ── Content Recommendation ─────────────────────────────────────────────
struct ContentRecommendation {
    contentId @0 :T.ContentId;
    score @1 :Float32;
    reason @2 :Text;
    source @3 :Text;
    recommendedAt @4 :T.Timestamp;
}

# ── Content Translation ────────────────────────────────────────────────
struct ContentTranslation {
    originalContentId @0 :T.ContentId;
    translatedContentId @1 :T.ContentId;
    sourceLanguage @2 :T.Language;
    targetLanguage @3 :T.Language;
    # Provider, as an open token. The previous examples ("ai-deepl",
    # "ai-google") were vendor names in a doc comment — a comment that
    # becomes an enum.
    provider @4 :Text;
    quality @5 :Float32;
    translatedAt @6 :T.Timestamp;
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Today's spellings for the open tokens above. Nothing requires them; an
# unrecognized token MUST be ignored rather than rejected.
# ══════════════════════════════════════════════════════════════════════

const refRoleReply      :Text = "reply";
const refRoleReference  :Text = "reference";
const refRoleParent     :Text = "parent";
const refRoleChild      :Text = "child";
const refRoleCited      :Text = "cited";
const refRoleRelated    :Text = "related";
const refRoleAttachment :Text = "attachment";
const refRolePreview    :Text = "preview";

const tagSourceUser   :Text = "user";
const tagSourceAi     :Text = "ai";
const tagSourceSystem :Text = "system";

const undoActionCreate  :Text = "create";
const undoActionModify  :Text = "modify";
const undoActionDelete  :Text = "delete";

const reactionLike     :Text = "like";
const reactionDislike  :Text = "dislike";
const reactionBookmark :Text = "bookmark";
const reactionFlag     :Text = "flag";

const visibilityPrivate :Text = "private";
const visibilityApp     :Text = "app";
const visibilityShared  :Text = "shared";
const visibilityPublic  :Text = "public";

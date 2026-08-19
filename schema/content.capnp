@0xa1b2c3d4e5f60055;

# ═══════════════════════════════════════════════════════════════════════
# Content — cross-app data sharing with relationships and versioning.
#
# Zero-backend-assumption IPC contract for content publication, querying,
# and lifecycle management. No filesystem, database, or transport assumptions.
#
# Improvements (audit):
#   - All IDs typed (T.ContentId, T.ContentSubscriptionId, T.AppId).
#   - ContentItem.mimeData → T.DataHandle for zero-copy large payloads.
#   - ContentItem.expiresAt for auto-expiry.
#   - ContentItem.trashed for soft delete (trash/restore vs hard delete).
#   - ContentItem.relationships for replies, references, threads.
#   - AccessPolicy/AccessRule for scoped, expiring, granular permissions.
#   - ContentFilter uses T.Pagination (no raw offset/limit).
#   - Bulk publishMany(items) for batch publishing.
#   - trash/restore/emptyTrash methods (soft delete workflow).
#   - ContentRef struct for typed relationships.
#   - ContentItem.version for optimistic-concurrency updates.
#   - ContentSubscription has cancel() for explicit teardown.
#   - All enums have custom/other variants for forward compatibility.
#   - ContentEvent union has custom variant for forward compatibility.
#   - ContentPermission.grantee typed as T.AppId (not bare Text).
#
# Audit-8 enhancements:
#   - AiProvenance: AI-generated content metadata (model, prompt, confidence).
#   - ContentEmbedding: vector embeddings for semantic search.
#   - ContentProvenance: chain of custody (creation, modification, import).
#   - ContentAccessibility: alt text, captions, transcripts.
#   - ContentReaction: typed reactions/votes on content.
#   - ContentGeoLocation: location-tagged content with spatial queries.
#   - ContentLicense: Creative Commons / proprietary / public domain.
#   - ContentTag: typed tags with provenance (user, AI, system).
#   - ContentUndoEntry: edit history for rollback.
#   - ContentTombstone: GDPR erasure with audit trail.
#   - ContentEncryptedEnvelope: E2E encrypted content wrapper.
#   - SearchMode: full-text, prefix, fuzzy, semantic search.
#   - Key rotation and access revocation for encrypted content.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ── Content Types ─────────────────────────────────────────────────────────

enum ContentType {
    unknown @0;
    image @1;
    video @2;
    audio @3;
    text @4;
    document @5;
    contact @6;
    calendar @7;
    bookmark @8;
    file @9;
    url @10;
    event @11;
    task @12;
    other @13;
    # Backend-specific content type.
    custom @14;
    # Audit-8 additions:
    embedding @15;
    model @16;
    dataset @17;
    code @18;
    archive @19;
    threeDmodel @20;
}

# ── Content Item ──────────────────────────────────────────────────────────

struct ContentItem {
    id @0 :T.ContentId;
    type @1 :ContentType;
    mimeType @2 :Text;
    title @3 :Text;
    summary @4 :Text;
    uri @5 :Text;
    size @6 :UInt64;
    createdAt @7 :T.Timestamp;
    modifiedAt @8 :T.Timestamp;
    publisher @9 :T.AppId;
    metadata @10 :T.StringMap;

    # Inline or buffered payload. Empty for items where uri is authoritative.
    mimeData @11 :T.DataHandle;
    # When to auto-delete this item (wall clock).
    expiresAt @12 :T.Timestamp;
    # Soft-delete flag: trashed items are hidden but restorable.
    trashed @13 :Bool;
    # Optimistic-concurrency version (increment on each update).
    version @14 :UInt64;
    # Relationships to other content items.
    relationships @15 :List(ContentRef);
    # Content visibility scope.
    visibility @16 :ContentVisibility;
    # Tags for organization (typed with provenance).
    tags @17 :List(ContentTag);
    # Audit-8 additions:
    aiProvenance @18 :AiProvenance;
    embedding @19 :ContentEmbedding;
    provenance @20 :ContentProvenance;
    accessibility @21 :ContentAccessibility;
    reactions @22 :List(ContentReaction);
    geoLocation @23 :ContentGeoLocation;
    license @24 :ContentLicense;
    undoHistory @25 :List(ContentUndoEntry);
    tombstone @26 :ContentTombstone;
    encryptedEnvelope @27 :ContentEncryptedEnvelope;
}

enum ContentVisibility {
    private @0;
    app @1;
    shared @2;
    public @3;
    other @4;
    # Backend-specific visibility scope.
    custom @5;
}

struct ContentRef {
    # ID of the related content item.
    targetId @0 :T.ContentId;
    # What role the target plays.
    role @1 :ContentRefRole;
    # Order within a collection (for sorting).
    order @2 :UInt32;
}

enum ContentRefRole {
    reply @0;
    reference @1;
    parent @2;
    child @3;
    cited @4;
    related @5;
    attachment @6;
    preview @7;
    other @8;
    # Backend-specific relationship role.
    custom @9;
}

# ── Filter ───────────────────────────────────────────────────────────────

struct ContentFilter {
    type @0 :ContentType;
    mimeTypePrefix @1 :Text;
    publisher @2 :T.AppId;
    createdAfter @3 :T.Timestamp;
    modifiedAfter @4 :T.Timestamp;
    # Pagination for unbounded result sets.
    page @5 :T.Pagination;
    query @6 :Text;
    # Only return items with these tags.
    tags @7 :List(Text);
    # Include trashed items in results.
    includeTrashed @8 :Bool;
    # Audit-8 additions:
    geoBounds @9 :GeoBounds;
    embeddingQuery @10 :ContentEmbedding;
    hasAiProvenance @11 :Bool;
    hasEmbedding @12 :Bool;
    licenseType @13 :Text;
    searchMode @14 :SearchMode;
}

# ── Access Control ────────────────────────────────────────────────────────

enum ContentPermission {
    read @0;
    write @1;
    share @2;
    delete @3;
    publish @4;
    comment @5;
    other @6;
    # Backend-specific permission type.
    custom @7;
}

struct AccessPolicy {
    rules @0 :List(AccessRule);
}

struct AccessRule {
    # Which permission this rule governs.
    permission @0 :ContentPermission;
    # Target app that receives this grant.
    grantee @1 :T.AppId;
    # Optional expiry for temporary grants.
    expiresAt @2 :T.Timestamp;
    # Whether this is an explicit grant or inherited.
    explicit @3 :Bool;
    # Optional scope description.
    scope @4 :Text;
}

# ── Service ───────────────────────────────────────────────────────────────

interface ContentService {
    publish @0 (item :ContentItem) -> (contentId :T.ContentId);
    publishMany @1 (items :List(ContentItem)) -> (contentIds :List(T.ContentId));

    update @2 (contentId :T.ContentId, item :ContentItem) -> T.VoidResult;

    unpublish @3 (contentId :T.ContentId) -> T.VoidResult;
    delete @4 (contentId :T.ContentId) -> T.VoidResult;

    trash @5 (contentId :T.ContentId) -> T.VoidResult;
    restore @6 (contentId :T.ContentId) -> T.VoidResult;
    emptyTrash @7 () -> T.VoidResult;

    # Paginated query — replaces unbounded List return.
    query @8 (filter :ContentFilter) -> (items :List(ContentItem), total :UInt64);

    get @9 (contentId :T.ContentId) -> (item :ContentItem);

    subscribe @10 (filter :ContentFilter) -> (subscription :ContentSubscription);

    grantAccess @11 (contentId :T.ContentId, policy :AccessPolicy) -> T.VoidResult;
    revokeAccess @12 (contentId :T.ContentId, grantee :T.AppId) -> T.VoidResult;
    checkAccess @13 (contentId :T.ContentId, permission :ContentPermission) -> (granted :Bool);
    getAccessPolicy @14 (contentId :T.ContentId) -> (policy :AccessPolicy);

    # Add/remove relationships.
    addRelationship @15 (contentId :T.ContentId, ref :ContentRef) -> T.VoidResult;
    removeRelationship @16 (contentId :T.ContentId, targetId :T.ContentId) -> T.VoidResult;

    # Query all items related to a given item (paginated).
    getRelationships @17 (contentId :T.ContentId, page :T.Pagination) -> (refs :List(ContentRef), total :UInt32);

    # -- Audit-8: Semantic search --
    semanticSearch @18 (embedding :ContentEmbedding, page :T.Pagination)
        -> (items :List(ContentItem), total :UInt64);

    # -- Audit-8: Content graph --
    getContentGraph @19 (contentId :T.ContentId, depth :UInt32, page :T.Pagination)
        -> (refs :List(ContentRef), total :UInt32);

    # -- Audit-8: Reactions --
    reactToContent @20 (contentId :T.ContentId, reaction :ContentReaction) -> T.VoidResult;
    getReactions @21 (contentId :T.ContentId, page :T.Pagination)
        -> (reactions :List(ContentReaction), total :UInt32);

    # -- Audit-8: Provenance --
    addProvenance @22 (contentId :T.ContentId, entry :ContentProvenance) -> T.VoidResult;
    getProvenance @23 (contentId :T.ContentId) -> (provenance :List(ContentProvenance));

    # -- Audit-8: GDPR erasure --
    eraseContent @24 (contentId :T.ContentId, reason :Text) -> T.VoidResult;

    # -- Audit-8: Undo history --
    getUndoHistory @25 (contentId :T.ContentId) -> (history :List(ContentUndoEntry));
    undoContent @26 (contentId :T.ContentId, entryIndex :UInt32) -> T.VoidResult;

    # -- Audit-8: Encryption management --
    encryptContent @27 (contentId :T.ContentId, keyId :T.KeyId) -> T.VoidResult;
    decryptContent @28 (contentId :T.ContentId) -> T.VoidResult;
    rotateEncryptionKey @29 (contentId :T.ContentId, newKeyId :T.KeyId) -> T.VoidResult;

    # -- Audit-8: Geolocation --
    geotagContent @30 (contentId :T.ContentId, geo :ContentGeoLocation) -> T.VoidResult;
    getByGeoLocation @31 (geo :ContentGeoLocation, radiusMeters :Float32, page :T.Pagination)
        -> (items :List(ContentItem), total :UInt64);

    # -- Audit-8: AI tagging --
    aiTagContent @32 (contentId :T.ContentId) -> (tags :List(ContentTag));

    # -- Audit-8: Accessibility --
    getAccessibilityReport @33 (contentId :T.ContentId) -> (report :ContentAccessibility);

    # -- Audit-8: Batch publish --
    batchPublish @34 (items :List(ContentItem), provenance :ContentProvenance)
        -> (contentIds :List(T.ContentId));

    # -- Audit-9: Branch versioning --
    createBranch @35 (contentId :T.ContentId, name :Text) -> (branch :ContentBranch);
    listBranches @36 (contentId :T.ContentId) -> (branches :List(ContentBranch));
    mergeBranch @37 (contentId :T.ContentId, sourceBranch :Text, targetBranch :Text) -> T.VoidResult;

    # -- Audit-9: Content composition --
    createComposite @38 (composite :ContentComposite) -> (compositeId :T.ContentId);
    getComposite @39 (compositeId :T.ContentId) -> (composite :ContentComposite);
    updateComposite @40 (compositeId :T.ContentId, components :List(ContentRef)) -> T.VoidResult;

    # -- Audit-9: Content lineage --
    addLineage @41 (contentId :T.ContentId, lineage :ContentLineage) -> T.VoidResult;
    getLineage @42 (contentId :T.ContentId) -> (lineage :List(ContentLineage));

    # -- Audit-9: Access delegation --
    delegateAccess @43 (contentId :T.ContentId, delegation :AccessDelegation) -> T.VoidResult;
    revokeDelegation @44 (contentId :T.ContentId, delegateId :T.AppId) -> T.VoidResult;
    getDelegationChain @45 (contentId :T.ContentId) -> (delegations :List(AccessDelegation));

    # -- Audit-9: Audit trail --
    getAuditTrail @46 (contentId :T.ContentId, page :T.Pagination) -> (entries :List(ContentAuditEntry), total :UInt32);

    # -- Audit-9: Rate limiting --
    setRateLimit @47 (config :RateLimitConfig) -> T.VoidResult;
    getRateLimit @48 (appId :T.AppId) -> (config :RateLimitConfig);

    # -- Audit-9: Preview generation --
    generatePreview @49 (contentId :T.ContentId, previewType :Text) -> (preview :ContentPreview);
    getPreview @50 (contentId :T.ContentId) -> (preview :ContentPreview);

    # -- Audit-9: Dependency tracking --
    getDependencies @51 (contentId :T.ContentId) -> (dependency :ContentDependency);
    addDependency @52 (contentId :T.ContentId, dependsOnId :T.ContentId) -> T.VoidResult;
    removeDependency @53 (contentId :T.ContentId, dependsOnId :T.ContentId) -> T.VoidResult;

    # -- Audit-9: Expiration scheduling --
    scheduleExpiration @54 (schedule :ExpirationSchedule) -> T.VoidResult;
    cancelExpiration @55 (contentIds :List(T.ContentId)) -> T.VoidResult;

    # -- Audit-9: Replication status --
    getReplicationStatus @56 (contentId :T.ContentId) -> (status :ReplicationStatus);

    # -- Audit-9: Quality scoring --
    getQualityScore @57 (contentId :T.ContentId) -> (score :QualityScore);

    # -- Audit-9: Recommendations --
    getRecommendations @58 (contentId :T.ContentId, page :T.Pagination)
        -> (recommendations :List(ContentRecommendation), total :UInt32);

    # -- Audit-9: Multi-language support --
    addTranslation @59 (contentId :T.ContentId, translation :ContentTranslation) -> T.VoidResult;
    getTranslations @60 (contentId :T.ContentId) -> (translations :List(ContentTranslation));
    getTranslatedContent @61 (contentId :T.ContentId, targetLanguage :Text) -> (item :ContentItem);
}

interface ContentSubscription {
    pull @0 () -> (events :List(ContentEvent));
    # Explicit cancellation — stops the event stream and releases resources.
    cancel @1 () -> T.VoidResult;
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
        accessChanged @7 :T.ContentId;
        # Backend-specific content event type.
        custom @8 :Data;
        # Audit-8 additions:
        reacted @9 :ContentReaction;
        encrypted @10 :T.KeyId;
        erased @11 :T.ContentId;
    }
}

# ════════════════════════════════════════════════════════════════════════
# Audit-8 additions: AI provenance, vector embeddings, content
# provenance, accessibility, reactions, geolocation, licensing,
# undo history, tombstones (GDPR), encrypted envelopes, tags,
# search modes, geo-bounds, and content encryption management.
# ════════════════════════════════════════════════════════════════════════

# ── AI Provenance ──────────────────────────────────────────────────────
# Structured metadata for AI-generated content. Records model,
# prompt, confidence, and generation timestamp for auditability.
struct AiProvenance {
    modelId @0 :Text;
    modelVersion @1 :T.Version;
    promptHash @2 :T.HashOutput;
    confidence @3 :Float32;
    generatedAt @4 :T.Timestamp;
    seed @5 :UInt64;
}

# ── Content Embedding ──────────────────────────────────────────────────
# Vector embedding for semantic similarity search. Enables finding
# content by meaning rather than keywords.
struct ContentEmbedding {
    vector @0 :T.DataHandle;
    dimensions @1 :UInt32;
    model @2 :Text;
    distanceMetric @3 :DistanceMetric;
}

enum DistanceMetric {
    cosine @0;
    euclidean @1;
    dotProduct @2;
    manhattan @3;
    custom @4;
}

# ── Content Provenance ─────────────────────────────────────────────────
# Chain of custody for content. Records creation, modification,
# import source, and licensing for compliance and audit.
struct ContentProvenance {
    createdAt @0 :T.Timestamp;
    createdBy @1 :T.AppId;
    modifiedBy @2 :List(T.AppId);
    importedFrom @3 :Text;
    license @4 :Text;
    sourceHash @5 :T.HashOutput;
}

# ── Content Accessibility ──────────────────────────────────────────────
# Accessibility metadata for content. Alt text, captions, transcripts,
# and reading order for compliance with accessibility standards.
struct ContentAccessibility {
    altText @0 :Text;
    captions @1 :List(CaptionEntry);
    transcript @2 :Text;
    readingOrder @3 :UInt32;
    language @4 :Text;
}

struct CaptionEntry {
    text @0 :Text;
    startTime @1 :T.Duration;
    endTime @2 :T.Duration;
    language @3 :Text;
}

# ── Content Reaction ───────────────────────────────────────────────────
# User reactions/votes on content. Typed reaction types with
# emoji support and provenance tracking.
struct ContentReaction {
    appId @0 :T.AppId;
    type @1 :ContentReactionType;
    emoji @2 :Text;
    timestamp @3 :T.Timestamp;
}

enum ContentReactionType {
    like @0;
    dislike @1;
    bookmark @2;
    flag @3;
    emoji @4;
    custom @5;
}

# ── Content Geo-Location ───────────────────────────────────────────────
# Location-tagged content with spatial query support. Enables
# finding content by geographic proximity.
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
# Licensing metadata for content. Creative Commons, proprietary,
# or public domain licensing with variant and holder info.
struct ContentLicense {
    type @0 :LicenseType;
    variant @1 :Text;
    url @2 :Text;
    holder @3 :Text;
}

enum LicenseType {
    creativeCommon @0;
    proprietary @1;
    publicDomain @2;
    custom @3;
}

# ── Content Tag ────────────────────────────────────────────────────────
# Typed tag with provenance. Replaces bare Text tags with structured
# tags that record source (user, AI, system) and confidence.
struct ContentTag {
    text @0 :Text;
    confidence @1 :Float32;
    source @2 :ContentTagSource;
    tagId @3 :T.TagId;
}

enum ContentTagSource {
    user @0;
    ai @1;
    system @2;
    custom @3;
}

# ── Content Undo Entry ─────────────────────────────────────────────────
# Edit history for content rollback. Records each change with
# actor, field, and before/after values.
struct ContentUndoEntry {
    timestamp @0 :T.Timestamp;
    action @1 :UndoAction;
    field @2 :Text;
    oldValue @3 :Text;
    newValue @4 :Text;
    actor @5 :T.AppId;
}

enum UndoAction {
    create @0;
    modify @1;
    delete @2;
    custom @3;
}

# ── Content Tombstone ──────────────────────────────────────────────────
# GDPR-compliant content erasure marker. Records when content was
# erased, by whom, and the legal basis for compliance auditing.
struct ContentTombstone {
    erasedAt @0 :T.Timestamp;
    reason @1 :Text;
    erasedBy @2 :T.AppId;
    legalBasis @3 :Text;
}

# ── Content Encrypted Envelope ─────────────────────────────────────────
# E2E encrypted content wrapper. Contains ciphertext handle, key
# reference, algorithm, and IV for encrypted content at rest.
struct ContentEncryptedEnvelope {
    ciphertext @0 :T.DataHandle;
    keyId @1 :T.KeyId;
    algorithm @2 :Text;
    iv @3 :Data;
}

# ── Search Mode ────────────────────────────────────────────────────────
# Optional search strategy for content queries. Backend may support
# full-text, prefix, fuzzy, or semantic search.
enum SearchMode {
    fullText @0;
    prefix @1;
    fuzzy @2;
    semantic @3;
    custom @4;
}

# ════════════════════════════════════════════════════════════════════════
# Audit-9 additions: content versioning with branching, composition,
# lineage tracking, access control delegation, audit trail, rate
# limiting, preview generation, dependency tracking, expiration
# scheduling, replication status, quality scoring, recommendations,
# and multi-language support.
# ════════════════════════════════════════════════════════════════════════

# ── Content Branch ─────────────────────────────────────────────────────
# Branch-based versioning for content. Enables forking, merging,
# and parallel editing workflows (like Git branches for content).
struct ContentBranch {
    branchId @0 :Text;
    contentId @1 :T.ContentId;
    # Branch name (e.g., "main", "draft", "review").
    name @2 :Text;
    # Parent branch this was forked from.
    parentBranch @3 :Text;
    # HEAD version in this branch.
    headVersion @4 :UInt64;
    # Whether this branch has unmerged changes.
    dirty @5 :Bool;
    createdAt @6 :T.Timestamp;
    createdBy @7 :T.AppId;
}

# ── Content Composite ──────────────────────────────────────────────────
# Combines multiple content items into a composite structure.
# Examples: newsletter = title + articles + images, magazine = TOC + articles.
struct ContentComposite {
    compositeId @0 :T.ContentId;
    # Ordered list of component content IDs.
    components @1 :List(ContentRef);
    # Layout template for composing components.
    template @2 :Text;
    # Whether the composite is auto-updated when components change.
    autoUpdate @3 :Bool;
}

# ── Content Lineage ────────────────────────────────────────────────────
# Tracks derivation lineage between content items. When content is
# derived from other content (remix, translation, adaptation),
# lineage records the provenance chain.
struct ContentLineage {
    contentId @0 :T.ContentId;
    # Source content this was derived from.
    sourceId @1 :T.ContentId;
    # Type of derivation (e.g., "translation", "remix", "adaptation").
    derivationType @2 :Text;
    # App that performed the derivation.
    derivedBy @3 :T.AppId;
    derivedAt @4 :T.Timestamp;
}

# ── Access Delegation ──────────────────────────────────────────────────
# Delegation chain for content access control. When a grantee
# delegates their access to another party, delegation records
# the chain of authority for compliance.
struct AccessDelegation {
    # The original granter of access.
    granterId @0 :T.AppId;
    # The party that received access and is delegating.
    delegateId @1 :T.AppId;
    # The party receiving delegated access.
    recipientId @2 :T.AppId;
    # Permissions being delegated.
    permissions @3 :List(ContentPermission);
    # When delegation expires.
    expiresAt @4 :T.Timestamp;
    # Maximum depth of delegation chain.
    maxDepth @5 :UInt32;
}

# ── Content Audit Entry ────────────────────────────────────────────────
# Audit trail entry for content access and modification. GDPR
# requires knowing who accessed content and when.
struct ContentAuditEntry {
    contentId @0 :T.ContentId;
    action @1 :Text;
    actor @2 :T.AppId;
    timestamp @3 :T.Timestamp;
    # What was accessed or changed.
    target @4 :Text;
    # IP address or device identifier (optional).
    sourceAddress @5 :Text;
    # Whether the action was successful.
    success @6 :Bool;
}

# ── Rate Limit Configuration ───────────────────────────────────────────
# Per-app rate limiting for content publish/update operations.
# Prevents runaway publishing from degrading system performance.
struct RateLimitConfig {
    appId @0 :T.AppId;
    # Maximum publishes per minute.
    maxPublishPerMinute @1 :UInt32;
    # Maximum updates per minute.
    maxUpdatePerMinute @2 :UInt32;
    # Maximum bulk operations per minute.
    maxBulkPerMinute @3 :UInt32;
    # Burst allowance (number of operations above limit before throttling).
    burstAllowance @4 :UInt32;
}

# ── Content Preview ────────────────────────────────────────────────────
# Generated preview for content items. Backends may generate
# thumbnails, summaries, or previews for content discovery.
struct ContentPreview {
    contentId @0 :T.ContentId;
    # Preview type (e.g., "thumbnail", "summary", "excerpt").
    type @1 :Text;
    # Preview data (image thumbnail, text summary, etc.).
    data @2 :T.DataHandle;
    # MIME type of the preview data.
    mimeType @3 :Text;
    generatedAt @4 :T.Timestamp;
}

# ── Content Dependency ─────────────────────────────────────────────────
# Tracks dependencies between content items. When content depends
# on other items (CSS depends on images, articles depend on media),
# dependency tracking enables cascading updates.
struct ContentDependency {
    contentId @0 :T.ContentId;
    # IDs of content items this content depends on.
    dependsOn @1 :List(T.ContentId);
    # IDs of content items that depend on this content.
    dependedOnBy @2 :List(T.ContentId);
    # Whether changes should cascade to dependents.
    cascadeChanges @3 :Bool;
}

# ── Expiration Schedule ────────────────────────────────────────────────
# Batch scheduling for content expiration. Enables setting
# expiration policies across multiple content items at once.
struct ExpirationSchedule {
    # Content IDs to schedule for expiration.
    contentIds @0 :List(T.ContentId);
    # When to expire the content.
    expiresAt @1 :T.Timestamp;
    # Action to take on expiration ("delete", "archive", "notify").
    action @2 :Text;
    # Notification recipients before expiration.
    notifyBefore @3 :T.Duration;
}

# ── Replication Status ─────────────────────────────────────────────────
# Tracks content replication state across distributed backends.
# Useful for multi-region content delivery.
struct ReplicationStatus {
    contentId @0 :T.ContentId;
    # Number of replicas across all backends.
    replicaCount @1 :UInt32;
    # Whether all replicas are in sync.
    inSync @2 :Bool;
    # Timestamp of last successful replication.
    lastReplicated @3 :T.Timestamp;
    # Backend regions where replicas exist.
    regions @4 :List(Text);
}

# ── Quality Score ──────────────────────────────────────────────────────
# Content quality scoring based on readability, completeness,
# and freshness metrics. Enables content curation workflows.
struct QualityScore {
    contentId @0 :T.ContentId;
    # Overall quality score (0.0–1.0).
    overall @1 :Float32;
    # Readability score (0.0–1.0, based on Flesch-Kincaid or similar).
    readability @2 :Float32;
    # Completeness score (0.0–1.0, based on required fields present).
    completeness @3 :Float32;
    # Freshness score (0.0–1.0, based on last modified vs current date).
    freshness @4 :Float32;
    scoredAt @5 :T.Timestamp;
}

# ── Content Recommendation ─────────────────────────────────────────────
# Personalized content recommendation with scoring and reasoning.
# Based on content graph analysis and user behavior.
struct ContentRecommendation {
    contentId @0 :T.ContentId;
    # Recommendation score (0.0–1.0, higher = more relevant).
    score @1 :Float32;
    # Reason for this recommendation (e.g., "similar to X", "trending").
    reason @2 :Text;
    # Source of the recommendation (e.g., "collaborative", "content-based").
    source @3 :Text;
    recommendedAt @4 :T.Timestamp;
}

# ── Content Translation ────────────────────────────────────────────────
# Multi-language support for content items. Tracks translations
# of content across languages with linkage to the original.
struct ContentTranslation {
    # Original content ID.
    originalContentId @0 :T.ContentId;
    # Translated content ID.
    translatedContentId @1 :T.ContentId;
    # Source language.
    sourceLanguage @2 :Text;
    # Target language.
    targetLanguage @3 :Text;
    # Translation provider (e.g., "human", "ai-deepl", "ai-google").
    provider @4 :Text;
    # Quality score of the translation (0.0–1.0).
    quality @5 :Float32;
    translatedAt @6 :T.Timestamp;
}

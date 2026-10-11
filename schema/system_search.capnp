@0xa1b2c3d4e5f60019;

using T = import "types.capnp";

# ══════════════════════════════════════════════════════════════════════
# SystemSearch — universal search across system providers.
#
# The runtime sibling is runtime_search.capnp: this file catalogs *what
# is stored*, that one catalogs *what is currently providing*. The split
# is kept — disjoint consumers, different truth conditions — and the
# shared primitives are flagged for promotion to types.capnp rather than
# duplicated (see the note at the bottom of this header).
#
# Improvements beyond the original schema:
#   - SearchProvider.icon uses T.DataHandle (was raw Data).
#   - SearchResult.icon/thumbnail use T.DataHandle.
#   - SearchAction.icon uses T.DataHandle.
#   - SearchAction.id uses T.ActionId (was raw Text).
#   - getProviders uses T.Pagination.
#   - search uses T.Pagination for result pagination.
#   - SearchProvider.version uses T.Version (was raw UInt32).
#   - ProvidersSubscription has cancel for clean teardown.
#   - SearchResultsStream has cancel for clean teardown.
#   - SearchResultType is an open token (was a closed enum).
#   - Audit-6: SearchResult.relevance range documented as 0.0-1.0 (normalized).
#   - Audit-6: SearchResult.iconMime / thumbnailMime declared via T.MimeType so
#     callers know whether to decode as PNG/SVG/JPEG without guessing.
#   - Audit-6: SearchQuery.modifiedAfter/modifiedBefore added for temporal
#     queries ("files modified in the last hour").
#
# Audit-7 improvements:
#   - VectorQuery for semantic similarity search.
#   - GraphQuery for relationship-based discovery.
#   - OntologyExpansion for synonym/abbreviation expansion.
#   - AgentContext for AI agent search with context.
#   - ResultCluster for grouped results by topic.
#   - SearchExplanation for transparent relevance.
#   - FederatedSearch for cross-provider ranked results.
#   - SearchCapabilities for capability discovery.
#
# ── TWO CONCRETE FIXES ─────────────────────────────────────────────────
#
# 1. RESULT IDENTITY WAS BROKEN BY TYPE. `SearchResult.resultId` was a
#    Text, while every method that consumes a result id
#    (`executeResult`, `getResultPreview`, `SearchHandler.execute`) took
#    a T.SearchProviderId — a PROVIDER id. You could not pass
#    resultId to any of them, so a caller could not act on a result at
#    all: there was no correct value to pass, and every implementer had
#    to invent a bridge between Text and UInt64. `explainResults` and
#    `deduplicateResults` used a third spelling (List(Text)). One typed
#    identifier is now used everywhere.
#
# 2. THE QUERY EMBEDDING STAYED INLINE. Icons and thumbnails were
#    migrated to T.DataHandle, but the file's hot payload — the vector a
#    semantic query sends — was still `Data`. A 1536-dimension float32
#    vector is 6 KB copied into every semantically-searched query, and
#    federated search multiplies it by the number of providers.
#
# 3. ONE PAGINATION MODEL. The query carried `limit`/`offset` AND the
#    method returned `T.Pagination`, with no precedence declared: a
#    backend honouring one and a backend honouring the other returned
#    different result sets for the same call. The query now carries
#    T.Pagination, and the federated/cross-device variants read it from
#    there instead of taking a competing parameter.
#
# 4. RESULT TYPE IS AN OPEN TOKEN. The previous 12-value enum froze
#    today's content taxonomy — and because it also drove the facet
#    counts, a provider indexing "message", "note", "reminder" or
#    "sensorReading" could not even be reported. The token is open, and
#    SearchFacet is keyed on the same token.
# ══════════════════════════════════════════════════════════════════════

interface SystemSearch {
    getProviders @0 (pagination :T.Pagination) -> (providers :List(SearchProvider), total :UInt64);
    subscribeProviders @1 () -> (subscription :ProvidersSubscription);
    pullProviders @2 (subscription :ProvidersSubscription) -> (providers :List(SearchProvider));
    cancelProviders @3 (subscription :ProvidersSubscription) -> T.VoidResult;

    search @4 (query :SearchQuery) -> (outcome :SearchOutcome);
    searchStream @5 (query :SearchQuery) -> (stream :SearchResultsStream);
    cancelSearchStream @6 (stream :SearchResultsStream) -> T.VoidResult;

    # `resultId` is the RESULT's identifier, not the provider's: see the
    # header. Previously this took T.SearchProviderId, so the value a
    # caller held could not be passed.
    executeResult @7 (resultId :SearchResultId, action :Text) -> T.VoidResult;
    registerProvider @8 (provider :SearchProvider, handler :SearchHandler) -> T.VoidResult;
    unregisterProvider @9 (providerId :T.SearchProviderId) -> T.VoidResult;

    # ── Federated search across all providers with unified ranking ──
    # Reads pagination from the query; the previous competing
    # `pagination` parameter left two models with no precedence.
    federatedSearch @10 (query :SearchQuery)
        -> (outcome :SearchOutcome, clusters :List(ResultCluster));

    # ── Get search explanations for results ──
    explainResults @11 (query :SearchQuery, resultIds :List(SearchResultId))
        -> (explanations :List(SearchExplanation));

    # ── Get supported search capabilities ──
    getSearchCapabilities @12 () -> (capabilities :SearchCapabilities);

    # ── Deduplicate results across providers ──
    deduplicateResults @13 (results :List(SearchResult))
        -> (deduplicated :List(SearchResult), duplicates :List(SearchResultId));

    # Audit-9: get search facets (counts by category).
    getFacets @14 (query :SearchQuery) -> (facets :List(SearchFacet));

    # Audit-9: save or retrieve saved search bookmarks.
    listBookmarks @15 (pagination :T.Pagination) -> (bookmarks :List(SearchBookmark));
    saveBookmark @16 (bookmark :SearchBookmark) -> T.VoidResult;
    deleteBookmark @17 (bookmarkId :T.SearchBookmarkId) -> T.VoidResult;

    # Audit-9: get search history.
    getSearchHistory @18 (pagination :T.Pagination) -> (history :List(SearchHistoryEntry));

    # Audit-9: get rich preview for a search result.
    getResultPreview @19 (resultId :SearchResultId) -> (preview :SearchResultPreview);

    # Audit-10: get autocomplete suggestions for a partial query.
    getAutocomplete @20 (partial :Text, maxSuggestions :UInt32)
                    -> (suggestions :List(SearchAutocomplete));

    # Audit-10: federated search across multiple devices.
    crossDeviceSearch @21 (query :SearchQuery, deviceIds :List(T.DeviceId))
                      -> (results :List(CrossDeviceSearchResult), total :UInt64);

    # Audit-10: get search analytics for a time range.
    getSearchAnalytics @22 (since :T.Timestamp) -> (analytics :SearchAnalytics);

    # Audit-10: get popular/trending search queries.
    getTrendingQueries @23 (pagination :T.Pagination)
                       -> (queries :List(TrendingQuery));
}

interface ProvidersSubscription {
    pull @0 () -> (providers :List(SearchProvider));
    cancel @1 () -> T.VoidResult;
}

interface SearchHandler {
    search @0 (query :SearchQuery) -> (results :List(SearchResult));
    execute @1 (resultId :SearchResultId, action :Text) -> T.VoidResult;
}

interface SearchResultsStream {
    pull @0 () -> (results :List(SearchResult), done :Bool);
    cancel @1 () -> T.VoidResult;
}

# ── Result identity ────────────────────────────────────────────────────
# One typed identifier for a search result, used by every method that
# consumes one. Declared locally because types.capnp is owned by the
# foundation batch and this promotion must be made there (see
# report.md); the local declaration is the minimum needed to make the
# file's core interaction type-correct.

struct SearchResultId { id @0 :UInt64; }

# A search that can fail. The previous bare `(results, pagination,
# total)` return had no way to report that a provider was unavailable or
# a query was malformed — every backend invented its own convention.
struct SearchOutcome {
    union {
        results @0 :List(SearchResult);
        error @1 :T.Error;
        # Opaque escape for a failure mode this schema does not name.
        custom @2 :Data;
    }
    pagination @3 :T.Pagination;
    total @4 :UInt64;
}

struct SearchProvider {
    id @0 :T.SearchProviderId;
    name @1 :Text;
    icon @2 :T.DataHandle;
    version @3 :T.Version;
    enabled @4 :Bool;
    priority @5 :UInt32;
    # Result types this provider can produce, as open tokens.
    resultTypes @6 :List(Text);
    iconMime @7 :T.MimeType;
    custom @8 :T.StringMap;
}

# Replaces the closed SearchResultType enum. A provider indexing a 2046
# content kind can now report it, and SearchFacet / SearchAutocomplete /
# ResultTypeCount all key on the same open token, so an unrecognised kind
# can still be counted.
const resultTypeApplication :Text = "application";
const resultTypeFile       :Text = "file";
const resultTypeMusic      :Text = "music";
const resultTypeVideo      :Text = "video";
const resultTypeImage      :Text = "image";
const resultTypeDocument   :Text = "document";
const resultTypeContact    :Text = "contact";
const resultTypeCalendar   :Text = "calendar";
const resultTypeWeb        :Text = "web";
const resultTypeSetting    :Text = "setting";
const resultTypeCommand    :Text = "command";

struct SearchQuery {
    # Field ordinals were re-issued when `limit`/`offset` were retired:
    # Cap'n Proto requires a gap-free sequence, and leaving @4 unused to
    # preserve the old numbering is not an option. The surface is
    # pre-release with no external consumers, so a clean sequence is
    # clearer than a preserved one with a hole in the middle.
    text @0 :Text;
    providers @1 :List(T.SearchProviderId);
    # Open tokens; see the conformance consts above.
    resultTypes @2 :List(Text);
    # The ONE pagination model: T.Pagination. This replaces the query's
    # own `limit`/`offset`, which competed with the method's T.Pagination
    # result with no precedence declared — a backend honouring one and a
    # backend honouring the other returned different result sets for the
    # same call.
    pagination @3 :T.Pagination;
    context @4 :T.StringMap;
    # Temporal window filters. Provider-honored when the indexed
    # resource has a modification timestamp. Zero means "unbounded".
    modifiedAfter @5 :T.Timestamp;
    modifiedBefore @6 :T.Timestamp;
    # Semantic similarity search (vector embedding).
    vector @7 :VectorQuery;
    # Relationship-based graph query.
    graph @8 :GraphQuery;
    # Synonym/abbreviation expansion.
    ontology @9 :OntologyExpansion;
    # AI agent search context.
    agentContext @10 :AgentContext;
    # Whether to group results by topic.
    clusterResults @11 :Bool;
    # Whether to include relevance explanations.
    explainResults @12 :Bool;
    # Query format hint, as an open token ("query-string", "keywords",
    # "natural-language", "regex"). Providers will otherwise interpret
    # the same text differently and a consumer cannot tell which to
    # trust for "find files edited by bob".
    textFormat @13 :Text;
    custom @14 :T.StringMap;
}

struct SearchResult {
    providerId @0 :T.SearchProviderId;
    # Open token; see the conformance consts above.
    type @1 :Text;
    title @2 :Text;
    description @3 :Text;
    icon @4 :T.DataHandle;
    url @5 :Text;
    thumbnail @6 :T.DataHandle;
    # Audit-6: relevance is normalized to [0.0, 1.0]. Higher = better match.
    # Providers MUST clamp to this range. A zero relevance does not imply
    # failure; consumers should fall back to insertion order.
    relevance @7 :Float32;
    actions @8 :List(SearchAction);
    metadata @9 :T.StringMap;
    # Audit-6: explicit MIME types so callers decode icons/thumbnails without
    # out-of-band knowledge. May be unset if provider cannot determine.
    iconMime @10 :T.MimeType;
    thumbnailMime @11 :T.MimeType;
    # Stable result identifier, and the value every method that acts on
    # a result takes.
    resultId @12 :SearchResultId;
    # Cluster this result belongs to (empty = no cluster).
    clusterId @13 :Text;
}

struct SearchAction {
    id @0 :T.ActionId;
    label @1 :Text;
    icon @2 :T.DataHandle;
}

# ── Vector Query (Semantic Search) ──────────────────────────────────────

struct VectorQuery {
    # A handle: the previous inline `Data` copied 6 KB per 1536-dimension
    # query, multiplied by the number of providers in a federated search.
    embedding @0 :T.DataHandle;
    dimensions @1 :UInt32;
    # Similarity metric. Kept as a closed enum because the set is closed
    # by arithmetic, not by a technology snapshot.
    similarity @2 :SimilarityMetric;
    topK @3 :UInt32;
    parameters @4 :T.StringMap;
}

enum SimilarityMetric {
    unspecified @0;   # Sentinel: an unset metric is not "cosine"
    cosine @1;
    euclidean @2;
    dotProduct @3;
    manhattan @4;
    custom @5;
}

# ── Graph Query (Relationship-Based) ───────────────────────────────────

struct GraphQuery {
    startNode @0 :Text;
    # Edge type to follow (e.g., "works_with", "related_to").
    relationship @1 :Text;
    direction @2 :GraphDirection;
    maxDepth @3 :UInt32;
    nodeTypes @4 :List(Text);
    parameters @5 :T.StringMap;
}

enum GraphDirection {
    unspecified @0;   # Sentinel: an unset direction is not "outgoing"
    outgoing @1;
    incoming @2;
    both @3;
    custom @4;
}

struct GraphResult {
    nodes @0 :List(GraphNode);
    edges @1 :List(GraphEdge);
}

struct GraphNode {
    id @0 :Text;
    type @1 :Text;
    properties @2 :T.StringMap;
}

struct GraphEdge {
    from @0 :Text;
    to @1 :Text;
    relationship @2 :Text;
    properties @3 :T.StringMap;
}

# ── Ontology Expansion (Synonym/Abbreviation) ──────────────────────────

struct OntologyExpansion {
    enabled @0 :Bool;
    ontologyId @1 :Text;
    expandSynonyms @2 :Bool;
    expandAbbreviations @3 :Bool;
    expandTranslations @4 :Bool;
    maxExpansion @5 :UInt32;
    parameters @6 :T.StringMap;
}

# ── Agent Context (AI Agent Search) ────────────────────────────────────

struct AgentContext {
    agentId @0 :Text;
    # What the agent is doing (task description).
    task @1 :Text;
    # Recent conversation history, as a handle: an agent's working
    # context is exactly the payload that grows without bound, and
    # passing it inline made every agent query copy the whole history
    # into the message.
    conversationHistory @2 :T.DataHandle;
    # Preferred output formats ("json", "markdown", "csv").
    preferredFormats @3 :List(Text);
    maxResults @4 :UInt32;
    freshnessBias @5 :Float32;
    parameters @6 :T.StringMap;
}

# ── Result Cluster (Grouped Results) ───────────────────────────────────

struct ResultCluster {
    clusterId @0 :Text;
    label @1 :Text;
    score @2 :Float32;
    results @3 :List(SearchResult);
    explanation @4 :Text;
}

# ── Search Explanation (Why Results Are Relevant) ──────────────────────

struct SearchExplanation {
    # The result this explains, by its typed identifier.
    resultId @0 :SearchResultId;
    score @1 :Float32;
    factors @2 :List(RelevanceFactor);
}

struct RelevanceFactor {
    # Feature name (e.g., "keyword_match", "freshness", "popularity").
    feature @0 :Text;
    # Contribution to score (weight).
    weight @1 :Float32;
    # Specific match detail.
    value @2 :Text;
}

# ── Search Capabilities ────────────────────────────────────────────────

struct SearchCapabilities {
    supportsVectorSearch @0 :Bool;
    supportsGraphSearch @1 :Bool;
    supportsEncryptedSearch @2 :Bool;
    supportsOntology @3 :Bool;
    supportsFederatedSearch @4 :Bool;
    supportedSimilarityMetrics @5 :List(SimilarityMetric);
    maxEmbeddingDimensions @6 :UInt32;
    # Result kinds this provider can produce, as open tokens, so an
    # unrecognised kind is still advertisable.
    supportedResultTypes @7 :List(Text);
    # Query text formats this provider understands.
    supportedTextFormats @8 :List(Text);
}

# ── Search Facets (counts by category) ─────────────────────────────

struct SearchFacet {
    # Open token, keyed on the same vocabulary as SearchResult.type, so
    # a kind the consumer does not recognise is still counted rather
    # than dropped.
    resultType @0 :Text;
    count @1 :UInt32;
    label @2 :Text;
}

# ── Search Bookmarks ────────────────────────────────────────────────

struct SearchBookmark {
    id @0 :T.SearchBookmarkId;
    query @1 :SearchQuery;
    name @2 :Text;
    createdAt @3 :T.Timestamp;
}

# ── Search History ──────────────────────────────────────────────────

struct SearchHistoryEntry {
    query @0 :Text;
    timestamp @1 :T.Timestamp;
    resultCount @2 :UInt32;
}

# ── Search Result Preview ──────────────────────────────────────────

struct SearchResultPreview {
    resultId @0 :SearchResultId;
    snippet @1 :Text;
    thumbnail @2 :T.DataHandle;
    thumbnailMime @3 :T.MimeType;
    metadata @4 :T.StringMap;
}

# ── Audit-10: Search Autocomplete ────────────────────────────────────

struct SearchAutocomplete {
    text @0 :Text;
    # Open token; see the conformance consts above.
    resultType @1 :Text;
    providerId @2 :T.SearchProviderId;
    confidence @3 :Float32;
}

# ── Audit-10: Cross-Device Search ────────────────────────────────────

struct CrossDeviceSearchResult {
    result @0 :SearchResult;
    # Typed device identity, so cross-device provenance is correlatable
    # instead of string-matched across two backends' namespaces.
    deviceId @1 :T.DeviceId;
    deviceName @2 :Text;
}

# ── Audit-10: Search Analytics ───────────────────────────────────────

struct SearchAnalytics {
    totalSearches @0 :UInt64;
    avgResultsPerSearch @1 :Float32;
    clickThroughRate @2 :Float32;
    abandonmentRate @3 :Float32;
    topQueries @4 :List(QueryCount);
    # Open token, not the retired result-type enum.
    byResultType @5 :List(ResultTypeCount);
}

struct QueryCount {
    query @0 :Text;
    count @1 :UInt64;
}

struct ResultTypeCount {
    resultType @0 :Text;
    count @1 :UInt64;
}

# ── Audit-10: Trending Queries ───────────────────────────────────────

struct TrendingQuery {
    query @0 :Text;
    count @1 :UInt64;
    trend @2 :TrendDirection;
}

enum TrendDirection {
    rising @0;
    stable @1;
    declining @2;
    custom @3;
}

# ══════════════════════════════════════════════════════════════════════
# SHARED SEARCH PRIMITIVES — CROSS-BATCH ITEM (see report.md)
#
# The query envelope (SearchQuery), the result envelope (SearchResult)
# and the subscription shape are declared here, in system_search.capnp,
# in contacts.capnp (SearchMode), in content.capnp (SearchMode,
# DistanceMetric) and in files.capnp (SearchQuery). Same names,
# divergent shapes, one protocol.
#
# The canonical home for these is types.capnp, which the foundation
# batch owns. This file does not attempt the promotion: it records the
# exact types to move and the collisions to resolve, so the promotion is
# a mechanical integration step rather than a second rewrite.
# ══════════════════════════════════════════════════════════════════════

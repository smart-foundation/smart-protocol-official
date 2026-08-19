@0xa1b2c3d4e5f60019;

using T = import "types.capnp";

# ══════════════════════════════════════════════════════════════════════
# SystemSearch — universal search across system providers.
#
# Improvements beyond the original schema:
#   - SearchProvider.icon uses T.DataHandle (was raw Data).
#   - SearchResult.icon/thumbnail use T.DataHandle.
#   - SearchAction.icon uses T.DataHandle.
#   - SearchAction.id uses T.EventId (was raw Text).
#   - getProviders uses T.Pagination.
#   - search uses T.Pagination for result pagination.
#   - SearchProvider.version uses T.Version (was raw UInt32).
#   - ProvidersSubscription has cancel for clean teardown.
#   - SearchResultsStream has cancel for clean teardown.
#   - SearchResultType enum has custom variant.
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
# ══════════════════════════════════════════════════════════════════════

interface SystemSearch {
    getProviders @0 (pagination :T.Pagination) -> (providers :List(SearchProvider), total :UInt64);
    subscribeProviders @1 () -> (subscription :ProvidersSubscription);
    pullProviders @2 (subscription :ProvidersSubscription) -> (providers :List(SearchProvider));
    cancelProviders @3 (subscription :ProvidersSubscription) -> T.VoidResult;

    search @4 (query :SearchQuery) -> (results :List(SearchResult), pagination :T.Pagination, total :UInt64);
    searchStream @5 (query :SearchQuery) -> (stream :SearchResultsStream);
    cancelSearchStream @6 (stream :SearchResultsStream) -> T.VoidResult;

    executeResult @7 (resultId :T.SearchProviderId, action :Text) -> T.VoidResult;
    registerProvider @8 (provider :SearchProvider, handler :SearchHandler) -> T.VoidResult;
    unregisterProvider @9 (providerId :T.SearchProviderId) -> T.VoidResult;

    # ── Federated search across all providers with unified ranking ──
    federatedSearch @10 (query :SearchQuery, pagination :T.Pagination)
        -> (results :List(SearchResult), clusters :List(ResultCluster), total :UInt64);

    # ── Get search explanations for results ──
    explainResults @11 (query :SearchQuery, resultIds :List(Text))
        -> (explanations :List(SearchExplanation));

    # ── Get supported search capabilities ──
    getSearchCapabilities @12 () -> (capabilities :SearchCapabilities);

    # ── Deduplicate results across providers ──
    deduplicateResults @13 (results :List(SearchResult))
        -> (deduplicated :List(SearchResult), duplicates :List(Text));

    # Audit-9: get search facets (counts by category).
    getFacets @14 (query :SearchQuery) -> (facets :List(SearchFacet));

    # Audit-9: save or retrieve saved search bookmarks.
    listBookmarks @15 (pagination :T.Pagination) -> (bookmarks :List(SearchBookmark));
    saveBookmark @16 (bookmark :SearchBookmark) -> T.VoidResult;
    deleteBookmark @17 (bookmarkId :T.SearchBookmarkId) -> T.VoidResult;

    # Audit-9: get search history.
    getSearchHistory @18 (pagination :T.Pagination) -> (history :List(SearchHistoryEntry));

    # Audit-9: get rich preview for a search result.
    getResultPreview @19 (resultId :T.SearchProviderId) -> (preview :SearchResultPreview);

    # Audit-10: get autocomplete suggestions for a partial query.
    getAutocomplete @20 (partial :Text, maxSuggestions :UInt32)
                    -> (suggestions :List(SearchAutocomplete));

    # Audit-10: federated search across multiple devices.
    crossDeviceSearch @21 (query :SearchQuery, deviceIds :List(Text), pagination :T.Pagination)
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
    execute @1 (resultId :T.SearchProviderId, action :Text) -> T.VoidResult;
}

interface SearchResultsStream {
    pull @0 () -> (results :List(SearchResult), done :Bool);
    cancel @1 () -> T.VoidResult;
}

struct SearchProvider {
    id @0 :T.SearchProviderId;
    name @1 :Text;
    icon @2 :T.DataHandle;
    version @3 :T.Version;
    enabled @4 :Bool;
    priority @5 :UInt32;
    resultTypes @6 :List(SearchResultType);
    # Audit-6: declared MIME for provider icon (PNG/SVG/JPEG).
    iconMime @7 :T.MimeType;
}

enum SearchResultType {
    application @0;
    file @1;
    music @2;
    video @3;
    image @4;
    document @5;
    contact @6;
    calendar @7;
    web @8;
    setting @9;
    command @10;
    custom @11;
}

struct SearchQuery {
    text @0 :Text;
    providers @1 :List(T.SearchProviderId);
    resultTypes @2 :List(SearchResultType);
    limit @3 :UInt32;
    offset @4 :UInt32;
    context @5 :T.StringMap;
    # Audit-6: temporal window filters. Provider-honored when the indexed
    # resource has a modification timestamp. Zero means "unbounded".
    modifiedAfter @6 :T.Timestamp;
    modifiedBefore @7 :T.Timestamp;
    # Semantic similarity search (vector embedding).
    vector @8 :VectorQuery;
    # Relationship-based graph query.
    graph @9 :GraphQuery;
    # Synonym/abbreviation expansion.
    ontology @10 :OntologyExpansion;
    # AI agent search context.
    agentContext @11 :AgentContext;
    # Whether to group results by topic.
    clusterResults @12 :Bool;
    # Whether to include relevance explanations.
    explainResults @13 :Bool;
}

struct SearchResult {
    providerId @0 :T.SearchProviderId;
    type @1 :SearchResultType;
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
    # Stable result identifier for referencing specific results.
    resultId @12 :Text;
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
    # Vector embedding (float32 array serialized as bytes).
    embedding @0 :Data;
    # Embedding dimensions.
    dimensions @1 :UInt32;
    # Similarity metric.
    similarity @2 :SimilarityMetric;
    # Maximum results to return.
    topK @3 :UInt32;
}

enum SimilarityMetric {
    cosine @0;
    euclidean @1;
    dotProduct @2;
    manhattan @3;
    custom @4;
}

# ── Graph Query (Relationship-Based) ───────────────────────────────────

struct GraphQuery {
    # Starting node identifier.
    startNode @0 :Text;
    # Edge type to follow (e.g., "works_with", "related_to").
    relationship @1 :Text;
    # Traversal direction.
    direction @2 :GraphDirection;
    # Maximum traversal depth.
    maxDepth @3 :UInt32;
    # Filter by node types.
    nodeTypes @4 :List(Text);
}

enum GraphDirection {
    outgoing @0;
    incoming @1;
    both @2;
    custom @3;
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
    # Whether expansion is enabled.
    enabled @0 :Bool;
    # Which ontology to use.
    ontologyId @1 :Text;
    # Whether to expand synonyms.
    expandSynonyms @2 :Bool;
    # Whether to expand abbreviations.
    expandAbbreviations @3 :Bool;
    # Whether to expand translations.
    expandTranslations @4 :Bool;
    # Maximum number of expanded terms.
    maxExpansion @5 :UInt32;
}

# ── Agent Context (AI Agent Search) ────────────────────────────────────

struct AgentContext {
    # Agent identifier.
    agentId @0 :Text;
    # What the agent is doing (task description).
    task @1 :Text;
    # Recent conversation history.
    conversationHistory @2 :List(Text);
    # Preferred output formats ("json", "markdown", "csv").
    preferredFormats @3 :List(Text);
    # Maximum results to return.
    maxResults @4 :UInt32;
    # Freshness bias (0.0 = no bias, 1.0 = prefer recent).
    freshnessBias @5 :Float32;
}

# ── Result Cluster (Grouped Results) ───────────────────────────────────

struct ResultCluster {
    # Cluster identifier.
    clusterId @0 :Text;
    # Cluster topic label.
    label @1 :Text;
    # Cluster relevance score.
    score @2 :Float32;
    # Results in this cluster.
    results @3 :List(SearchResult);
    # Why these results are grouped.
    explanation @4 :Text;
}

# ── Search Explanation (Why Results Are Relevant) ──────────────────────

struct SearchExplanation {
    # Result identifier.
    resultId @0 :Text;
    # Overall relevance score.
    score @1 :Float32;
    # Individual relevance factors.
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
    # Whether vector search is supported.
    supportsVectorSearch @0 :Bool;
    # Whether graph search is supported.
    supportsGraphSearch @1 :Bool;
    # Whether encrypted search is supported.
    supportsEncryptedSearch @2 :Bool;
    # Whether ontology expansion is supported.
    supportsOntology @3 :Bool;
    # Whether federated search is supported.
    supportsFederatedSearch @4 :Bool;
    # Supported similarity metrics.
    supportedSimilarityMetrics @5 :List(SimilarityMetric);
    # Maximum embedding dimensions supported.
    maxEmbeddingDimensions @6 :UInt32;
}

# ── Search Facets (counts by category) ─────────────────────────────

struct SearchFacet {
    resultType @0 :SearchResultType;
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
    resultId @0 :Text;
    snippet @1 :Text;
    thumbnail @2 :T.DataHandle;
    thumbnailMime @3 :T.MimeType;
    metadata @4 :T.StringMap;
}

# ── Audit-10: Search Autocomplete ────────────────────────────────────

struct SearchAutocomplete {
    # Suggested completion text.
    text @0 :Text;
    # Result type if this suggestion resolves to a known entity.
    resultType @1 :SearchResultType;
    # Associated provider (null if generic suggestion).
    providerId @2 :T.SearchProviderId;
    # Confidence score (0.0-1.0).
    confidence @3 :Float32;
}

# ── Audit-10: Cross-Device Search ────────────────────────────────────

struct CrossDeviceSearchResult {
    # The search result.
    result @0 :SearchResult;
    # Which device this result came from.
    deviceId @1 :Text;
    # Device-friendly name (e.g., "Living Room Hub").
    deviceName @2 :Text;
}

# ── Audit-10: Search Analytics ───────────────────────────────────────

struct SearchAnalytics {
    # Total searches performed.
    totalSearches @0 :UInt64;
    # Average results per search.
    avgResultsPerSearch @1 :Float32;
    # Click-through rate (0.0-1.0).
    clickThroughRate @2 :Float32;
    # Abandonment rate (search with no result clicked, 0.0-1.0).
    abandonmentRate @3 :Float32;
    # Top search queries by frequency.
    topQueries @4 :List(QueryCount);
    # Searches by result type breakdown.
    byResultType @5 :List(ResultTypeCount);
}

struct QueryCount {
    query @0 :Text;
    count @1 :UInt64;
}

struct ResultTypeCount {
    resultType @0 :SearchResultType;
    count @1 :UInt64;
}

# ── Audit-10: Trending Queries ───────────────────────────────────────

struct TrendingQuery {
    query @0 :Text;
    # How many times this query was searched recently.
    count @1 :UInt64;
    # Trend direction (rising, stable, declining).
    trend @2 :TrendDirection;
}

enum TrendDirection {
    rising @0;
    stable @1;
    declining @2;
    custom @3;
}

@0xa1b2c3d4e5f6001a;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# AppIndex - application discovery, search, launch, and tracking
#
# The app index is the catalog of all known applications. It supports
# discovery (list, search), launch (with typed args), pinned/recent
# tracking, and installation state. This schema owns metadata queries;
# lifecycle management lives in app.capnp.
#
# All IDs are typed. All lists are paginated. All mutations return
# T.VoidResult. Icons carry MIME type. Categories are typed enums.
#
# Audit-7 enhancements (zero-cost, info-density):
#   - LaunchArgs: typed launch arguments replacing bare List(Text)
#   - AppIndexSubscription filter: only these app IDs/state changes
#   - AppPermissions: permission listing in index
#   - AppSearchFilter: enriched search with category/source/version range
#   - AppIndexStats: aggregate statistics for the index
#   - LaunchResult enriched with instanceId
# ═══════════════════════════════════════════════════════════════════════

interface AppIndexService {
    # List all apps matching a filter, paginated.
    listApps @0 (filter :AppFilter, pagination :T.Pagination)
             -> (apps :List(AppInfo), totalCount :UInt32);

    # Get a single app by ID.
    getApp @1 (appId :T.AppId) -> (app :AppInfo);

    # Launch an app with optional arguments.
    launch @2 (appId :T.AppId, args :LaunchArgs) -> (result :LaunchResult);

    # Launch a URL via the appropriate app.
    launchUrl @3 (url :T.Uri) -> (result :LaunchResult);

    # Get pinned apps.
    getPinned @4 (pagination :T.Pagination) -> (apps :List(AppInfo), totalCount :UInt32);

    # Pin an app.
    pinApp @5 (appId :T.AppId) -> T.VoidResult;

    # Unpin an app.
    unpinApp @6 (appId :T.AppId) -> T.VoidResult;

    # Search apps by query, with relevance ranking.
    searchApps @7 (query :Text, filter :AppSearchFilter, pagination :T.Pagination)
               -> (results :List(AppSearchResult), totalCount :UInt32);

    # Get recent apps (ordered by last-used, most recent first).
    getRecentApps @8 (pagination :T.Pagination) -> (apps :List(AppInfo), totalCount :UInt32);

    # Clear recent apps history.
    clearRecentApps @9 () -> T.VoidResult;

    # Subscribe to app index changes (installed, updated, uninstalled).
    subscribe @10 (filter :AppIndexSubscriptionFilter) -> (subscription :AppIndexSubscription);
    pull @11 (subscription :AppIndexSubscription) -> (events :List(AppIndexEvent));
    cancel @12 (subscription :AppIndexSubscription) -> T.VoidResult;

    # Audit-7: get aggregate statistics for the index.
    getStats @13 () -> (stats :AppIndexStats);

    # Audit-7: list permissions for an app from the index.
    listPermissions @14 (appId :T.AppId, pagination :T.Pagination)
                    -> (permissions :List(AppIndexPermission), totalCount :UInt32);

    # Audit-7: get apps that depend on a given app/package.
    getDependents @15 (packageId :T.PackageId, pagination :T.Pagination)
                  -> (apps :List(AppInfo), totalCount :UInt32);

    # Audit-7: batch get multiple apps by ID.
    batchGet @16 (appIds :List(T.AppId)) -> (apps :List(AppInfo));

    # Audit-8: get app recommendations (false positive: app_recommendation.capnp belongs here).
    getRecommendations @17 (appId :T.AppId, pagination :T.Pagination)
                       -> (apps :List(AppInfo), totalCount :UInt32);

    # Audit-8: submit an app rating.
    submitRating @18 (appId :T.AppId, rating :Float32, review :Text) -> T.VoidResult;

    # Audit-8: compare two versions (is v2.0 > v1.9?).
    compareVersions @19 (versionA :T.Version, versionB :T.Version) -> (result :VersionComparison);

    # Audit-9: get recommendation explanation (why an app was recommended).
    getRecommendationReason @20 (appId :T.AppId, recommendedAppId :T.AppId) -> (reason :RecommendationReason);

    # Audit-10: set search ranking weights for custom relevance tuning.
    setSearchRankingWeights @21 (weights :SearchRankingWeights) -> T.VoidResult;

    # Audit-10: get current search ranking weights.
    getSearchRankingWeights @22 () -> (weights :SearchRankingWeights);

    # Audit-10: moderate a submitted rating (approve, reject, flag).
    moderateRating @23 (ratingId :Text, decision :RatingModerationDecision, reason :Text) -> T.VoidResult;

    # Audit-10: list ratings pending moderation.
    listPendingRatings @24 (pagination :T.Pagination) -> (ratings :List(AppRating), totalCount :UInt32);
}

# Audit-9: explanation for why an app was recommended.
struct RecommendationReason {
    # The app being recommended.
    appId @0 :T.AppId;
    # Reason category.
    category @1 :RecommendationCategory;
    # Human-readable explanation.
    explanation @2 :Text;
    # Related app or feature that triggered this recommendation.
    trigger @3 :Text;
}

enum RecommendationCategory {
    similarUsage @0;         # Used by people who use a similar app
    installedTogether @1;   # Often installed alongside another app
    popular @2;             # Popular in user's region or demographic
    trending @3;            # Trending or new app
    categoryMatch @4;       # Matches user's category preferences
    similarFunctionality @5; # Similar function to an app the user uses
    developerReputation @6; # From a trusted developer
    editorial @7;            # Editor's choice or staff pick
    custom @8;
}

# ── Launch Args (typed) ──────────────────────────────────────────────
# Audit-7 addition: typed launch arguments replacing bare List(Text).
# Enables structured arguments (files, URIs, key-value pairs) without
# requiring apps to parse text.
struct LaunchArgs {
    union {
        # Simple text arguments (most common).
        textArgs @0 :List(Text);
        # File arguments (typed, not raw paths).
        fileArgs @1 :List(FileRef);
        # URI arguments.
        uriArgs @2 :List(T.Uri);
        # Key-value arguments (for structured invocations).
        kvArgs @3 :List(LaunchArg);
        custom @4 :Data;
    }
}

struct LaunchArg {
    key @0 :Text;
    value @1 :LaunchArgValue;
}

struct LaunchArgValue {
    union {
        text @0 :Text;
        integer @1 :Int64;
        boolean @2 :Bool;
        file @3 :FileRef;
        uri @4 :T.Uri;
        custom @5 :Data;
    }
}

struct FileRef {
    union {
        path @0 :Text;
        uri @1 :Text;
        fileId @2 :T.FileId;
        custom @3 :Data;
    }
}

# ── Launch Result ─────────────────────────────────────────────────────

struct LaunchResult {
    union {
        success @0 :LaunchSuccess;
        error @1 :T.Error;
    }
}

struct LaunchSuccess {
    appId @0 :T.AppId;
    pid @1 :T.ProcessId;
    timestamp @2 :T.Timestamp;
    # Audit-7: instance ID for multi-instance apps.
    instanceId @3 :UInt32;
}

# ── Search Result ─────────────────────────────────────────────────────

struct AppSearchResult {
    app @0 :AppInfo;
    relevance @1 :Float32;
    matchField @2 :Text;
    # Audit-7: match highlights (character ranges in the name/description).
    highlights @3 :List(TextRange);
}

# Audit-7 addition: character range for search highlight display.
struct TextRange {
    start @0 :UInt32;
    end @1 :UInt32;
}

# ── App Search Filter ─────────────────────────────────────────────────
# Audit-7 addition: enriched search with category, source, version range.
# Replaces bare query text with structured filter.
struct AppSearchFilter {
    # Restrict to these categories.
    categories @0 :List(AppCategory);
    # Restrict to these sources.
    sources @1 :List(AppSource);
    # Minimum version requirement.
    minVersion @2 :T.Version;
    # Maximum version ceiling.
    maxVersion @3 :T.Version;
    # Only installed apps.
    installed @4 :T.BoolFilter;
    # Only apps matching these names (substring match).
    nameContains @5 :Text;
}

# ── Filter ────────────────────────────────────────────────────────────

struct AppFilter {
    name @0 :Text;
    category @1 :AppCategory;
    installed @2 :T.BoolFilter;
    source @3 :AppSource;
    # Audit-7 additions:
    # Restrict to specific app IDs.
    appIds @4 :List(T.AppId);
    # Minimum version.
    minVersion @5 :T.Version;
    # Maximum version.
    maxVersion @6 :T.Version;
    # Only apps in a specific state.
    state @7 :AppState;
}

# ── App Info ──────────────────────────────────────────────────────────

struct AppInfo {
    id @0 :T.AppId;
    packageId @1 :T.PackageId;
    name @2 :Text;
    description @3 :Text;
    version @4 :T.Version;
    icon @5 :AppIcon;
    categories @6 :List(AppCategory);
    source @7 :AppSource;
    state @8 :AppState;
    pinned @9 :Bool;
    developer @10 :Text;
    license @11 :Text;
    sizeBytes @12 :UInt64;
    installDate @13 :T.Timestamp;
    lastUsed @14 :T.Timestamp;
    minVersion @15 :T.Version;
    # Audit-7 additions:
    # Launch mode (single-instance, multi-instance, single-task).
    launchMode @16 :AppLaunchMode;
    # Whether the app supports messaging.
    supportsMessaging @17 :Bool;
    # Number of required permissions.
    permissionCount @18 :UInt32;
    # Rating (0.0 - 5.0).
    rating @19 :Float32;
    # Number of downloads/installs.
    installCount @20 :UInt64;
}

struct AppIcon {
    data @0 :Data;
    mimeType @1 :Text;
    width @2 :UInt32;
    height @3 :UInt32;
}

enum AppState {
    notInstalled @0;
    installing @1;
    installed @2;
    launching @3;
    running @4;
    suspended @5;
    stopping @6;
    stopped @7;
    errored @8;
    updating @9;
    custom @10;
}

# Audit-7: launch mode for multi-instance behavior.
enum AppLaunchMode {
    singleInstance @0;
    multiInstance @1;
    singleTask @2;
    singleTop @3;
    custom @4;
}

enum AppCategory {
    system @0;
    productivity @1;
    games @2;
    media @3;
    development @4;
    utilities @5;
    accessibility @6;
    communication @7;
    education @8;
    health @9;
    finance @10;
    social @11;
    custom @12;
}

enum AppSource {
    builtin @0;
    store @1;
    sideloaded @2;
    web @3;
    repository @4;
    unknown @5;
    custom @6;
}

# ── App Index Permission ──────────────────────────────────────────────
# Audit-7 addition: permission listing in the index. Users can see
# what permissions an app requires before installing.
struct AppIndexPermission {
    permission @0 :Text;
    name @1 :Text;
    description @2 :Text;
    # Whether the permission is required (app won't work without it).
    required @3 :Bool;
    # Risk level of the permission.
    risk @4 :PermissionRisk;
}

enum PermissionRisk {
    safe @0;        # No user data accessed
    normal @1;      # Non-sensitive data accessed
    dangerous @2;   # Sensitive data accessed (camera, microphone, location)
    custom @3;
}

# ── App Index Stats ───────────────────────────────────────────────────
# Audit-7 addition: aggregate statistics for the index. Useful for
# dashboards, analytics, and system health monitoring.
struct AppIndexStats {
    totalApps @0 :UInt32;
    installedApps @1 :UInt32;
    runningApps @2 :UInt32;
    suspendedApps @3 :UInt32;
    # Breakdown by source.
    builtinCount @4 :UInt32;
    storeCount @5 :UInt32;
    sideloadedCount @6 :UInt32;
    webCount @7 :UInt32;
    # Breakdown by category (top 5).
    topCategories @8 :List(CategoryCount);
    # Total storage used by installed apps.
    totalStorageBytes @9 :UInt64;
    # Timestamp of this snapshot.
    capturedAt @10 :T.Timestamp;
}

struct CategoryCount {
    category @0 :AppCategory;
    count @1 :UInt32;
}

# ── Subscription Filter ──────────────────────────────────────────────
# Audit-7 addition: filter for app index subscriptions. Consumers can
# subscribe to only specific app IDs or state changes to reduce noise.
struct AppIndexSubscriptionFilter {
    # Only events for these app IDs (empty = all apps).
    appIds @0 :List(T.AppId);
    # Only these event types.
    eventTypes @1 :List(AppIndexEventType);
    # Only events since this timestamp.
    since @2 :T.Timestamp;
    # Audit-9: coalesce rapid state changes within this window (ms).
    # Events for the same app within the window are batched together.
    coalesceWindowMs @3 :UInt32;
}

enum AppIndexEventType {
    installed @0;
    updated @1;
    uninstalled @2;
    stateChanged @3;
    custom @4;
}

# ── Events ────────────────────────────────────────────────────────────

interface AppIndexSubscription {
    pull @0 () -> (events :List(AppIndexEvent));
    cancel @1 () -> T.VoidResult;
}

struct AppIndexEvent {
    union {
        installed @0 :AppIndexInstallEvent;
        updated @1 :AppIndexUpdateEvent;
        uninstalled @2 :AppIndexUninstallEvent;
        stateChanged @3 :AppIndexStateEvent;
        custom @4 :Data;
    }
}

struct AppIndexInstallEvent {
    appId @0 :T.AppId;
    name @1 :Text;
    version @2 :T.Version;
    timestamp @3 :T.Timestamp;
}

struct AppIndexUpdateEvent {
    appId @0 :T.AppId;
    previousVersion @1 :T.Version;
    newVersion @2 :T.Version;
    timestamp @3 :T.Timestamp;
}

struct AppIndexUninstallEvent {
    appId @0 :T.AppId;
    timestamp @1 :T.Timestamp;
}

struct AppIndexStateEvent {
    appId @0 :T.AppId;
    previous @1 :AppState;
    current @2 :AppState;
    timestamp @3 :T.Timestamp;
}

# Audit-8 addition: version comparison result.
struct VersionComparison {
    # -1 if A < B, 0 if A == B, 1 if A > B.
    result @0 :Int8;
    # Whether the comparison is valid (e.g., not malformed versions).
    valid @1 :Bool;
}

# Audit-10: search ranking weights for custom relevance tuning.
struct SearchRankingWeights {
    # Weight for keyword match (0.0-1.0).
    keywordMatch @0 :Float32;
    # Weight for recency (0.0-1.0).
    recency @1 :Float32;
    # Weight for popularity (0.0-1.0).
    popularity @2 :Float32;
    # Weight for user rating (0.0-1.0).
    rating @3 :Float32;
    # Weight for category match (0.0-1.0).
    categoryMatch @4 :Float32;
}

# Audit-10: rating moderation decision.
enum RatingModerationDecision {
    approve @0;
    reject @1;
    flag @2;
    custom @3;
}

# Audit-10: app rating with moderation state.
struct AppRating {
    id @0 :Text;
    appId @1 :T.AppId;
    rating @2 :Float32;
    review @3 :Text;
    submittedAt @4 :T.Timestamp;
    moderationState @5 :RatingModerationState;
}

enum RatingModerationState {
    pending @0;
    approved @1;
    rejected @2;
    flagged @3;
    custom @4;
}

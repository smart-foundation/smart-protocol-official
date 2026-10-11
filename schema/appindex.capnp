@0xa1b2c3d4e5f6001a;

# ═══════════════════════════════════════════════════════════════════════
# AppIndex - application discovery, search, launch, and tracking.
#
# WHAT THIS IS
#   The catalog of all known applications: list, search, launch, pin, track,
#   and report INSTALL state. This schema owns catalog metadata; lifecycle
#   management lives in app.capnp; bundle self-description lives in
#   manifest.capnp.
#
# THE ONE APP TAXONOMY
#   `AppCategory` and `AppSource` are now OPEN TOKENS, published here as
#   conformance constants and imported by app.capnp and shell.capnp. There
#   were three rival category taxonomies (this file, app.capnp, and shell's
#   `ApplicationCategory`), so an app's category had to be mapped at every
#   surface boundary and a category added in any later year had no ordinal
#   anywhere. One home, one spelling, and a future category is a string.
#
# AN APP FORMAT THAT DOES NOT EXIST YET
#   `AppInfo.manifestName` points at the bundle's `Manifest`, which is the
#   self-description that already covers "apps, services, devices, plug-ins,
#   snapshots, payload bundles". Format knowledge never enters this contract:
#   a new app format is describable by adding a Manifest, with no change here.
#   `listCapabilities` reports the manifest's declared requirements, so an
#   index can show what an app will ask for without a permission-string
#   vocabulary of its own.
#
# TWO LIFECYCLES, DISAMBIGUATED
#   `AppState` (here) is INSTALL state. `AppLifecycle` (app.capnp) is RUNTIME
#   state. The two never overlap and never disagree, and a launcher that wants
#   both subscribes to both — it does not reconcile them. Previously both
#   files defined both kinds of value.
#
# THE STORE DOMAIN IS GONE
#   Ratings, moderation, recommendations, reason codes and search ranking
#   weights were a distribution service's internals inside the local index.
#   Moderation policy is store governance — a local backend would have
#   implemented five different policies behind field names that promised
#   contract semantics — and `setSearchRankingWeights` was a global mutable
#   shared resource with no stated authority. `compareVersions` was pure
#   arithmetic exposed as IPC, with a prerelease-ordering fork in it. All of
#   it is deleted; the index is now list/search/launch/pin/track.
#
# WHAT WAS KEPT
#   The core design: paginated everything, a typed launch-args union, a
#   subscription with filters and coalescing, and `LaunchResult` — the error
#   model the rest of the batch copies.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";
using M = import "manifest.capnp";

# An app-instance reference. A union rather than a `UInt32` with a sentinel:
# instance 0 and "not an instance app" were indistinguishable, and an ID
# allocator that starts at 0 produces two meanings for one number.
struct AppInstanceRef {
    union {
        none     @0 :Void;
        instance @1 :UInt32;
        unknown  @2 :Void;
    }
}

# A file/resource reference. This is the canonical definition; app.capnp and
# shell.capnp import it instead of carrying identical twins.
struct FileRef {
    union {
        path    @0 :T.FilePath;
        uri     @1 :T.Uri;
        fileId  @2 :T.FileId;
        custom  @3 :T.StringMap;
        unknown @4 :Void;
    }
}

# An app icon. `data` is a buffer reference: a launcher grid over 500 apps
# used to copy every icon into one message.
struct AppIcon {
    data     @0 :T.DataHandle;
    mimeType @1 :T.MimeType;
    width    @2 :UInt32;
    height   @3 :UInt32;
    metadata @4 :T.StringMap;
}

interface AppIndexService {
    # List all apps matching a filter, paginated.
    listApps @0 (filter :AppFilter, pagination :T.Pagination)
             -> (apps :List(AppInfo), total :UInt64);

    # Get a single app by ID. An id from a stale subscription or a race with
    # uninstall used to return a zero `AppInfo` (name "", state
    # `notInstalled` — which collides with a REAL state value), so the
    # launcher showed a phantom entry.
    getApp @1 (appId :T.AppId) -> (result :AppInfoResult);

    # Launch an app with optional arguments.
    launch @2 (appId :T.AppId, args :LaunchArgs) -> (result :LaunchResult);

    # Launch a URL via the appropriate app.
    launchUrl @3 (url :T.Uri) -> (result :LaunchResult);

    # Get pinned apps.
    getPinned @4 (pagination :T.Pagination) -> (apps :List(AppInfo), total :UInt64);

    # Pin an app.
    pinApp @5 (appId :T.AppId) -> T.VoidResult;

    # Unpin an app.
    unpinApp @6 (appId :T.AppId) -> T.VoidResult;

    # Search apps by query, with relevance ranking.
    searchApps @7 (query :Text, filter :AppSearchFilter, pagination :T.Pagination)
               -> (results :List(AppSearchResult), total :UInt64);

    # Get recent apps (ordered by last-used, most recent first).
    getRecentApps @8 (pagination :T.Pagination)
                  -> (apps :List(AppInfo), total :UInt64);

    # Clear recent apps history.
    clearRecentApps @9 () -> T.VoidResult;

    # Subscribe to app index changes (installed, updated, uninstalled).
    subscribe @10 (filter :AppIndexSubscriptionFilter)
               -> (subscription :AppIndexSubscription);
    pull @11 (maxEvents :UInt32) -> (events :List(AppIndexEvent));
    cancel @12 (subscription :AppIndexSubscription) -> T.VoidResult;

    # Get aggregate statistics for the index.
    getStats @13 () -> (stats :AppIndexStats);

    # The capabilities this app declares, as the manifest states them. No
    # permission-string vocabulary of our own.
    listCapabilities @14 (appId :T.AppId, pagination :T.Pagination)
                     -> (requirements :List(M.CapabilityRequirement), total :UInt64);

    # Get apps that depend on a given package.
    getDependents @15 (packageId :T.PackageId, pagination :T.Pagination)
                  -> (apps :List(AppInfo), total :UInt64);

    # Batch get multiple apps by ID. Bounded IN as well as out: batching
    # without pagination only moves the unboundedness.
    batchGet @16 (appIds :List(T.AppId), pagination :T.Pagination)
             -> (apps :List(AppInfo), total :UInt64);
}

# ── Results ───────────────────────────────────────────────────

struct AppInfoResult {
    union {
        app     @0 :AppInfo;
        error   @1 :T.Error;
        unknown @2 :Void;
    }
}

struct LaunchResult {
    union {
        success @0 :LaunchSuccess;
        error @1 :T.Error;
        unknown @2 :Void;
    }
}

struct LaunchSuccess {
    appId @0 :T.AppId;
    # Compatibility detail: which process was started. Not an authority and
    # not an identity — a launch is not a capability handover, and the
    # launched app is addressed through its service contracts.
    pid @1 :T.ProcessId;
    timestamp @2 :T.Timestamp;
    instance @3 :AppInstanceRef;
}

# ── Launch Args (typed) ──────────────────────────────────────

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
        custom @4 :T.StringMap;
        unknown @5 :Void;
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
        custom @5 :T.StringMap;
        unknown @6 :Void;
    }
}

# ── Search Result ─────────────────────────────────────────────

struct AppSearchResult {
    app @0 :AppInfo;
    relevance @1 :Float32;
    # A highlight is attributed to the field it came from. Previously the
    # field was a sibling `matchField :Text` beside a bare
    # `List(TextRange)`, so a client receiving three ranges had to guess
    # which field each referred to — one missed field turned highlights into
    # garbage.
    highlights @2 :List(Match);
}

struct Match {
    field @0 :Text;
    range @1 :TextSpan;
    metadata @2 :T.StringMap;
}

struct TextSpan {
    start @0 :UInt32;
    end @1 :UInt32;
}

# ── App Search Filter ─────────────────────────────────────────

struct AppSearchFilter {
    # Restrict to these categories (open tokens).
    categories @0 :List(Text);
    # Restrict to these sources (open tokens).
    sources @1 :List(Text);
    # Minimum version requirement.
    minVersion @2 :T.Version;
    # Maximum version ceiling.
    maxVersion @3 :T.Version;
    # Only installed apps.
    installed @4 :T.BoolFilter;
    # Only apps matching these names (substring match).
    nameContains @5 :Text;
}

# ── Filter ────────────────────────────────────────────────────

struct AppFilter {
    name @0 :Text;
    # Open tokens — see the conformance constants at the end of this file.
    category @1 :Text;
    categories @2 :List(Text);
    installed @3 :T.BoolFilter;
    source @4 :Text;
    appIds @5 :List(T.AppId);
    minVersion @6 :T.Version;
    maxVersion @7 :T.Version;
    # Install state only. Runtime lifecycle is app.capnp's `AppLifecycle`.
    state @8 :AppState;
}

# ── App Info ──────────────────────────────────────────────────

struct AppInfo {
    id @0 :T.AppId;
    packageId @1 :T.PackageId;
    # The bundle's self-description. Format knowledge lives there, never here.
    manifestName @2 :T.ManifestName;
    name @3 :Text;
    description @4 :Text;
    version @5 :T.Version;
    icon @6 :AppIcon;
    # Open tokens — the one app taxonomy.
    categories @7 :List(Text);
    source @8 :Text;
    # Install state. Runtime lifecycle is app.capnp's `AppLifecycle`.
    state @9 :AppState;
    pinned @10 :Bool;
    developer @11 :Text;
    license @12 :Text;
    sizeBytes @13 :UInt64;
    installDate @14 :T.Timestamp;
    lastUsed @15 :T.Timestamp;
    minVersion @16 :T.Version;
}

# INSTALL state only. A launcher that shows "running" reads app.capnp.
enum AppState {
    # Absent means the backend decides; it must never mean a
    # specific paradigm value.
    any @0;
    notInstalled @1;
    installing @2;
    installed @3;
    updating @4;
    uninstalling @5;
    errored @6;
    custom @7;
}

# ── App Index Stats ───────────────────────────────────────────

struct AppIndexStats {
    totalApps @0 :UInt32;
    installedApps @1 :UInt32;
    # Breakdown by source (open tokens).
    sourceCounts @2 :List(SourceCount);
    # Breakdown by category (open tokens).
    categoryCounts @3 :List(CategoryCount);
    # Total storage used by installed apps.
    totalStorageBytes @4 :UInt64;
    # Timestamp of this snapshot.
    capturedAt @5 :T.Timestamp;
}

struct CategoryCount {
    category @0 :Text;
    count @1 :UInt32;
}

struct SourceCount {
    source @0 :Text;
    count @1 :UInt32;
    metadata @2 :T.StringMap;
}

# ── Subscription Filter ──────────────────────────────────────

struct AppIndexSubscriptionFilter {
    # Only events for these app IDs (empty = all apps).
    appIds @0 :List(T.AppId);
    # Only these event types.
    eventTypes @1 :List(AppIndexEventType);
    # Only events since this timestamp.
    since @2 :T.Timestamp;
    # Coalesce rapid state changes within this window (ms). Events for the
    # same app within the window are batched together — the anti-thrash
    # pattern, kept and cited as the model.
    coalesceWindowMs @3 :UInt32;
}

enum AppIndexEventType {
    installed @0;
    updated @1;
    uninstalled @2;
    stateChanged @3;
    custom @4;
}

# ── Events ────────────────────────────────────────────────────

interface AppIndexSubscription {
    pull @0 (maxEvents :UInt32) -> (events :List(AppIndexEvent));
    cancel @1 () -> T.VoidResult;
}

struct AppIndexEvent {
    union {
        installed @0 :AppIndexInstallEvent;
        updated @1 :AppIndexUpdateEvent;
        uninstalled @2 :AppIndexUninstallEvent;
        stateChanged @3 :AppIndexStateEvent;
        unknown @4 :T.UnknownEvent;
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

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# The one app taxonomy. Published so today's tools have a discoverable
# spelling; an unrecognised value MUST be ignored, never rejected. They are
# Text and deliberately NOT enums: an enum here would be an eternal
# commitment to today's list of app genres and distribution channels.
# ══════════════════════════════════════════════════════════════════════

const categorySystem        :Text = "system";
const categoryProductivity  :Text = "productivity";
const categoryGames         :Text = "games";
const categoryMedia         :Text = "media";
const categoryDevelopment   :Text = "development";
const categoryUtilities     :Text = "utilities";
const categoryAccessibility :Text = "accessibility";
const categoryCommunication :Text = "communication";
const categoryEducation     :Text = "education";
const categoryHealth        :Text = "health";
const categoryFinance       :Text = "finance";
const categorySocial        :Text = "social";

const sourceBuiltin   :Text = "builtin";
const sourceStore     :Text = "store";
const sourceSideloaded :Text = "sideloaded";
const sourceWeb       :Text = "web";
const sourceRepository :Text = "repository";

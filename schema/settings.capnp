@0xa1b2c3d4e5f60022;

using T = import "types.capnp";

# ══════════════════════════════════════════════════════════════════════
# Settings — hierarchical key-value configuration store.
#
# Improvements beyond the original schema:
#   - SettingsSubscription has cancel method.
#   - SettingValue.data uses T.DataHandle for large payloads.
#   - SettingValue has custom variant for forward compatibility (audit-3).
#   - getAll uses T.Pagination for bounded results (audit-3).
#   - listDomains uses T.Pagination for bounded results (audit-3).
#   - SettingsSubscription.pullPage adds paginated variant (audit-3).
#   - SettingsSubscription.pull accepts T.Pagination (audit-4).
# ══════════════════════════════════════════════════════════════════════

struct SettingMap {
    entries @0 :List(SettingMapEntry);
}

struct SettingMapEntry {
    key   @0 :Text;
    value @1 :SettingValue;
}

interface Settings {
    get @0 (domain :Text, key :Text) -> (value :SettingValue);
    set @1 (domain :Text, key :Text, value :SettingValue) -> T.VoidResult;
    getAll @2 (domain :Text, pagination :T.Pagination) -> (settings :SettingMap, total :UInt32);

    delete @3 (domain :Text, key :Text) -> T.VoidResult;
    clear  @4 (domain :Text) -> T.VoidResult;

    listDomains @5 (pagination :T.Pagination) -> (domains :List(Text), total :UInt32);

    watch       @6 (domain :Text, key :Text) -> (subscription :SettingsSubscription);
    watchDomain @7 (domain :Text) -> (subscription :SettingsSubscription);
    # DEPRECATED: Use SettingsSubscription.pull or pullPage instead.
    pullSettings @8 (subscription :SettingsSubscription) -> (changes :List(SettingChange));

    # Audit-8: bulk set multiple settings at once (false positive: bulk operations belong here).
    bulkSet @9 (domain :Text, entries :List(SettingMapEntry)) -> T.VoidResult;

    # Audit-8: bulk get multiple settings at once.
    bulkGet @10 (domain :Text, keys :List(Text)) -> (entries :List(SettingMapEntry));

    # Audit-8: list settings by typed category.
    listByCategory @11 (category :SettingCategory, pagination :T.Pagination)
                   -> (entries :List(SettingMapEntry), total :UInt32);

    # Audit-8: set a per-app override.
    setAppOverride @12 (appId :T.AppId, key :Text, value :SettingValue) -> T.VoidResult;

    # Audit-8: get a per-app override.
    getAppOverride @13 (appId :T.AppId, key :Text) -> (value :SettingValue, exists :Bool);

    # Audit-8: clear a per-app override.
    clearAppOverride @14 (appId :T.AppId, key :Text) -> T.VoidResult;

    # Audit-8: create a roaming profile.
    createRoamingProfile @15 (name :Text) -> (profileId :Text);

    # Audit-8: sync a roaming profile across devices.
    syncRoamingProfile @16 (profileId :Text, deviceToken :Data) -> (changes :List(SettingChange));

    # Audit-8: get settings version for conflict detection.
    getVersion @17 (domain :Text, key :Text) -> (version :UInt64);

    # Audit-8: set if unchanged (optimistic concurrency).
    setIfUnchanged @18 (domain :Text, key :Text, value :SettingValue, expectedVersion :UInt64) -> T.VoidResult;

    # Audit-8: get settings history (audit trail).
    getHistory @19 (domain :Text, key :Text, pagination :T.Pagination)
               -> (changes :List(SettingChange), total :UInt32);

    # Audit-9: set a settings dependency (when keyA changes, re-evaluate keyB).
    setDependency @20 (domain :Text, key :Text, dependsOn :Text) -> T.VoidResult;

    # Audit-9: get all dependencies for a setting.
    getDependencies @21 (domain :Text, key :Text) -> (dependencies :List(SettingDependency));

    # Audit-9: get all settings that depend on a given setting.
    getDependents @22 (domain :Text, key :Text) -> (dependents :List(SettingDependency));

    # Audit-9: create a settings template/preset.
    createTemplate @23 (template :SettingTemplate) -> (templateId :Text);

    # Audit-9: apply a settings template.
    applyTemplate @24 (templateId :Text) -> T.VoidResult;

    # Audit-9: list all settings templates.
    listTemplates @25 () -> (templates :List(SettingTemplate));

    # Audit-9: delete a settings template.
    deleteTemplate @26 (templateId :Text) -> T.VoidResult;

    # Audit-10: Subscribe to settings as a reactive stream (push-based).
    subscribeSettingsReactive @27 (domain :Text) -> (subscription :ReactiveSettingsSubscription);

    # Audit-10: Get settings diff since a given version (efficient sync).
    getSettingsDiff @28 (domain :Text, sinceVersion :UInt64) -> (changes :List(SettingChange), currentVersion :UInt64);

    # Audit-10: Set an encrypted setting value.
    setEncrypted @29 (domain :Text, key :Text, value :Data, keyId :T.KeyId) -> T.VoidResult;

    # Audit-10: Get an encrypted setting value (decrypted).
    getEncrypted @30 (domain :Text, key :Text) -> (value :Data, exists :Bool);
}

interface SettingsSubscription {
    pull   @0 (pagination :T.Pagination) -> (changes :List(SettingChange), total :UInt32);
    cancel @1 () -> T.VoidResult;
    # Paginated variant of pull for large change streams.
    pullPage @2 (pagination :T.Pagination) -> (changes :List(SettingChange), total :UInt32);
}

interface ReactiveSettingsSubscription {
    pull @0 () -> (changes :List(SettingChange));
    cancel @1 () -> T.VoidResult;
}

struct SettingValue {
    union {
        string  @0 :Text;
        integer @1 :Int64;
        real    @2 :Float64;
        boolean @3 :Bool;
        data    @4 :T.DataHandle;
        list    @5 :List(SettingValue);
        dict    @6 :SettingMap;
        # Unknown or backend-specific value type.
        custom  @7 :Data;
    }
}

struct SettingChange {
    domain    @0 :Text;
    key       @1 :Text;
    value     @2 :SettingValue;
    timestamp @3 :T.Timestamp;
    # Audit-8: who made the change (actor ID).
    actorId   @4 :Text;
}

# Audit-8: typed setting categories (replaces freeform domain strings).
enum SettingCategory {
    security @0;
    display @1;
    accessibility @2;
    network @3;
    system @4;
    user @5;
    audio @6;
    privacy @7;
    developer @8;
    custom @9;
}

# Audit-8: setting scope for per-app overrides and managed settings.
struct SettingScope {
    union {
        global @0 :Void;
        perApp @1 :T.AppId;
        perUser @2 :Text;
        perProfile @3 :Text;
        managed @4 :ManagedPolicy;
        inherited @5 :Text;
        custom @6 :Data;
    }
}

# Audit-8: enterprise managed policy.
struct ManagedPolicy {
    policyId @0 :Text;
    provider @1 :Text;
    locked @2 :Bool;
    inheritedAt @3 :T.Timestamp;
}

# Audit-8: conditional value for time-aware settings.
struct ConditionalValue {
    value @0 :SettingValue;
    condition @1 :SettingCondition;
    priority @2 :UInt32;
}

# Audit-8: setting condition.
struct SettingCondition {
    union {
        always @0 :Void;
        timeRange @1 :TimeRangeCondition;
        batteryAbove @2 :UInt32;
        batteryBelow @3 :UInt32;
        charging @4 :Bool;
        custom @5 :Data;
    }
}

# Audit-8: time range condition.
struct TimeRangeCondition {
    afterHour @0 :UInt8;
    beforeHour @1 :UInt8;
    daysOfWeek @2 :UInt32;
}

# Audit-8: AI-tuned metadata.
struct AiTunedMetadata {
    modelId @0 :Text;
    confidence @1 :Float32;
    source @2 :AiTuneSource;
    learnedAt @3 :T.Timestamp;
}

# Audit-8: AI tune source.
enum AiTuneSource {
    usagePattern @0;
    timeOfDay @1;
    locationBased @2;
    explicitHint @3;
    custom @4;
}

# Audit-8: roaming profile.
struct RoamingProfile {
    profileId @0 :Text;
    name @1 :Text;
    settings @2 :List(SettingMapEntry);
    syncToken @3 :Data;
    lastSyncAt @4 :T.Timestamp;
    deviceCount @5 :UInt32;
}

# Audit-9: settings dependency graph for policy engine.

struct SettingDependency {
    domain @0 :Text;
    key @1 :Text;
    # Setting that must be re-evaluated when the above changes.
    dependsOn @2 :Text;
    # Trigger: re-read, re-evaluate, or disable.
    trigger @3 :DependencyTrigger;
    # Priority for ordering.
    priority @4 :UInt32;
}

enum DependencyTrigger {
    reRead @0;       # Re-read the dependent setting
    reEvaluate @1;  # Re-evaluate the dependent setting's condition
    disable @2;      # Disable the dependent setting
    custom @3;
}

# Audit-9: settings template/preset system.

struct SettingTemplate {
    templateId @0 :Text;
    name @1 :Text;
    description @2 :Text;
    # Settings entries in this template.
    entries @3 :List(SettingMapEntry);
    # Tags for categorization (e.g., "night-mode", "power-saving").
    tags @4 :List(Text);
    # When this template was created.
    createdAt @5 :T.Timestamp;
}

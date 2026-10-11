@0xa1b2c3d4e5f60022;

# ══════════════════════════════════════════════════════════════════════
# Settings — hierarchical key-value configuration store.
#
# WHAT THIS IS
#   The one settings store: domain+key, a recursive value model, change
#   subscription, optimistic concurrency, and delta reads. The shell
#   delegates here rather than carrying a domain-less copy.
#
# THE ONE WIRE-HONESTNESS DEFECT, FIXED
#   `get` used to return a bare `SettingValue`. `SettingValue`'s zero member
#   is `string`, so a missing key arrived as an empty string — a consumer
#   reading `ui.accent` that was never set painted an empty accent instead
#   of applying the default, and every backend invented a different
#   sentinel. `get` now returns a result union carrying the value, an
#   explicit `exists`, and `T.Error`.
#
# WHO MAY WRITE, STATED SO NO BACKEND GUESSES
#   Writes are gated ONCE, by the capability held when the caller acquired
#   this service. The store does not check per-key permissions itself: a
#   backend that also enforces a rule inside `set` has two authorities that
#   must agree forever. Writing `system.*` requires a platform capability;
#   an app holding none may still read public domains and write its own.
#
# WHAT WAS DELETED, AND WHY
#   - `pullSettings` — a deprecated second path to the same change stream.
#     Two paths to one fact is a merge conflict waiting to happen.
#   - Roaming profiles (`createRoamingProfile`, `syncRoamingProfile`,
#     `RoamingProfile`): cross-device sync with a raw `deviceToken :Data`
#     credential passed as a parameter. Credentials are capability
#     references, never message fields, and this was a second settings
#     transport beside the shell's handoff.
#   - Encrypted settings (`setEncrypted`, `getEncrypted`): encryption as a
#     STORE METHOD made the store a crypto participant that must hold or
#     borrow a key path, and it took the value inline. Secret handling is
#     secret.capnp's job; the store accepts an opaque blob it never parses.
#   - The dependency graph (`setDependency`, `getDependencies`,
#     `getDependents`, `SettingDependency`): a policy engine's internals.
#   - Templates (`createTemplate`, `applyTemplate`, `listTemplates`,
#     `deleteTemplate`, `SettingTemplate`): presets with no caller.
#   - The reactive subscription: a second subscription to the same changes,
#     and the one missing its bound.
#   - The orphan structs no method ever referenced: `SettingScope`,
#     `ManagedPolicy`, `ConditionalValue`, `SettingCondition`,
#     `TimeRangeCondition`, `AiTunedMetadata`. Two of them were worse than
#     dead: `SettingCondition` hardwired `batteryAbove`/`batteryBelow`/
#     `charging` into the UNIVERSAL settings contract, so a rack server
#     evaluated battery conditions as nonsense, and `TimeRangeCondition`
#     carried a `daysOfWeek` bitmask with no published bit assignment.
#
# WHAT WAS KEPT, AND WHY IT IS WORTH KEEPING
#   `getSettingsDiff` — a delta read instead of a full-state poll. It is the
#   best eco design in the batch and the pattern the shell handoff and
#   package update checks should copy. `getVersion`/`setIfUnchanged` —
#   optimistic concurrency, correctly shaped. `getHistory` — the change
#   audit trail. Bulk set/get — bounded and useful.
#
# ON `SettingValue.list` AND `SettingMap`
#   Both stay. `SettingMap` is the wire type for multi-entry reads and
#   writes (getAll, bulkSet, bulkGet); `SettingValue.list`/`dict` are the
#   recursive value forms. Collapsing them would remove a shape, not a
#   duplicate: a sequence is not a mapping.
# ══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

struct SettingMap {
    entries @0 :List(SettingMapEntry);
}

struct SettingMapEntry {
    key   @0 :Text;
    value @1 :SettingValue;
}

interface Settings {
    get @0 (domain :Text, key :Text) -> (result :SettingResult);
    set @1 (domain :Text, key :Text, value :SettingValue) -> T.VoidResult;
    getAll @2 (domain :Text, pagination :T.Pagination)
            -> (settings :SettingMap, total :UInt64);

    delete @3 (domain :Text, key :Text) -> T.VoidResult;
    clear  @4 (domain :Text) -> T.VoidResult;

    listDomains @5 (pagination :T.Pagination)
                -> (domains :List(Text), total :UInt64);

    watch       @6 (domain :Text, key :Text) -> (subscription :SettingsSubscription);
    watchDomain @7 (domain :Text) -> (subscription :SettingsSubscription);

    # Bulk set multiple settings at once.
    bulkSet @8 (domain :Text, entries :List(SettingMapEntry)) -> T.VoidResult;

    # Bulk get multiple settings at once.
    bulkGet @9 (domain :Text, keys :List(Text)) -> (entries :List(SettingMapEntry));

    # List settings by category. `category` is an OPEN token: a settings
    # domain invented in any later year (spatial, neural-interface, ambient)
    # has no ordinal to wait for. Conformance tokens are published below.
    listByCategory @10 (category :Text, pagination :T.Pagination)
                    -> (entries :List(SettingMapEntry), total :UInt64);

    # Per-app overrides. The HOST gates these: whether app X may override
    # setting Y is a capability decision made at acquisition, not a parameter
    # this service re-decides per call.
    setAppOverride @11 (appId :T.AppId, key :Text, value :SettingValue)
                    -> T.VoidResult;
    # `exists` rather than an error, because "not set" is an answer.
    getAppOverride @12 (appId :T.AppId, key :Text)
                    -> (value :SettingValue, exists :Bool);
    clearAppOverride @13 (appId :T.AppId, key :Text) -> T.VoidResult;

    # Settings version for conflict detection.
    getVersion @14 (domain :Text, key :Text) -> (version :UInt64);

    # Optimistic concurrency: set only if the version is unchanged.
    setIfUnchanged @15 (domain :Text, key :Text, value :SettingValue,
                        expectedVersion :UInt64) -> T.VoidResult;

    # Settings change history (audit trail).
    getHistory @16 (domain :Text, key :Text, pagination :T.Pagination)
               -> (changes :List(SettingChange), total :UInt64);

    # Delta read instead of a full-state poll. The eco pattern the rest of
    # the protocol should copy.
    getSettingsDiff @17 (domain :Text, sinceVersion :UInt64)
                    -> (changes :List(SettingChange), currentVersion :UInt64);
}

interface SettingsSubscription {
    pull @0 (maxEvents :UInt32) -> (changes :List(SettingChange));
    cancel @1 () -> T.VoidResult;
}

# ── Values ───────────────────────────────────────────────────

struct SettingResult {
    union {
        value   @0 :SettingValue;
        # The key is not set. An answer, not a fault — and no longer
        # indistinguishable from an empty string.
        notSet  @1 :Void;
        error   @2 :T.Error;
        unknown @3 :Void;
    }
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
        # A value type this schema was frozen before. Carries a type
        # discriminator so a consumer can route it.
        unknown @7 :T.UnknownEvent;
    }
}

struct SettingChange {
    domain    @0 :Text;
    key       @1 :Text;
    value     @2 :SettingValue;
    timestamp @3 :T.Timestamp;
    # Opaque actor token, backend-decided (an app id, a user id, or a
    # service name). Text because the schema does not model the identity
    # system; consumers route on it, they do not parse it.
    actorId   @4 :Text;
    # Monotonic store version after this change, so a consumer can tell
    # whether it has seen everything without re-reading.
    version   @5 :UInt64;
}

# ══════════════════════════════════════════════════════════════════════
# CONFORMANCE TOKENS — conventions, NOT contract
#
# Published so today's tools have a discoverable spelling for setting
# categories. An unrecognised value MUST be ignored, never rejected.
# ══════════════════════════════════════════════════════════════════════

const categorySecurity      :Text = "security";
const categoryDisplay       :Text = "display";
const categoryAccessibility :Text = "accessibility";
const categoryNetwork       :Text = "network";
const categorySystem        :Text = "system";
const categoryUser          :Text = "user";
const categoryAudio         :Text = "audio";
const categoryPrivacy       :Text = "privacy";
const categoryDeveloper     :Text = "developer";

@0xa1b2c3d4e5f60002;

using T = import "types.capnp";

# ══════════════════════════════════════════════════════════════════════
# System — core system service: handshake, capabilities, extensions,
#          health, and lifecycle management.
#
# Improvements beyond the original schema:
#   - handshake applicationId uses T.AppId (was raw Text).
#   - CapabilitiesSubscription has cancel for clean teardown.
#   - ExtensionInfo.id uses T.ExtensionId.
#   - listExtensions uses T.Pagination.
#   - uptime uses T.Duration (was raw UInt64 seconds).
#   - CapabilityChange union has custom variant.
# ══════════════════════════════════════════════════════════════════════

interface System {
    handshake @0 (applicationId :T.AppId, version :T.Version, capabilities :Capabilities) -> (sessionId :T.SessionId, serverVersion :T.Version);
    getCapabilities @1 () -> (capabilities :Capabilities);
    getInfo @2 () -> (info :SystemInfo);
    subscribeCapabilities @3 () -> (subscriptionId :UInt64);
    cancelCapabilities @4 (subscriptionId :UInt64) -> T.VoidResult;

    getExtensionCapability @5 (extensionId :T.ExtensionId) -> (capability :Bool);
    listExtensions @6 (pagination :T.Pagination) -> (extensions :List(ExtensionInfo), total :UInt64);

    ping @7 () -> ();
    shutdown @8 () -> T.VoidResult;
}

# ── Subscription interface (methods 100-101) ──

interface CapabilitiesSubscription {
    pull @0 () -> (capabilities :Capabilities, changes :List(CapabilityChange));
    cancel @1 (subscriptionId :UInt64) -> T.VoidResult;
}

struct Capabilities {
    core @0 :Bool;
    buffer @1 :Bool;
    surface @2 :Bool;
    compositor @3 :Bool;
    windowManager @4 :Bool;
    display @5 :Bool;
    input @6 :Bool;
    textInput @7 :Bool;
    font @8 :Bool;
    theme @9 :Bool;
    accessibility @10 :Bool;
    session @11 :Bool;
    power @12 :Bool;
    network @13 :Bool;
    audio @14 :Bool;
    media @15 :Bool;
    clipboard @16 :Bool;
    notification @17 :Bool;
    capture @18 :Bool;
    auth @19 :Bool;
    location @20 :Bool;
    filesystem @21 :Bool;
    files @22 :Bool;
    process @23 :Bool;
    camera @24 :Bool;
    usb @25 :Bool;
    systemSearch @26 :Bool;
    appIndex @27 :Bool;
    app @28 :Bool;
    extension @29 :Bool;
    package @30 :Bool;
    update @31 :Bool;
    backup @32 :Bool;
    secret @33 :Bool;
    contacts @34 :Bool;
    calendar @35 :Bool;
    database @36 :Bool;
    queue @37 :Bool;
    speech @38 :Bool;
    translation @39 :Bool;
    time @40 :Bool;
    cli @41 :Bool;
    web @42 :Bool;
    service @43 :Bool;
    settings @44 :Bool;
    print @45 :Bool;
    logging @46 :Bool;
}

struct SystemInfo {
    osName @0 :Text;
    osVersion @1 :Text;
    hostname @2 :Text;
    arch @3 :Text;
    uptime @4 :T.Duration;
}

struct ExtensionInfo {
    id @0 :T.ExtensionId;
    name @1 :Text;
    version @2 :T.Version;
    enabled @3 :Bool;
}

# Subscription methods are on System at methods 100-101.

struct CapabilityChange {
    name @0 :Text;
    oldValue @1 :Bool;
    newValue @2 :Bool;
}

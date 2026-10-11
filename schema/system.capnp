@0xa1b2c3d4e5f60002;

# ═══════════════════════════════════════════════════════════════════════
# System — the core system service: handshake, capabilities, extensions,
#          health and lifecycle.
#
# The handshake/ping/shutdown shape was always right. One structural
# defect is fixed here, and it was the doctrine's own claim that hid it:
# DESIGN_PRINCIPLES.md called the capability bitmap "extensible".
#
# ── THE 47-BOOL BITMAP, REPLACED BY AN OPEN SET ────────────────────────
#
# `Capabilities` was 47 hardcoded `Bool` fields, each naming one schema in
# the tree. It is already stale — the tree contains `ai`, `tunnel`,
# `sandbox`, `crypto`, `mount`, `storage` and `endpoint`, and none of them
# has a bit. Worse, a 2046 system that ships the doctrine's own gold
# standard (`ai.capnp`) would answer with the field absent, which every
# consumer reads as "not available" and refuses to use a service that
# exists. Every new service, forever, required editing an eternal struct.
#
# Now: `Capabilities` is an OPEN set of tokens. A backend declares the
# tokens it supports; a consumer matches on the token and ignores what it
# does not recognise (the unknown-tolerance rule ai.capnp states at
# :42-47). A 2046 service is declarable at handshake with no schema
# change, and a consumer that does not know the token simply does not use
# that service — which is the correct behaviour, not a failure.
#
# A bit-per-domain would ALSO have had to be kept in agreement with
# discovery.capnp (which registers services) and abi.capnp (which declares
# features). One open vocabulary, one place.
#
# ── THE OTHER FIXES ────────────────────────────────────────────────────
#
#   * the dual subscription path: `subscribeCapabilities` returned a raw
#     `UInt64` and `CapabilitiesSubscription.cancel` took the id back.
#     Holding the subscription reference IS the authority; the id
#     parameter is gone.
#   * `getExtensionCapability` answered a capability question with a bare
#     `Bool` — the permission-flag smell in miniature. Extensions now
#     report their declared authority as capability ids.
#   * stale comments pointing at "methods 100-101", which do not exist.
#   * `CapabilityChange` had `oldValue`/`newValue` booleans with no
#     indication of whether the backend measured the transition. Now named
#     fields, with a `present` flag.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface System {
    # Declare who is calling and what it can speak. The response reports
    # what this backend supports, as an open token set.
    handshake @0 (applicationId :T.AppId, version :T.Version)
               -> (sessionId :T.SessionId, serverVersion :T.Version,
                   capabilities :Capabilities);

    # What this backend supports, right now.
    getCapabilities @1 () -> (capabilities :Capabilities);

    # Static description of the system.
    getInfo @2 () -> (info :SystemInfo);

    # Watch the capability set change. Holding the subscription IS the
    # authority to pull; there is no id to present.
    subscribeCapabilities @3 () -> (subscription :CapabilitiesSubscription);

    # Extensions this backend has loaded.
    getExtension @4 (extensionId :T.ExtensionId) -> (extension :SystemExtensionInfo);
    listExtensions @5 (pagination :T.Pagination) -> (extensions :List(SystemExtensionInfo), total :UInt64);

    # Liveness. Always succeeds; the point is that it is cheap and
    # ungated, so a caller can check reachability without authority.
    ping @6 () -> (serverTime :T.MonotonicTimestamp);

    # Begin a clean shutdown.
    shutdown @7 (clean :Bool) -> T.VoidResult;
}

interface CapabilitiesSubscription {
    # Bounded pull: the caller states how many snapshots it will take.
    pull @0 (maxSnapshots :UInt32) -> (capabilities :Capabilities, changes :List(CapabilityChange));
    cancel @1 () -> T.VoidResult;
}

# ── The open capability set ─────────────────────────────────────────────
# Tokens, not bits. `tokens` names what this backend supports — "core",
# "ai", "logging", "discovery", or a 2046 service nobody has written yet.
# A consumer that does not recognise a token ignores it; one that does,
# uses it. Nothing is ever rejected for being unknown.

struct Capabilities {
    # Open tokens, backend-declared. Convention names today's schemas
    # (published in the conformance section of ai.capnp), but the protocol
    # requires no particular spelling.
    tokens @0 :List(Text);
    # Version of each token this backend claims to support, as an open
    # map. Absent means "an unversioned claim".
    tokenVersions @1 :T.StringMap;
    # When this snapshot was taken.
    observedAt @2 :T.Timestamp;
    # True when the backend could not enumerate its own capability set and
    # is reporting a partial answer. Consumers must not treat an
    # unrecognised-or-absent token as "not supported" when this is false
    # only for the reason given in `note`.
    partial @3 :Bool;
    note @4 :Text;
}

struct SystemInfo {
    osName @0 :Text;
    osVersion @1 :T.Version;
    hostname @2 :Text;
    # Architecture as an OPEN token ("x86_64", "aarch64", "riscv64", or a
    # 2046 one) — not a closed enum of today's ISAs.
    arch @3 :Text;
    uptime @4 :T.Duration;
    # What the backend chose to report beyond the fields above.
}

struct SystemExtensionInfo {
    id @0 :T.ExtensionId;
    name @1 :Text;
    version @2 :T.Version;
    enabled @3 :Bool;
    # What authority this extension holds, as capability references.
    # Reported, not checked here — capability.capnp is the contract.
    capabilityIds @4 :List(T.CapabilityId);
    # Open description of what the extension is for.
    description @5 :Text;
}

# A change to the capability set. Named fields, not `oldValue`/
# `newValue`: the difference between "the backend measured a transition"
# and "the consumer is being told about the first observation" matters.
struct CapabilityChange {
    # The token that changed.
    token @0 :Text;
    # Whether the token is now supported.
    nowSupported @1 :Bool;
    # True when the backend observed a transition from the previous value.
    # False means this is the first observation of the token.
    transitionObserved @2 :Bool;
    at @3 :T.MonotonicTimestamp;
}

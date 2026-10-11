@0xa1b2c3d4e5f60035;

# ═══════════════════════════════════════════════════════════════════════
# Tunnel - a universal bidirectional async channel
#
# A tunnel is a typed async channel between two entities. It carries
# typed frames with a topic/schema discriminator so receivers can route.
# Tunnels can be opened over any transport that the backend supports:
# in-process, kernel IPC, Unix socket, TCP, wasm postMessage, anything.
# The schema is timeless; backends may add transports freely.
#
# Use cases span every layer: chat between users, IPC between services,
# device-to-controller telemetry, sensor streams, web app dispatch.
#
# Fixes this revision makes:
#   - `TunnelHandle` is a pure reference again. It carried `subject`,
#     `meshId` and `logicalId` — routing state on a handle, which
#     DESIGN_PRINCIPLES names as the defect: a capability attenuated to
#     a mesh still carried the mesh id, and two backends handed out
#     handles that differed in fields consumers must not trust. The spec
#     and the info carry that state now.
#   - Health is a reported open token, not an enum: the batch carried
#     three `HealthStatus` enums (this one, endpoint's, filesystem's)
#     with two incompatible value sets.
#   - `TunnelEncryption` named a 2024 standardisation generation
#     (Kyber-768/1024, already renamed ML-KEM). Encryption is an open
#     algorithm token plus parameters; a 2046 post-quantum scheme is a
#     string.
#   - `TunnelInfo` is now returned by a method instead of being a struct
#     a consumer must assemble by hand from `getMetrics` and
#     `healthCheck`.
#   - `FlowPolicy` gained a neutral sentinel: an absent policy used to
#     silently mean "reliable and ordered", the most expensive default
#     for a lossy link.
#   - Framing is stated: what happens when a frame exceeds
#     `maxFrameSize`, and how `receive`'s `more` flag interacts with it.
#   - Trusted peers are identified (NodeId), not a bag of opaque key
#     bytes with no pairing to the peer they belong to.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

struct TunnelSpec {
    name @0 :Text;
    subject @1 :Text;
    schemaId @2 :T.SchemaId;
    # Maximum frame size in bytes.
    #
    # Framing contract: a frame larger than this is rejected by the
    # producer with `limitExceeded` — it is never silently truncated,
    # and never silently accepted. On `receive`, `more` is true when the
    # frame was continued from the previous call, so a consumer that
    # ignores it would reassemble a stream per call rather than per
    # frame; the limit bounds the message, and `more` bounds the
    # reassembly.
    maxFrameSize @3 :UInt32;
    flow @4 :FlowPolicy;
    # Security policy for this tunnel.
    security @5 :TunnelSecurityPolicy;
    # QoS requirements for this tunnel.
    qos @6 :QoSParams;
    metadata @7 :T.StringMap;
}

enum FlowPolicy {
    unspecified @0;
    reliableOrdered @1;
    reliableUnordered @2;
    lossyOldest @3;
    lossyNewest @4;
    atMostOnce @5;
    custom @6;
}

interface TunnelService {
    open @0 (spec :TunnelSpec, recipient :Text) -> (handle :TunnelHandle);
    accept @1 () -> (handle :TunnelHandle);
    send @2 (handle :TunnelHandle, frame :T.DataHandle) -> (result :T.VoidResult);
    receive @3 (handle :TunnelHandle) -> (result :TunnelFrameResult);
    subscribe @4 (handle :TunnelHandle) -> (subscription :TunnelSubscription);
    cancelSubscribe @5 (subscription :TunnelSubscription) -> T.VoidResult;
    close @6 (handle :TunnelHandle) -> (result :T.VoidResult);

    # ── Mesh topology ──
    getMeshTopology @7 (handle :TunnelHandle) -> (result :MeshTopologyResult);

    # ── Tunnel metrics ──
    getMetrics @8 (handle :TunnelHandle) -> (metrics :TunnelMetrics);

    # ── Health check ──
    healthCheck @9 (handle :TunnelHandle) -> (result :TunnelHealthResult);

    # ── Info ──
    # The aggregate descriptor a consumer would otherwise assemble by
    # hand from getMetrics and healthCheck.
    getInfo @10 (handle :TunnelHandle) -> (result :TunnelInfoResult);

    # ── Multiplexing ──
    openLogical @11 (handle :TunnelHandle, name :Text) -> (result :LogicalTunnelResult);
    closeLogical @12 (handle :TunnelHandle, logical :LogicalTunnel) -> T.VoidResult;
    listLogical @13 (handle :TunnelHandle, pagination :T.Pagination)
               -> (logicals :List(LogicalTunnel), totalCount :UInt64);
}

struct TunnelFrameResult {
    union {
        frame @0 :TunnelFrame;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct TunnelFrame {
    data @0 :T.DataHandle;
    # True when this frame continues the previous one; the frame is
    # complete when it is false (see the framing contract in TunnelSpec).
    more @1 :Bool;
    metadata @2 :T.StringMap;
}

# A pure reference: id only. The subject lives in TunnelSpec, the mesh in
# MeshTopology, and the logical stream in LogicalTunnel.
struct TunnelHandle {
    id @0 :T.TunnelId;
}

struct TunnelInfoResult {
    union {
        info @0 :TunnelInfo;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct TunnelInfo {
    handle @0 :TunnelHandle;
    peer @1 :Text;
    spec @2 :TunnelSpec;
    # State as an open token ("open", "halfClosed", "closing", ...).
    state @3 :Text;
    framesIn @4 :UInt64;
    framesOut @5 :UInt64;
    bytesIn @6 :UInt64;
    bytesOut @7 :UInt64;
    createdAt @8 :T.Timestamp;
    metrics @9 :TunnelMetrics;
    metadata @10 :T.StringMap;
}

enum TunnelState {
    unspecified @0;
    opening @1;
    open @2;
    halfClosed @3;
    closing @4;
    closed @5;
    error @6;
    custom @7;
}

interface TunnelSubscription {
    # Unbounded pull — returns all available frames. For high-throughput
    # tunnels, use pullPaged (ordinal @2) with T.Pagination to bound the
    # result set. Kept as the first ordinal for the existing wire shape.
    pull @0 (handle :TunnelHandle) -> (frames :List(T.DataHandle));
    cancel @1 () -> T.VoidResult;

    # Paginated frame retrieval. Returns at most `pagination.limit`
    # frames starting at `pagination.offset`.
    pullPaged @2 (handle :TunnelHandle, pagination :T.Pagination)
              -> (frames :List(T.DataHandle), totalCount :UInt64);
}

# ── Mesh Topology ────────────────────────────────────────────

struct MeshTopologyResult {
    union {
        topology @0 :MeshTopology;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct MeshTopology {
    meshId @0 :Text;
    # This node's tunnel handle within the mesh (a pure reference).
    localHandle @1 :TunnelHandle;
    peers @2 :List(TunnelPeer);
    routes @3 :List(TunnelRoute);
    # Routing algorithm as an open token ("flood", "gossip", ...):
    # routing is backend-internal, and the protocol reports rather than
    # instructs (TIMELESSNESS.md:84).
    algorithm @4 :Text;
    metadata @5 :T.StringMap;
}

struct TunnelPeer {
    peerId @0 :T.NodeId;
    # Peer's endpoint address (opaque; see endpoint.capnp).
    endpoint @1 :Text;
    # Capabilities this peer supports, as open tokens.
    capabilities @2 :List(Text);
    latency @3 :T.Duration;
    lastSeen @4 :T.Timestamp;
    state @5 :TunnelPeerState;
    metadata @6 :T.StringMap;
}

enum TunnelPeerState {
    unspecified @0;
    connected @1;
    disconnected @2;
    connecting @3;
    failed @4;
    custom @5;
}

struct TunnelRoute {
    destination @0 :T.NodeId;
    nextHop @1 :T.NodeId;
    metric @2 :UInt32;
    expiry @3 :T.Timestamp;
}

# ── Tunnel Security Policy ─────────────────────────────────

struct TunnelSecurityPolicy {
    # Encryption algorithm as an open token ("aes256GcmSiv",
    # "chacha20Poly1305", "ml-kem-768-hybrid", ...). Naming a 2024
    # standardisation generation is how this enum aged into a lie;
    # a token cannot.
    encryption @0 :Text;
    # Authentication method as an open token ("psk", "certificate",
    # "token", ...).
    authentication @1 :Text;
    # Key rotation interval (absent = no rotation).
    keyRotationInterval @2 :T.Duration;
    # Whether to verify peer identity.
    verifyPeer @3 :Bool;
    # Trusted peers, identified — the previous spelling was a bag of
    # opaque key bytes with no pairing to the peer they belonged to.
    trustedPeers @4 :List(T.NodeId);
    # Backend-declared parameters (key sizes, modes, ...).
    parameters @5 :T.StringMap;
}

# ── QoS Parameters ──────────────────────────────────────────

struct QoSParams {
    latencyBudget @0 :T.Duration;
    jitterTolerance @1 :T.Duration;
    # Required bandwidth in bits per second (0 = unlimited).
    bandwidthBps @2 :UInt64;
    # Priority (0 = lowest, 255 = highest).
    priority @3 :UInt8;
    # What to do when the queue is full, as an open token.
    dropPolicy @4 :Text;
    metadata @5 :T.StringMap;
}

# ── Tunnel Metrics ──────────────────────────────────────────

struct TunnelMetrics {
    latencyP50 @0 :T.Duration;
    latencyP99 @1 :T.Duration;
    lossRate @2 :Float32;
    throughputBps @3 :UInt64;
    retransmissions @4 :UInt64;
    lastUpdated @5 :T.Timestamp;
    framesInFlight @6 :UInt32;
    sendQueueDepth @7 :UInt32;
}

# ── Tunnel Health ───────────────────────────────────────────

struct TunnelHealthResult {
    union {
        health @0 :TunnelHealth;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct TunnelHealth {
    rtt @0 :T.Duration;
    loss @1 :Float32;
    jitter @2 :T.Duration;
    timestamp @3 :T.Timestamp;
    # Reported status as an open token ("healthy", "degraded", ...).
    status @4 :Text;
    metadata @5 :T.StringMap;
}

# ── Multiplexed Logical Tunnel ──────────────────────────────

struct LogicalTunnelResult {
    union {
        logical @0 :LogicalTunnel;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct LogicalTunnel {
    # Logical stream identity, unique within the parent tunnel. This is
    # the one spelling: `openLogical` returns this struct, so no consumer
    # has to track a bare UInt32 beside it.
    logicalId @0 :LogicalTunnelId;
    name @1 :Text;
    state @2 :TunnelState;
    bytesIn @3 :UInt64;
    bytesOut @4 :UInt64;
    flow @5 :FlowPolicy;
    metadata @6 :T.StringMap;
}

struct LogicalTunnelId {
    id @0 :UInt32;
}

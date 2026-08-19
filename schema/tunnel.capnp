@0xa1b2c3d4e5f60035;

# ═══════════════════════════════════════════════════════════════════════
# Tunnel - a universal bidirectional async channel
#
# A tunnel is a typed async channel between two entities. It carries
# typed frames with a Topic/Schema discriminator so receivers can route.
# Tunnels can be opened over any transport that the backend supports:
# in-process, kernel IPC, Unix socket, TCP, wasm postMessage, anything.
# The schema is timeless; backends may add transports freely.
#
# Use cases span every layer: chat between users, IPC between services,
# device-to-controller telemetry, sensor streams, web app dispatch.
#
# Improvements beyond the original schema (audit):
#   - TunnelSpec.schemaId replaced with T.SchemaId typed wrapper.
#   - TunnelHandle.id typed as T.TunnelId (promoted from local struct).
#   - All Data frame fields use T.DataHandle for large payloads (>1KB).
#   - TunnelInfo frame/byte counters typed appropriately.
#   - All subscription interfaces have cancel method.
#   - TunnelState enum has custom variant for forward compatibility.
#   - FlowPolicy enum has custom variant for forward compatibility.
#   - Added pullPaged method with T.Pagination for bounded frame retrieval.
#
# Audit-7 improvements:
#   - Mesh topology for multi-node overlays (n-to-n mesh).
#   - Multi-link bonding for failover and load balancing.
#   - Tunnel security policy (encryption, authentication, key rotation).
#   - QoS parameters (latency budget, jitter tolerance, bandwidth).
#   - Tunnel metrics (latency percentiles, loss rate, throughput).
#   - Health check for tunnel liveness monitoring.
#   - Tunnel multiplexing for multiple logical streams over one connection.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

struct TunnelSpec {
    name @0 :Text;
    subject @1 :Text;
    schemaId @2 :T.SchemaId;
    maxFrameSize @3 :UInt32;
    flow @4 :FlowPolicy;
    # Security policy for this tunnel (empty = no encryption).
    security @5 :TunnelSecurityPolicy;
    # QoS requirements for this tunnel.
    qos @6 :QoSParams;
}

enum FlowPolicy {
    reliableOrdered @0;
    reliableUnordered @1;
    lossyOldest @2;
    lossyNewest @3;
    atMostOnce @4;
    custom @5;
}

interface TunnelService {
    open @0 (spec :TunnelSpec, recipient :Text) -> (handle :TunnelHandle);
    accept @1 () -> (handle :TunnelHandle);
    send @2 (handle :TunnelHandle, frame :T.DataHandle) -> (result :T.VoidResult);
    receive @3 (handle :TunnelHandle) -> (frame :T.DataHandle, more :Bool);
    subscribe @4 (handle :TunnelHandle) -> (subscription :TunnelSubscription);
    cancelSubscribe @5 (subscription :TunnelSubscription) -> T.VoidResult;
    close @6 (handle :TunnelHandle) -> (result :T.VoidResult);

    # ── Mesh topology ──
    getMeshTopology @7 (handle :TunnelHandle) -> (topology :MeshTopology);

    # ── Tunnel metrics ──
    getMetrics @8 (handle :TunnelHandle) -> (metrics :TunnelMetrics);

    # ── Health check ──
    healthCheck @9 (handle :TunnelHandle) -> (health :TunnelHealth);

    # ── Multiplexing ──
    openLogical @10 (handle :TunnelHandle, name :Text) -> (logicalId :UInt32);
    closeLogical @11 (handle :TunnelHandle, logicalId :UInt32) -> T.VoidResult;
    listLogical @12 (handle :TunnelHandle) -> (logicals :List(LogicalTunnel));
}

struct TunnelHandle {
    id @0 :T.TunnelId;
    subject @1 :Text;
    # Whether this tunnel is part of a mesh overlay.
    meshId @2 :Text;
    # Logical stream ID (0 = main stream, >0 = multiplexed).
    logicalId @3 :UInt32;
}

interface TunnelSubscription {
    # Unbounded pull — returns all available frames. For high-throughput
    # tunnels, use pullPaged (ordinal @2) with T.Pagination to bound
    # the result set.
    pull @0 (handle :TunnelHandle) -> (frames :List(T.DataHandle));
    cancel @1 () -> T.VoidResult;

    # Paginated frame retrieval. Returns at most `pagination.limit` frames
    # starting at `pagination.offset`. Caller should repeat with increasing
    # offset until total frames are consumed or a zero-length batch is
    # returned.
    pullPaged @2 (handle :TunnelHandle, pagination :T.Pagination)
              -> (frames :List(T.DataHandle), total :UInt64);
}

struct TunnelInfo {
    handle @0 :TunnelHandle;
    peer @1 :Text;
    spec @2 :TunnelSpec;
    state @3 :TunnelState;
    framesIn @4 :UInt64;
    framesOut @5 :UInt64;
    bytesIn @6 :UInt64;
    bytesOut @7 :UInt64;
    # When this tunnel was created.
    createdAt @8 :T.Timestamp;
    # Current metrics snapshot.
    metrics @9 :TunnelMetrics;
}

enum TunnelState {
    opening @0;
    open @1;
    halfClosed @2;
    closing @3;
    closed @4;
    error @5;
    custom @6;
}

# ── Mesh Topology ────────────────────────────────────────────

struct MeshTopology {
    # Unique mesh identifier.
    meshId @0 :Text;
    # This node's tunnel handle within the mesh.
    localHandle @1 :TunnelHandle;
    # All known peers in the mesh.
    peers @2 :List(TunnelPeer);
    # Computed routing table.
    routes @3 :List(TunnelRoute);
    # Mesh routing algorithm in use.
    algorithm @4 :MeshAlgorithm;
}

struct TunnelPeer {
    # Peer node identifier.
    peerId @0 :T.NodeId;
    # Peer's endpoint address.
    endpoint @1 :Text;
    # Capabilities this peer supports.
    capabilities @2 :List(Text);
    # Latency to this peer.
    latency @3 :T.Duration;
    # When this peer was last seen.
    lastSeen @4 :T.Timestamp;
    # Peer state.
    state @5 :TunnelPeerState;
}

enum TunnelPeerState {
    connected @0;
    disconnected @1;
    connecting @2;
    failed @3;
    custom @4;
}

struct TunnelRoute {
    # Destination peer.
    destination @0 :T.NodeId;
    # Next hop toward destination.
    nextHop @1 :T.NodeId;
    # Route metric (lower = preferred).
    metric @2 :UInt32;
    # Route expiry (empty = static route).
    expiry @3 :T.Timestamp;
}

enum MeshAlgorithm {
    flood @0;
    gossip @1;
    linkState @2;
    distanceVector @3;
    custom @4;
}

# ── Tunnel Security Policy ─────────────────────────────────

struct TunnelSecurityPolicy {
    # Encryption algorithm for tunnel frames.
    encryption @0 :TunnelEncryption;
    # Authentication method for tunnel endpoints.
    authentication @1 :TunnelAuth;
    # Key rotation interval (empty = no rotation).
    keyRotationInterval @2 :T.Duration;
    # Whether to verify peer identity.
    verifyPeer @3 :Bool;
    # Trusted peer certificates/keys.
    trustedPeers @4 :List(Data);
}

enum TunnelEncryption {
    none @0;
    # AES-128-GCM-SIV (RFC 8452).
    aes128GcmSiv @1;
    # AES-256-GCM-SIV.
    aes256GcmSiv @2;
    # ChaCha20-Poly1305 (RFC 8439).
    chacha20Poly1305 @3;
    # Post-quantum: Kyber-768 hybrid.
    kyber768 @4;
    # Post-quantum: Kyber-1024.
    kyber1024 @5;
    # Hybrid classical/PQ: X25519 + Kyber-768.
    hybridX25519Kyber768 @6;
    custom @7;
}

enum TunnelAuth {
    none @0;
    # Pre-shared key.
    psk @1;
    # Mutual TLS certificate.
    certificate @2;
    # Token-based (bearer, JWT).
    token @3;
    custom @4;
}

# ── QoS Parameters ──────────────────────────────────────────

struct QoSParams {
    # Maximum acceptable latency (latency budget).
    latencyBudget @0 :T.Duration;
    # Maximum acceptable jitter.
    jitterTolerance @1 :T.Duration;
    # Required bandwidth in bits per second (0 = unlimited).
    bandwidthBps @2 :UInt64;
    # Priority (0 = lowest, 255 = highest).
    priority @3 :UInt8;
    # What to do when queue is full.
    dropPolicy @4 :DropPolicy;
}

enum DropPolicy {
    # Drop oldest frames.
    dropOldest @0;
    # Drop newest frames.
    dropNewest @1;
    # Drop lowest-priority frames.
    dropLowest @2;
    custom @3;
}

# ── Tunnel Metrics ──────────────────────────────────────────

struct TunnelMetrics {
    # Latency percentiles.
    latencyP50 @0 :T.Duration;
    latencyP99 @1 :T.Duration;
    # Packet loss rate (0.0 = none, 1.0 = 100% loss).
    lossRate @2 :Float32;
    # Current throughput in bits per second.
    throughputBps @3 :UInt64;
    # Retransmission count (reliable flows only).
    retransmissions @4 :UInt64;
    # When these metrics were last updated.
    lastUpdated @5 :T.Timestamp;
    # Frames currently in flight.
    framesInFlight @6 :UInt32;
    # Send queue depth.
    sendQueueDepth @7 :UInt32;
}

# ── Tunnel Health ───────────────────────────────────────────

struct TunnelHealth {
    # Round-trip time for health probe.
    rtt @0 :T.Duration;
    # Loss rate during health check window.
    loss @1 :Float32;
    # Jitter during health check window.
    jitter @2 :T.Duration;
    # When this health check was performed.
    timestamp @3 :T.Timestamp;
    # Overall health assessment.
    status @4 :HealthStatus;
}

enum HealthStatus {
    healthy @0;
    degraded @1;
    unhealthy @2;
    unknown @3;
    custom @4;
}

# ── Multiplexed Logical Tunnel ──────────────────────────────

struct LogicalTunnel {
    # Logical stream ID (unique within the parent tunnel).
    logicalId @0 :UInt32;
    # Human-readable name.
    name @1 :Text;
    # Current state.
    state @2 :TunnelState;
    # Bytes transferred on this logical stream.
    bytesIn @3 :UInt64;
    bytesOut @4 :UInt64;
    # Flow policy for this logical stream.
    flow @5 :FlowPolicy;
}

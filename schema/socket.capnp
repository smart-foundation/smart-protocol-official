@0xa1b2c3d4e5f60042;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Socket - network socket API (TCP, UDP, SCTP, Unix domain).
#
# Improvements beyond the original schema (audit):
#   - SocketKind extended with sctp, dccp.
#   - IPv4-mapped IPv6 addresses (critical for dual-stack).
#   - SocketFlags struct (nonBlock, cloexec — generic, not POSIX).
#   - SocketInfo includes latencyMs, mtu, localPort, error.
#   - connectWithDeadline (timeout for connection setup).
#   - shutdownEmergency for hard close.
#   - pendingConnect for non-blocking connect status.
#   - pending / ready methods for polling.
#   - SocketHandle.id uses T.SocketId (was raw UInt64).
#   - SocketInfo.error uses T.Error (was raw UInt32).
#   - SocketKind and ConnectionState have custom variants.
#   - latencyMs has unit comment (milliseconds).
#   - KeepAlive timeout fields use T.Duration (was raw UInt32).
#   - send/receive use T.DataHandle for large payloads.
#   - ShutdownHow has custom variant.
#   - SocketAddress union has custom variant.
#
# Audit-7 improvements:
#   - QoS/priority option for real-time traffic (TOS, DSCP, ECN).
#   - getSocketName/getPeerName for address introspection.
#   - Socket event subscription for state change notifications.
#   - closeGracefully for clean teardown with timeout.
#   - Socket proxy routing (SOCKS5, HTTP CONNECT).
#   - Socket multicast support.
#   - Socket compression option.
#   - Socket rate limiting for server sockets.
#
# Audit-9 improvements:
#   - TLS session integration (wrapTls/unwrapTls).
#   - Congestion control algorithm selection.
#   - TLS session ticket support for resumption.
#   - Real-time bandwidth measurement sampling.
#   - Socket pcap/traffic capture for debugging.
# ═══════════════════════════════════════════════════════════════════════

# ── Address Types ──────────────────────────────────────────────────────

struct SocketAddress {
    union {
        ipv4 @0 :Ipv4Address;
        ipv6 @1 :Ipv6Address;
        ipv4Mapped @3 :Ipv4MappedIpv6Address;
        unix @2 :UnixAddress;
        custom @4 :Data;
    }
}

struct Ipv4Address {
    octets @0 :Data;
    port @1 :UInt16;
}

struct Ipv6Address {
    octets @0 :Data;
    port @1 :UInt16;
    flowInfo @2 :UInt32;
    scopeId @3 :UInt32;
}

# IPv4-mapped IPv6: ::ffff:192.0.2.1 — critical for dual-stack.
struct Ipv4MappedIpv6Address {
    ipv4Octets @0 :Data;
    port @1 :UInt16;
    # Flow info / scope id are zero for mapped addresses.
}

struct UnixAddress {
    abstract @0 :Data;
    path @1 :Text;
}

# ── Socket Handles ──────────────────────────────────────────────────────

struct SocketHandle {
    id @0 :T.SocketId;
}

# ── Options ─────────────────────────────────────────────────────────────

struct SocketOption {
    union {
        keepAlive @0 :KeepAliveOption;
        linger @1 :LingerOption;
        sendBufferSize @2 :UInt32;
        recvBufferSize @3 :UInt32;
        reuseAddress @4 :Bool;
        reusePort @5 :Bool;
        noDelay @6 :Bool;
        broadcast @7 :Bool;
        dontRoute @8 :Bool;
        keepAliveTime @9 :T.Duration;
        keepAliveInterval @10 :T.Duration;
        keepAliveCount @11 :UInt32;
        custom @12 :CustomOption;
        # QoS / traffic prioritization (TOS, DSCP, ECN).
        qos @13 :QosOption;
        # Enable multiplexing on this socket.
        multiplex @14 :Bool;
        # Number of keepalive probes before declaring dead.
        keepAliveProbes @15 :UInt32;
        # Proxy routing configuration.
        proxy @16 :ProxyRoute;
        # Compression algorithm for socket data.
        compression @17 :CompressionOption;
        # Rate limiting for server sockets.
        rateLimit @18 :RateLimitOption;
        # Multicast group membership.
        multicast @19 :MulticastGroup;
    }
}

struct KeepAliveOption {
    enabled @0 :Bool;
    idleTime @1 :T.Duration;
    interval @2 :T.Duration;
    count @3 :UInt32;
}

struct LingerOption {
    enabled @0 :Bool;
    timeout @1 :T.Duration;
}

struct CustomOption {
    key @0 :Text;
    value @1 :Data;
}

# ── QoS Option ──────────────────────────────────────────────────────────

struct QosOption {
    # Traffic class (maps to IP_TOS / SO_PRIORITY).
    trafficClass @0 :TrafficClass;
    # 802.1p priority (0-7).
    priority @1 :UInt8;
    # DSCP value (0-63).
    dscp @2 :UInt8;
    # ECN codepoint (0-3).
    ecn @3 :UInt8;
}

enum TrafficClass {
    bestEffort @0;
    controlledLoad @1;
    guaranteed @2;
    networkControl @3;
    streaming @4;
    interactive @5;
    custom @6;
}

# ── Proxy Route ─────────────────────────────────────────────────────────

struct ProxyRoute {
    # Proxy type.
    type @0 :ProxyType;
    # Proxy address.
    address @1 :T.IpAddress;
    port @2 :T.Port;
    # Authentication for proxy.
    username @3 :Text;
    password @4 :Text;
    # Bypass rules: domains/IPs that bypass the proxy.
    bypass @5 :List(Text);
    # Connection timeout to proxy.
    timeout @6 :T.Duration;
}

enum ProxyType {
    none @0;
    socks4 @1;
    socks5 @2;
    socks5h @3;
    httpConnect @4;
    httpsConnect @5;
    transparent @6;
    custom @7;
}

# ── Compression Option ─────────────────────────────────────────────────

struct CompressionOption {
    # Whether compression is enabled.
    enabled @0 :Bool;
    # Compression algorithm.
    algorithm @1 :CompressionAlgorithm;
    # Minimum payload size to compress (below this, send uncompressed).
    minPayloadSize @2 :UInt32;
    # Compression level (1 = fastest, 9 = best compression).
    level @3 :UInt8;
}

enum CompressionAlgorithm {
    none @0;
    gzip @1;
    zstd @2;
    lz4 @3;
    snappy @4;
    custom @5;
}

# ── Rate Limit Option ──────────────────────────────────────────────────

struct RateLimitOption {
    # Maximum connections per second.
    maxConnectionsPerSecond @0 :UInt32;
    # Maximum bytes per second (0 = unlimited).
    maxBytesPerSecond @1 :UInt64;
    # Burst size.
    burstSize @2 :UInt32;
    # Whether rate limiting is enabled.
    enabled @3 :Bool;
}

# ── Multicast Group ────────────────────────────────────────────────────

struct MulticastGroup {
    # Multicast group address.
    groupAddress @0 :T.IpAddress;
    # Local interface to bind to.
    interfaceAddress @1 :T.IpAddress;
    # Multicast TTL.
    ttl @2 :UInt8;
    # Whether to enable loopback.
    loopback @3 :Bool;
}

# ── Socket Flags ────────────────────────────────────────────────────────

struct SocketFlags {
    nonBlock @0 :Bool;
    cloexec @1 :Bool;
    shared @2 :Bool;
    exclusive @3 :Bool;
}

# ── Connection Info ─────────────────────────────────────────────────────

struct SocketInfo {
    handle @0 :SocketHandle;
    kind @1 :SocketKind;
    localAddress @2 :SocketAddress;
    remoteAddress @3 :SocketAddress;
    localPort @4 :UInt16;
    state @5 :ConnectionState;
    options @6 :List(SocketOption);
    bytesSent @7 :UInt64;
    bytesReceived @8 :UInt64;
    # Round-trip latency in milliseconds (for connected sockets).
    latencyMs @9 :UInt32;
    # Path MTU in bytes (for UDP or connected TCP).
    mtu @10 :UInt32;
    # Last socket-level error.
    error @11 :T.Error;
}

enum SocketKind {
    tcp @0;
    udp @1;
    sctp @2;
    dccp @3;
    raw @4;
    custom @5;
}

enum ConnectionState {
    unconnected @0;
    connecting @1;
    connected @2;
    listening @3;
    disconnected @4;
    error @5;
    custom @6;
}

# ── Service Interface ────────────────────────────────────────────────────

interface SocketService {
    create @0 (kind :SocketKind) -> (handle :SocketHandle);

    bind @1 (handle :SocketHandle, address :SocketAddress) -> T.VoidResult;

    listen @2 (handle :SocketHandle, backlog :UInt32) -> T.VoidResult;

    accept @3 (handle :SocketHandle) -> (accepted :SocketHandle, remoteAddress :SocketAddress);

    connect @4 (handle :SocketHandle, address :SocketAddress) -> T.VoidResult;

    # Connect with a deadline (wall-clock timeout).
    connectWithDeadline @9 (handle :SocketHandle, address :SocketAddress, deadline :T.Timestamp) -> T.VoidResult;

    # Check if a non-blocking connect is still in progress.
    pendingConnect @10 (handle :SocketHandle) -> (pending :Bool);

    send @5 (handle :SocketHandle, data :T.DataHandle) -> (sent :UInt32);
    sendTo @6 (handle :SocketHandle, data :T.DataHandle, destination :SocketAddress) -> (sent :UInt32);

    receive @7 (handle :SocketHandle, maxLength :UInt32) -> (data :T.DataHandle);
    receiveFrom @8 (handle :SocketHandle, maxLength :UInt32) -> (data :T.DataHandle, source :SocketAddress);

    getInfo @11 (handle :SocketHandle) -> (info :SocketInfo);

    setOption @12 (handle :SocketHandle, option :SocketOption) -> T.VoidResult;
    getOption @13 (handle :SocketHandle, option :SocketOption) -> (option :SocketOption);

    # Set socket-level flags.
    setFlags @14 (handle :SocketHandle, flags :SocketFlags) -> T.VoidResult;
    getFlags @15 (handle :SocketHandle) -> (flags :SocketFlags);

    shutdown @16 (handle :SocketHandle, how :ShutdownHow) -> T.VoidResult;
    # Hard close without grace.
    shutdownEmergency @17 (handle :SocketHandle) -> T.VoidResult;

    close @18 (handle :SocketHandle) -> T.VoidResult;

    # ── Address introspection ──
    # Get the local address/port assigned after bind (useful for ephemeral ports).
    getSocketName @19 (handle :SocketHandle) -> (address :SocketAddress, port :UInt16);
    # Get the remote address after connect.
    getPeerName @20 (handle :SocketHandle) -> (address :SocketAddress, port :UInt16);

    # ── Graceful close ──
    # Close with a timeout: flush pending data, then close.
    closeGracefully @21 (handle :SocketHandle, timeout :T.Duration) -> T.VoidResult;

    # ── Event subscription ──
    # Subscribe to socket state changes (connected, disconnected, error).
    subscribeEvents @22 (handle :SocketHandle) -> (subscription :SocketEventSubscription);

    # ── TLS integration ──
    wrapTls @23 (handle :SocketHandle, serverName :Text) -> (tlsSession :TlsSession);
    unwrapTls @24 (handle :SocketHandle) -> T.VoidResult;

    # ── Congestion control ──
    getCongestionControl @25 (handle :SocketHandle) -> (config :CongestionControl);
    setCongestionControl @26 (handle :SocketHandle, config :CongestionControl) -> T.VoidResult;

    # ── Bandwidth measurement ──
    getBandwidthSample @27 (handle :SocketHandle) -> (sample :BandwidthSample);

    # ── Pcap capture ──
    startPcapCapture @28 (handle :SocketHandle, filePath :Text) -> (session :PcapSession);
    stopPcapCapture @29 (handle :SocketHandle) -> T.VoidResult;

    # ── Session ticket ──
    getSessionTicket @30 (handle :SocketHandle) -> (ticket :SessionTicket);
    setSessionTicket @31 (handle :SocketHandle, ticket :SessionTicket) -> T.VoidResult;

    # ── Session ticket store ──
    getSessionTicketStore @32 (serverName :Text) -> (tickets :List(SessionTicket));
    addSessionTicket @33 (handle :SocketHandle, ticket :SessionTicket) -> T.VoidResult;
    removeSessionTicket @34 (handle :SocketHandle, ticket :SessionTicket) -> T.VoidResult;
    clearSessionTickets @35 (handle :SocketHandle) -> T.VoidResult;

    # ── SCTP options ──
    setSctpOptions @36 (handle :SocketHandle, options :SctpOptions) -> T.VoidResult;
    getSctpOptions @37 (handle :SocketHandle) -> (options :SctpOptions);
}

enum ShutdownHow {
    read @0;
    write @1;
    both @2;
    custom @3;
}

# ── Socket Event Subscription ───────────────────────────────────────────

interface SocketEventSubscription {
    pull @0 () -> (event :SocketEvent);
    cancel @1 () -> T.VoidResult;
}

struct SocketEvent {
    # When this event occurred.
    timestamp @0 :T.Timestamp;
    union {
        stateChanged @1 :SocketStateChange;
        error @2 :T.Error;
        # Backend-specific socket event.
        custom @3 :Data;
    }
}

struct SocketStateChange {
    oldState @0 :ConnectionState;
    newState @1 :ConnectionState;
}

# ── TLS Session ─────────────────────────────────────────────────────────

struct TlsSession {
    # TLS version in use.
    version @0 :T.TlsVersion;
    # Cipher suite name.
    cipherSuite @1 :Text;
    # Whether session was resumed via ticket.
    resumed @2 :Bool;
    # Peer certificate data.
    peerCertificate @3 :Data;
}

# ── Congestion Control ─────────────────────────────────────────────────

struct CongestionControl {
    # Algorithm name (cubic, bbr, reno, etc.).
    algorithm @0 :CongestionAlgorithm;
    # Whether congestion control is enabled.
    enabled @1 :Bool;
}

enum CongestionAlgorithm {
    cubic @0;
    bbr @1;
    reno @2;
    vegas @3;
    bic @4;
    custom @5;
}

# ── Bandwidth Measurement ──────────────────────────────────────────────

struct BandwidthSample {
    # Throughput in bytes per second (instantaneous).
    bytesPerSecond @0 :UInt64;
    # Throughput in bits per second.
    bitsPerSecond @1 :UInt64;
    # Sample timestamp.
    timestamp @2 :T.Timestamp;
    # Sample window duration.
    window @3 :T.Duration;
}

# ── TLS Session Ticket ─────────────────────────────────────────────────

struct SessionTicket {
    # Session ticket data.
    ticket @0 :Data;
    # When this ticket expires.
    expiresAt @1 :T.Timestamp;
    # Associated server name.
    serverName @2 :Text;
}

# ── Pcap Session ────────────────────────────────────────────────────────

struct PcapSession {
    # Session identifier.
    sessionId @0 :Data;
    # Capture file path.
    filePath @1 :Text;
    # Whether capture is currently active.
    active @2 :Bool;
    # Packets captured so far.
    packetsCaptured @3 :UInt64;
}

# ── SCTP Options ──────────────────────────────────────────────────────

struct SctpOptions {
    # Number of outbound streams.
    outboundStreams @0 :UInt16;
    # Number of inbound streams.
    inboundStreams @1 :UInt16;
    # Whether to use ordered delivery.
    ordered @2 :Bool = true;
    # Maximum message size in bytes.
    maxMessageSize @3 :UInt32;
    # fragmentation threshold.
    fragmentationThreshold @4 :UInt32;
    # Heartbeat interval.
    heartbeatInterval @5 :T.Duration;
    # RTO initial value.
    rtoInitial @6 :T.Duration;
    # RTO minimum.
    rtoMin @7 :T.Duration;
    # RTO maximum.
    rtoMax @8 :T.Duration;
}

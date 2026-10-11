@0xa1b2c3d4e5f60042;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Socket — the connection contract, and the CANONICAL HOME for channel
# security in this protocol.
#
# Why security lives here: a connection's trust configuration belongs to
# the thing that establishes the connection. TLS configuration used to
# exist in three places with three shapes (this file's `TlsSession`,
# endpoint.capnp's `TlsConfig`/`TlsVersion`, and nothing at all in
# web.capnp, where `wss://` implied TLS the URL only). It now exists
# once, here; `endpoint.capnp` and `web.capnp` reference this type.
#
# Core of the contract: create/bind/listen/accept/connect/send/receive
# over `T.DataHandle`, measured options, honest deadlines, pull + cancel
# subscriptions. Options state intent; the backend maps intent onto
# whatever its stack has, and reports what it actually applied.
#
# Design rules applied:
#   - No POSIX flag names. The old `SocketFlags` carried `cloexec`
#     (close-on-exec: an exec semantic, not a socket semantic) and
#     `shared`/`exclusive` (file-lock semantics) in a struct whose own
#     comment claimed "generic, not POSIX".
#   - No algorithm hints as enums. Congestion control, compression and
#     traffic class are open tokens: a 2046 stack's algorithm is a
#     string, and the protocol reports what the stack uses rather than
#     instructing it (TIMELESSNESS.md:84).
#   - `receive` can say "nothing yet" without the caller polling.
#   - A capture sink is not a filesystem path: pcap output is a
#     path/buffer/handle union so a filesystem-less backend can honor it.
# ═══════════════════════════════════════════════════════════════════════

# ── Channel Security: the canonical TLS home ──────────────────────────

struct TlsConfig {
    # Whether channel security is required for this connection.
    enabled @0 :Bool = true;

    # Version bounds as open tokens ("tls12", "tls13", ...). A 2046
    # version is a string with unknown-tolerance; an unrecognized token
    # is ignored by a consumer that cannot act on it.
    minVersion @1 :Text;
    maxVersion @2 :Text;

    # Cipher suites as open tokens (empty = backend defaults).
    cipherSuites @3 :List(Text);

    # Application protocols for ALPN ("h2", "h3", ...).
    alpn @4 :List(Text);

    # Server name for SNI and certificate validation.
    serverName @5 :Text;

    # How the peer certificate is treated. See "what wss:// means" below.
    verifyMode @6 :VerifyMode = verifyPeer;

    # Trust anchors as content (PEM/DER), not as paths.
    trustAnchors @7 :List(T.DataHandle);

    # Client certificate and key for mutual TLS, as content.
    clientCert @8 :T.DataHandle;
    clientKey @9 :T.DataHandle;

    revocationCheck @10 :RevocationCheck;

    # Certificate pins for this configuration.
    pins @11 :List(CertificatePin);

    metadata @12 :T.StringMap;
}

enum VerifyMode {
    unknown @0;
    verifyNone @1;
    verifyPeer @2;
    verifyPeerOnce @3;
    custom @4;
}

enum RevocationCheck {
    unknown @0;
    none @1;
    crl @2;
    ocsp @3;
    ocspStapling @4;
    custom @5;
}

struct CertificatePin {
    # Pinning algorithm as an open token ("sha256").
    algorithm @0 :Text;
    # Pin over the Subject Public Key Info.
    spkiHash @1 :Data;
    expiresAt @2 :T.Timestamp;
    metadata @3 :T.StringMap;
}

# ── What `wss://` means (the semantics web.capnp delegates here) ──────
#
# A `wss://` endpoint is a TLS-protected stream socket, and its security
# requirements are the ones declared in `TlsConfig` — not ones implied by
# the URL:
#
#   1. `verifyMode` governs certificate checking. `verifyPeer` (the
#      default) requires a chain that validates against the trust
#      anchors. A backend that cannot verify MUST fail the connection;
#      silently retrying without verification is the failure mode this
#      rule exists to prevent.
#   2. `serverName` (SNI) and `pins` are the identity checks available to
#      a consumer. A connection that satisfies neither is encrypted but
#      not authenticated, and `verifyMode = verifyNone` is the only way
#      to say so — never an absence.
#   3. `alpn` selects the application protocol; an unknown token is
#      ignored, so a future protocol needs no schema change.
#   4. `trustAnchors`, `clientCert` and `clientKey` are content
#      (T.DataHandle), never file paths: a browser runtime or an
#      in-memory backend has no filesystem to read them from.
#
# The same configuration applies to `https://` fetches and to any other
# scheme that implies a secure channel; the scheme's meaning is defined
# once, here, rather than per schema.

# ── Datagram security (DTLS) ──────────────────────────────────────────

struct DtlsConfig {
    enabled @0 :Bool = true;
    minVersion @1 :Text;
    maxVersion @2 :Text;
    cipherSuites @3 :List(Text);
    verifyMode @4 :VerifyMode = verifyPeer;
    trustAnchors @5 :List(T.DataHandle);
    clientCert @6 :T.DataHandle;
    clientKey @7 :T.DataHandle;
    # Maximum transmission unit for the datagram channel.
    mtu @8 :UInt16;
    pins @9 :List(CertificatePin);
    metadata @10 :T.StringMap;
}

# ── Address Types ──────────────────────────────────────────────────────
# A socket address is a host/port pair, a name, or opaque bytes — the
# same three shapes endpoint.capnp uses, so an address means the same
# thing at both layers.

struct SocketAddress {
    union {
        network @0 :SocketNetworkAddress;
        # A named peer: a filesystem socket path, an abstract-socket
        # name, a bus name. Names avoid naming any OS's namespace.
        named @1 :Text;
        custom @2 :Data;
    }
}

struct SocketNetworkAddress {
    host @0 :T.IpAddress;
    port @1 :T.Port;
    # IPv6 scope id for link-local addresses (0 otherwise).
    scopeId @2 :UInt32;
    metadata @3 :T.StringMap;
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

        # Quality-of-service intent. The class is an open token: what a
        # backend does with it is its own business.
        qos @13 :QosOption;

        # Connection routing through a proxy.
        proxy @14 :ProxyConfig;

        # Whether the channel compresses, with an open algorithm token.
        compression @15 :CompressionOption;

        # Rate limiting for listening sockets.
        rateLimit @16 :RateLimitOption;

        # Multicast group membership.
        multicast @17 :MulticastGroup;

        # Channel security for this connection (the canonical TLS home).
        tls @18 :TlsConfig;
        dtls @19 :DtlsConfig;
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
    # Open traffic-class token ("bestEffort", "controlledLoad", ...).
    trafficClass @0 :Text;
    # 802.1p priority (0-7).
    priority @1 :UInt8;
    # DSCP value (0-63).
    dscp @2 :UInt8;
    # ECN codepoint (0-3).
    ecn @3 :UInt8;
    metadata @4 :T.StringMap;
}

# ── Proxy (canonical home; endpoint.capnp and web.capnp reference it) ──

struct ProxyConfig {
    # Open proxy-type token ("socks5", "httpConnect", ...).
    type @0 :Text;
    address @1 :T.IpAddress;
    port @2 :T.Port;
    # Credentials as opaque content — a secret never crosses the wire as
    # a bare Text field the schema invites callers to fill in.
    credential @3 :T.DataHandle;
    # Hosts that bypass the proxy.
    bypass @4 :List(Text);
    # Connection timeout to the proxy.
    timeout @5 :T.Duration;
    metadata @6 :T.StringMap;
}

# ── Compression Option ─────────────────────────────────────────────────

struct CompressionOption {
    enabled @0 :Bool;
    # Open algorithm token ("gzip", "zstd", "lz4", ...).
    algorithm @1 :Text;
    # Minimum payload size to compress (below this, send uncompressed).
    minPayloadSize @2 :UInt32;
    # Compression level.
    level @3 :UInt8;
    metadata @4 :T.StringMap;
}

# ── Rate Limit Option ──────────────────────────────────────────────────

struct RateLimitOption {
    maxConnectionsPerSecond @0 :UInt32;
    # Maximum bytes per second (0 = unlimited).
    maxBytesPerSecond @1 :UInt64;
    burstSize @2 :UInt32;
    enabled @3 :Bool;
}

# ── Multicast Group ────────────────────────────────────────────────────

struct MulticastGroup {
    groupAddress @0 :T.IpAddress;
    interfaceAddress @1 :T.IpAddress;
    ttl @2 :UInt8;
    loopback @3 :Bool;
    metadata @4 :T.StringMap;
}

# ── Socket Flags ────────────────────────────────────────────────────────
# Lifecycle intent only. The POSIX spellings this struct used to carry
# (`cloexec` — close-on-exec, an exec semantic; `shared`/`exclusive` —
# file-lock semantics) are gone: a capability runtime has no exec table
# and no advisory file locks to configure through a socket.

struct SocketFlags {
    # Whether operations on this socket do not block the caller.
    nonBlocking @0 :Bool;
    # Whether the socket survives after the creating reference is gone.
    durable @1 :Bool;
    # Whether other holders may use this socket concurrently.
    shared @2 :Bool;
}

# ── Connection Info ─────────────────────────────────────────────────────

struct SocketInfo {
    handle @0 :SocketHandle;
    # Socket kind as an open token ("stream", "datagram", "seqpacket",
    # "raw", ...): the transport is chosen by the address, the kind
    # states the semantics the caller asked for.
    kind @1 :Text;
    localAddress @2 :SocketAddress;
    remoteAddress @3 :SocketAddress;
    localPort @4 :UInt16;
    state @5 :ConnectionState;
    options @6 :List(SocketOption);
    bytesSent @7 :UInt64;
    bytesReceived @8 :UInt64;
    # Measured round-trip latency (absent when not measured).
    latency @9 :T.Duration;
    latencyMeasured @10 :Bool;
    # Path MTU in bytes, if known.
    mtu @11 :UInt32;
    mtuKnown @12 :Bool;
    # Last socket-level error.
    error @13 :T.Error;
    # Channel security in force, if any.
    security @14 :TlsConfig;
    metadata @15 :T.StringMap;
}

enum ConnectionState {
    unknown @0;
    unconnected @1;
    connecting @2;
    connected @3;
    listening @4;
    disconnected @5;
    error @6;
    custom @7;
}

# ── Service Interface ────────────────────────────────────────────────────

interface SocketService {
    create @0 (kind :Text) -> (handle :SocketHandle);

    bind @1 (handle :SocketHandle, address :SocketAddress) -> T.VoidResult;

    listen @2 (handle :SocketHandle, backlog :UInt32) -> T.VoidResult;

    accept @3 (handle :SocketHandle) -> (accepted :SocketHandle, remoteAddress :SocketAddress);

    connect @4 (handle :SocketHandle, address :SocketAddress) -> T.VoidResult;

    # Connect with a deadline (wall-clock timeout).
    connectWithDeadline @5 (handle :SocketHandle, address :SocketAddress, deadline :T.Timestamp) -> T.VoidResult;

    # Check whether a non-blocking connect is still in progress.
    pendingConnect @6 (handle :SocketHandle) -> (pending :Bool);

    send @7 (handle :SocketHandle, data :T.DataHandle) -> (sent :UInt32);
    sendTo @8 (handle :SocketHandle, data :T.DataHandle, destination :SocketAddress) -> (sent :UInt32);

    # `wouldBlock` says "nothing available yet" so a non-blocking caller
    # is not pushed into a poll loop; `closed` distinguishes an orderly
    # shutdown from an empty queue.
    receive @9 (handle :SocketHandle, maxLength :UInt32)
            -> (data :T.DataHandle, wouldBlock :Bool, closed :Bool);
    receiveFrom @10 (handle :SocketHandle, maxLength :UInt32)
                -> (data :T.DataHandle, source :SocketAddress, wouldBlock :Bool, closed :Bool);

    getInfo @11 (handle :SocketHandle) -> (info :SocketInfo);

    setOption @12 (handle :SocketHandle, option :SocketOption) -> T.VoidResult;
    getOption @13 (handle :SocketHandle, option :SocketOption) -> (option :SocketOption);

    setFlags @14 (handle :SocketHandle, flags :SocketFlags) -> T.VoidResult;
    getFlags @15 (handle :SocketHandle) -> (flags :SocketFlags);

    shutdown @16 (handle :SocketHandle, how :ShutdownHow) -> T.VoidResult;

    close @17 (handle :SocketHandle) -> T.VoidResult;

    # Close with a timeout: flush pending data, then close.
    closeGracefully @18 (handle :SocketHandle, timeout :T.Duration) -> T.VoidResult;

    # ── Address introspection ──
    getSocketName @19 (handle :SocketHandle) -> (address :SocketAddress, port :UInt16);
    getPeerName @20 (handle :SocketHandle) -> (address :SocketAddress, port :UInt16);

    # ── Event subscription ──
    # State changes AND readability. A readable event is what lets a
    # consumer wait instead of poll `receive`.
    subscribeEvents @21 (handle :SocketHandle) -> (subscription :SocketEventSubscription);

    # ── TLS integration ──
    # Wrap the connection with the given security configuration. The
    # configuration is the canonical one defined in this file.
    wrapTls @22 (handle :SocketHandle, config :TlsConfig) -> (tlsSession :TlsSession);
    unwrapTls @23 (handle :SocketHandle) -> T.VoidResult;

    # What the stack is actually using — reported, not instructed.
    getCongestionControl @24 (handle :SocketHandle) -> (config :CongestionControl);

    # ── Bandwidth measurement ──
    getBandwidthSample @25 (handle :SocketHandle) -> (sample :BandwidthSample);

    # ── Capture ──
    startPcapCapture @26 (handle :SocketHandle, sink :CaptureSink) -> (session :PcapSession);
    stopPcapCapture @27 (handle :SocketHandle) -> T.VoidResult;

    # ── Session tickets ──
    getSessionTicket @28 (handle :SocketHandle) -> (ticket :SessionTicket);
    setSessionTicket @29 (handle :SocketHandle, ticket :SessionTicket) -> T.VoidResult;
    getSessionTicketStore @30 (serverName :Text, pagination :T.Pagination)
                         -> (tickets :List(SessionTicket), totalCount :UInt64);
    addSessionTicket @31 (handle :SocketHandle, ticket :SessionTicket) -> T.VoidResult;
    removeSessionTicket @32 (handle :SocketHandle, ticket :SessionTicket) -> T.VoidResult;
    clearSessionTickets @33 (handle :SocketHandle) -> T.VoidResult;

    # ── SCTP options ──
    setSctpOptions @34 (handle :SocketHandle, options :SctpOptions) -> T.VoidResult;
    getSctpOptions @35 (handle :SocketHandle) -> (options :SctpOptions);
}

enum ShutdownHow {
    unknown @0;
    read @1;
    write @2;
    both @3;
    custom @4;
}

# ── Socket Event Subscription ───────────────────────────────────────────

interface SocketEventSubscription {
    pull @0 () -> (events :List(SocketEvent));
    cancel @1 () -> T.VoidResult;
}

struct SocketEvent {
    timestamp @0 :T.Timestamp;
    union {
        stateChanged @1 :SocketStateChange;
        # The socket has data to read — the event that makes waiting
        # possible instead of polling.
        readable @2 :Void;
        # The peer closed the write side.
        readClosed @3 :Void;
        error @4 :T.Error;
        custom @5 :Data;
    }
}

struct SocketStateChange {
    oldState @0 :ConnectionState;
    newState @1 :ConnectionState;
}

# ── TLS Session ─────────────────────────────────────────────────────────

struct TlsSession {
    # Version in force, as an open token.
    version @0 :Text;
    # Cipher suite in force, as an open token.
    cipherSuite @1 :Text;
    # ALPN protocol selected.
    alpn @2 :Text;
    # Whether the session was resumed via ticket.
    resumed @3 :Bool;
    # Peer certificate chain, as content.
    peerCertificate @4 :T.DataHandle;
    # Whether the peer's certificate was verified against the trust
    # anchors (false when verifyMode said not to).
    peerVerified @5 :Bool;
    metadata @6 :T.StringMap;
}

# ── Congestion Control ─────────────────────────────────────────────────

struct CongestionControl {
    # Algorithm in use, as an open token. Reported by the stack; the
    # protocol does not instruct it (TIMELESSNESS.md:84).
    algorithm @0 :Text;
    enabled @1 :Bool;
    metadata @2 :T.StringMap;
}

# ── Bandwidth Measurement ──────────────────────────────────────────────

struct BandwidthSample {
    bytesPerSecond @0 :UInt64;
    bitsPerSecond @1 :UInt64;
    timestamp @2 :T.Timestamp;
    window @3 :T.Duration;
}

# ── TLS Session Ticket ─────────────────────────────────────────────────

struct SessionTicket {
    ticket @0 :T.DataHandle;
    expiresAt @1 :T.Timestamp;
    serverName @2 :Text;
    metadata @3 :T.StringMap;
}

# ── Capture ─────────────────────────────────────────────────────────────
# A capture sink is not a filesystem path: the old signature forced a
# path, which a browser runtime or a filesystem-less backend cannot
# honor at all.

struct CaptureSink {
    union {
        path @0 :Text;
        buffer @1 :T.BufferId;
        handle @2 :T.FileHandleId;
        custom @3 :Data;
    }
}

struct PcapSession {
    sessionId @0 :Text;
    sink @1 :CaptureSink;
    active @2 :Bool;
    packetsCaptured @3 :UInt64;
    metadata @4 :T.StringMap;
}

# ── SCTP Options ──────────────────────────────────────────────────────

struct SctpOptions {
    outboundStreams @0 :UInt16;
    inboundStreams @1 :UInt16;
    ordered @2 :Bool = true;
    maxMessageSize @3 :UInt32;
    fragmentationThreshold @4 :UInt32;
    heartbeatInterval @5 :T.Duration;
    rtoInitial @6 :T.Duration;
    rtoMin @7 :T.Duration;
    rtoMax @8 :T.Duration;
    metadata @9 :T.StringMap;
}

@0xa1b2c3d4e5f60106;

using T = import "types.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Endpoint — typed endpoint addresses for service discovery.
#
# discovery.capnp ServiceDescriptor.endpoints is List(Text) with no structure.
# A typed EndpointAddress union (ipc/tcp/udp/unix/custom) enables
# transport-aware discovery and connection.
#
# Zero backend assumptions: no D-Bus, no gRPC, no Cap'n Proto RPC,
# no mDNS, no DNS-SD. Backend provides transport; protocol defines
# the address contract.
#
# Used by: discovery.capnp (ServiceDescriptor.endpoints), network.capnp
#          (connection endpoints), rpc.capnp (future)
#
# Audit-7 improvements:
#   - LoadBalancingHint for weighted endpoint selection.
#   - EndpointHealth for per-endpoint latency and error rate.
#   - SPIFFE identity for workload attestation.
#   - ConnectionPoolConfig for TCP/QUIC connection reuse.
#   - Certificate pinning for TLS/DTLS trust.
#
# Audit-9 improvements:
#   - VsockEndpoint constants (VMADDR_CID_ANY, VMADDR_CID_HOST).
#   - UnixEndpoint.bindAddress for datagram/seqpacket socket binding.
#   - ConnectionMigration struct for connection handoff.
#   - HTTP/2 and HTTP/3 specific settings in ConnectionHints.
#   - mDNS/DNS-SD service discovery integration.
# ═══════════════════════════════════════════════════════════════════════

interface EndpointService {
    # Resolve an endpoint address to connection details.
    resolve @0 (address :EndpointAddress) -> (result :ResolveResult);

    # Parse a string representation into an EndpointAddress.
    parse @1 (text :Text) -> (address :EndpointAddress);

    # Serialize an EndpointAddress to string.
    serialize @2 (address :EndpointAddress) -> (text :Text);

    # Check if an endpoint is reachable.
    checkReachable @3 (address :EndpointAddress, timeout :T.Duration) -> (reachable :Bool, latency :T.Duration);

    # Get default endpoints for a service category.
    getDefaults @4 (category :ServiceCategory) -> (endpoints :List(EndpointAddress));

    # Register a custom endpoint scheme handler.
    registerScheme @5 (scheme :Text, handler :EndpointHandler) -> T.VoidResult;

    # ── Endpoint Health ──
    getEndpointHealth @6 (address :EndpointAddress) -> (health :EndpointHealth);

    # ── Load Balancing ──
    getLoadBalancingHint @7 (address :EndpointAddress) -> (hint :LoadBalancingHint);

    # ── Connection Migration ──
    migrateConnection @8 (fromAddress :EndpointAddress, toAddress :EndpointAddress)
        -> (migration :ConnectionMigration);

    # ── mDNS/DNS-SD ──
    resolveMdnsService @9 (serviceName :Text, serviceType :Text, domain :Text)
        -> (services :List(MdnsServiceInfo), total :UInt32);
}

interface EndpointHandler {
    # Resolve custom scheme endpoint.
    resolve @0 (address :Data) -> (result :ResolveResult);
}

# ─── Endpoint Identity ───────────────────────────────────────────────

struct EndpointId { id @0 :UInt64; }

# ─── Endpoint Address Union ──────────────────────────────────────────

struct EndpointAddress {
    union {
        # IPC (Cap'n Proto RPC, D-Bus, custom IPC)
        ipc @0 :IpcEndpoint;

        # TCP connection
        tcp @1 :TcpEndpoint;

        # UDP connection
        udp @2 :UdpEndpoint;

        # Unix domain socket
        unix @3 :UnixEndpoint;

        # VSOCK (VM sockets)
        vsock @4 :VsockEndpoint;

        # WebSocket
        ws @5 :WsEndpoint;

        # QUIC
        quic @6 :QuicEndpoint;

        # In-process (same process, direct call)
        inproc @7 :InprocEndpoint;

        # Memory-mapped file (shared between processes)
        mmap @8 :MmapEndpoint;

        # Named pipe (Windows, also works as FIFO on Unix)
        namedpipe @9 :NamedpipeEndpoint;

        # Shared memory region (POSIX shm, Windows named shared memory)
        sharedmem @10 :SharedmemEndpoint;

        # Abstract namespace Unix socket (Linux)
        abstractUnix @11 :AbstractUnixEndpoint;

        # SCTP (multi-streaming transport)
        sctp @12 :SctpEndpoint;

        # Custom/opaque
        custom @13 :CustomEndpoint;
    }

    # Human-readable description.
    description @14 :Text;

    # Metadata (tags, version, capabilities, etc.).
    metadata @15 :T.StringMap;

    # Load-balancing hint for this endpoint.
    loadBalancing @16 :LoadBalancingHint;

    # SPIFFE workload identity (for zero-trust environments).
    spiffeId @17 :Text;

    # Connection pool configuration (for TCP/QUIC).
    connectionPool @18 :ConnectionPoolConfig;

    # Certificate pinning for TLS/DTLS.
    certificatePins @19 :List(CertificatePin);
}

# ─── Load Balancing Hint ─────────────────────────────────────────────

struct LoadBalancingHint {
    # Weight for weighted round-robin (higher = more traffic).
    weight @0 :UInt32;
    # Priority (lower = preferred).
    priority @1 :UInt32;
    # Whether this endpoint is currently healthy.
    healthy @2 :Bool;
    # Maximum concurrent connections (0 = unlimited).
    maxConnections @3 :UInt32;
}

# ─── Endpoint Health ──────────────────────────────────────────────────

struct EndpointHealth {
    # Whether the endpoint is reachable.
    reachable @0 :Bool;
    # Current latency.
    latency @1 :T.Duration;
    # Error rate (0.0 = none, 1.0 = all errors).
    errorRate @2 :Float32;
    # When this health check was performed.
    lastChecked @3 :T.Timestamp;
    # Health status.
    status @4 :HealthStatus;
}

enum HealthStatus {
    healthy @0;
    degraded @1;
    unhealthy @2;
    unknown @3;
    custom @4;
}

# ─── Connection Pool Config ───────────────────────────────────────────

struct ConnectionPoolConfig {
    # Maximum connections in the pool.
    maxSize @0 :UInt32;
    # Idle timeout before connection is closed.
    idleTimeout @1 :T.Duration;
    # Maximum connection lifetime.
    maxLifetime @2 :T.Duration;
    # Whether to run health checks on idle connections.
    healthCheck @3 :Bool;
    # Health check interval.
    healthInterval @4 :T.Duration;
}

# ─── Certificate Pin ──────────────────────────────────────────────────

struct CertificatePin {
    # Pinned certificate (DER-encoded).
    certificate @0 :Data;
    # Pin algorithm (e.g., "sha256").
    algorithm @1 :Text;
    # SHA-256 hash of the Subject Public Key Info (SPKI).
    spkiHash @2 :Data;
    # When this pin expires (empty = never).
    expiresAt @3 :T.Timestamp;
}

# ─── IPC Endpoint ────────────────────────────────────────────────────

struct IpcEndpoint {
    # IPC mechanism.
    mechanism @0 :IpcMechanism;

    # Service/interface name.
    service @1 :Text;

    # Instance identifier (for multiple instances).
    instance @2 :Text;

    # Object path (for D-Bus style).
    objectPath @3 :Text;

    # Bus address (for D-Bus).
    busAddress @4 :Text;

    # Capability handle (for Cap'n Proto RPC).
    capability @5 :T.CapabilityHandle;

    # Custom mechanism-specific data.
    custom @6 :Data;
}

enum IpcMechanism {
    # Cap'n Proto RPC over Unix socket
    capnp @0;

    # D-Bus
    dbus @1;

    # gRPC over Unix socket
    grpc @2;

    # Custom RPC
    custom @3;

    # Android Binder
    binder @4;

    # Windows RPC / ALPC
    alpc @5;

    # mach_msg (macOS/iOS)
    mach @6;

    # Fuchsia FIDL
    fidl @7;
}

# ─── TCP Endpoint ────────────────────────────────────────────────────

struct TcpEndpoint {
    # Host (IP address or hostname).
    host @0 :T.IpAddress;

    # Port number.
    port @1 :T.Port;

    # TLS configuration.
    tls @2 :TlsConfig;

    # Connection timeout.
    connectTimeout @3 :T.Duration;

    # Whether to use TCP_NODELAY.
    noDelay @4 :Bool = true;

    # Whether to use SO_KEEPALIVE.
    keepAlive @5 :Bool = false;

    # Keepalive parameters.
    keepAliveIdle @6 :T.Duration;
    keepAliveInterval @7 :T.Duration;
    keepAliveCount @8 :UInt32;

    # Proxy configuration.
    proxy @9 :ProxyConfig;

    # Source address to bind to.
    sourceAddress @10 :T.IpAddress;

    # Custom options.
    custom @11 :T.StringMap;

    # Connection pool configuration.
    connectionPool @12 :ConnectionPoolConfig;
}

# ─── UDP Endpoint ────────────────────────────────────────────────────

struct UdpEndpoint {
    # Host (IP address or hostname).
    host @0 :T.IpAddress;

    # Port number.
    port @1 :T.Port;

    # DTLS configuration.
    dtls @2 :DtlsConfig;

    # Bind to specific local address/port.
    bindAddress @3 :T.IpAddress;
    bindPort @4 :T.Port;

    # Multicast group to join.
    multicastGroup @5 :T.IpAddress;

    # Multicast interface.
    multicastInterface @6 :Text;

    # TTL for multicast.
    multicastTtl @7 :UInt8;

    # Whether to enable broadcast.
    broadcast @8 :Bool = false;

    # Receive buffer size.
    recvBufferSize @9 :UInt32;

    # Send buffer size.
    sendBufferSize @10 :UInt32;

    # Custom options.
    custom @11 :T.StringMap;
}

# ─── Unix Domain Socket Endpoint ─────────────────────────────────────

struct UnixEndpoint {
    # Socket path.
    path @0 :Text;

    # Socket type.
    type @1 :UnixSocketType;

    # Abstract namespace (Linux, path starts with @).
    abstract @2 :Bool;

    # Permissions for socket file (octal).
    permissions @3 :UInt32;

    # User/group ownership.
    uid @4 :UInt32;
    gid @5 :UInt32;

    # Connection timeout.
    connectTimeout @6 :T.Duration;

    # Custom options.
    custom @7 :T.StringMap;

    # Bind address for datagram/seqpacket sockets.
    bindAddress @8 :Text;
}

enum UnixSocketType {
    stream @0;      # SOCK_STREAM
    datagram @1;    # SOCK_DGRAM
    seqpacket @2;   # SOCK_SEQPACKET
}

# ─── VSOCK Endpoint ──────────────────────────────────────────────────
# VSOCK constants: VMADDR_CID_ANY = 0xFFFFFFFF (any CID for binding),
# VMADDR_CID_HOST = 2 (host context ID).

struct VsockEndpoint {
    # Context ID (CID) - 2 for host, >2 for guests, 0xFFFFFFFF for any.
    cid @0 :UInt32;

    # Port number.
    port @1 :UInt32;

    # Connection timeout.
    connectTimeout @2 :T.Duration;

    # Custom options.
    custom @3 :T.StringMap;

    # Well-known CID values.
    const vmaddrCidAny :UInt32 = 4294967295;  # 0xFFFFFFFF
    const vmaddrCidHost :UInt32 = 2;
}

# ─── WebSocket Endpoint ──────────────────────────────────────────────

struct WsEndpoint {
    # Base URL (ws:// or wss://).
    url @0 :T.Uri;

    # Subprotocols.
    subprotocols @1 :List(Text);

    # Headers.
    headers @2 :T.StringMap;

    # Origin header.
    origin @3 :Text;

    # TLS config (for wss://).
    tls @4 :TlsConfig;

    # Connection timeout.
    connectTimeout @5 :T.Duration;

    # Ping interval.
    pingInterval @6 :T.Duration;

    # WebSocket compression (permessage-deflate).
    compression @7 :WebSocketCompression;

    # Custom options.
    custom @8 :T.StringMap;
}

struct WebSocketCompression {
    # Whether to enable permessage-deflate.
    enabled @0 :Bool;
    # Server context takeover (can server compress?).
    serverContextTakeover @1 :Bool = true;
    # Client context takeover (can client compress?).
    clientContextTakeover @2 :Bool = true;
    # Max window bits (9-15).
    serverMaxWindowBits @3 :UInt8 = 15;
    clientMaxWindowBits @4 :UInt8 = 15;
}

# ─── QUIC Endpoint ───────────────────────────────────────────────────

struct QuicEndpoint {
    # Host (IP address or hostname).
    host @0 :T.IpAddress;

    # Port number.
    port @1 :T.Port;

    # Server name (SNI).
    serverName @2 :Text;

    # TLS configuration.
    tls @3 :TlsConfig;

    # ALPN protocols.
    alpn @4 :List(Text);

    # Connection timeout.
    connectTimeout @5 :T.Duration;

    # Idle timeout.
    idleTimeout @6 :T.Duration;

    # Max streams.
    maxStreams @7 :UInt64;

    # Initial congestion window.
    initialWindow @8 :UInt64;

    # Custom options.
    custom @9 :T.StringMap;

    # Connection pool configuration.
    connectionPool @10 :ConnectionPoolConfig;
}

# ─── In-Process Endpoint ─────────────────────────────────────────────

struct InprocEndpoint {
    # Service name/identifier within process.
    service @0 :Text;

    # Capability handle for direct invocation.
    capability @1 :T.CapabilityHandle;

    # Custom data.
    custom @2 :Data;
}

# ─── Memory-Mapped File Endpoint ──────────────────────────────────────

struct MmapEndpoint {
    # Path to the memory-mapped file.
    path @0 :Text;

    # Region size in bytes (0 = entire file).
    size @1 :UInt64;

    # Offset within the file to map from.
    offset @2 :UInt64;

    # Memory protection flags.
    protection @3 :MmapProtection;

    # Sharing mode.
    sharing @4 :MmapSharing;

    # Custom options.
    custom @5 :T.StringMap;
}

enum MmapProtection {
    readOnly @0;
    readWrite @1;
    readExecute @2;
    readWriteExecute @3;
    custom @4;
}

enum MmapSharing {
    private @0;       # MAP_PRIVATE — changes are private
    shared @1;        # MAP_SHARED — changes visible to other processes
    copyOnWrite @2;   # COW semantics
    custom @3;
}

# ─── Named Pipe Endpoint ─────────────────────────────────────────────

struct NamedpipeEndpoint {
    # Pipe path (e.g., \\.\pipe\my-pipe on Windows, /tmp/my-pipe on Unix).
    path @0 :Text;

    # Pipe direction.
    direction @1 :PipeDirection;

    # Maximum instances (0 = unlimited).
    maxInstances @2 :UInt32;

    # Inbound buffer size (bytes, 0 = default).
    inboundBufferSize @3 :UInt32;

    # Outbound buffer size (bytes, 0 = default).
    outboundBufferSize @4 :UInt32;

    # Connection timeout.
    connectTimeout @5 :T.Duration;

    # Custom options.
    custom @6 :T.StringMap;
}

enum PipeDirection {
    inbound @0;       # Client reads, server writes
    outbound @1;      # Client writes, server reads
    duplex @2;        # Bidirectional
    custom @3;
}

# ─── Abstract Namespace Unix Socket ──────────────────────────────
# Linux-specific: abstract namespace sockets exist in the kernel
# namespace but not on the filesystem. Identified by path starting
# with '\0' in the kernel (displayed with '@' prefix on disk).
# Structurally different from filesystem-path sockets.

struct AbstractUnixEndpoint {
    # Abstract socket name (without leading @ or \0).
    name @0 :Text;
    # Socket type.
    type @1 :UnixSocketType;
    # Connection timeout.
    connectTimeout @2 :T.Duration;
    # Custom options.
    custom @3 :T.StringMap;
}

# ─── SCTP Endpoint ─────────────────────────────────────────────

struct SctpEndpoint {
    # Host (IP address or hostname).
    host @0 :T.IpAddress;
    # Port number.
    port @1 :T.Port;
    # Number of outbound streams.
    outboundStreams @2 :UInt16;
    # Number of inbound streams.
    inboundStreams @3 :UInt16;
    # Whether to use ordered delivery.
    ordered @4 :Bool = true;
    # Maximum message size in bytes.
    maxMessageSize @5 :UInt32;
    # Connection timeout.
    connectTimeout @6 :T.Duration;
    # Custom options.
    custom @7 :T.StringMap;
}

# ─── Shared Memory Endpoint ──────────────────────────────────────────

struct SharedmemEndpoint {
    # Shared memory name/identifier (POSIX shm_open name or Windows name).
    name @0 :Text;

    # Region size in bytes.
    size @1 :UInt64;

    # Memory protection flags.
    protection @2 :MmapProtection;

    # Sharing mode.
    sharing @3 :MmapSharing;

    # Whether to create the region (true) or attach to existing (false).
    create @4 :Bool;

    # Custom options.
    custom @5 :T.StringMap;
}

# ─── Custom Endpoint ─────────────────────────────────────────────────

struct CustomEndpoint {
    # Scheme identifier (e.g., "custom+myscheme").
    scheme @0 :Text;

    # Opaque address data.
    data @1 :Data;

    # Human-readable representation.
    display @2 :Text;
}

# ─── TLS Configuration ───────────────────────────────────────────────

struct TlsConfig {
    # Whether TLS is enabled.
    enabled @0 :Bool = true;

    # Minimum TLS version.
    minVersion @1 :TlsVersion;

    # Maximum TLS version.
    maxVersion @2 :TlsVersion;

    # Cipher suites (empty = defaults).
    cipherSuites @3 :List(Text);

    # ALPN protocols.
    alpn @4 :List(Text);

    # Server name (SNI).
    serverName @5 :Text;

    # Certificate verification.
    verifyMode @6 :VerifyMode = verifyPeer;

    # Trust anchors (CA certificates, PEM/DER).
    trustAnchors @7 :List(Data);

    # Client certificate (for mTLS).
    clientCert @8 :Data;

    # Client private key.
    clientKey @9 :Data;

    # Certificate revocation checking.
    revocationCheck @10 :RevocationCheck = none;

    # Custom options.
    custom @11 :T.StringMap;

    # Certificate pins for this TLS config.
    pins @12 :List(CertificatePin);
}

enum TlsVersion {
    tls10 @0;
    tls11 @1;
    tls12 @2;
    tls13 @3;
}

enum VerifyMode {
    verifyNone @0;
    verifyPeer @1;
    verifyPeerOnce @2;
}

enum RevocationCheck {
    none @0;
    crl @1;
    ocsp @2;
    ocspStapling @3;
}

# ─── DTLS Configuration ──────────────────────────────────────────────

struct DtlsConfig {
    # Whether DTLS is enabled.
    enabled @0 :Bool = true;

    # Minimum DTLS version.
    minVersion @1 :DtlsVersion;

    # Maximum DTLS version.
    maxVersion @2 :DtlsVersion;

    # Cipher suites.
    cipherSuites @3 :List(Text);

    # Certificate verification.
    verifyMode @4 :VerifyMode = verifyPeer;

    # Trust anchors.
    trustAnchors @5 :List(Data);

    # Client certificate.
    clientCert @6 :Data;
    clientKey @7 :Data;

    # MTU.
    mtu @8 :UInt16;

    # Custom options.
    custom @9 :T.StringMap;

    # Certificate pins for this DTLS config.
    pins @10 :List(CertificatePin);
}

enum DtlsVersion {
    dtls10 @0;
    dtls12 @1;
}

# ─── Proxy Configuration ─────────────────────────────────────────────

struct ProxyConfig {
    # Proxy type.
    type @0 :ProxyType;

    # Proxy address.
    address @1 :T.IpAddress;
    port @2 :T.Port;

    # Authentication.
    username @3 :Text;
    password @4 :Text;

    # Bypass list (hosts that don't use proxy).
    bypass @5 :List(Text);

    # Custom options.
    custom @6 :T.StringMap;
}

enum ProxyType {
    none @0;
    http @1;
    https @2;
    socks4 @3;
    socks5 @4;
    socks5h @5;  # SOCKS5 with remote DNS resolution
    custom @6;
}

# ─── Resolve Result ──────────────────────────────────────────────────

struct ResolveResult {
    union {
        success @0 :ResolveSuccess;
        error @1 :T.Error;
    }
}

struct ResolveSuccess {
    # Resolved addresses (for TCP/UDP).
    addresses @0 :List(ResolvedAddress);

    # For IPC: capability handle or connection info.
    capability @1 :T.CapabilityHandle;

    # Connection hints.
    hints @2 :ConnectionHints;
}

struct ResolvedAddress {
    address @0 :T.IpAddress;
    port @1 :T.Port;
    # Address family preference.
    family @2 :AddressFamily;
}

enum AddressFamily {
    unspecified @0;
    ipv4 @1;
    ipv6 @2;
}

struct ConnectionHints {
    # Preferred transport.
    preferredTransport @0 :TransportPreference;

    # Whether HTTP/2 is supported.
    http2 @1 :Bool;

    # Whether HTTP/3 is supported.
    http3 @2 :Bool;

    # Whether WebSocket is supported.
    websocket @3 :Bool;

    # Whether SCTP is supported.
    sctp @4 :Bool;

    # HTTP/2 specific settings.
    http2Settings @5 :Http2Settings;

    # HTTP/3 specific settings.
    http3Settings @6 :Http3Settings;

    # SCTP specific settings.
    sctpSettings @7 :SctpSettings;

    # Custom hints.
    custom @8 :T.StringMap;
}

struct Http2Settings {
    # SETTINGS_HEADER_TABLE_SIZE (max dynamic table size).
    headerTableSize @0 :UInt32;
    # SETTINGS_INITIAL_WINDOW_SIZE (stream-level flow control).
    initialWindowSize @1 :UInt32;
    # SETTINGS_MAX_FRAME_SIZE (max frame size).
    maxFrameSize @2 :UInt32;
    # SETTINGS_MAX_CONCURRENT_STREAMS (max simultaneous streams).
    maxConcurrentStreams @3 :UInt32;
}

struct Http3Settings {
    # MAX_DATAGRAM_FRAME_SIZE for QUIC datagrams.
    maxDatagramFrameSize @0 :UInt32;
    # Connection window for incoming data.
    maxWindowSize @1 :UInt64;
}

struct SctpSettings {
    # Number of outbound streams.
    outboundStreams @0 :UInt16;
    # Number of inbound streams.
    inboundStreams @1 :UInt16;
    # Whether to use ordered delivery.
    ordered @2 :Bool = true;
    # Maximum message size in bytes.
    maxMessageSize @3 :UInt32;
    # Fragmentation threshold.
    fragmentationThreshold @4 :UInt32;
}

enum TransportPreference {
    tcp @0;
    quic @1;
    websocket @2;
    ipc @3;
    any @4;
}

# ─── Connection Migration ───────────────────────────────────────────────

struct ConnectionMigration {
    # Original endpoint address.
    fromAddress @0 :EndpointAddress;
    # Target endpoint address.
    toAddress @1 :EndpointAddress;
    # Whether migration was successful.
    success @2 :Bool;
    # Bytes transferred during migration.
    bytesTransferred @3 :UInt64;
    # Downtime during migration.
    downtime @4 :T.Duration;
}

# ─── mDNS/DNS-SD Service Discovery ─────────────────────────────────────

struct MdnsServiceInfo {
    # Service name (e.g., "_http._tcp").
    serviceName @0 :Text;
    # Service type (e.g., "http").
    serviceType @1 :Text;
    # Domain (e.g., "local").
    domain @2 :Text;
    # TXT record key-value pairs.
    txtRecords @3 :T.StringMap;
    # Port number.
    port @4 :UInt16;
    # Hostname.
    hostname @5 :Text;
}

# ─── Service Category (from discovery.capnp) ─────────────────────────

enum ServiceCategory {
    other @0;
    media @1;
    network @2;
    system @3;
    storage @4;
    input @5;
    display @6;
    audio @7;
    security @8;
    communication @9;
    application @10;
    data @11;
    messaging @12;
    location @13;
    iot @14;
    # Container/VM management endpoints
    container @15;
    # Cryptographic service endpoints
    crypto @16;
    # Diagnostics/monitoring endpoints
    diagnostics @17;
    custom @18;
}

@0xa1b2c3d4e5f60106;

using T = import "types.capnp";
using S = import "socket.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Endpoint — the transport-agnostic address contract.
#
# An endpoint answers ONE question: where is a peer, and how should a
# connection to it be secured and bounded. It does not answer "which
# transport exists": the previous revision of this file was a 14-variant
# museum of 2026 transports, each with its own structured fields, and a
# 2046 transport had exactly one outlet — a `custom` variant carrying
# none of the security, pooling or health structure the named variants
# carried, so every consumer's transport-aware logic silently degraded
# for anything new.
#
# The rewrite keeps the questions and drops the answers-by-enumeration:
#
#   transport       -> `scheme` :Text, an open token ("tcp", "udp",
#                      "unix", "quic", "ws", "ipc", "inproc", "mmap", ...).
#                      Unknown tokens are ignored, never rejected.
#   address         -> a small, math-closed union: a network address
#                      (host + port), a name (a socket path, a bus name,
#                      a pipe name), or opaque bytes. Every named
#                      transport's structured fields reduce to one of
#                      those three — a VSOCK CID is a number behind a
#                      name, an abstract socket is a name, a shared
#                      memory region is a name plus a size.
#   channel security -> `security` :S.TlsConfig, the ONE canonical TLS
#                      home (socket.capnp). How a `wss://` or `quic://`
#                      endpoint is verified is defined there, not per
#                      schema.
#   limits          -> `limits` :ConnectionLimits, framing and message
#                      size bounds shared by every transport.
#   lifecycle       -> `pool` :ConnectionPoolConfig, who owns idle
#                      connections and when they retire.
#
# What is deliberately GONE, with the reason:
#   - uid/gid/octal permissions and abstract-namespace sockets: POSIX
#     identity in required positions (a capability backend must invent
#     values consumers then trust).
#   - VSOCK constants, mmap/named-pipe/shared-memory variants, and an
#     IpcMechanism enum naming dbus/grpc/binder/mach/fidl: vendor and
#     platform nouns frozen into an eternal contract. Whatever survives
#     of these is a `scheme` token plus a name.
#   - SPIFFE ids: workload identity is capability.capnp's job.
#   - `registerScheme` + `EndpointHandler`: an arbitrary callback became
#     part of the address vocabulary with no authority model and no
#     lifetime. Gone; a backend that understands a scheme reports it.
#   - `migrateConnection`: it named two addresses and returned a report
#     about migrating a connection it was never given. Connection
#     migration belongs to the connection owner (socket.capnp).
#
# Reachability, health and load-balancing answers are REPORTED here as
# measured data with an honest validity flag, not as an enum a consumer
# switches on.
# ═══════════════════════════════════════════════════════════════════════

interface EndpointService {
    # Resolve an endpoint address to connection details.
    resolve @0 (address :EndpointAddress) -> (result :ResolveEndpointResult);

    # Parse a string representation into an endpoint address.
    parse @1 (text :Text) -> (result :ParseEndpointResult);

    # Serialize an endpoint address to its canonical string form.
    serialize @2 (address :EndpointAddress) -> (text :Text);

    # Check whether an endpoint is reachable, and what it cost to learn.
    checkReachable @3 (address :EndpointAddress, timeout :T.Duration)
                  -> (result :ReachabilityResult);

    # Measured health for an endpoint. Absent fields mean "not measured",
    # never "zero" — the validity flag says which.
    getEndpointHealth @4 (address :EndpointAddress) -> (health :EndpointHealth);

    # Reported load-balancing hint. Reporting only; a consumer that does
    # not understand the fields ignores them.
    getLoadBalancingHint @5 (address :EndpointAddress) -> (hint :LoadBalancingHint);
}

# ─── Address ──────────────────────────────────────────────────────────

struct EndpointAddress {
    # Open transport token. Conventionally "tcp", "udp", "unix", "quic",
    # "ws", "wss", "ipc", "inproc", "mmap", "vsock" — a convention, not
    # an enum: an unrecognized token is ignored, never rejected.
    scheme @0 :Text;

    union {
        # A host/port pair. Host is a typed address or a name.
        network @1 :NetworkAddress;
        # A named peer: a socket path, a bus name, a pipe name, an
        # abstract-socket name, a shared-memory object name.
        named @2 :Text;
        # Opaque bytes for a transport whose address has no name or
        # host/port shape.
        opaque @3 :Data;
        # Forward-compatibility slot for an address shape this schema
        # does not name.
        unknown @4 :T.UnknownEvent;
    }

    # Channel security for connections to this endpoint.
    security @5 :S.TlsConfig;

    # Framing and message-size bounds.
    limits @6 :ConnectionLimits;

    # Connection lifecycle ownership.
    pool @7 :ConnectionPoolConfig;

    # Human-readable description.
    description @8 :Text;

    # Reported metadata (tags, version, backend notes).
    metadata @9 :T.StringMap;

    # Extension slot.
    custom @10 :Data;
}

struct NetworkAddress {
    host @0 :T.IpAddress;
    port @1 :T.Port;
    metadata @2 :T.StringMap;
}

# ─── Limits ───────────────────────────────────────────────────────────

struct ConnectionLimits {
    # Maximum message size in bytes the channel will carry (0 = no
    # declared limit).
    maxMessageSize @0 :UInt32;
    # Maximum frame size in bytes for framed transports (0 = unframed).
    maxFrameSize @1 :UInt32;
    # Maximum concurrent streams/channels over one connection
    # (0 = unlimited).
    maxStreams @2 :UInt32;
    # Receive window in bytes the consumer is prepared to buffer.
    receiveWindowBytes @3 :UInt64;
    metadata @4 :T.StringMap;
}

struct ConnectionPoolConfig {
    # Maximum connections in the pool (0 = unlimited).
    maxSize @0 :UInt32;
    # Idle timeout before a connection is closed.
    idleTimeout @1 :T.Duration;
    # Maximum connection lifetime.
    maxLifetime @2 :T.Duration;
    # Whether idle connections are health-checked.
    healthCheck @3 :Bool;
    # Health-check interval.
    healthInterval @4 :T.Duration;
    metadata @5 :T.StringMap;
}

# ─── Certificate Pinning ──────────────────────────────────────────────

# ─── Results ──────────────────────────────────────────────────────────

struct ResolveEndpointResult {
    union {
        success @0 :ResolveEndpointSuccess;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct ResolveEndpointSuccess {
    # Resolved addresses for network transports.
    addresses @0 :List(ResolvedAddress);
    # Reported connection hints. A consumer that cannot act on them waits.
    hints @1 :ConnectionHints;
    metadata @2 :T.StringMap;
}

struct ParseEndpointResult {
    union {
        address @0 :EndpointAddress;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct ReachabilityResult {
    union {
        reachable @0 :Reachability;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct Reachability {
    reachable @0 :Bool;
    # Measured latency, if measured.
    latency @1 :T.Duration;
    # False when the backend did not measure (an in-process endpoint has
    # no latency to report — an honest "unknown", not zero).
    latencyMeasured @2 :Bool;
    metadata @3 :T.StringMap;
}

# ─── Reported Health ──────────────────────────────────────────────────

struct EndpointHealth {
    reachable @0 :Bool;
    # Measured latency (see `latencyMeasured`).
    latency @1 :T.Duration;
    latencyMeasured @2 :Bool;
    # Measured error rate, 0.0–1.0. `false` when not measured.
    errorRateMeasured @3 :Bool;
    errorRate @4 :Float32;
    # When this observation was taken.
    lastChecked @5 :T.Timestamp;
    # Open status token ("healthy", "degraded", ...): reported, not
    # switched on.
    status @6 :Text;
    metadata @7 :T.StringMap;
}

struct LoadBalancingHint {
    # Weight for weighted selection (higher = more traffic).
    weight @0 :UInt32;
    # Priority (lower = preferred).
    priority @1 :UInt32;
    # Whether the reporting backend considers this endpoint healthy.
    healthy @2 :Bool;
    healthyReported @3 :Bool;
    # Maximum concurrent connections (0 = unlimited).
    maxConnections @4 :UInt32;
    metadata @5 :T.StringMap;
}

struct ResolvedAddress {
    address @0 :T.IpAddress;
    port @1 :T.Port;
    metadata @2 :T.StringMap;
}

struct ConnectionHints {
    # Open token naming the transport the backend would use
    # ("tcp", "quic", ...), plus declared capabilities as open tokens.
    preferredTransport @0 :Text;
    supportedCapabilities @1 :List(Text);
    # Declared protocol support as open tokens ("http2", "http3",
    # "websocket", "sctp", ...).
    protocols @2 :List(Text);
    # Backend-declared settings (window sizes, stream counts, ...).
    settings @3 :T.StringMap;
    metadata @4 :T.StringMap;
}

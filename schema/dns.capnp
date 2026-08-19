@0xa1b2c3d4e5f60043;

# ═══════════════════════════════════════════════════════════════════════
# DNS — name resolution with typed records and privacy preferences.
#
# Zero-backend-assumption IPC contract. No specific resolver library,
# platform DNS stack, or stub resolver assumed. The backend decides the
# resolution mechanism; the protocol defines the contract.
#
# Improvements (audit):
#   - DnsRecordType enum for first-class A/AAAA/MX/SRV/TXT/CNAME/NS.
#   - RecordData union for typed records (not all opaque Data).
#   - DnsPrivacy for DoH/DoT preference.
#   - Truncation signal (truncated :Bool).
#   - NegativeCacheInfo for NXDOMAIN responses.
#   - reverseResolve with typed IpAddress (not bare Data).
#   - SrvLookup for service discovery (_service._proto.name).
#   - DnsConfig: current DNS servers and privacy settings.
#   - DnsEventSubscription has cancel() for explicit teardown.
#   - DnsEvent union has custom variant for forward compatibility.
#   - IpAddress union has custom variant for forward compatibility.
#   - ResolveHints.timeout → T.Duration (was raw UInt32 ms).
#   - DnsServerConfig.latencyMs → T.Duration.
#   - SoaRecord refresh/retry/expire → T.Duration (documented as seconds).
#   - NegativeCacheInfo.ttl → T.Duration.
#   - DnsRecordType has other variant for forward compatibility.
#   - ResolutionSource has other variant for forward compatibility.
#   - NegativeCacheKind has other variant for forward compatibility.
#   - DnsPrivacy has other variant for forward compatibility.
#   - IpAddress uses typed 4-byte/16-byte data (not opaque Data).
#
# Audit-7 improvements:
#   - DnsTransport enum for explicit transport selection (UDP/TCP/TLS/HTTPS/QUIC).
#   - DnsOverQuicConfig for QUIC transport configuration.
#   - DnsBlocklistEntry for domain blocking with categories and actions.
#   - DnsAppRouting for per-application DNS routing.
#   - DnsResolverPin for forcing specific resolvers per domain.
#   - DnsCacheEntry for detailed cache inspection.
#   - DnsGeoConfig for geo-aware DNS resolution.
#   - DnsQueryLogEntry for query history.
#   - DnsTelemetry for aggregate query statistics.
#   - ResolverHealth for resolver health monitoring.
#   - DNS security features (blocklists, threat intelligence).
#   - DnsResponsePolicy for per-domain response overrides.
#   - DnsFailoverConfig for automatic resolver failover.
#   - DnsRateLimit for query rate limiting.
#   - DnsCacheWarming for proactive cache population.
#
# Note: This file defines a local IpAddress struct for backward
# compatibility. types.capnp provides the canonical T.IpAddress with
# text fallback and custom variant. Future versions should migrate
# reverseResolveTyped to use T.IpAddress and remove the local definition.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

# ── Record Types ────────────────────────────────────────────────────────

enum DnsRecordType {
    a @0;
    aaaa @1;
    mx @2;
    srv @3;
    txt @4;
    cname @5;
    ns @6;
    soa @7;
    ptr @8;
    cert @9;
    dnskey @10;
    ds @11;
    nsec @12;
    other @13;
    # Backend-specific DNS record type.
    custom @14;
}

# ── Typed Record Data ──────────────────────────────────────────────────

struct RecordData {
    union {
        # IPv4 address (4 bytes, network byte order).
        a @0 :Data;
        # IPv6 address (16 bytes, network byte order).
        aaaa @1 :Data;
        # Mail exchange: priority + exchange name.
        mx @2 :MxRecord;
        # Service locator: priority + weight + port + target.
        srv @3 :SrvRecord;
        # Text string(s).
        txt @4 :List(Text);
        # Canonical name (alias target).
        cname @5 :Text;
        # Authoritative nameserver.
        ns @6 :Text;
        # Start of authority.
        soa @7 :SoaRecord;
        # Pointer to canonical name.
        ptr @8 :Text;
        # Raw opaque data (for cert/dnskey/ds/nsec/other).
        opaque @9 :Data;
    }
}

struct MxRecord {
    priority @0 :UInt16;
    exchange @1 :Text;
}

struct SrvRecord {
    priority @0 :UInt16;
    weight @1 :UInt16;
    port @2 :UInt16;
    target @3 :Text;
}

struct SoaRecord {
    mname @0 :Text;
    rname @1 :Text;
    serial @2 :UInt32;
    # Refresh interval in seconds (DNS RFC standard).
    refresh @3 :UInt32;
    # Retry interval in seconds (DNS RFC standard).
    retry @4 :UInt32;
    # Expiry interval in seconds (DNS RFC standard).
    expire @5 :UInt32;
}

# ── Resolution Query ────────────────────────────────────────────────────

struct ResolveRequest {
    name @0 :Text;
    types @1 :List(DnsRecordType);
    hints @2 :ResolveHints;
}

struct ResolveHints {
    preferCached @0 :Bool = false;
    # Maximum time to wait for resolution.
    timeout @1 :T.Duration;
    allowStale @2 :Bool = false;
    addressFamilies @3 :List(AddressFamilyPreference);
    # Preferred transport (empty = backend default).
    transport @4 :DnsTransport;
}

enum AddressFamilyPreference {
    any @0;
    ipv4Only @1;
    ipv6Only @2;
    other @3;
    # Backend-specific address family preference.
    custom @4;
}

# ── Resolution Result ───────────────────────────────────────────────────

struct ResolveResult {
    canonicalName @0 :Text;
    records @1 :List(DnsRecord);
    source @2 :ResolutionSource;
    # TTL of the DNS record set in seconds.
    ttl @3 :UInt32;
    # Set when the response was truncated (more records would fit).
    truncated @4 :Bool;
    # Negative cache info when name doesn't exist.
    negativeCache @5 :NegativeCacheInfo;
}

struct NegativeCacheInfo {
    # NXDOMAIN vs NODATA (query succeeded but no records of this type).
    kind @0 :NegativeCacheKind;
    # TTL of the negative cache entry in seconds.
    ttl @1 :UInt32;
}

enum NegativeCacheKind {
    nxDomain @0;
    noData @1;
    other @2;
    # Backend-specific negative cache kind.
    custom @3;
}

enum ResolutionSource {
    cache @0;
    localConfig @1;
    recursiveResolver @2;
    authoritative @3;
    multicast @4;
    other @5;
    # Backend-specific resolution source.
    custom @6;
}

struct DnsRecord {
    type @0 :DnsRecordType;
    # Typed data (preferred over opaque).
    typedData @6 :RecordData;
    # Raw opaque data (fallback when type is other).
    data @1 :Data;
    # TTL in seconds.
    ttl @2 :UInt32;
    priority @3 :UInt16;
    name @4 :Text;
    # Whether this is a DNSSEC-validated record.
    validated @5 :Bool;
}

# ── DNS Transport ──────────────────────────────────────────────────────

enum DnsTransport {
    udp @0;
    tcp @1;
    tls @2;
    https @3;
    quic @4;
    other @5;
    # Backend-specific DNS transport.
    custom @6;
}

# ── DNS-over-QUIC Configuration ────────────────────────────────────────

struct DnsOverQuicConfig {
    # QUIC server address.
    serverAddress @0 :T.IpAddress;
    # QUIC server port.
    port @1 :T.Port;
    # ALPN protocols (default: ["doq"]).
    alpn @2 :List(Text);
    # Connection timeout.
    connectionTimeout @3 :T.Duration;
    # Idle timeout before connection close.
    idleTimeout @4 :T.Duration;
    # Whether to use 0-RTT for initial queries.
    zeroRtt @5 :Bool;
    # Custom QUIC options.
    custom @6 :T.StringMap;
}

# ── DNS Blocklist ──────────────────────────────────────────────────────

enum BlocklistCategory {
    malware @0;
    phishing @1;
    advertising @2;
    tracking @3;
    gambling @4;
    adult @5;
    socialMedia @6;
    custom @7;
}

enum BlocklistAction {
    block @0;
    warn @1;
    log @2;
    redirect @3;
    custom @4;
}

struct DnsBlocklistEntry {
    # Domain to block (supports wildcards: *.example.com).
    domain @0 :Text;
    # Category of the blocked domain.
    category @1 :BlocklistCategory;
    # Action to take when this domain is queried.
    action @2 :BlocklistAction;
    # When this entry expires (empty = never expires).
    expiresAt @3 :T.Timestamp;
    # Reason for blocking (displayed to user in warn mode).
    reason @4 :Text;
    # Redirect address for redirect action (empty = NXDOMAIN).
    redirectAddress @5 :T.IpAddress;
}

# ── Per-App DNS Routing ────────────────────────────────────────────────

struct DnsAppRouting {
    # Application that uses this routing.
    appId @0 :T.AppId;
    # Resolver address for this application.
    resolver @1 :Text;
    # Domains that use this routing (empty = all domains).
    domains @2 :List(Text);
    # Transport to use for this routing.
    transport @3 :DnsTransport;
    # Whether this routing is active.
    enabled @4 :Bool;
}

# ── Resolver Pinning ───────────────────────────────────────────────────

struct DnsResolverPin {
    # Domain pattern (supports wildcards: *.example.com).
    domainPattern @0 :Text;
    # Resolver address to pin to.
    resolver @1 :Text;
    # Pin priority (higher = preferred).
    priority @2 :UInt32;
    # Whether this pin is active.
    enabled @3 :Bool;
}

# ── DNS Cache Entry ────────────────────────────────────────────────────

struct DnsCacheEntry {
    # Domain name.
    name @0 :Text;
    # Cached records.
    records @1 :List(DnsRecord);
    # When this entry was cached.
    cachedAt @2 :T.Timestamp;
    # Time-to-live remaining.
    ttlRemaining @3 :T.Duration;
    # Resolution source (cache, localConfig, etc.).
    source @4 :ResolutionSource;
}

# ── Geo-Aware DNS ──────────────────────────────────────────────────────

struct DnsGeoConfig {
    # Client region (e.g., "us-east-1", "eu-west-1").
    clientRegion @0 :Text;
    # Client subnet (for EDNS Client Subnet).
    clientSubnet @1 :Text;
    # Whether to send EDNS Client Subnet.
    ednsClientSubnet @2 :Bool;
    # Whether to use geo-filtered resolvers.
    geoFiltering @3 :Bool;
}

# ── DNS Query Log ──────────────────────────────────────────────────────

struct DnsQueryLogEntry {
    # Queried domain name.
    name @0 :Text;
    # Record type queried.
    type @1 :DnsRecordType;
    # When the query was made.
    timestamp @2 :T.Timestamp;
    # Resolution source (cache, recursive, etc.).
    source @3 :ResolutionSource;
    # Query latency.
    latency @4 :T.Duration;
    # DNS response code (0 = NOERROR, 3 = NXDOMAIN, etc.).
    responseCode @5 :UInt16;
    # Number of records in the response.
    recordCount @6 :UInt32;
    # Transport used.
    transport @7 :DnsTransport;
    # Whether the response was DNSSEC-validated.
    validated @8 :Bool;
}

# ── DNS Telemetry ──────────────────────────────────────────────────────

struct DomainCount {
    domain @0 :Text;
    count @1 :UInt64;
}

struct DnsTelemetry {
    # Total queries observed.
    totalQueries @0 :UInt64;
    # Cache hits.
    cacheHits @1 :UInt64;
    # Cache misses.
    cacheMisses @2 :UInt64;
    # Average query latency.
    avgLatency @3 :T.Duration;
    # Error rate (0.0 = none, 1.0 = all errors).
    errorRate @4 :Float32;
    # Top queried domains.
    topDomains @5 :List(DomainCount);
    # Queries by transport.
    byTransport @6 :T.StringMap;
    # Queries by record type.
    byRecordType @7 :T.StringMap;
}

# ── Resolver Health ────────────────────────────────────────────────────

struct ResolverHealth {
    # Resolver address.
    address @0 :Text;
    # Whether the resolver is healthy.
    healthy @1 :Bool;
    # Current latency.
    latency @2 :T.Duration;
    # When this health check was performed.
    lastChecked @3 :T.Timestamp;
    # Error rate (0.0 = none, 1.0 = all errors).
    errorRate @4 :Float32;
    # Transport in use.
    transport @5 :DnsTransport;
}

# ── DNS Response Policy ────────────────────────────────────────────────

struct DnsResponsePolicy {
    # Domain pattern (supports wildcards).
    domain @0 :Text;
    # Response to return for this domain.
    response @1 :DnsPolicyResponse;
    # Policy priority (higher = preferred).
    priority @2 :UInt32;
    # Whether this policy is active.
    enabled @3 :Bool;
}

enum DnsPolicyResponse {
    # Return NXDOMAIN.
    nxdomain @0;
    # Return NODATA (empty answer).
    nodata @1;
    # Return specific IP address.
    fixedAddress @2;
    # Block with custom response.
    blocked @3;
    custom @4;
}

# ── DNS Failover Config ───────────────────────────────────────────────

struct DnsFailoverConfig {
    # Primary resolver address.
    primaryResolver @0 :Text;
    # Fallback resolvers in priority order.
    fallbackResolvers @1 :List(Text);
    # Health check interval.
    healthCheckInterval @2 :T.Duration;
    # Number of consecutive failures before failover.
    failureThreshold @3 :UInt32;
    # Time to wait before retrying primary.
    retryInterval @4 :T.Duration;
}

# ── DNS Rate Limiting ──────────────────────────────────────────────────

struct DnsRateLimit {
    # Maximum queries per second per client.
    maxQueriesPerSecond @0 :UInt32;
    # Burst size (allows short spikes).
    burstSize @1 :UInt32;
    # Whether rate limiting is enabled.
    enabled @2 :Bool;
    # Action when rate limit exceeded.
    action @3 :DnsRateLimitAction;
}

enum DnsRateLimitAction {
    # Drop the query silently.
    drop @0;
    # Return SERVFAIL.
    servfail @1;
    # Queue and process later.
    queue @2;
    custom @3;
}

# ── DNS Cache Warming ──────────────────────────────────────────────────

struct DnsCacheWarming {
    # Domains to pre-populate.
    domains @0 :List(Text);
    # Warm-up interval.
    interval @1 :T.Duration;
    # Priority (higher = warmed first).
    priority @2 :UInt32;
    # Whether warming is active.
    enabled @3 :Bool;
}

# ── DNS Configuration ──────────────────────────────────────────────────

struct DnsConfig {
    servers @0 :List(DnsServerConfig);
    # Whether DoH is enabled.
    dohEnabled @1 :Bool;
    # DoH template URL.
    dohTemplate @2 :Text;
    # Whether DoT (DNS-over-TLS) is enabled.
    dotEnabled @3 :Bool;
    # Domains searched by default.
    searchDomains @4 :List(Text);
    # Number of successful queries from cache vs network.
    cacheHits @5 :UInt64;
    cacheMisses @6 :UInt64;
    # Default transport preference.
    defaultTransport @7 :DnsTransport;
    # QUIC configuration (when transport = quic).
    quicConfig @8 :DnsOverQuicConfig;
    # Per-app routing rules.
    appRouting @9 :List(DnsAppRouting);
    # Resolver pinning rules.
    resolverPins @10 :List(DnsResolverPin);
    # Geo-aware DNS configuration.
    geoConfig @11 :DnsGeoConfig;
    # Failover configuration.
    failoverConfig @12 :DnsFailoverConfig;
    # Rate limiting configuration.
    rateLimit @13 :DnsRateLimit;
}

struct DnsServerConfig {
    address @0 :Text;
    port @1 :UInt16;
    # Whether this server supports DoH.
    doh @2 :Bool;
    dohHostname @3 :Text;
    # Whether this server is trusted (DNSSEC-validated).
    trusted @4 :Bool;
    # Round-trip latency.
    latency @5 :T.Duration;
    # Transport for this server.
    transport @6 :DnsTransport;
}

# ── Service ─────────────────────────────────────────────────────────────

interface DnsService {
    resolve @0 (request :ResolveRequest) -> (result :ResolveResult);

    # Service discovery: SRV record lookup.
    srvLookup @5 (service :Text, proto :Text, domain :Text) -> (result :ResolveResult);

    # Reverse-resolve (pointer query).
    reverseResolve @1 (address :Data) -> (name :Text);

    # Typed reverse resolve (preferred).
    reverseResolveTyped @6 (address :IpAddress) -> (name :Text);

    flushCache @2 (name :Text) -> T.VoidResult;
    cacheStatus @3 (name :Text) -> (cached :Bool, recordCount :UInt32, ttl :UInt32);

    getConfig @7 () -> (config :DnsConfig);
    setPrivacy @8 (privacy :DnsPrivacy) -> T.VoidResult;

    subscribeEvents @4 () -> (subscription :DnsEventSubscription);

    # Typed reverse resolve using canonical T.IpAddress (preferred over reverseResolve).
    reverseResolveV2 @9 (address :T.IpAddress) -> (name :Text);

    # ── Blocklist management ──
    addBlocklistEntry @10 (entry :DnsBlocklistEntry) -> T.VoidResult;
    removeBlocklistEntry @11 (domain :Text) -> T.VoidResult;
    getBlocklist @12 (pagination :T.Pagination) -> (entries :List(DnsBlocklistEntry), total :UInt64);
    checkBlocklist @13 (domain :Text) -> (blocked :Bool, entry :DnsBlocklistEntry);

    # ── Per-app routing ──
    setAppRouting @14 (routing :DnsAppRouting) -> T.VoidResult;
    getAppRouting @15 (appId :T.AppId) -> (routing :DnsAppRouting);
    clearAppRouting @16 (appId :T.AppId) -> T.VoidResult;

    # ── Resolver pinning ──
    addResolverPin @17 (pin :DnsResolverPin) -> T.VoidResult;
    removeResolverPin @18 (domainPattern :Text) -> T.VoidResult;
    getResolverPins @19 (pagination :T.Pagination) -> (pins :List(DnsResolverPin), total :UInt64);

    # ── Cache management ──
    getCacheEntry @20 (name :Text) -> (entry :DnsCacheEntry);
    prefetchDomain @21 (name :Text) -> T.VoidResult;
    getCacheStats @22 () -> (hits :UInt64, misses :UInt64, size :UInt32, evictions :UInt64);

    # ── Geo-aware DNS ──
    setGeoConfig @23 (config :DnsGeoConfig) -> T.VoidResult;
    getGeoConfig @24 () -> (config :DnsGeoConfig);

    # ── Query logging ──
    getQueryLog @25 (pagination :T.Pagination) -> (entries :List(DnsQueryLogEntry), total :UInt64);

    # ── Telemetry ──
    getTelemetry @26 () -> (telemetry :DnsTelemetry);
    subscribeTelemetry @27 () -> (subscription :DnsTelemetrySubscription);

    # ── Resolver health ──
    getResolverHealth @28 () -> (resolvers :List(ResolverHealth));
    subscribeResolverHealth @29 () -> (subscription :ResolverHealthSubscription);

    # ── Response policy ──
    setResponsePolicy @30 (policy :DnsResponsePolicy) -> T.VoidResult;
    removeResponsePolicy @31 (domain :Text) -> T.VoidResult;
    getResponsePolicies @32 (pagination :T.Pagination) -> (policies :List(DnsResponsePolicy), total :UInt64);

    # ── Cache warming ──
    setCacheWarming @33 (warming :DnsCacheWarming) -> T.VoidResult;
    getCacheWarming @34 () -> (warming :DnsCacheWarming);

    # ── Batch resolve ──
    resolveBatch @35 (requests :List(ResolveRequest)) -> (results :List(ResolveResult));
}

enum DnsPrivacy {
    plain @0;
    dot @1;
    doh @2;
    odoh @3;
    other @4;
    # Backend-specific DNS privacy mode.
    custom @5;
}

# DEPRECATED — Local IpAddress struct kept solely for backward compatibility.
# The canonical type is T.IpAddress in types.capnp, which includes text
# fallback, custom variant, and structured octet fields.
#
# Migration path (canonical to deprecated):
#   reverseResolveV2 @9  uses T.IpAddress  ← PREFERRED, always use this.
#   reverseResolveTyped @6  uses local IpAddress  ← DEPRECATED, do not use.
#   reverseResolve @1  uses bare Data  ← DEPRECATED, do not use.
#
# This local struct will be removed in a future major version.
# All new methods MUST use T.IpAddress.
struct IpAddress {
    union {
        # IPv4 address (4 bytes, network byte order).
        ipv4 @0 :Data;
        # IPv6 address (16 bytes, network byte order).
        ipv6 @1 :Data;
        # Backend-specific address format.
        custom @2 :Data;
    }
}

interface DnsEventSubscription {
    pull @0 () -> (events :List(DnsEvent));
    # Explicit cancellation — stops the event stream and releases resources.
    cancel @1 () -> T.VoidResult;
}

struct DnsEvent {
    timestamp @0 :T.Timestamp;
    union {
        resolved @1 :DnsResolveEvent;
        cacheExpired @2 :DnsCacheEvent;
        error @3 :DnsErrorEvent;
        privacyChanged @4 :DnsPrivacy;
        # Backend-specific DNS event type.
        custom @5 :Data;
    }
}

struct DnsResolveEvent {
    name @0 :Text;
    recordCount @1 :UInt32;
    source @2 :ResolutionSource;
}

struct DnsCacheEvent {
    name @0 :Text;
}

struct DnsErrorEvent {
    name @0 :Text;
    error @1 :T.Error;
}

# ── Subscriptions ───────────────────────────────────────────

interface DnsTelemetrySubscription {
    pull @0 () -> (telemetry :DnsTelemetry);
    cancel @1 () -> T.VoidResult;
}

interface ResolverHealthSubscription {
    pull @0 () -> (resolvers :List(ResolverHealth));
    cancel @1 () -> T.VoidResult;
}

@0xa1b2c3d4e5f60043;

using T = import "types.capnp";
using S = import "socket.capnp";

# ═══════════════════════════════════════════════════════════════════════
# DNS — name resolution with typed records and privacy preferences.
#
# Zero-backend-assumption IPC contract. No specific resolver library,
# platform DNS stack, or stub resolver assumed. The backend decides the
# resolution mechanism; the protocol defines the contract.
#
# Fixes this revision makes:
#   - `resolve` and `srvLookup` can now FAIL. The result was a bare
#     struct, so SERVFAIL and a timeout were indistinguishable from
#     NXDOMAIN-with-no-negative-cache; every backend invented its own
#     encoding (a pseudo-record, an out-of-band field, a status code at a
#     new ordinal). The result is now a union carrying T.Error.
#   - One reverse-resolve path. The file carried three (@1 on bare Data,
#     @6 on a local IpAddress struct, @9 on T.IpAddress) and documented
#     the migration without performing it; there is now one, typed.
#   - One address vocabulary (T.IpAddress) and one port vocabulary
#     (T.Port) everywhere, including resolver addresses that were bare
#     Text.
#   - One time vocabulary: every TTL is a T.Duration. The old file's
#     header claimed "SoaRecord refresh/retry/expire → T.Duration" while
#     the fields stayed UInt32 seconds — a comment that taught a 10^9
#     error. The claim is now true.
#   - Transport security is expressible: `DnsConfig.transportSecurity`
#     is the canonical TlsConfig from socket.capnp, so "resolve over an
#     authenticated channel" is a declared requirement rather than a
#     backend's choice.
#   - Blocklist categories are open tokens. "socialMedia" as a blocking
#     category is a 2024 editorial fact, not a mathematical set.
# ═══════════════════════════════════════════════════════════════════════

# ── Record Types ────────────────────────────────────────────────────────

enum DnsRecordType {
    unspecified @0;
    a @1;
    aaaa @2;
    mx @3;
    srv @4;
    txt @5;
    cname @6;
    ns @7;
    soa @8;
    ptr @9;
    cert @10;
    dnskey @11;
    ds @12;
    nsec @13;
    other @14;
    custom @15;
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
        # Forward-compatibility slot for a record kind this schema does
        # not name. A consumer skips it; it never fails the parse.
        custom @9 :Data;
    }
}

struct MxRecord {
    priority @0 :UInt16;
    exchange @1 :Text;
    metadata @2 :T.StringMap;
}

struct SrvRecord {
    priority @0 :UInt16;
    weight @1 :UInt16;
    port @2 :T.Port;
    target @3 :Text;
    metadata @4 :T.StringMap;
}

struct SoaRecord {
    mname @0 :Text;
    rname @1 :Text;
    serial @2 :UInt32;
    refresh @3 :T.Duration;
    retry @4 :T.Duration;
    expire @5 :T.Duration;
    metadata @6 :T.StringMap;
}

# ── Resolution Query ────────────────────────────────────────────────────

struct ResolveRequest {
    name @0 :Text;
    types @1 :List(DnsRecordType);
    hints @2 :ResolveHints;
    metadata @3 :T.StringMap;
}

struct ResolveHints {
    preferCached @0 :Bool = false;
    timeout @1 :T.Duration;
    allowStale @2 :Bool = false;
    addressFamilies @3 :List(AddressFamilyPreference);
    # Preferred transport (open token): "udp", "tcp", "tls", "https",
    # "quic". Empty = backend default.
    transport @4 :Text;
    # Channel security required for this resolution (the canonical
    # TlsConfig from socket.capnp). Absent = no declared requirement.
    security @5 :S.TlsConfig;
    metadata @6 :T.StringMap;
}

enum AddressFamilyPreference {
    unspecified @0;
    any @1;
    ipv4Only @2;
    ipv6Only @3;
    custom @4;
}

# ── Resolution Result ───────────────────────────────────────────────────

struct ResolveResult {
    union {
        answer @0 :ResolveAnswer;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct ResolveAnswer {
    canonicalName @0 :Text;
    records @1 :List(DnsRecord);
    source @2 :ResolutionSource;
    ttl @3 :T.Duration;
    truncated @4 :Bool;
    negativeCache @5 :NegativeCacheInfo;
    metadata @6 :T.StringMap;
}

struct ReverseResolveResult {
    union {
        name @0 :Text;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct NegativeCacheInfo {
    kind @0 :NegativeCacheKind;
    ttl @1 :T.Duration;
}

enum NegativeCacheKind {
    unspecified @0;
    nxDomain @1;
    noData @2;
    custom @3;
}

enum ResolutionSource {
    unspecified @0;
    cache @1;
    localConfig @2;
    recursiveResolver @3;
    authoritative @4;
    multicast @5;
    custom @6;
}

struct DnsRecord {
    type @0 :DnsRecordType;
    typedData @1 :RecordData;
    # Raw opaque data (fallback when type is other/custom), as a handle.
    data @2 :T.DataHandle;
    ttl @3 :T.Duration;
    priority @4 :UInt16;
    name @5 :Text;
    # Whether this is a DNSSEC-validated record.
    validated @6 :Bool;
    metadata @7 :T.StringMap;
}

# ── DNS-over-QUIC Configuration ────────────────────────────────────────

struct DnsOverQuicConfig {
    serverAddress @0 :T.IpAddress;
    port @1 :T.Port;
    alpn @2 :List(Text);
    connectionTimeout @3 :T.Duration;
    idleTimeout @4 :T.Duration;
    zeroRtt @5 :Bool;
    # Channel security for the QUIC connection (canonical TLS home).
    security @6 :S.TlsConfig;
    metadata @7 :T.StringMap;
}

# ── DNS Blocklist ──────────────────────────────────────────────────────

# Category is an open token ("malware", "phishing", "advertising", ...):
# the taxonomy is editorial and ages.
struct DnsBlocklistEntry {
    domain @0 :Text;
    category @1 :Text;
    action @2 :BlocklistAction;
    expiresAt @3 :T.Timestamp;
    reason @4 :Text;
    redirectAddress @5 :T.IpAddress;
    metadata @6 :T.StringMap;
}

enum BlocklistAction {
    unspecified @0;
    block @1;
    warn @2;
    log @3;
    redirect @4;
    custom @5;
}

# ── Per-App DNS Routing ────────────────────────────────────────────────

struct DnsAppRouting {
    appId @0 :T.AppId;
    resolver @1 :T.IpAddress;
    domains @2 :List(Text);
    transport @3 :Text;
    enabled @4 :Bool;
    metadata @5 :T.StringMap;
}

# ── Resolver Pinning ───────────────────────────────────────────────────

struct DnsResolverPin {
    domainPattern @0 :Text;
    resolver @1 :T.IpAddress;
    priority @2 :UInt32;
    enabled @3 :Bool;
    metadata @4 :T.StringMap;
}

# ── DNS Cache Entry ────────────────────────────────────────────────────

struct DnsCacheEntry {
    name @0 :Text;
    records @1 :List(DnsRecord);
    cachedAt @2 :T.Timestamp;
    ttlRemaining @3 :T.Duration;
    source @4 :ResolutionSource;
    metadata @5 :T.StringMap;
}

# ── Geo-Aware DNS ──────────────────────────────────────────────────────

struct DnsGeoConfig {
    clientRegion @0 :Text;
    clientSubnet @1 :T.IpAddress;
    ednsClientSubnet @2 :Bool;
    geoFiltering @3 :Bool;
    metadata @4 :T.StringMap;
}

# ── DNS Query Log ──────────────────────────────────────────────────────

struct DnsQueryLogEntry {
    name @0 :Text;
    type @1 :DnsRecordType;
    timestamp @2 :T.Timestamp;
    source @3 :ResolutionSource;
    latency @4 :T.Duration;
    # DNS response code (0 = NOERROR, 3 = NXDOMAIN, ...).
    responseCode @5 :UInt16;
    recordCount @6 :UInt32;
    transport @7 :Text;
    validated @8 :Bool;
    metadata @9 :T.StringMap;
}

# ── DNS Telemetry ──────────────────────────────────────────────────────

struct DomainCount {
    domain @0 :Text;
    count @1 :UInt64;
    metadata @2 :T.StringMap;
}

struct DnsTelemetry {
    totalQueries @0 :UInt64;
    cacheHits @1 :UInt64;
    cacheMisses @2 :UInt64;
    avgLatency @3 :T.Duration;
    errorRate @4 :Float32;
    topDomains @5 :List(DomainCount);
    byTransport @6 :T.StringMap;
    byRecordType @7 :T.StringMap;
}

# ── Resolver Health ────────────────────────────────────────────────────

struct ResolverHealth {
    address @0 :T.IpAddress;
    healthy @1 :Bool;
    latency @2 :T.Duration;
    lastChecked @3 :T.Timestamp;
    errorRate @4 :Float32;
    transport @5 :Text;
    metadata @6 :T.StringMap;
}

# ── DNS Response Policy ────────────────────────────────────────────────

struct DnsResponsePolicy {
    domain @0 :Text;
    response @1 :DnsPolicyResponse;
    priority @2 :UInt32;
    enabled @3 :Bool;
    metadata @4 :T.StringMap;
}

enum DnsPolicyResponse {
    unspecified @0;
    nxdomain @1;
    nodata @2;
    fixedAddress @3;
    blocked @4;
    custom @5;
}

# ── DNS Failover Config ───────────────────────────────────────────────

struct DnsFailoverConfig {
    primaryResolver @0 :T.IpAddress;
    fallbackResolvers @1 :List(T.IpAddress);
    healthCheckInterval @2 :T.Duration;
    failureThreshold @3 :UInt32;
    retryInterval @4 :T.Duration;
    metadata @5 :T.StringMap;
}

# ── DNS Rate Limiting ──────────────────────────────────────────────────

struct DnsRateLimit {
    maxQueriesPerSecond @0 :UInt32;
    burstSize @1 :UInt32;
    enabled @2 :Bool;
    action @3 :DnsRateLimitAction;
}

enum DnsRateLimitAction {
    unspecified @0;
    drop @1;
    servfail @2;
    queue @3;
    custom @4;
}

# ── DNS Cache Warming ──────────────────────────────────────────────────

struct DnsCacheWarming {
    domains @0 :List(Text);
    interval @1 :T.Duration;
    priority @2 :UInt32;
    enabled @3 :Bool;
    metadata @4 :T.StringMap;
}

# ── DNS Configuration ──────────────────────────────────────────────────

struct DnsConfig {
    servers @0 :List(DnsServerConfig);
    searchDomains @1 :List(Text);
    # Default transport as an open token.
    defaultTransport @2 :Text;
    # Channel security for encrypted transports. This is where "DoH" and
    # "DoT" now live: not as separate booleans and a URL template, but
    # as a declared security requirement from the canonical TLS home.
    transportSecurity @3 :S.TlsConfig;
    quicConfig @4 :DnsOverQuicConfig;
    appRouting @5 :List(DnsAppRouting);
    resolverPins @6 :List(DnsResolverPin);
    geoConfig @7 :DnsGeoConfig;
    failoverConfig @8 :DnsFailoverConfig;
    rateLimit @9 :DnsRateLimit;
    cacheWarming @10 :DnsCacheWarming;
    cacheHits @11 :UInt64;
    cacheMisses @12 :UInt64;
    metadata @13 :T.StringMap;
}

struct DnsServerConfig {
    address @0 :T.IpAddress;
    port @1 :T.Port;
    # Transport as an open token ("udp", "tcp", "tls", "https", ...).
    transport @2 :Text;
    # Hostname used for certificate validation on encrypted transports.
    tlsHostname @3 :Text;
    # Whether this server is trusted (DNSSEC-validated).
    trusted @4 :Bool;
    latency @5 :T.Duration;
    metadata @6 :T.StringMap;
}

struct CacheStatus {
    cached @0 :Bool;
    recordCount @1 :UInt32;
    ttlRemaining @2 :T.Duration;
}

# ── Service ─────────────────────────────────────────────────────────────

interface DnsService {
    resolve @0 (request :ResolveRequest) -> (result :ResolveResult);

    # Service discovery: SRV record lookup.
    srvLookup @1 (service :Text, proto :Text, domain :Text) -> (result :ResolveResult);

    # Reverse-resolve (pointer query). The one path; typed address,
    # honest error when no PTR exists.
    reverseResolve @2 (address :T.IpAddress) -> (result :ReverseResolveResult);

    # Flush the cache for a name. An empty name flushes everything.
    flushCache @3 (name :Text) -> T.VoidResult;
    cacheStatus @4 (name :Text) -> (status :CacheStatus);

    getConfig @5 () -> (config :DnsConfig);
    setConfig @6 (config :DnsConfig) -> T.VoidResult;

    subscribeEvents @7 () -> (subscription :DnsEventSubscription);

    # ── Blocklist management ──
    addBlocklistEntry @8 (entry :DnsBlocklistEntry) -> T.VoidResult;
    removeBlocklistEntry @9 (domain :Text) -> T.VoidResult;
    getBlocklist @10 (pagination :T.Pagination) -> (entries :List(DnsBlocklistEntry), totalCount :UInt64);
    checkBlocklist @11 (domain :Text) -> (result :BlocklistCheckResult);

    # ── Per-app routing ──
    setAppRouting @12 (routing :DnsAppRouting) -> T.VoidResult;
    getAppRouting @13 (appId :T.AppId) -> (result :AppRoutingResult);
    clearAppRouting @14 (appId :T.AppId) -> T.VoidResult;

    # ── Resolver pinning ──
    addResolverPin @15 (pin :DnsResolverPin) -> T.VoidResult;
    removeResolverPin @16 (domainPattern :Text) -> T.VoidResult;
    getResolverPins @17 (pagination :T.Pagination) -> (pins :List(DnsResolverPin), totalCount :UInt64);

    # ── Cache management ──
    getCacheEntry @18 (name :Text) -> (result :CacheEntryResult);
    prefetchDomain @19 (name :Text) -> T.VoidResult;
    getCacheStats @20 () -> (hits :UInt64, misses :UInt64, size :UInt32, evictions :UInt64);

    # ── Geo-aware DNS ──
    setGeoConfig @21 (config :DnsGeoConfig) -> T.VoidResult;
    getGeoConfig @22 () -> (config :DnsGeoConfig);

    # ── Query logging ──
    getQueryLog @23 (pagination :T.Pagination) -> (entries :List(DnsQueryLogEntry), totalCount :UInt64);

    # ── Telemetry ──
    getTelemetry @24 () -> (telemetry :DnsTelemetry);
    subscribeTelemetry @25 () -> (subscription :DnsTelemetrySubscription);

    # ── Resolver health ──
    getResolverHealth @26 (pagination :T.Pagination) -> (resolvers :List(ResolverHealth), totalCount :UInt64);
    subscribeResolverHealth @27 () -> (subscription :ResolverHealthSubscription);

    # ── Response policy ──
    setResponsePolicy @28 (policy :DnsResponsePolicy) -> T.VoidResult;
    removeResponsePolicy @29 (domain :Text) -> T.VoidResult;
    getResponsePolicies @30 (pagination :T.Pagination) -> (policies :List(DnsResponsePolicy), totalCount :UInt64);

    # ── Cache warming ──
    setCacheWarming @31 (warming :DnsCacheWarming) -> T.VoidResult;
    getCacheWarming @32 () -> (warming :DnsCacheWarming);

    # ── Batch resolve ──
    # Bounded like every other list in this file: `page` limits how many
    # requests are processed in one message and `totalCount` reports the
    # request count, so a batch can never be one unbounded message.
    resolveBatch @33 (requests :List(ResolveRequest), page :T.Pagination)
                 -> (results :List(ResolveResult), totalCount :UInt64);
}

struct BlocklistCheckResult {
    union {
        blocked @0 :Bool;
        entry @1 :DnsBlocklistEntry;
        error @2 :T.Error;
        unknown @3 :T.UnknownEvent;
    }
}

struct AppRoutingResult {
    union {
        routing @0 :DnsAppRouting;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct CacheEntryResult {
    union {
        entry @0 :DnsCacheEntry;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

# ── Events ─────────────────────────────────────────────────────────────

interface DnsEventSubscription {
    pull @0 () -> (events :List(DnsEvent));
    cancel @1 () -> T.VoidResult;
}

struct DnsEvent {
    timestamp @0 :T.Timestamp;
    union {
        resolved @1 :DnsResolveEvent;
        cacheExpired @2 :DnsCacheEvent;
        error @3 :DnsErrorEvent;
        # Configuration changed; the config is the event.
        configChanged @4 :DnsConfig;
        custom @5 :Data;
    }
}

struct DnsResolveEvent {
    name @0 :Text;
    recordCount @1 :UInt32;
    source @2 :ResolutionSource;
    metadata @3 :T.StringMap;
}

struct DnsCacheEvent {
    name @0 :Text;
    metadata @1 :T.StringMap;
}

struct DnsErrorEvent {
    name @0 :Text;
    error @1 :T.Error;
    metadata @2 :T.StringMap;
}

# ── Subscriptions ──────────────────────────────────────────────────────

interface DnsTelemetrySubscription {
    pull @0 () -> (telemetry :DnsTelemetry);
    cancel @1 () -> T.VoidResult;
}

interface ResolverHealthSubscription {
    pull @0 () -> (resolvers :List(ResolverHealth));
    cancel @1 () -> T.VoidResult;
}

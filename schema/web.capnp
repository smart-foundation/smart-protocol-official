@0xa1b2c3d4e5f60020;

# ═══════════════════════════════════════════════════════════════════════
# Web — HTTP fetch, WebSocket, URL and HTML parsing primitives.
#
# Backend-agnostic. The HTTP transport may be elio, libcurl, a custom
# Rust reqwest clone, or a synthetic offline backend for tests. The
# protocol describes request/response and lifecycle — never the transport.
#
# Improvements beyond the original:
#   - HttpRequest.timeout is now T.Duration (was raw UInt64 ms).
#   - HttpRequest.body / HttpResponse.body are T.DataHandle
#     (inline <1KB or buffer-handle for large payloads).
#   - WebSocketConnection.close.code uses a typed WebSocketCloseCode
#     union instead of bare UInt16.
#   - All subscription interfaces have cancel.
#   - HTTP method is a typed enum (method :Text -> method :HttpMethod).
#   - MessagesSubscription has cancel.
# ═══════════════════════════════════════════════════════════════════════

using T = import "types.capnp";

interface WebService {

    fetch       @0 (request :HttpRequest)  -> (response :HttpResponse);
    fetchStream @1 (request :HttpRequest)  -> (stream :HttpStream);

    openWebSocket @2 (url :Text, protocols :List(Text))
                     -> (connection :WebSocketConnection);

    resolveUrl @3 (url :Text, baseUrl :Text) -> (resolved :Text);
    encodeUrl  @4 (url :Text)                 -> (encoded :Text);
    decodeUrl  @5 (url :Text)                 -> (decoded :Text);

    parseHtml @6 (html :Text) -> (parsed :ParsedHtml);

    # Audit-8: Register a service worker.
    registerServiceWorker @7 (scope :Text, scriptUrl :Text)
        -> (registration :ServiceWorkerRegistration);

    # Audit-8: Unregister a service worker.
    unregisterServiceWorker @8 (scope :Text) -> T.VoidResult;

    # Audit-8: Get service worker state.
    getServiceWorkerState @9 (scope :Text) -> (state :ServiceWorkerState);

    # Audit-8: Configure proxy settings.
    setProxyConfig @10 (config :ProxyConfig) -> T.VoidResult;

    # Audit-8: Get current proxy configuration.
    getProxyConfig @11 () -> (config :ProxyConfig);

    # Audit-8: Register a WebAuthn credential.
    registerWebAuthn @12 (request :WebAuthnRegisterRequest)
        -> (credential :WebAuthnCredential);

    # Audit-8: Authenticate with WebAuthn.
    authenticateWebAuthn @13 (request :WebAuthnAuthenticateRequest)
        -> (result :WebAuthnResult);

    # Audit-8: List WebAuthn credentials.
    listWebAuthnCredentials @14 (pagination :T.Pagination)
        -> (credentials :List(WebAuthnCredential), total :UInt64);

    # Audit-8: Delete a WebAuthn credential.
    deleteWebAuthnCredential @15 (credentialId :T.DataHandle) -> T.VoidResult;

    # Audit-8: Get CDN info for a URL.
    getCdnInfo @16 (url :Text) -> (cdn :CDNInfo);

    # Audit-8: Get privacy configuration.
    getPrivacyConfig @17 () -> (config :PrivacyConfig);

    # Audit-8: Set privacy configuration.
    setPrivacyConfig @18 (config :PrivacyConfig) -> T.VoidResult;

    # Audit-8: Get CORS policy for a URL.
    getCorsPolicy @19 (url :Text) -> (policy :CorsPolicy);

    # Audit-8: Check if a URL is allowed by CORS policy.
    checkCors @20 (origin :Text, url :Text, method :HttpMethod) -> (allowed :Bool);

    # Audit-9: Service worker fetch event interception.
    handleFetchEvent @21 (event :FetchEvent) -> (response :HttpResponse);

    # Audit-9: Readable stream reader.
    getStreamReader @22 (stream :ReadableStreamChunk) -> (reader :ReadableStreamReader);

    # Audit-9: WebRTC SDP negotiation.
    createWebRtcOffer @23 (sessionId :Text) -> (sdp :SdpOffer);
    createWebRtcAnswer @24 (sessionId :Text, offer :SdpOffer) -> (answer :SdpAnswer);
    setLocalDescription @25 (sessionId :Text, sdp :Text) -> T.VoidResult;
    setRemoteDescription @26 (sessionId :Text, sdp :Text) -> T.VoidResult;
    getLocalDescription @27 (sessionId :Text) -> (sdp :Text);

    # Audit-9: HTTP/2 server push.
    pushResource @28 (streamId :UInt32, pushPromises :List(PushPromise)) -> T.VoidResult;

    # Audit-10: WebRTC ICE candidate management.
    addIceCandidate @29 (sessionId :Text, candidate :IceCandidate) -> T.VoidResult;
    getIceCandidates @30 (sessionId :Text) -> (candidates :List(IceCandidate));
    removeIceCandidate @31 (sessionId :Text, candidate :IceCandidate) -> T.VoidResult;

    # Audit-10: WebRTC data channel.
    createDataChannel @32 (sessionId :Text, label :Text, config :DataChannelConfig)
        -> (channel :DataChannel);
    sendDataChannelMessage @33 (sessionId :Text, channelId :Text, data :Data) -> T.VoidResult;
    closeDataChannel @34 (sessionId :Text, channelId :Text) -> T.VoidResult;

    # Audit-10: HTTP/2 push cancellation.
    cancelPush @35 (streamId :UInt32, pushId :UInt32) -> T.VoidResult;

    # Audit-10: WebAuthn attestation verification.
    verifyWebAuthnAttestation @36 (attestation :WebAuthnAttestation)
        -> (result :WebAuthnAttestationResult);
}

# ── Streaming ──────────────────────────────────────────────────────────

interface HttpStream {
    pull   @0 () -> (chunk :T.DataHandle, done :Bool);
    cancel @1 () -> T.VoidResult;
}

# ── WebSocket ──────────────────────────────────────────────────────────

interface WebSocketConnection {
    send        @0 (data :Data)         -> T.VoidResult;
    sendText    @1 (text :Text)         -> T.VoidResult;
    close       @2 (code :WebSocketCloseCode, reason :Text) -> T.VoidResult;
    subscribeMessages @3 () -> (subscription :MessagesSubscription);
}

interface MessagesSubscription {
    pull   @0 () -> (messages :List(WebSocketMessage));
    cancel @1 () -> T.VoidResult;

    # Paginated message retrieval. Returns at most `pagination.limit` messages
    # starting at `pagination.offset`. Caller should repeat with increasing
    # offset until all messages are consumed.
    pullPaged @2 (pagination :T.Pagination)
              -> (messages :List(WebSocketMessage), total :UInt64);
}

# ── HTTP Request / Response ───────────────────────────────────────────

enum HttpMethod {
    get     @0;
    head    @1;
    post    @2;
    put     @3;
    delete  @4;
    connect @5;
    options @6;
    trace   @7;
    patch   @8;
    custom  @9;
}

struct HttpRequest {
    method     @0 :HttpMethod;
    # URL as text. HTTP URLs have specific semantics (scheme validation,
    # encoding) that a generic T.Uri doesn't capture. Text is appropriate.
    url        @1 :Text;
    headers    @2 :T.StringMap;
    # Inline for small bodies, buffer-handle for >1KB.
    body       @3 :T.DataHandle;
    timeout    @4 :T.Duration;
    # Optional cancellation handle (see access.capnp-style patterns).
    followRedirects @5 :Bool = true;
    # Maximum number of redirects to follow (0 = none).
    maxRedirects @6 :UInt32;
}

struct HttpResponse {
    status     @0 :UInt16;
    statusText @1 :Text;
    headers    @2 :T.StringMap;
    # Inline for small responses, buffer-handle for >1KB.
    body       @3 :T.DataHandle;
    url        @4 :Text;
    # Round-trip time the engine measured.
    latency    @5 :T.Duration;
}

# ── WebSocket ─────────────────────────────────────────────────────────

struct WebSocketMessage {
    type @0 :WebSocketMessageType;
    data @1 :Data;
    text @2 :Text;
}

enum WebSocketMessageType {
    text    @0;
    binary  @1;
    ping    @2;
    pong    @3;
    close   @4;
    custom  @5;
}

# WebSocket close codes. RFC 6455 + vendor-defined escape hatch.
struct WebSocketCloseCode {
    union {
        normal          @0  :Void;
        goingAway       @1  :Void;
        protocolError   @2  :Void;
        unsupportedData @3  :Void;
        invalidPayload  @4  :Text;
        policyViolation @5  :Void;
        tooLarge        @6  :Void;
        serverError     @7  :Void;
        # Vendor / application-defined.
        custom          @8  :UInt16;
    }
}

# ── HTML Parsing ──────────────────────────────────────────────────────

struct ParsedHtml {
    title  @0 :Text;
    meta   @1 :T.StringMap;
    links  @2 :List(HtmlLink);
    images @3 :List(HtmlImage);
}

struct HtmlLink {
    href @0 :Text;
    text @1 :Text;
    rel  @2 :Text;
}

struct HtmlImage {
    src    @0 :Text;
    alt    @1 :Text;
    width  @2 :UInt32;
    height @3 :UInt32;
}

# ── Audit-8: Service Worker ───────────────────────────────────────────

struct ServiceWorkerRegistration {
    # Service worker scope.
    scope @0 :Text;
    # Current registration state.
    state @1 :ServiceWorkerState;
    # Script URL.
    scriptUrl @2 :Text;
}

enum ServiceWorkerState {
    installing  @0;   # Script is being downloaded and installed
    installed   @1;   # Script is installed, waiting for activation
    activating  @2;   # Service worker is being activated
    activated   @3;   # Service worker is active and handling events
    redundant   @4;   # Service worker is obsolete
    custom      @5;   # Backend-specific state
}

struct ServiceWorkerInfo {
    # Registration state.
    state @0 :ServiceWorkerState;
    # Whether a new update is waiting.
    updateWaiting @1 :Bool;
    # Last update timestamp.
    lastUpdated @2 :T.Timestamp;
}

# ── Audit-8: Proxy Configuration ──────────────────────────────────────

struct ProxyConfig {
    # Proxy type.
    proxyType @0 :ProxyType;
    # Proxy host.
    host @1 :Text;
    # Proxy port.
    port @2 :UInt16;
    # Optional username for proxy authentication.
    username @3 :Text;
    # Optional password for proxy authentication.
    password @4 :Text;
    # Bypass list (URLs that bypass the proxy).
    bypassList @5 :List(Text);
    # PAC file URL (for proxyType = pac).
    pacUrl @6 :Text;
}

enum ProxyType {
    http    @0;   # HTTP proxy
    socks5  @1;   # SOCKS5 proxy
    pac     @2;   # Proxy auto-configuration
    direct  @3;   # Direct connection (no proxy)
    custom  @4;   # Backend-specific proxy type
}

# ── Audit-8: WebAuthn ─────────────────────────────────────────────────

struct WebAuthnRegisterRequest {
    # Relying party name.
    rpName @0 :Text;
    # User identifier.
    userId @1 :Data;
    # User display name.
    userName @2 :Text;
    # Preferred authenticator types.
    authenticatorTypes @3 :List(Text);
    # Timeout in milliseconds.
    timeout @4 :UInt32;
}

struct WebAuthnAuthenticateRequest {
    # Relying party ID.
    rpId @0 :Text;
    # Allowed credential IDs.
    allowedCredentials @1 :List(T.DataHandle);
    # Timeout in milliseconds.
    timeout @2 :UInt32;
}

struct WebAuthnCredential {
    # Credential identifier.
    id @0 :T.DataHandle;
    # Credential type (e.g., "public-key").
    type @1 :Text;
    # Supported transports.
    transports @2 :List(Text);
    # Public key.
    publicKey @3 :T.DataHandle;
    # Sign count (for clone protection).
    signCount @4 :UInt64;
    # Relying party ID.
    rpId @5 :Text;
}

struct WebAuthnResult {
    union {
        success @0 :WebAuthnCredential;
        error   @1 :T.Error;
    }
}

# ── Audit-8: CDN Info ─────────────────────────────────────────────────

struct CDNInfo {
    # Edge server hostname.
    edgeServer @0 :Text;
    # Whether the response was served from cache.
    cacheHit @1 :Bool;
    # Age of the cached response.
    cacheAge @2 :T.Duration;
    # Geographic region of the edge server.
    geographicRegion @3 :Text;
    # Remaining TTL.
    ttlRemaining @4 :T.Duration;
}

# ── Audit-8: Privacy Configuration ────────────────────────────────────

struct PrivacyConfig {
    # Enable tracking protection.
    trackingProtection @0 :Bool;
    # Enable storage partitioning (per-origin).
    storagePartitioning @1 :Bool;
    # Enable first-party isolation.
    firstPartyIsolation @2 :Bool;
    # Cookie policy.
    cookiePolicy @3 :CookiePolicy;
    # Enable fingerprint protection.
    fingerprintProtection @4 :Bool;
    # Blocked tracking domains.
    blockedDomains @5 :List(Text);
}

enum CookiePolicy {
    acceptAll       @0;   # Accept all cookies
    rejectThirdParty @1;  # Reject third-party cookies
    blockAll        @2;   # Block all cookies
    custom          @3;   # Backend-specific cookie policy
}

# ── Audit-8: HTTP/2 Stream ────────────────────────────────────────────

struct Http2Stream {
    # Stream identifier.
    streamId @0 :UInt32;
    # Stream priority.
    priority @1 :UInt8;
    # Request headers.
    headers @2 :T.StringMap;
    # Stream data.
    data @3 :T.DataHandle;
    # Whether this is the last frame.
    endStream @4 :Bool;
}

# ── Audit-8: WebRTC ───────────────────────────────────────────────────

struct WebRtcSession {
    # Session identifier.
    sessionId @0 :Text;
    # Session state.
    state @1 :WebRtcState;
    # ICE connection state.
    iceState @2 :Text;
    # DTLS connection state.
    dtlsState @3 :Text;
}

enum WebRtcState {
    new         @0;   # New session
    connecting  @1;   # Establishing connection
    connected   @2;   # Connection established
    disconnected @3;  # Connection temporarily lost
    failed      @4;   # Connection failed
    closed      @5;   # Session closed
    custom      @6;   # Backend-specific state
}

# ── Audit-8: CORS Policy ──────────────────────────────────────────────

struct CorsPolicy {
    # Allowed origins (empty = deny all).
    allowedOrigins @0 :List(Text);
    # Allowed HTTP methods.
    allowedMethods @1 :List(HttpMethod);
    # Allowed headers.
    allowedHeaders @2 :List(Text);
    # Whether credentials are allowed.
    credentials @3 :Bool;
    # Max age for preflight cache.
    maxAge @4 :T.Duration;
    # Exposed headers.
    exposedHeaders @5 :List(Text);
}

# ── Audit-8: CSP Report ───────────────────────────────────────────────

struct CspReport {
    # Document URI where violation occurred.
    documentUri @0 :Text;
    # Violated directive.
    violatedDirective @1 :Text;
    # Blocked URI.
    blockedUri @2 :Text;
    # Source file.
    sourceFile @3 :Text;
    # Line number in source.
    lineNumber @4 :UInt32;
    # Timestamp of violation.
    timestamp @5 :T.Timestamp;
}

# ── Audit-8: Abort Controller ─────────────────────────────────────────

struct AbortSignal {
    # Whether the signal has been aborted.
    aborted @0 :Bool;
    # Reason for abort (if aborted).
    reason @1 :Text;
}

# ── Audit-8: Readable Stream ──────────────────────────────────────────

struct ReadableStreamChunk {
    # Data chunk.
    data @0 :T.DataHandle;
    # Whether this is the final chunk.
    done @1 :Bool;
}

# ── Audit-8: Storage Estimate ─────────────────────────────────────────

struct StorageEstimate {
    # Current usage in bytes.
    usage @0 :UInt64;
    # Quota in bytes.
    quota @1 :UInt64;
}

# ── Audit-9: Service Worker Fetch Event ────────────────────────────────────

struct FetchEvent {
    # Request that triggered the fetch.
    request @0 :HttpRequest;
    # Client ID (service worker client).
    clientId @1 :Text;
    # Is this a navigation request.
    isNavigation @2 :Bool;
    # Preload response (if available).
    preloadResponse @3 :HttpResponse;
    # Timestamp.
    timestamp @4 :T.Timestamp;
}

# ── Audit-9: Readable Stream Reader ────────────────────────────────────────

interface ReadableStreamReader {
    # Read the next chunk.
    read @0 () -> (chunk :ReadableStreamChunk);
    # Cancel the stream.
    cancel @1 () -> T.VoidResult;
    # Release the reader.
    release @2 () -> T.VoidResult;
}

# ── Audit-9: WebRTC SDP Negotiation ────────────────────────────────────────

struct SdpOffer {
    sessionId @0 :Text;
    sdp @1 :Text;
    # Offer timestamp.
    timestamp @2 :T.Timestamp;
}

struct SdpAnswer {
    sessionId @0 :Text;
    sdp @1 :Text;
    # Answer timestamp.
    timestamp @2 :T.Timestamp;
}

# ── Audit-9: HTTP/2 Server Push ────────────────────────────────────────────

struct PushPromise {
    # Path to push.
    path @0 :Text;
    # Headers for the pushed response.
    headers @1 :T.StringMap;
    # Whether the push is for a GET request.
    isGet @2 :Bool;
}

# ── Audit-10: WebRTC ICE Candidate ─────────────────────────────────────

struct IceCandidate {
    # Candidate foundation (unique identifier).
    foundation @0 :Text;
    # Component ID (1 = RTP, 2 = RTCP).
    component @1 :UInt16;
    # Transport protocol (UDP, TCP).
    transport @2 :Text;
    # Priority value.
    priority @3 :UInt32;
    # Candidate address (IP:port or hostname:port).
    address @4 :Text;
    # Candidate type (host, srflx, relay, prflx).
    candidateType @5 :Text;
    # Related address (for server reflexive/relay candidates).
    relatedAddress @6 :Text;
    # Timestamp when candidate was gathered.
    timestamp @7 :T.Timestamp;
}

# ── Audit-10: WebRTC Data Channel ──────────────────────────────────────

struct DataChannelConfig {
    # Channel label.
    label @0 :Text;
    # Whether the channel is ordered.
    ordered @1 :Bool = true;
    # Max retransmit time in milliseconds (0 = default).
    maxRetransmitTime @2 :UInt32;
    # Max retransmit count (0 = default).
    maxRetransmits @3 :UInt32;
    # Protocol name.
    protocol @4 :Text;
    # Whether this is a legacy SCTP channel.
    negotiated @5 :Bool = false;
    # Channel ID (if negotiated).
    channelId @6 :UInt16;
}

struct DataChannel {
    # Channel identifier.
    channelId @0 :Text;
    # Channel label.
    label @1 :Text;
    # Whether the channel is ordered.
    ordered @2 :Bool;
    # Current channel state.
    state @3 :DataChannelState;
    # Messages sent.
    messagesSent @4 :UInt64;
    # Bytes sent.
    bytesSent @5 :UInt64;
}

enum DataChannelState {
    connecting @0;
    open @1;
    closing @2;
    closed @3;
    custom @4;
}

# ── Audit-10: WebAuthn Attestation Verification ────────────────────────

struct WebAuthnAttestation {
    # Attestation object (CBOR-encoded).
    attestationObject @0 :Data;
    # Client data JSON.
    clientDataJson @1 :Data;
    # Authenticator data.
    authenticatorData @2 :Data;
}

struct WebAuthnAttestationResult {
    # Whether verification succeeded.
    success @0 :Bool;
    # Verified credential (if successful).
    credential @1 :WebAuthnCredential;
    # Attestation format (e.g., "none", "fido-u2f", "packed", "tpm").
    format @2 :Text;
    # Attestation trust level.
    trustLevel @3 :AttestationTrustLevel;
    # Error message (if failed).
    error @4 :Text;
}

enum AttestationTrustLevel {
    # Attestation ca is trusted by the Relying Party.
    trusted @0;
    # Attestation is from an untrusted CA.
    untrusted @1;
    # Attestation format does not include attestation.
    none @2;
    # Attestation verification failed.
    failed @3;
    custom @4;
}

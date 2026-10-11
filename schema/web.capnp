@0xa1b2c3d4e5f60020;

using T = import "types.capnp";
using S = import "socket.capnp";

# ═══════════════════════════════════════════════════════════════════════
# Web — HTTP fetch, WebSocket, URL primitives.
#
# Backend-agnostic. The HTTP transport may be any library, a custom
# stack, or a synthetic offline backend for tests. The protocol
# describes request/response and lifecycle — never the transport.
#
# Fixes this revision makes:
#   - `fetch` can FAIL. The result was a bare `HttpResponse`, so a
#     refused connection, a DNS failure and a TLS failure all had to be
#     encoded as a `status` code — meaning "server answered 500" and "we
#     never reached the server" were the same shape. The result is now a
#     union carrying T.Error; `status` keeps its HTTP meaning.
#   - Transport security is expressible: `wss://` and any secure fetch
#     take the canonical TlsConfig from socket.capnp, which is where the
#     verification semantics are defined. Previously the URL implied TLS
#     and nothing said whether the peer certificate must be checked.
#   - WebSocket binary payloads are T.DataHandle. Binary frames are
#     arbitrary length; both directions were inline Data in a file whose
#     HTTP bodies had already been converted.
#   - `getStreamReader` takes a stream. It used to take a *chunk*, which
#     cannot be implemented as written without an out-of-band
#     chunk-to-stream map.
#   - WebRTC session state is observable (a typed session with typed
#     states), and SDP has one representation (the typed structs), not
#     one typed and one raw.
#   - Deleted: the service-worker block (a browser-runtime mechanism an
#     OS-level fetch service has no equivalent for), HTTP/2 server push
#     keyed by raw stream ids with no stream object, and five types
#     returned by no method (Http2Stream, CspReport, AbortSignal,
#     StorageEstimate, ServiceWorkerInfo).
#   - The local ProxyConfig/ProxyType are gone in favour of socket's,
#     which is now the single proxy home.
# ═══════════════════════════════════════════════════════════════════════

interface WebService {

    fetch @0 (request :HttpRequest) -> (result :HttpFetchResult);
    fetchStream @1 (request :HttpRequest) -> (stream :HttpStream);

    # `security` configures the channel for `wss://` (and any future
    # secure scheme). Absent = the backend's default, which MUST still
    # verify the peer unless the config says otherwise — see the
    # verification semantics in socket.capnp.
    openWebSocket @2 (url :Text, protocols :List(Text), security :S.TlsConfig)
                     -> (connection :WebSocketConnection);

    resolveUrl @3 (url :Text, baseUrl :Text) -> (resolved :Text);
    encodeUrl  @4 (url :Text) -> (encoded :Text);
    decodeUrl  @5 (url :Text) -> (decoded :Text);

    # Parse an HTML document. The document is content (T.DataHandle),
    # not an inline string.
    parseHtml @6 (html :T.DataHandle) -> (parsed :ParsedHtml);

    # ── Proxy (canonical home: socket.capnp) ──
    setProxyConfig @7 (config :S.ProxyConfig) -> T.VoidResult;
    getProxyConfig @8 () -> (config :S.ProxyConfig);

    # ── WebAuthn ──
    registerWebAuthn @9 (request :WebAuthnRegisterRequest) -> (result :WebAuthnRegisterResult);
    authenticateWebAuthn @10 (request :WebAuthnAuthenticateRequest) -> (result :WebAuthnResult);
    listWebAuthnCredentials @11 (pagination :T.Pagination) -> (credentials :List(WebAuthnCredential), totalCount :UInt64);
    deleteWebAuthnCredential @12 (credentialId :WebAuthnCredentialId) -> T.VoidResult;

    # ── CDN info ──
    getCdnInfo @13 (url :Text) -> (result :CdnInfoResult);

    # ── Privacy configuration ──
    getPrivacyConfig @14 () -> (config :PrivacyConfig);
    setPrivacyConfig @15 (config :PrivacyConfig) -> T.VoidResult;

    # ── CORS policy ──
    getCorsPolicy @16 (url :Text) -> (result :CorsPolicyResult);
    checkCors @17 (origin :Text, url :Text, method :Text) -> (allowed :Bool);

    # ── Stream readers ──
    getStreamReader @18 (stream :HttpStream) -> (reader :ReadableStreamReader);

    # ── WebRTC session lifecycle ──
    createWebRtcOffer @19 (sessionId :Text) -> (result :WebRtcOfferResult);
    createWebRtcAnswer @20 (sessionId :Text, offer :SdpOffer) -> (result :WebRtcAnswerResult);
    setLocalDescription @21 (sessionId :Text, sdp :SdpDescription) -> T.VoidResult;
    setRemoteDescription @22 (sessionId :Text, sdp :SdpDescription) -> T.VoidResult;
    getLocalDescription @23 (sessionId :Text) -> (result :SdpResult);
    getWebRtcSession @24 (sessionId :Text) -> (result :WebRtcSessionResult);

    # ── WebRTC ICE candidates ──
    addIceCandidate @25 (sessionId :Text, candidate :IceCandidate) -> T.VoidResult;
    getIceCandidates @26 (sessionId :Text, pagination :T.Pagination) -> (candidates :List(IceCandidate), totalCount :UInt64);
    removeIceCandidate @27 (sessionId :Text, candidate :IceCandidate) -> T.VoidResult;

    # ── WebRTC data channel ──
    createDataChannel @28 (sessionId :Text, label :Text, config :DataChannelConfig) -> (result :DataChannelResult);
    sendDataChannelMessage @29 (sessionId :Text, channelId :Text, data :T.DataHandle) -> T.VoidResult;
    closeDataChannel @30 (sessionId :Text, channelId :Text) -> T.VoidResult;

    # ── WebAuthn attestation ──
    verifyWebAuthnAttestation @31 (attestation :WebAuthnAttestation) -> (result :WebAuthnAttestationResult);
}

# ── Streaming ──────────────────────────────────────────────────────────

interface HttpStream {
    pull   @0 () -> (chunk :T.DataHandle, done :Bool);
    cancel @1 () -> T.VoidResult;
}

# ── WebSocket ──────────────────────────────────────────────────────────

interface WebSocketConnection {
    send        @0 (data :T.DataHandle) -> T.VoidResult;
    sendText    @1 (text :Text) -> T.VoidResult;
    close       @2 (code :WebSocketCloseCode, reason :Text) -> T.VoidResult;
    subscribeMessages @3 () -> (subscription :MessagesSubscription);
}

interface MessagesSubscription {
    pull   @0 () -> (messages :List(WebSocketMessage));
    cancel @1 () -> T.VoidResult;

    # Paginated message retrieval. Returns at most `pagination.limit`
    # messages starting at `pagination.offset`.
    pullPaged @2 (pagination :T.Pagination)
              -> (messages :List(WebSocketMessage), totalCount :UInt64);
}

# ── HTTP Request / Response ───────────────────────────────────────────

enum HttpMethod {
    unknown @0;
    get     @1;
    head    @2;
    post    @3;
    put     @4;
    delete  @5;
    connect @6;
    options @7;
    trace   @8;
    patch   @9;
    custom  @10;
}

struct HttpRequest {
    method     @0 :HttpMethod;
    # URL as text. HTTP URLs have scheme, percent-encoding and query
    # semantics that a generic T.Uri does not capture; text is the honest
    # spelling, and the scheme's security meaning is in `security`.
    url        @1 :Text;
    headers    @2 :T.StringMap;
    # Inline for small bodies, buffer-handle for >1KB.
    body       @3 :T.DataHandle;
    timeout    @4 :T.Duration;
    # Channel security for https:// and wss:// (canonical TLS home).
    security   @5 :S.TlsConfig;
    followRedirects @6 :Bool = true;
    maxRedirects @7 :UInt32;
    metadata @8 :T.StringMap;
}

struct HttpFetchResult {
    union {
        response @0 :HttpResponse;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
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
    latencyMeasured @6 :Bool;
}

# ── WebSocket ─────────────────────────────────────────────────────────

struct WebSocketMessage {
    type @0 :WebSocketMessageType;
    data @1 :T.DataHandle;
    text @2 :Text;
    metadata @3 :T.StringMap;
}

enum WebSocketMessageType {
    unknown @0;
    text    @1;
    binary  @2;
    ping    @3;
    pong    @4;
    close   @5;
    custom  @6;
}

# WebSocket close codes. RFC 6455 + a vendor-defined escape hatch.
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
    metadata @3 :T.StringMap;
}

struct HtmlImage {
    src    @0 :Text;
    alt    @1 :Text;
    width  @2 :UInt32;
    height @3 :UInt32;
    metadata @4 :T.StringMap;
}

# ── WebAuthn ──────────────────────────────────────────────────────────

# An identifier, not a payload: the previous spelling typed it as a
# T.DataHandle, conflating "reference to bulk data" with "identity".
struct WebAuthnCredentialId {
    id @0 :Data;
}

struct WebAuthnRegisterRequest {
    rpName @0 :Text;
    userId @1 :Data;
    userName @2 :Text;
    # Preferred authenticator types as open tokens.
    authenticatorTypes @3 :List(Text);
    timeout @4 :T.Duration;
}

struct WebAuthnAuthenticateRequest {
    rpId @0 :Text;
    allowedCredentials @1 :List(WebAuthnCredentialId);
    timeout @2 :T.Duration;
    metadata @3 :T.StringMap;
}

struct WebAuthnCredential {
    id @0 :WebAuthnCredentialId;
    # Credential type (e.g., "public-key") as an open token.
    type @1 :Text;
    transports @2 :List(Text);
    publicKey @3 :T.DataHandle;
    signCount @4 :UInt64;
    rpId @5 :Text;
    metadata @6 :T.StringMap;
}

struct WebAuthnRegisterResult {
    union {
        credential @0 :WebAuthnCredential;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct WebAuthnResult {
    union {
        success @0 :WebAuthnCredential;
        error   @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct WebAuthnAttestation {
    # Attestation object (CBOR-encoded), as content.
    attestationObject @0 :T.DataHandle;
    # Client data JSON, as content.
    clientDataJson @1 :T.DataHandle;
    # Authenticator data, as content.
    authenticatorData @2 :T.DataHandle;
    metadata @3 :T.StringMap;
}

struct WebAuthnAttestationResult {
    union {
        verified @0 :WebAuthnVerification;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct WebAuthnVerification {
    credential @0 :WebAuthnCredential;
    # Attestation format as an open token ("none", "packed", "tpm", ...).
    format @1 :Text;
    # Attestation trust level as an open token ("trusted", "untrusted",
    # "none", "failed"): reported, not switched on.
    trustLevel @2 :Text;
    metadata @3 :T.StringMap;
}

# ── CDN Info ──────────────────────────────────────────────────────────

struct CdnInfoResult {
    union {
        cdn @0 :CDNInfo;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct CDNInfo {
    edgeServer @0 :Text;
    cacheHit @1 :Bool;
    cacheAge @2 :T.Duration;
    geographicRegion @3 :Text;
    ttlRemaining @4 :T.Duration;
    metadata @5 :T.StringMap;
}

# ── Privacy Configuration ────────────────────────────────────────────

struct PrivacyConfig {
    trackingProtection @0 :Bool;
    storagePartitioning @1 :Bool;
    firstPartyIsolation @2 :Bool;
    cookiePolicy @3 :CookiePolicy;
    fingerprintProtection @4 :Bool;
    blockedDomains @5 :List(Text);
    metadata @6 :T.StringMap;
}

enum CookiePolicy {
    unknown @0;
    acceptAll @1;
    rejectThirdParty @2;
    blockAll @3;
    custom @4;
}

# ── CORS Policy ───────────────────────────────────────────────────────

struct CorsPolicyResult {
    union {
        policy @0 :CorsPolicy;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct CorsPolicy {
    allowedOrigins @0 :List(Text);
    allowedMethods @1 :List(HttpMethod);
    allowedHeaders @2 :List(Text);
    credentials @3 :Bool;
    maxAge @4 :T.Duration;
    exposedHeaders @5 :List(Text);
    metadata @6 :T.StringMap;
}

# ── Readable Stream ───────────────────────────────────────────────────

struct ReadableStreamChunk {
    data @0 :T.DataHandle;
    done @1 :Bool;
    metadata @2 :T.StringMap;
}

interface ReadableStreamReader {
    read @0 () -> (result :ReadableStreamResult);
    cancel @1 () -> T.VoidResult;
    release @2 () -> T.VoidResult;
}

struct ReadableStreamResult {
    union {
        chunk @0 :ReadableStreamChunk;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

# ── WebRTC ────────────────────────────────────────────────────────────

struct WebRtcOfferResult {
    union {
        offer @0 :SdpOffer;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct WebRtcAnswerResult {
    union {
        answer @0 :SdpAnswer;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct SdpResult {
    union {
        sdp @0 :SdpDescription;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct WebRtcSessionResult {
    union {
        session @0 :WebRtcSession;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

struct DataChannelResult {
    union {
        channel @0 :DataChannel;
        error @1 :T.Error;
        unknown @2 :T.UnknownEvent;
    }
}

# One representation for SDP. The file used to carry typed SdpOffer /
# SdpAnswer structs beside raw `sdp :Text` parameters on the set/get
# methods, with no rule for which won.
struct SdpDescription {
    sessionId @0 :Text;
    # The SDP document itself, as content.
    sdp @1 :T.DataHandle;
    timestamp @2 :T.Timestamp;
    metadata @3 :T.StringMap;
}

struct SdpOffer {
    sessionId @0 :Text;
    sdp @1 :T.DataHandle;
    timestamp @2 :T.Timestamp;
    metadata @3 :T.StringMap;
}

struct SdpAnswer {
    sessionId @0 :Text;
    sdp @1 :T.DataHandle;
    timestamp @2 :T.Timestamp;
    metadata @3 :T.StringMap;
}

# Observable session state. The previous revision declared this struct
# and returned it from nothing, so a consumer could not learn whether a
# session connected, ICE completed, or failed.
struct WebRtcSession {
    sessionId @0 :Text;
    state @1 :WebRtcState;
    # ICE and DTLS state as open tokens: the state machines are the
    # backend's, and a 2046 stack's phases are its own.
    iceState @2 :Text;
    dtlsState @3 :Text;
    metadata @4 :T.StringMap;
}

enum WebRtcState {
    unknown @0;
    new @1;
    connecting @2;
    connected @3;
    disconnected @4;
    failed @5;
    closed @6;
    custom @7;
}

struct IceCandidate {
    foundation @0 :Text;
    component @1 :UInt16;
    # Transport protocol as an open token.
    transport @2 :Text;
    priority @3 :UInt32;
    # Candidate address (host:port or hostname:port).
    address @4 :Text;
    # Candidate type as an open token ("host", "srflx", "relay", "prflx").
    candidateType @5 :Text;
    relatedAddress @6 :Text;
    timestamp @7 :T.Timestamp;
    metadata @8 :T.StringMap;
}

struct DataChannelConfig {
    label @0 :Text;
    ordered @1 :Bool = true;
    maxRetransmitTime @2 :T.Duration;
    maxRetransmits @3 :UInt32;
    # Protocol name as an open token.
    protocol @4 :Text;
    negotiated @5 :Bool = false;
    channelId @6 :UInt16;
    metadata @7 :T.StringMap;
}

struct DataChannel {
    channelId @0 :Text;
    label @1 :Text;
    ordered @2 :Bool;
    state @3 :DataChannelState;
    messagesSent @4 :UInt64;
    bytesSent @5 :UInt64;
    metadata @6 :T.StringMap;
}

enum DataChannelState {
    unknown @0;
    connecting @1;
    open @2;
    closing @3;
    closed @4;
    custom @5;
}

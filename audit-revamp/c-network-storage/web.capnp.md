# Audit — web.capnp (631 lines)

## Verdict
**FIX (targeted).** DESIGN_PRINCIPLES.md:547 calls this a "clean contract" and that is still true of the core: `fetch`/`fetchStream`/`openWebSocket`, `T.DataHandle` bodies, `HttpStream` with a `done` terminator, paginated WebAuthn listing. The Audit-8/9/10 additions are where it erodes: WebRTC, service workers, and HTTP/2 push were added as structs without checking reachability, leaving six dead types, a session state machine with no observable state, and one signature (`getStreamReader`) that can't mean what it says. Also: `fetch` has no error path, and transport security has no expression at all.

## Wire-breakers
None (compiles clean). `ProxyConfig`/`ProxyType` (:272/:289) collide with `endpoint.capnp:732/:751` and `socket.capnp:162/:177` — three incompatible vocabularies. `WebSocketMessageType`/`HttpMethod` are unremarkable but `HttpMethod.custom @9` :Text is absent — actually a plain enum variant, so a new HTTP method has no value (see R1).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R7 | `web.capnp:25`, `:175-184` | `fetch @0 -> HttpResponse` — `HttpResponse` has no error field; transport failure (DNS, refused, TLS, timeout) is unrepresentable (`status :UInt16` describes an HTTP response, not a failed connection) | A consumer cannot distinguish "server answered 500" from "connection refused". Every backend forks on a convention: `status = 0`? empty body? an error field at a new ordinal? Two client behaviors for the same failure — the same swallow-error defect as `dns.capnp:524` |
| R7 | `web.capnp:87` | `getStreamReader @22 (stream :ReadableStreamChunk) -> (reader :ReadableStreamReader)` | The parameter is a *data chunk*, not a stream handle — you pass a chunk to obtain a reader of the stream it came from. The signature cannot be implemented as written without inventing a chunk→stream map. Implementer trap in the literal sense |
| R8 | `web.capnp:399-408` | `WebRtcSession { sessionId, state, iceState, dtlsState }` is returned by no method; `WebRtcState`/`DataChannelState` enums likewise unreachable | The WebRTC session lifecycle is advertised with no observable state — `createWebRtcOffer @23` returns `SdpOffer`, `setLocalDescription @25` takes raw `sdp :Text` while the typed `SdpOffer`/`SdpAnswer` structs exist. A consumer cannot learn whether a session connected, ICE-completed, or failed. Backends invent state reporting outside the contract |
| R8 | `web.capnp:384-395`, `:439-452`, `:456-461`, `:474-479`, `:261-268` | `Http2Stream`, `CspReport`, `AbortSignal`, `StorageEstimate`, `ServiceWorkerInfo` — five more types returned by no method in the repo | False contract surface; `AbortSignal`/`CspReport` are language-runtime artifacts (JS) frozen into the protocol |
| R7 | `web.capnp:28-29` | `openWebSocket(url :Text, protocols)` — no TLS/trust configuration anywhere in the file | Whether `wss://` must verify the peer certificate is undefined. Two implementers build clients with different security postures for the same call — a demonstrated fork (endpoint.capnp *has* `TlsConfig` with `verifyMode`; web.capnp references nothing) |
| R1 | `web.capnp:252-259` | `ServiceWorkerState` = installing/installed/activating/activated/redundant | A browser-runtime state machine frozen into the contract; a 2046 module-based worker lifecycle has no value. `custom @5` is a valueless enum variant |
| R1 | `web.capnp:147-158` | `HttpMethod.get/head/post/put/delete/connect/options/trace/patch/custom` | The set is RFC-closed (defensible), but a method added by a future RFC has only the valueless `custom @9` |
| R2 | `web.capnp:128`, `:190` | `WebSocketConnection.send @0 (data :Data)` and `WebSocketMessage.data @1 :Data` | Binary WebSocket frames are arbitrary length — this is a bulk transport path (file transfer over WS) and both directions are inline. `T.DataHandle`/`T.MimeType`+handle is the fix; note `HttpRequest.body`/`HttpResponse.body` were already converted (:167/:180), so the inconsistency is inside one file |
| R4 | `web.capnp:323`, `:66` | `WebAuthnCredential.id :T.DataHandle` / `deleteWebAuthnCredential(credentialId :T.DataHandle)` | An identifier carried as a *payload buffer* type. It works (opaque) but conflates "reference to bulk data" with "identity", the exact distinction R4 draws |

Validator counts: E7 ×23, E8 ×8, E6 ×1 (`WebAuthnResult` union lacks unknown/custom).

## Duplicates & overlaps
- `ProxyConfig`/`ProxyType` — third family (endpoint/socket/web).
- `Http2Stream` (:384) vs `endpoint.capnp:823` `Http2Settings` — HTTP/2 modeled twice with different purposes (stream vs settings) and no cross-reference.
- `CorsPolicy`/`CspReport`/`CookiePolicy` — policy vocabularies that overlap `dns.capnp` `DnsResponsePolicy`/`BlocklistCategory` (the batch has two independent "policy category" taxonomies).
- `AttestationTrustLevel` (:621) vs `types.capnp:550` `TrustLevel` — two trust-level enums, different values.

## Gaps & holes
- **Transport security**: no way to require certificate verification, pin a certificate, or select a TLS version anywhere in `web.capnp` (see R7 row). This is the batch transport gap's sharpest edge because `wss://` implies TLS the URL only.
- `pushResource @28 (streamId :UInt32, pushPromises)` (:97) — HTTP/2 server push as standalone calls keyed by raw stream IDs with no stream object to attach them to; `cancelPush @35` likewise. Consumer must track stream lifetimes manually.
- No fetch cancellation besides subscription cancel — `HttpStream.cancel` exists (good), but `fetch @0` (one-shot) cannot be cancelled midway.

## Zero-cost / eco
- `HttpRequest.body`/`HttpResponse.body`/`ReadableStreamChunk.data`/`Http2Stream.data` are `T.DataHandle` — correct.
- `WebSocketMessage.data`/`send(data :Data)` inline — bulk on a streaming path (see R2 row).
- No polling pattern; streams are pull+cancel with `done`.

## UX & implementer guidance
- `handleFetchEvent @21 (event :FetchEvent) -> HttpResponse` (:84): `FetchEvent` embeds a full `HttpRequest` **and** a `preloadResponse :HttpResponse` (:491) — the event copies a request and a response into every delivery. Also service-worker interception is a browser-runtime mechanism; an OS-level fetch service has no equivalent, so the method is unimplementable off-browser.
- `verifyWebAuthnAttestation @36` returns `WebAuthnAttestationResult` with `error :Text` (:618) — a text error where the file elsewhere uses `T.Error` (`WebAuthnResult.error @1 :T.Error` :339). Two error conventions in one feature.
- `SdpOffer`/`SdpAnswer` typed structs coexist with `setLocalDescription(sdp :Text)`/`getLocalDescription() -> sdp :Text` (:92-94) — SDP has two representations, typed and raw, with no rule for which.

## Recommended actions
1. **Add an error path to `fetch`**: wrap `HttpResponse` in `union { response @0 :HttpResponse; error @1 :T.Error; }` (or add `error @6 :T.Error` to the struct, keeping `status` for HTTP semantics). Gain: connection failures become honest and retryable-settable; the dns.capnp pattern and this one should be fixed in the same wave. Cost: one type change on the batch's most-used method — cheapest now, before release.
2. **Fix or delete `getStreamReader @22`**: if the intent is "reader for an `HttpStream`", take `stream :HttpStream`; if it is "reader from a chunk stream", return it from `fetchStream` instead. Gain: removes a signature that cannot be implemented as written. Cost: one method signature.
3. **Wire the WebRTC session lifecycle or remove it**: add `getWebRtcSession @37 (sessionId :Text) -> (session :WebRtcSession)` (or extend `createWebRtcOffer` to return the session). Gain: session state becomes observable; two backends stop inventing reporting. Cost: one method, or delete six dead types (see next).
4. **Delete the dead types** (`Http2Stream`, `CspReport`, `AbortSignal`, `StorageEstimate`, `ServiceWorkerInfo`) or wire each to a method. Gain: removes ~90 lines of false surface. Cost: zero.
5. **Reference a shared `TlsConfig`** for `wss://` and any future secure fetch (batch action: promote to types.capnp). Gain: transport security expressible where it was previously URL-implied. Cost: one field + a types.capnp promotion.
6. **Convert WebSocket binary payloads to `T.DataHandle`** (`WebSocketMessage.data`, `send`). Gain: the WS bulk path stops copying. Cost: two field type changes, consistent with the same file's already-converted HTTP bodies.

# Audit — system_search.capnp (442 lines)

## Verdict
**FIX (targeted).** Two strong positives: the file's search icons and thumbnails were migrated to `T.DataHandle` (`:113`, `:167`, `:169`, `:189`) and every monetised interface is reachable (R8 passes). Against that: the file's own hot payload — the query embedding — is still inline `Data`, in a file whose header advertises the handle migration; and the identifier that a caller must pass back to act on a result has a *different type* from the field it is meant to reference. Both are concrete, not stylistic.

## Wire-breakers
No ordinal collisions (`SystemSearch` @0–@23 unique, `:36-93`). One type-level break that will not compile at a call site:
- `SearchResult.resultId @12 :Text` (`:181`) is the stable identifier of a result, but `executeResult @7 (resultId :T.SearchProviderId, action :Text)` (`:46`) demands a **provider** id. You cannot pass `SearchResult.resultId` to `executeResult`. The same mismatch appears at `SearchHandler.execute @1` (`:102`), `getResultPreview @19 (resultId :T.SearchProviderId)` (`:77`), `explainResults @11 (resultIds :List(Text))` (`:55`), and `deduplicateResults @13` which returns `duplicates :List(Text)` (`:63`). Result identity has three incompatible spellings in one file.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R2 | `system_search.capnp:196` `VectorQuery.embedding @0 :Data` — comment says "float32 array serialized as bytes" | The batch's named hot data (embeddings) inline, in the file whose header brags "SearchResult.icon/thumbnail use T.DataHandle (was raw Data)" (`:9-11`) | A 1536-dim float32 vector is 6 KB copied into every semantically-searched query; federated search across N providers (`federatedSearch @10`, `:51`) multiplies it by N. `T.DataHandle` exists and is used four lines away in the same file for icons 100× smaller |
| R4 | `system_search.capnp:181` + `:46` + `:77` + `:102` | `resultId` is `Text` on the result and `T.SearchProviderId` on the methods that consume it | The caller cannot act on a result: there is no correct value to pass. Every implementer must invent an encoding that bridges Text and UInt64, and no two will choose the same one. This is a wire-level type error in the file's core interaction |
| R7 | `system_search.capnp:141-142` `SearchQuery.limit @3` + `offset @4` **and** `search @4 -> (results, pagination :T.Pagination, total)` (`:42`) | Two pagination models in one interface with no precedence | Which wins when both are set? A backend honouring `SearchQuery.limit` and a backend honouring `T.Pagination` return different result sets for the same call, with no way for a consumer to detect which happened |
| R1 | `system_search.capnp:122-135` `SearchResultType` (application/file/music/video/image/document/contact/calendar/web/setting/command/custom) | Open result taxonomy frozen, and reused by `SearchFacet`, `ResultTypeCount`, `SearchAutocomplete` (`:344`, `:423`, `:382`) | A 2046 provider indexing "message", "note", "reminder", "sensorReading" or "email" has `custom @11` carrying nothing — and because the enum also drives the facet counts, an unrecognised result type cannot even be reported. `SearchCapabilities.supportedSimilarityMetrics @5` (`:336`) locks the same way |
| R4 | `system_search.capnp:84` `crossDeviceSearch @21 (deviceIds :List(Text))` | Bare Text device identifiers while `T.DeviceId` exists (`types.capnp:412`) | Cross-device result provenance (`CrossDeviceSearchResult.deviceId @1 :Text`, `:395`) is string-matched by consumers, and two backends' device-id namespaces are unrelated |
| R2 | `system_search.capnp:278` `AgentContext.conversationHistory @2 :List(Text)` | Bulk conversation history inline | An agent's working context is exactly the payload that grows without bound; passing it inline makes every agent query copy the whole history into the message |

## Duplicates & overlaps
- `SimilarityMetric` (`:205-211`) ≡ `content.capnp:389-395` `DistanceMetric`.
- The whole file is the content-centric sibling of `runtime_search.capnp` (the header says so, `:7-13`) and overlaps it on `SearchCapabilities` vs `Capability` advertisement (`:324-339` vs `runtime_search.capnp:238-248`).
- `GraphQuery`/`GraphNode`/`GraphEdge` (`:215-251`) define a graph vocabulary that `contacts.capnp`'s `ContactRelation`/`getRelations @17` and `content.capnp`'s relationship graph also model, each differently.

## Gaps & holes
- **No declared format for `SearchQuery.text`** — is it a query string, a keyword list, a natural-language question, or a regex? `T.Regex` exists (`types.capnp:1481-1484`) and `mimeTypePrefix @1 :Text` (`:151`) is a prefix convention. Providers will interpret the same query differently; a consumer cannot know which provider to trust for "find files edited by bob".
- `SearchResult.relevance @7 :Float32` (`:173`) documents "providers MUST clamp to this range" (`:170-172`) — a MUST that no consumer can verify, with the declared fallback being insertion order. Honest, but it means relevance is not comparable across providers, which is the entire point of federated search.
- `deduplicateResults @13` (`:62-63`) pushes dedup onto the caller and returns duplicates as `List(Text)` with no correlation key to the results the caller supplied.

## Zero-cost & eco
Two passes (icons, thumbnails, previews) and two failures (embedding, conversation history) — see the table. `ResultCluster.results @3 :List(SearchResult)` (`:297`) is unbounded and nested; a federated search returning 20 clusters of 50 results copies all 1000 result structs with their icons-as-handles into one message.

## UX & implementer guidance
- The header (`:9-24`) accurately describes the handle migration; it does not mention that the embedding was left inline, which is precisely the asymmetry a reader would want flagged.
- `SearchAction.id @0 :T.ActionId` (`:187`) — the type is right, but the header comment (`:12`) still says "SearchAction.id uses T.EventId (was raw Text)". The comment describes the *pre-migration* shape and is now wrong; it will send a reader to the wrong type.
- `SearchProvider.priority @5 :UInt32` (`:116`) has no declared direction, and `search @4` has no declared ordering between providers. A consumer cannot predict which provider's result wins a tie.
- `getAutocomplete @20 (partial :Text, maxSuggestions :UInt32)` (`:80-81`) takes a raw count while every other list method here uses `T.Pagination` — a third pagination spelling.

## Recommended actions
1. **Give search results one typed identifier and use it everywhere** (a `T.SearchResultId` promoted to `types.capnp`, or reuse of `T.SearchProviderId`-style wrapping), then fix `executeResult`, `SearchHandler.execute`, `getResultPreview`, `explainResults`, `deduplicateResults`. Gain: a caller can act on a result at all — this is the file's core interaction and it is currently broken by type; cost: one promoted id type plus five signatures.
2. **Make `VectorQuery.embedding` a `T.DataHandle`.** Gain: removes the one remaining bulk copy in the search path and matches the migration the header claims; cost: callers materialise a handle (the same pattern `ai.capnp:117-120` uses).
3. **Pick one pagination model** (`T.Pagination`) and delete `SearchQuery.limit`/`offset`. Gain: federated results become predictable; cost: a field removal.
4. **Open `SearchResultType` to a `Text` token** and keep `SearchFacet` keyed on the same token. Gain: providers can index 2046's content kinds and still report facet counts for them; cost: consumers switch on strings.
5. **Declare the query-text grammar (or point at a conformance-token list).** Gain: two providers stop interpreting one query differently; cost: one paragraph.

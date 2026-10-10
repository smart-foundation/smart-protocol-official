# Audit — database.capnp (720 lines)

## Verdict
**FIX (targeted).** DESIGN_PRINCIPLES.md:511 calls this a "clean key-value contract" and the base 0-15 ordinals still deserve that. Two waves of feature accretion then diluted it: a **SQL query surface in a file whose first sentence says "No SQL"** (:7 vs :177), `List(Float32)` vectors — the exact pattern `ai.capnp:74-75` says must not exist — and a graph/vector/CRDT/event-sourcing feature stack whose result sets are unbounded. The value path also stayed inline `Data` while export/import were converted to `T.DataHandle`.

## Wire-breakers
No compile errors. Name collisions: `KeyValue` (:268 vs `framebuffer.capnp:106`), `KeyMetadata` (:323 vs `key_management.capnp:76`), `KeySubscription` (:416 **struct** vs `key_management.capnp:254` **interface** — a struct/interface name collision), `ChangesSubscription` (:262 vs `clipboard.capnp:88`/`secret.capnp:116` — three interfaces, one name), `ConnectionPoolConfig` (:525 vs `endpoint.capnp:181` — different fields), `ReplicationStatus` (:668 vs `storage.capnp:1068`/`content.capnp:697`), `SimilarityMetric` (:603 vs `system_search.capnp:205`), `GraphEdge` (:572 vs `system_search.capnp:246`), `TransactionStatus` (:355 vs `queue.capnp:416`), `SchemaMigration` (:407 vs `abi.capnp:96`), `QueryResult` (:547 vs `compositor.capnp:773`).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R2 | `database.capnp:613`, `:619`, `:628` | `VectorEntry.vector :List(Float32)`, `VectorSearchRequest.queryVector`, `VectorSearchResult.vector` | `ai.capnp:74-75`: "The validator rejects List(Float32)... for this reason" — and this file keeps the pattern the gold standard rejected. Copy cost: a top-100 search at 4096 dims ships ~1.6 MB of copied floats **per response**, plus the caller's query vector copy on the way in. Dense vectors are content: `Artifact { mimeType, data :T.DataHandle }` with `application/vnd.smart.embedding` (`ai.capnp:606`) |
| R2 | `database.capnp:21`, `:27`, `:269` | `get @0 -> (value :Data)`, `set @4 (value :Data)`, `KeyValue.value :Data` | The primary get/set path is inline while `exportNamespace`/`importNamespace` were correctly converted to `T.DataHandle` (:39-40). Any value >1 KB (a blob, a serialized document) copies inline on every operation |
| R1 | `database.capnp:7` vs `:177`, `:542`, `:400-404`, `:410-411` | Header: "Zero-backend-assumption IPC contract. No SQL, no document store, no specific database engine assumed" — then `query @47 (request :QueryRequest)` "backend-specific SQL-like syntax", `NamespaceSchema.keyPattern`/`valueType`, `SchemaMigration.upScript`/`downScript :Text` | The schema's first sentence is contradicted by its query surface. 2046 failure: a graph/vector/object backend must accept "SQL-like syntax" it doesn't have — and since the protocol never specifies a dialect, every backend invents one anyway, so the field's presence is a promise the contract cannot keep. Two client-level behaviors (dialect assumptions) fork from one sentence |
| R7 | `database.capnp:199`, `:196` | `getNeighbors @53` and `detectCommunities @52` return unbounded lists | A hub node in a graph has unbounded neighbors; `detectCommunities` scales with the dataset. One message must carry them all — a memory blow-up with no pagination parameter while the file's own `listKeys` is paginated |
| R7 | `database.capnp:75-84` | `beginTransaction @23 -> (transaction :Transaction)` but `commitTransaction @24 (transactionId :UInt64)` — holding the `Transaction` struct and holding its raw `id` both authorize commit | Two representations of one handle (struct reference vs raw UInt64) — the "two authority paths" pattern in miniature. `Transaction.id @0 :UInt64` (:336) is what callers actually pass |
| R7 | `database.capnp:248`, `:253` | `readFromSnapshot @66 (snapshotId :Text)`, `deleteSnapshot @67 (snapshotId :Text)` while `createSnapshot @65` returns `DatabaseSnapshot.snapshotId :Text` | Text ids for snapshots with `T.SnapshotId` promoted at `types.capnp:1167` for exactly this purpose |
| R7 | `database.capnp:369-370` | `ChangeCaptureEvent.oldValue`/`newValue :DatabaseValue` inline | CDC doubles the copy cost of every change event (old+new inline). Should be `DataHandle` at least for the value case |
| R8 | `database.capnp:435-442` | `NamespaceQuota` referenced by no method | A third quota type (after `filesystem.capnp`'s and `types.capnp`'s `Quota`) and this one is dead |
| R1 | `database.capnp:556-561`, `:699-704` | `IndexType` = btree/hash/fullText; `ShardStrategy` = hash/range/geo | Storage-internals vocabulary; `custom @3` valueless. (`CrdtType` :634 and `SimilarityMetric` :603 are math-closed and defensible) |

Validator counts: E7 ×30, E8 ×10, E6 ×0.

## Duplicates & overlaps
- All name collisions above (8 real overlaps inside/with the tree).
- `QueryRequest`/`QueryResult` vs `system_search`'s query types — two query surfaces in the tree.
- Vector types (`VectorEntry`, `VectorSearchRequest/Result`) vs `ai.capnp`'s knowledge-base API — the batch's two vector stories, one DataHandle-based, one inline-float-based.
- `AuditLogEntry`/`AuditLogFilter` (:488-503) vs `capability.capnp`'s audit section and `files.capnp`'s `FileAuditEntry` — audit modeled three times in the batch.

## Gaps & holes
- No transaction isolation contract: `Transaction.status @3 :TransactionStatus` exists but nothing states what a reader sees mid-transaction, or what `snapshot` isolation guarantees relative to `beginTransaction`. The word "isolation" appears only in `createSnapshot`. Implementers fork on read-your-writes semantics.
- No change-feed ack/resume contract: `ChangeStreamOptions.fromTimestamp @1` starts from a timestamp, but with no event-id cursor (`EventLogEntry.eventId @0 :UInt64` exists but the CDC stream doesn't expose it) — a reconnecting consumer replays or skips, non-deterministically.
- Connection pool status is exposed (`getConnectionPoolStatus @45`) but nothing says whether pooled connections are capability-scoped — the pool's ownership story is absent.

## Zero-cost / eco
- `get`/`set`/`KeyValue` inline `Data` and inline `List(Float32)` vectors (the two R2 rows above).
- `getBatchMetadata @22`, `detectCommunities @52`, `getNeighbors @53`, `listIndexes @49` — unbounded lists (see R7).
- No polling pattern; all subscriptions are pull+cancel. `EventLogEntry` replay is paginated (:240) — good.

## UX & implementer guidance
- `getTyped @16`/`setTyped @17` (:48/:51) duplicate `get`/`set` with a typed wrapper — two paths for one operation, and nothing says whether they can disagree.
- `query @47` accepts a dialect-free SQL-like string with `page :T.Pagination` — pagination semantics for an arbitrary dialect query (OFFSET? cursor?) are undefined.
- `getTtl @19 -> (remaining :T.Duration, exists :Bool)` (:59) — a tuple where a struct with a sentinel field would be self-describing; `exists` as a parallel bool repeats the tuple pattern.

## Recommended actions
1. **Decide the SQL question honestly**: either (a) remove `query @47`/`SchemaMigration` SQL scripts and state that structured queries live outside this contract, or (b) keep `query` but declare it `Text :T.MimeType`-tagged content (e.g. `query :T.MimeType` + `body :T.DataHandle`) so a dialect is *content*, not a promise. (a) is simpler and honest to the header; (b) is the ai.capnp-shaped fix. Gain: the header stops lying; backends stop inventing dialects. Cost: (a) removes one of the 70 methods — the file gets smaller, which is the point.
2. **Convert vectors to `T.DataHandle`** (`VectorEntry.vector`, `VectorSearchRequest.queryVector`, `VectorSearchResult.vector`) with a documented embedding `T.MimeType` convention + `dimensions` in `T.StringMap` parameters. Gain: vector search stops copying megabytes per call; the batch speaks one vector story. Cost: consumers reshape float arrays through a buffer — the standard `ai.capnp` trade.
3. **Convert `get`/`set`/`KeyValue.value` to `T.DataHandle`** (inline stays valid for small values via `DataHandle.inline`). Gain: blob-sized values stop copying; the asymmetry with export/import disappears. Cost: one type change on the primary path — free now.
4. **Paginate the unbounded result sets** (`getNeighbors`, `detectCommunities`, `getBatchMetadata`, `listIndexes`). Gain: bounded memory per message, matching the file's own `listKeys` convention. Cost: four `T.Pagination` params.
5. **Give the CDC stream a resume cursor** (`ChangeCaptureEvent` gains `sequence :UInt64`, `ChangeStreamOptions` accepts `fromSequence` alongside `fromTimestamp`). Gain: reconnecting consumers resume deterministically instead of replaying or skipping — a demonstrated fork risk. Cost: one field + one option.
6. **Delete `NamespaceQuota`** and point quota at `types.capnp`'s `Quota` or filesystem's. Gain: three quota types become one. Cost: zero (dead type).

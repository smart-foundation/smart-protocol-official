# Audit — buffer.capnp (618 lines)

## Verdict
**KEEP — with four small honesty fixes.** This is the batch's model citizen: it exists to make every other schema's `T.DataHandle` real, its primary paths carry no inline bulk, its subscription is pull+cancel *and* paginated (`pullPaginated @2`, :392), and its errors are `T.Error`. The defects are small and specific: a POSIX file-descriptor number in a wire type (`DmaBufferHandle.fd :Int32`), POSIX `madvise`/fork vocabulary in an enum, a stale header comment referencing a `Buffer` interface that does not exist in the file, and one event union that violates the repo's own `unknown/custom` rule (E6). Do not restructure this schema.

## Wire-breakers
No compile errors. The nested `struct HandshakeRequest`/`HandshakeResponse`/`enum HandshakeResult` *inside* `interface BufferService` (:29-45) are legal Cap'n Proto but unique to this file in the batch — a parser that assumes top-level declarations (and several repo tools do, see below) misreads them. Name collisions: `CacheMode` (:253 vs `hal.capnp:55` vs `storage.capnp:836` — three, different values), `CustomQuery` (:363 vs `compositor.capnp:768` vs `shell.capnp:637` vs `windowmanager.capnp:798` — four), `HandshakeRequest`/`Response`/`Result` (:29/:35/:41 vs compositor/shell/ime/font/screenlock/windowmanager — documented as the sanctioned session pattern, DESIGN_PRINCIPLES.md:258, so these are acceptable copies), `TransferState` (:203) vs `MigrationState` (process/runtime_search/storage) vs `RolloutState` (update).

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R5 | `buffer.capnp:551` | `DmaBufferHandle.fd @0 :Int32` — "Opaque DMA file descriptor (backend-specific)" | An fd is a per-process table index: a number passed over IPC is meaningless in the receiving process (real dma-buf shares fds *by passing the descriptor*, not the integer). A browser or Windows backend has no fd at all. The field name promises something the type cannot deliver; implementers must smuggle the real fd out-of-band, which is exactly the unprotocol the schema should replace |
| R5 | `buffer.capnp:155-167` | `BufferAdvice` = normal/sequential/random/willNeed/dontNeed/remove/**dontFork**/merge/unmerge/hwpoison/softDirty — the comments cite "POSIX MADV_SEQUENTIAL/RANDOM/WILLNEED/DONTNEED" | `madvise` names and fork semantics are Linux memory-management vocabulary; a capability-runtime backend has none of them, and `dontFork` presumes `fork()` exists |
| R7 | `buffer.capnp:400-409` | `BufferEvent` union has no `unknown`/`custom` variant (validator E6) — the *event* union, the single most forward-compat-sensitive struct type (compare `ai.capnp:538-550`'s event union with `unknown @6`) | A backend cannot emit a future buffer event without a schema change; consumers' exhaustive switch is a fork waiting to happen. TIMELESSNESS.md:98 makes this a MUST for every union |
| R7 | `buffer.capnp:352-361` | `BufferQuery.formats @2 :T.OutputId` and `testPattern @5 :Text` (result `@6 :T.PixelFormat`) | A buffer-format query addressed by a *display output id* — buffers and outputs are unrelated concepts, so a headless backend cannot answer its own query. And a query named `testPattern` whose result type is a pixel format communicates nothing about the contract |
| R6 | `buffer.capnp:253-259` | `CacheMode` (defaultCached/writeBack/writeThrough/uncacheable) vs `hal.capnp:55` vs `storage.capnp:836` (writeBack/writeThrough/readAhead — no `uncacheable`, different @0) | Three cache-mode enums; translating between them is a hand-mapping. One canonical shape should live in `types.capnp` |
| UX | `buffer.capnp:14` | Header: "The deprecated `Buffer` interface is preserved for migration" — **no `Buffer` interface exists in this file** (only `BufferService`) | DESIGN_PRINCIPLES.md:215 says "deprecate `Buffer`, keep `BufferSession`"; the interface was renamed, and the header comment was not updated. Stale documentation is a (small) implementer trap: readers hunt for an interface that isn't there |

Validator counts: E7 ×37, E8 ×7, E6 ×8 (`SharedMemoryResult` :235, `BufferResult` :275, `RingBufferResult` :325, `BufferInfoResult` :345, `BufferEvent` :400, `BufferPoolResult` :469, `BufferMigrationResult` :579, `BufferExportResult` :613 — all result unions lacking unknown/custom).

## Duplicates & overlaps
- `CacheMode` ×3, `CustomQuery` ×4, `Handshake*` ×7 (sanctioned pattern — noted, not a finding).
- `BufferSync` (`producerFence`/`consumerFence` :451-455) vs `surface.capnp`/`compositor.capnp` `SyncFence` (`types.capnp:943` `T.FenceHandle` exists) — fence primitives typed three ways.
- `TensorBufferInfo.shape/strides :List(UInt32)` (:522-523) — small bounded lists (dimension counts, not bulk), so *not* an R2 violation; noted to show the distinction from `database.capnp`'s float lists.
- `SharedMemoryRegion.name @3 :Text` (:246) — a named shared-memory object is a POSIX `shm_open`/Windows named-object concept in a required field; mild R5 (mitigated by being optional in practice).

## Gaps & holes
- No overcommit/failure introspection: `BufferOvercommitConfig` (:173) configures behavior, `BufferStatistics.allocationFailures @4` (:539) counts it — but nothing subscribes to low-memory events so a consumer can *pre-emptively* release (the eco-relevant direction: backpressure signal, not just a post-hoc counter).
- `exportBufferToProcess @32` (:605) takes `targetProcessId :T.ProcessId` + raw `readable`/`writable` bools — the export authority is boolean flags rather than an attenuated capability (soft R3: the capability model can carry exactly this).

## Zero-cost / eco
- No inline bulk payloads: this is the file that makes zero-copy possible elsewhere; all payloads are `T.UInt64` handles into shared memory. `BufferPoolRequest` (:460) provides pre-allocation precisely to remove per-frame allocation. No findings — and the two `List(UInt32)` shape/stride fields are dimension metadata, not bulk.
- `waitPeerTransfer @40 (transferId, timeout :T.Duration)` (:124) — a blocking wait with timeout; acceptable (not busy-poll) but the subscription pattern would be the eco-consistent choice for high-frequency transfers.

## UX & implementer guidance
- `BufferQuery` (:352) mixes queries answerable by anyone (`maxBuffers`), queries needing a buffer id (`ringFill @4 :UInt64`), and one display-shaped query (`formats :T.OutputId`) in one union — three different addressing regimes. A headless implementer cannot answer `formats` and must guess whether to return `notSupported @4` (:374) or an empty list.
- Handles are bare `UInt64` throughout (:53, :60, ...) while `T.BufferId` (`types.capnp:8`) exists — typed IDs would prevent passing a pool id where a buffer handle belongs (`getPoolInfo(poolId :UInt64)` vs `getBufferInfo(handle :UInt64)` are two different UInt64 namespaces in one interface — an implementer trap with no compile guard).
- The nested-in-interface declarations (:29-45) break the structural uniformity every other schema in the tree has.

## Recommended actions
1. **Replace `DmaBufferHandle.fd :Int32` with an opaque token** (`handle :Data` or reuse `T.DataHandle`, with the fd-passing mechanism as backend detail). Gain: the DMA path becomes portable (browser/Windows/VM backends can represent it) instead of POSIX-only; the field stops promising something it can't carry. Cost: one field type change.
2. **Rename `BufferAdvice` values off POSIX** (drop `dontFork`, spell the rest as intent — `sequential`, `random`, `willNeed`, `doneWith`, ...) and fix the comments. Gain: stops naming `madvise`/fork in an eternal enum. Cost: nine value renames — cheap pre-release.
3. **Add a `custom`/`unknown` variant to `BufferEvent`** (and, for uniformity, to the eight result unions flagged by E6). Gain: closes the repo's own rule TIMELESSNESS.md:98 on this file's most sensitive struct. Cost: one variant per union — mechanical, additive.
4. **Type the handles** (`T.BufferId`-style IDs for buffers, pools, DMA exports, pipelines, transfers instead of bare `UInt64`). Gain: id-swap mistakes become compile errors across a 40-method interface. Cost: ~15 field type changes to existing typed-ID structs.
5. **Fix or delete the stale header comment** (:14). Gain: honest docs; cost: one line.
6. **Clean up `BufferQuery`**: drop `formats :T.OutputId` (display concept) in favor of `supportedFormats :Void`, and make `testPattern`'s contract explicit (or remove it). Gain: the query union stops mixing addressing regimes; headless backends can answer fully. Cost: two query variants.

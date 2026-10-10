# Audit — queue.capnp (541 lines)

## Verdict
**FIX (targeted) — and praise what's right.** The core queue is one of the batch's better citizens: `T.DataHandle` payloads (`queue.capnp:152`) — correct zero-cost choice, batch-unique among the bulk-carrying schemas; `T.Pagination` on `peek`/`replay`/subscriptions; typed IDs everywhere; ack/nack with structured `AckHandle` (`:215-219`); dead-letter routing. Then Audit-9/10 weld a distributed message broker onto an OS contract: federation, replication with leader election, cross-queue transactions, a schema registry, routing-rule engine, distributed tracing. One semantic trap deserves emphasis: `DeliveryMode.exactlyOnce` (`:205-210`) is a promise the mathematics cannot keep — implementers must invent the lie.

## Wire-breakers
None: ordinals unique (`@0..@59`), all `T.*` resolve.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| Implementer trap / semantics | `queue.capnp:205-210` `DeliveryMode { atMostOnce, atLeastOnce, exactlyOnce, custom }` | "Exactly-once" delivery is impossible over a lossy channel (two-generals); it can only be approximated by dedupe + idempotence | Demonstrated fork: backend A implements exactly-once as "at-least-once + dedupe window"; backend B as "at-least-once + producer-side dedupe." Consumers see different duplicate/loss profiles under the same contract and cannot write portable handlers. Either define the approximation or delete the value |
| R1 / 2046 test | `queue.capnp:329-341` `QueueFederation` + `createFederation @34`, `:345-359` `QueueReplica` + `createReplica @37`/`promoteReplica @40`, `:497-520` `FailoverPolicy`/`FailoverState` + `@53..@56` | Cross-node federation, replication roles, leader election as OS-queue methods | A single-device OS (the protocol's core audience) must stub 12+ methods naming a cluster it does not have. 2046: election timeouts and replica-lag semantics differ per backend — fork on every field |
| R1 / over-specification | `queue.capnp:363-376` `MessageSchema` + `registerSchema @41`, `:524-541` `SchemaMigrationStrategy` + `@57..@59` `migrateMessages` | A schema registry and automatic migration engine inside the queue contract | Wire-format migration is the *consumer's* concern; baking it in freezes today's migration vocabulary (additive/strip/full) into the contract and forces every backend to implement a transformer |
| R5 | `queue.capnp:396-421` `QueueTransaction` (atomic multi-queue ops), `:425-466` `RoutingRule` with `HeaderMatch`/`ContentMatch`/`TopicMatch` + `StringOperator` | Transaction coordinator and content-routing engine | 2046: a queue without cross-queue atomicity must still expose `begin/commit/abort`. The routing language (`xpath`? no — `regex`/`contains`/`startsWith`, `:459-466`) is a query-language commitment in an eternal schema |
| R5 / tech nouns | `queue.capnp:385-392` `MessageFilterType { header, content, xpath, jsonPath, regex }` — `xpath`, `jsonPath` name 2000s/2010s query technologies | Closed list of query syntaxes | A 2046 consumer filters by a mechanism with no ordinal; `custom @5` is the only honest escape, and it exists here — but the named values leak today's stack into required positions |
| R7 | `queue.capnp:285-292` `MessageStatus { pending, processing, completed, failed, deadLettered }`, `:416-421` `TransactionStatus`, `:512-520` `FailoverState` (7 states) | Closed state enums | All carry `custom`; the `FailoverState` ladder (detecting/electing/promoting/reconfiguring) is one election algorithm's steps — a different 2046 algorithm cannot express its states |
| R7 (soft) | `queue.capnp:119-121` `beginTransaction @45 () -> (transaction :QueueTransaction)` then `commitTransaction @46 (transactionId :UInt64)` | The transaction *reference* is returned but the API takes a raw `UInt64` back | Two identity paths (hold reference vs. present id) — the same defect class as the subscription-id pattern in `system.capnp`/`klog.capnp` |
| R2 (soft) | `queue.capnp:130` `injectTraceContext (message, trace) -> (tracedMessage :QueueMessage)` — whole-message echo | Copies the full message (payload is a handle — cheap) but the pattern invites payload duplication in implementations | Minor; the handle mitigates. Listed for honesty |

## Duplicates & overlaps
- `MessageTrace` (`:470-476`) vs `diagnostics.capnp:277-289` `TraceContext` vs `logging.capnp:323-336` vs `klog.capnp:318-329` — a fourth tracing shape (traceId/spanId/parentSpanId/correlationId + baggage).
- Consumer groups (`:297-311`) vs `signal.capnp:198` `SignalGroup`-style group semantics vs `process.capnp:262` `ProcessGroup` — three "group of processes" types.
- Dedupe (`:315-318`, `deduplicate @29`) vs the `AckHandle` redelivery mechanism — two idempotence mechanisms; also `DeliveryMode.exactlyOnce` implies a third.
- Dead-letter (`:223-229`, `listDeadLetters @20`, `retryDeadLetter @21`) — good design; no duplicate. Keep.

## Gaps & holes
- No maximum message size contract anywhere: `T.DataHandle` defers size to the backend, and nothing declares per-queue limits. Demonstrated fork: backend A accepts 1 GB messages, backend B 64 KB; a producer written against A fails on B with no contract to point at.
- `dequeue @1 (timeout :T.Duration)` (`:31`): zero-timeout semantics undocumented (contrast `process.capnp:28-31` which documents precisely this). Does zero return immediately or block forever? Every consumer must guess.

## Zero-cost / eco
- Right: `QueueMessage.data :T.DataHandle` (`:152`), paginated `peek` (`:32`), `FlowControl` (`:268-272`) — real backpressure affordances, the eco-correct pattern.
- Wrong-ish: `enqueueAll @9 (messages :List(QueueMessage))` (`:46-47`) — unbounded bulk enqueue with no bound declared; pagination/bounding belongs here or in `FlowControl.maxInflight`.
- `subscribeQueue`/`dequeueFromGroup` blocking-with-timeout is the correct middle ground (not polling); keep, document zero-timeout.

## UX & implementer guidance
- The header's honesty about `DataHandle` ("use buffer handle for payloads >1KB", `:151`) is exactly the guidance `ai.capnp` models — copy this pattern into `process.capnp`/`boot.capnp`/`hal.capnp`.
- `ReplayOffset { messageId, timestamp, offset }` (`:250-254`): three competing position identifiers in one struct; which wins when they disagree? Undefined.
- `deleteQueue @5` vs `clearQueue @4` (`:35-37`): distinguished well, documented by name — good.
- `QueueSubscription.pull @0 (pagination)` (`:145`) — correct pattern; contrast `logging.capnp` raw id subscriptions.

## Recommended actions
1. **Define or delete `exactlyOnce`** (`:205-210`): either specify the approximation contract (dedupe window semantics, at-least-once base) or delete the value and leave `atMostOnce`/`atLeastOnce` + explicit consumer dedupe. Gain: removes the impossible-promise fork — the single highest-risk semantic in the file; cost: one enum value.
2. **Delete the broker-infrastructure block** (`:329-466` federation/replication/transactions/routing/tracing + `@30..@59` config surface): `createFederation`, `createReplica`, `promoteReplica`, `setFailoverPolicy` family, `registerSchema` family, `createRoutingRule` family, `traceMessage`/`injectTraceContext`, `migrateMessages`. Gain: a single-device-implementable queue; removes ~150 lines and 8 enums naming cluster machinery; cost: none (no consumers).
3. **Keep the core + Audit-8 reliability layer** (ack/nack, dead-letter, TTL, ordering, encryption declaration, flow control, consumer groups, dedupe key). This is a coherent, defensible queue contract.
4. **Document zero-timeout semantics for `dequeue`** (`:31`, `:88`) and bound `enqueueAll` (`:46-47`) or tie it to `FlowControl.maxInflight`. Gain: closes two forks (blocking semantics, unbounded bulk); cost: spec text.
5. **Declare a max-message-size contract** (per-queue field or a protocol default). Gain: producers can pre-check instead of discovering limits by failure; cost: one field.
6. **Unify position identity in `ReplayOffset`** (`:250-254`) — one position field + optional hint. Gain: removes the three-way ambiguity fork; cost: one struct reshape, free pre-release.

# Audit — types.capnp (2162 lines)

## Verdict
**KEEP** with two targeted deletions. This is the foundation every schema imports and it does its job: ~150 opaque `UInt64`-wrapper IDs, `DataHandle` with inline/buffer union (`types.capnp:382-387`), `Error`/`VoidResult` (`:182-201`), honest typed primitives (`MimeType`, `StringMap`, `Pagination`, `Duration`). All 19 batch schemas' `T.*` references resolve — verified exhaustively. Two things must go before release: dead types the protocol itself documents as dead (`SubscriptionResult`/`SubscriptionData`), and the enum debt the file has accumulated in service of other schemas' violations (`TaskState` lives here? — no, but `SignalKind`, `LogLevel`, `TrustLevel` are the load-bearing ones and are fine; the enums to prune are the dead-result pair and the aliases that mislead).

## Wire-breakers
None. Machine-verified: every `T.*` reference in the other 18 batch schemas resolves to a definition here.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R6 | `types.capnp:907-914` `SubscriptionResult`, `:916-920` `SubscriptionData` | Dead code: zero schema references repo-wide (only the retired-plan doc mentions them). The plan file itself records them as dead | A "standardized subscription result" that standardizes nothing; a 2028 implementer finds two canonical subscription shapes (this and the local unions) and must guess which is normative. Demonstrated fork risk |
| R1 (soft) | `types.capnp:255-267` `LogLevel` (trace..custom, crash, security, audit) | Severity list closed at today's vocabulary; `crash`/`security`/`audit` are daemon-specific levels (syslog-isms) | A backend whose severity axis is not ordinal (e.g., structured event kinds) must map lies. It has `custom @10`; tolerable but it is the file's weakest enum |
| R1 | `types.capnp:120-138` `PixelFormat` (17 values incl. `custom @16`) | Technology list: yuyv/nv12/argb2101010 are today's hardware formats | 2046 failure: a holographic or light-field buffer has no ordinal and must ride `custom`, losing its self-description. Borderline — formats are arguably closed by physics; flagged for honesty, not action |
| R4 (soft) | `types.capnp:37, 430, 432, 450…` `DeviceAddress`, `HalDeviceId`, `HookId`, `ServiceName` | `ServiceName { id @0 :UInt64 }` — a *name* that carries a *number* | Implementer trap: `init.capnp:101` `stop (name :T.ServiceName)` reads as a name but is an opaque id; every consumer must call `resolveService` first or guess. Rename or document |

## Duplicates & overlaps
- Within-file: `StringMap` vs `OrderedStringMap` (`:142` vs `:884`) — duplicate concept, the only difference being an unmeasureable ordering promise; `Meta`/`MetaValue` (`:229`) is a third string-map spelling. Cost: three map types where `ai.capnp` uses one.
- Cross-file (created by others, listed here for the rewrite wave): `ResourceUsage` vs `task_scheduler.capnp:474`; `DeviceResource` vs `hal.capnp:185`; `RestartPolicy` vs `init.capnp:66`; `RecoveryAction` vs `boot.capnp:708`; `TaskState` name vs `kernel.capnp:51`/`task_scheduler.capnp:104` (enums defined there, same names).

## Gaps & holes
- No canonical `UnknownEvent { typeId @0 :UInt64; payload @1 :Data; }` lives in `types.capnp` — `ai.capnp:533` defines its own private copy. The doctrine (TIMELESSNESS.md:98) says every union MUST have one, yet the pattern is copy-pasted per schema. Demonstrated fork risk: two files' `UnknownEvent` structs are distinct types with distinct IDs; a generic "unknown-event-tolerant" consumer cannot be written against one canonical type. Recommend promoting `ai.capnp`'s copy here once, pre-release.

## Zero-cost / eco
`DataHandle` (`:382-387`) is the right primitive and is used correctly by `queue.capnp:152`, `signal.capnp:64`, `diagnostics.capnp:336`, `boot.capnp:150-157` (`BootBlob` inline/reference). The file is not the copy-cost problem in this batch.

## UX & implementer guidance
- Batch comments ("BATCH 9", "BATCH 13", "audit-6", "audit-005") record the file's archaeology but not its rules. An implementer cannot tell which of the four functionally identical ID families (`ServiceId`/`ServiceName`/`ServiceHandleId`, `types.capnp:22,450,446`) to use. Consolidate or cross-reference.
- `Warning.code @0 :UInt32` ("backend-defined, 0 = generic", `:703`) is honest but unroutable; tolerable.

## Recommended actions
1. **Delete `SubscriptionResult`/`SubscriptionData` (`:903-920`).** Gain: removes the dead second subscription contract that forks behavior; cost: nothing — zero references.
2. **Promote one canonical `UnknownEvent { typeId, payload :Data }` here.** Gain: R7 becomes mechanically checkable against one type instead of per-file copies; cost: one struct, additive, pre-release.
3. **Document or rename `ServiceName`/`ServiceHandleId` ambiguity.** Gain: removes a trap where `init.capnp:101` looks like it takes a name; cost: a comment (or a rename, free pre-release).
4. **Do not** touch the ID family wholesale: ~150 typed wrappers are verbose but wire-stable and each prevents a real cross-domain confusion. Changing them buys no correctness.

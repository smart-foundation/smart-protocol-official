# Audit — abi.capnp (541 lines)

## Verdict
**FIX (targeted).** The negotiation core is exemplary: `Abi` (`abi.capnp:198-225`) with `schemaVersions`, honest `T.Error` failure cases (`NegotiateResult` `:342-349`, `CompatibilityReport` `:59-66`), paginated `list` (`:287`), subscription with `cancel` (`:290-292`). One hard defect and one simplification: `BootCapability` (`:259-270`) is a byte-identical duplicate of `boot.capnp:647-658` — same name, same members, two distinct type IDs — which is a codegen collision for any consumer importing both schemas, and it is a permission-enum the doctrine forbids. The Audit-7/9 registry apparatus (`AbiRegistryService`, endorsement chain, version pinning, `:439-481`) is speculative infrastructure with no demonstrated consumer.

## Wire-breakers
No compile errors. The `BootCapability` duplication is a *tooling* wire hazard rather than a capnp compile error: two schemas define the same-named type with identical ordinals but different type IDs, so generated code collides (or silently aliases) in every target language. Treated as a wire-breaker-class defect because it produces divergent binaries from two "identical" enums.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R6 | `abi.capnp:259-270` | `BootCapability` duplicates `boot.capnp:647-658` verbatim (readMemory/writeMemory/…/custom) | Two type IDs, one name. A 2028 tool that imports both schemas produces two unrelated enum classes; a capability minted under boot's `readMemory` fails `==` against abi's. Wire-level confusion that is invisible at the schema level |
| R3 (as permission model) | `abi.capnp:259-270`, used at `:189`, `:210`, `:469` | A permission enum (readMemory/writeStorage/…) is the model the doctrine forbids: "Do NOT define permission strings, boolean flags… The capability system IS the access control" (DESIGN_PRINCIPLES.md:399) | An ABI declares rights in a vocabulary parallel to `capability.capnp.Operation`; the two must agree forever, and neither is authoritative. Every implementer invents the mapping |
| Simplicity | `abi.capnp:439-481` + `:395-433` + `:530-541` | `AbiRegistryService`: global registry, endorsement trust chain, cryptographic endorsement verification, version pinning | 2046 test: who operates this registry on an offline embedded device? The machinery adds a trust service and a pin/unpin lifecycle with no demonstrated consumer; cost exceeds gain. It exists because "each backend maintains its own list" was deemed insufficient — an internal-implementation concern |

## Duplicates & overlaps
- `BootCapability` ↔ `boot.capnp:647` (above).
- `SchemaSupport`/`SchemaSupportStatus` (`:357-372`) overlap `PartialCompatibility.unsupportedSchemas` (`:70`) — two ways to say "unsupported schema."
- `NegotiateSession`/`NegotiationRound` (`:166-180`) overlap `AbiHandshake` (`:109-130`) — two handshake-shaped exchanges.

## Gaps & holes
None material. `Abi.features` (`:208`) is an open `List(AbiFeature)` with `T.StringMap`-style payload — good forward-compat shape.

## Zero-cost / eco
No bulk payloads; `platformHints :List(Text)` (`:213`) is fine. No findings.

## UX & implementer guidance
- `AbiRange.maxExclusive` comment (`:51-52`) says "inclusive (default = true -> closed)" while the field name says the opposite of the default — a coin-flip trap for every caller. Name the field `maxInclusive` or invert the default.
- Registry comments (`:393`, `:436`) justify the interface as a "false positive integration" — audit vocabulary leaking into the schema. Schema comments should teach the contract, not the audit trail.

## Recommended actions
1. **Delete the duplicate `BootCapability` enum and the Audit-7/9 registry block** (`:182-192` `CapabilityBundle`, `:259-270`, `:439-481`, `:483-528`, `:530-541`). Replace `capabilities` fields with `List(capability.capnp.Operation)` or an open `List(Text)` feature name. Gain: kills the cross-file enum collision, removes a forbidden permission model, deletes ~150 lines of speculative trust machinery; cost: the registry's three hypothetical consumers — none exist (nothing external consumes the protocol pre-release).
2. **Rename or invert `AbiRange.maxExclusive`.** Gain: removes a boolean-semantics trap; cost: one ordinal, free pre-release.
3. **Keep the negotiation core as-is.** It is the model the rest of the tree should copy.

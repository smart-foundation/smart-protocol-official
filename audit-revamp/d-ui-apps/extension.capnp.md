# Audit — extension.capnp (387 lines)

## Verdict
**FIX (targeted).** The lifecycle core (list/enable/disable/reload/uninstall, settings, subscription with `custom @8` events) is honest, backend-neutral, and uses `T.PermissionId`/`T.DataHandle` correctly. Two serious defects and one collapse. (1) **`ScriptAction.language @1 :Text` with `script @0 :Text` (336–339) puts executable scripts in the contract** — a lifecycle "around" hook that runs arbitrary code on install/enable. That is a remote-code-execution instruction published as protocol, the same class of hole ai.capnp's header calls out (ai.capnp:329–327: the previous revision's `ToolRegistry.invoke` was unauthenticated RCE). Scripts must be capability-secured calls or backend-internal policy, never a contract field. (2) **WASM became the extension runtime**: `loadWasmModule/…/grantWasmCapability` (25–30) + `WasmExtensionInfo` with `memoryPages`, `wasiVersion`, `threads` (262–276) + an `interface WasmExtensionHost` (283–290) make one 2026 sandbox technology the required execution model; a host running native sandboxed code (seL4-style, Lua, JS) has no WASM to report. (3) The **bus collapse**: `grantCapability @11` takes `T.PermissionId` while `grantWasmCapability @29` takes `capability :Text` — the same concept, typed in one method and a string in another. Fix these three and the file is clean.

## Wire-breakers
`WasmExtensionHost` (283) duplicates the five wasm methods already on `Extension` (25–29) — two parallel wasm interfaces, one reachable (nothing returns `WasmExtensionHost`; `Extension.getExtensionBus @37` returns the bus, not the wasm host) — a validator E4-class orphan surfacing in-repo. Verified: no method returns `WasmExtensionHost`.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| Agnostic / security | `extension.capnp:336–339` | `ScriptAction { script :Text, language :Text }` as a lifecycle-hook action (`LifecycleAction.runScript @1`, 322–328) | The contract instructs hosts to execute arbitrary text on install/enable/update paths. Script semantics, sandboxing, and language availability all become protocol obligations; a host that refuses to run scripts silently breaks `around` hooks. This is the ai.capnp RCE finding reborn (see `AiToolInvocation` note at ai.capnp:327) |
| R5 | `extension.capnp:87–92, 262–290` | `loadWasmModule`/`WasmExtensionInfo`/`WasmCapability`/`WasmExtensionHost` make WASM the extension runtime — `memoryPages @2 :UInt32` (64KB granularity), `wasiVersion @5 :Text`, `threads :Bool` (SharedArrayBuffer) | A 2046 extension host that runs a different sandbox (native capability-isolated like seL4, or a VM not yet invented) cannot describe its runtime in this contract; it must fake WASM fields. The header (5–9) promises "the backend decides the extension host" and then freezes one host technology into five required methods |
| R4 | `extension.capnp:91, 288–289` | `grantWasmCapability @29 (capability :Text)` vs `grantCapability @11 (capabilityId :T.PermissionId)` — capability granted by string in one method, typed ID in another, same file | The typed path is the correct one; the string path produces permissions no verifier can resolve, and the two must be reconciled by every backend. One representation |
| R3 | `extension.capnp:195–210` | `ExtensionCapability { id :T.PermissionId, scope :CapabilityScope { extension, system, network, filesystem } }` — a *new* capability model (id + scope enum) beside `capability.capnp`'s `Capability { target, operations, constraints }` | Two capability vocabularies: extension capabilities cannot express target/operations/expiry/attenuation, and authority decisions made in this model are invisible to the canonical one. One authority path (the doctrine's rule) |
| R7 | `extension.capnp:95–97` | `registerLifecycleHook @31 (hook :ExtensionLifecycleHook)` / `unregisterLifecycleHook (hookId :UInt64)` / `listLifecycleHooks` — the hook id is caller-chosen and unverified | Two extensions registering hook id 1 collide invisibly; ids should be server-issued (the compositor `defineAnimation` pattern, compositor.capnp:138) |
| R7 | `extension.capnp:56` | `checkCompatibility @15 -> (compatible :Bool, issues :List(Text))` — compatibility as a bool plus prose | Failure detail in free text is unroutable; `T.Error` with a code + the issues as structured entries is the protocol's pattern |
| R6 | `extension.capnp:356–387` | `ExtensionBus` (channels, postMessage/subscribe/listChannels) — a third messaging model in the batch beside `queue.capnp`'s durable Queue and `app.capnp:63 AppService.sendMessage` | Three buses with three subscription shapes (`ExtensionBusSubscription`, `QueueSubscription`, app events); a cross-extension message and a queue message are different types with the same purpose. If a bus is needed, queue.capnp is the closer host |

## Duplicates & overlaps
- `WasmExtensionHost` (283–290) vs `Extension` (25–29) — five identical methods in an orphan interface; delete the orphan, keep one home.
- `checkExtensionUpdate @20`/`rollbackExtension @21`/`hotReload @22` vs package.capnp's update lifecycle (`checkUpdate`, `rollback @10`, `updateDelta`) — a second update path beside package's (see package audit); extensions are packages (`PackageType.extension @6`, package.capnp:158 — the closed-taxonomy field naming them).
- `setSandboxConfig @16` + `ExtensionSandboxConfig` (221–228) vs `sandbox.capnp` (exists in the tree, not deep-verified here — flagged for the sandbox batch): a third sandbox configuration shape.
- `ExtensionTrustLevel` (185–192) vs `T.TrustLevel` (types.capnp:550) — identical value sets (system/platform/user/sandbox/untrusted/custom); the promoted type exists and is used by capability/runtime_search. Use it.

## Gaps & holes
- **Extension ↔ onboarding authority**: nothing states who may install/enable a trusted extension vs an untrusted one; the `grantCapability` methods look like the answer but don't say who may call them. Capability-gated acquisition (the doctrine's accessor pattern) is the missing sentence.
- **Extension API surface**: `callExtensionApi @8 (method :Text, params :T.DataHandle)` — an honest open RPC, but there is no way to *discover* an extension's methods except `apis @9 :List(Text)` (bare names). A typed declaration (capnp schema id — `T.SchemaId` exists) makes the CLI and bindings generatable from it.

## Zero-cost / eco
- `callExtensionApi` and bus payloads are `T.DataHandle` — the file gets the bulk discipline right. Good.
- `getResourceUsage @18` returns counters, no sampling interval — at what cadence "usage" is meaningful is unstated (implementers will guess and callers will poll).

## UX & implementer guidance
- The header (5–9) is honest and correct — the audit-9 wasm block contradicts it; an implementer reading both gets whiplash.
- `listExtensions @0` unbounded (paged twin at 41 exists) — the unbounded ordinal stays callable.
- `ExtensionEvent.timestamp @0` then a `union` (163–176): timestamp *before* the union in field order is unusual for the batch (events elsewhere lead with identity) — harmless, but it signals two authors.
- `getExtensionHealth @24 -> (healthy :Bool, message :Text)` — health as bool+prose; `T.Warning` (types.capnp:702) is the typed form.

## Recommended actions
1. **Delete `ScriptAction` and make hook actions capability-secured invocations only** (`invokeApi` with a capability reference, or backend-internal policy the contract doesn't name). Gain: the protocol stops instructing arbitrary code execution; hook security becomes the host's enforceable property. Cost: `runScript` removed; `LifecycleAction` keeps `invokeApi` + `custom`.
2. **Generalize the wasm runtime**: replace `loadWasmModule`-family with `loadModule (module :T.DataHandle, runtime :T.MimeType)` + `getModuleInfo` returning open metadata (`T.StringMap`), or move wasm specifics behind an optional backend schema. Gain: any sandbox technology — including ones not invented — hosts extensions; the header's promise becomes true. Cost: five methods collapse to two + metadata; wasm fields move to backend-reported strings.
3. **Delete the orphan `WasmExtensionHost`** (283–290). Gain: one wasm surface, no unreachable interface. Cost: none (nothing returns it).
4. **One capability model**: replace `ExtensionCapability`/`CapabilityScope` with `Capability` references (capability.capnp); retype `grantWasmCapability`'s string to `T.PermissionId`. Gain: extension grants inherit attenuation/revocation/audit; the string path dies. Cost: one struct + one signature.
5. **Delete the bus** (356–387) or delegate to `queue.capnp` channels. Gain: one messaging contract; extensions stop being a special snowflake. Cost: if a bus is genuinely needed, it grows out of queue's model, not beside it.
6. **Route extension updates through package.capnp** (`checkExtensionUpdate`/`rollbackExtension`/`hotReload`). Gain: one update lifecycle for apps, packages and extensions. Cost: three methods deleted here.
7. **Adopt `T.TrustLevel`** and make hook ids server-issued. Gain: removes a duplicated enum and a collision class. Cost: one enum import + one signature.

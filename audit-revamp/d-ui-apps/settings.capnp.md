# Audit — settings.capnp (266 lines)

## Verdict
**FIX (targeted).** The core store is right: domain+key, a value union with `custom @7`, paginated reads, `T.DataHandle` for data values, a `SettingsSubscription` with cancel. Two problems. (1) **A wire-level honesty defect at the core method**: `get @0 (domain, key) -> (value :SettingValue)` has no not-found path — `SettingValue`'s union has no "unset" member, so a missing key returns the zero union member (`string` with empty text), indistinguishable from an empty string. The author knew the right pattern: `getAppOverride @13` returns `(value, exists :Bool)` (56). Every consumer must invent a sentinel, and they will invent different ones. (2) The audit-8/9/10 layer (dependency graphs, templates, roaming sync, conditional values, AI tuning, reactive subscriptions, encrypted values, versioning) is 17 methods of optional machinery around a key-value store — each is individually defensible and collectively an invitation for backends to implement divergent subsets. Fix the core, then demand a consumer for each optional method or delete it.

## Wire-breakers
None.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R7 | `settings.capnp:28` | `get @0 (domain, key) -> (value :SettingValue)` — not-found is unrepresentable; the union's zero member is `string`, so missing == empty-string | A settings consumer reading `ui.accent` that was never set gets `""` and paints the accent empty-black instead of applying the default. Two backends, two sentinels, no way for an app to detect which. The protocol's own error rules (DESIGN_PRINCIPLES:406–418) require an error/discovery path |
| R7 | `settings.capnp:105, 108` | `setEncrypted @29 (domain, key, value :Data, keyId)` / `getEncrypted @30 -> (value :Data, exists :Bool)` — encryption is a *store method*, with the encrypted value passed inline | The store becomes a crypto participant (it must hold/borrow the key path), and `value :Data` is inline bulk. Secret handling belongs to secret.capnp/capability references; the store should accept an opaque encrypted blob it never parses — and it still lacks an error path |
| R6 | `settings.capnp:62–71` | Roaming profiles (`createRoamingProfile`, `syncRoamingProfile (profileId, deviceToken :Data)`) — cross-device sync with a raw `deviceToken` credential | A second settings-transport model parallel to the shell's `HandoffRequest` (shell.capnp:743) with incompatible shapes; and `deviceToken :Data` is a raw credential in a message — the capability model exists precisely to avoid passing credentials as parameters |
| R1 | `settings.capnp:147` | `SettingCategory { security, display, accessibility, network, system, user, audio, privacy, developer }` — names today's subsystems | A 2050 settings domain (spatial, neural-interface, ambient) has no category and lands in `custom` for every backend to interpret differently. Categories aren't closed by mathematics — domains are unbounded |
| R1 | `settings.capnp:182–205` | `ConditionalValue`/`SettingCondition` embed `batteryAbove/batteryBelow/charging` (192–195) | The universal settings contract presupposes battery-powered devices: a desktop, a wall panel, a rack server evaluates `batteryAbove` as nonsense or a lie. Device-property conditions belong to the power domain, open-declared, not hardwired here |
| R3 | `settings.capnp:12, 19` | `setAppOverride @12 (appId :T.AppId, ...)`/`clearAppOverride` — per-app authority by app identity parameter | Per-app override is an access decision; done by parameter it is a second authority path alongside capabilities. Attenuating "app X may override setting Y" is exactly capability.capnp's job |
| R7 | `settings.capnp:40` | `pullSettings @8 (subscription) -> (changes :List(SettingChange))` — deprecated pull kept alongside `SettingsSubscription.pull/pullPage` | Two paths to the same data, one marked deprecated; the deprecated one is un-paginated. Merge conflict risk on the wire is low, but the surface invites implementers to implement both |

## Duplicates & overlaps
- vs `shell.capnp:522–550 ShellSettingValue/ShellSetting/SettingFilter` — shell's third copy of the value union, *missing* the `data`/`list`/`dict` variants this file has (shell's `getSetting(key :Text)` is domain-less). Resolution: shell delegates here; delete shell's copy (doctrine:220).
- vs `SettingValue.list/dict` (130–131): a recursive value type plus `SettingMap` is two list/map models in one file (`SettingMap.entries` and `SettingValue.list :List(SettingValue)`).
- `ManagedPolicy.policyId :Text`/`provider :Text` vs `auth.capnp` policies (not verified deep — flagged): policy identity as free text while `T.PolicyId` exists in types.capnp:1518.

## Gaps & holes
- **Write authorization**: no statement of who may write a domain. A store where any process writes `system.*` is only safe if the capability layer gates it — but the contract doesn't say that, so backends diverge on whether the store itself checks.
- **Change causality**: `SettingChange.actorId @4 :Text` — actor as free text; with capability-based identity this should be a capability reference or opaque ID.
- **Reserved namespace collision**: no rule against an app writing `system.*`; the fork risk is a settings store that enforces and one that doesn't.

## Zero-cost / eco
- `getSettingsDiff @28 (domain, sinceVersion)` (102) is genuinely good design — delta reads instead of full-state polling; the eco pattern the doctrine wants. Keep.
- `ReactiveSettingsSubscription.pull @0` (119) is unbounded per pull while `SettingsSubscription.pull` takes pagination — the "reactive" variant is the one missing the bound.
- `syncRoamingProfile` pulls a full changeset; with `getSettingsDiff` present this should be a diff, not a re-publish.

## UX & implementer guidance
- Nineteen of thirty methods are audit-8/9/10 additions (bulk ops are fine; templates/dependencies/roaming/conditional/AI-tuning/reactive/encrypted are the contested set). An implementer reads this as a checklist and produces five incompatible "settings services" — each complete on a different subset. The contract should be explicit about which layer is required.
- `getVersion @17`/`setIfUnchanged @18` (optimistic concurrency) is well-designed; `AiTunedMetadata.modelId @0 :Text` invites backends to advertise AI adjustments with no consumer that can act on them.
- `TimeRangeCondition.daysOfWeek @2 :UInt32` — a bitmask with no bit assignment in the contract; every backend picks its own bit order. That is a fork in one integer.

## Recommended actions
1. **`get`/`getEncrypted`/`setEncrypted` return results with not-found and error** (`SettingValueResult { value, exists } | T.Error`). Gain: missing keys stop being indistinguishable from empty strings — the single wire-honesty defect in the file. Cost: three signatures.
2. **Demand a named consumer for each audit-8/9/10 method or delete it** (templates, dependencies/dependents, conditional values, AI tuning, roaming, reactive subscription). Gain: the store returns to "get/set/watch/bulk/version/diff" — a surface every backend completes identically; the fork cost of divergent subsets disappears. Cost: those features return if a real consumer files them (cheap pre-release).
3. **Per-app overrides and write authority via capability** (or an explicit statement that the host gates writes). Gain: one authority path; `setAppOverride` stops being an access decision by parameter. Cost: method semantics documented, no signature change needed for the gating statement.
4. **Remove device-presupposing conditions** (battery fields) or move them to a power-domain open extension. Gain: the settings contract works on a rack server unmodified. Cost: 4 fields.
5. **Assign `daysOfWeek` bits explicitly or replace with `List(Bool)`×7.** Gain: one interpretation. Cost: one field.
6. **Unify the value model**: one list/map representation (`SettingMap` or `SettingValue.list`, not both). Gain: half the union's surface to implement. Cost: one union member removed.
7. **Keep `getSettingsDiff` and celebrate it** — it is the batch's model for eco reads; use it as the pattern for shell handoff and package update checks.

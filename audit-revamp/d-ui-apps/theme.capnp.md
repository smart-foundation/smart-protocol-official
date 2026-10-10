# Audit — theme.capnp (549 lines)

## Verdict
**FIX (targeted).** The token model (ThemeTokens/Colors/Typography/Shape/Motion, 115–292) is the correct shape for a timeless theme contract: a named token set, a subscription, per-subsystem and typed-ID references, no engine named in the contract itself. But the audit-7/9 additions turned four *algorithms* into protocol methods — `extractColorsFromImage @20`, `generateThemeFromColors @21`, `checkContrastRatio @22`, `simulateColorBlindness @24` (91–101) — and none of them is an interop contract: contrast ratio is arithmetic on two colors any consumer runs locally, color extraction and blindness simulation are theming-engine internals whose output differs per engine. They fail the Agnostic Test ("would swapping the engine break the contract?" — yes, because different engines produce different palettes and the contract says nothing about which is right), and they add a fork surface (every backend must invent extraction behavior). Add a migration subsystem that Cap'n Proto's additive field evolution makes unnecessary, and a subscription method (`ThemeSubscription.pullPaged`, 110) that conflates paginated *events* with whole *snapshots*. Fix: cut the algorithms and the migration machinery, keep the tokens.

## Wire-breakers
None.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R1 | `theme.capnp:289` | `ThemeVariantKind { default, highContrast, monochrome, colorful, accessibility, brand, custom }` — "colorful"/"brand" are 2020s design-tool vocabulary | A future variant (e.g. "high-legibility", "thermal-friendly") has no ordinal; worse, `brand` has no protocol meaning at all. Variants are engine policy; an open name (already present as `setThemeVariant @7 (variant :Text)`, line 56) plus this enum create two naming systems |
| R1 | `theme.capnp:405` | `WcagLevel { fail, aa, aaa }` freezes one accessibility standard's grading | WCAG is a 2008 document; its successors (or a 2046 equivalent) have no ordinal. And the value is *derived* — a consumer computes the level from the ratio it already has |
| Agnostic | `theme.capnp:91, 101` | `extractColorsFromImage @20`, `generateThemeFromColors @21` — extraction is Material-You-class engine behavior, now protocol | Two engines swapping produces different `DynamicColorPalette`s from the same wallpaper; the contract names no winner, so consumers cannot depend on the output. Every engine implementer must reverse-engineer each other's extraction to "match" |
| Agnostic | `theme.capnp:95` | `checkContrastRatio @22 (fg, bg) -> ContrastResult` — a pure function exposed as IPC | The consumer already holds both colors; the round trip computes what the consumer could compute locally for free. Protocol surface that adds a fork (rounding conventions) instead of removing one |
| R6 | `theme.capnp:473–494` | `ThemeMigration`/`ThemeMigrationResult` — version-to-version token migration inside the live protocol | Cap'n Proto's additive field evolution IS the migration story: unknown fields are ignored, new fields default. A migration subsystem duplicates machinery the wire format already provides, and invents a second versioning channel next to `abi.capnp` |
| R7 | `theme.capnp:110` | `ThemeSubscription.pullPaged @2 (pagination) -> (tokens :List(ThemeTokens), total :UInt64)` — paginating a snapshot stream | A theme is not a list; "page 3 of the theme" is meaningless. The method will be implemented as "return the last N snapshots" by one backend and "error" by another — a fork in an unused method |
| R6 | `theme.capnp:639, compositor.capnp:639` | compositor carries its own 10-field `Theme` + `ThemeChangedEvent`, while this file is canonical | Two theme transports agree on nothing; a compositor-consuming app must convert. (Compositor audit, action 2-adjacent.) |

## Duplicates & overlaps
- vs `compositor.capnp:639 Theme` — the fork above; compositor should import this file.
- vs `types.capnp:1239 AnimationEasing`/`1271 AnimationSpec` — this file defines its own `ThemeMotion`(262)/`EasingCurve`(275); `T.AnimationSpec` is the canonical animation vocabulary the rest of the batch uses (windowmanager.capnp:953, compositor.capnp:1375). Theme should reuse it.
- `ThemeSchedule.startTime/endTime :Text` (381) — times as unstructured Text with a separate `timezone :Text`; no format stated. Each backend parses "22:00" its own way.

## Gaps & holes
- **No statement of token-namespace ownership**: who defines a new token name ("shell.accent-hover") when a future display paradigm needs one? Tokens are a closed list of structs here — a new token requires an ordinal. One open map (`additional :T.StringMap` or per-section maps) closes it without touching ordinals.
- **Accessibility preferences live elsewhere**: `AccessibilityPreferences` (accessibility.capnp:548) and shell's `AccessibilityMode` (shell.capnp:837) both carry `reducedMotion`/`highContrast`, and theme carries them as *variants* — three homes. One owner needed (accessibility.capnp is the natural one; theme reports them as tokens).

## Zero-cost / eco
- `ThemeTokens.lightTokens @10 :ThemeTokens` (141) — a recursively nested full token copy: the dual-palette design costs 2× the snapshot size on every theme change, delivered to every subscriber. An alternative (one palette + a swap rule, or separate light/dark ids fetched on demand) halves the copy; at minimum, do not also nest `ThemeTokens` inside itself.
- `EcoModeConfig` (431) is good doctrine (a real eco contract) — but its knobs (oledSafeDark, disableBlur) are engine instructions smuggled into token data. Keep the *declaration* (a theme may be power-frugal), drop the rendering directives.
- The subscription is pull-based with cancel (105–112) — the canonical pattern.

## UX & implementer guidance
- `installTheme @12 (themeId, data :T.DataHandle)` accepts a serialized token bundle but nothing declares the bundle format — each backend defines its own and users' themes stop being portable. `T.MimeType` on the bundle (or an open `format :Text` field) makes the escape hatch self-describing.
- `ThemeExport.formatVersion @1 :T.Version` (501) + `ThemeImportRequest.validate` (519) — portable themes without a declared schema version semantics = silent breakage on import.
- `simulateColorBlindness @24 (tokens, deficiency) -> (tokens)` — output tokens from a simulation are not installable themes; what a consumer does with them (preview? publish?) is undefined.
- Validator E8: `SystemColorScheme.@0 = light` (349) — an absent preference silently means *light*; a "no preference" system flips users to light against their will. `noPreference` exists at 352 but is not `@0`.

## Recommended actions
1. **Delete the four algorithm methods** (`extractColorsFromImage`, `generateThemeFromColors`, `checkContrastRatio`, `simulateColorBlindness`) and their result structs. Gain: the theming engine stays internal (the doctrine's Swap Test passes: swapping engines no longer changes contract-visible behavior); ~40 lines and 4 fork surfaces removed. Cost: consumers wanting contrast checks compute them locally (they already hold the colors).
2. **Delete the migration subsystem** (`ThemeMigration`, `ThemeMigrationResult`). Gain: Cap'n Proto's additive evolution is the migration; the second versioning channel disappears. Cost: none — abi.capnp governs schema versions.
3. **Fix `ThemeSubscription.pullPaged`** — either delete it or redefine it as a bounded event batch (the pattern every other subscription in the batch uses). Gain: no backend invents "page of theme" semantics. Cost: one method.
4. **Add an open token map to `ThemeTokens`** (`tokens :T.StringMap` or per-section maps). Gain: a future display paradigm names new tokens with no schema change — the ai.capnp move (open values instead of frozen lists). Cost: one field; the fixed sections stay for today's tokens.
5. **Declare the theme bundle's content type** on `installTheme` (`format :T.MimeType` or Text). Gain: user themes stay portable across backends. Cost: one field.
6. **Demote the eco directives** (EcoModeConfig) to a declaration the engine interprets; keep `enabled` and target intensity. Gain: the protocol stops instructing GPU work. Cost: several fields.
7. **Make `SystemColorScheme.@0` neutral** (`noPreference`) — validator E8. Gain: absent preference stops meaning "light". Cost: one enum reorder.

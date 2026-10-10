# Audit — accessibility.capnp (657 lines)

## Verdict
**FIX (targeted) — small, surgical.** This file is close to exemplary and I say so plainly: lazy tree (children as IDs, line 13–15), deltas not snapshots (`TreeDelta`, 243), ranges with granularity (117), relationships (178), paginated flat traversal (67), text attributes for rich text (139), preferences as contract (548). Two real defects. (1) The audit-10 ARIA insertion (`AriaProperties`, 585–616, plus `getAriaProperties @19`, `setAriaProperties @20`, `resolveLabelledBy @21`, `resolveDescribedBy @22`, 79–89) contradicts the file's own header (line 10–12): the contract promises AT-SPI/NSAccessibility/UIA neutrality and then bolted WAI-ARIA — a *web* platform vocabulary — into the canonical property model, in position where non-web backends (an automotive HMI, a game UI, a robot face) must now emulate ARIA to be complete. (2) `exportTreeJson @16` (71) returns the whole tree as inline `Text` — the file's own lazy design undone for the one call where trees are largest. Fix those, dedupe two politeness scales, and this is a KEEP.

## Wire-breakers
None.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R5 | `accessibility.capnp:585` | `AriaProperties { label, labelledBy, describedBy, live, atomic, busy, current, hasPopup, hidden, invalid, controls, owns }` makes WAI-ARIA (a W3C web document mechanism) a required vocabulary of the universal accessibility contract | The Swap Test fails: swapping a webview backend for an AR/VR HMI backend requires *emulating* ARIA semantics the backend does not possess (`current: step`, `owns`, `hasPopup: listbox`). Non-web ATs (voice control on a car cluster) must map their model onto web roles — the exact platform-noun-in-required-position the doctrine bans, and the file's own header promises otherwise |
| R2 | `accessibility.capnp:71` | `exportTreeJson @16 (rootId) -> (json :Text)` — a full tree serialized inline as JSON | A spreadsheet or a document with 50k nodes returns megabytes of inline JSON, allocated whole on both ends; the same data as `T.DataHandle` is a buffer reference. The batch's #1 copy-cost pattern on the batch's largest structure |
| R2 | `accessibility.capnp:51` | `getSelectedText @10 -> (text :Text, range :TextRange)` — entire selection inline | A "select all" in a large document copies the whole document into the result; a handle + range (or DataHandle) keeps it zero-cost |
| R6 | `accessibility.capnp:234, 618` | `LiveRegionMode { off, polite, assertive }` and `AriaLive { off, polite, assertive, rude }` — two politeness scales, one a subset with a different name | A live region announced through `AnnouncementEvent.politeness :LiveRegionMode` (331) cannot express `rude`; an ARIA-shaped producer can. One scale, one home |
| R1 | `accessibility.capnp:369` | `AccessibilityRole` — 70 values | This is the defensible enum family: cross-platform AT interop genuinely needs a shared vocabulary (that's its interop purpose), and `custom @69` exists. But it is frozen ARIA-2018: a 2046 GUI concept (a spatial node, an agent-avatar) lands in `custom` with no dispatch protocol — the `unknown`/typed-value escape should be an explicit open token alongside, same as ai.capnp's capability names |
| R4 | `accessibility.capnp:99` | `NodePropertyChange { field :Text, value :Text }` — batch updates set node fields as text pairs | `batchUpdate @17` (74) is the only path that mutates properties in bulk, and it is text-typed: a boolean becomes "true"/"false" by convention, a numeric value becomes "42" — every backend and every client agrees on nothing. Typed property changes (or `T.MetaValue`, which exists) keep it honest |
| R7 | `accessibility.capnp:74` | `batchUpdate @17 (updates :List(NodeUpdate)) -> T.VoidResult` — one failure anywhere fails the whole batch with no per-update result | "Node 4 failed" vs "nodes 1–17 succeeded" is unanswerable; the caller must re-fetch the world to reconcile |

## Duplicates & overlaps
- vs `compositor.capnp:668–750` — the compositor's local `AccessibilityNode/Role/State/Action/Tree` (a *reduced* copy: no coordinateSpace, liveRegion, value, ranges, readingOrder). Resolution: compositor imports this file (it is the canonical contract) and deletes its fork.
- vs `shell.capnp:1026–1037 ShellAccessibilityTree/Node` — a third tree model, worse (Text ids, Text roles). Delete; delegate here.
- vs `types.capnp:989` — the comment there documents `ComponentName` promotion referencing accessibility.capnp; consistent, no action.

## Gaps & holes
- **Who owns the root tree?** The service serves per-node trees by `AccessNodeId`, but nothing states how a consumer discovers the *root* of an app's tree (no "get root for surface"). ATs will each invent a root-finding convention.
- **Node id issuance**: no statement that ids are app-issued, server-issued, or compositor-assigned across surfaces — a genuine fork for any AT building a global address space over multiple apps.

## Zero-cost / eco
- The tree model is the batch's best eco design: lazy children (204), deltas (`TreeDelta`, 243), paginated flat traversal (67). The two inline-bulk methods (`exportTreeJson`, `getSelectedText`) contradict it — fix those two and the eco story is complete.
- `pullEvents @5` returns `List(AccessibilityEvent)` unbounded; focus storms on a busy surface should get the same `maxEvents` bound the batch's other subscriptions are getting.

## UX & implementer guidance
- `performAction @7 (nodeId, action) -> T.VoidResult` — good; error codes will carry not-supported. Specify that unsupported actions return `T.ErrorCode.notSupported` so consumers can degrade instead of retry.
- `getPreferences @12` bundles screen-reader, magnifier, keyboard prefs — correct and canonical; theme.capnp and shell.capnp duplicate fragments of it (see their audits).
- Validator E8: 9 non-neutral `@0`s (`screen`, `press`, `bold`, `character`, …) — machine-reported, cheap to fix.

## Recommended actions
1. **Delete the ARIA property model** (`AriaProperties` + four methods, 79–89, 581–657) or move it behind a web-backend extension schema. Gain: the file's own header promise (AT-SPI/NSAccessibility/UIA neutrality) becomes true; non-web backends implement one neutral contract. Cost: web-backed UIs map ARIA → the neutral node model (they must, to serve any other AT anyway); `AriaRelationship` (652) survives as the neutral relationship form if the `type :Text` open token is kept.
2. **`exportTreeJson` and `getSelectedText` via `T.DataHandle`.** Gain: the largest trees stop being inline copies; consistent with the file's lazy design. Cost: two retypes.
3. **One politeness scale** (fold `AriaLive.rude` into `LiveRegionMode`). Gain: live-region announcements become expressible at full severity. Cost: one enum member (or one enum deleted).
4. **Type the batch-update change values** (`T.MetaValue` union instead of `value :Text`), and add per-update results to `batchUpdate`. Gain: bulk updates stop being convention-driven string encoding; partial success becomes visible. Cost: one struct retyped.
5. **Add one discovering method** (`getRoot (surfaceId)` or document root issuance). Gain: ATs stop inventing root discovery — the fork with every new backend. Cost: one method or one paragraph.
6. **Keep everything else.** The lazy tree, deltas, ranges, granularity, relationships, preferences and paginated traversal are the model the rest of the protocol should copy; no change.

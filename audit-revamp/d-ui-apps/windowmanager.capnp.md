# Audit — windowmanager.capnp (1078 lines)

## Verdict
**FIX (targeted).** The Session interface (27–207) is structurally right — handshake, paginated queries, event stream with `unknown @20`. But the file carries the batch's largest collection of doctrine leaks and one live type collision. The pending items are known and confirmed: `Window.pid @15 :UInt32` (line 316) and `WindowFilter.processId @6 :UInt32` (362) are the offenders the doctrine named, both still present. Worse and unreported until now: `Window.groupId @18 :T.WindowId` (319) cannot be matched against `WindowGroup.groupId @0 :UInt32` (1007) / `destroyWindowGroup(groupId :UInt32)` (193) — window→group references join with nothing. The flat `WindowManager` interface (214–293) survives alongside the Session, and the audit-7 block is a domain grab (foldable, automotive HMI, voice windows, mobile presets) that belongs in optional domain modules, not the universal window contract. Fix: delete the legacy interface, fix the ID types, and cut the domain grab.

## Wire-breakers
None. Imports resolve (`Shell` is imported for `Shell.ShellAction` at 1047). No ordinal collisions. Note the interface-internal `HandshakeRequest/Response/Result` and `WindowManagerInfo/LayoutEngine` are scoped inside `Session`, which is fine but incompatible with a shared handshake contract.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R4 | `windowmanager.capnp:316` | `Window.pid @15 :UInt32` — the doctrine's own named offender (DESIGN_PRINCIPLES:236) | UInt32 cannot address processes in a distributed system; and a window system with no per-window process (a tiler managing its own surfaces, a remote desktop) must invent a sentinel. `T.ProcessId` exists and is opaque |
| R4 | `windowmanager.capnp:362` | `WindowFilter.processId @6 :UInt32` | Same failure in filter position: filters by process cannot be expressed portably |
| R4 | `windowmanager.capnp:1007, 193` | `WindowGroup.groupId :UInt32` vs `Window.groupId :T.WindowId` (319) | The handle you pass to `createWindowGroup` cannot be correlated with the `groupId` a window reports — every client must maintain its own string/UInt32 mapping table. Two ID types for one entity is a guaranteed implementer fork |
| R4 | `windowmanager.capnp:368` | `SnapZone.id @0 :UInt32`, `animationId :UInt32` (189), `presetId :Text` (206) | Snap zones and animations are referenced by raw integers/text with no typed ID; collision across outputs is invisible to the type system |
| R1 | `windowmanager.capnp:374` | `SnapPreset` freezes 17 layout positions (thirdLeft, twoThirdsRight…) | A 3-column grid in 2028, a radial layout in 2035: no ordinal for either; `custom @9`/`grid @10` exist but every backend then invents its own preset grammar. Presets are WM policy; the contract needs "place at rect" + let the WM name its zones |
| R1 | `windowmanager.capnp:913` | `AutomotiveDisplayRole { instrumentCluster, centerStack, headUpDisplay, rearSeat }` | Vehicle-electronic nouns (ECU/display roles) are a product taxonomy of one decade. A 2046 window manager on glasses or a wall panel has no ordinal, and the alternative shell has no concept to map to |
| R1/R6 | `windowmanager.capnp:820` | `WindowManagerCapability` closes the capability vocabulary at 27 values (incl. `automotiveMode`, `foldableAware`, `voiceOnlyMode`) | A capability kind added next year cannot be requested in `HandshakeRequest.capabilities :List(WindowManagerCapability)` (32). compositor.capnp:1244 solved this with `CapabilityRequest { standard, hotkeys, custom }`; this file did not adopt it |
| R5 | `windowmanager.capnp:645` `WindowType` + `929` `VoiceWindowMode` + `871` `FoldableState` | Android/iOS window vocabulary (`onscreenDisplay`, flex/hinge `FoldState`, `continuityToken`) in a position every WM implementer reads | A desktop compositor, a VR shell and an embedded HMI must all translate concepts they do not possess ("hinge angle") into their model — the swap test breaks: swapping a phone for a wall display forces schema edits, not just backend changes |
| R7 | `windowmanager.capnp:73, 111, 128, 160` | `listWindows @1`, `listSnapZones @16`, `listWorkspaces @20`, `listOutputs @33` return unbounded lists | Paged twins exist (@37/@38/@39/@40 and on the legacy side @44–@47) — proving the author knew. But the original ordinals remain callable and unbounded, so the paging fix is optional and clients that never migrated still OOM. Post-merge, delete the unbounded originals |
| R8 | `windowmanager.capnp:1047` | `LockScreenShortcut.action :Shell.ShellAction` — a **dependency on shell.capnp** from windowmanager | windowmanager now cannot compile without shell.capnp, inverting the layering (compositor/windowmanager should sit below shell). Any shell rewrite forces a windowmanager rebuild |

## Duplicates & overlaps
- `OutputInfo` (480) + `OutputMode` (495) vs `compositor.capnp:797, 812`; `OutputInformation` (502) is a *third* near-identical struct in the same file. Pick one (ideally shared with display/compositor).
- `FocusReason` (754) vs `compositor.capnp:1138` (same 6 values); `CustomQuery` (798) vs `compositor.capnp:768` / `shell.capnp:637` / `buffer.capnp`.
- Flat `WindowManager` (214–293) duplicates `Session` wholesale: listWindows, focus/close/minimize, snap, tile, workspaces, overview, capture, outputs, query — 30 methods that exist only because the Session arrived later. The `*Paged` ordinals (44–48) exist only to patch the legacy interface.
- Screen capture (`CaptureRequest` 520, `CaptureFrame` 577, `captureFrameReady` stream 713) overlaps `compositor.Session` capture (`Compositor @19 captureOutput`, capability `captureOutput/captureAll` at 1216 file line 226) — two capture authorities.
- `NotificationWindow` (1051) drives `notification.capnp` windows from the WM side — the notification service should own its own surfaces via the compositor, not the WM.

## Gaps & holes
- **Window↔group identity is unrepresentable** (see R4): no typed `WindowGroupId`, so cross-referencing windows to their group depends on a UInt32↔WindowId mapping each client hand-rolls.
- No error union anywhere on `Window` queries: `getWindow @2`, `getFocusedWindow @3` return the struct directly — a missing window arrives as a default-valued `Window` (id 0), indistinguishable from window 0. `appindex.LaunchResult` (appindex.capnp:172) shows the pattern this file should follow.

## Zero-cost / eco
- `EventSubscription.pull @0 () -> (events :List(WmEvent))` (609) is the right shape; `WindowManagerEventStream.next @0` (669) returns one event per call — for a WM driving an overview grid at 60 Hz the round trips dominate. One `pull (maxEvents)` semantics for both.
- `getWindowThumbnail @45` / `listWindowThumbnails @46` correctly use `T.DataHandle` for pixels — the task-switcher path stays zero-cost. Good.
- `WindowFilter` has no pagination inside itself; `listWindowsPaged` covers it. Fine post-cleanup.

## UX & implementer guidance
- Handshake `applicationId @0 :Text` (30) vs `compositor.capnp:47 :T.AppId` — the same field is an opaque ID in one file and a free string in another, so an app cannot port its handshake code between services unchanged.
- `animateWindow @47` takes a `WindowAnimation` with `animationId :UInt32` chosen by the caller, then `cancelAnimation @48 (animationId :UInt32)` collides with any app-local numbering. IDs should be server-issued (see `compositor.defineAnimation @25` which returns an id).
- `queryPaged @48` ignores its `pagination` argument in the result type (`WindowManagerQueryResult` has no total) — the name promises a bound the return type does not carry.
- Validator E8: 19 enums with non-neutral `@0` (`normal`, `topLeft`, `userClick`, `running`, …). Machine-reported.

## Recommended actions
1. **Delete the flat `WindowManager` interface (214–293) and its five `*Paged` ordinals (44–48).** Gain: removes 30 duplicated methods; the unbounded originals on Session (@1/16/20/33) become the only paths and can then be fixed honestly. Cost: none pre-release.
2. **`Window.pid` → `T.ProcessId`, `WindowFilter.processId` → `T.ProcessId`.** Gain: closes the doctrine's named offender; distributed and pid-less window systems become expressible. Cost: one field type change per line.
3. **Introduce `T.WindowGroupId` (UInt64 wrapper) and retype `WindowGroup.groupId`, `Window.groupId`, `destroyWindowGroup`.** Gain: window↔group correlation becomes possible for every client without a hand-rolled mapping. Cost: three field changes.
4. **Move the domain grab out of the universal file**: foldable (871), automotive (906, 913), voice (932), mobile snap/presets (988, 1065), input redirection (1023). Gain: the universal contract shrinks to what every WM must answer; domains become optional modules a vehicle/AR WM implements or ignores. Cost: one new domain-module schema (or an appendix in the same file marked optional-by-contract).
5. **Unify output types**: one `OutputInfo`/`OutputMode` set shared by compositor and windowmanager (promote to types.capnp or a common schema). Gain: output objects compose across the two services. Cost: a cross-file move; delete `OutputInformation`.
6. **Adopt `CapabilityRequest { standard, custom }`** in the handshake. Gain: capability kinds invented after the freeze remain requestable — the exact R1 fix compositor already made. Cost: handshake struct change (free pre-release).
7. **Break the shell.capnp dependency** (`Shell.ShellAction` at 1047): define the lock-screen action as a generic intent reference (`T.IntentId`/open Text token) instead. Gain: WM compiles without shell; layering restored. Cost: one field retype.
8. **Make `getWindow`/`getFocusedWindow` return a result union (notFound + error).** Gain: callers can distinguish "no such window" from a real window. Cost: two signatures.

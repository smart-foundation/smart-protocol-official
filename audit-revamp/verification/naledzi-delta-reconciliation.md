# Naledzi Delta Reconciliation — canonical ↔ working-tree schema reconciliation

**Verifier:** DELTA VERIFIER (read-only audit)
**Canonical tree:** `smart-protocol-official/schema/` (92 schemas, under rewrite)
**Working tree:** `naledzi/protocol/schemas/` (93 files, the OS that actually consumes it)
**Method:** filesystem diff + `git -C naledzi log/diff` per file + consumer grep over `naledzi/{kernel,uspace,servers,shared,boot}` and every live `build.rs`.

## Scope correction (state this before anything else)

The working tree is **not** a snapshot of the canonical tree. It is a descendant of the
same ancestor that diverged in **two directions at once**:

* **additive downstream work** the canonical tree never saw (the majority of the delta), and
* **semantic rewrites** that reused Cap'n Proto ordinals with different meanings.

Only 3 of the 11 differing files are pure additive (console, cli, types — see below).
`boot.capnp`, `kernel.capnp` and `input.capnp` contain **wire-level breaks** that the
canonical audits' "ordinals unique, verified mechanically" checks could not have caught.

The single largest un-audited commit is **`1619da8d` "new chapter 3.1 but not finished"
(2026-10-09 14:06)**, which touched 8 of the 11 differing schemas in one commit:
`boot +65, cli +125, discovery +81, display +60/-, kernel +143/-, service +90,
shell +734, system +810`. It also added `shared/boot-protocol/src/cpuid.rs` (683 lines) —
the CPUID/ACPI boot-time enumeration that is the *producer* for system.capnp's new
hardware structs. The canonical audits (dated 2026-10-10) read files frozen at
2026-08-19 and never saw any of it.

Second-largest un-audited work: **`5a05e79c` (2026-08-30)** — the real uspace Intel GPU
driver and the capnp build-pipeline decoupling, which added `gpu.capnp` (+257) and
`input.capnp`'s `KeyboardEvent` path, plus `9f19ac8f` (2026-09-03) `gpu.capnp +125`.

---

## Delta classification

### Unique files

| File | naledzi side | Verdict |
|---|---|---|
| `ai.capnp` | **absent** from naledzi | **SUPERSEDED-BY-OFFICIAL** |
| `gpu.capnp` | created `5a05e79c` 2026-08-30 (+257), extended `9f19ac8f` 2026-09-03 (+125); 15,615 B | **IMPORT-TO-CANONICAL** |
| `improved.md` | `776b9bb1` (mass schema copy); a stale 8-improved/82-existing checklist | **DO-NOT-IMPORT (stale)** |

`ai.capnp` (official, 29,618 B, mtime 2026-09-30 — i.e. added *after* the 2026-08-19
snapshot every other schema came from) is the doctrine's gold standard and the
e-security-intelligence batch's own benchmark: zero enums, `T.DataHandle` for every bulk
payload, `Capability` confined to seven `AI` accessors. It has no naledzi counterpart at
all, so there is nothing to reconcile — it is newer and better by construction and the
rewrite should treat it as the reference implementation the other waves are measured
against. Note it carries 120 cross-citations from the other 11 audit MDs; those citations
are valid and unaffected.

`gpu.capnp` is a genuine vendor-agnostic GPU contract (`GpuVendor`, `BufferUsage`,
`BufferDesc`, `GpuBuffer` with `dmaBufFd`/`mappedRegion`, `GpuProvider`, and — from
`9f19ac8f` — `Gpu3DProvider`, `ShaderStage`, `PipelineState`, `DrawCall`). It is **not
dead schema**: `uspace/servers/gpu-intel/build.rs:4` compiles it, `gpu-intel/src/main.rs:73`
declares `mod gpu_capnp`, and `main.rs:1018-1113` uses `gpu_capnp::gpu_provider::*_results::Builder`
and `gpu_capnp::GpuVendor::Intel`. This is exactly the "contract is the durable artifact"
pattern the doctrine wants, backed by a real driver. It has **no audit batch** in
`audit-revamp/` — the canonical tree has no `gpu.capnp` and no `gpu.capnp.md`. Wave **A**
(foundation/kernel-adjacent; it depends on `types`, `hal` and `capability`), and the batch
needs a new slot.

`improved.md` is a planning artifact of a *different schema universe*: it lists 24 schemas
that exist in neither tree (`alarm`, `cloud`, `desktop`, `email`, `firewall`, `gamepad`,
`graphics`, `messaging`, `microphone`, `phone`, `printer`, `sandbox_config`, `scanner`,
`search`, `security`, `vpn`, `workspace`, …) and omits 23 that do exist (including `cli`,
`console`, `input`, `system`, `textinput`, `ime`, `filesystem`, `ipc-message`). Official's
`audit-revamp/` (97 MDs, 2026-10-10) supersedes it outright. Its only value is as evidence
that the naledzi-side audit lineage is the *older, abandoned* one — which is why the
canonical rewrite is the right direction of travel.

### The 11 differing files

| File | naledzi delta and date | Verdict | Wave |
|---|---|---|---|
| `types.capnp` | `ed0b37b1` 2026-08-27 — **one comment line only**: `CYBERSPACE PROTOCOL` → `NALEDZI PROTOCOL` at `types.capnp:1771`. Files otherwise byte-identical (80,220 vs 80,223 B). | **NO-OP / cosmetic only** — nothing to import | A |
| `console.capnp` | `781869e9` 2026-09-05 — pure addition: `writeBytes @46 (data :Data)` (console.capnp:379) and `pushInput @47 ()` (:386). | **IMPORT-TO-CANONICAL** | B |
| `input.capnp` | `5a05e79c` 2026-08-30 — `InputEvent` union gains `keyboard @0 :KeyboardEvent` (`input.capnp:696-719`); new `KeyboardEvent {scancode, pressed, text, modifiers, deviceId}`. | **CONFLICT** (ordinal renumber) — import the idea, re-issue the ordinal | B |
| `display.capnp` | `1619da8d` 2026-10-09 — HONESTY RULE block + 7 new `Monitor` fields: `physicalSizeValid @27`, `refreshRateValid @28`, `refreshRateMin @29`, `refreshRateMax @30`, `refreshRateRangeValid @31`, `edid @32`, `edidValid @33` (display.capnp:267-375). | **IMPORT-TO-CANONICAL** (with a producer gap — see Part 3) | B |
| `cli.capnp` | `1619da8d` 2026-10-09 — command registry: `listCommands @17`, `listUnavailable @18`, `getSyntax @19` + `CommandRegistration`, `CommandPresentation`, `AvailabilityReason`, `SyntaxReference`, `DomainInfo` (cli.capnp:67-178). | **IMPORT-TO-CANONICAL** | D |
| `discovery.capnp` | `1619da8d` 2026-10-09 — RUNTIME HEALTH block: `ServiceHealthDetail` (discovery.capnp:186) + `resolve @24`, `getRuntimeHealth @25`, `listRuntimeHealth @26`, `listQuarantined @27` (:527-541). | **IMPORT-TO-CANONICAL** | A |
| `service.capnp` | `1619da8d` 2026-10-09 — `resolve @49`, `getHealth @50`, `listHealth @51`, `listQuarantined @52` + `ServiceHealth` (service.capnp:214-228, :356). | **IMPORT-TO-CANONICAL** | A |
| `kernel.capnp` | `1619da8d` 2026-10-09 — `getTopology @38`, `getCurrentCpu @39`, `getTickStats @40` + `CpuTopology`, `TickStats`, `EventSubscriptionService` (kernel.capnp:206-208, :219, :261, :355); **`CapOperation`/`CapRights` deleted in favour of capability.capnp's `Operation`** (:628-640); `CapabilityGrant.expiry` `@5`→`@4`. | **CONFLICT** (capability-vocabulary refactor + grant ordinal break) — naledzi wins on the vocabulary, official wins on the ordinal | A |
| `boot.capnp` | `692ba1e7` 2026-09-24 (+240, "boot-info CLI baseline") then `1619da8d` 2026-10-09 (+65) — `BootManifest.kernels @39 :KernelSelectionSet` + `KernelSelectionSet`/`KernelSelectionSource` (boot.capnp:168-214); **`BootService` interface replaced wholesale** (`handOff@0…delegateCapability@10` → `getInfo@0…subscribe@16`, :730-784) plus 14 new types (`BootInfo`, `BootParameters`, `BootEntry`, `BootLogEntry`, `BootSplashConfig`, `SecureBootStatus`, `BootAttempts`, `BootMethod`, `FirmwareType`, …); `Module.data :Data` → `vaddr @1`/`size @2` (:1383); `handlerTableVaddr` `@7`→`@8` with `reserved @7 :Void` (:1371-1374). | **CONFLICT** — **manifest wins: naledzi; BootService interface: needs an explicit merge decision (recommend official's surface + naledzi's additive ordinals)** | A |
| `shell.capnp` | `1619da8d` 2026-10-09 — **+734 lines**: a whole second interface `ShellService` (45 methods, shell.capnp:329) alongside a `Session` interface that is **byte-identical to official's** (67 methods, verified by block diff), plus a file header recording the two-surface design decision and the fix of the official file's mangled `using import "power.capnp".PowerState;# ══…` line 4. | **IMPORT-TO-CANONICAL** (the ShellService surface; not a conflict) | D |
| `system.capnp` | `1619da8d` 2026-10-09 — HONESTY RULE header + 22 new structs/enums (`CpuInfo`, `CpuTopology`, `MemoryInfo`, `MemoryRegion`, `SwapInfo`, `DiskInfo`, `GpuInfo`, `ThermalZone`, `FanInfo`, `PowerSupply`, `LoadInfo`, `UptimeInfo`, `SystemTime`, `FirmwareInfo`, `ChassisInfo`, `KernelInfo`, `ArchitectureInfo`, `SystemCapability`, …) and `System` `@9`–`@25` (`getCpuInfo`…`getSystemCapabilities`, system.capnp:68-121); producer is the new `shared/boot-protocol/src/cpuid.rs`. | **IMPORT-TO-CANONICAL** | A |

**Classification tally:** IMPORT-TO-CANONICAL ×8 (`gpu`, `console`, `input`*, `display`,
`cli`, `discovery`, `service`, `shell`, `system`) — of which `input` is import-with-reissue.
CONFLICT ×3 (`boot`, `kernel`, `input`). SUPERSEDED-BY-OFFICIAL ×1 (`ai`).
NO-OP ×1 (`types`). DO-NOT-IMPORT ×1 (`improved.md`).

### The three conflicts, resolved per concern

**`boot.capnp` — CONFLICT.**
*Concern 1: `BootManifest` content.* Additive on the naledzi side: official has 39 fields
(`@0`–`@38`), naledzi has 40 (`@0`–`@39`). Wire-compatible. **Naledzi wins** — the
runtime kernel-selection envelope is exactly the "selection as data, not a string in a
build script" fix the canonical audit asks for in spirit (boot.capnp.md:47's action 1
wants open content; `KernelSelectionSet.selectedPresent`/`defaultPresent` is that discipline
applied honestly).
*Concern 2: `Module` payload.* Naledzi replaces inline `data :Data` with a `vaddr`/`size`
reference pair. **Naledzi wins** — this is literally boot.capnp.md action 4, already done.
*Concern 3: `BootService` method surface.* This is the hard break. Official's
`handOff @0 / state @1 / subscribe @2 / pull @3 / cancel @4 / verifyAttestationChain @5 /
firmwareUpdate @6 / firmwareRollback @7 / configureNetworkBoot @8 / enableHardwareDevice @9 /
delegateCapability @10` (boot.capnp:661-689) is gone; naledzi's `getInfo @0 / getParameters @1 /
setParameters @2 / listEntries @3 … subscribe @16` (boot.capnp:730-784) **reuses `@0`–`@6`
for entirely different meanings** and silently drops the audit-9 attestation methods.
Neither tree can consume the other's boot service. **Resolution: neither side wins
wholesale.** Take naledzi's *types* and *methods* but re-issue the ordinals: official's
`handOff/state/subscribe/pull/cancel` keep `@0`–`@4` (they are the published wire contract
and the subscription shape other schemas copy); naledzi's `getInfo @0`…`getBootAttempts @14`
move to `@17`+; `verifyAttestationChain @5`…`delegateCapability @10` are retained but
re-examined against the rewrite's R1 pass (they are the technology-museum candidates, not
free wins). Note `subscribe` is the one name on both sides — naledzi puts it at `@16`,
official at `@2`; the renumber above makes that harmless.
*Concern 4: new technology enums.* Naledzi added `BootMethod {efi,bios,coreboot,uboot,petitboot}`
and `FirmwareType {uefi,legacy,coreboot,openFirmware}` — **the exact class boot.capnp.md
action 2 deletes**. These must NOT be imported; if the boot-info CLI needs them they belong
as open `Text` tokens per the audit's prescription.

**`kernel.capnp` — CONFLICT.**
*Concern 1: capability vocabulary.* Naledzi deleted `CapOperation`/`CapRights` and now uses
capability.capnp's `Operation` at `delegateCapability @28` (`KernelSelectionSet`-adjacent
`CapabilityGrant.operations @3`) and at `CrossKernelCapability.operations @3`. **Naledzi
wins** — this is kernel.capnp.md action 4, already executed and correctly reasoned (the
comment at kernel.capnp:628-640 spells out that `grant`/`delete` could not be expressed in
`Operation`'s vocabulary, so the local copy was a grant nobody checked). Import this.
*Concern 2: `CapabilityGrant` shape.* Official is `{cap @0, source @1, target @2,
operations @3, rights @4, expiry @5}`; naledzi is `{… operations @3, expiry @4}`. Dropping
`rights` and moving `expiry` to `@4` is a **field-ordinal wire break**. **Official wins** —
keep `expiry @5` and treat `@4` as reserved; the capability-vocabulary fix does not require
touching `CapabilityGrant`'s ordinals, and this break was collateral damage.
*Concern 3: scheduler introspection.* Naledzi adds `getTopology @38`/`getCurrentCpu @39`/
`getTickStats @40` + `CpuTopology`/`TickStats`. This grows the very class the audit
condemns (`KernelIntrospectionTarget.scheduler`, TIMELESSNESS.md:84). But unlike the
condemned block, naledzi's addition is **measured data with an explicit provenance honesty
rule** (`valid :Bool` + `source :Text`, `perCpuBusyValid`, `sinceSampleUs`) and it is
**implemented** (`servers/init/src/main.rs:853 handle_get_topology`, `:890 handle_get_tick_stats`,
dispatched at `:1080-1081`). **Verdict: import, but hold for the R1/swap-test wave** — it
is a real, honest, consumed contract that nonetheless needs a documented carve-out from
"internal kernel machinery is excluded", or it becomes the next contradiction. Wave A,
after the introspection strip.
*Concern 4:* naledzi also adds a seventh unreachable interface (`EventSubscriptionService`,
kernel.capnp:355) — the audit's R8 finding currently lists six. It must be counted in the
rewrite's unreachable-interface purge.

**`input.capnp` — CONFLICT (narrow).**
Naledzi fixed the audit's #1 gap ("no key event path") by inserting `keyboard @0` at the
*head* of the `InputEvent` union, which **re-numbered every existing arm** (eyeTracking
`@0`→`@1`, brainInput `@1`→`@2`, spatialInput `@2`→`@3`, digitalCrown `@3`→`@4`,
cabinAttention `@4`→`@5`, custom `@5`→`@6`). Any existing consumer of the extended-modality
union breaks silently. **Resolution: import `KeyboardEvent` and the `keyboard` arm, but
issue it at a fresh ordinal (`@6`, displacing `custom` to `@7`)** so the five published
arms keep their discriminants. The cost is one ordinal re-shuffle in a schema that
`input.capnp.md` action 1 itself says should be done pre-release anyway.
`KeyboardEvent`'s own field shape is good and should be imported verbatim — `scancode :UInt16`
raw set-1/HID + `text :Text` translated Unicode + `modifiers` + `deviceId` is the one
place the protocol names the scancode-vs-codepoint split explicitly.

---

## Deletion risks

Counts are over the **live** tree (`naledzi/{kernel,uspace,servers,shared,boot}` + every
non-excluded `build.rs`). Excluded: `.kilo/worktrees/*` (4 agent worktrees that each carry
a duplicate copy of `ipc-message`), `BACKUPS_NOT_TO_TOUCHED/`, `target/`, `vendor/`.
Also excluded from "live": `uspace/servers/compositor/{kage,kukan-slint,wall-lockscreen}` —
three **separate Cargo workspaces** none of which is in the root `Cargo.toml` `members`
list — which is called out explicitly where it matters.

### `ipc-message.capnp` — **NEEDS-MIGRATION (build break, no logic break)**

The audit's claim "zero references exist repo-wide (verified by search)" is **true in the
canonical tree and false in the working tree**: `ipc-message.capnp` is a *compiled* schema here.

| Consumer | Count |
|---|---|
| `build.rs` compiling it | 2 — `uspace/lib/capnp/build.rs:8`, `uspace/services/ipc-service/build.rs:14` |
| `include!(.../ipc_message_capnp.rs)` | 2 — `uspace/lib/capnp/src/lib.rs:8`, `uspace/services/ipc-service/src/lib.rs:29` |
| `mod ipc_capnp` declarations | 2 (same files) |
| `ipc_capnp::` type references | **0** |
| `LogParams` references anywhere | **0** (only its own definition) |
| name-only references | 1 — `kernel/src/ipc.rs:588` `fn test_ipc_message_size_layout` (a test name) |

Both consuming crates **are** in the root workspace, so deleting the file breaks
`space-capnp` and `space-ipc-service` at codegen. **But nothing reads a type from it** —
`LogParams` is dead in both trees. Verdict: the audit's *reasoning* is right; its
"verified no consumers" was scoped to the wrong tree. Migration is mechanical:
drop `"ipc-message.capnp"` from both `build.rs` lists and delete both `mod ipc_capnp`
blocks. No logic, no naming, no call-site change. ~15 lines of build glue.
**And because naledzi carries its own byte-identical copy (148 B, same retired-id header),
the deletion must happen in both trees or the fork diverges by exactly the file the
doctrine says should not exist.**

### `textinput.capnp` → `ime.capnp` — **SAFE (zero consumers on both sides)**

| Consumer | Count |
|---|---|
| `build.rs` compiling `textinput.capnp` | **0** |
| `mod textinput_capnp` | **0** |
| `textinput_capnp::` type refs | **0** |
| any `textinput`/`text_input` reference in live `.rs`/`.toml` | **0** — the only hits are `uspace/servers/system/src/state.rs:21,63,196,249` (`CAP_TEXT_INPUT`, the `"textInput"` capability-bitmap string), which is a **flag in system.capnp's `Capabilities` bitmap, not a schema import** |
| `ime_capnp` consumers | **0** — the merge *target* has no consumers either |

Confirmed by the finding itself: system.capnp.md already flags `textInput @7` as "names a
schema slated for deletion", and `ime.capnp` is compiled by no `build.rs` in the tree.
The merge strands **no code**. Migration: none beyond the schema merge itself (port
`ContextRequest`/`SurroundingText`/`InputMethodInfo`/`InputMethodState`'s better halves,
per the ime audit's port list). One caveat the audit should absorb: after the merge the
canonical tree will have `ime.capnp` with zero consumers, so it is a candidate for the
same R8/zero-consumer treatment as the interfaces the kernel audit purges.

### `surface.capnp` → `compositor.capnp` — **NEEDS-MIGRATION (strands a live, diverged fork)**

| Consumer | Count |
|---|---|
| `build.rs` compiling `surface.capnp` from the canonical tree | **0** |
| `mod surface_capnp` in the live tree | **0** |
| `surface_capnp::` refs in the live tree | **0** |
| `surface_capnp` refs in `uspace/servers/compositor/kukan-slint/wall-lockscreen/` | **20 refs across 4 files** — `wall-protocol/src/lib.rs:6` (`pub mod surface_capnp { include!("gen/surface_capnp.rs") }`), `wall-compositor/src/lib.rs`, `wall-protocol/src/gen/compositor_capnp.rs`, `wall-protocol/src/gen/surface_capnp.rs` |

So in the root workspace the deletion is safe — **but not in the repo**. The wall lockscreen
subtree is a separate workspace with a **vendored, git-untracked, stale** generated copy
(`src/gen/surface_capnp.rs`, 41,363 B, header: `source: home/lufuno/wall-lockscreen/protocol/surface.capnp`,
capnpc 0.25.3). That path does not exist, and `wall-protocol/build.rs:3` points at
`../../protocol` — a directory that is absent — so that build is already broken and the
`gen/` artifacts are frozen. Consequence: **the wall fork has already silently diverged** from
the canonical surface contract, and it will keep compiling its own frozen `surface.capnp`
world after the merge deletes the canonical one. Migration must therefore be explicit:
either delete the vendored `gen/surface_capnp.rs` + `wall-protocol`'s `surface_capnp` mod and
repoint the 20 references at compositor's types, or restore that build to compile from
`naledzi/protocol/schemas` **before** the merge lands. Composition note: the kage workspace
compiles `compositor.capnp` and uses `SurfaceRole` from **compositor's own** enum
(`kage/main.rs:89-98`), so it is unaffected by the merge.

Also worth recording for the rewrite: naledzi's `gpu.capnp` is the answer to the surface
audit's R5 row `setGpu @40 (gpu :GpuSelection { gpuId, requireHwAccel })` — the GPU
contract now exists, so that field's removal has somewhere to land instead of nowhere.

### `filesystem.capnp` → `files.capnp` — **NEEDS-MIGRATION (strands the filesystem server)**

| Consumer | Count |
|---|---|
| `build.rs` compiling it | 1 — `uspace/servers/filesystem/build.rs:4` compiles `["types.capnp", "filesystem.capnp", "files.capnp"]` — **both** files, in one list |
| `mod filesystem_capnp` | 1 — `uspace/servers/filesystem/src/main.rs:20` |
| `filesystem_capnp::` type refs | **61** (all in `uspace/servers/filesystem`) |
| `files_capnp::` type refs | **107** (same crate) — `files::analyze/apply/backup/batch/branch/change/check/clone/close/compare/copy/create/deduplicate/file/get/file/get/list/lock/open/poll/pull/read/remove/rename/resolve/search/stat/store/subscribe/sync/touch/walk/warm/watch/write` (35 methods) vs `filesystem::clone/get/list/mount/resolve/set/snapshot` (7 methods) |

This is the **only** deletion candidate that strands substantial real code: the filesystem
server is a live root-workspace crate that dispatches against **both** interfaces. The
merge is feasible precisely because one `build.rs` already compiles both, but it is a
genuine port: the 7 `filesystem::*` methods (`mount`, `unmount`/`set`, `snapshot`, `clone`,
`resolve`, `list`, `get`) must be relocated into `Files` (or into `mount.capnp`, per the
audit's action 1) and every call site in `uspace/servers/filesystem/src/main.rs` retargeted.
The audit's wire-breaker note is correct and is the real hazard: `files.capnp` imports
`FS.SpecialPathType` from the very file being deleted, so the merge order matters —
move `SpecialPathType` first. Because naledzi's copy of both files is byte-identical to
official's, the merge happens in both trees or the fork diverges on the file protocol.

---

## Invalidated audit findings

**48 findings across 10 of the 11 differing schemas.** (`types.capnp` contributes 0.)

### `boot.capnp` — 6 invalidated
1. **R2 row / action 4** "`Module { name, data :Data, hash }` — module blobs inline
   (`:1114`)" → **already fixed** in naledzi (`Module.vaddr @1`, `size @2`, `hash @3`;
   boot.capnp:1383). The rewrite must not re-do this or re-introduce the inline blob.
2. **action 5** "Resolve `handlerTableVaddr` (`:1109`): either delete it or document why" →
   naledzi did **neither**: it renumbered `@7`→`@8` and filled `@7` with `reserved :Void`
   (boot.capnp:1371-1374). The raw function-pointer table survives under a new ordinal;
   the audit's fix is unimplemented and its line reference is dead.
3. **action 2** "Delete `BootloaderKind`, `FirmwareKind`, … (12 enums)" → naledzi **added
   two more enums of exactly that class** (`BootMethod`, boot.capnp:810; `FirmwareType`,
   :819). The deletion list is now 14, and an import of the boot-info surface without
   stripping them lands new R1 violations in the rewritten file.
4. **Verdict** "the largest single collection of frozen technology in the entire 92-schema
   tree … 1166 lines" → naledzi is 42,089 B / 1,466 lines and grew.
5. **UX row** "`BootManifest` field count (38)" → 40 in naledzi (`kernels @39`).
6. **Verdict / Wire-breakers** read official's `BootService` (`handOff @0`…
   `delegateCapability @10`) as the live surface → naledzi **replaced it wholesale**
   (boot.capnp:730-784), reusing `@0`–`@6` for different meanings and deleting the audit-9
   attestation methods. A hard wire break invisible to the audit, and a merge decision the
   rewrite cannot defer.

### `kernel.capnp` — 5 invalidated
1. **action 4 + R6 row** "Replace `CapOperation`/`CapRights` with capability.capnp
   `Operation`/`Constraints` (`:164`, `:437-438`, `:798`)" → **already executed** in naledzi
   (kernel.capnp:164 uses `Operation`; the deletion and its rationale are recorded at
   :628-640). The rewrite should cite this as done and not re-plan it.
2. **Wire-breakers** "ordinals unique across `@0..@37`" → `KernelService` now spans `@0..@40`.
3. **NEW** (not in the audit): `CapabilityGrant` dropped `rights @4` and moved `expiry`
   `@5`→`@4` (kernel.capnp:620-643) — a field-ordinal wire break inside a struct the audit
   verified as collision-free.
4. **R8 row** "Six interfaces; no method anywhere returns any of them" → **seven**: naledzi
   adds `EventSubscriptionService` (kernel.capnp:355), also unreachable. The purge list is
   incomplete.
5. **Verdict** "881 lines" and its premise that the accretion stops at introspection →
   naledzi grows the same condemned class (`getTopology @38`/`getCurrentCpu @39`/
   `getTickStats @40`, kernel.capnp:206-208), i.e. scheduler-internal state exposed as
   protocol queries — the exact TIMELESSNESS.md:84 finding, now with three new methods.

### `system.capnp` — 5 invalidated
1. **Verdict** "FIX (targeted), small file, one structural defect … 110 lines" → naledzi is
   ~920 lines / 22 new structs / 16 new methods.
2. **R1 row + Duplicates row** "47 fixed `Bool` fields naming today's service list …
   three capability-declaration mechanisms in the batch" → **four**: naledzi adds
   `SystemCapability` + `getSystemCapabilities @25` (system.capnp:121, :719).
3. **Zero-cost/eco** "No bulk payloads. No findings." → naledzi adds 22 measurement structs
   (`CpuInfo`, `MemoryInfo`, `DiskInfo`, `GpuInfo.edid`, `ThermalZone`, `FanInfo`,
   `PowerSupply`, …) that each must be filled from boot-time enumeration.
4. **NEW cross-schema finding the audit lacks**: naledzi's documented refusal to import
   `boot.capnp` (system.capnp:5-8: "no `using B = import "boot.capnp"` here, deliberately …
   not currently possible without editing four uspace/*/build.rs files"). Either the
   rewrite honours that (a 4th firmware-kind vocabulary, versus boot.capnp's `FirmwareKind`
   and naledzi's new `FirmwareType` — three spellings of one concept) or it resolves the
   build-helper limitation. Either way it is an R6 collision the canonical audit missed.
5. **Duplicates row** "`Capabilities` overlaps `abi.capnp:208` `Abi.features`" → also
   overlaps the new `SystemCapability`, so the recommended action 1 ("replace the bitmap
   with an open set") now has two targets in the same file.

### `discovery.capnp` — 5 invalidated
1. **Verdict** "601 lines — strip the service-mesh half" → ~730 lines with a new RUNTIME
   HEALTH block (discovery.capnp:172-216).
2. **Wire-breakers** "ordinals unique (`@0..@23`)" → `@0..@27`.
3. **R6 row** "Four same-name-different-shape pairs across two files" → **five**, plus a
   *third* health-result shape (`ServiceHealthDetail` vs `ServiceHealthStatus` vs
   service.capnp's new `ServiceHealth`), and naledzi explicitly documents reusing
   `ServiceState` across files (discovery.capnp:176-180) — the audit's worst case
   (enum-vs-struct) is now a three-way.
4. **action 1** "cost: none (no consumers)" → naledzi implements `resolve @24`,
   `getRuntimeHealth @25`, `listRuntimeHealth @26`, `listQuarantined @27`
   (`uspace/servers/discovery/src/handlers.rs:260, 288, 328`; dispatch at `:949-951`). The
   mesh-struct deletion is still low-cost, but "discovery.capnp has no consumers" is false.
5. **Duplicates row** "`ServiceHealth` (`:154-169`) vs `service.capnp:302-307`" → the pair on
   disk is now `ServiceHealthStatus` (service.capnp:336) vs `ServiceHealth` (:356) vs
   discovery's `ServiceHealthDetail` (:186); the finding's file:line no longer resolves.

### `service.capnp` — 4 invalidated
1. **Verdict** "468 lines" → ~600 lines with a new Runtime Health block.
2. Implied ordinal range `@0..@48` → `@0..@52`.
3. **action 1** "cost: consumers re-acquire — none exist pre-release" **and the naledzi
   file's own comment** "Nothing consumes this file today (no build.rs lists
   service.capnp)" (service.capnp:197-199) → **both false**: `servers/init/build.rs:4`
   compiles `service.capnp` and `servers/init/src/main.rs:1084` dispatches
   `listQuarantined @52`. There is at least one real consumer of the capability gate the
   audit says can be added for free.
4. **R6 row** "Four duplicate type names across `service`/`init`/`discovery`" → five, plus
   the new `ServiceHealth`/`ServiceHealthStatus` pair.

### `display.capnp` — 5 invalidated
1. **Verdict** "897 lines / the best-structured large schema in this batch" → 34,331 B with a
   30-line HONESTY RULE block (display.capnp:267-296).
2. **R6 row** "six encodings of one physical quantity where `T.Frequency` exists" →
   **eight-plus**: naledzi adds `refreshRateValid @28`, `refreshRateMin @29`,
   `refreshRateMax @30`, `refreshRateRangeValid @31` (display.capnp:327-333). Action 2's
   "merge into one `T.Frequency`-typed method" now has a strictly bigger surface.
3. **UX row** "`Monitor` has 27" → **33** (7 new fields, `@27`–`@33`).
4. **R6 row** "`getEdidData @63 → T.DataHandle` plus `DisplayMetadata.rawDescriptor @5 :Data`
   — two raw-descriptor channels … nothing states they are the same bytes" → **three**:
   `Monitor.edid @32 :Data` + `edidValid @33` (display.capnp:374-375).
5. **NEW gap the audit does not have**: the HONESTY RULE's `*Valid` flags have **no
   producer**. `uspace/servers/display/fb-embedded/src/handlers/monitors.rs:33-36` sets
   `physical_size_mm` and `set_refresh_rate` but never `physical_size_valid`,
   `refresh_rate_valid` or `edid_valid`. Importing the fields without the flags populated
   ships exactly the "one way to proceed when the hardware had nothing to say: invent a
   value" defect the block was written to prevent — the flags will read `false` on hardware
   that does have a panel.

### `cli.capnp` — 5 invalidated
1. **Verdict** "335 lines" → ~460 lines.
2. **R7 row + Gaps row + action 1** "The missing registry is the gap: no `listCommands`, no
   command→schema binding, no argument types … the CLI stays hand-maintained per domain
   forever" → naledzi **added** `listCommands @17`, `listUnavailable @18`, `getSyntax @19`
   + 6 structs (cli.capnp:67-178). The enumeration half is **fixed**; the schema-derived
   half is still open (`CommandRegistration.methodId @1 :UInt32` is a number, args are
   still `List(Text)`). The finding must be split, not carried forward.
3. **action 1's cost** "the dispatch core is a rewrite (~2 methods + 2 structs)" → already
   spent; the estimate is wrong for the file the OS now runs.
4. **R3 row** "`checkPermission @11 (command :Text)` — authority interrogated per call by
   name" → naledzi keeps it **and** adds `CommandRegistration.capability @2 :Text` — a
   per-command-name capability token, persisted in a registry the whole file is built
   around. The finding must be re-scoped from "delete one method" to "the registry design
   sits on the wrong side of the authority rule", which is a bigger fix.
5. **Eco/R7 row** `getJobStatus @2` / `pollPrompt @16` polling — both still present unchanged
   (cli.capnp:13, :53) and untouched by the +125-line addition. Not invalidated, but the
   rewrite should record that the file grew by four methods without addressing any of its
   three standing polling findings.

### `console.capnp` — 4 invalidated
1. **Verdict** "723 lines" → 24,351 B; every `file:line` citation in the audit is dead.
2. **action 4** "Choose one input pattern: delete `readInput @0` (blocking, uncancellable,
   no error) and keep `subscribeInput`" → naledzi's new `pushInput @47` (console.capnp:386)
   documents `readInput`/`subscribeInput` as the **production pull path** ("the console
   then pulls them via `readInput` / `subscribeInput` — pull-based data flow; the push is
   just a wake-up"), and `uspace/servers/console/src/main.rs:891` implements the dispatch.
   Deleting `readInput` would strand the shipped design.
3. **Gaps row** "**No output-flow control** … `writeText @2`/`writeStyled @3` have no
   backpressure, no chunking" → naledzi adds `writeBytes @46 (data :Data)`
   (console.capnp:379), a **third** unbounded write path, and it is now the hot path for
   fullscreen TUIs (`vim`, `htop`, `less`) and SSH bridges. The unbounded-write family is
   3, not 2.
4. **Duplicates row** "`KeyEvent.key @0 :Text` (console.capnp:49) vs `T.KeyCode.code :UInt32`
   — **two key-identity representations in the batch, neither with a defined spelling** …
   the batch's worst implementer trap" → **three**: input.capnp's new
   `KeyboardEvent.scancode @0 :UInt16` + `text @2 :Text`, with the input service's own
   comment documenting the split and its resolution
   (`uspace/servers/input/src/main.rs:127-129`: "The shell re-decodes scancodes through its
   own pc-keyboard state machine to get the Unicode text").

### `input.capnp` — 5 invalidated
1. **Verdict (2)** "**The schema has no key or pointer event path at all**:
   `subscribeInputEvents @46` carries eye-tracking/brain/spatial/crown/cabin events only" →
   the **keyboard path now exists** (`InputEvent.keyboard @0`, `KeyboardEvent`,
   input.capnp:696-719). Pointer/touch are still absent, so this is half-invalidated.
2. **Gaps row + action 1** "**No key or pointer event contract.** … the batch's most
   consequential hole … Cost: ~20 lines and an ordinal addition — the highest-value single
   change in this file" → the keyboard half is **done** (a struct + a union arm + the
   input-service implementation at `uspace/servers/input/src/main.rs:120-133`).
3. **Wire-breakers** "no ordinal collisions (verified mechanically)" + the `InputEvent`
   union → naledzi **re-numbered every existing arm** to make room for `keyboard @0`
   (eyeTracking `@0`→`@1`, brainInput `@1`→`@2`, spatialInput `@2`→`@3`, digitalCrown
   `@3`→`@4`, cabinAttention `@4`→`@5`, custom `@5`→`@6`). A discriminant wire break the
   mechanical check did not anticipate, and a merge decision the rewrite must make
   explicitly (see the conflict resolution above).
4. **R4 row** "`T.KeyCode.code :UInt32` — an opaque numeric id with **no published domain**
   … the single largest source of divergent implementations in the file" → a **fourth**
   representation exists (`KeyboardEvent.scancode :UInt16`, raw PS/2 set-1 / USB HID usage)
   and the input service treats it as the live one.
5. **Verdict** "743 lines" → 24,732 B; and **R7 row** "Every subscription `pull` returns a
   bare value with **no error variant**" is **unchanged by the new code** — naledzi's
   `InputEventSubscription.pull @0 () -> (events :List(InputEvent))` still has no error
   variant, so the finding persists in the file the OS runs and was not addressed by the
   one change that most needed to address it.

### `shell.capnp` — 4 invalidated
1. **Verdict** "a 75-method kitchen sink … 1037 lines" → **112 methods across two
   interfaces** (`Session` 67 + `ShellService` 45), 64,511 B, 116 top-level types.
2. **action 1** "Strip every duplicated service surface to a thin façade: notification,
   clipboard, settings, audio, network, bluetooth, brightness, power. Gain: shell methods
   shrink (~30 removed)" → naledzi's file header (shell.capnp:18-57) records the **opposite
   decision**: the session methods were deliberately KEPT at their existing ordinals
   (`@13`–`@19` clipboard, `@28`–`@29` Bluetooth, `@55`–`@61` pagination, `@62`–`@75`
   multi-modal/voice/gesture/accessibility) and the interpreter surface was added
   alongside. The audit's deletion plan collides head-on with a recorded design decision
   that cites a plan document; this is the single most consequential merge in the delta.
3. **action 2** "Delete the speculative feature blocks with no consumer: AR spatial shell,
   car zones, shell analytics, AI completion, handoff, command-history analytics … the
   contract shrinks ~200 lines" → naledzi **added ~730 lines of exactly that class**
   (`ShellService`: natural-language `interpret @4`, `confirmAndExecute`, guided sessions,
   undo, watchers, bookmarks, selector/domain completion) with **zero consumers today**
   (`cli.capnp`/`shell_capnp` is compiled by no live `build.rs`; `smart-shell`'s
   `build.rs:5-15` lists console/system/process/logging/abi/capability/manifest/init/input/
   discovery/clock but **not** `shell.capnp`). Applying action 2 to naledzi nets a file that
   is larger than the one audited.
4. **Wire-breakers** "None structurally. Semantic breakage risk: … `CommandHistoryAnalytics`
   at 1018 vs `cli.capnp:57`" → the collision is **still live** (cli.capnp:182 and shell's
   copy both survive the delta), so the recommendation stands but both line references are
   dead. Separately, the audit read `shell.capnp:4` as a clean
   `using import "power.capnp".PowerState;` when the official file actually has the `using`
   and the banner comment on one line; naledzi fixed that. Cosmetic, but it means the
   official file's line 4 is malformed and the naledzi file's is not.

### `types.capnp` — 0 invalidated
The only delta is the one-line comment rename at `types.capnp:1771`
(`CYBERSPACE PROTOCOL` → `NALEDZI PROTOCOL`, commit `ed0b37b1`). The files are otherwise
byte-identical (80,220 vs 80,223 B), so **every audit finding stands and every line
reference remains valid**. The expected pattern "naledzi's types.capnp carries foundation
types" is verified, but it is **not** a semantic delta — there is no naledzi-side
foundation-type work to import. Consequence for the rewrite: the two targeted deletions
(`SubscriptionResult`/`SubscriptionData`, `types.capnp.md` action 1) and the promoted
canonical `UnknownEvent` (action 2) must still be done **in both trees**, because there is
nothing in the fork that already did them. And because `types.capnp` is imported by 41
crates' `build.rs` (533 type references), any change to it is the widest-blast-radius
change in the whole rewrite.

---

## What the rewrite must do differently

1. **Re-scope the mechanical verification.** All five batch summaries verify "zero undefined
   `T.*` references" and "zero method-ordinal collisions" against the **official** files.
   Two of those claims are already falsified by the naledzi variants: `boot.capnp`'s
   `BootService` (ordinals `@0`–`@6` reused with different meanings) and `input.capnp`'s
   `InputEvent` (every arm renumbered). Any rewrite that applies the audits unchanged will
   import or destroy wire contracts the OS is actually speaking.
2. **Two of the audits' headline actions are already done.** `kernel.capnp` action 4
   (`CapOperation`/`CapRights` → `Operation`) and `boot.capnp` action 4
   (`Module.data` → reference union) are complete in naledzi. Delete them from the plan and
   cite the fork as the implementation, or the rewrite will do them a second time with a
   different shape and fork the wire format.
3. **Two of the audits' headline gaps are already closed.** `input.capnp`'s "no key event
   path" and `cli.capnp`'s "no command registry" both have naledzi implementations with
   real or planned consumers. The remaining halves (pointer/touch; schema-derived binding)
   are what the rewrite should actually plan.
4. **Four honesty/oracle contracts were added downstream and have no producer or consumer
   yet.** `system.capnp`'s 22 measurement structs (producer exists — the new `cpuid.rs`),
   `display.capnp`'s `*Valid` flags (**no producer** — the display server never sets them),
   `boot.capnp`'s `KernelSelectionSet` (**no consumer**), and `shell.capnp`'s `ShellService`
   (**no consumer**). Import the shapes, but track the missing halves as named work items
   rather than assuming the import is complete.
5. **The deletion list must be re-run against the working tree, not the canonical one.**
   `ipc-message` is compiled by two live crates; `filesystem` is consumed 61 times by the
   filesystem server; `surface` is frozen into a diverged, separate workspace; `textinput`
   really is dead. Only the last one is a free deletion, and its merge target
   (`ime.capnp`) is equally dead.

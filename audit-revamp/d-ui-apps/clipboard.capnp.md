# Audit — clipboard.capnp (265 lines)

## Verdict
**FIX (targeted).** The file reads like it already fixed R2 — it *defines* the correct zero-copy type `ClipboardContent { mimeType, data :T.DataHandle }` (98–102) and its history item model is sound — but the live interface never uses it: `getContent @0 -> (data :Data)` and `setContent @1 (mimeType, data :Data)` (20–23) pass clipboard payloads **inline**, on the protocol's single most copy-prone path. The zero-copy type is a dead orphan; the methods beside it copy whole images into messages. Add a second contradiction: the security model (49–70, 170–239) is a from-scratch string-ACL that duplicates — and contradicts — capability.capnp's authority system. Fix: wire the methods to the DataHandle type, delete the ACL in favor of capability references, and the file is exemplary.

## Wire-breakers
`ClipboardContent` (98) is referenced by no method — a dead type whose existence proves the intended design was bypassed. Verified by search: the only `Data`-payload methods return `Data` directly.

## Doctrine violations
| Rule | file:line | What fails | Concrete 2046 failure / cost |
|---|---|---|---|
| R2 | `clipboard.capnp:20, 23` | `getContent @0 (mimeType) -> (data :Data)`, `setContent @1 (mimeType, data :Data)` — bulk payload inline | The highest-volume clipboard path in the batch: pasting a screenshot or a PDF copies the entire buffer into the RPC message, deserialized into a fresh allocation. A 20 MB paste = 20 MB copied, twice (request + response on round trips), when the buffer already exists in shared memory. `T.DataHandle` exists in this very file, unused |
| R2 | `clipboard.capnp:79` | `convertContent @19 -> (data :Data, success :Bool)` — converted payload inline plus a bool-instead-of-result | Same copy cost, plus failure hidden in a boolean that callers will ignore (`custom 0-byte Data` vs error indistinguishable) |
| R3 | `clipboard.capnp:58–70, 184–203` | `grantAccess/revokeAccess/getAccessControlList` with `ClipboardAccessControlEntry { entityId :Text, grantType :AccessGrantType, allowedMimeTypes }` — a parallel access-control system with permission strings | The doctrine is explicit (DESIGN_PRINCIPLES:399, TIMELESSNESS:135): the capability system IS access control; do not define permission strings. Now every clipboard item has two authorities (its capability reference and its ACL entry) that must agree forever — the classic two-paths divergence the doctrine names |
| R6 | `clipboard.capnp:67` | `getAuditLog @15` re-implements an audit trail (actor, action, result, source) alongside `capability.capnp`'s `AuditEntry`/`queryAudit @14` | Two audit formats for one action space; a security consumer must merge them. Capability's is canonical |
| R7 | `clipboard.capnp:29, 41, 67, 117` | History/audit pulls return `totalCount :UInt32` (inconsistent with the batch's `total :UInt64`) and `getAccessControlList @14` returns an unbounded list with no pagination at all | A heavily-used clipboard (password manager, screenshot tool) accumulates hundreds of entries; the ACL for a shared item is unbounded |
| R1 | `clipboard.capnp:176` | `ClipboardSecurityLevel { none, sensitive, encrypted, restricted }` names protection postures | Mostly closed — but it presupposes the *store* encrypts at rest (a backend choice), embedding "encrypted" as a wire-visible level rather than a reported property |
| R7 | `clipboard.capnp:73, 76` | `getPreview @17` and `validateContent @18 -> (valid :Bool, actualMimeType :Text)` — validation results as bare tuples | "Content doesn't match its claimed type" is a security-relevant event with no `T.Error` code and no severity; a consumer checking spoofed clipboard content must parse prose |

## Duplicates & overlaps
- vs `shell.capnp:343–366 ClipboardEntry` — shell's second clipboard model (with a `ClipboardContentType` enum shell pins/unpins through). Resolution: shell deletes its copy; this file is canonical (doctrine:219).
- `StructuredContentType` (128) sits unused by live methods — a third content-type model in the batch (clipboard's, shell's, and MIME-as-Text in both).
- `getSizeLimits.inlineThreshold @3 :UInt64` (264): a protocol field stating *when* to switch inline→buffer — an implementation tuning knob in the contract (Agnostic Test: performance tuning keeps out). The backend decides; the protocol just uses DataHandle.

## Gaps & holes
- **No ownership of selection vs clipboard**: X11/Wayland have primary/middle selection plus clipboard; the contract has exactly one clipboard. A 2046 input device with two concurrent selections (gaze + hand, or two users on one seat) has no vocabulary. Either document single-selection as a deliberate limit or add an open selection-name parameter — the fork will happen silently otherwise.
- **Paste consent**: `requireConsent @3 :Bool` (230) exists in the policy but nothing in the interface *implements* consent — no method to answer a prompt, so a backend enforcing consent must invent a side channel. That's a protocol hole with a guaranteed nonstandard resolution.

## Zero-cost / eco
- The inline `Data` payloads (R2 row) are the finding: the two hottest methods in the file force copies the file's own unused struct was built to avoid.
- `getSupportedMimeTypes @6` — unbounded list, trivial size. Fine.
- Change subscription (`ChangesSubscription`, 88–96) is pull-based with `pullPaginated` — the canonical pattern, correctly implemented.

## UX & implementer guidance
- `ClipboardChange.source @2 :Text` ("Application name or identifier… opaque text") — app identity as free text while `T.AppId` exists; consumers will string-match it to `ApplicationEntry.name`. The header (12–13) justifies Text to avoid coupling, but `T.AppId` is typed and opaque — decoupling was already solved.
- `setContent` has no notion of *offering multiple representations* (text + image + rich text at once) — the mechanism every real clipboard has. An app must call `setContent` once per type and the backend must guess they belong together; the shell's `ClipboardEntry` (shell.capnp:347–349) shows the multi-rep model this file lacks.
- `ClipboardAuditEntry.action @4 :Text` ("read, write, clear") — free-text action names where a closed enum exists everywhere else.

## Recommended actions
1. **Make `getContent`/`setContent`/`convertContent` carry `T.DataHandle`** (adopt the orphaned `ClipboardContent` as the parameter/return type). Gain: screenshot and file pastes become buffer references — the copy cost on the batch's hottest clipboard path disappears; the dead struct becomes live. Cost: two signatures, one new return type.
2. **Delete the string ACL and the audit trail** (58–70, 170–239); clipboard authority = capability.capnp references, audit = capability's. Gain: one authority path and one audit trail (the doctrine's explicit rule); ~90 lines removed. Cost: clipboard loses per-item ACL strings — capabilities express the same grants with revocation.
3. **Add multi-representation offers** (one `setOffer(List(ClipboardContent))` instead of N `setContent` calls). Gain: copy of an image with its text alternative is one call; backends stop guessing associations. Cost: one method added, one retyped.
4. **Name the selection semantics** (single selection, or open selection name parameter). Gain: dual-selection future devices stop forcing a fork. Cost: one optional parameter.
5. **Unify totals to `total :UInt64` and paginate `getAccessControlList`** (or delete it with action 2). Gain: consistent paging contract. Cost: trivial.
6. **Delete `inlineThreshold` from `ClipboardSizeLimits`.** Gain: the protocol stops prescribing implementation thresholds. Cost: one field.

# Verification — what is checked, what is not, and what remains

> **The pledge.** No claim ships that the gate cannot prove. A number that is
> not counted is not a number. A residual that is not listed is a lie with a
> schema ID.

This document exists to make that pledge auditable rather than rhetorical. It
states what `scripts/validate.py` enforces, what it currently reports, why the
gate still exits 0, and exactly which findings remain. Nothing here is a summary
of a memory: every figure comes from a command printed beside it.

---

## 1. How to check any claim in this repository

```bash
# the structural inventory quoted in README and SCHEMAS.md
python3 scripts/docstats.py

# the rule gate — the authority on every E-number
python3 scripts/validate.py

# the compiler is the only real authority on the schema language
capnp compile -I schema -o- schema/*.capnp

# a single file, without a code generator
bash scripts/check.sh schema/kernel.capnp

# the file count, the interface count, the payload positions
ls schema/*.capnp | wc -l
grep -h '^interface ' schema/*.capnp | wc -l
grep -o 'T.DataHandle' schema/*.capnp | wc -l
```

If a document disagrees with one of these commands, the document is wrong. The
repository's rule is that documentation is downstream of the artifact and is
regenerated, never argued with.

---

## 2. What the gate is

`scripts/validate.py` does not grep. It strips comments first — so a phrase in
prose is not evidence — and then parses declarations, interfaces, unions, enums
and fields. That distinction matters: the previous `grep`-based checker passed
almost everything, because it could not see an inline enum, a comment, or a
`custom` variant that was not last.

Every number it prints is computed from the tree it just parsed. No schema total
is hardcoded anywhere in the script, so the printed counts cannot drift from
`ls schema/`.

### Severity model

| Severity | Meaning |
|---|---|
| **ERROR** | Enforced. A finding fails the gate. Applied where the doctrine is already fully implemented. |
| **REPORT** | Measured, printed, and not blocking. Used while a rule is being driven to zero across the tree. |

`ai.capnp` is the gold standard and is held at ERROR for its rules. Every other
schema is REPORT, because the 2026-10-10 revamp rewrote the tree in five waves
and a wave may not land with a hard failure in a rule outside its scope. The
intent is explicit: **every schema reaches zero in every rule.**

### The rules

| Rule | Enforces | Severity today |
|---|---|---|
| E1 | `ai.capnp` declares zero enums | ERROR |
| E2 | `ai.capnp` carries no bulk list; payload is `T.DataHandle` | ERROR |
| E3 | `Capability` appears only on an accessor of `interface AI` | ERROR |
| E4 | Every interface is returned by at least one method | ERROR |
| E5 | Every stream's `pull` returns a structural terminator | ERROR |
| E6 | Every union has an `unknown`/`custom` arm | ENFORCED |
| E7 | Every struct has an open extension point | REPORT |
| E8 | Every enum's `@0` is a neutral sentinel | REPORT |
| E9 | No platform, vendor or POSIX noun in a required position | ENFORCED |
| E10 | No bulk payload outside `T.DataHandle` | REPORT |
| E11 | Authority is the reference — no per-method token, no authority-as-string | REPORT |
| E12 | One canonical home per type name | REPORT |
| E13 | Method ordinals sequential and declared in order | ENFORCED |
| E14 | Every interface reachable; no declared type unreferenced | ENFORCED |
| E15 | Agent tool authority is per-tool, explicit and deny-by-default | ERROR in `ai.capnp` |

---

## 3. The result on 2026-10-23

```
Schemas parsed: 89 (88 besides ai.capnp)
E1 enums in ai.capnp            : 0
E2 bulk lists in ai.capnp       : 0
E4 interfaces unreachable (all) : 0 reported
E6 hits (all schemas)           : 0
E7 hits (all schemas)           : 716
E8 hits (all schemas)           : 267
E9 hits (all schemas)           : 0
E10 hits (all schemas)          : 59
E11 hits (all schemas)          : 6
E12 hits (all schemas)          : 1
E13 hits (all schemas)          : 0
E14 hits (all schemas)          : 0

--- REPORTED (not blocking, 1049) ---
PASSED — all enforced rules clean for schema/ai.capnp
```

Exit code: **0**. Compilation: **89/89**, no warnings.

Read precisely: every rule that is enforced today is at zero tree-wide. The
1,049 residual findings are all in four rules that are measured but not yet
gating, and they are listed in the next section rather than summarised away.

---

## 4. The residual ledger

### E7 — 716 structs without an open extension point

A struct with no `T.StringMap` field, no `custom` arm and no `unknown` arm cannot
be extended by a future backend without a schema edit. That is a genuine
timelessness risk for *data structs*.

It is not a risk for pure *value structs* — a `Vec2`, a `Rect`, a `Range` — where
there is nothing future-proof to add and a string map would be noise. The rule
is written to measure all structs, so the number is large and the work is
triage, not blanket remediation.

By file, the largest concentrations are `font.capnp` (35), `audio.capnp` (33),
`compositor.capnp` (31), `intent.capnp` (21), `contacts.capnp` (19),
`content.capnp` (18), `calendar.capnp` (16), `console.capnp` (16),
`capture.capnp` (15) and `display.capnp` (15).

**Path to zero:** classify each as value struct (exempt by intent — extend the
rule's allowlist, with the classification recorded in the schema header) or
data struct (add `metadata :T.StringMap`). The second category is the one that
matters; the first is bookkeeping.

### E8 — 267 enums whose `@0` is a paradigm value

An enum's `@0` is what an absent field means. If it is `trace` (`LogLevel`),
`always` (`RestartPolicy`), `usd` (`Currency`), `srgb` (`ColorSpace`) or
`terminate` (`SignalKind`), then a field that was never set silently asserts a
paradigm. In a contract, "unset" must be sayable, or absence becomes a claim.

**Path to zero:** insert a neutral `unknown @0`/`unspecified @0` and renumber, or
— while the pre-release carve-out allows it — delete the enum where an open
token would do. The tree has done this 190-odd times already in the revamp; these
are the cases that were missed.

### E10 — 59 bulk payload positions

Two shapes are flagged:

1. **A list of machine words in a field** — `audio.capnp`'s `sampleRates :
   List(UInt32)`, `audio.capnp`'s `channelPeaks : List(Float32)`, `buffer.capnp`'s
   `shape : List(UInt32)`. Some are a bounded vocabulary (supported sample rates)
   and belong inline; some are bulk (metering, tensor geometry over 4 KiB) and
   belong behind a handle. The rule cannot tell the difference, so it reports
   both.
2. **A field or parameter named like a payload but typed inline `Data`** —
   `bluetooth.capnp`'s `sendMeshMessage(data :Data)`, `auth.capnp`'s
   `AuthMfaChallenge.payload :Data`.

By file, the largest concentrations are `audio.capnp` (9), `bluetooth.capnp` (5),
`input.capnp` (5), `sensor.capnp` (5), `nfc.capnp` (4), `timezone.capnp` (4).

**Path to zero:** for each finding, move genuine bulk to `T.DataHandle`; for each
bounded vocabulary, record in the schema header why the list is bounded, and
carry the rationale into the rule's allowlist so the count falls for the right
reason.

### E11 — 6 second authority grammars

This is the most serious residual, because authority is the one model the
doctrine says cannot have a second path. All six, by name:

| Finding | Reading |
|---|---|
| `sandbox.capnp:150` `SandboxCapabilityAdmin.grant(capability :Capability)` | **Real defect.** A per-method capability token in a file whose whole point is that the sandbox reference is not the authority to arm the sandbox. |
| `sandbox.capnp:150` `SandboxCapabilityAdmin.revoke(capabilityId :T.CapabilityId)` | **Real defect.** Authority by opaque id, which is the parallel model the revamp deleted everywhere else. |
| `contacts.capnp:219` `OrganizationName.role :Text` | **False positive.** A job title. It is not an authority declaration and must not be renamed to satisfy a rule. |
| `content.capnp:341` `ContentRef.role :Text` | **False positive.** The semantic role of a content reference (primary, attachment), not permission. |
| `vcard.capnp:365` `VCardContact.role :Text` | **False positive.** RFC 6350's `ROLE` property — a job description field. |
| `vcard.capnp:507` `VCardOrganization.role :Text` | **False positive.** Same property, organisation variant. |

**Path to zero:** four are resolved by narrowing the rule to authority-typed
names in authority-bearing structs (a validator change that must be justified in
its own docstring, not silenced); `sandbox.capnp` is real and must be redesigned
so that the gated accessor is the only way in.

### E12 — 1 duplicate type name

| Finding | Reading |
|---|---|
| `ProxyConfig` declared in both `network.capnp:697` and `socket.capnp:244` | **Real defect.** Two canonical homes for one type, which is exactly the drift E12 exists to prevent. One of the two must reference the other. |

**Path to zero:** delete the socket-local definition and import network's, or
vice versa — whichever home the dependency direction allows.

---

## 5. Why the gate exits 0 with 1,049 findings

Because a gate that is red on day one is a gate nobody runs. The revamp is
explicit about the model:

- Hard errors are enforced where the doctrine is complete (`ai.capnp`, plus the
  tree-wide rules that are already at zero).
- Everything else is measured and published, so the number is visible, tracked,
  and can only fall.
- The pre-release carve-out allows deletion rather than deprecation while
  nothing external consumes the schemas, which is what makes the path to zero
  cheap.

What would be dishonest is the alternative: lowering the rule to match the tree,
or hiding the count behind "in progress". Both are refused. The count is in the
README, in this document, and in the validator's own output, and it is the same
number in all three.

---

## 6. Proposed 2026-10-26 security gate — E15

E15 mechanically rejects the old broad tool invocation shape. `ToolRegistry` exposes no generic `invoke(ToolId, ...)`; it opens a `ToolExecutor` bound to one tool. `ToolExecutor.invoke` accepts `ToolRequest`, which contains no `ToolId`. `AgentDeclaration.tools` is an explicit allowlist whose empty value means no tools, and `AgentService.spawn` receives matching `AgentToolBinding` records. `AgentDescriptor` contains no embedded capability snapshot.

This is a structural schema check, **not proof of runtime enforcement**. A conforming implementation must verify that allowlisted IDs and bindings match exactly, reject duplicate/missing/extraneous or misbound executors, never pass the global registry to agent code, and re-check revocation when an executor is invoked. Run `python3 scripts/validate.py` and `capnp compile -I schema -o- schema/*.capnp`; the pull request's CI and runtime tests must confirm these claims before merge. The historical counts above describe the 2026-10-23 tree and are not a result for the proposed branch.

## 7. What this gate does not measure

A validator is a floor, not a proof. It does not measure:

- **Whether a schema is worth having.** It cannot tell a well-designed interface
  from a bad one that satisfies every rule.
- **Whether two implementations interoperate.** Only a second implementation
  and a real call can establish that.
- **Whether a backend is honest.** `REAL`, `DEGRADED` and `Unavailable` are a
  contract between a backend and its consumers; no static check can enforce it.
- **Whether the doctrine was applied in spirit.** E9 bans a list of nouns; it
  cannot detect a new noun nobody has thought to ban. That is what review is
  for, and why every finding must be justified in the header of its own schema.

The gate's job is narrower and more defensible: **make the mechanical promises
mechanical.** Ordinals in order, one home per type, no frozen enum at `@0`, no
second grammar for permission, no bulk copied into a message. Those are
checkable, so they are checked.

---

## 8. The rule for changing the gate

Do not edit `scripts/validate.py` to silence a finding. A schema that adds a
finding must justify it in its own header, by name and reason. A rule that is
genuinely wrong — as E11's job-title false positives show — is corrected in the
rule, with the correction documented in the script, not worked around in the
data.

The gate is part of the contract. It is reviewed like one.

---

*Next: [`TIMELESSNESS.md`](TIMELESSNESS.md) for why these rules exist; [`implementer.md`](implementer.md) for how to satisfy them; `audit-revamp/INTEGRATION-REPORT.md` for the batch-by-batch evidence of the revamp.*

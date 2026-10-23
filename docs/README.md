# Documentation

Smart Protocol is one contract with several audiences. Each document below has
one job; none of them is a summary of another. Start with the path that matches
why you are here.

---

## Reading paths

### "What is this, and why should I care?" — 15 minutes

1. [`../README.md`](../README.md) — the front door.
2. [`VISION.md`](VISION.md) — what the world looks like if this succeeds, and
   what is built versus ambition.
3. [`MANIFESTO.md`](MANIFESTO.md) — the argument for why contracts win, and the
   seven refusals that define this one.

### "I want to build against it." — one afternoon

1. [`ARCHITECTURE.md`](ARCHITECTURE.md) — boot to a running service plane.
2. `schema/types.capnp`, `schema/capability.capnp`, then your domain schema.
3. [`implementer.md`](implementer.md) — the five-step build path, the honesty
   model, per-language notes.
4. [`../BINDING_CONVENTIONS.md`](../BINDING_CONVENTIONS.md) — if you are writing
   the language binding rather than the service.
5. [`VERIFICATION.md`](VERIFICATION.md) — what the gate will check.

### "I want to understand the design rules." — the deep path

1. [`../DESIGN_PRINCIPLES.md`](../DESIGN_PRINCIPLES.md) — the constitution:
   Agnostic Test, Opacity Principle, anti-patterns, schema template, Swap Test.
2. [`TIMELESSNESS.md`](TIMELESSNESS.md) — why the constraints are shaped the way
   they are, with the revamp's evidence.
3. [`SCHEMAS.md`](SCHEMAS.md) — every file in the tree, by domain.
4. `audit-revamp/INTEGRATION-REPORT.md` — the 2026-10-10 rewrite, batch by batch.

### "I want to contribute." — read first

1. [`CONTRIBUTING.md`](CONTRIBUTING.md) — the proposal workflow and the five
   questions every change answers.
2. [`../DESIGN_PRINCIPLES.md`](../DESIGN_PRINCIPLES.md) §1, §4, §5.
3. [`VERIFICATION.md`](VERIFICATION.md) §7 — the rule for changing the gate.

---

## The documents

| Document | Its job |
|---|---|
| [`../README.md`](../README.md) | The front door: what this is, what it replaces, how to check it |
| [`VISION.md`](VISION.md) | The endgame, stated plainly, with what is built and what is ambition |
| [`MANIFESTO.md`](MANIFESTO.md) | The argument: why contracts outlive products, and the refusals that make this one durable |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | How a system is assembled: handoff, kernel, init, service plane, domains |
| [`TIMELESSNESS.md`](TIMELESSNESS.md) | The long argument for the negative constraints, and what the tree gave up for them |
| [`SCHEMAS.md`](SCHEMAS.md) | The catalog: 89 files, counted, grouped by job |
| [`VERIFICATION.md`](VERIFICATION.md) | What the gate checks, what it currently reports, and every residual by name |
| [`implementer.md`](implementer.md) | How to build a conforming backend |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to propose a schema change |
| [`GLOSSARY.md`](GLOSSARY.md) | The vocabulary, defined once |
| [`FAQ.md`](FAQ.md) | The objections, answered directly |
| [`../DESIGN_PRINCIPLES.md`](../DESIGN_PRINCIPLES.md) | The governing design rules and the E1–E14 rule table |
| [`../BINDING_CONVENTIONS.md`](../BINDING_CONVENTIONS.md) | What a language binding must get right |
| `../audit-revamp/` | The evidence: five batch reports, verification records, integration report |

---

## The three things to know first

1. **The contract is the design; implementations are disposable.** Every rule
   in these documents follows from that sentence.
2. **Authority is the reference you hold**, gated once at acquisition. There is
   no second permission model anywhere in the tree.
3. **Every number is counted and every residual is published.** If a document
   and a command disagree, the command wins:
   `python3 scripts/docstats.py` and `python3 scripts/validate.py`.

---

## Conventions used here

- **Schema** — a `.capnp` file in `schema/`. **Interface** — a Cap'n Proto
  `interface`, i.e. a capability. **Service** — a running implementation of one
  or more interfaces.
- **Gated** — reached through an accessor that takes a `Capability` and returns
  a service. **Ungated** — callable without acquiring authority.
- **REPORT / ERROR** — the validator's severity levels. Only ERROR fails the
  gate.
- Counts are current as of the commands printed beside them and are regenerated,
  not remembered.

# Contributing

This repository is the contract. A change here changes every implementation of
every component that will ever be written against it, including ones that do not
exist yet. That is a high bar, and it is applied deliberately.

Implementation code does not live here. A pull request that adds a service, a
driver or a runtime belongs in that component's repository; a pull request that
changes what components may exchange belongs here.

---

## Before you propose a schema change

Answer these five questions in the pull request. If any answer is "no", the
change belongs inside a component, not in the contract.

1. **Is this an external contract?** Does it describe what two components
   exchange in order to interoperate, rather than how one of them works
   internally?
2. **Can two unrelated implementations satisfy it?** If the schema only makes
   sense for one backend, it has captured that backend.
3. **Does it cross a trust boundary?** If not, it is a private detail.
4. **Will it still make sense on different hardware, in ten years?** If it names
   today's technology, it will not.
5. **Does it survive the Swap Test?** Replace the implementation of the
   component; if the contract has to change, the contract leaked.

The doctrinal detail behind each question — the Agnostic Test, the Opacity
Principle, the anti-pattern catalogue and the schema template — is in
[`../DESIGN_PRINCIPLES.md`](../DESIGN_PRINCIPLES.md).

---

## The workflow

1. **Read** `DESIGN_PRINCIPLES.md` §1 (Agnostic Test), §2 (Opacity), §4 (schema
   template) and §5 (Swap Test).
2. **Find the canonical home.** Use `grep` and E12: a type that already exists
   somewhere gets imported, not re-declared. A second home for a type is a
   defect even when both copies agree today.
3. **Edit the schema**, following the template: header first, then imports,
   then value types, then events, then interfaces.
4. **Run the gate.**
   ```bash
   bash scripts/check.sh schema/<your>.capnp
   python3 scripts/validate.py
   ```
   Exit code 0 is required. A new finding must be justified, by rule and reason,
   in the header of the schema that introduces it.
5. **Run the counter** if your change moves a number quoted in the docs:
   `python3 scripts/docstats.py`. Documentation is downstream of the artifact;
   update it in the same pull request.
6. **Open the pull request** stating which questions above you answered, and
   how.

---

## What a schema change must contain

Every schema file follows the same shape. A change is complete when all six
parts are present.

### 1. The header argument

Not a description — an argument. What boundary does this file define? Who
consumes it? What is deliberately opaque? What was deleted, and why? The header
is where a reviewer learns whether you applied the doctrine or merely satisfied
the parser.

### 2. Imports with a canonical direction

`using T = import "types.capnp";` in every file. Domain imports follow
dependency direction; a cycle is a design error, not a build error.

### 3. Opaque identifiers

Every identity is a wrapper struct over an opaque value, never a bare `UInt64`
in a public signature, and never arithmetic.

### 4. Open vocabularies instead of enums

| You want to express | Use |
|---|---|
| A technology-specific value | `T.MimeType` or a documented open token |
| A named-but-unbounded value | `T.StringMap` |
| A payload of any size | `T.DataHandle` |
| An event kind that may grow | a union with an `unknown` arm |

An enum is acceptable only for a genuinely closed set, and its `@0` must be a
neutral sentinel (`unknown`, `none`, `unspecified`). Rule E8 measures this.

### 5. Interfaces with sequential ordinals

Methods are declared in ordinal order, starting at `@0`, with no gaps. A new
method takes the next free ordinal. An existing ordinal is never reused,
renumbered or reordered, even during the pre-release period, because downstream
code may already be generated from it.

### 6. Result unions that can fail

A method that can fail returns a union carrying `T.Error`. A method that cannot
fail may return `T.VoidResult`. A method returning an empty struct to signal
failure is a defect.

---

## Rules that are never negotiable

These are the contract's promises to everyone who builds on it. A pull request
that breaks one is rejected regardless of how useful it seems.

- **No platform, vendor or POSIX noun in a required position.** E9.
- **No bulk payload outside `T.DataHandle`.** E10.
- **No second authority grammar.** No role strings, ACLs, per-method tokens,
  permission enums or free-text authority fields. E11.
- **No second home for a type.** E12.
- **No union without an `unknown`/`custom` arm.** E6.
- **No fabricated value.** `Unavailable` with a reason beats a plausible default.
- **No editing `validate.py` to silence a finding.** Fix the schema, or fix the
  rule with a documented justification in the script itself.

---

## Changing the gate

The validator is part of the contract, so it is reviewed like one.

A change to `scripts/validate.py` must:

1. state, in the docstring, what the rule now measures and why the previous
   definition was wrong;
2. show the finding count before and after, tree-wide;
3. not reduce a count by narrowing a rule in a way that lets a real defect pass.

The E11 job-title false positives in `contacts`, `content` and `vcard`
(`role :Text` meaning a job title, not permission) are the model for a legitimate
rule correction: the rule was too broad, the data was right, and the fix
belongs in the rule with the reasoning recorded.

---

## Changing the documentation

Documentation is part of the deliverable, not commentary on it.

- **Numbers are counted, never remembered.** Use `scripts/docstats.py` and
  `scripts/validate.py`; if a document quotes a figure, the command that
  produced it belongs nearby.
- **Claims are checkable or labelled.** If something is ambition, say so in the
  sentence. If it is a residual, list it. The credibility rule applies to prose
  exactly as it applies to schemas.
- **Each document has one job.** The front door introduces, the vision argues
  consequence, the architecture explains assembly, the catalog enumerates, the
  doctrines justify constraints. Do not restate another document; link to it.

---

## Review criteria

A reviewer asks, in order:

1. Does it pass the gate?
2. Does the header argue for the change, or merely describe it?
3. Is anything named that will not exist in ten years?
4. Is there a second home, a second authority path, or a second way to carry
   the same data?
5. Does an existing interface already answer this? (Most proposals do.)
6. If it were deleted tomorrow, would anyone notice? If not, delete it now —
   that is the pre-release carve-out's whole purpose.

---

*Next: [`implementer.md`](implementer.md) to build against the contract; [`VERIFICATION.md`](VERIFICATION.md) for what the gate enforces.*

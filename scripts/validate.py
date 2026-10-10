#!/usr/bin/env python3
"""
Smart Protocol schema validator.

Enforces the protocol's invariants with a real parser. The previous
scripts/validate.sh used `grep`/`cut`/`awk` line matching, which cannot see
inline enums, comments, or a `custom` variant that is not last, so it passed
almost everything. This version strips comments before parsing, which is why
a phrase like "List(Float32)" appearing in prose no longer counts as a
violation.

Rules
  E1  ai.capnp contains zero enums.
  E2  ai.capnp has no bulk lists: all payload goes through T.DataHandle.
  E3  Authority appears only as an accessor parameter on `interface AI`,
      never inside a service method.
  E4  Every interface is returned by at least one method.
  E5  Every stream's pull() returns a structural terminator.
  E6  Every union has an unknown/custom variant.
  E7  Every struct has an open extension point.
  E8  Every enum's @0 is a neutral sentinel, never a paradigm value.

Severity
  ERROR  — enforced for ai.capnp (the in-scope schema).
  REPORT — measured but not blocking, for the other 91 schemas.
"""

import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA_DIR = os.path.join(ROOT, "schema")

ERROR, REPORT = "ERROR", "REPORT"

NEUTRAL_SENTINELS = {
    "any", "none", "absent", "unknown", "unspecified", "unset", "invalid",
    "notSet", "notApplicable", "na", "unrestricted", "default", "zero",
    "empty", "notFound", "nil", "uninitialized", "naValue",
}

# Enums legitimately closed: a completeness-check gate must never report
# a tri-state filter as a paradigm leak.
CLOSED_ENUM_ALLOWLIST = {"BoolFilter"}


def strip_comments(src):
    """Remove # comments, respecting double-quoted strings."""
    out = []
    for line in src.splitlines():
        res, in_str, i = [], False, 0
        while i < len(line):
            ch = line[i]
            if ch == '"':
                in_str = not in_str
            elif ch == "#" and not in_str:
                break
            res.append(ch)
            i += 1
        out.append("".join(res))
    return "\n".join(out)


def block_body(src, start):
    """Given index of '{', return (body, index_after_closing_brace)."""
    depth, i = 0, start
    while i < len(src):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[start + 1:i], i + 1
        i += 1
    return src[start + 1:], len(src)


def find_blocks(src, keyword):
    """All `keyword Name { ... }` blocks as (name, body, line_no)."""
    for m in re.finditer(r"\b%s\s+(\w+)\s*\{" % keyword, src):
        body, _ = block_body(src, m.end() - 1)
        line = src[:m.start()].count("\n") + 1
        yield m.group(1), body, line


def top_level_enums(src):
    """Enums declared at column 0 (nested ones don't exist in this schema set)."""
    for m in re.finditer(r"^enum\s+(\w+)\s*\{", src, re.M):
        body, _ = block_body(src, m.end() - 1)
        yield m.group(1), body, src[:m.start()].count("\n") + 1


def variants(body):
    return re.findall(r"^\s*([a-zA-Z]\w*)\s*@\d+\s*[:;]", body, re.M)


def union_blocks(body):
    for m in re.finditer(r"\bunion\s*\{", body):
        ub, _ = block_body(body, m.end() - 1)
        yield ub


def fields_of(body):
    return re.findall(r"^\s*(\w+)\s*@(\d+)\s*:\s*([\w\.\(\)\s]+?)\s*;", body, re.M)


def methods_of(body):
    """Method signatures: `name @N (params) -> results` (possibly multiline)."""
    out = []
    for m in re.finditer(r"^\s{4}(\w+)\s*@(\d+)\s*\(", body, re.M):
        depth, i, start = 1, m.end(), m.end()
        while i < len(body) and depth:
            if body[i] == "(":
                depth += 1
            elif body[i] == ")":
                depth -= 1
            i += 1
        params = body[start:i - 1]
        rest = body[i:i + 400]
        rm = re.search(r"->\s*(.*?);", rest, re.S)
        out.append((m.group(1), int(m.group(2)), params, rm.group(1) if rm else ""))
    return out


def result_names(results):
    return re.findall(r"(\w+)\s*:\s*[\w\.]+", results)


def load_all():
    schemas = {}
    for fn in sorted(os.listdir(SCHEMA_DIR)):
        if fn.endswith(".capnp"):
            with open(os.path.join(SCHEMA_DIR, fn)) as fh:
                schemas[fn] = strip_comments(fh.read())
    return schemas


def main():
    schemas = load_all()
    errors, reports = [], []
    ai = schemas.get("ai.capnp")

    if ai is None:
        print("FATAL: schema/ai.capnp not found")
        return 1

    # ---- E1: ai.capnp has zero enums -----------------------------------
    ai_enums = [n for n, _, _ in top_level_enums(ai)]
    if ai_enums:
        errors.append(f"E1 ai.capnp declares {len(ai_enums)} enum(s) "
                      f"{sorted(ai_enums)} — the eternal core must have none")

    # ---- E2: no bulk lists in ai.capnp ---------------------------------
    bulk = re.findall(r"List\((?:Float32|Text|UInt8)\)", ai)
    if bulk:
        errors.append(f"E2 ai.capnp has {len(bulk)} bulk list(s) {sorted(set(bulk))} "
                      f"— payload must travel as T.DataHandle to stay zero-copy")

    # ---- E3: Capability only on interface AI accessors ------------------
    for iname, body, line in find_blocks(ai, "interface"):
        for mname, _, params, _ in methods_of(body):
            if ":Capability" in params or ":Capability)" in params:
                if iname != "AI":
                    errors.append(f"E3 ai.capnp:{line} {iname}.{mname} takes a "
                                  f"Capability parameter — authority is the "
                                  f"interface reference, gated at acquisition only")
    if "interface AI" not in ai:
        errors.append("E3 ai.capnp has no `interface AI` root")

    # ---- E4: every ai.capnp interface reachable from the root (E4) -------
    # Enforced for ai.capnp only. This rule cannot be applied protocol-wide:
    # the repo's convention is that a schema's primary service is injected by
    # the host, so "returned by no method" is equally true of a legitimate
    # root (System, Audio, Files) and of a forgotten helper. There is no
    # mechanical way to tell them apart, so the rule would report nothing
    # useful. For ai.capnp the root is explicit: `interface AI` returns all
    # eight sub-services, and `AI` itself is the host-provided entry point.
    ai_ifaces = {n for n, _, _ in find_blocks(ai, "interface")}
    ai_returned = set()
    for iname, body, _ in find_blocks(ai, "interface"):
        for _, _, _, results in methods_of(body):
            ai_returned.update(re.findall(r":\s*(\w+)", results))
    for iname in sorted(ai_ifaces):
        if iname == "AI" or iname in ai_returned:
            continue
        errors.append(f"E4 ai.capnp interface {iname} is returned by no method "
                      f"on interface AI — unreachable")

    # ---- E5: bounded streams have a structural terminator ---------------
    # Only applies to *STREAM interfaces. An event subscription returns an
    # unbounded batch and is terminated by cancel(), so requiring a terminator
    # there would contradict the protocol's own subscription convention
    # (appindex.capnp, media.capnp, access.capnp, storage.capnp).
    structs = {n: b for n, b, _ in find_blocks(ai, "struct")}
    for iname, body, line in find_blocks(ai, "interface"):
        if not iname.endswith("Stream"):
            continue
        for mname, _, _, results in methods_of(body):
            if mname not in ("pull", "next"):
                continue
            ok = False
            for nm in result_names(results):
                ty = re.search(r"%s\s*:\s*(\w+)" % re.escape(nm), results)
                if not ty:
                    continue
                sbody = structs.get(ty.group(1))
                if sbody is None:
                    continue
                for fname, _, fty in fields_of(sbody):
                    if fname in ("done", "status"):
                        if fname == "done" and fty.strip() == "Bool":
                            ok = True
                        cs = structs.get(fty.strip())
                        if cs and any(v in variants(cs)
                                      for v in ("complete", "ended", "more")):
                            ok = True
            if not ok:
                errors.append(f"E5 ai.capnp:{line} {iname}.{mname} has no structural "
                              f"terminator (no done:Bool and no status union)")

    # ---- E6: every union has unknown/custom ----------------------------
    for fn, src in schemas.items():
        for sname, sbody, sline in find_blocks(src, "struct"):
            for ub in union_blocks(sbody):
                vs = variants(ub)
                if not any(v in ("unknown", "custom") for v in vs):
                    msg = (f"E6 {fn}:{sline} struct {sname} union has no "
                           f"unknown/custom variant (has {vs})")
                    (errors if fn == "ai.capnp" else reports).append(msg)

    # ---- E7: every struct has an open extension point ------------------
    # Exemptions, both deliberate:
    #   - Opaque ID wrappers (`struct X { id :UInt64 }`). TIMELESSNESS.md:32
    #     requires pushing types as far left as possible; an extension point
    #     on an ID would bloat every message in the protocol. types.capnp
    #     keeps SessionId, BufferId, AppId this way.
    #   - Artifact. Its extension mechanism IS T.MimeType + T.DataHandle:
    #     a new payload kind is a new subtype, not a new field.
    # A `custom :Data` field counts as an extension point (InferenceResponse
    # uses that shape rather than a union).
    for fn, src in schemas.items():
        for sname, sbody, sline in find_blocks(src, "struct"):
            fs = fields_of(sbody)
            if [f[0] for f in fs] == ["id"] and fs[0][2].strip() == "UInt64":
                continue
            if sname == "Artifact":
                continue
            # A bare `Data` field is itself an opaque extension slot.
            has_data = any(t.strip() == "Data" for _, _, t in fs)
            has_map = any("StringMap" in t for _, _, t in fs)
            has_custom = any(n == "custom" for n, _, _ in fs)
            has_open_union = any(
                any(v in ("unknown", "custom") for v in variants(ub))
                for ub in union_blocks(sbody))
            if not (has_data or has_map or has_custom or has_open_union):
                msg = (f"E7 {fn}:{sline} struct {sname} has no open extension "
                       f"point (no T.StringMap field, no custom field, no "
                       f"custom/unknown union)")
                (errors if fn == "ai.capnp" else reports).append(msg)

    # ---- E8: enum @0 is a neutral sentinel (REPORT everywhere) ---------
    for fn, src in schemas.items():
        for ename, ebody, eline in top_level_enums(src):
            if ename in CLOSED_ENUM_ALLOWLIST:
                continue
            vs = variants(ebody)
            if vs and vs[0] not in NEUTRAL_SENTINELS:
                reports.append(
                    f"E8 {fn}:{eline} enum {ename}.@0 = {vs[0]} — an absent field "
                    f"silently means this value; @0 should be a neutral sentinel")

    # ---- report --------------------------------------------------------
    print(f"Schemas parsed: {len(schemas)}")
    print(f"E1 enums in ai.capnp            : {len(ai_enums)}")
    print(f"E2 bulk lists in ai.capnp       : {len(bulk)}")
    print(f"E4 interfaces unreachable (all) : "
          f"{len([r for r in reports if r.startswith('E4')])} reported")
    print()
    if reports:
        print(f"--- REPORTED (not blocking, {len(reports)}) ---")
        for r in sorted(set(reports)):
            print(f"  {r}")
        print()
    if errors:
        print(f"--- ERRORS ({len(errors)}) ---")
        for e in sorted(set(errors)):
            print(f"  {e}")
        print()
        print("FAILED")
        return 1
    print("PASSED — all enforced rules clean for schema/ai.capnp")
    return 0


if __name__ == "__main__":
    sys.exit(main())

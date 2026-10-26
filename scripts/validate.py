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
  E9  No platform/vendor noun in a required position (R5).
  E10 No bulk payload outside T.DataHandle (R2).
  E11 Authority is the reference: no per-method Capability token, no
      authority-by-string (R3).
  E12 No type name declared in two schemas (R6).
  E13 Interface method ordinals are sequential and declared in order.
  E14 Every interface is reachable; no declared type is unreferenced (R8).
  E15 Agent tool authority is per-tool, explicit, and deny-by-default.

Severity
  ERROR  — enforced for ai.capnp (the in-scope schema).
  REPORT — measured but not blocking, for every other schema in the tree.

E9–E14 are the tree-wide gate for the revamp wave. They are REPORT for the
non-ai schemas so that the tree stays green while other waves land; the
intent is that every schema reaches zero in each of them.

Every count this script prints is computed from the tree it just parsed —
there is no hardcoded schema total anywhere in it, so the numbers in the
report and in the docs cannot drift from `ls schema/`.
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

# ── E9: platform, vendor and POSIX nouns banned from required positions ──
# Matched against enum variant names, struct field names, type names and
# method names. Exact match (case-insensitive) or prefix match for compound
# spellings (`hhdmOffset`, `uartConfig`, `acpiTables`, `grpcMetadata`).
PLATFORM_NOUNS = {
    "zombie", "defunct", "grub", "grub2", "limine", "syslinux", "systemd",
    "journald", "syslog", "stdout", "stderr", "kmsg", "dmesg", "inode",
    "cgroup", "cr3", "hhdm", "nvme", "ahci", "iscsi", "pxe", "ipxe", "tftp",
    "dhcp", "smbios", "dmi", "uart", "acpi", "posix", "win32", "linux",
    "x86", "x8664", "amd64", "i386", "i686", "arm64", "aarch64", "riscv",
    "s390x", "pulseaudio", "alsa", "pipewire", "jack", "consul", "etcd",
    "zookeeper", "kubernetes", "docker", "rabbitmq", "kafka", "grpc",
    "prometheus", "opentelemetry", "ebpf", "dtrace", "seccomp", "landlock",
    "rlimit", "cygwin", "machport",
}
# Compound spellings only match as a prefix, never as an arbitrary substring,
# so `dmiStatus` is caught while `admin` is not.
PLATFORM_PREFIX_NOUNS = {
    "hhdm", "cgroup", "uart", "acpi", "smbios", "stdout", "stderr", "syslog",
    "journald", "inode", "grpc", "nvme", "ahci", "iscsi", "pxe", "ipxe",
    "tftp", "dhcp", "posix", "x86", "grub", "limine", "systemd",
    "pulseaudio", "alsa", "consul", "etcd", "zookeeper", "kubernetes",
    "docker", "rabbitmq", "kafka", "prometheus", "opentelemetry", "ebpf",
    "dtrace", "seccomp", "landlock", "rlimit", "zombie", "defunct",
}

# ── E10: bulk payloads ────────────────────────────────────────────────
# A list of machine words in a FIELD is a copied payload, not a bounded
# vocabulary: it belongs behind T.DataHandle.
BULK_LIST_TYPES = {
    "Float32", "Float64", "UInt8", "UInt16", "UInt32", "UInt64",
    "Int8", "Int16", "Int32", "Int64", "Bool",
}
# A field with one of these names typed inline `Data` is a payload position
# (as opposed to an opaque id/proof/hash/digest/signature, which is correctly
# inline). Names carry bytes of bulk; ids and proofs carry identity.
PAYLOAD_FIELD_NAMES = {
    "data", "content", "payload", "frames", "manifestbytes", "blob",
    "image", "dump", "rawbytes", "sample", "samples",
}

# ── E11: authority ────────────────────────────────────────────────────
# Fields named like an authority declaration but typed as free text or a
# flag are the parallel-permission-model anti-pattern (DESIGN_PRINCIPLES §399).
AUTHORITY_FIELD_NAMES = {
    "capabilities", "requiredcaps", "requiredcapabilities", "permission",
    "permissions", "roles", "role", "acl", "authority", "accesspolicy",
    "allowedroles", "readrole", "writterole", "writerole", "droppedcapabilities",
    "keptcapabilities", "permissioncapability",
}
AUTHORITY_VALUE_TYPES = {"Text", "Bool", "UInt8", "UInt32", "UInt64"}

# Files where a `Capability` parameter is the OBJECT UNDER MANIPULATION,
# not an authority token: capability.capnp's attenuate/transfer/revoke/
# revokeControlled/evaluateCondition act on the capability named by the
# parameter. Everywhere else a Capability parameter is legal ONLY on a
# root accessor that returns a service (the ai.capnp precedent).
CAPABILITY_OBJECT_HOME = {"capability.capnp"}

# (struct, field) pairs where a name collides with the authority vocabulary
# but the field is something else entirely: `Uri.authority` is the authority
# COMPONENT of a URI (user@host:port), not an authority declaration.
AUTHORITY_FALSE_POSITIVES = {("Uri", "authority")}

# Unions whose non-success arm is the extension point.
TERMINAL_UNIONS = {"VoidResult", "BoolResult", "DataHandle"}

# ── The declared R2 exception: ONE inline payload in the protocol ──────
#
# `T.UnknownEvent.payload` is inline `Data` and the validator must never
# report it, because it is not a defect — it is the protocol's single
# sanctioned escape hatch (see the reasoning written into the struct's own
# header in types.capnp). The exemption is deliberately narrow: it applies
# ONLY to the canonical `UnknownEvent` declared in types.capnp, so a second
# schema cannot inherit the exemption by re-declaring a struct of the same
# name (which is exactly the drift R6 exists to stop).
R2_ESCAPE_HATCH = ("types.capnp", "UnknownEvent")

# Unions whose non-success arm is `T.Error` are the RESPECTED error model
# (DESIGN_PRINCIPLES "How to Handle Errors": `union { buffer; error :T.Error }`).
# `T.Error` already carries a code, a message, a context and a retryable flag,
# so it is the extension point a further `unknown` arm would pretend to add.
# Exempting by SHAPE rather than by a hand-maintained name list is what keeps
# the exemption honest: a result union that gains a third arm still reports.
ERROR_ARM_TYPES = {"T.Error", "Error"}


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


# A declaration head tolerates an `extends` clause:
#   interface X { ... }
#   interface X extends(Y) { ... }
#   interface X extends Y { ... }
# Without the optional clause the parser stops matching at `extends`, so an
# inherited interface is silently invisible to E11/E13/E14 and produces
# false reachability findings for the interface that returns it.
_HEAD = r"\b%s\s+(\w+)\s*(?:extends\s*\(?\s*[\w\.\s,]*\)?\s*)?\{"
_HEAD_LINE = r"^%s\s+(\w+)\s*(?:extends\s*\(?\s*[\w\.\s,]*\)?\s*)?\{"


def find_blocks(src, keyword):
    """All `keyword Name { ... }` blocks as (name, body, line_no)."""
    for m in re.finditer(_HEAD % keyword, src):
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


def union_arms(body):
    """A union's arms as (name, type): `name @N :Type;` or `name @N;`.

    The type is matched permissively (`List(X)`, `T.Y`, `Void`) because an
    arm's type is what the E6 shape test reads; a strict pattern silently
    dropped `pages @1 :List(UInt16)` and under-reported the union's arms.
    """
    out = []
    for m in re.finditer(r"^\s*([a-zA-Z]\w*)\s*@(\d+)\s*(?::\s*(.+?)\s*)?;",
                         body, re.M):
        out.append((m.group(1), (m.group(3) or "").strip()))
    return out


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


def interface_types_of(results):
    """Interface-typed results (an accessor returning a service)."""
    return set(re.findall(r":\s*([A-Z]\w*)", results))


def is_platform_noun(name):
    low = name.lower()
    if low in PLATFORM_NOUNS:
        return True
    return any(low.startswith(p) for p in PLATFORM_PREFIX_NOUNS)


def params_of(signature):
    """`(a :Text, b :List(Text))` -> [(name, type), ...] honoring nesting."""
    out, depth, cur, i = [], 0, "", 0
    while i < len(signature):
        ch = signature[i]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
        i += 1
    if cur.strip():
        out.append(cur)
    parsed = []
    for part in out:
        m = re.match(r"\s*(\w+)\s*:\s*(.+?)\s*$", part, re.S)
        if m:
            parsed.append((m.group(1), m.group(2).strip()))
    return parsed


def declared_interfaces(src):
    """[(name, body, line)] in declaration order."""
    return list(find_blocks(src, "interface"))


# Structs that are values rather than specifications: even though they are
# structs, a backend has nothing to extend in them.
VALUE_STRUCTS = {"Timestamp", "Duration", "MonotonicTimestamp", "Version"}

SCALAR_TYPES = re.compile(
    r"(UInt|Int)(8|16|32|64)|Float(32|64)|Bool")


def compute_value_like_structs(schemas):
    """Types whose every field is a scalar, enum, id wrapper or another
    value struct — i.e. complete by construction. Transitive, memoised."""
    bodies = {}
    enums = set()
    for src in schemas.values():
        for kind, name, line in top_level_types(src):
            if kind == "enum":
                enums.add(name)
                continue
            if kind != "struct" or name in bodies:
                continue
            for m in re.finditer(r"^struct\s+%s\s*\{" % re.escape(name), src,
                                 re.M):
                bodies[name] = block_body(src, m.end() - 1)[0]
                break
    memo = {}

    def scalar(t, seen):
        t = t.strip()
        if SCALAR_TYPES.fullmatch(t):
            return True
        inner = re.fullmatch(r"List\((.+)\)", t)
        if inner:
            return scalar(inner.group(1), seen)
        name = t.split(".")[-1]
        if name in enums or name in VALUE_STRUCTS:
            return True
        if name in memo:
            return memo[name]
        if name not in bodies or name in seen:
            return False
        seen.add(name)
        fs = fields_of(bodies[name])
        ok = bool(fs) and all(scalar(ft, seen) for _, _, ft in fs)
        memo[name] = ok
        return ok

    for name in bodies:
        scalar(name, set())
    return memo


def top_level_types(src):
    """Every `struct|enum|interface Name {` at top level, in order."""
    out = []
    for kw in ("struct", "enum", "interface"):
        for m in re.finditer(_HEAD_LINE % kw, src, re.M):
            out.append((kw, m.group(1), src[:m.start()].count("\n") + 1))
    out.sort(key=lambda t: t[2])
    return out


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

    # ---- E15: explicit scoped agent-tool authority ----------------------
    # Structural gate only: runtime behavior still needs review and tests.
    # A spawned agent must receive per-tool capabilities, not a global registry.
    ai_structs = {n: b for n, b, _ in find_blocks(ai, "struct")}
    ai_ifaces = {n: b for n, b, _ in find_blocks(ai, "interface")}
    decl_fields = fields_of(ai_structs.get("AgentDeclaration", ""))
    descriptor_fields = fields_of(ai_structs.get("AgentDescriptor", ""))
    binding_fields = fields_of(ai_structs.get("AgentToolBinding", ""))
    request_fields = fields_of(ai_structs.get("ToolRequest", ""))
    registry_methods = methods_of(ai_ifaces.get("ToolRegistry", ""))
    executor_methods = methods_of(ai_ifaces.get("ToolExecutor", ""))
    agent_methods = methods_of(ai_ifaces.get("AgentService", ""))
    declaration_tools = any(n == "tools" and t.replace(" ", "") == "List(ToolId)"
                            for n, _, t in decl_fields)
    descriptor_exports_authority = any(
        n.lower() in ("grantedauthority", "grantedcapabilities")
        or "Capability" in t
        for n, _, t in descriptor_fields)
    binding_executor = any(n == "executor" and t.strip() == "ToolExecutor"
                           for n, _, t in binding_fields)
    request_has_tool_id = any(t.strip().split(".")[-1] == "ToolId"
                              for _, _, t in request_fields)
    registry_open = any(
        name == "open" and ordinal == 4 and "ToolExecutor" in results
        for name, ordinal, _, results in registry_methods)
    registry_has_unscoped_invoke = any(
        name == "invoke" for name, _, _, _ in registry_methods)
    executor_describe = any(
        name == "describe" and ordinal == 0 and "ToolId" in results
        for name, ordinal, _, results in executor_methods)
    executor_invoke = any(
        name == "invoke" and ordinal == 1 and "ToolRequest" in params
        and not request_has_tool_id
        for name, ordinal, params, _ in executor_methods)
    spawn_scoped = any(
        name == "spawn" and "AgentDeclaration" in params
        and "AgentToolBinding" in params
        for name, _, params, _ in agent_methods)
    if not (declaration_tools and not descriptor_exports_authority
            and binding_executor and registry_open and not registry_has_unscoped_invoke
            and executor_describe and executor_invoke and spawn_scoped):
        errors.append(
            "E15 ai.capnp lacks scoped agent tool authority: require "
            "AgentDeclaration.tools, an AgentDescriptor with no embedded authority, "
            "AgentToolBinding.executor, ToolRegistry.open returning ToolExecutor, "
            "no ToolRegistry.invoke(ToolId, ...), "
            "ToolExecutor.invoke(ToolRequest without ToolId), and "
            "AgentService.spawn(toolBindings)")

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
    # `TERMINAL_UNIONS` are the three whose non-success arm IS the extension
    # point, so a further `unknown` arm would be noise: `VoidResult` and
    # `BoolResult` carry `T.Error` (the open error model), and `DataHandle`
    # is closed by construction (inline bytes or a buffer reference — there
    # is no third possibility to extend towards). Everything else,
    # especially event unions, must terminate with `unknown @N :T.UnknownEvent`
    # or `custom`.
    #
    # Widened by SHAPE (batch B's finding): any union with a `T.Error` arm is
    # the error model DESIGN_PRINCIPLES blesses, so requiring an extra
    # `unknown` arm on `{ ok; error }` reports a correct contract as a
    # defect. The widening is a shape test, not a name list, so it cannot go
    # stale: a result union that gains an unrelated third arm still reports
    # if it has neither `T.Error` nor `unknown`.
    for fn, src in schemas.items():
        for sname, sbody, sline in find_blocks(src, "struct"):
            for ub in union_blocks(sbody):
                arms = union_arms(ub)
                vs = [a for a, _ in arms]
                if any(v in ("unknown", "custom") for v in vs):
                    continue
                if sname in TERMINAL_UNIONS:
                    continue
                if any(t in ERROR_ARM_TYPES for _, t in arms):
                    continue
                msg = (f"E6 {fn}:{sline} struct {sname} union has no "
                       f"unknown/custom variant (has {vs})")
                (errors if fn == "ai.capnp" else reports).append(msg)

    # ---- E7: every struct has an open extension point ------------------
    # Scoped, deliberately. A struct whose every field is a scalar, an id
    # wrapper, an enum or another value struct is COMPLETE BY CONSTRUCTION:
    # `AckHandle { messageId, queueId, sequence, expiresAt }` has nothing a
    # backend could add, and Cap'n Proto already ignores unknown fields in
    # old readers. Forcing a T.StringMap onto every value struct would
    # bloat the protocol for no gain — the same over-breadth the verifier
    # rejected for E8 (see audit-verification.md O4).
    #
    # So the rule bites where extension is real: structs that DESCRIBE,
    # SPECIFY or REQUEST something (any Text, List, Data, map or nested
    # spec field). Those must carry an extension point.
    #
    # Exemptions, both deliberate:
    #   - Opaque ID wrappers (`struct X { id :UInt64 }`). TIMELESSNESS.md:32
    #     requires pushing types as far left as possible; an extension point
    #     on an ID would bloat every message in the protocol. types.capnp
    #     keeps SessionId, BufferId, AppId this way.
    #   - Artifact. Its extension mechanism IS T.MimeType + T.DataHandle:
    #     a new payload kind is a new subtype, not a new field.
    # A `custom :Data` field counts as an extension point (InferenceResponse
    # uses that shape rather than a union).
    value_like = compute_value_like_structs(schemas)
    for fn, src in schemas.items():
        for sname, sbody, sline in find_blocks(src, "struct"):
            fs = fields_of(sbody)
            if [f[0] for f in fs] == ["id"] and fs[0][2].strip() == "UInt64":
                continue
            if sname == "Artifact":
                continue
            if value_like.get(sname):
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

    # ---- E9: platform / vendor nouns in required positions -------------
    for fn, src in schemas.items():
        for kind, tname, tline in top_level_types(src):
            if is_platform_noun(tname):
                reports.append(
                    f"E9 {fn}:{tline} {kind} {tname} names a platform, vendor "
                    f"or POSIX concept in a required position")
        for ename, ebody, eline in top_level_enums(src):
            for v in variants(ebody):
                if is_platform_noun(v):
                    reports.append(
                        f"E9 {fn}:{eline} enum {ename}.{v} is a platform, vendor "
                        f"or POSIX noun frozen into an eternal contract")
        for sname, sbody, sline in find_blocks(src, "struct"):
            for fname, _, ftype in fields_of(sbody):
                if is_platform_noun(fname):
                    reports.append(
                        f"E9 {fn}:{sline} struct {sname}.{fname} is a platform, "
                        f"vendor or POSIX noun in a required position")
        for iname, ibody, iline in find_blocks(src, "interface"):
            for mname, _, _, _ in methods_of(ibody):
                if is_platform_noun(mname):
                    reports.append(
                        f"E9 {fn}:{iline} {iname}.{mname} names a platform, "
                        f"vendor or POSIX mechanism")

    # ---- E10: bulk payloads outside T.DataHandle -----------------------
    # Exempt: a list of ID WRAPPERS (`List(T.ServiceId)`, `List(SchemaId)`)
    # is a set of references, not a copied payload; and the one declared R2
    # escape hatch, whose opaque payload is the point (see R2_ESCAPE_HATCH).
    def is_id_list(ftype):
        inner = re.fullmatch(r"List\((.+)\)", ftype)
        if not inner:
            return False
        return inner.group(1).strip().split(".")[-1].endswith("Id")

    for fn, src in schemas.items():
        for sname, sbody, sline in find_blocks(src, "struct"):
            for fname, _, ftype in fields_of(sbody):
                ftype = ftype.strip()
                if re.fullmatch(r"List\((%s)\)" % "|".join(BULK_LIST_TYPES),
                                ftype) and not is_id_list(ftype):
                    reports.append(
                        f"E10 {fn}:{sline} {sname}.{fname} :{ftype} — a list of "
                        f"machine words is a copied payload; bulk belongs in "
                        f"T.DataHandle")
                if ftype == "Data" and fname.lower() in PAYLOAD_FIELD_NAMES \
                        and (fn, sname) != R2_ESCAPE_HATCH:
                    reports.append(
                        f"E10 {fn}:{sline} {sname}.{fname} :Data — a payload "
                        f"position must be T.DataHandle (zero-cost reference)")
        for iname, ibody, iline in find_blocks(src, "interface"):
            for mname, _, params, _ in methods_of(ibody):
                for pname, ptype in params_of(params):
                    if ptype == "Data" and pname.lower() in PAYLOAD_FIELD_NAMES:
                        reports.append(
                            f"E10 {fn}:{iline} {iname}.{mname}({pname} :Data) — "
                            f"a payload parameter must be T.DataHandle")

    # ---- E11: authority is the reference -------------------------------
    for fn, src in schemas.items():
        for sname, sbody, sline in find_blocks(src, "struct"):
            for fname, _, ftype in fields_of(sbody):
                if (sname, fname) in AUTHORITY_FALSE_POSITIVES:
                    continue
                if (fname.lower() in AUTHORITY_FIELD_NAMES
                        and ftype.strip() in AUTHORITY_VALUE_TYPES):
                    reports.append(
                        f"E11 {fn}:{sline} struct {sname}.{fname} :"
                        f"{ftype.strip()} — an authority declaration as free "
                        f"text/flag; use a Capability reference")
        for iname, ibody, iline in find_blocks(src, "interface"):
            ifaces = {n for n, _, _ in find_blocks(src, "interface")}
            for mname, _, params, results in methods_of(ibody):
                for pname, ptype in params_of(params):
                    if "Capability" not in ptype:
                        continue
                    if fn in CAPABILITY_OBJECT_HOME:
                        continue
                    # An accessor that returns a service is the ai.capnp
                    # precedent: the reference is the authority.
                    if interface_types_of(results) & ifaces:
                        continue
                    reports.append(
                        f"E11 {fn}:{iline} {iname}.{mname}({pname} :{ptype}) — "
                        f"authority must be the interface reference granted at "
                        f"acquisition, not a per-method token")

    # ---- E12: one canonical home per type name -------------------------
    where = defaultdict(list)
    for fn, src in schemas.items():
        for kind, tname, tline in top_level_types(src):
            where[tname].append((fn, tline))
    for tname, spots in sorted(where.items()):
        if len(spots) > 1:
            files = ", ".join(f"{f}:{l}" for f, l in spots)
            reports.append(
                f"E12 type {tname} is declared in {len(spots)} schemas "
                f"({files}) — one canonical home per type")

    # ---- E13: ordinal sequencing ---------------------------------------
    for fn, src in schemas.items():
        for iname, ibody, iline in find_blocks(src, "interface"):
            ms = methods_of(ibody)
            ords = [o for _, o, _, _ in ms]
            if ords != sorted(ords):
                reports.append(
                    f"E13 {fn}:{iline} {iname} methods are not declared in "
                    f"ascending ordinal order ({ords})")
            if ords and (ords[0] != 0 or ords != list(range(len(ords)))):
                reports.append(
                    f"E13 {fn}:{iline} {iname} method ordinals are not "
                    f"sequential from 0 ({ords})")
        for sname, sbody, sline in find_blocks(src, "struct"):
            fs = fields_of(sbody)
            for (n1, o1, _), (n2, o2, _) in zip(fs, fs[1:]):
                if int(o2) <= int(o1):
                    reports.append(
                        f"E13 {fn}:{sline} struct {sname} fields are not in "
                        f"ascending ordinal order ({n1}@{o1} then {n2}@{o2})")

    # ---- E14: reachability ---------------------------------------------
    # The first interface declared in a file is that schema's root: like
    # ai.capnp's `AI` (and System, Audio, Files), it is handed to the caller
    # by the host, so "returned by no method" is the correct shape for it.
    # The second signal is the FILE'S OWN NAME: `hal.capnp` -> HalService,
    # `boot.capnp` -> BootService, `compositor.capnp` -> CompositorSession.
    # Anything prefixed with the file's stem is that schema's entry point.
    #
    # Reachability also counts an interface taken as a PARAMETER: a
    # provider-registered callback (`registerAuthMethod(handler :AuthHandler)`)
    # is reachable because the caller supplies an implementation and the peer
    # calls it. Counting only return types missed that whole shape and
    # reported three live interfaces as unreachable.
    returned = set()
    taken = set()
    for fn, src in schemas.items():
        for iname, ibody, _ in find_blocks(src, "interface"):
            for _, _, params, results in methods_of(ibody):
                returned.update(re.findall(r":\s*(\w+)", results))
                for _, ptype in params_of(params):
                    taken.update(re.findall(r"[A-Z]\w*", ptype))
    referenced = set()
    for fn, src in schemas.items():
        for _, tname, _ in top_level_types(src):
            referenced.add(tname)
        for sname, sbody, _ in find_blocks(src, "struct"):
            for _, _, ftype in fields_of(sbody):
                referenced.update(re.findall(r"\w+", ftype))
        for iname, ibody, _ in find_blocks(src, "interface"):
            for _, _, params, results in methods_of(ibody):
                referenced.update(re.findall(r"\w+", params))
                referenced.update(re.findall(r"\w+", results))
    for fn, src in schemas.items():
        declared = declared_interfaces(src)
        stem = re.sub(r"[^a-z0-9]", "", fn[:-len(".capnp")].lower())
        roots = set()
        if declared:
            roots.add(declared[0][0])
            for iname, _, _ in declared:
                # `hal.capnp` -> HalService, `boot.capnp` -> BootService,
                # `queue.capnp` -> Queue, `compositor.capnp` ->
                # CompositorSession. The file's own name is the best
                # signal of which interface is the host-injected root.
                low = re.sub(r"[^a-z0-9]", "", iname.lower())
                if low == stem or low == stem + "service" \
                        or low.startswith(stem):
                    roots.add(iname)
        for iname, _, iline in declared:
            if iname in roots or iname in returned or iname in taken:
                continue
            reports.append(
                f"E14 {fn}:{iline} interface {iname} is returned by no method "
                f"anywhere — unreachable")
        for kind, tname, tline in top_level_types(src):
            if kind == "interface":
                continue
            if tname not in referenced:
                reports.append(
                    f"E14 {fn}:{tline} {kind} {tname} is referenced by no "
                    f"field, parameter or result — unreachable")

    # ---- report --------------------------------------------------------
    other_schemas = len(schemas) - 1  # every schema except ai.capnp
    print(f"Schemas parsed: {len(schemas)} ({other_schemas} besides ai.capnp)")
    print(f"E1 enums in ai.capnp            : {len(ai_enums)}")
    print(f"E2 bulk lists in ai.capnp       : {len(bulk)}")
    print("E15 scoped agent tool authority  : " +
          ("FAILED" if any(e.startswith("E15") for e in errors) else "OK"))
    print(f"E4 interfaces unreachable (all) : "
          f"{len([r for r in reports if r.startswith('E4')])} reported")
    for tag in ("E6", "E7", "E8", "E9", "E10", "E11", "E12", "E13", "E14"):
        print(f"{tag} hits (all schemas)        : "
              f"{len([r for r in reports if r.startswith(tag)])}")
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
    print("PASSED — enforced rules clean, including scoped agent tool authority (E15)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

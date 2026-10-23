#!/usr/bin/env python3
"""
docstats — the single source of the numbers quoted in the documentation.

The rule in this repository is that no number in prose is remembered; every
one is counted from the tree at the moment it is printed. This script is the
counter. Run it before editing any document that quotes a figure:

    python3 scripts/docstats.py

It prints the structural inventory of `schema/` as plain `key: value` lines,
so a document can be updated (or diffed) mechanically. It deliberately does
not restate the validator's findings: those belong to `scripts/validate.py`,
which is the only authority on rule counts. Run both:

    python3 scripts/docstats.py
    python3 scripts/validate.py
"""

import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA_DIR = os.path.join(ROOT, "schema")


def main() -> int:
    files = sorted(glob.glob(os.path.join(SCHEMA_DIR, "*.capnp")))
    if not files:
        print("no schemas found", file=os.sys.stderr)
        return 1

    text = {f: open(f, encoding="utf-8").read() for f in files}

    def total(pattern: str, flags: int = re.MULTILINE) -> int:
        return sum(len(re.findall(pattern, body, flags)) for body in text.values())

    interfaces = total(r"^\s*interface\s+\w+")
    structs = total(r"^\s*struct\s+\w+")
    enums = total(r"^\s*enum\s+\w+")
    methods = total(r"^\s{4}\w+\s+@\d+\s*\(")

    print(f"schemas: {len(files)}")
    print(f"lines: {sum(len(body.splitlines()) for body in text.values())}")
    print(f"interfaces: {interfaces}")
    print(f"structs: {structs}")
    print(f"enums: {enums}")
    print(f"methods: {methods}")

    # The three vocabularies the timelessness rule depends on.
    datahandle = total(r"\bT\.DataHandle\b")
    stringmap = total(r"\bT\.StringMap\b")
    unknown_arms = total(r"unknown\s+@\d+\s*:\s*T\.UnknownEvent")
    gated = total(r":Capability\s*\)\s*->")
    print(f"datahandle_positions: {datahandle}")
    print(f"stringmap_positions: {stringmap}")
    print(f"unknown_event_arms: {unknown_arms}")
    print("unknown_event_schemas: %d" % sum(
        1 for body in text.values() if "T.UnknownEvent" in body))
    print(f"gated_accessors: {gated}")

    # Domains are the section headings of docs/SCHEMAS.md; the count below is
    # the number of schema files, not the number of domain headings.
    print(f"schemas_without_interfaces: {sum(1 for b in text.values() if 'interface ' not in b)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

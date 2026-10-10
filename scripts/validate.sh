#!/bin/bash
# Validate all Cap'n Proto schemas.
#
# Two stages:
#   1. Compile every schema (the compiler is the only real authority).
#   2. Run the structural validator, which enforces the protocol's
#      invariants with a real parser.
#
# The previous version of this script checked invariants with grep/cut/awk
# line matching. That cannot see inline enums, comments, or a `custom`
# variant that is not last, so it reported almost nothing. Logic now lives
# in scripts/validate.py.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA_DIR="$ROOT/schema"

echo "=============================================="
echo " Stage 1/2: compiling schemas"
echo "=============================================="
echo "Schema dir: $SCHEMA_DIR"
echo ""

if ! command -v capnp >/dev/null 2>&1; then
    echo "FATAL: capnp not found on PATH"
    exit 1
fi

COUNT=$(find "$SCHEMA_DIR" -name '*.capnp' | wc -l | tr -d ' ')
echo "Compiling $COUNT schemas..."
capnp compile -o - -I "$SCHEMA_DIR" "$SCHEMA_DIR"/*.capnp > /dev/null
echo "All $COUNT schemas compile successfully."
echo ""

echo "=============================================="
echo " Stage 2/2: structural validation"
echo "=============================================="
echo ""
python3 "$ROOT/scripts/validate.py"

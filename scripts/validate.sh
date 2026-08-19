#!/bin/bash
# Validate all Cap'n Proto schemas compile correctly

set -e

SCHEMA_DIR="$(dirname "$0")/../schema"

echo "Validating Cap'n Proto schemas..."
echo "Schema dir: $SCHEMA_DIR"

# Check all schemas compile
capnp compile -o - -I "$SCHEMA_DIR" "$SCHEMA_DIR"/*.capnp

echo "All schemas compile successfully!"

# Additional checks
echo ""
echo "Running additional validation checks..."

# Check for ordinal gaps
echo "Checking ordinal stability..."
for f in "$SCHEMA_DIR"/*.capnp; do
    echo "Checking $f..."
    capnp compile -o - -I "$SCHEMA_DIR" "$f" 2>&1 | grep -i "ordinal" || true
done

# Check for required custom variants
echo "Checking for custom variants in enums..."
for f in "$SCHEMA_DIR"/*.capnp; do
    enums=$(grep -n "^enum " "$f" | cut -d' ' -f2)
    while IFS= read -r enum; do
        if [ -n "$enum" ]; then
            # Check if last variant is custom
            last_variant=$(awk "/^enum $enum/,/^[^ ]/" "$f" | grep -E '^\s+[a-zA-Z]' | tail -1 | awk '{print $1}')
            if [ "$last_variant" != "custom" ] && [ "$last_variant" != "Custom" ]; then
                echo "WARNING: $f enum $enum may be missing custom variant (last: $last_variant)"
            fi
        fi
    done <<< "$enums"
done

# Check for unknown variant in unions
echo "Checking for unknown variants in unions..."
for f in "$SCHEMA_DIR"/*.capnp; do
    unions=$(grep -n "union {" "$f" | wc -l)
    if [ "$unions" -gt 0 ]; then
        has_unknown=$(awk '/union \{/,/\}/' "$f" | grep -E "unknown\s+@" || true)
        if [ -z "$has_unknown" ]; then
            echo "WARNING: $f has unions but may be missing unknown variant"
        fi
    fi
done

echo ""
echo "Validation complete!"
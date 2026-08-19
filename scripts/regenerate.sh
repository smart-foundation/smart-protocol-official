#!/bin/bash
# Regenerate Cap'n Proto Rust bindings for all schemas

set -e

SCHEMA_DIR="$(dirname "$0")/../schema"
OUT_DIR="$(dirname "$0")/../gen"

echo "Regenerating Cap'n Proto bindings..."
echo "Schema dir: $SCHEMA_DIR"
echo "Output dir: $OUT_DIR"

mkdir -p "$OUT_DIR"

# Clean previous generation
rm -rf "$OUT_DIR"/*.rs

# Compile all schemas
capnp compile -o rust:"$OUT_DIR" -I "$SCHEMA_DIR" "$SCHEMA_DIR"/*.capnp

echo "Generation complete. Files generated:"
ls -la "$OUT_DIR"/*.rs | wc -l
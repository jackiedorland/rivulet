#!/usr/bin/env bash
set -euo pipefail

REPO="https://codeberg.org/api/v1/repos/river/river/raw/protocol"
PROTO_DIR="$(dirname "$0")/../protocol"
OUT_DIR="$(dirname "$0")/../src/Rivulet/FFI"

PROTOCOLS=(
  river-window-management-v1
  river-xkb-bindings-v1
  river-input-management-v1
)

mkdir -p "$PROTO_DIR" "$OUT_DIR"

for proto in "${PROTOCOLS[@]}"; do
  xml="$PROTO_DIR/${proto}.xml"

  echo "Fetching ${proto}.xml..."
  curl -sSfL "${REPO}/${proto}.xml?ref=v0.4.1" -o "$xml"

  echo "Generating ${proto}..."
  wayland-scanner client-header "$xml" "${OUT_DIR}/${proto}.h"
  wayland-scanner private-code  "$xml" "${OUT_DIR}/${proto}.c"
done

echo "Done. Files written to ${OUT_DIR}/"

#!/usr/bin/env bash
set -euo pipefail

REPO="https://codeberg.org/api/v1/repos/river/river/raw/protocol"
REF="${RIVER_PROTOCOL_REF:-v0.4.1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTO_DIR="${SCRIPT_DIR}/../protocol"
OUT_DIR="${SCRIPT_DIR}/../src/Rivulet/Foreign"

PROTOCOLS=(
  river-window-management-v1
  river-xkb-bindings-v1
  river-input-management-v1
  river-layer-shell-v1
)

if ! command -v wayland-scanner >/dev/null 2>&1; then
  echo "error: wayland-scanner is required but not found in PATH" >&2
  exit 127
fi

mkdir -p "$PROTO_DIR" "$OUT_DIR"

for proto in "${PROTOCOLS[@]}"; do
  xml="$PROTO_DIR/${proto}.xml"

  if [ "${RIVULET_FETCH_PROTOCOLS:-0}" = "1" ] || [ ! -f "$xml" ]; then
    if ! command -v curl >/dev/null 2>&1; then
      echo "error: curl is required to fetch ${proto}.xml" >&2
      exit 127
    fi
    echo "Fetching ${proto}.xml..."
    curl -sSfL "${REPO}/${proto}.xml?ref=${REF}" -o "$xml"
  else
    echo "Using existing ${proto}.xml"
  fi

  echo "Generating ${proto}..."
  wayland-scanner client-header "$xml" "${OUT_DIR}/${proto}.h"
  wayland-scanner private-code "$xml" "${OUT_DIR}/${proto}.c"
done

echo "Done. Files written to ${OUT_DIR}/"

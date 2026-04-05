#!/usr/bin/env bash
set -euo pipefail

export LD_LIBRARY_PATH=/usr/local/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

RIVER="${HOME}/.local/bin/river"
SOCKET_DIR="/run/user/$(id -u)"

# snapshot existing sockets before starting river
existing_sockets() {
  ls "${SOCKET_DIR}"/wayland-* 2>/dev/null | grep -v '\.lock$' | sort || true
}

BEFORE=$(existing_sockets)

echo "[run-tests] starting river headless..."

env -u WAYLAND_DISPLAY -u DISPLAY \
  WLR_BACKENDS=headless \
  WLR_RENDERER=pixman \
  WLR_LIBINPUT_NO_DEVICES=1 \
  WLR_NO_HARDWARE_CURSORS=1 \
  "$RIVER" 2>/tmp/river-test.log &
RIVER_PID=$!

# wait for a new socket to appear (up to 5s)
DISPLAY_NAME=""
for i in $(seq 1 50); do
  AFTER=$(existing_sockets)
  NEW=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | head -1)
  if [ -n "$NEW" ]; then
    DISPLAY_NAME=$(basename "$NEW")
    break
  fi
  sleep 0.1
done

if [ -z "$DISPLAY_NAME" ]; then
  echo "[run-tests] error: river socket never appeared" >&2
  echo "[run-tests] river log:" >&2
  cat /tmp/river-test.log >&2
  kill "$RIVER_PID" 2>/dev/null || true
  exit 1
fi

echo "[run-tests] river up (pid=${RIVER_PID}, display=${DISPLAY_NAME})"

cleanup() {
  echo "[run-tests] stopping river (pid=${RIVER_PID})..."
  kill "$RIVER_PID" 2>/dev/null || true
  wait "$RIVER_PID" 2>/dev/null || true
  echo "[run-tests] river stopped"
}
trap cleanup EXIT

export WAYLAND_DISPLAY="$DISPLAY_NAME"
echo "[run-tests] running: cabal test"
cabal test

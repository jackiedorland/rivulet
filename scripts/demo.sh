#!/usr/bin/env bash
set -euo pipefail

export LD_LIBRARY_PATH=/usr/local/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

RIVER="${HOME}/.local/bin/river"
SYNC_LOG_DIR="${HOME}/.rivulet-log-sync"
SYNC_LOG="${SYNC_LOG_DIR}/rivulet.log"
LOG="${HOME}/.rivulet.log"
mkdir -p "$SYNC_LOG_DIR"
ln -sfn "$SYNC_LOG" "$LOG"

cabal build exe:rivulet 2>&1 | tee "$LOG"
RIVULET="$(cabal list-bin exe:rivulet)"

# Run as nested compositor in Sway
export WL_DISPLAY=wayland-0
export WAYLAND_DISPLAY=wayland-1
export WLR_NO_HARDWARE_CURSORS=1
export RIVULET_DEBUG=1

"$RIVER" -c "$RIVULET" 2>>"$LOG"

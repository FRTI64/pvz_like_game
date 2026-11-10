#!/bin/bash
# tools/verify/godot_shot.sh — run the verifier capture scene (windowed WSLg/llvmpipe).
# Usage: tools/verify/godot_shot.sh [setup] [out.png] [wait_seconds]
#   setups: empty | plants | zombies | suns | gameplay | pause | victory | gameover | menu
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 2
export LD_LIBRARY_PATH="$ROOT/.tools/libs/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XKB_CONFIG_ROOT="$ROOT/.tools/libs/usr/share/X11/xkb"
GODOT="${GODOT:-/usr/lib/godot-mono/godot.linuxbsd.editor.x86_64.mono}"
setup="${1:-gameplay}"
out="${2:-screenshots/godot_3d_${setup}.png}"
wait_s="${3:-2.5}"
mkdir -p tools/verify/tmp screenshots
log="tools/verify/tmp/godot_capture_${setup}.log"
timeout 180 "$GODOT" --path "$ROOT" tools/verify/capture_godot.tscn \
  --display-driver wayland --rendering-driver opengl3 \
  -- --setup "$setup" --out "$out" --wait "$wait_s" > "$log" 2>&1
code=$?
grep -E "VERIFY_CAPTURE_(OK|FAIL|WARN)" "$log" || true
if grep -q "SCRIPT ERROR" "$log"; then
  echo "FAIL: SCRIPT ERROR(s) in capture log: $log" >&2
  grep -n "SCRIPT ERROR" "$log" | head -10 >&2
  exit 1
fi
if [ "$code" -ne 0 ]; then
  echo "FAIL: godot exit code $code (log: $log)" >&2
  tail -25 "$log" >&2
  exit "$code"
fi
if [ ! -f "$out" ]; then
  echo "FAIL: no screenshot written at $out" >&2
  exit 1
fi
echo "SHOT_OK $out ($(stat -c%s "$out") bytes)"

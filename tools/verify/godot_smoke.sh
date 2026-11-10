#!/bin/bash
# tools/verify/godot_smoke.sh — headless logic/flow smoke test (no rendering).
# Usage: tools/verify/godot_smoke.sh [--frames N] [--level res://data/levels/level_1.tres] [--report path]
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 2
export LD_LIBRARY_PATH="$ROOT/.tools/libs/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XKB_CONFIG_ROOT="$ROOT/.tools/libs/usr/share/X11/xkb"
GODOT="${GODOT:-/usr/lib/godot-mono/godot.linuxbsd.editor.x86_64.mono}"
frames=600
level="res://data/levels/level_1.tres"
report="tools/verify/tmp/smoke_report.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --frames) frames="$2"; shift 2;;
    --level) level="$2"; shift 2;;
    --report) report="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
mkdir -p tools/verify/tmp
log="tools/verify/tmp/godot_smoke.log"
timeout 240 "$GODOT" --headless --fixed-fps 60 --path "$ROOT" tools/verify/smoke_logic.tscn \
  -- --frames "$frames" --level "$level" --out "$report" > "$log" 2>&1
code=$?
grep -E "VERIFY_SMOKE_(RESULT|FATAL)|^(PASS|FAIL|WARN) " "$log" | tail -60 || true
# Real script/runtime errors (filter known environment noise: user:// log dir, shader cache).
if grep -q "SCRIPT ERROR" "$log"; then
  echo "FAIL: SCRIPT ERROR in log $log" >&2
  grep -n -A2 "SCRIPT ERROR" "$log" | head -30 >&2
  exit 1
fi
real_errors=$(grep -nE "ERROR:|FATAL:" "$log" \
  | grep -vE "user://logs|user://shader_cache|Failed to open log file|core/io/dir_access.cpp:429|core/io/logger.cpp:169|shader_gles3|EGL: Can't create shader cache|Could not create directory: 'user://|Condition \"err != OK\" is true" || true)
if [ -n "$real_errors" ]; then
  echo "FAIL: runtime errors in log $log" >&2
  echo "$real_errors" | head -20 >&2
  exit 1
fi
if [ "$code" -ne 0 ]; then
  echo "FAIL: smoke test exit code $code (log: $log)" >&2
  exit "$code"
fi
echo "SMOKE_OK $report"

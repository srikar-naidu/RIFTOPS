#!/bin/bash
# Windowed auto-quitting screenshot batch for mobile HUD / viewmodel
# verification. Each run saves a PNG to builds/screenshots/ and logs the
# draw-call counters ([SHOT] lines). Uses port 28100 to stay clear of the
# default game port. Usage: bash tests/screenshot_pass.sh [WxH]
set -u
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
RES="${1:-2400x1080}"
OUT="$PROJ/builds/screenshots"
mkdir -p "$OUT"
TAG="${RES%x*}"

shot() { # name, extra args...
  local name="$1"; shift
  echo "--- $name ---"
  "$GODOT" --path "$PROJ" --resolution "$RES" -- --port 28100 --touch \
    --screenshot "$OUT/$name.png" --autoquit 45 "$@" 2>&1 | grep -E "\[SHOT\]|ERROR|SCRIPT ERROR" | head -8
}

shot "menu_$TAG"      --shot-delay 2
shot "lobby_$TAG"     --host --shot-delay 3
shot "hud_buy_$TAG"   --host --map solstice --mode spike --start-when 1 --shot-in-match --shot-delay 4
shot "buymenu_$TAG"   --host --map solstice --mode spike --start-when 1 --shot-in-match --shot-delay 4 --shot-ui buy
shot "score_$TAG"     --host --map solstice --mode spike --start-when 1 --shot-in-match --shot-delay 4 --shot-ui score
for W in classic sheriff spectre phantom vandal operator knife; do
  shot "vm_${W}_$TAG" --host --map solstice --mode tdm --start-when 1 --shot-in-match --shot-delay 3 --shot-weapon "$W"
done
echo "DONE $RES"

#!/bin/bash
# Valu two-instance LAN smoke test.
# Spawns a headless host and a headless client on this machine, then asserts
# via log markers that: the client connects, both instances see 2 player
# nodes, a scripted server-side shot damages the dummy target, and the kill
# feed event reaches both peers.
#
# Usage: bash tests/two_instance_test.sh
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
LOGDIR="$PROJ/tests/logs"
mkdir -p "$LOGDIR"
HOST_LOG="$LOGDIR/host.log"
CLIENT_LOG="$LOGDIR/client.log"

echo "== starting headless host =="
"$GODOT" --headless --path "$PROJ" -- --host --map graybox --name TestHost \
  --start-when 2 --spawn-dummy --test-shot --seed 42 --autoquit 45 \
  >"$HOST_LOG" 2>&1 &
HOST_PID=$!

sleep 3

echo "== starting headless client =="
"$GODOT" --headless --path "$PROJ" -- --join 127.0.0.1 --name TestClient --autoquit 45 \
  >"$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!

wait $HOST_PID
HOST_EXIT=$?
wait $CLIENT_PID
CLIENT_EXIT=$?

echo "host exit=$HOST_EXIT client exit=$CLIENT_EXIT"

PASS=1
check() { # file, pattern, label
  if grep -q "$2" "$1"; then
    echo "  ok: $3"
  else
    echo "  MISSING: $3  (pattern: $2)"
    PASS=0
  fi
}

echo "== host log checks =="
check "$HOST_LOG" "\[TEST\] server_started"        "server started"
check "$HOST_LOG" "\[TEST\] peer_connected"         "client registered on host"
check "$HOST_LOG" "\[TEST\] players_in_tree=2"      "host sees 2 player nodes"
check "$HOST_LOG" "\[TEST\] dummy_spawned"          "dummy target spawned"
check "$HOST_LOG" "\[TEST\] shot_hit target=Dummy"  "server-side shot damaged dummy"
check "$HOST_LOG" "\[TEST\] killfeed_received .*victim=Dummy" "kill feed fired on host"
check "$HOST_LOG" "\[TEST\] HOST_OK"                "host assertions passed"

echo "== client log checks =="
check "$CLIENT_LOG" "\[TEST\] connected_to_server"  "client connected"
check "$CLIENT_LOG" "\[TEST\] players_in_tree=2"    "client sees 2 player nodes"
check "$CLIENT_LOG" "\[TEST\] killfeed_received .*victim=Dummy" "kill feed replicated to client"
check "$CLIENT_LOG" "\[TEST\] CLIENT_OK"            "client assertions passed"

if [ "$PASS" = "1" ] && [ "$HOST_EXIT" = "0" ] && [ "$CLIENT_EXIT" = "0" ]; then
  echo "== TWO-INSTANCE TEST: PASS =="
  exit 0
else
  echo "== TWO-INSTANCE TEST: FAIL (see $LOGDIR) =="
  exit 1
fi

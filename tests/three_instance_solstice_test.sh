#!/bin/bash
# Valu 3-instance smoke on the real competitive map (Solstice):
# host (attacker, forced spike carrier) + attacker client + defender client.
#
#   Round 1: pistol economy (800), host buys a Sheriff (deduct assert),
#            attacker client buys light shields, host plants on site A with
#            the real plant zone, defender client teleports in and defuses
#            (full 7s hold) -> defenders win, win/loss/plant credits paid.
#   Round 2: host re-plants, nobody defuses -> detonation -> attackers win.
#
# Verifies the plant/defuse/economy/win flow works on Solstice with its
# real spawns and zones. Usage: bash tests/three_instance_solstice_test.sh
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
LOGDIR="$PROJ/tests/logs"
mkdir -p "$LOGDIR"

PASS=1
check() { # file, pattern, label
  if grep -qE "$2" "$1"; then
    echo "  ok: $3"
  else
    echo "  MISSING: $3  (pattern: $2)"
    PASS=0
  fi
}

echo "== 3-instance spike round on Solstice =="
HOST="$LOGDIR/solstice3_host.log"
CA="$LOGDIR/solstice3_client_att.log"
CD="$LOGDIR/solstice3_client_def.log"

"$GODOT" --headless --path "$PROJ" -- --host --map solstice --mode spike \
  --spike-fast --rounds-to-win 3 --carrier 1 --spike-script c --start-when 3 \
  --name Host --seed 7 --autoquit 150 >"$HOST" 2>&1 &
HOST_PID=$!
sleep 3
"$GODOT" --headless --path "$PROJ" -- --join 127.0.0.1 --team attacker \
  --spike-script c --name AttClient --autoquit 150 >"$CA" 2>&1 &
CA_PID=$!
sleep 1
"$GODOT" --headless --path "$PROJ" -- --join 127.0.0.1 --team defender \
  --spike-script c --name DefClient --autoquit 150 >"$CD" 2>&1 &
CD_PID=$!
wait $HOST_PID; HOST_EXIT=$?
wait $CA_PID; CA_EXIT=$?
wait $CD_PID; CD_EXIT=$?
echo "exits: host=$HOST_EXIT att_client=$CA_EXIT def_client=$CD_EXIT"

echo "-- host log checks --"
check "$HOST" "\[TEST\] server_started"                                 "server started"
check "$HOST" "match starting: map=res://maps/solstice/solstice.tscn"   "match runs on Solstice"
check "$HOST" "\[TEST\] round_start n=1 pistol=true carrier=1"          "round 1 pistol, host carries the spike"
check "$HOST" "\[TEST\] economy peer=1 credits=800"                     "800 pistol credits"
check "$HOST" "\[TEST\] barriers enabled=true phase=BUY"                "solstice buy barriers up"
check "$HOST" "\[TEST\] buy peer=1 item=weapon:sheriff ok reason=- credits=0"        "host buys sheriff (800->0)"
check "$HOST" "\[TEST\] buy peer=[0-9]{2,} item=shield:light ok reason=- credits=400" "attacker client buys light shield"
check "$HOST" "\[TEST\] barriers enabled=false phase=LIVE"              "barriers drop at live"
check "$HOST" "\[TEST\] plant_start peer=1 site=A"                      "plant started in Solstice zone A"
check "$HOST" "\[TEST\] spike_planted site=A"                           "spike planted on A"
check "$HOST" "\[TEST\] award peer=1 amount=300"                        "plant bonus paid to attackers"
check "$HOST" "\[TEST\] defuse_start peer=[0-9]{2,} from=0\.0"          "defender started defusing"
check "$HOST" "\[TEST\] defuse_checkpoint locked=3\.5"                  "defuse crossed the 3.5s checkpoint"
check "$HOST" "\[TEST\] spike_defused peer=[0-9]{2,}"                   "spike defused on Solstice"
check "$HOST" "\[TEST\] round_end n=1 winner=2 reason=defuse"           "defenders win round 1"
check "$HOST" "\[TEST\] award peer=[0-9]{2,} amount=3000"               "round win credits paid"
check "$HOST" "\[TEST\] loss_bonus team=1 streak=1 amount=1900"         "attacker loss bonus 1900"
check "$HOST" "\[TEST\] round_start n=2 pistol=false"                   "round 2 keeps economy (no pistol reset)"
check "$HOST" "\[TEST\] spike_planted site=A.*|\[TEST\] plant_start peer=1 site=A" "round 2 replant"
check "$HOST" "\[TEST\] spike_detonated"                                "spike detonated round 2"
check "$HOST" "\[TEST\] round_end n=2 winner=1 reason=detonation"       "attackers win round 2 by detonation"
check "$HOST" "\[TEST\] HOST_OK"                                        "host scenario passed"
N_READY=$(grep -c "\[TEST\] player_node_ready" "$HOST")
if [ "$N_READY" -ge 3 ]; then echo "  ok: 3 player nodes spawned on host ($N_READY)"; else echo "  MISSING: 3 player nodes (got $N_READY)"; PASS=0; fi

echo "-- attacker client checks --"
check "$CA" "\[TEST\] connected_to_server"                              "attacker client connected"
check "$CA" "\[TEST\] c_role team=1"                                    "attacker client on attackers"
check "$CA" "\[TEST\] CLIENT_OK"                                        "attacker client passed"

echo "-- defender client checks --"
check "$CD" "\[TEST\] connected_to_server"                              "defender client connected"
check "$CD" "\[TEST\] c_role team=2"                                    "defender client on defenders"
check "$CD" "\[TEST\] CLIENT_OK"                                        "defender client passed"

echo ""
if [ "$PASS" = "1" ] && [ "$HOST_EXIT" = "0" ] && [ "$CA_EXIT" = "0" ] && [ "$CD_EXIT" = "0" ]; then
  echo "== 3-INSTANCE SOLSTICE TEST: PASS =="
  exit 0
else
  echo "== 3-INSTANCE SOLSTICE TEST: FAIL (see $LOGDIR) =="
  exit 1
fi

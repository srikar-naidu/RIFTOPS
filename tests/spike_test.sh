#!/bin/bash
# Valu spike-mode automated test. Two headless host+client scenarios:
#
#  A (rounds/economy): buy-phase gating + credit deduction, barrier toggling,
#    scripted plant -> post-plant window, defuse with the 3.5s checkpoint
#    (release + resume), defuse round win + economy awards, loss-streak
#    credits across consecutive losses, halftime side swap + pistol reset,
#    elimination win + spike drop on death, 9000 credit cap, match end.
#
#  B (agents): one scripted server-side cast per ability for all 4 agents
#    (12 casts) with effect assertions (smoke spawns, molly ticks, stim
#    buffs fire rate, wall blocks a shot, slow + concuss + flash received on
#    the client, heal ticks, recon pings, dash/updraft displace), plus spike
#    drop -> pickup -> plant -> detonation.
#
# Usage: bash tests/spike_test.sh          # logs in tests/logs/, exit 0 = PASS
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

# ------------------------------------------------------------------
echo "== scenario A: rounds / economy / plant / defuse / halftime =="
HOST_A="$LOGDIR/spike_a_host.log"
CLIENT_A="$LOGDIR/spike_a_client.log"

"$GODOT" --headless --path "$PROJ" -- --host --map graybox --mode spike \
  --spike-fast --rounds-to-win 3 --spike-script a --start-when 2 \
  --name SpikeHost --seed 42 --autoquit 210 >"$HOST_A" 2>&1 &
HOST_PID=$!
sleep 3
"$GODOT" --headless --path "$PROJ" -- --join 127.0.0.1 --spike-script a \
  --name SpikeClient --autoquit 210 >"$CLIENT_A" 2>&1 &
CLIENT_PID=$!
wait $HOST_PID; HOST_EXIT=$?
wait $CLIENT_PID; CLIENT_EXIT=$?
echo "scenario A: host exit=$HOST_EXIT client exit=$CLIENT_EXIT"

echo "-- A: host log checks --"
check "$HOST_A" "\[TEST\] server_started"                                  "server started"
check "$HOST_A" "\[TEST\] spike_constants .*detonate=45 defuse=7\.0 checkpoint=3\.5" "round constants intact (45s window, 7s defuse, 3.5s checkpoint)"
check "$HOST_A" "\[TEST\] round_start n=1 pistol=true"                     "round 1 is a pistol round"
check "$HOST_A" "\[TEST\] economy peer=1 credits=800"                      "800 starting credits (host)"
check "$HOST_A" "\[TEST\] economy peer=[0-9]{2,} credits=800"                      "800 starting credits (client)"
check "$HOST_A" "\[TEST\] barriers enabled=true phase=BUY"                 "barriers up during buy phase"
check "$HOST_A" "\[TEST\] buy peer=1 item=weapon:sheriff ok reason=- credits=0" "purchase deducts credits (sheriff 800->0)"
check "$HOST_A" "\[TEST\] buy peer=[0-9]{2,} item=weapon:vandal denied reason=credits"  "insufficient credits denied (vandal)"
check "$HOST_A" "\[TEST\] buy peer=[0-9]{2,} item=shield:light ok reason=- credits=400" "shield purchase ok (light 400)"
check "$HOST_A" "\[TEST\] phase=LIVE round=1"                              "buy phase ended"
check "$HOST_A" "\[TEST\] barriers enabled=false phase=LIVE"               "barriers drop at live"
check "$HOST_A" "\[TEST\] buy peer=1 item=shield:light denied reason=phase" "purchases gated outside buy phase"
check "$HOST_A" "\[TEST\] plant_start peer=1 site=A"                       "scripted plant started in zone A"
check "$HOST_A" "\[TEST\] spike_planted site=A window="                    "plant opens the post-plant window"
check "$HOST_A" "\[TEST\] defuse_start peer=[0-9]{2,} from=0\.0"                   "defuse started"
check "$HOST_A" "\[TEST\] defuse_checkpoint locked=3\.5"                   "defuse checkpoint locked at 3.5s"
check "$HOST_A" "\[TEST\] defuse_stop at="                                 "defuse released after checkpoint"
check "$HOST_A" "\[TEST\] defuse_start peer=[0-9]{2,} from=3\.5"                   "defuse resumed from checkpoint"
check "$HOST_A" "\[TEST\] spike_defused peer=[0-9]{2,}"                            "defuse completed"
check "$HOST_A" "\[TEST\] round_end n=1 winner=2 reason=defuse"            "defenders win round 1 by defuse"
check "$HOST_A" "\[TEST\] loss_bonus team=1 streak=1 amount=1900"          "first loss bonus 1900"
check "$HOST_A" "\[TEST\] economy peer=1 credits=2200"                     "attacker economy correct (0+300 plant+1900 loss)"
check "$HOST_A" "\[TEST\] economy peer=[0-9]{2,} credits=3400"                     "defender economy correct (400+3000 win)"
check "$HOST_A" "\[TEST\] round_end n=2 winner=2 reason=timeout"           "round 2: timeout with no plant -> defenders"
check "$HOST_A" "\[TEST\] loss_bonus team=1 streak=2 amount=2400"          "loss streak 2 pays 2400"
check "$HOST_A" "\[TEST\] halftime_swap"                                   "halftime swap after round 2"
check "$HOST_A" "\[TEST\] team_swapped my_team=2"                          "host swapped to defenders"
check "$HOST_A" "\[TEST\] round_start n=3 pistol=true"                     "post-half pistol round (economy reset)"
check "$HOST_A" "\[TEST\] spike_dropped"                                   "spike dropped on carrier death"
check "$HOST_A" "\[TEST\] round_end n=3 winner=2 reason=elimination"       "elimination win"
check "$HOST_A" "\[TEST\] loss_bonus team=1 streak=3 amount=2900"          "loss streak 3 pays 2900"
check "$HOST_A" "\[TEST\] award peer=1 amount=3000 credits=9000"           "9000 credit cap enforced"
check "$HOST_A" "\[TEST\] match_end winner=2 score=2-3"                    "match end with final score"
check "$HOST_A" "\[TEST\] HOST_OK"                                         "host scenario A passed"

echo "-- A: client log checks --"
check "$CLIENT_A" "\[TEST\] connected_to_server"                           "client connected"
check "$CLIENT_A" "\[TEST\] team_swapped my_team=1"                        "client swapped to attackers"
check "$CLIENT_A" "\[TEST\] match_end winner=2"                            "match end replicated"
check "$CLIENT_A" "\[TEST\] CLIENT_OK"                                     "client scenario A passed"

# ------------------------------------------------------------------
echo "== scenario B: agent ability battery + spike drop/pickup/detonation =="
HOST_B="$LOGDIR/spike_b_host.log"
CLIENT_B="$LOGDIR/spike_b_client.log"

"$GODOT" --headless --path "$PROJ" -- --host --map graybox --mode spike \
  --spike-fast --live-time 90 --carrier 1 --spike-script b --start-when 2 \
  --name SpikeHost --seed 42 --autoquit 140 >"$HOST_B" 2>&1 &
HOST_PID=$!
sleep 3
"$GODOT" --headless --path "$PROJ" -- --join 127.0.0.1 --team attacker \
  --spike-script b --name SpikeClient --autoquit 140 >"$CLIENT_B" 2>&1 &
CLIENT_PID=$!
wait $HOST_PID; HOST_B_EXIT=$?
wait $CLIENT_PID; CLIENT_B_EXIT=$?
echo "scenario B: host exit=$HOST_B_EXIT client exit=$CLIENT_B_EXIT"

echo "-- B: host log checks --"
check "$HOST_B" "\[TEST\] buy peer=1 item=ability:2 ok reason=- credits=600" "ability charge purchase deducts credits"
for AB in dash updraft cloudburst sky_smoke molly stim wall slow heal flash recon concuss; do
  check "$HOST_B" "\[TEST\] cast peer=1 ability=$AB ok"                    "cast ok: $AB"
done
check "$HOST_B" "\[TEST\] dash_displaced=([4-9]|1[0-9])\."                 "dash displaced the caster (>=4m)"
check "$HOST_B" "\[TEST\] updraft_y=[1-9]"                                 "updraft launched the caster (>=1m up)"
check "$HOST_B" "\[TEST\] effect smoke spawned id=[0-9]+ r=4\.0 dur=4\.5"  "cloudburst smoke spawned (4m, 4.5s)"
check "$HOST_B" "\[TEST\] effect smoke spawned id=[0-9]+ r=4\.0 dur=15\.0" "sky smoke landed (4m, 15s)"
check "$HOST_B" "\[TEST\] effect fire spawned"                             "molly fire pool spawned"
check "$HOST_B" "\[TEST\] molly_tick peer=[0-9]{2,} dmg=2"                         "molly ticks damage (ally half)"
check "$HOST_B" "\[TEST\] effect stim spawned"                             "stim beacon zone spawned"
check "$HOST_B" "\[TEST\] stim_shot peer=1"                                "stim buffs fire rate on server"
check "$HOST_B" "\[TEST\] effect wall spawned id=[0-9]+ segs=4"            "barrier wall placed (4 segments)"
check "$HOST_B" "\[TEST\] wall_hit id=[0-9]+ seg=[0-9] hp="                "wall blocked a test shot (segment damaged)"
check "$HOST_B" "\[TEST\] effect slow spawned"                             "slow orb zone spawned"
check "$HOST_B" "\[TEST\] heal_target peer=1 self=true"                    "heal targeted self"
check "$HOST_B" "\[TEST\] heal_tick peer=1 hp="                            "heal ticks health"
check "$HOST_B" "\[TEST\] flash_applied peer=[0-9]{2,}"                            "flash resolved against client"
check "$HOST_B" "\[TEST\] recon_ping target=Dummy"                         "recon pulse revealed an enemy"
check "$HOST_B" "\[TEST\] concuss_hit peer=[0-9]{2,}"                              "concussion blast hit client"
check "$HOST_B" "\[TEST\] spike_dropped"                                   "spike dropped on carrier death"
check "$HOST_B" "\[TEST\] spike_pickup peer="                              "spike picked up by teammate"
check "$HOST_B" "\[TEST\] spike_planted site=A"                            "recovered spike planted"
check "$HOST_B" "\[TEST\] spike_detonated"                                 "spike detonated"
check "$HOST_B" "\[TEST\] round_end n=1 winner=1 reason=detonation"        "attackers win by detonation"
check "$HOST_B" "\[TEST\] HOST_OK"                                         "host scenario B passed"

echo "-- B: client log checks --"
check "$CLIENT_B" "\[TEST\] slowed mult=0\.35"                             "client slowed by slow orb (65%)"
check "$CLIENT_B" "\[TEST\] concussed dur=4\.0"                            "client concussed (4s)"
check "$CLIENT_B" "\[TEST\] flashed strength="                             "client received flash event"
check "$CLIENT_B" "\[TEST\] CLIENT_OK"                                     "client scenario B passed"

echo ""
if [ "$PASS" = "1" ] && [ "$HOST_EXIT" = "0" ] && [ "$CLIENT_EXIT" = "0" ] \
  && [ "$HOST_B_EXIT" = "0" ] && [ "$CLIENT_B_EXIT" = "0" ]; then
  echo "== SPIKE TEST: PASS =="
  exit 0
else
  echo "== SPIKE TEST: FAIL (see $LOGDIR) =="
  exit 1
fi

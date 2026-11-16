extends Node
## GameState (autoload singleton) — authoritative match/round state.
##
## Owns the Spike round state machine, economy, per-player stats and the
## spike lifecycle, plus the Phase-2 TDM mode. Only the server mutates match
## state; clients receive it via the cl_* RPCs. Per-player combat/ability
## RPCs stay on the Player node (see docs/CONVENTIONS.md RPC surface rules).

enum Team { NONE = 0, ATTACKERS = 1, DEFENDERS = 2 }

enum RoundPhase {
	IDLE,       ## No match running (menus / lobby).
	BUY,        ## Buy phase; spawn barriers up.
	ACTIVE,     ## Round live, spike not planted.
	PLANTED,    ## Spike planted; detonation timer running.
	ROUND_END,  ## Short outro before next round / match end.
}

enum Mode { TDM, SPIKE }

enum SpikeState { CARRIED, DROPPED, PLANTED, DEFUSED, DETONATED }

## Competitive round timings (seconds). --spike-fast (test flag, host side)
## shortens buy/live/detonate/round-end; plant/defuse/checkpoint stay real.
const BUY_PHASE_TIME := 30.0
const ROUND_TIME := 100.0
const SPIKE_PLANT_TIME := 4.0
const SPIKE_DETONATION_TIME := 45.0
const SPIKE_DEFUSE_TIME := 7.0
const SPIKE_DEFUSE_CHECKPOINT := 3.5
const ROUND_END_TIME := 7.0
const ROUNDS_TO_WIN := 13
const HALFTIME_AFTER_ROUND := 12

## Round economy.
const CREDITS_START := 800
const CREDITS_MAX := 9000
const CREDITS_KILL := 200
const CREDITS_PLANT := 300
const CREDITS_WIN := 3000
const CREDITS_LOSS_BASE := 1900
const CREDITS_LOSS_STEP := 500
const CREDITS_LOSS_MAX := 2900

## Shields absorb 66% of damage and break after absorbing 25/50.
const SHIELD_ABSORB := 0.66
const SHIELD_LIGHT_VALUE := 25
const SHIELD_LIGHT_PRICE := 400
const SHIELD_HEAVY_VALUE := 50
const SHIELD_HEAVY_PRICE := 1000

const DEFUSE_RADIUS := 1.9
const SPIKE_PICKUP_RADIUS := 1.4
const SPIKE_LETHAL_RADIUS := 5.0
const SPIKE_DAMAGE_RADIUS := 9.0
const INTERACT_MAX_SPEED := 1.2
const ASSIST_WINDOW_MS := 5000

const TDM_TARGET_KILLS := 40
const TDM_TIME_LIMIT := 600.0
const TDM_RESPAWN_DELAY := 3.0

signal match_started
signal match_ended(winning_team: int)
signal kill_feed_event(killer_name: String, victim_name: String, weapon_id: String, headshot: bool, killer_team: int)
signal team_scores_changed
signal match_time_updated
signal local_player_spawned(player: Node)
signal phase_changed(phase: int)
signal round_ended(winner: int, reason: String)
signal spike_changed
signal economy_changed
signal stats_changed
signal interact_progress(kind: int, value: float, total: float, peer: int)
signal teams_swapped

var phase: RoundPhase = RoundPhase.IDLE
var round_number: int = 0
## Round scores are side-keyed and swapped together with the players at
## halftime, so score_att is always "rounds won by the current attackers".
var score_att: int = 0
var score_def: int = 0

var mode: Mode = Mode.TDM
var map_path: String = "res://maps/graybox/graybox.tscn"
var team_size: int = 5
var tdm_target: int = TDM_TARGET_KILLS
var match_seed: int = 0
var match_running := false
## TDM: match time left. SPIKE: time left in the current phase.
var match_time_left: float = 0.0
var kills_a: int = 0
var kills_b: int = 0

## Spike config (replicated in cl_start_match; scaled by --spike-fast).
var rounds_to_win: int = ROUNDS_TO_WIN
var halftime_after: int = HALFTIME_AFTER_ROUND
var cfg_buy := BUY_PHASE_TIME
var cfg_live := ROUND_TIME
var cfg_plant := SPIKE_PLANT_TIME
var cfg_detonate := SPIKE_DETONATION_TIME
var cfg_defuse := SPIKE_DEFUSE_TIME
var cfg_checkpoint := SPIKE_DEFUSE_CHECKPOINT
var cfg_round_end := ROUND_END_TIME

## Replicated spike state: {"state": SpikeState, "carrier": peer, "pos": Vector3, "site": String}
var spike: Dictionary = {}
## peer_id -> credits (replicated).
var economy: Dictionary = {}
## peer_id -> {"k": int, "d": int, "a": int} (replicated).
var stats: Dictionary = {}

var local_player: Node = null

# --- server-only spike state ---
var _loadouts: Dictionary = {}       # peer -> {primary, secondary, armor, charges: {slot: n}}
var _loss_streak := {Team.ATTACKERS: 0, Team.DEFENDERS: 0}
var _interact_held: Dictionary = {}  # peer -> bool
var _plant_peer := 0
var _plant_progress := 0.0
var _defuse_peer := 0
var _defuse_progress := 0.0
var _defuse_checkpoint := 0.0
var _recent_damage: Dictionary = {}  # victim_peer -> {attacker_peer: expire_ms}
var _pistol_next := false
var _progress_bcast_accum := 0.0
var _time_bcast_accum := 0.0


func _ready() -> void:
	var autoquit := Cli.value_int("autoquit", 0)
	if autoquit > 0:
		get_tree().create_timer(float(autoquit)).timeout.connect(
			func() -> void:
				print("[TEST] TIMEOUT after %ds, quitting" % autoquit)
				get_tree().quit(2))
	Net.player_left.connect(_on_net_player_left)
	if Cli.has_flag("screenshot"):
		var probe := ScreenshotProbe.new()
		probe.name = "ScreenshotProbe"
		add_child(probe)


func _process(delta: float) -> void:
	if not match_running:
		return
	match_time_left = maxf(match_time_left - delta, 0.0)
	if not multiplayer.is_server():
		return
	_time_bcast_accum += delta
	if _time_bcast_accum >= 2.0:
		_time_bcast_accum = 0.0
		rpc("cl_time", match_time_left)
	if mode == Mode.TDM:
		if match_time_left <= 0.0:
			_server_end_match(_leading_team())
	else:
		_spike_server_tick(delta)


func map_display_name() -> String:
	return map_path.get_file().get_basename()


static func team_name(team: int) -> String:
	match team:
		Team.ATTACKERS: return "Attackers"
		Team.DEFENDERS: return "Defenders"
		_: return "Nobody"


static func team_color(team: int) -> Color:
	match team:
		Team.ATTACKERS: return Color(0.35, 0.8, 0.65)
		Team.DEFENDERS: return Color(0.95, 0.45, 0.35)
		_: return Color(0.8, 0.8, 0.8)


static func phase_name(p: int) -> String:
	match p:
		RoundPhase.BUY: return "BUY"
		RoundPhase.ACTIVE: return "LIVE"
		RoundPhase.PLANTED: return "PLANTED"
		RoundPhase.ROUND_END: return "ROUND_END"
		_: return "IDLE"


## Host-only entry point (lobby Start button / CLI auto-start).
func host_start_match(p_map: String, p_mode: Mode, p_team_size: int, p_target: int = TDM_TARGET_KILLS) -> void:
	if not multiplayer.is_server():
		return
	var cfg := {
		"map": p_map,
		"mode": p_mode,
		"team_size": p_team_size,
		"tdm_target": p_target,
		"seed": Cli.value_int("seed", randi()),
		"rounds_to_win": maxi(Cli.value_int("rounds-to-win", ROUNDS_TO_WIN), 2),
		"fast": Cli.has_flag("spike-fast"),
		"buy_time": Cli.value_int("buy-time", -1),
		"live_time": Cli.value_int("live-time", -1),
		"detonate_time": Cli.value_int("detonate-time", -1),
	}
	rpc("cl_start_match", cfg)


@rpc("authority", "call_local", "reliable")
func cl_start_match(cfg: Dictionary) -> void:
	map_path = String(cfg.get("map", "res://maps/graybox/graybox.tscn"))
	mode = int(cfg.get("mode", Mode.TDM)) as Mode
	team_size = int(cfg.get("team_size", 5))
	tdm_target = int(cfg.get("tdm_target", TDM_TARGET_KILLS))
	match_seed = int(cfg.get("seed", 0))
	rounds_to_win = int(cfg.get("rounds_to_win", ROUNDS_TO_WIN))
	halftime_after = (rounds_to_win - 1)
	if bool(cfg.get("fast", false)):
		cfg_buy = 3.0
		cfg_live = 20.0
		cfg_detonate = 15.0
		cfg_round_end = 2.0
	else:
		cfg_buy = BUY_PHASE_TIME
		cfg_live = ROUND_TIME
		cfg_detonate = SPIKE_DETONATION_TIME
		cfg_round_end = ROUND_END_TIME
	if int(cfg.get("buy_time", -1)) > 0:
		cfg_buy = float(int(cfg.buy_time))
	if int(cfg.get("live_time", -1)) > 0:
		cfg_live = float(int(cfg.live_time))
	if int(cfg.get("detonate_time", -1)) > 0:
		cfg_detonate = float(int(cfg.detonate_time))
	cfg_plant = SPIKE_PLANT_TIME
	cfg_defuse = SPIKE_DEFUSE_TIME
	cfg_checkpoint = SPIKE_DEFUSE_CHECKPOINT
	if Cli.test_mode() and mode == Mode.SPIKE:
		print("[TEST] spike_constants buy=%.0f live=%.0f plant=%.0f detonate=%.0f defuse=%.1f checkpoint=%.1f" % [
			BUY_PHASE_TIME, ROUND_TIME, SPIKE_PLANT_TIME, SPIKE_DETONATION_TIME, SPIKE_DEFUSE_TIME, SPIKE_DEFUSE_CHECKPOINT])
		print("[TEST] spike_cfg buy=%.0f live=%.0f plant=%.0f detonate=%.0f defuse=%.1f checkpoint=%.1f rtw=%d" % [
			cfg_buy, cfg_live, cfg_plant, cfg_detonate, cfg_defuse, cfg_checkpoint, rounds_to_win])
	kills_a = 0
	kills_b = 0
	score_att = 0
	score_def = 0
	round_number = 0
	economy = {}
	stats = {}
	spike = {}
	_loadouts = {}
	_loss_streak = {Team.ATTACKERS: 0, Team.DEFENDERS: 0}
	_interact_held = {}
	_pistol_next = false
	match_time_left = TDM_TIME_LIMIT if mode == Mode.TDM else cfg_buy
	match_running = true
	phase = RoundPhase.ACTIVE if mode == Mode.TDM else RoundPhase.BUY
	local_player = null
	match_started.emit()
	print("[GAME] match starting: map=%s mode=%d rtw=%d" % [map_path, mode, rounds_to_win])
	get_tree().change_scene_to_file.call_deferred("res://scenes/match.tscn")


# ------------------------------------------------------------------
# Spike round state machine (server)
# ------------------------------------------------------------------

## Called by match.gd once all peers are ready and player nodes are spawned.
func server_begin_spike() -> void:
	if not multiplayer.is_server() or mode != Mode.SPIKE:
		return
	_start_round(1)


func _start_round(n: int) -> void:
	round_number = n
	var pistol := n == 1 or n == halftime_after + 1 or _pistol_next
	_pistol_next = false
	for peer: int in Net.players:
		if pistol:
			economy[peer] = CREDITS_START
			_loadouts[peer] = _fresh_loadout()
		else:
			if not _loadouts.has(peer):
				_loadouts[peer] = _fresh_loadout()
				economy[peer] = CREDITS_START
			var node := _player_node(peer)
			if node == null or not bool(node.alive):
				# Died last round: lose guns/armor, keep bought ability charges.
				var charges: Dictionary = _loadouts[peer].charges
				_loadouts[peer] = _fresh_loadout()
				_loadouts[peer].charges = charges
			else:
				# Survivors keep their guns and whatever armor is LEFT.
				_loadouts[peer].armor = int(node.armor)
		if not stats.has(peer):
			stats[peer] = {"k": 0, "d": 0, "a": 0}
		_refill_signatures(peer)
	# Assign the spike to a random attacker (test override: --carrier <peer>).
	var attackers: Array = []
	for peer: int in Net.players:
		if int(Net.players[peer].get("team", 0)) == Team.ATTACKERS:
			attackers.append(peer)
	var carrier := 0
	if not attackers.is_empty():
		var forced := Cli.value_int("carrier", 0)
		carrier = forced if attackers.has(forced) else attackers[randi() % attackers.size()]
	spike = {"state": SpikeState.CARRIED, "carrier": carrier, "pos": Vector3.ZERO, "site": ""}
	_plant_peer = 0
	_plant_progress = 0.0
	_defuse_peer = 0
	_defuse_progress = 0.0
	_defuse_checkpoint = 0.0
	_interact_held.clear()
	_recent_damage.clear()
	phase = RoundPhase.BUY
	match_time_left = cfg_buy
	# Respawn everyone at their side's spawns with their persisted loadout.
	var idx := {Team.ATTACKERS: 0, Team.DEFENDERS: 0}
	for peer: int in Net.players:
		var node := _player_node(peer)
		if node == null:
			continue
		var team := int(Net.players[peer].get("team", Team.ATTACKERS))
		var tr: Transform3D = get_tree().current_scene.pick_spawn(team, int(idx.get(team, 0)))
		idx[team] = int(idx.get(team, 0)) + 1
		node.server_round_spawn(tr.origin, tr.basis.get_euler().y, _loadouts[peer])
	rpc("cl_phase", RoundPhase.BUY, match_time_left, round_number, score_att, score_def)
	rpc("cl_spike", spike)
	rpc("cl_economy", economy)
	rpc("cl_stats", stats)
	print("[GAME] round %d start (pistol=%s carrier=%d)" % [n, str(pistol), carrier])
	if Cli.test_mode():
		print("[TEST] round_start n=%d pistol=%s carrier=%d" % [n, str(pistol), carrier])
		for peer: int in economy:
			print("[TEST] economy peer=%d credits=%d" % [peer, int(economy[peer])])


func _fresh_loadout() -> Dictionary:
	return {"primary": "", "secondary": "classic", "armor": 0, "charges": {0: 0, 1: 0, 2: 0}}


func _refill_signatures(peer: int) -> void:
	var agent := String(Net.players[peer].get("agent", AgentDB.DEFAULT_AGENT))
	var charges: Dictionary = _loadouts[peer].charges
	for slot in 3:
		var ab := AgentDB.ability(agent, slot)
		if ab != null:
			if ab.signature:
				charges[slot] = maxi(int(charges.get(slot, 0)), 1)
			charges[slot] = mini(int(charges.get(slot, 0)), ab.max_charges)


func _spike_server_tick(delta: float) -> void:
	match phase:
		RoundPhase.BUY:
			if match_time_left <= 0.0:
				_enter_live()
		RoundPhase.ACTIVE:
			_tick_plant(delta)
			_tick_pickup()
			if phase == RoundPhase.ACTIVE and match_time_left <= 0.0:
				_end_round(Team.DEFENDERS, "timeout")
		RoundPhase.PLANTED:
			_tick_defuse(delta)
			if phase == RoundPhase.PLANTED and match_time_left <= 0.0:
				_detonate()
		RoundPhase.ROUND_END:
			if match_time_left <= 0.0:
				_next_round_or_end()


func _enter_live() -> void:
	phase = RoundPhase.ACTIVE
	match_time_left = cfg_live
	rpc("cl_phase", phase, match_time_left, round_number, score_att, score_def)
	if Cli.test_mode():
		print("[TEST] phase=LIVE round=%d" % round_number)


func _tick_plant(delta: float) -> void:
	var carrier := int(spike.get("carrier", 0))
	var valid := false
	var site := ""
	if int(spike.get("state", -1)) == SpikeState.CARRIED and carrier != 0 and _interact_held.get(carrier, false):
		var node := _player_node(carrier)
		if node != null and bool(node.alive) and Vector3(node.observed_velocity).length() < INTERACT_MAX_SPEED:
			site = _plant_site_for(node)
			valid = site != ""
	if valid:
		if _plant_peer != carrier:
			_plant_peer = carrier
			_plant_progress = 0.0
			rpc("cl_spike_cue", "plant", _player_node(carrier).global_position)
			if Cli.test_mode():
				print("[TEST] plant_start peer=%d site=%s" % [carrier, site])
		_plant_progress += delta
		_broadcast_progress(0, _plant_progress, cfg_plant, carrier, delta)
		if _plant_progress >= cfg_plant:
			_do_plant(site)
	elif _plant_peer != 0:
		_plant_peer = 0
		_plant_progress = 0.0
		rpc("cl_progress", 0, 0.0, cfg_plant, 0)
		if Cli.test_mode():
			print("[TEST] plant_cancel")


func _plant_site_for(node: Node3D) -> String:
	for group: String in ["plant_zone_a", "plant_zone_b"]:
		for zone: Node in get_tree().get_nodes_in_group(group):
			if zone is Area3D and (zone as Area3D).overlaps_body(node):
				return "A" if group == "plant_zone_a" else "B"
	return ""


func _do_plant(site: String) -> void:
	var carrier := int(spike.get("carrier", 0))
	var node := _player_node(carrier)
	var pos: Vector3 = node.global_position if node != null else Vector3.ZERO
	pos.y = maxf(pos.y, 0.02)
	spike = {"state": SpikeState.PLANTED, "carrier": 0, "pos": pos, "site": site}
	phase = RoundPhase.PLANTED
	match_time_left = cfg_detonate
	_plant_peer = 0
	_plant_progress = 0.0
	# Plant bonus goes to the whole attacking team immediately.
	for peer: int in Net.players:
		if int(Net.players[peer].get("team", 0)) == Team.ATTACKERS:
			_srv_award(peer, CREDITS_PLANT)
	rpc("cl_phase", phase, match_time_left, round_number, score_att, score_def)
	rpc("cl_spike", spike)
	rpc("cl_economy", economy)
	print("[GAME] spike planted at %s (site %s)" % [str(pos), site])
	if Cli.test_mode():
		print("[TEST] spike_planted site=%s window=%.1f" % [site, cfg_detonate])


func _tick_pickup() -> void:
	if int(spike.get("state", -1)) != SpikeState.DROPPED:
		return
	var pos: Vector3 = spike.get("pos", Vector3.ZERO)
	for peer: int in Net.players:
		if int(Net.players[peer].get("team", 0)) != Team.ATTACKERS:
			continue
		var node := _player_node(peer)
		if node == null or not bool(node.alive):
			continue
		var d2 := Vector2(node.global_position.x - pos.x, node.global_position.z - pos.z).length()
		if d2 <= SPIKE_PICKUP_RADIUS and absf(node.global_position.y - pos.y) < 2.0:
			spike["state"] = SpikeState.CARRIED
			spike["carrier"] = peer
			rpc("cl_spike", spike)
			if Cli.test_mode():
				print("[TEST] spike_pickup peer=%d" % peer)
			return


func _tick_defuse(delta: float) -> void:
	var pos: Vector3 = spike.get("pos", Vector3.ZERO)
	var defuser := 0
	# Prefer the current defuser if still valid, otherwise take any valid one.
	var candidates: Array = []
	for peer: int in Net.players:
		if int(Net.players[peer].get("team", 0)) != Team.DEFENDERS or not _interact_held.get(peer, false):
			continue
		var node := _player_node(peer)
		if node == null or not bool(node.alive):
			continue
		if node.global_position.distance_to(pos) <= DEFUSE_RADIUS and Vector3(node.observed_velocity).length() < INTERACT_MAX_SPEED:
			candidates.append(peer)
	if candidates.has(_defuse_peer):
		defuser = _defuse_peer
	elif not candidates.is_empty():
		defuser = candidates[0]
	if defuser != 0:
		if _defuse_peer != defuser:
			_defuse_peer = defuser
			_defuse_progress = _defuse_checkpoint
			rpc("cl_spike_cue", "defuse", pos)
			if Cli.test_mode():
				print("[TEST] defuse_start peer=%d from=%.1f" % [defuser, _defuse_progress])
		var before := _defuse_progress
		_defuse_progress += delta
		if before < cfg_checkpoint and _defuse_progress >= cfg_checkpoint and _defuse_checkpoint < cfg_checkpoint:
			_defuse_checkpoint = cfg_checkpoint
			if Cli.test_mode():
				print("[TEST] defuse_checkpoint locked=%.1f" % cfg_checkpoint)
		_broadcast_progress(1, _defuse_progress, cfg_defuse, defuser, delta)
		if _defuse_progress >= cfg_defuse:
			_do_defuse_win(defuser)
	elif _defuse_peer != 0:
		if Cli.test_mode():
			print("[TEST] defuse_stop at=%.2f checkpoint=%.1f" % [_defuse_progress, _defuse_checkpoint])
		_defuse_peer = 0
		_defuse_progress = _defuse_checkpoint
		rpc("cl_progress", 1, _defuse_checkpoint, cfg_defuse, 0)


func _broadcast_progress(kind: int, value: float, total: float, peer: int, delta: float) -> void:
	_progress_bcast_accum += delta
	if _progress_bcast_accum >= 0.1 or value >= total:
		_progress_bcast_accum = 0.0
		rpc("cl_progress", kind, value, total, peer)


func _do_defuse_win(defuser: int) -> void:
	spike["state"] = SpikeState.DEFUSED
	rpc("cl_spike", spike)
	print("[GAME] spike defused by peer %d" % defuser)
	if Cli.test_mode():
		print("[TEST] spike_defused peer=%d" % defuser)
	_end_round(Team.DEFENDERS, "defuse")


func _detonate() -> void:
	spike["state"] = SpikeState.DETONATED
	var pos: Vector3 = spike.get("pos", Vector3.ZERO)
	rpc("cl_spike", spike)
	var fx := get_tree().get_first_node_in_group("effects_manager")
	if fx != null:
		fx.server_spike_explosion(pos)
	# Lethal core, damage falloff to the edge; hits both teams (no LOS check).
	for node: Node in get_tree().get_nodes_in_group("players"):
		if not bool(node.alive):
			continue
		var d := (node as Node3D).global_position.distance_to(pos)
		if d > SPIKE_DAMAGE_RADIUS:
			continue
		var dmg := 999
		if d > SPIKE_LETHAL_RADIUS:
			dmg = int(lerpf(150.0, 50.0, (d - SPIKE_LETHAL_RADIUS) / (SPIKE_DAMAGE_RADIUS - SPIKE_LETHAL_RADIUS)))
		node.server_apply_ability_damage(dmg, "Spike", Team.NONE, 0, "spike")
	print("[GAME] spike detonated")
	if Cli.test_mode():
		print("[TEST] spike_detonated")
	_end_round(Team.ATTACKERS, "detonation")


func _end_round(winner: int, reason: String) -> void:
	if phase == RoundPhase.ROUND_END or not match_running:
		return
	phase = RoundPhase.ROUND_END
	match_time_left = cfg_round_end
	if winner == Team.ATTACKERS:
		score_att += 1
	else:
		score_def += 1
	_award_round_credits(winner)
	_interact_held.clear()
	_plant_peer = 0
	_defuse_peer = 0
	rpc("cl_round_end", winner, reason, score_att, score_def, round_number)
	rpc("cl_economy", economy)
	print("[GAME] round %d over: %s win (%s)  %d-%d" % [round_number, team_name(winner), reason, score_att, score_def])
	if Cli.test_mode():
		print("[TEST] round_end n=%d winner=%d reason=%s score=%d-%d" % [round_number, winner, reason, score_att, score_def])


func _award_round_credits(winner: int) -> void:
	var loser: int = Team.DEFENDERS if winner == Team.ATTACKERS else Team.ATTACKERS
	_loss_streak[winner] = 0
	_loss_streak[loser] = int(_loss_streak[loser]) + 1
	var loss_bonus: int = mini(CREDITS_LOSS_BASE + (int(_loss_streak[loser]) - 1) * CREDITS_LOSS_STEP, CREDITS_LOSS_MAX)
	if Cli.test_mode():
		print("[TEST] loss_bonus team=%d streak=%d amount=%d" % [loser, int(_loss_streak[loser]), loss_bonus])
	for peer: int in Net.players:
		var team := int(Net.players[peer].get("team", 0))
		_srv_award(peer, CREDITS_WIN if team == winner else loss_bonus)


func _next_round_or_end() -> void:
	# Forfeit: a side with no registered players left loses the match.
	var att_count := 0
	var def_count := 0
	for peer: int in Net.players:
		match int(Net.players[peer].get("team", 0)):
			Team.ATTACKERS: att_count += 1
			Team.DEFENDERS: def_count += 1
	if att_count == 0 and def_count > 0:
		_server_end_match(Team.DEFENDERS)
		return
	if def_count == 0 and att_count > 0:
		_server_end_match(Team.ATTACKERS)
		return
	if score_att >= rounds_to_win:
		_server_end_match(Team.ATTACKERS)
		return
	if score_def >= rounds_to_win:
		_server_end_match(Team.DEFENDERS)
		return
	if round_number == halftime_after:
		_halftime_swap()
	_start_round(round_number + 1)


func _halftime_swap() -> void:
	# Flip every player's side; scores follow the group, streaks/economy reset.
	for peer: int in Net.players:
		var t := int(Net.players[peer].get("team", Team.ATTACKERS))
		Net.players[peer].team = Team.DEFENDERS if t == Team.ATTACKERS else Team.ATTACKERS
	Net.rpc("cl_players", Net.players)
	Net.player_list_changed.emit()
	var tmp := score_att
	score_att = score_def
	score_def = tmp
	_loss_streak = {Team.ATTACKERS: 0, Team.DEFENDERS: 0}
	_pistol_next = true
	rpc("cl_swap_teams", score_att, score_def)
	print("[GAME] halftime: teams swapped")
	if Cli.test_mode():
		print("[TEST] halftime_swap")


## Called on carrier death (from server_report_kill) or disconnect.
func _drop_spike_at(pos: Vector3) -> void:
	pos.y = maxf(pos.y, 0.02)
	spike["state"] = SpikeState.DROPPED
	spike["carrier"] = 0
	spike["pos"] = pos
	rpc("cl_spike", spike)
	if Cli.test_mode():
		print("[TEST] spike_dropped pos=%s" % str(pos.snappedf(0.1)))


func _check_elimination() -> void:
	if mode != Mode.SPIKE or (phase != RoundPhase.ACTIVE and phase != RoundPhase.PLANTED):
		return
	var registered := {Team.ATTACKERS: 0, Team.DEFENDERS: 0}
	var alive := {Team.ATTACKERS: 0, Team.DEFENDERS: 0}
	for peer: int in Net.players:
		var t := int(Net.players[peer].get("team", 0))
		if t != Team.ATTACKERS and t != Team.DEFENDERS:
			continue
		registered[t] = int(registered[t]) + 1
		var node := _player_node(peer)
		if node != null and bool(node.alive):
			alive[t] = int(alive[t]) + 1
	# Only judge a side that actually has players (test configs may not).
	if int(registered[Team.DEFENDERS]) > 0 and int(alive[Team.DEFENDERS]) == 0:
		_end_round(Team.ATTACKERS, "elimination")
		return
	if phase == RoundPhase.ACTIVE and int(registered[Team.ATTACKERS]) > 0 and int(alive[Team.ATTACKERS]) == 0:
		# Post-plant, dead attackers can still win via detonation.
		_end_round(Team.DEFENDERS, "elimination")


func _on_net_player_left(peer: int) -> void:
	if not multiplayer.is_server() or mode != Mode.SPIKE or not match_running:
		return
	_interact_held.erase(peer)
	economy.erase(peer)
	if int(spike.get("carrier", 0)) == peer:
		var node := _player_node(peer)  # still in tree; match.gd frees it after us
		_drop_spike_at(node.global_position if node != null else Vector3.ZERO)
	if phase == RoundPhase.ACTIVE or phase == RoundPhase.PLANTED:
		# Forfeit the round immediately if a side emptied out.
		var att := 0
		var def := 0
		for p: int in Net.players:
			match int(Net.players[p].get("team", 0)):
				Team.ATTACKERS: att += 1
				Team.DEFENDERS: def += 1
		if att == 0 and def > 0:
			_end_round(Team.DEFENDERS, "forfeit")
		elif def == 0 and att > 0:
			_end_round(Team.ATTACKERS, "forfeit")
		else:
			_check_elimination()


# ------------------------------------------------------------------
# Economy / buying (server-validated)
# ------------------------------------------------------------------

func _srv_award(peer: int, amount: int) -> void:
	economy[peer] = clampi(int(economy.get(peer, 0)) + amount, 0, CREDITS_MAX)
	if Cli.test_mode():
		print("[TEST] award peer=%d amount=%d credits=%d" % [peer, amount, int(economy[peer])])


## Client-side helper: request a purchase ("weapon:<id>" | "shield:light" |
## "shield:heavy" | "ability:<slot 0-2>").
func request_buy(item: String) -> void:
	if multiplayer.is_server():
		srv_buy(item)
	else:
		rpc_id(1, "srv_buy", item)


@rpc("any_peer", "call_remote", "reliable")
func srv_buy(item: String) -> void:
	if not multiplayer.is_server() or mode != Mode.SPIKE:
		return
	var peer := _sender()
	if phase != RoundPhase.BUY:
		_buy_result(peer, item, false, "phase")
		return
	var node := _player_node(peer)
	if node == null or not Net.players.has(peer):
		_buy_result(peer, item, false, "no_player")
		return
	if not _loadouts.has(peer):
		_loadouts[peer] = _fresh_loadout()
	var lo: Dictionary = _loadouts[peer]
	var credits := int(economy.get(peer, 0))
	var kind := item.get_slice(":", 0)
	var arg := item.get_slice(":", 1)
	match kind:
		"weapon":
			var w := WeaponDB.get_weapon(StringName(arg))
			if w == null or w.slot == WeaponData.Slot.KNIFE:
				_buy_result(peer, item, false, "item")
				return
			var slot_key := "primary" if w.slot == WeaponData.Slot.PRIMARY else "secondary"
			if String(lo[slot_key]) == arg:
				_buy_result(peer, item, false, "owned")
				return
			if credits < w.price:
				_buy_result(peer, item, false, "credits")
				return
			economy[peer] = credits - w.price
			lo[slot_key] = arg
			node.server_give_weapon(String(lo.primary), String(lo.secondary))
		"shield":
			var value := SHIELD_LIGHT_VALUE if arg == "light" else SHIELD_HEAVY_VALUE
			var price := SHIELD_LIGHT_PRICE if arg == "light" else SHIELD_HEAVY_PRICE
			if arg != "light" and arg != "heavy":
				_buy_result(peer, item, false, "item")
				return
			if int(node.armor) >= value:
				_buy_result(peer, item, false, "owned")
				return
			if credits < price:
				_buy_result(peer, item, false, "credits")
				return
			economy[peer] = credits - price
			lo.armor = value
			node.server_set_armor(value)
		"ability":
			var slot := int(arg)
			var agent := String(Net.players[peer].get("agent", AgentDB.DEFAULT_AGENT))
			var ab := AgentDB.ability(agent, slot)
			if ab == null or slot < 0 or slot > 2:
				_buy_result(peer, item, false, "item")
				return
			if ab.signature:
				_buy_result(peer, item, false, "signature")
				return
			var charges: Dictionary = lo.charges
			if int(charges.get(slot, 0)) >= ab.max_charges:
				_buy_result(peer, item, false, "max")
				return
			if credits < ab.cost:
				_buy_result(peer, item, false, "credits")
				return
			economy[peer] = credits - ab.cost
			charges[slot] = int(charges.get(slot, 0)) + 1
			node.server_set_charges(charges)
		_:
			_buy_result(peer, item, false, "item")
			return
	_buy_result(peer, item, true, "-")
	rpc("cl_economy", economy)


func _buy_result(peer: int, item: String, ok: bool, reason: String) -> void:
	if Cli.test_mode():
		print("[TEST] buy peer=%d item=%s %s reason=%s credits=%d" % [
			peer, item, "ok" if ok else "denied", reason, int(economy.get(peer, 0))])
	var node := _player_node(peer)
	if node != null:
		node.notify_buy_result(ok, reason)


# ------------------------------------------------------------------
# Plant/defuse interact input (client -> server)
# ------------------------------------------------------------------

func send_interact(held: bool) -> void:
	if multiplayer.is_server():
		srv_interact(held)
	else:
		rpc_id(1, "srv_interact", held)


@rpc("any_peer", "call_remote", "reliable")
func srv_interact(held: bool) -> void:
	if not multiplayer.is_server():
		return
	_interact_held[_sender()] = held


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return 1 if id == 0 else id


func _player_node(peer: int) -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("Players/%d" % peer)


# ------------------------------------------------------------------
# Kills / stats (both modes)
# ------------------------------------------------------------------

## Server-side kill bookkeeping. Victims may be non-player targets (dummies),
## so identity is passed explicitly; peer ids are 0 for non-players.
func server_report_kill(killer_name: String, killer_team: int, victim_name: String, victim_team: int, weapon_id: String, headshot: bool, killer_peer := 0, victim_peer := 0) -> void:
	if not multiplayer.is_server():
		return
	if killer_team != victim_team:
		match killer_team:
			Team.ATTACKERS: kills_a += 1
			Team.DEFENDERS: kills_b += 1
	rpc("cl_kill_feed", killer_name, victim_name, weapon_id, headshot, killer_team, kills_a, kills_b)
	if mode == Mode.TDM and match_running:
		if kills_a >= tdm_target:
			_server_end_match(Team.ATTACKERS)
		elif kills_b >= tdm_target:
			_server_end_match(Team.DEFENDERS)
		return
	if mode != Mode.SPIKE or not match_running:
		return
	# Stats + kill credits + assists.
	if victim_peer != 0:
		if not stats.has(victim_peer):
			stats[victim_peer] = {"k": 0, "d": 0, "a": 0}
		stats[victim_peer].d = int(stats[victim_peer].d) + 1
	if killer_peer != 0 and killer_peer != victim_peer and killer_team != victim_team:
		if not stats.has(killer_peer):
			stats[killer_peer] = {"k": 0, "d": 0, "a": 0}
		stats[killer_peer].k = int(stats[killer_peer].k) + 1
		_srv_award(killer_peer, CREDITS_KILL)
	if victim_peer != 0:
		var now := Time.get_ticks_msec()
		var dam: Dictionary = _recent_damage.get(victim_peer, {})
		for attacker: int in dam:
			if attacker == killer_peer or attacker == victim_peer or int(dam[attacker]) < now:
				continue
			if int(Net.players.get(attacker, {}).get("team", 0)) == victim_team:
				continue
			if stats.has(attacker):
				stats[attacker].a = int(stats[attacker].a) + 1
		_recent_damage.erase(victim_peer)
	rpc("cl_stats", stats)
	rpc("cl_economy", economy)
	if victim_peer != 0 and int(spike.get("carrier", 0)) == victim_peer and int(spike.get("state", -1)) == SpikeState.CARRIED:
		var node := _player_node(victim_peer)
		_drop_spike_at(node.global_position if node != null else Vector3.ZERO)
	_check_elimination()


## Assist tracking: called by the damage pipeline for player-vs-player damage.
func server_note_damage(victim_peer: int, attacker_peer: int) -> void:
	if not multiplayer.is_server() or attacker_peer == 0 or victim_peer == 0:
		return
	if not _recent_damage.has(victim_peer):
		_recent_damage[victim_peer] = {}
	_recent_damage[victim_peer][attacker_peer] = Time.get_ticks_msec() + ASSIST_WINDOW_MS


## Late joiner: give them a default economy/loadout entry (spawned dead
## mid-round by match.gd; they play from the next round).
func server_init_late_joiner(peer: int) -> void:
	if not multiplayer.is_server() or mode != Mode.SPIKE:
		return
	if not economy.has(peer):
		economy[peer] = CREDITS_START
	if not _loadouts.has(peer):
		_loadouts[peer] = _fresh_loadout()
		_refill_signatures(peer)
	if not stats.has(peer):
		stats[peer] = {"k": 0, "d": 0, "a": 0}
	rpc("cl_economy", economy)
	rpc("cl_stats", stats)


## Late joiner physical spawn: joins live during BUY, otherwise sits out
## (spawned dead) until the next round starts.
func server_spawn_late_joiner(peer: int) -> void:
	if not multiplayer.is_server() or mode != Mode.SPIKE or not match_running:
		return
	server_init_late_joiner(peer)
	var node := _player_node(peer)
	if node == null:
		return
	if phase == RoundPhase.BUY:
		var team := int(Net.players.get(peer, {}).get("team", Team.ATTACKERS))
		var tr: Transform3D = get_tree().current_scene.pick_spawn(team)
		node.server_round_spawn(tr.origin, tr.basis.get_euler().y, _loadouts[peer])
	else:
		node.server_spawn_dead()


## Late joiner state snapshot, sent when the peer has loaded the match scene.
func server_on_peer_ready(peer: int) -> void:
	if not multiplayer.is_server() or not match_running or peer == 1:
		return
	rpc_id(peer, "cl_sync", {
		"phase": phase, "time": match_time_left, "round": round_number,
		"score_att": score_att, "score_def": score_def,
		"spike": spike, "economy": economy, "stats": stats,
		"kills_a": kills_a, "kills_b": kills_b,
	})


# ------------------------------------------------------------------
# Replication RPCs (server -> clients)
# ------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func cl_phase(p: int, time_left: float, rnd: int, sa: int, sd: int) -> void:
	phase = p as RoundPhase
	match_time_left = time_left
	round_number = rnd
	score_att = sa
	score_def = sd
	phase_changed.emit(phase)
	team_scores_changed.emit()


@rpc("authority", "call_local", "reliable")
func cl_spike(s: Dictionary) -> void:
	spike = s
	spike_changed.emit()


@rpc("authority", "call_local", "reliable")
func cl_economy(e: Dictionary) -> void:
	economy = e
	economy_changed.emit()


@rpc("authority", "call_local", "reliable")
func cl_stats(s: Dictionary) -> void:
	stats = s
	stats_changed.emit()


@rpc("authority", "call_local", "unreliable_ordered")
func cl_progress(kind: int, value: float, total: float, peer: int) -> void:
	interact_progress.emit(kind, value, total, peer)


## 3D audio cue for plant/defuse start, audible in range of the position.
@rpc("authority", "call_local", "reliable")
func cl_spike_cue(kind: String, pos: Vector3) -> void:
	var path := "res://assets/audio/foley/cloth1.ogg" if kind == "plant" else "res://assets/audio/foley/metalLatch.ogg"
	if ResourceLoader.exists(path):
		Fx.play_sound_3d(get_tree().current_scene, load(path), pos + Vector3.UP, 2.0)


@rpc("authority", "call_local", "reliable")
func cl_round_end(winner: int, reason: String, sa: int, sd: int, rnd: int) -> void:
	phase = RoundPhase.ROUND_END
	match_time_left = cfg_round_end
	score_att = sa
	score_def = sd
	round_number = rnd
	team_scores_changed.emit()
	phase_changed.emit(phase)
	round_ended.emit(winner, reason)


@rpc("authority", "call_local", "reliable")
func cl_swap_teams(sa: int, sd: int) -> void:
	score_att = sa
	score_def = sd
	# The registry mirror arrived just before via Net.cl_players (same reliable
	# channel); sync the live nodes to it rather than blind-flipping.
	for node: Node in get_tree().get_nodes_in_group("players"):
		var pid: int = node.peer_id()
		if Net.players.has(pid):
			node.team = int(Net.players[pid].team)
		else:
			node.team = Team.DEFENDERS if int(node.team) == Team.ATTACKERS else Team.ATTACKERS
		if node.has_method("refresh_team_visuals"):
			node.refresh_team_visuals()
	team_scores_changed.emit()
	teams_swapped.emit()
	if Cli.test_mode() and local_player != null:
		print("[TEST] team_swapped my_team=%d" % int(local_player.team))


@rpc("authority", "call_remote", "reliable")
func cl_sync(s: Dictionary) -> void:
	phase = int(s.get("phase", RoundPhase.BUY)) as RoundPhase
	match_time_left = float(s.get("time", 0.0))
	round_number = int(s.get("round", 1))
	score_att = int(s.get("score_att", 0))
	score_def = int(s.get("score_def", 0))
	spike = s.get("spike", {})
	economy = s.get("economy", {})
	stats = s.get("stats", {})
	kills_a = int(s.get("kills_a", 0))
	kills_b = int(s.get("kills_b", 0))
	phase_changed.emit(phase)
	spike_changed.emit()
	economy_changed.emit()
	stats_changed.emit()
	team_scores_changed.emit()


@rpc("authority", "call_local", "reliable")
func cl_kill_feed(killer_name: String, victim_name: String, weapon_id: String, headshot: bool, killer_team: int, ka: int, kb: int) -> void:
	kills_a = ka
	kills_b = kb
	team_scores_changed.emit()
	kill_feed_event.emit(killer_name, victim_name, weapon_id, headshot, killer_team)
	print("[KILLFEED] %s -> %s (%s%s)  A:%d B:%d" % [killer_name, victim_name, weapon_id, ", HS" if headshot else "", ka, kb])
	if Cli.test_mode():
		print("[TEST] killfeed_received killer=%s victim=%s weapon=%s" % [killer_name, victim_name, weapon_id])


@rpc("authority", "call_remote", "unreliable")
func cl_time(t: float) -> void:
	match_time_left = t
	match_time_updated.emit()


func _leading_team() -> int:
	if kills_a > kills_b:
		return Team.ATTACKERS
	if kills_b > kills_a:
		return Team.DEFENDERS
	return Team.NONE


func _server_end_match(winning_team: int) -> void:
	if not match_running:
		return
	if mode == Mode.SPIKE:
		rpc("cl_match_end", winning_team, score_att, score_def)
	else:
		rpc("cl_match_end", winning_team, kills_a, kills_b)


@rpc("authority", "call_local", "reliable")
func cl_match_end(winning_team: int, a: int, b: int) -> void:
	match_running = false
	phase = RoundPhase.ROUND_END
	if mode == Mode.SPIKE:
		score_att = a
		score_def = b
	match_ended.emit(winning_team)
	print("[GAME] match over — %s win (%d-%d)" % [team_name(winning_team), a, b])
	if Cli.test_mode():
		print("[TEST] match_end winner=%d score=%d-%d" % [winning_team, a, b])
	get_tree().create_timer(8.0).timeout.connect(_return_to_menu)


func _return_to_menu() -> void:
	reset_match_state()
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path != "res://scenes/boot.tscn":
		get_tree().change_scene_to_file("res://scenes/boot.tscn")


func reset_match_state() -> void:
	match_running = false
	phase = RoundPhase.IDLE
	kills_a = 0
	kills_b = 0
	score_att = 0
	score_def = 0
	round_number = 0
	match_time_left = 0.0
	spike = {}
	economy = {}
	stats = {}
	_loadouts = {}
	local_player = null

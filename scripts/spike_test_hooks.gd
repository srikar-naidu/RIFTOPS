class_name SpikeTestHooks
extends Node
## Scripted spike-mode test orchestration (added by match.gd when
## --spike-script is present). Two scenarios, each with a host + client side:
##
##   a — full round loop: buy gating/deductions, scripted plant, defuse with
##       checkpoint interruption, loss-streak economy, halftime swap,
##       elimination + spike drop, timeout rounds, match end.
##   b — ability battery: every agent kit cast server-side through the real
##       pipeline + spike drop/pickup/plant/detonation (both players are
##       attackers; --carrier 1 forces the host to start with the spike).
##
## Everything asserts via "[TEST] ..." log markers that tests/spike_test.sh
## greps. Quits 0 on success, 3 on an internal wait timeout, 2 via autoquit.

var _defuse_val := 0.0


func _ready() -> void:
	print("[TEST] spike_hooks script=%s server=%s" % [Cli.value("spike-script", "a"), str(multiplayer.is_server())])
	GameState.interact_progress.connect(func(kind: int, value: float, _total: float, _peer: int) -> void:
		if kind == 1:
			_defuse_val = value)
	_run.call_deferred()


func _run() -> void:
	var which := Cli.value("spike-script", "a")
	if multiplayer.is_server():
		match which:
			"a": await _host_a()
			"c": await _host_c()
			_: await _host_b()
	else:
		match which:
			"a": await _client_a()
			"c": await _client_c()
			_: await _client_b()


# ------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _until(pred: Callable, timeout: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if pred.call():
			return true
		await _sleep(0.1)
	print("[TEST] FAIL wait=%s" % label)
	get_tree().quit(3)
	return false


func _p(peer: int) -> Player:
	return get_tree().current_scene.get_node_or_null("Players/%d" % peer) as Player


func _me() -> Player:
	return GameState.local_player as Player


func _in_phase(ph: int, rnd := -1) -> bool:
	return GameState.phase == ph and (rnd < 0 or GameState.round_number == rnd)


func _teleport_local(pos: Vector3) -> void:
	var me := _me()
	if me == null:
		return
	me.global_position = pos
	me.sync_position = pos
	me.velocity = Vector3.ZERO


func _teleport_server_player(p: Player, pos: Vector3) -> void:
	p.global_position = pos
	p.sync_position = pos
	p.velocity = Vector3.ZERO


func _zone_pos(group: String) -> Vector3:
	var nodes := get_tree().get_nodes_in_group(group)
	if nodes.is_empty():
		return Vector3.ZERO
	return (nodes[0] as Node3D).global_position


func _other_peer() -> int:
	for id: int in Net.players:
		if id != 1:
			return id
	return 0


# ------------------------------------------------------------------
# Scenario A — rounds / economy / plant / defuse / halftime / match end
# ------------------------------------------------------------------

func _host_a() -> void:
	if not await _until(func() -> bool: return get_tree().get_nodes_in_group("players").size() >= 2, 20.0, "players"):
		return
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.BUY, 1), 10.0, "r1_buy"):
		return
	await _sleep(0.5)
	GameState.srv_buy("weapon:sheriff")            # 800 -> 0 (deduct assert)
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.ACTIVE, 1), 15.0, "r1_live"):
		return
	GameState.srv_buy("shield:light")              # denied: phase gate assert
	# Scripted plant: walk (teleport) into site A, hold interact.
	var host := _p(1)
	_teleport_server_player(host, _zone_pos("plant_zone_a") + Vector3(0, 0.1, 0))
	await _sleep(0.4)
	GameState.srv_interact(true)
	if not await _until(func() -> bool: return GameState.phase == GameState.RoundPhase.PLANTED, 12.0, "planted"):
		return
	GameState.srv_interact(false)
	# Client defuses (with checkpoint interruption) -> defenders win round 1.
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.ROUND_END, 1), 20.0, "r1_end"):
		return
	# Round 2: nobody moves -> defender win by timeout (loss streak 2 for attackers).
	# Round 3 (post-halftime): host is now a DEFENDER; kill the attacking client
	# (who is the sole attacker and spike carrier) -> spike drop + elimination.
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.ACTIVE, 3), 90.0, "r3_live"):
		return
	await _sleep(1.5)  # client teleports itself to a known spot
	var victim := _p(_other_peer())
	if victim != null:
		for i in 12:
			if not victim.alive or GameState.phase != GameState.RoundPhase.ACTIVE:
				break
			_p(1).server_test_fire(victim.global_position + Vector3.UP * 1.1)
			await _sleep(0.35)
	# Rounds 4 + 5 run out by timeout; the host's team reaches 3 -> match end.
	if not await _until(func() -> bool: return not GameState.match_running and GameState.round_number >= 5, 180.0, "match_end"):
		return
	print("[TEST] HOST_OK")
	await _sleep(0.8)
	get_tree().quit(0)


func _client_a() -> void:
	if not await _until(func() -> bool: return get_tree().get_nodes_in_group("players").size() >= 2, 25.0, "players"):
		return
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.BUY, 1), 10.0, "r1_buy"):
		return
	await _sleep(0.6)
	GameState.request_buy("weapon:vandal")   # denied: credits (2900 > 800)
	await _sleep(0.3)
	GameState.request_buy("weapon:spectre")  # denied: credits (1600 > 800)
	await _sleep(0.3)
	GameState.request_buy("shield:light")    # ok: 800 -> 400, armor 25
	# Defuse round 1 with a checkpoint interruption.
	if not await _until(func() -> bool: return GameState.phase == GameState.RoundPhase.PLANTED, 30.0, "planted"):
		return
	await _sleep(0.3)
	var spike_pos: Vector3 = GameState.spike.get("pos", Vector3.ZERO)
	_teleport_local(spike_pos + Vector3(0.4, 0.05, 0))
	await _sleep(0.5)
	_defuse_val = 0.0
	GameState.send_interact(true)
	if not await _until(func() -> bool: return _defuse_val >= 4.0, 8.0, "defuse_past_checkpoint"):
		return
	GameState.send_interact(false)           # release past the 3.5s checkpoint
	await _sleep(0.6)
	GameState.send_interact(true)            # resume from 3.5 -> completes
	if not await _until(func() -> bool: return GameState.phase == GameState.RoundPhase.ROUND_END, 10.0, "defused"):
		return
	GameState.send_interact(false)
	# Round 3: post-halftime we are the (sole) attacker; stand still and die.
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.ACTIVE, 3), 90.0, "r3_live"):
		return
	_teleport_local(Vector3(0, 0.1, 8))
	if not await _until(func() -> bool: return not GameState.match_running and GameState.round_number >= 5, 180.0, "match_end"):
		return
	print("[TEST] CLIENT_OK")
	await _sleep(0.5)
	get_tree().quit(0)


# ------------------------------------------------------------------
# Scenario B — ability battery + spike drop/pickup/plant/detonation
# ------------------------------------------------------------------

func _host_b() -> void:
	if not await _until(func() -> bool: return get_tree().get_nodes_in_group("players").size() >= 2, 20.0, "players"):
		return
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.BUY, 1), 10.0, "r1_buy"):
		return
	await _sleep(0.5)
	GameState.srv_buy("ability:2")           # gale cloudburst charge: 800 -> 600
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.ACTIVE, 1), 15.0, "r1_live"):
		return
	var dummy := DummyTarget.new()
	dummy.name = "Dummy"
	add_sibling(dummy)
	dummy.global_position = Vector3(6, 0, 18)
	print("[TEST] dummy_spawned at %s" % str(dummy.global_position))
	await _sleep(1.0)  # client teleports itself to (0, 0.1, 10)

	var host := _p(1)
	var client := _p(_other_peer())
	var ctrl := host.abilities

	# --- GALE ---
	ctrl.server_force_agent("gale")
	_teleport_server_player(host, Vector3(-6, 0.1, 2))
	await _sleep(0.3)
	var before := host.global_position
	ctrl.server_test_cast(0)                                     # dash
	await _sleep(0.6)
	print("[TEST] dash_displaced=%.1f" % before.distance_to(host.global_position))
	ctrl.server_test_cast(1)                                     # updraft
	await _sleep(0.35)
	print("[TEST] updraft_y=%.2f" % host.global_position.y)
	await _sleep(0.8)
	ctrl.server_test_cast(2, Vector3.ZERO, Vector3(1, 0.25, 0))  # cloudburst smoke
	await _sleep(2.0)

	# --- EMBER ---
	ctrl.server_force_agent("ember")
	_teleport_server_player(host, Vector3(6, 0.1, 4))
	await _sleep(0.3)
	ctrl.server_test_cast(0, Vector3(-20, 0, -15))   # sky smoke (map target, away from the client so it can't block the later flash LOS)
	var eye := host.global_position + Vector3.UP * Player.STAND_EYE
	ctrl.server_test_cast(1, Vector3.ZERO, (client.global_position - eye).normalized())  # molly at client
	await _sleep(2.6)                                            # molly ticks (ally half)
	ctrl.server_test_cast(2, Vector3.ZERO, Vector3(0.2, -0.4, 0.4))       # stim beacon nearby
	await _sleep(1.2)
	host.server_test_fire(Vector3(6, 1.2, 18))                   # stim-buffed shot at dummy
	await _sleep(0.8)

	# --- WARDEN ---
	ctrl.server_force_agent("warden")
	_teleport_server_player(host, Vector3(6, 0.1, 12))
	await _sleep(0.3)
	ctrl.server_test_cast(0, Vector3.ZERO, Vector3(0, 0, 1))     # wall toward dummy (z=15.5)
	await _sleep(0.5)
	host.server_test_fire(Vector3(6, 1.2, 18))                   # blocked -> wall_hit
	await _sleep(0.3)
	host.server_test_fire(Vector3(6, 1.2, 18))
	await _sleep(0.5)
	eye = host.global_position + Vector3.UP * Player.STAND_EYE
	ctrl.server_test_cast(1, Vector3.ZERO, (client.global_position - eye).normalized())  # slow orb at client
	await _sleep(1.2)
	host.take_damage_server(60, HitboxRegion.Region.BODY, dummy, WeaponDB.get_weapon(&"classic"))
	await _sleep(0.2)
	ctrl.server_test_cast(2, Vector3.ZERO, Vector3.UP)           # heal self
	await _sleep(1.6)                                            # heal ticks

	# --- FLINT ---
	ctrl.server_force_agent("flint")
	_teleport_server_player(host, Vector3(-5, 0.1, 8))
	await _sleep(0.3)
	eye = host.global_position + Vector3.UP * Player.STAND_EYE
	ctrl.server_test_cast(0, Vector3.ZERO, (client.global_position + Vector3.UP * 1.5 - eye).normalized())  # flash near client
	await _sleep(1.2)
	_teleport_server_player(host, Vector3(12, 0.1, 14))  # angle that clears the test wall
	await _sleep(0.2)
	eye = host.global_position + Vector3.UP * Player.STAND_EYE
	ctrl.server_test_cast(1, Vector3.ZERO, (dummy.global_position - eye).normalized())   # recon at dummy
	await _sleep(2.2)                                            # 2 pulses
	eye = host.global_position + Vector3.UP * Player.STAND_EYE
	ctrl.server_test_cast(2, Vector3.ZERO, (client.global_position - eye).normalized())  # concuss at client
	await _sleep(1.6)

	# --- spike drop -> client pickup -> client plants -> detonation ---
	host.take_damage_server(999, HitboxRegion.Region.BODY, dummy, WeaponDB.get_weapon(&"classic"))
	if not await _until(func() -> bool: return int(GameState.spike.get("state", -1)) == GameState.SpikeState.PLANTED, 30.0, "client_plant"):
		return
	if not await _until(func() -> bool: return int(GameState.spike.get("state", -1)) == GameState.SpikeState.DETONATED, GameState.cfg_detonate + 8.0, "detonation"):
		return
	print("[TEST] HOST_OK")
	await _sleep(0.8)
	get_tree().quit(0)


# ------------------------------------------------------------------
# Scenario C — 3-instance full round flow on the real map (Solstice):
# host (attacker, forced carrier) + attacker client + defender client.
# Round 1: buys, host plants on A, defender defuses -> defender win.
# Round 2: host plants again, nobody defuses -> detonation -> attacker win.
# ------------------------------------------------------------------

func _host_c() -> void:
	if not await _until(func() -> bool: return get_tree().get_nodes_in_group("players").size() >= 3, 25.0, "players3"):
		return
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.BUY, 1), 10.0, "r1_buy"):
		return
	await _sleep(0.5)
	GameState.srv_buy("weapon:sheriff")            # 800 -> 0
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.ACTIVE, 1), 15.0, "r1_live"):
		return
	await _plant_here()
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.ROUND_END, 1), 25.0, "r1_end"):
		return
	# Round 2: plant again and let it detonate.
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.ACTIVE, 2), 20.0, "r2_live"):
		return
	await _plant_here()
	if not await _until(func() -> bool:
		return int(GameState.spike.get("state", -1)) == GameState.SpikeState.DETONATED, GameState.cfg_detonate + 10.0, "detonation"):
		return
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.ROUND_END, 2), 10.0, "r2_end"):
		return
	print("[TEST] HOST_OK")
	await _sleep(1.5)
	get_tree().quit(0)


func _plant_here() -> void:
	var host := _p(1)
	_teleport_server_player(host, _zone_pos("plant_zone_a") + Vector3(0, 0.1, 0))
	await _sleep(0.5)
	GameState.srv_interact(true)
	await _until(func() -> bool: return GameState.phase == GameState.RoundPhase.PLANTED, 12.0, "planted")
	GameState.srv_interact(false)


func _client_c() -> void:
	if not await _until(func() -> bool: return get_tree().get_nodes_in_group("players").size() >= 3, 30.0, "players3"):
		return
	if not await _until(func() -> bool: return Net.players.has(Net.my_id()), 10.0, "registered"):
		return
	var team := int(Net.players[Net.my_id()].get("team", 0))
	print("[TEST] c_role team=%d" % team)
	if team == GameState.Team.ATTACKERS:
		await _client_c_attacker()
	else:
		await _client_c_defender()


func _client_c_attacker() -> void:
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.BUY, 1), 10.0, "r1_buy"):
		return
	await _sleep(0.6)
	GameState.request_buy("shield:light")          # 800 -> 400
	# Stay at spawn; win round 2 via detonation.
	if not await _until(func() -> bool:
		return GameState.round_number >= 2 and GameState.phase == GameState.RoundPhase.ROUND_END, 150.0, "r2_end"):
		return
	print("[TEST] CLIENT_OK")
	await _sleep(0.5)
	get_tree().quit(0)


func _client_c_defender() -> void:
	# Round 1: full defuse (no interruption).
	if not await _until(func() -> bool: return GameState.phase == GameState.RoundPhase.PLANTED and GameState.round_number == 1, 45.0, "r1_planted"):
		return
	await _sleep(0.3)
	var spike_pos: Vector3 = GameState.spike.get("pos", Vector3.ZERO)
	_teleport_local(spike_pos + Vector3(0.4, 0.05, 0))
	await _sleep(0.6)
	GameState.send_interact(true)
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.ROUND_END, 1), 12.0, "defused"):
		return
	GameState.send_interact(false)
	# Round 2: stay far away so the spike detonates.
	if not await _until(func() -> bool: return GameState.phase == GameState.RoundPhase.PLANTED and GameState.round_number == 2, 60.0, "r2_planted"):
		return
	var away: Vector3 = GameState.spike.get("pos", Vector3.ZERO) + Vector3(25, 0.1, 25)
	_teleport_local(away)
	if not await _until(func() -> bool:
		return GameState.round_number >= 2 and GameState.phase == GameState.RoundPhase.ROUND_END, 60.0, "r2_end"):
		return
	print("[TEST] CLIENT_OK")
	await _sleep(0.5)
	get_tree().quit(0)


func _client_b() -> void:
	if not await _until(func() -> bool: return get_tree().get_nodes_in_group("players").size() >= 2, 25.0, "players"):
		return
	if not await _until(func() -> bool: return _in_phase(GameState.RoundPhase.ACTIVE, 1), 20.0, "r1_live"):
		return
	_teleport_local(Vector3(0, 0.1, 10))  # battery target spot
	# Wait for the carrier (host) to die and the spike to drop, then recover it.
	if not await _until(func() -> bool: return int(GameState.spike.get("state", -1)) == GameState.SpikeState.DROPPED, 90.0, "spike_dropped"):
		return
	await _sleep(0.3)
	var pos: Vector3 = GameState.spike.get("pos", Vector3.ZERO)
	_teleport_local(Vector3(pos.x, pos.y + 0.05, pos.z))
	if not await _until(func() -> bool:
		return int(GameState.spike.get("carrier", 0)) == Net.my_id() \
			and int(GameState.spike.get("state", -1)) == GameState.SpikeState.CARRIED, 10.0, "pickup"):
		return
	# Plant it and let it detonate.
	_teleport_local(_zone_pos("plant_zone_a") + Vector3(0, 0.1, 0))
	await _sleep(0.5)
	GameState.send_interact(true)
	if not await _until(func() -> bool: return GameState.phase == GameState.RoundPhase.PLANTED, 12.0, "plant"):
		return
	GameState.send_interact(false)
	if not await _until(func() -> bool: return int(GameState.spike.get("state", -1)) == GameState.SpikeState.DETONATED, GameState.cfg_detonate + 8.0, "detonation"):
		return
	print("[TEST] CLIENT_OK")
	await _sleep(0.5)
	get_tree().quit(0)

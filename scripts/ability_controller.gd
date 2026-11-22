class_name AbilityController
extends Node
## Per-player ability state + cast pipeline. Lives inside player.tscn on
## every peer (stable path => RPCs allowed here, same ownership rules as the
## Player combat RPCs). Charges are server-authoritative and mirrored to the
## owner via cl_charges; casts are validated server-side and executed by the
## EffectsManager. Slots 0/1/2 bind to ability_1 (Q) / ability_2 (E) /
## ability_3 (X).

signal charges_changed(charges: Array)
signal map_target_requested(slot: int)
signal cast_denied(reason: String)

var player: Player = null
## Owner: local mirror. Server: authoritative charge counts.
var charges: Array[int] = [0, 0, 0]


func setup(p: Player) -> void:
	player = p
	if not player.is_local():
		set_process(false)


func agent_data() -> AgentData:
	return AgentDB.get_agent(StringName(player.agent_id))


func ability(slot: int) -> AbilityData:
	var a := agent_data()
	return a.ability(slot) if a != null else null


func _process(_delta: float) -> void:
	if player == null or not player.is_local() or not player.alive:
		return
	if not Settings.gameplay_input_active():
		return
	for slot in 3:
		if Input.is_action_just_pressed("ability_%d" % (slot + 1)):
			try_cast(slot)


## Local entry point (input / HUD). Map-targeted abilities detour through the
## targeting overlay, which calls cast_at() with a world position.
func try_cast(slot: int) -> void:
	if GameState.mode == GameState.Mode.FFA:
		return
	var ab := ability(slot)
	if ab == null:
		return
	if charges[slot] <= 0:
		cast_denied.emit("no_charges")
		return
	if GameState.phase != GameState.RoundPhase.ACTIVE and GameState.phase != GameState.RoundPhase.PLANTED:
		cast_denied.emit("phase")
		return
	if ab.map_targeted:
		map_target_requested.emit(slot)
		return
	_send(slot, player.eye_position(), player.aim_direction(), Vector3.ZERO)


func cast_at(slot: int, world_target: Vector3) -> void:
	_send(slot, player.eye_position(), player.aim_direction(), world_target)


func _send(slot: int, origin: Vector3, dir: Vector3, target: Vector3) -> void:
	if multiplayer.is_server():
		_server_cast(slot, origin, dir, target)
	else:
		rpc_id(1, "srv_cast", slot, origin, dir, target)


@rpc("any_peer", "call_remote", "reliable")
func srv_cast(slot: int, origin: Vector3, dir: Vector3, target: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != player.peer_id():
		return
	_server_cast(slot, origin, dir, target)


func _server_cast(slot: int, origin: Vector3, dir: Vector3, target: Vector3) -> void:
	if GameState.mode == GameState.Mode.FFA or not player.alive or not GameState.match_running:
		return
	if GameState.phase != GameState.RoundPhase.ACTIVE and GameState.phase != GameState.RoundPhase.PLANTED:
		return
	var ab := ability(slot)
	if ab == null or slot < 0 or slot > 2 or charges[slot] <= 0:
		return
	var eye := player.global_position + Vector3.UP * Player.STAND_EYE
	if origin.distance_to(eye) > 3.0:
		origin = eye
	if dir.length_squared() < 0.5:
		dir = -player.head.global_basis.z
	dir = dir.normalized()
	var fx := get_tree().get_first_node_in_group("effects_manager")
	if fx == null:
		return
	var ok: bool = fx.server_execute(player, ab, origin, dir, target)
	if Cli.test_mode():
		print("[TEST] cast peer=%d ability=%s %s" % [player.peer_id(), String(ab.id), "ok" if ok else "denied"])
	if not ok:
		return
	charges[slot] -= 1
	_sync_owner()
	if String(ab.id) == "dash" or String(ab.id) == "updraft":
		_owner_call("cl_cast_motion", [String(ab.id)])


## Server: apply full charge dict (round spawn / buy).
func server_set_charges(d: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	for slot in 3:
		charges[slot] = int(d.get(slot, 0))
	_sync_owner()


## Test-only: swap this player's agent server-side and refill all charges so
## the scripted ability battery can exercise every kit in one round.
func server_force_agent(agent: String) -> void:
	if not multiplayer.is_server() or not AgentDB.is_valid(agent):
		return
	player.agent_id = agent
	if Net.players.has(player.peer_id()):
		Net.players[player.peer_id()].agent = agent
	for slot in 3:
		var ab := ability(slot)
		charges[slot] = ab.max_charges if ab != null else 0
	_sync_owner()


## Test-only: server-side scripted cast through the real validation pipeline.
func server_test_cast(slot: int, target := Vector3.ZERO, dir := Vector3.ZERO) -> void:
	if not multiplayer.is_server():
		return
	var origin := player.global_position + Vector3.UP * Player.STAND_EYE
	if dir.length_squared() < 0.5:
		dir = -player.head.global_basis.z if player.head != null else -player.global_basis.z
	_server_cast(slot, origin, dir.normalized(), target)


func _sync_owner() -> void:
	_owner_call("cl_charges", [charges])


func _owner_call(method: StringName, args: Array) -> void:
	if player.peer_id() == 1:
		callv(method, args)
	else:
		callv("rpc_id", [player.peer_id(), method] + args)


@rpc("authority", "call_remote", "reliable")
func cl_charges(arr: Array) -> void:
	for slot in mini(arr.size(), 3):
		charges[slot] = int(arr[slot])
	charges_changed.emit(charges)


## Dash/updraft are movement: the owner applies them locally after the server
## validated + consumed the charge (movement is owner-authoritative).
@rpc("authority", "call_remote", "reliable")
func cl_cast_motion(ability_id: String) -> void:
	if ability_id == "dash":
		player.apply_dash()
	else:
		player.apply_updraft()

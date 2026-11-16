extends Node3D
## Match scene root. Loads the map, spawns players (server), runs TDM
## respawns and the physical side of Spike rounds (barriers, spike entity,
## round spawn positions). Spawning waits until every registered peer has
## loaded the scene (clients report in via srv_client_ready) so
## MultiplayerSpawner replication never races scene loading.
##
## Late-join safety: player MoveSync ships with public_visibility=false; the
## server opens per-peer visibility only for peers that reported ready, so
## the spawner never sends nodes to a peer that hasn't loaded the scene yet.

const PLAYER_SCENE := preload("res://scenes/player.tscn")

var _ready_peers: Dictionary = {}
var _spawned := false

@onready var map_root: Node3D = $MapRoot
@onready var players_root: Node3D = $Players


func _ready() -> void:
	var map_res: PackedScene = load(GameState.map_path) as PackedScene
	if map_res != null:
		map_root.add_child(map_res.instantiate())
	else:
		push_error("Match: could not load map '%s'" % GameState.map_path)
	if GameState.mode == GameState.Mode.SPIKE:
		var spike := SpikeEntity.new()
		spike.name = "SpikeEntity"
		add_child(spike)
		GameState.phase_changed.connect(_on_phase_changed)
		_set_buy_barriers_enabled(true)  # round 1 starts in BUY
	else:
		_set_buy_barriers_enabled(false)
	if Cli.test_mode():
		if Cli.has_flag("spike-script"):
			var shooks := SpikeTestHooks.new()
			shooks.name = "SpikeTestHooks"
			add_child(shooks)
		else:
			var hooks := TestHooks.new()
			hooks.name = "TestHooks"
			add_child(hooks)
	if DisplayServer.get_name() != "headless" and not Settings.touch_enabled():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if multiplayer.is_server():
		Net.player_left.connect(_on_player_left)
		get_tree().create_timer(8.0).timeout.connect(func() -> void:
			if not _spawned:
				_spawn_all())
		_mark_ready(1)
	else:
		rpc_id(1, "srv_client_ready")


func _on_phase_changed(p: int) -> void:
	_set_buy_barriers_enabled(p == GameState.RoundPhase.BUY)


func _set_buy_barriers_enabled(enabled: bool) -> void:
	for group: String in ["buy_barrier_attacker", "buy_barrier_defender"]:
		for n: Node in get_tree().get_nodes_in_group(group):
			if n is Node3D:
				(n as Node3D).visible = enabled
			if n is CollisionObject3D:
				(n as CollisionObject3D).collision_layer = 1 if enabled else 0
	if Cli.test_mode() and multiplayer.is_server():
		print("[TEST] barriers enabled=%s phase=%s" % [str(enabled), GameState.phase_name(GameState.phase)])


@rpc("any_peer", "call_remote", "reliable")
func srv_client_ready() -> void:
	if not multiplayer.is_server():
		return
	_mark_ready(multiplayer.get_remote_sender_id())


func _mark_ready(id: int) -> void:
	_ready_peers[id] = true
	if _spawned:
		# Late joiner: reveal all existing players to them, then spawn theirs.
		_set_peer_visibility(id)
		_spawn_player(id)
		GameState.server_on_peer_ready(id)
		if GameState.mode == GameState.Mode.SPIKE:
			GameState.server_spawn_late_joiner(id)
	elif _all_ready():
		_spawn_all()


func _set_peer_visibility(peer: int) -> void:
	if peer == 1:
		return
	for node: Node in players_root.get_children():
		var sync := node.get_node_or_null("MoveSync") as MultiplayerSynchronizer
		if sync != null:
			sync.set_visibility_for(peer, true)


func _all_ready() -> bool:
	for pid: int in Net.players:
		if not _ready_peers.has(pid):
			return false
	return true


func _spawn_all() -> void:
	if _spawned:
		return
	_spawned = true
	for id: int in Net.players:
		if _ready_peers.has(id):
			_spawn_player(id)
	if GameState.mode == GameState.Mode.SPIKE and multiplayer.is_server():
		GameState.server_begin_spike()


func _spawn_player(id: int) -> void:
	if not multiplayer.is_server() or players_root.has_node(str(id)):
		return
	var info: Dictionary = Net.players.get(id, {})
	var p: Player = PLAYER_SCENE.instantiate()
	p.name = str(id)
	p.player_name = String(info.get("name", "Player"))
	p.team = int(info.get("team", GameState.Team.ATTACKERS))
	p.primary_id = String(info.get("primary", "vandal"))
	p.secondary_id = String(info.get("secondary", "classic"))
	p.agent_id = String(info.get("agent", AgentDB.DEFAULT_AGENT))
	if GameState.mode == GameState.Mode.SPIKE:
		p.primary_id = ""
		p.secondary_id = "classic"
	var tr := pick_spawn(p.team)
	p.position = tr.origin
	p.sync_position = tr.origin
	var yaw := tr.basis.get_euler().y
	p.rotation = Vector3(0, yaw, 0)
	p.sync_yaw = yaw
	players_root.add_child(p, true)
	# Open replication only toward peers that have the scene loaded.
	var sync := p.get_node("MoveSync") as MultiplayerSynchronizer
	for pid: int in _ready_peers:
		if pid != 1:
			sync.set_visibility_for(pid, true)
	# The owner's copy never receives spawn state (it owns the synchronizer),
	# so push identity/team/loadout/position to it explicitly.
	if id != 1:
		p.rpc_id(id, "cl_identity", p.player_name, p.team, p.primary_id, p.secondary_id,
			p.agent_id, p.position, p.rotation.y)
	p.server_died.connect(_on_player_died)


## Spawn transform for a team; deterministic when idx >= 0 (round starts),
## random otherwise (TDM respawns).
func pick_spawn(team: int, idx: int = -1) -> Transform3D:
	var group := "spawn_attacker" if team == GameState.Team.ATTACKERS else "spawn_defender"
	var markers := get_tree().get_nodes_in_group(group)
	if markers.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0))
	var pick := idx % markers.size() if idx >= 0 else randi() % markers.size()
	var m: Node3D = markers[pick] as Node3D
	var t := m.global_transform
	t.origin += Vector3.UP * 0.1
	return t


func _on_player_died(pid: int) -> void:
	if not GameState.match_running or GameState.mode != GameState.Mode.TDM:
		return
	get_tree().create_timer(GameState.TDM_RESPAWN_DELAY).timeout.connect(func() -> void:
		if not GameState.match_running:
			return
		var node: Player = players_root.get_node_or_null(str(pid)) as Player
		if node != null:
			var tr := pick_spawn(node.team)
			node.server_respawn(tr.origin, tr.basis.get_euler().y))


func _on_player_left(pid: int) -> void:
	var node := players_root.get_node_or_null(str(pid))
	if node != null:
		node.queue_free()

class_name TestHooks
extends Node
## Automated-test orchestration inside a running match. Added by match.gd when
## any test CLI flag is present. Prints "[TEST] ..." markers that
## tests/two_instance_test.sh greps, then quits with a meaningful exit code.

var expected_players := 2

var _saw_killfeed := false
var _dummy: DummyTarget = null


func _ready() -> void:
	print("[TEST] match_started map=%s mode=%d server=%s" % [GameState.map_path, GameState.mode, str(multiplayer.is_server())])
	GameState.kill_feed_event.connect(_on_killfeed)
	_run.call_deferred()


func _on_killfeed(_killer: String, _victim: String, _weapon: String, _hs: bool, _team: int) -> void:
	_saw_killfeed = true


func _run() -> void:
	var expected := Cli.value_int("expect-players", expected_players)
	var deadline := Time.get_ticks_msec() + 20000
	while get_tree().get_nodes_in_group("players").size() < expected and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.25).timeout
	var count := get_tree().get_nodes_in_group("players").size()
	print("[TEST] players_in_tree=%d" % count)
	if count < expected:
		print("[TEST] FAIL not enough players (want %d)" % expected)
		get_tree().quit(3)
		return

	if multiplayer.is_server():
		await _run_server_side(count)
	else:
		await _run_client_side()


func _run_server_side(count: int) -> void:
	if Cli.has_flag("spawn-dummy"):
		_dummy = DummyTarget.new()
		_dummy.name = "Dummy"
		add_sibling(_dummy)
		_dummy.global_position = Vector3(0, 0, 10)
		print("[TEST] dummy_spawned at %s" % str(_dummy.global_position))
	if Cli.has_flag("test-shot") and _dummy != null:
		await get_tree().create_timer(1.0).timeout
		var host_player: Player = get_tree().current_scene.get_node_or_null("Players/1") as Player
		if host_player == null:
			print("[TEST] FAIL no host player node")
			get_tree().quit(4)
			return
		for i in 8:
			if not _dummy.alive:
				break
			host_player.server_test_fire(_dummy.global_position + Vector3.UP * 1.25)
			await get_tree().create_timer(0.6).timeout
	var deadline := Time.get_ticks_msec() + 6000
	while not _saw_killfeed and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.25).timeout
	if _saw_killfeed and count >= Cli.value_int("expect-players", expected_players):
		print("[TEST] HOST_OK")
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)
	else:
		print("[TEST] HOST_FAIL killfeed=%s players=%d" % [str(_saw_killfeed), count])
		get_tree().quit(4)


func _run_client_side() -> void:
	var deadline := Time.get_ticks_msec() + 25000
	while not _saw_killfeed and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.25).timeout
	if _saw_killfeed:
		print("[TEST] CLIENT_OK")
		await get_tree().create_timer(0.4).timeout
		get_tree().quit(0)
	else:
		print("[TEST] CLIENT_FAIL no killfeed received")
		get_tree().quit(5)

extends SceneTree
## Real ENet integration: two processes, equal team IDs, damage, stats, respawn and end.
var state: Node
var net: Node
var finished := false
func _init() -> void:
	_run.call_deferred()

func fail(message: String) -> void:
	push_error("FFA FAIL: " + message)
	finished = true
	quit(1)

func _run() -> void:
	state = root.get_node("GameState")
	net = root.get_node("Net")
	create_timer(35).timeout.connect(func():
		if not finished: fail("timeout"))
	change_scene_to_file("res://scenes/boot.tscn")
	await process_frame
	await process_frame
	var hosting := "--ffa-host" in OS.get_cmdline_user_args()
	if hosting:
		if net.host_game(28123) != OK:
			fail("host bind")
			return
		while net.players.size() < 2:
			await create_timer(.1).timeout
		state.host_start_match("res://maps/testsite07/testsite07.tscn",2,5,2)
	else:
		net.join_game("127.0.0.1",28123)
	while current_scene == null or current_scene.scene_file_path != "res://scenes/match.tscn":
		await process_frame
	while current_scene.get_node("Players").get_child_count() < 2:
		await create_timer(.1).timeout
	await create_timer(1).timeout
	if hosting:
		var host: Node = current_scene.get_node("Players/1")
		var victim: Node
		for p in current_scene.get_node("Players").get_children():
			if p.name != "1": victim = p
		if host.team != 0 or victim.team != 0:
			fail("FFA assigned a team")
			return
		var weapon = load("res://weapons/vandal.tres")
		victim.take_damage_server(100,1,host,weapon)
		if victim.alive or int(state.stats.get(1,{}).get("k",0)) != 1:
			fail("equal-team FFA damage or score failed")
			return
		await create_timer(3.5).timeout
		if not victim.alive or victim.health != 100:
			fail("respawn failed")
			return
		victim.server_respawn(Vector3(0,.2,-5),0)
		host.server_respawn(Vector3(0,.2,2),0)
		await create_timer(1.3).timeout
		for shot in range(8):
			if not is_instance_valid(victim) or not victim.alive: break
			host.server_test_fire(victim.global_position + Vector3.UP*1.25)
			await create_timer(.2).timeout
		if state.match_running:
			fail("kill limit did not end match")
			return
		await create_timer(1).timeout
		print("FFA HOST PASS: equal-team damage, kills, respawn, kill limit")
	else:
		while state.match_running:
			await create_timer(.1).timeout
		if int(state.stats.get(1,{}).get("k",0)) != 2:
			fail("client final score not replicated")
			return
		if int(state.stats.get(net.my_id(),{}).get("d",0)) != 2:
			fail("client deaths not replicated")
			return
		print("FFA CLIENT PASS: replicated kills, deaths, match end")
		await create_timer(2).timeout
	finished = true
	state.reset_match_state()
	net.leave()
	change_scene_to_file("res://scenes/boot.tscn")
	await process_frame
	await process_frame
	quit(0)



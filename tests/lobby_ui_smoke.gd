extends SceneTree
## Integration smoke: the real lobby Play and Leave controls preserve session flow.
func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	change_scene_to_file("res://scenes/boot.tscn")
	await process_frame
	await process_frame
	var net: Node = root.get_node("Net")
	var state: Node = root.get_node("GameState")
	if net.host_game(28112) != OK:
		push_error("Lobby smoke could not bind test port")
		quit(1)
		return
	current_scene.call("_show_lobby")
	var lobby: Control = current_scene.get("lobby")
	if not lobby.visible or lobby.find_children("*", "OptionButton", true, false).size() != 0:
		push_error("Lobby is hidden or still contains selectors")
		quit(1)
		return
	var play: Button = lobby.get("_play")
	if play.disabled:
		push_error("Host Play control is disabled")
		quit(1)
		return
	play.pressed.emit()
	await process_frame
	await process_frame
	if current_scene.scene_file_path != "res://scenes/match.tscn" or not state.match_running:
		push_error("Play did not enter a running match")
		quit(1)
		return
	if current_scene.get_node("MapRoot").get_child(0).name != "Solstice":
		push_error("Play loaded the wrong arena")
		quit(1)
		return
	state.reset_match_state()
	change_scene_to_file("res://scenes/boot.tscn")
	await process_frame
	await process_frame
	lobby = current_scene.get("lobby")
	if not lobby.visible:
		push_error("Active session did not return to lobby")
		quit(1)
		return
	lobby.emit_signal("leave_requested")
	if net.is_active() or lobby.visible:
		push_error("Leave did not close the session and room")
		quit(1)
		return
	print("LOBBY UI SMOKE: PASS (no selectors, host Play, Solstice, return, Leave)")
	quit(0)

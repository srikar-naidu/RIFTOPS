class_name ScreenshotProbe
extends Node
## Dev/verification tool (created by GameState when --screenshot is passed).
## Waits for the match (when hosting) plus --shot-delay seconds, optionally
## forces a viewmodel / opens a UI, saves a PNG of the viewport and prints
## the render perf counters, then quits. Windowed runs only.
##
##   --screenshot <abs path>   output PNG
##   --shot-delay <sec>        wait after boot/match start (default 3)
##   --shot-in-match           wait for the match + local player spawn first
##   --shot-ui <buy|score>     open the buy menu / scoreboard first
##   --shot-weapon <id>        force the local first-person weapon
##   --shot-stay               don't quit after capturing (for multi-probe runs)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := Cli.value("screenshot", "")
	var delay := float(Cli.value("shot-delay", "3"))
	if Cli.has_flag("shot-in-match"):
		if not GameState.match_running:
			await GameState.match_started
		# Wait for the local player to spawn.
		var deadline := Time.get_ticks_msec() + 15000
		while GameState.local_player == null and Time.get_ticks_msec() < deadline:
			await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(delay).timeout

	var wid := Cli.value("shot-weapon", "")
	if wid != "" and GameState.local_player != null:
		var p := GameState.local_player as Player
		p.weapons.set_loadout(wid, "classic")
		await get_tree().create_timer(1.2).timeout  # equip dip settles

	if Cli.has_flag("touch-selftest"):
		await _touch_selftest()

	match Cli.value("shot-ui", ""):
		"buy":
			var hud := get_tree().get_first_node_in_group("hud")
			if hud != null:
				hud.toggle_buy_menu()
			await get_tree().create_timer(0.5).timeout
		"score":
			Input.action_press("scoreboard")
			await get_tree().create_timer(0.5).timeout

	# Two frames so the capture includes the final UI state.
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if out != "":
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var err := img.save_png(out)
		print("[SHOT] saved=%s err=%d size=%dx%d" % [out, err, img.get_width(), img.get_height()])
	print("[SHOT] draw_calls=%d primitives=%d objects=%d vram=%.1fMB fps=%.0f scale3d=%.2f" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.TIME_FPS),
		get_viewport().scaling_3d_scale,
	])
	if not Cli.has_flag("shot-stay"):
		await get_tree().create_timer(0.2).timeout
		get_tree().quit(0)


# ------------------------------------------------------------------
# Touch input pipeline self-test (--touch-selftest, needs --touch):
# injects synthetic InputEventScreenTouch/Drag through the real input
# stack and asserts the player moves / aims / fires / crouches / jumps.
# ------------------------------------------------------------------

## Logical (stretched canvas) -> window pixel coordinates for injection;
## Window input handling applies the inverse stretch transform.
func _in_scale() -> Vector2:
	var win := get_window()
	var logical := get_viewport().get_visible_rect().size
	return Vector2(win.size) / logical


func _touch(idx: int, pressed: bool, pos_logical: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos_logical * _in_scale()
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(idx: int, pos_logical: Vector2, rel_logical: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = pos_logical * _in_scale()
	ev.relative = rel_logical * _in_scale()
	Input.parse_input_event(ev)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _touch_selftest() -> void:
	var p := GameState.local_player as Player
	if p == null:
		print("[TOUCHTEST] FAIL no_player")
		return
	var hud := get_tree().get_first_node_in_group("hud")
	var touch: TouchControls = hud._touch
	var vp := get_viewport().get_visible_rect().size
	var ok := true

	# 1) Virtual joystick: press in the left zone, drag up (forward), hold.
	var start := p.global_position
	var joy := Vector2(vp.x * 0.2, vp.y * 0.72)
	_touch(0, true, joy)
	await _frames(2)
	for i in 8:
		_drag(0, joy + Vector2(0, -12.0 * (i + 1)), Vector2(0, -12))
		await _frames(1)
	await get_tree().create_timer(0.9).timeout
	var moved := start.distance_to(p.global_position)
	print("[TOUCHTEST] joystick_moved=%.2f" % moved)
	ok = ok and moved > 1.5
	_touch(0, false, joy)
	await _frames(2)

	# 2) Aim drag on the right half: yaw must change (negative for a
	# rightward drag = turning right).
	var yaw0 := p.rotation.y
	var aim := Vector2(vp.x * 0.68, vp.y * 0.42)
	_touch(1, true, aim)
	await _frames(1)
	for i in 10:
		_drag(1, aim + Vector2(24.0 * (i + 1), 0), Vector2(24, 0))
		await _frames(1)
	_touch(1, false, aim + Vector2(240, 0))
	await _frames(2)
	var dyaw := p.rotation.y - yaw0
	print("[TOUCHTEST] aim_dyaw=%.3f" % dyaw)
	ok = ok and dyaw < -0.05

	# 3) Fire button: ammo must drop.
	var mag0 := int(p.weapons.current_state().get("mag", 0))
	var fire_pos: Vector2 = touch._by_id.fire_r.pos
	_touch(2, true, fire_pos)
	await get_tree().create_timer(0.35).timeout
	_touch(2, false, fire_pos)
	await _frames(3)
	var mag1 := int(p.weapons.current_state().get("mag", 0))
	print("[TOUCHTEST] fired=%d" % (mag0 - mag1))
	ok = ok and mag1 < mag0

	# 4) Crouch toggle on/off.
	var crouch_pos: Vector2 = touch._by_id.crouch.pos
	_touch(3, true, crouch_pos)
	await _frames(2)
	_touch(3, false, crouch_pos)
	await get_tree().create_timer(0.3).timeout
	var crouched_on := p.crouched
	_touch(3, true, crouch_pos)
	await _frames(2)
	_touch(3, false, crouch_pos)
	await get_tree().create_timer(0.4).timeout
	print("[TOUCHTEST] crouch_toggle on=%s off=%s" % [str(crouched_on), str(not p.crouched)])
	ok = ok and crouched_on and not p.crouched

	# 5) Jump button.
	var jump_pos: Vector2 = touch._by_id.jump.pos
	_touch(4, true, jump_pos)
	await _frames(3)
	var vy := p.velocity.y
	_touch(4, false, jump_pos)
	print("[TOUCHTEST] jump_vy=%.2f" % vy)
	ok = ok and vy > 1.0

	print("[TOUCHTEST] %s" % ("PASS" if ok else "FAIL"))

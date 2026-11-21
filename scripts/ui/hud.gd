extends Control
## In-match HUD (desktop v1; mobile layout lands in the mobile-ux phase).
## Crosshair w/ live spread, health/armor, ammo, credits, kill feed, team
## scores, phase/round timers, spike indicators, plant/defuse progress,
## ability bar, flash overlay, buy menu, scoreboard, hitmarkers, damage
## flash, death/respawn overlay, round banners, match end + pause menu.

var player: Player = null
var wm: WeaponManager = null

var _crosshair: Crosshair
var _hp_label: Label
var _armor_label: Label
var _hp_bar: ProgressBar
var _ammo_label: Label
var _weapon_label: Label
var _credits_label: Label
var _score_att: Label
var _score_def: Label
var _timer_label: Label
var _phase_label: Label
var _feed_box: VBoxContainer
var _death_overlay: Control
var _death_title: Label
var _death_sub: Label
var _damage_flash: ColorRect
var _flash_rect: ColorRect
var _end_panel: PanelContainer
var _end_title: Label
var _end_sub: Label
var _banner: Label
var _pause_panel: Control
var _progress_box: VBoxContainer
var _progress_bar: ProgressBar
var _progress_label: Label
var _spike_hint: Label
var _buy_hint: Label
var _ability_box: HBoxContainer
var _ability_slots: Array = []
var _buy_menu: BuyMenu
var _scoreboard: Scoreboard
var _smoke_overlay: SmokeTargetOverlay

var _touch: TouchControls
var _death_time_ms := 0
var _progress_last_ms := 0
var _flash_tween: Tween

# Simple spectate: after dying in Spike mode, follow a living teammate
# from a chase camera until the next round spawn.
var _spectate_cam: Camera3D = null
var _spectate_target: Player = null
var _spectate_at_ms := 0


static func _font() -> Font:
	var p := "res://assets/fonts/Rajdhani-SemiBold.ttf"
	if ResourceLoader.exists(p):
		return load(p)
	return null


func _mk_label(size_px: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	var f := _font()
	if f != null:
		l.add_theme_font_override("font", f)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _ready() -> void:
	add_to_group("hud")
	add_child(preload("res://scripts/ui/minimap.gd").new())
	GameState.stats_changed.connect(_update_scores)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_damage_flash = ColorRect.new()
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.color = Color(0.8, 0.1, 0.1, 0.0)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_flash)

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_crosshair)

	var bottom_left := VBoxContainer.new()
	bottom_left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom_left.position = Vector2(24, -150)
	bottom_left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_left)
	_credits_label = _mk_label(24, Color(0.95, 0.85, 0.45))
	_credits_label.text = ""
	bottom_left.add_child(_credits_label)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 10)
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_left.add_child(hp_row)
	_hp_label = _mk_label(34)
	_hp_label.text = "100"
	hp_row.add_child(_hp_label)
	_armor_label = _mk_label(24, Color(0.55, 0.75, 0.95))
	_armor_label.text = ""
	hp_row.add_child(_armor_label)
	_hp_bar = ProgressBar.new()
	_hp_bar.max_value = 100
	_hp_bar.value = 100
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(180, 10)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_left.add_child(_hp_bar)

	var bottom_right := VBoxContainer.new()
	bottom_right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom_right.position = Vector2(-260, -110)
	bottom_right.custom_minimum_size = Vector2(230, 0)
	bottom_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_right)
	_weapon_label = _mk_label(22, Color(0.8, 0.85, 0.9))
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom_right.add_child(_weapon_label)
	_ammo_label = _mk_label(38)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom_right.add_child(_ammo_label)

	_build_top_center()
	_build_ability_bar()
	_build_progress()

	_feed_box = VBoxContainer.new()
	_feed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed_box.position = Vector2(-360, 14)
	_feed_box.custom_minimum_size = Vector2(340, 0)
	_feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed_box)

	_spike_hint = _mk_label(20, Color(0.95, 0.85, 0.45))
	_spike_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_spike_hint.position = Vector2(-160, -210)
	_spike_hint.custom_minimum_size = Vector2(320, 0)
	_spike_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_spike_hint)

	_buy_hint = _mk_label(18, Color(0.7, 0.8, 0.9))
	_buy_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_buy_hint.position = Vector2(-160, -240)
	_buy_hint.custom_minimum_size = Vector2(320, 0)
	_buy_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buy_hint.text = "TAP  BUY  TO OPEN SHOP" if Settings.touch_enabled() else "[B]  BUY MENU"
	_buy_hint.visible = false
	add_child(_buy_hint)

	_banner = _mk_label(40)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-300, 90)
	_banner.custom_minimum_size = Vector2(600, 0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	add_child(_banner)

	_death_overlay = _build_death_overlay()
	add_child(_death_overlay)

	_end_panel = _build_end_panel()
	add_child(_end_panel)

	_touch = TouchControls.new()
	_touch.hud = self
	add_child(_touch)

	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)

	_buy_menu = BuyMenu.new()
	add_child(_buy_menu)
	_scoreboard = Scoreboard.new()
	add_child(_scoreboard)
	_smoke_overlay = SmokeTargetOverlay.new()
	add_child(_smoke_overlay)
	_smoke_overlay.target_chosen.connect(_on_smoke_target)
	_smoke_overlay.closed.connect(_restore_mouse)

	_pause_panel = _build_pause_panel()
	add_child(_pause_panel)

	GameState.local_player_spawned.connect(_bind_player)
	if GameState.local_player != null:
		_bind_player(GameState.local_player)
	GameState.kill_feed_event.connect(_on_killfeed)
	GameState.team_scores_changed.connect(_update_scores)
	GameState.match_ended.connect(_on_match_end)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.round_ended.connect(_on_round_end)
	GameState.spike_changed.connect(_update_spike_hint)
	GameState.economy_changed.connect(_update_credits)
	GameState.interact_progress.connect(_on_progress)
	_update_scores()
	_update_credits()


func _build_top_center() -> void:
	var top_center := VBoxContainer.new()
	top_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_center.position = Vector2(-160, 8)
	top_center.custom_minimum_size = Vector2(320, 0)
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_center)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_child(row)
	_score_att = _mk_label(30, GameState.team_color(GameState.Team.ATTACKERS))
	_score_att.text = "0"
	row.add_child(_score_att)
	_timer_label = _mk_label(26)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(_timer_label)
	_score_def = _mk_label(30, GameState.team_color(GameState.Team.DEFENDERS))
	_score_def.text = "0"
	row.add_child(_score_def)
	_phase_label = _mk_label(16, Color(0.75, 0.8, 0.85))
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_center.add_child(_phase_label)


func _build_ability_bar() -> void:
	_ability_box = HBoxContainer.new()
	_ability_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ability_box.position = Vector2(-170, -84)
	_ability_box.custom_minimum_size = Vector2(340, 0)
	_ability_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_ability_box.add_theme_constant_override("separation", 22)
	_ability_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ability_box)
	var keys := ["Q", "E", "X"]
	for slot in 3:
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key := _mk_label(15, Color(0.65, 0.7, 0.78))
		key.text = keys[slot]
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(key)
		var name_l := _mk_label(16)
		name_l.text = "—"
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(name_l)
		var pips := _mk_label(16, Color(0.9, 0.92, 0.95))
		pips.text = ""
		pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(pips)
		_ability_box.add_child(box)
		_ability_slots.append({"name": name_l, "pips": pips})
	_ability_box.visible = false


func _build_progress() -> void:
	_progress_box = VBoxContainer.new()
	UiUtil.center(_progress_box, 280, 60, 0, 95)
	_progress_box.custom_minimum_size = Vector2(280, 0)
	_progress_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_box.visible = false
	add_child(_progress_box)
	_progress_label = _mk_label(20)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_box.add_child(_progress_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(280, 14)
	_progress_bar.show_percentage = false
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_box.add_child(_progress_bar)


func _build_death_overlay() -> Control:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.05, 0.02, 0.03, 0.55)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	UiUtil.center(box, 320, 110, 0, -40)
	box.custom_minimum_size = Vector2(320, 0)
	overlay.add_child(box)
	_death_title = _mk_label(46, Color(1, 0.35, 0.3))
	_death_title.text = "YOU DIED"
	_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_death_title)
	_death_sub = _mk_label(22)
	_death_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_death_sub)
	return overlay


func _build_end_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	UiUtil.center(panel, 440, 160)
	panel.custom_minimum_size = Vector2(440, 160)
	panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_end_title = _mk_label(44)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_title)
	_end_sub = _mk_label(22, Color(0.8, 0.85, 0.9))
	_end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_sub)
	return panel


func _build_pause_panel() -> Control:
	var panel := PanelContainer.new()
	UiUtil.center(panel, 260, 150)
	panel.custom_minimum_size = Vector2(260, 150)
	panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := _mk_label(24)
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.custom_minimum_size = Vector2(0, 48)
	resume.pressed.connect(toggle_pause)
	box.add_child(resume)
	var leave := Button.new()
	leave.text = "Leave Match"
	leave.custom_minimum_size = Vector2(0, 48)
	leave.pressed.connect(func() -> void:
		Net.leave()
		GameState.reset_match_state()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_tree().change_scene_to_file("res://scenes/boot.tscn"))
	box.add_child(leave)
	return panel


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _smoke_overlay.visible:
			return
		toggle_pause()
	elif event.is_action_pressed("buy_menu"):
		toggle_buy_menu()


## True while a UI that should block gameplay input is up (mirrors what
## mouse capture gates on desktop; the touch layer polls this).
func modal_ui_open() -> bool:
	return _buy_menu.visible or _pause_panel.visible or _smoke_overlay.visible or _end_panel.visible


func toggle_pause() -> void:
	_pause_panel.visible = not _pause_panel.visible
	if DisplayServer.get_name() == "headless" or Settings.touch_enabled():
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if _pause_panel.visible else Input.MOUSE_MODE_CAPTURED)


func toggle_buy_menu() -> void:
	if GameState.mode != GameState.Mode.SPIKE:
		return
	if _buy_menu.visible:
		_buy_menu.close()
		_restore_mouse()
	elif GameState.phase == GameState.RoundPhase.BUY and player != null and player.alive:
		_buy_menu.open(player)
		if DisplayServer.get_name() != "headless" and not Settings.touch_enabled():
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _restore_mouse() -> void:
	if DisplayServer.get_name() == "headless" or Settings.touch_enabled() or _pause_panel.visible:
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _bind_player(p: Node) -> void:
	player = p as Player
	if player == null:
		return
	wm = player.weapons
	player.health_changed.connect(_on_health)
	player.died_local.connect(_on_died)
	player.respawned_local.connect(_on_respawned)
	player.hit_confirmed.connect(_on_hit_confirmed)
	player.tagged.connect(_on_tagged)
	player.flashed.connect(_on_flashed)
	wm.ammo_changed.connect(_on_ammo)
	wm.weapon_changed.connect(_on_weapon)
	player.abilities.charges_changed.connect(_on_charges)
	player.abilities.map_target_requested.connect(_on_map_target_requested)
	_on_health(player.health, player.armor)
	_refresh_ability_bar()
	_update_spike_hint()
	var d := wm.current_data()
	if d != null:
		_on_weapon(d)
		var st: Dictionary = wm.current_state()
		_on_ammo(int(st.get("mag", 0)), int(st.get("reserve", 0)))


func _process(_delta: float) -> void:
	Settings.touch_block_gameplay = modal_ui_open()
	var t := int(maxf(GameState.match_time_left, 0.0))
	if GameState.mode == GameState.Mode.SPIKE:
		if GameState.phase == GameState.RoundPhase.PLANTED:
			_timer_label.text = "⬤"
			_timer_label.add_theme_color_override("font_color", Color(1, 0.3, 0.2) if fmod(GameState.match_time_left, 0.6) < 0.3 else Color(0.7, 0.2, 0.15))
			_phase_label.text = "SPIKE PLANTED"
		else:
			_timer_label.text = "%d:%02d" % [t / 60, t % 60]
			_timer_label.add_theme_color_override("font_color", Color.WHITE)
			_phase_label.text = "ROUND %d — %s" % [GameState.round_number, GameState.phase_name(GameState.phase)]
	else:
		_timer_label.text = "%d:%02d" % [t / 60, t % 60]
		_phase_label.text = "FREE FOR ALL  /  %d KILLS" % GameState.tdm_target if GameState.mode == GameState.Mode.FFA else ""
	if player != null and wm != null and player.alive:
		_crosshair.spread_px = _spread_to_px(wm.current_spread_deg())
	if _death_overlay.visible and GameState.mode != GameState.Mode.SPIKE:
		var left := maxf(GameState.TDM_RESPAWN_DELAY - float(Time.get_ticks_msec() - _death_time_ms) / 1000.0, 0.0)
		_death_sub.text = "Respawning in %.1f" % left
	# Progress bar auto-hide when updates stop coming.
	if _progress_box.visible and Time.get_ticks_msec() - _progress_last_ms > 450:
		_progress_box.visible = false
	# Scoreboard: hold Tab (or touch toggle); auto during round end / match end.
	var want_sb := (GameState.mode == GameState.Mode.FFA and not GameState.match_running) or Input.is_action_pressed("scoreboard") or _touch.scoreboard_open() \
		or (GameState.mode == GameState.Mode.SPIKE and GameState.phase == GameState.RoundPhase.ROUND_END) \
		or (not GameState.match_running and GameState.round_number > 0 and GameState.mode == GameState.Mode.SPIKE)
	if want_sb and not _scoreboard.visible:
		_scoreboard.open()
	elif not want_sb and _scoreboard.visible:
		_scoreboard.close()
	_tick_spectate()


# ------------------------------------------------------------------
# Spectate (dead in Spike mode: chase-cam a living teammate)
# ------------------------------------------------------------------

func _tick_spectate() -> void:
	var want := GameState.mode == GameState.Mode.SPIKE and GameState.match_running \
		and player != null and not player.alive \
		and (GameState.phase == GameState.RoundPhase.ACTIVE or GameState.phase == GameState.RoundPhase.PLANTED)
	if not want:
		_end_spectate()
		return
	if _spectate_cam == null:
		if Time.get_ticks_msec() < _spectate_at_ms:
			return
		_spectate_target = _pick_spectate_target()
		if _spectate_target == null:
			return
		_spectate_cam = Camera3D.new()
		_spectate_cam.fov = 70.0
		get_tree().current_scene.add_child(_spectate_cam)
		_snap_spectate(true)
		_spectate_cam.make_current()
		_death_sub.text = "Spectating %s" % _spectate_target.player_name
		(_death_overlay as ColorRect).color.a = 0.16  # lighter dim while spectating
	else:
		if not is_instance_valid(_spectate_target) or not _spectate_target.alive:
			_spectate_target = _pick_spectate_target()
			if _spectate_target == null:
				_end_spectate()
				return
			_death_sub.text = "Spectating %s" % _spectate_target.player_name
		_snap_spectate(false)


func _pick_spectate_target() -> Player:
	if player == null:
		return null
	for node: Node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p != null and p != player and p.alive and int(p.team) == int(player.team):
			return p
	return null


func _snap_spectate(instant: bool) -> void:
	if _spectate_cam == null or _spectate_target == null:
		return
	var head: Node3D = _spectate_target.head
	var fwd := -head.global_basis.z
	var want_pos := head.global_position - fwd * 2.7 + Vector3.UP * 0.4
	if instant:
		_spectate_cam.global_position = want_pos
	else:
		_spectate_cam.global_position = _spectate_cam.global_position.lerp(want_pos, 0.25)
	var look_at_point := head.global_position + fwd * 4.0
	if _spectate_cam.global_position.distance_to(look_at_point) > 0.01:
		_spectate_cam.look_at(look_at_point)


func _end_spectate() -> void:
	if _spectate_cam == null:
		return
	_spectate_cam.queue_free()
	_spectate_cam = null
	_spectate_target = null
	if player != null and is_instance_valid(player):
		player.camera.make_current()


func _spread_to_px(deg: float) -> float:
	if player == null:
		return 8.0
	var vp := get_viewport_rect().size
	return tan(deg_to_rad(deg)) / tan(deg_to_rad(player.camera.fov * 0.5)) * (vp.y * 0.5)


func _on_health(hp: int, ar: int) -> void:
	_hp_label.text = str(hp)
	_hp_bar.value = hp
	_armor_label.text = ("+%d" % ar) if ar > 0 else ""
	var frac := float(hp) / float(Player.MAX_HEALTH)
	_hp_label.add_theme_color_override("font_color", Color(1, 0.3 + frac * 0.7, 0.3 + frac * 0.7))


func _update_credits() -> void:
	if GameState.mode != GameState.Mode.SPIKE:
		_credits_label.text = ""
		return
	_credits_label.text = "¤ %d" % int(GameState.economy.get(Net.my_id(), 0))


func _on_charges(_charges: Array) -> void:
	_refresh_ability_bar()


func _refresh_ability_bar() -> void:
	if player == null:
		return
	var agent := AgentDB.get_agent(StringName(player.agent_id))
	if agent == null or GameState.mode != GameState.Mode.SPIKE or Settings.touch_enabled():
		_ability_box.visible = false  # touch mode has its own ability buttons
		return
	_ability_box.visible = true
	for slot in 3:
		var ab: AbilityData = agent.ability(slot)
		var ui: Dictionary = _ability_slots[slot]
		if ab == null:
			(ui.name as Label).text = "—"
			(ui.pips as Label).text = ""
			continue
		(ui.name as Label).text = ab.display_name
		(ui.name as Label).add_theme_color_override("font_color", ab.icon_color)
		var n: int = player.abilities.charges[slot]
		var pips := ""
		for i in ab.max_charges:
			pips += "●" if i < n else "○"
		(ui.pips as Label).text = pips
		(ui.pips as Label).add_theme_color_override("font_color", Color(0.95, 0.95, 1.0) if n > 0 else Color(0.45, 0.48, 0.52))


func _on_map_target_requested(slot: int) -> void:
	if player == null:
		return
	_smoke_overlay.open(slot, player)
	if DisplayServer.get_name() != "headless" and not Settings.touch_enabled():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_smoke_target(slot: int, world_pos: Vector3) -> void:
	if player != null:
		player.abilities.cast_at(slot, world_pos)
	_restore_mouse()


func _update_spike_hint() -> void:
	if GameState.mode != GameState.Mode.SPIKE or player == null:
		_spike_hint.text = ""
		return
	var s: Dictionary = GameState.spike
	var state := int(s.get("state", -1))
	var carrier := int(s.get("carrier", 0))
	if state == GameState.SpikeState.CARRIED and carrier == Net.my_id():
		_spike_hint.text = "YOU HAVE THE SPIKE"
	elif int(player.team) == GameState.Team.ATTACKERS:
		match state:
			GameState.SpikeState.CARRIED:
				_spike_hint.text = "Spike: %s" % String(Net.players.get(carrier, {}).get("name", "?"))
			GameState.SpikeState.DROPPED:
				_spike_hint.text = "SPIKE DROPPED — recover it!"
			_:
				_spike_hint.text = ""
	else:
		_spike_hint.text = ""


func _on_progress(kind: int, value: float, total: float, peer: int) -> void:
	if value <= 0.0:
		_progress_box.visible = false
		return
	if peer != Net.my_id():
		return
	_progress_last_ms = Time.get_ticks_msec()
	_progress_box.visible = true
	_progress_label.text = "PLANTING..." if kind == 0 else "DEFUSING..."
	_progress_bar.max_value = total
	_progress_bar.value = value


func _on_phase_changed(p: int) -> void:
	_buy_hint.visible = GameState.mode == GameState.Mode.SPIKE and p == GameState.RoundPhase.BUY
	if p == GameState.RoundPhase.BUY:
		_banner.visible = false
		_death_overlay.visible = false
		if _buy_menu.visible:
			_buy_menu.refresh()
	else:
		if _buy_menu.visible:
			_buy_menu.close()
			_restore_mouse()
	_update_spike_hint()
	_update_scores()


func _on_round_end(winner: int, reason: String) -> void:
	var why := ""
	match reason:
		"elimination": why = "Enemy team eliminated"
		"detonation": why = "Spike detonated"
		"defuse": why = "Spike defused"
		"timeout": why = "Time expired"
		"forfeit": why = "Opponents left"
	_banner.text = "%s WIN THE ROUND\n%s" % [GameState.team_name(winner).to_upper(), why]
	_banner.add_theme_color_override("font_color", GameState.team_color(winner))
	_banner.visible = true


func _on_flashed(strength: float, duration: float) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.color.a = clampf(strength, 0.0, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_interval(duration * 0.55)
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, duration * 0.45)


func _on_ammo(mag: int, reserve: int) -> void:
	var d := wm.current_data() if wm != null else null
	if d != null and d.mag_size <= 0:
		_ammo_label.text = "—"
	else:
		_ammo_label.text = "%d / %d" % [mag, reserve]


func _on_weapon(d: WeaponData) -> void:
	_weapon_label.text = d.display_name.to_upper()
	var st: Dictionary = wm.current_state()
	_on_ammo(int(st.get("mag", 0)), int(st.get("reserve", 0)))


func _on_hit_confirmed(_damage: int, region: int, killed: bool) -> void:
	_crosshair.show_hitmarker(killed)
	if killed:
		Fx.play_sound_2d(self, Sfx.ui_stream("kill"), -4.0)
	elif region == HitboxRegion.Region.HEAD:
		Fx.play_sound_2d(self, Sfx.ui_stream("headshot"), -6.0)
	else:
		Fx.play_sound_2d(self, Sfx.ui_stream("hit"), -8.0)


func _on_tagged() -> void:
	_damage_flash.color.a = 0.28
	var tw := create_tween()
	tw.tween_property(_damage_flash, "color:a", 0.0, 0.4)


func _on_died(killer_name: String) -> void:
	_death_time_ms = Time.get_ticks_msec()
	_spectate_at_ms = Time.get_ticks_msec() + 1800
	(_death_overlay as ColorRect).color.a = 0.55
	if killer_name == "":
		_death_title.text = "STANDBY"
		_death_sub.text = "You deploy next round"
	else:
		_death_title.text = "YOU DIED"
		_death_sub.text = "Killed by %s" % killer_name
	_death_overlay.visible = true


func _on_respawned() -> void:
	_death_overlay.visible = false
	_end_spectate()


func _on_killfeed(killer: String, victim: String, weapon_id: String, headshot: bool, killer_team: int) -> void:
	var row := _mk_label(18)
	row.text = "%s   [%s%s]   %s" % [killer, weapon_id, " HS" if headshot else "", victim]
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_theme_color_override("font_color", GameState.team_color(killer_team))
	_feed_box.add_child(row)
	_feed_box.move_child(row, 0)
	while _feed_box.get_child_count() > 6:
		_feed_box.get_child(_feed_box.get_child_count() - 1).free()
	var tw := row.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(row, "modulate:a", 0.0, 0.6)
	tw.tween_callback(row.queue_free)


func _update_scores() -> void:
	if GameState.mode == GameState.Mode.FFA:
		_score_att.text = "K %d" % int(GameState.stats.get(Net.my_id(), {}).get("k",0))
		_score_def.text = "D %d" % int(GameState.stats.get(Net.my_id(), {}).get("d",0))
		return
	if GameState.mode == GameState.Mode.SPIKE:
		var my_team := int(player.team) if player != null else 0
		_score_att.text = ("▶%d" if my_team == GameState.Team.ATTACKERS else "%d") % GameState.score_att
		_score_def.text = ("%d◀" if my_team == GameState.Team.DEFENDERS else "%d") % GameState.score_def
	else:
		_score_att.text = str(GameState.kills_a)
		_score_def.text = str(GameState.kills_b)


func _on_match_end(winning_team: int) -> void:
	_death_overlay.visible = false
	_banner.visible = false
	_end_panel.visible = true
	if GameState.mode == GameState.Mode.FFA:
		_end_title.text = "DRAW" if winning_team == 0 else "%s WINS" % String(Net.players.get(winning_team, {}).get("name", "Player")).to_upper()
		_end_sub.text = "Match complete · returning to lobby"
		_scoreboard.open()
		return
	if winning_team == GameState.Team.NONE:
		_end_title.text = "DRAW"
	else:
		_end_title.text = "%s WIN" % GameState.team_name(winning_team).to_upper()
	_end_title.add_theme_color_override("font_color", GameState.team_color(winning_team))
	if GameState.mode == GameState.Mode.SPIKE:
		_end_sub.text = "%d — %d   ·   returning to lobby..." % [GameState.score_att, GameState.score_def]
	else:
		_end_sub.text = "%d — %d kills   ·   returning to lobby..." % [GameState.kills_a, GameState.kills_b]
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

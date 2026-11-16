extends Control
## Pre-match lobby: player list with teams + agents, team pick (enforces the
## host's team size), per-player agent select with role/kit tooltips,
## loadout pick (TDM), host-only map/mode/team-size/start controls.

signal leave_requested

var _player_list: VBoxContainer
var _map_option: OptionButton
var _size_option: OptionButton
var _mode_option: OptionButton
var _primary_option: OptionButton
var _secondary_option: OptionButton
var _start_btn: Button
var _host_row: Control
var _status: Label
var _ip_label: Label
var _team_a_btn: Button
var _team_b_btn: Button
var _agent_buttons: Dictionary = {}
var _maps: Array[String] = []


static func _font() -> Font:
	var p := "res://assets/fonts/Rajdhani-SemiBold.ttf"
	if ResourceLoader.exists(p):
		return load(p)
	return null


func _mk_label(text: String, size_px: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	var f := _font()
	if f != null:
		l.add_theme_font_override("font", f)
	return l


func _ready() -> void:
	UiUtil.full_rect(self)
	var panel := PanelContainer.new()
	UiUtil.center(panel, 720, 600)
	panel.custom_minimum_size = Vector2(720, 600)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	box.add_child(_mk_label("LOBBY", 36))
	_player_list = VBoxContainer.new()
	_player_list.custom_minimum_size = Vector2(0, 160)
	box.add_child(_player_list)
	box.add_child(HSeparator.new())

	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 8)
	box.add_child(team_row)
	team_row.add_child(_mk_label("Your team:", 18, Color(0.7, 0.75, 0.8)))
	_team_a_btn = Button.new()
	_team_a_btn.pressed.connect(func() -> void: Net.set_my_team(GameState.Team.ATTACKERS))
	team_row.add_child(_team_a_btn)
	_team_b_btn = Button.new()
	_team_b_btn.pressed.connect(func() -> void: Net.set_my_team(GameState.Team.DEFENDERS))
	team_row.add_child(_team_b_btn)

	var agent_row := HBoxContainer.new()
	agent_row.add_theme_constant_override("separation", 8)
	box.add_child(agent_row)
	agent_row.add_child(_mk_label("Agent:", 18, Color(0.7, 0.75, 0.8)))
	var group := ButtonGroup.new()
	for aid: StringName in AgentDB.IDS:
		var agent := AgentDB.get_agent(aid)
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = group
		btn.text = agent.display_name
		btn.custom_minimum_size = Vector2(110, 40)
		var kit := ""
		for slot in 3:
			var ab: AbilityData = agent.ability(slot)
			if ab != null:
				kit += "\n  [%s] %s — %s" % [["Q", "E", "X"][slot], ab.display_name, ab.description]
		btn.tooltip_text = "%s (%s)\n%s%s" % [agent.display_name, agent.role, agent.description, kit]
		btn.add_theme_color_override("font_color", agent.tint)
		btn.toggled.connect(func(on: bool) -> void:
			if on:
				Net.set_my_agent(String(aid)))
		agent_row.add_child(btn)
		_agent_buttons[String(aid)] = btn

	var loadout_row := HBoxContainer.new()
	loadout_row.add_theme_constant_override("separation", 8)
	box.add_child(loadout_row)
	loadout_row.add_child(_mk_label("TDM loadout:", 18, Color(0.7, 0.75, 0.8)))
	_primary_option = OptionButton.new()
	for id: StringName in WeaponDB.PRIMARIES:
		_primary_option.add_item(WeaponDB.get_weapon(id).display_name)
	loadout_row.add_child(_primary_option)
	_secondary_option = OptionButton.new()
	for id: StringName in WeaponDB.SECONDARIES:
		_secondary_option.add_item(WeaponDB.get_weapon(id).display_name)
	loadout_row.add_child(_secondary_option)
	_select_loadout_defaults()
	_primary_option.item_selected.connect(func(_i: int) -> void: _send_loadout())
	_secondary_option.item_selected.connect(func(_i: int) -> void: _send_loadout())

	_host_row = HBoxContainer.new()
	(_host_row as HBoxContainer).add_theme_constant_override("separation", 8)
	box.add_child(_host_row)
	_host_row.add_child(_mk_label("Mode:", 18, Color(0.7, 0.75, 0.8)))
	_mode_option = OptionButton.new()
	_mode_option.add_item("Spike")   # index 0 -> Mode.SPIKE
	_mode_option.add_item("TDM")     # index 1 -> Mode.TDM
	_mode_option.select(0)
	_mode_option.item_selected.connect(func(_i: int) -> void: _update_start_label())
	_host_row.add_child(_mode_option)
	_host_row.add_child(_mk_label("Map:", 18, Color(0.7, 0.75, 0.8)))
	_map_option = OptionButton.new()
	_scan_maps()
	_host_row.add_child(_map_option)
	_host_row.add_child(_mk_label("Team size:", 18, Color(0.7, 0.75, 0.8)))
	_size_option = OptionButton.new()
	for n in range(1, 6):
		_size_option.add_item("%dv%d" % [n, n])
	_size_option.select(4)
	_size_option.item_selected.connect(func(i: int) -> void:
		Net.set_lobby_team_size(i + 1))
	_host_row.add_child(_size_option)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_start_btn = Button.new()
	_start_btn.custom_minimum_size = Vector2(240, 44)
	_start_btn.pressed.connect(_on_start)
	buttons.add_child(_start_btn)
	var leave := Button.new()
	leave.text = "LEAVE"
	leave.custom_minimum_size = Vector2(120, 44)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	buttons.add_child(leave)

	_ip_label = _mk_label("", 16, Color(0.6, 0.8, 0.75))
	box.add_child(_ip_label)
	_status = _mk_label("", 16, Color(1, 0.6, 0.4))
	box.add_child(_status)

	Net.player_list_changed.connect(_refresh)
	Net.lobby_cfg_changed.connect(_refresh)
	Net.action_denied.connect(_on_denied)
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())
	_update_start_label()
	_refresh()


func _on_denied(msg: String) -> void:
	_status.text = msg
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_callback(func() -> void: _status.text = "")


func _update_start_label() -> void:
	_start_btn.text = "START MATCH (%s)" % ("SPIKE" if _mode_option.selected == 0 else "TDM")


func _scan_maps() -> void:
	_maps.clear()
	_map_option.clear()
	var dir := DirAccess.open("res://maps")
	if dir != null:
		for d: String in dir.get_directories():
			var p := "res://maps/%s/%s.tscn" % [d, d]
			if ResourceLoader.exists(p):
				_maps.append(d)
				_map_option.add_item(d)
	if _maps.is_empty():
		_maps.append("graybox")
		_map_option.add_item("graybox")


func _select_loadout_defaults() -> void:
	var pi := WeaponDB.PRIMARIES.find(StringName(Settings.loadout_primary))
	_primary_option.select(maxi(pi, 0))
	var si := WeaponDB.SECONDARIES.find(StringName(Settings.loadout_secondary))
	_secondary_option.select(maxi(si, 0))


func _send_loadout() -> void:
	var primary := String(WeaponDB.PRIMARIES[_primary_option.selected])
	var secondary := String(WeaponDB.SECONDARIES[_secondary_option.selected])
	Settings.loadout_primary = primary
	Settings.loadout_secondary = secondary
	Settings.save_settings()
	Net.set_my_loadout(primary, secondary)


func _refresh() -> void:
	if _player_list == null:
		return
	for c in _player_list.get_children():
		c.queue_free()
	var ids := Net.players.keys()
	ids.sort()
	for id: int in ids:
		var info: Dictionary = Net.players[id]
		var team := int(info.get("team", 0))
		var agent := AgentDB.get_agent(StringName(String(info.get("agent", "gale"))))
		var row := _mk_label("%s%s   —   %s   ·   %s   (%s / %s)" % [
			String(info.get("name", "?")),
			"  [HOST]" if id == 1 else "",
			GameState.team_name(team),
			agent.display_name if agent != null else "?",
			String(info.get("primary", "?")), String(info.get("secondary", "?"))],
			20, GameState.team_color(team))
		_player_list.add_child(row)
	var cap := Net.lobby_team_size
	_team_a_btn.text = "Attackers (%d/%d)" % [Net.team_count(GameState.Team.ATTACKERS), cap]
	_team_b_btn.text = "Defenders (%d/%d)" % [Net.team_count(GameState.Team.DEFENDERS), cap]
	var my_agent := String(Net.players.get(Net.my_id(), {}).get("agent", "gale"))
	for aid: String in _agent_buttons:
		(_agent_buttons[aid] as Button).set_pressed_no_signal(aid == my_agent)
	var am_host := multiplayer.is_server() and Net.is_active()
	_host_row.visible = am_host
	_start_btn.visible = am_host
	_start_btn.disabled = Net.players.is_empty()
	if am_host:
		var ips := _lan_ips()
		_ip_label.text = ("Your IP for manual join: %s" % ", ".join(ips)) if not ips.is_empty() else ""
	else:
		_ip_label.text = ""


## Local LAN addresses (for the "manual IP" fallback when UDP discovery is
## blocked by the router).
static func _lan_ips() -> Array[String]:
	var out: Array[String] = []
	for ip: String in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			out.append(ip)
	return out


func _on_start() -> void:
	if not multiplayer.is_server():
		return
	var map_name := _maps[_map_option.selected] if _map_option.selected >= 0 else "graybox"
	var mode := GameState.Mode.SPIKE if _mode_option.selected == 0 else GameState.Mode.TDM
	GameState.team_size = Net.lobby_team_size
	GameState.host_start_match(
		"res://maps/%s/%s.tscn" % [map_name, map_name],
		mode,
		Net.lobby_team_size)

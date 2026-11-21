extends Control
## Presentation-only room view. Transport and match authority remain in Net/GameState.

signal leave_requested

const STAGE = preload("res://scripts/ui/operator_stage.gd")
const ACCENT := Color("e1ed53")
const INK := Color("101815")
const MUTED := Color("9aafb8")
const MAP := "res://maps/solstice/solstice.tscn"
var _roster: VBoxContainer
var _count: Label
var _identity: Label
var _connection: Label
var _status: Label
var _play: Button
var _address: Label
var _layout: MarginContainer

func _label(value: String, font_size: int, color := Color.WHITE) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_color_override("font_color", color)
	node.add_theme_font_size_override("font_size", font_size)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func _panel() -> PanelContainer:
	var node := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.055, 0.88)
	style.border_color = Color(0.44, 0.62, 0.66, 0.24)
	style.set_border_width_all(1)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	node.add_theme_stylebox_override("panel", style)
	return node

func _button(value: String, primary := false) -> Button:
	var node := Button.new()
	node.text = value
	node.custom_minimum_size.y = 52
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.add_theme_font_size_override("font_size", 22)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = ACCENT if primary else Color("17262d")
		if state == "hover":
			style.bg_color = style.bg_color.lightened(0.13)
		elif state == "pressed":
			style.bg_color = style.bg_color.darkened(0.15)
		elif state == "disabled":
			style.bg_color = Color("354246")
		style.border_color = Color.WHITE if state == "focus" else Color(0.55, 0.7, 0.72, 0.3)
		style.set_border_width_all(2 if state == "focus" else 1)
		style.content_margin_left = 20
		style.content_margin_right = 20
		node.add_theme_stylebox_override(state, style)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(state, INK if primary else Color.WHITE)
	return node

func _ready() -> void:
	UiUtil.full_rect(self)
	var theme_resource := Theme.new()
	theme_resource.default_font = preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
	theme = theme_resource
	var stage := SubViewportContainer.new()
	stage.set_script(STAGE)
	add_child(stage)
	var shade := ColorRect.new()
	UiUtil.full_rect(shade)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ float edge = pow(abs(UV.x - 0.5) * 2.0, 2.0); float bottom = smoothstep(0.55, 1.0, UV.y); COLOR = vec4(0.015,0.025,0.035, max(max(edge * 0.72, bottom * 0.8), (1.0 - smoothstep(0.0, 0.24, UV.y)) * 0.8)); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	shade.material = material
	add_child(shade)
	_layout = MarginContainer.new()
	UiUtil.full_rect(_layout)
	for side: String in ["left", "right", "top", "bottom"]:
		_layout.add_theme_constant_override("margin_" + side, 28)
	add_child(_layout)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	_layout.add_child(stack)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	stack.add_child(top)
	top.add_child(_label("RIFTOPS", 34))
	var tag := _label(" /  PRIVATE ROOM", 17, MUTED)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tag)
	_connection = _label("LOCAL NETWORK", 16, ACCENT)
	top.add_child(_connection)
	var leave := _button("LEAVE ROOM")
	leave.pressed.connect(func() -> void: leave_requested.emit())
	top.add_child(leave)
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 20)
	stack.add_child(middle)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 220
	middle.add_child(left)
	left.add_child(_label("OPERATOR / 01", 15, ACCENT))
	_identity = _label("", 26)
	_identity.custom_minimum_size.x = 220
	_identity.clip_text = true
	left.add_child(_identity)
	left.add_child(_label("LOCAL CONNECTION ACTIVE", 13, MUTED))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(_label("NO SIGNAL\nREQUIRED.", 38))
	left.add_child(_label("Your network. Your match.", 17, MUTED))
	var breathing_room := Control.new()
	breathing_room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(breathing_room)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 300
	right.add_theme_constant_override("separation", 12)
	middle.add_child(right)
	var roster_panel := _panel()
	roster_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(roster_panel)
	var roster_stack := VBoxContainer.new()
	roster_stack.add_theme_constant_override("separation", 10)
	roster_panel.add_child(roster_stack)
	_count = _label("PLAYERS", 22)
	roster_stack.add_child(_count)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_stack.add_child(scroll)
	_roster = VBoxContainer.new()
	_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster.add_theme_constant_override("separation", 7)
	scroll.add_child(_roster)
	var match_panel := _panel()
	right.add_child(match_panel)
	var match_stack := VBoxContainer.new()
	match_panel.add_child(match_stack)
	match_stack.add_child(_label("CURRENT ARENA", 13, ACCENT))
	match_stack.add_child(_label("SOLSTICE", 32))
	match_stack.add_child(_label("TEAM DEATHMATCH", 16, MUTED))
	_play = _button("PLAY  >", true)
	_play.custom_minimum_size.y = 68
	_play.pressed.connect(_on_start)
	right.add_child(_play)
	var footer := _panel()
	stack.add_child(footer)
	var footer_stack := VBoxContainer.new()
	footer.add_child(footer_stack)
	_address = _label("", 15, MUTED)
	_address.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_stack.add_child(_address)
	_status = _label("", 15, ACCENT)
	footer_stack.add_child(_status)
	Net.player_list_changed.connect(_refresh)
	Net.lobby_cfg_changed.connect(_refresh)
	Net.action_denied.connect(func(message: String) -> void: _status.text = message)
	visibility_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(_roster):
		return
	for child in _roster.get_children():
		child.free()
	var ids := Net.players.keys()
	ids.sort()
	for id: int in ids:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 34
		var marker := _label("%02d" % (ids.find(id) + 1), 18, ACCENT)
		marker.custom_minimum_size.x = 34
		row.add_child(marker)
		var player_label := _label(String(Net.players[id].get("name", "Player")), 19)
		player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_label.clip_text = true
		row.add_child(player_label)
		row.add_child(_label("HOST" if id == 1 else "LAN", 12, MUTED))
		_roster.add_child(row)
	_count.text = "PLAYERS   %02d / %02d" % [ids.size(), Net.lobby_team_size * 2]
	_identity.text = Settings.player_name
	var am_host := Net.is_active() and multiplayer.is_server()
	_play.disabled = not am_host or ids.is_empty()
	_play.text = "PLAY  >" if am_host else "WAITING FOR HOST"
	_connection.text = "HOST / LOCAL NETWORK" if am_host else "CONNECTED / LOCAL NETWORK"
	_address.text = "MANUAL JOIN  /  " + ", ".join(_lan_ips()) if am_host else "Connected to the host's private room."
	_status.text = "Start when everyone has joined." if am_host else "The host will start the match for everyone."

static func _lan_ips() -> Array[String]:
	var addresses: Array[String] = []
	for ip: String in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10."):
			addresses.append(ip)
		elif ip.begins_with("172."):
			var second := ip.get_slice(".", 1).to_int()
			if second >= 16 and second <= 31:
				addresses.append(ip)
	return addresses

func _on_start() -> void:
	if not Net.is_active() or not multiplayer.is_server():
		return
	GameState.host_start_match(MAP, GameState.Mode.TDM, Net.lobby_team_size)

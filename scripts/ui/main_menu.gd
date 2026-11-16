extends Control
## Main menu: Host / Join (LAN discovery list + manual IP) / Settings / Quit.

signal host_requested
signal join_requested(ip: String)

var _status: Label
var _root_box: VBoxContainer
var _join_panel: Control
var _settings_panel: Control
var _server_list: ItemList
var _ip_edit: LineEdit
var _servers: Array = []

var _name_edit: LineEdit
var _sens_slider: HSlider
var _sens_value: Label
var _touch_sens_slider: HSlider
var _touch_sens_value: Label
var _ads_sens_slider: HSlider
var _ads_sens_value: Label
var _res_slider: HSlider
var _res_value: Label
var _ads_check: CheckBox
var _invert_check: CheckBox
var _touch_option: OptionButton
var _tap_fire_check: CheckBox


static func _font(weight := "SemiBold") -> Font:
	var p := "res://assets/fonts/Rajdhani-%s.ttf" % weight
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


func _mk_button(text: String, size_px := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 54)
	b.add_theme_font_size_override("font_size", size_px)
	var f := _font()
	if f != null:
		b.add_theme_font_override("font", f)
	return b


func _ready() -> void:
	UiUtil.full_rect(self)
	_root_box = VBoxContainer.new()
	UiUtil.center(_root_box, 300, 480)
	_root_box.custom_minimum_size = Vector2(300, 0)
	_root_box.add_theme_constant_override("separation", 12)
	add_child(_root_box)

	var title := _mk_label("RIFTOPS", 64, Color(1, 0.27, 0.33))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_box.add_child(title)
	var subtitle := _mk_label("LAN tactical shooter", 18, Color(0.6, 0.65, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_box.add_child(subtitle)
	_root_box.add_child(HSeparator.new())

	var host_btn := _mk_button("HOST GAME")
	host_btn.pressed.connect(func() -> void: host_requested.emit())
	_root_box.add_child(host_btn)
	var join_btn := _mk_button("JOIN GAME")
	join_btn.pressed.connect(_show_join)
	_root_box.add_child(join_btn)
	var settings_btn := _mk_button("SETTINGS")
	settings_btn.pressed.connect(_show_settings)
	_root_box.add_child(settings_btn)
	var quit_btn := _mk_button("QUIT")
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	_root_box.add_child(quit_btn)

	_status = _mk_label("", 16, Color(1, 0.75, 0.4))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_box.add_child(_status)

	_join_panel = _build_join_panel()
	add_child(_join_panel)
	_settings_panel = _build_settings_panel()
	add_child(_settings_panel)

	Net.lan_servers_updated.connect(_on_servers_updated)
	visibility_changed.connect(func() -> void:
		if not visible:
			Net.stop_discovery())


func set_status(text: String) -> void:
	_status.text = text


func _build_join_panel() -> Control:
	var panel := PanelContainer.new()
	UiUtil.center(panel, 440, 360)
	panel.custom_minimum_size = Vector2(440, 360)
	panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_mk_label("JOIN LAN GAME", 30))
	box.add_child(_mk_label("Servers on your network:", 16, Color(0.7, 0.75, 0.8)))
	_server_list = ItemList.new()
	_server_list.custom_minimum_size = Vector2(0, 160)
	_server_list.item_activated.connect(_on_server_activated)
	box.add_child(_server_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "IP address (e.g. 192.168.1.42)"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ip_edit)
	var join := _mk_button("JOIN", 18)
	join.custom_minimum_size = Vector2(100, 36)
	join.pressed.connect(func() -> void:
		var ip := _ip_edit.text.strip_edges()
		if _server_list.get_selected_items().size() > 0:
			var idx := _server_list.get_selected_items()[0]
			if idx < _servers.size():
				ip = String(_servers[idx].ip)
		if ip != "":
			join_requested.emit(ip))
	row.add_child(join)
	var back := _mk_button("BACK", 18)
	back.custom_minimum_size = Vector2(100, 36)
	back.pressed.connect(func() -> void:
		_join_panel.visible = false
		_root_box.visible = true
		Net.stop_discovery())
	box.add_child(back)
	return panel


func _show_join() -> void:
	_root_box.visible = false
	_join_panel.visible = true
	Net.start_discovery()
	_refresh_server_list()


func _on_servers_updated(servers: Array) -> void:
	_servers = servers
	_refresh_server_list()


func _refresh_server_list() -> void:
	if _server_list == null:
		return
	_server_list.clear()
	for s: Dictionary in _servers:
		_server_list.add_item("%s  —  %s  (%d/%d)  %s" % [
			String(s.get("name", "?")), String(s.get("map", "?")),
			int(s.get("players", 0)), int(s.get("max", 0)), String(s.get("ip", "?"))])
	if _servers.is_empty():
		_server_list.add_item("Searching...  (hosts broadcast on UDP %d)" % Net.DISCOVERY_PORT)
		_server_list.set_item_disabled(0, true)


func _on_server_activated(idx: int) -> void:
	if idx < _servers.size():
		join_requested.emit(String(_servers[idx].ip))


func _mk_slider_row(box: VBoxContainer, label: String, min_v: float, max_v: float, step: float, fmt: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	row.add_child(_mk_label(label, 16, Color(0.7, 0.75, 0.8)))
	var value := _mk_label("", 16)
	row.add_child(value)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.custom_minimum_size = Vector2(0, 32)
	slider.value_changed.connect(func(v: float) -> void:
		value.text = fmt % v)
	box.add_child(slider)
	return [slider, value]


func _build_settings_panel() -> Control:
	var panel := PanelContainer.new()
	UiUtil.center(panel, 500, 660)
	panel.custom_minimum_size = Vector2(500, 660)
	panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_mk_label("SETTINGS", 30))

	box.add_child(_mk_label("Player name", 16, Color(0.7, 0.75, 0.8)))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 20
	box.add_child(_name_edit)

	var pair := _mk_slider_row(box, "Mouse sensitivity", 0.02, 1.0, 0.01, "%.2f")
	_sens_slider = pair[0]
	_sens_value = pair[1]
	pair = _mk_slider_row(box, "Touch sensitivity", 0.3, 3.0, 0.05, "%.2f")
	_touch_sens_slider = pair[0]
	_touch_sens_value = pair[1]
	pair = _mk_slider_row(box, "ADS sensitivity scale", 0.4, 1.5, 0.05, "%.2f")
	_ads_sens_slider = pair[0]
	_ads_sens_value = pair[1]
	pair = _mk_slider_row(box, "3D resolution scale", 0.7, 1.0, 0.05, "%.2f")
	_res_slider = pair[0]
	_res_value = pair[1]

	var touch_row := HBoxContainer.new()
	touch_row.add_theme_constant_override("separation", 8)
	box.add_child(touch_row)
	touch_row.add_child(_mk_label("Touch controls", 16, Color(0.7, 0.75, 0.8)))
	_touch_option = OptionButton.new()
	_touch_option.add_item("Auto (on for phones)")   # TouchMode.AUTO
	_touch_option.add_item("On")                     # TouchMode.ON
	_touch_option.add_item("Off")                    # TouchMode.OFF
	touch_row.add_child(_touch_option)

	_tap_fire_check = CheckBox.new()
	_tap_fire_check.text = "Touch: tap right half to fire"
	box.add_child(_tap_fire_check)
	_ads_check = CheckBox.new()
	_ads_check.text = "Toggle ADS (unchecked = hold)"
	box.add_child(_ads_check)
	_invert_check = CheckBox.new()
	_invert_check.text = "Invert Y axis"
	box.add_child(_invert_check)

	var back := _mk_button("SAVE & BACK", 18)
	back.pressed.connect(_save_settings)
	box.add_child(back)
	return panel


func _show_settings() -> void:
	_root_box.visible = false
	_settings_panel.visible = true
	_name_edit.text = Settings.player_name
	_sens_slider.value = Settings.mouse_sensitivity
	_sens_value.text = "%.2f" % Settings.mouse_sensitivity
	_touch_sens_slider.value = Settings.touch_sensitivity
	_touch_sens_value.text = "%.2f" % Settings.touch_sensitivity
	_ads_sens_slider.value = Settings.ads_sensitivity_scale
	_ads_sens_value.text = "%.2f" % Settings.ads_sensitivity_scale
	_res_slider.value = Settings.resolution_scale
	_res_value.text = "%.2f" % Settings.resolution_scale
	_touch_option.select(Settings.touch_mode)
	_tap_fire_check.button_pressed = Settings.touch_tap_fire
	_ads_check.button_pressed = Settings.ads_toggle_mode
	_invert_check.button_pressed = Settings.invert_y


func _save_settings() -> void:
	if _name_edit.text.strip_edges() != "":
		Settings.player_name = _name_edit.text.strip_edges()
	Settings.mouse_sensitivity = _sens_slider.value
	Settings.touch_sensitivity = _touch_sens_slider.value
	Settings.ads_sensitivity_scale = _ads_sens_slider.value
	Settings.resolution_scale = _res_slider.value
	Settings.touch_mode = _touch_option.selected
	Settings.touch_tap_fire = _tap_fire_check.button_pressed
	Settings.ads_toggle_mode = _ads_check.button_pressed
	Settings.invert_y = _invert_check.button_pressed
	Settings.apply_graphics()
	Settings.apply_touch_bindings()
	Settings.save_settings()
	_settings_panel.visible = false
	_root_box.visible = true

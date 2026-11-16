class_name BuyMenu
extends Control
## Buy-phase shop: weapons grid by category with prices + owned/affordable
## states, shields, and ability charges for the local agent. Every purchase
## is validated server-side (GameState.srv_buy); this UI just sends requests
## and re-renders from the replicated economy/loadout state.

const CATEGORIES := [
	["SIDEARMS", [&"classic", &"sheriff"]],
	["SMG", [&"spectre"]],
	["RIFLES", [&"phantom", &"vandal"]],
	["SNIPER", [&"operator"]],
]

var _player: Player = null
var _grid_box: VBoxContainer
var _credits_label: Label
var _status_label: Label
var _buttons: Array = []  # {btn, item, price, check: Callable -> String state}


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
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.04, 0.06, 0.72)
	add_child(dim)
	var panel := PanelContainer.new()
	UiUtil.center(panel, 660, 580)
	panel.custom_minimum_size = Vector2(660, 580)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	header.add_child(_mk_label("BUY", 32))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_credits_label = _mk_label("¤ 0", 28, Color(0.95, 0.85, 0.45))
	header.add_child(_credits_label)
	_grid_box = VBoxContainer.new()
	_grid_box.add_theme_constant_override("separation", 6)
	box.add_child(_grid_box)
	_status_label = _mk_label(" ", 16, Color(1, 0.6, 0.4))
	box.add_child(_status_label)
	var close_btn := Button.new()
	close_btn.text = "CLOSE" if Settings.touch_enabled() else "CLOSE  [B]"
	close_btn.custom_minimum_size = Vector2(0, 48)
	close_btn.pressed.connect(func() -> void:
		close()
		if DisplayServer.get_name() != "headless" and not Settings.touch_enabled() and GameState.match_running:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED))
	box.add_child(close_btn)
	GameState.economy_changed.connect(func() -> void:
		if visible:
			refresh())


func open(p: Player) -> void:
	_player = p
	if not _player.buy_result.is_connected(_on_buy_result):
		_player.buy_result.connect(_on_buy_result)
	_rebuild()
	visible = true


func close() -> void:
	visible = false


func _on_buy_result(ok: bool, reason: String) -> void:
	if ok:
		_status_label.text = " "
		Fx.play_sound_2d(self, _snd("confirmation_001"), -6.0)
	else:
		match reason:
			"credits": _status_label.text = "Not enough credits."
			"phase": _status_label.text = "You can only buy during the buy phase."
			"owned": _status_label.text = "Already owned."
			"max": _status_label.text = "Max charges."
			_: _status_label.text = "Can't buy that."
		Fx.play_sound_2d(self, _snd("error_001"), -6.0)
	if visible:
		refresh()


func _snd(base: String) -> AudioStream:
	var p := "res://assets/audio/ui/%s.ogg" % base
	return load(p) if ResourceLoader.exists(p) else null


func _rebuild() -> void:
	for c in _grid_box.get_children():
		c.queue_free()
	_buttons.clear()
	for cat: Array in CATEGORIES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_grid_box.add_child(row)
		var lbl := _mk_label(String(cat[0]), 16, Color(0.6, 0.68, 0.75))
		lbl.custom_minimum_size = Vector2(110, 0)
		row.add_child(lbl)
		for wid: StringName in cat[1]:
			var w := WeaponDB.get_weapon(wid)
			if w == null:
				continue
			_add_button(row, "%s  ¤%d" % [w.display_name, w.price], "weapon:%s" % wid, w.price,
				func() -> String:
					if _player == null:
						return "no"
					if (w.slot == WeaponData.Slot.PRIMARY and _player.primary_id == String(wid)) \
						or (w.slot == WeaponData.Slot.SECONDARY and _player.secondary_id == String(wid)):
						return "owned"
					return "buy")
	var shield_row := HBoxContainer.new()
	shield_row.add_theme_constant_override("separation", 8)
	_grid_box.add_child(shield_row)
	var slbl := _mk_label("SHIELDS", 16, Color(0.6, 0.68, 0.75))
	slbl.custom_minimum_size = Vector2(110, 0)
	shield_row.add_child(slbl)
	_add_button(shield_row, "Light Shield (+25)  ¤%d" % GameState.SHIELD_LIGHT_PRICE, "shield:light", GameState.SHIELD_LIGHT_PRICE,
		func() -> String:
			return "owned" if _player != null and _player.armor >= GameState.SHIELD_LIGHT_VALUE else "buy")
	_add_button(shield_row, "Heavy Shield (+50)  ¤%d" % GameState.SHIELD_HEAVY_PRICE, "shield:heavy", GameState.SHIELD_HEAVY_PRICE,
		func() -> String:
			return "owned" if _player != null and _player.armor >= GameState.SHIELD_HEAVY_VALUE else "buy")
	var ab_row := HBoxContainer.new()
	ab_row.add_theme_constant_override("separation", 8)
	_grid_box.add_child(ab_row)
	var albl := _mk_label("ABILITIES", 16, Color(0.6, 0.68, 0.75))
	albl.custom_minimum_size = Vector2(110, 0)
	ab_row.add_child(albl)
	var agent := AgentDB.get_agent(StringName(_player.agent_id)) if _player != null else null
	if agent != null:
		for slot in 3:
			var ab: AbilityData = agent.ability(slot)
			if ab == null:
				continue
			var slot_i := slot
			var ab_ref := ab
			if ab.signature:
				var sig := _mk_label("%s — signature (1 free/round)" % ab.display_name, 15, ab.icon_color)
				ab_row.add_child(sig)
				continue
			_add_button(ab_row, "%s  ¤%d" % [ab.display_name, ab.cost], "ability:%d" % slot, ab.cost,
				func() -> String:
					if _player == null:
						return "no"
					if _player.abilities.charges[slot_i] >= ab_ref.max_charges:
						return "max"
					return "buy")
	refresh()


func refresh() -> void:
	var credits := int(GameState.economy.get(Net.my_id(), 0))
	_credits_label.text = "¤ %d" % credits
	for entry: Dictionary in _buttons:
		var btn: Button = entry.btn
		if not is_instance_valid(btn):
			continue
		var state: String = (entry.check as Callable).call()
		match state:
			"owned":
				btn.disabled = true
				btn.text = String(entry.base_text) + "  [OWNED]"
			"max":
				btn.disabled = true
				btn.text = String(entry.base_text) + "  [MAX]"
			_:
				btn.text = String(entry.base_text)
				btn.disabled = credits < int(entry.price)


func _add_button(parent: Node, text: String, item: String, price: int, check: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(150, 48)
	var f := _font()
	if f != null:
		btn.add_theme_font_override("font", f)
	btn.pressed.connect(func() -> void:
		GameState.request_buy(item))
	parent.add_child(btn)
	_buttons.append({"btn": btn, "item": item, "price": price, "check": check, "base_text": text})

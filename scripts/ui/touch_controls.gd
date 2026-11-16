class_name TouchControls
extends Control
## Mobile tactical-shooter touch input layer, child of the HUD.
##
## Active only when Settings.touch_enabled() (auto on Android, forced via the
## Settings menu or the --touch CLI flag). All gameplay input is synthesized
## through the existing input actions (Input.action_press/release) plus
## Player.touch_move/touch_walk for the analog joystick, so the player /
## weapon / ability code paths are identical for desktop and touch.
##
## Multi-touch: every touch index is tracked and routed exactly once — to a
## virtual button, the floating joystick (left zone) or the aim area (right
## zone). Buttons are drawn in _draw() and hit-tested manually with a
## generous radius; Godot GUI is bypassed entirely while no modal menu is
## open (touches are consumed), and left alone when one is (so the buy menu
## / pause menu receive normal emulated-mouse taps).

const JOY_ZONE_X := 0.44        # left fraction of the screen that spawns the joystick
const JOY_RADIUS := 95.0
const JOY_KNOB_RADIUS := 38.0
const JOY_WALK_FRAC := 0.55     # deflection below this = walk (quiet)
const JOY_DEAD_FRAC := 0.16
const AIM_DEG_PER_PX := 0.24    # base aim sensitivity (scaled by Settings)
const TAP_FIRE_MS := 190
const TAP_FIRE_MAX_MOVE := 14.0
const HIT_SLOP := 1.45          # hit-test radius multiplier (generous targets)

const COL_BG := Color(0.05, 0.075, 0.105, 0.42)
const COL_BG_PRESSED := Color(0.28, 0.55, 0.5, 0.55)
const COL_RING := Color(0.85, 0.9, 0.95, 0.38)
const COL_RING_ACTIVE := Color(0.35, 1.0, 0.85, 0.85)
const COL_TEXT := Color(0.94, 0.96, 0.99, 0.9)

var hud: Node = null  # set by the HUD right after instantiation

var _buttons: Array = []          # ordered button dicts
var _by_id: Dictionary = {}
var _touches: Dictionary = {}     # touch index -> routing entry
var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_vec := Vector2.ZERO      # clamped -1..1 deflection
var _aim_index := -1
var _crouch_on := false
var _score_on := false
var _tap_fire_release_ms := 0
var _font: Font = null
var _was_modal := false
var _laid_out_size := Vector2.ZERO


func _ready() -> void:
	UiUtil.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fp := "res://assets/fonts/Rajdhani-SemiBold.ttf"
	if ResourceLoader.exists(fp):
		_font = load(fp)
	_build_buttons()
	resized.connect(_layout)
	_layout()


func _active() -> bool:
	return Settings.touch_enabled() and GameState.match_running


func _modal_open() -> bool:
	return hud != null and bool(hud.modal_ui_open())


func _player() -> Player:
	return GameState.local_player as Player


# ------------------------------------------------------------------
# Button table
# ------------------------------------------------------------------

func _mk_btn(id: String, label: String, r: float, kind: String, action := "", font_size := 18) -> void:
	var b := {
		"id": id, "label": label, "sub": "", "r": r, "kind": kind,
		"action": action, "font_size": font_size, "pos": Vector2.ZERO,
		"visible": true, "pressed_by": -1, "pips_max": 0, "pips": 0,
		"active": false,
	}
	_buttons.append(b)
	_by_id[id] = b


func _build_buttons() -> void:
	# Hit-test order = array order (all buttons before zones).
	_mk_btn("pause", "II", 26, "tap")
	_mk_btn("score", "SCORE", 26, "toggle_score", "", 13)
	_mk_btn("buy", "BUY", 30, "tap", "", 18)
	_mk_btn("interact", "PLANT", 54, "hold", "interact", 22)
	_mk_btn("fire_l", "FIRE", 46, "hold", "fire", 18)
	_mk_btn("fire_r", "FIRE", 62, "hold", "fire", 22)
	_mk_btn("ads", "ADS", 42, "hold", "ads", 18)
	_mk_btn("jump", "JUMP", 42, "hold", "jump", 16)
	_mk_btn("crouch", "CRCH", 36, "toggle_crouch", "", 15)
	_mk_btn("reload", "RLD", 36, "hold", "reload", 16)
	_mk_btn("weapon", "SWAP", 34, "tap", "", 14)
	for slot in 3:
		_mk_btn("ability%d" % slot, ["Q", "E", "X"][slot], 36, "ability", "", 18)
		_by_id["ability%d" % slot]["slot"] = slot


func _layout() -> void:
	var w := size.x
	var h := size.y
	var ins := _safe_insets()
	var l: float = ins.left
	var r: float = ins.right
	var t: float = ins.top
	var b: float = ins.bottom
	_by_id.pause.pos = Vector2(l + 50, t + 40)
	_by_id.score.pos = Vector2(w * 0.5 + 150, t + 40)
	_by_id.buy.pos = Vector2(w * 0.5 - 150, t + 44)
	_by_id.interact.pos = Vector2(w * 0.5 + 265, h - b - 195)
	_by_id.fire_l.pos = Vector2(l + 150, h - b - 330)
	_by_id.fire_r.pos = Vector2(w - r - 135, h - b - 135)
	_by_id.ads.pos = Vector2(w - r - 232, h - b - 295)
	_by_id.jump.pos = Vector2(w - r - 52, h - b - 300)
	_by_id.crouch.pos = Vector2(w - r - 320, h - b - 180)
	_by_id.reload.pos = Vector2(w - r - 320, h - b - 88)
	_by_id.weapon.pos = Vector2(w - r - 425, h - b - 70)
	for slot in 3:
		_by_id["ability%d" % slot].pos = Vector2(w * 0.5 - 80 + slot * 95, h - b - 56)


## Safe-area (notch) insets in logical pixels; mobile only.
func _safe_insets() -> Dictionary:
	var zero := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if not OS.has_feature("mobile"):
		return zero
	var win := get_window()
	var wpx := Vector2(win.size)
	if wpx.x <= 0 or wpx.y <= 0:
		return zero
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var sx := size.x / wpx.x
	var sy := size.y / wpx.y
	return {
		"left": maxf(safe.position.x, 0.0) * sx,
		"top": maxf(safe.position.y, 0.0) * sy,
		"right": maxf(wpx.x - safe.end.x, 0.0) * sx,
		"bottom": maxf(wpx.y - safe.end.y, 0.0) * sy,
	}


# ------------------------------------------------------------------
# Per-frame state (context visibility, action upkeep)
# ------------------------------------------------------------------

func _process(_delta: float) -> void:
	var on := _active()
	if visible != on:
		visible = on
		if not on:
			_release_all()
	if not on:
		return
	if size != _laid_out_size and size.x > 0:
		_laid_out_size = size
		_layout()
	var modal := _modal_open()
	if modal and not _was_modal:
		_release_all()
	_was_modal = modal
	_update_context()
	# Keep the analog vector applied even while the finger holds still.
	var p := _player()
	if p != null:
		if _joy_index >= 0 and p.alive and not modal:
			p.touch_move = _joy_vec
			p.touch_walk = _joy_vec.length() < JOY_WALK_FRAC
		else:
			p.touch_move = Vector2.ZERO
			p.touch_walk = false
	if _tap_fire_release_ms > 0 and Time.get_ticks_msec() >= _tap_fire_release_ms:
		_tap_fire_release_ms = 0
		Input.action_release("fire")
	queue_redraw()


func _update_context() -> void:
	var p := _player()
	var alive := p != null and p.alive
	var spike := GameState.mode == GameState.Mode.SPIKE
	_by_id.fire_r.visible = alive
	_by_id.fire_l.visible = alive
	_by_id.ads.visible = alive
	_by_id.jump.visible = alive
	_by_id.crouch.visible = alive
	_by_id.reload.visible = alive
	_by_id.weapon.visible = alive
	_by_id.pause.visible = true
	_by_id.score.visible = true
	_by_id.buy.visible = alive and spike and GameState.phase == GameState.RoundPhase.BUY
	var ctx := _interact_context(p) if alive and spike else ""
	var ib: Dictionary = _by_id.interact
	ib.visible = ctx != ""
	if ctx != "":
		ib.label = ctx
	# ADS button reflects the weapon's alt-fire behavior.
	if alive:
		var d := p.weapons.current_data()
		var ab: Dictionary = _by_id.ads
		if d != null and d.has_burst_alt():
			ab.label = "BURST"
		elif d != null and d.has_zoom_stages():
			ab.label = "ZOOM"
		else:
			ab.label = "ADS"
		ab.active = p.weapons.is_ads()
	_by_id.crouch.active = _crouch_on
	_by_id.score.active = _score_on
	# Ability pips.
	var show_ab := alive and spike
	for slot in 3:
		var btn: Dictionary = _by_id["ability%d" % slot]
		btn.visible = show_ab
		if not show_ab:
			continue
		var ability: AbilityData = p.abilities.ability(slot)
		if ability == null:
			btn.visible = false
			continue
		btn.pips_max = ability.max_charges
		btn.pips = int(p.abilities.charges[slot])
		btn["tint"] = ability.icon_color
	# A held button that turned invisible must release its action.
	for btn: Dictionary in _buttons:
		if not bool(btn.visible) and int(btn.pressed_by) >= 0:
			_release_button(btn)


func _interact_context(p: Player) -> String:
	var s: Dictionary = GameState.spike
	var state := int(s.get("state", -1))
	if GameState.phase == GameState.RoundPhase.ACTIVE \
			and state == GameState.SpikeState.CARRIED and int(s.get("carrier", 0)) == Net.my_id():
		for group: String in ["plant_zone_a", "plant_zone_b"]:
			for zone: Node in get_tree().get_nodes_in_group(group):
				if zone is Area3D and (zone as Area3D).overlaps_body(p):
					return "PLANT"
	elif GameState.phase == GameState.RoundPhase.PLANTED and int(p.team) == GameState.Team.DEFENDERS:
		var pos: Vector3 = s.get("pos", Vector3.ZERO)
		if p.global_position.distance_to(pos) <= GameState.DEFUSE_RADIUS + 0.4:
			return "DEFUSE"
	return ""


# ------------------------------------------------------------------
# Touch routing
# ------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _active() or _modal_open():
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_route_press(st.index, st.position)
		else:
			_route_release(st.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var dr := event as InputEventScreenDrag
		_route_drag(dr.index, dr.position, dr.relative)
		get_viewport().set_input_as_handled()


func _route_press(idx: int, pos: Vector2) -> void:
	_route_release(idx)  # defensive: stale entry for a reused index
	for btn: Dictionary in _buttons:
		if not bool(btn.visible) or int(btn.pressed_by) >= 0:
			continue
		if pos.distance_to(btn.pos) <= float(btn.r) * HIT_SLOP:
			btn.pressed_by = idx
			_touches[idx] = {"kind": "button", "btn": btn}
			_press_button(btn)
			return
	if pos.x < size.x * JOY_ZONE_X and pos.y > size.y * 0.22 and _joy_index < 0:
		_joy_index = idx
		_joy_origin = pos
		_joy_vec = Vector2.ZERO
		_touches[idx] = {"kind": "joy"}
		return
	# Right/rest of screen: aim. First finger rotates; extra fingers only
	# count as optional tap-to-fire.
	var kind := "aim" if _aim_index < 0 else "aim_extra"
	if kind == "aim":
		_aim_index = idx
	_touches[idx] = {"kind": kind, "start": pos, "start_ms": Time.get_ticks_msec(), "moved": 0.0}


func _route_drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if not _touches.has(idx):
		return
	var entry: Dictionary = _touches[idx]
	match String(entry.kind):
		"joy":
			var v := (pos - _joy_origin) / JOY_RADIUS
			if v.length() > 1.0:
				v = v.normalized()
			_joy_vec = v if v.length() >= JOY_DEAD_FRAC else Vector2.ZERO
		"aim", "aim_extra":
			entry.moved = float(entry.moved) + rel.length()
			if String(entry.kind) == "aim":
				_apply_aim(rel)
		"button":
			pass  # buttons stay held even if the finger slides off


func _route_release(idx: int) -> void:
	if not _touches.has(idx):
		return
	var entry: Dictionary = _touches[idx]
	_touches.erase(idx)
	match String(entry.kind):
		"button":
			_release_button(entry.btn)
		"joy":
			_joy_index = -1
			_joy_vec = Vector2.ZERO
			var p := _player()
			if p != null:
				p.touch_move = Vector2.ZERO
				p.touch_walk = false
		"aim", "aim_extra":
			if String(entry.kind) == "aim":
				_aim_index = -1
			if Settings.touch_tap_fire and Time.get_ticks_msec() - int(entry.start_ms) <= TAP_FIRE_MS \
					and float(entry.moved) <= TAP_FIRE_MAX_MOVE:
				var p := _player()
				if p != null and p.alive:
					Input.action_press("fire")
					_tap_fire_release_ms = Time.get_ticks_msec() + 70


func _apply_aim(rel: Vector2) -> void:
	var p := _player()
	if p == null or not p.alive:
		return
	var k := AIM_DEG_PER_PX * Settings.touch_sensitivity
	if p.weapons.is_ads():
		# Natural FOV-ratio scaling plus the user's ADS multiplier.
		k *= (p.camera.fov / 75.0) * Settings.ads_sensitivity_scale
	p.rotation.y -= deg_to_rad(rel.x * k)
	var dy := deg_to_rad(rel.y * k) * (-1.0 if Settings.invert_y else 1.0)
	p.head.rotation.x = clampf(p.head.rotation.x - dy, -1.55, 1.55)
	if p.weapons.view != null:
		p.weapons.view.add_sway(rel)


func _release_all() -> void:
	for btn: Dictionary in _buttons:
		if int(btn.pressed_by) >= 0:
			_release_button(btn)
	for action: StringName in [&"fire", &"ads", &"jump", &"reload", &"interact"]:
		Input.action_release(action)
	_touches.clear()
	_joy_index = -1
	_aim_index = -1
	_joy_vec = Vector2.ZERO
	var p := _player()
	if p != null:
		p.touch_move = Vector2.ZERO
		p.touch_walk = false
	# Crouch is a latched toggle: keep its action state consistent.
	if _crouch_on:
		Input.action_press("crouch")


func _press_button(btn: Dictionary) -> void:
	match String(btn.kind):
		"hold":
			Input.action_press(StringName(btn.action))
		"toggle_crouch":
			_crouch_on = not _crouch_on
			if _crouch_on:
				Input.action_press("crouch")
			else:
				Input.action_release("crouch")
		"toggle_score":
			_score_on = not _score_on
		"ability":
			var p := _player()
			if p != null and p.alive:
				p.abilities.try_cast(int(btn.slot))
		"tap":
			_tap_action(String(btn.id))


func _release_button(btn: Dictionary) -> void:
	btn.pressed_by = -1
	if String(btn.kind) == "hold":
		Input.action_release(StringName(btn.action))


func _tap_action(id: String) -> void:
	match id:
		"pause":
			if hud != null:
				hud.toggle_pause()
		"buy":
			if hud != null:
				hud.toggle_buy_menu()
		"weapon":
			var p := _player()
			if p != null and p.alive:
				p.weapons.cycle_slot()


## Read by the HUD: scoreboard stays open while toggled on.
func scoreboard_open() -> bool:
	return _score_on and _active()


func reset_scoreboard_toggle() -> void:
	_score_on = false


# ------------------------------------------------------------------
# Drawing
# ------------------------------------------------------------------

func _draw() -> void:
	if not _active() or _modal_open():
		return
	var p := _player()
	# Joystick: live base + knob, or a faint resting hint.
	if p != null and p.alive:
		if _joy_index >= 0:
			draw_circle(_joy_origin, JOY_RADIUS, Color(0.05, 0.075, 0.105, 0.3))
			draw_arc(_joy_origin, JOY_RADIUS, 0, TAU, 48, COL_RING, 2.0, true)
			var walk := _joy_vec.length() > 0.0 and _joy_vec.length() < JOY_WALK_FRAC
			var knob_col := Color(0.75, 0.85, 0.95, 0.55) if walk else Color(0.35, 1.0, 0.85, 0.6)
			draw_circle(_joy_origin + _joy_vec * JOY_RADIUS, JOY_KNOB_RADIUS, knob_col)
		else:
			var ins := _safe_insets()
			var rest := Vector2(float(ins.left) + 205, size.y - float(ins.bottom) - 185)
			draw_arc(rest, JOY_RADIUS * 0.7, 0, TAU, 40, Color(0.85, 0.9, 0.95, 0.14), 2.0, true)
			draw_circle(rest, JOY_KNOB_RADIUS * 0.5, Color(0.85, 0.9, 0.95, 0.1))
	for btn: Dictionary in _buttons:
		if not bool(btn.visible):
			continue
		_draw_button(btn)


func _draw_button(btn: Dictionary) -> void:
	var pos: Vector2 = btn.pos
	var r := float(btn.r)
	var pressed := int(btn.pressed_by) >= 0
	var active := bool(btn.active)
	draw_circle(pos, r, COL_BG_PRESSED if pressed else COL_BG)
	var ring := COL_RING_ACTIVE if (pressed or active) else COL_RING
	if btn.has("tint") and not pressed:
		ring = (btn.tint as Color)
		ring.a = 0.8 if int(btn.pips) > 0 else 0.3
	draw_arc(pos, r, 0, TAU, 48, ring, 2.5, true)
	if _font != null:
		var fs := int(btn.font_size)
		var label := String(btn.label)
		draw_string(_font, pos + Vector2(-r, fs * 0.36), label,
			HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, COL_TEXT)
	# Charge pips under ability buttons.
	var pips_max := int(btn.pips_max)
	if pips_max > 0:
		var pips := int(btn.pips)
		var y := pos.y + r + 10.0
		var x0 := pos.x - (pips_max - 1) * 7.0
		for i in pips_max:
			var c := Color(0.35, 1.0, 0.85, 0.95) if i < pips else Color(0.5, 0.55, 0.6, 0.5)
			draw_circle(Vector2(x0 + i * 14.0, y), 4.0, c)

extends Node
## Settings (autoload singleton) — user-facing options, persisted locally.
## Read/written from menus; gameplay code reads values every frame, so keep
## them as plain vars (no getters doing I/O).

const SETTINGS_PATH := "user://settings.cfg"

enum TouchMode { AUTO, ON, OFF }

var mouse_sensitivity: float = 0.2
## Touch aim sensitivity multiplier (1.0 = default feel).
var touch_sensitivity: float = 1.0
## Extra sensitivity scale applied while aiming down sights (on top of the
## natural FOV-ratio scaling).
var ads_sensitivity_scale: float = 0.9
var invert_y: bool = false
## false = hold RMB to ADS, true = RMB toggles ADS. Touch always toggles.
var ads_toggle_mode: bool = false
## AUTO = touch UI on mobile only. ON/OFF force it (desktop testing).
var touch_mode: int = TouchMode.AUTO
## Optional: a quick tap on the right (aim) half fires one shot.
var touch_tap_fire: bool = false
## 3D resolution scale (0.7-1.0), applied to the root viewport.
var resolution_scale: float = 1.0

var player_name: String = ""
var loadout_primary: String = "vandal"
var loadout_secondary: String = "classic"

## Set by the HUD while a modal UI (buy menu / pause / smoke targeting) is
## open, so touch gameplay input can be gated the way mouse capture gates
## desktop input.
var touch_block_gameplay := false

var _touch_bindings_stripped := false
var _stripped_events: Dictionary = {}  # action -> Array[InputEvent]


func _ready() -> void:
	resolution_scale = 0.85 if OS.has_feature("mobile") else 1.0
	load_settings()
	if player_name.strip_edges() == "":
		player_name = "Player%03d" % (randi() % 1000)
		save_settings()
	var cli_name := Cli.value("name", "")
	if cli_name != "":
		player_name = cli_name.substr(0, 20)
	apply_graphics.call_deferred()
	apply_touch_bindings()


## True when the touch UI should be shown / drive gameplay input.
func touch_enabled() -> bool:
	match touch_mode:
		TouchMode.ON:
			return true
		TouchMode.OFF:
			return false
		_:
			return OS.has_feature("mobile") or Cli.has_flag("touch")


## Unified "is gameplay input live" gate: desktop uses mouse capture, touch
## uses the modal flag maintained by the HUD.
func gameplay_input_active() -> bool:
	if touch_enabled():
		return not touch_block_gameplay
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED


func apply_graphics() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = clampf(resolution_scale, 0.5, 1.0)


## With touch UI active, taps must not trigger fire/ads through the emulated
## mouse (Android emulates mouse from touch for GUI). Strip the mouse-button
## bindings from those actions; the virtual buttons drive them via
## Input.action_press instead. Keyboard bindings stay for hybrid testing.
## Restores the bindings if touch mode is switched off again.
func apply_touch_bindings() -> void:
	if touch_enabled() and not _touch_bindings_stripped:
		_touch_bindings_stripped = true
		for action: StringName in [&"fire", &"ads"]:
			for ev: InputEvent in InputMap.action_get_events(action):
				if ev is InputEventMouseButton:
					if not _stripped_events.has(action):
						_stripped_events[action] = []
					(_stripped_events[action] as Array).append(ev)
					InputMap.action_erase_event(action, ev)
	elif not touch_enabled() and _touch_bindings_stripped:
		_touch_bindings_stripped = false
		for action: StringName in _stripped_events:
			for ev: InputEvent in _stripped_events[action]:
				InputMap.action_add_event(action, ev)
		_stripped_events.clear()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("input", "touch_sensitivity", touch_sensitivity)
	cfg.set_value("input", "ads_sensitivity_scale", ads_sensitivity_scale)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("input", "ads_toggle_mode", ads_toggle_mode)
	cfg.set_value("input", "touch_mode", touch_mode)
	cfg.set_value("input", "touch_tap_fire", touch_tap_fire)
	cfg.set_value("graphics", "resolution_scale", resolution_scale)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "loadout_primary", loadout_primary)
	cfg.set_value("player", "loadout_secondary", loadout_secondary)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)
	touch_sensitivity = cfg.get_value("input", "touch_sensitivity", touch_sensitivity)
	ads_sensitivity_scale = cfg.get_value("input", "ads_sensitivity_scale", ads_sensitivity_scale)
	invert_y = cfg.get_value("input", "invert_y", invert_y)
	ads_toggle_mode = cfg.get_value("input", "ads_toggle_mode", ads_toggle_mode)
	touch_mode = cfg.get_value("input", "touch_mode", touch_mode)
	touch_tap_fire = cfg.get_value("input", "touch_tap_fire", touch_tap_fire)
	resolution_scale = cfg.get_value("graphics", "resolution_scale", resolution_scale)
	player_name = cfg.get_value("player", "name", player_name)
	loadout_primary = cfg.get_value("player", "loadout_primary", loadout_primary)
	loadout_secondary = cfg.get_value("player", "loadout_secondary", loadout_secondary)

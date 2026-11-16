class_name SpikeEntity
extends Node3D
## World representation of the spike, driven purely by the replicated
## GameState.spike dictionary (no RPCs of its own): shown on the carrier's
## back, as a glowing dropped pickup, or planted with escalating beeps
## (assets/audio/ui/spike_beep*.wav) until detonation/defuse.

const BEEP_FAST_UNDER := 10.0

var _mesh_root: Node3D
var _light: OmniLight3D
var _audio: AudioStreamPlayer3D
var _beep_in := 0.0
var _bob_t := 0.0

var _beep: AudioStream = null
var _beep_fast: AudioStream = null


func _ready() -> void:
	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.38, 0.18)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.22, 0.25)
	m.emission_enabled = true
	m.emission = Color(0.9, 0.25, 0.2)
	m.emission_energy_multiplier = 0.8
	bm.material = m
	body.mesh = bm
	body.position = Vector3(0, 0.19, 0)
	_mesh_root.add_child(body)
	var antenna := MeshInstance3D.new()
	var am := CylinderMesh.new()
	am.top_radius = 0.012
	am.bottom_radius = 0.012
	am.height = 0.3
	am.material = Fx.unshaded_mat(Color(0.9, 0.3, 0.25))
	antenna.mesh = am
	antenna.position = Vector3(0.1, 0.5, 0)
	_mesh_root.add_child(antenna)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.3, 0.2)
	_light.omni_range = 4.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 0.45, 0)
	_mesh_root.add_child(_light)
	_audio = AudioStreamPlayer3D.new()
	_audio.unit_size = 16.0
	_audio.max_distance = 120.0
	add_child(_audio)
	if ResourceLoader.exists("res://assets/audio/ui/spike_beep.wav"):
		_beep = load("res://assets/audio/ui/spike_beep.wav")
	if ResourceLoader.exists("res://assets/audio/ui/spike_beep_fast.wav"):
		_beep_fast = load("res://assets/audio/ui/spike_beep_fast.wav")


func _process(delta: float) -> void:
	var s: Dictionary = GameState.spike
	if s.is_empty() or GameState.mode != GameState.Mode.SPIKE:
		visible = false
		return
	match int(s.get("state", -1)):
		GameState.SpikeState.CARRIED:
			var carrier := int(s.get("carrier", 0))
			var node: Node3D = get_tree().current_scene.get_node_or_null("Players/%d" % carrier)
			if node != null and bool(node.get("alive")):
				visible = true
				# On the carrier's back (forward is -Z, so back is +Z).
				global_position = node.global_position + node.global_basis.z * 0.32 + Vector3.UP * 1.05
				rotation.y = node.rotation.y
				_light.light_energy = 0.0
			else:
				visible = false
		GameState.SpikeState.DROPPED:
			visible = true
			_bob_t += delta * 2.0
			var pos: Vector3 = s.get("pos", Vector3.ZERO)
			global_position = pos + Vector3.UP * (0.15 + sin(_bob_t) * 0.08)
			rotation.y += delta * 1.5
			_light.light_color = Color(1.0, 0.85, 0.3)
			_light.light_energy = 1.2 + sin(_bob_t * 2.0) * 0.6
		GameState.SpikeState.PLANTED:
			visible = true
			global_position = Vector3(s.get("pos", Vector3.ZERO))
			_light.light_color = Color(1.0, 0.3, 0.2)
			_tick_beeps(delta)
		_:
			visible = false


func _tick_beeps(delta: float) -> void:
	var window := GameState.cfg_detonate
	var left := GameState.match_time_left
	var frac := clampf(left / maxf(window, 0.1), 0.0, 1.0)
	_beep_in -= delta
	_light.light_energy = maxf(_light.light_energy - delta * 8.0, 0.4)
	if _beep_in <= 0.0:
		_beep_in = lerpf(0.12, 1.0, pow(frac, 1.25))
		var fast := left <= BEEP_FAST_UNDER
		var stream := _beep_fast if fast and _beep_fast != null else _beep
		if stream != null:
			_audio.stream = stream
			_audio.pitch_scale = 1.15 if left <= 5.0 else 1.0
			_audio.play()
		_light.light_energy = 2.5

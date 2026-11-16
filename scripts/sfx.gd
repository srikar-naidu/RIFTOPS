class_name Sfx
extends RefCounted
## Sound lookup with synthesized fallbacks. If the asset agent has delivered
## real SFX at res://assets/audio/guns/{weapon_id}_fire.(ogg|wav) they are used
## automatically; otherwise a procedural placeholder is generated at runtime.

const RATE := 22050

static var _cache: Dictionary = {}


static func fire_stream(w: WeaponData) -> AudioStream:
	var key := "fire_" + String(w.id)
	if _cache.has(key):
		return _cache[key]
	var s: AudioStream = null
	if w.fire_sound_path != "" and ResourceLoader.exists(w.fire_sound_path):
		s = load(w.fire_sound_path)
	else:
		for ext: String in ["ogg", "wav"]:
			var p := "res://assets/audio/guns/%s_fire.%s" % [w.id, ext]
			if ResourceLoader.exists(p):
				s = load(p)
				break
	if s == null:
		s = _synth_for(w)
	_cache[key] = s
	return s


## Preferred real assets per UI cue (delivered by the asset agent, see
## docs/ASSETS.md); falls back to assets/audio/ui/{kind}.* then to synth.
const UI_ASSET_CANDIDATES := {
	"hit": ["res://assets/audio/ui/tick_001.ogg"],
	"headshot": ["res://assets/audio/foley/impactBell_heavy_000.ogg"],
	"dry": ["res://assets/audio/foley/metalClick.ogg"],
	"reload": ["res://assets/audio/foley/beltHandle1.ogg"],
}

const DEATH_GRUNTS := [
	"res://assets/audio/foley/grunt_die1.wav",
	"res://assets/audio/foley/grunt_die2.wav",
	"res://assets/audio/foley/grunt_deathh.wav",
]

const FOOTSTEPS := [
	"res://assets/audio/foley/footstep_concrete_000.ogg",
	"res://assets/audio/foley/footstep_concrete_001.ogg",
	"res://assets/audio/foley/footstep_concrete_002.ogg",
	"res://assets/audio/foley/footstep_concrete_003.ogg",
	"res://assets/audio/foley/footstep_concrete_004.ogg",
]


static func death_grunt() -> AudioStream:
	var options: Array = []
	for p: String in DEATH_GRUNTS:
		if ResourceLoader.exists(p):
			options.append(p)
	if options.is_empty():
		return null
	return load(options[randi() % options.size()])


static func footstep_stream() -> AudioStream:
	if not _cache.has("footsteps"):
		var list: Array = []
		for p: String in FOOTSTEPS:
			if ResourceLoader.exists(p):
				list.append(load(p))
		_cache["footsteps"] = list
	var options: Array = _cache["footsteps"]
	if options.is_empty():
		return null
	return options[randi() % options.size()]


static func ui_stream(kind: String) -> AudioStream:
	var key := "ui_" + kind
	if _cache.has(key):
		return _cache[key]
	for cand: String in UI_ASSET_CANDIDATES.get(kind, []):
		if ResourceLoader.exists(cand):
			var pre: AudioStream = load(cand)
			_cache[key] = pre
			return pre
	for ext: String in ["ogg", "wav"]:
		var p := "res://assets/audio/ui/%s.%s" % [kind, ext]
		if ResourceLoader.exists(p):
			var loaded: AudioStream = load(p)
			_cache[key] = loaded
			return loaded
	var s: AudioStream
	match kind:
		"hit":
			s = _synth_tone(2200.0, 0.05, 0.35, 70.0)
		"headshot":
			s = _concat([_synth_tone(1760.0, 0.04, 0.4, 60.0), _synth_tone(2637.0, 0.06, 0.4, 55.0)])
		"kill":
			s = _concat([_synth_tone(880.0, 0.06, 0.45, 40.0), _synth_tone(1318.0, 0.1, 0.45, 35.0)])
		"dry":
			s = _synth_tone(1500.0, 0.025, 0.3, 160.0)
		_:
			s = _synth_tone(1000.0, 0.05, 0.3, 80.0)
	_cache[key] = s
	return s


static func _synth_for(w: WeaponData) -> AudioStreamWAV:
	match String(w.id):
		"knife":
			return _synth_whoosh()
		"classic":
			return _synth_shot(0.09, 1250.0, 55.0, 0.5)
		"sheriff":
			return _synth_shot(0.17, 300.0, 30.0, 0.85)
		"spectre":
			return _synth_shot(0.06, 950.0, 60.0, 0.45)
		"phantom":
			return _synth_shot(0.07, 500.0, 55.0, 0.3)
		"vandal":
			return _synth_shot(0.12, 620.0, 40.0, 0.75)
		"operator":
			return _synth_shot(0.26, 190.0, 20.0, 1.0)
		_:
			return _synth_shot(0.1, 700.0, 45.0, 0.65)


static func _pack(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav


static func _synth_shot(dur: float, thump_hz: float, decay: float, amp: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(thump_hz)
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * decay)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.4
		var thump := sin(TAU * thump_hz * t) * exp(-t * decay * 0.55)
		s[i] = (lp * 0.85 + thump * 0.7) * env * amp
	return _pack(s)


static func _synth_whoosh() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var dur := 0.14
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * t / dur)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.12
		s[i] = lp * env * 0.5
	return _pack(s)


static func _synth_tone(freq: float, dur: float, amp: float, decay: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = sin(TAU * freq * t) * exp(-t * decay) * amp
	return _pack(s)


static func _concat(streams: Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	for st: AudioStreamWAV in streams:
		data.append_array(st.data)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav

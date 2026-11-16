class_name EffectsManager
extends Node3D
## Replicated world effects for abilities + the spike explosion. Lives in
## match.tscn as "Effects" on every peer (stable path => RPC surface).
##
## The server executes casts (server_execute), owns all effect state (fire
## ticks, wall HP, recon pulses, expiries) and broadcasts cl_spawn/cl_event/
## cl_end so every peer builds identical local visuals/collision. Zone
## queries (slow/stim) read the replicated effect list locally on each peer,
## because movement is owner-authoritative.

# --- ability tuning ---
const SMOKE_RADIUS := 4.0
const CLOUDBURST_DURATION := 4.5
const SKY_SMOKE_DURATION := 15.0
const SKY_SMOKE_RANGE := 50.0
const SKY_SMOKE_DROP_DELAY := 1.0
const MOLLY_RADIUS := 3.5
const MOLLY_DURATION := 5.5
const MOLLY_TICK := 0.5
const MOLLY_DPS := 8.0          # enemies full, allies half (documented choice)
const STIM_RADIUS := 12.0
const STIM_DURATION := 12.0
const SLOW_RADIUS := 3.0
const SLOW_DURATION := 7.0
const SLOW_MULT := 0.35         # 65% slow
const WALL_SEGMENTS := 4
const WALL_SEG_WIDTH := 1.25
const WALL_HEIGHT := 2.5
const WALL_THICKNESS := 0.3
const WALL_HP := 400
const WALL_PLACE_DIST := 3.5
const HEAL_RANGE := 10.0
const HEAL_TOTAL := 100         # Sage patch 13.00: 100hp over 5s (self too)
const HEAL_DURATION := 5.0
const FLASH_RANGE := 25.0
const FLASH_FUSE := 0.6
const FLASH_MAX_DURATION := 2.0
const RECON_RANGE := 15.0
const RECON_PULSES := 2
const RECON_PULSE_GAP := 1.5
const RECON_REVEAL := 2.0
const CONCUSS_RADIUS := 5.0
const CONCUSS_DURATION := 4.0

const SND_WHOOSH := "res://assets/audio/foley/thrusterFire_001.ogg"
const SND_DASH := "res://assets/audio/foley/thrusterFire_000.ogg"
const SND_WALL := "res://assets/audio/foley/forceField_000.ogg"
const SND_SMOKE := "res://assets/audio/foley/forceField_001.ogg"
const SND_GLASS := "res://assets/audio/foley/impactGlass_heavy_001.ogg"
const SND_EXPLODE := "res://assets/audio/foley/explosionCrunch_000.ogg"
const SND_EXPLODE_FAR := "res://assets/audio/foley/lowFrequency_explosion_000.ogg"
const SND_FIRE_LOOP := "res://assets/audio/foley/fire_loop.ogg"

var _next_id := 1
## Every peer: id -> {"kind": String, "params": Dictionary, "node": Node3D}
var _effects: Dictionary = {}
## Server only: id -> per-kind authoritative state.
var _srv: Dictionary = {}


func _ready() -> void:
	add_to_group("effects_manager")
	GameState.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(p: int) -> void:
	# Round reset: all lingering effects end when a new buy phase starts.
	if multiplayer.is_server() and p == GameState.RoundPhase.BUY:
		for id: int in _srv.keys().duplicate():
			_end(id)


# ------------------------------------------------------------------
# Server cast execution
# ------------------------------------------------------------------

func server_execute(caster: Player, ability: AbilityData, origin: Vector3, dir: Vector3, target: Vector3) -> bool:
	if not multiplayer.is_server():
		return false
	match String(ability.id):
		"dash", "updraft":
			_sound(SND_DASH, caster.global_position, -4.0)
			return true
		"cloudburst":
			_launch(caster, "cloudburst", origin, dir * 14.0 + Vector3.UP * 2.0, 1.2, "res://assets/weapons/Grenade.gltf")
			return true
		"sky_smoke":
			var flat := Vector2(target.x - caster.global_position.x, target.z - caster.global_position.z)
			if flat.length() > SKY_SMOKE_RANGE:
				return false
			var id := _new_id()
			_srv[id] = {"kind": "sky_pending", "at": Time.get_ticks_msec() + int(SKY_SMOKE_DROP_DELAY * 1000.0), "target": target}
			_sound(SND_WHOOSH, caster.global_position, -6.0)
			return true
		"molly":
			_launch(caster, "molly", origin, dir * 12.0 + Vector3.UP * 4.5, 3.0, "res://assets/weapons/FireGrenade.gltf")
			return true
		"stim":
			_launch(caster, "stim", origin, dir * 8.0 + Vector3.UP * 2.0, 2.0, "res://assets/weapons/Grenade.gltf")
			return true
		"wall":
			return _try_place_wall(caster)
		"slow":
			_launch(caster, "slow", origin, dir * 13.0 + Vector3.UP * 3.0, 2.5, "res://assets/weapons/Grenade.gltf")
			return true
		"heal":
			return _do_heal(caster, origin, dir)
		"flash":
			_launch(caster, "flash", origin, dir * 16.0 + Vector3.UP * 1.5, FLASH_FUSE, "res://assets/weapons/Grenade.gltf")
			return true
		"recon":
			_launch(caster, "recon", origin, dir * 18.0 + Vector3.UP * 2.0, 3.0, "res://assets/weapons/Grenade.gltf")
			return true
		"concuss":
			_launch(caster, "concuss", origin, dir * 14.0 + Vector3.UP * 3.0, 1.0, "res://assets/weapons/Grenade.gltf")
			return true
	return false


func _launch(caster: Player, kind: String, origin: Vector3, vel: Vector3, fuse: float, model: String) -> void:
	var id := _new_id()
	var params := {"kind": kind, "pos": origin + vel.normalized() * 0.4, "vel": vel, "fuse": fuse, "model": model,
		"caster": caster.peer_id(), "caster_name": caster.player_name, "caster_team": caster.team}
	_srv[id] = {"kind": "projectile", "caster": caster.peer_id(), "caster_name": caster.player_name, "caster_team": caster.team}
	rpc("cl_spawn", "projectile", id, params)
	_sound(SND_WHOOSH, origin, -8.0)


func server_projectile_done(id: int, kind: String, pos: Vector3) -> void:
	if not multiplayer.is_server() or not _srv.has(id):
		return
	var meta: Dictionary = _srv[id]
	_end(id)  # remove projectile visuals everywhere
	match kind:
		"cloudburst":
			_spawn_smoke(pos, CLOUDBURST_DURATION)
		"molly":
			var fid := _spawn_zone("fire", _ground(pos), MOLLY_RADIUS, MOLLY_DURATION)
			_srv[fid].merge({"tick": 0.0, "caster": meta.caster, "caster_name": meta.caster_name, "caster_team": meta.caster_team})
		"stim":
			_spawn_zone("stim", _ground(pos), STIM_RADIUS, STIM_DURATION, {"team": meta.caster_team})
		"slow":
			_spawn_zone("slow", _ground(pos), SLOW_RADIUS, SLOW_DURATION)
		"flash":
			_resolve_flash(pos, meta)
		"recon":
			var rid := _new_id()
			var ground := _ground(pos)
			_srv[rid] = {"kind": "recon", "pos": ground, "pulses": RECON_PULSES,
				"next": Time.get_ticks_msec(), "caster_team": meta.caster_team, "caster_name": meta.caster_name}
			rpc("cl_spawn", "recon_sensor", rid, {"pos": ground})
		"concuss":
			_resolve_concuss(pos, meta)


func _new_id() -> int:
	_next_id += 1
	return _next_id


func _spawn_smoke(pos: Vector3, duration: float) -> int:
	return _spawn_zone("smoke", _ground(pos), SMOKE_RADIUS, duration)


func _spawn_zone(kind: String, pos: Vector3, radius: float, duration: float, extra: Dictionary = {}) -> int:
	var id := _new_id()
	_srv[id] = {"kind": kind, "pos": pos, "radius": radius, "until": Time.get_ticks_msec() + int(duration * 1000.0)}
	var params := {"pos": pos, "radius": radius, "duration": duration}
	params.merge(extra)
	rpc("cl_spawn", kind, id, params)
	if Cli.test_mode():
		print("[TEST] effect %s spawned id=%d r=%.1f dur=%.1f" % [kind, id, radius, duration])
	return id


func _ground(pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.0, pos + Vector3.DOWN * 40.0, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit.position
	return pos


# --- wall ---

func _try_place_wall(caster: Player) -> bool:
	var fwd := -caster.head.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = -caster.global_basis.z
		fwd.y = 0.0
	fwd = fwd.normalized()
	var yaw := atan2(fwd.x, fwd.z)
	var right := fwd.cross(Vector3.UP).normalized()
	var center := caster.global_position + fwd * WALL_PLACE_DIST
	var segs: Array = []
	for i in WALL_SEGMENTS:
		var offset := (float(i) - (WALL_SEGMENTS - 1) * 0.5) * WALL_SEG_WIDTH
		var p := center + right * offset
		p = _ground(p)
		p.y += WALL_HEIGHT * 0.5
		# Refuse placement that would trap a player inside a segment.
		for node: Node in get_tree().get_nodes_in_group("players"):
			var n3 := node as Node3D
			var dxz := Vector2(n3.global_position.x - p.x, n3.global_position.z - p.z).length()
			if dxz < 0.95 and absf(n3.global_position.y + 0.9 - p.y) < 2.2:
				return false
		segs.append(p)
	var id := _new_id()
	var hp: Array = []
	for i in WALL_SEGMENTS:
		hp.append(WALL_HP)
	_srv[id] = {"kind": "wall", "hp": hp, "alive": WALL_SEGMENTS, "until": Time.get_ticks_msec() + 40000}
	rpc("cl_spawn", "wall", id, {"segs": segs, "yaw": yaw})
	if Cli.test_mode():
		print("[TEST] effect wall spawned id=%d segs=%d" % [id, segs.size()])
	return true


func server_wall_damage(effect_id: int, seg_index: int, dmg: int) -> void:
	if not multiplayer.is_server() or not _srv.has(effect_id):
		return
	var st: Dictionary = _srv[effect_id]
	if String(st.kind) != "wall" or seg_index < 0 or seg_index >= st.hp.size():
		return
	if int(st.hp[seg_index]) <= 0:
		return
	st.hp[seg_index] = int(st.hp[seg_index]) - dmg
	if Cli.test_mode():
		print("[TEST] wall_hit id=%d seg=%d hp=%d" % [effect_id, seg_index, int(st.hp[seg_index])])
	if int(st.hp[seg_index]) <= 0:
		st.alive = int(st.alive) - 1
		rpc("cl_event", effect_id, "seg_break", {"i": seg_index})
		if int(st.alive) <= 0:
			_end(effect_id)


# --- heal ---

func _do_heal(caster: Player, origin: Vector3, dir: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * HEAL_RANGE, 0b10, [caster.get_rid()])
	var hit := space.intersect_ray(q)
	var target := caster
	if not hit.is_empty() and hit.collider is Player:
		var cand := hit.collider as Player
		if cand.team == caster.team and cand.alive:
			target = cand
	target.server_heal(HEAL_TOTAL, HEAL_DURATION)
	_sound(SND_WALL, target.global_position, -8.0)
	if Cli.test_mode():
		print("[TEST] heal_target peer=%d self=%s" % [target.peer_id(), str(target == caster)])
	return true


# --- flash ---

func _resolve_flash(pos: Vector3, meta: Dictionary) -> void:
	rpc("cl_spawn", "flashpop", 0, {"pos": pos})
	for node: Node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == null or not p.alive:
			continue
		var eye := p.global_position + Vector3.UP * Player.STAND_EYE
		var dist := eye.distance_to(pos)
		if dist > FLASH_RANGE:
			continue
		if _los_blocked(pos, eye, []):
			continue
		var to_flash := (pos - eye).normalized()
		var facing := -p.head.global_basis.z
		var dot := facing.dot(to_flash)
		var factor := 1.0
		if dot < -0.2:
			factor = 0.25   # looking away: short blind
		elif dot < 0.25:
			factor = 0.6
		var duration := lerpf(FLASH_MAX_DURATION, 1.2, clampf(dist / FLASH_RANGE, 0.0, 1.0)) * factor
		if duration < 0.2:
			continue
		p.server_apply_flash(factor, duration)
		if Cli.test_mode():
			print("[TEST] flash_applied peer=%d factor=%.2f dur=%.2f" % [p.peer_id(), factor, duration])


# --- concuss ---

func _resolve_concuss(pos: Vector3, _meta: Dictionary) -> void:
	rpc("cl_spawn", "concussblast", 0, {"pos": pos})
	for node: Node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == null or not p.alive:
			continue
		if p.global_position.distance_to(pos) > CONCUSS_RADIUS:
			continue
		p.server_apply_concuss(CONCUSS_DURATION)  # allies are affected too
		if Cli.test_mode():
			print("[TEST] concuss_hit peer=%d" % p.peer_id())


# --- spike detonation FX (damage handled by GameState) ---

func server_spike_explosion(pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	rpc("cl_spawn", "explosion", 0, {"pos": pos, "scale": 3.0})


# ------------------------------------------------------------------
# Server tick: expiries, fire ticks, recon pulses, delayed sky smokes
# ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _srv.is_empty():
		return
	var now := Time.get_ticks_msec()
	for id: int in _srv.keys().duplicate():
		if not _srv.has(id):
			continue
		var st: Dictionary = _srv[id]
		match String(st.kind):
			"sky_pending":
				if now >= int(st.at):
					var t: Vector3 = st.target
					_srv.erase(id)
					_spawn_smoke(t + Vector3.UP * 0.2, SKY_SMOKE_DURATION)
			"fire":
				st.tick = float(st.tick) + delta
				if float(st.tick) >= MOLLY_TICK:
					st.tick = float(st.tick) - MOLLY_TICK
					_fire_tick(st)
				if now >= int(st.until):
					_end(id)
			"recon":
				if int(st.pulses) > 0 and now >= int(st.next):
					st.pulses = int(st.pulses) - 1
					st.next = now + int(RECON_PULSE_GAP * 1000.0)
					_recon_pulse(id, st)
				elif int(st.pulses) <= 0 and now >= int(st.get("next", 0)) + 500:
					_end(id)
			"smoke", "slow", "stim", "wall":
				if now >= int(st.until):
					_end(id)


func _fire_tick(st: Dictionary) -> void:
	var pos: Vector3 = st.pos
	var caster_team := int(st.caster_team)
	var dmg_enemy := int(round(MOLLY_DPS * MOLLY_TICK))
	for node: Node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p == null or not p.alive:
			continue
		var dxz := Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length()
		if dxz > float(st.radius) or absf(p.global_position.y - pos.y) > 2.2:
			continue
		var dmg := dmg_enemy if p.team != caster_team else maxi(dmg_enemy / 2, 1)
		p.server_apply_ability_damage(dmg, String(st.caster_name), caster_team, int(st.caster), "molly")
		if Cli.test_mode():
			print("[TEST] molly_tick peer=%d dmg=%d hp=%d" % [p.peer_id(), dmg, p.health])


func _recon_pulse(id: int, st: Dictionary) -> void:
	var pos: Vector3 = st.pos
	rpc("cl_event", id, "pulse", {})
	var caster_team := int(st.caster_team)
	var targets: Array = []
	targets.append_array(get_tree().get_nodes_in_group("players"))
	targets.append_array(get_tree().get_nodes_in_group("dummy_targets"))
	for node: Node in targets:
		var n3 := node as Node3D
		if n3 == null or not bool(node.get("alive")):
			continue
		var t_team := int(node.get("team")) if node.get("team") != null else 0
		if t_team == caster_team:
			continue
		var eye := n3.global_position + Vector3.UP * 1.2
		if eye.distance_to(pos + Vector3.UP * 0.5) > RECON_RANGE:
			continue
		if _los_blocked(pos + Vector3.UP * 0.5, eye, []):
			continue
		if node is Player:
			(node as Player).server_reveal(RECON_REVEAL)
		if Cli.test_mode():
			print("[TEST] recon_ping target=%s" % String(node.get("player_name")))


## World + smoke LOS check (used by flash and recon).
func _los_blocked(from: Vector3, to: Vector3, exclude: Array) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, exclude)
	if not space.intersect_ray(q).is_empty():
		return true
	return _smoke_blocks(from, to)


func _smoke_blocks(a: Vector3, b: Vector3) -> bool:
	for id: int in _effects:
		var e: Dictionary = _effects[id]
		if String(e.kind) != "smoke":
			continue
		var c: Vector3 = e.params.pos + Vector3.UP * float(e.params.radius) * 0.5
		var ab := b - a
		var len2 := ab.length_squared()
		var t := 0.0 if len2 < 0.0001 else clampf((c - a).dot(ab) / len2, 0.0, 1.0)
		if (a + ab * t).distance_to(c) < float(e.params.radius) * 0.85:
			return true
	return false


# ------------------------------------------------------------------
# Zone queries (run locally on every peer from the replicated list)
# ------------------------------------------------------------------

func slow_mult_for(player: Node3D) -> float:
	var m := 1.0
	for id: int in _effects:
		var e: Dictionary = _effects[id]
		if String(e.kind) != "slow":
			continue
		var pos: Vector3 = e.params.pos
		var dxz := Vector2(player.global_position.x - pos.x, player.global_position.z - pos.z).length()
		if dxz <= float(e.params.radius) and absf(player.global_position.y - pos.y) < 2.5:
			m = minf(m, SLOW_MULT)
	return m


func stim_active_for(player: Node) -> bool:
	for id: int in _effects:
		var e: Dictionary = _effects[id]
		if String(e.kind) != "stim":
			continue
		if int(e.params.get("team", 0)) != int(player.get("team")):
			continue
		var pos: Vector3 = e.params.pos
		var p3 := player as Node3D
		var dxz := Vector2(p3.global_position.x - pos.x, p3.global_position.z - pos.z).length()
		if dxz <= float(e.params.radius) and absf(p3.global_position.y - pos.y) < 4.0:
			return true
	return false


# ------------------------------------------------------------------
# Replication: every peer builds identical local effect nodes
# ------------------------------------------------------------------

func _end(id: int) -> void:
	_srv.erase(id)
	rpc("cl_end", id)


@rpc("authority", "call_local", "reliable")
func cl_spawn(kind: String, id: int, params: Dictionary) -> void:
	# One-shot FX kinds are not tracked.
	match kind:
		"sound":
			_play_path(String(params.get("path", "")), params.get("pos", Vector3.ZERO), float(params.get("db", 0.0)))
			return
		"explosion":
			_build_explosion(params.get("pos", Vector3.ZERO), float(params.get("scale", 1.0)))
			return
		"flashpop":
			_play_path(SND_GLASS, params.get("pos", Vector3.ZERO), -2.0)
			return
		"concussblast":
			_build_blast_ring(params.get("pos", Vector3.ZERO), Color(0.9, 0.7, 1.0))
			_play_path(SND_EXPLODE, params.get("pos", Vector3.ZERO), -8.0)
			return
	var node: Node3D = null
	match kind:
		"projectile":
			node = AbilityProjectile.create(id, params, self, multiplayer.is_server())
			add_child(node)
		"smoke":
			node = _build_smoke(params)
		"fire":
			node = _build_fire(params)
		"slow":
			node = _build_slow(params)
		"stim":
			node = _build_stim(params)
		"wall":
			_build_wall(id, params)  # stores its own _effects entry (with segs)
			return
		"recon_sensor":
			node = _build_recon(params)
	if node != null:
		_effects[id] = {"kind": kind, "params": params, "node": node}


@rpc("authority", "call_local", "reliable")
func cl_event(id: int, ev: String, params: Dictionary) -> void:
	if not _effects.has(id):
		return
	var e: Dictionary = _effects[id]
	match ev:
		"seg_break":
			var segs: Array = e.get("segs", [])
			var i := int(params.get("i", -1))
			if i >= 0 and i < segs.size() and is_instance_valid(segs[i]):
				_play_path(SND_GLASS, (segs[i] as Node3D).global_position, -4.0)
				(segs[i] as Node).queue_free()
		"pulse":
			var node: Node3D = e.node
			if is_instance_valid(node):
				_build_pulse_ring(node.global_position)


@rpc("authority", "call_local", "reliable")
func cl_end(id: int) -> void:
	if not _effects.has(id):
		return
	var node: Node = _effects[id].node
	if is_instance_valid(node):
		node.queue_free()
	_effects.erase(id)


# ------------------------------------------------------------------
# Visual builders (local, per peer)
# ------------------------------------------------------------------

func _play_path(path: String, pos: Vector3, db: float) -> void:
	if path != "" and ResourceLoader.exists(path):
		Fx.play_sound_3d(get_tree().current_scene, load(path), pos, db)


func _sound(path: String, pos: Vector3, db := 0.0) -> void:
	rpc("cl_spawn", "sound", 0, {"path": path, "pos": pos, "db": db})


func _zone_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _build_smoke(params: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = params.pos
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = float(params.radius)
	mesh.height = float(params.radius) * 2.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.76, 0.79, 0.84)
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # opaque from inside too
	mesh.material = m
	mi.mesh = mesh
	mi.position = Vector3(0, float(params.radius) * 0.5, 0)
	root.add_child(mi)
	_play_path(SND_SMOKE, params.pos, -6.0)
	# quick grow-in
	mi.scale = Vector3.ONE * 0.1
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.25)
	return root


func _build_fire(params: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = params.pos
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = float(params.radius)
	mesh.bottom_radius = float(params.radius)
	mesh.height = 0.5
	mesh.material = _zone_material(Color(1.0, 0.42, 0.1, 0.45))
	mi.mesh = mesh
	mi.position = Vector3(0, 0.25, 0)
	root.add_child(mi)
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 25.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 2.5
	mat.gravity = Vector3.ZERO
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = float(params.radius) * 0.8
	p.process_material = mat
	var pm := BoxMesh.new()
	pm.size = Vector3(0.12, 0.12, 0.12)
	pm.material = Fx.unshaded_mat(Color(1.0, 0.6, 0.15))
	p.draw_pass_1 = pm
	p.amount = 40
	p.lifetime = 0.8
	root.add_child(p)
	p.position = Vector3(0, 0.3, 0)
	p.emitting = true
	if ResourceLoader.exists(SND_FIRE_LOOP):
		var ap := AudioStreamPlayer3D.new()
		var stream: AudioStream = (load(SND_FIRE_LOOP) as AudioStream).duplicate()
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		ap.stream = stream
		ap.unit_size = 10.0
		ap.max_distance = 60.0
		root.add_child(ap)
		ap.play()
	return root


func _build_slow(params: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = params.pos
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = float(params.radius)
	mesh.bottom_radius = float(params.radius)
	mesh.height = 0.4
	mesh.material = _zone_material(Color(0.45, 0.75, 1.0, 0.4))
	mi.mesh = mesh
	mi.position = Vector3(0, 0.2, 0)
	root.add_child(mi)
	_play_path(SND_SMOKE, params.pos, -8.0)
	return root


func _build_stim(params: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = params.pos
	var beacon := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.25, 0.5, 0.25)
	bm.material = Fx.unshaded_mat(Color(0.4, 1.0, 0.5))
	beacon.mesh = bm
	beacon.position = Vector3(0, 0.25, 0)
	root.add_child(beacon)
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = float(params.radius)
	rm.bottom_radius = float(params.radius)
	rm.height = 0.06
	rm.material = _zone_material(Color(0.35, 0.95, 0.5, 0.12))
	ring.mesh = rm
	ring.position = Vector3(0, 0.03, 0)
	root.add_child(ring)
	return root


func _build_wall(id: int, params: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var segs: Array = []
	var seg_positions: Array = params.get("segs", [])
	var yaw := float(params.get("yaw", 0.0))
	for i in seg_positions.size():
		var seg := WallSegment.new()
		seg.effect_id = id
		seg.seg_index = i
		seg.manager = self
		seg.collision_layer = 1
		seg.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(WALL_SEG_WIDTH, WALL_HEIGHT, WALL_THICKNESS)
		cs.shape = shape
		seg.add_child(cs)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(WALL_SEG_WIDTH - 0.04, WALL_HEIGHT, WALL_THICKNESS)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.75, 0.95, 0.9)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = Color(0.3, 0.5, 0.8)
		m.emission_energy_multiplier = 0.4
		mesh.material = m
		mi.mesh = mesh
		seg.add_child(mi)
		root.add_child(seg)
		seg.global_position = seg_positions[i]
		seg.rotation.y = yaw
		segs.append(seg)
	_play_path(SND_WALL, seg_positions[0] if seg_positions.size() > 0 else Vector3.ZERO, -2.0)
	_effects[id] = {"kind": "wall", "params": params, "node": root, "segs": segs}
	return root


func _build_recon(params: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = params.pos
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.05
	mesh.bottom_radius = 0.09
	mesh.height = 0.7
	mesh.material = Fx.unshaded_mat(Color(0.95, 0.85, 0.3))
	mi.mesh = mesh
	mi.position = Vector3(0, 0.35, 0)
	root.add_child(mi)
	return root


func _build_pulse_ring(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var m := _zone_material(Color(0.95, 0.85, 0.3, 0.25))
	mesh.material = m
	mi.mesh = mesh
	add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.5
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * RECON_RANGE * 2.0, 0.6)
	tw.tween_property(mi, "transparency", 1.0, 0.6)
	tw.chain().tween_callback(mi.queue_free)
	_play_path(SND_SMOKE, pos, -10.0)


func _build_blast_ring(pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	color.a = 0.4
	mesh.material = _zone_material(color)
	mi.mesh = mesh
	add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.6
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * CONCUSS_RADIUS, 0.35)
	tw.tween_property(mi, "transparency", 1.0, 0.35)
	tw.chain().tween_callback(mi.queue_free)


func _build_explosion(pos: Vector3, scale_f: float) -> void:
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 80.0
	mat.initial_velocity_min = 6.0 * scale_f
	mat.initial_velocity_max = 16.0 * scale_f
	mat.gravity = Vector3(0, -9.0, 0)
	mat.scale_min = 1.0
	mat.scale_max = 3.0
	p.process_material = mat
	var pm := BoxMesh.new()
	pm.size = Vector3(0.25, 0.25, 0.25)
	pm.material = Fx.unshaded_mat(Color(1.0, 0.55, 0.15))
	p.draw_pass_1 = pm
	p.amount = 120
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 1.0
	add_child(p)
	p.global_position = pos + Vector3.UP * 0.5
	p.emitting = true
	p.finished.connect(p.queue_free)
	var flash_sphere := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 1.0
	fm.height = 2.0
	fm.material = _zone_material(Color(1.0, 0.8, 0.4, 0.7))
	flash_sphere.mesh = fm
	add_child(flash_sphere)
	flash_sphere.global_position = pos + Vector3.UP * 0.5
	var tw := flash_sphere.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash_sphere, "scale", Vector3.ONE * 9.0 * (scale_f / 3.0 + 0.6), 0.5)
	tw.tween_property(flash_sphere, "transparency", 1.0, 0.5)
	tw.chain().tween_callback(flash_sphere.queue_free)
	_play_path(SND_EXPLODE, pos, 4.0)
	_play_path(SND_EXPLODE_FAR, pos, 2.0)

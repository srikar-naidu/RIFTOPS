class_name Player
extends CharacterBody3D
## Networked player. Movement is owner-authoritative (the owning client
## simulates and syncs transform via MultiplayerSynchronizer at 25 Hz, remote
## peers interpolate). Combat is server-authoritative: fire/reload/switch are
## requested via srv_* RPCs, validated and resolved on the server, and results
## are broadcast via cl_* RPCs. Node name == owning peer id.
##
## Spike-mode additions: 66% armor absorption, round spawns with
## persisted loadouts, plant/defuse interact input, status effects
## (concuss/slow/stim), heal-over-time, reveal outlines, flash events and a
## third-person gun attachment so remote players visibly hold their weapon.

signal health_changed(health: int, armor: int)
signal died_local(killer_name: String)
signal respawned_local
signal hit_confirmed(damage: int, region: int, killed: bool)
signal tagged
signal server_died(peer_id: int)
signal flashed(strength: float, duration: float)
signal buy_result(ok: bool, reason: String)

const RUN_SPEED := 6.75
const WALK_SPEED := 3.6
const CROUCH_SPEED := 3.0
const JUMP_APEX := 0.9
const GRAVITY := 18.0
const GROUND_ACCEL := 60.0
const GROUND_DECEL := 95.0
const AIR_ACCEL := 12.0
const STAND_EYE := 1.6
const CROUCH_EYE := 1.15
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.3
const MAX_HEALTH := 100
const TAG_SPEED_MULT := 0.275      # Tagged players move at 27.5% speed
const TAG_RECOVERY_PER_SEC := 1.45 # back to full speed in ~0.5 s
const SHOT_MASK := 0b101           # layers 1 (world) + 3 (hitboxes)
const CONCUSS_SPEED_MULT := 0.35   # 65% slow
const CONCUSS_EXTRA_SPREAD_DEG := 3.0
const STIM_MULT := 1.15
const DASH_DISTANCE := 7.0
const DASH_TIME := 0.22
const UPDRAFT_HEIGHT := 4.5

# Replicated via MultiplayerSynchronizer (see player.tscn).
@export var sync_position := Vector3.ZERO
@export var sync_yaw := 0.0
@export var sync_pitch := 0.0
@export var sync_crouched := false
@export var sync_slot := 0
@export var player_name := "Player"
@export var team := 1
@export var primary_id := "vandal"
@export var secondary_id := "classic"
@export var agent_id := "gale"

var health: int = MAX_HEALTH
var armor: int = 0
var alive := true
var crouched := false
var tag_mult := 1.0
## Position delta per second, valid for local AND remote nodes (used by the
## server for plant/defuse "mostly stationary" checks on remote players).
var observed_velocity := Vector3.ZERO
var concussed_until_ms := 0

## Written by the touch controls layer every frame when touch mode is on
## (replaces the WASD vector; y = forward/back like Input.get_vector).
var touch_move := Vector2.ZERO
## Touch joystick at small deflection = walk (quiet movement).
var touch_walk := false

var _cam_kick := 0.0
var _capsule_height := STAND_HEIGHT
var _prev_gp := Vector3.ZERO
var _dash_until_ms := 0
var _dash_vel := Vector3.ZERO
var _was_slowed := false
var _step_accum := 0.0
var _steps_audio: AudioStreamPlayer3D = null

# --- server-side combat state (only meaningful on the server) ---
var srv_mag: Dictionary = {}
var srv_reserve: Dictionary = {}
var srv_slot: int = WeaponData.Slot.PRIMARY
var srv_next_fire_ms := 0
var srv_last_shot_ms := -100000
var srv_spray_index := 0
var srv_burst_left := 0
var srv_reloading := false
var srv_equip_ready_ms := 0
var srv_rng := RandomNumberGenerator.new()
var srv_concussed_until_ms := 0
var _srv_heal_left := 0.0
var _srv_heal_rate := 0.0
var _srv_heal_chunk := 0.0
var _srv_heal_accum := 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var capsule: CollisionShape3D = $Capsule
@onready var body_visual: Node3D = $Body
@onready var fallback_mesh: MeshInstance3D = $Body/Mesh
@onready var name_tag: Label3D = $NameTag
@onready var audio_3d: AudioStreamPlayer3D = $Shot3D
@onready var hitboxes: Node3D = $Hitboxes
@onready var weapons: WeaponManager = $WeaponManager
@onready var abilities: AbilityController = $AbilityController

var _tp_gun: Node3D = null
var _tp_gun_key := ""


func peer_id() -> int:
	return str(name).to_int()


func is_local() -> bool:
	return peer_id() == multiplayer.get_unique_id()


func _enter_tree() -> void:
	get_node("MoveSync").set_multiplayer_authority(str(name).to_int())
	# MoveSync ships with public_visibility=false so the server can gate
	# spawn/sync per peer (late-join safety). Owning CLIENTS broadcast openly;
	# the server manages per-peer filters on all its copies (see match.gd).
	if str(name).to_int() == multiplayer.get_unique_id() and not multiplayer.is_server():
		get_node("MoveSync").public_visibility = true


func _ready() -> void:
	add_to_group("players")
	if Cli.test_mode():
		print("[TEST] player_node_ready peer=%d team=%d name=%s agent=%s pos=%s local=%s" % [
			peer_id(), team, player_name, agent_id, str(sync_position.snappedf(0.1)), str(is_local())])
	capsule.shape = capsule.shape.duplicate()
	if not multiplayer.is_server():
		position = sync_position
	rotation.y = sync_yaw
	_prev_gp = global_position
	for hb: HitboxRegion in hitboxes.get_children():
		hb.receiver = self
	name_tag.text = player_name
	name_tag.modulate = GameState.team_color(team)
	_steps_audio = AudioStreamPlayer3D.new()
	_steps_audio.max_distance = 26.0
	_steps_audio.unit_size = 4.0
	_steps_audio.position = Vector3(0, 0.2, 0)
	add_child(_steps_audio)
	if is_local():
		camera.make_current()
		body_visual.visible = false
		name_tag.visible = false
		GameState.local_player = self
		GameState.local_player_spawned.emit(self)
	else:
		_setup_third_person_model()
	if multiplayer.is_server():
		_server_init_combat()
	weapons.setup(self)
	abilities.setup(self)


func _exit_tree() -> void:
	if GameState.local_player == self:
		GameState.local_player = null


func refresh_team_visuals() -> void:
	name_tag.modulate = GameState.team_color(team)


func _setup_third_person_model() -> void:
	var agent := AgentDB.get_agent(StringName(agent_id))
	var model_path := "res://assets/characters/rift_operator.tscn" if GameState.mode == GameState.Mode.FFA else (agent.model_path if agent != null else "res://assets/characters/Character_Soldier.gltf")
	if not ResourceLoader.exists(model_path):
		model_path = "res://assets/characters/Character_Soldier.gltf"
	if ResourceLoader.exists(model_path):
		var ps: PackedScene = load(model_path) as PackedScene
		if ps != null:
			var inst: Node3D = ps.instantiate() as Node3D
			if inst != null:
				fallback_mesh.visible = false
				body_visual.add_child(inst)
				if GameState.mode != GameState.Mode.FFA:
					_normalize_model_height(inst, 1.75)
				var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
				if ap != null and ap.has_animation("Idle"):
					ap.play("Idle")
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = GameState.team_color(team).darkened(0.2)
		fallback_mesh.material_override = mat
	if GameState.mode == GameState.Mode.FFA:
		return
	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(0.68, 0.07, 0.48)
	band_mesh.material = Fx.unshaded_mat(GameState.team_color(team))
	band.mesh = band_mesh
	band.position = Vector3(0, 1.3, 0)
	body_visual.add_child(band)


func _normalize_model_height(inst: Node3D, target: float) -> void:
	var aabb := AABB()
	var found := false
	for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var box := m.get_aabb()
		box.position += m.position
		if found:
			aabb = aabb.merge(box)
		else:
			aabb = box
			found = true
	if found and aabb.size.y > 0.05:
		inst.scale = Vector3.ONE * (target / aabb.size.y)


## Simple third-person gun so enemies can read what you're holding
## (matters for Operators). Rebuilt when the synced slot/loadout changes.
func _update_tp_gun() -> void:
	if GameState.mode == GameState.Mode.FFA:
		return
	var wid := ""
	match sync_slot:
		WeaponData.Slot.PRIMARY: wid = primary_id
		WeaponData.Slot.SECONDARY: wid = secondary_id
		_: wid = "knife"
	if wid == "":
		wid = "knife"
	var key := "%d|%s" % [sync_slot, wid]
	if key == _tp_gun_key:
		return
	_tp_gun_key = key
	if _tp_gun != null:
		_tp_gun.queue_free()
	_tp_gun = Node3D.new()
	_tp_gun.position = Vector3(0.24, 1.08, -0.2)
	body_visual.add_child(_tp_gun)
	var w := WeaponDB.get_weapon(StringName(wid))
	var loaded := false
	if w != null and w.viewmodel_path != "" and ResourceLoader.exists(w.viewmodel_path):
		var ps: PackedScene = load(w.viewmodel_path) as PackedScene
		if ps != null:
			var inst: Node3D = ps.instantiate() as Node3D
			if inst != null:
				_tp_gun.add_child(inst)
				WeaponView.fit_gun_model(inst, 0.55)
				loaded = true
	if not loaded:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.05, 0.08, 0.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = w.viewmodel_tint if w != null else Color(0.6, 0.6, 0.65)
		mesh.material = mat
		mi.mesh = mesh
		_tp_gun.add_child(mi)




func _unhandled_input(event: InputEvent) -> void:
	if not is_local() or not alive:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var k := Settings.mouse_sensitivity * 0.01
		rotation.y -= motion.relative.x * k
		var dy := motion.relative.y * k * (-1.0 if Settings.invert_y else 1.0)
		head.rotation.x = clampf(head.rotation.x - dy, -1.55, 1.55)
		if weapons.view != null:
			weapons.view.add_sway(motion.relative)


func _physics_process(delta: float) -> void:
	tag_mult = minf(tag_mult + delta * TAG_RECOVERY_PER_SEC, 1.0)
	if is_local():
		if alive:
			_simulate_movement(delta)
			_handle_interact_input()
		sync_position = global_position
		sync_yaw = rotation.y
		sync_pitch = head.rotation.x
		sync_crouched = crouched
	else:
		var t := clampf(delta * 14.0, 0.0, 1.0)
		if global_position.distance_to(sync_position) > 4.0:
			global_position = sync_position
		else:
			global_position = global_position.lerp(sync_position, t)
		rotation.y = lerp_angle(rotation.y, sync_yaw, t)
		head.rotation.x = lerpf(head.rotation.x, sync_pitch, t)
		crouched = sync_crouched
	_update_capsule(delta)
	observed_velocity = (global_position - _prev_gp) / maxf(delta, 0.0001)
	_prev_gp = global_position
	_tick_footsteps(delta)
	if multiplayer.is_server():
		_server_tick_heal(delta)
	if is_local():
		_cam_kick = maxf(_cam_kick - delta * 6.0 * maxf(_cam_kick, 0.4), 0.0)
		camera.rotation.x = _cam_kick


## Tactical audio cue: running is loud, walking/crouching is
## silent. Surface-agnostic (concrete set) for v1.
func _tick_footsteps(delta: float) -> void:
	if not alive or _steps_audio == null:
		return
	var hvel := Vector2(velocity.x, velocity.z) if is_local() else Vector2(observed_velocity.x, observed_velocity.z)
	var grounded := is_on_floor() if is_local() else absf(observed_velocity.y) < 1.2
	if hvel.length() < 4.2 or not grounded or crouched:
		_step_accum = 0.12  # short lead-in when a sprint starts
		return
	_step_accum -= delta
	if _step_accum <= 0.0:
		_step_accum = clampf(2.35 / hvel.length(), 0.3, 0.45)
		var stream := Sfx.footstep_stream()
		if stream != null:
			_steps_audio.stream = stream
			_steps_audio.volume_db = -12.0 if is_local() else -5.0
			_steps_audio.pitch_scale = randf_range(0.92, 1.08)
			_steps_audio.play()


func _handle_interact_input() -> void:
	if GameState.mode != GameState.Mode.SPIKE:
		return
	if Input.is_action_just_pressed("interact"):
		GameState.send_interact(true)
	elif Input.is_action_just_released("interact"):
		GameState.send_interact(false)


## Movement input vector: virtual joystick when touch mode is on, WASD
## otherwise (same axes convention as Input.get_vector).
func move_input() -> Vector2:
	if Settings.touch_enabled():
		return touch_move
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _simulate_movement(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _dash_until_ms:
		velocity.x = _dash_vel.x
		velocity.z = _dash_vel.z
		velocity.y = 0.0
		move_and_slide()
		return
	var input2 := move_input()
	var wish := global_basis * Vector3(input2.x, 0, input2.y)
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()

	var wdata := weapons.current_data()
	var target := RUN_SPEED * (wdata.move_speed_mult if wdata != null else 1.0)
	if weapons.is_ads() and wdata != null and wdata.has_ads():
		target *= wdata.ads_move_mult
	var want_crouch := Input.is_action_pressed("crouch")
	crouched = want_crouch or (crouched and not _can_stand())
	if crouched:
		target = minf(target, CROUCH_SPEED)
	elif Input.is_action_pressed("walk") or (Settings.touch_enabled() and touch_walk):
		target = minf(target, WALK_SPEED)
	target *= tag_mult * status_speed_mult()

	var hvel := Vector3(velocity.x, 0, velocity.z)
	if is_on_floor():
		if wish.length_squared() > 0.001:
			hvel = hvel.move_toward(wish * target, GROUND_ACCEL * delta)
		else:
			hvel = hvel.move_toward(Vector3.ZERO, GROUND_DECEL * delta)
	else:
		hvel = hvel.move_toward(wish * target, AIR_ACCEL * delta)
	velocity.x = hvel.x
	velocity.z = hvel.z

	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = sqrt(2.0 * GRAVITY * JUMP_APEX)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


# ------------------------------------------------------------------
# Status effects (concuss / slow zones / stim)
# ------------------------------------------------------------------

func _effects() -> Node:
	return get_tree().get_first_node_in_group("effects_manager")


func is_concussed() -> bool:
	return Time.get_ticks_msec() < concussed_until_ms


func stim_active() -> bool:
	var fx := _effects()
	return fx != null and fx.stim_active_for(self)


## Combined ability speed multiplier for the local simulation.
func status_speed_mult() -> float:
	var m := 1.0
	if is_concussed():
		m = minf(m, CONCUSS_SPEED_MULT)
	var fx := _effects()
	if fx != null:
		var slow: float = fx.slow_mult_for(self)
		m = minf(m, slow)
		if Cli.test_mode() and is_local():
			if slow < 1.0 and not _was_slowed:
				_was_slowed = true
				print("[TEST] slowed mult=%.2f" % slow)
			elif slow >= 1.0:
				_was_slowed = false
		if fx.stim_active_for(self):
			m *= STIM_MULT
	return m


## Owner-side dash burst (server has already validated + consumed the charge).
func apply_dash() -> void:
	var input2 := move_input()
	var dir := global_basis * Vector3(input2.x, 0, input2.y)
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = -global_basis.z
		dir.y = 0.0
	dir = dir.normalized()
	_dash_vel = dir * (DASH_DISTANCE / DASH_TIME)
	_dash_until_ms = Time.get_ticks_msec() + int(DASH_TIME * 1000.0)


func apply_updraft() -> void:
	velocity.y = sqrt(2.0 * GRAVITY * UPDRAFT_HEIGHT)


func _can_stand() -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * (CROUCH_HEIGHT - 0.2),
		global_position + Vector3.UP * (STAND_HEIGHT + 0.02), 1)
	return space.intersect_ray(q).is_empty()


func _update_capsule(delta: float) -> void:
	var target_h := CROUCH_HEIGHT if crouched else STAND_HEIGHT
	_capsule_height = move_toward(_capsule_height, target_h, delta * 6.0)
	var shape := capsule.shape as CapsuleShape3D
	shape.height = _capsule_height
	capsule.position.y = _capsule_height * 0.5
	var eye := CROUCH_EYE if crouched else STAND_EYE
	head.position.y = move_toward(head.position.y, eye, delta * 6.0)
	var head_box: Node3D = hitboxes.get_node("HeadBox")
	head_box.position.y = head.position.y - 0.04


func _process(_delta: float) -> void:
	if not is_local():
		var lp := GameState.local_player
		name_tag.visible = GameState.mode != GameState.Mode.FFA and alive and lp != null and lp != self and int(lp.team) == team
		_update_remote_anim()
		_update_tp_gun()


var _anim_player: AnimationPlayer = null
var _anim_checked := false

func _update_remote_anim() -> void:
	if not _anim_checked:
		_anim_checked = true
		_anim_player = body_visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player == null or not alive:
		return
	var moving := velocity.length() > 0.5 or global_position.distance_to(sync_position) > 0.05
	var want := "Run" if moving else "Idle"
	if _anim_player.has_animation(want) and _anim_player.current_animation != want:
		_anim_player.play(want)


func eye_position() -> Vector3:
	return camera.global_position


func aim_direction() -> Vector3:
	return -head.global_basis.z


func add_cam_kick(deg: float) -> void:
	_cam_kick = minf(_cam_kick + deg_to_rad(deg), 0.2)


# ------------------------------------------------------------------
# Combat entry points called by WeaponManager (local player only)
# ------------------------------------------------------------------

func request_fire(origin: Vector3, dir: Vector3, speed_frac: float, airborne: bool, p_crouched: bool, ads: bool, alt := false) -> void:
	if multiplayer.is_server():
		_server_fire(origin, dir, speed_frac, airborne, p_crouched, ads, alt)
	else:
		rpc_id(1, "srv_fire", origin, dir, speed_frac, airborne, p_crouched, ads, alt)


func request_reload() -> void:
	if multiplayer.is_server():
		_server_reload()
	else:
		rpc_id(1, "srv_reload")


func request_switch(slot: int) -> void:
	if multiplayer.is_server():
		_server_switch(slot)
	else:
		rpc_id(1, "srv_switch", slot)


# ------------------------------------------------------------------
# Server-side combat
# ------------------------------------------------------------------

func _server_init_combat() -> void:
	for slot: int in [WeaponData.Slot.PRIMARY, WeaponData.Slot.SECONDARY, WeaponData.Slot.KNIFE]:
		var w := _weapon_for_slot(slot)
		srv_mag[slot] = w.mag_size if w != null else 0
		srv_reserve[slot] = w.reserve_ammo if w != null else 0
	srv_slot = WeaponData.Slot.PRIMARY if _weapon_for_slot(WeaponData.Slot.PRIMARY) != null else WeaponData.Slot.SECONDARY
	srv_equip_ready_ms = Time.get_ticks_msec() + 500
	srv_burst_left = 0
	srv_rng.seed = hash([GameState.match_seed, peer_id()])


func _weapon_for_slot(slot: int) -> WeaponData:
	match slot:
		WeaponData.Slot.PRIMARY:
			return WeaponDB.get_weapon(StringName(primary_id)) if primary_id != "" else null
		WeaponData.Slot.SECONDARY:
			return WeaponDB.get_weapon(StringName(secondary_id)) if secondary_id != "" else null
		_:
			return WeaponDB.get_weapon(&"knife")


@rpc("any_peer", "call_remote", "reliable")
func srv_fire(origin: Vector3, dir: Vector3, speed_frac: float, airborne: bool, p_crouched: bool, ads: bool, alt := false) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != peer_id():
		return
	_server_fire(origin, dir, speed_frac, airborne, p_crouched, ads, alt)


func _server_fire(origin: Vector3, dir: Vector3, speed_frac: float, airborne: bool, p_crouched: bool, ads: bool, alt := false) -> void:
	if not alive or not GameState.match_running:
		return
	var w := _weapon_for_slot(srv_slot)
	if w == null:
		return
	var is_burst := alt and w.has_burst_alt()
	if not is_burst:
		srv_burst_left = 0
	var now := Time.get_ticks_msec()
	if now < srv_equip_ready_ms or srv_reloading:
		return
	if now < srv_next_fire_ms - 20:
		return
	if w.mag_size > 0 and int(srv_mag[srv_slot]) <= 0:
		return
	var eye := global_position + Vector3.UP * (CROUCH_EYE if sync_crouched else STAND_EYE)
	if origin.distance_to(eye) > 3.0:
		origin = eye
	if dir.length_squared() < 0.5:
		return
	dir = dir.normalized()

	var concussed := now < srv_concussed_until_ms
	if concussed:
		ads = false  # concussion: no ADS
	if is_burst:
		ads = false
	var interval := w.fire_interval_ms(ads)
	if is_burst:
		# Burst rounds arrive faster than the base fire rate; validate them
		# against the burst timing instead (cooldown after the last round).
		# Within-burst gap is validated at 70% to absorb network jitter.
		if srv_burst_left <= 0:
			srv_burst_left = w.alt_burst_count - 1
			interval = int(w.alt_burst_interval * 700.0)
		else:
			srv_burst_left -= 1
			interval = int(w.alt_burst_interval * 700.0) if srv_burst_left > 0 else int(w.alt_burst_cooldown * 1000.0)
	else:
		var fx := _effects()
		if fx != null and fx.stim_active_for(self):
			interval = int(float(interval) / STIM_MULT)
			if Cli.test_mode():
				print("[TEST] stim_shot peer=%d interval=%d" % [peer_id(), interval])
	srv_next_fire_ms = now + interval
	if w.mag_size > 0:
		srv_mag[srv_slot] = int(srv_mag[srv_slot]) - 1
	if now - srv_last_shot_ms > int(w.recovery_time * 1000.0) + interval:
		srv_spray_index = 0
	else:
		srv_spray_index += 1
	srv_last_shot_ms = now

	var spread := w.compute_spread_deg(ads, p_crouched, airborne, clampf(speed_frac, 0.0, 1.5), srv_spray_index)
	if is_burst:
		spread += w.alt_burst_spread
	if concussed:
		spread += CONCUSS_EXTRA_SPREAD_DEG
	var final_dir := WeaponData.deviate(dir, w.spray_offset_deg(srv_spray_index, srv_rng), spread, srv_rng)
	_server_resolve_shot(w, origin, final_dir)


func _server_resolve_shot(w: WeaponData, origin: Vector3, dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [get_rid()]
	for hb: HitboxRegion in hitboxes.get_children():
		exclude.append(hb.get_rid())
	var to := origin + dir * w.max_range
	var q := PhysicsRayQueryParameters3D.create(origin, to, SHOT_MASK, exclude)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)

	var end := to
	var normal := Vector3.UP
	var hit_flesh := false
	var hit_anything := false
	if not hit.is_empty():
		hit_anything = true
		end = hit.position
		normal = hit.normal
		var col: Object = hit.collider
		if col is HitboxRegion:
			var hb := col as HitboxRegion
			var recv := hb.receiver
			if recv != null:
				hit_flesh = true
				var dist := origin.distance_to(end)
				var dmg := w.damage_for(dist, hb.region)
				if w.is_melee() and recv is Node3D:
					var victim_forward: Vector3 = -(recv as Node3D).global_basis.z
					if dir.dot(victim_forward) > 0.35:
						dmg = int(dmg * w.melee_back_multiplier)
				var res: Dictionary = recv.take_damage_server(dmg, hb.region, self, w)
				if int(res.applied) > 0:
					if Cli.test_mode():
						print("[TEST] shot_hit target=%s region=%d dmg=%d" % [recv.get("player_name"), hb.region, int(res.applied)])
					_rpc_owner("cl_hit_confirm", [int(res.applied), int(hb.region), bool(res.killed)])
		elif col is WallSegment:
			var dist_w := origin.distance_to(end)
			(col as WallSegment).server_bullet_hit(w.damage_for(dist_w, HitboxRegion.Region.BODY))
	rpc("cl_shot_fx", String(w.id), origin, end, normal, hit_flesh, hit_anything)


## Test hook: server-side scripted shot (aim straight at a point, no spread
## trickery beyond the normal pipeline). Used by the automated tests.
func server_test_fire(target: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var origin := global_position + Vector3.UP * STAND_EYE
	var dir := (target - origin).normalized()
	_server_fire(origin, dir, 0.0, false, true, false)


## Bullet damage entry (also implemented by DummyTarget). Bullets have no
## friendly fire; ability damage uses server_apply_ability_damage instead.
func take_damage_server(amount: int, region: int, attacker: Node, weapon: WeaponData) -> Dictionary:
	if not multiplayer.is_server() or not alive:
		return {"applied": 0, "killed": false}
	var attacker_team := int(attacker.get("team")) if attacker != null and attacker.get("team") != null else 0
	if GameState.mode != GameState.Mode.FFA and attacker != self and attacker_team != 0 and attacker_team == team:
		return {"applied": 0, "killed": false}  # no bullet friendly fire
	var killer_name := String(attacker.get("player_name")) if attacker != null else "World"
	var killer_peer := (attacker as Player).peer_id() if attacker is Player else 0
	return _server_damage_core(amount, region, killer_name, attacker_team, killer_peer, String(weapon.id), weapon.applies_tag)


## Ability/spike damage: no team gate (callers decide ally scaling).
func server_apply_ability_damage(amount: int, source_name: String, source_team: int, source_peer: int, weapon_id: String) -> Dictionary:
	if not multiplayer.is_server() or not alive:
		return {"applied": 0, "killed": false}
	return _server_damage_core(amount, HitboxRegion.Region.BODY, source_name, source_team, source_peer, weapon_id, false)


func _server_damage_core(amount: int, region: int, killer_name: String, killer_team: int, killer_peer: int, weapon_id: String, tag: bool) -> Dictionary:
	# Shields absorb 66% of incoming damage, capped by the
	# remaining shield; the rest goes to health. Breaks when absorb hits 0.
	var absorbed := mini(armor, int(round(float(amount) * GameState.SHIELD_ABSORB)))
	armor -= absorbed
	health = maxi(health - (amount - absorbed), 0)
	_srv_heal_left = 0.0  # taking damage stops an active heal-over-time
	rpc("cl_health", health, armor)
	if killer_peer != 0 and killer_peer != peer_id():
		GameState.server_note_damage(peer_id(), killer_peer)
	if tag and health > 0:
		_rpc_owner("cl_tag", [])
	var killed := health <= 0
	if killed:
		alive = false
		rpc("cl_die", killer_name)
		server_died.emit(peer_id())
		GameState.server_report_kill(
			killer_name, killer_team, player_name, team,
			weapon_id, region == HitboxRegion.Region.HEAD, killer_peer, peer_id())
	return {"applied": amount, "killed": killed}


## Heal-over-time (server): Sage-mirrored 100hp over 5s, ticked every 0.5s.
func server_heal(total: int, duration: float) -> void:
	if not multiplayer.is_server() or not alive:
		return
	_srv_heal_left = float(total)
	_srv_heal_rate = float(total) / maxf(duration, 0.1)
	_srv_heal_chunk = 0.0
	_srv_heal_accum = 0.0


func _server_tick_heal(delta: float) -> void:
	if _srv_heal_left <= 0.0 or not alive:
		return
	if health >= MAX_HEALTH:
		_srv_heal_left = 0.0
		return
	var gain := minf(_srv_heal_rate * delta, _srv_heal_left)
	_srv_heal_left -= gain
	_srv_heal_chunk += gain
	_srv_heal_accum += delta
	if _srv_heal_accum >= 0.5 or _srv_heal_left <= 0.0:
		_srv_heal_accum = 0.0
		var add := int(round(_srv_heal_chunk))
		if add > 0:
			_srv_heal_chunk -= float(add)
			health = mini(health + add, MAX_HEALTH)
			rpc("cl_health", health, armor)
			if Cli.test_mode():
				print("[TEST] heal_tick peer=%d hp=%d" % [peer_id(), health])


func _server_reload() -> void:
	if not alive:
		return
	var w := _weapon_for_slot(srv_slot)
	if w == null or w.mag_size <= 0 or srv_reloading:
		return
	if int(srv_mag[srv_slot]) >= w.mag_size or int(srv_reserve[srv_slot]) <= 0:
		return
	srv_reloading = true
	var slot_at_start := srv_slot
	get_tree().create_timer(w.reload_time).timeout.connect(_server_finish_reload.bind(slot_at_start))


func _server_finish_reload(slot: int) -> void:
	if not srv_reloading or srv_slot != slot or not alive:
		return
	srv_reloading = false
	var w := _weapon_for_slot(slot)
	if w == null:
		return
	var need := w.mag_size - int(srv_mag[slot])
	var take := mini(need, int(srv_reserve[slot]))
	srv_mag[slot] = int(srv_mag[slot]) + take
	srv_reserve[slot] = int(srv_reserve[slot]) - take
	_rpc_owner("cl_ammo", [slot, int(srv_mag[slot]), int(srv_reserve[slot])])


@rpc("any_peer", "call_remote", "reliable")
func srv_reload() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != peer_id():
		return
	_server_reload()


func _server_switch(slot: int) -> void:
	if slot < WeaponData.Slot.PRIMARY or slot > WeaponData.Slot.KNIFE or slot == srv_slot:
		return
	var w := _weapon_for_slot(slot)
	if w == null:
		return
	srv_slot = slot
	srv_reloading = false
	srv_burst_left = 0
	srv_equip_ready_ms = Time.get_ticks_msec() + int(w.equip_time * 1000.0)


@rpc("any_peer", "call_remote", "reliable")
func srv_switch(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != peer_id():
		return
	_server_switch(slot)


## TDM respawn (spike mode uses server_round_spawn instead).
func server_respawn(pos: Vector3, yaw: float) -> void:
	if not multiplayer.is_server():
		return
	health = MAX_HEALTH
	alive = true
	_server_init_combat()
	rpc("cl_respawn", pos, yaw)


# ------------------------------------------------------------------
# Spike-mode server entry points (round spawns, buys, statuses)
# ------------------------------------------------------------------

## Revive + teleport + apply the persisted loadout at round start.
func server_round_spawn(pos: Vector3, yaw: float, loadout: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	primary_id = String(loadout.get("primary", ""))
	secondary_id = String(loadout.get("secondary", "classic"))
	armor = int(loadout.get("armor", 0))
	health = MAX_HEALTH
	alive = true
	srv_concussed_until_ms = 0
	_srv_heal_left = 0.0
	_server_init_combat()
	abilities.server_set_charges(loadout.get("charges", {}))
	rpc("cl_round_spawn", pos, yaw, primary_id, secondary_id, armor)


## Buy-phase weapon purchase: swap loadout in place, refill that slot.
func server_give_weapon(new_primary: String, new_secondary: String) -> void:
	if not multiplayer.is_server():
		return
	primary_id = new_primary
	secondary_id = new_secondary
	for slot: int in [WeaponData.Slot.PRIMARY, WeaponData.Slot.SECONDARY]:
		var w := _weapon_for_slot(slot)
		srv_mag[slot] = w.mag_size if w != null else 0
		srv_reserve[slot] = w.reserve_ammo if w != null else 0
	if _weapon_for_slot(srv_slot) == null:
		srv_slot = WeaponData.Slot.SECONDARY
	rpc("cl_loadout", primary_id, secondary_id)


func server_set_armor(v: int) -> void:
	if not multiplayer.is_server():
		return
	armor = v
	rpc("cl_health", health, armor)


func server_set_charges(charges: Dictionary) -> void:
	abilities.server_set_charges(charges)


## Late joiner mid-round: exists but sits out until the next round.
func server_spawn_dead() -> void:
	if not multiplayer.is_server():
		return
	alive = false
	health = 0
	rpc("cl_spawn_dead")


func server_apply_concuss(duration: float) -> void:
	if not multiplayer.is_server():
		return
	srv_concussed_until_ms = Time.get_ticks_msec() + int(duration * 1000.0)
	_rpc_owner("cl_concussed", [duration])


func server_apply_flash(strength: float, duration: float) -> void:
	if not multiplayer.is_server():
		return
	_rpc_owner("cl_flashed", [strength, duration])


func server_reveal(duration: float) -> void:
	if not multiplayer.is_server():
		return
	rpc("cl_revealed", duration)


func notify_buy_result(ok: bool, reason: String) -> void:
	_rpc_owner("cl_buy_result", [ok, reason])


func _rpc_owner(method: StringName, args: Array) -> void:
	if peer_id() == 1:
		callv(method, args)
	else:
		callv("rpc_id", [peer_id(), method] + args)


# ------------------------------------------------------------------
# Client-side result RPCs (server -> everyone / owner)
# ------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func cl_health(hp: int, ar: int) -> void:
	var was_hp := health
	var was_ar := armor
	health = hp
	armor = ar
	if was_ar > 0 and ar == 0 and hp > 0:
		var p := "res://assets/audio/foley/impactGlass_heavy_000.ogg"
		if ResourceLoader.exists(p):
			Fx.play_sound_3d(get_tree().current_scene, load(p), global_position + Vector3.UP, -6.0)
	if is_local():
		health_changed.emit(health, armor)
		if hp < was_hp:
			tagged.emit()


@rpc("authority", "call_remote", "reliable")
func cl_tag() -> void:
	tag_mult = TAG_SPEED_MULT


@rpc("authority", "call_remote", "reliable")
func cl_hit_confirm(damage: int, region: int, killed: bool) -> void:
	hit_confirmed.emit(damage, region, killed)


@rpc("authority", "call_local", "reliable")
func cl_die(killer_name: String) -> void:
	alive = false
	health = 0
	velocity = Vector3.ZERO
	set_deferred("collision_layer", 0)
	for hb: HitboxRegion in hitboxes.get_children():
		hb.set_deferred("collision_layer", 0)
	body_visual.visible = false
	name_tag.visible = false
	Fx.corpse(get_tree().current_scene, global_position, rotation.y, GameState.team_color(team))
	Fx.play_sound_3d(get_tree().current_scene, Sfx.death_grunt(), global_position + Vector3.UP, -4.0)
	if is_local():
		health_changed.emit(0, armor)
		died_local.emit(killer_name)
		weapons.on_died()


@rpc("authority", "call_local", "reliable")
func cl_respawn(pos: Vector3, yaw: float) -> void:
	health = MAX_HEALTH
	alive = true
	tag_mult = 1.0
	set_deferred("collision_layer", 2)
	for hb: HitboxRegion in hitboxes.get_children():
		hb.set_deferred("collision_layer", 4)
	global_position = pos
	sync_position = pos
	velocity = Vector3.ZERO
	rotation.y = yaw
	sync_yaw = yaw
	if is_local():
		head.rotation.x = 0.0
		camera.make_current()  # reclaim from a spectate camera
		health_changed.emit(health, armor)
		weapons.on_respawn()
		respawned_local.emit()
	else:
		body_visual.visible = true


@rpc("authority", "call_local", "reliable")
func cl_round_spawn(pos: Vector3, yaw: float, p_primary: String, p_secondary: String, ar: int) -> void:
	primary_id = p_primary
	secondary_id = p_secondary
	health = MAX_HEALTH
	armor = ar
	alive = true
	tag_mult = 1.0
	concussed_until_ms = 0
	_dash_until_ms = 0
	set_deferred("collision_layer", 2)
	for hb: HitboxRegion in hitboxes.get_children():
		hb.set_deferred("collision_layer", 4)
	global_position = pos
	sync_position = pos
	velocity = Vector3.ZERO
	rotation.y = yaw
	sync_yaw = yaw
	_tp_gun_key = ""  # force third-person gun rebuild
	if is_local():
		head.rotation.x = 0.0
		camera.make_current()  # reclaim from a spectate camera
		health_changed.emit(health, armor)
		weapons.set_loadout(primary_id, secondary_id)
		respawned_local.emit()
	else:
		body_visual.visible = true


## Owner-side identity fix-up. Godot's spawner does NOT apply spawn state to
## the peer that owns the node's synchronizer, so the owning client's copy
## would keep default name/team/loadout/position — the server sends this
## right after spawning (see match.gd).
@rpc("authority", "call_remote", "reliable")
func cl_identity(pname: String, p_team: int, p_primary: String, p_secondary: String, p_agent: String, pos: Vector3, yaw: float) -> void:
	player_name = pname
	team = p_team
	primary_id = p_primary
	secondary_id = p_secondary
	agent_id = p_agent
	global_position = pos
	sync_position = pos
	velocity = Vector3.ZERO
	rotation.y = yaw
	sync_yaw = yaw
	name_tag.text = player_name
	refresh_team_visuals()
	if is_local():
		weapons.set_loadout(primary_id, secondary_id)
	if Cli.test_mode():
		print("[TEST] identity_applied peer=%d team=%d" % [peer_id(), team])


@rpc("authority", "call_local", "reliable")
func cl_loadout(p_primary: String, p_secondary: String) -> void:
	primary_id = p_primary
	secondary_id = p_secondary
	_tp_gun_key = ""
	if is_local():
		weapons.set_loadout(primary_id, secondary_id)


@rpc("authority", "call_local", "reliable")
func cl_spawn_dead() -> void:
	alive = false
	health = 0
	velocity = Vector3.ZERO
	set_deferred("collision_layer", 0)
	for hb: HitboxRegion in hitboxes.get_children():
		hb.set_deferred("collision_layer", 0)
	body_visual.visible = false
	name_tag.visible = false
	if is_local():
		health_changed.emit(0, armor)
		died_local.emit("")
		weapons.on_died()


@rpc("authority", "call_remote", "reliable")
func cl_ammo(slot: int, mag: int, reserve: int) -> void:
	weapons.on_server_ammo(slot, mag, reserve)


@rpc("authority", "call_remote", "reliable")
func cl_buy_result(ok: bool, reason: String) -> void:
	buy_result.emit(ok, reason)


@rpc("authority", "call_remote", "reliable")
func cl_concussed(duration: float) -> void:
	concussed_until_ms = Time.get_ticks_msec() + int(duration * 1000.0)
	if Cli.test_mode():
		print("[TEST] concussed dur=%.1f" % duration)


@rpc("authority", "call_remote", "reliable")
func cl_flashed(strength: float, duration: float) -> void:
	flashed.emit(strength, duration)
	if Cli.test_mode():
		print("[TEST] flashed strength=%.2f dur=%.2f" % [strength, duration])


## Recon reveal: everyone sees a through-wall outline on this player.
@rpc("authority", "call_local", "reliable")
func cl_revealed(duration: float) -> void:
	if Cli.test_mode() and is_local():
		print("[TEST] revealed_me")
	if is_local():
		return
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.42
	mesh.height = 1.9
	var mat := Fx.unshaded_mat(Color(0.95, 0.2, 0.15, 0.4))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 10
	mesh.material = mat
	mi.mesh = mesh
	mi.position = Vector3(0, 0.95, 0)
	add_child(mi)
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		if is_instance_valid(mi):
			mi.queue_free())


@rpc("authority", "call_local", "unreliable")
func cl_shot_fx(weapon_id: String, origin: Vector3, end: Vector3, normal: Vector3, hit_flesh: bool, hit_anything: bool) -> void:
	if is_local():
		return  # the shooter already played predicted FX
	var w := WeaponDB.get_weapon(StringName(weapon_id))
	if w == null:
		return
	var world := get_tree().current_scene
	if w.tracer_visible_to_others and not w.is_melee():
		Fx.tracer(world, origin, end)
	if hit_anything:
		Fx.impact(world, end, normal, hit_flesh)
	audio_3d.stream = Sfx.fire_stream(w)
	audio_3d.play()

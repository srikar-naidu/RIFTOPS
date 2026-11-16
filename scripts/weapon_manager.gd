class_name WeaponManager
extends Node
## Client-side weapon simulation for the LOCAL player: inventory, fire modes,
## reload/equip timers, ADS, spread prediction, viewmodel + first-person FX.
## Every action is also requested from the server, which owns the truth
## (see Player srv_* / cl_* RPCs). For remote players this node is inert.

signal ammo_changed(mag: int, reserve: int)
signal weapon_changed(data: WeaponData)
signal reload_started(duration: float)

var player: Player = null
var view: WeaponView = null

var slots: Dictionary = {}
var current_slot: int = WeaponData.Slot.PRIMARY

var _next_fire_ms := 0
var _last_shot_ms := -100000
var _spray_index := 0
var _reloading := false
var _reload_end_ms := 0
var _equip_end_ms := 0
var _ads := false
## 0 = hip, 1 = first zoom, 2 = second zoom (Operator stages).
var _ads_stage := 0
var _ads_amount := 0.0
var _base_fov := 75.0
var _burst_left := 0
var _burst_next_ms := 0
var _rng := RandomNumberGenerator.new()
var _local_audio: AudioStreamPlayer = null


func setup(p: Player) -> void:
	player = p
	var prim := WeaponDB.get_weapon(StringName(p.primary_id)) if p.primary_id != "" else null
	if prim == null and GameState.mode == GameState.Mode.TDM:
		prim = WeaponDB.get_weapon(&"vandal")
	var sec := WeaponDB.get_weapon(StringName(p.secondary_id)) if p.secondary_id != "" else null
	if sec == null:
		sec = WeaponDB.get_weapon(&"classic")
	slots = {
		WeaponData.Slot.PRIMARY: _make_state(prim),
		WeaponData.Slot.SECONDARY: _make_state(sec),
		WeaponData.Slot.KNIFE: _make_state(WeaponDB.get_weapon(&"knife")),
	}
	if not player.is_local():
		set_process(false)
		return
	_base_fov = player.camera.fov
	view = WeaponView.new()
	player.camera.add_child(view)
	_local_audio = AudioStreamPlayer.new()
	_local_audio.bus = &"Master"
	add_child(_local_audio)
	_switch_to(WeaponData.Slot.PRIMARY if prim != null else WeaponData.Slot.SECONDARY, true)


## Rebuild slots after a buy-phase purchase or round spawn (full ammo).
func set_loadout(new_primary: String, new_secondary: String) -> void:
	var prim := WeaponDB.get_weapon(StringName(new_primary)) if new_primary != "" else null
	var sec := WeaponDB.get_weapon(StringName(new_secondary)) if new_secondary != "" else null
	if sec == null:
		sec = WeaponDB.get_weapon(&"classic")
	slots[WeaponData.Slot.PRIMARY] = _make_state(prim)
	slots[WeaponData.Slot.SECONDARY] = _make_state(sec)
	if not player.is_local():
		return
	if view != null:
		view.visible = true
	_switch_to(WeaponData.Slot.PRIMARY if prim != null else WeaponData.Slot.SECONDARY, true)


func _make_state(data: WeaponData) -> Dictionary:
	return {"data": data, "mag": data.mag_size if data != null else 0, "reserve": data.reserve_ammo if data != null else 0}


func current_data() -> WeaponData:
	if slots.is_empty():
		return null
	return slots[current_slot].data


func current_state() -> Dictionary:
	return slots.get(current_slot, {})


func is_ads() -> bool:
	return _ads


func is_reloading() -> bool:
	return _reloading


func speed_frac() -> float:
	var v := Vector3(player.velocity.x, 0, player.velocity.z)
	return v.length() / Player.RUN_SPEED


## Live inaccuracy in degrees — drives the dynamic crosshair.
func current_spread_deg() -> float:
	var d := current_data()
	if d == null:
		return 0.0
	var now := Time.get_ticks_msec()
	var idx := _spray_index
	if now - _last_shot_ms > int(d.recovery_time * 1000.0) + d.fire_interval_ms(_ads):
		idx = 0
	var s := d.compute_spread_deg(_ads, player.crouched, not player.is_on_floor(), speed_frac(), idx)
	if player.is_concussed():
		s += Player.CONCUSS_EXTRA_SPREAD_DEG
	return s


func _process(delta: float) -> void:
	if player == null or slots.is_empty():
		return
	var d := current_data()
	var target_ads := 1.0 if (_ads and d != null and d.has_ads()) else 0.0
	var ads_speed := 1.0 / maxf(d.ads_time if d != null else 0.2, 0.05)
	_ads_amount = move_toward(_ads_amount, target_ads, delta * ads_speed)
	if d != null and d.has_ads():
		player.camera.fov = lerpf(_base_fov, _base_fov / d.zoom_for_stage(maxi(_ads_stage, 1)), _ads_amount)
	else:
		player.camera.fov = _base_fov
	if view != null:
		view.set_ads_amount(_ads_amount)
		view.set_move_state(speed_frac(), player.is_on_floor())

	if not player.alive:
		return
	var live := Settings.gameplay_input_active()
	_handle_switching()
	_handle_reload_progress()
	if live:
		_handle_ads_input(d)
		_handle_fire(d)


func _handle_switching() -> void:
	if Input.is_action_just_pressed("weapon_primary"):
		_switch_to(WeaponData.Slot.PRIMARY)
	elif Input.is_action_just_pressed("weapon_secondary"):
		_switch_to(WeaponData.Slot.SECONDARY)
	elif Input.is_action_just_pressed("weapon_knife"):
		_switch_to(WeaponData.Slot.KNIFE)
	elif Input.is_action_just_pressed("reload"):
		_start_reload()


func _switch_to(slot: int, force := false) -> void:
	if not slots.has(slot) or (slot == current_slot and not force):
		return
	if slots[slot].data == null:
		return  # empty slot (e.g. no primary bought this round)
	var now := Time.get_ticks_msec()
	current_slot = slot
	player.sync_slot = slot
	var d := current_data()
	_equip_end_ms = now + int(d.equip_time * 1000.0)
	_reloading = false
	_set_ads(0)
	_burst_left = 0
	_spray_index = 0
	if view != null:
		view.show_weapon(d)
	weapon_changed.emit(d)
	ammo_changed.emit(int(slots[slot].mag), int(slots[slot].reserve))
	player.request_switch(slot)


## Touch UI helper: primary -> secondary -> knife -> primary, skipping
## empty slots.
func cycle_slot() -> void:
	var order: Array = [WeaponData.Slot.PRIMARY, WeaponData.Slot.SECONDARY, WeaponData.Slot.KNIFE]
	var idx := order.find(current_slot)
	for i in order.size():
		var slot: int = order[(idx + 1 + i) % order.size()]
		if slots.has(slot) and slots[slot].data != null:
			_switch_to(slot)
			return


func _start_reload() -> void:
	var d := current_data()
	var st: Dictionary = current_state()
	if d == null or d.mag_size <= 0 or _reloading:
		return
	if int(st.mag) >= d.mag_size or int(st.reserve) <= 0:
		return
	var now := Time.get_ticks_msec()
	if now < _equip_end_ms:
		return
	_reloading = true
	_reload_end_ms = now + int(d.reload_time * 1000.0)
	_ads = false
	Fx.play_sound_2d(player, Sfx.ui_stream("reload"), -10.0)
	reload_started.emit(d.reload_time)
	if view != null:
		view.play_reload(d.reload_time)
	player.request_reload()


func _handle_reload_progress() -> void:
	if not _reloading:
		return
	if Time.get_ticks_msec() >= _reload_end_ms:
		_reloading = false
		var d := current_data()
		var st: Dictionary = current_state()
		var need: int = d.mag_size - int(st.mag)
		var take: int = mini(need, int(st.reserve))
		st.mag = int(st.mag) + take
		st.reserve = int(st.reserve) - take
		ammo_changed.emit(int(st.mag), int(st.reserve))


func _set_ads(stage: int) -> void:
	_ads_stage = stage
	_ads = stage > 0


## The "ads" input is the alt-fire input: normal weapons aim (hold or
## toggle), the Classic fires a 3-round burst, the Operator cycles its two
## zoom stages (always toggle).
func _handle_ads_input(d: WeaponData) -> void:
	if d == null or (not d.has_ads() and not d.has_burst_alt()):
		_set_ads(0)
		return
	if _reloading or player.is_concussed():
		_set_ads(0)
		return
	if d.has_burst_alt():
		if Input.is_action_just_pressed("ads"):
			_try_start_burst(d)
		return
	if d.has_zoom_stages():
		if Input.is_action_just_pressed("ads"):
			_set_ads((_ads_stage + 1) % 3)
		return
	if Settings.ads_toggle_mode or Settings.touch_enabled():
		if Input.is_action_just_pressed("ads"):
			_set_ads(0 if _ads else 1)
	else:
		_set_ads(1 if Input.is_action_pressed("ads") else 0)


func _try_start_burst(d: WeaponData) -> void:
	if _burst_left > 0:
		return
	var now := Time.get_ticks_msec()
	if _reloading or now < _equip_end_ms or now < _next_fire_ms:
		return
	var st: Dictionary = current_state()
	if d.mag_size > 0 and int(st.mag) <= 0:
		Fx.play_sound_2d(player, Sfx.ui_stream("dry"), -8.0)
		return
	_burst_left = d.alt_burst_count
	_burst_next_ms = now


func _handle_fire(d: WeaponData) -> void:
	if d == null:
		return
	if _burst_left > 0:
		_tick_burst(d)
		return
	var want := Input.is_action_just_pressed("fire") if d.is_semi() else Input.is_action_pressed("fire")
	if not want:
		return
	var now := Time.get_ticks_msec()
	if _reloading or now < _equip_end_ms or now < _next_fire_ms:
		return
	var st: Dictionary = current_state()
	if d.mag_size > 0 and int(st.mag) <= 0:
		if Input.is_action_just_pressed("fire"):
			Fx.play_sound_2d(player, Sfx.ui_stream("dry"), -8.0)
		return
	_fire_one(d, false)


func _tick_burst(d: WeaponData) -> void:
	var now := Time.get_ticks_msec()
	if now < _burst_next_ms:
		return
	var st: Dictionary = current_state()
	if not d.has_burst_alt() or (d.mag_size > 0 and int(st.mag) <= 0):
		_burst_left = 0
		_next_fire_ms = now + int(d.alt_burst_cooldown * 1000.0)
		return
	_fire_one(d, true)
	_burst_left -= 1
	if _burst_left > 0:
		_burst_next_ms = now + int(d.alt_burst_interval * 1000.0)
	else:
		_next_fire_ms = now + int(d.alt_burst_cooldown * 1000.0)


func _fire_one(d: WeaponData, alt: bool) -> void:
	var now := Time.get_ticks_msec()
	var interval := d.fire_interval_ms(_ads)
	if player.stim_active() and not alt:
		interval = int(float(interval) / Player.STIM_MULT)
	if not alt:
		_next_fire_ms = now + interval
	var st: Dictionary = current_state()
	if d.mag_size > 0:
		st.mag = int(st.mag) - 1
		ammo_changed.emit(int(st.mag), int(st.reserve))
	if now - _last_shot_ms > int(d.recovery_time * 1000.0) + interval:
		_spray_index = 0
	else:
		_spray_index += 1
	_last_shot_ms = now

	var origin := player.eye_position()
	var base_dir := player.aim_direction()
	_predicted_shot_fx(d, origin, base_dir, alt)
	player.request_fire(origin, base_dir, speed_frac(), not player.is_on_floor(), player.crouched, _ads, alt)
	player.add_cam_kick(d.recoil_kick_deg)
	if view != null:
		view.kick(d)


func _predicted_shot_fx(d: WeaponData, origin: Vector3, base_dir: Vector3, alt := false) -> void:
	_local_audio.stream = Sfx.fire_stream(d)
	_local_audio.volume_db = -4.0
	_local_audio.play()
	if view != null:
		view.flash()
	if d.is_melee():
		return
	var spread := d.compute_spread_deg(_ads, player.crouched, not player.is_on_floor(), speed_frac(), _spray_index)
	if alt and d.has_burst_alt():
		spread += d.alt_burst_spread
	var dir := WeaponData.deviate(base_dir, d.spray_offset_deg(_spray_index, _rng), spread, _rng)
	var space := player.get_world_3d().direct_space_state
	var exclude: Array[RID] = [player.get_rid()]
	for hb: HitboxRegion in player.hitboxes.get_children():
		exclude.append(hb.get_rid())
	var to := origin + dir * d.max_range
	var q := PhysicsRayQueryParameters3D.create(origin, to, Player.SHOT_MASK, exclude)
	q.collide_with_areas = true
	var hit := space.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit.position
	var world := get_tree().current_scene
	var from := view.muzzle_global() if view != null else origin
	Fx.tracer(world, from, end)
	if not hit.is_empty():
		Fx.impact(world, end, hit.normal, hit.collider is HitboxRegion)


func on_server_ammo(slot: int, mag: int, reserve: int) -> void:
	if not slots.has(slot):
		return
	slots[slot].mag = mag
	slots[slot].reserve = reserve
	if slot == current_slot:
		ammo_changed.emit(mag, reserve)


func on_died() -> void:
	_set_ads(0)
	_burst_left = 0
	_reloading = false
	if view != null:
		view.visible = false
	player.camera.fov = _base_fov


func on_respawn() -> void:
	for slot: int in slots:
		var d: WeaponData = slots[slot].data
		slots[slot].mag = d.mag_size if d != null else 0
		slots[slot].reserve = d.reserve_ammo if d != null else 0
	if view != null:
		view.visible = true
	_switch_to(WeaponData.Slot.PRIMARY, true)

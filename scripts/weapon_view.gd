class_name WeaponView
extends Node3D
## First-person viewmodel. Uses the CC0 gun models from assets/weapons/ when
## present (checked at runtime), otherwise builds a clean placeholder mesh.
## Handles bob, sway, ADS positioning, recoil kick and muzzle flash.

const HIP_POS := Vector3(0.26, -0.23, -0.45)
const ADS_POS := Vector3(0.0, -0.175, -0.32)

var _model_root: Node3D = null
var _muzzle: Node3D = null
var _flash: MeshInstance3D = null
var _kick_pos := 0.0
var _kick_rot := 0.0
var _bob_t := 0.0
var _speed_frac := 0.0
var _grounded := true
var _ads_amount := 0.0
var _sway := Vector2.ZERO


func _ready() -> void:
	position = HIP_POS


func show_weapon(d: WeaponData) -> void:
	if _model_root != null:
		_model_root.queue_free()
	_model_root = Node3D.new()
	add_child(_model_root)
	var loaded := false
	if d != null and d.viewmodel_path != "" and ResourceLoader.exists(d.viewmodel_path):
		var ps: PackedScene = load(d.viewmodel_path) as PackedScene
		if ps != null:
			var inst: Node3D = ps.instantiate() as Node3D
			if inst != null:
				_model_root.add_child(inst)
				_fit_model(inst, d)  # orients, scales and recenters
				loaded = true
	if not loaded:
		_build_placeholder(d)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.02, -0.55)
	_model_root.add_child(_muzzle)
	_flash = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var m := Fx.unshaded_mat(Color(1.0, 0.85, 0.4))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = m
	_flash.mesh = quad
	_flash.position = _muzzle.position
	_flash.visible = false
	_model_root.add_child(_flash)
	_kick_pos = 0.0
	_kick_rot = 0.0
	# equip dip
	position = HIP_POS + Vector3(0, -0.18, 0)


func _fit_model(inst: Node3D, d: WeaponData) -> void:
	if String(d.id) == "vandal":
		inst.scale = Vector3.ONE * 0.85
	else:
		fit_gun_model(inst, 0.62 * d.viewmodel_scale)


## Shared gun-model normalization (first- and third-person): orients the
## barrel down -Z, scales the longest horizontal extent to target_len and
## recenters the visual bounds on the node origin. The Quaternius kit guns
## are authored barrel along -X (verified by screenshot); +Z-forward models
## get the classic PI flip instead.
static func fit_gun_model(inst: Node3D, target_len: float) -> void:
	var aabb := merged_aabb(inst)
	if aabb.size.length_squared() < 0.000001:
		return
	inst.rotation.y = -PI * 0.5 if aabb.size.x > aabb.size.z else PI
	var length := maxf(maxf(aabb.size.x, aabb.size.z), 0.01)
	var s := clampf(target_len / length, 0.02, 40.0)
	inst.scale = Vector3.ONE * s
	# Exact recenter: cancel the transformed AABB-center offset.
	inst.position = -(inst.basis * aabb.get_center())


## Merged AABB of all MeshInstance3Ds in `inst` LOCAL space, including each
## mesh's transform relative to `inst` (mi.get_aabb() alone ignores node
## offsets/scales inside the GLTF and badly misjudges some models).
static func merged_aabb(inst: Node3D) -> AABB:
	var aabb := AABB()
	var found := false
	var inv := inst.global_transform.affine_inverse()
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var box: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if found:
			aabb = aabb.merge(box)
		else:
			aabb = box
			found = true
	return aabb


func _build_placeholder(d: WeaponData) -> void:
	var tint: Color = d.viewmodel_tint if d != null else Color(0.7, 0.7, 0.75)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.metallic = 0.45
	mat.roughness = 0.5
	if d != null and d.is_melee():
		var blade := MeshInstance3D.new()
		var blade_mesh := BoxMesh.new()
		blade_mesh.size = Vector3(0.012, 0.05, 0.3)
		blade_mesh.material = mat
		blade.mesh = blade_mesh
		blade.position = Vector3(0, 0, -0.22)
		_model_root.add_child(blade)
		var handle := MeshInstance3D.new()
		var handle_mesh := BoxMesh.new()
		handle_mesh.size = Vector3(0.03, 0.04, 0.12)
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color(0.15, 0.12, 0.1)
		handle_mesh.material = hm
		handle.mesh = handle_mesh
		handle.position = Vector3(0, -0.01, 0.0)
		_model_root.add_child(handle)
		return
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.055, 0.09, 0.36)
	body_mesh.material = mat
	body.mesh = body_mesh
	body.position = Vector3(0, 0, -0.18)
	_model_root.add_child(body)
	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.014
	barrel_mesh.bottom_radius = 0.014
	barrel_mesh.height = 0.24
	barrel_mesh.material = mat
	barrel.mesh = barrel_mesh
	barrel.rotation.x = PI * 0.5
	barrel.position = Vector3(0, 0.02, -0.44)
	_model_root.add_child(barrel)
	var grip := MeshInstance3D.new()
	var grip_mesh := BoxMesh.new()
	grip_mesh.size = Vector3(0.04, 0.12, 0.05)
	grip_mesh.material = mat
	grip.mesh = grip_mesh
	grip.position = Vector3(0, -0.09, -0.06)
	grip.rotation.x = 0.25
	_model_root.add_child(grip)


func muzzle_global() -> Vector3:
	if _muzzle != null and _muzzle.is_inside_tree():
		return _muzzle.global_position
	return global_position


func set_move_state(speed_frac: float, grounded: bool) -> void:
	_speed_frac = speed_frac
	_grounded = grounded


func set_ads_amount(a: float) -> void:
	_ads_amount = a


func add_sway(mouse_rel: Vector2) -> void:
	_sway += mouse_rel * 0.00012
	_sway = _sway.clamp(Vector2(-0.02, -0.02), Vector2(0.02, 0.02))


func kick(d: WeaponData) -> void:
	_kick_pos = minf(_kick_pos + 0.035, 0.1)
	_kick_rot = minf(_kick_rot + deg_to_rad(d.recoil_kick_deg) * 1.6, 0.3)


func flash() -> void:
	if _flash == null:
		return
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	get_tree().create_timer(0.045).timeout.connect(func() -> void:
		if is_instance_valid(_flash):
			_flash.visible = false)


func play_reload(duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", -0.5, duration * 0.3)
	tw.tween_interval(duration * 0.4)
	tw.tween_property(self, "rotation:x", 0.0, duration * 0.3)


func _process(delta: float) -> void:
	if _grounded and _speed_frac > 0.05:
		_bob_t += delta * (4.0 + 8.0 * _speed_frac)
	var bob_amp := 0.006 * _speed_frac * (1.0 - _ads_amount * 0.85)
	var bob := Vector3(sin(_bob_t) * bob_amp, absf(cos(_bob_t)) * bob_amp * 0.8, 0)
	_kick_pos = move_toward(_kick_pos, 0.0, delta * 0.5)
	_kick_rot = move_toward(_kick_rot, 0.0, delta * 2.2)
	_sway = _sway.move_toward(Vector2.ZERO, delta * 0.12)
	var base := HIP_POS.lerp(ADS_POS, _ads_amount)
	var target := base + bob + Vector3(-_sway.x, _sway.y, _kick_pos)
	position = position.lerp(target, clampf(delta * 14.0, 0.0, 1.0))
	rotation.x = lerpf(rotation.x, _kick_rot, clampf(delta * 16.0, 0.0, 1.0)) if _kick_rot > 0.001 else lerpf(rotation.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))

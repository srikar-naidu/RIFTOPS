class_name Fx
extends RefCounted
## One-shot combat visual/audio effects (tracers, impacts, corpses, sounds).
## All helpers add temporary nodes that free themselves.

static func unshaded_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.6
	return m


static func tracer(world: Node, from: Vector3, to: Vector3, color := Color(1.0, 0.82, 0.4)) -> void:
	var length := from.distance_to(to)
	if length < 0.6 or world == null or not world.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.014, 0.014, length)
	mesh.material = unshaded_mat(color)
	mi.mesh = mesh
	world.add_child(mi)
	var dir := (to - from).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(dir, up), (from + to) * 0.5)
	var tw := mi.create_tween()
	tw.tween_property(mi, "transparency", 1.0, 0.07)
	tw.tween_callback(mi.queue_free)


static func impact(world: Node, pos: Vector3, normal: Vector3, flesh: bool) -> void:
	if world == null or not world.is_inside_tree():
		return
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = normal
	mat.spread = 42.0
	mat.initial_velocity_min = 1.6
	mat.initial_velocity_max = 4.5
	mat.gravity = Vector3(0, -9.0, 0)
	mat.scale_min = 0.4
	mat.scale_max = 1.0
	p.process_material = mat
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.03, 0.03)
	mesh.material = unshaded_mat(Color(0.85, 0.25, 0.2) if flesh else Color(0.95, 0.8, 0.5))
	p.draw_pass_1 = mesh
	p.amount = 10
	p.lifetime = 0.3
	p.one_shot = true
	p.explosiveness = 1.0
	world.add_child(p)
	p.global_position = pos + normal * 0.02
	p.emitting = true
	p.finished.connect(p.queue_free)


static func corpse(world: Node, pos: Vector3, yaw: float, color: Color) -> void:
	if world == null or not world.is_inside_tree():
		return
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 1.7
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.35)
	mesh.material = m
	mi.mesh = mesh
	root.add_child(mi)
	world.add_child(root)
	root.global_position = pos + Vector3.UP * 0.35
	root.rotation.y = yaw
	mi.rotation.x = PI * 0.5
	var tw := root.create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(root, "position:y", root.position.y - 1.2, 1.6)
	tw.tween_callback(root.queue_free)


static func play_sound_2d(host: Node, stream: AudioStream, volume_db := 0.0) -> void:
	if stream == null or host == null or not host.is_inside_tree():
		return
	var ap := AudioStreamPlayer.new()
	ap.stream = stream
	ap.volume_db = volume_db
	ap.bus = &"Master"
	host.add_child(ap)
	ap.play()
	ap.finished.connect(ap.queue_free)


static func play_sound_3d(world: Node, stream: AudioStream, pos: Vector3, volume_db := 0.0) -> void:
	if stream == null or world == null or not world.is_inside_tree():
		return
	var ap := AudioStreamPlayer3D.new()
	ap.stream = stream
	ap.volume_db = volume_db
	ap.unit_size = 14.0
	ap.max_distance = 90.0
	world.add_child(ap)
	ap.global_position = pos
	ap.play()
	ap.finished.connect(ap.queue_free)

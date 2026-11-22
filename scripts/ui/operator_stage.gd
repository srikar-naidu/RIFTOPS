extends SubViewportContainer
## A private, non-networked showroom. Rendering stops when the lobby is hidden.
var _viewport: SubViewport
var _world: Node3D

func _material(color: Color, metal := 0.0, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = 0.55
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	return material

func _box(position_value: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = material
	instance.mesh = mesh
	instance.position = position_value
	_world.add_child(instance)
	return instance

func _ready() -> void:
	UiUtil.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if DisplayServer.get_name() == "headless":
		return
	stretch = true
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("243b46")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("a5c7d1")
	settings.ambient_light_energy = 0.65
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.fog_enabled = true
	settings.fog_light_color = Color("46616b")
	settings.fog_density = 0.015
	environment.environment = settings
	_world.add_child(environment)
	var camera := Camera3D.new()
	_world.add_child(camera)
	camera.position = Vector3(0.0, 1.45, 3.8)
	camera.look_at(Vector3(0.15, 1.05, 0))
	camera.fov = 43
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -25, 0)
	key.light_color = Color("edf5e5")
	key.light_energy = 1.6
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 20
	_world.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.5, 2.4, -1.5)
	rim.light_color = Color("63d9e6")
	rim.light_energy = 3.0
	rim.omni_range = 8
	_world.add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(1, 2, 2.3)
	fill.light_color = Color("e3e7cd")
	fill.light_energy = 1.6
	fill.omni_range = 6
	_world.add_child(fill)
	_build_hangar()
	_build_operator()
	visibility_changed.connect(_update_visibility)
	_update_visibility()

func _update_visibility() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED

func _build_hangar() -> void:
	var concrete := _material(Color("455057"))
	var steel := _material(Color("27343b"), 0.65)
	var trim := _material(Color("889899"), 0.5)
	var glass := _material(Color("8ec8d3"), 0.0, true)
	var yellow := _material(Color("b8c246"))
	_box(Vector3(0, -0.12, -3), Vector3(24, 0.2, 25), concrete)
	_box(Vector3(0, 5.4, -3), Vector3(24, 0.25, 25), steel)
	_box(Vector3(0, 2.7, -8), Vector3(24, 5.4, 0.3), concrete)
	for x in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		_box(Vector3(x, 3.5, -7.8), Vector3(3.6, 2.4, 0.08), glass)
		_box(Vector3(x, 3.5, -7.65), Vector3(0.06, 2.5, 0.1), steel)
		_box(Vector3(x, 3.5, -7.64), Vector3(3.6, 0.06, 0.12), steel)
		_box(Vector3(x - 1.9, 2.7, -7.5), Vector3(0.25, 5.4, 0.4), steel)
	for z in [-6.0, -2.0, 2.0]:
		_box(Vector3(-5, 2.7, z), Vector3(0.35, 5.4, 0.35), steel)
		_box(Vector3(5, 2.7, z), Vector3(0.35, 5.4, 0.35), steel)
		_box(Vector3(0, 5.0, z), Vector3(10, 0.35, 0.35), steel)
		_box(Vector3(0, 4.77, z), Vector3(3, 0.04, 0.2), glass)
	# Service gantry and railings give the scene depth behind the operator.
	_box(Vector3(0, 2.0, -6.2), Vector3(16, 0.18, 2.5), steel)
	for x in range(-7, 8):
		_box(Vector3(x, 2.5, -4.9), Vector3(0.04, 1, 0.04), trim)
	_box(Vector3(0, 3, -4.9), Vector3(15, 0.05, 0.05), trim)
	for x in [-1.3, 1.3]:
		_box(Vector3(x, 0.005, -0.5), Vector3(0.045, 0.01, 4.5), yellow)
	for z in [-2.7, 1.7]:
		_box(Vector3(0, 0.005, z), Vector3(2.6, 0.01, 0.045), yellow)
	for i in range(5):
		var locker := _box(Vector3(2.7 + i * 0.6, 0.8, -4.2), Vector3(0.55, 1.6, 0.65), steel)
		_box(locker.position + Vector3(0.15, 0, 0.34), Vector3(0.035, 0.2, 0.03), trim)
	for position_value: Vector3 in [Vector3(-3, 0, -2.4), Vector3(-3.6, 0, -3.2), Vector3(3, 0, -1.8)]:
		var prop := (load("res://assets/props/fantasy_props/Crate_Metal.gltf") as PackedScene).instantiate() as Node3D
		_world.add_child(prop)
		var bounds := WeaponView.merged_aabb(prop)
		prop.scale *= 0.75 / maxf(bounds.size.y, 0.01)
		prop.position = position_value - Vector3.UP * bounds.position.y * prop.scale.y

func _build_operator() -> void:
	var actor := (load("res://assets/characters/rift_operator.tscn") as PackedScene).instantiate() as Node3D
	_world.add_child(actor)
	var bounds := WeaponView.merged_aabb(actor)
	var scale_factor := 2.1 / maxf(bounds.size.y, 0.01)
	actor.scale = Vector3.ONE * scale_factor
	actor.position.y = -bounds.position.y * scale_factor
	actor.rotation.y = PI - 0.3
	var animation := actor.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation != null and animation.has_animation("Idle"):
		animation.play("Idle")


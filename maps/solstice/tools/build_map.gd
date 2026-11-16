# Solstice map generator. Authors res://maps/solstice/solstice.tscn as a text scene.
# Run:  Godot --headless --path . --script res://maps/solstice/tools/build_map.gd
#
# Layout is data-driven below; regenerate any time. Coordinates: 1 unit = 1 m,
# x = east(+)/west(-), z = north(+)/south(-). Attackers spawn south (-Z),
# defenders north (+Z), matching the graybox/map contract.
extends SceneTree

const OUT_PATH := "res://maps/solstice/solstice.tscn"
const TEX := "res://assets/textures/"
const FPROPS := "res://assets/props/fantasy_props/"
const FONT_PATH := "res://assets/fonts/Rajdhani-Bold.ttf"
const SKY_HDR := "res://assets/sky/kloofendal_48d_partly_cloudy_puresky_2k.hdr"

const WALL_H := 4.2      # walls sink 0.2 below floor top (y=0) to seal seams
const WALL_BASE := -0.2
const WALL_T := 0.5
const LINTEL_BASE := 2.8 # door clearance; lintels run 2.8..4.0

# Prop base sizes measured by tools/probe_props.gd (model AABB at scale 1,
# plus the AABB's min-y so models can be seated on the floor). If a model is
# missing at build time we fall back to primitive meshes so the map never
# depends on the asset drop.
var PROP_BASE := {
	"Barrel": [Vector3(0.70, 0.90, 0.70), 0.0],
	"Crate_Wooden": [Vector3(0.84, 0.93, 0.91), -0.05],
	"Crate_Metal": [Vector3(0.86, 0.87, 0.87), 0.0],
	"Stall_Empty": [Vector3(1.84, 2.63, 0.93), 0.0],
	"Stall_Cart_Empty": [Vector3(3.02, 2.63, 1.06), 0.0],
	"Bench": [Vector3(2.78, 0.53, 0.53), -0.01],
	"Banner_1": [Vector3(1.61, 2.39, 0.19), -1.55],
	"Banner_2": [Vector3(1.61, 2.08, 0.19), -1.23],
	"Bag": [Vector3(0.66, 0.80, 0.54), 0.0],
	"Chest_Wood": [Vector3(1.28, 0.72, 0.76), -0.02],
	"Bucket_Wooden_1": [Vector3(0.43, 0.29, 0.38), 0.0],
	"Vase_2": [Vector3(0.69, 0.52, 0.69), 0.0],
}

var map_root: Node3D
var world: Node3D
var decor: Node3D
var mats := {}
var meshes := {}
var shapes := {}
var counters := {}

func _init() -> void:
	_build()
	for c in map_root.get_children():
		_set_owners(c)
	var packed := PackedScene.new()
	var err := packed.pack(map_root)
	if err != OK:
		push_error("PackedScene.pack failed: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT_PATH)
	if err != OK:
		push_error("ResourceSaver.save failed: %d" % err)
		quit(1)
		return
	print("BUILD OK: saved %s" % OUT_PATH)
	map_root.free()
	quit(0)

func _set_owners(n: Node) -> void:
	n.owner = map_root
	if n.scene_file_path != "":
		return # instanced sub-scene: don't own its internals
	for c in n.get_children():
		_set_owners(c)

func _uname(base: String) -> String:
	var i: int = counters.get(base, 0) + 1
	counters[base] = i
	return "%s%d" % [base, i]

# ---------------------------------------------------------------- materials

func mat_tex(key: String, base: String, tint: Color, tile_m: float, use_normal := true) -> StandardMaterial3D:
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	var color_path := TEX + base + "_Color.jpg"
	if ResourceLoader.exists(color_path):
		m.albedo_texture = load(color_path)
		var rough := TEX + base + "_Roughness.jpg"
		if ResourceLoader.exists(rough):
			m.roughness_texture = load(rough)
		var nrm := TEX + base + "_NormalGL.jpg"
		if use_normal and ResourceLoader.exists(nrm):
			m.normal_enabled = true
			m.normal_texture = load(nrm)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		var s := 1.0 / tile_m
		m.uv1_scale = Vector3(s, s, s)
	m.albedo_color = tint
	mats[key] = m
	return m

func mat_flat(key: String, color: Color, emission := 0.0, rough := 0.9) -> StandardMaterial3D:
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = color
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	mats[key] = m
	return m

func mat_glass(key: String, color: Color) -> StandardMaterial3D:
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats[key] = m
	return m

# ------------------------------------------------------------- mesh helpers

func box_mesh(size: Vector3, m: Material) -> BoxMesh:
	var key := "%s|%.2f,%.2f,%.2f" % [m.resource_name, size.x, size.y, size.z]
	if meshes.has(key):
		return meshes[key]
	var b := BoxMesh.new()
	b.size = size
	b.material = m
	b.add_uv2 = true
	meshes[key] = b
	return b

func cyl_mesh(radius: float, height: float, m: Material) -> CylinderMesh:
	var key := "cyl|%s|%.2f,%.2f" % [m.resource_name, radius, height]
	if meshes.has(key):
		return meshes[key]
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.material = m
	c.add_uv2 = true
	c.radial_segments = 24
	meshes[key] = c
	return c

func box_shape(size: Vector3) -> BoxShape3D:
	var key := "%.2f,%.2f,%.2f" % [size.x, size.y, size.z]
	if shapes.has(key):
		return shapes[key]
	var s := BoxShape3D.new()
	s.size = size
	shapes[key] = s
	return s

func cyl_shape(radius: float, height: float) -> CylinderShape3D:
	var key := "cyl|%.2f,%.2f" % [radius, height]
	if shapes.has(key):
		return shapes[key]
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	shapes[key] = s
	return s

# ------------------------------------------------------------- node helpers

func static_box(parent: Node, nm: String, center: Vector3, size: Vector3, m: Material, rot_y_deg := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = _uname(nm)
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	if rot_y_deg != 0.0:
		body.rotation_degrees = Vector3(0, rot_y_deg, 0)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = box_mesh(size, m)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = box_shape(size)
	body.add_child(cs)
	parent.add_child(body)
	return body

func static_cyl(parent: Node, nm: String, base_pos: Vector3, radius: float, height: float, m: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = _uname(nm)
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = base_pos + Vector3(0, height * 0.5, 0)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = cyl_mesh(radius, height, m)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = cyl_shape(radius, height)
	body.add_child(cs)
	parent.add_child(body)
	return body

func decor_box(parent: Node, nm: String, center: Vector3, size: Vector3, m: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = _uname(nm)
	mi.mesh = box_mesh(size, m)
	mi.position = center
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group("decor_nocollide", true)
	parent.add_child(mi)
	return mi

func wall_x(parent: Node, x: float, z1: float, z2: float, m: Material, h := WALL_H, base := WALL_BASE, t := WALL_T) -> void:
	static_box(parent, "WallX", Vector3(x, base + h * 0.5, (z1 + z2) * 0.5), Vector3(t, h, z2 - z1), m)

func wall_z(parent: Node, z: float, x1: float, x2: float, m: Material, h := WALL_H, base := WALL_BASE, t := WALL_T) -> void:
	static_box(parent, "WallZ", Vector3((x1 + x2) * 0.5, base + h * 0.5, z), Vector3(x2 - x1, h, t), m)

func wall_diag(parent: Node, p1: Vector2, p2: Vector2, m: Material, h := WALL_H, base := WALL_BASE, t := WALL_T) -> void:
	var d := p2 - p1
	var length := d.length()
	var rot_y := rad_to_deg(atan2(-d.y, d.x))
	static_box(parent, "WallDiag", Vector3((p1.x + p2.x) * 0.5, base + h * 0.5, (p1.y + p2.y) * 0.5), Vector3(length, h, t), m, rot_y)

func floor_rect(parent: Node, nm: String, x1: float, z1: float, x2: float, z2: float, m: Material, thick := 0.6, top := 0.0) -> void:
	static_box(parent, nm, Vector3((x1 + x2) * 0.5, top - thick * 0.5, (z1 + z2) * 0.5), Vector3(x2 - x1, thick, z2 - z1), m)

func ramp(parent: Node, nm: String, start: Vector3, end: Vector3, width: float, m: Material) -> void:
	var t := 0.35
	var dir := end - start
	var length := dir.length() + 0.15
	var basis := Basis.looking_at(dir.normalized(), Vector3.UP)
	var center := (start + end) * 0.5 - basis.y * (t * 0.5)
	var body := StaticBody3D.new()
	body.name = _uname(nm)
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = Transform3D(basis, center)
	var size := Vector3(width, t, length)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = box_mesh(size, m)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = box_shape(size)
	body.add_child(cs)
	parent.add_child(body)

func lintel_x(parent: Node, x: float, z1: float, z2: float, m: Material) -> void:
	var h := WALL_H + WALL_BASE - LINTEL_BASE
	static_box(parent, "Lintel", Vector3(x, LINTEL_BASE + h * 0.5, (z1 + z2) * 0.5), Vector3(WALL_T, h, z2 - z1), m)

func lintel_z(parent: Node, z: float, x1: float, x2: float, m: Material) -> void:
	var h := WALL_H + WALL_BASE - LINTEL_BASE
	static_box(parent, "Lintel", Vector3((x1 + x2) * 0.5, LINTEL_BASE + h * 0.5, z), Vector3(x2 - x1, h, WALL_T), m)

func awning(parent: Node, center: Vector3, size: Vector3, m: Material, rot_deg: Vector3) -> void:
	var body := static_box(parent, "Awning", center, size, m)
	body.rotation_degrees = rot_deg

# Cover prop: deterministic primitive collision; visual is a CC0 model when
# available, else the primitive box/cylinder itself.
func cover_crate(parent: Node, x: float, z: float, rot := 0.0, base_y := 0.0, model := "Crate_Wooden", size := 1.2) -> void:
	var m: Material = mats["wood"] if model != "Crate_Metal" else mats["metal"]
	var body := StaticBody3D.new()
	body.name = _uname("Crate")
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(x, base_y + size * 0.5, z)
	body.rotation_degrees = Vector3(0, rot, 0)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = box_shape(Vector3(size, size, size))
	body.add_child(cs)
	var visual := _model_or_null(model, Vector3(size, size, size))
	if visual != null:
		visual.position += Vector3(0, -size * 0.5, 0) # body center -> floor point
		body.add_child(visual)
	else:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = box_mesh(Vector3(size, size, size), m)
		body.add_child(mi)
	parent.add_child(body)

func cover_barrel(parent: Node, x: float, z: float) -> void:
	var r := 0.42
	var h := 1.0
	var body := StaticBody3D.new()
	body.name = _uname("Barrel")
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(x, h * 0.5, z)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = cyl_shape(r, h)
	body.add_child(cs)
	var visual := _model_or_null("Barrel", Vector3(r * 2, h, r * 2))
	if visual != null:
		visual.position += Vector3(0, -h * 0.5, 0) # body center -> floor point
		body.add_child(visual)
	else:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = cyl_mesh(r, h, mats["metal_barrel"])
		body.add_child(mi)
	parent.add_child(body)

# Instance a fantasy_props model scaled so its AABB fits inside target (fit
# the tightest axis so it never exceeds the collision box). Returns null if
# the asset isn't available/importable yet.
func _model_or_null(model: String, target: Vector3) -> Node3D:
	var path := FPROPS + model + ".gltf"
	if not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var inst: Node3D = ps.instantiate()
	inst.name = "Model"
	var base: Vector3 = PROP_BASE[model][0] if PROP_BASE.has(model) else Vector3.ONE
	var ymin: float = PROP_BASE[model][1] if PROP_BASE.has(model) else 0.0
	var s: float = min(target.x / base.x, min(target.y / base.y, target.z / base.z))
	inst.scale = Vector3(s, s, s)
	inst.position = Vector3(0, -ymin * s, 0) # seat the model's AABB base at y=0
	return inst

# Pure-decor model (no gameplay role). Optional box collider when solid.
func decor_model(parent: Node, model: String, pos: Vector3, rot_y: float, target_h: float, solid := false, collider := Vector3.ZERO) -> void:
	var path := FPROPS + model + ".gltf"
	if not ResourceLoader.exists(path):
		return
	var ps: PackedScene = load(path)
	if ps == null:
		return
	var base: Vector3 = PROP_BASE[model][0] if PROP_BASE.has(model) else Vector3.ONE
	var s := target_h / base.y
	if solid and collider != Vector3.ZERO:
		var body := StaticBody3D.new()
		body.name = _uname(model)
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = pos
		body.rotation_degrees = Vector3(0, rot_y, 0)
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		cs.shape = box_shape(collider)
		cs.position = Vector3(0, collider.y * 0.5, 0)
		body.add_child(cs)
		var inst: Node3D = ps.instantiate()
		inst.name = "Model"
		inst.scale = Vector3(s, s, s)
		body.add_child(inst)
		parent.add_child(body)
	else:
		var inst2: Node3D = ps.instantiate()
		inst2.name = _uname(model)
		inst2.scale = Vector3(s, s, s)
		inst2.position = pos
		inst2.rotation_degrees = Vector3(0, rot_y, 0)
		inst2.add_to_group("decor_nocollide", true)
		parent.add_child(inst2)

func sign_label(parent: Node, text: String, pos: Vector3, rot_deg: Vector3, size_px: int, color: Color, outline: Color) -> void:
	var lb := Label3D.new()
	lb.name = _uname("Sign" + text)
	lb.text = text
	lb.position = pos
	lb.rotation_degrees = rot_deg
	lb.font_size = size_px
	lb.pixel_size = 0.01
	lb.modulate = color
	lb.outline_size = int(size_px / 12.0)
	lb.outline_modulate = outline
	if ResourceLoader.exists(FONT_PATH):
		lb.font = load(FONT_PATH)
	lb.add_to_group("decor_nocollide", true)
	parent.add_child(lb)

func marker(parent: Node, nm: String, group: String, x: float, z: float, face_south: bool) -> void:
	var mk := Marker3D.new()
	mk.name = nm
	mk.position = Vector3(x, 0, z)
	if not face_south:
		# -Z must face the enemy: attackers (south, enemy at +Z) get rotated 180
		mk.rotation_degrees = Vector3(0, 180, 0)
	mk.add_to_group(group, true)
	parent.add_child(mk)

func plant_zone(parent: Node, nm: String, group: String, center: Vector3, fill: Material, frame: Material) -> void:
	var zone := Area3D.new()
	zone.name = nm
	zone.position = center
	zone.collision_layer = 16 # physics layer 5: triggers
	zone.collision_mask = 2   # players
	zone.monitoring = true
	zone.add_to_group(group, true)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.position = Vector3(0, 1, 0)
	cs.shape = box_shape(Vector3(6, 2, 6))
	zone.add_child(cs)
	var fill_mi := MeshInstance3D.new()
	fill_mi.name = "Fill"
	fill_mi.mesh = box_mesh(Vector3(6, 0.05, 6), fill)
	fill_mi.position = Vector3(0, 0.03, 0)
	fill_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone.add_child(fill_mi)
	for i in 4:
		var strip := MeshInstance3D.new()
		strip.name = "Frame%d" % i
		var horizontal := i < 2
		strip.mesh = box_mesh(Vector3(6.2, 0.22, 0.14) if horizontal else Vector3(0.14, 0.22, 6.2), frame)
		var off := 3.03
		strip.position = Vector3(0, 0.11, off if i == 0 else (-off if i == 1 else 0)) if horizontal \
			else Vector3(off if i == 2 else -off, 0.11, 0)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		zone.add_child(strip)
	parent.add_child(zone)

func buy_barrier(parent: Node, group: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = _uname("Barrier")
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	body.add_to_group(group, true)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = box_mesh(size, mats["barrier"])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = box_shape(size)
	body.add_child(cs)
	parent.add_child(body)

func ambient_audio(parent: Node, nm: String, pos: Vector3, stream_path := "", vol_db := 0.0) -> void:
	var ap := AudioStreamPlayer3D.new()
	ap.name = nm
	ap.position = pos
	ap.max_distance = 24.0
	ap.unit_size = 6.0
	ap.autoplay = true
	ap.volume_db = vol_db
	if stream_path != "" and ResourceLoader.exists(stream_path):
		ap.stream = load(stream_path)  # .ogg imports have loop=true (see .import)
	ap.add_to_group("ambient_audio", true)
	parent.add_child(ap)

# ------------------------------------------------------------------- build

func _build() -> void:
	map_root = Node3D.new()
	map_root.name = "Solstice"

	_make_materials()
	_make_environment()

	world = Node3D.new()
	world.name = "World"
	map_root.add_child(world)
	decor = Node3D.new()
	decor.name = "Decor"
	map_root.add_child(decor)

	_make_floors()
	_make_walls()
	_make_cover()
	_make_signs_and_trim()
	_make_markers_zones_barriers()
	_make_audio()

func _make_materials() -> void:
	# Area identity: warm plaster/sand = A side & attacker south, cool
	# plaster/stone = B side, brick = mid & defender links.
	mat_tex("plaster_warm", "PaintedPlaster017_1K-JPG", Color(1.0, 0.93, 0.84), 3.0)
	mat_tex("plaster_cool", "Plaster001_1K-JPG", Color(0.85, 0.90, 0.98), 3.0)
	mat_tex("brick", "Bricks075A_1K-JPG", Color(0.98, 0.94, 0.90), 2.6)
	mat_tex("paving", "PavingStones138_2K-JPG", Color(1, 1, 1), 3.2)
	mat_tex("paving_warm", "PavingStones138_2K-JPG", Color(1.0, 0.92, 0.80), 3.2)
	mat_tex("paving_cool", "PavingStones138_2K-JPG", Color(0.80, 0.87, 1.0), 3.2)
	mat_tex("concrete", "Concrete034_1K-JPG", Color(0.98, 0.97, 0.95), 2.8)
	mat_tex("concrete_warm", "Concrete034_1K-JPG", Color(1.0, 0.92, 0.80), 2.8)
	mat_tex("wood", "Planks037A_1K-JPG", Color(1, 1, 1), 1.3)
	mat_tex("wood_floor", "WoodFloor043_1K-JPG", Color(1, 1, 1), 2.0)
	mat_tex("metal", "PaintedMetal004_1K-JPG", Color(0.62, 0.78, 0.80), 1.6)
	mat_tex("metal_barrel", "PaintedMetal004_1K-JPG", Color(0.85, 0.48, 0.36), 1.2)
	mat_tex("roof", "RoofingTiles013A_1K-JPG", Color(1, 1, 1), 1.8)
	mat_tex("fabric_green", "Fabric030_1K-JPG", Color(0.44, 0.62, 0.42), 1.0)
	mat_tex("sand", "Fabric030_1K-JPG", Color(0.80, 0.73, 0.58), 0.8)
	mat_flat("accent_a", Color(0.86, 0.36, 0.20), 0.5)
	mat_flat("accent_b", Color(0.14, 0.62, 0.66), 0.5)
	mat_flat("hedge", Color(0.30, 0.46, 0.27), 0.0, 1.0)
	mat_flat("water", Color(0.30, 0.72, 0.78), 0.35, 0.15)
	mat_flat("panel", Color(0.97, 0.95, 0.90), 0.0, 0.8)
	mat_flat("zone_frame", Color(0.95, 0.80, 0.25), 0.8)
	mat_glass("zone_a_fill", Color(0.20, 0.80, 0.35, 0.30))
	mat_glass("zone_b_fill", Color(0.90, 0.55, 0.15, 0.30))
	mat_glass("barrier", Color(0.25, 0.75, 0.95, 0.30))

func _make_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	if ResourceLoader.exists(SKY_HDR):
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(SKY_HDR)
		sky.sky_material = pano
	else:
		var proc := ProceduralSkyMaterial.new()
		proc.sky_top_color = Color(0.30, 0.50, 0.78)
		proc.sky_horizon_color = Color(0.82, 0.80, 0.72)
		proc.ground_bottom_color = Color(0.22, 0.19, 0.15)
		proc.ground_horizon_color = Color(0.82, 0.80, 0.72)
		sky.sky_material = proc
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.83, 0.76)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	map_root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42, 210, 0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 85.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS # mobile perf
	sun.light_bake_mode = Light3D.BAKE_STATIC
	map_root.add_child(sun)

	var lm := LightmapGI.new()
	lm.name = "LightmapGI"
	lm.quality = LightmapGI.BAKE_QUALITY_MEDIUM
	lm.bounces = 2
	lm.directional = false
	lm.max_texture_size = 4096
	lm.generate_probes_subdiv = LightmapGI.GENERATE_PROBES_SUBDIV_8
	lm.environment_mode = LightmapGI.ENVIRONMENT_MODE_SCENE
	map_root.add_child(lm)

func _make_floors() -> void:
	var f := Node3D.new()
	f.name = "Floors"
	world.add_child(f)
	var P: Material = mats["paving"]
	var PW: Material = mats["paving_warm"]
	var PC: Material = mats["paving_cool"]
	var C: Material = mats["concrete"]
	var CW: Material = mats["concrete_warm"]
	floor_rect(f, "FloorSpawnA", -16, -30, 16, -22, C)
	floor_rect(f, "FloorMidS", -3, -22, 3, -16, P)
	floor_rect(f, "FloorMid", -8, -16, 8, 8, P)
	floor_rect(f, "FloorALobby", 16, -26, 33, -12, CW)
	floor_rect(f, "FloorAMain", 25, -12, 33, 10, CW)
	floor_rect(f, "FloorALink1", 8, -2, 16, 4, CW)
	floor_rect(f, "FloorALink2", 10, 4, 16, 13, CW)
	floor_rect(f, "FloorMarket1", -16, 0, -8, 6, PC)
	floor_rect(f, "FloorMarket2", -20, 6, -12, 10, PC)
	floor_rect(f, "FloorBLobby", -33, -26, -16, -14, PC)
	floor_rect(f, "FloorBMain", -33, -14, -26, 10, PC)
	floor_rect(f, "FloorASite", 16, 10, 33, 27, PW)
	floor_rect(f, "FloorBSite", -33, 10, -14, 27, PC)
	floor_rect(f, "FloorDefLink", -4, 8, 3, 23, P)
	floor_rect(f, "FloorDefSpawn", -14, 23, 16, 30, C)

func _make_walls() -> void:
	var w := Node3D.new()
	w.name = "Walls"
	world.add_child(w)
	var WARM: Material = mats["plaster_warm"]
	var COOL: Material = mats["plaster_cool"]
	var BRICK: Material = mats["brick"]

	# X-constant walls: [x, z1, z2, material]
	var xwalls := [
		[-16.0, -30.0, -26.0, WARM], [-16.0, -23.0, -14.0, COOL], [-16.0, 0.0, 6.0, COOL],
		[-26.0, -14.0, 10.0, COOL], [-20.0, 6.0, 10.0, COOL], [-12.0, 6.0, 10.0, COOL],
		[-14.0, 10.0, 23.0, COOL], [-14.0, 26.5, 30.0, COOL],
		[-8.0, -16.0, 1.0, BRICK], [-8.0, 5.0, 8.0, BRICK],
		[-3.0, -22.0, -16.0, WARM], [3.0, -22.0, -16.0, WARM],
		[-4.0, 8.0, 23.0, BRICK], [3.0, 8.0, 23.0, BRICK],
		[8.0, -16.0, -1.0, BRICK], [8.0, 3.0, 8.0, BRICK],
		[10.0, 4.0, 13.0, WARM],
		[16.0, -30.0, -26.0, WARM], [16.0, -23.0, -12.0, WARM], [16.0, -2.0, 4.0, WARM],
		[16.0, 4.0, 10.0, WARM], [16.0, 13.0, 23.0, WARM], [16.0, 26.5, 30.0, WARM],
		[25.0, -12.0, 10.0, WARM],
	]
	for a in xwalls:
		wall_x(w, a[0], a[1], a[2], a[3])

	# Z-constant walls: [z, x1, x2, material]
	var zwalls := [
		[-22.0, -16.0, -3.0, WARM], [-22.0, 3.0, 16.0, WARM],
		[-26.0, 16.0, 33.0, WARM], [-26.0, -33.0, -16.0, COOL],
		[-16.0, -8.0, -3.0, BRICK], [-16.0, 3.0, 8.0, BRICK],
		[-12.0, 16.0, 25.0, WARM], [-14.0, -26.0, -16.0, COOL],
		[-2.0, 8.0, 16.0, WARM], [4.0, 8.0, 10.0, WARM],
		[0.0, -16.0, -8.0, COOL], [6.0, -12.0, -8.0, COOL], [6.0, -20.0, -16.0, COOL],
		[8.0, -8.0, -3.0, BRICK], [8.0, 1.0, 8.0, BRICK],
		[13.0, 10.0, 16.0, WARM],
		[10.0, 25.0, 26.0, WARM], [10.0, 31.0, 33.0, WARM], [10.0, 16.0, 25.0, WARM],
		[10.0, -28.0, -20.0, COOL], [10.0, -15.0, -12.0, COOL],
		[23.0, -14.0, -4.0, BRICK], [23.0, 3.0, 16.0, BRICK],
		[27.0, 16.0, 33.0, WARM], [27.0, -33.0, -14.0, COOL],
	]
	for a in zwalls:
		wall_z(w, a[0], a[1], a[2], a[3])

	# Chamfered corners (off-angles) in mid
	wall_diag(w, Vector2(5, 8), Vector2(8, 5), BRICK)
	wall_diag(w, Vector2(-8, -13), Vector2(-5, -16), BRICK)

	# Outer boundary (taller, thicker)
	var B := Node3D.new()
	B.name = "Boundary"
	world.add_child(B)
	wall_z(B, -30.5, -34.0, 34.0, BRICK, 6.6, -0.6, 1.0)
	wall_z(B, 30.5, -34.0, 34.0, BRICK, 6.6, -0.6, 1.0)
	wall_x(B, 33.5, -31.0, 31.0, BRICK, 6.6, -0.6, 1.0)
	wall_x(B, -33.5, -31.0, 31.0, BRICK, 6.6, -0.6, 1.0)

	# Door lintels (doors are 2.8 m tall). x-doors then z-doors.
	var L := Node3D.new()
	L.name = "Lintels"
	world.add_child(L)
	# NOTE: no lintel on the heaven door (x=16, z 23..26.5) — its floor is the
	# raised platform (y=1.5), a lintel at 2.8 would block head clearance.
	for d in [
		[16.0, -26.0, -23.0, WARM],   # spawn -> A lobby
		[-16.0, -26.0, -23.0, COOL],  # spawn -> B lobby
		[8.0, -1.0, 3.0, BRICK],      # mid doors (east, to A link)
		[-8.0, 1.0, 5.0, BRICK],      # market door (west)
		[16.0, 10.0, 13.0, WARM],     # A link -> A site
		[-14.0, 23.0, 26.5, COOL],    # defender -> B back
	]:
		lintel_x(L, d[0], d[1], d[2], d[3])
	for d in [
		[-22.0, -3.0, 3.0, WARM],     # spawn -> mid corridor
		[-16.0, -3.0, 3.0, BRICK],    # mid south door
		[8.0, -3.0, 1.0, BRICK],      # mid north door
		[10.0, 26.0, 31.0, WARM],     # A main -> A site
		[10.0, -20.0, -15.0, COOL],   # market -> B site
		[10.0, -33.0, -28.0, COOL],   # B main -> B site
		[23.0, -4.0, 3.0, BRICK],     # def link -> def spawn
	]:
		lintel_z(L, d[0], d[1], d[2], d[3])

	# Tiled awnings over the site doors (art beat marking each site entrance)
	var AW := Node3D.new()
	AW.name = "Awnings"
	world.add_child(AW)
	awning(AW, Vector3(28.5, 4.35, 9.4), Vector3(5.6, 0.12, 2.0), mats["roof"], Vector3(-16, 0, 0))
	awning(AW, Vector3(-30.5, 4.35, 9.4), Vector3(5.6, 0.12, 2.0), mats["roof"], Vector3(-16, 0, 0))
	awning(AW, Vector3(-17.5, 4.35, 9.4), Vector3(5.6, 0.12, 2.0), mats["roof"], Vector3(-16, 0, 0))
	awning(AW, Vector3(6.9, 3.75, 1.0), Vector3(2.2, 0.12, 4.6), mats["fabric_green"], Vector3(0, 0, 14))
	awning(AW, Vector3(-6.9, 3.75, 3.0), Vector3(2.2, 0.12, 4.6), mats["fabric_green"], Vector3(0, 0, -14))

func _make_cover() -> void:
	var c := Node3D.new()
	c.name = "Cover"
	world.add_child(c)

	# ---- A site ----
	static_box(c, "GeneratorA", Vector3(24.5, 0.85, 17.0), Vector3(4, 1.7, 3), mats["metal"])
	decor_box(decor, "GeneratorTrim", Vector3(24.5, 1.74, 17.0), Vector3(4.1, 0.1, 3.1), mats["accent_a"])
	cover_crate(c, 31.0, 20.6, 8)
	cover_crate(c, 31.0, 21.9, -4)
	cover_crate(c, 31.0, 21.25, 0, 1.2)          # stacked
	cover_crate(c, 17.6, 12.2, 22)               # near A link door
	cover_crate(c, 27.0, 25.4, -12, 0.0, "Crate_Metal")
	cover_barrel(c, 23.2, 25.8)
	# Heaven platform + ramps (defender-side elevated position)
	static_box(c, "HeavenPlatform", Vector3(19.0, 0.75, 24.5), Vector3(6, 1.5, 5), mats["wood_floor"])
	ramp(c, "HeavenRampSite", Vector3(18, 0, 18), Vector3(18, 1.5, 21.95), 4.0, mats["wood_floor"])
	ramp(c, "HeavenRampSpawn", Vector3(13.05, 0, 24.75), Vector3(16, 1.5, 24.75), 3.5, mats["wood_floor"])

	# ---- B site ----
	cover_crate(c, -24.6, 17.0, 0)
	cover_crate(c, -23.4, 17.0, 0)
	cover_crate(c, -24.0, 17.0, 14, 1.2)         # stacked
	static_box(c, "BPillar", Vector3(-29.0, 1.9, 23.0), Vector3(2.5, 4.2, 2.5), mats["brick"])
	cover_crate(c, -16.6, 12.6, 15)
	cover_crate(c, -31.4, 13.0, 0, 0.0, "Crate_Metal")
	cover_barrel(c, -15.6, 25.4)

	# ---- Mid ----
	static_box(c, "Fountain", Vector3(0, 0.5, -4), Vector3(3, 1.0, 3), mats["concrete"])
	decor_box(decor, "FountainWater", Vector3(0, 1.02, -4), Vector3(2.4, 0.1, 2.4), mats["water"])
	static_box(c, "MidStallTable", Vector3(-6.2, 0.45, -9), Vector3(2.2, 0.9, 1.4), mats["wood"])
	awning(c, Vector3(-6.0, 2.5, -9), Vector3(2.6, 0.1, 1.9), mats["fabric_green"], Vector3(0, 0, -12))
	static_box(c, "PlanterMidNE", Vector3(5.8, 0.28, 6.3), Vector3(2, 0.55, 1), mats["concrete"])
	decor_box(decor, "HedgeMidNE", Vector3(5.8, 0.8, 6.3), Vector3(1.9, 0.5, 0.9), mats["hedge"])
	static_box(c, "PlanterMidW", Vector3(-7.2, 0.28, -3.0), Vector3(1, 0.55, 2.4), mats["concrete"])
	decor_box(decor, "HedgeMidW", Vector3(-7.2, 0.8, -3.0), Vector3(0.9, 0.5, 2.3), mats["hedge"])
	cover_barrel(c, 6.9, -14.7)
	cover_barrel(c, 5.7, -15.1)

	# ---- A lobby ----
	static_box(c, "KioskALobby", Vector3(22, 0.55, -17), Vector3(3, 1.1, 1.8), mats["wood"], 40)
	awning(c, Vector3(22, 2.45, -17), Vector3(3.4, 0.1, 2.2), mats["roof"], Vector3(0, 40, 12))
	cover_crate(c, 30.5, -24.6, -6)
	cover_barrel(c, 17.3, -13.4)

	# ---- B lobby ----
	cover_crate(c, -24.0, -17.6, 30)
	cover_crate(c, -25.3, -18.3, 18)
	cover_barrel(c, -17.6, -15.6)

	# ---- Long lanes: low jiggle cover ----
	static_box(c, "SandbagsAMain", Vector3(32.3, 0.4, 2.5), Vector3(1.6, 0.8, 1.1), mats["sand"])
	cover_barrel(c, -32.2, -6.0)
	cover_barrel(c, -31.4, -6.9)

	# ---- Spawns / def link dressing ----
	cover_crate(c, -13.0, -28.4, 0)
	cover_crate(c, -11.7, -28.6, 12)
	cover_crate(c, 12.5, 28.3, -8)
	cover_barrel(c, -10.8, 28.2)
	static_box(c, "PlanterDefLink", Vector3(-2.6, 0.28, 15.5), Vector3(1, 0.55, 2.4), mats["concrete"])
	decor_box(decor, "HedgeDefLink", Vector3(-2.6, 0.8, 15.5), Vector3(0.9, 0.5, 2.3), mats["hedge"])

	# Decorative CC0 props (skipped silently if assets not there yet)
	decor_model(c, "Stall_Empty", Vector3(-12.0, 0, 5.2), 180, 2.5, true, Vector3(1.9, 1.2, 1.0))
	decor_model(c, "Stall_Cart_Empty", Vector3(-29.5, 0, -17.5), 25, 2.0, true, Vector3(2.3, 1.1, 0.9))
	decor_model(decor, "Bench", Vector3(2.0, 0, 28.9), 0, 0.55)
	decor_model(decor, "Bench", Vector3(-6.5, 0, -28.9), 0, 0.55)
	decor_model(decor, "Bench", Vector3(2.4, 0, 20.0), 90, 0.55)
	decor_model(decor, "Banner_1", Vector3(7.55, 2.6, 5.5), -90, 2.2)
	decor_model(decor, "Banner_2", Vector3(-7.55, 2.6, -6.0), 90, 2.2)
	decor_model(decor, "Banner_1", Vector3(16.3, 2.6, 18.0), 90, 2.2)
	decor_model(decor, "Banner_2", Vector3(-14.3, 2.6, 18.0), -90, 2.2)
	decor_model(decor, "Bucket_Wooden_1", Vector3(-6.4, 0.92, -9.1), 30, 0.30)
	decor_model(decor, "Vase_2", Vector3(15.2, 0, 26.4), 0, 0.7)
	decor_model(decor, "Bag", Vector3(31.9, 0, 5.6), 140, 0.7)
	decor_model(decor, "Chest_Wood", Vector3(13.9, 0, 29.3), 190, 0.65)

func _make_signs_and_trim() -> void:
	var ink := Color(0.13, 0.15, 0.22)
	var cream := Color(0.97, 0.95, 0.90)
	# A site: door panel + huge lane letter + floor letter
	decor_box(decor, "PanelAMain", Vector3(28.5, 2.1, 9.69), Vector3(2.4, 2.4, 0.1), mats["panel"])
	sign_label(decor, "A", Vector3(28.5, 2.1, 9.62), Vector3(0, 180, 0), 200, ink, cream)
	sign_label(decor, "A", Vector3(32.94, 2.4, 0.0), Vector3(0, -90, 0), 320, mats["accent_a"].albedo_color, cream)
	sign_label(decor, "A", Vector3(15.66, 3.4, 11.5), Vector3(0, -90, 0), 110, ink, cream)
	sign_label(decor, "A", Vector3(24.5, 0.02, 21.5), Vector3(-90, 0, 0), 420, Color(0.86, 0.36, 0.20, 0.55), Color(0, 0, 0, 0))
	# B site
	decor_box(decor, "PanelBMarket", Vector3(-17.5, 2.1, 9.69), Vector3(2.4, 2.4, 0.1), mats["panel"])
	sign_label(decor, "B", Vector3(-17.5, 2.1, 9.62), Vector3(0, 180, 0), 200, ink, cream)
	sign_label(decor, "B", Vector3(-32.94, 2.4, -2.0), Vector3(0, 90, 0), 320, mats["accent_b"].albedo_color, cream)
	sign_label(decor, "B", Vector3(-24.0, 0.02, 21.5), Vector3(-90, 0, 0), 420, Color(0.14, 0.62, 0.66, 0.55), Color(0, 0, 0, 0))
	# Wayfinding accent trims (emissive strips at skirting height)
	for t in [
		[Vector3(16.29, 0.14, -17.5), Vector3(0.07, 0.28, 11.0), "accent_a"],  # lobby W wall
		[Vector3(25.29, 0.14, -1.0), Vector3(0.07, 0.28, 22.0), "accent_a"],   # A main W wall
		[Vector3(7.68, 0.14, -8.5), Vector3(0.07, 0.28, 15.0), "accent_a"],    # mid E wall -> A
		[Vector3(-26.29, 0.14, -2.0), Vector3(0.07, 0.28, 24.0), "accent_b"],  # B main E wall
		[Vector3(-7.68, 0.14, -5.0), Vector3(0.07, 0.28, 10.0), "accent_b"],   # mid W wall -> B
		[Vector3(-21.0, 0.14, -14.32), Vector3(10.0, 0.28, 0.07), "accent_b"], # B lobby N wall
	]:
		decor_box(decor, "Trim", t[0], t[1], mats[t[2]])

func _make_markers_zones_barriers() -> void:
	var mk := Node3D.new()
	mk.name = "Spawns"
	map_root.add_child(mk)
	var ax := [[-6.0, -27.5], [-3.0, -25.5], [0.0, -27.5], [3.0, -25.5], [6.0, -27.5]]
	for i in 5:
		marker(mk, "AttackerSpawn%d" % (i + 1), "spawn_attacker", ax[i][0], ax[i][1], false)
	var dx := [[-6.0, 27.5], [-3.0, 25.5], [0.0, 27.5], [3.0, 25.5], [6.0, 27.5]]
	for i in 5:
		marker(mk, "DefenderSpawn%d" % (i + 1), "spawn_defender", dx[i][0], dx[i][1], true)

	plant_zone(map_root, "PlantZoneA", "plant_zone_a", Vector3(24.5, 0, 16), mats["zone_a_fill"], mats["zone_frame"])
	plant_zone(map_root, "PlantZoneB", "plant_zone_b", Vector3(-24.0, 0, 16), mats["zone_b_fill"], mats["zone_frame"])

	var bar := Node3D.new()
	bar.name = "Barriers"
	map_root.add_child(bar)
	# Attackers own spawn + both lobbies pre-round
	buy_barrier(bar, "buy_barrier_attacker", Vector3(29.0, 1.5, -12.0), Vector3(8, 3, 0.4))   # A main entry
	buy_barrier(bar, "buy_barrier_attacker", Vector3(0.0, 1.5, -16.0), Vector3(6, 3, 0.4))    # mid top
	buy_barrier(bar, "buy_barrier_attacker", Vector3(-29.5, 1.5, -14.0), Vector3(7, 3, 0.4))  # B main entry
	# Defenders own sites + def link pre-round
	buy_barrier(bar, "buy_barrier_defender", Vector3(28.5, 1.5, 10.0), Vector3(5, 3, 0.4))    # A main door
	buy_barrier(bar, "buy_barrier_defender", Vector3(16.0, 1.5, 11.5), Vector3(0.4, 3, 3))    # A link door
	buy_barrier(bar, "buy_barrier_defender", Vector3(-1.0, 1.5, 8.0), Vector3(4, 3, 0.4))     # mid north door
	buy_barrier(bar, "buy_barrier_defender", Vector3(-17.5, 1.5, 10.0), Vector3(5, 3, 0.4))   # market door
	buy_barrier(bar, "buy_barrier_defender", Vector3(-30.5, 1.5, 10.0), Vector3(5, 3, 0.4))   # B main door

func _make_audio() -> void:
	var au := Node3D.new()
	au.name = "Ambience"
	map_root.add_child(au)
	# Positional loops from assets/audio/ambient (processed seamless OGGs,
	# loop flag set at import time — see docs/ASSETS.md section 8).
	ambient_audio(au, "FountainWater", Vector3(0, 1.2, -4), "res://assets/audio/ambient/amb_fountain_water.ogg", -4.0)
	ambient_audio(au, "MarketAmbience", Vector3(-6.2, 2.2, -9), "res://assets/audio/ambient/amb_plaza_wind_light.ogg", -6.0)
	ambient_audio(au, "GeneratorHumA", Vector3(24.5, 1.6, 17), "res://assets/audio/ambient/amb_generator_hum.ogg", -3.0)
	ambient_audio(au, "WindB", Vector3(-24, 3.0, 20), "res://assets/audio/ambient/amb_wind_soft.ogg", -6.0)
	# Quiet non-positional town bed under everything.
	var bed := AudioStreamPlayer.new()
	bed.name = "TownBed"
	bed.autoplay = true
	bed.volume_db = -18.0
	var bed_path := "res://assets/audio/ambient/amb_town_bed.ogg"
	if ResourceLoader.exists(bed_path):
		bed.stream = load(bed_path)
	au.add_child(bed)

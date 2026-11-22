extends Node3D
## Deterministic original suburban arena. All collision is built identically on each peer.
const P = preload("res://scripts/art/mesh_parts.gd")
var footprints: Array[Rect2] = []
var concrete := textured("Concrete034", "c0bdb0", .4)
var trim := P.material("e2dcc7")
var roof := textured("RoofingTiles013A", "667780", .5)
var wood := textured("WoodFloor043", "ab9474", .5)
var asphalt := textured("Concrete034", "414b50", .5)
var grass := textured("Ground054", "8d9b77", .3)
var foliage := P.material("526b59")

func textured(id: String, tint: String, uv_scale: float) -> StandardMaterial3D:
	var mat := P.material(tint)
	mat.albedo_texture = load("res://assets/textures/%s_1K-JPG_Color.jpg" % id)
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * uv_scale
	return mat

func block(pos: Vector3, dimensions: Vector3, mat: Material, collision := true, rot := Vector3.ZERO) -> Node3D:
	var mesh := P.box(self,pos,dimensions,mat,rot)
	if collision:
		var body := StaticBody3D.new()
		mesh.add_child(body)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = dimensions
		shape.shape = box
		body.add_child(shape)
	return mesh

func _ready() -> void:
	add_to_group("arena_map")
	block(Vector3(0,-.25,0),Vector3(180,.5,180),grass)
	block(Vector3(0,.01,0),Vector3(10,.08,66),asphalt)
	for x in [-6.0,6.0]:
		block(Vector3(x,.10,0),Vector3(2,.20,66),concrete)
	for z in range(-30,31,6):
		block(Vector3(0,.058,z),Vector3(.13,.01,2.7),trim,false)
	for x in [-5.0,5.0]:
		block(Vector3(x,.21,0),Vector3(.18,.15,66),trim)
	house(Vector3(-15,0,-8),textured("PaintedPlaster017","779b9b",.4),false)
	house(Vector3(15,0,8),textured("PaintedPlaster017","b29372",.4),true)
	# Outbuildings and garden cover create a connected perimeter route.
	for pos in [Vector3(-15,0,16),Vector3(15,0,-16)]:
		block(pos+Vector3(0,1.4,0),Vector3(6,2.8,4),wood)
		block(pos+Vector3(0,2.85,0),Vector3(6.5,.25,4.6),roof)
		footprints.append(Rect2(Vector2(pos.x-3,pos.z-2),Vector2(6,4)))
		for x in range(-2,3):
			block(pos+Vector3(x,1.2,-2.02),Vector3(.04,2.3,.05),trim,false)
	for pos in [Vector3(-2,0,-9),Vector3(2,0,10),Vector3(-13,0,-20)]:
		vehicle(pos, P.material("a5a58a",.45))
	for pos in [Vector3(-8,0,8),Vector3(8,0,-8),Vector3(-22,0,6),Vector3(22,0,-6)]:
		block(pos+Vector3(0,.6,0),Vector3(2.6,1.2,1.2),concrete)
		block(pos+Vector3(0,1.2,0),Vector3(2.8,.15,1.4),trim)
		P.capsule(self,pos+Vector3(0,1.45,0),.55,1.1,P.material("4e6b4b"),Vector3(0,0,PI/2))
	# Low perimeter fences and distant scenery replace the skybox/wall seam.
	for x in [-29.0,29.0]:
		block(Vector3(x,1,0),Vector3(.2,2,64),wood)
		for z in range(-32,33,4):
			block(Vector3(x,1.15,z),Vector3(.3,2.3,.3),trim)
	for z in [-32.0,32.0]:
		block(Vector3(0,1,z),Vector3(58,2,.2),wood)
	for i in range(32):
		var angle := i*TAU/32.0
		var pos := Vector3(cos(angle)*(42+i%3*7),0,sin(angle)*(46+i%4*6))
		tree(pos,4.5+i%4)
	for i in range(12):
		var pos := Vector3(-66+i*12,0, -57 if i%2==0 else 57)
		block(pos+Vector3(0,2.5,0),Vector3(8,5,7),concrete,false)
		block(pos+Vector3(0,5.2,0),Vector3(9,.5,8),roof,false)
	# Eight covered distributed spawns, oriented toward the arena.
	for i in range(8):
		var points := [Vector3(-24,.2,-24),Vector3(24,.2,24),Vector3(-24,.2,24),Vector3(24,.2,-24),Vector3(-13,.2,26),Vector3(13,.2,-26),Vector3(-25,.2,0),Vector3(25,.2,0)]
		var marker := Marker3D.new()
		marker.position = points[i]
		marker.rotation.y = atan2(marker.position.x,marker.position.z)
		marker.add_to_group("spawn_ffa")
		marker.add_to_group("spawn_attacker" if i%2==0 else "spawn_defender")
		add_child(marker)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var atmosphere := PanoramaSkyMaterial.new()
	atmosphere.panorama = load("res://assets/sky/kloofendal_48d_partly_cloudy_puresky_2k.hdr")
	sky.sky_material = atmosphere
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = .4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color("bccbc6")
	e.fog_density = .0015
	e.fog_sky_affect = .08
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_color = Color("fff1d4")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	add_child(sun)
	P.merge_static(self)

func house(center: Vector3, paint: Material, mirror: bool) -> void:
	footprints.append(Rect2(Vector2(center.x-5,center.z-6),Vector2(10,12)))
	block(center+Vector3(0,.10,0),Vector3(10,.2,12),concrete)
	# Front and rear doors stay open; side windows have actual openings.
	for z in [-6.0,6.0]:
		for x in [-3.2,3.2]:
			block(center+Vector3(x,1.65,z),Vector3(3.6,3.3,.25),paint)
		block(center+Vector3(0,2.95,z),Vector3(2.8,.7,.25),paint)
		for x in [-1.45,1.45]:
			block(center+Vector3(x,1.35,z),Vector3(.12,2.7,.35),trim)
	for x in [-5.0,5.0]:
		block(center+Vector3(x,.55,0),Vector3(.25,1.1,12),paint)
		block(center+Vector3(x,2.85,0),Vector3(.25,.9,12),paint)
		for z in [-5.0,0.0,5.0]:
			block(center+Vector3(x,1.7,z),Vector3(.25,1.2,2),paint)
		for z in [-2.5,2.5]:
			block(center+Vector3(x,1.10,z),Vector3(.42,.10,3),trim)
	# Upper terrace over half the house, stair access and railings.
	block(center+Vector3(0,3.35,2.7),Vector3(10,.22,6.6),concrete)
	for x in [-5.0,5.0]:
		block(center+Vector3(x,3.9,2.7),Vector3(.12,1.0,6.6),trim)
	block(center+Vector3(0,3.9,6),Vector3(10,1,.12),trim)
	for i in range(15):
		var height := (i+1)*.22
		block(center+Vector3(-3.8,height/2,-5.4+i*.38),Vector3(1.7,height,.38),concrete)
	var ramp := block(center+Vector3(-3.8,1.66,-2.65),Vector3(1.7,.06,6.60),concrete,true,Vector3(-atan(.22/.38),0,0))
	ramp.visible = false
	ramp.set_meta("collision_only",true)
	# Sloping roof over the front room; keeps terrace and stairs clear.
	for side in [-1,1]:
		block(center+Vector3(side*2.55,4.15,-3.5),Vector3(5.5,.18,4.6),roof,true,Vector3(0,0,-side*.25))
	for z in [-6.3,6.3]:
		block(center+Vector3(0,.12,z+signf(z)),Vector3(3,.24,2),concrete)
	# Interior fittings and cover.
	block(center+Vector3(3, .75,2),Vector3(2,1.5,.8),wood)
	block(center+Vector3(1, .4,4.8),Vector3(2.5,.8,.9),paint)
	var label := Label3D.new()
	label.text = "07 / B" if mirror else "07 / A"
	label.font_size = 64
	label.pixel_size = .008
	label.position = center+Vector3(3,2,-6.16)
	label.modulate = Color("f0e6be")
	add_child(label)

func tree(pos: Vector3, height: float) -> void:
	P.cylinder(self,pos+Vector3.UP*height*.35,.18,height*.7,wood)
	for i in range(3):
		P.cylinder(self,pos+Vector3.UP*(height*.5+i*.9),1.7-i*.3,2.8,foliage,Vector3.ZERO,0)

func vehicle(pos: Vector3, paint: Material) -> void:
	block(pos+Vector3(0,.75,0),Vector3(1.9,.6,4.2),paint)
	block(pos+Vector3(0,1.35,.2),Vector3(1.7,.7,2.1),paint)
	var glass := P.material("344c59",.6,.2)
	block(pos+Vector3(0,1.43,-.87),Vector3(1.5,.5,.04),glass,false)
	block(pos+Vector3(0,1.43,1.27),Vector3(1.5,.5,.04),glass,false)
	for side in [-1,1]:
		block(pos+Vector3(side*.86,1.43,.2),Vector3(.03,.5,1.8),glass,false)
		for z in [-1.4,1.4]:
			P.cylinder(self,pos+Vector3(side*.94,.45,z),.39,.25,P.material("20282a"),Vector3(0,0,PI/2))
		block(pos+Vector3(side*.66,.79,-2.12),Vector3(.4,.18,.05),trim,false)
	block(pos+Vector3(0,.52,-2.13),Vector3(1.8,.15,.1),roof)

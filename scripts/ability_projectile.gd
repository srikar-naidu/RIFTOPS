class_name AbilityProjectile
extends Node3D
## Thrown ability projectile. Spawned on EVERY peer with identical params and
## simulated deterministically (no randomness), so visuals agree; only the
## server's instance is authoritative and reports back to the EffectsManager,
## which then broadcasts the resulting effect + removes all instances.

const GRAV := 14.0

var id := 0
var kind := ""
var vel := Vector3.ZERO
var fuse_left := 10.0
var authoritative := false
var manager: Node = null

var _done := false
var _spin := 0.0


static func create(p_id: int, params: Dictionary, p_manager: Node, p_authoritative: bool) -> AbilityProjectile:
	var p := AbilityProjectile.new()
	p.id = p_id
	p.kind = String(params.get("kind", ""))
	p.position = params.get("pos", Vector3.ZERO)
	p.vel = params.get("vel", Vector3.ZERO)
	p.fuse_left = float(params.get("fuse", 10.0))
	p.manager = p_manager
	p.authoritative = p_authoritative
	p._build_visual(String(params.get("model", "")))
	return p


func _build_visual(model_path: String) -> void:
	var loaded := false
	if model_path != "" and ResourceLoader.exists(model_path):
		var ps: PackedScene = load(model_path) as PackedScene
		if ps != null:
			var inst: Node3D = ps.instantiate() as Node3D
			if inst != null:
				inst.scale = Vector3.ONE * 0.5
				add_child(inst)
				loaded = true
	if not loaded:
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.09
		mesh.height = 0.18
		mesh.material = Fx.unshaded_mat(Color(0.85, 0.85, 0.9))
		mi.mesh = mesh
		add_child(mi)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_spin += delta * 9.0
	rotation = Vector3(_spin, _spin * 0.7, 0)
	vel.y -= GRAV * delta
	var step := vel * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position + hit.normal * 0.08
		_finish()
		return
	global_position += step
	fuse_left -= delta
	if fuse_left <= 0.0:
		_finish()


func _finish() -> void:
	_done = true
	set_physics_process(false)
	if authoritative and manager != null:
		manager.server_projectile_done(id, kind, global_position)
	# Non-authoritative instances idle at rest until cl_end removes them.

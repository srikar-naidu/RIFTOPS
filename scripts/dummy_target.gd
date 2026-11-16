class_name DummyTarget
extends Node3D
## Server-side shootable target used by the automated two-instance test
## (--spawn-dummy). Exposes the same take_damage_server contract as Player.
## Not replicated — it only needs to exist where the raycasts run.

const MAX_HEALTH := 100

var health := MAX_HEALTH
var alive := true
var team: int = GameState.Team.DEFENDERS
var player_name := "Dummy"


func _ready() -> void:
	add_to_group("dummy_targets")
	_add_hitbox(HitboxRegion.Region.HEAD, _sphere(0.14), Vector3(0, 1.56, 0))
	_add_hitbox(HitboxRegion.Region.BODY, _capsule(0.26, 0.85), Vector3(0, 1.12, 0))
	_add_hitbox(HitboxRegion.Region.LEGS, _box(Vector3(0.42, 0.8, 0.34)), Vector3(0, 0.42, 0))
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.32
	mesh.height = 1.75
	mesh.material = Fx.unshaded_mat(Color(0.9, 0.6, 0.2))
	mi.mesh = mesh
	mi.position = Vector3(0, 0.875, 0)
	add_child(mi)


func _add_hitbox(region: int, shape: Shape3D, pos: Vector3) -> void:
	var hb := HitboxRegion.new()
	hb.region = region as HitboxRegion.Region
	hb.receiver = self
	hb.collision_layer = 4
	hb.collision_mask = 0
	hb.monitoring = false
	hb.position = pos
	var cs := CollisionShape3D.new()
	cs.shape = shape
	hb.add_child(cs)
	add_child(hb)


func _sphere(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s


func _capsule(r: float, h: float) -> CapsuleShape3D:
	var s := CapsuleShape3D.new()
	s.radius = r
	s.height = h
	return s


func _box(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


func take_damage_server(amount: int, region: int, attacker: Node, weapon: WeaponData) -> Dictionary:
	if not alive:
		return {"applied": 0, "killed": false}
	var attacker_team := int(attacker.get("team")) if attacker != null and attacker.get("team") != null else 0
	if attacker_team == team:
		return {"applied": 0, "killed": false}
	health = maxi(health - amount, 0)
	var killed := health <= 0
	if killed:
		alive = false
		var killer_name := String(attacker.get("player_name")) if attacker != null else "World"
		GameState.server_report_kill(
			killer_name, attacker_team, player_name, team,
			String(weapon.id), region == HitboxRegion.Region.HEAD)
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			health = MAX_HEALTH
			alive = true)
	return {"applied": amount, "killed": killed}

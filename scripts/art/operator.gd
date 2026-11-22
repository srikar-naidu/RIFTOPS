extends Node3D
## Skinned CC0 Quaternius hero, with original palette and procedural bone posing.
## Geometry is artist-authored; this adapter never changes gameplay collision.
var model: Node3D
var rig: Skeleton3D
var clock := 0.0
var player: Node3D
var rest_rotations: Dictionary = {}
var gun: Node3D

func _ready() -> void:
	model = preload("res://assets/characters/modular/Punk.glb").instantiate()
	add_child(model)
	var bounds := WeaponView.merged_aabb(model)
	model.scale *= 1.78 / bounds.size.y
	model.position.y = -bounds.position.y * model.scale.y
	# Source faces +Z. The player and viewmodels use -Z.
	model.rotation.y = PI
	rig = model.find_child("Skeleton3D",true,false) as Skeleton3D
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var material := source.duplicate() as StandardMaterial3D
			material.roughness = .72
			match source.resource_name:
				"Red": material.albedo_color = Color("f5a13c")
				"Red_Dark": material.albedo_color = Color("147b91")
				"LightBlue": material.albedo_color = Color("47d9df")
				"Black": material.albedo_color = Color("233447")
			material.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
			mesh.set_surface_override_material(surface,material)
	player = get_parent().get_parent() as Node3D
	if not player is CharacterBody3D:
		player = null
	for i in rig.get_bone_count():
		rest_rotations[i] = rig.get_bone_pose_rotation(i)
	gun = preload("res://assets/weapons/rx24.tscn").instantiate()
	add_child(gun)
	gun.scale = Vector3.ONE*.8
	gun.visible = player != null
	_pose(0)

func _point_bone(bone_name: String, child_name: String, direction: Vector3) -> void:
	var index := rig.find_bone(bone_name)
	var child := rig.find_bone(child_name)
	if index < 0 or child < 0:
		return
	var current := rig.get_bone_global_pose(index)
	var next := rig.get_bone_global_pose(child)
	var from := (rig.global_basis * (next.origin-current.origin)).normalized()
	var to := (global_basis * direction).normalized()
	var change := Basis(Quaternion(from,to))
	var basis_world := (rig.global_basis * current.basis).orthonormalized()
	var local_change := basis_world.inverse()*change*basis_world
	rig.set_bone_pose_rotation(index, rig.get_bone_pose_rotation(index)*local_change.get_rotation_quaternion())

func _pose(speed: float) -> void:
	for index: int in rest_rotations:
		rig.set_bone_pose_rotation(index,rest_rotations[index])
	var swing := sin(clock*9)*minf(speed*.09,.5)
	_point_bone("UpperArm.L","LowerArm.L", Vector3(.15,-.8,-.35))
	_point_bone("UpperArm.R","LowerArm.R", Vector3(-.12,-.8,-.25))
	_point_bone("LowerArm.L","Hand.L",Vector3(-.25,-.2,-.8))
	_point_bone("LowerArm.R","Hand.R",Vector3(.2,-.15,-.8))
	_point_bone("Hand.R","Middle2.R",Vector3(0,-.65,-.4))
	_point_bone("Hand.L","Middle2.L",Vector3(0,-.2,-.8))
	# Bend each authored finger chain, retaining the sculpted hand mesh.
	for side in ["L","R"]:
		for finger in ["Index","Middle","Ring","Pinky"]:
			for joint in [2,3,4]:
				var index := rig.find_bone("%s%d.%s" % [finger,joint,side])
				if index >= 0:
					rig.set_bone_pose_rotation(index,rest_rotations[index]*Quaternion(Vector3.RIGHT,-.35))
	if player == null:
		_point_bone("UpperArm.L","LowerArm.L",Vector3(.18,-1,.03))
		_point_bone("UpperArm.R","LowerArm.R",Vector3(-.15,-1,.04))
		_point_bone("LowerArm.L","Hand.L",Vector3(-.05,-1,-.06))
		_point_bone("LowerArm.R","Hand.R",Vector3(.04,-1,-.06))
		_point_bone("Hand.L","Middle2.L",Vector3(0,-1,.04))
		_point_bone("Hand.R","Middle2.R",Vector3(0,-1,.04))
	_point_bone("UpperLeg.L","LowerLeg.L",Vector3(.03,-1,swing))
	_point_bone("UpperLeg.R","LowerLeg.R",Vector3(-.03,-1,-swing))
	var hand := rig.find_bone("Hand.R")
	var hand_position := rig.to_global(rig.get_bone_global_pose(hand).origin)
	gun.global_position = hand_position + global_basis*Vector3(0,.045,-.08)
	gun.global_basis = global_basis.orthonormalized()*Basis(Vector3.UP,-.12)*.8
	model.position.y = sin(clock*2.0)*.007

func _process(delta: float) -> void:
	clock += delta
	var speed := float(player.observed_velocity.length()) if is_instance_valid(player) else 0.0
	_pose(speed)

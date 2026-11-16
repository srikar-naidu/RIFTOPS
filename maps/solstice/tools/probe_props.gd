# Prints the combined AABB of candidate GLTF props so build_map.gd can use
# correct scales and collider sizes. Run:
#   Godot --headless --path . --script res://maps/solstice/tools/probe_props.gd
extends SceneTree

const CANDIDATES := [
	"res://assets/props/fantasy_props/Barrel.gltf",
	"res://assets/props/fantasy_props/Crate_Wooden.gltf",
	"res://assets/props/fantasy_props/Crate_Metal.gltf",
	"res://assets/props/fantasy_props/FarmCrate_Empty.gltf",
	"res://assets/props/fantasy_props/Stall_Empty.gltf",
	"res://assets/props/fantasy_props/Stall_Cart_Empty.gltf",
	"res://assets/props/fantasy_props/Bench.gltf",
	"res://assets/props/fantasy_props/Table_Large.gltf",
	"res://assets/props/fantasy_props/Banner_1.gltf",
	"res://assets/props/fantasy_props/Banner_2.gltf",
	"res://assets/props/fantasy_props/Bag.gltf",
	"res://assets/props/fantasy_props/Chest_Wood.gltf",
	"res://assets/props/fantasy_props/Bucket_Wooden_1.gltf",
	"res://assets/props/fantasy_props/Vase_2.gltf",
	"res://assets/props/medieval_kit/Overhang_Plaster_Long.gltf",
	"res://assets/props/medieval_kit/Overhang_Plaster_Short.gltf",
	"res://assets/props/medieval_kit/Roof_Support2.gltf",
]

func _init() -> void:
	for path in CANDIDATES:
		if not ResourceLoader.exists(path):
			print("MISSING  %s" % path)
			continue
		var ps: PackedScene = load(path)
		if ps == null:
			print("LOADFAIL %s" % path)
			continue
		var inst := ps.instantiate()
		var aabb := _combined_aabb(inst)
		print("OK %-58s size=(%.2f, %.2f, %.2f) origin_min=(%.2f, %.2f, %.2f)" % [
			path.get_file(), aabb.size.x, aabb.size.y, aabb.size.z,
			aabb.position.x, aabb.position.y, aabb.position.z])
		inst.free()
	quit(0)

func _combined_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			var xf: Transform3D = _global_xf(n, node)
			var ab: AABB = xf * n.mesh.get_aabb()
			if first:
				result = ab
				first = false
			else:
				result = result.merge(ab)
		for c in n.get_children():
			stack.push_back(c)
	return result

func _global_xf(n: Node3D, stop: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != stop:
		if cur is Node3D:
			xf = cur.transform * xf
		cur = cur.get_parent()
	return xf

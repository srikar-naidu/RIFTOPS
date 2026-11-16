# Canonical MAP CONTRACT check for Solstice (see docs/CONVENTIONS.md).
# Run:  Godot --headless --path . --script res://maps/solstice/tools/validate_map.gd
# Prints PASS/FAIL lines and exits 0 only if every check passes.
extends SceneTree

const SCENE := "res://maps/solstice/solstice.tscn"

var failures := 0

func check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("PASS  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])
	else:
		failures += 1
		print("FAIL  %s%s" % [label, ("  (%s)" % detail) if detail != "" else ""])

func _init() -> void:
	if not ResourceLoader.exists(SCENE):
		print("FAIL  scene file missing: %s" % SCENE)
		quit(1)
		return
	var ps: PackedScene = load(SCENE)
	check(ps != null, "scene loads")
	if ps == null:
		quit(1)
		return
	var map: Node = ps.instantiate()

	var nodes: Array[Node] = []
	_collect(map, nodes)

	# ---- groups ----
	var spawn_a := _in_group(nodes, "spawn_attacker")
	var spawn_d := _in_group(nodes, "spawn_defender")
	check(spawn_a.size() == 5, "spawn_attacker count == 5", str(spawn_a.size()))
	check(spawn_d.size() == 5, "spawn_defender count == 5", str(spawn_d.size()))
	check(_all_type(spawn_a, "Marker3D"), "attacker spawns are Marker3D")
	check(_all_type(spawn_d, "Marker3D"), "defender spawns are Marker3D")

	for m in spawn_a:
		check(absf(m.position.y) < 0.01, "attacker spawn on floor (y=0)", m.name)
		check((-m.transform.basis.z).z > 0.9, "attacker spawn faces enemy (+Z)", m.name)
	for m in spawn_d:
		check(absf(m.position.y) < 0.01, "defender spawn on floor (y=0)", m.name)
		check((-m.transform.basis.z).z < -0.9, "defender spawn faces enemy (-Z)", m.name)

	if spawn_a.size() > 0 and spawn_d.size() > 0:
		var ca := Vector3.ZERO
		for m in spawn_a: ca += m.position
		ca /= spawn_a.size()
		var cd := Vector3.ZERO
		for m in spawn_d: cd += m.position
		cd /= spawn_d.size()
		var dist := ca.distance_to(cd)
		check(dist > 40.0, "team spawn centroids > 40 m apart", "%.1f m" % dist)

	# ---- plant zones ----
	for info in [["plant_zone_a", "A"], ["plant_zone_b", "B"]]:
		var zs := _in_group(nodes, info[0])
		check(zs.size() == 1, "%s count == 1" % info[0], str(zs.size()))
		for z in zs:
			check(z is Area3D, "%s is Area3D" % info[0], z.name)
			if z is Area3D:
				check(z.collision_layer == 16, "zone %s on trigger layer 5 only" % info[1], "layer=%d" % z.collision_layer)
				check((z.collision_mask & 2) != 0, "zone %s masks players (bit 2)" % info[1], "mask=%d" % z.collision_mask)
				var shp := _first_shape(z)
				check(shp != null, "zone %s has a CollisionShape3D" % info[1])
				if shp != null and shp.shape is BoxShape3D:
					var s: Vector3 = shp.shape.size
					check(s.x >= 5.9 and s.z >= 5.9 and s.y >= 1.9, "zone %s ~6x6 m, 2 m tall" % info[1], "%v" % s)

	# ---- buy barriers ----
	for grp in ["buy_barrier_attacker", "buy_barrier_defender"]:
		var bars := _in_group(nodes, grp)
		check(bars.size() >= 1, "%s present" % grp, "%d barriers" % bars.size())
		for b in bars:
			check(b is StaticBody3D, "%s is StaticBody3D" % grp, b.name)
			if b is StaticBody3D:
				check((b.collision_layer & 1) != 0, "barrier solid on layer 1", b.name)
				check(_first_shape(b) != null, "barrier has collision shape", b.name)

	# ---- world geometry: no visible mesh without collision (best effort) ----
	var mesh_count := 0
	var naked: Array[String] = []
	var unique_meshes := {}
	var unique_mats := {}
	for n in nodes:
		if n is MeshInstance3D and n.mesh != null:
			mesh_count += 1
			unique_meshes[n.mesh.get_instance_id()] = true
			for i in n.mesh.get_surface_count():
				var mt: Material = n.get_active_material(i)
				if mt != null:
					unique_mats[mt.get_instance_id()] = true
			if _is_decor(n):
				continue
			var body := _body_ancestor(n)
			if body == null or (body.collision_layer & 1) == 0 or _first_shape(body) == null:
				naked.append(str(map.get_path_to(n)))
	check(naked.is_empty(), "all world meshes have layer-1 collision", "%d naked: %s" % [naked.size(), ", ".join(naked.slice(0, 5))])

	# ---- lighting / audio readiness ----
	check(_count_type(nodes, "DirectionalLight3D") == 1, "exactly one sun")
	for n in nodes:
		if n is DirectionalLight3D:
			check(n.shadow_enabled, "sun casts shadows")
	check(_count_type(nodes, "WorldEnvironment") == 1, "WorldEnvironment present")
	check(_count_type(nodes, "LightmapGI") == 1, "LightmapGI present (bake-ready)")
	check(_in_group(nodes, "ambient_audio").size() >= 3, "ambient audio emitters placed")

	# ---- perf report ----
	print("INFO  MeshInstance3D: %d | unique meshes: %d | unique materials: %d | StaticBody3D: %d | nodes: %d" % [
		mesh_count, unique_meshes.size(), unique_mats.size(), _count_type(nodes, "StaticBody3D"), nodes.size()])

	map.free()
	if failures == 0:
		print("VALIDATION PASSED")
		quit(0)
	else:
		print("VALIDATION FAILED: %d failure(s)" % failures)
		quit(1)

func _collect(n: Node, out: Array[Node]) -> void:
	out.append(n)
	for c in n.get_children():
		_collect(c, out)

func _in_group(nodes: Array[Node], grp: String) -> Array[Node]:
	var out: Array[Node] = []
	for n in nodes:
		if n.is_in_group(grp):
			out.append(n)
	return out

func _all_type(nodes: Array[Node], cls: String) -> bool:
	for n in nodes:
		if not n.is_class(cls):
			return false
	return true

func _count_type(nodes: Array[Node], cls: String) -> int:
	var c := 0
	for n in nodes:
		if n.is_class(cls):
			c += 1
	return c

func _first_shape(body: Node) -> CollisionShape3D:
	for c in body.get_children():
		if c is CollisionShape3D and c.shape != null and not c.disabled:
			return c
	return null

func _is_decor(n: Node) -> bool:
	var cur: Node = n
	while cur != null:
		if cur.is_in_group("decor_nocollide") or cur is Area3D:
			return true
		cur = cur.get_parent()
	return false

func _body_ancestor(n: Node) -> StaticBody3D:
	var cur: Node = n.get_parent()
	while cur != null:
		if cur is StaticBody3D:
			return cur
		cur = cur.get_parent()
	return null

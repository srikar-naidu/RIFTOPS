extends RefCounted
## Small shared geometry vocabulary for original RIFTOPS art.
static func material(hex: String, metal := 0.0, rough := 0.65) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.metallic = metal
	m.roughness = rough
	return m

static func part(root: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	n.rotation = rot
	root.add_child(n)
	return n

static func box(root: Node3D, pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return part(root, m, pos, mat, rot)

static func cylinder(root: Node3D, pos: Vector3, radius: float, height: float, mat: Material, rot := Vector3.ZERO, top := -1.0) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius if top < 0 else top
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 12
	return part(root, m, pos, mat, rot)

static func capsule(root: Node3D, pos: Vector3, radius: float, height: float, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 4
	return part(root, m, pos, mat, rot)

static func merge_static(root: Node3D) -> void:
	# One surface per shared material. Preserve each collision transform.
	var batches: Dictionary = {}
	for child: Node in root.get_children():
		if not child is MeshInstance3D:
			continue
		var mesh := child as MeshInstance3D
		var mat := mesh.material_override
		if not batches.has(mat):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surface.set_material(mat)
			batches[mat] = surface
		var source: ArrayMesh = mesh.mesh if mesh.mesh is ArrayMesh else ArrayMesh.new()
		if not mesh.mesh is ArrayMesh:
			source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.mesh.surface_get_arrays(0))
		batches[mat].append_from(source, 0, mesh.transform)
		for attachment: Node in mesh.get_children():
			var transform_value: Transform3D = mesh.transform * attachment.transform
			attachment.reparent(root, false)
			attachment.transform = transform_value
		mesh.visible = false
		mesh.queue_free()
	for mat: Material in batches:
		var instance := MeshInstance3D.new()
		instance.mesh = batches[mat].commit()
		root.add_child(instance)

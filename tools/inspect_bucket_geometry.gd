extends SceneTree

func _initialize() -> void:
	var model = load("res://assets/models/GLB format/end-square.glb").instantiate()
	var report: Array = []
	inspect(model, Transform3D.IDENTITY, report)
	var file = FileAccess.open("res://docs/bucket_geometry.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	model.free()
	quit()

func inspect(node: Node, parent_transform: Transform3D, report: Array) -> void:
	var accumulated = parent_transform
	if node is Node3D: accumulated *= node.transform
	if node is MeshInstance3D:
		var hits: Array = []
		var faces = node.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			var hit = Geometry3D.segment_intersects_triangle(Vector3(0, 2, 0), Vector3(0, -1, 0), accumulated * faces[index], accumulated * faces[index + 1], accumulated * faces[index + 2])
			if hit != null and not hits.has(hit.y): hits.append(hit.y)
		report.append({"node": String(node.name), "transform": str(accumulated), "bounds": str(accumulated * node.mesh.get_aabb()), "triangles": faces.size() / 3, "center_surface_heights": hits})
	for child in node.get_children(): inspect(child, accumulated, report)

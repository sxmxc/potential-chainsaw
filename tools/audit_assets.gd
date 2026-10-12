extends SceneTree
var report: Dictionary = {}
func _initialize() -> void:
	for file in DirAccess.get_files_at("res://assets/models/GLB format"):
		if not file.ends_with(".glb"): continue
		var node = load("res://assets/models/GLB format/" + file).instantiate()
		var points: Array[Vector3] = []
		collect(node, Transform3D.IDENTITY, points)
		var bounds = AABB(points[0], Vector3.ZERO)
		for p in points: bounds = bounds.expand(p)
		var edges = {}
		for axis in [0, 2]:
			for side in [0, 1]:
				var value = bounds.position[axis] if side == 0 else bounds.end[axis]
				var pts = []
				for p in points:
					if abs(p[axis] - value) < 0.002: pts.append([snappedf(p.x,0.001),snappedf(p.y,0.001),snappedf(p.z,0.001)])
				edges[str(axis)+":"+str(side)] = pts
		report[file.get_basename()] = {"min": [bounds.position.x,bounds.position.y,bounds.position.z],"size":[bounds.size.x,bounds.size.y,bounds.size.z],"edges": edges,"vertices":points.size()}
		node.free()
	var out = FileAccess.open("res://docs/asset_geometry.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"\t"))
	quit()
func collect(node: Node, parent: Transform3D, points: Array[Vector3]) -> void:
	var t = parent
	if node is Node3D: t = parent * node.transform
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			for p in node.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]: points.append(t * p)
	for child in node.get_children(): collect(child,t,points)

extends SceneTree
func _initialize() -> void:
	var report = JSON.parse_string(FileAccess.get_file_as_string("res://docs/asset_geometry.json"))
	for id in report:
		var root = load("res://assets/models/GLB format/"+id+".glb").instantiate()
		var planes: Dictionary = {}
		collect(root,Transform3D.IDENTITY,planes)
		var connectors: Array = []
		for key in planes:
			var pts: Array = planes[key]
			var axis = int(key.split(":")[0])
			var cross_axis = 2 if axis == 0 else 0
			for p in pts:
				for q in pts:
					var width = abs(p[cross_axis]-q[cross_axis])
					if abs(p.y-q.y) > 0.001 or (abs(width-0.2)>0.005 and abs(width-0.4)>0.005): continue
					var center = (p+q)*0.5
					var half = 0.35 if width < 0.3 else 0.7
					var left = false
					var right = false
					for r in pts:
						if abs(r.y-center.y-0.25)<0.005:
							if abs(r[cross_axis]-center[cross_axis]+half)<0.005: left=true
							if abs(r[cross_axis]-center[cross_axis]-half)<0.005: right=true
					if not left or not right: continue
					var exists = false
					for c in connectors:
						if Vector3(c.p[0],c.p[1],c.p[2]).distance_to(center)<0.02: exists=true
					if exists: continue
					var direction = Vector3.ZERO
					direction[axis] = float(key.split(":")[2])
					connectors.append({"p":[center.x,center.y,center.z],"n":[direction.x,direction.y,direction.z],"type":"wide" if width>0.3 else "standard"})
		report[id]["connectors"] = connectors
		root.free()
	var out=FileAccess.open("res://docs/asset_geometry.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"\t"))
	quit()
func collect(node: Node,parent: Transform3D,planes: Dictionary) -> void:
	var t=parent
	if node is Node3D: t=parent*node.transform
	if node is MeshInstance3D:
		for s in node.mesh.get_surface_count():
			var a=node.mesh.surface_get_arrays(s)
			var vs=a[Mesh.ARRAY_VERTEX]
			var ns=a[Mesh.ARRAY_NORMAL]
			for i in vs.size():
				var p: Vector3=t*vs[i]
				var n: Vector3=t.basis*ns[i]
				for axis in [0,2]:
					if abs(n[axis])<0.999: continue
					var key=str(axis)+":"+str(snappedf(p[axis],0.001))+":"+str(signf(n[axis]))
					if not planes.has(key): planes[key]=[]
					planes[key].append(p)
	for child in node.get_children(): collect(child,t,planes)

extends SceneTree

const Definition = preload("res://scripts/construction/piece_definition.gd")
const Connector = preload("res://scripts/construction/connector.gd")
var audit: Dictionary

func _initialize() -> void:
	audit = JSON.parse_string(FileAccess.get_file_as_string("res://docs/asset_geometry.json"))
	for id in audit:
		if id.begins_with("marble"): continue
		var def = Definition.new()
		def.id = StringName(id)
		def.display_name = id.replace("-", " ").capitalize()
		def.model = load("res://assets/models/GLB format/" + id + ".glb")
		var data: Dictionary = audit[id]
		def.bounds = AABB(vector(data.min), vector(data.size))
		def.category = category(id)
		def.behavior = "static"
		if id.begins_with("support"): def.behavior = "support"
		elif id.begins_with("fan"): def.behavior = "rotor"
		elif id.begins_with("tree") or id.begins_with("banner") or id == "tunnel": def.behavior = "decoration"
		def.description = description(def)
		for c in data.connectors:
			var connector = Connector.new()
			connector.position = vector(c.p)
			connector.outward = vector(c.n)
			connector.profile = StringName(c.type)
			def.connectors.append(connector)
		var model = def.model.instantiate()
		var faces: Array[Vector3] = []
		collect(model, Transform3D.IDENTITY, faces, def.behavior == "rotor")
		def.surface_cells = interior_samples(faces, def.bounds)
		model.free()
		ResourceSaver.save(def, "res://resources/pieces/" + id + ".tres")
		print("Catalog: ", id, " / ", def.connectors.size(), " ports / ",def.surface_cells.size()," interior samples")
	for behavior in ["start", "finish"]:
		var def = load("res://resources/pieces/straight.tres").duplicate(true) if behavior == "start" else load("res://resources/pieces/end-square.tres").duplicate(true)
		def.id = StringName("sandbox-" + behavior)
		def.display_name = "Marble release" if behavior == "start" else "Finish catcher"
		def.category = "Start & finish"
		def.behavior = behavior
		def.description = "Release a real rolling marble. The arrow points in the launch direction; adjust speed in the inspector." if behavior == "start" else "A collection cup with an arrival sensor. The glowing gold ring marks the destination."
		ResourceSaver.save(def, "res://resources/pieces/sandbox-"+behavior+".tres")
	quit()

func vector(data: Array) -> Vector3:
	return Vector3(data[0],data[1],data[2])

func category(id: String) -> String:
	if id.begins_with("support"): return "Supports"
	if id.begins_with("fan"): return "Mechanisms"
	if id.begins_with("tree") or id.begins_with("banner") or id == "tunnel": return "Scenery"
	if id.begins_with("slant") or id.begins_with("ramp") or id.begins_with("helix"): return "Elevation"
	if id.begins_with("split") or id == "cross" or id.begins_with("funnel"): return "Junctions & transitions"
	if id.begins_with("end"): return "Ends & drops"
	if id.begins_with("bump") or id.begins_with("wave"): return "Waves & bumps"
	if id.begins_with("straight"): return "Straight tracks"
	return "Curves & turns"

func description(def: PieceDefinition) -> String:
	var text = "%s · %.2f × %.2f m footprint · %.2f m tall." % [def.category,def.bounds.size.x,def.bounds.size.z,def.bounds.size.y]
	if def.behavior == "rotor": text += " Rotating obstacle; operates during simulation. Place on a channel or as a freestanding obstacle."
	elif def.behavior == "decoration": text += " Physical scenery. Tunnel arches can surround an existing channel."
	elif def.behavior == "support": text += " Stack structural sections beneath raised tracks. Supports are optional in free build."
	else: text += " Mesh-matched collision. Disconnected sections are allowed."
	return text

func collect(node: Node, parent: Transform3D, faces: Array[Vector3], skip_fan: bool) -> void:
	var t = parent
	if node is Node3D: t = parent * node.transform
	if node is MeshInstance3D and not (skip_fan and node.name == "fan"):
		for point in node.mesh.get_faces(): faces.append(t * point)
	for child in node.get_children(): collect(child,t,faces,skip_fan)

func interior_samples(faces: Array[Vector3], bounds: AABB) -> PackedVector3Array:
	var cells = PackedVector3Array()
	# Cast along X through each Y/Z slice. Parity recovers solid interiors rather than bounding boxes.
	for yi in range(floori(bounds.position.y*10), ceili(bounds.end.y*10)):
		var y = yi*0.1+0.05
		for zi in range(floori(bounds.position.z*10), ceili(bounds.end.z*10)):
			var z = zi*0.1+0.05
			var hits: Array[float] = []
			for i in range(0,faces.size(),3):
				var a = faces[i]
				var b = faces[i+1]
				var c = faces[i+2]
				var den = (b.z-c.z)*(a.y-c.y)+(c.y-b.y)*(a.z-c.z)
				if abs(den)<0.000001: continue
				var u = ((b.z-c.z)*(y-c.y)+(c.y-b.y)*(z-c.z))/den
				var v = ((c.z-a.z)*(y-c.y)+(a.y-c.y)*(z-c.z))/den
				if u<0 or v<0 or u+v>1: continue
				hits.append(a.x*u+b.x*v+c.x*(1-u-v))
			hits.sort()
			var unique: Array[float] = []
			for hit in hits:
				if unique.is_empty() or abs(hit-unique[-1])>0.001: unique.append(hit)
			for i in range(0,unique.size()-1,2):
				for xi in range(floori(unique[i]*10),ceili(unique[i+1]*10)):
					var x=xi*0.1+0.05
					if x>unique[i]+0.005 and x<unique[i+1]-0.005: cells.append(Vector3(x,y,z))
	return cells

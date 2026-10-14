class_name PuzzleEnvironment
extends RefCounted

# Scenery placements refer only to authoring pieces in the shared registry.
static func get_asset(asset: String) -> PieceDefinition:
	var definition := PieceCatalog.REGISTRY.load_entry(StringName("environment:" + asset)) as PieceDefinition
	return definition if definition and definition.authoring_only and definition.model else null

static func construction(data: Dictionary) -> Array:
	var result: Array = []
	for item: Dictionary in data.get("environment_instances", []):
		result.append({"uid": item.uid, "piece": "environment:" + item.asset, "position": item.position.duplicate(), "rotation": item.rotation, "config": {}})
	return result

static func capture(data: Dictionary, objects: Array[BuildingPiece]) -> void:
	data.pieces = []
	data.environment_instances = []
	for object in objects:
		var record := object.serialize()
		if object.definition.authoring_only:
			data.environment_instances.append({"uid": record.uid, "asset": record.piece.trim_prefix("environment:"), "position": record.position, "rotation": record.rotation})
		else:
			data.pieces.append(record)
	if not data.environment_instances.is_empty(): data.version = 2

static func transform_for(item: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, int(item.rotation) * PI / 2), Vector3(item.position[0], item.position[1], item.position[2]))

static func inspect_definition(data: Dictionary) -> Dictionary:
	var result := {"solids": [], "errors": []}
	var instances = data.get("environment_instances", [])
	if not instances is Array:
		result.errors.append("Scenery placements must be a list")
		return result
	var seen: Array[String] = []
	for item in instances:
		if not item is Dictionary or not item.get("asset") is String:
			result.errors.append("Scenery must reference a catalog asset")
			continue
		var definition := get_asset(item.asset)
		if not definition:
			result.errors.append("Unknown scenery asset: " + item.asset)
			continue
		var point = item.get("position", [])
		var turn = item.get("rotation")
		var uid = item.get("uid", "")
		if not uid is String or uid.is_empty() or uid in seen or not point is Array or point.size() != 3 or not point.all(func(value): return (value is int or value is float) and is_finite(float(value))) or not (turn is int or turn is float) or not is_finite(float(turn)) or float(turn) != int(turn) or int(turn) < 0 or int(turn) > 3:
			result.errors.append("Invalid scenery placement")
			continue
		seen.append(uid)
		for solid: AABB in definition.collision_solids: result.solids.append(transform_for(item) * solid)
	return result

static func instantiate_definition(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Environment"
	for item: Dictionary in data.get("environment_instances", []):
		var piece: BuildingPiece = load("res://scenes/building_piece.tscn").instantiate()
		piece.instance_id = item.uid
		piece.setup(get_asset(item.asset))
		piece.name = item.uid
		piece.transform = transform_for(item)
		root.add_child(piece)
	return root

static func definition_signature(data: Dictionary) -> String:
	var contents := ""
	var assets: Array[String] = []
	for item in data.get("environment_instances", []):
		if item is Dictionary and item.get("asset") is String and get_asset(item.asset) and item.asset not in assets: assets.append(item.asset)
	assets.sort()
	for asset in assets:
		contents += asset + signature(get_asset(asset).resource_path)
	return contents

static func signature(path: String) -> String:
	if path.is_empty(): return ""
	var paths: Array[String] = [path]
	var contents := ""
	var index := 0
	while index < paths.size():
		var current := paths[index]
		index += 1
		# Compiled exports keep remapped native resources rather than every source
		# file. Publication proof is local to that build; imports check catalog IDs.
		contents += current + (FileAccess.get_sha256(current) if FileAccess.file_exists(current) else "")
		for dependency in ResourceLoader.get_dependencies(current):
			var referenced: String = dependency.get_slice("::", dependency.get_slice_count("::") - 1)
			if referenced.begins_with("res://") and referenced not in paths: paths.append(referenced)
	return contents.sha256_text()

class_name PuzzleEnvironment
extends RefCounted

# Reusable scenes own geometry; puzzle JSON owns instance placement.
const LEGACY_UID = "legacy-environment"

static func scene_path(asset: String) -> String:
	var definition := PieceCatalog.REGISTRY.load_entry(StringName("environment:" + asset)) as PieceDefinition
	return definition.model.resource_path if definition and definition.authoring_only and definition.model else ""

static func instance_scene(item: Dictionary) -> String:
	return str(item.scene) if item.get("scene") is String else scene_path(str(item.get("asset", "")))

# Saved environment records are decoded at the puzzle boundary, not by construction.
static func construction(data: Dictionary) -> Array:
	var result: Array = []
	for item: Dictionary in _placements(data):
		var id: String = "environment_scene:" + item.scene if item.has("scene") else "environment:" + item.asset
		result.append({"uid": item.uid, "piece": id, "position": item.position.duplicate(), "rotation": item.rotation, "config": {}})
	return result

static func capture(data: Dictionary, objects: Array[BuildingPiece]) -> void:
	data.pieces = []
	data.environment_instances = []
	data.erase("environment")
	data.erase("environment_placement")
	for object in objects:
		var record := object.serialize()
		if not object.definition.authoring_only:
			data.pieces.append(record)
			continue
		var item := {"uid": record.uid, "position": record.position, "rotation": record.rotation}
		if record.piece.begins_with("environment_scene:"):
			item.scene = record.piece.trim_prefix("environment_scene:")
		else:
			item.asset = record.piece.trim_prefix("environment:")
		if item.uid == LEGACY_UID:
			data.environment = item.scene
			if not transform_for(item).is_equal_approx(Transform3D.IDENTITY):
				data.environment_placement = {"position": item.position, "rotation": item.rotation}
		else:
			data.environment_instances.append(item)
	if not data.environment_instances.is_empty(): data.version = 2

static func _placements(data: Dictionary) -> Array:
	var instances: Array = data.get("environment_instances", []).duplicate(true)
	var path := str(data.get("environment", ""))
	if not path.is_empty():
		var placement: Dictionary = data.get("environment_placement", {"position": [0, 0, 0], "rotation": 0}).duplicate(true)
		placement.uid = LEGACY_UID
		placement.scene = path
		instances.push_front(placement)
	return instances

static func transform_for(item: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, int(item.rotation) * PI / 2), Vector3(item.position[0], item.position[1], item.position[2]))

static func inspect_definition(data: Dictionary) -> Dictionary:
	var result := {"solids": [], "errors": []}
	var instances = data.get("environment_instances", [])
	if not instances is Array:
		result.errors.append("Environment instances must be a list")
		return result
	if not data.get("environment_placement", {}) is Dictionary:
		result.errors.append("Invalid environment placement")
		return result
	var seen: Array[String] = []
	for item in _placements(data):
		if not item is Dictionary or instance_scene(item).is_empty():
			result.errors.append("Unknown environment asset")
			continue
		var point = item.get("position", [])
		var turn = item.get("rotation")
		var uid = item.get("uid", "")
		if not uid is String or uid.is_empty() or uid in seen or not point is Array or point.size() != 3 or not point.all(func(value): return (value is int or value is float) and is_finite(float(value))) or not (turn is int or turn is float) or not is_finite(float(turn)) or float(turn) != int(turn) or int(turn) < 0 or int(turn) > 3:
			result.errors.append("Invalid environment instance")
			continue
		seen.append(uid)
		var asset: Dictionary
		if item.has("scene"):
			asset = inspect(item.scene)
		else:
			var definition := PieceCatalog.REGISTRY.load_entry(StringName("environment:" + item.asset)) as PieceDefinition
			asset = {"solids": definition.collision_solids, "errors": []}
		result.errors.append_array(asset.errors)
		for solid: AABB in asset.solids: result.solids.append(transform_for(item) * solid)
	return result

static func instantiate_definition(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Environment"
	for item in _placements(data):
		var object: Node3D
		if item.has("scene"):
			object = ResourceLoader.load(item.scene, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
		else:
			var piece: BuildingPiece = load("res://scenes/building_piece.tscn").instantiate()
			piece.instance_id = item.uid
			piece.setup(PieceCatalog.REGISTRY.load_entry(StringName("environment:" + item.asset)))
			object = piece
		object.name = str(data.environment).get_file().get_basename() if item.uid == LEGACY_UID and data.has("environment") else item.uid
		object.set_meta("environment_uid", item.uid)
		object.transform = transform_for(item) * object.transform
		root.add_child(object)
	return root

static func definition_signature(data: Dictionary) -> String:
	var contents := signature(str(data.get("environment", "")))
	var assets: Array[String] = []
	for item in data.get("environment_instances", []):
		if item is Dictionary and not scene_path(str(item.get("asset", ""))).is_empty() and item.asset not in assets: assets.append(item.asset)
	assets.sort()
	for asset in assets:
		var definition := PieceCatalog.REGISTRY.load_entry(StringName("environment:" + asset)) as PieceDefinition
		contents += asset + signature(definition.resource_path)
	var scenes: Array[String] = []
	for item in data.get("environment_instances", []):
		if item is Dictionary and item.get("scene") is String and item.scene not in scenes: scenes.append(item.scene)
	scenes.sort()
	for path in scenes: contents += path + signature(path)
	return contents

# Publication freezes native resources, including imported mesh/collision dependencies.
static func freeze(data: Dictionary, path: String) -> Error:
	var root := instantiate_definition(data)
	_own(root, root)
	var packed := PackedScene.new()
	var error := packed.pack(root)
	root.free()
	if error != OK: return error
	return ResourceSaver.save(packed, path, ResourceSaver.FLAG_BUNDLE_RESOURCES)

static func _own(node: Node, root: Node) -> void:
	if node != root: node.owner = root
	# Published scenery keeps native geometry and collision, not construction behavior.
	if node is BuildingPiece: node.set_script(null)
	if node is Node3D: node.scene_file_path = ""
	for child in node.get_children(): _own(child, root)
static func inspect(path: String) -> Dictionary:
	var result := {"solids": [], "errors": []}
	if path.is_empty(): return result
	if not path.begins_with("res://scenes/environments/") or not path.ends_with(".tscn") or not ResourceLoader.exists(path):
		result.errors.append("Choose an environment scene under scenes/environments")
		return result
	var scene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if not scene:
		result.errors.append("Invalid environment scene")
		return result
	var root = scene.instantiate()
	if not root is Node3D: result.errors.append("Environment root must be Node3D")
	else: _collect(root, Transform3D.IDENTITY, result)
	root.free()
	return result

static func _collect(node: Node, parent_transform: Transform3D, result: Dictionary) -> void:
	var placement := parent_transform
	if node is Node3D: placement *= node.transform
	if node is CollisionShape3D and not node.disabled:
		if not node.get_parent() is StaticBody3D or not (node.shape is BoxShape3D or node.shape is ConcavePolygonShape3D):
			result.errors.append("Scenery collision must use static boxes or triangle meshes")
		elif node.get_parent().collision_layer != 1 or node.get_parent().collision_mask != 2:
			result.errors.append("Environment bodies must use layer 1 and mask 2")
		elif not placement.basis.is_equal_approx(Basis.IDENTITY) and not _axis_aligned(placement.basis):
			result.errors.append("Environment solids must use quarter turns without scale; resize the box shape")
		else:
			result.solids.append(placement * node.shape.get_debug_mesh().get_aabb())
	for child in node.get_children(): _collect(child, placement, result)

static func _axis_aligned(basis: Basis) -> bool:
	for axis in [basis.x, basis.y, basis.z]:
		var absolute: Vector3 = axis.abs()
		if not (absolute.is_equal_approx(Vector3.RIGHT) or absolute.is_equal_approx(Vector3.UP) or absolute.is_equal_approx(Vector3.BACK)): return false
	return true

static func signature(path: String) -> String:
	if path.is_empty(): return ""
	var paths: Array[String] = [path]
	var contents := ""
	var index := 0
	while index < paths.size():
		var current := paths[index]
		index += 1
		contents += current + FileAccess.get_sha256(current)
		for dependency in ResourceLoader.get_dependencies(current):
			var referenced: String = dependency.get_slice("::", dependency.get_slice_count("::") - 1)
			if referenced.begins_with("res://") and referenced not in paths: paths.append(referenced)
	return contents.sha256_text()

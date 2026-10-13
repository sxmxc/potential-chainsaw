class_name PuzzleEnvironment
extends RefCounted

# Reusable scenes own geometry; puzzle JSON owns instance placement.
const LEGACY_UID = "legacy-environment"

static func scene_path(asset: String) -> String:
	var definition := PieceCatalog.REGISTRY.load_entry(StringName("environment:" + asset)) as PieceDefinition
	return definition.model.resource_path if definition and definition.authoring_only and definition.model else ""

static func instance_scene(item: Dictionary) -> String:
	return str(item.scene) if item.get("scene") is String else scene_path(str(item.get("asset", "")))

# Project legacy references into the same placed-object records without rewriting them.
static func construction_instances(data: Dictionary) -> Array:
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
	for item in construction_instances(data):
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
		var asset := inspect(instance_scene(item))
		result.errors.append_array(asset.errors)
		for solid: AABB in asset.solids: result.solids.append(transform_for(item) * solid)
	return result

static func instantiate_definition(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Environment"
	for item in construction_instances(data):
		var object: Node3D = ResourceLoader.load(instance_scene(item), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
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
	for asset in assets: contents += asset + signature(scene_path(asset))
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
		if not node.get_parent() is StaticBody3D or not node.shape is BoxShape3D:
			result.errors.append("Environment collision must use static BoxShape3D solids")
		elif node.get_parent().collision_layer != 1 or node.get_parent().collision_mask != 2:
			result.errors.append("Environment bodies must use layer 1 and mask 2")
		elif not placement.basis.is_equal_approx(Basis.IDENTITY) and not _axis_aligned(placement.basis):
			result.errors.append("Environment solids must use quarter turns without scale; resize the box shape")
		else:
			result.solids.append(placement * AABB(-node.shape.size / 2, node.shape.size))
	for child in node.get_children(): _collect(child, placement, result)

static func _axis_aligned(basis: Basis) -> bool:
	for axis in [basis.x, basis.y, basis.z]:
		var absolute: Vector3 = axis.abs()
		if not (absolute.is_equal_approx(Vector3.RIGHT) or absolute.is_equal_approx(Vector3.UP) or absolute.is_equal_approx(Vector3.BACK)): return false
	return true

static func blocked(definition: PieceDefinition, placement: Transform3D, solids: Array) -> bool:
	var bounds: AABB = placement * definition.bounds
	for solid: AABB in solids:
		if not bounds.grow(-0.001).intersects(solid): continue
		if definition.reserve_bounds or definition.surface_cells.is_empty(): return true
		# Existing catalog samples represent occupied 10 cm cells. Test their
		# volumes, not just centres: even a thin partition must block placement.
		for point in definition.surface_cells:
			var cell := placement * AABB(point - Vector3.ONE * 0.05, Vector3.ONE * 0.1)
			if cell.grow(-0.001).intersects(solid): return true
	return false

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

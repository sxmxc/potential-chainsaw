class_name PieceCatalog
extends RefCounted

const REGISTRY: Registry = preload("res://resources/registries/piece_registry.tres")
# Order is presentation only; category membership comes from registered resources.
const CATEGORY_ORDER: Array[String] = ["Start & finish", "Straight tracks", "Curves & turns", "Elevation", "Junctions & transitions", "Waves & bumps", "Ends & drops", "Supports", "Mechanisms", "Scenery", "Architecture", "Platforms & stairs", "Factory structures", "Industrial props"]
var scene_definitions: Dictionary = {}
# ResourceLoader's cache is weak; retain loaded entries without a second ID map.
var resident_definitions: Array[PieceDefinition] = []

func query(criteria: Dictionary[StringName, Variant] = {}) -> Array[PieceDefinition]:
	var result: Array[PieceDefinition] = []
	var ids := REGISTRY.get_all_string_ids() if criteria.is_empty() else REGISTRY.where(criteria)
	for id in ids:
		var definition := get_piece(String(id))
		if definition: result.append(definition)
	result.sort_custom(func(a: PieceDefinition, b: PieceDefinition): return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return result

func get_piece(id: String) -> PieceDefinition:
	if not id.begins_with("environment_scene:"):
		var definition := REGISTRY.load_entry(StringName(id)) as PieceDefinition
		if definition and definition.id != StringName(id):
			push_error("Registry ID does not match PieceDefinition.id: " + id)
			return null
		if definition and definition not in resident_definitions: resident_definitions.append(definition)
		return definition
	# Legacy and user-authored scene references are placements, not library entries.
	if not scene_definitions.has(StringName(id)):
		var path := id.trim_prefix("environment_scene:")
		var inspected := PuzzleEnvironment.inspect(path)
		if not inspected.errors.is_empty(): return null
		var definition := PieceDefinition.new()
		definition.id = StringName(id)
		definition.display_name = path.get_file().get_basename().replace("_", " ").capitalize()
		definition.category = "Scenery"
		definition.behavior = "decoration"
		definition.authoring_only = true
		definition.collision_enabled = false
		definition.model = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		definition.collision_solids.assign(inspected.solids)
		for index in definition.collision_solids.size():
			definition.bounds = definition.collision_solids[index] if index == 0 else definition.bounds.merge(definition.collision_solids[index])
		scene_definitions[definition.id] = definition
	return scene_definitions.get(StringName(id))

func categories() -> Array[String]:
	var result: Array[String] = []
	for piece in query():
		if not result.has(piece.category): result.append(piece.category)
	result.sort_custom(func(a: String, b: String):
		var first := CATEGORY_ORDER.find(a)
		var second := CATEGORY_ORDER.find(b)
		if first == -1: first = CATEGORY_ORDER.size()
		if second == -1: second = CATEGORY_ORDER.size()
		return a.naturalnocasecmp_to(b) < 0 if first == second else first < second)
	result.push_front("All pieces")
	return result

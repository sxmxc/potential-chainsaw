class_name PieceCatalog
extends RefCounted

const REGISTRY: Registry = preload("res://resources/registries/piece_registry.tres")
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
	var definition := REGISTRY.load_entry(StringName(id)) as PieceDefinition
	if definition and definition.id != StringName(id):
		push_error("Registry ID does not match PieceDefinition.id: " + id)
		return null
	if definition and definition not in resident_definitions: resident_definitions.append(definition)
	return definition

func categories() -> Array[String]:
	var result: Array[String] = []
	for piece in query():
		if not result.has(piece.category): result.append(piece.category)
	result.sort_custom(func(a: String, b: String): return a.naturalnocasecmp_to(b) < 0)
	result.push_front("All pieces")
	return result

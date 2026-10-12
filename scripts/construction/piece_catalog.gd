class_name PieceCatalog
extends RefCounted

var pieces: Array[PieceDefinition] = []
var by_id: Dictionary = {}

func _init() -> void:
	for file in DirAccess.get_files_at("res://resources/pieces"):
		if file.ends_with(".tres"):
			var definition = load("res://resources/pieces/" + file) as PieceDefinition
			if definition:
				pieces.append(definition)
				by_id[definition.id] = definition
	pieces.sort_custom(func(a: PieceDefinition, b: PieceDefinition): return a.display_name.naturalnocasecmp_to(b.display_name) < 0)

func get_piece(id: String) -> PieceDefinition:
	return by_id.get(StringName(id))

func categories() -> Array[String]:
	var result: Array[String] = ["All pieces", "Start & finish", "Straight tracks", "Curves & turns", "Elevation", "Junctions & transitions", "Waves & bumps", "Ends & drops", "Supports", "Mechanisms", "Scenery"]
	for piece in pieces:
		if not result.has(piece.category): result.append(piece.category)
	return result

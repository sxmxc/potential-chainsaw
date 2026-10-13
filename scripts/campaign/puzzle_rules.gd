class_name PuzzleRules
extends RefCounted

var puzzle: Dictionary
var catalog: PieceCatalog
var initial: Dictionary = {}
var environment_solids: Array = []

func _init(data: Dictionary, definitions: PieceCatalog, solids: Variant = null) -> void:
	puzzle = data.duplicate(true)
	catalog = definitions
	environment_solids = PuzzleEnvironment.inspect_definition(data).solids if solids == null else solids
	for piece in puzzle.get("pieces", []): initial[piece.uid] = piece

func permits(uid: String, action: String) -> bool:
	return not initial.has(uid) or bool(puzzle.get("permissions", {}).get(uid, {}).get(action, false))

func remaining(id: String, construction: Array) -> int:
	var quantity = int(puzzle.get("inventory", {}).get(id, 0))
	for piece in construction:
		if not initial.has(piece.uid) and piece.piece == id: quantity -= 1
	return quantity

func validate(construction: Array) -> String:
	var seen: Dictionary = {}
	var present: Array = []
	for item in construction: present.append(item.uid)
	for item in construction:
		if seen.has(item.uid): return "Duplicate instance identifier"
		seen[item.uid] = item
		var definition = catalog.get_piece(item.piece)
		if not definition or definition.authoring_only: return "Unknown piece"
		var configured_definition := definition.configured(item.get("config", {}))
		var bounds_changed := initial.has(item.uid) and configured_definition.bounds != definition.configured(initial[item.uid].get("config", {})).bounds
		definition = configured_definition
		for key in puzzle.get("configuration_limits", {}).get(item.piece, {}):
			var limits: Array = puzzle.configuration_limits[item.piece][key]
			var value = item.get("config", {}).get(key)
			if value != null and (not (value is float or value is int) or float(value) < float(limits[0]) or float(value) > float(limits[1])): return "Mechanism setting exceeds puzzle limits: " + key
		var placement := Transform3D(Basis(Vector3.UP, int(item.rotation) * PI / 2), Vector3(item.position[0], item.position[1], item.position[2]))
		if SnapManager.intersects_solids(definition, placement, environment_solids): return "Blocked by the environment"
		if initial.has(item.uid):
			var original: Dictionary = initial[item.uid]
			if item.piece != original.piece: return "Authored pieces cannot be replaced"
			if item.position != original.position and not permits(item.uid, "move"): return "This piece is fixed in place"
			if posmod(int(item.rotation), 4) != posmod(int(original.rotation), 4) and not permits(item.uid, "rotate"): return "Rotation is locked"
			var settings: Dictionary = item.get("config", {})
			var old: Dictionary = original.get("config", {}).duplicate(true)
			if old.has("links"): old.links = old.links.filter(func(link): return link.get("target", "") in present)
			if settings != old:
				if not permits(item.uid, "configure"): return "Configuration is locked"
				var permission: Dictionary = puzzle.get("permissions", {}).get(item.uid, {})
				for key in settings.keys() + old.keys():
					if settings.get(key) == old.get(key): continue
					if permission.has("config_keys") and key not in permission.config_keys: return "Setting is locked: " + key
					if permission.get("limits", {}).has(key):
						var limits: Array = permission.limits[key]
						if not (settings.get(key) is float or settings.get(key) is int): return "Invalid setting"
						if float(settings[key]) < float(limits[0]) or float(settings[key]) > float(limits[1]): return "Setting exceeds puzzle limits: " + key
		if not initial.has(item.uid) or item.position != initial[item.uid].position or item.rotation != initial[item.uid].rotation or bounds_changed:
			var position = Vector3(item.position[0], item.position[1], item.position[2])
			var volume = Transform3D(Basis(Vector3.UP, int(item.rotation) * PI / 2), position) * definition.bounds
			var bounds = puzzle.get("bounds", [-12, -12, 12, 12, 0, 12])
			if volume.position.x < bounds[0] - 0.001 or volume.position.z < bounds[1] - 0.001 or volume.end.x > bounds[2] + 0.001 or volume.end.z > bounds[3] + 0.001 or position.y < bounds[4] - 0.001 or volume.end.y > bounds[5] + 0.001: return "Outside the visible build region"
			for zone in puzzle.get("restricted_zones", []):
				if volume.intersects(AABB(Vector3(zone[0], zone[1], zone[2]), Vector3(zone[3], zone[4], zone[5]))): return "Inside a restricted zone"
	for uid in initial:
		if not seen.has(uid) and not permits(uid, "remove"): return "An authored piece cannot be removed"
	for item in construction:
		if not initial.has(item.uid) and remaining(item.piece, construction) < 0: return "No inventory remaining for " + catalog.get_piece(item.piece).display_name
	return ""

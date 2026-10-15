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
			if placement.origin != Vector3(original.position[0], original.position[1], original.position[2]) and not permits(item.uid, "move"): return "This piece is fixed in place"
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
		if not initial.has(item.uid) or placement.origin != Vector3(initial[item.uid].position[0], initial[item.uid].position[1], initial[item.uid].position[2]) or item.rotation != initial[item.uid].rotation or bounds_changed:
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

# Definition checks run before resource use; construction checks above enforce player edits.
static func definition_errors(data: Dictionary, definitions: PieceCatalog, check_solution: bool = false) -> Array[String]:
	var errors := shape_errors(data)
	if not errors.is_empty(): return errors
	for id in data.get("inventory", {}).keys() + data.get("configuration_limits", {}).keys():
		if not PieceCatalog.REGISTRY.has_string_id(StringName(id)): errors.append("Unknown catalog piece: " + id)
	for item in data.get("pieces", []) + data.get("solution", []):
		# Resolve only registered pieces.
		if not PieceCatalog.REGISTRY.has_string_id(StringName(item.piece)): errors.append("Unknown catalog piece: " + item.piece)
		else:
			var definition := definitions.get_piece(item.piece)
			if definition.authoring_only: errors.append("Scenery must use environment placements: " + item.piece)
			for setting in definition.settings:
				if not item.get("config", {}).has(setting.key): continue
				var value = item.config[setting.key]
				if (setting.kind == PieceSetting.Kind.NUMBER and not _is_number(value)) or (setting.kind == PieceSetting.Kind.FLAG and not value is bool) or (setting.kind == PieceSetting.Kind.STRING and not value is String): errors.append("Invalid setting: " + String(setting.key))
	for id in data.get("required_assets", []):
		if not PieceCatalog.REGISTRY.has_string_id(StringName(id)): errors.append("Missing required asset: " + id)
	if not errors.is_empty(): return errors
	var environment = PuzzleEnvironment.inspect_definition(data)
	for error in environment.errors: errors.append(str(error))
	if not SaveStorage.valid_id(data.id): errors.append("Invalid puzzle ID")
	if str(data.get("name", "")).strip_edges().is_empty(): errors.append("A puzzle needs a name")
	var by_id: Dictionary = {}
	var starts = 0
	for piece in data.get("pieces", []):
		if by_id.has(piece.uid): errors.append("Duplicate piece ID")
		by_id[piece.uid] = piece
		var definition = definitions.get_piece(piece.piece)
		if not definition: errors.append("Unknown piece: " + piece.piece)
		elif definition.has_behavior(MarbleRelease): starts += 1
		if definition:
			definition = definition.configured(piece.get("config", {}))
			if SnapManager.intersects_solids(definition, Transform3D(Basis(Vector3.UP, int(piece.rotation) * PI / 2), Vector3(piece.position[0], piece.position[1], piece.position[2])), environment.solids): errors.append("Starting piece intersects environment: " + piece.uid)
	if starts == 0: errors.append("Place a marble release")
	if data.get("objectives", []).is_empty(): errors.append("Add a completion objective")
	for objective in data.get("objectives", []):
		if not by_id.has(objective.get("target", "")): errors.append("Objective target is missing")
		elif objective.get("type", "deliver") == "deliver" and definitions.get_piece(by_id[objective.target].piece) and not definitions.get_piece(by_id[objective.target].piece).has_behavior(MarbleCollector): errors.append("Delivery objective needs a collector")
		if objective.get("type", "deliver") not in ["deliver", "activate"]: errors.append("Unknown objective type")
		if int(objective.get("count", 1)) < 1: errors.append("Objective quantity must be positive")
		if not objective.get("source", "").is_empty() and not by_id.has(objective.source): errors.append("Required marble source is missing")
	for id in data.get("inventory", {}):
		var definition := definitions.get_piece(id)
		if not definition or definition.authoring_only or int(data.inventory[id]) < 0: errors.append("Invalid inventory: " + id)
	var bounds = data.get("bounds", [])
	if bounds.size() != 6 or bounds[0] >= bounds[2] or bounds[1] >= bounds[3] or bounds[4] >= bounds[5]: errors.append("Build region is empty")
	for id in data.get("configuration_limits", {}):
		if not definitions.get_piece(id): errors.append("Unknown restricted mechanism")
		for key in data.configuration_limits[id]:
			var limits = data.configuration_limits[id][key]
			if not limits is Array or limits.size() != 2 or limits[0] > limits[1]: errors.append("Invalid mechanism setting limits")
	for source in data.get("pieces", []):
		for link in source.get("config", {}).get("links", []):
			if not by_id.has(link.get("target", "")): errors.append("Mechanism link target is missing")
	# Draft edits may invalidate the preserved solution; only distribution checks
	# require that solution to obey the current player rules.
	if check_solution and errors.is_empty() and not data.get("solution", []).is_empty():
		var problem := PuzzleRules.new(data, definitions, environment.solids).validate(data.solution)
		if not problem.is_empty(): errors.append(problem)
	return errors

# Check JSON types before any engine/resource operation. Unknown fields cannot
# introduce resource loading; scene-bearing fields are blocked for community data.
static func shape_errors(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in ["environment", "environment_placement", "environment_snapshot"]:
		if data.has(key): errors.append("Scene-based scenery is no longer supported; rebuild this puzzle with catalog pieces")
	for key in ["id", "name", "version", "pieces"]:
		if not data.has(key): errors.append("Missing puzzle field: " + key)
	for key in ["version", "revision", "time_limit"]:
		if data.has(key) and not _is_number(data[key]): errors.append("Invalid number: " + key)
	for key in ["id", "name", "description", "creator", "difficulty", "status"]:
		if data.has(key) and not data[key] is String: errors.append("Invalid text: " + key)
	for key in ["pieces", "solution", "environment_instances", "objectives", "restricted_zones", "hints", "required_assets"]:
		if not data.get(key, []) is Array or data.get(key, []).size() > 5000: errors.append("Invalid list: " + key)
	for key in ["inventory", "permissions", "configuration_limits", "camera", "awards", "validation", "campaign"]:
		if not data.get(key, {}) is Dictionary: errors.append("Invalid object: " + key)
	if not _numeric_array(data.get("bounds"), 6): errors.append("Invalid build bounds")
	if not errors.is_empty(): return errors
	if int(data.version) not in [1, 2] or float(data.version) != int(data.version): errors.append("Unsupported puzzle version")
	for key in ["pieces", "solution"]:
		for item in data.get(key, []):
			if not item is Dictionary or not item.get("uid") is String or not item.get("piece") is String or not _numeric_array(item.get("position"), 3) or not _is_number(item.get("rotation")) or not item.get("config", {}) is Dictionary:
				errors.append("Invalid construction record")
				continue
			var config: Dictionary = item.get("config", {})
			if config.has("release_speed") and not _is_number(config.release_speed): errors.append("Invalid release speed")
			if float(item.rotation) != int(item.rotation) or int(item.rotation) not in [0, 1, 2, 3]: errors.append("Invalid piece rotation")
			for value in config.values():
				if not (value is String or value is bool or _is_number(value) or value is Array): errors.append("Invalid mechanism configuration")
			if not config.get("links", []) is Array: errors.append("Invalid mechanism links"); continue
			for link in config.get("links", []):
				if not link is Dictionary or not link.get("target") is String or not link.get("event") is String or not link.get("action") is String: errors.append("Invalid mechanism link")
	for item in data.get("environment_instances", []):
		if not item is Dictionary or not item.get("uid") is String or not _numeric_array(item.get("position"), 3) or not _is_number(item.get("rotation")) or item.has("scene") or not item.get("asset") is String: errors.append("Invalid scenery record")
	for objective in data.get("objectives", []):
		if not objective is Dictionary: errors.append("Invalid objective"); continue
		for key in ["target", "source", "type", "event"]:
			if objective.has(key) and not objective[key] is String: errors.append("Invalid objective " + key)
		for key in ["count", "time_limit"]:
			if objective.has(key) and not _is_number(objective[key]): errors.append("Invalid objective " + key)
	for zone in data.get("restricted_zones", []):
		if not _numeric_array(zone, 6): errors.append("Invalid restricted region")
	for value in data.get("hints", []) + data.get("required_assets", []):
		if not value is String: errors.append("Invalid text list")
	for count in data.get("inventory", {}).values():
		if not _is_number(count): errors.append("Invalid inventory count")
	for permission in data.get("permissions", {}).values():
		if not permission is Dictionary: errors.append("Invalid permissions"); continue
		if not permission.get("config_keys", []) is Array: errors.append("Invalid permitted settings")
		if not _valid_limits(permission.get("limits", {})): errors.append("Invalid permission limits")
	for limits in data.get("configuration_limits", {}).values():
		if not _valid_limits(limits): errors.append("Invalid configuration limits")
	var camera: Dictionary = data.get("camera", {})
	if not camera.is_empty():
		if not _numeric_array(camera.get("focus"), 3): errors.append("Invalid camera focus")
		for key in ["yaw", "pitch", "distance"]:
			if not _is_number(camera.get(key)): errors.append("Invalid camera " + key)
	for value in data.get("awards", {}).values():
		if not _is_number(value): errors.append("Invalid award")
	var proof: Dictionary = data.get("validation", {})
	if proof.has("physics_success") and not proof.physics_success is bool: errors.append("Invalid validation result")
	if proof.has("fingerprint") and not proof.fingerprint is String: errors.append("Invalid validation fingerprint")
	return errors

static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _numeric_array(value: Variant, size: int) -> bool:
	return value is Array and value.size() == size and value.all(func(item): return _is_number(item) and absf(float(item)) <= 1000)

static func _valid_limits(value: Variant) -> bool:
	if not value is Dictionary: return false
	for limits in value.values():
		if not _numeric_array(limits, 2) or limits[0] > limits[1]: return false
	return true

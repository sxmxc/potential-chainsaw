class_name PuzzleStore
extends RefCounted

const DRAFTS = "user://puzzles/drafts"
const PUBLISHED = "user://puzzles/published"
const PROGRESS = "user://campaign_progress.json"
var catalog: PieceCatalog
var progress: Dictionary = {}
var last_error: String = ""

func _init(definitions: PieceCatalog) -> void:
	catalog = definitions
	DirAccess.make_dir_recursive_absolute(DRAFTS)
	DirAccess.make_dir_recursive_absolute(PUBLISHED)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS)) if FileAccess.file_exists(PROGRESS) else null
	if saved is Dictionary: progress = saved

func create() -> Dictionary:
	return {"version": 1, "id": "puzzle-" + Crypto.new().generate_random_bytes(8).hex_encode(), "revision": 1, "name": "New puzzle", "description": "Deliver the marble to the collector.", "order": 1, "difficulty": "Introduction", "pieces": [], "permissions": {}, "inventory": {}, "bounds": [-12, -12, 12, 12, 0, 12], "restricted_zones": [], "objectives": [], "hints": [], "prerequisites": [], "camera": {}, "awards": {}, "solution": [], "validation": {}, "status": "draft"}

func fingerprint(data: Dictionary) -> String:
	var content = data.duplicate(true)
	for key in ["solution", "validation", "status", "modified"]: content.erase(key)
	# Canonicalize the numeric types and precision produced by JSON persistence.
	return JSON.stringify(JSON.parse_string(JSON.stringify(content)), "", true, true).sha256_text()

func validate(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(data.get("version", 0)) != 1: errors.append("Unsupported puzzle version")
	if not TrackSerializer.new(catalog).valid_id(str(data.get("id", ""))): errors.append("Invalid puzzle ID")
	if str(data.get("name", "")).strip_edges().is_empty(): errors.append("A puzzle needs a name")
	var track = TrackSerializer.new(catalog)
	var construction = track.decode(JSON.stringify({"version": 1, "name": str(data.get("name", "")), "pieces": data.get("pieces", [])}))
	if construction.is_empty() or not track.warnings.is_empty(): errors.append("Starting construction is invalid: " + track.last_error + " ".join(track.warnings))
	if not data.get("inventory", {}) is Dictionary or not data.get("permissions", {}) is Dictionary: errors.append("Invalid rule data"); return errors
	var by_id: Dictionary = {}
	var starts = 0
	for piece in data.get("pieces", []):
		if by_id.has(piece.uid): errors.append("Duplicate piece ID")
		by_id[piece.uid] = piece
		var definition = catalog.get_piece(piece.piece)
		if not definition: errors.append("Unknown piece: " + piece.piece)
		elif definition.behavior == "start": starts += 1
	if starts == 0: errors.append("Place a marble release")
	if data.get("objectives", []).is_empty(): errors.append("Add a completion objective")
	for objective in data.get("objectives", []):
		if not by_id.has(objective.get("target", "")): errors.append("Objective target is missing")
		elif objective.get("type", "deliver") == "deliver" and catalog.get_piece(by_id[objective.target].piece) and catalog.get_piece(by_id[objective.target].piece).behavior != "finish": errors.append("Delivery objective needs a collector")
		if objective.get("type", "deliver") not in ["deliver", "activate"]: errors.append("Unknown objective type")
		if int(objective.get("count", 1)) < 1: errors.append("Objective quantity must be positive")
		if not objective.get("source", "").is_empty() and not by_id.has(objective.source): errors.append("Required marble source is missing")
	for id in data.get("inventory", {}):
		if not catalog.get_piece(id) or int(data.inventory[id]) < 0: errors.append("Invalid inventory: " + id)
	var bounds = data.get("bounds", [])
	if bounds.size() != 6 or bounds[0] >= bounds[2] or bounds[1] >= bounds[3] or bounds[4] >= bounds[5]: errors.append("Build region is empty")
	for id in data.get("configuration_limits", {}):
		if not catalog.get_piece(id): errors.append("Unknown restricted mechanism")
		for key in data.configuration_limits[id]:
			var limits = data.configuration_limits[id][key]
			if not limits is Array or limits.size() != 2 or limits[0] > limits[1]: errors.append("Invalid mechanism setting limits")
	for source in data.get("pieces", []):
		for link in source.get("config", {}).get("links", []):
			if not by_id.has(link.get("target", "")): errors.append("Mechanism link target is missing")
	return errors

func write(path: String, data: Dictionary) -> bool:
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file: last_error = "Could not write " + path; return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK: last_error = "Could not finish saving"; return false
	return true

func save_draft(data: Dictionary) -> bool:
	if not TrackSerializer.new(catalog).valid_id(str(data.get("id", ""))): return false
	return write(DRAFTS + "/" + data.id + ".json", data)

func publish(data: Dictionary) -> bool:
	var errors = validate(data)
	if data.get("validation", {}).get("fingerprint", "") != fingerprint(data) or not data.get("validation", {}).get("physics_success", false): errors.append("Test this revision successfully as a player and preserve the solution first")
	if not errors.is_empty(): last_error = "\n".join(errors); return false
	var published = data.duplicate(true)
	published.status = "published"
	return write(PUBLISHED + "/" + data.id + ".json", published)

func list_puzzles(drafts: bool = false) -> Array[Dictionary]:
	var by_id: Dictionary = {}
	var directories = [DRAFTS] if drafts else ["res://resources/campaign", PUBLISHED]
	for directory in directories:
		for filename in DirAccess.get_files_at(directory):
			if not filename.ends_with(".json"): continue
			var data = JSON.parse_string(FileAccess.get_file_as_string(directory + "/" + filename))
			if data is Dictionary and (drafts or data.get("status") == "published"): by_id[data.id] = data
	var result: Array[Dictionary] = []
	for data in by_id.values(): result.append(data)
	result.sort_custom(func(a, b): return int(a.order) < int(b.order))
	return result

func unlocked(data: Dictionary, levels: Array) -> bool:
	for id in data.get("prerequisites", []):
		if not progress.has(id): return false
	if not data.get("prerequisites", []).is_empty(): return true
	if levels.is_empty() or data.id == levels[0].id: return true
	for i in levels.size():
		if levels[i].id == data.id: return progress.has(data.id) or progress.has(levels[i - 1].id)
	return false

func complete(data: Dictionary, seconds: float, count: int) -> void:
	var previous: Dictionary = progress.get(data.id, {})
	progress[data.id] = {"completed": true, "revision": data.get("revision", 1), "best_time": minf(seconds, float(previous.get("best_time", INF))), "fewest_pieces": mini(count, int(previous.get("fewest_pieces", 99999)))}
	var awards: Array = previous.get("awards", []).duplicate()
	var goals: Dictionary = data.get("awards", {})
	if float(goals.get("time", 0)) > 0 and seconds <= float(goals.time) and "time" not in awards: awards.append("time")
	if int(goals.get("pieces", 0)) > 0 and count <= int(goals.pieces) and "pieces" not in awards: awards.append("pieces")
	progress[data.id].awards = awards
	write(PROGRESS, progress)

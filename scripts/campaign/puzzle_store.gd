class_name PuzzleStore
extends RefCounted

var drafts_directory: String = SavePaths.resolve("user://puzzles/drafts")
var published_directory: String = SavePaths.resolve("user://puzzles/published")
var progress_path: String = SavePaths.resolve("user://campaign_progress.json")
var campaign_state_path: String = SavePaths.resolve("user://campaign_state.json")
const CHAPTERS = "res://resources/campaign_chapters.json"
var catalog: PieceCatalog
var progress: Dictionary = {}
var campaign: Dictionary = {}
var last_error: String = ""

func _init(definitions: PieceCatalog) -> void:
	catalog = definitions
	DirAccess.make_dir_recursive_absolute(drafts_directory)
	DirAccess.make_dir_recursive_absolute(published_directory)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(progress_path)) if FileAccess.file_exists(progress_path) else null
	if saved is Dictionary: progress = saved
	var state = JSON.parse_string(FileAccess.get_file_as_string(campaign_state_path)) if FileAccess.file_exists(campaign_state_path) else null
	if state is Dictionary:
		campaign = state
	elif not progress.is_empty():
		# Legacy progress remains in place, including IDs, records, and awards.
		campaign = {"version": 1, "started": true, "introduction_skipped": false}
		var levels = list_puzzles()
		for data in levels:
			if not completed(data.id) and unlocked(data, levels):
				campaign.current_level = data.id
				campaign.current_chapter = chapter_for(data).id
				break
		if not campaign.has("current_chapter"): campaign.current_chapter = first_chapter(false).get("id", "")

func create() -> Dictionary:
	return {"version": 2, "environment_instances": [], "id": "puzzle-" + Crypto.new().generate_random_bytes(8).hex_encode(), "revision": 1, "name": "New puzzle", "description": "Deliver the marble to the collector.", "chapter": first_chapter(false), "order": 1, "difficulty": "Workshop", "pieces": [], "permissions": {}, "inventory": {}, "bounds": [-12, -12, 12, 12, 0, 12], "restricted_zones": [], "objectives": [], "hints": [], "prerequisites": [], "camera": {}, "awards": {}, "solution": [], "validation": {}, "status": "draft"}

func fingerprint(data: Dictionary) -> String:
	var content = data.duplicate(true)
	for key in ["solution", "validation", "status", "modified", "environment_snapshot"]: content.erase(key)
	if not str(data.get("environment", "")).is_empty() or not data.get("environment_instances", []).is_empty(): content["environment_signature"] = PuzzleEnvironment.definition_signature(data)
	if content.get("environment_instances", []).is_empty(): content.erase("environment_instances")
	# Canonicalize the numeric types and precision produced by JSON persistence.
	return JSON.stringify(JSON.parse_string(JSON.stringify(content)), "", true, true).sha256_text()

func validate(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var environment = PuzzleEnvironment.inspect_definition(data)
	for error in environment.errors: errors.append(str(error))
	if int(data.get("version", 0)) not in [1, 2]: errors.append("Unsupported puzzle version")
	if not TrackSerializer.new(catalog).valid_id(str(data.get("id", ""))): errors.append("Invalid puzzle ID")
	if str(data.get("name", "")).strip_edges().is_empty(): errors.append("A puzzle needs a name")
	var chapter = chapter_for(data)
	if not TrackSerializer.new(catalog).valid_id(str(chapter.get("id", ""))): errors.append("Invalid chapter ID")
	if str(chapter.get("name", "")).strip_edges().is_empty(): errors.append("A chapter needs a display name")
	if int(data.get("order", 0)) < 1: errors.append("Level order must be positive")
	if chapter.get("introduction", false) and not chapter.get("optional", false): errors.append("Introduction chapters must be optional")
	if not chapter.get("prerequisites", []) is Array: errors.append("Chapter unlock requirements must be a list")
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
		if definition:
			definition = definition.configured(piece.get("config", {}))
			if SnapManager.intersects_solids(definition, Transform3D(Basis(Vector3.UP, int(piece.rotation) * PI / 2), Vector3(piece.position[0], piece.position[1], piece.position[2])), environment.solids): errors.append("Starting piece intersects environment: " + piece.uid)
	if starts == 0: errors.append("Place a marble release")
	if data.get("objectives", []).is_empty(): errors.append("Add a completion objective")
	for objective in data.get("objectives", []):
		if not by_id.has(objective.get("target", "")): errors.append("Objective target is missing")
		elif objective.get("type", "deliver") == "deliver" and catalog.get_piece(by_id[objective.target].piece) and catalog.get_piece(by_id[objective.target].piece).behavior != "finish": errors.append("Delivery objective needs a collector")
		if objective.get("type", "deliver") not in ["deliver", "activate"]: errors.append("Unknown objective type")
		if int(objective.get("count", 1)) < 1: errors.append("Objective quantity must be positive")
		if not objective.get("source", "").is_empty() and not by_id.has(objective.source): errors.append("Required marble source is missing")
	for id in data.get("inventory", {}):
		var definition := catalog.get_piece(id)
		if not definition or definition.authoring_only or int(data.inventory[id]) < 0: errors.append("Invalid inventory: " + id)
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
	return write(drafts_directory + "/" + data.id + ".json", data)

func publish(data: Dictionary) -> bool:
	var errors = validate(data)
	if data.get("validation", {}).get("fingerprint", "") != fingerprint(data) or not data.get("validation", {}).get("physics_success", false): errors.append("Test this revision successfully as a player and preserve the solution first")
	if not errors.is_empty(): last_error = "\n".join(errors); return false
	var published = data.duplicate(true)
	published.status = "published"
	published.erase("environment_snapshot")
	if not str(data.get("environment", "")).is_empty() or not data.get("environment_instances", []).is_empty():
		var snapshot_path: String = published_directory + "/" + data.id + "-" + fingerprint(data) + ".tscn"
		if PuzzleEnvironment.freeze(data, snapshot_path) != OK:
			last_error = "Could not preserve the published environment"
			return false
		published.environment_snapshot = snapshot_path
	return write(published_directory + "/" + data.id + ".json", published)

func list_puzzles(drafts: bool = false) -> Array[Dictionary]:
	var by_id: Dictionary = {}
	var directories = ["res://resources/puzzle_drafts", drafts_directory] if drafts else ["res://resources/campaign", published_directory]
	for directory in directories:
		for filename in DirAccess.get_files_at(directory):
			if not filename.ends_with(".json"): continue
			var data = JSON.parse_string(FileAccess.get_file_as_string(directory + "/" + filename))
			if data is Dictionary and (drafts or data.get("status") == "published"): by_id[data.id] = data
	var result: Array[Dictionary] = []
	for data in by_id.values(): result.append(data)
	result.sort_custom(func(a, b):
		var ca = chapter_for(a)
		var cb = chapter_for(b)
		if int(ca.get("order", 1)) != int(cb.get("order", 1)): return int(ca.get("order", 1)) < int(cb.get("order", 1))
		if ca.id != cb.id: return str(ca.id) < str(cb.id)
		if int(a.order) != int(b.order): return int(a.order) < int(b.order)
		return str(a.id) < str(b.id))
	return result

func unlocked(data: Dictionary, levels: Array) -> bool:
	if completed(data.id): return true
	var chapter = chapter_for(data)
	# Introduction puzzles can always be revisited independently.
	if chapter.get("introduction", false): return true
	if not chapter_unlocked(chapter): return false
	for id in data.get("prerequisites", []):
		if not requirement_completed(id): return false
	if not data.get("prerequisites", []).is_empty(): return true
	var previous: Dictionary = {}
	for level in levels:
		if chapter_for(level).id != chapter.id: continue
		if level.id == data.id: return previous.is_empty() or completed(previous.id)
		previous = level
	return false

func completed(id: String) -> bool:
	return progress.get(id, {}).get("completed", false)

func base_chapters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var data = JSON.parse_string(FileAccess.get_file_as_string(CHAPTERS))
	if data is Dictionary:
		for chapter in data.get("chapters", []): result.append(chapter)
	result.sort_custom(func(a, b): return int(a.get("order", 1)) < int(b.get("order", 1)))
	return result

func chapter_for(data: Dictionary) -> Dictionary:
	var metadata: Dictionary = data.get("chapter", {})
	for chapter in base_chapters():
		if metadata.get("id", "") == chapter.id or (metadata.is_empty() and data.get("id", "") in chapter.get("levels", [])):
			var result = chapter.duplicate(true)
			result.merge(metadata, true)
			return result
	if not metadata.is_empty(): return metadata
	return first_chapter(false)

func first_chapter(intro: bool) -> Dictionary:
	for chapter in base_chapters():
		if bool(chapter.get("introduction", false)) == intro: return chapter.duplicate(true)
	return {}

func list_chapters(levels: Array) -> Array[Dictionary]:
	var by_id: Dictionary = {}
	for chapter in base_chapters(): by_id[chapter.id] = chapter
	for data in levels:
		var chapter = chapter_for(data)
		by_id[chapter.id] = chapter
	var result: Array[Dictionary] = []
	for chapter in by_id.values(): result.append(chapter)
	result.sort_custom(func(a, b):
		if int(a.get("order", 1)) != int(b.get("order", 1)): return int(a.get("order", 1)) < int(b.get("order", 1))
		return str(a.id) < str(b.id))
	return result

func requirement_completed(id: String) -> bool:
	# Optional introduction never gates the main campaign, even in legacy prerequisites.
	for chapter in list_chapters(list_puzzles()):
		if chapter.get("introduction", false) and id in chapter.get("levels", []): return true
	for level in list_puzzles():
		if level.id == id and chapter_for(level).get("introduction", false): return true
	return completed(id)

func chapter_unlocked(chapter: Dictionary) -> bool:
	if chapter.get("introduction", false): return true
	for id in chapter.get("prerequisites", []):
		if not requirement_completed(id): return false
	return true

func chapter_progress(id: String, levels: Array) -> Dictionary:
	var total = 0
	var done = 0
	for data in levels:
		if chapter_for(data).id != id: continue
		total += 1
		if completed(data.id): done += 1
	return {"completed": done, "total": total}

func start_campaign(play_introduction: bool) -> Dictionary:
	var chapter = first_chapter(play_introduction)
	campaign = {"version": 1, "started": true, "introduction_skipped": not play_introduction, "current_chapter": chapter.get("id", ""), "current_level": ""}
	var target = resume_level()
	if not target.is_empty(): campaign.current_level = target.id
	write(campaign_state_path, campaign)
	return target

func remember_level(data: Dictionary) -> void:
	if not campaign.get("started", false):
		campaign = {"version": 1, "started": true, "introduction_skipped": false}
	var chapter = chapter_for(data)
	campaign.current_level = data.id
	campaign.current_chapter = chapter.id
	campaign["introduction_level" if chapter.get("introduction", false) else "main_level"] = data.id
	write(campaign_state_path, campaign)

func resume_level() -> Dictionary:
	var levels = list_puzzles()
	for data in levels:
		if data.id == campaign.get("current_level", "") and unlocked(data, levels): return data
	for data in levels:
		if chapter_for(data).id == campaign.get("current_chapter", "") and unlocked(data, levels) and not completed(data.id): return data
	return {}

func next_level(data: Dictionary) -> Dictionary:
	var levels = list_puzzles()
	var chapter = chapter_for(data)
	var after = false
	for level in levels:
		if chapter_for(level).id != chapter.id: continue
		if after: return level if unlocked(level, levels) else {}
		if level.id == data.id: after = true
	# Optional chapters join the main route; main chapters advance by chapter order.
	for candidate in list_chapters(levels):
		if candidate.get("optional", false): continue
		if not chapter.get("optional", false) and int(candidate.get("order", 1)) <= int(chapter.get("order", 1)): continue
		if not chapter_unlocked(candidate): continue
		for level in levels:
			if chapter_for(level).id == candidate.id and unlocked(level, levels) and not completed(level.id): return level
		if chapter_progress(candidate.id, levels).total == 0:
			campaign.current_chapter = candidate.id
			campaign.current_level = ""
			return {}
	return {}

func complete(data: Dictionary, seconds: float, count: int) -> void:
	var previous: Dictionary = progress.get(data.id, {})
	progress[data.id] = previous.duplicate(true)
	progress[data.id].merge({"completed": true, "revision": data.get("revision", 1), "best_time": minf(seconds, float(previous.get("best_time", INF))), "fewest_pieces": mini(count, int(previous.get("fewest_pieces", 99999)))}, true)
	var awards: Array = previous.get("awards", []).duplicate()
	var goals: Dictionary = data.get("awards", {})
	if float(goals.get("time", 0)) > 0 and seconds <= float(goals.time) and "time" not in awards: awards.append("time")
	if int(goals.get("pieces", 0)) > 0 and count <= int(goals.pieces) and "pieces" not in awards: awards.append("pieces")
	progress[data.id].awards = awards
	write(progress_path, progress)
	var next = next_level(data)
	if not next.is_empty():
		campaign.current_level = next.id
		campaign.current_chapter = chapter_for(next).id
	else:
		campaign.current_level = ""
	write(campaign_state_path, campaign)

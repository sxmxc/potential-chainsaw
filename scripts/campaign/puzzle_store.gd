class_name PuzzleStore
extends RefCounted

var drafts_directory: String = SavePaths.resolve("user://puzzles/drafts")
var published_directory: String = SavePaths.resolve("user://puzzles/published")
var community_directory: String = SavePaths.resolve("user://puzzles/community")
var community_progress_path: String = SavePaths.resolve("user://community_progress.json")
var community_progress: Dictionary = {}
var manifest_path: String = "res://resources/campaign_manifest.json"
var chapters_path: String = CHAPTERS
var campaign_directory: String = "res://resources/campaign"
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
	DirAccess.make_dir_recursive_absolute(community_directory)
	var local_progress = JSON.parse_string(FileAccess.get_file_as_string(community_progress_path)) if FileAccess.file_exists(community_progress_path) else null
	if local_progress is Dictionary: community_progress = local_progress
	var saved = JSON.parse_string(FileAccess.get_file_as_string(progress_path)) if FileAccess.file_exists(progress_path) else null
	if saved is Dictionary: progress = saved
	var state = JSON.parse_string(FileAccess.get_file_as_string(campaign_state_path)) if FileAccess.file_exists(campaign_state_path) else null
	if state is Dictionary:
		campaign = state
	elif not progress.is_empty():
		# Legacy progress remains in place, including IDs, records, and awards.
		campaign = {"version": 1, "started": true, "introduction_skipped": false}
		var definition := load_campaign()
		for data in definition.levels:
			if not completed(data.id) and definition.unlocked(data, progress):
				campaign.current_level = data.id
				campaign.current_chapter = definition.chapter_for(data).id
				break
		if not campaign.has("current_chapter"): campaign.current_chapter = definition.first_chapter(false).get("id", "")

func create() -> Dictionary:
	return {"version": 2, "environment_instances": [], "id": "puzzle-" + Crypto.new().generate_random_bytes(8).hex_encode(), "revision": 1, "name": "New puzzle", "description": "Deliver the marble to the collector.", "creator": "", "difficulty": "Workshop", "pieces": [], "permissions": {}, "inventory": {}, "bounds": [-12, -12, 12, 12, 0, 12], "restricted_zones": [], "objectives": [], "hints": [], "camera": {}, "awards": {}, "solution": [], "validation": {}, "status": "draft"}

func fingerprint(data: Dictionary) -> String:
	var content = data.duplicate(true)
	for key in ["solution", "validation", "status", "modified", "campaign", "_source", "required_assets"]: content.erase(key)
	if not data.get("environment_instances", []).is_empty(): content["environment_signature"] = PuzzleEnvironment.definition_signature(data)
	if content.get("environment_instances", []).is_empty(): content.erase("environment_instances")
	# Canonicalize the numeric types and precision produced by JSON persistence.
	return JSON.stringify(JSON.parse_string(JSON.stringify(content)), "", true, true).sha256_text()

func validate(data: Dictionary, check_solution: bool = false) -> Array[String]:
	var errors := shape_errors(data)
	if not errors.is_empty(): return errors
	for id in data.get("inventory", {}).keys() + data.get("configuration_limits", {}).keys():
		if not PieceCatalog.REGISTRY.has_string_id(StringName(id)): errors.append("Unknown catalog piece: " + id)
	for item in data.get("pieces", []) + data.get("solution", []):
		# Resolve only registered pieces.
		if not PieceCatalog.REGISTRY.has_string_id(StringName(item.piece)): errors.append("Unknown catalog piece: " + item.piece)
		else:
			var definition := catalog.get_piece(item.piece)
			if definition.authoring_only: errors.append("Scenery must use environment placements: " + item.piece)
			for setting in definition.settings:
				if not item.get("config", {}).has(setting.key): continue
				var value = item.config[setting.key]
				if (setting.kind == PieceSetting.Kind.NUMBER and not number(value)) or (setting.kind == PieceSetting.Kind.FLAG and not value is bool) or (setting.kind == PieceSetting.Kind.STRING and not value is String): errors.append("Invalid setting: " + String(setting.key))
	for id in data.get("required_assets", []):
		if not PieceCatalog.REGISTRY.has_string_id(StringName(id)): errors.append("Missing required asset: " + id)
	if not errors.is_empty(): return errors
	var environment = PuzzleEnvironment.inspect_definition(data)
	for error in environment.errors: errors.append(str(error))
	if not SavePaths.valid_id(data.id): errors.append("Invalid puzzle ID")
	if str(data.get("name", "")).strip_edges().is_empty(): errors.append("A puzzle needs a name")
	var by_id: Dictionary = {}
	var starts = 0
	for piece in data.get("pieces", []):
		if by_id.has(piece.uid): errors.append("Duplicate piece ID")
		by_id[piece.uid] = piece
		var definition = catalog.get_piece(piece.piece)
		if not definition: errors.append("Unknown piece: " + piece.piece)
		elif definition.has_behavior(MarbleRelease): starts += 1
		if definition:
			definition = definition.configured(piece.get("config", {}))
			if SnapManager.intersects_solids(definition, Transform3D(Basis(Vector3.UP, int(piece.rotation) * PI / 2), Vector3(piece.position[0], piece.position[1], piece.position[2])), environment.solids): errors.append("Starting piece intersects environment: " + piece.uid)
	if starts == 0: errors.append("Place a marble release")
	if data.get("objectives", []).is_empty(): errors.append("Add a completion objective")
	for objective in data.get("objectives", []):
		if not by_id.has(objective.get("target", "")): errors.append("Objective target is missing")
		elif objective.get("type", "deliver") == "deliver" and catalog.get_piece(by_id[objective.target].piece) and not catalog.get_piece(by_id[objective.target].piece).has_behavior(MarbleCollector): errors.append("Delivery objective needs a collector")
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
	# Draft edits may invalidate the preserved solution; only distribution checks
	# require that solution to obey the current player rules.
	if check_solution and errors.is_empty() and not data.get("solution", []).is_empty():
		var problem := PuzzleRules.new(data, catalog, environment.solids).validate(data.solution)
		if not problem.is_empty(): errors.append(problem)
	return errors

# Check JSON types before any engine/resource operation. Unknown fields cannot
# introduce resource loading; scene-bearing fields are blocked for community data.
func shape_errors(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in ["environment", "environment_placement", "environment_snapshot"]:
		if data.has(key): errors.append("Scene-based scenery is no longer supported; rebuild this puzzle with catalog pieces")
	for key in ["id", "name", "version", "pieces"]:
		if not data.has(key): errors.append("Missing puzzle field: " + key)
	for key in ["version", "revision", "time_limit"]:
		if data.has(key) and not number(data[key]): errors.append("Invalid number: " + key)
	for key in ["id", "name", "description", "creator", "difficulty", "status"]:
		if data.has(key) and not data[key] is String: errors.append("Invalid text: " + key)
	for key in ["pieces", "solution", "environment_instances", "objectives", "restricted_zones", "hints", "required_assets"]:
		if not data.get(key, []) is Array or data.get(key, []).size() > 5000: errors.append("Invalid list: " + key)
	for key in ["inventory", "permissions", "configuration_limits", "camera", "awards", "validation", "campaign"]:
		if not data.get(key, {}) is Dictionary: errors.append("Invalid object: " + key)
	if not numeric_array(data.get("bounds"), 6): errors.append("Invalid build bounds")
	if not errors.is_empty(): return errors
	if int(data.version) not in [1, 2] or float(data.version) != int(data.version): errors.append("Unsupported puzzle version")
	for key in ["pieces", "solution"]:
		for item in data.get(key, []):
			if not item is Dictionary or not item.get("uid") is String or not item.get("piece") is String or not numeric_array(item.get("position"), 3) or not number(item.get("rotation")) or not item.get("config", {}) is Dictionary:
				errors.append("Invalid construction record")
				continue
			var config: Dictionary = item.get("config", {})
			if config.has("release_speed") and not number(config.release_speed): errors.append("Invalid release speed")
			if float(item.rotation) != int(item.rotation) or int(item.rotation) not in [0, 1, 2, 3]: errors.append("Invalid piece rotation")
			for value in config.values():
				if not (value is String or value is bool or number(value) or value is Array): errors.append("Invalid mechanism configuration")
			if not config.get("links", []) is Array: errors.append("Invalid mechanism links"); continue
			for link in config.get("links", []):
				if not link is Dictionary or not link.get("target") is String or not link.get("event") is String or not link.get("action") is String: errors.append("Invalid mechanism link")
	for item in data.get("environment_instances", []):
		if not item is Dictionary or not item.get("uid") is String or not numeric_array(item.get("position"), 3) or not number(item.get("rotation")) or item.has("scene") or not item.get("asset") is String: errors.append("Invalid scenery record")
	for objective in data.get("objectives", []):
		if not objective is Dictionary: errors.append("Invalid objective"); continue
		for key in ["target", "source", "type", "event"]:
			if objective.has(key) and not objective[key] is String: errors.append("Invalid objective " + key)
		for key in ["count", "time_limit"]:
			if objective.has(key) and not number(objective[key]): errors.append("Invalid objective " + key)
	for zone in data.get("restricted_zones", []):
		if not numeric_array(zone, 6): errors.append("Invalid restricted region")
	for value in data.get("hints", []) + data.get("required_assets", []):
		if not value is String: errors.append("Invalid text list")
	for count in data.get("inventory", {}).values():
		if not number(count): errors.append("Invalid inventory count")
	for permission in data.get("permissions", {}).values():
		if not permission is Dictionary: errors.append("Invalid permissions"); continue
		if not permission.get("config_keys", []) is Array: errors.append("Invalid permitted settings")
		if not valid_limits(permission.get("limits", {})): errors.append("Invalid permission limits")
	for limits in data.get("configuration_limits", {}).values():
		if not valid_limits(limits): errors.append("Invalid configuration limits")
	var camera: Dictionary = data.get("camera", {})
	if not camera.is_empty():
		if not numeric_array(camera.get("focus"), 3): errors.append("Invalid camera focus")
		for key in ["yaw", "pitch", "distance"]:
			if not number(camera.get(key)): errors.append("Invalid camera " + key)
	for value in data.get("awards", {}).values():
		if not number(value): errors.append("Invalid award")
	var proof: Dictionary = data.get("validation", {})
	if proof.has("physics_success") and not proof.physics_success is bool: errors.append("Invalid validation result")
	if proof.has("fingerprint") and not proof.fingerprint is String: errors.append("Invalid validation fingerprint")
	return errors

func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func numeric_array(value: Variant, size: int) -> bool:
	return value is Array and value.size() == size and value.all(func(item): return number(item) and absf(float(item)) <= 1000)

func valid_limits(value: Variant) -> bool:
	if not value is Dictionary: return false
	for limits in value.values():
		if not numeric_array(limits, 2) or limits[0] > limits[1]: return false
	return true

func write(path: String, data: Dictionary) -> bool:
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file: last_error = "Could not write " + path; return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK: last_error = "Could not finish saving"; return false
	return true

func save_draft(data: Dictionary) -> bool:
	if not SavePaths.valid_id(str(data.get("id", ""))): return false
	var draft := data.duplicate(true)
	draft.erase("_source")
	return write(drafts_directory + "/" + data.id + ".json", draft)

# Only this loader assigns provenance. File properties never select a distribution.
func load_puzzle(path: String, source: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file or file.get_length() > 5000000:
		last_error = "Puzzle file is missing or too large"
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		last_error = "Invalid puzzle JSON"
		return {}
	var data: Dictionary = parsed
	var shape := shape_errors(data)
	if not shape.is_empty(): last_error = "\n".join(shape); return {}
	data.erase("_source")
	if source == "community":
		var errors := validate(data, true)
		if not errors.is_empty():
			last_error = "\n".join(errors)
			return {}
	# Legacy embedded registration becomes draft-only metadata. Preserve valid proof.
	var previous_fingerprint := fingerprint(data)
	var registration: Dictionary = data.get("campaign", {}).duplicate(true)
	if source != "community" and (data.has("chapter") or data.has("order") or data.has("prerequisites")):
		registration = {"chapter": CampaignDefinition.new(base_chapters(), []).chapter_for(data), "order": data.get("order", 1), "prerequisites": data.get("campaign", {}).get("prerequisites", data.get("prerequisites", []))}
	for key in ["chapter", "order", "prerequisites", "campaign"]: data.erase(key)
	if data.get("validation", {}).get("fingerprint", "") == previous_fingerprint:
		data.validation.fingerprint = fingerprint(data)
	if source != "community" and not registration.is_empty(): data.campaign = registration
	data._source = source
	return data

func publication_errors(data: Dictionary) -> Array[String]:
	var errors := validate(data, true)
	if not errors.is_empty(): return errors
	if data.get("solution", []).is_empty() or data.get("validation", {}).get("fingerprint", "") != fingerprint(data) or not data.get("validation", {}).get("physics_success", false):
		errors.append("Test this revision successfully as a player and preserve the solution first")
	return errors

func playable_content(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	for key in ["chapter", "order", "prerequisites", "campaign", "_source"]: result.erase(key)
	return result

func publish(data: Dictionary) -> bool:
	var errors := publication_errors(data)
	if not errors.is_empty(): last_error = "\n".join(errors); return false
	var published := playable_content(data)
	published.status = "published"
	published.required_assets = required_assets(published)
	return write(published_directory.path_join(data.id + ".json"), published)

func can_add_to_campaign() -> bool:
	return OS.has_feature("editor") and FileAccess.file_exists("res://project.godot")

# Project-only promotion keeps registration separate from playable JSON.
func add_to_campaign(data: Dictionary) -> bool:
	if not can_add_to_campaign(): last_error = "Campaign publishing is available only in the Godot project"; return false
	var errors := publication_errors(data)
	var registration: Dictionary = data.get("campaign", {})
	var chapter: Dictionary = registration.get("chapter", {})
	if not SavePaths.valid_id(str(chapter.get("id", ""))) or str(chapter.get("name", "")).strip_edges().is_empty(): errors.append("Choose a campaign chapter")
	if int(registration.get("order", 0)) < 1: errors.append("Level order must be positive")
	if not registration.get("prerequisites", []) is Array or not chapter.get("prerequisites", []) is Array: errors.append("Unlock requirements must be lists")
	if chapter.get("introduction", false) and not chapter.get("optional", false): errors.append("Introduction must be optional")
	if not errors.is_empty(): last_error = "\n".join(errors); return false
	var manifest := campaign_manifest()
	var entries: Array = manifest.get("puzzles", [])
	var target := campaign_directory.path_join(data.id + ".json")
	var existing: Dictionary = {}
	for entry in entries:
		if entry.id == data.id: existing = entry; target = entry.path
	if existing.is_empty() and FileAccess.file_exists(target): last_error = "An unregistered file already uses this ID"; return false
	if not existing.is_empty():
		var old := load_puzzle(target, "campaign")
		if old.is_empty(): return false
		if fingerprint(old) != fingerprint(data) and int(data.get("revision", 1)) <= int(old.get("revision", 1)):
			last_error = "This campaign revision already exists; reopen it before revising"
			return false
	var published := playable_content(data)
	published.status = "published"
	published.required_assets = required_assets(published)
	var entry := {"id": data.id, "path": target, "chapter": chapter.id, "order": registration.order, "prerequisites": registration.get("prerequisites", [])}
	if not existing.is_empty(): entries.erase(existing)
	entries.append(entry)
	manifest.puzzles = entries
	var chapters := base_chapters()
	var replaced := false
	for index in chapters.size():
		if chapters[index].id == chapter.id:
			var merged := chapters[index].duplicate(true)
			merged.merge(chapter, true)
			chapters[index] = merged
			replaced = true
	if not replaced: chapters.append(chapter.duplicate(true))
	# Membership belongs to registration, including moves between chapters.
	for item in chapters:
		item.levels = []
		for registered in entries:
			if registered.chapter == item.id: item.levels.append(registered.id)
	# Commit content before registration; roll back file bytes on any failure.
	var backups: Dictionary = {}
	for path in [target, chapters_path, manifest_path]:
		backups[path] = null
		if FileAccess.file_exists(path):
			backups[path] = FileAccess.get_file_as_bytes(path)
	if not write(target, published) or not write(chapters_path, {"version": 1, "chapters": chapters}) or not write(manifest_path, manifest):
		for path in backups:
			if backups[path] == null: DirAccess.remove_absolute(path)
			else:
				var original := FileAccess.open(path, FileAccess.WRITE)
				if original: original.store_buffer(backups[path])
		return false
	return true

func campaign_manifest() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) if FileAccess.file_exists(manifest_path) else null
	return data if data is Dictionary else {"version": 1, "puzzles": []}

func list_drafts() -> Array[Dictionary]:
	var by_id: Dictionary = {}
	for filename in DirAccess.get_files_at(drafts_directory):
		if not filename.ends_with(".json"): continue
		var data := load_puzzle(drafts_directory.path_join(filename), "draft")
		if not data.is_empty(): by_id[data.id] = data
	return CampaignDefinition.new(base_chapters(), by_id.values()).levels

func load_campaign() -> CampaignDefinition:
	var chapters := base_chapters()
	var by_id: Dictionary = {}
	for entry in campaign_manifest().get("puzzles", []):
		var data := load_puzzle(entry.path, "campaign")
		if data.is_empty() or data.get("status") != "published" or data.id != entry.id: continue
		var chapter: Dictionary = {}
		for candidate in chapters:
			if candidate.id == entry.chapter: chapter = candidate
		if chapter.is_empty(): continue
		data.campaign = {"chapter": chapter, "order": entry.order, "prerequisites": entry.get("prerequisites", [])}
		if entry.has("legacy_chapter"): data.campaign.legacy_chapter = entry.legacy_chapter.duplicate(true)
		by_id[data.id] = data
	return CampaignDefinition.new(chapters, by_id.values())

func list_community() -> Array[Dictionary]:
	var by_id: Dictionary = {}
	for directory in [published_directory, community_directory]:
		for filename in DirAccess.get_files_at(directory):
			if not filename.ends_with(".json"): continue
			var data := load_puzzle(directory.path_join(filename), "local" if directory == published_directory else "community")
			if not data.is_empty() and data.get("status") == "published" and not by_id.has(data.id): by_id[data.id] = data
	var result: Array[Dictionary] = []
	for data in by_id.values(): result.append(data)
	result.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return result

func is_official(data: Dictionary) -> bool:
	return data.get("_source", "") == "campaign"

func export_puzzle(data: Dictionary, path: String) -> bool:
	var published_path := published_directory.path_join(str(data.get("id", "")) + ".json")
	if not SavePaths.valid_id(str(data.get("id", ""))) or not FileAccess.file_exists(published_path): last_error = "Publish locally before exporting"; return false
	var published := load_puzzle(published_path, "community")
	if published.is_empty(): return false
	return write(path, playable_content(published))

func import_puzzle(path: String) -> Dictionary:
	var data := load_puzzle(path, "community")
	if data.is_empty(): return {}
	# Imported proof records the author's run. Resource hashes differ between a
	# project and its compiled export; safety and solution rules are checked above.
	if data.get("status") != "published" or not data.get("validation", {}).get("physics_success", false) or data.get("solution", []).is_empty():
		last_error = "Import a published puzzle with a tested solution"
		return {}
	# Identity is retained. Conflicting copies are rejected, never renamed or overwritten.
	for directory in [drafts_directory, published_directory, community_directory]:
		var existing_path: String = directory.path_join(data.id + ".json")
		if not FileAccess.file_exists(existing_path): continue
		var existing := load_puzzle(existing_path, "community")
		if existing.is_empty() or fingerprint(existing) != fingerprint(data):
			last_error = "A different puzzle or draft already uses this ID"
			return {}
	var installed := playable_content(data)
	installed.erase("campaign")
	if not write(community_directory.path_join(data.id + ".json"), installed): return {}
	return load_puzzle(community_directory.path_join(data.id + ".json"), "community")

func required_assets(data: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for item in data.get("pieces", []) + data.get("solution", []):
		if item.piece not in ids: ids.append(item.piece)
	for id in data.get("inventory", {}):
		if id not in ids: ids.append(id)
	for item in data.get("environment_instances", []):
		if item.has("asset") and "environment:" + item.asset not in ids: ids.append("environment:" + item.asset)
	ids.sort()
	return ids

func completed(id: String) -> bool:
	return progress.get(id, {}).get("completed", false)

func base_chapters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var data = JSON.parse_string(FileAccess.get_file_as_string(chapters_path))
	if data is Dictionary:
		for chapter in data.get("chapters", []): result.append(chapter)
	result.sort_custom(func(a, b): return int(a.get("order", 1)) < int(b.get("order", 1)))
	return result

func start_campaign(play_introduction: bool) -> Dictionary:
	var definition := load_campaign()
	var chapter := definition.first_chapter(play_introduction)
	campaign = {"version": 1, "started": true, "introduction_skipped": not play_introduction, "current_chapter": chapter.get("id", ""), "current_level": ""}
	var target := definition.resume_level(campaign, progress)
	if not target.is_empty(): campaign.current_level = target.id
	write(campaign_state_path, campaign)
	return target

func remember_level(data: Dictionary) -> void:
	if not is_official(data): return
	if not campaign.get("started", false):
		campaign = {"version": 1, "started": true, "introduction_skipped": false}
	var chapter: Dictionary = data.campaign.chapter
	campaign.current_level = data.id
	campaign.current_chapter = chapter.id
	campaign["introduction_level" if chapter.get("introduction", false) else "main_level"] = data.id
	write(campaign_state_path, campaign)

func complete(data: Dictionary, seconds: float, count: int) -> void:
	var records := progress if is_official(data) else community_progress
	var previous: Dictionary = records.get(data.id, {})
	records[data.id] = previous.duplicate(true)
	records[data.id].merge({"completed": true, "revision": data.get("revision", 1), "best_time": minf(seconds, float(previous.get("best_time", INF))), "fewest_pieces": mini(count, int(previous.get("fewest_pieces", 99999)))}, true)
	var awards: Array = previous.get("awards", []).duplicate()
	var goals: Dictionary = data.get("awards", {})
	if float(goals.get("time", 0)) > 0 and seconds <= float(goals.time) and "time" not in awards: awards.append("time")
	if int(goals.get("pieces", 0)) > 0 and count <= int(goals.pieces) and "pieces" not in awards: awards.append("pieces")
	records[data.id].awards = awards
	write(progress_path if is_official(data) else community_progress_path, records)
	if not is_official(data): return
	var step := load_campaign().next_step(data, progress)
	campaign.current_level = step.level.get("id", "")
	campaign.current_chapter = step.chapter.get("id", campaign.get("current_chapter", ""))
	write(campaign_state_path, campaign)

class_name PuzzleStore
extends RefCounted

var drafts_directory: String = SavePaths.resolve("user://puzzles/drafts")
var published_directory: String = SavePaths.resolve("user://puzzles/published")
var community_directory: String = SavePaths.resolve("user://puzzles/community")
var manifest_path: String = "res://resources/campaign_manifest.json"
var chapters_path: String = CHAPTERS
var campaign_directory: String = "res://resources/campaign"
const CHAPTERS = "res://resources/campaign_chapters.json"
var catalog: PieceCatalog
var last_error: String = ""

func _init(definitions: PieceCatalog) -> void:
	catalog = definitions
	DirAccess.make_dir_recursive_absolute(drafts_directory)
	DirAccess.make_dir_recursive_absolute(published_directory)
	DirAccess.make_dir_recursive_absolute(community_directory)

func create() -> Dictionary:
	return {"version": 2, "environment_instances": [], "id": "puzzle-" + Crypto.new().generate_random_bytes(8).hex_encode(), "revision": 1, "name": "New puzzle", "description": "Deliver the marble to the collector.", "creator": "", "difficulty": "Workshop", "pieces": [], "permissions": {}, "inventory": {}, "bounds": [-12, -12, 12, 12, 0, 12], "restricted_zones": [], "objectives": [], "hints": [], "camera": {}, "awards": {}, "solution": [], "validation": {}, "status": "draft"}

func fingerprint(data: Dictionary) -> String:
	var content = data.duplicate(true)
	for key in ["solution", "validation", "status", "modified", "campaign", "_source", "required_assets"]: content.erase(key)
	if not data.get("environment_instances", []).is_empty(): content["environment_signature"] = PuzzleEnvironment.definition_signature(data)
	if content.get("environment_instances", []).is_empty(): content.erase("environment_instances")
	# Canonicalize the numeric types and precision produced by JSON persistence.
	return JSON.stringify(JSON.parse_string(JSON.stringify(content)), "", true, true).sha256_text()

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
	return decode_puzzle(parsed, source)

func decode_puzzle(value: Dictionary, source: String) -> Dictionary:
	var data := value.duplicate(true)
	var shape := PuzzleRules.shape_errors(data)
	if not shape.is_empty(): last_error = "\n".join(shape); return {}
	data.erase("_source")
	if source == "community":
		var errors := PuzzleRules.definition_errors(data, catalog, true)
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
	var errors := PuzzleRules.definition_errors(data, catalog, true)
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

static func is_official(data: Dictionary) -> bool:
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
	return install_community(data)

# JSON imports and network downloads share validation, conflict checks and storage.
func install_community(value: Dictionary) -> Dictionary:
	if JSON.stringify(value).to_utf8_buffer().size() > 5000000:
		last_error = "Puzzle is too large"
		return {}
	var data := decode_puzzle(value, "community")
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

func base_chapters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var data = JSON.parse_string(FileAccess.get_file_as_string(chapters_path))
	if data is Dictionary:
		for chapter in data.get("chapters", []): result.append(chapter)
	result.sort_custom(func(a, b): return int(a.get("order", 1)) < int(b.get("order", 1)))
	return result

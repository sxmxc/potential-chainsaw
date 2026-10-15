class_name PuzzleProgress
extends RefCounted

# Player state is independent of the puzzle library and publication lifecycle.
var progress_path: String = SaveStorage.resolve("user://campaign_progress.json")
var campaign_state_path: String = SaveStorage.resolve("user://campaign_state.json")
var community_progress_path: String = SaveStorage.resolve("user://community_progress.json")
var records: Dictionary = {}
var community_records: Dictionary = {}
var route: Dictionary = {}
var last_error: String = ""

func _init(definition: CampaignDefinition) -> void:
	var local_progress = JSON.parse_string(FileAccess.get_file_as_string(community_progress_path)) if FileAccess.file_exists(community_progress_path) else null
	if local_progress is Dictionary: community_records = local_progress
	var saved = JSON.parse_string(FileAccess.get_file_as_string(progress_path)) if FileAccess.file_exists(progress_path) else null
	if saved is Dictionary: records = saved
	var state = JSON.parse_string(FileAccess.get_file_as_string(campaign_state_path)) if FileAccess.file_exists(campaign_state_path) else null
	if state is Dictionary:
		route = state
	elif not records.is_empty():
		# Legacy progress remains in place, including IDs, records, and awards.
		route = {"version": 1, "started": true, "introduction_skipped": false}
		for data in definition.levels:
			if not records.get(data.id, {}).get("completed", false) and definition.unlocked(data, records):
				route.current_level = data.id
				route.current_chapter = definition.chapter_for(data).id
				break
		if not route.has("current_chapter"): route.current_chapter = definition.first_chapter(false).get("id", "")

func start_campaign(definition: CampaignDefinition, play_introduction: bool) -> Dictionary:
	var chapter := definition.first_chapter(play_introduction)
	route = {"version": 1, "started": true, "introduction_skipped": not play_introduction, "current_chapter": chapter.get("id", ""), "current_level": ""}
	var target := definition.resume_level(route, records)
	if not target.is_empty(): route.current_level = target.id
	last_error = SaveStorage.write_json(campaign_state_path, route)
	return target

func remember_level(data: Dictionary) -> void:
	if not PuzzleStore.is_official(data): return
	if not route.get("started", false):
		route = {"version": 1, "started": true, "introduction_skipped": false}
	var chapter: Dictionary = data.campaign.chapter
	route.current_level = data.id
	route.current_chapter = chapter.id
	route["introduction_level" if chapter.get("introduction", false) else "main_level"] = data.id
	last_error = SaveStorage.write_json(campaign_state_path, route)

func complete(data: Dictionary, seconds: float, count: int, definition: CampaignDefinition) -> void:
	var results := records if PuzzleStore.is_official(data) else community_records
	var previous: Dictionary = results.get(data.id, {})
	results[data.id] = previous.duplicate(true)
	results[data.id].merge({"completed": true, "revision": data.get("revision", 1), "best_time": minf(seconds, float(previous.get("best_time", INF))), "fewest_pieces": mini(count, int(previous.get("fewest_pieces", 99999)))}, true)
	var awards: Array = previous.get("awards", []).duplicate()
	var goals: Dictionary = data.get("awards", {})
	if float(goals.get("time", 0)) > 0 and seconds <= float(goals.time) and "time" not in awards: awards.append("time")
	if int(goals.get("pieces", 0)) > 0 and count <= int(goals.pieces) and "pieces" not in awards: awards.append("pieces")
	results[data.id].awards = awards
	last_error = SaveStorage.write_json(progress_path if PuzzleStore.is_official(data) else community_progress_path, results)
	if not PuzzleStore.is_official(data): return
	var step := definition.next_step(data, results)
	route.current_level = step.level.get("id", "")
	route.current_chapter = step.chapter.get("id", route.get("current_chapter", ""))
	var route_error := SaveStorage.write_json(campaign_state_path, route)
	if last_error.is_empty(): last_error = route_error

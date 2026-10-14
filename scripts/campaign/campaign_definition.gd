class_name CampaignDefinition
extends RefCounted

# One loaded campaign. Queries read only this content and the supplied progress;
# they neither load files nor change the player's saved route.
var levels: Array[Dictionary] = []
var chapters: Array[Dictionary] = []

func _init(chapter_definitions: Array, puzzle_definitions: Array) -> void:
	chapters.assign(chapter_definitions)
	levels.assign(puzzle_definitions)
	var by_id: Dictionary = {}
	for chapter in chapters: by_id[chapter.id] = chapter
	for data in levels:
		var chapter := chapter_for(data)
		by_id[chapter.id] = chapter
	chapters.assign(by_id.values())
	chapters.sort_custom(func(a, b):
		if int(a.get("order", 1)) != int(b.get("order", 1)): return int(a.get("order", 1)) < int(b.get("order", 1))
		return str(a.id) < str(b.id))
	levels.sort_custom(func(a, b):
		var ca := chapter_for(a)
		var cb := chapter_for(b)
		if int(ca.get("order", 1)) != int(cb.get("order", 1)): return int(ca.get("order", 1)) < int(cb.get("order", 1))
		if ca.id != cb.id: return str(ca.id) < str(cb.id)
		if level_order(a) != level_order(b): return level_order(a) < level_order(b)
		return str(a.id) < str(b.id))

static func level_order(data: Dictionary) -> int:
	return int(data.get("campaign", {}).get("order", data.get("order", 1)))

func chapter_for(data: Dictionary) -> Dictionary:
	var metadata: Dictionary = data.get("campaign", {}).get("chapter", data.get("chapter", {}))
	for chapter in chapters:
		if metadata.get("id", "") == chapter.id or (metadata.is_empty() and data.get("id", "") in chapter.get("levels", [])):
			var result := chapter.duplicate(true)
			result.merge(metadata, true)
			return result
	return metadata if not metadata.is_empty() else first_chapter(false)

func first_chapter(introduction: bool) -> Dictionary:
	for chapter in chapters:
		if bool(chapter.get("introduction", false)) == introduction: return chapter.duplicate(true)
	return {}

func requirement_completed(id: String, progress: Dictionary) -> bool:
	# Optional Introduction never gates the main route, including legacy requirements.
	for chapter in chapters:
		if chapter.get("introduction", false) and id in chapter.get("levels", []): return true
	for level in levels:
		if level.id == id and chapter_for(level).get("introduction", false): return true
	return progress.get(id, {}).get("completed", false)

func chapter_unlocked(chapter: Dictionary, progress: Dictionary) -> bool:
	if chapter.get("introduction", false): return true
	for id in chapter.get("prerequisites", []):
		if not requirement_completed(id, progress): return false
	return true

func unlocked(data: Dictionary, progress: Dictionary) -> bool:
	if progress.get(data.id, {}).get("completed", false): return true
	var chapter := chapter_for(data)
	if chapter.get("introduction", false): return true
	if not chapter_unlocked(chapter, progress): return false
	var requirements: Array = data.get("campaign", {}).get("prerequisites", data.get("prerequisites", []))
	for id in requirements:
		if not requirement_completed(id, progress): return false
	if not requirements.is_empty(): return true
	var previous: Dictionary = {}
	for level in levels:
		if chapter_for(level).id != chapter.id: continue
		if level.id == data.id: return previous.is_empty() or progress.get(previous.id, {}).get("completed", false)
		previous = level
	return false

func chapter_progress(id: String, progress: Dictionary) -> Dictionary:
	var total := 0
	var done := 0
	for data in levels:
		if chapter_for(data).id != id: continue
		total += 1
		if progress.get(data.id, {}).get("completed", false): done += 1
	return {"completed": done, "total": total}

func resume_level(route: Dictionary, progress: Dictionary) -> Dictionary:
	for data in levels:
		if data.id == route.get("current_level", "") and unlocked(data, progress): return data
	for data in levels:
		if chapter_for(data).id == route.get("current_chapter", "") and unlocked(data, progress) and not progress.get(data.id, {}).get("completed", false): return data
	return {}

# Return the destination explicitly, including an empty chapter. Reading Next
# must never move the saved route; PuzzleStore applies it when recording a win.
func next_step(data: Dictionary, progress: Dictionary) -> Dictionary:
	var chapter := chapter_for(data)
	var after := false
	for level in levels:
		if chapter_for(level).id != chapter.id: continue
		if after: return {"level": level if unlocked(level, progress) else {}, "chapter": chapter}
		if level.id == data.id: after = true
	for candidate in chapters:
		if candidate.get("optional", false): continue
		if not chapter.get("optional", false) and int(candidate.get("order", 1)) <= int(chapter.get("order", 1)): continue
		if not chapter_unlocked(candidate, progress): continue
		for level in levels:
			if chapter_for(level).id == candidate.id and unlocked(level, progress) and not progress.get(level.id, {}).get("completed", false): return {"level": level, "chapter": candidate}
		if chapter_progress(candidate.id, progress).total == 0: return {"level": {}, "chapter": candidate}
	return {"level": {}, "chapter": chapter}

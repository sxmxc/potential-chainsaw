extends Window

var session: PuzzleSession
var editing: bool = false
var levels: Array[Dictionary] = []
var all_levels: Array[Dictionary] = []
var chapters: Array[Dictionary] = []

func configure(value: PuzzleSession) -> void:
	session = value
	close_requested.connect(hide)
	%Back.pressed.connect(hide)
	%Open.pressed.connect(open_selected)
	%Levels.item_activated.connect(func(_index): open_selected())
	%Chapters.item_selected.connect(show_chapter)
	%PlayIntroduction.pressed.connect(func(): start_campaign(true))
	%SkipIntroduction.pressed.connect(func(): start_campaign(false))
	%Resume.pressed.connect(resume_campaign)
	%Levels.item_selected.connect(func(index):
		%Details.text = levels[index].description
		%Open.disabled = not editing and not session.store.unlocked(levels[index], all_levels))

func open_campaign() -> void:
	if session.store.campaign.get("started", false):
		resume_campaign()
	else:
		open()
		%StartChoice.show()
		%Heading.text = "NEW CAMPAIGN · Introduction is optional"

func start_campaign(play_introduction: bool) -> void:
	var target = session.store.start_campaign(play_introduction)
	if not target.is_empty():
		hide()
		session.player(target)
	else: open()

func resume_campaign() -> void:
	var target = session.store.resume_level()
	if target.is_empty(): open(); return
	hide()
	session.player(target)

func open(editor_mode: bool = false) -> void:
	editing = editor_mode
	title = "Open a puzzle" if editing else "Campaign · Level Select"
	%Heading.text = "PUZZLE LIBRARY" if editing else "CAMPAIGN · choose a chapter"
	%StartChoice.hide()
	%Resume.visible = not editing and session.store.campaign.get("started", false)
	%Open.text = "Edit selected puzzle" if editing else "Play selected puzzle"
	all_levels = session.store.list_puzzles()
	if editing:
		var drafts = session.store.list_puzzles(true)
		var ids: Array = []
		for data in drafts: ids.append(data.id)
		for i in range(all_levels.size() - 1, -1, -1):
			if all_levels[i].id in ids: all_levels.remove_at(i)
		all_levels.append_array(drafts)
	chapters = session.store.list_chapters(all_levels)
	%Chapters.clear()
	var selected = 0
	for i in chapters.size():
		var chapter = chapters[i]
		var counts = session.store.chapter_progress(chapter.id, all_levels)
		%Chapters.add_item("%s%s · %d / %d complete" % [chapter.name, " (optional)" if chapter.get("optional", false) else "", counts.completed, counts.total])
		if chapter.id == session.store.campaign.get("current_chapter", ""): selected = i
	if not chapters.is_empty():
		%Chapters.select(selected)
		show_chapter(selected)
	popup_centered(Vector2i(620, 620))

func show_chapter(index: int) -> void:
	var chapter = chapters[index]
	levels.clear()
	for data in all_levels:
		if session.store.chapter_for(data).id == chapter.id: levels.append(data)
	levels.sort_custom(func(a, b):
		if int(a.order) != int(b.order): return int(a.order) < int(b.order)
		return str(a.id) < str(b.id))
	%Levels.clear()
	for data in levels:
		var status = "Draft" if data.status != "published" else ("Complete" if session.store.completed(data.id) else ("Ready" if session.store.unlocked(data, all_levels) else "Locked"))
		var awards: Array = session.store.progress.get(data.id, {}).get("awards", [])
		if not awards.is_empty(): status += " · %d awards" % awards.size()
		%Levels.add_item("%02d  %s · %s" % [data.order, data.name, status])
	%Details.text = chapter.get("description", "Select a level.")
	if levels.is_empty(): %Details.text += "\nNo published puzzles yet."
	if not session.store.chapter_unlocked(chapter): %Details.text += "\nComplete this chapter's required puzzles to unlock it."
	%Open.disabled = true

func open_selected() -> void:
	var selected = %Levels.get_selected_items()
	if selected.is_empty(): return
	var data = levels[selected[0]]
	if editing: session.editor(data)
	elif session.store.unlocked(data, all_levels): session.player(data)
	else: return
	hide()

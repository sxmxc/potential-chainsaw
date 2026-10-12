extends "res://scripts/ui/modal_window.gd"

var session: PuzzleSession
var editing: bool = false
var levels: Array[Dictionary] = []
var all_levels: Array[Dictionary] = []
var chapters: Array[Dictionary] = []
const Copy = preload("res://scripts/ui/puzzle_copy.gd")
const CHAPTER_BUTTON = preload("res://scenes/ui/widgets/chapter_button.tscn")

func configure(value: PuzzleSession) -> void:
	session = value
	closed.connect(session.game.modal_closed)
	%Back.pressed.connect(close)
	%Open.pressed.connect(open_selected)
	%Levels.item_activated.connect(func(_index): open_selected())
	%PlayIntroduction.pressed.connect(func(): start_campaign(true))
	%SkipIntroduction.pressed.connect(func(): start_campaign(false))
	%Resume.pressed.connect(resume_campaign)
	%Levels.item_selected.connect(select_level)

func open_campaign() -> void:
	open()
	if not session.store.campaign.get("started", false):
		%StartChoice.show()
		%Heading.text = "Campaign"

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
	session.game.open_modal()
	title = "Puzzle library" if editing else "Campaign"
	%Heading.text = title
	%StartChoice.hide()
	%Resume.visible = not editing and session.store.campaign.get("started", false)
	%Open.text = "Edit" if editing else "Play"
	all_levels = session.store.list_puzzles()
	if editing:
		var drafts = session.store.list_puzzles(true)
		var ids: Array = []
		for data in drafts: ids.append(data.id)
		for i in range(all_levels.size() - 1, -1, -1):
			if all_levels[i].id in ids: all_levels.remove_at(i)
		all_levels.append_array(drafts)
	chapters = session.store.list_chapters(all_levels)
	for button in %Chapters.get_children():
		%Chapters.remove_child(button)
		button.queue_free()
	var selected = 0
	for i in chapters.size():
		var chapter = chapters[i]
		var counts = session.store.chapter_progress(chapter.id, all_levels)
		var status = "%d / %d complete" % [counts.completed,counts.total] if counts.total > 0 else "No levels yet"
		if chapter.get("optional",false) and counts.total>0: status="%d / %d" % [counts.completed,counts.total]
		if not session.store.chapter_unlocked(chapter): status = "Locked"
		var button=CHAPTER_BUTTON.instantiate()
		%Chapters.add_child(button)
		button.get_node("%ChapterTitle").text=chapter.name
		button.get_node("%ChapterProgress").text=("Optional · " if chapter.get("optional",false) else "")+status
		button.pressed.connect(show_chapter.bind(i))
		if chapter.id == session.store.campaign.get("current_chapter", ""): selected = i
	if not chapters.is_empty():
		show_chapter(selected)
	popup_centered(size)

func show_chapter(index: int) -> void:
	var chapter = chapters[index]
	for i in %Chapters.get_child_count(): %Chapters.get_child(i).button_pressed=i==index
	%ChapterName.text=chapter.name
	%ChapterName.hide()
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
		var icon: Texture2D=null
		if session.store.completed(data.id): icon=load("res://assets/ui/icons/complete.svg")
		elif status=="Locked": icon=load("res://assets/ui/icons/locked.svg")
		%Levels.add_item("%02d  %s%s" % [data.order, data.name," · Draft" if data.status!="published" else ""],icon)
		%Levels.set_item_tooltip(%Levels.item_count-1,status)
		if status=="Locked":
			%Levels.set_item_custom_fg_color(%Levels.item_count-1,get_theme_color("font_disabled_color","ItemList"))
			%Levels.set_item_tooltip(%Levels.item_count-1,"Complete the required levels to unlock this level.")
	%Levels.visible=not levels.is_empty()
	%Details.visible=%Levels.visible
	%Open.visible=%Levels.visible
	%Empty.visible=levels.is_empty()
	%Empty.text="No levels available yet." if session.store.chapter_unlocked(chapter) else "Complete the required levels to unlock this chapter."
	%Details.text = "Select a level."
	%Open.disabled = true
	if not levels.is_empty():
		var selected=0
		for i in levels.size():
			if not session.store.completed(levels[i].id) and session.store.unlocked(levels[i],all_levels):
				selected=i
				break
		%Levels.select(selected)
		select_level(selected)
	size=Vector2i(920,320 if levels.is_empty() else 500)
	if visible: popup_centered(size)

func select_level(index: int) -> void:
	%Details.text = Copy.objective(levels[index])
	%Open.disabled = not editing and not session.store.unlocked(levels[index], all_levels)
	if %Open.disabled: %Details.text += "\nComplete the required levels to unlock this level."
	var resume: Dictionary=session.store.resume_level()
	%Resume.visible=not editing and not resume.is_empty() and resume.id!=levels[index].id
	%Open.text="Edit" if editing else ("Continue" if not resume.is_empty() and resume.id==levels[index].id else "Play")

func open_selected() -> void:
	var selected = %Levels.get_selected_items()
	if selected.is_empty(): return
	var data = levels[selected[0]]
	if editing: session.editor(data)
	elif session.store.unlocked(data, all_levels): session.player(data)
	else: return
	hide()

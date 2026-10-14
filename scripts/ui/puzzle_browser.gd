extends "res://scripts/ui/modal_window.gd"

signal modal_opened

var session: ConstructionSession
var editing: bool = false
var community: bool = false
var levels: Array[Dictionary] = []
var campaign_definition: CampaignDefinition
const Copy = preload("res://scripts/ui/puzzle_copy.gd")
const CHAPTER_BUTTON = preload("res://scenes/ui/widgets/chapter_button.tscn")

func configure(value: ConstructionSession) -> void:
	session = value
	$Surface.minimum_size_changed.connect(func():
		if visible: fit_contents.call_deferred())
	%Back.pressed.connect(close)
	%Import.pressed.connect(func(): %ImportDialog.popup_centered(Vector2i(700, 500)))
	%ImportDialog.file_selected.connect(func(path):
		var imported := session.store.import_puzzle(path)
		if imported.is_empty(): session.message_requested.emit(session.store.last_error)
		else: open(false, true))
	%NewPuzzle.pressed.connect(func(): hide(); session.editor())
	%Open.pressed.connect(open_selected)
	%Levels.item_activated.connect(func(_index): open_selected())
	%PlayIntroduction.pressed.connect(func(): start_campaign(true))
	%SkipIntroduction.pressed.connect(func(): start_campaign(false))
	%Resume.pressed.connect(resume_campaign)
	%Levels.item_selected.connect(select_level)

func open_campaign() -> void:
	open()
	if not session.progress.route.get("started", false):
		%StartChoice.show()
		%Heading.text = "Campaign"
		fit_contents.call_deferred()

func start_campaign(play_introduction: bool) -> void:
	var target = session.progress.start_campaign(campaign_definition, play_introduction)
	if not target.is_empty():
		hide()
		session.player(target)
	else: open()

func resume_campaign() -> void:
	var target = campaign_definition.resume_level(session.progress.route, session.progress.records)
	if target.is_empty(): open(); return
	hide()
	session.player(target)

func open(editor_mode: bool = false, community_mode: bool = false) -> void:
	editing = editor_mode
	community = community_mode or (editing and not session.official_authoring)
	modal_opened.emit()
	title = "Puzzle library" if editing else ("Community puzzles" if community else "Campaign")
	%Heading.text = title
	%StartChoice.hide()
	%Resume.visible = not editing and not community and session.progress.route.get("started", false)
	%Open.text = "Edit" if editing else "Play"
	campaign_definition = session.store.load_campaign()
	var all_levels := session.store.list_community() if community else campaign_definition.levels.duplicate()
	%Import.visible = community
	%NewPuzzle.visible = community and not editing
	if editing:
		var drafts = session.store.list_drafts()
		var ids: Array = []
		for data in drafts: ids.append(data.id)
		for i in range(all_levels.size() - 1, -1, -1):
			if all_levels[i].id in ids: all_levels.remove_at(i)
		all_levels.append_array(drafts)
	if community:
		campaign_definition = CampaignDefinition.new([{"id": "local", "name": "Community puzzles", "prerequisites": []}], all_levels)
	else:
		campaign_definition = CampaignDefinition.new(campaign_definition.chapters, all_levels)
	%Chapters.get_parent().visible = not community
	for button in %Chapters.get_children():
		%Chapters.remove_child(button)
		button.queue_free()
	var selected = 0
	for i in campaign_definition.chapters.size():
		var chapter = campaign_definition.chapters[i]
		var counts = campaign_definition.chapter_progress(chapter.id, session.progress.records)
		var status = "%d / %d complete" % [counts.completed,counts.total] if counts.total > 0 else "No levels yet"
		if chapter.get("optional",false) and counts.total>0: status="%d / %d" % [counts.completed,counts.total]
		if not campaign_definition.chapter_unlocked(chapter, session.progress.records): status = "Locked"
		var button=CHAPTER_BUTTON.instantiate()
		%Chapters.add_child(button)
		button.get_node("%ChapterTitle").text=chapter.name
		button.get_node("%ChapterProgress").text=("Optional · " if chapter.get("optional",false) else "")+status
		button.pressed.connect(show_chapter.bind(i))
		if chapter.id == session.progress.route.get("current_chapter", ""): selected = i
	if not campaign_definition.chapters.is_empty():
		show_chapter(selected)
	fit_contents.call_deferred()

func show_chapter(index: int) -> void:
	var chapter = campaign_definition.chapters[index]
	for i in %Chapters.get_child_count(): %Chapters.get_child(i).button_pressed=i==index
	%ChapterName.text=chapter.name
	%ChapterName.hide()
	levels.clear()
	for data in campaign_definition.levels:
		if community or campaign_definition.chapter_for(data).id == chapter.id: levels.append(data)
	levels.sort_custom(func(a, b):
		if community: return str(a.name).naturalnocasecmp_to(str(b.name)) < 0
		if CampaignDefinition.level_order(a) != CampaignDefinition.level_order(b): return CampaignDefinition.level_order(a) < CampaignDefinition.level_order(b)
		return str(a.id) < str(b.id))
	%Levels.clear()
	for data in levels:
		var status = "Draft" if data.status != "published" else ("Complete" if is_completed(data) else ("Ready" if (community or campaign_definition.unlocked(data, session.progress.records)) else "Locked"))
		var records: Dictionary = session.progress.community_records if community else session.progress.records
		var awards: Array = records.get(data.id, {}).get("awards", [])
		if not awards.is_empty(): status += " · %d awards" % awards.size()
		if community and data.get("_source") != "draft": status = ("Imported · " if data.get("_source") == "community" else "Local · ") + status
		var icon: Texture2D=null
		if is_completed(data): icon=load("res://assets/ui/icons/complete.svg")
		elif status=="Locked": icon=load("res://assets/ui/icons/locked.svg")
		var label: String = data.name if community else "%02d  %s" % [CampaignDefinition.level_order(data), data.name]
		%Levels.add_item(label + (" · Draft" if data.status != "published" else ""), icon)
		%Levels.set_item_tooltip(%Levels.item_count-1,status)
		if status=="Locked":
			%Levels.set_item_custom_fg_color(%Levels.item_count-1,get_theme_color("font_disabled_color","ItemList"))
			%Levels.set_item_tooltip(%Levels.item_count-1,"Complete the required levels to unlock this level.")
	%Levels.visible=not levels.is_empty()
	%Details.visible=%Levels.visible
	%Open.visible=%Levels.visible
	%Empty.visible=levels.is_empty()
	%Empty.text="No levels available yet." if campaign_definition.chapter_unlocked(chapter, session.progress.records) else "Complete the required levels to unlock this chapter."
	%Details.text = "Select a level."
	%Open.disabled = true
	if not levels.is_empty():
		var selected=0
		for i in levels.size():
			if not is_completed(levels[i]) and (community or campaign_definition.unlocked(levels[i], session.progress.records)):
				selected=i
				break
		%Levels.select(selected)
		select_level(selected)
	fit_contents.call_deferred()

func fit_contents() -> void:
	reset_size()
	popup_centered()

func select_level(index: int) -> void:
	%Details.text = Copy.objective(levels[index])
	%Open.disabled = not editing and not community and not campaign_definition.unlocked(levels[index], session.progress.records)
	if %Open.disabled: %Details.text += "\nComplete the required levels to unlock this level."
	var resume: Dictionary=campaign_definition.resume_level(session.progress.route, session.progress.records)
	%Resume.visible=not editing and not community and not resume.is_empty() and resume.id!=levels[index].id
	%Open.text="Edit" if editing else ("Continue" if not community and not resume.is_empty() and resume.id==levels[index].id else "Play")

func open_selected() -> void:
	var selected = %Levels.get_selected_items()
	if selected.is_empty(): return
	var data = levels[selected[0]]
	if editing: session.editor(data, session.official_authoring)
	elif (community or campaign_definition.unlocked(data, session.progress.records)): session.player(data)
	else: return
	hide()

func is_completed(data: Dictionary) -> bool:
	return session.progress.community_records.get(data.id, {}).get("completed", false) if community else session.progress.records.get(data.id, {}).get("completed", false)

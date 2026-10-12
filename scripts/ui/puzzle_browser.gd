extends Window

var session: PuzzleSession
var editing: bool = false
var levels: Array[Dictionary] = []

func configure(value: PuzzleSession) -> void:
	session = value
	close_requested.connect(hide)
	%Back.pressed.connect(hide)
	%Open.pressed.connect(open_selected)
	%Levels.item_activated.connect(func(_index): open_selected())
	%Levels.item_selected.connect(func(index):
		%Details.text = levels[index].description
		%Open.disabled = not editing and not session.store.unlocked(levels[index], levels))

func open(editor_mode: bool = false) -> void:
	editing = editor_mode
	title = "Open a puzzle" if editing else "Campaign"
	levels = session.store.list_puzzles()
	if editing:
		var drafts = session.store.list_puzzles(true)
		var ids: Array = []
		for data in drafts: ids.append(data.id)
		for i in range(levels.size() - 1, -1, -1):
			if levels[i].id in ids: levels.remove_at(i)
		levels.append_array(drafts)
	%Levels.clear()
	for data in levels:
		var status = "Draft" if data.status != "published" else ("Complete" if session.store.progress.has(data.id) else ("Ready" if session.store.unlocked(data, levels) else "Locked"))
		var awards: Array = session.store.progress.get(data.id, {}).get("awards", [])
		if not awards.is_empty(): status += " · %d awards" % awards.size()
		%Levels.add_item("%02d  %s · %s" % [data.order, data.name, status])
	%Details.text = "%d / %d complete" % [session.store.progress.size(), levels.size()] if not levels.is_empty() else "No published puzzles yet."
	%Open.disabled = true
	popup_centered(Vector2i(620, 580))

func open_selected() -> void:
	var selected = %Levels.get_selected_items()
	if selected.is_empty(): return
	var data = levels[selected[0]]
	if editing: session.editor(data)
	elif session.store.unlocked(data, levels): session.player(data)
	else: return
	hide()

extends VBoxContainer

var build: BuildManager
var event_choice: OptionButton
var target_choice: OptionButton
var action_choice: OptionButton
var targets: Array[TrackPiece] = []

func configure(manager: BuildManager) -> void:
	build = manager
	build.selection_changed.connect(refresh)

func refresh(piece: TrackPiece) -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	if not piece or build.selection.size() != 1 or piece.supported_events().is_empty(): return
	var label = Label.new()
	label.text = "EVENT → ACTION"
	label.theme_type_variation = "AccentSmallLabel"
	add_child(label)
	event_choice = OptionButton.new()
	for event in piece.supported_events(): event_choice.add_item(event.capitalize())
	add_child(event_choice)
	target_choice = OptionButton.new()
	target_choice.fit_to_longest_item = false
	target_choice.clip_text = true
	targets.clear()
	for target in build.pieces:
		if target == piece or target.supported_actions().is_empty(): continue
		targets.append(target)
		target_choice.add_item(target.definition.display_name + " · " + target.instance_id.right(4))
	add_child(target_choice)
	action_choice = OptionButton.new()
	add_child(action_choice)
	target_choice.item_selected.connect(func(_index): refresh_actions())
	refresh_actions()
	var add = Button.new()
	add.text = "Connect event"
	add.theme_type_variation = "SecondaryButton"
	add.disabled = targets.is_empty() or (build.rules != null and not build.rules.permits(piece.instance_id, "configure"))
	add_child(add)
	add.pressed.connect(func():
		if targets.is_empty() or not build.selected: return
		var source = build.selected
		var target = targets[target_choice.selected]
		var config = source.configuration.duplicate(true)
		var links: Array = config.get("links", [])
		var link = {"event": source.supported_events()[event_choice.selected], "target": target.instance_id, "action": target.supported_actions()[action_choice.selected]}
		if link not in links: links.append(link)
		config.links = links
		build.configure_selected(config, "Connect mechanism"))
	for index in piece.configuration.get("links", []).size():
		var link: Dictionary = piece.configuration.links[index]
		var remove = Button.new()
		remove.clip_text = true
		remove.text = link.event.capitalize() + " → " + link.action.capitalize() + " ×"
		remove.tooltip_text = "Remove this link"
		remove.theme_type_variation = "QuietButton"
		remove.disabled = build.rules != null and not build.rules.permits(piece.instance_id, "configure")
		add_child(remove)
		remove.pressed.connect(func():
			if not build.selected: return
			var config = build.selected.configuration.duplicate(true)
			config.links.remove_at(index)
			build.configure_selected(config, "Remove mechanism link"))

func refresh_actions() -> void:
	action_choice.clear()
	if targets.is_empty(): return
	for action in targets[target_choice.selected].supported_actions(): action_choice.add_item(action.capitalize())

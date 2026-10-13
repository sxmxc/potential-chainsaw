extends VBoxContainer

var build: BuildManager

func configure(manager: BuildManager) -> void:
	build = manager
	build.selection_changed.connect(refresh)
	build.changed.connect(func(): refresh(build.selected))
	%LinkTarget.item_selected.connect(func(_index): refresh_actions())
	%AddLink.pressed.connect(add_link)
	%RemoveLink.pressed.connect(remove_link)
	%LinkList.item_selected.connect(func(_index): %RemoveLink.disabled = not can_configure())
	refresh(null)

func can_configure() -> bool:
	return build.enabled and build.selection.size() == 1 and (not build.rules or build.rules.permits(build.selected.instance_id, "configure"))

func refresh(piece: BuildingPiece) -> void:
	var previous_target: String = %LinkTarget.get_item_metadata(%LinkTarget.selected) if %LinkTarget.item_count > 0 else ""
	%LinkEvent.clear()
	%LinkTarget.clear()
	%LinkAction.clear()
	%LinkList.clear()
	%AddLink.disabled = true
	%RemoveLink.disabled = true
	if not piece or build.selection.size() != 1 or not piece.mechanism_component or piece.mechanism_component.events.is_empty():
		hide()
		return
	for event in piece.mechanism_component.events:
		%LinkEvent.add_item(event.capitalize())
		%LinkEvent.set_item_metadata(%LinkEvent.item_count - 1, event)
	for target in build.pieces:
		if not target.mechanism_component or target.mechanism_component.actions.is_empty(): continue
		%LinkTarget.add_item(target.definition.display_name + " · " + target.instance_id.right(4))
		var index: int = %LinkTarget.item_count - 1
		%LinkTarget.set_item_metadata(index, target.instance_id)
		if target.instance_id == previous_target: %LinkTarget.select(index)
	refresh_actions()
	for link: Dictionary in piece.configuration.get("links", []):
		var target := build.find_piece(link.target)
		%LinkList.add_item(link.event.capitalize() + " → " + (target.definition.display_name if target else "Missing target") + " / " + link.action.capitalize())
	%AddLink.disabled = not can_configure() or %LinkTarget.item_count == 0 or %LinkAction.item_count == 0

func refresh_actions() -> void:
	%LinkAction.clear()
	if %LinkTarget.item_count == 0: return
	var target := build.find_piece(%LinkTarget.get_item_metadata(%LinkTarget.selected))
	if not target or not target.mechanism_component: return
	for action in target.mechanism_component.actions:
		%LinkAction.add_item(action.capitalize())
		%LinkAction.set_item_metadata(%LinkAction.item_count - 1, action)

func add_link() -> void:
	if not can_configure() or %LinkEvent.item_count == 0 or %LinkTarget.item_count == 0 or %LinkAction.item_count == 0: return
	var config := build.selected.configuration.duplicate(true)
	var links: Array = config.get("links", [])
	var link := {"event": %LinkEvent.get_item_metadata(%LinkEvent.selected), "target": %LinkTarget.get_item_metadata(%LinkTarget.selected), "action": %LinkAction.get_item_metadata(%LinkAction.selected)}
	if link in links: return
	links.append(link)
	config.links = links
	build.configure_selected(config, "Connect mechanism")

func remove_link() -> void:
	if not can_configure(): return
	var selected: PackedInt32Array = %LinkList.get_selected_items()
	if selected.is_empty(): return
	var config := build.selected.configuration.duplicate(true)
	config.links.remove_at(selected[0])
	build.configure_selected(config, "Remove mechanism link")

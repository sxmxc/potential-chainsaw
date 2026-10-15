extends VBoxContainer
## Guidance fields live inside the existing Objectives authoring page.
var session: ConstructionSession
var selected_step: int = -1
var refreshing: bool = false

func configure(value: ConstructionSession) -> void:
	session = value
	for kind in ["Point here", "Destination", "Direction", "Interact", "Blocked"]: %MarkerKind.add_item(kind)
	for condition in ["Player selects this piece", "Player connects this track end", "Player starts a run", "Objective receives a marble or activates", "Player presses Next"]: %StepComplete.add_item(condition)
	for context in ["While building", "During run", "Always"]: %StepAppear.add_item(context)
	%StepList.item_selected.connect(edit_step)
	%NewStep.pressed.connect(new_step)
	%AdvancedToggle.toggled.connect(func(shown): %Advanced.visible = shown)
	%StepComplete.item_selected.connect(func(index):
		if index == 1:
			%AdvancedToggle.button_pressed = true
			if %StepConnector.selected == 0 and %StepConnector.item_count > 1: %StepConnector.select(1))
	%SaveStep.pressed.connect(save_step)
	%DeleteStep.pressed.connect(func():
		if selected_step < 0: return
		session.puzzle.guidance.remove_at(selected_step)
		selected_step = -1
		session.metadata_changed()
		refresh()
		new_step())
	%PreviewStep.pressed.connect(preview_step)
	%StepTarget.item_selected.connect(func(_index): refresh_connectors(); _show_point_options())
	%UseSelection.pressed.connect(func():
		var piece := session.world.build.selected
		if not piece: return
		for index in %StepTarget.item_count:
			if %StepTarget.get_item_metadata(index) == piece.instance_id: %StepTarget.select(index); refresh_connectors())
	session.context_changed.connect(func(): selected_step = -1; refresh(); new_step())
	session.world.build.changed.connect(refresh)
	session.world.build.selection_changed.connect(func(piece): %UseSelection.disabled = piece == null)
	visibility_changed.connect(func(): if visible: refresh())

func refresh() -> void:
	if not session or not session.is_authoring: return
	refreshing = true
	var target: String = %StepTarget.get_item_metadata(%StepTarget.selected) if %StepTarget.selected >= 0 else ""
	%StepTarget.clear()
	%StepTarget.add_item("World point")
	%StepTarget.set_item_metadata(0, "")
	var counts: Dictionary = {}
	for piece in session.world.build.pieces:
		if piece.definition.authoring_only: continue
		var display_name: String = piece.definition.display_name
		counts[display_name] = counts.get(display_name, 0) + 1
		%StepTarget.add_item(display_name + (" (%d)" % counts[display_name] if counts[display_name] > 1 else ""))
		var index: int = %StepTarget.item_count - 1
		%StepTarget.set_item_metadata(index, piece.instance_id)
		%StepTarget.get_popup().set_item_tooltip(index, piece.instance_id)
		if piece.instance_id == target: %StepTarget.select(index)
	%StepList.clear()
	var steps: Array = session.puzzle.get("guidance", [])
	for index in steps.size():
		var step: Dictionary = steps[index]
		%StepList.add_item("%d. %s" % [index + 1, step.get("text", "").left(45) if not step.get("text", "").is_empty() else "Point here"])
	if selected_step >= steps.size(): selected_step = -1
	if selected_step >= 0: %StepList.select(selected_step)
	%SaveStep.text = "Save hint" if selected_step >= 0 else "Add hint"
	%DeleteStep.disabled = selected_step < 0
	%UseSelection.disabled = session.world.build.selected == null
	refresh_connectors()
	var problems := WorldGuidance.definition_errors(session.capture(), session.catalog)
	%StepStatus.text = "\n".join(problems)
	refreshing = false

func new_step() -> void:
	if not session or not session.is_authoring: return
	selected_step = -1
	%StepList.deselect_all()
	%StepText.text = ""
	%MarkerKind.select(0)
	%StepComplete.select(4)
	%StepAppear.select(0)
	%StepConnector.select(0)
	%StepTarget.select(1 if %StepTarget.item_count > 1 else 0)
	var piece := session.world.build.selected
	if piece:
		for index in %StepTarget.item_count:
			if %StepTarget.get_item_metadata(index) == piece.instance_id: %StepTarget.select(index)
	%PointX.value = 0
	%PointY.value = 0
	%PointZ.value = 0
	refresh_connectors()
	%AdvancedToggle.button_pressed = false
	_show_point_options()
	%SaveStep.text = "Add hint"
	%DeleteStep.disabled = true
	%StepStatus.text = ""

func _show_point_options() -> void:
	if %StepTarget.selected == 0: %AdvancedToggle.button_pressed = true

func preview_step() -> void:
	var data := session.capture()
	data.version = 3
	data.guidance = [fields()]
	var problems := WorldGuidance.shape_errors(data)
	if problems.is_empty(): problems = WorldGuidance.definition_errors(data, session.catalog)
	if not problems.is_empty(): %StepStatus.text = "\n".join(problems); return
	session.get_parent().guidance.preview(fields())
	%StepStatus.text = "Previewing for five seconds."

func refresh_connectors() -> void:
	var previous: int = %StepConnector.selected - 1
	%StepConnector.clear()
	%StepConnector.add_item("Whole piece")
	var uid: String = %StepTarget.get_item_metadata(%StepTarget.selected) if %StepTarget.selected >= 0 else ""
	var piece := session.world.build.find_piece(uid)
	if piece:
		for index in piece.definition.connectors.size(): %StepConnector.add_item("Track end %d" % (index + 1))
	%StepConnector.select(clampi(previous + 1, 0, %StepConnector.item_count - 1))
	%PointFields.visible = uid.is_empty()

func fields() -> Dictionary:
	return {"kind": WorldGuidance.KINDS[%MarkerKind.selected], "target": %StepTarget.get_item_metadata(%StepTarget.selected), "connector": %StepConnector.selected - 1, "position": [%PointX.value, %PointY.value, %PointZ.value], "text": %StepText.text, "appear": ["build", "run", "always"][%StepAppear.selected], "complete": WorldGuidance.CONDITIONS[%StepComplete.selected]}

func save_step() -> void:
	if not session.is_authoring: return
	var data := session.capture()
	data.version = 3
	if not data.has("guidance"): data.guidance = []
	if selected_step < 0: data.guidance.append(fields())
	else: data.guidance[selected_step] = fields()
	var problems := WorldGuidance.shape_errors(data)
	if problems.is_empty(): problems = WorldGuidance.definition_errors(data, session.catalog)
	if not problems.is_empty(): %StepStatus.text = "\n".join(problems); return
	session.puzzle.version = 3
	session.puzzle.guidance = data.guidance
	if selected_step < 0: selected_step = data.guidance.size() - 1
	session.metadata_changed()
	refresh()

func edit_step(index: int) -> void:
	selected_step = index
	var step: Dictionary = session.puzzle.guidance[index]
	%MarkerKind.select(WorldGuidance.KINDS.find(step.kind))
	%StepText.text = step.get("text", "")
	%StepComplete.select(WorldGuidance.CONDITIONS.find(step.complete))
	%StepAppear.select(["build", "run", "always"].find(step.appear))
	%StepTarget.select(0)
	var found := str(step.get("target", "")).is_empty()
	for target_index in %StepTarget.item_count:
		if %StepTarget.get_item_metadata(target_index) == step.get("target", ""): %StepTarget.select(target_index); found = true
	refresh_connectors()
	%StepConnector.select(clampi(int(step.get("connector", -1)) + 1, 0, %StepConnector.item_count - 1))
	var point: Array = step.get("position", [0, 0, 0])
	%PointX.value = point[0]
	%PointY.value = point[1]
	%PointZ.value = point[2]
	%StepStatus.text = "" if found else "Target was removed. Choose a replacement or remove this step."
	%SaveStep.text = "Save hint"
	%DeleteStep.disabled = false
	%AdvancedToggle.button_pressed = step.kind != "attention" or step.get("connector", -1) >= 0 or step.appear != "build" or str(step.get("target", "")).is_empty()

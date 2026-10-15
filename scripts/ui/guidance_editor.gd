extends VBoxContainer
## Guidance fields live inside the existing Objectives authoring page.
var session: ConstructionSession
var selected_step: int = -1
var refreshing: bool = false

func configure(value: ConstructionSession) -> void:
	session = value
	for kind in WorldGuidance.KINDS: %MarkerKind.add_item(kind.capitalize())
	for condition in ["Select target", "Connect target connector", "Start run", "Objective activity", "Dismiss step"]: %StepComplete.add_item(condition)
	for context in ["While building", "During run", "Always"]: %StepAppear.add_item(context)
	%StepList.item_selected.connect(edit_step)
	%NewStep.pressed.connect(func(): selected_step = -1; %StepList.deselect_all(); %StepText.text = ""; %StepStatus.text = "Choose a target, then add the step.")
	%SaveStep.pressed.connect(save_step)
	%DeleteStep.pressed.connect(func():
		if selected_step < 0: return
		session.puzzle.guidance.remove_at(selected_step)
		selected_step = -1
		session.metadata_changed()
		refresh())
	%PreviewStep.pressed.connect(func(): session.get_parent().guidance.preview(fields()))
	%StepTarget.item_selected.connect(func(_index): refresh_connectors())
	%UseSelection.pressed.connect(func():
		var piece := session.world.build.selected
		if not piece: return
		for index in %StepTarget.item_count:
			if %StepTarget.get_item_metadata(index) == piece.instance_id: %StepTarget.select(index); refresh_connectors())
	session.context_changed.connect(func(): selected_step = -1; refresh())
	session.world.build.changed.connect(refresh)
	visibility_changed.connect(func(): if visible: refresh())

func refresh() -> void:
	if not session or not session.is_authoring: return
	refreshing = true
	var target: String = %StepTarget.get_item_metadata(%StepTarget.selected) if %StepTarget.selected >= 0 else ""
	%StepTarget.clear()
	%StepTarget.add_item("World point")
	%StepTarget.set_item_metadata(0, "")
	for piece in session.world.build.pieces:
		if piece.definition.authoring_only: continue
		%StepTarget.add_item(piece.definition.display_name + " · " + piece.instance_id)
		var index: int = %StepTarget.item_count - 1
		%StepTarget.set_item_metadata(index, piece.instance_id)
		if piece.instance_id == target: %StepTarget.select(index)
	%StepList.clear()
	var steps: Array = session.puzzle.get("guidance", [])
	for step in steps: %StepList.add_item(step.get("text", "").left(45) if not step.get("text", "").is_empty() else str(step.get("kind", "Marker")))
	if selected_step >= steps.size(): selected_step = -1
	if selected_step >= 0: %StepList.select(selected_step)
	refresh_connectors()
	var problems := WorldGuidance.definition_errors(session.capture(), session.catalog)
	%StepStatus.text = "\n".join(problems)
	refreshing = false

func refresh_connectors() -> void:
	var previous: int = %StepConnector.selected - 1
	%StepConnector.clear()
	%StepConnector.add_item("Whole piece")
	var uid: String = %StepTarget.get_item_metadata(%StepTarget.selected) if %StepTarget.selected >= 0 else ""
	var piece := session.world.build.find_piece(uid)
	if piece:
		for index in piece.definition.connectors.size(): %StepConnector.add_item("Connector %d" % (index + 1))
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

extends PanelContainer

signal action_requested(action: String)
signal modal_opened
signal inventory_mode_changed(active: bool)
signal modal_closed

var session: ConstructionSession
var boundary: PuzzleBoundary
var refreshing: bool = false
const INVENTORY_ROW = preload("res://scenes/ui/widgets/inventory_row.tscn")
var inventory_id: String = ""
var objective_index: int = -1
var publish_blocked: bool = true
var opened_puzzle: String = ""
var motion: UIMotion

func _ready() -> void:
	motion = UIMotion.attach(self, Vector2(UIMotion.PANEL_SHIFT, 0.0))
	ButtonFeedback.install(self)
	visibility_changed.connect(func():
		if session:
			boundary.set_editing(visible and %Tabs.current_tab == 2)
			inventory_mode_changed.emit(accepts_inventory()))

func close_drawer() -> void:
	motion.set_open(false)

func configure(puzzle_session: ConstructionSession) -> void:
	session = puzzle_session
	boundary = session.world.boundary
	boundary.edited.connect(func(): metadata_changed(); refresh_zones(); refresh_region())
	boundary.selection_changed.connect(refresh_region)
	%RestrictedList.item_selected.connect(func(index): boundary.select_region(index - 1))
	%RegionPrecision.pressed.connect(func(): %RegionDimensions.visible = not %RegionDimensions.visible)
	for field in [%RegionX, %RegionZ, %RegionWidth, %RegionDepth]:
		field.value_changed.connect(func(_value):
			if not refreshing: boundary.set_footprint(%RegionX.value, %RegionZ.value, %RegionWidth.value, %RegionDepth.value))
	%InventoryRulesToggle.pressed.connect(func(): %InventoryRules.visible = not %InventoryRules.visible)
	%InventorySetting.item_selected.connect(func(_index): refresh_inventory_limit())
	%NextAction.pressed.connect(next_publish_action)
	%ObjectiveList.item_selected.connect(edit_objective)
	%NewObjective.pressed.connect(func(): objective_index = -1; %ObjectiveList.deselect_all(); %AddObjective.text = "Add goal"; %RemoveObjective.disabled = true)
	session.world.build.selection_changed.connect(select_objective_target)
	%Close.pressed.connect(close_drawer)
	%Destination.item_selected.connect(func(index):
		if refreshing or not session.store.can_add_to_campaign(): return
		session.official_authoring = index == 1
		if session.official_authoring and not session.puzzle.has("campaign"):
			session.puzzle.campaign = {"chapter": CampaignDefinition.new(session.store.base_chapters(), []).first_chapter(false), "order": 1, "prerequisites": []}
		session.metadata_changed()
		open())
	%Advanced.pressed.connect(func(): %AdvancedFields.visible=not %AdvancedFields.visible)
	%Tabs.tab_changed.connect(func(index):
		for button in %Navigation.get_children(): button.button_pressed=int(button.get_meta("page"))==index
		UIMotion.section(%Tabs.get_tab_control(index))
		boundary.set_editing(visible and index == 2)
		inventory_mode_changed.emit(accepts_inventory())
		if %Tabs.get_tab_control(index).name == "Publish": refresh_publish())
	for button in %Navigation.get_children(): button.pressed.connect(func(): %Tabs.current_tab=int(button.get_meta("page")))
	session.changed.connect(func(): if visible: refresh_publish())
	%ChapterId.text_changed.connect(select_chapter)
	%ChapterName.text_changed.connect(func(_text): update_chapter())
	%ChapterOrder.value_changed.connect(func(_value): update_chapter())
	%ChapterOptional.toggled.connect(func(_value): update_chapter())
	%ChapterIntroduction.toggled.connect(func(value):
		if value: %ChapterOptional.button_pressed = true
		update_chapter())
	%ChapterRequirements.text_changed.connect(func(_text): update_chapter())
	%PuzzleName.text_changed.connect(func(text): if not refreshing: session.puzzle.name = text)
	%Description.text_changed.connect(func(): if not refreshing: session.puzzle.description = %Description.text)
	%Hint.text_changed.connect(func(): if not refreshing: session.puzzle.hints = [%Hint.text])
	%Order.value_changed.connect(func(value): if not refreshing and session.official_authoring: session.puzzle.campaign.order = int(value))
	%Difficulty.item_selected.connect(func(index): if not refreshing: session.puzzle.difficulty = %Difficulty.get_item_text(index))
	%TimeLimit.value_changed.connect(func(value): if not refreshing: session.puzzle.time_limit = value)
	%AwardTime.value_changed.connect(func(value): if not refreshing: session.puzzle.awards["time"] = value)
	%AwardPieces.value_changed.connect(func(value): if not refreshing: session.puzzle.awards["pieces"] = int(value))
	%SetInventoryLimit.pressed.connect(func():
		if %InventorySetting.item_count == 0 or inventory_id.is_empty(): return
		var limits: Dictionary = session.puzzle.get("configuration_limits", {})
		var settings: Dictionary = limits.get(inventory_id, {})
		settings[%InventorySetting.get_item_metadata(%InventorySetting.selected)] = [%InventoryMin.value, %InventoryMax.value]
		limits[inventory_id] = settings
		session.puzzle.configuration_limits = limits)
	%ClearInventoryLimits.pressed.connect(func(): session.puzzle.get("configuration_limits", {}).erase(inventory_id); refresh_inventory_limit())
	%DrawBuild.pressed.connect(func(): boundary.begin())
	%DrawZone.pressed.connect(func(): boundary.begin(true))
	%ClearZones.pressed.connect(func(): session.puzzle.restricted_zones = []; boundary.select_region(-1); refresh_zones())
	%RemoveZone.pressed.connect(func():
		var selected = %RestrictedList.get_selected_items()
		if not selected.is_empty() and selected[0] > 0: session.puzzle.restricted_zones.remove_at(selected[0] - 1); boundary.select_region(-1); refresh_zones())
	%ModifyZone.pressed.connect(func():
		var selected = %RestrictedList.get_selected_items()
		if not selected.is_empty(): boundary.begin(selected[0] > 0, selected[0] - 1))
	%Prerequisites.multi_selected.connect(func(index, selected):
		if refreshing or not session.official_authoring: return
		var id = %Prerequisites.get_item_metadata(index)
		if selected and id not in session.puzzle.campaign.prerequisites: session.puzzle.campaign.prerequisites.append(id)
		elif not selected: session.puzzle.campaign.prerequisites.erase(id))
	%MinHeight.value_changed.connect(func(value): if not refreshing: boundary.set_elevation(value, true))
	%MaxHeight.value_changed.connect(func(value): if not refreshing: boundary.set_elevation(value, false))
	%AddObjective.pressed.connect(add_objective)
	%ObjectiveType.item_selected.connect(func(_index): refresh_objects())
	%ObjectiveTarget.item_selected.connect(func(_index): refresh_objective_events())
	%AllMarbles.pressed.connect(func():
		var count = 0
		var source = %MarbleSource.get_item_metadata(%MarbleSource.selected)
		for piece in session.world.build.pieces:
			if piece.behaviors.any(func(behavior_node): return behavior_node is MarbleRelease) and (source.is_empty() or source == piece.instance_id): count += int(piece.definition.resolved_configuration(piece.configuration).get("quantity", 1))
		%RequiredCount.value = maxi(1, count))
	%RemoveObjective.pressed.connect(func():
		var selected = %ObjectiveList.get_selected_items()
		if not selected.is_empty(): session.puzzle.objectives.remove_at(selected[0]); objective_index = -1; refresh_objectives())
	%CaptureCamera.pressed.connect(func(): session.capture_camera(); %CameraStatus.text = "Current camera saved")
	%SaveDraft.pressed.connect(func(): %Validation.text = "Draft saved" if session.save_draft() else "Could not save the draft")
	%TestPlayer.pressed.connect(func(): hide(); session.test_player())
	%Validate.pressed.connect(validate_puzzle)
	%PublishOnline.pressed.connect(func(): action_requested.emit("publish_online"))
	%Export.pressed.connect(func(): modal_opened.emit(); %ExportDialog.popup_centered(Vector2i(700, 500)))
	%ExportDialog.canceled.connect(modal_closed.emit)
	%ExportDialog.file_selected.connect(func(path: String):
		modal_closed.emit()
		%Validation.text = "Puzzle exported" if session.store.export_puzzle(session.capture(), path) else session.store.last_error)
	%NewPuzzle.pressed.connect(func(): hide(); session.editor({}, session.official_authoring))
	%OpenPuzzle.pressed.connect(func(): action_requested.emit("open_puzzle"))
	session.world.build.changed.connect(func(): if visible: refresh_objects(); refresh_objectives(); refresh_publish())
	for field in [%PuzzleName, %Order, %TimeLimit, %AwardTime, %AwardPieces]:
		if field is LineEdit: field.text_changed.connect(func(_text): metadata_changed())
		else: field.value_changed.connect(func(_value): metadata_changed())
	%Creator.text_changed.connect(func(value): if not refreshing: session.puzzle.creator = value; metadata_changed())
	%Description.text_changed.connect(metadata_changed)
	%Hint.text_changed.connect(metadata_changed)
	%Difficulty.item_selected.connect(func(_index): metadata_changed())
	%Prerequisites.multi_selected.connect(func(_index, _selected): metadata_changed())
	for button in [%SetInventoryLimit, %ClearInventoryLimits, %ClearZones, %RemoveZone, %RemoveObjective, %CaptureCamera]:
		button.pressed.connect(metadata_changed)

func open() -> void:
	refreshing = true
	var data = session.capture()
	if opened_puzzle != str(data.id):
		opened_puzzle = str(data.id)
		inventory_id = ""
		objective_index = -1
		%Tabs.current_tab = 0
	%Destination.visible = session.store.can_add_to_campaign()
	%DestinationLabel.visible = %Destination.visible
	%Destination.select(1 if session.official_authoring else 0)
	%PuzzleName.text = data.name
	%Description.text = data.description
	%Hint.text = "\n".join(data.get("hints", []))
	for field in [%ChapterId, %ChapterIdLabel, %ChapterName, %ChapterNameLabel, %ChapterOrder, %ChapterOrderLabel, %ChapterOptional, %ChapterIntroduction, %ChapterRequirements, %ChapterRequirementsLabel, %Order, %OrderLabel, %Prerequisites, %PrerequisiteLabel]:
		field.visible = session.official_authoring
	%Export.visible = not session.official_authoring
	%PublishOnline.visible = not session.official_authoring
	%Creator.text = data.get("creator", "")
	show_chapter(CampaignDefinition.new(session.store.base_chapters(), []).chapter_for(data))
	%Order.value = CampaignDefinition.level_order(data)
	for index in %Difficulty.item_count:
		if %Difficulty.get_item_text(index) == data.get("difficulty", "Introduction"): %Difficulty.select(index)
	%TimeLimit.value = data.get("time_limit", 90)
	%AwardTime.value = data.get("awards", {}).get("time", 0)
	%AwardPieces.value = data.get("awards", {}).get("pieces", 0)
	%MinHeight.value = data.bounds[4]
	%MaxHeight.value = data.bounds[5]
	refresh_inventory()
	refresh_inventory_settings()
	refresh_objects()
	refresh_objectives()
	refresh_zones()
	refresh_region()
	%Prerequisites.clear()
	var available = session.store.load_campaign().levels
	available.append_array(session.store.list_drafts())
	var seen: Dictionary = {}
	for level in available:
		if level.id == data.id or seen.has(level.id): continue
		seen[level.id] = true
		%Prerequisites.add_item(level.name)
		var index = %Prerequisites.item_count - 1
		%Prerequisites.set_item_metadata(index, level.id)
		if level.id in data.get("campaign", {}).get("prerequisites", []): %Prerequisites.select(index, false)
	refreshing = false
	motion.set_open(true)
	boundary.set_editing(%Tabs.current_tab == 2)
	inventory_mode_changed.emit(accepts_inventory())
	refresh_publish()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_drawer()
		get_viewport().set_input_as_handled()

func refresh_publish() -> void:
	if not session or not session.is_authoring: return
	var data: Dictionary=session.capture()
	var validation: Dictionary=data.get("validation",{})
	var tested: bool=validation.get("physics_success",false)
	var solved: bool=not data.get("solution",[]).is_empty()
	var current: bool=validation.get("fingerprint","")==session.store.fingerprint(data)
	%TestStatus.text=("✓" if tested else "○")+" Player test completed"
	%SolutionStatus.text=("✓" if solved else "○")+" Solution saved"
	%RevisionStatus.text=("✓" if current else "○")+" Current draft verified"
	publish_blocked=not session.validate().is_empty()
	%PublishOnline.disabled = publish_blocked
	%Readiness.text = "Ready to release" if not publish_blocked else ("Test your machine" if not current else "Finish your puzzle")
	%NextStep.text = "Your solution verifies this draft." if not publish_blocked else "Solve as a player, then save the successful solution."
	if not %Destination.visible: %NextStep.text = "Community · local file or online\n" + %NextStep.text
	%NextAction.text = ("Add to Campaign" if session.official_authoring else "Publish locally") if not publish_blocked else "Test as player"
	if data.get("name", "").strip_edges().is_empty():
		%Readiness.text = "Name your puzzle"
		%NextStep.text = "Give players a name to remember."
		%NextAction.text = "Edit puzzle name"
	elif data.objectives.is_empty():
		%Readiness.text = "Choose the goal"
		%NextStep.text = "Add a delivery or mechanism goal before testing."
		%NextAction.text = "Add a goal"
	%TestPlayer.visible = not publish_blocked

	%Export.disabled = not FileAccess.file_exists(session.store.published_directory.path_join(data.id + ".json"))

func show_chapter(chapter: Dictionary) -> void:
	%ChapterId.text = chapter.get("id", "")
	%ChapterName.text = chapter.get("name", "")
	%ChapterOrder.value = chapter.get("order", 1)
	%ChapterOptional.button_pressed = chapter.get("optional", false)
	%ChapterIntroduction.button_pressed = chapter.get("introduction", false)
	%ChapterRequirements.text = ", ".join(chapter.get("prerequisites", []))

func select_chapter(id: String) -> void:
	if refreshing or not session.official_authoring: return
	var available = session.store.load_campaign().levels
	available.append_array(session.store.list_drafts())
	for chapter in CampaignDefinition.new(session.store.base_chapters(), available).chapters:
		if chapter.id == id.strip_edges():
			refreshing = true
			show_chapter(chapter)
			refreshing = false
			break
	update_chapter()

func update_chapter() -> void:
	if refreshing or not session.official_authoring: return
	var requirements: Array[String] = []
	for id in %ChapterRequirements.text.split(",", false):
		if not id.strip_edges().is_empty(): requirements.append(id.strip_edges())
	session.puzzle.campaign.chapter = {"id": %ChapterId.text.strip_edges(), "name": %ChapterName.text.strip_edges(), "order": int(%ChapterOrder.value), "optional": %ChapterOptional.button_pressed, "introduction": %ChapterIntroduction.button_pressed, "prerequisites": requirements}
	metadata_changed()

func accepts_inventory() -> bool:
	return visible and session != null and session.is_authoring and %Tabs.current_tab == 1

func add_inventory(definition: PieceDefinition) -> void:
	if not accepts_inventory() or definition.authoring_only: return
	inventory_id = String(definition.id)
	session.puzzle.inventory[inventory_id] = int(session.puzzle.inventory.get(inventory_id, 0)) + 1
	metadata_changed()
	refresh_inventory()
	refresh_inventory_settings()

func refresh_inventory() -> void:
	for child in %InventoryList.get_children():
		%InventoryList.remove_child(child)
		child.queue_free()
	for id: String in session.puzzle.inventory:
		var definition := session.catalog.get_piece(id)
		if not definition: continue
		var row := INVENTORY_ROW.instantiate()
		%InventoryList.add_child(row)
		var button: Button = row.get_node("%Piece")
		button.text = definition.display_name
		button.icon = definition.thumbnail
		button.tooltip_text = definition.display_name + " · edit restrictions"
		button.pressed.connect(func(): inventory_id = id; refresh_inventory_settings())
		var quantity: SpinBox = row.get_node("%Quantity")
		quantity.set_value_no_signal(session.puzzle.inventory[id])
		quantity.value_changed.connect(func(value):
			if value <= 0: session.puzzle.inventory.erase(id)
			else: session.puzzle.inventory[id] = int(value)
			metadata_changed()
			if value <= 0: refresh_inventory.call_deferred(); refresh_inventory_settings.call_deferred())
	if inventory_id.is_empty() and not session.puzzle.inventory.is_empty(): inventory_id = session.puzzle.inventory.keys()[0]

func refresh_inventory_settings() -> void:
	%InventorySetting.clear()
	var definition := session.catalog.get_piece(inventory_id)
	%InventorySelection.text = definition.display_name if definition and session.puzzle.inventory.has(inventory_id) else "Add pieces from the browser"
	%InventoryRulesToggle.visible = definition != null and session.puzzle.inventory.has(inventory_id) and definition.settings.any(func(setting): return setting.kind == PieceSetting.Kind.NUMBER)
	%InventorySelection.visible = %InventoryRulesToggle.visible
	if not %InventoryRulesToggle.visible:
		%InventoryRules.hide()
		return
	for setting in definition.settings:
		if setting.kind != PieceSetting.Kind.NUMBER: continue
		%InventorySetting.add_item(setting.label)
		%InventorySetting.set_item_metadata(%InventorySetting.item_count - 1, String(setting.key))
	refresh_inventory_limit()

func refresh_inventory_limit() -> void:
	if %InventorySetting.item_count == 0: return
	var key: String = %InventorySetting.get_item_metadata(%InventorySetting.selected)
	var definition := session.catalog.get_piece(inventory_id)
	var defaults: Array = [0, 100]
	for setting in definition.settings:
		if String(setting.key) != key: continue
		defaults = [setting.minimum, setting.maximum]
		for field in [%InventoryMin, %InventoryMax]:
			field.min_value = setting.minimum
			field.max_value = setting.maximum
			field.step = setting.step
	var limits: Array = session.puzzle.get("configuration_limits", {}).get(inventory_id, {}).get(key, defaults)
	%InventoryMin.set_value_no_signal(limits[0])
	%InventoryMax.set_value_no_signal(limits[1])

func refresh_zones() -> void:
	%RestrictedList.clear()
	%RestrictedList.add_item("Build area · pieces allowed")
	for index in session.puzzle.restricted_zones.size():
		var zone: Array = session.puzzle.restricted_zones[index]
		%RestrictedList.add_item("Restricted %d · %s × %s m" % [index + 1, zone[3], zone[5]])
	%RestrictedList.select(clampi(boundary.selected_region + 1, 0, %RestrictedList.item_count - 1))

func refresh_region() -> void:
	var box := boundary.region_box(boundary.selected_region)
	var was_refreshing := refreshing
	refreshing = true
	%MinHeight.set_value_no_signal(box.position.y)
	%MaxHeight.set_value_no_signal(box.end.y)
	%RegionX.set_value_no_signal(box.position.x)
	%RegionZ.set_value_no_signal(box.position.z)
	%RegionWidth.set_value_no_signal(box.size.x)
	%RegionDepth.set_value_no_signal(box.size.z)
	refreshing = was_refreshing
	%RegionSummary.text = ("Build area · building allowed" if boundary.selected_region < 0 else "Restricted area · no building") + "\n%s × %s m" % [snappedf(box.size.x, 0.01), snappedf(box.size.z, 0.01)]
	%RemoveZone.disabled = boundary.selected_region < 0
	if %RestrictedList.item_count > 0: %RestrictedList.select(clampi(boundary.selected_region + 1, 0, %RestrictedList.item_count - 1))

func refresh_objects() -> void:
	var target_id: String = %ObjectiveTarget.get_item_metadata(%ObjectiveTarget.selected) if %ObjectiveTarget.selected >= 0 else ""
	var source_id: String = %MarbleSource.get_item_metadata(%MarbleSource.selected) if %MarbleSource.selected >= 0 else ""
	var output: String = %ObjectiveEvent.get_item_metadata(%ObjectiveEvent.selected) if %ObjectiveEvent.selected >= 0 else ""
	%ObjectiveTarget.clear()
	%MarbleSource.clear()
	%MarbleSource.add_item("Any marble release")
	%MarbleSource.set_item_metadata(0, "")
	for piece in session.world.build.pieces:
		var object_label := piece_caption(piece)
		if (piece.behaviors.any(func(behavior_node): return behavior_node is MarbleCollector) and %ObjectiveType.selected == 0) or (not piece.output_ports.is_empty() and %ObjectiveType.selected == 1):
			%ObjectiveTarget.add_item(object_label)
			%ObjectiveTarget.set_item_metadata(%ObjectiveTarget.item_count - 1, piece.instance_id)
		if piece.behaviors.any(func(behavior_node): return behavior_node is MarbleRelease):
			%MarbleSource.add_item(object_label)
			%MarbleSource.set_item_metadata(%MarbleSource.item_count - 1, piece.instance_id)
	select_option(%ObjectiveTarget, target_id)
	select_option(%MarbleSource, source_id)
	refresh_objective_events()
	select_option(%ObjectiveEvent, output)
	%AddObjective.disabled = %ObjectiveTarget.item_count == 0

func refresh_objective_events() -> void:
	var delivery = %ObjectiveType.selected == 0
	%ObjectiveEvent.visible = not delivery
	for control in [%MarbleSource, %MarbleSourceLabel, %RequiredCount, %RequiredCountLabel, %AllMarbles]: control.visible = delivery
	%ObjectiveEvent.clear()
	if delivery or %ObjectiveTarget.item_count == 0: return
	var target: BuildingPiece = session.world.build.find_piece(%ObjectiveTarget.get_item_metadata(%ObjectiveTarget.selected))
	for event in target.output_ports.keys():
		%ObjectiveEvent.add_item(event.capitalize())
		%ObjectiveEvent.set_item_metadata(%ObjectiveEvent.item_count - 1, event)

func add_objective() -> void:
	if %ObjectiveTarget.item_count == 0: return
	var target = session.world.build.find_piece(%ObjectiveTarget.get_item_metadata(%ObjectiveTarget.selected))
	var type = "deliver" if %ObjectiveType.selected == 0 else "activate"
	if type == "deliver" and not target.behaviors.any(func(behavior_node): return behavior_node is MarbleCollector): %Validation.text = "Choose a collector for delivery"; return
	var data = {"type": type, "target": target.instance_id, "count": int(%RequiredCount.value), "source": %MarbleSource.get_item_metadata(%MarbleSource.selected), "time_limit": %ObjectiveTime.value}
	if type == "activate":
		if target.output_ports.is_empty(): return
		var events = target.output_ports.keys()
		if events.is_empty(): return
		data.event = events[maxi(0, %ObjectiveEvent.selected)]
	if objective_index >= 0 and objective_index < session.puzzle.objectives.size(): session.puzzle.objectives[objective_index] = data
	else:
		session.puzzle.objectives.append(data)
		objective_index = session.puzzle.objectives.size() - 1
	metadata_changed()
	refresh_objectives()

func refresh_objectives() -> void:
	%ObjectiveList.clear()
	%RemoveObjective.disabled = objective_index < 0
	%AddObjective.text = "Save goal" if objective_index >= 0 else "Add goal"
	for objective in session.puzzle.objectives:
		var target = session.world.build.find_piece(objective.target)
		var summary := "Deliver %d marbles to %s" % [objective.get("count", 1), piece_caption(target)] if objective.type == "deliver" else "%s · %s" % [piece_caption(target), str(objective.get("event", "activated")).replace("_", " ").capitalize()]
		var conditions: Array[String] = []
		if not str(objective.get("source", "")).is_empty(): conditions.append("From " + piece_caption(session.world.build.find_piece(objective.source)))
		if float(objective.get("time_limit", 0)) > 0: conditions.append("Within %s seconds" % str(objective.time_limit).trim_suffix(".0"))
		%ObjectiveList.add_item(summary)
		conditions.push_front(summary)
		%ObjectiveList.set_item_tooltip(%ObjectiveList.item_count - 1, "\n".join(conditions))

	if objective_index >= 0 and objective_index < %ObjectiveList.item_count: %ObjectiveList.select(objective_index)

func piece_caption(piece: BuildingPiece) -> String:
	if not piece: return "Missing object"
	var label: String = str(piece.definition.resolved_configuration(piece.configuration).get("label", "")).strip_edges()
	return (piece.definition.display_name if label.is_empty() else label) + " · %d" % (session.world.build.pieces.find(piece) + 1)

func validate_puzzle() -> void:
	var errors := session.validate()
	%Validation.text = "Ready to publish" if errors.is_empty() else "\n".join(errors)
	refresh_publish()

func metadata_changed() -> void:
	if refreshing or not session.is_authoring: return
	%Validation.text = ""
	session.metadata_changed()
	refresh_publish()

func select_option(control: OptionButton, value: String) -> bool:
	for index in control.item_count:
		if control.get_item_metadata(index) == value: control.select(index); return true
	return false

func select_objective_target(piece: BuildingPiece) -> void:
	if not visible or %Tabs.current_tab != 3 or not piece: return
	if %ObjectiveTarget.selected >= 0 and %ObjectiveTarget.get_item_metadata(%ObjectiveTarget.selected) == piece.instance_id: return
	if select_option(%ObjectiveTarget, piece.instance_id): refresh_objective_events()

func edit_objective(index: int) -> void:
	if index < 0 or index >= session.puzzle.objectives.size(): return
	objective_index = index
	var objective: Dictionary = session.puzzle.objectives[index]
	%ObjectiveType.select(0 if objective.type == "deliver" else 1)
	refresh_objects()
	select_option(%ObjectiveTarget, objective.target)
	refresh_objective_events()
	select_option(%MarbleSource, objective.get("source", ""))
	%RequiredCount.value = objective.get("count", 1)
	%ObjectiveTime.value = objective.get("time_limit", 0)
	for event in %ObjectiveEvent.item_count:
		if %ObjectiveEvent.get_item_metadata(event) == objective.get("event", ""): %ObjectiveEvent.select(event)
	%AddObjective.text = "Save goal"
	%RemoveObjective.disabled = false
	var target := session.world.build.find_piece(objective.target)
	if target: session.world.build.select(target); session.world.build.frame_pieces([target])

func next_publish_action() -> void:
	if publish_blocked:
		var errors := session.validate(false)
		if session.puzzle.get("name", "").strip_edges().is_empty():
			%Tabs.current_tab = 0
			return
		if session.puzzle.objectives.is_empty():
			%Tabs.current_tab = 3
			return
		if not errors.is_empty():
			%Validation.text = "\n".join(errors)
			return
		hide()
		session.test_player()
	else:
		if session.publish():
			%Validation.text = "Added to Campaign" if session.official_authoring else "Published locally. Export a file or share online."
			refresh_publish()

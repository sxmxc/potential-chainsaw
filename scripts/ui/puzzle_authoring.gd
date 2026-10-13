extends PanelContainer

var session: PuzzleSession
var refreshing: bool = false

func configure(puzzle_session: PuzzleSession) -> void:
	session = puzzle_session
	%Close.pressed.connect(func(): hide(); session.game.get_node("%HUD").refresh())
	%Advanced.pressed.connect(func(): %AdvancedFields.visible=not %AdvancedFields.visible)
	%Tabs.tab_changed.connect(func(index):
		for button in %Navigation.get_children(): button.button_pressed=int(button.get_meta("page"))==index
		if %Tabs.get_tab_control(index).name == "Publish": refresh_publish())
	for button in %Navigation.get_children(): button.pressed.connect(func(): %Tabs.current_tab=int(button.get_meta("page")))
	session.mode_changed.connect(func(): if visible: refresh_publish())
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
	%Order.value_changed.connect(func(value): if not refreshing: session.puzzle.order = int(value))
	%Difficulty.item_selected.connect(func(index): if not refreshing: session.puzzle.difficulty = %Difficulty.get_item_text(index))
	%TimeLimit.value_changed.connect(func(value): if not refreshing: session.puzzle.time_limit = value)
	%AwardTime.value_changed.connect(func(value): if not refreshing: session.puzzle.awards["time"] = value)
	%AwardPieces.value_changed.connect(func(value): if not refreshing: session.puzzle.awards["pieces"] = int(value))
	%InventoryPiece.item_selected.connect(func(index): %Quantity.value = session.puzzle.inventory.get(%InventoryPiece.get_item_metadata(index), 0); refresh_inventory_settings())
	%SetInventoryLimit.pressed.connect(func():
		if %InventorySetting.item_count == 0: return
		var id = %InventoryPiece.get_item_metadata(%InventoryPiece.selected)
		var limits: Dictionary = session.puzzle.get("configuration_limits", {})
		var settings: Dictionary = limits.get(id, {})
		settings[%InventorySetting.get_item_metadata(%InventorySetting.selected)] = [%InventoryMin.value, %InventoryMax.value]
		limits[id] = settings
		session.puzzle.configuration_limits = limits)
	%ClearInventoryLimits.pressed.connect(func(): session.puzzle.get("configuration_limits", {}).erase(%InventoryPiece.get_item_metadata(%InventoryPiece.selected)))
	%SetQuantity.pressed.connect(func():
		if %InventoryPiece.item_count == 0: return
		var id = %InventoryPiece.get_item_metadata(%InventoryPiece.selected)
		if %Quantity.value <= 0: session.puzzle.inventory.erase(id)
		else: session.puzzle.inventory[id] = int(%Quantity.value)
		refresh_inventory())
	%DrawBuild.pressed.connect(func(): hide(); session.begin_boundary())
	%DrawZone.pressed.connect(func(): hide(); session.begin_boundary(true))
	%ClearZones.pressed.connect(func(): session.puzzle.restricted_zones = []; session.refresh_boundary())
	%RemoveZone.pressed.connect(func():
		var selected = %RestrictedList.get_selected_items()
		if not selected.is_empty(): session.puzzle.restricted_zones.remove_at(selected[0]); session.refresh_boundary(); refresh_zones())
	%ModifyZone.pressed.connect(func():
		var selected = %RestrictedList.get_selected_items()
		if not selected.is_empty(): hide(); session.begin_boundary(true, selected[0]))
	%Prerequisites.multi_selected.connect(func(index, selected):
		if refreshing: return
		var id = %Prerequisites.get_item_metadata(index)
		if selected and id not in session.puzzle.prerequisites: session.puzzle.prerequisites.append(id)
		elif not selected: session.puzzle.prerequisites.erase(id))
	%MinHeight.value_changed.connect(func(value): if not refreshing: session.puzzle.bounds[4] = value; session.refresh_boundary())
	%MaxHeight.value_changed.connect(func(value): if not refreshing: session.puzzle.bounds[5] = value; session.refresh_boundary())
	%AddObjective.pressed.connect(add_objective)
	%ObjectiveType.item_selected.connect(func(_index): refresh_objects())
	%ObjectiveTarget.item_selected.connect(func(_index): refresh_objective_events())
	%AllMarbles.pressed.connect(func():
		var count = 0
		var source = %MarbleSource.get_item_metadata(%MarbleSource.selected)
		for piece in session.game.sandbox.build.pieces:
			if piece.definition.behavior == "start" and (source.is_empty() or source == piece.instance_id): count += int(piece.configuration.get("quantity", 1))
		%RequiredCount.value = maxi(1, count))
	%RemoveObjective.pressed.connect(func():
		var selected = %ObjectiveList.get_selected_items()
		if not selected.is_empty(): session.puzzle.objectives.remove_at(selected[0]); refresh_objectives())
	%CaptureCamera.pressed.connect(func(): session.capture_camera(); %CameraStatus.text = "Current camera saved")
	%SaveDraft.pressed.connect(func(): %Validation.text = "Draft saved" if session.save() else "Could not save the draft")
	%TestPlayer.pressed.connect(func(): hide(); session.test_player())
	%Validate.pressed.connect(validate_puzzle)
	%Publish.pressed.connect(func(): if session.publish(): %Validation.text = "Published to Campaign")
	%Export.pressed.connect(func(): session.game.open_modal(); %ExportDialog.popup_centered(Vector2i(700, 500)))
	%ExportDialog.canceled.connect(session.game.modal_closed)
	%ExportDialog.file_selected.connect(export_package)
	%NewPuzzle.pressed.connect(func(): hide(); session.editor())
	%OpenPuzzle.pressed.connect(func(): session.game.handle_action("open_puzzle"))
	session.game.sandbox.build.changed.connect(func(): if visible: refresh_objects(); refresh_objectives(); refresh_publish())
	for field in [%PuzzleName, %Order, %TimeLimit, %AwardTime, %AwardPieces, %MinHeight, %MaxHeight]:
		if field is LineEdit: field.text_changed.connect(func(_text): metadata_changed())
		else: field.value_changed.connect(func(_value): metadata_changed())
	%Description.text_changed.connect(metadata_changed)
	%Hint.text_changed.connect(metadata_changed)
	%Difficulty.item_selected.connect(func(_index): metadata_changed())
	%Prerequisites.multi_selected.connect(func(_index, _selected): metadata_changed())
	for button in [%SetQuantity, %SetInventoryLimit, %ClearInventoryLimits, %ClearZones, %RemoveZone, %RemoveObjective, %CaptureCamera]:
		button.pressed.connect(metadata_changed)
	for definition in session.game.catalog.query():
		if not definition.library_visible or definition.authoring_only: continue
		%InventoryPiece.add_icon_item(definition.thumbnail, definition.display_name)
		%InventoryPiece.set_item_metadata(%InventoryPiece.item_count - 1, String(definition.id))

func open() -> void:
	refreshing = true
	var data = session.capture()
	%PuzzleName.text = data.name
	%Description.text = data.description
	%Hint.text = "\n".join(data.get("hints", []))
	show_chapter(session.store.chapter_for(data))
	%Order.value = data.order
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
	%Prerequisites.clear()
	var available = session.store.list_puzzles()
	available.append_array(session.store.list_puzzles(true))
	var seen: Dictionary = {}
	for level in available:
		if level.id == data.id or seen.has(level.id): continue
		seen[level.id] = true
		%Prerequisites.add_item(level.name)
		var index = %Prerequisites.item_count - 1
		%Prerequisites.set_item_metadata(index, level.id)
		if level.id in data.get("prerequisites", []): %Prerequisites.select(index, false)
	refreshing = false
	show()
	refresh_publish()
	session.game.get_node("%HUD").refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		session.game.get_node("%HUD").refresh()
		get_viewport().set_input_as_handled()

func refresh_publish() -> void:
	if not session or session.mode!="editor": return
	var data: Dictionary=session.capture()
	var validation: Dictionary=data.get("validation",{})
	var tested: bool=validation.get("physics_success",false)
	var solved: bool=not data.get("solution",[]).is_empty()
	var current: bool=validation.get("fingerprint","")==session.store.fingerprint(data)
	%TestStatus.text=("✓" if tested else "○")+" Player test completed"
	%SolutionStatus.text=("✓" if solved else "○")+" Solution saved"
	%RevisionStatus.text=("✓" if current else "○")+" Current draft verified"
	%Publish.disabled=not session.validate().is_empty()
	%Publish.tooltip_text="Complete a player test and validate this draft to publish." if %Publish.disabled else "Publish this verified puzzle"

func show_chapter(chapter: Dictionary) -> void:
	%ChapterId.text = chapter.get("id", "")
	%ChapterName.text = chapter.get("name", "")
	%ChapterOrder.value = chapter.get("order", 1)
	%ChapterOptional.button_pressed = chapter.get("optional", false)
	%ChapterIntroduction.button_pressed = chapter.get("introduction", false)
	%ChapterRequirements.text = ", ".join(chapter.get("prerequisites", []))

func select_chapter(id: String) -> void:
	if refreshing: return
	var available = session.store.list_puzzles()
	available.append_array(session.store.list_puzzles(true))
	for chapter in session.store.list_chapters(available):
		if chapter.id == id.strip_edges():
			refreshing = true
			show_chapter(chapter)
			refreshing = false
			break
	update_chapter()

func update_chapter() -> void:
	if refreshing: return
	var requirements: Array[String] = []
	for id in %ChapterRequirements.text.split(",", false):
		if not id.strip_edges().is_empty(): requirements.append(id.strip_edges())
	session.puzzle.chapter = {"id": %ChapterId.text.strip_edges(), "name": %ChapterName.text.strip_edges(), "order": int(%ChapterOrder.value), "optional": %ChapterOptional.button_pressed, "introduction": %ChapterIntroduction.button_pressed, "prerequisites": requirements}
	metadata_changed()

func refresh_inventory() -> void:
	%InventoryList.clear()
	for id in session.puzzle.inventory:
		var definition = session.game.catalog.get_piece(id)
		if definition: %InventoryList.add_item("%s × %d" % [definition.display_name, session.puzzle.inventory[id]], definition.thumbnail)

func refresh_inventory_settings() -> void:
	%InventorySetting.clear()
	if %InventoryPiece.item_count == 0: return
	var definition = session.game.catalog.get_piece(%InventoryPiece.get_item_metadata(%InventoryPiece.selected))
	var keys: Array = preload("res://scripts/mechanisms/settings_schema.gd").NUMBERS.get(definition.behavior, {}).keys()
	if definition.behavior == "elevator": keys = ["elevator_height", "elevator_speed"]
	if definition.behavior == "resizable_support": keys = ["support_height"]
	for key in keys:
		%InventorySetting.add_item(key.capitalize())
		%InventorySetting.set_item_metadata(%InventorySetting.item_count - 1, key)

func refresh_zones() -> void:
	%RestrictedList.clear()
	for zone in session.puzzle.restricted_zones: %RestrictedList.add_item("Region (%g, %g) · %g × %g m" % [zone[0], zone[2], zone[3], zone[5]])

func refresh_objects() -> void:
	%ObjectiveTarget.clear()
	%MarbleSource.clear()
	%MarbleSource.add_item("Any marble release")
	%MarbleSource.set_item_metadata(0, "")
	for piece in session.game.sandbox.build.pieces:
		var object_label = piece.definition.display_name + " · " + piece.instance_id.right(6)
		if (piece.definition.behavior == "finish" and %ObjectiveType.selected == 0) or (not piece.supported_events().is_empty() and %ObjectiveType.selected == 1):
			%ObjectiveTarget.add_item(object_label)
			%ObjectiveTarget.set_item_metadata(%ObjectiveTarget.item_count - 1, piece.instance_id)
		if piece.definition.behavior == "start":
			%MarbleSource.add_item(object_label)
			%MarbleSource.set_item_metadata(%MarbleSource.item_count - 1, piece.instance_id)
	refresh_objective_events()

func refresh_objective_events() -> void:
	var delivery = %ObjectiveType.selected == 0
	%ObjectiveEvent.visible = not delivery
	for control in [%MarbleSource, %MarbleSourceLabel, %RequiredCount, %RequiredCountLabel, %AllMarbles]: control.visible = delivery
	%ObjectiveEvent.clear()
	if %ObjectiveTarget.item_count == 0: return
	for event in session.game.sandbox.build.find_piece(%ObjectiveTarget.get_item_metadata(%ObjectiveTarget.selected)).supported_events(): %ObjectiveEvent.add_item(event.capitalize())

func add_objective() -> void:
	if %ObjectiveTarget.item_count == 0: return
	var target = session.game.sandbox.build.find_piece(%ObjectiveTarget.get_item_metadata(%ObjectiveTarget.selected))
	var type = "deliver" if %ObjectiveType.selected == 0 else "activate"
	if type == "deliver" and target.definition.behavior != "finish": %Validation.text = "Choose a collector for delivery"; return
	var data = {"type": type, "target": target.instance_id, "count": int(%RequiredCount.value), "source": %MarbleSource.get_item_metadata(%MarbleSource.selected), "time_limit": %ObjectiveTime.value}
	if type == "activate":
		var events = target.supported_events()
		if events.is_empty(): return
		data.event = events[maxi(0, %ObjectiveEvent.selected)]
	session.puzzle.objectives.append(data)
	metadata_changed()
	refresh_objectives()

func refresh_objectives() -> void:
	%ObjectiveList.clear()
	for objective in session.puzzle.objectives:
		var target = session.game.sandbox.build.find_piece(objective.target)
		%ObjectiveList.add_item(("Deliver %d to " % objective.get("count", 1) if objective.type == "deliver" else "Activate ") + (target.definition.display_name if target else "Missing target"))

func validate_puzzle() -> void:
	var errors := session.validate()
	%Validation.text = "Ready to publish" if errors.is_empty() else "\n".join(errors)
	refresh_publish()

func metadata_changed() -> void:
	if refreshing or session.mode != "editor": return
	session.game.sandbox.build.dirty = true
	session.game.track_name = session.puzzle.name
	session.game.update_name()
	refresh_publish()

func export_package(path: String) -> void:
	session.game.modal_closed()
	var zip = ZIPPacker.new()
	if zip.open(path) != OK: %Validation.text = "Could not open export file"; return
	var count = 0
	for data in session.store.list_puzzles():
		if not data.get("validation", {}).get("physics_success", false): continue
		data = data.duplicate(true)
		# Manifest membership is exported separately to preserve validated fingerprints.
		var frozen := str(data.get("environment_snapshot", ""))
		if not frozen.is_empty():
			if not FileAccess.file_exists(frozen):
				zip.close()
				%Validation.text = "Published environment is missing"
				return
			var filename := frozen.get_file()
			zip.start_file("environments/" + filename)
			zip.write_file(FileAccess.get_file_as_bytes(frozen))
			zip.close_file()
			data.environment_snapshot = "res://resources/campaign/environments/" + filename
		zip.start_file("campaign/" + data.id + ".json")
		zip.write_file(JSON.stringify(data, "\t").to_utf8_buffer())
		zip.close_file()
		count += 1
	zip.start_file("campaign_chapters.json")
	zip.write_file(JSON.stringify({"version": 1, "chapters": session.store.list_chapters(session.store.list_puzzles())}, "\t").to_utf8_buffer())
	zip.close_file()
	zip.close()
	%Validation.text = "Exported %d puzzles. Import the bundle into resources/campaign before building the game." % count

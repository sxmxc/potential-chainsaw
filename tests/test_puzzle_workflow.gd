extends "res://tests/support/scene_test.gd"

var game: Node

func item(id: String, uid: String, z: float, turn: int = 0) -> Dictionary:
	return {"piece": id, "uid": uid, "position": [0.0, 0.0, z], "rotation": turn, "config": {}}

func place(build: BuildManager, id: String, at: Vector3) -> void:
	build.choose(game.catalog.get_piece(id))
	assert_not_null(build.ghost, "Inventory permits " + id)
	if not build.ghost: return
	build.proposed = Transform3D(Basis.IDENTITY, at)
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces).is_empty()
	build.ghost.visible = true
	build.commit()
	build.cancel()

func test_boundary_authoring_and_mode_lifecycle() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	await get_tree().process_frame
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	var boundary: PuzzleBoundary = game.sandbox.boundary
	var input := GutInputSender.new(boundary)
	var authoring: PanelContainer = game.get_node("%HUD").get_node("%PuzzleAuthoring")
	var data := session.store.create()
	data.pieces = [item("sandbox-start", "start", 2), item("sandbox-finish", "finish", -2, 2)]
	data.objectives = [{"type": "deliver", "target": "finish", "count": 1}]
	session.editor(data)
	assert_true(await wait_until(func(): return game.sandbox.camera.global_position.y > 2 and not game.sandbox.camera.is_position_behind(Vector3(2, 0, 2)), 2.0), "The world camera reaches the construction before projecting clicks")
	assert_true(boundary.visible)
	authoring.get_node("%DrawBuild").pressed.emit()
	assert_false(build.enabled, "Drawing suspends construction")
	for point in [Vector3(-2, 0, -2), Vector3(2, 0, 2)]:
		var screen: Vector2 = game.sandbox.camera.unproject_position(point)
		input.mouse_left_button_down(screen)
		input.mouse_left_button_up(screen)
	assert_eq(session.puzzle.bounds.slice(0, 4), [-2.0, -2.0, 2.0, 2.0])
	assert_true(build.enabled and build.dirty, "Completing a boundary resumes construction and marks the draft changed")
	assert_eq(boundary.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 24, "The build box has twelve visible edges")
	authoring.get_node("%DrawZone").pressed.emit()
	for point in [Vector3(-1, 0, -1), Vector3(1, 0, 1)]:
		var screen: Vector2 = game.sandbox.camera.unproject_position(point)
		input.mouse_left_button_down(screen)
		input.mouse_left_button_up(screen)
	assert_eq(session.puzzle.restricted_zones.size(), 1)
	assert_eq(boundary.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 48, "Restricted regions share the boundary display")
	authoring.get_node("%RestrictedList").select(0)
	authoring.get_node("%ModifyZone").pressed.emit()
	for point in [Vector3(-2, 0, -1), Vector3(1, 0, 2)]:
		var screen: Vector2 = game.sandbox.camera.unproject_position(point)
		input.mouse_left_button_down(screen)
		input.mouse_left_button_up(screen)
	assert_eq(session.puzzle.restricted_zones.size(), 1, "Modifying a region replaces it")
	assert_eq(session.puzzle.restricted_zones[0], [-2.0, data.bounds[4], -1.0, 3.0, data.bounds[5] - data.bounds[4], 3.0])
	var before := session.capture()
	build.dirty = false
	authoring.get_node("%DrawBuild").pressed.emit()
	input.key_down(KEY_ESCAPE)
	input.key_up(KEY_ESCAPE)
	assert_true(build.enabled)
	assert_false(build.dirty, "Cancelling does not change the draft")
	assert_eq(session.capture(), before)
	# A mode transition must discard a partially drawn region.
	authoring.get_node("%DrawZone").pressed.emit()
	assert_true(session.test_player())
	assert_true(boundary.visible and build.enabled)
	session.return_editor()
	assert_true(boundary.visible and build.enabled)
	session.player(data)
	assert_true(boundary.visible)
	boundary.begin()
	assert_true(build.enabled, "Campaign cannot start an authoring gesture")
	game.new_track()
	assert_false(boundary.visible)
	assert_eq(build.pieces.size(), 0)

func test_puzzle_workflow() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	await get_tree().process_frame
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	var data = session.store.create()
	data.id = "qa-puzzle-workflow"
	data.pieces = [item("sandbox-start", "start", 2), item("straight", "approach", 1), item("straight", "exit", -1), item("sandbox-finish", "finish", -2, 2)]
	data.bounds = [-2, -3, 2, 3, 0, 2]
	session.editor(data)
	assert_true(session.mode == "editor" and build.rules == null, "Editor uses unrestricted existing construction")
	var hud := game.get_node("%HUD")
	var inspector := hud.get_node("%Inspector")
	var authoring: PanelContainer = hud.get_node("%PuzzleAuthoring")
	build.select(build.pieces[0])
	inspector.get_node("%PermissionsToggle").pressed.emit()
	inspector.get_node("%Preset").select(3)
	inspector.get_node("%Preset").item_selected.emit(3)
	inspector.get_node("%RestrictSetting").button_pressed = true
	var keys := inspector.get_node("%ConfigKeys")
	for index in keys.item_count:
		if keys.get_item_metadata(index) == "release_speed": keys.select(index)
	inspector.get_node("%SettingMin").value = 0.5
	inspector.get_node("%SettingMax").value = 2.0
	inspector.get_node("%ApplyPermissions").pressed.emit()
	assert_true(session.puzzle.permissions.start.configure, "The shared selection inspector authors player permissions")
	authoring.open()
	assert_true(authoring.visible, "Complete native visual authoring panel opens")
	authoring.get_node("%PuzzleName").text = "Shared construction workflow"
	assert_true(build.dirty, "Metadata edits participate in draft saving")
	var inventory: OptionButton = authoring.get_node("%InventoryPiece")
	for index in inventory.item_count:
		if inventory.get_item_metadata(index) == "straight": inventory.select(index)
	authoring.get_node("%Quantity").value = 1
	authoring.get_node("%SetQuantity").pressed.emit()
	authoring.get_node("%AddObjective").pressed.emit()
	assert_eq(session.puzzle.objectives[0].target, "finish", "Objectives use placed construction objects")
	authoring.hide()
	place(build, "environment:partition", Vector3(10, 0, 6))
	game.handle_action("place_scenery")
	assert_true(game.scenery_dialog.visible and not build.enabled, "Scene import suspends world input")
	game.scenery_dialog.hide()
	game.scenery_dialog.file_selected.emit("res://scenes/environments/service_block.tscn")
	assert_true(build.enabled and build.chosen != null, "Imported scenery enters ordinary placement")
	assert_eq(build.pieces.size(), 5, "Choosing a scene does not replace or immediately modify the layout")
	build.proposed = Transform3D(Basis.IDENTITY, Vector3(18, 0, 0))
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces).is_empty()
	assert_true(build.valid, "Imported scene passes shared placement validation")
	build.apply_preview()
	build.commit()
	build.cancel()
	place(build, "sensor", Vector3(5, 0, 6))
	place(build, "gate", Vector3(7, 0, 6))
	var sensor := build.pieces[-2]
	var sensor_uid := sensor.instance_id
	build.select(sensor)
	var wiring: Control = game.get_node("%HUD").get_node("%MechanismWiring")
	wiring.set_tool(true)
	wiring.open_context(sensor_uid, build.pieces[-1].instance_id, "entered", -1, Vector2(700, 300))
	wiring.context_action = "open"
	wiring.get_node("%Apply").pressed.emit()
	assert_eq(sensor.configuration.links.size(), 1, "Authoring uses the shared visual connection editor")
	build.undo()
	assert_true(build.find_piece(sensor_uid).configuration.get("links", []).is_empty(), "Link edits use shared configuration history")
	build.redo()
	assert_eq(build.find_piece(sensor_uid).configuration.links.size(), 1)
	assert_true(session.save(), "Draft saves outside sandbox track storage")
	var original = session.capture()
	var starting_count: int = original.pieces.size()
	assert_eq(original.environment_instances.size(), 2, "Catalog scenery and imported composites retain their saved puzzle records")
	assert_true(build.snapshot(true).all(func(record): return record.has("piece") and record.has("config")), "Construction uses one record format for every object")
	assert_true(not session.publish(), "Publishing an untested revision is rejected")
	game.message_dialog.close()
	assert_true(session.test_player(), "Test as Player enters restricted session")
	assert_true(build.rules != null and session.mode == "test", "Campaign restrictions active in test")
	var first = build.pieces[0]
	build.select(first)
	build.move_selected()
	assert_true(build.ghost == null, "Fixed piece drag blocked")
	build.rotate_piece()
	assert_true(first.rotation.y == 0, "Fixed piece rotation blocked")
	build.delete_selected()
	assert_true(build.pieces.size() == starting_count, "Fixed deletion blocked")
	build.move_selected(true)
	assert_true(build.ghost == null, "Fixed duplication blocked")
	var config = first.configuration.duplicate(true)
	config.release_speed = 3
	assert_true(not build.configure_selected(config, "Forbidden setting"), "Mechanism configuration range enforced")
	config.release_speed = 1.5
	assert_true(build.configure_selected(config, "Allowed setting"), "Fixed release allows permitted setting")
	place(build, "straight", Vector3(5, 0, 0))
	assert_true(build.pieces.size() == starting_count, "Out-of-bounds placement rolls back atomically")
	place(build, "straight", Vector3.ZERO)
	assert_true(build.pieces.size() == starting_count + 1 and build.rules.remaining("straight", build.snapshot()) == 0, "Normal placement consumes inventory")
	build.choose(game.catalog.get_piece("straight"))
	assert_true(build.ghost == null, "Inventory exhaustion blocks further placement")
	build.undo()
	assert_true(build.pieces.size() == starting_count and build.rules.remaining("straight", build.snapshot()) == 1, "Undo restores inventory")
	build.redo()
	assert_true(build.pieces.size() == starting_count + 1 and build.rules.remaining("straight", build.snapshot()) == 0, "Redo consumes inventory")
	build.select(build.pieces[-1])
	build.delete_selected()
	assert_true(build.rules.remaining("straight", build.snapshot()) == 1, "Removing player piece restores inventory")
	build.undo()
	assert_true(game.qa_test(), "Player solution starts actual physics")
	for frame in 1500:
		await get_tree().physics_frame
		if game.sandbox.simulation.state in [SimulationManager.State.SUCCESS, SimulationManager.State.FAILED]: break
	assert_true(game.sandbox.simulation.state == SimulationManager.State.SUCCESS, "Objectives detect physical collector arrival")
	assert_true(session.preserve_solution(), "Successful player solution preserved separately")
	assert_true(session.authored.pieces == original.pieces and session.authored.solution.size() == starting_count + 1, "Solution never overwrites starting construction")
	session.return_editor()
	assert_true(build.snapshot() == original.pieces and session.mode == "editor", "Returning from test restores authored layout")
	assert_true(session.publish(), "Verified revision publishes")
	var levels = session.store.list_puzzles()
	assert_true(levels.any(func(level): return level.id == data.id), "Published content appears in campaign")
	session.player(session.puzzle)
	place(build, "straight", Vector3.ZERO)
	assert_true(game.qa_test(), "Published level runs in Campaign")
	for frame in 1500:
		await get_tree().physics_frame
		if game.sandbox.simulation.state in [SimulationManager.State.SUCCESS, SimulationManager.State.FAILED]: break
	assert_true(game.sandbox.simulation.state == SimulationManager.State.SUCCESS and session.store.progress.has(data.id), "Campaign completion records progress")
	var reopened = PuzzleStore.new(game.catalog)
	assert_true(reopened.progress.has(data.id), "Progress persists across store reload")
	session.return_editor()
	session.editor(original)
	session.puzzle.description = "Revised"
	assert_true(not session.publish(), "Content edit invalidates working solution proof")
	game.message_dialog.close()

extends "res://tests/support/scene_test.gd"

var game: Node

func item(id: String, uid: String, z: float, turn: int = 0) -> Dictionary:
	return {"piece": id, "uid": uid, "position": [0.0, 0.0, z], "rotation": turn, "config": {}}

func place(build: BuildManager, id: String, at: Vector3) -> void:
	build.choose(game.workspace.catalog.get_piece(id))
	assert_not_null(build.ghost, "Inventory permits " + id)
	if not build.ghost: return
	build.proposed = Transform3D(Basis.IDENTITY, at)
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces).is_empty()
	build.ghost.visible = true
	build.commit()
	build.cancel()

func test_sandbox_runs_without_a_finish_or_puzzle_timeout() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.workspace.session.sandbox()
	var build: BuildManager = game.workspace.world.build
	var simulation: SimulationManager = game.workspace.world.simulation
	assert_false(simulation.start(), "Sandbox still requires a marble release")
	build.spawn(game.workspace.catalog.get_piece("sandbox-start"), Transform3D.IDENTITY, "release")
	var layout := build.snapshot()
	assert_true(game.workspace.session.start_simulation(), "A release without a finish can start a Sandbox run")
	assert_eq(simulation.marbles.size(), 1, "The release spawns a real physics marble")
	# Cross the former timeout without waiting 90 seconds in the test.
	simulation.elapsed = 90.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_gt(simulation.elapsed, 90.0)
	assert_eq(simulation.state, SimulationManager.State.RUNNING)
	simulation.toggle_pause()
	assert_eq(simulation.state, SimulationManager.State.PAUSED)
	simulation.toggle_pause()
	assert_eq(simulation.state, SimulationManager.State.RUNNING)
	simulation.reset()
	assert_eq(simulation.state, SimulationManager.State.BUILD)
	assert_true(simulation.marbles.is_empty() and build.enabled)
	assert_eq(build.snapshot(), layout, "Reset preserves a finish-free construction")
	var puzzle: Dictionary = game.workspace.session.store.create()
	puzzle.pieces = layout
	puzzle.objectives = [{"type": "deliver", "target": "finish", "count": 1}]
	game.workspace.session.player(puzzle)
	assert_false(simulation.start(), "A puzzle with delivery objectives still requires a collector")
	assert_eq(simulation.state, SimulationManager.State.BUILD)
	puzzle.objectives = []
	puzzle.time_limit = 1.0
	game.workspace.session.player(puzzle)
	assert_true(simulation.start())
	simulation.elapsed = 1.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(simulation.state, SimulationManager.State.FAILED, "Puzzle time limits still apply")

func test_boundary_authoring_and_mode_lifecycle() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	await get_tree().process_frame
	var session: ConstructionSession = game.workspace.session
	var build: BuildManager = game.workspace.world.build
	var boundary: PuzzleBoundary = game.workspace.world.boundary
	var input := GutInputSender.new(boundary)
	var authoring: PanelContainer = game.get_node("Workspace/Interface/HUD/Margin/Layout/Body/AuthoringSlot/PuzzleAuthoring")
	var data := session.store.create()
	data.pieces = [item("sandbox-start", "start", 2), item("sandbox-finish", "finish", -2, 2)]
	data.objectives = [{"type": "deliver", "target": "finish", "count": 1}]
	session.editor(data)
	assert_true(await wait_until(func(): return game.workspace.world.camera.global_position.y > 2 and not game.workspace.world.camera.is_position_behind(Vector3(2, 0, 2)), 2.0), "The world camera reaches the construction before projecting clicks")
	assert_true(boundary.visible)
	authoring.get_node("%DrawBuild").pressed.emit()
	assert_false(build.enabled, "Drawing suspends construction")
	for point in [Vector3(-2, 0, -2), Vector3(2, 0, 2)]:
		var screen: Vector2 = game.workspace.world.camera.unproject_position(point)
		input.mouse_left_button_down(screen)
		input.mouse_left_button_up(screen)
	assert_eq(session.puzzle.bounds.slice(0, 4), [-2.0, -2.0, 2.0, 2.0])
	assert_true(build.enabled and build.dirty, "Completing a boundary resumes construction and marks the draft changed")
	assert_eq(boundary.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 24, "The build box has twelve visible edges")
	authoring.get_node("%DrawZone").pressed.emit()
	for point in [Vector3(-1, 0, -1), Vector3(1, 0, 1)]:
		var screen: Vector2 = game.workspace.world.camera.unproject_position(point)
		input.mouse_left_button_down(screen)
		input.mouse_left_button_up(screen)
	assert_eq(session.puzzle.restricted_zones.size(), 1)
	assert_eq(boundary.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 48, "Restricted regions share the boundary display")
	authoring.get_node("%RestrictedList").select(0)
	authoring.get_node("%ModifyZone").pressed.emit()
	for point in [Vector3(-2, 0, -1), Vector3(1, 0, 2)]:
		var screen: Vector2 = game.workspace.world.camera.unproject_position(point)
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
	game.workspace.session.sandbox()
	assert_false(boundary.visible)
	assert_eq(build.pieces.size(), 0)

func test_shared_workspace_workflow() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	await get_tree().process_frame
	var session: ConstructionSession = game.workspace.session
	var build: BuildManager = game.workspace.world.build
	game.handle_action("sandbox")
	place(build, "straight", Vector3.ZERO)
	game.workspace.hud.get_node("%FileToolbar").get_node("%Save").pressed.emit()
	assert_true(game.name_dialog.visible, "Sandbox Save opens the personal track dialog")
	game.name_field.text = "Workspace transition fixture"
	game.name_dialog.confirmed.emit()
	game.name_dialog.close()
	var personal_track_id := session.track_id
	assert_false(personal_track_id.is_empty())
	assert_eq(session.serializer.load_track(personal_track_id).pieces, build.snapshot(), "Personal tracks retain their own save format")
	var data = session.store.create()
	data.id = "qa-puzzle-workflow"
	data.pieces = [item("sandbox-start", "start", 2), item("straight", "approach", 1), item("straight", "exit", -1), item("sandbox-finish", "finish", -2, 2)]
	data.bounds = [-2, -3, 2, 3, 0, 2]
	session.editor(data, true)
	session.store.campaign_directory = test_directory.path_join("resources/campaign")
	session.store.manifest_path = test_directory.path_join("resources/campaign_manifest.json")
	session.store.chapters_path = test_directory.path_join("resources/campaign_chapters.json")
	DirAccess.make_dir_recursive_absolute(session.store.campaign_directory)
	assert_true(session.store.write(session.store.chapters_path, {"version": 1, "chapters": [{"id": "chapter-1", "name": "Chapter 1", "order": 1, "prerequisites": []}]}))
	assert_true(session.is_authoring and build.rules == null, "Editor uses unrestricted existing construction")
	var hud := game.get_node("Workspace/Interface/HUD")
	var inspector := hud.get_node("%Inspector")
	var authoring: PanelContainer = game.get_node("Workspace/Interface/HUD/Margin/Layout/Body/AuthoringSlot/PuzzleAuthoring")
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
	place(build, "environment:column", Vector3(18, 0, 0))
	place(build, "sensor", Vector3(5, 0, 6))
	place(build, "gate", Vector3(7, 0, 6))
	var sensor := build.pieces[-2]
	var sensor_uid := sensor.instance_id
	build.select(sensor)
	var wiring: Control = game.get_node("Workspace/Interface/HUD").get_node("%MechanismWiring")
	wiring.set_tool(true)
	wiring.open_context(sensor_uid, build.pieces[-1].instance_id, "entered", -1, Vector2(700, 300))
	wiring.context_action = "open"
	wiring.get_node("%Apply").pressed.emit()
	assert_eq(sensor.configuration.links.size(), 1, "Authoring uses the shared visual connection editor")
	build.undo()
	assert_true(build.find_piece(sensor_uid).configuration.get("links", []).is_empty(), "Link edits use shared configuration history")
	build.redo()
	assert_eq(build.find_piece(sensor_uid).configuration.links.size(), 1)
	assert_true(session.save_draft(), "Draft saves outside sandbox track storage")
	var original = session.capture()
	var starting_count: int = original.pieces.size()
	assert_eq(original.environment_instances.size(), 2, "Catalog scenery retains its saved puzzle records")
	assert_true(build.snapshot(true).all(func(record): return record.has("piece") and record.has("config")), "Construction uses one record format for every object")
	assert_true(not session.publish(), "Publishing an untested revision is rejected")
	game.message_dialog.close()
	assert_true(session.test_player(), "Test as Player enters restricted session")
	assert_true(build.rules != null and session.is_testing, "Campaign restrictions active in test")
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
	build.choose(game.workspace.catalog.get_piece("straight"))
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
		if game.workspace.world.simulation.state in [SimulationManager.State.SUCCESS, SimulationManager.State.FAILED]: break
	assert_true(game.workspace.world.simulation.state == SimulationManager.State.SUCCESS, "Objectives detect physical collector arrival")
	assert_true(session.preserve_solution(), "Successful player solution preserved separately")
	assert_true(session.authored.pieces == original.pieces and session.authored.solution.size() == starting_count + 1, "Solution never overwrites starting construction")
	session.return_editor()
	assert_true(build.snapshot() == original.pieces and session.is_authoring, "Returning from test restores authored layout")
	assert_true(session.publish(), "Verified revision publishes")
	var levels = session.store.load_campaign().levels
	assert_true(levels.any(func(level): return level.id == data.id), "Published content appears in campaign")
	assert_true(session.store.load_campaign().unlocked(levels[0], session.store.progress), "First registered level is unlocked")
	assert_eq(levels[0].campaign.chapter.id, "chapter-1")
	assert_false(JSON.parse_string(FileAccess.get_file_as_string(session.store.campaign_directory.path_join(data.id + ".json"))).has("campaign"), "Packaged gameplay definition excludes registration")
	assert_true(session.publish(), "Identical promotion is idempotent")
	assert_eq(session.store.load_campaign().levels.size(), 1, "Promotion does not duplicate entries")
	session.player(levels[0])
	place(build, "straight", Vector3.ZERO)
	assert_true(game.qa_test(), "Published level runs in Campaign")
	for frame in 1500:
		await get_tree().physics_frame
		if game.workspace.world.simulation.state in [SimulationManager.State.SUCCESS, SimulationManager.State.FAILED]: break
	assert_true(game.workspace.world.simulation.state == SimulationManager.State.SUCCESS and session.store.progress.has(data.id), "Campaign completion records progress")
	var reopened = PuzzleStore.new(game.workspace.catalog)
	assert_true(reopened.progress.has(data.id), "Progress persists across store reload")
	game.handle_action("sandbox")
	assert_true(session.is_sandbox and build.rules == null and not build.authoring, "Campaign restrictions are cleared before Sandbox")
	session.editor(original)
	session.puzzle.description = "Revised"
	assert_true(not session.publish(), "Content edit invalidates working solution proof")
	game.message_dialog.close()
	game.handle_action("sandbox")
	assert_true(session.is_sandbox and build.rules == null and not build.authoring, "Leaving Campaign or Authoring restores unrestricted Sandbox")
	assert_true(game.workspace.world.simulation.puzzle.is_empty())
	assert_true(build.snap.environment_solids.is_empty())
	assert_false(build.history.has_undo(), "Context transitions start a new construction history")
	assert_false(build.connect_mode)
	assert_false(game.workspace.hud.get_node("%MechanismWiring").overlay_enabled)
	assert_true(session.authored.is_empty() and not session.test_success, "Temporary player-test state does not survive into Sandbox")
	assert_false(game.workspace.authoring.visible)
	assert_true(game.workspace.hud.get_node("%FileToolbar").get_node("%Save").visible)
	assert_true(session.load_track(personal_track_id, false))
	assert_eq(build.pieces.size(), 1, "The personal track reopens after puzzle contexts")
	assert_eq(build.pieces[0].definition.id, &"straight")

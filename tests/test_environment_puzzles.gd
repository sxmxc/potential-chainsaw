extends "res://tests/support/scene_test.gd"

var game: Node
const IDS = ["chapter1-service-block", "chapter1-loading-loft", "chapter1-shared-clearance"]

func before_each() -> void:
	super()
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	await get_tree().process_frame

func draft(index: int) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://resources/puzzle_drafts/" + IDS[index] + ".json"))

func test_bundled_validation_matches_current_definitions() -> void:
	for index in 3:
		var data := draft(index)
		assert_true(data.validation.get("physics_success", false))
		assert_eq(data.validation.get("fingerprint", ""), game.puzzle_session.store.fingerprint(data), data.name + ": proof matches bundled content")
		game.puzzle_session.editor(data)
		assert_eq(game.puzzle_session.store.fingerprint(game.puzzle_session.capture()), data.validation.fingerprint, "Editor load does not stale proof")

func run_physics(data: Dictionary) -> void:
	assert_true(game.sandbox.simulation.start())
	for frame in int(float(data.time_limit) * 120 + 5):
		await get_tree().physics_frame
		if game.sandbox.simulation.state in [SimulationManager.State.SUCCESS, SimulationManager.State.FAILED]: break

func test_solutions_use_player_placement_and_physics(index = use_parameters([0, 1, 2])) -> void:
	var data := draft(index)
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	assert_eq(session.store.validate(data), [], data.name + ": valid definition")
	session.editor(data)
	assert_true(session.test_player())
	for record in data.solution:
		if data.pieces.any(func(piece): return piece.uid == record.uid): continue
		build.choose(game.catalog.get_piece(record.piece))
		assert_not_null(build.ghost, "Inventory permits " + record.piece)
		if not build.ghost: return
		build.ghost.apply_configuration(record.config)
		build.preview_items[0].config = build.ghost.configuration.duplicate(true)
		build.preview_items[0].definition = build.ghost.definition
		build.proposed = Transform3D(Basis(Vector3.UP, int(record.rotation) * PI / 2), Vector3(record.position[0], record.position[1], record.position[2]))
		var problem := build.snap.validate_group(build.preview_items, build.proposed, build.pieces)
		assert_eq(problem, "", data.name + ": " + record.uid + " placement")
		build.valid = problem.is_empty()
		build.ghost.visible = true
		build.commit()
		build.cancel()
	assert_eq(build.rules.validate(build.snapshot()), "")
	var solution := build.snapshot()
	await run_physics(data)
	var positions: Array = []
	for marble in game.sandbox.simulation.marbles: positions.append(marble.position)
	assert_eq(game.sandbox.simulation.state, SimulationManager.State.SUCCESS, data.name + ": completion; marble positions " + str(positions))
	assert_true(session.test_success)
	if session.test_success:
		print("PROTOTYPE_EVIDENCE " + JSON.stringify({"id": data.id, "validation": {"physics_success": true, "fingerprint": session.successful_fingerprint, "seconds": session.successful_time, "engine": Engine.get_version_info().string, "tested_at": Time.get_datetime_string_from_system(true)}}))
	game.sandbox.simulation.reset()
	assert_eq(build.snapshot(), solution, "Reset keeps construction")
	session.return_editor()
	assert_eq(build.snapshot().size(), data.pieces.size(), "Return restores incomplete baseline")
	assert_not_null(session.environment_node)
	session.sandbox()
	assert_null(session.environment_node)
	assert_eq(build.snap.environment_solids, [])

func test_starting_layouts_do_not_complete(index = use_parameters([0, 1, 2])) -> void:
	var data := draft(index)
	game.puzzle_session.player(data, true)
	await run_physics(data)
	assert_ne(game.sandbox.simulation.state, SimulationManager.State.SUCCESS)

func test_solids_passages_history_and_save_load() -> void:
	var data := draft(0)
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	session.editor(data)
	assert_true(session.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.store.drafts_directory + "/" + data.id + ".json"))
	assert_eq(saved.environment, data.environment)
	assert_true(session.test_player())
	var straight := game.catalog.get_piece("straight") as PieceDefinition
	var inside := Transform3D(Basis.IDENTITY, Vector3(0, 1, -1.5))
	assert_eq(build.snap.validate(straight, inside, []), "Blocked by the environment")
	var allowed := Transform3D(Basis.IDENTITY, Vector3(3, 1, -0.5))
	assert_eq(build.snap.validate(straight, allowed, []), "")
	var candidate: Array = build.snapshot()
	candidate.append({"uid": "exploit", "piece": "straight", "position": [0, 1, -1.5], "rotation": 0, "config": {}})
	assert_eq(build.rules.validate(candidate), "Blocked by the environment")
	assert_eq(build.snap.validate_group([{"definition": straight, "local": Transform3D.IDENTITY}], inside, []), "Blocked by the environment")
	assert_false(session.store.list_puzzles().any(func(level): return level.id in IDS), "Drafts are excluded from campaign")
	assert_eq(session.store.list_puzzles(true).filter(func(level): return level.id in IDS).size(), 3)
	# A legal free placement remains an ordinary undoable construction edit.
	build.choose(straight)
	build.proposed = allowed
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces).is_empty()
	assert_true(build.valid, "Free placement passes real placement validation")
	build.ghost.show()
	build.commit()
	build.cancel()
	assert_eq(build.pieces.size(), 3)
	build.undo()
	assert_eq(build.pieces.size(), 2)
	build.redo()
	assert_eq(build.pieces.size(), 3)
	assert_not_null(session.environment_node)

func test_environment_physically_blocks_marble_and_keeps_open_space() -> void:
	game.puzzle_session.player(draft(0), true)
	var body: RigidBody3D = autoqfree(load("res://scenes/marble.tscn").instantiate())
	game.sandbox.add_child(body)
	body.position = Vector3(0, 1, -0.5)
	body.linear_velocity = Vector3(0, 0, -2)
	for frame in 80: await get_tree().physics_frame
	assert_gt(body.position.z, -1.5, "Physical marble cannot pass through partition")
	game.puzzle_session.player(draft(1), true)
	var straight := game.catalog.get_piece("straight") as PieceDefinition
	assert_eq(game.sandbox.build.snap.validate(straight, Transform3D(Basis.IDENTITY, Vector3(0, 0, 1)), []), "", "Space below canopy is usable")
	assert_eq(game.sandbox.build.snap.validate(straight, Transform3D(Basis.IDENTITY, Vector3(0, 2, 1)), []), "Blocked by the environment")
	var lift = TrackPiece.ElevatorGeometry.configured(game.catalog.get_piece("bucket-elevator"), {"elevator_height": 4, "elevator_speed": 0.8})
	assert_eq(game.sandbox.build.snap.validate(lift, Transform3D.IDENTITY, []), "Blocked by the environment", "A lift cannot grow through canopy")

func test_editable_environment_roundtrip_and_player_isolation() -> void:
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	session.editor(draft(0))
	session.set_environment_editing(true)
	assert_false(build.enabled, "Track input is suspended during environment editing")
	assert_true(build.grid_mesh.visible, "Environment placement keeps the shared grid visible")
	assert_true(session.place_environment("machine", Vector3(6, 0, 0)))
	var uid := session.environment_selected
	assert_true(session.transform_environment(Vector3(7, 0.5, 1), 1))
	assert_true(session.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.store.drafts_directory + "/" + session.puzzle.id + ".json"))
	assert_eq(saved.environment_instances[0].position, [7.0, 0.5, 1.0])
	assert_eq(saved.environment_instances[0].rotation, 1.0)
	session.editor(saved)
	assert_eq(session.puzzle.environment_instances[0].uid, uid)
	var object := session.environment_node.get_node(NodePath(uid)) as Node3D
	assert_almost_eq(object.position, Vector3(7, 0.5, 1), Vector3.ONE * 0.001)
	assert_eq(object.get_node("Body").collision_layer, 1)
	assert_eq(build.snap.validate(game.catalog.get_piece("straight"), Transform3D(Basis.IDENTITY, Vector3(7, 0.5, 1)), []), "Blocked by the environment")
	assert_true(session.test_player())
	assert_false(session.environment_editing)
	assert_false(session.place_environment("deck", Vector3(8, 0, 0)))
	session.select_environment(uid)
	assert_false(session.transform_environment(Vector3.ZERO, 2))
	session.remove_environment()
	assert_eq(session.puzzle.environment_instances, saved.environment_instances)
	assert_eq(build.pieces.size(), saved.pieces.size(), "Scenery stays outside construction/inventory")
	session.return_editor()
	session.select_environment(uid)
	session.remove_environment()
	assert_eq(session.puzzle.environment_instances.size(), 0)
	session.environment_undo()
	assert_eq(session.puzzle.environment_instances.size(), 1)
	session.environment_undo(true)
	assert_eq(session.puzzle.environment_instances.size(), 0)

func test_environment_edits_stale_proof_and_reject_track_intersection() -> void:
	var session: PuzzleSession = game.puzzle_session
	session.editor(draft(0))
	session.puzzle.version = 2
	var proof := session.store.fingerprint(session.capture())
	assert_true(session.place_environment("column", Vector3(6, 0, 0)))
	assert_ne(session.store.fingerprint(session.capture()), proof)
	assert_ne(session.store.fingerprint(session.capture()), session.puzzle.validation.fingerprint)
	var changed := session.store.fingerprint(session.capture())
	assert_true(session.transform_environment(Vector3(7, 0, 0), 1))
	assert_ne(session.store.fingerprint(session.capture()), changed)
	var before: Array = session.puzzle.environment_instances.duplicate(true)
	var track_position: Vector3 = game.sandbox.build.pieces[0].position
	assert_false(session.transform_environment(track_position, 0), "Cannot place scenery through a starting track")
	assert_eq(session.puzzle.environment_instances, before)
	session.remove_environment()
	assert_eq(session.store.fingerprint(session.capture()), proof, "Removing the added object restores effective authored content")

func test_native_environment_snapshot_is_self_contained() -> void:
	var data := draft(0)
	data.environment_instances = [{"uid": "env-test", "asset": "deck", "position": [6, 1, 0], "rotation": 1}]
	var path: String = game.puzzle_session.store.drafts_directory + "/environment.tscn"
	assert_eq(PuzzleEnvironment.freeze(data, path), OK)
	assert_eq(ResourceLoader.get_dependencies(path).size(), 0, "Published snapshot embeds mesh, texture and collision resources")
	data.environment_snapshot = path
	game.puzzle_session.player(data)
	assert_not_null(game.puzzle_session.environment_node.get_node("env-test/Body/Solid"))
	assert_eq(game.sandbox.build.snap.environment_solids.size(), PuzzleEnvironment.inspect_definition(data).solids.size())

func test_environment_shortcuts_after_leaving_catalog_focus() -> void:
	var session: PuzzleSession = game.puzzle_session
	session.editor(draft(0))
	game.authoring.open()
	game.authoring.get_node("%Tabs").current_tab = 7
	assert_true(session.place_environment("column", Vector3(6, 0, 0)))
	var uid := session.environment_selected
	var sender := GutInputSender.new(Input)
	autofree(sender)
	game.authoring.get_node("%EnvironmentCatalog").grab_focus()
	sender.mouse_motion(Vector2(550, 300))
	await get_tree().process_frame
	sender.mouse_left_button_down(Vector2(550, 300))
	await get_tree().process_frame
	sender.mouse_left_button_up(Vector2(550, 300))
	await get_tree().process_frame
	assert_null(get_viewport().gui_get_focus_owner(), "World click releases catalog focus")
	session.select_environment(uid)
	sender.key_down(KEY_R)
	await get_tree().process_frame
	sender.key_up(KEY_R)
	await get_tree().process_frame
	assert_eq(session.environment_item().rotation, 1, "Rotation uses the shared InputMap shortcut")
	sender.release_all()

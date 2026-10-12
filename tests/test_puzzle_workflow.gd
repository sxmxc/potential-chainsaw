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
	data.inventory = {"straight": 1}
	data.objectives = [{"type": "deliver", "target": "finish", "count": 1}]
	data.bounds = [-2, -3, 2, 3, 0, 2]
	session.editor(data)
	assert_true(session.mode == "editor" and build.rules == null, "Editor uses unrestricted existing construction")
	build.select(build.pieces[0])
	session.set_permissions({"move": false, "rotate": false, "configure": true, "remove": false, "duplicate": false, "config_keys": ["release_speed"], "limits": {"release_speed": [0.5, 2.0]}})
	game.authoring.open()
	assert_true(game.authoring.visible, "Complete native visual authoring panel opens")
	game.authoring.hide()
	assert_true(session.save(), "Draft saves outside sandbox track storage")
	var original = session.capture()
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
	assert_true(build.pieces.size() == 4, "Fixed deletion blocked")
	build.move_selected(true)
	assert_true(build.ghost == null, "Fixed duplication blocked")
	var config = first.configuration.duplicate(true)
	config.release_speed = 3
	assert_true(not build.configure_selected(config, "Forbidden setting"), "Mechanism configuration range enforced")
	config.release_speed = 1.5
	assert_true(build.configure_selected(config, "Allowed setting"), "Fixed release allows permitted setting")
	place(build, "straight", Vector3(5, 0, 0))
	assert_true(build.pieces.size() == 4, "Out-of-bounds placement rolls back atomically")
	place(build, "straight", Vector3.ZERO)
	assert_true(build.pieces.size() == 5 and build.rules.remaining("straight", build.snapshot()) == 0, "Normal placement consumes inventory")
	build.choose(game.catalog.get_piece("straight"))
	assert_true(build.ghost == null, "Inventory exhaustion blocks further placement")
	build.undo()
	assert_true(build.pieces.size() == 4 and build.rules.remaining("straight", build.snapshot()) == 1, "Undo restores inventory")
	build.redo()
	assert_true(build.pieces.size() == 5 and build.rules.remaining("straight", build.snapshot()) == 0, "Redo consumes inventory")
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
	assert_true(session.authored.pieces == original.pieces and session.authored.solution.size() == 5, "Solution never overwrites starting construction")
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

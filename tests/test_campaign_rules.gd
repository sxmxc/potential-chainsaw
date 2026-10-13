extends "res://tests/support/scene_test.gd"

var game: Node
var session: PuzzleSession
var build: BuildManager

func ticks(count: int) -> void:
	for i in count: await get_tree().physics_frame

func record(id: String, uid: String, at: Vector3, config: Dictionary = {}) -> Dictionary:
	return {"piece": id, "uid": uid, "position": [at.x, at.y, at.z], "rotation": 0, "config": config}

func test_campaign_rules() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	await get_tree().process_frame
	session = game.puzzle_session
	build = game.sandbox.build
	var data = session.store.create()
	data.pieces = [record("straight", "locked", Vector3.ZERO), record("straight", "editable", Vector3(2, 0, 0))]
	data.permissions.editable = {"move": true, "rotate": true, "remove": true, "duplicate": true}
	data.inventory = {"straight": 2}
	session.player(data, true)
	build.set_selection(build.pieces)
	build.move_selected()
	assert_true(build.ghost == null, "Mixed group cannot move fixed members")
	build.rotate_piece()
	assert_true(build.snapshot() == data.pieces, "Mixed group rotation is atomic")
	build.elevate_selected(0.5)
	assert_true(build.snapshot() == data.pieces, "Mixed group elevation is atomic")
	build.move_selected(true)
	assert_true(build.ghost == null, "Mixed group duplication blocked")
	build.delete_selected()
	assert_true(build.pieces.size() == 2, "Mixed group deletion blocked")
	build.select(build.pieces[1])
	build.move_selected(true)
	build.proposed.origin = Vector3(4, 0, 0)
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces, build.moving_group).is_empty()
	assert_true(build.valid, "Proposed edit passes real placement validation")
	build.ghost.visible = true
	build.commit()
	assert_true(build.pieces.size() == 3 and build.rules.remaining("straight", build.snapshot()) == 1, "Duplicating authored editable piece costs inventory")
	build.undo()
	assert_true(build.rules.remaining("straight", build.snapshot()) == 2, "Undo duplication refunds exactly one")
	build.redo()
	build.select(build.pieces[1])
	build.delete_selected()
	assert_true(build.rules.remaining("straight", build.snapshot()) == 1, "Removing authored piece does not manufacture inventory")
	data = session.store.create()
	data.inventory = {"bucket-elevator": 1}
	data.configuration_limits = {"bucket-elevator": {"elevator_height": [4, 4]}}
	session.player(data, true)
	build.choose(game.catalog.get_piece("bucket-elevator"))
	build.proposed = Transform3D.IDENTITY
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces, build.moving_group).is_empty()
	assert_true(build.valid, "Proposed edit passes real placement validation")
	build.ghost.visible = true
	build.commit()
	build.cancel()
	build.select(build.pieces[0])
	assert_true(not build.configure_selected({"elevator_height": 6, "elevator_speed": 0.8}, "Too tall"), "Inventory elevator height restriction enforced")
	build.rules.puzzle.configuration_limits = {}
	build.rules.puzzle.bounds[5] = 7
	assert_true(not build.configure_selected({"elevator_height": 6, "elevator_speed": 0.8}, "Outside height"), "Configured elevator volume respects elevation boundary")
	session.sandbox()
	build.restore([])
	var source = build.spawn(game.catalog.get_piece("sensor"), Transform3D.IDENTITY, "source", {"links": [{"event": "entered", "target": "target", "action": "open"}]})
	var target = build.spawn(game.catalog.get_piece("gate"), Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)), "target")
	build.set_selection([source, target])
	build.move_selected(true)
	build.proposed.origin = Vector3(0, 0, 3)
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces, build.moving_group).is_empty()
	assert_true(build.valid, "Proposed edit passes real placement validation")
	build.ghost.visible = true
	build.commit()
	var duplicate_source = build.pieces[2]
	var duplicate_target = build.pieces[3]
	assert_true(duplicate_source.instance_id != source.instance_id and duplicate_source.configuration.links[0].target == duplicate_target.instance_id, "Duplicate group remaps internal links to fresh IDs")
	build.select(duplicate_target)
	build.delete_selected()
	assert_true(duplicate_source.configuration.links.is_empty() and source.configuration.links.size() == 1, "Deletion cleans only links to the removed target")
	build.undo()
	assert_true(build.pieces.size() == 4 and build.pieces[2].configuration.links.size() == 1, "Undo restores target and link together")
	var serializer = TrackSerializer.new(game.catalog)
	var payload = {"version": 1, "name": "Link round trip", "pieces": build.snapshot()}
	assert_true(serializer.decode(JSON.stringify(payload)).pieces == payload.pieces, "Mechanism links survive existing track serializer")
	build.pieces[0].configuration.links[0].action = "unsupported"
	assert_true(not game.sandbox.simulation.validate_links().is_empty(), "Unsupported actions are rejected by link validator")
	data = session.store.create()
	data.pieces = [record("sandbox-start", "release", Vector3(0, 0, 2), {"quantity": 2, "interval": 0.8}), record("straight", "a", Vector3(0, 0, 1)), record("straight", "b", Vector3.ZERO), record("straight", "c", Vector3(0, 0, -1)), record("sandbox-finish", "goal", Vector3(0, 0, -2))]
	data.pieces[-1].rotation = 2
	data.objectives = [{"type": "deliver", "target": "goal", "count": 2, "source": "release"}]
	session.player(data, true)
	assert_true(game.qa_test(), "Multi-marble campaign begins")
	game.sandbox.simulation.toggle_pause()
	await ticks(150)
	assert_true(game.sandbox.simulation.marbles.size() == 1 and game.sandbox.simulation.elapsed == 0, "Pause suspends timed releases")
	game.sandbox.simulation.toggle_pause()
	for frame in 1800:
		await get_tree().physics_frame
		if game.sandbox.simulation.state in [SimulationManager.State.SUCCESS, SimulationManager.State.FAILED]: break
	assert_true(game.sandbox.simulation.state == SimulationManager.State.SUCCESS and game.sandbox.simulation.objectives.deliveries.size() == 2, "Two real marbles fulfill quantity and source objectives")
	game.sandbox.simulation.reset()
	assert_true(game.sandbox.simulation.marbles.is_empty() and game.sandbox.simulation.pending_releases.is_empty(), "Reset clears all bodies and pending releases")
	data = session.store.create()
	data.pieces = [record("sandbox-start", "release", Vector3(0, 0, 2)), record("gate", "gate", Vector3.ZERO, {"delay": 1})]
	data.objectives = [{"type": "activate", "target": "gate", "event": "opened"}]
	session.player(data, true)
	assert_true(game.qa_test(), "Activation objective works without a collector")
	await ticks(150)
	assert_true(game.sandbox.simulation.state == SimulationManager.State.SUCCESS, "Timed gate event fulfills activation objective")
	session.store.progress.clear()
	var levels: Array = [{"id": "qa-first", "prerequisites": []}, {"id": "qa-second", "prerequisites": ["qa-first"]}]
	assert_true(session.store.unlocked(levels[0], levels) and not session.store.unlocked(levels[1], levels), "New progress unlocks only the first level")
	levels[0].awards = {"time": 10, "pieces": 5}
	session.store.complete(levels[0], 4, 3)
	assert_true(session.store.unlocked(levels[1], levels), "Completion unlocks prerequisite level")
	assert_true(session.store.progress["qa-first"].awards.size() == 2, "Optional awards persist without gating progression")

extends "res://tests/support/scene_test.gd"

var game: Node

func before_each() -> void:
	super()
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	await get_tree().process_frame

func level(index: int) -> Dictionary:
	return game.workspace.session.store.load_campaign().levels.filter(func(data): return data.id == "campaign-%02d" % (index + 1))[0]

func run_physics(data: Dictionary) -> void:
	assert_true(game.workspace.world.simulation.start(), data.name + ": simulation starts")
	for frame in int(float(data.time_limit) * 120 + 5):
		await get_tree().physics_frame
		if game.workspace.world.simulation.state in [SimulationManager.State.SUCCESS, SimulationManager.State.FAILED]: break

func test_reference_solution(index = use_parameters([0,1,2,3,4,5,6,7,8,9])) -> void:
	var data = level(index)
	var session: ConstructionSession = game.workspace.session
	var build: BuildManager = game.workspace.world.build
	session.player(data, true)
	for record in data.solution:
		var existing: BuildingPiece
		for piece in build.pieces:
			if piece.instance_id == record.uid: existing = piece; break
		if existing:
			if existing.configuration != record.config:
				build.select(existing)
				assert_true(build.configure_selected(record.config, "Reference configuration"), data.name + ": configuration permitted")
		else:
			build.choose(game.workspace.catalog.get_piece(record.piece))
			assert_not_null(build.ghost, data.name + ": reference inventory permits " + record.piece)
			if not build.ghost: return
			build.ghost.apply_configuration(record.config)
			build.preview_items[0].config = build.ghost.configuration.duplicate(true)
			build.preview_items[0].definition = build.ghost.definition
			build.proposed = Transform3D(Basis(Vector3.UP, int(record.rotation) * PI / 2), Vector3(record.position[0], record.position[1], record.position[2]))
			build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces).is_empty()
			build.ghost.visible = true
			assert_true(build.valid, data.name + ": reference placement permitted")
			build.commit()
			build.cancel()
	assert_eq(build.rules.validate(build.snapshot()), "", data.name + ": reference follows puzzle rules")
	var solution = build.snapshot()
	await run_physics(data)
	assert_eq(game.workspace.world.simulation.state, SimulationManager.State.SUCCESS, data.name + ": physical objectives complete")
	game.workspace.world.simulation.reset()
	assert_eq(build.snapshot(), solution, data.name + ": reset preserves construction")

func test_incomplete_layout_does_not_complete(index = use_parameters([0,1,2,3,4,5,6,7,8,9])) -> void:
	var data = level(index)
	game.workspace.session.player(data, true)
	await run_physics(data)
	assert_ne(game.workspace.world.simulation.state, SimulationManager.State.SUCCESS, data.name + ": incomplete starting layout cannot complete")

extends "res://tests/support/game_test.gd"

func test_collection_outputs_track_deliveries_and_wired_actions_across_runs() -> void:
	var workspace := load("res://scenes/construction_workspace.tscn").instantiate() as ConstructionWorkspace
	add_child_autoqfree(workspace)
	await get_tree().process_frame
	var build := workspace.world.build
	var simulation := workspace.world.simulation
	for index in 2:
		build.spawn(workspace.catalog.get_piece("sandbox-start"), Transform3D(Basis.IDENTITY, Vector3(index * 3, 3, 0)), "release-%d" % index)
	var collector := build.spawn(workspace.catalog.get_piece("sandbox-finish"), Transform3D.IDENTITY, "collector", {"links": [{"event": "collected", "target": "counter", "action": "increment"}]})
	var counter := build.spawn(workspace.catalog.get_piece("logic-counter"), Transform3D(Basis.IDENTITY, Vector3(4, 2, 0)), "counter")
	simulation.puzzle = {"objectives": [{"type": "deliver", "target": "collector", "source": "release-1", "count": 1}]}
	for run in 2:
		assert_true(simulation.start())
		assert_eq(simulation.marbles.size(), 2)
		var first := simulation.marbles[0]
		var second := simulation.marbles[1]
		assert_eq(first.get_parent(), simulation, "Initial release transfers ownership through its output")
		assert_eq(first.get_meta("marble_id"), "release-0:0")
		assert_eq(second.get_meta("marble_id"), "release-1:0")
		var catcher := collector.behaviors[0] as MarbleCollector
		catcher.call("_collect_marble", first)
		catcher.call("_collect_marble", first)
		assert_eq(simulation.objectives.delivery_count("collector"), 1, "Repeated collection cannot count a marble twice")
		assert_false(simulation.objectives.satisfied(simulation.elapsed), "The objective filters the release identity")
		assert_eq(counter.behaviors[0].get("count"), 1, "Collection reaches a wired receiver exactly once")
		assert_true(simulation.objectives.activation_seen("collector", "collected"))
		catcher.call("_collect_marble", second)
		assert_true(simulation.objectives.satisfied(simulation.elapsed))
		assert_eq(counter.behaviors[0].get("count"), 2)
		await get_tree().physics_frame
		await get_tree().physics_frame
		assert_eq(simulation.state, SimulationManager.State.SUCCESS)
		assert_false(first.visible)
		assert_eq(first.collision_layer, 0)
		simulation.reset()
		assert_true(simulation.marbles.is_empty())
		assert_eq(simulation.objectives.delivery_count("collector"), 0)
		assert_false(simulation.objectives.has_activity("collector"))
		assert_eq(counter.behaviors[0].get("count"), 0)

func test_physics_collection_ends_sandbox_and_restart_uses_current_piece_nodes() -> void:
	var workspace := load("res://scenes/construction_workspace.tscn").instantiate() as ConstructionWorkspace
	add_child_autoqfree(workspace)
	await get_tree().process_frame
	var build := workspace.world.build
	var simulation := workspace.world.simulation
	build.spawn(workspace.catalog.get_piece("sandbox-start"), Transform3D(Basis.IDENTITY, Vector3(3, 3, 0)), "release", {"release_speed": 0})
	build.spawn(workspace.catalog.get_piece("sandbox-finish"), Transform3D.IDENTITY, "collector")
	var construction := build.snapshot()
	for run in 2:
		assert_true(simulation.start())
		var body := simulation.marbles[0]
		body.global_position = Vector3(0, 0.5, 0)
		body.reset_physics_interpolation()
		for frame in 12:
			await get_tree().physics_frame
			if simulation.state == SimulationManager.State.SUCCESS: break
		assert_eq(simulation.state, SimulationManager.State.SUCCESS, "The real collector Area ends a Sandbox run")
		assert_eq(simulation.objectives.delivery_count("collector"), 1)
		simulation.reset()
		build.restore(construction)
		assert_eq(build.snapshot(), construction, "Replacing live nodes retains the build and fresh run connections")

func test_sandbox_runs_multiple_releases_and_resets_them_together() -> void:
	var workspace := load("res://scenes/construction_workspace.tscn").instantiate() as ConstructionWorkspace
	add_child_autoqfree(workspace)
	await get_tree().process_frame
	var build := workspace.world.build
	var simulation := workspace.world.simulation
	assert_false(workspace.session.start_simulation(), "An empty build still needs a release")
	assert_eq(simulation.state, SimulationManager.State.BUILD)
	for index in 3:
		build.spawn(workspace.catalog.get_piece("sandbox-start"), Transform3D(Basis.IDENTITY, Vector3(index * 3, 2, 0)), "release-%d" % index, {"quantity": 2, "interval": 0.6, "start_delay": index * 0.1})
	var construction := build.snapshot()
	assert_true(workspace.session.start_simulation(), "Sandbox accepts more than one release")
	while simulation.elapsed < 0.9 and simulation.state == SimulationManager.State.RUNNING:
		await get_tree().physics_frame
	assert_eq(simulation.marbles.size(), 6, "Every release runs its schedule")
	var sources: Dictionary = {}
	var identities: Dictionary = {}
	for body in simulation.marbles:
		var source: String = body.get_meta("source")
		sources[source] = sources.get(source, 0) + 1
		identities[body.get_meta("marble_id")] = true
	assert_eq(sources, {"release-0": 2, "release-1": 2, "release-2": 2})
	assert_eq(identities.size(), 6, "Release ordinals remain unique across sources")
	simulation.toggle_pause()
	for body in simulation.marbles: assert_true(body.freeze)
	simulation.toggle_pause()
	for body in simulation.marbles: assert_false(body.freeze)
	simulation.reset()
	assert_true(simulation.marbles.is_empty())
	assert_eq(build.snapshot(), construction, "Reset retains every start drop")
	assert_true(workspace.session.start_simulation())
	assert_eq(simulation.marbles.size(), 1, "Restart begins a fresh schedule without retaining old marbles")
	simulation.reset()

func test_run_pause_and_reset_respect_workspace_input() -> void:
	var workspace := load("res://scenes/construction_workspace.tscn").instantiate() as ConstructionWorkspace
	add_child_autoqfree(workspace)
	await get_tree().process_frame
	var world := workspace.world
	var build := world.build
	build.spawn(workspace.catalog.get_piece("sandbox-start"), Transform3D.IDENTITY, "release")
	var construction := build.snapshot()
	build.set_connect_mode(true)
	assert_true(world.simulation.start())
	assert_false(build.enabled, "Running disables construction")
	assert_true(world.camera.enabled, "The camera remains usable during a run")
	world.boundary.cancel()
	assert_false(build.enabled, "Boundary cancellation cannot enable construction during a run")
	world.simulation.toggle_pause()
	assert_false(build.enabled, "Pausing does not allow construction edits")
	world.simulation.toggle_pause()
	world.simulation.reset()
	assert_true(build.enabled)
	assert_true(build.connect_mode, "Reset restores Connect after construction becomes available")
	assert_eq(build.snapshot(), construction, "Reset preserves the build")
	assert_true(world.simulation.start())
	workspace.suspend_input()
	world.simulation.reset()
	assert_false(build.enabled, "Reset cannot override modal suspension")
	assert_false(world.camera.enabled)
	assert_false(build.grid_mesh.visible)
	build.choose(workspace.catalog.get_piece("straight"))
	assert_null(build.chosen, "Construction operations remain blocked while suspended")
	workspace.resume_input()
	assert_true(build.enabled)
	assert_true(build.grid_mesh.visible)
	workspace.deactivate()
	world.simulation.reset()
	assert_false(build.enabled, "Reset cannot reactivate a hidden workspace")
	workspace.activate()
	assert_true(build.enabled)

func test_boundary_tools_and_context_transitions_share_the_input_gate() -> void:
	var workspace := load("res://scenes/construction_workspace.tscn").instantiate() as ConstructionWorkspace
	add_child_autoqfree(workspace)
	await get_tree().process_frame
	workspace.session.editor()
	var world := workspace.world
	var boundary := world.boundary
	boundary.set_editing(true)
	assert_false(world.build.enabled, "Region selection excludes piece editing")
	assert_true(world.camera.enabled)
	boundary.begin(true)
	assert_eq(boundary.tool, "zone")
	boundary.cancel()
	assert_false(world.build.enabled, "Cancelling drawing retains region selection")
	boundary.set_editing(false)
	assert_true(world.build.enabled)
	boundary.begin()
	assert_false(world.build.enabled, "Drawing also excludes piece editing outside selection mode")
	workspace.suspend_input()
	assert_true(boundary.tool.is_empty())
	assert_false(world.build.enabled, "Cancelling a drawing cannot override modal suspension")
	workspace.resume_input()
	assert_true(world.build.enabled)
	boundary.set_editing(true)
	workspace.session.player(workspace.session.store.create(), true)
	assert_false(boundary.selecting)
	assert_true(world.build.enabled, "Entering player context leaves boundary editing behind")
	workspace.session.sandbox()
	assert_true(world.build.enabled)

func test_world_without_interactive_host_stays_disabled_across_runs() -> void:
	var world := load("res://scenes/world.tscn").instantiate() as WorldManager
	add_child_autoqfree(world)
	await get_tree().process_frame
	var catalog := PieceCatalog.new()
	world.configure(catalog)
	world.load_construction([{"uid": "release", "piece": "sandbox-start", "position": [0, 0, 0], "rotation": 0, "config": {}}])
	assert_false(world.build.enabled, "A world such as the showcase starts without player input")
	assert_false(world.camera.enabled)
	assert_true(world.simulation.start())
	world.simulation.toggle_pause()
	world.simulation.reset()
	assert_false(world.build.enabled, "Showcase reset needs no compensating disable call")
	assert_false(world.build.grid_mesh.visible)
	assert_true(world.simulation.start(), "A noninteractive world can still restart its machine")
	world.simulation.reset()
	assert_false(world.build.enabled)

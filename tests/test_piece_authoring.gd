extends "res://tests/support/scene_test.gd"

var game: Node
var build: BuildManager

func before_each() -> void:
	super()
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.workspace.session.sandbox()
	build = game.workspace.world.build
	await get_tree().process_frame

func ticks(count: int) -> void:
	for index in count: await get_tree().physics_frame

func test_existing_capabilities_and_preview_collision() -> void:
	var plain := build.spawn(game.workspace.catalog.get_piece("straight"), Transform3D.IDENTITY)
	assert_true(plain.behaviors.is_empty())
	assert_false(plain.bodies.is_empty())
	game.workspace.session.editor()
	var obstacle := build.spawn(game.workspace.catalog.get_piece("environment:partition"), Transform3D.IDENTITY)
	assert_true(obstacle.behaviors.is_empty())
	assert_false(obstacle.bodies.is_empty())
	game.workspace.session.sandbox()
	for id in ["sensor", "gate", "launcher", "diverter", "fan-two", "fan-four", "fan-standing-two", "fan-standing-four", "fan-simple-two", "fan-simple-four", "bucket-elevator", "support-single", "sandbox-start", "sandbox-finish"]:
		var definition: PieceDefinition = game.workspace.catalog.get_piece(id)
		var piece := build.spawn(definition, Transform3D.IDENTITY)
		assert_eq(piece.behaviors.size(), 1, id + " supplies its behavior through the saved scene")
		assert_false(piece.meshes.is_empty())
		assert_false(piece.bodies.is_empty())
		assert_eq(piece.behaviors[0].configuration_fields.map(func(field): return field.key), definition.settings.map(func(field): return field.key), "Live components and saved metadata share the same fields")
		build.choose(definition)
		assert_true(build.ghost.behaviors[0].preview_only)
		for collider in build.ghost.model_node.find_children("*", "CollisionObject3D", true, false):
			assert_eq(collider.collision_layer, 0)
			assert_eq(collider.collision_mask, 0)
		build.cancel()
		build.restore([])
	var fan := build.spawn(game.workspace.catalog.get_piece("fan-two"), Transform3D.IDENTITY)
	assert_true(fan.definition.connectors.is_empty())
	assert_true(fan.input_ports.has("activate") and fan.output_ports.has("activated"), "Existing connector-free pieces can send and receive")

func test_unlisted_composed_behavior_uses_its_settings_and_ports() -> void:
	var definition := load("res://tests/fixtures/composed_behavior.tres") as PieceDefinition
	assert_eq(definition.settings.map(func(field): return String(field.key)), ["threshold", "label", "invert"])
	var piece := build.spawn(definition, Transform3D.IDENTITY, "processor")
	assert_eq(piece.behaviors.size(), 2)
	assert_eq(piece.input_ports.keys(), ["trigger", "value", "ping", "other_value"])
	assert_eq(piece.output_ports.keys(), ["passed", "state", "pong", "other_state"])
	assert_eq(piece.compatible_actions(piece, "passed"), ["trigger", "ping"])
	assert_eq(piece.compatible_actions(piece, "state"), ["value", "other_value"])
	assert_true(piece.compatible_actions(piece, "missing").is_empty())
	assert_eq(piece.compatible_events(piece), ["passed", "state", "pong", "other_state"])
	assert_true(build.validate_wiring().is_empty())
	assert_true(piece.configuration.is_empty(), "Runtime defaults do not rewrite saved overrides")
	assert_eq(piece.behaviors[0].config.threshold, 2.0)
	build.select(piece)
	await get_tree().process_frame
	var editor = game.get_node("Workspace/Interface/HUD").get_node("%Inspector").get_node("%MechanismSettings")
	assert_true(editor.fields.has("threshold") and editor.fields.has("invert"))
	var text_input: LineEdit = editor.fields.label
	assert_eq(text_input.text, "Processor")
	text_input.text = "Sorting station"
	text_input.text_submitted.emit(text_input.text)
	assert_eq(piece.behaviors[0].config.label, "Sorting station")
	assert_eq(piece.serialize().config.label, "Sorting station", "Text overrides are serialized")
	assert_true(build.configure_selected({"threshold": 4.0}, "Threshold"))
	assert_eq(piece.behaviors[0].config.threshold, 4.0)
	build.spawn(game.workspace.catalog.get_piece("sandbox-start"), Transform3D(Basis.IDENTITY, Vector3(4, 0, 0)), "release", {"start_delay": 60})
	game.workspace.world.simulation.puzzle = {"objectives": []}
	assert_true(build.edit_link("processor", -1, {"event": "passed", "target": "processor", "action": "ping"}))
	assert_false(build.edit_link("processor", -1, {"event": "state", "target": "processor", "action": "ping"}))
	assert_true(game.workspace.world.simulation.start())
	piece.input_ports.trigger.receive("trigger")
	assert_eq(piece.behaviors[1].received_pulses, 1, "The pulse reaches another component on the same piece")
	piece.input_ports.value.receive("value", 3.0)
	assert_false(piece.behaviors[0].output_values.state, "Authored settings affect the actual processor")
	piece.input_ports.value.receive("value", 5.0)
	assert_true(piece.behaviors[0].output_values.state)
	game.workspace.world.simulation.reset()
	assert_eq(piece.behaviors[1].received_pulses, 0)
	assert_false(piece.behaviors[0].output_values.state)

func test_state_feedback_settles_and_pulse_feedback_is_bounded() -> void:
	var piece := build.spawn(load("res://tests/fixtures/composed_behavior.tres"), Transform3D.IDENTITY, "processor")
	build.spawn(game.workspace.catalog.get_piece("sandbox-start"), Transform3D(Basis.IDENTITY, Vector3(4, 0, 0)), "release", {"start_delay": 60})
	var sim: SimulationManager = game.workspace.world.simulation
	sim.puzzle = {"objectives": []}
	assert_true(build.edit_link("processor", -1, {"event": "state", "target": "processor", "action": "other_value"}))
	assert_true(build.edit_link("processor", -1, {"event": "other_state", "target": "processor", "action": "value"}))
	assert_true(sim.start())
	piece.input_ports.value.receive("value", true)
	assert_true(piece.behaviors[0].output_values.state and piece.behaviors[1].output_values.other_state)
	assert_eq(sim.state, SimulationManager.State.RUNNING)
	sim.toggle_pause()
	assert_false(piece.input_ports.value.receive("value", false))
	sim.toggle_pause()
	sim.reset()
	assert_false(piece.behaviors[0].output_values.state)
	assert_true(build.edit_link("processor", -1, {"event": "passed", "target": "processor", "action": "trigger"}))
	assert_true(sim.start())
	piece.input_ports.trigger.receive("trigger")
	assert_eq(sim.state, SimulationManager.State.FAILED, "Non-settling feedback stops after bounded work")
	assert_true(sim.signal_queue.is_empty())
	sim.reset()
	assert_eq(piece.behaviors[0].received_pulses, 0)

func test_release_and_collector_labels_edit_clear_and_reload() -> void:
	for id in ["sandbox-start", "sandbox-finish"]:
		build.restore([])
		var piece := build.spawn(game.workspace.catalog.get_piece(id), Transform3D.IDENTITY, "labeled")
		build.select(piece)
		await get_tree().process_frame
		var editor = game.get_node("Workspace/Interface/HUD").get_node("%Inspector").get_node("%MechanismSettings")
		var input: LineEdit = editor.fields.display_label
		input.text = "Route A"
		input.text_submitted.emit(input.text)
		assert_eq(piece.behaviors[0].display_label.text, "Route A")
		assert_true(piece.behaviors[0].display_label.visible)
		var save_id: String = game.workspace.session.serializer.save_track("Labeled route", build.snapshot())
		assert_false(save_id.is_empty())
		build.restore(game.workspace.session.serializer.load_track(save_id).pieces)
		piece = build.find_piece("labeled")
		assert_eq(piece.behaviors[0].display_label.text, "Route A")
		build.select(piece)
		assert_true(build.configure_selected({"display_label": ""}, "Clear label"))
		assert_false(piece.behaviors[0].display_label.visible)
		build.undo()
		piece = build.find_piece("labeled")
		assert_eq(piece.behaviors[0].display_label.text, "Route A")
		build.redo()
		assert_false(build.find_piece("labeled").behaviors[0].display_label.visible)

func test_initial_release_pulse_reaches_a_receiver_before_physics_advances() -> void:
	build.spawn(game.workspace.catalog.get_piece("sandbox-start"), Transform3D.IDENTITY, "release")
	var gate := build.spawn(game.workspace.catalog.get_piece("gate"), Transform3D(Basis.IDENTITY, Vector3(4, 0, 0)), "gate")
	assert_true(build.edit_link("release", -1, {"event": "released", "target": "gate", "action": "open"}))
	game.workspace.world.simulation.puzzle = {"objectives": []}
	assert_true(game.workspace.world.simulation.start())
	assert_true(gate.behaviors[0].open, "All receivers start before queued initial outputs propagate")
	assert_eq(game.workspace.world.simulation.marbles.size(), 1)

func test_sensor_indicator_tracks_multiple_marbles_and_isolated_materials() -> void:
	var sensor := build.spawn(game.workspace.catalog.get_piece("sensor"), Transform3D.IDENTITY)
	var behavior_node := sensor.behaviors[0]
	var other := build.spawn(game.workspace.catalog.get_piece("sensor"), Transform3D(Basis.IDENTITY, Vector3(4, 0, 0)))
	behavior_node.active = true
	var bodies: Array[RigidBody3D] = []
	for x in [-0.1, 0.1]:
		var body: RigidBody3D = load("res://scenes/marble.tscn").instantiate()
		add_child_autofree(body)
		body.gravity_scale = 0
		body.position = Vector3(x, 0.55, 0)
		bodies.append(body)
	await ticks(8)
	await get_tree().process_frame
	var indicator := sensor.model_node.get_node("Indicator") as MeshInstance3D
	var untouched := other.model_node.get_node("Indicator") as MeshInstance3D
	assert_true(behavior_node.output_values.occupied)
	assert_ne(indicator.material_override.albedo_color, untouched.material_override.albedo_color)
	bodies[0].position = Vector3(0, 3, 0)
	await ticks(8)
	assert_true(behavior_node.output_values.occupied, "One remaining marble keeps the occupied state")
	bodies[1].position = Vector3(0, 3, 0)
	await ticks(8)
	await get_tree().process_frame
	assert_false(behavior_node.output_values.occupied)
	assert_eq(indicator.material_override.albedo_color, untouched.material_override.albedo_color)
	behavior_node.reset()
	assert_false(behavior_node.output_values.occupied)

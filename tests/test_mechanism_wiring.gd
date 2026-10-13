extends "res://tests/support/scene_test.gd"

var game: Node
var sender: GutInputSender
var build: BuildManager
var wiring: Control

func before_each() -> void:
	super()
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	game.new_track()
	build = game.sandbox.build
	wiring = game.get_node("%HUD").get_node("%MechanismWiring")
	game.get_node("%HUD").library_open = false
	game.get_node("%HUD").refresh()
	sender = autofree(GutInputSender.new(Input))
	await settle()

func after_each() -> void:
	sender.release_all()
	await super()

func settle() -> void:
	for frame in 6: await get_tree().process_frame

func drag(source: BuildingPiece, target: BuildingPiece) -> void:
	var start: Vector2 = wiring.port_position(source, true, 0)
	var finish: Vector2 = wiring.port_position(target, false)
	sender.mouse_motion(start)
	await settle()
	sender.mouse_left_button_down(start)
	await settle()
	assert_false(wiring.dragging.is_empty(), "Output handle starts a connection gesture")
	sender.mouse_motion(finish)
	await settle()
	assert_true(wiring.valid_receiver(wiring.hovered_handle), "Input responds as a valid receiver")
	sender.mouse_left_button_up(finish)
	await settle()
	assert_true(wiring.get_node("%Context").visible, "Multiple actions open the contextual chooser")

func choose_action(label: String) -> void:
	for button in wiring.get_node("%Actions").get_children():
		if button.text == label:
			button.pressed.emit()
			return
	fail_test("Missing supported action: " + label)

func test_visual_wiring_construction_and_physics() -> void:
	var sensor := build.spawn(game.catalog.get_piece("sensor"), Transform3D.IDENTITY, "trigger")
	var gate := build.spawn(game.catalog.get_piece("gate"), Transform3D(Basis.IDENTITY, Vector3(3, 0, 0)), "gate")
	var second := build.spawn(game.catalog.get_piece("gate"), Transform3D(Basis.IDENTITY, Vector3(-3, 0, 0)), "second")
	build.frame_all()
	await wait_seconds(0.6)
	await settle()
	game.get_node("%HUD").get_node("%BuildToolbar").get_node("%Connect").pressed.emit()
	await drag(sensor, gate)
	assert_true(sensor.configuration.get("links", []).is_empty(), "A gesture and chooser do not write persistent state")
	choose_action("Open")
	wiring.get_node("%Apply").pressed.emit()
	assert_eq(sensor.configuration.links, [{"event": "entered", "target": "gate", "action": "open"}])
	await drag(sensor, second)
	choose_action("Open")
	wiring.get_node("%Apply").pressed.emit()
	assert_eq(sensor.configuration.links.size(), 2, "One source can control two receivers")
	wiring.set_tool(false)
	game.get_node("%HUD").get_node("%BuildToolbar").get_node("%Connections").pressed.emit()
	await settle()
	assert_true(wiring.overlay_enabled and not build.connect_mode, "Overlay visibility is independent of editing")
	assert_true(wiring.handles.is_empty(), "Inspection overlay hides authoring handles")
	assert_eq(wiring.wires.size(), 2)
	wiring.toggle_overlay()
	assert_false(wiring.overlay_enabled or build.connect_mode, "Overlay switches off without entering another tool")
	assert_eq(sensor.configuration.links.size(), 2, "Visibility never changes authored links")
	wiring.toggle_overlay()
	var wire: Dictionary = wiring.wires[0]
	assert_lt(wire.points[0].distance_to(wiring.port_position(sensor, true, 0)), 0.1, "Directed curve starts at source output")
	assert_lt(wire.points[-1].distance_to(wiring.port_position(gate, false)), 0.1, "Directed curve ends at receiver input")
	build.select(sensor)
	build.move_selected()
	build.proposed = Transform3D(Basis.IDENTITY, Vector3(0, 0, 2))
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces, build.moving_group).is_empty()
	build.apply_preview()
	wiring.refresh_projection()
	assert_gt(wiring.wires[0].points[0].distance_to(wire.points[0]), 20.0, "Wiring follows the live move preview before committing")
	build.commit()
	await settle()
	assert_lt(wiring.wires[0].points[0].distance_to(wiring.port_position(sensor, true, 0)), 0.1, "Wiring follows moved pieces")
	var assembly: Array[BuildingPiece] = [sensor, gate, second]
	build.set_selection(assembly)
	build.move_selected(true)
	build.proposed = Transform3D(Basis.IDENTITY, Vector3(0, 0, 8))
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces).is_empty()
	build.apply_preview()
	build.commit()
	assert_eq(build.selection.size(), 3)
	var duplicate_source := build.selected
	for link: Dictionary in duplicate_source.configuration.links:
		assert_true(build.find_piece(link.target) in build.selection, "Duplicated assembly links stay inside the duplicate")
		assert_false(link.target in ["gate", "second"])
	var save_id: String = game.serializer.save_track("Wiring fixture", build.snapshot())
	assert_false(save_id.is_empty())
	build.restore(game.serializer.load_track(save_id).pieces)
	assert_eq(build.find_piece("trigger").configuration.links.size(), 2, "Existing save format round-trips wiring")
	wiring.set_tool(true)
	await settle()
	wire = wiring.wires.filter(func(value): return value.source == "trigger" and value.index == 0)[0]
	var click: Vector2 = wire.points[16]
	sender.mouse_motion(click)
	await settle()
	sender.mouse_left_click_at(click)
	await sender.idle
	await settle()
	assert_true(wiring.get_node("%Context").visible, "Clicking a curve opens its relationship")
	choose_action("Close")
	wiring.get_node("%Apply").pressed.emit()
	assert_eq(build.find_piece("trigger").configuration.links[0].action, "close")
	build.undo()
	assert_eq(build.find_piece("trigger").configuration.links[0].action, "open")
	assert_true(build.connect_mode, "Undo keeps the active tool")
	build.redo()
	assert_eq(build.find_piece("trigger").configuration.links[0].action, "close")
	wiring.open_context("trigger", "gate", "entered", 0, click)
	wiring.get_node("%Remove").pressed.emit()
	assert_eq(build.find_piece("trigger").configuration.links.size(), 1, "Deleting one relationship preserves the other")
	build.undo()
	build.undo()
	assert_eq(build.find_piece("trigger").configuration.links[0].action, "open")
	await settle()
	if DisplayServer.get_name() != "headless" and OS.has_environment("MARBLE_ENGINEER_WIRING_CAPTURE"):
		await RenderingServer.frame_post_draw
		assert_eq(get_viewport().get_texture().get_image().save_png(OS.get_environment("MARBLE_ENGINEER_WIRING_CAPTURE")), OK)
	var simulation: SimulationManager = game.sandbox.simulation
	build.spawn(game.catalog.get_piece("sandbox-start"), Transform3D(Basis.IDENTITY, Vector3(9, 0, 0)), "release", {"start_delay": 60})
	simulation.puzzle = {"objectives": []}
	assert_true(simulation.start())
	await settle()
	assert_true(wiring.overlay_enabled, "Simulation preserves the overlay preference")
	assert_false(wiring.get_node("%Context").visible, "Simulation hides editing controls")
	var marble: RigidBody3D = load("res://scenes/marble.tscn").instantiate()
	add_child_autofree(marble)
	marble.position = build.find_piece("trigger").position + Vector3(0, 0.46, 0.4)
	marble.linear_velocity = Vector3(0, 0, -0.6)
	for tick in 80: await get_tree().physics_frame
	assert_true(build.find_piece("gate").mechanism_component.open, "A physical sensor crossing opens the linked gate")
	assert_true(build.find_piece("second").mechanism_component.open, "The same crossing reaches the second receiver")
	simulation.reset()
	assert_true(build.connect_mode and wiring.overlay_enabled, "Return to build restores tool and overlay")
	build.select(build.find_piece("gate"))
	build.delete_selected()
	assert_eq(build.find_piece("trigger").configuration.links.size(), 1, "Deleting a receiver cleans only dangling links")

func test_cancellation_and_locked_configuration() -> void:
	var sensor := build.spawn(game.catalog.get_piece("sensor"), Transform3D.IDENTITY, "trigger")
	var gate := build.spawn(game.catalog.get_piece("gate"), Transform3D(Basis.IDENTITY, Vector3(3, 0, 0)), "gate")
	build.frame_all()
	await wait_seconds(0.6)
	await settle()
	wiring.set_tool(true)
	await drag(sensor, gate)
	wiring.escape()
	assert_false(wiring.get_node("%Context").visible)
	assert_true(sensor.configuration.get("links", []).is_empty())
	var start: Vector2 = wiring.port_position(sensor, true, 0)
	sender.mouse_left_button_down(start)
	await settle()
	wiring.escape()
	assert_true(wiring.dragging.is_empty(), "Escape cancels a drag")
	sender.mouse_left_button_up(Vector2(900, 500))
	await settle()
	assert_true(sensor.configuration.get("links", []).is_empty(), "Cancelled drag never commits")
	wiring.escape()
	assert_false(build.connect_mode, "Escape from idle returns to normal construction")
	build.rules = PuzzleRules.new({"pieces": build.snapshot(), "permissions": {}, "inventory": {}}, game.catalog, [])
	assert_false(build.edit_link("trigger", -1, {"event": "entered", "target": "gate", "action": "open"}), "Actual operation respects configuration permission")
	assert_true(sensor.configuration.get("links", []).is_empty())
	build.rules = null
	assert_false(build.edit_link("trigger", -1, {"event": "unsupported", "target": "gate", "action": "open"}), "Cannot invent unsupported events")
	assert_false(build.edit_link("trigger", -1, {"event": "entered", "target": "gate", "action": "unsupported"}), "Cannot invent unsupported actions")

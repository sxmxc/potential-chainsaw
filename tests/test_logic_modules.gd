extends "res://tests/support/game_test.gd"

var workspace: ConstructionWorkspace
var build: BuildManager
var simulation: SimulationManager

func before_each() -> void:
	super.before_each()
	workspace = load("res://scenes/construction_workspace.tscn").instantiate()
	add_child_autoqfree(workspace)
	await get_tree().process_frame
	build = workspace.world.build
	simulation = workspace.world.simulation

func module(id: String, config: Dictionary = {}) -> BuildingPiece:
	return build.spawn(build.catalog.get_piece("logic-" + id), Transform3D(Basis.IDENTITY, Vector3(4, 2, 0)), id, config)

func link(source: BuildingPiece, event: String, target: BuildingPiece, action: String) -> void:
	var links: Array = source.configuration.get("links", [])
	links.append({"event": event, "target": target.instance_id, "action": action})
	source.configuration.links = links

func release(config: Dictionary = {}) -> BuildingPiece:
	return build.spawn(build.catalog.get_piece("sandbox-start"), Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)), "release", config)

func test_memory_commands_retain_state_and_reset_defaults() -> void:
	var piece := module("memory", {"initial_state": true})
	var behavior := piece.behaviors[0]
	assert_true(behavior.output_values.state)
	watch_signals(behavior)
	behavior.start_run()
	for command in ["reset", "reset", "set", "toggle", "toggle"]: assert_true(behavior.receive(command))
	assert_true(behavior.output_values.state)
	assert_signal_emit_count(behavior, "output_raised", 8, "Four changes each emit state and changed")
	behavior.active = false
	assert_false(behavior.receive("reset"), "Paused commands are ignored")
	behavior.reset()
	assert_true(behavior.output_values.state)
	assert_false(behavior.active)

func test_counter_latches_once_until_reset_and_restores_initial_count() -> void:
	var behavior := module("counter", {"initial_count": 1, "threshold": 3}).behaviors[0]
	watch_signals(behavior)
	behavior.start_run()
	for index in 5: behavior.receive("increment")
	assert_eq(behavior.get("count"), 6)
	assert_eq(behavior.get_node("ReadoutHUD").text, "6", "Optional billboard readout follows the live count")
	assert_true(behavior.output_values.threshold_reached)
	assert_signal_emit_count(behavior, "output_raised", 2, "One reached event and one state transition")
	behavior.receive("reset")
	assert_eq(behavior.get("count"), 1)
	assert_false(behavior.output_values.threshold_reached)
	behavior.receive("increment")
	behavior.receive("increment")
	assert_true(behavior.output_values.threshold_reached)
	behavior.reset()
	assert_eq(behavior.get("count"), 1)
	assert_false(behavior.output_values.threshold_reached)

func test_gate_truth_tables_use_states_and_suppress_unchanged_outputs() -> void:
	for id in ["and", "or", "not"]:
		var behavior := module(id).behaviors[0]
		behavior.start_run()
		for a in [false, true]:
			for b in [false, true]:
				behavior.receive("a", a)
				if id != "not": behavior.receive("b", b)
				var expected: bool = (a and b) if id == "and" else ((a or b) if id == "or" else not a)
				assert_eq(bool(behavior.output_values.result), expected, "%s: %s %s" % [id, a, b])
		watch_signals(behavior)
		behavior.receive("a", true)
		if id != "not": behavior.receive("b", true)
		assert_signal_not_emitted(behavior, "output_raised", "Identical state deliveries emit nothing")
		behavior.reset()
		assert_eq(bool(behavior.output_values.result), id == "not")

func test_dropper_signal_supply_cooldown_pause_and_automatic_compatibility() -> void:
	var source := release({"signal_controlled": true, "quantity": 2, "interval": 0.6, "start_delay": 0.2})
	var behavior := source.behaviors[0]
	assert_true(simulation.start())
	assert_eq(simulation.marbles.size(), 0)
	behavior.receive("release")
	assert_eq(simulation.marbles.size(), 0, "Start delay blocks early commands")
	behavior.call("_physics_process", 0.2)
	behavior.receive("release")
	behavior.receive("release")
	assert_eq(simulation.marbles.size(), 1, "Repeated pulses do not bypass cooldown")
	simulation.toggle_pause()
	assert_false(behavior.receive("release"))
	simulation.toggle_pause()
	behavior.call("_physics_process", 0.61)
	behavior.receive("release")
	behavior.call("_physics_process", 1.0)
	behavior.receive("release")
	assert_eq(simulation.marbles.size(), 2, "Quantity is finite")
	assert_ne(simulation.marbles[0].get_meta("marble_id"), simulation.marbles[1].get_meta("marble_id"))
	simulation.reset()
	source.apply_configuration({"quantity": 2, "interval": 0.6})
	assert_true(simulation.start())
	assert_eq(simulation.marbles.size(), 1, "Omitted mode retains automatic initial release")
	behavior.call("_physics_process", 0.61)
	assert_eq(simulation.marbles.size(), 2)

func test_initial_state_settles_before_gate_pulses_and_repeated_runs_are_clean() -> void:
	release({"signal_controlled": true})
	var memory := module("memory", {"initial_state": true})
	var inverse := module("not")
	link(memory, "state", inverse, "a")
	link(inverse, "rising", build.find_piece("release"), "release")
	assert_true(PieceWiring.validation_errors(build.pieces).is_empty())
	assert_eq(memory.compatible_actions(inverse, "state"), ["a"])
	assert_false("a" in memory.compatible_actions(inverse, "changed"))
	for run in 3:
		assert_true(simulation.start())
		assert_false(inverse.behaviors[0].output_values.result)
		assert_eq(simulation.marbles.size(), 0, "No transient NOT startup activation")
		memory.behaviors[0].receive("reset")
		assert_eq(simulation.marbles.size(), 1)
		simulation.reset()
	memory.apply_configuration({"initial_state": false, "links": memory.configuration.links})
	assert_true(simulation.start())
	assert_true(inverse.behaviors[0].output_values.result)
	assert_eq(simulation.marbles.size(), 1, "Initially true NOT activates once after seeding")

func test_fifo_command_order_and_feedback_limit() -> void:
	var source := release()
	var memory := module("memory")
	link(source, "released", memory, "set")
	link(source, "released", memory, "reset")
	link(source, "released", memory, "toggle")
	assert_true(simulation.start())
	assert_true(memory.behaviors[0].output_values.state, "Saved link order is set, reset, toggle")
	simulation.reset()
	link(memory, "changed", memory, "toggle")
	simulation.wiring.delivery_limit = 32
	assert_false(simulation.start(), "Non-settling pulse feedback fails the run")
	assert_eq(simulation.state, SimulationManager.State.FAILED)
	assert_false(memory.behaviors[0].active, "Signal failure stops receiver activity")

func test_reset_rebuilds_wiring_after_link_edits_and_history_restore() -> void:
	var source := release({"signal_controlled": true})
	var memory := mount_on(source)
	link(source, "released", memory, "toggle")
	for run in 2:
		assert_true(simulation.start())
		source.behaviors[0].receive("release")
		assert_true(memory.behaviors[0].output_values.state, "Each run delivers exactly one toggle")
		simulation.reset()
	assert_true(build.edit_link("release", 0, {"event": "released", "target": "memory", "action": "set"}))
	build.undo()
	# History replaces the live piece nodes while keeping their saved UIDs.
	source = build.find_piece("release")
	memory = build.find_piece("memory")
	assert_true(simulation.start())
	source.behaviors[0].receive("release")
	assert_true(memory.behaviors[0].output_values.state, "Restored wiring resolves the current receiver")
	simulation.reset()
	build.redo()
	source = build.find_piece("release")
	memory = build.find_piece("memory")
	assert_true(simulation.start())
	memory.behaviors[0].receive("set")
	source.behaviors[0].receive("release")
	assert_true(memory.behaviors[0].output_values.state, "Redo uses set, with no stale toggle connection")

func mount_on(support: BuildingPiece, id: String = "memory") -> BuildingPiece:
	var normal := Vector3.RIGHT
	var point := support.position + Vector3(0.5, 0.25, 0)
	var definition := build.catalog.get_piece("logic-" + id)
	var item := {"definition": definition, "local": Transform3D.IDENTITY}
	var candidate := build.snap.mounted_candidates(item, Transform3D.IDENTITY, support, point, normal)[0]
	return build.spawn(definition, candidate.transform, id, {"mount_target": support.instance_id, "mount_basis": PieceAttachment.basis_values(candidate.transform.basis)})

func test_surface_alignment_on_multiple_normals_and_geometry_validation() -> void:
	var support := build.spawn(build.catalog.get_piece("straight"), Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)), "support")
	var definition := build.catalog.get_piece("logic-memory")
	var item := {"definition": definition, "local": Transform3D.IDENTITY}
	for normal in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD, Vector3(1, 1, 0).normalized()]:
		var point := support.position + Vector3(0.5, 0.25, 0)
		var placement: Transform3D = build.snap.mounted_candidates(item, Transform3D.IDENTITY, support, point, normal)[0].transform
		assert_true(placement.basis.y.is_equal_approx(normal))
		assert_true(placement.origin.is_equal_approx(point))
		assert_gt((placement * definition.bounds).get_center().distance_to(point), 0.0)
	var accessory := mount_on(support)
	assert_eq(PieceAttachment.validate(build.snapshot(), build.catalog), "")
	assert_eq(build.snap.validate(accessory.definition, accessory.transform, [support]), "", "Side mounting clears track collision")
	assert_true(accessory.find_children("*", "StaticBody3D", true, false).all(func(body): return body.collision_layer == 4), "Accessories do not obstruct marbles")
	assert_false(PieceAttachment.valid_basis([0, 0, 0, 0, 0, 0, 0, 0, 0]))

func test_mount_movement_rotation_duplication_deletion_history_and_save_load() -> void:
	var support := build.spawn(build.catalog.get_piece("straight"), Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)), "support")
	mount_on(support)
	var before := build.snapshot()
	build.select(support)
	build.rotate_piece()
	assert_eq(build.selection.size(), 2, "Supporting piece includes mounted accessories")
	var rotated := build.snapshot()
	assert_ne(rotated, before)
	assert_eq(PieceAttachment.validate(rotated, build.catalog), "")
	build.undo()
	assert_eq(build.snapshot(), before)
	build.redo()
	assert_eq(build.snapshot(), rotated)
	support = build.find_piece("support")
	build.select(support)
	build.move_selected(true)
	build.preview.position += Vector3(4, 0, 0)
	build.valid = true
	build.apply_preview()
	build.commit()
	assert_eq(build.pieces.size(), 4)
	assert_eq(PieceAttachment.validate(build.snapshot(), build.catalog), "")
	var copies := build.selection
	var copied_accessory: BuildingPiece = copies.filter(func(piece): return piece.definition.surface_mounted)[0]
	assert_ne(copied_accessory.configuration.mount_target, "support", "Duplicate remaps attachment UID")
	var saved := build.snapshot()
	var track_id := workspace.session.serializer.save_track("Mounted", saved)
	var loaded := workspace.session.serializer.load_track(track_id)
	assert_false(loaded.is_empty())
	build.restore(loaded.pieces)
	assert_eq(build.snapshot(), saved)
	build.select(build.find_piece("support"))
	build.delete_selected()
	assert_eq(build.pieces.size(), 2, "Deleting support removes its accessory atomically")
	build.undo()
	assert_eq(build.snapshot(), saved)
	build.redo()
	assert_eq(build.pieces.size(), 2)

func test_puzzle_inventory_and_locked_accessory_reject_group_edits() -> void:
	var support := build.spawn(build.catalog.get_piece("straight"), Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)), "support")
	var accessory := mount_on(support)
	var data := workspace.session.store.create()
	data.pieces = build.snapshot()
	data.permissions = {"support": {"move": true, "rotate": true, "remove": true}}
	build.rules = PuzzleRules.new(data, build.catalog)
	var before := build.snapshot()
	build.select(support)
	build.rotate_piece()
	build.delete_selected()
	assert_eq(build.snapshot(), before, "Locked mounted accessory blocks the entire operation")
	assert_eq(build.selection, [support], "Rejected edits preserve selection")
	assert_false(build.history.has_undo())
	assert_false(build.configure_piece(accessory, {"initial_state": true}, "Locked"))
	var extra := accessory.serialize()
	extra.uid = "extra"
	assert_string_contains(build.rules.validate(before + [extra]), "No inventory")
	data.inventory = {"logic-memory": 1}
	assert_eq(PuzzleRules.new(data, build.catalog).validate(before + [extra]), "")

func test_cursor_surface_preview_commit_remount_and_cancel() -> void:
	# Keep the GUT panel and the user's real mouse out of this synthetic cursor test.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	add_child_autoqfree(viewport)
	workspace.reparent(viewport)
	workspace.get_node("Interface/HUD").hide()
	var support := build.spawn(build.catalog.get_piece("straight"), Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)), "support")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var camera := ConstructionCamera.new()
	camera.automatic_composition = false
	viewport.add_child(camera)
	camera.set_process(false)
	camera.position = Vector3(5, 2.25, 0)
	camera.look_at(Vector3(0, 2.25, 0))
	build.camera = camera
	build.set_process(false)
	build.choose(build.catalog.get_piece("logic-memory"))
	build.cursor_position = camera.unproject_position(Vector3(0.5, 2.25, 0))
	build.update_preview()
	assert_true(build.is_snapped)
	assert_true(build.valid, build.validation_message)
	var shown: Transform3D = build.preview.get_child(0).global_transform
	assert_true(shown.basis.y.is_equal_approx(Vector3.RIGHT))
	build.rotate_piece()
	build.update_preview()
	shown = build.preview.get_child(0).global_transform
	build.commit()
	build.cancel()
	assert_eq(build.pieces.size(), 2)
	if build.pieces.size() != 2: return
	var accessory: BuildingPiece = build.pieces[1]
	assert_true(accessory.transform.is_equal_approx(shown), "Commit uses the visible normal and twist")
	assert_eq(accessory.configuration.mount_target, support.instance_id)
	var saved := build.snapshot()
	build.select(accessory)
	build.move_selected()
	build.cursor_position = Vector2(-5000, -5000)
	build.update_preview()
	assert_false(build.valid, "Mounted accessories have no floating grid fallback")
	build.commit()
	assert_eq(build.snapshot(), saved, "Invalid commit leaves the original attachment intact")
	build.cancel()
	assert_true(accessory.visible)

func test_authoring_player_test_and_return_preserve_mounted_layout() -> void:
	var support := release({"signal_controlled": true})
	mount_on(support)
	var data := workspace.session.store.create()
	data.name = "Mounted controls"
	data.pieces = build.snapshot()
	data.objectives = [{"type": "activate", "target": "release", "event": "released"}]
	data.inventory = {"logic-counter": 1}
	var original := build.snapshot()
	workspace.session.editor(data)
	assert_eq(build.snapshot(), original)
	assert_true(build.authoring)
	assert_true(workspace.session.test_player(), "Valid authored mounted controls enter Player Test")
	assert_true(workspace.session.is_testing)
	assert_eq(build.snapshot(), original)
	build.select(build.find_piece("release"))
	build.move_selected()
	assert_null(build.chosen, "Locked authored assembly is enforced in the shared player path")
	workspace.session.return_editor()
	assert_true(build.authoring)
	assert_eq(build.snapshot(), original)
	build.select(build.find_piece("memory"))
	assert_true(build.configure_selected({"initial_state": true, "mount_target": "release", "mount_basis": build.selected.configuration.mount_basis}, "Initial state"))

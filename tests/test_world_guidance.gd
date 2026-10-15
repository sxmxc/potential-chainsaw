extends "res://tests/support/game_test.gd"

var workspace: ConstructionWorkspace

func setup_workspace() -> void:
	workspace = load("res://scenes/development/guidance_workshop.tscn").instantiate()
	add_child_autoqfree(workspace)
	await get_tree().process_frame

func sample() -> Dictionary:
	var data := workspace.session.store.load_puzzle("res://resources/development/guidance_workshop.json", "draft")
	data.version = 3
	data.guidance = [
		{"kind": "interaction", "target": "approach", "connector": -1, "text": "Select this track.", "appear": "build", "complete": "selected"},
		{"kind": "attention", "target": "approach", "connector": 0, "text": "Connect the gap.", "appear": "build", "complete": "connected"},
	]
	return data

func test_sequence_resolves_live_connector_advances_and_restarts() -> void:
	await setup_workspace()
	var data := sample()
	assert_eq(PuzzleRules.definition_errors(data, workspace.catalog), [])
	workspace.session.player(data, true)
	assert_false(workspace.guidance.marker.visible, "Ordinary puzzles do not disclose authored hints automatically")
	workspace.guidance.request()
	assert_eq(workspace.guidance.instruction, "Select this track.")
	var build := workspace.world.build
	build.set_selection([build.find_piece("approach")])
	assert_eq(workspace.guidance.step_index, 1)
	var arrow := workspace.guidance.marker.get_node("Pointer/Arrow") as Node3D
	assert_gt((-arrow.global_basis.x).normalized().dot(Vector3.DOWN), 0.999, "Authored icon correction points the chevron down")
	var resolved := workspace.guidance.resolve(data.guidance[1])
	var piece := build.find_piece("approach")
	assert_true(resolved.point.is_equal_approx(piece.global_transform * piece.definition.connectors[0].position))
	build.spawn(workspace.catalog.get_piece("straight"), Transform3D.IDENTITY, "bridge")
	build.changed.emit()
	assert_eq(workspace.guidance.step_index, 2, "Compatible connector topology advances guidance")
	assert_false(workspace.guidance.marker.visible)
	workspace.session.player(data, true)
	workspace.guidance.request()
	assert_eq(workspace.guidance.step_index, 0)
	workspace.session.sandbox()
	assert_false(workspace.guidance.marker.visible, "Context changes clear markers and text")
	assert_eq(workspace.guidance.instruction, "")

func test_missing_targets_safe_and_authoring_round_trip() -> void:
	await setup_workspace()
	var data := sample()
	workspace.session.editor(data)
	var editor: Control = workspace.authoring.get_node("%GuidanceEditor")
	editor.refresh()
	editor.edit_step(0)
	assert_eq(editor.fields(), data.guidance[0].merged({"position": [0.0, 0.0, 0.0]}))
	assert_true(workspace.session.save_draft())
	var path := workspace.session.store.drafts_directory.path_join(data.id + ".json")
	var loaded := workspace.session.store.load_puzzle(path, "draft")
	assert_eq(loaded.guidance, JSON.parse_string(JSON.stringify(data.guidance)))
	workspace.session.player(loaded, true)
	workspace.guidance.request()
	var target := workspace.world.build.find_piece("approach")
	workspace.world.build.pieces.erase(target)
	target.queue_free()
	workspace.world.build.changed.emit()
	assert_false(workspace.guidance.marker.visible)
	assert_eq(workspace.guidance.instruction, "")
	loaded.pieces = loaded.pieces.filter(func(item): return item.uid != "approach")
	assert_true(WorldGuidance.definition_errors(loaded, workspace.catalog).any(func(error): return "missing" in error))

func test_guidance_rejects_executable_fields_bad_types_and_old_formats() -> void:
	await setup_workspace()
	var data := sample()
	data.guidance[0].scene = "res://evil.tscn"
	assert_false(PuzzleRules.shape_errors(data).is_empty())
	data = sample()
	data.guidance[0].connector = "bad"
	assert_false(PuzzleRules.shape_errors(data).is_empty())
	data = sample()
	data.version = 2
	assert_false(PuzzleRules.shape_errors(data).is_empty())

func test_preview_objective_and_run_lifecycle() -> void:
	await setup_workspace()
	var data := sample()
	data.guidance = [{"kind": "direction", "target": "release", "connector": 0, "appear": "always", "complete": "run_started", "text": "Run the machine."}]
	workspace.session.player(data, true)
	workspace.guidance.request()
	assert_true(workspace.guidance.marker.visible)
	var arrow := workspace.guidance.marker.get_node("Pointer/Arrow") as Node3D
	var target := workspace.guidance.resolve(data.guidance[0])
	assert_gt((-arrow.global_basis.x).normalized().dot(target.direction), 0.999, "Direction uses the connector's world orientation")
	assert_true(workspace.session.start_simulation())
	assert_false(workspace.guidance.marker.visible)
	workspace.guidance.locate_objectives()
	assert_true(workspace.guidance.marker.visible)
	assert_eq(workspace.guidance.instruction, "Destination")
	workspace.guidance.timer.timeout.emit()
	assert_false(workspace.guidance.marker.visible)
	workspace.world.simulation.reset()
	workspace.guidance.request()
	assert_eq(workspace.guidance.step_index, 0)

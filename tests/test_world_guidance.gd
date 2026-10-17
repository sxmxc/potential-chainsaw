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
	assert_eq(workspace.guidance.instruction, "", "Goal highlights the destination without a redundant label")
	var previous_step := workspace.guidance.step_index
	workspace.guidance.dismiss()
	assert_eq(workspace.guidance.step_index, previous_step, "Closing a goal preview does not skip a hint")
	assert_false(workspace.guidance.marker.visible)
	workspace.guidance.locate_objectives()
	workspace.guidance.timer.timeout.emit()
	assert_false(workspace.guidance.marker.visible)
	workspace.world.simulation.reset()
	workspace.guidance.request()
	assert_eq(workspace.guidance.step_index, 0)

func test_simple_hint_fields_and_new_hint_do_not_inherit_advanced_settings() -> void:
	await setup_workspace()
	var data := sample()
	workspace.session.editor(data)
	var editor: Control = workspace.authoring.get_node("%GuidanceEditor")
	var build := workspace.world.build
	build.set_selection([build.find_piece("approach")])
	editor.get_node("%NewStep").pressed.emit()
	assert_false(editor.get_node("%Advanced").visible)
	assert_eq(editor.fields().target, "approach", "A new hint uses the selected piece")
	assert_eq(editor.fields().complete, "dismissed", "Simple hints advance with Next")
	editor.get_node("%StepText").text = "Start here."
	editor.get_node("%PreviewStep").pressed.emit()
	assert_eq(workspace.hud.get_node("%GuidanceText").text, "Start here.", "Preview shows the hint text as well as the marker")
	editor.get_node("%SaveStep").pressed.emit()
	assert_eq(workspace.session.puzzle.guidance[-1].text, "Start here.")
	assert_eq(workspace.session.puzzle.guidance[-1].kind, "attention")
	assert_eq(workspace.session.puzzle.version, 3)
	editor.get_node("%MarkerKind").select(2)
	editor.get_node("%StepAppear").select(2)
	editor.get_node("%StepConnector").select(1)
	editor.get_node("%NewStep").pressed.emit()
	var fresh: Dictionary = editor.fields()
	assert_eq(fresh.kind, "attention")
	assert_eq(fresh.appear, "build")
	assert_eq(fresh.connector, -1)
	assert_eq(fresh.text, "")
	assert_false(editor.get_node("%Advanced").visible)
	editor.edit_step(1)
	assert_true(editor.get_node("%Advanced").visible, "Editing a track-end hint reveals its saved settings")
	assert_eq(editor.fields().connector, 0)

func test_objective_notifications_update_toolbar_and_guidance_and_reset_together() -> void:
	await setup_workspace()
	var data := sample()
	var target: String = data.objectives[0].target
	data.objectives = [{"target": target, "source": "release", "count": 2}]
	data.guidance = [{"kind": "target", "target": target, "appear": "always", "complete": "objective", "text": "Watch the catcher."}]
	workspace.session.player(data, true)
	workspace.guidance.request()
	var objectives: PuzzleObjectives = workspace.world.simulation.objectives
	var label: Label = workspace.hud.get_node("%FileToolbar").get_node("%Progress")
	assert_eq(label.text, "0 / 2 arrived")
	objectives.delivered(target, "other:0", "other")
	assert_eq(label.text, "0 / 2 arrived", "HUD applies the goal's source filter")
	assert_eq(workspace.guidance.step_index, 1, "Guidance still advances on first target activity")
	objectives.delivered(target, "release:0", "release")
	assert_eq(label.text, "1 / 2 arrived")
	assert_false(objectives.satisfied(0))
	objectives.delivered(target, "release:1", "release")
	assert_eq(label.text, "2 / 2 arrived")
	assert_true(objectives.satisfied(0))
	workspace.world.simulation.reset()
	workspace.guidance.request()
	assert_eq(label.text, "0 / 2 arrived")
	assert_eq(workspace.guidance.step_index, 0)

func test_older_text_hints_use_the_same_owner_and_next_control() -> void:
	await setup_workspace()
	var data := sample()
	data.erase("guidance")
	data.version = 2
	data.hints = ["First hint.", " ", "Second hint."]
	workspace.session.player(data, true)
	assert_true(workspace.guidance.has_hints())
	assert_eq(workspace.guidance.instruction, "")
	workspace.guidance.request()
	assert_eq(workspace.guidance.instruction, "First hint.")
	assert_eq(workspace.hud.get_node("%GuidanceText").text, "First hint.")
	assert_false(workspace.guidance.marker.visible, "A text hint does not fabricate a world target")
	workspace.hud.get_node("%DismissGuidance").pressed.emit()
	assert_eq(workspace.guidance.instruction, "Second hint.")
	workspace.hud.get_node("%DismissGuidance").pressed.emit()
	assert_eq(workspace.guidance.instruction, "")
	await get_tree().create_timer(UIMotion.EXIT_TIME + 0.05).timeout
	assert_false(workspace.hud.get_node("%Guidance").visible)
	assert_eq(workspace.session.puzzle.version, 2)
	assert_false(workspace.session.puzzle.has("guidance"), "Reading old hints does not rewrite saves or proof")
	workspace.guidance.request()
	assert_eq(workspace.guidance.instruction, "First hint.", "Hint can replay a manually completed sequence")
	workspace.session.sandbox()
	assert_eq(workspace.guidance.step_index, 0)
	assert_false(workspace.hud.get_node("%Guidance").visible)

func test_authored_introduction_sequence_takes_precedence_over_older_hint_text() -> void:
	await setup_workspace()
	var data: Dictionary = workspace.session.store.load_campaign().levels.filter(func(item): return item.id == "campaign-01")[0]
	workspace.session.player(data, true)
	assert_eq(workspace.guidance.instruction, data.guidance[0].text, "Introduction uses its authored sequence automatically")
	assert_eq(workspace.hud.get_node("%GuidanceText").text, data.guidance[0].text)
	assert_false(workspace.guidance.marker.has_node("Caption"), "World markers do not repeat obvious labels")
	assert_false(workspace.hud.get_node("%DismissGuidance").visible, "An action-driven step advances through play")
	assert_eq(workspace.hud.get_node("%GuidanceProgress").text, "1 / 3")
	await get_tree().create_timer(UIMotion.ENTER_TIME + 0.1).timeout
	assert_false(workspace.guidance.marker.get_node("Arrival").is_playing())
	var pointer: Node3D = workspace.guidance.marker.get_node("Pointer")
	var first_position := pointer.position
	var pointer_motion: Tween = workspace.guidance.marker.pointer_motion
	assert_true(pointer_motion.is_running(), "The pointer continues tweening after its entrance")
	await get_tree().create_timer(0.2).timeout
	assert_gt(pointer.position.distance_to(first_position), 0.01, "The pointer visibly moves toward its target")
	workspace.guidance.refresh()
	assert_same(workspace.guidance.marker.pointer_motion, pointer_motion, "Refresh retains the running pointer loop")
	assert_false(workspace.guidance.marker.get_node("Arrival").is_playing(), "Unchanged refreshes do not restart arrival motion")
	assert_false(workspace.authoring.has_node("%Hint"), "The editor has one place to author player hints")
	workspace.guidance.step_index = data.guidance.size()
	workspace.guidance.refresh()
	assert_eq(workspace.guidance.instruction, "", "Finishing a sequence cannot fall back to the retired tutorial")
	assert_null(workspace.guidance.marker.pointer_motion, "Clearing guidance stops the pointer tween")
	assert_true(pointer.position.is_zero_approx())
	await get_tree().create_timer(UIMotion.EXIT_TIME + 0.05).timeout
	assert_false(workspace.hud.get_node("%Guidance").visible)

func test_hud_targets_share_steps_follow_cards_and_clear_on_context_change() -> void:
	await setup_workspace()
	var data := sample()
	data.guidance[0].ui_targets = ["piece:straight", "action:run"]
	data.guidance[0].ui_style = "pointer"
	assert_eq(PuzzleRules.definition_errors(data, workspace.catalog), [])
	workspace.session.player(data, true)
	workspace.guidance.request()
	await wait_seconds(0.25)
	assert_true(workspace.guidance.marker.visible, "World and HUD guidance coexist")
	var hud := workspace.hud
	var card := hud.guidance_control("piece:straight")
	var overlay: Control = hud.hud_indicators["piece:straight"]
	assert_same(overlay.get_parent(), card)
	assert_true(overlay.size.is_equal_approx(card.size), "Anchors follow actual geometry")
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(overlay.mouse_behavior_recursive, Control.MOUSE_BEHAVIOR_DISABLED)
	assert_eq(overlay.focus_behavior_recursive, Control.FOCUS_BEHAVIOR_DISABLED)
	var toolbox: Control = hud.get_node("%Toolbox")
	toolbox.get_node("%Scroll").scroll_vertical = 100
	await get_tree().process_frame
	assert_true(overlay.get_global_rect().is_equal_approx(card.get_global_rect()), "Scrolling needs no layout polling")
	toolbox.hide()
	assert_false(overlay.is_visible_in_tree())
	toolbox.show()
	assert_true(overlay.is_visible_in_tree())
	toolbox.refresh()
	var rebuilt := hud.guidance_control("piece:straight")
	assert_same(hud.hud_indicators["piece:straight"].get_parent(), rebuilt, "Dynamic rebuild rebinds by piece ID")
	rebuilt.pressed.emit()
	assert_eq(workspace.world.build.chosen.id, &"straight", "Highlighted cards retain their action")
	workspace.world.build.cancel()
	workspace.world.build.set_selection([workspace.world.build.find_piece("approach")])
	assert_eq(workspace.guidance.step_index, 1)
	assert_true(hud.hud_indicators.is_empty(), "Advancing removes every HUD target together")
	workspace.guidance.preview(data.guidance[0])
	assert_eq(hud.hud_indicators.size(), 2)
	workspace.guidance.timer.timeout.emit()
	assert_true(hud.hud_indicators.is_empty())
	workspace.session.sandbox()
	assert_true(hud.hud_indicators.is_empty())

func test_hud_authoring_round_trip_ui_only_run_and_validation() -> void:
	await setup_workspace()
	var data := sample()
	data.guidance[0].ui_targets = ["piece:straight", "action:run"]
	data.guidance[0].ui_style = "halo"
	data.guidance[0].show_world = false
	workspace.session.editor(data)
	var editor: Control = workspace.authoring.get_node("%GuidanceEditor")
	editor.refresh()
	editor.edit_step(0)
	assert_eq(editor.fields().ui_targets, data.guidance[0].ui_targets)
	assert_eq(editor.fields().ui_style, "halo")
	assert_false(editor.fields().show_world)
	editor.preview_step()
	assert_false(workspace.guidance.marker.visible)
	assert_eq(workspace.hud.hud_indicators.size(), 2)
	assert_true(workspace.session.save_draft())
	var loaded := workspace.session.store.load_puzzle(workspace.session.store.drafts_directory.path_join(data.id + ".json"), "draft")
	assert_eq(loaded.guidance, JSON.parse_string(JSON.stringify(data.guidance)))
	data.guidance = [{"kind": "attention", "target": "", "show_world": false, "ui_targets": ["action:run"], "text": "Run the machine.", "appear": "build", "complete": "run_started"}]
	workspace.session.player(data, true)
	workspace.guidance.request()
	assert_eq(workspace.hud.hud_indicators.size(), 1)
	assert_false(workspace.guidance.marker.visible)
	workspace.hud.guidance_control("action:run").pressed.emit()
	assert_eq(workspace.world.simulation.state, SimulationManager.State.RUNNING)
	assert_true(workspace.hud.hud_indicators.is_empty(), "Run uses the same progression rule")
	for invalid: Variant in ["action:unknown", "res://evil.tscn", 42]:
		data.guidance[0].ui_targets = [invalid]
		assert_false(WorldGuidance.shape_errors(data).is_empty())
	data.guidance[0].ui_targets = ["piece:missing"]
	assert_false(WorldGuidance.definition_errors(data, workspace.catalog).is_empty())
	data.guidance[0].ui_targets = ["action:run", "action:run"]
	assert_false(WorldGuidance.shape_errors(data).is_empty())

func test_introduction_uses_hud_guidance_for_cards_run_and_connect() -> void:
	await setup_workspace()
	var introductions: Array[Dictionary] = workspace.session.store.load_campaign().levels.filter(func(data): return data.campaign.chapter.get("introduction", false))
	assert_eq(introductions.size(), 10, "Keep all ten optional Introduction puzzles")
	var placement_cards := {"campaign-01": "straight", "campaign-02": "curve", "campaign-03": "ramp-long-a", "campaign-06": "bucket-elevator", "campaign-10": "bucket-elevator"}
	for data: Dictionary in introductions:
		assert_eq(workspace.session.store.publication_errors(data), [], "Current proof covers " + str(data.id))
		var run_hints: int = 0
		for step: Dictionary in data.guidance:
			if step.complete == "run_started":
				run_hints += 1
				assert_has(step.get("ui_targets", []), "action:run", data.name + " points at Run")
			if "Use Connect" in step.text:
				assert_has(step.get("ui_targets", []), "action:connect", data.name + " points at Connect")
		assert_eq(run_hints, 1, "Retain the existing run progression in " + str(data.name))
		if placement_cards.has(data.id):
			assert_has(data.guidance[0].get("ui_targets", []), "piece:" + placement_cards[data.id], data.name + " points at its inventory card")
		else:
			assert_eq(data.guidance[0].complete, "selected", "Select the existing world mechanism")
			assert_true(data.guidance[0].get("show_world", true))
	var first: Dictionary = introductions.filter(func(data): return data.id == "campaign-01")[0]
	workspace.session.player(first, true)
	assert_has(workspace.hud.hud_indicators, "piece:straight", "The first puzzle highlights its card automatically")
	workspace.world.build.restore(first.solution)
	workspace.guidance.refresh()
	assert_eq(workspace.guidance.step_index, 1)
	assert_has(workspace.hud.hud_indicators, "action:run", "After bridging the gap, guidance points at Run")
	assert_false(workspace.guidance.marker.visible, "A pure Run instruction needs only the HUD target")
	var wiring: Dictionary = introductions.filter(func(data): return data.id == "campaign-09")[0]
	workspace.session.player(wiring, true)
	workspace.world.build.set_selection([workspace.world.build.find_piece("detector")])
	assert_has(workspace.hud.hud_indicators, "action:connect")
	assert_has(workspace.hud.hud_indicators, "action:run")
	assert_true(workspace.guidance.marker.visible, "The sensor and toolbar targets coexist")

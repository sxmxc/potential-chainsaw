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
	assert_true(build.pieces.any(func(piece): return piece.instance_id == PuzzleEnvironment.LEGACY_UID))
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
	data.id = "gut-environment-draft"
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
	assert_false(session.store.list_puzzles().any(func(level): return level.id == data.id), "The isolated draft is excluded from campaign")
	assert_eq(session.store.list_puzzles(true).filter(func(level): return level.id in IDS).size(), 3)
	# A legal free placement remains an ordinary undoable construction edit.
	build.choose(straight)
	build.proposed = allowed
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces).is_empty()
	assert_true(build.valid, "Free placement passes real placement validation")
	build.ghost.show()
	build.commit()
	build.cancel()
	assert_eq(build.snapshot().size(), 3)
	build.undo()
	assert_eq(build.snapshot().size(), 2)
	build.redo()
	assert_eq(build.snapshot().size(), 3)
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
	var lift = BuildingPiece.ElevatorGeometry.configured(game.catalog.get_piece("bucket-elevator"), {"elevator_height": 4, "elevator_speed": 0.8})
	assert_eq(game.sandbox.build.snap.validate(lift, Transform3D.IDENTITY, []), "Blocked by the environment", "A lift cannot grow through canopy")

func place_object(definition: PieceDefinition, point: Vector3) -> BuildingPiece:
	var build: BuildManager = game.sandbox.build
	build.choose(definition)
	if not build.ghost: return null
	build.proposed = Transform3D(Basis.IDENTITY, point)
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces).is_empty()
	build.apply_preview()
	var count := build.pieces.size()
	build.commit()
	build.cancel()
	return build.pieces.back() if build.pieces.size() > count else null

func test_editable_environment_roundtrip_and_player_isolation() -> void:
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	session.editor(draft(0))
	assert_true(build.enabled)
	var wall := place_object(game.catalog.get_piece("environment:partition"), Vector3(6, 0, 0))
	assert_not_null(wall)
	if not wall: return
	var uid := wall.instance_id
	build.select(wall)
	build.move_selected()
	build.proposed.origin = Vector3(7, 0.5, 1)
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces, build.moving_group).is_empty()
	build.apply_preview()
	build.commit()
	build.rotate_piece()
	assert_true(session.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.store.drafts_directory + "/" + session.puzzle.id + ".json"))
	assert_eq(saved.environment_instances[0].position, [7.0, 0.5, 1.0])
	assert_eq(saved.environment_instances[0].rotation, 1.0)
	session.editor(saved)
	var restored: BuildingPiece = build.pieces.back()
	assert_eq(restored.instance_id, uid)
	assert_almost_eq(restored.position, Vector3(7, 0.5, 1), Vector3.ONE * 0.001)
	assert_eq(restored.bodies[0].collision_layer, 1)
	assert_false(restored.definition.connectors.size() > 0)
	assert_ne(build.snap.validate(game.catalog.get_piece("straight"), restored.transform, build.pieces), "")
	assert_true(session.test_player())
	assert_false(build.authoring)
	build.choose(game.catalog.get_piece("environment:partition"))
	assert_null(build.ghost)
	assert_null(build.spawn(game.catalog.get_piece("environment:partition"), Transform3D.IDENTITY))
	assert_eq(build.pieces.size(), saved.pieces.size(), "Player construction excludes environment inventory")
	var fixed_bodies := session.environment_node.get_node(NodePath(uid)).find_children("*", "StaticBody3D", true, false)
	assert_false(fixed_bodies.is_empty(), "Player scenery retains generated collision")
	assert_true(fixed_bodies.all(func(body): return body.collision_layer == 1 and body.collision_mask == 2))
	var invalid_inventory := saved.duplicate(true)
	invalid_inventory.inventory["environment:partition"] = 1
	assert_true(session.store.validate(invalid_inventory).has("Invalid inventory: environment:partition"), "Registry scenery cannot enter player stock")
	session.return_editor()
	build.select(build.pieces.back())
	build.delete_selected()
	assert_eq(session.capture().environment_instances.size(), 0)
	build.undo()
	assert_eq(session.capture().environment_instances.size(), 1)
	build.redo()
	assert_eq(session.capture().environment_instances.size(), 0)

func test_environment_edits_stale_proof_and_reject_track_intersection() -> void:
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	session.editor(draft(0))
	session.puzzle.version = 2
	var proof := session.store.fingerprint(session.capture())
	var column := place_object(game.catalog.get_piece("environment:column"), Vector3(6, 0, 0))
	assert_not_null(column)
	if not column: return
	var changed := session.store.fingerprint(session.capture())
	assert_ne(changed, proof)
	build.select(column)
	assert_eq(session.store.fingerprint(session.capture()), changed, "Selection keeps proof unchanged")
	build.move_selected()
	build.proposed.origin = build.pieces[0].position
	var error := build.snap.validate_group(build.preview_items, build.proposed, build.pieces, build.moving_group)
	assert_ne(error, "", "Scenery cannot overlap track")
	build.valid = error.is_empty()
	build.apply_preview()
	build.commit()
	build.cancel()
	assert_eq(session.store.fingerprint(session.capture()), changed)
	build.delete_selected()
	assert_eq(session.store.fingerprint(session.capture()), proof)

func test_mixed_groups_share_atomic_history_and_keep_elevations() -> void:
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	session.editor()
	var track := place_object(game.catalog.get_piece("straight"), Vector3(4, 1, 0))
	var wall := place_object(game.catalog.get_piece("environment:partition"), Vector3(7, 0, 0))
	assert_not_null(track)
	assert_not_null(wall)
	if not track or not wall: return
	var baseline := build.snapshot(true)
	build.set_selection([track, wall])
	build.move_selected()
	build.proposed.origin += Vector3(0, 0.5, 2)
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces, build.moving_group).is_empty()
	build.apply_preview()
	build.commit()
	assert_eq(track.position.y - wall.position.y, 1.0)
	var moved := build.snapshot(true)
	build.undo()
	assert_eq(build.snapshot(true), baseline)
	build.redo()
	assert_eq(build.snapshot(true), moved)
	build.rotate_piece()
	assert_eq(build.selection.size(), 2)
	assert_eq(build.selection[0].position.y - build.selection[1].position.y, 1.0)
	var rotated := build.snapshot(true)
	build.move_selected(true)
	for preview in build.ghosts:
		for body in preview.bodies: assert_eq(body.collision_layer, 0, "Native scenery ghosts cannot obstruct editing or physics")
	build.proposed.origin += Vector3(0, 0, 5)
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces).is_empty()
	build.apply_preview()
	build.commit()
	assert_eq(build.pieces.size(), 4)
	assert_eq(build.selection.size(), 2)
	assert_eq(session.capture().pieces.size(), 2)
	assert_eq(session.capture().environment_instances.size(), 2)
	build.undo()
	assert_eq(build.snapshot(true), rotated)
	build.redo()
	build.delete_selected()
	assert_eq(build.pieces.size(), 2)
	build.undo()
	assert_eq(build.pieces.size(), 4)

func test_native_environment_snapshot_is_self_contained() -> void:
	var data := draft(0)
	data.environment_instances = [{"uid": "env-test", "asset": "deck", "position": [6, 1, 0], "rotation": 1}]
	var path: String = game.puzzle_session.store.drafts_directory + "/environment.tscn"
	assert_eq(PuzzleEnvironment.freeze(data, path), OK)
	assert_eq(ResourceLoader.get_dependencies(path).size(), 0, "Published snapshot embeds mesh, texture and collision resources")
	data.environment_snapshot = path
	game.puzzle_session.player(data)
	var solids: Array[Node] = game.puzzle_session.environment_node.get_node("env-test").find_children("*", "CollisionShape3D", true, false)
	assert_false(solids.is_empty(), "Published scenery preserves native collision")
	assert_true(solids.all(func(solid): return solid.shape is ConcavePolygonShape3D), "Published collision comes from the same mesh pipeline as other pieces")
	assert_eq(game.sandbox.build.snap.environment_solids.size(), PuzzleEnvironment.inspect_definition(data).solids.size())

func test_environment_shortcuts_after_leaving_catalog_focus() -> void:
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	session.editor(draft(0))
	var toolbox = game.get_node("%HUD").get_node("%Toolbox")
	assert_not_null(place_object(game.catalog.get_piece("straight"), Vector3(6, 0, 5)))
	toolbox.get_node("%Category").select(game.catalog.categories().find("Scenery"))
	toolbox.refresh()
	assert_true(toolbox.buttons.has(&"environment:partition"))
	assert_true(toolbox.buttons.has(&"banner"), "Kit scenery and native solids share a category")
	assert_null(toolbox.get_node_or_null("%Catalog"), "There is one catalog")
	var sender := GutInputSender.new(Input)
	autofree(sender)
	build.camera.frame_point(Vector3(6, 1, 0), 5)
	for frame in 40: await get_tree().physics_frame
	toolbox.buttons[&"environment:partition"].chosen.emit(game.catalog.get_piece("environment:partition"))
	toolbox.get_node("%Search").grab_focus()
	var screen := build.camera.unproject_position(Vector3(6, 0, 0))
	sender.mouse_motion(screen)
	await get_tree().process_frame
	sender.mouse_left_button_down(screen)
	await get_tree().process_frame
	sender.mouse_left_button_up(screen)
	await get_tree().process_frame
	assert_null(get_viewport().gui_get_focus_owner(), "World click releases catalog focus")
	assert_eq(session.capture().environment_instances.size(), 1, "Wall is placed through normal world input")
	if session.capture().environment_instances.is_empty(): return
	build.cancel()
	var wall: BuildingPiece = build.pieces.back()
	var initial := wall.position
	var uid := wall.instance_id
	for frame in 2: await get_tree().physics_frame
	screen = build.camera.unproject_position(wall.transform * wall.definition.bounds.get_center())
	sender.mouse_motion(screen)
	await get_tree().process_frame
	sender.mouse_left_button_down(screen)
	await get_tree().process_frame
	assert_eq(build.selected, wall, "World click selects scenery")
	sender.mouse_motion(screen + Vector2(75, 0))
	await get_tree().process_frame
	sender.mouse_left_button_up(screen + Vector2(75, 0))
	await get_tree().process_frame
	assert_ne(wall.position, initial, "Normal drag moves the wall")
	assert_eq(wall.position.y, initial.y, "Drag preserves elevation")
	sender.key_down(KEY_R)
	await get_tree().process_frame
	sender.key_up(KEY_R)
	await get_tree().process_frame
	assert_eq(wall.serialize().rotation, 1, "Environment uses the shared rotation shortcut")
	build.move_selected(true)
	sender.mouse_motion(screen + Vector2(170, 50))
	await get_tree().process_frame
	sender.mouse_left_button_down(screen + Vector2(170, 50))
	await get_tree().process_frame
	sender.mouse_left_button_up(screen + Vector2(170, 50))
	await get_tree().process_frame
	assert_eq(session.capture().environment_instances.size(), 2, "Duplicate uses the shared placement gesture")
	var duplicate := build.snapshot(true)
	build.undo()
	assert_eq(session.capture().environment_instances.size(), 1)
	build.redo()
	assert_eq(build.snapshot(true), duplicate)
	assert_true(session.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.store.drafts_directory + "/" + session.puzzle.id + ".json"))
	session.editor(saved)
	assert_eq(session.capture().environment_instances.size(), saved.environment_instances.size())
	for record in saved.environment_instances:
		var restored: Array[BuildingPiece] = build.pieces.filter(func(piece): return piece.instance_id == record.uid)
		assert_eq(restored.size(), 1, "The saved instance ID survives reopening")
		if restored.size() == 1:
			assert_eq(restored[0].transform, PuzzleEnvironment.transform_for(record), "Saved placement survives reopening")
	for piece in build.pieces:
		if piece.definition.authoring_only:
			var active_bodies: Array[StaticBody3D] = piece.bodies.filter(func(body): return body.collision_layer != 0)
			assert_false(active_bodies.is_empty(), "Restored scenery retains active collision")
			for body in active_bodies:
				assert_eq(body.collision_layer, 1)
				assert_eq(body.collision_mask, 2)
	assert_true(session.test_player())
	for frame in 2: await get_tree().physics_frame
	var fixed := session.environment_node.get_node(NodePath(uid)) as Node3D
	screen = build.camera.unproject_position(fixed.position + Vector3(0, 1.2, 0))
	sender.mouse_motion(screen)
	await get_tree().process_frame
	sender.mouse_left_button_down(screen)
	await get_tree().process_frame
	sender.mouse_left_button_up(screen)
	await get_tree().process_frame
	assert_null(build.selected, "Player cannot select environment")
	build.rotate_piece()
	build.delete_selected()
	assert_eq(fixed.transform, PuzzleEnvironment.transform_for(saved.environment_instances[0]))
	assert_eq(build.rules.validate(build.snapshot()), "", "Track construction still obeys the player rules")
	sender.release_all()
	session.sandbox()
	toolbox.refresh()
	assert_false(toolbox.buttons.keys().any(func(id): return String(id).begins_with("environment:")))

func test_scenery_surface_placement_through_world_input(example = use_parameters([
	{"target":"partition", "source":"partition", "turn":0, "point":Vector3(6, 0, 1)},
	{"target":"partition", "source":"partition", "turn":1, "point":Vector3(6, 0, 1)},
	{"target":"partition", "source":"column", "turn":0, "point":Vector3(6, 0, 1)},
	{"target":"column", "source":"column", "turn":0, "point":Vector3(6, 2.4, 0)}
])) -> void:
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	session.editor()
	var target := place_object(game.catalog.get_piece("environment:" + example.target), Vector3(6, 0, 0))
	assert_not_null(target)
	if not target: return
	build.camera.frame_point(Vector3(6, 1.2, 0), 6)
	await wait_seconds(1.5)
	var sender := GutInputSender.new(Input)
	autofree(sender)
	sender.set_auto_flush_input(true)
	var toolbox = game.get_node("%HUD").get_node("%Toolbox")
	toolbox.buttons[StringName("environment:" + example.source)].chosen.emit(game.catalog.get_piece("environment:" + example.source))
	if example.turn == 1:
		sender.key_down(KEY_R)
		await get_tree().process_frame
		sender.key_up(KEY_R)
		await get_tree().process_frame
	var screen := build.camera.unproject_position(example.point)
	sender.mouse_motion(screen)
	await wait_process_frames(2)
	assert_true(build.is_snapped, "Cursor-intended solid provides a surface alignment")
	assert_true(build.valid, build.validation_message)
	assert_eq(build.turn, example.turn, "Surface snapping keeps the chosen rotation")
	if not build.is_snapped or not build.valid: return
	var preview := build.proposed
	sender.mouse_left_button_down(screen)
	await get_tree().process_frame
	sender.mouse_left_button_up(screen)
	await get_tree().process_frame
	assert_eq(build.pieces.size(), 2, "Normal click commits the aligned object")
	if build.pieces.size() != 2: return
	var placed: BuildingPiece = build.pieces.back()
	assert_eq(placed.transform, preview, "Placement matches the preview")
	if not build.snap.permits_overlap(target.definition, placed.definition):
		assert_false(build.snap.solid_overlap(target.definition, target.transform, placed.definition, placed.transform), "Collision solids do not overlap")
	var target_box: AABB = target.transform * target.definition.collision_solids[0]
	var placed_box: AABB = placed.transform * placed.definition.collision_solids[0]
	assert_true(target_box.grow(0.002).intersects(placed_box), "Aligned geometry touches without a gap")
	if example.point.y > 0:
		assert_almost_eq(placed.position.y, 2.4, 0.001, "Column stacks on the existing top without selecting a build level")
	else:
		assert_eq(placed.position.y, 0.0, "Side attachment preserves elevation")
	var arrangement := build.snapshot(true)
	build.cancel()
	build.undo()
	assert_eq(build.pieces.size(), 1)
	build.redo()
	assert_eq(build.snapshot(true), arrangement)
	assert_true(session.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.store.drafts_directory.path_join(session.puzzle.id + ".json")))
	session.editor(saved)
	assert_eq(build.snapshot(true), arrangement, "Off-grid contact positions survive save and reopen")
	sender.release_all()

func test_column_overlaps_wall_corner_through_normal_placement() -> void:
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	session.editor()
	var wall: PieceDefinition = game.catalog.get_piece("environment:partition")
	var column: PieceDefinition = game.catalog.get_piece("environment:column")
	var first := place_object(wall, Vector3(6, 0, 0))
	assert_not_null(first)
	build.choose(wall)
	build.proposed = Transform3D(Basis(Vector3.UP, PI / 2), Vector3(7, 0, 1.05))
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces).is_empty()
	build.apply_preview()
	build.commit()
	build.cancel()
	assert_eq(build.pieces.size(), 2, "Perpendicular walls form the starting corner")
	if build.pieces.size() != 2: return
	var second: BuildingPiece = build.pieces.back()
	build.camera.frame_point(Vector3(6, 1.2, 1), 6)
	await wait_seconds(1.5)
	var sender := GutInputSender.new(Input)
	autofree(sender)
	sender.set_auto_flush_input(true)
	build.choose(column)
	var screen := build.camera.unproject_position(Vector3(6, 0, 1))
	sender.mouse_motion(screen)
	await wait_process_frames(2)
	assert_true(build.is_snapped, "The column aligns with the wall junction")
	assert_true(build.valid, build.validation_message)
	if not build.valid: return
	var preview := build.proposed
	sender.mouse_left_button_down(screen)
	await get_tree().process_frame
	sender.mouse_left_button_up(screen)
	await get_tree().process_frame
	assert_eq(build.pieces.size(), 3, "Normal placement commits the intersecting column")
	if build.pieces.size() != 3: return
	var placed: BuildingPiece = build.pieces.back()
	assert_eq(placed.transform, preview)
	var column_box: AABB = placed.transform * column.collision_solids[0]
	for target in [first, second]:
		assert_true(column_box.intersects(target.transform * wall.collision_solids[0]), "Column physically overlaps both wall ends")
		assert_eq(build.snap.validate(column, placed.transform, build.pieces, placed), "")
		assert_eq(build.snap.validate(wall, target.transform, build.pieces, target), "", "Moving a wall uses the same symmetric joint rule")
	var arrangement := build.snapshot(true)
	build.cancel()
	build.undo()
	assert_eq(build.pieces.size(), 2)
	build.redo()
	assert_eq(build.snapshot(true), arrangement)
	sender.release_all()

func test_column_wall_overlap_permission_does_not_allow_other_overlaps() -> void:
	var snap := SnapManager.new()
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	var column: PieceDefinition = game.catalog.get_piece("environment:column")
	var wall: PieceDefinition = game.catalog.get_piece("environment:partition")
	var machine: PieceDefinition = game.catalog.get_piece("environment:machine")
	assert_true(snap.permits_overlap(column, wall))
	assert_true(snap.permits_overlap(wall, column))
	assert_true(snap.solid_overlap(column, Transform3D.IDENTITY, wall, Transform3D.IDENTITY), "Permitted joints still have real overlapping geometry")
	assert_true(snap.solid_overlap(column, Transform3D.IDENTITY, column, Transform3D.IDENTITY))
	assert_true(snap.solid_overlap(wall, Transform3D.IDENTITY, wall, Transform3D.IDENTITY))
	assert_true(snap.solid_overlap(column, Transform3D.IDENTITY, machine, Transform3D.IDENTITY))
	assert_true(snap.solid_overlap(column, Transform3D.IDENTITY, game.catalog.get_piece("straight"), Transform3D.IDENTITY), "Track cannot pass through the column")
	for definition in [column, machine, game.catalog.get_piece("straight")]:
		session.editor()
		assert_not_null(place_object(definition, Vector3(6, 0, 0)))
		assert_null(place_object(column, Vector3(6, 0, 0)), "Actual placement rejects overlap with " + definition.display_name)
		assert_eq(build.pieces.size(), 1, "Rejected placement preserves the existing object")

func test_legacy_scene_is_selected_dragged_and_persisted_by_shared_construction() -> void:
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	var data := draft(0)
	session.editor(data)
	assert_null(session.environment_node, "The authored scene is inside shared construction")
	assert_eq(build.snap.environment_solids.size(), 0, "No duplicate fixed collision remains")
	var composites: Array[BuildingPiece] = build.pieces.filter(func(piece): return piece.instance_id == PuzzleEnvironment.LEGACY_UID)
	assert_eq(composites.size(), 1)
	if composites.size() != 1: return
	var composite: BuildingPiece = composites[0]
	assert_eq(composite.definition.collision_solids.size(), 6)
	assert_gt(composite.meshes.size(), 0, "Composite meshes participate in selection highlighting")
	assert_eq(session.store.fingerprint(session.capture()), data.validation.fingerprint, "Opening an existing scene preserves proof")
	build.camera.frame_point(Vector3(5, 1.2, -4), 5)
	for frame in 40: await get_tree().physics_frame
	var screen := build.camera.unproject_position(Vector3(5, 1.2, -4))
	var sender := GutInputSender.new(Input)
	autofree(sender)
	sender.mouse_motion(screen)
	await get_tree().process_frame
	sender.mouse_left_button_down(screen)
	await get_tree().process_frame
	assert_eq(build.selected, composite, "Clicking the existing column selects Service block")
	sender.mouse_motion(screen + Vector2(90, 0))
	await get_tree().process_frame
	sender.mouse_left_button_up(screen + Vector2(90, 0))
	await get_tree().process_frame
	assert_ne(composite.position, Vector3.ZERO, "Normal drag moves the existing scene")
	assert_eq(composite.position.y, 0.0)
	var moved := build.snapshot(true)
	build.undo()
	assert_eq(session.store.fingerprint(session.capture()), data.validation.fingerprint)
	build.redo()
	assert_eq(build.snapshot(true), moved)
	build.rotate_piece()
	var edited := session.capture()
	assert_true(edited.has("environment_placement"))
	assert_eq(edited.environment, data.environment, "The source scene reference is preserved")
	assert_true(session.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.store.drafts_directory + "/" + data.id + ".json"))
	session.editor(saved)
	composite = build.pieces.filter(func(piece): return piece.instance_id == PuzzleEnvironment.LEGACY_UID)[0]
	assert_eq(composite.transform, PuzzleEnvironment.transform_for(saved.environment_placement))
	assert_eq(composite.model_node.get_node("Object0/Body").collision_layer, 1)
	assert_eq(composite.model_node.get_node("Object0/Visual/Body/Solid").disabled, true, "Original companion collision stays intact")
	build.select(composite)
	build.move_selected(true)
	build.proposed.origin += Vector3(12, 0, 0)
	build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces).is_empty()
	build.apply_preview()
	build.commit()
	assert_eq(session.capture().environment_instances.size(), 1, "Composite duplication uses ordinary placed scene data")
	assert_true(session.save())
	saved = JSON.parse_string(FileAccess.get_file_as_string(session.store.drafts_directory + "/" + data.id + ".json"))
	session.editor(saved)
	assert_eq(session.capture().environment_instances[0].scene, data.environment)
	build.select(build.pieces.filter(func(piece): return piece.instance_id == PuzzleEnvironment.LEGACY_UID)[0])
	build.delete_selected()
	assert_false(session.capture().has("environment"))
	build.undo()
	assert_eq(session.capture().environment, data.environment)
	session.player(session.capture(), true)
	assert_false(build.authoring)
	assert_false(build.pieces.any(func(piece): return piece.definition.authoring_only))
	assert_not_null(session.environment_node.get_node("service_block/Object0/Body"))
	assert_eq(build.snap.environment_solids.size(), 12, "Player mode retains both fixed scene collisions")
	sender.release_all()

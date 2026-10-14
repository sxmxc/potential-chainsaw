extends "res://tests/support/scene_test.gd"

var game: Node
const PUBLISHED_IDS = ["chapter1-service-block", "chapter1-loading-loft", "chapter1-shared-clearance", "chapter1-jwytyk"]

func before_each() -> void:
	super()
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	await get_tree().process_frame

func draft() -> Dictionary:
	var data : Dictionary = game.workspace.session.store.create()
	data.pieces = [
		{"piece": "sandbox-start", "uid": "start", "position": [0, 0, 2], "rotation": 0, "config": {}},
		{"piece": "straight", "uid": "approach", "position": [0, 0, 1], "rotation": 0, "config": {}},
		{"piece": "straight", "uid": "exit", "position": [0, 0, -1], "rotation": 0, "config": {}},
		{"piece": "sandbox-finish", "uid": "finish", "position": [0, 0, -2], "rotation": 2, "config": {}}
	]
	data.objectives = [{"type": "deliver", "target": "finish", "count": 1}]
	data.inventory = {"straight": 1}
	return data

func test_retired_scene_fields_are_rejected_for_every_source() -> void:
	var store: PuzzleStore = game.workspace.session.store
	assert_null(game.workspace.catalog.get_piece("environment_scene:res://scenes/main.tscn"))
	assert_null(game.workspace.get_node_or_null("SceneDialog"))
	assert_null(game.workspace.hud.get_node("%Toolbox").get_node_or_null("%AddScenery"))
	for key in ["environment", "environment_snapshot", "environment_placement"]:
		var data := draft()
		data[key] = "res://scenes/main.tscn"
		var path := test_directory.path_join("retired.json")
		assert_true(store.write(path, data))
		for source in ["draft", "local", "campaign", "community"]:
			assert_true(store.load_puzzle(path, source).is_empty())
			assert_true(store.last_error.contains("no longer supported"))
	assert_true(store.list_drafts().is_empty(), "Draft discovery reads only the isolated user library")

func test_published_scenery_solutions_use_catalog_physics(index = use_parameters([0, 1, 2, 3])) -> void:
	var session: ConstructionSession = game.workspace.session
	var levels := session.store.load_campaign().levels
	var matching: Array[Dictionary] = levels.filter(func(item): return item.id == PUBLISHED_IDS[index])
	assert_eq(matching.size(), 1, "The published puzzle resolves through its manifest registration")
	if matching.is_empty(): return
	var data: Dictionary = matching[0]
	assert_false(data.has("environment_snapshot"))
	assert_false(data.environment_instances.is_empty())
	session.editor(data, true)
	assert_true(session.test_player(), "Published catalog layout passes player rules: " + data.name)
	if not session.is_testing: return
	assert_eq(game.workspace.world.build.rules.validate(data.solution), "", "Stored reference follows current catalog rules: " + data.name)
	assert_true(session.restore_reference(), "Reference passes actual player construction validation")
	if game.workspace.world.build.rules.validate(data.solution) != "": return
	assert_true(game.workspace.world.simulation.start())
	for frame in int(float(data.get("time_limit", 90)) * 120 + 5):
		await get_tree().physics_frame
		if game.workspace.world.simulation.state in [SimulationManager.State.SUCCESS, SimulationManager.State.FAILED]: break
	assert_eq(game.workspace.world.simulation.state, SimulationManager.State.SUCCESS, data.name + ": catalog scenery preserves physical completion")
	game.workspace.world.simulation.reset()
	session.return_editor()
	assert_eq(session.capture().environment_instances.size(), data.environment_instances.size())

func test_catalog_scenery_physically_blocks_marble() -> void:
	var data := draft()
	data.environment_instances = [{"uid": "column", "asset": "column", "position": [6, 0, 0], "rotation": 0}]
	game.workspace.session.player(data, true)
	var body: RigidBody3D = autoqfree(load("res://scenes/marble.tscn").instantiate())
	game.workspace.world.add_child(body)
	body.position = Vector3(6, 3, 0)
	for frame in 150: await get_tree().physics_frame
	assert_gt(body.position.y, 2.3, "The registered column physically catches the marble")
	var straight: PieceDefinition = game.workspace.catalog.get_piece("straight")
	assert_eq(game.workspace.world.build.snap.validate(straight, Transform3D(Basis.IDENTITY, Vector3(6, 1, 0)), []), "Blocked by the environment")

func place_object(definition: PieceDefinition, point: Vector3) -> BuildingPiece:
	var build: BuildManager = game.workspace.world.build
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
	var session: ConstructionSession = game.workspace.session
	var build: BuildManager = game.workspace.world.build
	session.editor(draft())
	assert_true(build.enabled)
	var wall := place_object(game.workspace.catalog.get_piece("environment:partition"), Vector3(6, 0, 0))
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
	assert_true(session.save_draft())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.store.drafts_directory + "/" + session.puzzle.id + ".json"))
	assert_eq(saved.environment_instances[0].position, [7.0, 0.5, 1.0])
	assert_eq(saved.environment_instances[0].rotation, 1.0)
	session.editor(saved)
	var restored: BuildingPiece = build.pieces.back()
	assert_eq(restored.instance_id, uid)
	assert_almost_eq(restored.position, Vector3(7, 0.5, 1), Vector3.ONE * 0.001)
	assert_eq(restored.bodies[0].collision_layer, 1)
	assert_false(restored.definition.connectors.size() > 0)
	assert_ne(build.snap.validate(game.workspace.catalog.get_piece("straight"), restored.transform, build.pieces), "")
	assert_true(session.test_player())
	assert_false(build.authoring)
	build.choose(game.workspace.catalog.get_piece("environment:partition"))
	assert_null(build.ghost)
	assert_null(build.spawn(game.workspace.catalog.get_piece("environment:partition"), Transform3D.IDENTITY))
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
	var session: ConstructionSession = game.workspace.session
	var build: BuildManager = game.workspace.world.build
	session.editor(draft())
	session.puzzle.version = 2
	var proof := session.store.fingerprint(session.capture())
	var column := place_object(game.workspace.catalog.get_piece("environment:column"), Vector3(6, 0, 0))
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
	var session: ConstructionSession = game.workspace.session
	var build: BuildManager = game.workspace.world.build
	session.editor()
	var track := place_object(game.workspace.catalog.get_piece("straight"), Vector3(4, 1, 0))
	var wall := place_object(game.workspace.catalog.get_piece("environment:partition"), Vector3(7, 0, 0))
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

func test_environment_shortcuts_after_leaving_catalog_focus() -> void:
	var session: ConstructionSession = game.workspace.session
	var build: BuildManager = game.workspace.world.build
	session.editor(draft())
	var toolbox = game.get_node("Workspace/Interface/HUD").get_node("%Toolbox")
	var categories: Array[String] = game.workspace.catalog.categories()
	var category_menu: OptionButton = toolbox.get_node("%Category")
	assert_eq(category_menu.item_count, categories.size(), "The toolbox adds no categories outside the registry and All pieces")
	for index in categories.size():
		assert_eq(category_menu.get_item_text(index), categories[index])
	assert_not_null(place_object(game.workspace.catalog.get_piece("straight"), Vector3(6, 0, 5)))
	var category: String = game.workspace.catalog.get_piece("environment:partition").category
	toolbox.get_node("%Category").select(game.workspace.catalog.categories().find(category))
	toolbox.refresh()
	assert_true(toolbox.buttons.has(&"environment:partition"))
	assert_true(toolbox.buttons.keys().all(func(id): return game.workspace.catalog.get_piece(String(id)).category == category), "Category filtering follows registered membership")
	assert_null(toolbox.get_node_or_null("%Catalog"), "There is one catalog")
	var sender := GutInputSender.new(Input)
	autofree(sender)
	build.camera.frame_point(Vector3(6, 1, 0), 5)
	for frame in 40: await get_tree().physics_frame
	toolbox.buttons[&"environment:partition"].chosen.emit(game.workspace.catalog.get_piece("environment:partition"))
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
	assert_true(session.save_draft())
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
	var session: ConstructionSession = game.workspace.session
	var build: BuildManager = game.workspace.world.build
	session.editor()
	var target := place_object(game.workspace.catalog.get_piece("environment:" + example.target), Vector3(6, 0, 0))
	assert_not_null(target)
	if not target: return
	build.camera.frame_point(Vector3(6, 1.2, 0), 6)
	await wait_seconds(1.5)
	var sender := GutInputSender.new(Input)
	autofree(sender)
	sender.set_auto_flush_input(true)
	var toolbox = game.get_node("Workspace/Interface/HUD").get_node("%Toolbox")
	toolbox.buttons[StringName("environment:" + example.source)].chosen.emit(game.workspace.catalog.get_piece("environment:" + example.source))
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
	assert_true(session.save_draft())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.store.drafts_directory.path_join(session.puzzle.id + ".json")))
	session.editor(saved)
	assert_eq(build.snapshot(true), arrangement, "Off-grid contact positions survive save and reopen")
	sender.release_all()

func test_column_overlaps_wall_corner_through_normal_placement() -> void:
	var session: ConstructionSession = game.workspace.session
	var build: BuildManager = game.workspace.world.build
	session.editor()
	var wall: PieceDefinition = game.workspace.catalog.get_piece("environment:partition")
	var column: PieceDefinition = game.workspace.catalog.get_piece("environment:column")
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
	var session: ConstructionSession = game.workspace.session
	var build: BuildManager = game.workspace.world.build
	var column: PieceDefinition = game.workspace.catalog.get_piece("environment:column")
	var wall: PieceDefinition = game.workspace.catalog.get_piece("environment:partition")
	var machine: PieceDefinition = game.workspace.catalog.get_piece("environment:machine")
	assert_true(snap.permits_overlap(column, wall))
	assert_true(snap.permits_overlap(wall, column))
	assert_true(snap.solid_overlap(column, Transform3D.IDENTITY, wall, Transform3D.IDENTITY), "Permitted joints still have real overlapping geometry")
	assert_true(snap.solid_overlap(column, Transform3D.IDENTITY, column, Transform3D.IDENTITY))
	assert_true(snap.solid_overlap(wall, Transform3D.IDENTITY, wall, Transform3D.IDENTITY))
	assert_true(snap.solid_overlap(column, Transform3D.IDENTITY, machine, Transform3D.IDENTITY))
	assert_true(snap.solid_overlap(column, Transform3D.IDENTITY, game.workspace.catalog.get_piece("straight"), Transform3D.IDENTITY), "Track cannot pass through the column")
	for definition in [column, machine, game.workspace.catalog.get_piece("straight")]:
		session.editor()
		assert_not_null(place_object(definition, Vector3(6, 0, 0)))
		assert_null(place_object(column, Vector3(6, 0, 0)), "Actual placement rejects overlap with " + definition.display_name)
		assert_eq(build.pieces.size(), 1, "Rejected placement preserves the existing object")

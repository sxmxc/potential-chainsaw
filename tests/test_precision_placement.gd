extends "res://tests/support/scene_test.gd"

var game: Node
var build: BuildManager
var sender: GutInputSender

func before_each() -> void:
	super()
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	await get_tree().process_frame
	game.workspace.session.editor()
	build = game.workspace.world.build
	game.get_node("Workspace/Interface/HUD").hide()
	sender = autofree(GutInputSender.new(Input))
	sender.set_auto_flush_input(true)

func attach(definition: PieceDefinition, point: Vector3) -> BuildingPiece:
	build.choose(definition)
	var cursor := build.camera.unproject_position(point)
	Input.warp_mouse(cursor)
	sender.mouse_motion(cursor)
	await wait_process_frames(3)
	assert_true(build.is_snapped, "Placement targets the pointed surface")
	assert_true(build.valid, build.validation_message)
	if not build.valid: return null
	var preview := build.proposed
	var count := build.pieces.size()
	sender.mouse_left_button_down(cursor)
	await get_tree().process_frame
	sender.mouse_left_button_up(cursor)
	await get_tree().process_frame
	assert_eq(build.pieces.size(), count + 1, "Ordinary click commits placement")
	if build.pieces.size() != count + 1: return null
	var placed: BuildingPiece = build.pieces.back()
	assert_true(placed.transform.is_equal_approx(preview), "Preview and committed transform agree")
	build.cancel()
	return placed

func test_representative_editor_construction_workflow() -> void:
	var wall := game.workspace.catalog.get_piece("environment:partition") as PieceDefinition
	var floor_piece := game.workspace.catalog.get_piece("environment:deck") as PieceDefinition
	build.spawn(wall, Transform3D.IDENTITY)
	build.camera.frame_point(Vector3(0,1.2,1), 6)
	await wait_seconds(0.8)
	var second := await attach(wall, Vector3(0.05,1.2,0.99))
	assert_not_null(second)
	if not second: return
	assert_almost_eq(second.position, Vector3(0,0,2), Vector3.ONE * 0.002, "Walls join end to end")
	var platform := build.spawn(floor_piece, Transform3D(Basis.IDENTITY,Vector3(6,3,0)))
	build.camera.frame_point(Vector3(6,3.1,0), 8)
	await wait_seconds(0.8)
	var next_floor := await attach(floor_piece, Vector3(6.99,3.1,0))
	assert_not_null(next_floor)
	if not next_floor: return
	assert_almost_eq(next_floor.position, Vector3(8,3,0), Vector3.ONE * 0.002, "Floor edges meet flush")
	var elevated_wall := await attach(wall, Vector3(6,3.1,0))
	assert_not_null(elevated_wall)
	if not elevated_wall: return
	assert_almost_eq(elevated_wall.position.y, 3.1, 0.002, "Elevated platform overrides the active ground grid")
	build.select(elevated_wall)
	build.rotate_piece()
	assert_almost_eq(absf(elevated_wall.rotation.y), PI/2, 0.002)
	assert_almost_eq(elevated_wall.position, Vector3(6,3.1,0), Vector3.ONE * 0.002, "Rotation keeps the pivot")
	# Grab above the base and drag through ordinary input, preserving its height.
	var start := build.camera.unproject_position(Vector3(6,4.1,0))
	var destination := start + Vector2(170,40)
	Input.warp_mouse(start)
	sender.mouse_motion(start)
	sender.mouse_left_button_down(start)
	await get_tree().process_frame
	Input.warp_mouse(destination)
	sender.mouse_motion(destination)
	await wait_process_frames(3)
	assert_true(build.direct_drag)
	var moved_preview := build.proposed
	sender.mouse_left_button_up(destination)
	await get_tree().process_frame
	assert_true(elevated_wall.transform.is_equal_approx(moved_preview), "Dragging commits the preview")
	assert_almost_eq(elevated_wall.position.y, 3.1, 0.002, "Free dragging preserves elevation")
	var group: Array[BuildingPiece] = [platform,next_floor]
	build.set_selection(group)
	var arrangement := build.snapshot(true)
	build.elevate_selected(-0.5)
	assert_almost_eq(next_floor.position - platform.position, Vector3(2,0,0), Vector3.ONE * 0.002, "Group edit preserves relative transforms")
	build.undo()
	assert_eq(build.snapshot(true), arrangement, "One undo restores the group")
	build.redo()
	build.undo()
	build.camera.frame_point(Vector3(-6,1,0), 6)
	await wait_seconds(0.8)
	var straight := game.workspace.catalog.get_piece("straight") as PieceDefinition
	var track := build.spawn(straight,Transform3D(Basis.IDENTITY,Vector3(-6,1,0)))
	await get_tree().physics_frame
	var port: Dictionary = build.snap.exposed([track])[0]
	var connected := await attach(straight, port.point)
	assert_not_null(connected)
	assert_eq(build.snap.exposed([track,connected]).size(), 2, "Track attachment consumes matching connectors")
	assert_true(build.pieces.all(func(piece: BuildingPiece): return piece.visible))
	sender.release_all()
	game.get_node("Workspace/Interface/HUD").show()
	build.frame_all()
	await wait_seconds(3.0)

func test_precision_faces_and_elevated_surfaces() -> void:
	var wall := game.workspace.catalog.get_piece("environment:partition") as PieceDefinition
	var floor_piece := game.workspace.catalog.get_piece("environment:deck") as PieceDefinition
	var target := build.spawn(wall, Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)))
	var platform := build.spawn(floor_piece, Transform3D(Basis.IDENTITY, Vector3(6, 3, 0)))
	var cases: Array[Dictionary] = [
		{"target":target, "source":wall, "point":Vector3(0.05,4.2,0.99), "expected":Vector3(0,3,2)},
		{"target":platform, "source":floor_piece, "point":Vector3(6.99,3.1,0), "expected":Vector3(8,3,0)},
		{"target":platform, "source":wall, "point":Vector3(6,3.1,0), "expected":Vector3(6,3.1,0)}
	]
	for example in cases:
		var items: Array[Dictionary] = [{"definition":example.source, "local":Transform3D.IDENTITY}]
		for angle in [0.4, 0.8, 1.2]:
			build.camera.target_focus = example.point
			build.camera.target_yaw = angle
			build.camera.target_pitch = 0.6
			build.camera.target_distance = 7
			build.camera._update(1)
			await wait_seconds(0.6)
			await get_tree().physics_frame
			var cursor := build.camera.unproject_position(example.point)
			var candidates := build.snap.screen_candidates(items, [], [], build.camera, cursor, build.pieces, [])
			assert_false(candidates.is_empty(), "Ray finds the intended surface at yaw " + str(angle))
			if candidates.is_empty(): continue
			assert_eq(candidates[0].target.piece, example.target)
			assert_eq(candidates[0].error, "")
			assert_almost_eq(candidates[0].transform.origin, example.expected, Vector3.ONE * 0.002, "World geometry decides alignment, independent of active height and camera")
			assert_true(candidates[0].transform.basis.is_equal_approx(Basis.IDENTITY), "Surface attachment retains rotation")
	var penetrating := Transform3D(Basis.IDENTITY, Vector3(6,3.05,0))
	assert_ne(build.snap.validate(floor_piece, penetrating, build.pieces), "", "Contact tolerance does not permit penetration")

func test_curated_geometry_and_decorative_selection() -> void:
	var doorway := game.workspace.catalog.get_piece("environment:building-wall-doorway-square") as PieceDefinition
	var probe := PieceDefinition.new()
	probe.bounds = AABB(Vector3(-0.2, 0, -0.2), Vector3(0.4, 1, 0.4))
	probe.collision_solids = [probe.bounds]
	assert_false(build.snap.solid_overlap(probe, Transform3D.IDENTITY, doorway, Transform3D.IDENTITY), "Doorway opening remains usable")
	assert_true(build.snap.solid_overlap(probe, Transform3D(Basis.IDENTITY, Vector3(0,0,0.8)), doorway, Transform3D.IDENTITY), "Doorway jamb remains solid")
	var display := build.spawn(game.workspace.catalog.get_piece("environment:factory-screen-panel-small"), Transform3D.IDENTITY)
	assert_eq(display.bodies[0].collision_layer, 4, "Decorative display is pickable")
	assert_eq(display.bodies[0].collision_mask, 0, "Decorative display does not interact with marbles")
	assert_false(build.snap.solid_overlap(display.definition, display.transform, doorway, Transform3D.IDENTITY))
	for definition in game.workspace.catalog.query():
		if not String(definition.id).begins_with("environment:building-") and not String(definition.id).begins_with("environment:factory-"): continue
		var piece := autofree(BuildManager.PIECE_SCENE.instantiate()) as BuildingPiece
		piece.setup(definition, true)
		var measured := AABB()
		for index in piece.meshes.size():
			var mesh: MeshInstance3D = piece.meshes[index]
			var placement := mesh.transform
			var parent := mesh.get_parent() as Node3D
			while parent != piece:
				placement = parent.transform * placement
				parent = parent.get_parent() as Node3D
			var box := placement * mesh.get_aabb()
			measured = box if index == 0 else measured.merge(box)
		assert_almost_eq(measured.position, definition.bounds.position, Vector3.ONE * 0.001, String(definition.id) + " measured pivot")
		assert_almost_eq(measured.size, definition.bounds.size, Vector3.ONE * 0.001, String(definition.id) + " measured bounds")



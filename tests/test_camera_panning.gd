extends GutTest

var viewport: SubViewport
var camera: ConstructionCamera

func before_each() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	add_child_autoqfree(viewport)
	camera = ConstructionCamera.new()
	viewport.add_child(camera)
	camera.set_process(false)

func settle() -> void:
	camera._update(1)
	camera.reset_physics_interpolation()
	await get_tree().physics_frame
	await get_tree().physics_frame
	for frame in 4: await get_tree().process_frame

func mouse_button(button: MouseButton, point: Vector2, alt: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.pressed = true
	event.alt_pressed = alt
	camera._unhandled_input(event)

func drag(point: Vector2, motion: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.relative = motion
	camera._unhandled_input(event)

func test_pan_tracks_pixels_at_near_far_and_horizon() -> void:
	for dimensions in [Vector2i(1024,720), Vector2i(1920,1080)]:
		viewport.size = dimensions
		for zoom in [0.3, 8.0, 220.0]:
			for angle in [0.01, 0.65, 1.48]:
				camera.target_pitch = angle
				camera.target_distance = zoom
				camera.target_focus = Vector3(0, 20, 0)
				camera.navigation_pivot = camera.target_focus
				await settle()
				var point := Vector2(dimensions)*0.6
				var motion := Vector2(80,50)
				var grabbed := camera.project_position(point, zoom)
				mouse_button(MOUSE_BUTTON_MIDDLE, point)
				drag(point+motion, motion)
				await settle()
				assert_almost_eq(camera.unproject_position(grabbed), point+motion, Vector2.ONE*0.1)
				camera.drag_button = 0

func test_framing_fits_every_corner_for_small_tall_and_sprawling_bounds() -> void:
	camera.composition_offset = Vector2(0.08,0.08)
	for dimensions in [Vector2i(1920,1080), Vector2i(720,1024)]:
		viewport.size = dimensions
		for extent in [Vector3(0.03,0.05,0.04), Vector3(3,160,4), Vector3(400,80,280)]:
			var bounds := AABB(Vector3(20,30,-90), extent)
			camera.frame_bounds(bounds)
			await settle()
			assert_eq(camera.navigation_pivot, bounds.get_center())
			for index in 8:
				var screen := camera.unproject_position(bounds.get_endpoint(index))
				assert_true(Rect2(Vector2.ZERO, Vector2(dimensions)).has_point(screen), "Every corner fits: %s" % screen)
				assert_true(camera.is_position_in_frustum(bounds.get_endpoint(index)))

func test_orbit_preserves_pivot_projection_without_start_jump() -> void:
	camera.navigation_pivot = Vector3(2,3,-1)
	await settle()
	var eye := camera.get_camera_transform().origin
	var screen := camera.unproject_position(camera.navigation_pivot)
	mouse_button(MOUSE_BUTTON_RIGHT, screen)
	assert_eq(camera.get_camera_transform().origin, eye)
	var radius := eye.distance_to(camera.navigation_pivot)
	for index in 10:
		drag(screen, Vector2(15,5))
		await settle()
		assert_almost_eq(camera.unproject_position(camera.orbit_pivot), screen, Vector2.ONE*0.1)
		assert_almost_eq(camera.get_camera_transform().origin.distance_to(camera.orbit_pivot), radius, 0.001)

func test_cursor_zoom_preserves_off_center_anchor_through_smoothing() -> void:
	camera.composition_offset = Vector2(0.08,0.08)
	await settle()
	var pointer := Vector2(1300,400)
	var anchor := camera.project_position(pointer, camera.distance)
	var old_eye := camera.get_camera_transform().origin
	camera.zoom_at(pointer, 1)
	for index in 20:
		camera._update(0.2)
		camera.reset_physics_interpolation()
		await get_tree().process_frame
		assert_almost_eq(camera.unproject_position(anchor), pointer, Vector2.ONE*0.1)
	assert_lt(camera.get_camera_transform().origin.distance_to(anchor), old_eye.distance_to(anchor))

func test_disabled_camera_clears_drag_and_ignores_input() -> void:
	mouse_button(MOUSE_BUTTON_RIGHT, Vector2(900,500))
	camera.enabled = false
	assert_eq(camera.drag_button, 0)
	var old_yaw := camera.target_yaw
	drag(Vector2(900,500), Vector2(100,100))
	assert_eq(camera.target_yaw, old_yaw)

func test_large_construction_navigation_with_real_geometry_and_phantom_host() -> void:
	camera.queue_free()
	await get_tree().process_frame
	var world := load("res://scenes/world.tscn").instantiate() as WorldManager
	viewport.add_child(world)
	world.configure(PieceCatalog.new())
	world.set_input_enabled(true)
	camera = world.camera
	camera.set_process(false)
	var build := world.build
	var definition := build.catalog.get_piece("straight")
	# A three-dimensional lattice: 240 pieces spanning 210 x 60 x 90 units.
	for level in 4:
		for row in 6:
			for column in 10:
				build.spawn(definition, Transform3D(Basis.IDENTITY, Vector3(column*23,level*20,row*18)), "nav-%d-%d-%d" % [level,row,column])
	await get_tree().physics_frame
	await get_tree().physics_frame
	for frame in 4: await get_tree().process_frame
	var before := build.snapshot()
	build.frame_all()
	await settle()
	await get_tree().process_frame
	var whole_distance := camera.distance
	var all_bounds := build.navigation_bounds(build.pieces)
	for index in 8: assert_true(camera.is_position_in_frustum(all_bounds.get_endpoint(index)))
	var piece := build.pieces[137]
	build.set_selection([piece, build.pieces[218]])
	build.frame_pieces(build.selection)
	await settle()
	var group_bounds := build.navigation_bounds(build.selection)
	for index in 8: assert_true(camera.is_position_in_frustum(group_bounds.get_endpoint(index)))
	build.set_selection([piece])
	var frame := InputEventKey.new()
	frame.keycode = KEY_F
	frame.pressed = true
	camera._unhandled_input(frame)
	await settle()
	await get_tree().process_frame
	assert_lt(camera.distance, whole_distance/20.0, "F approaches one small piece in a large machine")
	assert_almost_eq(camera.target_focus, build.navigation_bounds([piece]).get_center(), Vector3.ONE*0.001)
	var point := camera.unproject_position(camera.target_focus)
	var hit := camera.geometry_hit(point)
	assert_false(hit.is_empty(), "Real collision geometry supplies the cursor depth")
	if hit.is_empty(): return
	var surface: Vector3 = hit.position
	mouse_button(MOUSE_BUTTON_RIGHT, point)
	var pivot := camera.orbit_pivot
	assert_almost_eq(pivot, build.navigation_bounds([piece]).get_center(), Vector3.ONE*0.001)
	build.set_selection([build.pieces[138]])
	drag(point, Vector2(40,15))
	await settle()
	assert_eq(camera.orbit_pivot, pivot, "Selection changes cannot move a pivot mid-gesture")
	camera.drag_button = 0
	build.set_selection([piece])
	build.frame_pieces([piece])
	await settle()
	await get_tree().process_frame
	point = camera.unproject_position(surface)
	mouse_button(MOUSE_BUTTON_RIGHT, point, true)
	assert_almost_eq(camera.orbit_pivot, surface, Vector3.ONE*0.01, "Explicit focus uses the surface, not the piece center")
	camera.drag_button = 0
	# Pan the actual surface off center, then zoom toward that same collision hit.
	mouse_button(MOUSE_BUTTON_MIDDLE, point)
	drag(point+Vector2(180,-90), Vector2(180,-90))
	await settle()
	camera.drag_button = 0
	point = camera.unproject_position(surface)
	assert_false(camera.geometry_hit(point).is_empty())
	camera.zoom_at(point, 2)
	for index in 8:
		camera._update(0.3)
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().process_frame
		await get_tree().process_frame
		assert_almost_eq(camera.unproject_position(surface), point, Vector2.ONE*0.2, "Geometry stays under the cursor throughout zoom")
	# Burst scrolling must stop outside the surface even before a rendered frame.
	for index in 60: camera.zoom_at(point, 1)
	await settle()
	await get_tree().process_frame
	assert_gt(camera.working_depth(surface), camera.near*2.0)
	build.set_selection([])
	mouse_button(MOUSE_BUTTON_MIDDLE, point)
	drag(point+Vector2(120,40), Vector2(120,40))
	await settle()
	camera.drag_button = 0
	camera._unhandled_input(frame)
	await settle()
	await get_tree().process_frame
	assert_almost_eq(camera.target_focus, all_bounds.get_center(), Vector3.ONE*0.001, "F without selection returns to the full construction")
	for index in 8: assert_true(camera.is_position_in_frustum(all_bounds.get_endpoint(index)))
	assert_eq(build.snapshot(), before, "Camera navigation never edits pieces or identities")
	assert_false(build.history.has_undo())

func test_ui_consumes_navigation_and_release_cannot_latch_a_drag() -> void:
	var panel := Panel.new()
	panel.size = Vector2(viewport.size)
	viewport.add_child(panel)
	await get_tree().process_frame
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_RIGHT
	button.pressed = true
	button.position = Vector2(500,500)
	viewport.push_input(button, true)
	assert_eq(camera.drag_button, 0, "GUI consumption prevents navigation from starting")
	panel.queue_free()
	await get_tree().process_frame
	viewport.push_input(button, true)
	assert_eq(camera.drag_button, MOUSE_BUTTON_RIGHT, "World pointer input reaches the existing controller")
	panel = Panel.new()
	panel.size = Vector2(viewport.size)
	viewport.add_child(panel)
	await get_tree().process_frame
	button.pressed = false
	viewport.push_input(button, true)
	assert_eq(camera.drag_button, 0, "Release over UI ends an active orbit")

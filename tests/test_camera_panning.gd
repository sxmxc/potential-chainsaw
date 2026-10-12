extends GutTest

func test_pan_in_small_viewport() -> void:
	await check_pan(Vector2i(1024, 720))

func test_pan_in_large_viewport() -> void:
	await check_pan(Vector2i(1920, 1080))

func check_pan(dimensions: Vector2i) -> void:
	var viewport := SubViewport.new()
	add_child_autoqfree(viewport)
	var camera := ConstructionCamera.new()
	viewport.add_child(camera)
	camera.set_process(false)
	viewport.size = dimensions
	await get_tree().process_frame
	for zoom in [8.0, 22.0]:
		for vertical in [false, true]:
			camera.target_distance = zoom
			camera.target_focus = Vector3(0, 2, 0)
			camera._update(1)
			camera.reset_physics_interpolation()
			await get_tree().process_frame
			var pointer := Vector2(dimensions) * Vector2(0.6, 0.6)
			var motion := Vector2(80, 50)
			var normal := camera.global_basis.z if vertical else Vector3.UP
			var plane := Plane(normal, normal.dot(camera.focus_point))
			var grabbed: Vector3 = plane.intersects_ray(camera.project_ray_origin(pointer), camera.project_ray_normal(pointer))
			camera.target_focus += camera.pan_offset(pointer + motion, motion, vertical)
			camera._update(1)
			camera.reset_physics_interpolation()
			await get_tree().process_frame
			assert_almost_eq(camera.unproject_position(grabbed).x, pointer.x + motion.x, 0.1, "Horizontal pan matches mouse pixels")
			assert_almost_eq(camera.unproject_position(grabbed).y, pointer.y + motion.y, 0.1, "Vertical pan follows the mouse")
			if not vertical: assert_almost_eq(camera.target_focus.y, 2.0, 0.001, "Ordinary pan preserves elevation")
	# Near the horizon, missing plane intersections must not jump the camera.
	camera.target_pitch = 0.01
	camera._update(1)
	camera.reset_physics_interpolation()
	await get_tree().process_frame
	var offset := camera.pan_offset(Vector2(10, 10), Vector2(40, 40))
	assert_eq(offset, Vector3.ZERO)

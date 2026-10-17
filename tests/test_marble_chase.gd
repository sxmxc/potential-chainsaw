extends GutTest

var world: WorldManager

func before_each() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(640, 360)
	add_child_autoqfree(viewport)
	world = load("res://scenes/world.tscn").instantiate()
	viewport.add_child(world)
	world.configure(PieceCatalog.new())
	world.build.spawn(world.build.catalog.get_piece("sandbox-start"), Transform3D(Basis.IDENTITY, Vector3(0, 5, 0)), "source", {"quantity": 1})
	assert_true(world.simulation.start())
	for frame in 4: await get_tree().process_frame

func test_freed_target_returns_to_free_view() -> void:
	var chase := world.simulation_camera.chase
	var body := world.simulation.marble
	assert_true(world.simulation_camera.follow(body))
	assert_true(world.camera.chase_active)
	watch_signals(chase)
	world.simulation.marbles.erase(body)
	body.queue_free()
	for frame in 3: await get_tree().process_frame
	assert_false(is_instance_valid(chase.marble))
	assert_false(world.camera.chase_active)
	assert_signal_emitted(chase, "target_lost")
	for view in chase.views: assert_eq(view.priority, 0)

func test_hidden_target_and_reset_clear_the_chase() -> void:
	var body := world.simulation.marble
	assert_true(world.simulation_camera.follow(body))
	world.hide()
	for frame in 3: await get_tree().process_frame
	assert_false(world.camera.chase_active, "Hidden ancestors make a target unsuitable")
	world.show()
	assert_true(world.simulation_camera.follow(body))
	world.simulation.reset()
	assert_false(world.camera.chase_active)
	assert_true(world.simulation_camera.available().is_empty())
	for view in world.simulation_camera.chase.views: assert_eq(view.priority, 0)

func test_follow_requires_current_simulation_membership() -> void:
	var body := world.simulation.marble
	world.simulation.marbles.erase(body)
	assert_false(world.simulation_camera.follow(body), "A live body outside this simulation cannot become its target")
	world.simulation.marbles.append(body)
	assert_true(world.simulation_camera.follow(body))
	world.simulation_camera.chase.tilt = .25
	world.simulation_camera.chase.stop()
	body.linear_velocity = Vector3(0, -2, -2)
	assert_true(world.simulation_camera.follow(body))
	assert_almost_eq(world.simulation_camera.chase.tilt, -.65, .001, "A fresh target does not inherit the previous shot's upward tilt")

func make_director() -> Node3D:
	world.name = "Track"
	var director := Node3D.new()
	director.name = "Director"
	director.set_script(load("res://scripts/camera/menu_camera_director.gd"))
	var detail := PhantomCamera3D.new()
	detail.name = "Detail"
	director.add_child(detail)
	var shots := Node3D.new()
	shots.name = "Shots"
	director.add_child(shots)
	for x in [-3.0, 3.0]:
		var pose := Marker3D.new()
		pose.position = Vector3(x, 10, 10)
		shots.add_child(pose)
	world.get_parent().add_child(director)
	director.set_process(false)
	return director

func test_director_cycles_detail_poses_and_abandons_a_missing_simulation_target() -> void:
	var director := make_director()
	var detail: PhantomCamera3D = director.get_node("Detail")
	var shots := director.get_node("Shots")
	director.set_active(true)
	for index in 2:
		director.remaining = 0
		director.call("_process", .01)
		assert_eq(director.shot, 1)
		assert_eq(detail.global_transform, shots.get_child(index).global_transform)
		director.remaining = 0
		director.call("_process", .01)
		assert_eq(director.shot, 2)
		assert_true(is_instance_valid(world.simulation_camera.chase.marble))
		for frame in 3: await get_tree().physics_frame
		await get_tree().process_frame
		director.remaining = 0
		director.call("_process", .01)
		assert_eq(director.shot, 0, "Every chase returns to a wide/detail cycle")
	director.remaining = 0
	director.call("_process", .01)
	director.remaining = 0
	director.call("_process", .01)
	world.simulation.marbles.clear()
	director.call("_process", .01)
	assert_eq(director.shot, 0)
	assert_false(is_instance_valid(world.simulation_camera.chase.marble))
	assert_eq(detail.priority, 0)
	director.set_active(false)

func test_director_only_follows_visible_moving_action() -> void:
	var director := make_director()
	var body := world.simulation.marble
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.camera.set_process(false)
	world.camera.get_node("PhantomCameraHost").set_process(false)
	world.camera.get_node("PhantomCameraHost").set_physics_process(false)
	body.gravity_scale = 0.0
	world.camera.global_position = Vector3(0, 10, 10)
	world.camera.look_at(Vector3(0, 10, 0))
	world.camera.h_offset = 0.0
	world.camera.v_offset = 0.0
	world.camera.reset_physics_interpolation()
	body.global_position = Vector3(0, 10, 0)
	body.linear_velocity = Vector3.RIGHT
	body.reset_physics_interpolation()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(director.call("_choose_marble"), "Moving action in the current shot can be followed")
	world.simulation_camera.chase.stop()
	body.global_position = Vector3(0, 10, 20)
	body.reset_physics_interpolation()
	await get_tree().process_frame
	assert_false(director.call("_choose_marble"), "Do not jump to a marble behind the camera")
	body.global_position = Vector3(100, 10, 0)
	body.reset_physics_interpolation()
	await get_tree().process_frame
	assert_false(director.call("_choose_marble"), "Do not jump to action outside the frame")
	body.global_position = Vector3(0, 10, 0)
	body.reset_physics_interpolation()
	body.freeze = true
	assert_false(director.call("_choose_marble"), "Captured marbles do not start chase shots")
	body.freeze = false
	body.linear_velocity = Vector3.ZERO
	assert_false(director.call("_choose_marble"), "Stationary marbles do not start chase shots")
	body.linear_velocity = Vector3.RIGHT
	var obstacle := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	obstacle.add_child(collision)
	world.add_child(obstacle)
	obstacle.global_position = Vector3(0, 10, 5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(director.call("_choose_marble"), "Occluded action does not start a chase")

func test_showcase_wide_orbit_covers_all_sides_and_wraps_continuously() -> void:
	# Exercise the scene-authored rig without starting the showcase simulation.
	var showcase: Node = load("res://scenes/showcase.tscn").instantiate()
	var orbit: Node3D = showcase.get_node("World/Orbit")
	var motion: AnimationPlayer = showcase.get_node("World/CameraMotion")
	orbit.get_parent().remove_child(orbit)
	motion.get_parent().remove_child(motion)
	showcase.free()
	var rig := Node3D.new()
	world.add_child(rig)
	rig.add_child(orbit)
	rig.add_child(motion)
	motion.set_process(false)
	var wide: PhantomCamera3D = orbit.get_node("Wide")
	var poses: Array[Transform3D] = []
	motion.play("showcase")
	for time in [0.0, 18.0, 36.0, 54.0, 71.999]:
		motion.seek(time, true)
		poses.append(wide.global_transform)
		var facing := -wide.global_basis.z
		assert_almost_eq(facing.dot(wide.global_position.direction_to(orbit.global_position)), 1.0, 0.001, "Every angle faces the machine")
		assert_almost_eq(wide.global_position.distance_to(orbit.global_position), 44.0, 0.001)
	for index in 3:
		assert_gt(poses[index].origin.distance_to(poses[index + 1].origin), 40.0, "Quarter turns cover distinct sides")
	assert_lt(poses[0].origin.distance_to(poses[4].origin), 0.01, "Loop seam preserves the pose")
	assert_eq(wide.priority, 10)

func test_first_chase_prepares_the_spring_before_activating() -> void:
	var chase := world.simulation_camera.chase
	var body := world.simulation.marble
	body.global_position = Vector3(30, 8, -20)
	body.reset_physics_interpolation()
	for view in chase.views: view.tween_resource.duration = 0
	assert_true(world.simulation_camera.follow(body))
	assert_true(chase.preparing)
	assert_eq(chase.views[chase.slot].priority, 0, "A cold spring arm does not take over the camera")
	for frame in 4: await get_tree().physics_frame
	await get_tree().process_frame
	assert_false(chase.preparing)
	assert_eq(chase.views[chase.slot].priority, 30)
	assert_gt(chase.views[chase.slot].global_position.distance_to(chase.targets[chase.slot].global_position), 1.0, "The spring has extended at the new target")
	assert_false(world.camera.is_position_behind(body.global_position))
	assert_true(Rect2(Vector2.ZERO, Vector2(640, 360)).has_point(world.camera.unproject_position(body.global_position)))

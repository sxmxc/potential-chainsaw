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

func test_director_cycles_detail_poses_and_abandons_a_missing_simulation_target() -> void:
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

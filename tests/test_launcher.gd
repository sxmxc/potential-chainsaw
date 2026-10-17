extends GutTest

var piece: BuildingPiece
var launcher: PieceBehavior
var shot_count: int = 0

func before_each() -> void:
	shot_count = 0
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autoqfree(viewport)
	piece = BuildingPiece.new()
	piece.position.y = 5
	viewport.add_child(piece)
	piece.setup(PieceCatalog.new().get_piece("launcher"))
	launcher = piece.behaviors[0]
	launcher.set_physics_process(false)
	launcher.start_run()
	watch_signals(launcher)
	launcher.output_raised.connect(func(port, _value):
		if port == "fired": shot_count += 1)

func marble() -> Marble:
	var body: Marble = load("res://scenes/marble.tscn").instantiate()
	body.gravity_scale = 0
	body.collision_mask = 0
	body.position = Vector3(10, 5, 0)
	piece.get_parent().add_child(body)
	return body

func move_marble(body: Marble, point: Vector3) -> void:
	body.global_position = point
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	for frame in 3: await get_tree().physics_frame

func test_auto_rearm_launches_returning_marbles_on_repeated_passes() -> void:
	var bodies: Array[Marble] = [marble(), marble(), marble()]
	for pass_index in 12:
		var body := bodies[pass_index % bodies.size()]
		await move_marble(body, launcher.area.global_position)
		assert_true(body.carried, "The launcher owns a physically captured waiting marble")
		advance(1.0)
		await get_tree().physics_frame
		assert_lt(body.linear_velocity.z, -1.0, "Every returning marble receives the launch impulse")
		assert_eq(shot_count, pass_index + 1)
		await move_marble(body, Vector3(10, 5, 0))
	assert_true(launcher.fired.is_empty(), "Departed marbles do not accumulate in the per-pass guard")

func test_one_shot_latches_across_exit_until_reset() -> void:
	launcher.configure({"auto_rearm": false})
	launcher.start_run()
	var body := marble()
	await move_marble(body, launcher.area.global_position)
	advance(0.6)
	await move_marble(body, Vector3(10, 5, 0))
	await move_marble(body, launcher.area.global_position)
	advance(0.6)
	assert_eq(shot_count, 1)
	launcher.reset()
	launcher.start_run()
	advance(0.6)
	assert_eq(shot_count, 2, "Reset restores the one-shot launcher")

func test_external_fire_pause_and_rearm_preserve_waiting_marbles() -> void:
	var shots: Array = []
	launcher.output_raised.connect(func(port, body):
		if port == "fired": shots.append(body))
	launcher.configure({"external": true})
	launcher.start_run()
	var body := marble()
	await move_marble(body, launcher.area.global_position)
	advance(0.6)
	assert_eq(shot_count, 0)
	launcher.active = false
	assert_false(launcher.receive("fire"), "Paused launchers ignore fire commands")
	launcher.active = true
	assert_true(launcher.receive("fire"))
	advance(0.12)
	await get_tree().physics_frame
	advance(0.12)
	assert_eq(shots.size(), 1, "Fire releases one captured waiting marble")
	advance(0.6)
	assert_eq(shots.size(), 1, "A marble still in the detector is not fired twice")
	await move_marble(body, Vector3(10, 5, 0))
	await move_marble(body, launcher.area.global_position)
	advance(0.6)
	assert_eq(shots.size(), 1, "A returning marble needs a new external trigger")
	launcher.receive("fire")
	advance(0.12)
	await get_tree().physics_frame
	advance(0.12)
	assert_eq(shots.size(), 2)

func test_build_arc_uses_world_direction_and_tracks_configuration() -> void:
	var original := launcher.build_trajectory()
	assert_true(original[0].is_equal_approx(launcher.release_point.global_position))
	assert_gt(original[1].y, original[0].y)
	assert_lt(original[1].z, original[0].z)
	assert_lt(original[-1].y, original[0].y, "Gravity bends the arc down")
	piece.rotation.y = PI / 2
	for frame in 2: await get_tree().physics_frame
	var rotated := launcher.build_trajectory()
	assert_lt(rotated[1].x, rotated[0].x, "Rotating the piece rotates the arc")
	launcher.configure({"angle": 0.0, "strength": 8.0})
	var flat := launcher.build_trajectory()
	assert_lt(flat[1].y, flat[0].y, "Zero elevation falls immediately")
	assert_gt(flat[0].x - flat[1].x, rotated[0].x - rotated[1].x, "Launch speed extends the arc")

func test_launch_velocity_is_independent_of_incoming_speed_and_spin() -> void:
	var body := marble()
	for incoming in [Vector3(0, 0, -0.5), Vector3(2, -3, -8), Vector3(-4, 1, 3)]:
		launcher.reset()
		launcher.start_run()
		await move_marble(body, launcher.area.global_position + Vector3(0.1, 0, 0.03))
		body.linear_velocity = incoming
		body.angular_velocity = Vector3(5, 2, -3)
		advance(0.6)
		assert_true(body.global_position.is_equal_approx(launcher.release_point.global_position), "Each shot starts at the same discharge point as the preview")
		assert_true(body.linear_velocity.is_equal_approx(launcher.launch_velocity()), "Every shot replaces the entire incoming velocity")
		assert_true(body.angular_velocity.is_zero_approx(), "Old rolling spin cannot change the shot")
		assert_false(body.freeze)
		assert_eq(body.collision_layer, 2, "Marble remains in normal rigid-body physics after launch")
		await move_marble(body, Vector3(10, 5, 0))

func test_handle_fires_rearms_and_freezes_on_pause() -> void:
	var handle: Node3D = launcher.arrow.get_node("Handle")
	assert_almost_eq(handle.rotation.x, 0.0, .001)
	var body := marble()
	await move_marble(body, launcher.area.global_position)
	advance(.22)
	advance(.05)
	assert_lt(handle.rotation.x, 0.0, "A front pivot lifts the trailing paddle forward")
	assert_true(body.carried, "The marble stays on the paddle during the stroke")
	var held_pose := body.global_transform
	var held_angle := handle.rotation.x
	launcher.active = false
	advance(.3)
	assert_eq(body.global_transform, held_pose)
	assert_almost_eq(handle.rotation.x, held_angle, .001)
	launcher.start_run()
	advance(.1)
	assert_false(body.carried)
	advance(.2)
	assert_eq(launcher.handle_animation.current_animation, "rearm")
	assert_between(handle.rotation.x, -.687, 0.0)
	advance(.5)
	assert_almost_eq(handle.rotation.x, 0.0, .001)
	launcher.reset()
	assert_almost_eq(handle.rotation.x, 0.0, .001)

func test_one_shot_handle_stays_unarmed_until_reset() -> void:
	launcher.configure({"auto_rearm": false, "angle": 45.0})
	launcher.start_run()
	var body := marble()
	await move_marble(body, launcher.area.global_position)
	advance(0.6)
	advance(0.6)
	var handle: Node3D = launcher.arrow.get_node("Handle")
	assert_almost_eq(handle.rotation.x, -0.6860478808414067, 0.001)
	launcher.reset()
	assert_almost_eq(handle.rotation.x, 0.0, 0.001)
	assert_almost_eq(atan2(launcher.launch_velocity().y, -launcher.launch_velocity().z), PI / 4, 0.001, "Configured elevation sets the deterministic release velocity")
	launcher.configure({"enabled": false})
	assert_almost_eq(handle.rotation.x, -0.6860478808414067, 0.001, "Disabled launcher is unarmed")

func test_arc_stops_at_marble_contact_and_ignores_nonphysical_layers() -> void:
	for frame in 2: await get_tree().physics_frame
	var unobstructed := launcher.build_trajectory()
	var wall := StaticBody3D.new()
	wall.collision_layer = 4
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# The centerline misses this narrow obstacle, but the marble's side hits it.
	shape.size = Vector3(0.1, 4, 0.02)
	collision.shape = shape
	wall.add_child(collision)
	piece.get_parent().add_child(wall)
	wall.global_position = launcher.release_point.global_position + Vector3(0.21, 0, -1)
	for frame in 2: await get_tree().physics_frame
	assert_eq(launcher.build_trajectory().size(), unobstructed.size(), "Selection-only collision does not stop a marble")
	wall.collision_layer = 1
	for frame in 2: await get_tree().physics_frame
	var blocked := launcher.build_trajectory()
	assert_gt(blocked.size(), 1)
	assert_lt(blocked.size(), unobstructed.size(), "End at the first obstacle, even if the centerline misses it")
	assert_gt(blocked[-1].z, wall.global_position.z, "Marble radius stops the center before the surface")
	assert_eq(launcher.build_trajectory([wall.get_rid()]).size(), unobstructed.size(), "Hidden moving originals can be excluded")
	wall.global_position = launcher.release_point.global_position
	for frame in 2: await get_tree().physics_frame
	assert_eq(launcher.build_trajectory().size(), 1, "A blocked discharge cannot show flight through the obstruction")

func test_trajectory_mesh_uses_depth_and_clears_outside_build_selection() -> void:
	var build := BuildManager.new()
	var preview := Node3D.new()
	preview.name = "PlacementPreview"
	build.add_child(preview)
	piece.get_parent().add_child(build)
	build.enabled = true
	build.selection = [piece]
	var overlay: Control = load("res://scenes/ui/widgets/selection_overlay.tscn").instantiate()
	piece.get_parent().add_child(overlay)
	overlay.build = build
	overlay.set_physics_process(false)
	for frame in 2: await get_tree().physics_frame
	overlay.call("_physics_process", 0.0)
	var visual: MeshInstance3D = overlay.get_node("Trajectories")
	assert_eq(visual.mesh.get_surface_count(), 1)
	assert_false(visual.material_override.no_depth_test, "Scene geometry occludes the world-space trajectory")
	var vertices: PackedVector3Array = visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_true(vertices[0].is_equal_approx(launcher.release_point.global_position))
	build.selection.clear()
	overlay.call("_physics_process", 0.0)
	assert_eq(visual.mesh.get_surface_count(), 0)
	build.selection = [piece]
	build.enabled = false
	overlay.call("_physics_process", 0.0)
	assert_false(visual.visible, "Simulation hides the trajectory")
	build.enabled = true
	overlay.hide()
	overlay.call("_physics_process", 0.0)
	assert_false(visual.visible, "Hiding the HUD hides its 3D feedback too")


func test_waiting_output_tracks_unfired_marbles_and_reset() -> void:
	launcher.configure({"external": true})
	launcher.start_run()
	var body := marble()
	await move_marble(body, launcher.area.global_position)
	advance(0.25)
	assert_true(launcher.output_values.loaded, "An unfired marble requests permission")
	launcher.receive("fire")
	advance(0.12)
	await get_tree().physics_frame
	advance(0.12)
	advance(0.12)
	assert_eq(shot_count, 1)
	assert_false(launcher.output_values.loaded, "A fired marble cannot request another shot")
	launcher.reset()
	assert_false(launcher.output_values.loaded)


func test_external_capture_holds_a_real_marble_until_firing() -> void:
	launcher.set_physics_process(true)
	launcher.configure({"external": true})
	launcher.start_run()
	var body := marble()
	body.gravity_scale = 1
	body.collision_mask = 1
	body.global_position = piece.global_position + Vector3(0, 0.46, 0.2)
	body.linear_velocity = Vector3(0, 0, -1.4)
	body.angular_velocity = Vector3(-7, 0, 0)
	for frame in 360: await get_tree().physics_frame
	assert_gt(body.global_position.y, piece.global_position.y + 0.4, "A waiting marble stays supported under gravity")
	assert_true(launcher.output_values.loaded, "The stopped marble stays detectable")
	assert_eq(shot_count, 0)
	launcher.receive("fire")
	for frame in 18: await get_tree().physics_frame
	assert_eq(shot_count, 1, "Permission launches the physically waiting marble")

func test_external_launcher_holds_a_close_following_marble_until_its_own_fire() -> void:
	var feeder := BuildingPiece.new()
	piece.get_parent().add_child(feeder)
	feeder.position = piece.position + Vector3(0, 0, 1)
	feeder.setup(PieceCatalog.new().get_piece("straight"))
	launcher.configure({"external": true})
	launcher.start_run()
	launcher.set_physics_process(true)
	var bodies: Array[Marble] = [marble(), marble()]
	for index in bodies.size():
		var body := bodies[index]
		body.gravity_scale = 1
		body.collision_mask = 1
		body.global_position = piece.global_position + Vector3(0, .46, .15 + index * .45)
		body.linear_velocity = Vector3(0, 0, -1.8)
		body.angular_velocity = Vector3(-9, 0, 0)
	for frame in 90: await get_tree().physics_frame
	launcher.receive("fire")
	for frame in 120: await get_tree().physics_frame
	assert_eq(shot_count, 1)
	assert_gt(bodies[1].position.y, piece.position.y + .4, "The following marble remains on the track")
	assert_gt(bodies[1].position.z, -.5, "The following marble stays captured until its own command")
	assert_true(launcher.output_values.loaded, "The next marble can request its own shot")
	launcher.receive("fire")
	for frame in 30: await get_tree().physics_frame
	assert_eq(shot_count, 2, "A second command fires the second queued marble")

func test_reset_restores_physics_for_every_waiting_marble() -> void:
	launcher.configure({"external": true})
	launcher.start_run()
	var bodies: Array[Marble] = [marble(), marble()]
	for body in bodies:
		body.collision_mask = 1
		await move_marble(body, launcher.area.global_position)
		assert_true(body.carried)
	launcher.active = false
	for frame in 3: await get_tree().physics_frame
	for body in bodies: assert_true(body.carried, "Pause retains loading ownership")
	launcher.reset()
	for body in bodies:
		assert_false(body.carried)
		assert_false(body.freeze)
		assert_eq(body.collision_layer, 2)
		assert_eq(body.collision_mask, 1)
	assert_true(launcher.waiting.is_empty())

func test_automatic_loading_queue_fires_each_close_arrival_once() -> void:
	for index in 2:
		var feeder := BuildingPiece.new()
		piece.get_parent().add_child(feeder)
		feeder.position = piece.position + Vector3(0, 0, index + 1)
		feeder.setup(PieceCatalog.new().get_piece("straight"))
	launcher.configure({"auto_rearm": true})
	launcher.start_run()
	launcher.set_physics_process(true)
	var bodies: Array[Marble] = []
	for index in 3:
		var body := marble()
		body.gravity_scale = 1
		body.collision_mask = 1
		body.global_position = piece.global_position + Vector3(0, .46, .15 + index * .45)
		body.linear_velocity = Vector3(0, 0, -1.8)
		body.angular_velocity = Vector3(-9, 0, 0)
		bodies.append(body)
	for frame in 240: await get_tree().physics_frame
	assert_eq(shot_count, 3, "Cooldown captures each follower until its own automatic shot")
	for body in bodies:
		assert_false(body.carried)
		assert_false(body.freeze)
		assert_eq(body.collision_layer, 2)
		assert_eq(body.collision_mask, 1)

func test_marble_rolls_from_standard_track_onto_flush_armed_paddle() -> void:
	piece.apply_configuration({"external": true})
	launcher.start_run()
	launcher.set_physics_process(true)
	var feeder := BuildingPiece.new()
	feeder.position = piece.position + Vector3(0, 0, 1)
	piece.get_parent().add_child(feeder)
	feeder.setup(PieceCatalog.new().get_piece("straight"))
	var body := marble()
	body.gravity_scale = 1
	body.collision_mask = 1
	body.global_position = piece.global_position + Vector3(0, .46, 1.1)
	body.linear_velocity = Vector3(0, 0, -1.4)
	for frame in 180: await get_tree().physics_frame
	assert_true(body.carried, "The normal inlet loads without a raised lip or external gate")
	assert_between(body.global_position.z, -.5, .35, "The captured marble has reached the armed paddle")
	assert_almost_eq(body.global_position.y, piece.global_position.y + .45, .03)
	assert_eq(shot_count, 0, "Loading waits for the external command")

func advance(seconds: float) -> void:
	var remaining := seconds
	while remaining > .000001:
		var step := minf(remaining, 1.0 / 120.0)
		launcher.call("_physics_process", step)
		remaining -= step

func test_loading_ignores_airborne_marbles_and_the_front_gap() -> void:
	launcher.configure({"external": true, "strength": .5, "angle": 65.0})
	launcher.start_run()
	var body := marble()
	await move_marble(body, piece.to_global(Vector3(0, .75, -.4)))
	advance(.3)
	assert_false(body.carried, "Passing above the paddle must not freeze a marble in midair")
	await move_marble(body, piece.to_global(Vector3(0, .45, -.6)))
	advance(.3)
	assert_false(body.carried, "A marble over the front gap is outside the loading surface")
	await move_marble(body, piece.to_global(Vector3(0, .45, .15)))
	advance(.3)
	assert_true(body.carried, "A marble on the track still loads normally")
	launcher.receive("fire")
	advance(.12)
	assert_false(body.carried)
	assert_true(body.linear_velocity.is_equal_approx(launcher.launch_velocity()))

func test_angle_and_speed_range_releases_into_moving_physics() -> void:
	for elevation in [0.0, 25.0, 65.0]:
		for speed in [.5, 4.0, 8.0]:
			launcher.configure({"external": true, "angle": elevation, "strength": speed})
			launcher.start_run()
			var body := marble()
			body.gravity_scale = 1
			body.collision_mask = 1
			await move_marble(body, launcher.area.global_position)
			advance(.25)
			launcher.receive("fire")
			advance(.12)
			assert_false(body.carried)
			assert_false(body.freeze)
			assert_true(body.linear_velocity.is_equal_approx(launcher.launch_velocity()))
			var release_position := body.global_position
			for frame in 6: await get_tree().physics_frame
			assert_false(body.carried, "A departing shot cannot be reclaimed in midair")
			assert_gt(body.global_position.distance_to(release_position), .002, "Every angle/speed combination moves after release")

func test_editing_settings_midstroke_restores_the_captured_body() -> void:
	launcher.configure({"external": true})
	launcher.start_run()
	var body := marble()
	body.collision_mask = 1
	await move_marble(body, launcher.area.global_position)
	advance(.25)
	launcher.receive("fire")
	advance(.05)
	assert_true(body.carried)
	piece.apply_configuration({"angle": 50.0, "strength": 7.0})
	assert_false(body.carried)
	assert_false(body.freeze)
	assert_eq(body.collision_layer, 2)
	assert_eq(body.collision_mask, 1)
	assert_true(launcher.waiting.is_empty())

func test_forward_stroke_keeps_contact_until_continuous_release() -> void:
	launcher.configure({"external": true})
	launcher.start_run()
	var body := marble()
	await move_marble(body, launcher.area.global_position)
	advance(.25)
	assert_true(launcher.output_values.loaded)
	assert_almost_eq(piece.to_local(body.global_position).y, .45, .0001, "Loading seats the marble on the flush paddle")
	launcher.receive("fire")
	advance(1.0 / 120.0)
	var previous := body.global_position
	for frame in 11:
		advance(1.0 / 120.0)
		assert_true(body.carried, "Release waits for the physical stroke")
		assert_true(body.global_position.is_equal_approx(launcher.loading_seat.global_position))
		assert_lt(body.global_position.z, previous.z, "The marble moves toward the track outlet, not backward")
		assert_gt(body.global_position.y, previous.y, "The paddle lifts the marble")
		assert_lt(body.global_position.distance_to(previous), .025, "The marble moves continuously on each tick")
		var contact: Vector3 = launcher.arrow.get_node("Handle").to_local(body.global_position)
		assert_almost_eq(contact.y, .23, .0001, "Marble radius plus paddle half-thickness: no penetration")
		previous = body.global_position
	advance(1.0 / 120.0)
	assert_eq(shot_count, 1)
	assert_false(body.carried)
	assert_lt(body.global_position.distance_to(previous), .025, "Release adds no visible position jump")
	assert_true(body.global_position.is_equal_approx(launcher.release_point.global_position))
	assert_true(body.linear_velocity.is_equal_approx(launcher.launch_velocity()))
	assert_true(body.angular_velocity.is_zero_approx())

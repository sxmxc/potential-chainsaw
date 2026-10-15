extends GutTest

var piece: BuildingPiece
var launcher: PieceBehavior

func before_each() -> void:
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
		assert_true(launcher.area.overlaps_body(body))
		launcher.call("_physics_process", 0.6)
		await get_tree().physics_frame
		assert_lt(body.linear_velocity.z, -1.0, "Every returning marble receives the launch impulse")
		assert_signal_emit_count(launcher, "output_raised", pass_index + 1)
		await move_marble(body, Vector3(10, 5, 0))
	assert_true(launcher.fired.is_empty(), "Departed marbles do not accumulate in the per-pass guard")

func test_one_shot_latches_across_exit_until_reset() -> void:
	launcher.configure({"auto_rearm": false})
	launcher.start_run()
	var body := marble()
	await move_marble(body, launcher.area.global_position)
	launcher.call("_physics_process", 0.6)
	await move_marble(body, Vector3(10, 5, 0))
	await move_marble(body, launcher.area.global_position)
	launcher.call("_physics_process", 0.6)
	assert_signal_emit_count(launcher, "output_raised", 1)
	launcher.reset()
	launcher.start_run()
	launcher.call("_physics_process", 0.6)
	assert_signal_emit_count(launcher, "output_raised", 2, "Reset restores the one-shot launcher")

func test_external_fire_pause_and_rearm_preserve_waiting_marbles() -> void:
	var shots: Array = []
	launcher.output_raised.connect(func(port, body):
		if port == "fired": shots.append(body))
	launcher.configure({"external": true})
	launcher.start_run()
	var body := marble()
	await move_marble(body, launcher.area.global_position)
	launcher.call("_physics_process", 0.6)
	assert_signal_not_emitted(launcher, "output_raised")
	launcher.active = false
	assert_false(launcher.receive("fire"), "Paused launchers ignore fire commands")
	launcher.active = true
	assert_true(launcher.receive("fire"))
	launcher.call("_physics_process", 0.01)
	await get_tree().physics_frame
	launcher.call("_physics_process", 0.01)
	assert_eq(shots.size(), 1, "Fire releases a waiting marble after the stop clears")
	launcher.call("_physics_process", 0.6)
	assert_eq(shots.size(), 1, "A marble still in the detector is not fired twice")
	await move_marble(body, Vector3(10, 5, 0))
	await move_marble(body, launcher.area.global_position)
	launcher.call("_physics_process", 0.6)
	assert_eq(shots.size(), 1, "A returning marble needs a new external trigger")
	launcher.receive("fire")
	launcher.call("_physics_process", 0.01)
	await get_tree().physics_frame
	launcher.call("_physics_process", 0.01)
	assert_eq(shots.size(), 2)

func test_build_arc_uses_world_direction_and_tracks_configuration() -> void:
	var original := launcher.build_trajectory()
	assert_true(original[0].is_equal_approx(launcher.area.global_position))
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
		await move_marble(body, launcher.area.global_position + Vector3(0.1, 0, 0.03))
		body.linear_velocity = incoming
		body.angular_velocity = Vector3(5, 2, -3)
		launcher.call("_physics_process", 0.6)
		assert_true(body.global_position.is_equal_approx(launcher.area.global_position), "Each shot starts at the same discharge point as the preview")
		assert_true(body.linear_velocity.is_equal_approx(launcher.launch_velocity()), "Every shot replaces the entire incoming velocity")
		assert_true(body.angular_velocity.is_zero_approx(), "Old rolling spin cannot change the shot")
		assert_false(body.freeze)
		assert_eq(body.collision_layer, 2, "Marble remains in normal rigid-body physics after launch")
		await move_marble(body, Vector3(10, 5, 0))

func test_handle_fires_rearms_and_freezes_on_pause() -> void:
	var handle: Node3D = launcher.arrow.get_node("Handle")
	assert_almost_eq(handle.rotation.x, 0.0, 0.001, "Ready launcher is cocked")
	var body := marble()
	await move_marble(body, launcher.area.global_position)
	launcher.call("_physics_process", 0.6)
	assert_eq(launcher.handle_animation.current_animation, "fire")
	launcher.call("_physics_process", 0.07)
	assert_almost_eq(handle.rotation.x, -0.9, 0.001, "Handle strikes forward with the shot")
	launcher.active = false
	launcher.call("_physics_process", 0.3)
	for frame in 3: await get_tree().physics_frame
	assert_almost_eq(handle.rotation.x, -0.9, 0.001, "Pause freezes the stroke")
	launcher.start_run()
	launcher.call("_physics_process", 0.23)
	assert_eq(launcher.handle_animation.current_animation, "rearm")
	assert_between(handle.rotation.x, -0.9, 0.0, "Handle returns during cooldown")
	launcher.call("_physics_process", 0.3)
	assert_almost_eq(handle.rotation.x, 0.0, 0.001)
	launcher.reset()
	assert_almost_eq(handle.rotation.x, 0.0, 0.001)

func test_one_shot_handle_stays_unarmed_until_reset() -> void:
	launcher.configure({"auto_rearm": false, "angle": 45.0})
	launcher.start_run()
	var body := marble()
	await move_marble(body, launcher.area.global_position)
	launcher.call("_physics_process", 0.6)
	launcher.call("_physics_process", 0.6)
	var handle: Node3D = launcher.arrow.get_node("Handle")
	assert_almost_eq(handle.rotation.x, -0.9, 0.001)
	launcher.reset()
	assert_almost_eq(handle.rotation.x, 0.0, 0.001)
	assert_almost_eq(launcher.arrow.rotation.x, PI / 4, 0.001, "Configured elevation sets the handle's armed direction")
	launcher.configure({"enabled": false})
	assert_almost_eq(handle.rotation.x, -0.9, 0.001, "Disabled launcher is unarmed")

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
	wall.global_position = launcher.area.global_position + Vector3(0.21, 0, -1)
	for frame in 2: await get_tree().physics_frame
	assert_eq(launcher.build_trajectory().size(), unobstructed.size(), "Selection-only collision does not stop a marble")
	wall.collision_layer = 1
	for frame in 2: await get_tree().physics_frame
	var blocked := launcher.build_trajectory()
	assert_gt(blocked.size(), 1)
	assert_lt(blocked.size(), unobstructed.size(), "End at the first obstacle, even if the centerline misses it")
	assert_gt(blocked[-1].z, wall.global_position.z, "Marble radius stops the center before the surface")
	assert_eq(launcher.build_trajectory([wall.get_rid()]).size(), unobstructed.size(), "Hidden moving originals can be excluded")
	wall.global_position = launcher.area.global_position
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
	assert_true(vertices[0].is_equal_approx(launcher.area.global_position))
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

extends "res://tests/support/game_test.gd"

func test_marble_camera() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(autoqfree(game))
	await wait_seconds(0.1)
	var showcase = game.get_node("%MainMenu").showcase
	var director = showcase.director
	var menu_world = showcase.world_manager
	var menu_host = menu_world.camera.get_node("PhantomCameraHost")
	var player_host = game.sandbox.camera.get_node("PhantomCameraHost")
	assert_true(menu_host.host_layers == 2 and player_host.host_layers == 1, "Menu and player hosts are isolated")
	var shots: Dictionary = {}
	var targets: Dictionary = {}
	var bounded_horizon: bool = true
	var transition_bank: float = 0.0
	var previous_shot: int = -1
	var chase_shots: int = 0
	# Camera scheduling and tweening use time, not a fixed render frame rate.
	var elapsed: float = 0.0
	while elapsed < 70.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		shots[director.shot] = true
		if director.shot == 2 and previous_shot != 2:
			chase_shots += 1
			assert_true(director.remaining >= 16.0 and director.remaining <= 20.0, "Showcase follows for 16–20 seconds per shot")
		previous_shot = director.shot
		var followed = menu_world.simulation_camera.chase.marble
		if is_instance_valid(followed): targets[followed.get_instance_id()] = true
		transition_bank = maxf(transition_bank, absf(menu_world.camera.global_basis.x.y))
		if director.shot == 2 and director.remaining < 4.0:
			bounded_horizon = bounded_horizon and absf(menu_world.camera.global_basis.x.y) < 0.01
	assert_true(shots.has(0) and shots.has(1) and shots.has(2) and shots.has(3), "Menu visits wide, detail, chase and return shots")
	assert_true(targets.size() >= 2, "Menu chooses different active marbles")
	assert_true(chase_shots >= 2, "Longer chase shots still cycle through different marbles")
	assert_true(bounded_horizon, "Settled menu chase horizon stays level")
	print("CAMERA maximum bank during addon shot transitions: %.3f" % transition_bank)
	assert_true(player_host.get_active_pcam() == game.sandbox.camera.free_view, "Menu priorities cannot switch player camera")
	showcase.set_active(false)
	assert_true(menu_world.simulation_camera.chase.marble == null, "Showcase reset clears chase target")

	game.qa_example("bucket-elevator-demo")
	await wait_seconds(2.0)
	var world = game.sandbox
	var control = world.simulation_camera
	var camera = world.camera
	var original = camera.free_view.global_transform
	var original_offset = camera.free_view.h_offset
	var original_state = [camera.focus_point,camera.yaw,camera.pitch,camera.distance]
	assert_true(world.simulation.start(), "Representative elevator simulation starts")
	await wait_seconds(1.0 / 3.0)
	assert_true(control.follow(world.simulation.marbles[0]), "Follow actual simulated marble")
	var first = control.chase.marble
	var slot = control.chase.slot
	assert_true(player_host.get_active_pcam() == control.chase.views[slot], "Host switches to chase by priority")
	assert_true(camera.chase_active, "Free camera input suspended")
	await wait_seconds(1.0)
	assert_true(camera.free_view.global_transform.is_equal_approx(original), "Free pose remains preserved")
	assert_true(control.chase.targets[slot].global_position.distance_to(first.global_position) < 1.5, "Tracking target stays close to moving marble")
	assert_true(absf(camera.global_basis.x.y) < 0.01, "Rolling marble cannot roll camera horizon")
	assert_true(camera.global_position.distance_to(first.global_position) < 5.0, "Camera follows closely")
	control.chase.stop()
	await wait_seconds(1.0)
	assert_true(camera.global_transform.is_equal_approx(original), "Exit restores original rendered pose")
	assert_true(is_equal_approx(camera.h_offset, original_offset), "Exit restores composition")
	assert_true(camera.focus_point.is_equal_approx(original_state[0]) and is_equal_approx(camera.yaw, original_state[1]) and is_equal_approx(camera.pitch, original_state[2]) and is_equal_approx(camera.distance, original_state[3]), "Exit preserves free orbit state")
	assert_true(not camera.chase_active and camera.enabled, "Normal camera input restored")
	control.follow(first)
	var previous_slot = control.chase.slot
	world.simulation.spawn_marble({"piece": world.build.pieces.filter(func(piece): return piece.definition.behavior == "start")[0], "index": 99})
	control.next_marble()
	assert_true(control.chase.marble != first and control.chase.slot != previous_slot, "Next marble uses another PCam for tweening")
	world.simulation.reset()
	assert_true(control.chase.marble == null and not camera.chase_active, "Reset during transition clears target and returns camera")
	await wait_seconds(1.0)
	assert_true(player_host.get_active_pcam() == camera.free_view, "Reset restores free view")
	control.next_marble()
	assert_true(control.chase.marble == null, "No-marble follow request is harmless")
	assert_true(world.simulation.start(), "Simulation restarts")
	control.next_marble()
	var removed = control.chase.marble
	world.simulation.marbles.erase(removed)
	removed.queue_free()
	await wait_process_frames(3)
	assert_true(control.chase.marble == null and not camera.chase_active, "Freed target falls back safely")
	world.simulation.reset()
	game.queue_free()
	await wait_process_frames(4)

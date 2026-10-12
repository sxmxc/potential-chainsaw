extends SceneTree

const Cleanup = preload("res://tests/cleanup.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func wait_frames(count: int) -> void:
	for frame in count: await process_frame

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await wait_frames(12)
	var showcase = game.get_node("%MainMenu").showcase
	var director = showcase.director
	var menu_world = showcase.world_manager
	var menu_host = menu_world.camera.get_node("PhantomCameraHost")
	var player_host = game.sandbox.camera.get_node("PhantomCameraHost")
	check(menu_host.host_layers == 2 and player_host.host_layers == 1, "Menu and player hosts are isolated")
	var shots: Dictionary = {}
	var targets: Dictionary = {}
	var bounded_horizon: bool = true
	var transition_bank: float = 0.0
	for frame in 120*42:
		await process_frame
		shots[director.shot] = true
		var followed = menu_world.simulation_camera.chase.marble
		if is_instance_valid(followed): targets[followed.get_instance_id()] = true
		transition_bank = maxf(transition_bank, absf(menu_world.camera.global_basis.x.y))
		if director.shot == 2 and director.remaining < 4.0:
			bounded_horizon = bounded_horizon and absf(menu_world.camera.global_basis.x.y) < 0.01
	check(shots.has(0) and shots.has(1) and shots.has(2) and shots.has(3), "Menu visits wide, detail, chase and return shots")
	check(targets.size() >= 2, "Menu chooses different active marbles")
	check(bounded_horizon, "Settled menu chase horizon stays level")
	print("CAMERA maximum bank during addon shot transitions: %.3f" % transition_bank)
	check(player_host.get_active_pcam() == game.sandbox.camera.free_view, "Menu priorities cannot switch player camera")
	showcase.set_active(false)
	check(menu_world.simulation_camera.chase.marble == null, "Showcase reset clears chase target")

	game.qa_example("bucket-elevator-demo")
	await wait_frames(120)
	var world = game.sandbox
	var control = world.simulation_camera
	var camera = world.camera
	var original = camera.free_view.global_transform
	var original_offset = camera.free_view.h_offset
	var original_state = [camera.focus_point,camera.yaw,camera.pitch,camera.distance]
	check(world.simulation.start(), "Representative elevator simulation starts")
	await wait_frames(40)
	check(control.follow(world.simulation.marbles[0]), "Follow actual simulated marble")
	var first = control.chase.marble
	var slot = control.chase.slot
	check(player_host.get_active_pcam() == control.chase.views[slot], "Host switches to chase by priority")
	check(camera.chase_active, "Free camera input suspended")
	await wait_frames(120)
	check(camera.free_view.global_transform.is_equal_approx(original), "Free pose remains preserved")
	check(control.chase.targets[slot].global_position.distance_to(first.global_position) < 1.5, "Tracking target stays close to moving marble")
	check(absf(camera.global_basis.x.y) < 0.01, "Rolling marble cannot roll camera horizon")
	check(camera.global_position.distance_to(first.global_position) < 5.0, "Camera follows closely")
	control.chase.stop()
	await wait_frames(120)
	check(camera.global_transform.is_equal_approx(original), "Exit restores original rendered pose")
	check(is_equal_approx(camera.h_offset, original_offset), "Exit restores composition")
	check(camera.focus_point.is_equal_approx(original_state[0]) and is_equal_approx(camera.yaw, original_state[1]) and is_equal_approx(camera.pitch, original_state[2]) and is_equal_approx(camera.distance, original_state[3]), "Exit preserves free orbit state")
	check(not camera.chase_active and camera.enabled, "Normal camera input restored")
	control.follow(first)
	var previous_slot = control.chase.slot
	world.simulation.spawn_marble({"piece": world.build.pieces.filter(func(piece): return piece.definition.behavior == "start")[0], "index": 99})
	control.next_marble()
	check(control.chase.marble != first and control.chase.slot != previous_slot, "Next marble uses another PCam for tweening")
	world.simulation.reset()
	check(control.chase.marble == null and not camera.chase_active, "Reset during transition clears target and returns camera")
	await wait_frames(120)
	check(player_host.get_active_pcam() == camera.free_view, "Reset restores free view")
	control.next_marble()
	check(control.chase.marble == null, "No-marble follow request is harmless")
	check(world.simulation.start(), "Simulation restarts")
	control.next_marble()
	var removed = control.chase.marble
	world.simulation.marbles.erase(removed)
	removed.queue_free()
	await wait_frames(3)
	check(control.chase.marble == null and not camera.chase_active, "Freed target falls back safely")
	world.simulation.reset()
	game.queue_free()
	await wait_frames(4)
	await Cleanup.stop_audio(self)
	print("MARBLE CAMERA RESULT: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

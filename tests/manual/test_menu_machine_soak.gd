extends GutTest
## Explicit opt-in physical soak; excluded from the default suite.
var events: Dictionary = {}
var travel: Dictionary = {}
var previous: Dictionary = {}
func test_machine_soak() -> void:
	var showcase = load("res://scenes/showcase.tscn").instantiate()
	add_child_autoqfree(showcase)
	await get_tree().process_frame
	var sim: SimulationManager = showcase.world_manager.simulation
	sim.wiring.output_observed.connect(func(port, _value, piece):
		var key: String = piece.instance_id + "/" + port
		events[key] = int(events.get(key, 0)) + 1)
	sim.state_changed.connect(func(state, message):
		print("STATE ", state, " ", message, " t=", sim.elapsed)
		if state == SimulationManager.State.FAILED:
			for body in sim.marbles: print("FAILPOS ", body.get_meta("marble_id"), " ", body.position, " v=", body.linear_velocity))
	showcase.set_active(true)
	for second in 600:
		for frame in 120: await get_tree().physics_frame
		if OS.get_environment("SHOWCASE_CAPTURE") == "1" and second == 4:
			showcase.director.set_active(false)
			for draw in 3: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			showcase.get_node("World").get_texture().get_image().save_png("res://.godot/showcase-wide.png")
		if sim.state == SimulationManager.State.FAILED: break
		if second >= 480:
			for body in sim.marbles:
				var id: String = body.get_meta("marble_id")
				if previous.has(id): travel[id] = float(travel.get(id, 0.0)) + body.position.distance_to(previous[id])
				previous[id] = body.position
		if second % 120 == 119:
			print("SOAK ", second+1, " state=", sim.state, " loops=", showcase.loops, " bodies=", sim.marbles.size(), " events=", JSON.stringify(events))
			for body in sim.marbles:
				print(body.get_meta("marble_id"), " ", body.position, " speed=", body.linear_velocity.length(), " carried=", body.carried)
	assert_eq(showcase.loops, 1, "No restart may hide a lost marble")
	assert_eq(sim.state, SimulationManager.State.RUNNING)
	assert_eq(sim.marbles.size(), 24, "All four finite supplies are released")
	for id in travel:
		assert_gt(float(travel[id]), 5.0, id + " keeps travelling during the final two minutes")
	for prefix in ["hero", "return"]:
		for suffix in ["-00/unloaded", "-bay-lift/unloaded", "-20/fired", "-bay-launcher/fired", "-05/entered", "-37/entered"]:
			var key: String = prefix + suffix
			assert_gt(int(events.get(key, 0)), 10, key + " repeats")
	print("TRAVEL ", JSON.stringify(travel))
	showcase.set_active(false)


extends "res://tests/support/scene_test.gd"

var game: Node
var build: BuildManager

func ticks(count: int) -> void:
	for i in count: await get_tree().physics_frame

func ball(at: Vector3, velocity: Vector3 = Vector3.ZERO) -> RigidBody3D:
	var body: RigidBody3D = load("res://scenes/marble.tscn").instantiate()
	add_child_autofree(body)
	body.position = at
	body.linear_velocity = velocity
	return body

func test_functional_mechanisms() -> void:
	var body: RigidBody3D
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	await get_tree().process_frame
	game.new_track()
	build = game.sandbox.build
	for id in ["fan-two", "fan-four", "fan-standing-two", "fan-standing-four"]:
		var piece = build.spawn(game.catalog.get_piece(id), Transform3D.IDENTITY, "", {"power": 0.2, "range": 2})
		var airflow = piece.behaviors[0]
		assert_true(airflow != null and not airflow is RotorComponent, id + " uses airflow without moving blade collision")
		body = ball(Vector3(0, 0.7, -0.8) if id.contains("standing") else Vector3(0, 0.8, 0))
		body.gravity_scale = 0
		airflow.active = true
		await ticks(20)
		assert_true(body.linear_velocity.dot(piece.basis * airflow.axis) > 0.05, id + " applies forward force in real physics")
		assert_true(piece.behaviors[0].receive("switch_direction") and airflow.active, id + " linked reversal keeps simulation active")
		assert_true(airflow.area.position.dot(airflow.axis) < 0, id + " linked reversal moves the force region")
		body.position = Vector3(0, 0.5, 0.8) if id.contains("standing") else Vector3(0, -0.5, 0)
		body.linear_velocity = Vector3.ZERO
		await ticks(20)
		assert_true(body.linear_velocity.dot(piece.basis * airflow.axis) < -0.02, id + " reverse force")
		body.position = airflow.axis * -4
		body.linear_velocity = Vector3.ZERO
		await ticks(20)
		assert_true(body.linear_velocity.length() < 0.01, id + " has no force outside its range")
		airflow.reset()
		assert_true(not airflow.active and airflow.angle == 0, id + " reset")
		body.queue_free()
		build.restore([])
		await get_tree().process_frame
	for id in ["fan-simple-two", "fan-simple-four"]:
		var piece = build.spawn(game.catalog.get_piece(id), Transform3D.IDENTITY)
		var paddle = piece.behaviors[0]
		assert_true(paddle is RotorComponent, id + " is exclusively physical")
		body = ball(Vector3(0.38, 0.4, 0.0))
		body.gravity_scale = 0
		paddle.active = true
		var peak_speed = 0.0
		for i in 120:
			await get_tree().physics_frame
			peak_speed = maxf(peak_speed, body.linear_velocity.length())
		assert_true(peak_speed > 0.03, id + " transfers momentum through blade collision")
		paddle.reset()
		assert_true(paddle.angle == 0, id + " reset")
		body.queue_free()
		build.restore([])
		await get_tree().process_frame
	var gate = build.spawn(game.catalog.get_piece("gate"), Transform3D.IDENTITY)
	build.spawn(game.catalog.get_piece("straight"), Transform3D(Basis.IDENTITY, Vector3(0, 0, 1)))
	body = ball(Vector3(0, 0.46, 0.8), Vector3(0, 0, -1))
	gate.behaviors[0].active = true
	await ticks(120)
	assert_true(body.position.z > 0.15, "Closed gate physically stops marble")
	assert_true(gate.behaviors[0].receive("open"), "Gate exposes Open action")
	await ticks(160)
	assert_true(body.position.z < -0.1, "Opening gate releases a stopped marble without an external impulse")
	gate.behaviors[0].reset()
	assert_true(not gate.behaviors[0].open, "Gate resets initial state")
	body.queue_free()
	await ticks(4)
	gate.apply_configuration({"open": true, "auto_close": 0.2})
	gate.behaviors[0].active = true
	await ticks(80)
	assert_true(not gate.behaviors[0].open and gate.behaviors[0].barrier.position.y < 0.7, "Gate automatically closes physically after delay")
	build.restore([])
	await get_tree().process_frame
	var launcher = build.spawn(game.catalog.get_piece("launcher"), Transform3D.IDENTITY)
	body = ball(Vector3(0, 0.46, 0.1), Vector3(0, 0, -0.8))
	launcher.behaviors[0].active = true
	await ticks(140)
	assert_true(launcher.behaviors[0].fired.size() == 1 and body.position.z < -0.7, "Launcher detects and fires a real impulse once")
	body.queue_free()
	build.restore([])
	await get_tree().process_frame
	launcher = build.spawn(game.catalog.get_piece("launcher"), Transform3D.IDENTITY, "", {"external": true})
	body = ball(Vector3(0, 0.46, 0.1), Vector3(0, 0, -0.8))
	launcher.behaviors[0].active = true
	await ticks(240)
	assert_true(launcher.behaviors[0].fired.is_empty() and body.position.z > -0.8, "External launcher physically retains loaded marble before trigger")
	launcher.behaviors[0].receive("fire")
	await ticks(100)
	assert_true(launcher.behaviors[0].fired.size() == 1 and body.position.z < -1, "External trigger launches the retained marble")
	launcher.behaviors[0].reset()
	assert_true(launcher.behaviors[0].fired.is_empty() and not launcher.behaviors[0].pending, "Launcher resets loading and firing state")
	body.queue_free()
	build.restore([])
	await get_tree().process_frame
	var sensor = build.spawn(game.catalog.get_piece("sensor"), Transform3D.IDENTITY, "sensor", {"links": [{"event": "entered", "target": "gate", "action": "open"}]})
	gate = build.spawn(game.catalog.get_piece("gate"), Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)), "gate")
	var events: Array = []
	sensor.behaviors[0].output_raised.connect(func(event, _body): events.append(event))
	var sim: SimulationManager = game.sandbox.simulation
	sim.puzzle = {"objectives": []}
	build.spawn(game.catalog.get_piece("sandbox-start"), Transform3D(Basis.IDENTITY, Vector3(4, 0, 0)), "release", {"start_delay": 60})
	assert_true(sim.start())
	body = ball(Vector3(0, 0.46, 0.4), Vector3(0, 0, -0.6))
	await ticks(80)
	assert_true(events.count("entered") == 1 and gate.behaviors[0].open, "Sensor crossing dispatches one persistent Open link")
	assert_true(sim.validate_links().is_empty(), "Link validation")
	sim.reset()
	body.queue_free()
	build.restore([])
	await get_tree().process_frame
	# Verify both exits follow physical guide geometry, including an undesired collector.
	for route_left in [false, true]:
		var diverter = build.spawn(game.catalog.get_piece("diverter"), Transform3D.IDENTITY, "fork", {"left": route_left})
		build.spawn(game.catalog.get_piece("straight"), Transform3D(Basis.IDENTITY, Vector3(0, 0, -1.5)))
		build.spawn(game.catalog.get_piece("straight"), Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-2, 0, 0.5)))
		build.spawn(game.catalog.get_piece("straight"), Transform3D(Basis(Vector3.UP, PI / 2), Vector3(2, 0, 0.5)))
		await ticks(4)
		body = ball(Vector3(0, 0.46, -1.7), Vector3(0, 0, 1.4))
		body.angular_velocity = Vector3(7, 0, 0)
		diverter.behaviors[0].active = true
		await ticks(500)
		assert_true(body.position.x < -0.6 if route_left else body.position.x > 0.6, "Diverter physically selects " + ("left" if route_left else "right") + " exit")
		diverter.behaviors[0].reset()
		assert_true(diverter.behaviors[0].left == route_left, "Diverter initial direction resets")
		body.queue_free()
		build.restore([])
		await get_tree().process_frame
	# Alternation switches only after the previous marble has physically cleared the fork.
	var alternating = build.spawn(game.catalog.get_piece("diverter"), Transform3D.IDENTITY, "", {"alternating": true})
	build.spawn(game.catalog.get_piece("straight"), Transform3D(Basis.IDENTITY, Vector3(0, 0, -1.5)))
	for x in [-2, 2]:
		build.spawn(game.catalog.get_piece("straight"), Transform3D(Basis(Vector3.UP, PI / 2), Vector3(x, 0, 0.5)))
	alternating.behaviors[0].active = true
	for expected_left in [false, true]:
		body = ball(Vector3(0, 0.46, -1.7), Vector3(0, 0, 1.4))
		body.angular_velocity = Vector3(7, 0, 0)
		await ticks(500)
		assert_true(body.position.x < -0.6 if expected_left else body.position.x > 0.6, "Alternating fork physically routes successive marbles")
		assert_true(alternating.behaviors[0].left != expected_left, "Alternating fork rearms after marble exits")
		body.queue_free()
		await ticks(4)

func test_link_dispatch_preserves_downstream_signal_chains() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	await get_tree().process_frame
	game.new_track()
	build = game.sandbox.build
	var sim: SimulationManager = game.sandbox.simulation
	build.spawn(game.catalog.get_piece("sandbox-start"), Transform3D.IDENTITY, "release", {"start_delay": 60})
	var sensor = build.spawn(game.catalog.get_piece("sensor"), Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)), "sensor", {"links": [{"event": "entered", "target": "gate", "action": "toggle"}]})
	var gate = build.spawn(game.catalog.get_piece("gate"), Transform3D(Basis.IDENTITY, Vector3(4, 0, 0)), "gate", {"links": [{"event": "opened", "target": "downstream", "action": "open"}]})
	var downstream = build.spawn(game.catalog.get_piece("gate"), Transform3D(Basis.IDENTITY, Vector3(6, 0, 0)), "downstream")
	sim.puzzle = {"objectives": [{"type": "activate", "target": "gate", "event": "opened"}]}
	assert_true(sim.validate_links().is_empty())
	assert_true(sim.start())
	sensor.behaviors[0].output_raised.emit("entered", null)
	assert_true(gate.behaviors[0].open and downstream.behaviors[0].open, "Linked action outputs reach downstream receivers")
	assert_true(sim.objectives.satisfied(0), "The linked gate's Opened event still counts toward objectives")
	sim.reset()
	sensor.behaviors[0].output_raised.emit("entered", null)
	assert_false(gate.behaviors[0].open, "Build mode ignores mechanism links")
	assert_false(sim.objectives.satisfied(0), "Reset clears activation progress")
	assert_true(sim.start())
	sim.toggle_pause()
	sensor.behaviors[0].output_raised.emit("entered", null)
	assert_false(gate.behaviors[0].open, "Paused simulation ignores mechanism links")
	assert_false(sim.objectives.satisfied(0), "Paused events do not count toward objectives")
	sim.toggle_pause()
	sensor.behaviors[0].output_raised.emit("entered", null)
	assert_true(gate.behaviors[0].open, "Restart handles the source event once, without duplicate toggles")
	sim.reset()
	for invalid_link in [
		{"event": "entered", "target": "missing", "action": "open"},
		{"event": "unknown", "target": "gate", "action": "open"},
		{"event": "entered", "target": "release", "action": "open"},
		{"event": "entered", "target": "gate", "action": "unknown"}
	]:
		sensor.configuration.links = [invalid_link]
		assert_false(sim.validate_links().is_empty(), "Reject invalid target, event or action")

func test_linked_motion_survives_pause_and_resets_to_configuration() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	await get_tree().process_frame
	game.new_track()
	build = game.sandbox.build
	var sim: SimulationManager = game.sandbox.simulation
	sim.puzzle = {"objectives": []}
	build.spawn(game.catalog.get_piece("sandbox-start"), Transform3D.IDENTITY, "release", {"start_delay": 60})
	var moving: Array[BuildingPiece] = []
	var links: Array = []
	for id in ["fan-simple-two", "bucket-elevator", "fan-two"]:
		var piece = build.spawn(game.catalog.get_piece(id), Transform3D(Basis.IDENTITY, Vector3(moving.size() * 5 + 5, 0, 0)), id, {"enabled": false})
		moving.append(piece)
		links.append({"event": "entered", "target": id, "action": "activate"})
	var sensor = build.spawn(game.catalog.get_piece("sensor"), Transform3D.IDENTITY, "sensor", {"links": links})
	var baseline = build.snapshot()
	assert_true(sim.start())
	await ticks(12)
	for piece in moving:
		var progress: float = piece.behaviors[0].get("phase" if piece.definition.behavior == "elevator" else "angle")
		assert_eq(progress, 0.0, "Initially disabled mechanism remains stationary")
	sensor.behaviors[0].output_raised.emit("entered", null)
	await ticks(12)
	for piece in moving:
		var progress: float = piece.behaviors[0].get("phase" if piece.definition.behavior == "elevator" else "angle")
		assert_gt(progress, 0.0, "Sensor link activates physical motion")
		assert_true(piece.behaviors[0].receive("deactivate"))
	sim.toggle_pause()
	await ticks(4)
	sim.toggle_pause()
	var stopped: Array[float] = []
	for piece in moving:
		stopped.append(piece.behaviors[0].get("phase" if piece.definition.behavior == "elevator" else "angle"))
	await ticks(12)
	for index in moving.size():
		var piece = moving[index]
		var progress: float = piece.behaviors[0].get("phase" if piece.definition.behavior == "elevator" else "angle")
		assert_eq(progress, stopped[index], "Resume preserves linked deactivation")
		assert_true(piece.behaviors[0].receive("toggle"))
	await ticks(12)
	for index in moving.size():
		var piece = moving[index]
		var progress: float = piece.behaviors[0].get("phase" if piece.definition.behavior == "elevator" else "angle")
		assert_gt(progress, stopped[index], "Toggle restarts motion")
	sim.reset()
	assert_eq(build.snapshot(), baseline, "Runtime actions do not alter saved construction")
	assert_true(sim.start())
	await ticks(12)
	for piece in moving:
		var progress: float = piece.behaviors[0].get("phase" if piece.definition.behavior == "elevator" else "angle")
		assert_eq(progress, 0.0, "New run restores configured disabled state")
	sim.reset()

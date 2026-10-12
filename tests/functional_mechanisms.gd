extends SceneTree

const Cleanup = preload("res://tests/cleanup.gd")

var failures: Array[String] = []
var checks: int = 0
var game: Node
var build: BuildManager

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func ticks(count: int) -> void:
	for i in count: await physics_frame

func ball(at: Vector3, velocity: Vector3 = Vector3.ZERO) -> RigidBody3D:
	var body: RigidBody3D = load("res://scenes/marble.tscn").instantiate()
	root.add_child(body)
	body.position = at
	body.linear_velocity = velocity
	return body

func run() -> void:
	var body: RigidBody3D
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.new_track()
	build = game.sandbox.build
	for id in ["fan-two", "fan-four", "fan-standing-two", "fan-standing-four"]:
		var piece = build.spawn(game.catalog.get_piece(id), Transform3D.IDENTITY, "", {"power": 0.2, "range": 2})
		var airflow = piece.mechanism_component
		check(airflow != null and piece.rotor_component == null, id + " uses airflow without moving blade collision")
		body = ball(Vector3(0, 0.7, -0.8) if id.contains("standing") else Vector3(0, 0.8, 0))
		body.gravity_scale = 0
		airflow.active = true
		await ticks(20)
		check(body.linear_velocity.dot(piece.basis * airflow.axis) > 0.05, id + " applies forward force in real physics")
		check(piece.perform_action("switch_direction") and airflow.active, id + " linked reversal keeps simulation active")
		check(airflow.area.position.dot(airflow.axis) < 0, id + " linked reversal moves the force region")
		body.position = Vector3(0, 0.5, 0.8) if id.contains("standing") else Vector3(0, -0.5, 0)
		body.linear_velocity = Vector3.ZERO
		await ticks(20)
		check(body.linear_velocity.dot(piece.basis * airflow.axis) < -0.02, id + " reverse force")
		body.position = airflow.axis * -4
		body.linear_velocity = Vector3.ZERO
		await ticks(20)
		check(body.linear_velocity.length() < 0.01, id + " has no force outside its range")
		airflow.reset()
		check(not airflow.active and airflow.angle == 0, id + " reset")
		body.queue_free()
		build.restore([])
		await process_frame
	for id in ["fan-simple-two", "fan-simple-four"]:
		var piece = build.spawn(game.catalog.get_piece(id), Transform3D.IDENTITY)
		var paddle = piece.rotor_component
		check(paddle != null and piece.mechanism_component == null, id + " is exclusively physical")
		body = ball(Vector3(0.38, 0.4, 0.0))
		body.gravity_scale = 0
		paddle.active = true
		var peak_speed = 0.0
		for i in 120:
			await physics_frame
			peak_speed = maxf(peak_speed, body.linear_velocity.length())
		check(peak_speed > 0.03, id + " transfers momentum through blade collision")
		paddle.reset()
		check(paddle.angle == 0, id + " reset")
		body.queue_free()
		build.restore([])
		await process_frame
	var gate = build.spawn(game.catalog.get_piece("gate"), Transform3D.IDENTITY)
	build.spawn(game.catalog.get_piece("straight"), Transform3D(Basis.IDENTITY, Vector3(0, 0, 1)))
	body = ball(Vector3(0, 0.46, 0.8), Vector3(0, 0, -1))
	gate.mechanism_component.active = true
	await ticks(120)
	check(body.position.z > 0.15, "Closed gate physically stops marble")
	check(gate.perform_action("open"), "Gate exposes Open action")
	await ticks(80)
	body.apply_central_impulse(Vector3(0, 0, -0.08))
	await ticks(80)
	check(body.position.z < -0.1, "Open gate allows marble through")
	gate.mechanism_component.reset()
	check(not gate.mechanism_component.open, "Gate resets initial state")
	body.queue_free()
	await ticks(4)
	gate.apply_configuration({"open": true, "auto_close": 0.2})
	gate.mechanism_component.active = true
	await ticks(80)
	check(not gate.mechanism_component.open and gate.mechanism_component.barrier.position.y < 0.7, "Gate automatically closes physically after delay")
	build.restore([])
	await process_frame
	var launcher = build.spawn(game.catalog.get_piece("launcher"), Transform3D.IDENTITY)
	body = ball(Vector3(0, 0.46, 0.1), Vector3(0, 0, -0.8))
	launcher.mechanism_component.active = true
	await ticks(140)
	check(launcher.mechanism_component.fired.size() == 1 and body.position.z < -0.7, "Launcher detects and fires a real impulse once")
	body.queue_free()
	build.restore([])
	await process_frame
	launcher = build.spawn(game.catalog.get_piece("launcher"), Transform3D.IDENTITY, "", {"external": true})
	body = ball(Vector3(0, 0.46, 0.1), Vector3(0, 0, -0.8))
	launcher.mechanism_component.active = true
	await ticks(240)
	check(launcher.mechanism_component.fired.is_empty() and body.position.z > -0.8, "External launcher physically retains loaded marble before trigger")
	launcher.perform_action("fire")
	await ticks(100)
	check(launcher.mechanism_component.fired.size() == 1 and body.position.z < -1, "External trigger launches the retained marble")
	launcher.mechanism_component.reset()
	check(launcher.mechanism_component.fired.is_empty() and not launcher.mechanism_component.pending, "Launcher resets loading and firing state")
	body.queue_free()
	build.restore([])
	await process_frame
	var sensor = build.spawn(game.catalog.get_piece("sensor"), Transform3D.IDENTITY, "sensor", {"links": [{"event": "entered", "target": "gate", "action": "open"}]})
	gate = build.spawn(game.catalog.get_piece("gate"), Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)), "gate")
	var events: Array = []
	sensor.mechanism_event.connect(func(event, _body): events.append(event))
	sensor.mechanism_component.active = true
	gate.mechanism_component.active = true
	var links = MechanismLinks.new()
	links.bind(build.pieces, func(): return true)
	body = ball(Vector3(0, 0.46, 0.4), Vector3(0, 0, -0.6))
	await ticks(80)
	check(events.count("entered") == 1 and gate.mechanism_component.open, "Sensor crossing dispatches one persistent Open link")
	check(MechanismLinks.validate(build.pieces).is_empty(), "Link validation")
	body.queue_free()
	build.restore([])
	await process_frame
	# Verify both exits follow physical guide geometry, including an undesired collector.
	for route_left in [false, true]:
		var diverter = build.spawn(game.catalog.get_piece("diverter"), Transform3D.IDENTITY, "fork", {"left": route_left})
		build.spawn(game.catalog.get_piece("straight"), Transform3D(Basis.IDENTITY, Vector3(0, 0, -1.5)))
		build.spawn(game.catalog.get_piece("straight"), Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-2, 0, 0.5)))
		build.spawn(game.catalog.get_piece("straight"), Transform3D(Basis(Vector3.UP, PI / 2), Vector3(2, 0, 0.5)))
		await ticks(4)
		body = ball(Vector3(0, 0.46, -1.7), Vector3(0, 0, 1.4))
		body.angular_velocity = Vector3(7, 0, 0)
		diverter.mechanism_component.active = true
		await ticks(500)
		check(body.position.x < -0.6 if route_left else body.position.x > 0.6, "Diverter physically selects " + ("left" if route_left else "right") + " exit")
		diverter.mechanism_component.reset()
		check(diverter.mechanism_component.left == route_left, "Diverter initial direction resets")
		body.queue_free()
		build.restore([])
		await process_frame
	# Alternation switches only after the previous marble has physically cleared the fork.
	var alternating = build.spawn(game.catalog.get_piece("diverter"), Transform3D.IDENTITY, "", {"alternating": true})
	build.spawn(game.catalog.get_piece("straight"), Transform3D(Basis.IDENTITY, Vector3(0, 0, -1.5)))
	for x in [-2, 2]:
		build.spawn(game.catalog.get_piece("straight"), Transform3D(Basis(Vector3.UP, PI / 2), Vector3(x, 0, 0.5)))
	alternating.mechanism_component.active = true
	for expected_left in [false, true]:
		body = ball(Vector3(0, 0.46, -1.7), Vector3(0, 0, 1.4))
		body.angular_velocity = Vector3(7, 0, 0)
		await ticks(500)
		check(body.position.x < -0.6 if expected_left else body.position.x > 0.6, "Alternating fork physically routes successive marbles")
		check(alternating.mechanism_component.left != expected_left, "Alternating fork rearms after marble exits")
		body.queue_free()
		await ticks(4)
	print("MECHANISM TESTS: ", checks, " checks, ", failures.size(), " failures")
	game.queue_free()
	await process_frame
	await Cleanup.stop_audio(self)
	quit(0 if failures.is_empty() else 1)

class_name SimulationManager
extends Node3D

const Capture = preload("res://scripts/mechanisms/marble_capture.gd")

enum State { BUILD, RUNNING, PAUSED, SUCCESS, FAILED }
signal state_changed(state: State, message: String)
signal arrived
signal objective_progress
var links = MechanismLinks.new()
var state: State = State.BUILD
var build: BuildManager
var marble: RigidBody3D
var marbles: Array[RigidBody3D] = []
var pending_releases: Array[Dictionary] = []
var paused_velocities: Dictionary = {}
var objectives = PuzzleObjectives.new()
var puzzle: Dictionary = {}
var construction_before: Array = []
var sensors: Array[Area3D] = []
var elapsed: float = 0
var paused_linear: Vector3
var paused_angular: Vector3

func start() -> bool:
	reset()
	var starts: Array[BuildingPiece] = []
	var finishes: Array[BuildingPiece] = []
	for piece in build.pieces:
		if piece.definition.behavior == "start": starts.append(piece)
		if piece.definition.behavior == "finish": finishes.append(piece)
	if starts.is_empty() or (puzzle.is_empty() and starts.size()!=1):
		state_changed.emit(State.BUILD,"Add one marble release to test the track.")
		return false
	if finishes.is_empty() and (puzzle.is_empty() or puzzle.get("objectives", []).any(func(objective): return objective.get("type", "deliver") == "deliver")):
		state_changed.emit(State.BUILD,"Add a finish catcher to test the track.")
		return false
	build.cancel()
	build.select(null)
	build.enabled = false
	build.refresh_grid()
	construction_before = build.snapshot()
	objectives.reset(puzzle.get("objectives", []))
	pending_releases.clear()
	for start_piece in starts:
		var quantity = clampi(int(start_piece.configuration.get("quantity", 1)), 1, 20)
		for index in quantity:
			pending_releases.append({"piece": start_piece, "time": float(start_piece.configuration.get("start_delay", 0)) + index * maxf(0.6, float(start_piece.configuration.get("interval", 1))), "index": index})
	for release in pending_releases.duplicate():
		if release.time <= 0:
			spawn_marble(release)
			pending_releases.erase(release)
	for finish in finishes:
		var area = Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		var shape = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = finish.definition.trigger_size
		shape.shape = box
		area.add_child(shape)
		add_child(area)
		area.transform = finish.transform*Transform3D(Basis.IDENTITY,finish.definition.trigger_position)
		area.body_entered.connect(_on_finish.bind(finish.instance_id))
		sensors.append(area)
	for piece in build.pieces:
		if piece.mechanism_component: piece.mechanism_component.active = true
		piece.mechanism_enabled = bool(piece.configuration.get("enabled",true))
		if piece.rotor_component: piece.rotor_component.active = piece.mechanism_enabled
		if piece.elevator_component: piece.elevator_component.active = piece.mechanism_enabled
	for piece in build.pieces:
		var callback = _mechanism_event.bind(piece)
		if not piece.mechanism_event.is_connected(callback): piece.mechanism_event.connect(callback)
	links.bind(build.pieces, func(): return state == State.RUNNING)
	elapsed = 0
	state = State.RUNNING
	state_changed.emit(state,"Testing")
	return true

func spawn_marble(release: Dictionary) -> void:
	var start_piece: BuildingPiece = release.piece
	var body: RigidBody3D = preload("res://scenes/marble.tscn").instantiate()
	add_child(body)
	body.position = start_piece.transform * start_piece.definition.spawn_position
	body.set_meta("source", start_piece.instance_id)
	body.set_meta("marble_id", start_piece.instance_id + ":" + str(release.index))
	body.reset_physics_interpolation()
	body.linear_velocity = start_piece.basis * start_piece.definition.spawn_direction * clampf(float(start_piece.configuration.get("release_speed", 1.4)), 0, 6)
	body.angular_velocity = Vector3(body.linear_velocity.z, 0, -body.linear_velocity.x) / 0.2
	marbles.append(body)
	if not is_instance_valid(marble): marble = body

func _mechanism_event(event: String, body: RigidBody3D, piece: BuildingPiece) -> void:
	if state != State.RUNNING: return
	objectives.activated(event, body, piece)
	objective_progress.emit()

func _physics_process(delta: float) -> void:
	if state != State.RUNNING: return
	elapsed += delta
	for release in pending_releases.duplicate():
		if elapsed >= release.time:
			spawn_marble(release)
			pending_releases.erase(release)
	for body in marbles:
		if body.get_meta("delivered", false): continue
		if body.position.y < -4 or abs(body.position.x) > build.snap.boundary + 4 or abs(body.position.z) > build.snap.boundary + 4:
			_end(State.FAILED, "Marble lost · return to building or roll again")
			return
	if not puzzle.is_empty() and objectives.satisfied(elapsed):
		_end(State.SUCCESS, "Puzzle complete")
		arrived.emit()
	elif elapsed > float(puzzle.get("time_limit", 90)):
		_end(State.FAILED, "Time ran out · return to building or roll again")

func _on_finish(body: Node3D, collector: String) -> void:
	if body not in marbles or state != State.RUNNING or body.get_meta("delivered", false): return
	body.set_meta("delivered", true)
	objectives.delivered(collector, body.get_meta("marble_id"), body.get_meta("source"))
	objective_progress.emit()
	body.set_deferred("freeze", true)
	body.set_deferred("collision_layer", 0)
	body.set_deferred("collision_mask", 0)
	body.hide()
	if puzzle.is_empty():
		_end(State.SUCCESS, "Finish reached in %.1f seconds" % elapsed)
		arrived.emit()

func _end(result: State, message: String) -> void:
	state = result
	for piece in build.pieces:
		if piece.mechanism_component: piece.mechanism_component.active = false
		if piece.rotor_component: piece.rotor_component.active = false
		if piece.elevator_component: piece.elevator_component.active = false
	state_changed.emit(state,message)

func toggle_pause() -> void:
	if state == State.RUNNING:
		paused_velocities.clear()
		for body in marbles:
			paused_velocities[body.get_instance_id()] = [body.linear_velocity, body.angular_velocity]
			if not Capture.is_carried(body): body.freeze = true
		state = State.PAUSED
	elif state == State.PAUSED:
		for body in marbles:
			if not Capture.is_carried(body) and not body.get_meta("delivered", false):
				body.freeze = false
				var velocities: Array = paused_velocities.get(body.get_instance_id(), [Vector3.ZERO, Vector3.ZERO])
				body.linear_velocity = velocities[0]
				body.angular_velocity = velocities[1]
		state = State.RUNNING
	else: return
	for piece in build.pieces:
		if piece.mechanism_component: piece.mechanism_component.active = state == State.RUNNING
		if piece.rotor_component: piece.rotor_component.active = state == State.RUNNING and piece.mechanism_enabled
		if piece.elevator_component: piece.elevator_component.active = state == State.RUNNING and piece.mechanism_enabled
	state_changed.emit(state, "Paused" if state == State.PAUSED else "Testing")

func reset() -> void:
	if build:
		for piece in build.pieces:
			if piece.elevator_component: piece.elevator_component.reset()
			if piece.mechanism_component: piece.mechanism_component.reset()
	for body in marbles:
		if is_instance_valid(body):
			remove_child(body)
			body.queue_free()
	marbles.clear()
	pending_releases.clear()
	marble = null
	for sensor in sensors:
		remove_child(sensor)
		sensor.queue_free()
	sensors.clear()
	if build:
		for piece in build.pieces:
			if piece.rotor_component: piece.rotor_component.reset()
		build.enabled = true
		build.refresh_grid()
	state = State.BUILD
	elapsed = 0
	objectives.reset(puzzle.get("objectives", []))
	state_changed.emit(state,"")



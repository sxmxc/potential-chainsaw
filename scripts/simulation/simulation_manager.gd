class_name SimulationManager
extends Node3D

const Capture = preload("res://scripts/mechanisms/marble_capture.gd")

enum State { BUILD, RUNNING, PAUSED, SUCCESS, FAILED }
signal state_changed(state: State, message: String)
signal arrived
var state: State = State.BUILD
var build: BuildManager
var marble: RigidBody3D
var sensors: Array[Area3D] = []
var elapsed: float = 0
var paused_linear: Vector3
var paused_angular: Vector3

func start() -> bool:
	reset()
	var starts: Array[TrackPiece] = []
	var finishes: Array[TrackPiece] = []
	for piece in build.pieces:
		if piece.definition.behavior == "start": starts.append(piece)
		if piece.definition.behavior == "finish": finishes.append(piece)
	if starts.size()!=1:
		state_changed.emit(State.BUILD,"Place exactly one Marble release from Start & finish")
		return false
	if finishes.is_empty():
		state_changed.emit(State.BUILD,"Place a Finish catcher from Start & finish")
		return false
	build.cancel()
	build.select(null)
	build.enabled = false
	build.refresh_grid()
	var start_piece = starts[0]
	marble = preload("res://scenes/marble.tscn").instantiate()
	add_child(marble)
	marble.position = start_piece.transform*start_piece.definition.spawn_position
	marble.reset_physics_interpolation()
	marble.linear_velocity = start_piece.basis*start_piece.definition.spawn_direction*float(start_piece.configuration.get("release_speed",1.4))
	marble.angular_velocity = Vector3(marble.linear_velocity.z,0,-marble.linear_velocity.x)/0.2
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
		area.body_entered.connect(_on_finish)
		sensors.append(area)
	for piece in build.pieces:
		if piece.rotor_component: piece.rotor_component.active = true
		if piece.elevator_component: piece.elevator_component.active = true
	elapsed = 0
	state = State.RUNNING
	state_changed.emit(state,"Marble released · test in progress")
	return true

func _physics_process(delta: float) -> void:
	if state != State.RUNNING or not is_instance_valid(marble): return
	elapsed += delta
	if marble.position.y < -4 or abs(marble.position.x)>build.snap.boundary+4 or abs(marble.position.z)>build.snap.boundary+4:
		_end(State.FAILED,"Off the track · reset to try again")
	elif elapsed > 90:
		_end(State.FAILED,"Time limit reached · inspect the route and release speed")

func _on_finish(body: Node3D) -> void:
	if body == marble and state == State.RUNNING:
		_end(State.SUCCESS,"Destination reached in %.1f seconds!" % elapsed)
		arrived.emit()

func _end(result: State, message: String) -> void:
	state = result
	for piece in build.pieces:
		if piece.rotor_component: piece.rotor_component.active = false
		if piece.elevator_component: piece.elevator_component.active = false
	state_changed.emit(state,message)

func toggle_pause() -> void:
	if state == State.RUNNING:
		paused_linear = marble.linear_velocity
		paused_angular = marble.angular_velocity
		if not Capture.is_carried(marble): marble.freeze = true
		state = State.PAUSED
	elif state == State.PAUSED:
		if not Capture.is_carried(marble):
			marble.freeze = false
			marble.linear_velocity = paused_linear
			marble.angular_velocity = paused_angular
		state = State.RUNNING
	else: return
	for piece in build.pieces:
		if piece.rotor_component: piece.rotor_component.active = state == State.RUNNING
		if piece.elevator_component: piece.elevator_component.active = state == State.RUNNING
	state_changed.emit(state,"Simulation paused" if state == State.PAUSED else "Simulation resumed")

func reset() -> void:
	if build:
		for piece in build.pieces:
			if piece.elevator_component: piece.elevator_component.reset()
	if is_instance_valid(marble):
		remove_child(marble)
		marble.queue_free()
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
	state_changed.emit(state,"Build mode · ready to construct")



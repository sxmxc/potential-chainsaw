class_name SimulationManager
extends Node3D

enum State { BUILD, RUNNING, PAUSED, SUCCESS, FAILED }
signal state_changed(state: State, message: String)
signal arrived
signal objective_progress
var connect_before_run: bool = false
@onready var wiring: PieceWiring = $PieceWiring
var state: State = State.BUILD
var build: BuildManager
var marble: Marble
var marbles: Array[Marble] = []
var paused_velocities: Dictionary = {}
var objectives = PuzzleObjectives.new()
var puzzle: Dictionary = {}
var construction_before: Array = []
var elapsed: float = 0

func _ready() -> void:
	wiring.output_observed.connect(_observe_output)
	wiring.failed.connect(func(message): _end(State.FAILED, message))

func start() -> bool:
	reset()
	var starts: Array[MarbleRelease] = []
	var finishes: Array[MarbleCollector] = []
	for piece in build.pieces:
		for behavior_node in piece.behaviors:
			if behavior_node is MarbleRelease: starts.append(behavior_node)
			if behavior_node is MarbleCollector: finishes.append(behavior_node)
	if starts.is_empty():
		state_changed.emit(State.BUILD,"Add a marble release to test the track.")
		return false
	if finishes.is_empty() and puzzle.get("objectives", []).any(func(objective): return objective.get("type", "deliver") == "deliver"):
		state_changed.emit(State.BUILD,"Add a finish catcher to test the track.")
		return false
	var link_errors := PieceWiring.validation_errors(build.pieces)
	if not link_errors.is_empty():
		state_changed.emit(State.BUILD, "\n".join(link_errors))
		return false
	connect_before_run = build.connect_mode
	build.cancel()
	build.select(null)
	construction_before = build.snapshot()
	objectives.reset(puzzle.get("objectives", []))
	elapsed = 0
	state = State.RUNNING
	state_changed.emit(state,"Testing")
	wiring.start(build.pieces)
	return state == State.RUNNING

func _track_marble(body: Marble, piece: BuildingPiece) -> void:
	body.reparent(self)
	body.reset_physics_interpolation()
	body.set_meta("source", piece.instance_id)
	body.set_meta("marble_id", piece.instance_id + ":" + str(body.release_ordinal))
	marbles.append(body)
	if not is_instance_valid(marble): marble = body

func _observe_output(port: String, value: Variant, piece: BuildingPiece) -> void:
	# Run bookkeeping precedes objectives and wired receivers on the same output.
	if value is Marble:
		match port:
			"released": _track_marble(value, piece)
			"collected": _on_finish(value, piece.instance_id)
	var body: RigidBody3D = value if value is RigidBody3D else null
	objectives.activated(port, body, piece)
	objective_progress.emit()

func _physics_process(delta: float) -> void:
	if state != State.RUNNING: return
	elapsed += delta
	for body in marbles:
		if body.get_meta("delivered", false): continue
		if body.position.y < -4 or abs(body.position.x) > build.snap.boundary + 4 or abs(body.position.z) > build.snap.boundary + 4:
			_end(State.FAILED, "Marble lost · return to building or roll again")
			return
	if not puzzle.is_empty() and objectives.satisfied(elapsed):
		_end(State.SUCCESS, "Puzzle complete")
		arrived.emit()
	elif not puzzle.is_empty() and elapsed > float(puzzle.get("time_limit", 90)):
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
	wiring.stop()
	state_changed.emit(state,message)

func toggle_pause() -> void:
	if state == State.RUNNING:
		paused_velocities.clear()
		for body in marbles:
			paused_velocities[body.get_instance_id()] = [body.linear_velocity, body.angular_velocity]
			if not body.carried: body.freeze = true
		state = State.PAUSED
	elif state == State.PAUSED:
		for body in marbles:
			if not body.carried and not body.get_meta("delivered", false):
				body.freeze = false
				var velocities: Array = paused_velocities.get(body.get_instance_id(), [Vector3.ZERO, Vector3.ZERO])
				body.linear_velocity = velocities[0]
				body.angular_velocity = velocities[1]
		state = State.RUNNING
	else: return
	wiring.set_paused(state == State.PAUSED)
	if state in [State.RUNNING, State.PAUSED]:
		state_changed.emit(state, "Paused" if state == State.PAUSED else "Testing")

func reset() -> void:
	var restore_connect := state != State.BUILD and connect_before_run
	connect_before_run = false
	state = State.BUILD
	if build: wiring.reset(build.pieces)
	for body in marbles:
		if is_instance_valid(body):
			remove_child(body)
			body.queue_free()
	marbles.clear()
	marble = null
	elapsed = 0
	objectives.reset(puzzle.get("objectives", []))
	state_changed.emit(state,"")
	if restore_connect: build.set_connect_mode(true)

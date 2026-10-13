class_name SimulationManager
extends Node3D

const Capture = preload("res://scripts/mechanisms/marble_capture.gd")

enum State { BUILD, RUNNING, PAUSED, SUCCESS, FAILED }
signal state_changed(state: State, message: String)
signal arrived
signal objective_progress
var connect_before_run: bool = false
@export_range(1, 65536, 1) var signal_delivery_limit: int = 16384
var signal_queue: Array[Dictionary] = []
var draining_signals: bool = false
var state: State = State.BUILD
var build: BuildManager
var marble: RigidBody3D
var marbles: Array[RigidBody3D] = []
var paused_velocities: Dictionary = {}
var objectives = PuzzleObjectives.new()
var puzzle: Dictionary = {}
var construction_before: Array = []
var elapsed: float = 0

func start() -> bool:
	reset()
	var starts: Array[MarbleRelease] = []
	var finishes: Array[MarbleCollector] = []
	for piece in build.pieces:
		for behavior_node in piece.behaviors:
			if behavior_node is MarbleRelease: starts.append(behavior_node)
			if behavior_node is MarbleCollector: finishes.append(behavior_node)
	if starts.is_empty() or (puzzle.is_empty() and starts.size()!=1):
		state_changed.emit(State.BUILD,"Add one marble release to test the track.")
		return false
	if finishes.is_empty() and (puzzle.is_empty() or puzzle.get("objectives", []).any(func(objective): return objective.get("type", "deliver") == "deliver")):
		state_changed.emit(State.BUILD,"Add a finish catcher to test the track.")
		return false
	var link_errors := validate_links()
	if not link_errors.is_empty():
		state_changed.emit(State.BUILD, "\n".join(link_errors))
		return false
	connect_before_run = build.connect_mode
	build.cancel()
	build.select(null)
	build.enabled = false
	build.refresh_grid()
	construction_before = build.snapshot()
	objectives.reset(puzzle.get("objectives", []))
	for piece in build.pieces:
		for behavior_node in piece.behaviors:
			var callback := _behavior_output.bind(piece)
			if not behavior_node.output_raised.is_connected(callback): behavior_node.output_raised.connect(callback)
			if behavior_node is MarbleRelease:
				var released := _track_marble.bind(piece)
				if not behavior_node.marble_spawned.is_connected(released): behavior_node.marble_spawned.connect(released)
			if behavior_node is MarbleCollector:
				var collected := _on_finish.bind(piece.instance_id)
				if not behavior_node.marble_collected.is_connected(collected): behavior_node.marble_collected.connect(collected)
	elapsed = 0
	state = State.RUNNING
	# Queue initial emissions until every receiver has entered its run lifecycle.
	draining_signals = true
	for piece in build.pieces:
		for behavior_node in piece.behaviors: behavior_node.start_run()
	# Seed persistent wires from configured initial output states after every reset.
	for piece in build.pieces:
		for behavior_node in piece.behaviors:
			for port in behavior_node.state_outputs:
				_behavior_output(port, behavior_node.output_values[port], piece)
	draining_signals = false
	_flush_signals()
	if state != State.RUNNING: return false
	state_changed.emit(state,"Testing")
	return true

func _track_marble(body: RigidBody3D, ordinal: int, piece: BuildingPiece) -> void:
	body.reparent(self)
	body.reset_physics_interpolation()
	body.set_meta("source", piece.instance_id)
	body.set_meta("marble_id", piece.instance_id + ":" + str(ordinal))
	marbles.append(body)
	if not is_instance_valid(marble): marble = body

func _behavior_output(port: String, value: Variant, piece: BuildingPiece) -> void:
	if state != State.RUNNING: return
	var body: RigidBody3D = value if value is RigidBody3D else null
	objectives.activated(port, body, piece)
	objective_progress.emit()
	signal_queue.append({"source": piece, "port": port, "value": value})
	_flush_signals()

func _flush_signals() -> void:
	if draining_signals: return
	draining_signals = true
	var deliveries := 0
	# FIFO preserves source emissions and saved link order. An action's outputs
	# join the queue instead of recursing or being discarded.
	while not signal_queue.is_empty() and state == State.RUNNING:
		var emission: Dictionary = signal_queue.pop_front()
		for link in emission.source.configuration.get("links", []):
			if link.get("event") != emission.port: continue
			var target := build.find_piece(link.get("target", ""))
			if not target or not target.input_ports.has(link.get("action", "")): continue
			deliveries += 1
			if deliveries > signal_delivery_limit:
				signal_queue.clear()
				_end(State.FAILED, "Signal loop did not settle. Check the wiring.")
				break
			target.input_ports[link.action].receive(link.action, emission.value)
	draining_signals = false

func validate_links() -> Array[String]:
	var errors: Array[String] = []
	for source in build.pieces:
		var inputs_seen: Dictionary = {}
		var outputs_seen: Dictionary = {}
		var fields_seen: Dictionary = {}
		for behavior_node in source.behaviors:
			for port in behavior_node.inputs:
				if inputs_seen.has(port): errors.append("Duplicate input on " + source.instance_id + ": " + port)
				inputs_seen[port] = true
			for field in behavior_node.configuration_fields:
				if field.key.is_empty(): errors.append("Unnamed configuration field on " + source.instance_id)
				if fields_seen.has(field.key): errors.append("Duplicate configuration field on " + source.instance_id + ": " + String(field.key))
				fields_seen[field.key] = true
				if field.kind == PieceSetting.Kind.NUMBER and (field.minimum > field.maximum or field.step <= 0 or not is_finite(field.default_number) or field.default_number < field.minimum or field.default_number > field.maximum):
					errors.append("Invalid configuration range on " + source.instance_id + ": " + String(field.key))
			for port in behavior_node.output_ports():
				if outputs_seen.has(port): errors.append("Duplicate output on " + source.instance_id + ": " + port)
				outputs_seen[port] = true
			for port in behavior_node.state_inputs:
				if not behavior_node.inputs.has(port): errors.append("State input has no receiver on " + source.instance_id + ": " + port)
		for link in source.configuration.get("links", []):
			var target := build.find_piece(link.get("target", ""))
			if not target or not source.output_ports.has(link.get("event", "")) or not target.input_ports.has(link.get("action", "")):
				errors.append("Invalid mechanism link on " + source.instance_id)
			elif source.output_ports[link.event].state_outputs.has(link.event) != target.input_ports[link.action].state_inputs.has(link.action):
				errors.append("Pulse and state ports cannot be connected on " + source.instance_id)
	return errors

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
		for behavior_node in piece.behaviors: behavior_node.active = false
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
		for behavior_node in piece.behaviors: behavior_node.active = state == State.RUNNING
	if state == State.RUNNING:
		for piece in build.pieces:
			for behavior_node in piece.behaviors:
				for port in behavior_node.state_outputs: _behavior_output(port, behavior_node.output_values[port], piece)
	if state in [State.RUNNING, State.PAUSED]:
		state_changed.emit(state, "Paused" if state == State.PAUSED else "Testing")

func reset() -> void:
	var restore_connect := state != State.BUILD and connect_before_run
	connect_before_run = false
	state = State.BUILD
	signal_queue.clear()
	if build:
		for piece in build.pieces:
			for behavior_node in piece.behaviors: behavior_node.reset()
	for body in marbles:
		if is_instance_valid(body):
			remove_child(body)
			body.queue_free()
	marbles.clear()
	marble = null
	if build:
		build.enabled = true
		build.refresh_grid()
	state = State.BUILD
	if restore_connect: build.set_connect_mode(true)
	elapsed = 0
	objectives.reset(puzzle.get("objectives", []))
	state_changed.emit(state,"")



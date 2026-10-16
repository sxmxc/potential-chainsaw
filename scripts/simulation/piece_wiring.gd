class_name PieceWiring
extends Node
## Owns a run's resolved signal connections and behavior lifecycle.
signal output_observed(port: String, value: Variant, piece: BuildingPiece)
signal failed(message: String)

@export_range(1, 65536, 1) var delivery_limit: int = 16384
var _connections: Dictionary[PieceBehavior, Callable] = {}
var _queue: Array[Dictionary] = []
var _running: bool = false
var _draining: bool = false

static func validation_errors(pieces: Array[BuildingPiece]) -> Array[String]:
	var errors: Array[String] = []
	var by_id: Dictionary = {}
	for piece in pieces: by_id[piece.instance_id] = piece
	for source in pieces:
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
			var target: BuildingPiece = by_id.get(link.get("target", ""))
			if not target or not source.output_ports.has(link.get("event", "")) or not target.input_ports.has(link.get("action", "")):
				errors.append("Invalid mechanism link on " + source.instance_id)
			elif link.action not in source.compatible_actions(target, link.event):
				errors.append("Pulse and state ports cannot be connected on " + source.instance_id)
	return errors

func start(pieces: Array[BuildingPiece]) -> void:
	# Resolve saved UIDs and ports once, while construction is fixed for the run.
	var by_id: Dictionary = {}
	for piece in pieces: by_id[piece.instance_id] = piece
	for piece in pieces:
		var routes: Dictionary = {}
		for link in piece.configuration.get("links", []):
			var target: BuildingPiece = by_id[link.target]
			if not routes.has(link.event): routes[link.event] = []
			routes[link.event].append({"behavior": target.input_ports[link.action], "port": link.action})
		for behavior in piece.behaviors:
			var callback := _output.bind(piece, routes)
			behavior.output_raised.connect(callback)
			_connections[behavior] = callback
	_running = true
	# Every receiver must enter its run lifecycle before initial outputs settle.
	_draining = true
	for behavior in _connections:
		behavior.initializing_signals = true
		behavior.start_run()
	_seed_states()
	_draining = false
	_flush()
	if not _running: return
	# Gates expose initial rising events only after persistent states settle.
	_draining = true
	for behavior in _connections: behavior.signals_ready()
	_draining = false
	_flush()

func _output(port: String, value: Variant, piece: BuildingPiece, routes: Dictionary) -> void:
	if not _running: return
	output_observed.emit(port, value, piece)
	_queue.append({"receivers": routes.get(port, []), "value": value})
	_flush()

func _seed_states() -> void:
	for behavior in _connections:
		for port in behavior.state_outputs:
			_connections[behavior].call(port, behavior.output_values[port])

func _flush() -> void:
	if _draining: return
	_draining = true
	var deliveries := 0
	# Queue emissions, not individual actions: all links from one emission must
	# precede any outputs raised by its receivers, in saved-link order.
	while not _queue.is_empty() and _running:
		var emission: Dictionary = _queue.pop_front()
		for receiver: Dictionary in emission.receivers:
			deliveries += 1
			if deliveries > delivery_limit:
				stop()
				failed.emit("Signal loop did not settle. Check the wiring.")
				break
			receiver.behavior.receive(receiver.port, emission.value)
	_draining = false

func set_paused(paused: bool) -> void:
	_running = not paused
	for behavior in _connections: behavior.active = _running
	if _running: _seed_states()

func stop() -> void:
	_running = false
	_queue.clear()
	for behavior in _connections:
		if is_instance_valid(behavior): behavior.active = false

func reset(pieces: Array[BuildingPiece]) -> void:
	stop()
	for behavior in _connections:
		if is_instance_valid(behavior): behavior.output_raised.disconnect(_connections[behavior])
	_connections.clear()
	for piece in pieces:
		for behavior in piece.behaviors: behavior.reset()

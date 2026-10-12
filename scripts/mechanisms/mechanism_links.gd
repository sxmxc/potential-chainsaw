class_name MechanismLinks
extends RefCounted

var pieces: Dictionary = {}
var running: Callable
var dispatching: bool = false

func bind(construction: Array, is_running: Callable) -> void:
	pieces.clear()
	running = is_running
	for piece in construction: pieces[piece.instance_id] = piece
	for piece in construction:
		var callback = dispatch.bind(piece)
		if not piece.mechanism_event.is_connected(callback): piece.mechanism_event.connect(callback)

func dispatch(event: String, _marble: RigidBody3D, source: TrackPiece) -> void:
	# Reject synchronous cycles; separate crossings may still use the same link.
	if dispatching or not running.call(): return
	dispatching = true
	for link in source.configuration.get("links", []):
		if link.get("event") != event: continue
		var target = pieces.get(link.get("target", "")) as TrackPiece
		if is_instance_valid(target) and link.get("action", "") in target.supported_actions():
			target.perform_action(link.action)
	dispatching = false

static func validate(construction: Array) -> Array[String]:
	var errors: Array[String] = []
	var by_id: Dictionary = {}
	for piece in construction: by_id[piece.instance_id] = piece
	for source in construction:
		for link in source.configuration.get("links", []):
			var target = by_id.get(link.get("target", "")) as TrackPiece
			if not target or link.get("action") not in target.supported_actions() or link.get("event") not in source.supported_events(): errors.append("Invalid mechanism link on " + source.instance_id)
	return errors

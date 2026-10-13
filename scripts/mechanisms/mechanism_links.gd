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
		if not piece.mechanism_component: continue
		var callback = dispatch.bind(piece)
		if not piece.mechanism_component.event_raised.is_connected(callback): piece.mechanism_component.event_raised.connect(callback)

func dispatch(event: String, _marble: RigidBody3D, source: BuildingPiece) -> void:
	# Reject synchronous cycles; separate crossings may still use the same link.
	if dispatching or not running.call(): return
	dispatching = true
	for link in source.configuration.get("links", []):
		if link.get("event") != event: continue
		var target = pieces.get(link.get("target", "")) as BuildingPiece
		if is_instance_valid(target) and target.mechanism_component:
			target.mechanism_component.perform(link.get("action", ""))
	dispatching = false

static func validate(construction: Array) -> Array[String]:
	var errors: Array[String] = []
	var by_id: Dictionary = {}
	for piece in construction: by_id[piece.instance_id] = piece
	for source in construction:
		for link in source.configuration.get("links", []):
			var target = by_id.get(link.get("target", "")) as BuildingPiece
			if not target or not target.mechanism_component or not source.mechanism_component or not target.mechanism_component.actions.has(link.get("action")) or link.get("event") not in source.mechanism_component.events: errors.append("Invalid mechanism link on " + source.instance_id)
	return errors

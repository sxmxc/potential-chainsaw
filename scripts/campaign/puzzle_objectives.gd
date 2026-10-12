class_name PuzzleObjectives
extends RefCounted

var objectives: Array = []
var deliveries: Dictionary = {}
var activations: Dictionary = {}

func reset(data: Array) -> void:
	objectives = data.duplicate(true)
	deliveries.clear()
	activations.clear()

func delivered(collector: String, marble_id: String, source: String) -> void:
	deliveries[marble_id] = {"collector": collector, "source": source}

func activated(event: String, _body: RigidBody3D, piece: TrackPiece) -> void:
	activations[piece.instance_id + ":" + event] = true

func satisfied(elapsed: float) -> bool:
	if objectives.is_empty(): return false
	for objective in objectives:
		if float(objective.get("time_limit", 0)) > 0 and elapsed > float(objective.time_limit): return false
		if objective.get("type", "deliver") == "activate":
			if not activations.has(objective.target + ":" + str(objective.get("event", "activated"))): return false
		else:
			var count = 0
			for delivery in deliveries.values():
				if delivery.collector == objective.target and (objective.get("source", "").is_empty() or delivery.source == objective.source): count += 1
			if count < int(objective.get("count", 1)): return false
	return true

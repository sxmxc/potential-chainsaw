class_name PuzzleObjectives
extends RefCounted

signal changed

var _objectives: Array = []
var _deliveries: Dictionary = {}
var _activations: Dictionary = {}

func reset(data: Array) -> void:
	_objectives = data.duplicate(true)
	_deliveries.clear()
	_activations.clear()
	changed.emit()

func delivered(collector: String, marble_id: String, source: String) -> void:
	_deliveries[marble_id] = {"collector": collector, "source": source}
	changed.emit()

func activated(target: String, event: String) -> void:
	_activations[target + ":" + event] = true
	changed.emit()

func delivery_count(collector: String, source: String = "") -> int:
	var count := 0
	for delivery: Dictionary in _deliveries.values():
		if delivery.collector == collector and (source.is_empty() or delivery.source == source):
			count += 1
	return count

func activation_seen(target: String, event: String) -> bool:
	return _activations.has(target + ":" + event)

# Guidance advances on first activity, not completion of an entire goal.
func has_activity(target: String) -> bool:
	if delivery_count(target) > 0: return true
	for key: String in _activations:
		if key.begins_with(target + ":"): return true
	return false

func progress(objective: Dictionary) -> int:
	if objective.get("type", "deliver") == "activate":
		return 1 if activation_seen(objective.target, objective.get("event", "activated")) else 0
	return delivery_count(objective.target, objective.get("source", ""))

func satisfied(elapsed: float) -> bool:
	if _objectives.is_empty(): return false
	for objective: Dictionary in _objectives:
		if float(objective.get("time_limit", 0)) > 0 and elapsed > float(objective.time_limit): return false
		var required := 1 if objective.get("type", "deliver") == "activate" else int(objective.get("count", 1))
		if progress(objective) < required: return false
	return true

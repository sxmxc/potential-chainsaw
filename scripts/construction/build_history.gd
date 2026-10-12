class_name BuildHistory
extends RefCounted

signal changed
var commands: Array[Dictionary] = []
var cursor: int = 0

func record(before: Array, after: Array, label: String) -> void:
	commands.resize(cursor)
	commands.append({"before": before.duplicate(true), "after": after.duplicate(true), "label": label})
	cursor += 1
	changed.emit()

func undo() -> Array:
	if cursor == 0: return []
	cursor -= 1
	changed.emit()
	return commands[cursor].before.duplicate(true)

func redo() -> Array:
	if cursor >= commands.size(): return []
	var result: Array = commands[cursor].after.duplicate(true)
	cursor += 1
	changed.emit()
	return result

func clear() -> void:
	commands.clear()
	cursor = 0
	changed.emit()

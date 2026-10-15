class_name WorldGuidance
extends Node3D
## One presentation owner for authored steps, previews, and objective location.
signal changed

const MARKER = preload("res://scenes/guidance/marker.tscn")
const KINDS = ["attention", "target", "direction", "interaction", "problem"]
const CONDITIONS = ["selected", "connected", "run_started", "objective", "dismissed"]
var session: ConstructionSession
var step_index: int = 0
var requested: bool = false
var instruction: String = ""
var marker: Node3D
var temporary: Dictionary = {}
var timer: Timer
var objective_index: int = 0

func _ready() -> void:
	marker = MARKER.instantiate()
	add_child(marker)
	marker.clear()
	timer = Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(func(): temporary.clear(); refresh())

func configure(value: ConstructionSession) -> void:
	session = value
	session.context_changed.connect(restart)
	session.changed.connect(refresh)
	session.world.build.changed.connect(refresh)
	session.world.build.selection_changed.connect(func(_piece): refresh())
	session.world.build.options_changed.connect(refresh)
	session.world.simulation.objective_progress.connect(refresh)
	session.world.simulation.state_changed.connect(func(state, _message):
		if state == SimulationManager.State.BUILD: restart()
		else: refresh())

func restart() -> void:
	marker.clear()
	step_index = 0
	requested = false
	objective_index = 0
	temporary.clear()
	timer.stop()
	refresh()

func request() -> void:
	temporary.clear()
	timer.stop()
	var count: int = session.puzzle.get("guidance", []).size()
	if count == 0: count = session.puzzle.get("hints", []).size()
	if step_index >= count: step_index = 0
	requested = true
	refresh()

func dismiss() -> void:
	if not temporary.is_empty():
		temporary.clear()
		timer.stop()
	else:
		step_index += 1
	refresh()

func has_hints() -> bool:
	return session != null and (not session.puzzle.get("guidance", []).is_empty() or session.puzzle.get("hints", []).any(func(text): return not str(text).strip_edges().is_empty()))

func preview(step: Dictionary) -> void:
	temporary = step.duplicate(true)
	timer.start(5.0)
	refresh()

func locate_objectives() -> void:
	if not session.is_playing: return
	var goals: Array = session.puzzle.get("objectives", [])
	if goals.is_empty(): return
	preview({"kind": "target", "target": goals[objective_index % goals.size()].target, "connector": -1})
	objective_index += 1

func active_step() -> Dictionary:
	if not temporary.is_empty(): return temporary
	if not session or not session.is_playing: return {}
	var automatic: bool = PuzzleStore.is_official(session.puzzle) and session.puzzle.get("campaign", {}).get("chapter", {}).get("introduction", false)
	if not automatic and not requested: return {}
	var steps: Array = session.puzzle.get("guidance", [])
	# Read older puzzle formats through this owner without rewriting their saved data.
	if steps.is_empty():
		var hints: Array = session.puzzle.get("hints", [])
		if session.world.simulation.state != SimulationManager.State.BUILD: return {}
		while step_index < hints.size():
			if not str(hints[step_index]).strip_edges().is_empty(): return {"text": str(hints[step_index])}
			step_index += 1
		return {}
	while step_index < steps.size():
		var step: Dictionary = steps[step_index]
		if not completed(step):
			var running := session.world.simulation.state != SimulationManager.State.BUILD
			if step.get("appear", "build") == "build" and running: return {}
			if step.get("appear", "build") == "run" and not running: return {}
			return step
		step_index += 1
	return {}

func completed(step: Dictionary) -> bool:
	var build := session.world.build
	var piece := build.find_piece(step.get("target", ""))
	match step.get("complete", "dismissed"):
		"selected": return piece != null and piece in build.selection
		"connected":
			var index := int(step.get("connector", -1))
			if not piece or index < 0 or index >= piece.definition.connectors.size(): return false
			var key := piece.instance_id + ":" + str(index)
			return not build.snap.exposed(build.pieces).any(func(port): return port.key == key)
		"run_started": return session.world.simulation.state != SimulationManager.State.BUILD
		"objective":
			var objectives: PuzzleObjectives = session.world.simulation.objectives
			for delivery in objectives.deliveries.values():
				if delivery.collector == step.get("target", ""): return true
			for key: String in objectives.activations:
				if key.begins_with(str(step.get("target", "")) + ":"): return true
	return false

func resolve(step: Dictionary) -> Dictionary:
	if step.get("target", "").is_empty():
		var point: Array = step.get("position", [0, 0, 0])
		return {"point": session.world.global_transform * Vector3(point[0], point[1], point[2]), "direction": -session.world.global_basis.z}
	var piece := session.world.build.find_piece(step.target)
	if not piece: return {}
	var index := int(step.get("connector", -1))
	if index >= 0:
		if index >= piece.definition.connectors.size(): return {}
		var connector := piece.definition.connectors[index]
		return {"point": piece.global_transform * connector.position, "direction": piece.global_basis * connector.outward}
	return {"point": piece.global_transform * (piece.definition.bounds.get_center() + Vector3.UP * piece.definition.bounds.size.y * 0.5), "direction": -piece.global_basis.z}

func refresh() -> void:
	if not marker or not session: return
	var show_marker := false
	instruction = ""
	var step := active_step()
	if not step.is_empty():
		if not step.has("kind"):
			instruction = step.get("text", "")
		else:
			var target := resolve(step)
			if not target.is_empty():
				instruction = step.get("text", "")
				# Placement and connector handles already show the cursor's exact target.
				show_marker = session.world.build.chosen == null
				if show_marker: marker.present(step.get("kind", "attention"), target.point, target.direction)
	if not show_marker: marker.clear()
	changed.emit()

static func shape_errors(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var steps: Variant = data.get("guidance", [])
	if not steps is Array or steps.size() > 32: return ["Guidance must contain at most 32 steps"]
	if data.has("guidance") and int(data.get("version", 0)) < 3: errors.append("Guidance requires puzzle format 3")
	for step in steps:
		if not step is Dictionary: errors.append("Invalid guidance step"); continue
		for key in step:
			if key not in ["kind", "target", "connector", "position", "text", "appear", "complete"]: errors.append("Unsupported guidance field: " + str(key))
		if step.get("kind") not in KINDS or step.get("complete") not in CONDITIONS or step.get("appear") not in ["build", "run", "always"]: errors.append("Invalid guidance condition or indicator")
		if not step.get("text", "") is String or str(step.get("text", "")).length() > 200: errors.append("Guidance text must be at most 200 characters")
		if not step.get("target", "") is String: errors.append("Invalid guidance target")
		if not PuzzleRules._is_number(step.get("connector", -1)) or float(step.get("connector", -1)) != int(step.get("connector", -1)) or int(step.get("connector", -1)) < -1: errors.append("Invalid guidance connector")
		if not PuzzleRules._numeric_array(step.get("position", [0, 0, 0]), 3): errors.append("Invalid guidance point")
	return errors

static func definition_errors(data: Dictionary, catalog: PieceCatalog) -> Array[String]:
	var errors: Array[String] = []
	var records: Dictionary = {}
	for item in data.get("pieces", []): records[item.uid] = item
	for step in data.get("guidance", []):
		var uid: String = step.get("target", "")
		if uid.is_empty():
			if step.complete in ["selected", "connected", "objective"] or int(step.get("connector", -1)) >= 0: errors.append("Guidance condition needs a piece target")
			continue
		if not records.has(uid): errors.append("Guidance target is missing: " + uid); continue
		var definition := catalog.get_piece(records[uid].piece)
		var index := int(step.get("connector", -1))
		if not definition or index >= definition.connectors.size(): errors.append("Guidance connector is missing: " + uid)
		if step.complete == "connected" and index < 0: errors.append("Choose a connector for connection guidance")
		if step.complete == "objective" and not data.get("objectives", []).any(func(goal): return goal.get("target") == uid): errors.append("Guidance target has no objective: " + uid)
	return errors

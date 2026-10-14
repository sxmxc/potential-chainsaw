class_name PuzzleSession
extends Node

signal mode_changed
var game: Node
var store: PuzzleStore
var mode: String = "sandbox"
var puzzle: Dictionary = {}
var authored: Dictionary = {}
var test_success: bool = false
var successful_solution: Array = []
var successful_time: float = 0
var successful_fingerprint: String = ""
var testing_fingerprint: String = ""
var opening_fingerprint: String = ""
var opening_revision: int = 1
var environment_node: Node3D

func configure(owner_game: Node) -> void:
	game = owner_game
	store = PuzzleStore.new(game.catalog)
	game.sandbox.simulation.state_changed.connect(_result)

func editor(data: Dictionary = {}) -> void:
	mode = "editor"
	game.sandbox.build.authoring = true
	puzzle = store.create() if data.is_empty() else data.duplicate(true)
	opening_fingerprint = store.fingerprint(puzzle)
	opening_revision = int(puzzle.get("revision", 1))
	game.sandbox.build.rules = null
	game.sandbox.simulation.puzzle = {}
	game.sandbox.build.dirty = false
	reload_environment()
	game.sandbox.load_construction(puzzle.pieces + PuzzleEnvironment.construction(puzzle))
	game.track_name = puzzle.name
	game.track_id = ""
	game.enter_sandbox()
	apply_camera()
	mode_changed.emit()

func capture() -> Dictionary:
	if mode == "editor":
		PuzzleEnvironment.capture(puzzle, game.sandbox.build.pieces)
		if puzzle.get("status") == "published" and store.fingerprint(puzzle) != opening_fingerprint:
			puzzle.revision = opening_revision + 1
			puzzle.status = "draft"
	return puzzle.duplicate(true)

func player(data: Dictionary, testing: bool = false) -> void:
	if not testing: store.remember_level(data)
	mode = "test" if testing else "campaign"
	game.sandbox.build.authoring = false
	puzzle = data.duplicate(true)
	game.sandbox.build.rules = null
	game.sandbox.simulation.puzzle = puzzle
	game.sandbox.build.dirty = false
	reload_environment()
	game.sandbox.load_construction(puzzle.pieces)
	# Normalize instance-specific geometry before using the immutable rule baseline.
	puzzle.pieces = game.sandbox.build.snapshot()
	game.sandbox.build.rules = PuzzleRules.new(puzzle, game.catalog, game.sandbox.build.snap.environment_solids)
	game.track_name = puzzle.name
	game.track_id = ""
	game.enter_sandbox()
	var toolbox = game.get_node("%HUD").get_node("%Toolbox")
	toolbox.get_node("%Category").select(0)
	toolbox.get_node("%Search").clear()
	apply_camera()
	test_success = false
	mode_changed.emit()

func sandbox() -> void:
	mode = "sandbox"
	game.sandbox.build.authoring = false
	puzzle = {}
	reload_environment()
	game.sandbox.build.rules = null
	game.sandbox.simulation.puzzle = {}
	mode_changed.emit()

func reload_environment() -> bool:
	game.sandbox.simulation.reset()
	game.sandbox.build.cancel()
	if is_instance_valid(environment_node):
		game.sandbox.remove_child(environment_node)
		environment_node.queue_free()
		environment_node = null
	var inspected := {"solids": [], "errors": []}
	var frozen := str(puzzle.get("environment_snapshot", "")) if mode == "campaign" else ""
	if not frozen.is_empty():
		var scene := ResourceLoader.load(frozen, "PackedScene") as PackedScene
		if not scene:
			game.show_message("Published environment is missing")
			return false
		environment_node = scene.instantiate()
		PuzzleEnvironment._collect(environment_node, Transform3D.IDENTITY, inspected)
	else:
		var fixed_data := puzzle.duplicate(true)
		if mode == "editor":
			fixed_data.environment_instances = []
			fixed_data.erase("environment")
			fixed_data.erase("environment_placement")
		inspected = PuzzleEnvironment.inspect_definition(fixed_data)
		if not inspected.errors.is_empty():
			game.show_message("\n".join(inspected.errors))
			return false
		if not str(fixed_data.get("environment", "")).is_empty() or not fixed_data.get("environment_instances", []).is_empty():
			environment_node = PuzzleEnvironment.instantiate_definition(fixed_data)
	game.sandbox.build.snap.environment_solids = inspected.solids
	if environment_node: game.sandbox.add_child(environment_node)
	return true

func test_player() -> bool:
	if mode != "editor": return false
	var errors := validate(false)
	if not errors.is_empty(): game.show_message("\n".join(errors)); return false
	authored = capture()
	testing_fingerprint = store.fingerprint(authored)
	player(authored, true)
	return true

func return_editor() -> void:
	if mode != "test": return
	editor(authored)

func restore_reference() -> bool:
	if mode != "test" or puzzle.get("solution", []).is_empty(): return false
	var problem = game.sandbox.build.rules.validate(puzzle.solution)
	if not problem.is_empty(): game.sandbox.build.show_status(problem); return false
	game.sandbox.simulation.reset()
	game.sandbox.build.restore(puzzle.solution)
	game.sandbox.build.history.clear_history()
	game.sandbox.build.dirty = false
	return true

func preserve_solution() -> bool:
	if mode != "test" or not test_success: return false
	if store.fingerprint(authored) != successful_fingerprint: return false
	authored.solution = successful_solution.duplicate(true)
	authored.validation = {"physics_success": true, "fingerprint": successful_fingerprint, "seconds": successful_time, "engine": Engine.get_version_info().string, "tested_at": Time.get_datetime_string_from_system(true)}
	return store.save_draft(authored)

func _result(state: int, _message: String) -> void:
	if state != SimulationManager.State.SUCCESS or mode not in ["test", "campaign"]: return
	if mode == "test":
		if store.fingerprint(authored) != testing_fingerprint: return
		test_success = true
		successful_solution = game.sandbox.simulation.construction_before.duplicate(true)
		successful_time = game.sandbox.simulation.elapsed
		successful_fingerprint = store.fingerprint(authored)
	else:
		store.complete(puzzle, game.sandbox.simulation.elapsed, game.sandbox.build.pieces.size())
	mode_changed.emit()

func save() -> bool:
	if mode != "editor": return false
	var saved = store.save_draft(capture())
	if saved: game.sandbox.build.dirty = false
	return saved

func publish() -> bool:
	if mode != "editor": return false
	var errors := validate()
	if not errors.is_empty(): game.show_message("\n".join(errors)); return false
	if not store.publish(capture()): game.show_message(store.last_error); return false
	game.sandbox.build.show_status("Published · available in Campaign")
	return true

func validate(require_solution: bool = true) -> Array[String]:
	var data := capture()
	var errors := store.validate(data)
	errors.append_array(game.sandbox.simulation.validate_links())
	var proof: Dictionary = data.get("validation", {})
	if require_solution and (data.get("solution", []).is_empty() or not proof.get("physics_success", false) or proof.get("fingerprint", "") != store.fingerprint(data)):
		errors.append("This revision needs a successful Test as Player solution")
	return errors

func set_permissions(values: Dictionary) -> void:
	if mode != "editor": return
	for piece in game.sandbox.build.selection:
		if not piece.definition.authoring_only: puzzle.permissions[piece.instance_id] = values.duplicate(true)
	game.sandbox.build.dirty = true
	mode_changed.emit()

func capture_camera() -> void:
	var camera: ConstructionCamera = game.sandbox.camera
	puzzle.camera = {"focus": [camera.target_focus.x, camera.target_focus.y, camera.target_focus.z], "yaw": camera.target_yaw, "pitch": camera.target_pitch, "distance": camera.target_distance}

func apply_camera() -> void:
	var saved: Dictionary = puzzle.get("camera", {})
	if saved.is_empty(): return
	var camera: ConstructionCamera = game.sandbox.camera
	camera.target_focus = Vector3(saved.focus[0], saved.focus[1], saved.focus[2])
	camera.target_yaw = saved.yaw
	camera.target_pitch = saved.pitch
	camera.target_distance = saved.distance

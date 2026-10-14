class_name ConstructionSession
extends Node

enum Context { SANDBOX, AUTHORING, PUZZLE_PLAY, PLAYER_TEST }
signal context_changed
signal changed
signal message_requested(text: String)
var world: WorldManager
var catalog: PieceCatalog
var serializer: TrackSerializer
var track_name: String = "Untitled track"
var track_id: String = ""
var store: PuzzleStore
var context: Context = Context.SANDBOX
var is_sandbox: bool:
	get: return context == Context.SANDBOX
var is_authoring: bool:
	get: return context == Context.AUTHORING
var is_testing: bool:
	get: return context == Context.PLAYER_TEST
var is_playing: bool:
	get: return context in [Context.PUZZLE_PLAY, Context.PLAYER_TEST]
var puzzle: Dictionary = {}
var authored: Dictionary = {}
var test_success: bool = false
var successful_solution: Array = []
var successful_time: float = 0
var successful_fingerprint: String = ""
var testing_fingerprint: String = ""
var opening_fingerprint: String = ""
var opening_revision: int = 1
var official_authoring: bool = false
var environment_node: Node3D

func configure(construction_world: WorldManager, piece_catalog: PieceCatalog) -> void:
	world = construction_world
	catalog = piece_catalog
	serializer = TrackSerializer.new(catalog)
	store = PuzzleStore.new(catalog)
	world.simulation.state_changed.connect(_result)

# A context transition clears the old run and editing state before loading data.
func _clear_runtime() -> void:
	world.simulation.reset()
	world.build.cancel()
	world.boundary.cancel()
	world.build.rules = null
	world.build.authoring = false
	world.simulation.puzzle = {}
	world.build.snap.environment_solids.clear()
	if is_instance_valid(environment_node):
		world.remove_child(environment_node)
		environment_node.queue_free()
		environment_node = null
	test_success = false
	successful_solution.clear()
	successful_time = 0
	successful_fingerprint = ""

func _entered() -> void:
	context_changed.emit()
	changed.emit()

func editor(data: Dictionary = {}, official: bool = false) -> void:
	_clear_runtime()
	context = Context.AUTHORING
	authored = {}
	testing_fingerprint = ""
	world.build.authoring = true
	official_authoring = official and store.can_add_to_campaign()
	puzzle = store.create() if data.is_empty() else data.duplicate(true)
	if official_authoring and puzzle.get("campaign", {}).has("legacy_chapter"):
		puzzle.campaign.chapter = puzzle.campaign.legacy_chapter.duplicate(true)
		puzzle.campaign.erase("legacy_chapter")
	if official_authoring and not puzzle.has("campaign"):
		puzzle.campaign = {"chapter": CampaignDefinition.new(store.base_chapters(), []).first_chapter(false), "order": 1, "prerequisites": []}
	opening_fingerprint = store.fingerprint(puzzle)
	opening_revision = int(puzzle.get("revision", 1))
	world.build.rules = null
	world.simulation.puzzle = {}
	world.build.dirty = false
	reload_environment()
	world.load_construction(puzzle.pieces + PuzzleEnvironment.construction(puzzle))
	track_name = puzzle.name
	track_id = ""
	apply_camera()
	_entered()

func capture() -> Dictionary:
	if is_authoring:
		PuzzleEnvironment.capture(puzzle, world.build.pieces)
		if puzzle.get("status") == "published" and store.fingerprint(puzzle) != opening_fingerprint:
			puzzle.revision = opening_revision + 1
			puzzle.status = "draft"
	return puzzle.duplicate(true)

func player(data: Dictionary, testing: bool = false) -> void:
	if not testing: store.remember_level(data)
	_clear_runtime()
	context = Context.PLAYER_TEST if testing else Context.PUZZLE_PLAY
	if not testing:
		authored = {}
		testing_fingerprint = ""
	world.build.authoring = false
	puzzle = data.duplicate(true)
	world.build.rules = null
	world.simulation.puzzle = puzzle
	world.build.dirty = false
	reload_environment()
	world.load_construction(puzzle.pieces)
	# Normalize instance-specific geometry before using the immutable rule baseline.
	puzzle.pieces = world.build.snapshot()
	world.build.rules = PuzzleRules.new(puzzle, catalog, world.build.snap.environment_solids)
	track_name = puzzle.name
	track_id = ""
	apply_camera()
	test_success = false
	_entered()

func sandbox(pieces: Array = [], track_title: String = "Untitled track", id: String = "", circulation: bool = false) -> void:
	_clear_runtime()
	context = Context.SANDBOX
	authored = {}
	testing_fingerprint = ""
	track_name = track_title
	track_id = id
	world.build.authoring = false
	puzzle = {}
	reload_environment()
	world.build.rules = null
	world.simulation.puzzle = {"objectives": [], "time_limit": 3600} if circulation else {}
	world.load_construction(pieces)
	_entered()

func load_track(id: String, example: bool) -> bool:
	var path := "res://resources/menu_machine.json" if id == "menu-machine" else "res://resources/examples/" + id + ".json"
	var data := serializer.decode(FileAccess.get_file_as_string(path)) if example else serializer.load_track(id)
	if data.is_empty():
		message_requested.emit(serializer.last_error)
		return false
	sandbox(data.pieces, data.name, "" if example else id, example and id == "menu-machine")
	if not serializer.warnings.is_empty(): message_requested.emit("\n".join(serializer.warnings))
	return true

func save_track(track_title: String, existing_id: String = "") -> bool:
	if not is_sandbox: return false
	var id := serializer.save_track(track_title, world.build.snapshot(), existing_id)
	if id.is_empty():
		message_requested.emit(serializer.last_error)
		return false
	track_name = track_title.strip_edges()
	track_id = id
	world.build.dirty = false
	world.build.show_status("Track saved")
	changed.emit()
	return true

func start_simulation() -> bool:
	return test_player() if is_authoring else world.simulation.start()

func metadata_changed() -> void:
	if not is_authoring: return
	world.build.dirty = true
	track_name = puzzle.name
	changed.emit()

func reload_environment() -> bool:
	var fixed_data := puzzle.duplicate(true)
	if is_authoring: fixed_data.environment_instances = []
	var inspected := PuzzleEnvironment.inspect_definition(fixed_data)
	if not inspected.errors.is_empty():
		message_requested.emit("\n".join(inspected.errors))
		return false
	if not fixed_data.get("environment_instances", []).is_empty():
		environment_node = PuzzleEnvironment.instantiate_definition(fixed_data)
	world.build.snap.environment_solids = inspected.solids
	if environment_node: world.add_child(environment_node)
	return true

func test_player() -> bool:
	if not is_authoring: return false
	var errors := validate(false)
	if not errors.is_empty(): message_requested.emit("\n".join(errors)); return false
	authored = capture()
	testing_fingerprint = store.fingerprint(authored)
	player(authored, true)
	return true

func return_editor() -> void:
	if not is_testing: return
	editor(authored, official_authoring)

func restore_reference() -> bool:
	if not is_testing or puzzle.get("solution", []).is_empty(): return false
	var problem = world.build.rules.validate(puzzle.solution)
	if not problem.is_empty(): world.build.show_status(problem); return false
	world.simulation.reset()
	world.build.restore(puzzle.solution)
	world.build.history.clear_history()
	world.build.dirty = false
	return true

func preserve_solution() -> bool:
	if not is_testing or not test_success: return false
	if store.fingerprint(authored) != successful_fingerprint: return false
	authored.solution = successful_solution.duplicate(true)
	authored.validation = {"physics_success": true, "fingerprint": successful_fingerprint, "seconds": successful_time, "engine": Engine.get_version_info().string, "tested_at": Time.get_datetime_string_from_system(true)}
	return store.save_draft(authored)

func _result(state: int, _message: String) -> void:
	if state != SimulationManager.State.SUCCESS or not is_playing: return
	if is_testing:
		if store.fingerprint(authored) != testing_fingerprint: return
		test_success = true
		successful_solution = world.simulation.construction_before.duplicate(true)
		successful_time = world.simulation.elapsed
		successful_fingerprint = store.fingerprint(authored)
	else:
		store.complete(puzzle, world.simulation.elapsed, world.build.pieces.size())
	changed.emit()

func save_draft() -> bool:
	if not is_authoring: return false
	var saved = store.save_draft(capture())
	if saved:
		world.build.dirty = false
		changed.emit()
	return saved

func publish() -> bool:
	if not is_authoring: return false
	var errors := validate()
	if not errors.is_empty(): message_requested.emit("\n".join(errors)); return false
	var saved := store.add_to_campaign(capture()) if official_authoring else store.publish(capture())
	if not saved: message_requested.emit(store.last_error); return false
	puzzle.status = "published"
	opening_fingerprint = store.fingerprint(puzzle)
	opening_revision = int(puzzle.get("revision", 1))
	world.build.show_status("Added to Campaign" if official_authoring else "Published locally")
	return true

func validate(require_solution: bool = true) -> Array[String]:
	var data := capture()
	var errors := store.validate(data)
	errors.append_array(world.build.validate_wiring())
	var proof: Dictionary = data.get("validation", {})
	if require_solution and (data.get("solution", []).is_empty() or not proof.get("physics_success", false) or proof.get("fingerprint", "") != store.fingerprint(data)):
		errors.append("This revision needs a successful Test as Player solution")
	return errors

func set_permissions(values: Dictionary) -> void:
	if not is_authoring: return
	for piece in world.build.selection:
		if not piece.definition.authoring_only: puzzle.permissions[piece.instance_id] = values.duplicate(true)
	world.build.dirty = true
	changed.emit()

func capture_camera() -> void:
	var camera: ConstructionCamera = world.camera
	puzzle.camera = {"focus": [camera.target_focus.x, camera.target_focus.y, camera.target_focus.z], "yaw": camera.target_yaw, "pitch": camera.target_pitch, "distance": camera.target_distance}

func apply_camera() -> void:
	var saved: Dictionary = puzzle.get("camera", {})
	if saved.is_empty(): return
	var camera: ConstructionCamera = world.camera
	camera.target_focus = Vector3(saved.focus[0], saved.focus[1], saved.focus[2])
	camera.target_yaw = saved.yaw
	camera.target_pitch = saved.pitch
	camera.target_distance = saved.distance

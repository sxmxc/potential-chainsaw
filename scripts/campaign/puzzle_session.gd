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
var boundary_visual: MeshInstance3D
var boundary_tool: String = ""
var first_corner: Variant = null
var boundary_zone_index: int = -1
var opening_fingerprint: String = ""
var opening_revision: int = 1
var environment_node: Node3D

func configure(owner_game: Node) -> void:
	game = owner_game
	store = PuzzleStore.new(game.catalog)
	game.sandbox.simulation.state_changed.connect(_result)
	boundary_visual = MeshInstance3D.new()
	boundary_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.sandbox.add_child(boundary_visual)

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
	refresh_boundary()
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
	refresh_boundary()
	test_success = false
	mode_changed.emit()

func sandbox() -> void:
	mode = "sandbox"
	game.sandbox.build.authoring = false
	puzzle = {}
	reload_environment()
	game.sandbox.build.rules = null
	game.sandbox.simulation.puzzle = {}
	boundary_visual.hide()
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

func refresh_boundary() -> void:
	boundary_visual.visible = mode != "sandbox"
	if mode == "sandbox": return
	var b: Array = puzzle.bounds
	var mesh = ImmediateMesh.new()
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("59e5b1")
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	draw_box(mesh, AABB(Vector3(b[0], b[4] + 0.02, b[1]), Vector3(b[2] - b[0], b[5] - b[4], b[3] - b[1])))
	for zone in puzzle.get("restricted_zones", []): draw_box(mesh, AABB(Vector3(zone[0], zone[1], zone[2]), Vector3(zone[3], zone[4], zone[5])))
	mesh.surface_end()
	boundary_visual.mesh = mesh

func draw_box(mesh: ImmediateMesh, box: AABB) -> void:
	var corners: Array[Vector3] = []
	for x in [box.position.x, box.end.x]:
		for y in [box.position.y, box.end.y]:
			for z in [box.position.z, box.end.z]: corners.append(Vector3(x, y, z))
	for i in 8:
		for bit in [1, 2, 4]:
			var j = i ^ bit
			if i < j: mesh.surface_add_vertex(corners[i]); mesh.surface_add_vertex(corners[j])

func begin_boundary(zone: bool = false, zone_index: int = -1) -> void:
	boundary_tool = "zone" if zone else "build"
	boundary_zone_index = zone_index
	first_corner = null
	game.sandbox.build.cancel()
	game.sandbox.build.enabled = false
	game.sandbox.build.show_status("Build region · click two opposite corners in the world · Esc cancels")

func _input(event: InputEvent) -> void:
	if boundary_tool.is_empty(): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		boundary_tool = ""
		game.sandbox.build.enabled = true
		get_viewport().set_input_as_handled()
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT or get_viewport().gui_get_hovered_control() != null: return
	var point = game.sandbox.build.plane_point(event.position, 0)
	if point == null: return
	point = game.sandbox.build.snap.grid_position(point)
	if first_corner == null:
		first_corner = point
		game.sandbox.build.show_status("Now click the opposite corner")
	else:
		var low: Vector3 = first_corner.min(point)
		var high: Vector3 = first_corner.max(point)
		if high.x - low.x < 1 or high.z - low.z < 1: return
		if boundary_tool == "build": puzzle.bounds = [low.x, low.z, high.x, high.z, puzzle.bounds[4], puzzle.bounds[5]]
		else:
			var zone = [low.x, puzzle.bounds[4], low.z, high.x - low.x, puzzle.bounds[5] - puzzle.bounds[4], high.z - low.z]
			if boundary_zone_index >= 0 and boundary_zone_index < puzzle.restricted_zones.size(): puzzle.restricted_zones[boundary_zone_index] = zone
			else: puzzle.restricted_zones.append(zone)
		boundary_tool = ""
		game.sandbox.build.enabled = true
		game.sandbox.build.dirty = true
		refresh_boundary()
		mode_changed.emit()
	get_viewport().set_input_as_handled()

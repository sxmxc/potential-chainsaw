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
signal environment_selection_changed
var environment_editing: bool = false
var environment_selected: String = ""
var environment_asset: String = ""
var environment_history := BuildHistory.new()
var environment_press: Variant = null
var environment_offset := Vector3.ZERO
var environment_dragging: bool = false
var environment_node: Node3D

func configure(owner_game: Node) -> void:
	game = owner_game
	store = PuzzleStore.new(game.catalog)
	game.sandbox.simulation.state_changed.connect(_result)
	game.sandbox.build.changed.connect(func(): mode_changed.emit())
	boundary_visual = MeshInstance3D.new()
	boundary_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.sandbox.add_child(boundary_visual)

func editor(data: Dictionary = {}) -> void:
	set_environment_editing(false)
	mode = "editor"
	puzzle = store.create() if data.is_empty() else data.duplicate(true)
	opening_fingerprint = store.fingerprint(puzzle)
	opening_revision = int(puzzle.get("revision", 1))
	environment_history.clear()
	game.sandbox.build.rules = null
	game.sandbox.simulation.puzzle = {}
	game.sandbox.build.dirty = false
	reload_environment()
	game.sandbox.load_construction(puzzle.pieces)
	game.track_name = puzzle.name
	game.track_id = ""
	game.enter_sandbox()
	apply_camera()
	refresh_boundary()
	mode_changed.emit()

func capture() -> Dictionary:
	if mode == "editor":
		puzzle.pieces = game.sandbox.build.snapshot()
		if puzzle.get("status") == "published" and store.fingerprint(puzzle) != opening_fingerprint:
			puzzle.revision = opening_revision + 1
			puzzle.status = "draft"
	return puzzle.duplicate(true)

func player(data: Dictionary, testing: bool = false) -> void:
	if not testing: store.remember_level(data)
	set_environment_editing(false)
	mode = "test" if testing else "campaign"
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
	set_environment_editing(false)
	mode = "sandbox"
	puzzle = {}
	reload_environment()
	game.sandbox.build.rules = null
	game.sandbox.simulation.puzzle = {}
	boundary_visual.hide()
	mode_changed.emit()

func set_environment(path: String) -> bool:
	if mode != "editor": return false
	var inspected := PuzzleEnvironment.inspect(path)
	if not inspected.errors.is_empty():
		game.show_message("\n".join(inspected.errors))
		return false
	if path.is_empty(): puzzle.erase("environment")
	else: puzzle["environment"] = path
	game.sandbox.build.history.clear()
	environment_history.clear()
	reload_environment()
	game.sandbox.build.dirty = true
	mode_changed.emit()
	return true

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
		inspected = PuzzleEnvironment.inspect_definition(puzzle)
		if not inspected.errors.is_empty():
			game.show_message("\n".join(inspected.errors))
			return false
		if not str(puzzle.get("environment", "")).is_empty() or not puzzle.get("environment_instances", []).is_empty():
			environment_node = PuzzleEnvironment.instantiate_definition(puzzle)
	game.sandbox.build.snap.environment_solids = inspected.solids
	if environment_node: game.sandbox.add_child(environment_node)
	update_environment_highlight()
	environment_selection_changed.emit()
	return true

func set_environment_editing(active: bool) -> void:
	if not game: return
	if active and (mode != "editor" or game.sandbox.simulation.state != SimulationManager.State.BUILD): return
	cancel_environment_gesture()
	environment_editing = active
	if active:
		boundary_tool = ""
		first_corner = null
	game.sandbox.build.cancel()
	game.sandbox.build.select(null)
	game.sandbox.build.environment_editing = active
	game.sandbox.build.enabled = not active and game.sandbox.simulation.state == SimulationManager.State.BUILD
	game.sandbox.build.refresh_grid()
	if not active:
		environment_asset = ""
		environment_selected = ""
	update_environment_highlight()
	environment_selection_changed.emit()
	game.get_node("%HUD").refresh()

func environment_item() -> Dictionary:
	for item in puzzle.get("environment_instances", []):
		if item.uid == environment_selected: return item
	return {}

func select_environment(uid: String) -> void:
	if mode != "editor": return
	environment_selected = uid
	environment_asset = ""
	update_environment_highlight()
	environment_selection_changed.emit()

func choose_environment(asset: String) -> void:
	if not PuzzleEnvironment.CATALOG.has(asset): return
	set_environment_editing(true)
	if not environment_editing: return
	environment_asset = asset
	environment_selected = ""
	game.sandbox.build.show_status("Click the grid to place · Esc cancels")
	environment_selection_changed.emit()

func edit_environment(items: Array, label: String, record_history: bool = true) -> bool:
	if mode != "editor" or game.sandbox.simulation.state != SimulationManager.State.BUILD: return false
	var candidate := puzzle.duplicate(true)
	candidate.environment_instances = items
	var inspected := PuzzleEnvironment.inspect_definition(candidate)
	if not inspected.errors.is_empty(): return false
	for piece in game.sandbox.build.pieces:
		if PuzzleEnvironment.blocked(piece.definition, piece.transform, inspected.solids):
			game.sandbox.build.show_status("Blocked by a track piece")
			return false
	var before: Array = puzzle.get("environment_instances", []).duplicate(true)
	if before == items: return true
	puzzle.version = 2
	puzzle.environment_instances = items.duplicate(true)
	if record_history: environment_history.record(before, items, label)
	# Track history belongs to the previous collision arrangement.
	game.sandbox.build.history.clear()
	reload_environment()
	game.sandbox.build.dirty = true
	mode_changed.emit()
	return true

func place_environment(asset: String, point: Vector3) -> bool:
	if not PuzzleEnvironment.CATALOG.has(asset): return false
	var items: Array = puzzle.get("environment_instances", []).duplicate(true)
	var uid := "environment-" + Crypto.new().generate_random_bytes(8).hex_encode()
	items.append({"uid": uid, "asset": asset, "position": [point.x, point.y, point.z], "rotation": 0})
	if not edit_environment(items, "Place environment"): return false
	select_environment(uid)
	return true

func transform_environment(point: Vector3, turn: int) -> bool:
	var items: Array = puzzle.get("environment_instances", []).duplicate(true)
	for item in items:
		if item.uid == environment_selected:
			item.position = [point.x, point.y, point.z]
			item.rotation = posmod(turn, 4)
			return edit_environment(items, "Move/rotate environment")
	return false

func remove_environment() -> void:
	if environment_selected.is_empty(): return
	var items: Array = puzzle.get("environment_instances", []).filter(func(item): return item.uid != environment_selected)
	if edit_environment(items, "Remove environment"): select_environment("")

func duplicate_environment() -> void:
	var item := environment_item().duplicate(true)
	if item.is_empty(): return
	item.uid = "environment-" + Crypto.new().generate_random_bytes(8).hex_encode()
	item.position[0] += game.sandbox.build.snap.horizontal_step
	var items: Array = puzzle.get("environment_instances", []).duplicate(true)
	items.append(item)
	if edit_environment(items, "Duplicate environment"): select_environment(item.uid)

func environment_undo(redo: bool = false) -> void:
	if mode != "editor" or game.sandbox.simulation.state != SimulationManager.State.BUILD: return
	cancel_environment_gesture()
	if redo and environment_history.cursor >= environment_history.commands.size(): return
	if not redo and environment_history.cursor == 0: return
	var index := environment_history.cursor if redo else environment_history.cursor - 1
	var items: Array = environment_history.commands[index]["after" if redo else "before"]
	if edit_environment(items, "Restore environment", false):
		environment_history.cursor += 1 if redo else -1
		environment_history.changed.emit()
		environment_selection_changed.emit()

func cancel_environment_gesture() -> void:
	if environment_dragging:
		# Drag only previews the node; JSON remains the committed source of truth.
		reload_environment()
	environment_press = null
	environment_dragging = false

func pick_environment(screen: Vector2) -> String:
	var camera: ConstructionCamera = game.sandbox.camera
	var ray := camera.project_ray_origin(screen)
	var hit: Dictionary = game.sandbox.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(ray, ray + camera.project_ray_normal(screen) * 250, 1))
	var node := hit.get("collider") as Node
	while node:
		if node.has_meta("environment_uid"): return str(node.get_meta("environment_uid"))
		node = node.get_parent()
	return ""

func _unhandled_input(event: InputEvent) -> void:
	if not environment_editing or mode != "editor" or not game.sandbox.camera.enabled or game.sandbox.simulation.state != SimulationManager.State.BUILD or ConstructionInput.typing(get_viewport()): return
	var build: BuildManager = game.sandbox.build
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and game.sandbox.camera.drag_button == 0:
		if not environment_asset.is_empty():
			var point = build.plane_point(event.position, build.height)
			if point != null: place_environment(environment_asset, build.snap.grid_position(point))
		else:
			select_environment(pick_environment(event.position))
			if not environment_item().is_empty():
				environment_press = event.position
				var placement := PuzzleEnvironment.transform_for(environment_item())
				var point = build.plane_point(event.position, placement.origin.y)
				if point != null: environment_offset = placement.origin - point
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and environment_press != null and game.sandbox.camera.drag_button == 0:
		if event.position.distance_to(environment_press) < build.drag_threshold and not environment_dragging: return
		var item := environment_item()
		if item.is_empty(): return
		var point = build.plane_point(event.position, float(item.position[1]))
		if point != null:
			environment_dragging = true
			var object := environment_node.get_node(NodePath(environment_selected)) as Node3D
			object.position = build.snap.grid_position(point + environment_offset)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var item := environment_item()
		if event.is_action_pressed("build_cancel", false, true): cancel_environment_gesture(); environment_asset = ""; select_environment("")
		elif event.is_action_pressed("build_remove", false, true): remove_environment()
		elif event.is_action_pressed("build_duplicate", false, true): duplicate_environment()
		elif event.is_action_pressed("build_rotate", false, true) and not item.is_empty(): transform_environment(PuzzleEnvironment.transform_for(item).origin, int(item.rotation) + 1)
		elif event.is_action_pressed("build_undo", false, true): environment_undo()
		elif event.is_action_pressed("build_redo", false, true): environment_undo(true)
		elif event.is_action_pressed("build_height_up", false, true): build.set_height(build.height + build.height_step())
		elif event.is_action_pressed("build_height_down", false, true): build.set_height(build.height - build.height_step())
		else: return
		get_viewport().set_input_as_handled()

func test_player() -> bool:
	if mode != "editor": return false
	authored = capture()
	var errors = store.validate(authored)
	errors.append_array(MechanismLinks.validate(game.sandbox.build.pieces))
	if not errors.is_empty(): game.show_message("\n".join(errors)); return false
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
	game.sandbox.build.history.clear()
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
	var errors = MechanismLinks.validate(game.sandbox.build.pieces)
	if not errors.is_empty(): game.show_message("\n".join(errors)); return false
	if not store.publish(capture()): game.show_message(store.last_error); return false
	game.sandbox.build.show_status("Published · available in Campaign")
	return true

func set_permissions(values: Dictionary) -> void:
	if mode != "editor": return
	for piece in game.sandbox.build.selection: puzzle.permissions[piece.instance_id] = values.duplicate(true)
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
	set_environment_editing(false)
	boundary_tool = "zone" if zone else "build"
	boundary_zone_index = zone_index
	first_corner = null
	game.sandbox.build.cancel()
	game.sandbox.build.enabled = false
	game.sandbox.build.show_status("Build region · click two opposite corners in the world · Esc cancels")

func _input(event: InputEvent) -> void:
	if environment_editing and event is InputEventMouseButton and event.pressed and get_viewport().gui_get_hovered_control() == null:
		var focus := get_viewport().gui_get_focus_owner()
		if focus: focus.release_focus()
	if environment_editing and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and environment_press != null:
		if environment_dragging and get_viewport().gui_get_hovered_control() == null:
			var object := environment_node.get_node(NodePath(environment_selected)) as Node3D
			var obj_point := object.position
			var turn := int(environment_item().rotation)
			environment_dragging = false
			if not transform_environment(obj_point, turn): reload_environment()
		else: cancel_environment_gesture()
		environment_press = null
		get_viewport().set_input_as_handled()
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

func update_environment_highlight() -> void:
	if not is_instance_valid(environment_node): return
	for object in environment_node.get_children():
		var highlighted: bool = environment_editing and str(object.get_meta("environment_uid", "")) == environment_selected and not environment_selected.is_empty()
		for mesh in object.find_children("*", "MeshInstance3D", true, false):
			mesh.material_overlay = preload("res://resources/environment_selection.tres") if highlighted else null

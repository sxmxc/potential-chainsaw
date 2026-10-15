class_name PuzzleBoundary
extends MeshInstance3D

signal edited
signal selection_changed
signal interaction_changed

@export var build: BuildManager
var session: ConstructionSession
var tool: String = ""
var first_corner: Variant = null
var zone_index: int = -1
var selected_region: int = -1
var selecting: bool = false
var drag_start: Variant = null
var drag_box: AABB

func set_editing(active: bool) -> void:
	if selecting == active: return
	cancel()
	selecting = active and session.is_authoring
	if selecting: build.cancel()
	interaction_changed.emit()
	refresh()

func select_region(index: int) -> void:
	selected_region = clampi(index, -1, session.puzzle.restricted_zones.size() - 1)
	refresh()
	selection_changed.emit()

func region_box(index: int) -> AABB:
	if index >= 0 and index < session.puzzle.restricted_zones.size():
		var zone: Array = session.puzzle.restricted_zones[index]
		return AABB(Vector3(zone[0], zone[1], zone[2]), Vector3(zone[3], zone[4], zone[5]))
	var bounds: Array = session.puzzle.bounds
	return AABB(Vector3(bounds[0], bounds[4], bounds[1]), Vector3(bounds[2] - bounds[0], bounds[5] - bounds[4], bounds[3] - bounds[1]))

func write_region(box: AABB) -> void:
	if selected_region < 0:
		session.puzzle.bounds = [box.position.x, box.position.z, box.end.x, box.end.z, box.position.y, box.end.y]
	else:
		session.puzzle.restricted_zones[selected_region] = [box.position.x, box.position.y, box.position.z, box.size.x, box.size.y, box.size.z]
	refresh()

func set_elevation(value: float, lower: bool) -> void:
	var box := region_box(selected_region)
	var top := box.end.y
	if lower:
		box.position.y = minf(value, top - 0.125)
		box.size.y = top - box.position.y
	else: box.size.y = maxf(0.125, value - box.position.y)
	write_region(box)
	edited.emit()

func set_footprint(x: float, z: float, width: float, depth: float) -> void:
	var box := region_box(selected_region)
	box.position.x = x
	box.position.z = z
	box.size.x = maxf(1.0, width)
	box.size.z = maxf(1.0, depth)
	if box == region_box(selected_region): return
	write_region(box)
	edited.emit()

func configure(puzzle_session: ConstructionSession) -> void:
	session = puzzle_session
	session.context_changed.connect(func(): drag_start = null; selected_region = -1; cancel(); refresh())
	refresh()

func refresh() -> void:
	if not session.is_authoring:
		selecting = false
		drag_start = null
		tool = ""
		first_corner = null
		zone_index = -1
		interaction_changed.emit()
	visible = not session.is_sandbox
	if not visible: return
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	lines.surface_set_color(Color("f8da70") if selecting and selected_region == -1 else Color("59e5b1"))
	_draw_box(lines, region_box(-1))
	for index in session.puzzle.get("restricted_zones", []).size():
		lines.surface_set_color(Color("f8da70") if selecting and selected_region == index else Color("f78390"))
		_draw_box(lines, region_box(index))
	lines.surface_end()
	mesh = lines

func _draw_box(lines: ImmediateMesh, box: AABB) -> void:
	for index in 8:
		for bit in [1, 2, 4]:
			var other: int = index ^ bit
			if index < other:
				lines.surface_add_vertex(box.get_endpoint(index))
				lines.surface_add_vertex(box.get_endpoint(other))

func begin(zone: bool = false, index: int = -1) -> void:
	if not session.is_authoring or (not build.enabled and not selecting): return
	tool = "zone" if zone else "build"
	zone_index = index
	first_corner = null
	build.cancel()
	interaction_changed.emit()
	build.show_status(("Restricted area" if zone else "Build area") + " · click two opposite corners · Esc cancels")

func cancel() -> void:
	if drag_start != null:
		write_region(drag_box)
		drag_start = null
		selection_changed.emit()
	tool = ""
	first_corner = null
	zone_index = -1
	interaction_changed.emit()

func _input(event: InputEvent) -> void:
	if not session.is_authoring or not build.camera.enabled: return
	if tool.is_empty() and not selecting: return
	if event.is_action_pressed("build_cancel") and (not tool.is_empty() or drag_start != null):
		cancel()
		get_viewport().set_input_as_handled()
		return
	if tool.is_empty():
		select_input(event)
		return
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT or get_viewport().gui_get_hovered_control() != null: return
	var point: Variant = build.plane_point(event.position, 0)
	if point == null: return
	point = build.snap.grid_position(point)
	if first_corner == null:
		first_corner = point
		build.show_status("Now click the opposite corner")
	else:
		var low: Vector3 = first_corner.min(point)
		var high: Vector3 = first_corner.max(point)
		if high.x - low.x < 1 or high.z - low.z < 1: return
		var bounds: Array = session.puzzle.bounds
		if tool == "build":
			session.puzzle.bounds = [low.x, low.z, high.x, high.z, bounds[4], bounds[5]]
		else:
			var zone := [low.x, bounds[4], low.z, high.x - low.x, bounds[5] - bounds[4], high.z - low.z]
			if zone_index >= 0 and zone_index < session.puzzle.restricted_zones.size():
				zone[1] = session.puzzle.restricted_zones[zone_index][1]
				zone[4] = session.puzzle.restricted_zones[zone_index][4]
				session.puzzle.restricted_zones[zone_index] = zone
			else:
				session.puzzle.restricted_zones.append(zone)
		var result_region: int = -1 if tool == "build" else (zone_index if zone_index >= 0 else session.puzzle.restricted_zones.size() - 1)
		cancel()
		selected_region = result_region
		build.dirty = true
		refresh()
		edited.emit()
	get_viewport().set_input_as_handled()

func select_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and drag_start != null:
		var point: Variant = build.plane_point(event.position, 0)
		if point != null:
			var moved := drag_box
			moved.position += build.snap.grid_position(point - drag_start)
			write_region(moved)
			selection_changed.emit()
		get_viewport().set_input_as_handled()
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	if not event.pressed and drag_start != null:
		if get_viewport().gui_get_hovered_control() != null: write_region(drag_box)
		elif region_box(selected_region) != drag_box: edited.emit()
		drag_start = null
		selection_changed.emit()
		get_viewport().set_input_as_handled()
		return
	if not event.pressed or get_viewport().gui_get_hovered_control() != null: return
	var origin := build.camera.project_ray_origin(event.position)
	var direction := build.camera.project_ray_normal(event.position)
	var found := -1
	var nearest := INF
	for index in session.puzzle.restricted_zones.size():
		var hit: Variant = region_box(index).intersects_ray(origin, direction)
		if hit != null and origin.distance_to(hit) < nearest:
			found = index
			nearest = origin.distance_to(hit)
	if found < 0 and region_box(-1).intersects_ray(origin, direction) == null: return
	select_region(found)
	drag_start = build.plane_point(event.position, 0)
	drag_box = region_box(found)
	get_viewport().set_input_as_handled()

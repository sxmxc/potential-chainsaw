class_name PuzzleBoundary
extends MeshInstance3D

signal edited

@export var build: BuildManager
var session: ConstructionSession
var tool: String = ""
var first_corner: Variant = null
var zone_index: int = -1

func configure(puzzle_session: ConstructionSession) -> void:
	session = puzzle_session
	session.context_changed.connect(func(): cancel(); refresh())
	refresh()

func refresh() -> void:
	if not session.is_authoring:
		tool = ""
		first_corner = null
		zone_index = -1
	visible = not session.is_sandbox
	if not visible: return
	var bounds: Array = session.puzzle.bounds
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	_draw_box(lines, AABB(Vector3(bounds[0], bounds[4] + 0.02, bounds[1]), Vector3(bounds[2] - bounds[0], bounds[5] - bounds[4], bounds[3] - bounds[1])))
	for zone in session.puzzle.get("restricted_zones", []):
		_draw_box(lines, AABB(Vector3(zone[0], zone[1], zone[2]), Vector3(zone[3], zone[4], zone[5])))
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
	if not session.is_authoring or not build.enabled: return
	tool = "zone" if zone else "build"
	zone_index = index
	first_corner = null
	build.cancel()
	build.enabled = false
	build.show_status("Build region · click two opposite corners in the world · Esc cancels")

func cancel() -> void:
	tool = ""
	first_corner = null
	zone_index = -1
	build.enabled = true

func _input(event: InputEvent) -> void:
	if tool.is_empty(): return
	if event.is_action_pressed("build_cancel"):
		cancel()
		get_viewport().set_input_as_handled()
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
				session.puzzle.restricted_zones[zone_index] = zone
			else:
				session.puzzle.restricted_zones.append(zone)
		cancel()
		build.dirty = true
		refresh()
		edited.emit()
	get_viewport().set_input_as_handled()

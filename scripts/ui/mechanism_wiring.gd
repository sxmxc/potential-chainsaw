extends Control

## Presentation only: relationships are read from BuildingPiece.configuration.
## Projected, fixed-size handles remain usable as the construction camera orbits.
var build: BuildManager
var simulation: SimulationManager
var exclusions: Array[Control] = []
var overlay_enabled: bool = false
var handles: Array[Dictionary] = []
var wires: Array[Dictionary] = []
var hovered_handle: Dictionary = {}
var hovered_wire: Dictionary = {}
var receivers: Array[BuildingPiece] = []
var dragging: Dictionary = {}
var context_source: String = ""
var context_target: String = ""
var context_index: int = -1
var context_event: String = ""
var context_action: String = ""
var pointer := Vector2.ZERO
var context_anchor := Vector2.ZERO
var confirmation: PackedVector2Array = []
var confirmation_until: int = 0

static func readable(value: String) -> String:
	match value:
		"entered": return "Marble entered"
		"exited": return "Marble exited"
		"loaded": return "Marble loaded"
		"unloaded": return "Marble unloaded"
	return value.replace("_", " ").capitalize()

func configure(manager: BuildManager, simulator: SimulationManager) -> void:
	build = manager
	simulation = simulator
	pointer = get_viewport().get_mouse_position()
	%Apply.pressed.connect(apply_connection)
	%Events.item_selected.connect(func(index):
		context_event = %Events.get_item_metadata(index)
		refresh_actions())
	%Actions.item_selected.connect(func(index): context_action = %Actions.get_item_metadata(index))
	%Remove.pressed.connect(func():
		if build.edit_link(context_source, context_index): clear_context())
	%Dismiss.pressed.connect(clear_context)
	build.changed.connect(clear_interaction)
	build.options_changed.connect(func():
		if not build.connect_mode: clear_interaction())
	simulation.state_changed.connect(func(state, _message):
		if state != SimulationManager.State.BUILD:
			clear_interaction())

func set_tool(active: bool) -> void:
	clear_interaction()
	build.set_connect_mode(active)
	if active: build.show_status("Drag a send handle onto a receiving piece · Esc cancels")

func toggle_overlay() -> void:
	overlay_enabled = not overlay_enabled
	build.options_changed.emit()

func clear_context() -> void:
	%Context.hide()
	context_source = ""
	context_target = ""
	context_index = -1

func clear_interaction() -> void:
	dragging.clear()
	hovered_handle.clear()
	hovered_wire.clear()
	clear_context()
	%Hint.hide()

func permitted(piece: BuildingPiece) -> bool:
	return build.enabled and (not build.rules or build.rules.permits(piece.instance_id, "configure"))

func covered(point: Vector2) -> bool:
	for control in exclusions:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(point): return true
	return %Context.visible and %Context.get_global_rect().has_point(point)

func anchor(piece: BuildingPiece) -> Vector3:
	var visual := piece
	var moving_index := build.moving_group.find(piece)
	if moving_index >= 0 and moving_index < build.ghosts.size(): visual = build.ghosts[moving_index]
	var bounds := visual.definition.bounds
	return visual.global_transform * (bounds.get_center() + Vector3.UP * bounds.size.y * 0.5)

func port_position(piece: BuildingPiece, output: bool) -> Vector2:
	var center := build.camera.unproject_position(anchor(piece))
	return center + Vector2(30 if output else -30, -18)

func receiver_at(point: Vector2) -> Dictionary:
	if dragging.is_empty() or covered(point): return {}
	var picked := build.pick_piece(point)
	if picked in receivers: return {"source": picked.instance_id, "output": false, "point": port_position(picked, false)}
	var found: Dictionary = {}
	var distance := INF
	for piece in receivers:
		var bounds := ConstructionSelection.projected_bounds(piece, build.camera).grow(12)
		if not bounds.has_point(point): continue
		var pixels := bounds.get_center().distance_to(point)
		if pixels < distance:
			distance = pixels
			found = {"source": piece.instance_id, "output": false, "point": port_position(piece, false)}
	# The large role handle remains useful on tiny or partly occluded pieces.
	if found.is_empty():
		var handle := handle_at(point)
		if not handle.is_empty() and not handle.output and build.find_piece(handle.source) in receivers: return handle
	return found

func curve(start: Vector2, finish: Vector2, lane: float = 0) -> PackedVector2Array:
	var points := PackedVector2Array()
	var bend := clampf(start.distance_to(finish) * 0.22, 28, 100)
	var c1 := start + Vector2(bend, -18 - lane * 14)
	var c2 := finish + Vector2(-bend, -18 - lane * 14)
	for i in 33:
		var t := i / 32.0
		var u := 1.0 - t
		points.append(u*u*u*start + 3*u*u*t*c1 + 3*u*t*t*c2 + t*t*t*finish)
	return points

func refresh_projection() -> void:
	handles.clear()
	wires.clear()
	receivers.clear()
	var source := build.find_piece(dragging.get("source", ""))
	for piece in build.pieces:
		if build.camera.is_position_behind(anchor(piece)): continue
		if source and not source.compatible_events(piece).is_empty(): receivers.append(piece)
		if build.connect_mode:
			if not piece.output_ports.is_empty():
				handles.append({"source": piece.instance_id, "output": true, "point": port_position(piece, true), "allowed": permitted(piece)})
			if not piece.input_ports.is_empty():
				handles.append({"source": piece.instance_id, "output": false, "point": port_position(piece, false), "allowed": true})
		var links: Array = piece.configuration.get("links", [])
		for i in links.size():
			var link: Dictionary = links[i]
			var target := build.find_piece(link.get("target", ""))
			if not target or target.input_ports.is_empty() or build.camera.is_position_behind(anchor(target)): continue
			var points := curve(port_position(piece, true), port_position(target, false), i)
			wires.append({"source": piece.instance_id, "target": target.instance_id, "index": i, "link": link, "points": points})

func handle_at(point: Vector2) -> Dictionary:
	var result: Dictionary = {}
	var distance := 24.0
	for handle in handles:
		if covered(handle.point): continue
		var candidate: float = point.distance_to(handle.point)
		if candidate < distance:
			distance = candidate
			result = handle
	return result

func wire_at(point: Vector2) -> Dictionary:
	var result: Dictionary = {}
	var distance := 8.0
	for wire in wires:
		var points: PackedVector2Array = wire.points
		for i in range(1, points.size()):
			var candidate := point.distance_to(Geometry2D.get_closest_point_to_segment(point, points[i-1], points[i]))
			if candidate < distance:
				distance = candidate
				result = wire
	return result

func valid_receiver(handle: Dictionary) -> bool:
	return not handle.is_empty() and not handle.output and not dragging.is_empty() and build.find_piece(handle.source) in receivers

func _process(_delta: float) -> void:
	if not build: return
	var shown := simulation.state == SimulationManager.State.BUILD and build.enabled and (overlay_enabled or build.connect_mode)
	if not shown:
		if not build.enabled: clear_interaction()
		%Hint.hide()
		%Context.hide()
		queue_redraw()
		return
	if not build.connect_mode and not dragging.is_empty(): clear_interaction()
	refresh_projection()
	hovered_handle = receiver_at(pointer) if not dragging.is_empty() else (handle_at(pointer) if build.connect_mode and not covered(pointer) else {})
	hovered_wire = wire_at(pointer) if hovered_handle.is_empty() and not covered(pointer) else {}
	var hint := ""
	if not hovered_handle.is_empty():
		var piece := build.find_piece(hovered_handle.source)
		hint = "Output ▶ · " + ", ".join(piece.output_ports.keys().map(func(event): return readable(event))) if hovered_handle.output else "Input ◇ · " + ", ".join(piece.input_ports.keys().map(func(action): return readable(action)))
		if hovered_handle.output and not hovered_handle.allowed: hint += " · Locked"
		elif not dragging.is_empty() and hovered_handle.output: hint = "Drop onto a highlighted piece"
	elif not hovered_wire.is_empty():
		hint = describe(hovered_wire.source, hovered_wire.target) + "\n" + readable(hovered_wire.link.event) + " → " + readable(hovered_wire.link.action)
	%Hint.visible = not hint.is_empty() and not %Context.visible and build.camera.drag_button == 0
	%Text.text = hint
	%Hint.reset_size()
	%Hint.position = bounded(pointer + Vector2(16, 20), %Hint.size)
	if %Context.visible:
		%Context.reset_size()
		%Context.position = bounded(context_anchor + Vector2(16, 16), %Context.size)
	queue_redraw()

func bounded(point: Vector2, extent: Vector2) -> Vector2:
	return point.clamp(Vector2(8, 8), (size - extent - Vector2(8, 8)).max(Vector2(8, 8)))

func describe(source_id: String, target_id: String) -> String:
	var source := build.find_piece(source_id)
	var target := build.find_piece(target_id)
	return (source.definition.display_name if source else "Missing source") + " → " + (target.definition.display_name if target else "Missing receiver")

func open_context(source_id: String, target_id: String, event: String, index: int, at: Vector2) -> void:
	clear_context()
	var source := build.find_piece(source_id)
	var target := build.find_piece(target_id)
	if not source or not target: return
	context_source = source_id
	context_target = target_id
	context_index = index
	context_event = event
	context_action = source.configuration.links[index].action if index >= 0 else ""
	context_anchor = at
	%Relationship.text = describe(source_id, target_id)
	%Apply.text = "Apply" if index >= 0 else "Connect"
	%Apply.disabled = not permitted(source)
	%Remove.visible = index >= 0
	%Remove.disabled = not permitted(source)
	%Dismiss.text = "Close" if index >= 0 else "Cancel"
	choices(%Events, source.compatible_events(target), context_event)
	if %Events.item_count > 0: context_event = %Events.get_item_metadata(%Events.selected)
	refresh_actions()
	%Context.show()
	%Hint.hide()

func choices(control: OptionButton, values: Array, selected: String) -> void:
	control.clear()
	for value: String in values:
		var piece := build.find_piece(context_source if control == %Events else context_target)
		var state_port: bool = piece.output_ports[value].state_outputs.has(value) if control == %Events else piece.input_ports[value].state_inputs.has(value)
		control.add_item(value.replace("_", " ").capitalize())
		control.set_item_metadata(control.item_count - 1, value)
		control.get_popup().set_item_tooltip(control.item_count - 1, "Persistent state" if state_port else "Event pulse")
		if value == selected: control.select(control.item_count - 1)
	control.disabled = values.size() <= 1

func refresh_actions() -> void:
	var source := build.find_piece(context_source)
	var target := build.find_piece(context_target)
	if not source or not target: return
	choices(%Actions, source.compatible_actions(target, context_event), context_action)
	context_action = %Actions.get_item_metadata(%Actions.selected) if %Actions.item_count > 0 else ""
	%Apply.disabled = not permitted(source) or context_action.is_empty()

func finish_drag(at: Vector2, over_ui: bool = false) -> void:
	var receiver := receiver_at(at) if not over_ui else {}
	if valid_receiver(receiver):
		var source_id: String = dragging.source
		var source := build.find_piece(source_id)
		var target := build.find_piece(receiver.source)
		var events := source.compatible_events(target)
		var event: String = events[0]
		var actions := source.compatible_actions(target, event)
		if events.size() == 1 and actions.size() == 1:
			var link := {"event": event, "target": receiver.source, "action": actions[0]}
			if build.edit_link(source_id, -1, link): flash(source_id, link)
		else: open_context(source_id, receiver.source, event, -1, at)
	dragging.clear()

func apply_connection() -> void:
	var source_id := context_source
	var link := {"event": context_event, "target": context_target, "action": context_action}
	if build.edit_link(source_id, context_index, link):
		flash(source_id, link)
		clear_context()
	else: build.show_status("Connection unchanged · check permissions or an existing matching connection")

func flash(source_id: String, link: Dictionary) -> void:
	var source := build.find_piece(source_id)
	var target := build.find_piece(link.target)
	confirmation = curve(port_position(source, true), port_position(target, false))
	confirmation_until = Time.get_ticks_msec() + 250

func escape() -> void:
	if not dragging.is_empty(): dragging.clear()
	elif %Context.visible: clear_context()
	else: set_tool(false)

func _input(event: InputEvent) -> void:
	if not build: return
	if event is InputEventMouseMotion or event is InputEventMouseButton: pointer = event.position
	if not build.enabled or simulation.state != SimulationManager.State.BUILD or not (build.connect_mode or %Context.visible): return
	if event is InputEventKey and event.pressed and not event.echo and not ConstructionInput.typing(get_viewport()):
		if event.is_action_pressed("build_cancel", false, true):
			escape()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("build_remove", false, true):
			if %Context.visible and context_index >= 0 and build.edit_link(context_source, context_index): clear_context()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("build_undo", false, true):
			clear_interaction()
			build.undo()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("build_redo", false, true):
			clear_interaction()
			build.redo()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("build_frame_all", false, true):
			build.frame_all()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("build_select_tool", false, true):
			set_tool(false)
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not dragging.is_empty():
		finish_drag(event.position, get_viewport().gui_get_hovered_control() != null)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not build or not build.enabled or simulation.state != SimulationManager.State.BUILD or not (build.connect_mode or overlay_enabled): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and build.camera.drag_button == 0:
		refresh_projection()
		var handle := handle_at(event.position) if build.connect_mode else {}
		clear_context()
		if build.connect_mode and not handle.is_empty() and handle.output and handle.allowed:
			dragging = handle.duplicate()
		else:
			var wire := wire_at(event.position)
			if not wire.is_empty() and (build.connect_mode or not build.pick_piece(event.position)):
				open_context(wire.source, wire.target, wire.link.event, wire.index, event.position)
				get_viewport().set_input_as_handled()
		if not dragging.is_empty(): get_viewport().set_input_as_handled()

func ink(token: String) -> Color:
	return get_theme_color(token, &"MechanismWiring")

func draw_wire(points: PackedVector2Array, color: Color, width: float = 2.5) -> void:
	draw_polyline(points, ink("backdrop"), width + 2, true)
	draw_polyline(points, color, width, true)
	for i in [10, 21, 30]:
		var direction := (points[i+1] - points[i-1]).normalized()
		var normal := direction.orthogonal()
		var tip := points[i] + direction * 7
		draw_polyline(PackedVector2Array([tip - direction * 10 + normal * 6, tip, tip - direction * 10 - normal * 6]), color, width, true)
	draw_circle(points[0], 5, color, true, -1, true)
	draw_circle(points[-1], 6, color, false, 2.0, true)

func _draw() -> void:
	if not build or not build.enabled or simulation.state != SimulationManager.State.BUILD or not (overlay_enabled or build.connect_mode): return
	for wire in wires:
		var focused: bool = wire == hovered_wire or (wire.source == context_source and wire.index == context_index)
		var related := build.selection.any(func(piece): return piece.instance_id in [wire.source, wire.target])
		var color := ink("selected" if focused or related else "wire")
		if not build.selection.is_empty() and not related and not focused: color.a = 0.58
		draw_wire(wire.points, color, 3.5 if focused or related else 2.5)
	if Time.get_ticks_msec() < confirmation_until and not confirmation.is_empty(): draw_wire(confirmation, ink("selected"), 2.5)
	if build.connect_mode:
		for receiver in receivers:
			var bounds := ConstructionSelection.projected_bounds(receiver, build.camera).grow(8)
			var color := ink("selected" if not hovered_handle.is_empty() and hovered_handle.source == receiver.instance_id else "output")
			var fill := color
			fill.a = 0.1
			draw_rect(bounds, fill, true)
			draw_rect(bounds, color, false, 2.0)
		for handle in handles:
			if covered(handle.point): continue
			var point: Vector2 = handle.point
			var color := ink("output" if handle.output else "input")
			var radius := 15.0
			if handle == hovered_handle: radius = 18
			if not dragging.is_empty():
				if handle.output: color = ink("invalid")
				elif build.find_piece(handle.source) in receivers: radius = 18; color = ink("output")
				else: color = ink("invalid")
			elif not handle.allowed: color = ink("invalid")
			draw_circle(point, radius + 2, ink("backdrop"), true, -1, true)
			if handle.output:
				draw_circle(point, radius, color, false, 2.0, true)
				draw_colored_polygon(PackedVector2Array([point + Vector2(-4,-6), point + Vector2(6,0), point + Vector2(-4,6)]), color)
			else:
				draw_polyline(PackedVector2Array([point + Vector2(0,-radius), point + Vector2(radius,0), point + Vector2(0,radius), point + Vector2(-radius,0), point + Vector2(0,-radius)]), color, 1.5, true)
		if not dragging.is_empty():
			var source := build.find_piece(dragging.source)
			if source:
				var start := port_position(source, true)
				draw_wire(curve(start, hovered_handle.point if valid_receiver(hovered_handle) else pointer), ink("selected" if valid_receiver(hovered_handle) else "output"), 2)

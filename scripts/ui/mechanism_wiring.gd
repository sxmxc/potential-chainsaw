extends Control

## Presentation only: relationships are read from BuildingPiece.configuration.
## World-space conduits and terminals share their projection with pointer picking.
const TERMINAL: PackedScene = preload("res://scenes/ui/widgets/wiring_terminal.tscn")
const INPUT_SNAP_RADIUS := 16.0
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
var confirmation_source: String = ""
var confirmation_target: String = ""
var confirmation_until: int = 0
var context_motion: UIMotion
var conduits: Dictionary[String, WiringConduit] = {}
var terminals: Dictionary[String, Node3D] = {}
var preview_conduit: WiringConduit

func _ready() -> void:
	context_motion = UIMotion.attach(%Context, Vector2.ZERO, UIMotion.SURFACE_SCALE)
	preview_conduit = WiringConduit.new()
	$Network.add_child(preview_conduit)
	preview_conduit.hide()

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
	build.selection_changed.connect(func(_piece): clear_interaction())
	build.options_changed.connect(func():
		if not build.connect_mode: clear_interaction())
	simulation.state_changed.connect(func(state, _message):
		if state != SimulationManager.State.BUILD:
			clear_interaction())

func set_tool(active: bool) -> void:
	clear_interaction()
	build.set_connect_mode(active)
	if active: build.show_status("Drag from an output to an input · Esc cancels")

func toggle_overlay() -> void:
	overlay_enabled = not overlay_enabled
	build.options_changed.emit()

func clear_context() -> void:
	context_motion.set_open(false)
	context_source = ""
	context_target = ""
	context_index = -1

func clear_interaction() -> void:
	dragging.clear()
	hovered_handle.clear()
	hovered_wire.clear()
	clear_context()
	%Hint.hide()
	confirmation_source = ""
	confirmation_target = ""

func permitted(piece: BuildingPiece) -> bool:
	return build.enabled and (not build.rules or build.rules.permits(piece.instance_id, "configure"))

func covered(point: Vector2) -> bool:
	for control in exclusions:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(point): return true
	return %Context.visible and %Context.get_global_rect().has_point(point)

func visual_piece(piece: BuildingPiece) -> BuildingPiece:
	var visual := piece
	var moving_index := build.moving_group.find(piece)
	if moving_index >= 0 and moving_index < build.preview.get_child_count(): visual = build.preview.get_child(moving_index) as BuildingPiece
	return visual

func anchor(piece: BuildingPiece) -> Vector3:
	var visual := visual_piece(piece)
	var bounds := visual.definition.bounds
	return visual.global_transform * (bounds.get_center() + Vector3.UP * bounds.size.y * 0.5)

func port_world(piece: BuildingPiece, output: bool) -> Vector3:
	# Terminal height matches the authored housing. Paired roles sit one housing apart.
	var paired := not piece.input_ports.is_empty() and not piece.output_ports.is_empty()
	var side := visual_piece(piece).global_basis.x.normalized() * (0.23 if output else -0.23) if paired else Vector3.ZERO
	return anchor(piece) + Vector3.UP * 0.26 + side

func port_position(piece: BuildingPiece, output: bool) -> Vector2:
	return build.camera.unproject_position(port_world(piece, output))

func receiver_at(point: Vector2) -> Dictionary:
	if dragging.is_empty() or covered(point): return {}
	var found: Dictionary = {}
	var distance := INPUT_SNAP_RADIUS
	for handle in handles:
		if handle.output or covered(handle.point) or build.find_piece(handle.source) not in receivers: continue
		var pixels: float = point.distance_to(handle.point)
		if pixels >= distance: continue
		distance = pixels
		found = handle
	return found

func palette(mesh_instance: MeshInstance3D) -> void:
	mesh_instance.set_instance_shader_parameter("source_tint", ink("output"))
	mesh_instance.set_instance_shader_parameter("target_tint", ink("input"))
	mesh_instance.set_instance_shader_parameter("highlight", ink("selected"))

func terminal_key(piece_id: String, output: bool) -> String:
	return piece_id + (":out" if output else ":in")

func show_terminal(piece: BuildingPiece, output: bool, used: Array[String]) -> void:
	var key := terminal_key(piece.instance_id, output)
	used.append(key)
	if not terminals.has(key):
		var terminal := TERMINAL.instantiate() as Node3D
		$Network.add_child(terminal)
		terminal.get_node("Sender").visible = output
		terminal.get_node("Receiver").visible = not output
		terminals[key] = terminal
	terminals[key].position = port_world(piece, output)

func refresh_projection() -> void:
	handles.clear()
	wires.clear()
	receivers.clear()
	var used_conduits: Array[String] = []
	var used_terminals: Array[String] = []
	var source := build.find_piece(dragging.get("source", ""))
	var selected_ids: Array[String] = []
	for selected_piece in build.selection:
		if not selected_piece.input_ports.is_empty() or not selected_piece.output_ports.is_empty():
			selected_ids.append(selected_piece.instance_id)
	for piece in build.pieces:
		if build.camera.is_position_behind(anchor(piece)): continue
		if source and not source.compatible_events(piece).is_empty(): receivers.append(piece)
		if build.connect_mode:
			if not piece.output_ports.is_empty():
				handles.append({"source": piece.instance_id, "output": true, "point": port_position(piece, true), "allowed": permitted(piece)})
				show_terminal(piece, true, used_terminals)
			if not piece.input_ports.is_empty():
				handles.append({"source": piece.instance_id, "output": false, "point": port_position(piece, false), "allowed": true})
				show_terminal(piece, false, used_terminals)
		var links: Array = piece.configuration.get("links", [])
		for i in links.size():
			var link: Dictionary = links[i]
			var target := build.find_piece(link.get("target", ""))
			if not target or target.input_ports.is_empty() or build.camera.is_position_behind(anchor(target)): continue
			if not selected_ids.is_empty() and piece.instance_id not in selected_ids and target.instance_id not in selected_ids: continue
			var key := piece.instance_id + ":" + str(i)
			used_conduits.append(key)
			if not conduits.has(key):
				conduits[key] = WiringConduit.new()
				$Network.add_child(conduits[key])
				palette(conduits[key])
			var conduit := conduits[key]
			conduit.route(port_world(piece, true), port_world(target, false), i)
			wires.append({"source": piece.instance_id, "target": target.instance_id, "index": i, "link": link, "points": conduit.project(build.camera), "visual": conduit})
			show_terminal(piece, true, used_terminals)
			show_terminal(target, false, used_terminals)
	for key in conduits.keys():
		if key not in used_conduits:
			conduits[key].free()
			conduits.erase(key)
	for key in terminals.keys():
		if key not in used_terminals:
			terminals[key].free()
			terminals.erase(key)

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

func _process(delta: float) -> void:
	if not build: return
	var shown := is_visible_in_tree() and simulation.state == SimulationManager.State.BUILD and build.enabled and (overlay_enabled or build.connect_mode)
	$Network.visible = shown
	if not shown:
		if not build.enabled or not is_visible_in_tree(): clear_interaction()
		clear_network()
		%Hint.hide()
		%Context.hide()
		preview_conduit.hide()
		queue_redraw()
		return
	if not build.connect_mode and not dragging.is_empty(): clear_interaction()
	refresh_projection()
	hovered_handle = receiver_at(pointer) if not dragging.is_empty() else (handle_at(pointer) if build.connect_mode and not covered(pointer) else {})
	hovered_wire = wire_at(pointer) if hovered_handle.is_empty() and not covered(pointer) else {}
	var hint := ""
	if not hovered_handle.is_empty():
		var piece := build.find_piece(hovered_handle.source)
		hint = "Send ▶ · " + ", ".join(piece.output_ports.keys().map(func(event): return readable(event))) if hovered_handle.output else "Receive ◇ · " + ", ".join(piece.input_ports.keys().map(func(action): return readable(action)))
		if hovered_handle.output and not hovered_handle.allowed: hint += " · Locked"
		elif not dragging.is_empty() and hovered_handle.output: hint = "Drop onto an input"
	elif not hovered_wire.is_empty():
		hint = describe(hovered_wire.source, hovered_wire.target) + "\n" + readable(hovered_wire.link.event) + " → " + readable(hovered_wire.link.action)
	%Hint.visible = not hint.is_empty() and not %Context.visible and build.camera.drag_button == 0
	%Text.text = hint
	%Hint.reset_size()
	%Hint.position = bounded(pointer + Vector2(16, 20), %Hint.size)
	if %Context.visible:
		%Context.reset_size()
		%Context.position = bounded(context_anchor + Vector2(16, 16), %Context.size)
	refresh_visuals(delta)
	queue_redraw()

func clear_network() -> void:
	handles.clear()
	wires.clear()
	receivers.clear()
	for conduit in conduits.values(): conduit.free()
	conduits.clear()
	for terminal in terminals.values(): terminal.free()
	terminals.clear()

func refresh_visuals(delta: float) -> void:
	for wire in wires:
		var focused: bool = wire == hovered_wire or (wire.source == context_source and wire.index == context_index)
		var related := build.selection.any(func(piece): return piece.instance_id in [wire.source, wire.target])
		var confirmed: bool = Time.get_ticks_msec() < confirmation_until and wire.source == confirmation_source and wire.target == confirmation_target
		var conduit: WiringConduit = wire.visual
		conduit.emphasize(focused or related or confirmed, delta)
	for key in terminals:
		var terminal := terminals[key]
		var output: bool = terminal.get_node("Sender").visible
		var piece_id := key.trim_suffix(":out" if output else ":in")
		var piece := build.find_piece(piece_id)
		var hovered: bool = not hovered_handle.is_empty() and hovered_handle.source == piece_id and hovered_handle.output == output
		var compatible: bool = not dragging.is_empty() and not output and piece in receivers
		var focused := hovered or compatible or piece in build.selection or piece_id in [context_source, context_target]
		var allowed := permitted(piece) if output else true
		if not dragging.is_empty(): allowed = compatible or (output and piece_id == dragging.source)
		var branch: Node3D = terminal.get_node("Sender" if output else "Receiver")
		for part: MeshInstance3D in branch.get_children():
			part.set_instance_shader_parameter("tint", ink("output" if output else "input"))
			part.set_instance_shader_parameter("highlight", ink("selected"))
			part.set_instance_shader_parameter("focus", 1.0 if focused else 0.0)
			part.set_instance_shader_parameter("available", 1.0 if allowed else 0.0)
	var pending := context_index == -1 and not context_source.is_empty() and not context_target.is_empty()
	preview_conduit.visible = not dragging.is_empty() or pending
	if preview_conduit.visible:
		var source := build.find_piece(context_source if pending else dragging.source)
		var target := build.find_piece(context_target) if pending else null
		if not source or (pending and not target):
			preview_conduit.hide()
			return
		var start := port_world(source, true)
		var finish: Vector3
		if pending:
			finish = port_world(target, false)
		elif valid_receiver(hovered_handle):
			finish = port_world(build.find_piece(hovered_handle.source), false)
		else:
			# Cursor follows the source depth until a real receiver supplies its elevation.
			var depth := - (build.camera.get_camera_transform().affine_inverse() * start).z
			finish = build.camera.project_position(pointer, depth)
		preview_conduit.route(start, finish)
		palette(preview_conduit)
		preview_conduit.emphasize(pending or valid_receiver(hovered_handle), delta)

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
	context_motion.set_open(true)
	%Hint.hide()

func choices(control: OptionButton, values: Array, selected: String) -> void:
	control.clear()
	for value: String in values:
		var piece := build.find_piece(context_source if control == %Events else context_target)
		var state_port: bool = piece.output_ports[value].state_outputs.has(value) if control == %Events else piece.input_ports[value].state_inputs.has(value)
		control.add_item(readable(value))
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
	if not source or not target: return
	confirmation_source = source_id
	confirmation_target = link.target
	confirmation_until = Time.get_ticks_msec() + 650

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

func _draw() -> void:
	if not build or not build.enabled or simulation.state != SimulationManager.State.BUILD or not build.connect_mode: return
	var font := get_theme_default_font()
	for handle in handles:
		if covered(handle.point): continue
		var point: Vector2 = handle.point
		var color := ink("output" if handle.output else "input")
		var hovered: bool = not hovered_handle.is_empty() and handle.source == hovered_handle.source and handle.output == hovered_handle.output
		var origin: bool = not dragging.is_empty() and handle.output and handle.source == dragging.source
		var inspecting: bool = (handle.output and handle.source == context_source) or (not handle.output and handle.source == context_target)
		var focused: bool = hovered or origin or inspecting
		var compatible := valid_receiver(handle)
		if not focused and not compatible: continue
		if focused: color = ink("selected")
		var available: bool = handle.allowed
		if not dragging.is_empty(): available = (not handle.output and build.find_piece(handle.source) in receivers) or (handle.output and handle.source == dragging.source)
		if not available: color = ink("invalid")
		if focused:
			var caption := "Output" if handle.output else "Input"
			if not handle.allowed: caption += " · Locked"
			var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
			var baseline := point + Vector2(-text_size.x * 0.5, 27)
			draw_string_outline(font, baseline, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, ink("backdrop"))
			draw_string(font, baseline, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		if focused or compatible:
			draw_arc(point, 20, PI * 0.12, PI * 0.88, 24, color, 2, true)
			draw_arc(point, 20, PI * 1.12, PI * 1.88, 24, color, 2, true)

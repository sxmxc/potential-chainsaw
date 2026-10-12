class_name BuildManager
extends Node3D

signal changed
signal selection_changed(piece: TrackPiece)
signal status_changed(message: String)
signal options_changed
signal marquee_changed(rectangle: Rect2, active: bool)
signal extension_requested(target: Dictionary, screen: Vector2)

const PIECE_SCENE = preload("res://scenes/track_piece.tscn")
const SupportGeometry = preload("res://scripts/construction/support_geometry.gd")
@export var drag_threshold: float = 7.0
@export_range(12,96,1) var connector_target_radius: float = 32.0
var rules: PuzzleRules
var catalog: PieceCatalog
var camera: ConstructionCamera
var snap = SnapManager.new()
var history = BuildHistory.new()
var pieces: Array[TrackPiece] = []
var selection: Array[TrackPiece] = []
var selected: TrackPiece
var chosen: PieceDefinition
var ghost: TrackPiece
var ghosts: Array[TrackPiece] = []
var moving: TrackPiece
var moving_group: Array[TrackPiece] = []
var preview_items: Array[Dictionary] = []
var preview_ports: Array[Dictionary] = []
var operation: String = ""
var turn: int = 0
var height: float = 0
var movement_height: float = 0
var pointer_offset: Vector3 = Vector3.ZERO
var grid_visible: bool = true
var snapping: bool = true
var enabled: bool = false
var proposed: Transform3D = Transform3D.IDENTITY
var valid: bool = false
var is_snapped: bool = false
var validation_message: String = ""
var grid_mesh: MeshInstance3D
var connector_markers: Node3D
var targets: Array[Dictionary] = []
var candidates: Array[Dictionary] = []
var candidate_key: String = ""
var sticky_target: String = ""
var forced_target: Dictionary = {}
var next_uid: int = 1
var dirty: bool = false
var cursor_position: Vector2
var pointer_down: bool = false
var press_position: Vector2
var press_piece: TrackPiece
var additive: bool = false
var box_active: bool = false
var direct_drag: bool = false
var last_status: String = ""

func _ready() -> void:
	snap.target_radius=connector_target_radius
	cursor_position=get_viewport().get_mouse_position()
	grid_mesh=MeshInstance3D.new()
	add_child(grid_mesh)
	connector_markers=Node3D.new()
	add_child(connector_markers)
	refresh_grid()

func snapshot() -> Array:
	var result: Array = []
	for piece in pieces: result.append(piece.serialize())
	return result

func restore(data: Array) -> void:
	cancel()
	snap.sample_indices.clear()
	select(null)
	for piece in pieces:
		remove_child(piece)
		piece.queue_free()
	pieces.clear()
	for item in data:
		var definition=catalog.get_piece(item.piece)
		if not definition: continue
		spawn(definition,Transform3D(Basis(Vector3.UP,int(item.rotation)*PI/2),Vector3(item.position[0],item.position[1],item.position[2])),item.uid,item.get("config",{}))
	refresh_connectors()
	changed.emit()

func spawn(definition: PieceDefinition, placement: Transform3D, uid: String = "", config: Dictionary = {}) -> TrackPiece:
	var piece=PIECE_SCENE.instantiate() as TrackPiece
	piece.instance_id=uid if not uid.is_empty() else "piece-%d-%d" % [Time.get_ticks_usec(),next_uid]
	next_uid+=1
	add_child(piece)
	piece.setup(definition,false,config)
	piece.transform=placement
	pieces.append(piece)
	return piece

func choose(definition: PieceDefinition) -> void:
	if not enabled: return
	if rules and rules.remaining(String(definition.id), snapshot()) <= 0:
		show_status("No inventory remaining")
		return
	cancel()
	select(null)
	chosen=definition
	turn=0
	operation="place"
	preview_items=[{"definition":definition,"local":Transform3D.IDENTITY,"config":{}}]
	movement_height=height
	make_ghost()
	if definition.behavior=="resizable_support": resize_support_preview(maxf(SupportGeometry.MIN_HEIGHT,height))
	options_changed.emit()

func choose_extension(definition: PieceDefinition, target: Dictionary) -> void:
	choose(definition)
	forced_target=target
	sticky_target=target.key
	update_preview()

func make_ghost() -> void:
	preview_ports=snap.boundary_sources(preview_items)
	for item in preview_items:
		var preview=PIECE_SCENE.instantiate() as TrackPiece
		add_child(preview)
		preview.setup(item.definition,true,item.config)
		preview.visible=false
		ghosts.append(preview)
	ghost=ghosts[0]
	refresh_connectors()

func select(piece: TrackPiece) -> void:
	var values: Array[TrackPiece] = []
	if ConstructionSelection.editable(piece): values.append(piece)
	set_selection(values)

func set_selection(values: Array[TrackPiece]) -> void:
	for piece in selection:
		if is_instance_valid(piece): piece.tint(Color.WHITE,false)
	selection.clear()
	for piece in values:
		if ConstructionSelection.editable(piece) and piece not in selection: selection.append(piece)
	selected=selection[0] if not selection.is_empty() else null
	for piece in selection: piece.tint(Color(1,0.78,0.25,0.4))
	selection_changed.emit(selected)
	refresh_connectors()

func select_connected(piece: TrackPiece) -> void:
	set_selection(ConstructionSelection.connected(piece,pieces,snap))
	show_status("%d connected pieces · drag to move the assembly" % selection.size())

func select_all() -> void:
	set_selection(pieces)

func cancel() -> void:
	for preview in ghosts:
		if is_instance_valid(preview): preview.queue_free()
	ghosts.clear()
	ghost=null
	for piece in moving_group:
		if is_instance_valid(piece): piece.visible=true
	moving_group.clear()
	moving=null
	chosen=null
	preview_items.clear()
	preview_ports.clear()
	operation=""
	forced_target.clear()
	candidates.clear()
	candidate_key=""
	sticky_target=""
	pointer_offset=Vector3.ZERO
	pointer_down=false
	direct_drag=false
	box_active=false
	marquee_changed.emit(Rect2(),false)
	refresh_connectors()
	options_changed.emit()

func height_step(fine: bool = false) -> float:
	return snap.vertical_step if fine else 0.5

func set_height(value: float) -> void:
	height=clampf(snappedf(value,snap.vertical_step),0,30)
	if chosen:
		movement_height=height
		forced_target.clear()
		if operation=="place" and chosen.behavior=="resizable_support": resize_support_preview(maxf(SupportGeometry.MIN_HEIGHT,height))
	refresh_grid()
	options_changed.emit()

func resize_support_preview(value: float) -> void:
	if ghosts.is_empty(): return
	var config=ghost.configuration.duplicate(true)
	config.support_height=value
	config=SupportGeometry.normalized(config)
	if config==ghost.configuration: return
	ghost.apply_configuration(config)
	preview_items[0].definition=ghost.definition
	preview_items[0].config=ghost.configuration.duplicate(true)

func refresh_grid() -> void:
	if not grid_mesh: return
	var mesh=ImmediateMesh.new()
	var material=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(0.65,0.76,0.74,0.028)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,material)
	for i in range(-48,49):
		mesh.surface_add_vertex(Vector3(i,0,-48))
		mesh.surface_add_vertex(Vector3(i,0,48))
		mesh.surface_add_vertex(Vector3(-48,0,i))
		mesh.surface_add_vertex(Vector3(48,0,i))
	mesh.surface_end()
	grid_mesh.mesh=mesh
	grid_mesh.position.y=height+0.006
	grid_mesh.visible=grid_visible and enabled

func refresh_connectors() -> void:
	if not connector_markers: return
	for child in connector_markers.get_children():
		connector_markers.remove_child(child)
		child.queue_free()
	targets=snap.exposed(pieces,moving_group)
	if not snapping or not enabled: return
	for target in targets:
		if not chosen and target.piece not in selection: continue
		var marker=MeshInstance3D.new()
		var sphere=SphereMesh.new()
		sphere.radius=0.065
		sphere.height=0.13
		marker.mesh=sphere
		marker.position=target.point
		var material=StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color=Color("80b9af")
		marker.material_override=material
		marker.set_meta("target_key",target.key)
		connector_markers.add_child(marker)

func _process(_delta: float) -> void:
	if not enabled: return
	if is_instance_valid(ghost): update_preview()
	update_marker_feedback()

func plane_point(screen: Vector2, elevation: float) -> Variant:
	var origin=camera.project_ray_origin(screen)
	var direction=camera.project_ray_normal(screen)
	if abs(direction.y)<0.001: return null
	var distance=(elevation-origin.y)/direction.y
	return origin+direction*distance if distance>=0 else null

func update_preview() -> void:
	if not chosen or ghosts.is_empty(): return
	if get_viewport().gui_get_hovered_control()!=null or camera.drag_button!=0:
		for preview in ghosts: preview.hide()
		return
	var preview_height=movement_height
	var support_placement=operation=="place" and chosen.behavior=="resizable_support"
	if support_placement:
		var under_cursor=pick_piece(cursor_position)
		if under_cursor and under_cursor.definition.behavior in ["static","start","finish"] and not under_cursor.definition.connectors.is_empty():
			var level=under_cursor.definition.connectors[0].position.y
			var flat=true
			for port in under_cursor.definition.connectors:
				if absf(port.position.y-level)>0.02: flat=false
			if flat: preview_height=maxf(SupportGeometry.MIN_HEIGHT,under_cursor.position.y+level-0.25)
		resize_support_preview(maxf(SupportGeometry.MIN_HEIGHT,preview_height))
	var point=plane_point(cursor_position,preview_height)
	var free_position: Vector3 = snap.grid_position(point+pointer_offset) if point!=null else proposed.origin
	if operation=="place": free_position.y=height
	else: free_position.y=movement_height
	if support_placement: free_position.y=0
	proposed=Transform3D(Basis(Vector3.UP,turn*PI/2),free_position)
	candidates=snap.screen_candidates(preview_items,preview_ports,targets,camera,cursor_position,pieces,moving_group,sticky_target,forced_target,proposed) if snapping else []
	is_snapped=not candidates.is_empty()
	if is_snapped:
		var candidate: Dictionary=candidates[0]
		for value in candidates:
			if value.key==candidate_key and (value.error.is_empty() or not candidate.error.is_empty()): candidate=value; break
		proposed=candidate.transform
		candidate_key=candidate.key
		sticky_target=candidate.target.key
		validation_message=candidate.error
	else:
		candidate_key=""
		sticky_target=""
		validation_message=snap.validate_group(preview_items,proposed,pieces,moving_group)
		if point==null:
			for preview in ghosts: preview.hide()
			return
	if validation_message.is_empty() and rules: validation_message=rules.validate(proposed_snapshot())
	valid=validation_message.is_empty()
	apply_preview()
	var message="✕  "+validation_message if not valid else ("Connected · click to attach" if is_snapped else "Click to place · R rotate · right-click cancel")
	if direct_drag: message="Release to move · Esc cancel" if valid else "✕  "+validation_message
	if is_snapped and candidates.size()>1: message+=" · Tab: attachment %d/%d" % [candidate_index()+1,candidates.size()]
	show_status(message)

func apply_preview() -> void:
	for index in ghosts.size():
		ghosts[index].transform=proposed*preview_items[index].local
		ghosts[index].visible=true
		ghosts[index].tint(Color(1,0.29,0.32,0.55) if not valid else (Color(0.2,0.9,0.68,0.4) if is_snapped else Color(0.38,0.72,1,0.35)))

func candidate_index() -> int:
	for i in candidates.size():
		if candidates[i].key==candidate_key: return i
	return 0

func cycle_candidate() -> void:
	if candidates.size()<2: return
	candidate_key=candidates[(candidate_index()+1)%candidates.size()].key
	update_preview()

func update_marker_feedback() -> void:
	for marker in connector_markers.get_children():
		var key: String=marker.get_meta("target_key")
		var active: bool=key==sticky_target
		var hovered: bool=false
		if not camera.is_position_behind(marker.position): hovered=camera.unproject_position(marker.position).distance_to(cursor_position)<snap.target_radius
		marker.scale=Vector3.ONE*(1.6 if active else (1.3 if hovered else 1.0))
		marker.material_override.albedo_color=Color("55e4ba") if active else (Color("ffd17a") if hovered else Color("80b9af"))

func commit() -> void:
	if not is_instance_valid(ghost) or not ghost.visible or not valid: return
	if rules:
		var rule_error = rules.validate(proposed_snapshot())
		if not rule_error.is_empty(): show_status(rule_error); return
	var before=snapshot()
	var mode=operation
	var edited: Array[TrackPiece] = []
	for index in preview_items.size():
		var item: Dictionary=preview_items[index]
		var placement: Transform3D=proposed*item.local
		if mode=="move":
			moving_group[index].transform=placement
			edited.append(moving_group[index])
		else:
			var piece=spawn(item.definition,placement,"",item.config)
			edited.append(piece)
	if mode == "duplicate":
		var duplicated_ids: Dictionary = {}
		for index in edited.size(): duplicated_ids[preview_items[index].get("uid", "")] = edited[index].instance_id
		for piece in edited:
			for link in piece.configuration.get("links", []):
				if duplicated_ids.has(link.target): link.target = duplicated_ids[link.target]
	if mode!="place":
		cancel()
		set_selection(edited)
	else:
		forced_target.clear()
		candidate_key=""
		sticky_target=""
		refresh_connectors()
	record(before,"Move assembly" if mode=="move" else ("Duplicate assembly" if mode=="duplicate" else "Place"))

func record(before: Array, label: String) -> void:
	if rules:
		var problem = rules.validate(snapshot())
		if not problem.is_empty():
			restore(before)
			show_status("Blocked: " + problem)
			return
	history.record(before,snapshot(),label)
	dirty=true
	refresh_connectors()
	changed.emit()

func configure_selected(config: Dictionary, label: String) -> bool:
	if not enabled or selection.size()!=1 or chosen: return false
	if rules and not rules.permits(selected.instance_id, "configure"):
		show_status("Configuration is locked")
		return false
	var before=snapshot()
	var previous=selected.configuration.duplicate(true)
	snap.sample_indices.erase(selected.definition.get_instance_id())
	selected.apply_configuration(config)
	var problem=snap.validate(selected.definition,selected.transform,pieces,selected) if selected.definition.behavior in ["elevator", "resizable_support"] else ""
	if not problem.is_empty():
		selected.apply_configuration(previous)
		show_status("✕  "+problem)
		selection_changed.emit(selected)
		return false
	if rules:
		var rule_error = rules.validate(snapshot())
		if not rule_error.is_empty():
			selected.apply_configuration(previous)
			show_status(rule_error)
			selection_changed.emit(selected)
			return false
	if selected.configuration==previous: return true
	selected.tint(Color(1,0.78,0.25,0.4))
	record(before,label)
	selection_changed.emit(selected)
	return true

func delete_selected() -> void:
	if not enabled or selection.is_empty() or not selection_permitted("remove"): return
	cancel()
	var before=snapshot()
	var removing=selection.duplicate()
	select(null)
	for piece in removing:
		pieces.erase(piece)
		remove_child(piece)
		piece.queue_free()
	var remaining_ids: Array[String] = []
	for piece in pieces: remaining_ids.append(piece.instance_id)
	for piece in pieces:
		if not piece.configuration.has("links"): continue
		piece.configuration.links = piece.configuration.links.filter(func(link): return link.get("target", "") in remaining_ids)
	record(before,"Delete assembly")

func selection_pivot() -> Vector3:
	# The first selected piece is a stable visible anchor, including measured slope offsets.
	return selected.position if selected else Vector3.ZERO

func move_selected(duplicate_piece: bool = false) -> void:
	if not enabled or selection.is_empty(): return
	if not selection_permitted("duplicate" if duplicate_piece else "move"): return
	cancel()
	var pivot=selection_pivot()
	chosen=selected.definition
	turn=roundi(selected.rotation.y/(PI/2))
	var frame=Transform3D(Basis(Vector3.UP,turn*PI/2),pivot)
	movement_height=pivot.y
	proposed=frame
	operation="duplicate" if duplicate_piece else "move"
	for piece in selection:
		preview_items.append({"definition":piece.definition,"local":frame.affine_inverse()*piece.transform,"config":piece.configuration.duplicate(true),"uid":piece.instance_id})
		if not duplicate_piece:
			moving_group.append(piece)
			piece.hide()
	moving=selected if not duplicate_piece else null
	make_ghost()
	options_changed.emit()

func rotate_piece() -> void:
	if not enabled: return
	if chosen:
		if is_snapped and candidates.size()>1: cycle_candidate()
		else:
			turn=posmod(turn+1,4)
			forced_target.clear()
			candidate_key=""
	elif selected:
		if not selection_permitted("rotate"): return
		var pivot=selection_pivot()
		var rotation_transform=Transform3D(Basis(Vector3.UP,PI/2),pivot)
		var items: Array[Dictionary] = []
		for piece in selection: items.append({"definition":piece.definition,"local":Transform3D(piece.basis,piece.position-pivot)})
		var error=snap.validate_group(items,rotation_transform,pieces,selection)
		if not error.is_empty(): show_status("✕  "+error); return
		var before=snapshot()
		for index in selection.size(): selection[index].transform=rotation_transform*items[index].local
		record(before,"Rotate assembly")
		selection_changed.emit(selected)

func elevate_selected(delta: float) -> void:
	if not selected or not enabled or not selection_permitted("move"): return
	if selection.size()==1 and selected.support_component:
		var config=selected.configuration.duplicate(true)
		config.support_height=float(config.support_height)+delta
		configure_selected(config,"Support height")
		return
	var items: Array[Dictionary] = []
	for piece in selection: items.append({"definition":piece.definition,"local":piece.transform})
	var placement=Transform3D(Basis.IDENTITY,Vector3(0,delta,0))
	var error=snap.validate_group(items,placement,pieces,selection)
	if not error.is_empty(): show_status("✕  "+error); return
	var before=snapshot()
	for piece in selection: piece.position.y+=delta
	record(before,"Raise/lower assembly")
	selection_changed.emit(selected)

func undo() -> void:
	if not enabled or history.cursor==0: return
	restore_history(history.undo())
	dirty=true

func redo() -> void:
	if not enabled or history.cursor>=history.commands.size(): return
	restore_history(history.redo())
	dirty=true

func restore_history(data: Array) -> void:
	var ids: Array[String] = []
	var previous: Array[String] = []
	for piece in selection: ids.append(piece.instance_id)
	for piece in pieces: previous.append(piece.instance_id)
	for item in data:
		if item.uid not in previous: ids.append(item.uid)
	restore(data)
	var restored: Array[TrackPiece] = []
	for piece in pieces:
		if piece.instance_id in ids: restored.append(piece)
	set_selection(restored)

func frame_all() -> void:
	frame_pieces(pieces)

func frame_pieces(values: Array) -> void:
	if values.is_empty(): camera.reset_view(); return
	var bounds: AABB=values[0].transform*values[0].definition.bounds
	for piece in values: bounds=bounds.merge(piece.transform*piece.definition.bounds)
	camera.frame_point(bounds.get_center(),maxf(2,bounds.size.length()*0.65))

func pick_piece(screen: Vector2) -> TrackPiece:
	var origin=camera.project_ray_origin(screen)
	# Layer 4 supplies pick-only shapes on moving mechanism visuals.
	var query=PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*250,5)
	var hit=get_world_3d().direct_space_state.intersect_ray(query)
	var node=hit.get("collider") as Node
	while node and not node is TrackPiece: node=node.get_parent()
	return node as TrackPiece

func extension_at(screen: Vector2) -> Dictionary:
	var best=7.0
	var found: Dictionary = {}
	for target in targets:
		if target.piece not in selection or camera.is_position_behind(target.point): continue
		var distance=screen.distance_to(camera.unproject_position(target.point))
		if distance<best and snap.target_visible(target,camera):
			best=distance
			found=target
	return found

func show_status(message: String) -> void:
	if message==last_status: return
	last_status=message
	status_changed.emit(message)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton: cursor_position=event.position
	if not enabled: return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE] and not chosen:
		pointer_down=false
		box_active=false
		marquee_changed.emit(Rect2(),false)
	# Releases crossing the UI must end a gesture but must never place through it.
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and pointer_down:
		finish_pointer(event.position,get_viewport().gui_get_hovered_control()!=null)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and get_viewport().gui_get_hovered_control()==null:
		var focus=get_viewport().gui_get_focus_owner()
		if focus: focus.release_focus()

func finish_pointer(screen: Vector2, over_ui: bool = false) -> void:
	if direct_drag:
		if over_ui: cancel()
		else:
			update_preview()
			if valid: commit()
			else: cancel()
	elif box_active:
		var rectangle=Rect2(press_position,screen-press_position).abs()
		var result=ConstructionSelection.in_rectangle(pieces,camera,rectangle)
		if additive:
			for piece in selection:
				if piece not in result: result.append(piece)
		set_selection(result)
	pointer_down=false
	direct_drag=false
	box_active=false
	marquee_changed.emit(Rect2(),false)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or ConstructionInput.typing(get_viewport()): return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT and chosen:
			cancel()
			camera.drag_button=0
			get_viewport().set_input_as_handled()
			return
		if event.button_index==MOUSE_BUTTON_LEFT and camera.drag_button==0:
			if chosen:
				update_preview()
				commit()
			else:
				var target=extension_at(event.position)
				if not target.is_empty() and not event.shift_pressed and not event.double_click:
					extension_requested.emit(target,event.position)
				else:
					press_piece=pick_piece(event.position)
					press_position=event.position
					additive=event.shift_pressed
					if event.double_click and press_piece:
						select_connected(press_piece)
					elif event.shift_pressed and press_piece:
						var result=selection.duplicate()
						if press_piece in result: result.erase(press_piece)
						else: result.append(press_piece)
						set_selection(result)
					else:
						if press_piece and press_piece not in selection: select(press_piece)
						elif not press_piece and not additive: select(null)
						pointer_down=true
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and pointer_down and camera.drag_button==0:
		if event.position.distance_to(press_position)>=drag_threshold:
			if press_piece and not chosen and press_piece in selection:
				var anchor=selection_pivot()
				move_selected()
				pointer_down=true
				direct_drag=true
				var point=plane_point(press_position,movement_height)
				pointer_offset=anchor-point if point!=null else Vector3.ZERO
			elif not press_piece:
				box_active=true
				marquee_changed.emit(Rect2(press_position,event.position-press_position).abs(),true)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("build_cancel",false,true):
			if chosen or pointer_down: cancel()
			else: select(null)
		elif event.is_action_pressed("build_remove",false,true): delete_selected()
		elif event.is_action_pressed("build_rotate",false,true): rotate_piece()
		elif event.is_action_pressed("build_move_piece",false,true): move_selected()
		elif event.is_action_pressed("build_duplicate",false,true): move_selected(true)
		elif event.is_action_pressed("build_select_all",false,true): cancel(); select_all()
		elif event.is_action_pressed("build_cycle_snap",false,true): cycle_candidate()
		elif event.is_action_pressed("build_undo",false,true): undo()
		elif event.is_action_pressed("build_redo",false,true): redo()
		elif event.is_action_pressed("build_select_tool",false,true): cancel()
		elif event.is_action_pressed("build_grid",false,true): grid_visible=not grid_visible; refresh_grid(); options_changed.emit()
		elif event.is_action_pressed("build_snap",false,true): snapping=not snapping; refresh_connectors(); options_changed.emit()
		elif event.is_action_pressed("build_height_up_fine",false,true): set_height(height+height_step(true))
		elif event.is_action_pressed("build_height_down_fine",false,true): set_height(height-height_step(true))
		elif event.is_action_pressed("build_height_up",false,true): set_height(height+height_step())
		elif event.is_action_pressed("build_height_down",false,true): set_height(height-height_step())
		elif event.is_action_pressed("build_frame",false,true): frame_pieces(selection)
		elif event.is_action_pressed("build_frame_all",false,true): frame_all()

func selection_permitted(action: String) -> bool:
	if not rules: return true
	for piece in selection:
		if not rules.permits(piece.instance_id, action):
			show_status("This assembly contains a piece with locked " + action)
			return false
	return true

func proposed_snapshot() -> Array:
	var result: Array = []
	for piece in pieces:
		if piece not in moving_group: result.append(piece.serialize())
	for index in preview_items.size():
		var item: Dictionary = preview_items[index]
		var placement: Transform3D = proposed * item.local
		result.append({"uid": moving_group[index].instance_id if operation == "move" else "preview-new-%d" % index, "piece": String(item.definition.id), "position": [placement.origin.x, placement.origin.y, placement.origin.z], "rotation": posmod(roundi(placement.basis.get_euler().y / (PI / 2)), 4), "config": item.config.duplicate(true)})
	return result

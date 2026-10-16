class_name BuildManager
extends Node3D

signal changed
signal selection_changed(piece: BuildingPiece)
signal status_changed(message: String)
signal options_changed
signal marquee_changed(rectangle: Rect2, active: bool)
signal extension_requested(target: Dictionary, screen: Vector2)

const PIECE_SCENE = preload("res://scenes/building_piece.tscn")
@export var drag_threshold: float = 7.0
@export_range(12,96,1) var connector_target_radius: float = 32.0
var rules: PuzzleRules
var catalog: PieceCatalog
var camera: ConstructionCamera
var snap = SnapManager.new()
var history: UndoRedo = UndoRedo.new()
var pieces: Array[BuildingPiece] = []
var selection: Array[BuildingPiece] = []
var selected: BuildingPiece
var chosen: PieceDefinition
@onready var preview: Node3D = $PlacementPreview
var moving_group: Array[BuildingPiece] = []
var preview_ports: Array[Dictionary] = []
var operation: String = ""
var turn: int = 0
var height: float = 0
var movement_height: float = 0
var grab_height: float = 0
var pointer_offset: Vector3 = Vector3.ZERO
var grid_visible: bool = true
var snapping: bool = true
var authoring: bool = false
var connect_mode: bool = false
var enabled: bool = false
var valid: bool = false
var is_snapped: bool = false
var validation_message: String = ""
var grid_mesh: MeshInstance3D
var targets: Array[Dictionary] = []
var candidates: Array[Dictionary] = []
var candidate_key: String = ""
var candidate_cycled: bool = false
var sticky_target: String = ""
var forced_target: Dictionary = {}
var next_uid: int = 1
var dirty: bool = false
var cursor_position: Vector2
var pointer_down: bool = false
var press_position: Vector2
var press_piece: BuildingPiece
var additive: bool = false
var box_active: bool = false
var direct_drag: bool = false
var last_status: String = ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		history.free()

func _ready() -> void:
	snap.target_radius=connector_target_radius
	cursor_position=get_viewport().get_mouse_position()
	grid_mesh=MeshInstance3D.new()
	add_child(grid_mesh)
	refresh_grid()

func snapshot(include_environment: bool = false) -> Array:
	var result: Array = []
	for piece in pieces:
		if include_environment or not piece.definition.authoring_only: result.append(piece.serialize())
	return result

func find_piece(uid: String) -> BuildingPiece:
	for piece in pieces:
		if piece.instance_id == uid: return piece
	return null

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
		if not definition or (definition.authoring_only and not authoring): continue
		spawn(definition,PieceAttachment.record_transform(item),item.uid,item.get("config",{}))
	refresh_targets()
	changed.emit()

func spawn(definition: PieceDefinition, placement: Transform3D, uid: String = "", config: Dictionary = {}) -> BuildingPiece:
	if definition.authoring_only and not authoring: return null
	var piece=PIECE_SCENE.instantiate() as BuildingPiece
	piece.instance_id=uid if not uid.is_empty() else "piece-%d-%d" % [Time.get_ticks_usec(),next_uid]
	next_uid+=1
	add_child(piece)
	piece.setup(definition,false,config)
	piece.transform=placement
	pieces.append(piece)
	return piece

func choose(definition: PieceDefinition) -> void:
	if not enabled or (definition.authoring_only and not authoring): return
	if rules and rules.remaining(String(definition.id), snapshot()) <= 0:
		show_status("No inventory remaining")
		return
	cancel()
	select(null)
	chosen=definition
	turn=0
	operation="place"
	movement_height=height
	add_preview_piece(definition)
	preview_ports=snap.boundary_sources(placement_items())
	refresh_targets()
	if not definition.height_setting.is_empty(): resize_height_preview(height)
	options_changed.emit()

func choose_extension(definition: PieceDefinition, target: Dictionary) -> void:
	choose(definition)
	forced_target=target
	sticky_target=target.key
	update_preview()

func add_preview_piece(definition: PieceDefinition, local: Transform3D = Transform3D.IDENTITY, config: Dictionary = {}, uid: String = "") -> void:
	var piece := PIECE_SCENE.instantiate() as BuildingPiece
	preview.add_child(piece)
	piece.setup(definition, true, config)
	piece.transform = local
	piece.instance_id = uid

# The scene hierarchy owns preview configuration and relative transforms.
# Placement validation consumes a fresh view of those nodes, never a second copy.
func placement_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for piece: BuildingPiece in preview.get_children():
		items.append({"definition": piece.definition, "local": piece.transform, "config": piece.configuration, "uid": piece.instance_id})
	return items

func select(piece: BuildingPiece) -> void:
	var values: Array[BuildingPiece] = []
	if ConstructionSelection.editable(piece) and (authoring or not piece.definition.authoring_only): values.append(piece)
	set_selection(values)

func set_selection(values: Array[BuildingPiece]) -> void:
	for piece in selection:
		if is_instance_valid(piece): piece.tint(Color.WHITE,false)
	selection.clear()
	for piece in values:
		if ConstructionSelection.editable(piece) and (authoring or not piece.definition.authoring_only) and piece not in selection: selection.append(piece)
	selected=selection[0] if not selection.is_empty() else null
	for piece in selection: piece.tint(Color(1,0.78,0.25,0.4))
	selection_changed.emit(selected)
	refresh_targets()

func select_connected(piece: BuildingPiece) -> void:
	set_selection(snap.connected_section(piece, pieces.filter(ConstructionSelection.editable)))
	show_status("%d connected pieces · drag to move the assembly" % selection.size())

func select_all() -> void:
	set_selection(pieces)

func set_connect_mode(active: bool) -> void:
	if active and not enabled: return
	cancel()
	connect_mode = active
	refresh_targets()
	options_changed.emit()

func cancel() -> void:
	connect_mode = false
	preview.hide()
	for piece in preview.get_children():
		preview.remove_child(piece)
		piece.queue_free()
	for piece in moving_group:
		if is_instance_valid(piece): piece.visible=true
	moving_group.clear()
	chosen=null
	preview_ports.clear()
	operation=""
	forced_target.clear()
	candidates.clear()
	candidate_key=""
	candidate_cycled=false
	sticky_target=""
	pointer_offset=Vector3.ZERO
	pointer_down=false
	direct_drag=false
	box_active=false
	marquee_changed.emit(Rect2(),false)
	refresh_targets()
	options_changed.emit()

func height_step(fine: bool = false) -> float:
	return snap.vertical_step if fine else 0.5

func set_height(value: float) -> void:
	height=clampf(snappedf(value,snap.vertical_step),0,30)
	if chosen:
		movement_height=height
		forced_target.clear()
		if operation=="place" and not chosen.height_setting.is_empty(): resize_height_preview(height)
	refresh_grid()
	options_changed.emit()

func resize_height_preview(value: float) -> void:
	if preview.get_child_count() == 0: return
	var piece := preview.get_child(0) as BuildingPiece
	var config=piece.configuration.duplicate(true)
	config[String(chosen.height_setting)] = value
	config=chosen.normalized_configuration(config)
	if config==piece.configuration: return
	piece.apply_configuration(config)
	preview_ports=snap.boundary_sources(placement_items())

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

func refresh_targets() -> void:
	targets = snap.exposed(pieces, moving_group)

func _process(_delta: float) -> void:
	if enabled and chosen: update_preview()

func plane_point(screen: Vector2, elevation: float) -> Variant:
	var origin=camera.project_ray_origin(screen)
	var direction=camera.project_ray_normal(screen)
	if abs(direction.y)<0.001: return null
	var distance=(elevation-origin.y)/direction.y
	return origin+direction*distance if distance>=0 else null

func update_preview() -> void:
	if not chosen or preview.get_child_count() == 0: return
	if get_viewport().gui_get_hovered_control()!=null or camera.drag_button!=0:
		preview.hide()
		return
	var preview_height=movement_height
	var height_placement=operation=="place" and chosen.ground_placement and not chosen.height_setting.is_empty()
	if height_placement:
		var under_cursor=pick_piece(cursor_position)
		if under_cursor and not under_cursor.definition.authoring_only and not under_cursor.definition.connectors.is_empty():
			var level=under_cursor.definition.connectors[0].position.y
			var flat=true
			for port in under_cursor.definition.connectors:
				if absf(port.position.y-level)>0.02: flat=false
			if flat: preview_height=under_cursor.position.y+level+chosen.height_offset
		resize_height_preview(preview_height)
	var point=plane_point(cursor_position,grab_height if direct_drag else preview_height)
	var free_position: Vector3 = snap.grid_position(point+pointer_offset) if point!=null else preview.position
	if operation=="place": free_position.y=height
	else: free_position.y=movement_height
	if height_placement: free_position.y=0
	preview.transform=Transform3D(Basis(Vector3.UP,turn*PI/2),free_position)
	var items := placement_items()
	var grab_offset: Variant = null
	if direct_drag: grab_offset = pointer_offset
	candidates=snap.screen_candidates(items,preview_ports,targets,camera,cursor_position,pieces,moving_group,sticky_target,forced_target,preview.transform,grab_offset) if snapping else []
	is_snapped=not candidates.is_empty()
	if is_snapped:
		if not candidates.any(func(value: Dictionary): return value.key==candidate_key): candidate_cycled=false
		var candidate: Dictionary=candidates[0]
		for value in candidates:
			if value.key==candidate_key and (value.error.is_empty() or not candidate.error.is_empty()) and (not value.target.get("surface",false) or candidate_cycled): candidate=value; break
		preview.transform=candidate.transform
		candidate_key=candidate.key
		sticky_target=candidate.target.key
	else:
		candidate_key=""
		candidate_cycled=false
		sticky_target=""
		if point==null:
			preview.hide()
			return
	if items.size() == 1 and chosen.surface_mounted:
		var accessory := preview.get_child(0) as BuildingPiece
		if is_snapped:
			accessory.configuration.mount_target = candidates[candidate_index()].target.piece.instance_id
		else:
			accessory.configuration.erase("mount_target")
		accessory.configuration.mount_basis = PieceAttachment.basis_values(preview.basis * accessory.basis)
		items = placement_items()
	validation_message = validate_edit(items, preview.transform, moving_group)
	valid=validation_message.is_empty()
	apply_preview()
	var message="✕  "+validation_message if not valid else ("Aligned · click to place" if is_snapped else "Click to place · R rotate · right-click cancel")
	if direct_drag: message="Release to move · Esc cancel" if valid else "✕  "+validation_message
	if is_snapped and candidates.size()>1: message+=" · Tab: attachment %d/%d" % [candidate_index()+1,candidates.size()]
	show_status(message)

func apply_preview() -> void:
	preview.show()
	for piece: BuildingPiece in preview.get_children():
		piece.tint(Color(1,0.29,0.32,0.55) if not valid else (Color(0.2,0.9,0.68,0.4) if is_snapped else Color(0.38,0.72,1,0.35)))

func candidate_index() -> int:
	for i in candidates.size():
		if candidates[i].key==candidate_key: return i
	return 0

func cycle_candidate() -> void:
	if candidates.size()<2: return
	candidate_key=candidates[(candidate_index()+1)%candidates.size()].key
	candidate_cycled=true
	update_preview()

func commit() -> void:
	if not enabled or not chosen or not preview.visible or not valid: return
	if chosen.authoring_only and not authoring: return
	var items := placement_items()
	var placement_error = validate_edit(items, preview.transform, moving_group)
	if not placement_error.is_empty(): show_status(placement_error); return
	var before=snapshot(true)
	var mode=operation
	var edited: Array[BuildingPiece] = []
	for index in items.size():
		var item: Dictionary=items[index]
		var placement: Transform3D=preview.transform*item.local
		if mode=="move":
			moving_group[index].transform=placement
			moving_group[index].configuration = PieceAttachment.transformed_config(item.config, placement.basis)
			edited.append(moving_group[index])
		else:
			var piece=spawn(item.definition,placement,"",PieceAttachment.transformed_config(item.config, placement.basis))
			edited.append(piece)
	if mode == "duplicate":
		var duplicated_ids: Dictionary = {}
		for index in edited.size(): duplicated_ids[items[index].uid] = edited[index].instance_id
		for piece in edited:
			if duplicated_ids.has(piece.configuration.get("mount_target", "")):
				piece.configuration.mount_target = duplicated_ids[piece.configuration.mount_target]
			for link in piece.configuration.get("links", []):
				if duplicated_ids.has(link.target): link.target = duplicated_ids[link.target]
	if mode!="place":
		cancel()
		set_selection(edited)
	else:
		forced_target.clear()
		candidate_key=""
		candidate_cycled=false
		sticky_target=""
		refresh_targets()
	_record_edit(before,"Move assembly" if mode=="move" else ("Duplicate assembly" if mode=="duplicate" else "Place"))

func _record_edit(before: Array, label: String) -> void:
	var after := snapshot(true)
	if before == after: return
	history.create_action(label)
	history.add_do_method(restore_history.bind(after))
	history.add_undo_method(restore_history.bind(before.duplicate(true)))
	# The validated edit is already applied; only redo should restore its snapshot.
	history.commit_action(false)
	dirty=true
	refresh_targets()
	changed.emit()

func configure_selected(config: Dictionary, label: String) -> bool:
	if selection.size()!=1 or not selection_permitted("configure"): return false
	return configure_piece(selected, config, label)

func configure_piece(piece: BuildingPiece, config: Dictionary, label: String) -> bool:
	if not enabled or piece not in pieces or chosen: return false
	if rules and not rules.permits(piece.instance_id, "configure"):
		show_status("Configuration is locked")
		return false
	var normalized := piece.base_definition.normalized_configuration(config)
	var definition := piece.base_definition.configured(normalized)
	var items: Array[Dictionary] = [{"uid": piece.instance_id, "definition": definition, "local": piece.transform, "config": normalized}]
	var problem := validate_edit(items, Transform3D.IDENTITY, [piece], false, definition != piece.definition)
	if not problem.is_empty():
		show_status("✕  "+problem)
		selection_changed.emit(selected)
		return false
	if normalized == piece.configuration: return true
	var before := snapshot(true)
	snap.sample_indices.erase(piece.definition.get_instance_id())
	piece.apply_configuration(normalized)
	if piece in selection: piece.tint(Color(1,0.78,0.25,0.4))
	_record_edit(before,label)
	selection_changed.emit(selected)
	return true

func edit_link(source_id: String, index: int, link: Dictionary = {}) -> bool:
	var source := find_piece(source_id)
	if not source or source.output_ports.is_empty(): return false
	var config := source.configuration.duplicate(true)
	var links: Array = config.get("links", [])
	if index < -1 or index >= links.size(): return false
	if not link.is_empty():
		var target := find_piece(link.get("target", ""))
		if not target or link.get("action", "") not in source.compatible_actions(target, link.get("event", "")): return false
		for other in links.size():
			if other != index and links[other] == link: return false
		if index == -1: links.append(link.duplicate(true))
		else: links[index] = link.duplicate(true)
	else:
		if index == -1: return false
		links.remove_at(index)
	config.links = links
	return configure_piece(source, config, "Remove connection" if link.is_empty() else ("Connect mechanisms" if index == -1 else "Edit connection"))

func delete_selected() -> void:
	if not enabled or selection.is_empty() or not selection_permitted("remove"): return
	var removing := attached_selection()
	var problem := validate_edit([], Transform3D.IDENTITY, removing, true)
	if not problem.is_empty(): show_status(problem); return
	cancel()
	var before=snapshot(true)
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
	_record_edit(before,"Delete assembly")

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
	preview.transform=frame
	operation="duplicate" if duplicate_piece else "move"
	for piece in attached_selection():
		add_preview_piece(piece.base_definition, frame.affine_inverse()*piece.transform, piece.configuration, piece.instance_id)
		if not duplicate_piece:
			moving_group.append(piece)
			piece.hide()
	preview_ports=snap.boundary_sources(placement_items())
	refresh_targets()
	options_changed.emit()

func rotate_piece() -> void:
	if not enabled: return
	if chosen:
		if is_snapped and candidates.size()>1 and not chosen.connectors.is_empty(): cycle_candidate()
		else:
			turn=posmod(turn+1,maxi(1,chosen.rotation_steps))
			forced_target.clear()
			candidate_key=""
			candidate_cycled=false
	elif selected:
		if not selection_permitted("rotate"): return
		var pivot := selection_pivot()
		var axis := selected.basis.y if selection.size() == 1 and selected.definition.surface_mounted else Vector3.UP
		var rotation_basis := Basis(axis, PI / 2)
		_transform_selection(Transform3D(rotation_basis, pivot - rotation_basis * pivot), "Rotate assembly")

func elevate_selected(delta: float) -> void:
	if not selected or not enabled or not selection_permitted("move"): return
	if selection.size()==1 and not selected.definition.height_setting.is_empty():
		var config=selected.configuration.duplicate(true)
		var key := String(selected.definition.height_setting)
		config[key] = float(selected.definition.resolved_configuration(config)[key]) + delta
		configure_selected(config,"Height")
		return
	_transform_selection(Transform3D(Basis.IDENTITY, Vector3(0, delta, 0)), "Raise/lower assembly")

func _transform_selection(placement: Transform3D, label: String) -> void:
	var group := attached_selection()
	var items: Array[Dictionary] = []
	for piece in group:
		items.append({"uid": piece.instance_id, "definition": piece.definition, "local": piece.transform, "config": piece.configuration})
	var problem := validate_edit(items, placement, group)
	if not problem.is_empty(): show_status("✕  " + problem); return
	var before := snapshot(true)
	for index in group.size():
		group[index].transform = placement * items[index].local
		group[index].configuration = PieceAttachment.transformed_config(group[index].configuration, group[index].basis)
	set_selection(group)
	_record_edit(before, label)

func undo() -> void:
	if not enabled: return
	history.undo()

func redo() -> void:
	if not enabled: return
	history.redo()

func restore_history(data: Array) -> void:
	var was_connecting := connect_mode
	dirty=true
	var ids: Array[String] = []
	var previous: Array[String] = []
	for piece in selection: ids.append(piece.instance_id)
	for piece in pieces: previous.append(piece.instance_id)
	for item in data:
		if item.uid not in previous: ids.append(item.uid)
	restore(data)
	var restored: Array[BuildingPiece] = []
	for piece in pieces:
		if piece.instance_id in ids: restored.append(piece)
	set_selection(restored)
	connect_mode = was_connecting
	refresh_targets()
	options_changed.emit()

func frame_all() -> void:
	frame_pieces(pieces)

func frame_pieces(values: Array) -> void:
	if values.is_empty(): camera.reset_view(); return
	var bounds: AABB=values[0].transform*values[0].definition.bounds
	for piece in values: bounds=bounds.merge(piece.transform*piece.definition.bounds)
	camera.frame_point(bounds.get_center(),maxf(2,bounds.size.length()*0.65))

func pick_piece(screen: Vector2) -> BuildingPiece:
	var origin=camera.project_ray_origin(screen)
	# Layer 4 supplies pick-only shapes on moving mechanism visuals.
	var query=PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*250,5)
	var hit=get_world_3d().direct_space_state.intersect_ray(query)
	var node=hit.get("collider") as Node
	while node and not node is BuildingPiece: node=node.get_parent()
	return node as BuildingPiece

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
	if not enabled or connect_mode or ConstructionInput.typing(get_viewport()): return
	if event is InputEventMouseButton and event.pressed:
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
				var grabbed := snap.surface_hit(camera,press_position,[],5)
				move_selected()
				pointer_down=true
				direct_drag=true
				grab_height=grabbed.position.y if not grabbed.is_empty() else movement_height
				var point=plane_point(press_position,grab_height)
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
		elif event.is_action_pressed("build_snap",false,true): snapping=not snapping; options_changed.emit()
		elif event.is_action_pressed("build_height_up_fine",false,true): set_height(height+height_step(true))
		elif event.is_action_pressed("build_height_down_fine",false,true): set_height(height-height_step(true))
		elif event.is_action_pressed("build_height_up",false,true): set_height(height+height_step())
		elif event.is_action_pressed("build_height_down",false,true): set_height(height-height_step())
		elif event.is_action_pressed("build_frame",false,true): frame_pieces(selection)
		elif event.is_action_pressed("build_frame_all",false,true): frame_all()

func attached_selection() -> Array[BuildingPiece]:
	var expanded: Array[BuildingPiece] = selection.duplicate()
	for piece in pieces:
		if piece in expanded: continue
		for support in selection:
			if piece.configuration.get("mount_target", "") == support.instance_id:
				expanded.append(piece)
				break
	return expanded

func selection_permitted(action: String) -> bool:
	var affected := attached_selection() if action in ["move", "rotate", "duplicate", "remove"] else selection
	for piece in affected:
		if piece.definition.authoring_only and not authoring: return false
	if not rules: return true
	for piece in affected:
		if not rules.permits(piece.instance_id, action):
			show_status("This assembly contains a piece with locked " + action)
			return false
	return true

# Validate the complete proposed edit before changing live nodes or history.
# Geometry uses the same group check for preview, placement and direct edits.
func validate_edit(items: Array, placement: Transform3D, replaced: Array, prune_links: bool = false, check_geometry: bool = true) -> String:
	if check_geometry:
		var problem := snap.validate_group(items, placement, pieces, replaced)
		if not problem.is_empty(): return problem
	var result: Array = []
	for piece in pieces:
		if piece not in replaced and not piece.definition.authoring_only: result.append(piece.serialize())
	for index in items.size():
		var item: Dictionary = items[index]
		if item.definition.authoring_only: continue
		var transform_value: Transform3D = placement * item.local
		var original := find_piece(item.get("uid", ""))
		var uid: String = original.instance_id if original and original in replaced else "preview-new-%d" % index
		result.append({"uid": uid, "piece": String(item.definition.id), "position": [transform_value.origin.x, transform_value.origin.y, transform_value.origin.z], "rotation": posmod(roundi(transform_value.basis.get_euler().y / (PI / 2)), 4), "config": PieceAttachment.transformed_config(item.config, transform_value.basis)})
	var proposed_ids: Dictionary = {}
	for index in items.size():
		if items[index].get("uid", "").is_empty(): continue
		var original := find_piece(items[index].get("uid", ""))
		proposed_ids[items[index].get("uid", "")] = original.instance_id if original and original in replaced else "preview-new-%d" % index
	for record in result:
		if record.uid not in proposed_ids.values(): continue
		if proposed_ids.has(record.config.get("mount_target", "")):
			record.config.mount_target = proposed_ids[record.config.mount_target]
	if prune_links:
		var present: Array = result.map(func(item): return item.uid)
		for item in result:
			if item.config.has("links"): item.config.links = item.config.links.filter(func(link): return link.get("target", "") in present)
	var attachment_error := PieceAttachment.validate(result, catalog)
	if not attachment_error.is_empty(): return attachment_error
	return rules.validate(result) if rules else ""

extends SubViewportContainer
## Static view of the starting machine, using registered geometry and settings.
## Preview-only behaviors never run physics or emit mechanism signals.
var catalog: PieceCatalog
var model_bounds := AABB()

func _ready() -> void:
	resized.connect(frame_preview)

func display(data: Dictionary, pieces_catalog: PieceCatalog) -> void:
	catalog = pieces_catalog
	for child in %Models.get_children():
		%Models.remove_child(child)
		child.queue_free()
	var records: Array = data.get("pieces", []).duplicate()
	for item in data.get("environment_instances", []):
		records.append({"piece": item.asset, "position": item.position, "rotation": item.rotation, "config": {}})
	var bounds := AABB()
	var first := true
	for item in records:
		var definition := catalog.get_piece(item.piece)
		if not definition: continue
		var piece := BuildingPiece.new()
		%Models.add_child(piece)
		piece.setup(definition, true, item.get("config", {}))
		piece.transform = PieceAttachment.record_transform(item)
		for model: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = model.global_transform * model.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	var center := bounds.get_center()
	model_bounds = bounds
	%PreviewCamera.position = center + Vector3(1.2, 1.0, 1.5).normalized() * maxf(bounds.size.length(), 5.0)
	%PreviewCamera.look_at(center)
	%PreviewCamera.reset_physics_interpolation()
	frame_preview()

func frame_preview() -> void:
	if not is_node_ready(): return
	var view_bounds: AABB = %PreviewCamera.global_transform.affine_inverse() * model_bounds
	var aspect := maxf(size.x, 1.0) / maxf(size.y, 1.0)
	%PreviewCamera.size = maxf(maxf(view_bounds.size.x / aspect, view_bounds.size.y) * 1.2, 1.0)
	%PreviewViewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree() and is_node_ready():
		%PreviewViewport.render_target_update_mode = SubViewport.UPDATE_ONCE

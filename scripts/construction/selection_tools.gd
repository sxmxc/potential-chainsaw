class_name ConstructionSelection
extends RefCounted

static func editable(piece: BuildingPiece) -> bool:
	return is_instance_valid(piece) and not bool(piece.configuration.get("locked", false))

static func projected_bounds(piece: BuildingPiece, camera: Camera3D) -> Rect2:
	var points: Array[Vector2] = []
	for i in 8:
		var p: Vector3 = piece.transform * piece.definition.bounds.get_endpoint(i)
		if not camera.is_position_behind(p): points.append(camera.unproject_position(p))
	if points.is_empty(): return Rect2()
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points: rect = rect.expand(point)
	return rect

static func in_rectangle(pieces: Array, camera: Camera3D, rectangle: Rect2) -> Array[BuildingPiece]:
	var result: Array[BuildingPiece] = []
	for piece in pieces:
		if not editable(piece): continue
		var bounds := projected_bounds(piece, camera)
		if bounds.has_area() and rectangle.intersects(bounds): result.append(piece)
	return result

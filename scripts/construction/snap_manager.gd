class_name SnapManager
extends RefCounted

const POSITION_TOLERANCE = 0.015
const ORIENTATION_TOLERANCE = 0.995
var horizontal_step: float = 0.5
var vertical_step: float = 0.125
var snap_radius: float = 0.65
var boundary: float = 48.0
var target_radius: float = 32.0
var candidate_budget: int = 12
var sample_indices: Dictionary = {}
var environment_solids: Array = []

# Sources contain a definition and a transform relative to one group anchor.
# All editing paths use the same rigid transform and boundary connectors.
func exposed(pieces: Array, ignored: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for piece in pieces:
		if piece in ignored: continue
		for index in piece.definition.connectors.size():
			var connector: TrackConnector = piece.definition.connectors[index]
			var point: Vector3 = piece.transform*connector.position
			var normal: Vector3 = piece.basis*connector.outward
			var occupied := false
			for other in pieces:
				if other == piece or other in ignored: continue
				for port in other.definition.connectors:
					if connector.compatible(port) and (other.transform*port.position).distance_to(point)<POSITION_TOLERANCE and (other.basis*port.outward).dot(normal)<-ORIENTATION_TOLERANCE:
						occupied = true
			if not occupied:
				result.append({"piece":piece,"connector":connector,"point":point,"normal":normal,"key":piece.instance_id+":"+str(index)})
	return result

func boundary_sources(items: Array) -> Array[Dictionary]:
	var ports: Array[Dictionary] = []
	for index in items.size():
		var item: Dictionary = items[index]
		for connector in item.definition.connectors:
			var point: Vector3 = item.local*connector.position
			var normal: Vector3 = item.local.basis*connector.outward
			var internal := false
			for other_index in items.size():
				if index==other_index: continue
				var other: Dictionary = items[other_index]
				for port in other.definition.connectors:
					if connector.compatible(port) and (other.local*port.position).distance_to(point)<POSITION_TOLERANCE and (other.local.basis*port.outward).dot(normal)<-ORIENTATION_TOLERANCE: internal=true
			if not internal: ports.append({"connector":connector,"point":point,"normal":normal,"index":index})
	return ports

func validate_group(items: Array, placement: Transform3D, pieces: Array, ignored: Array = []) -> String:
	var external: Array = []
	for piece in pieces:
		if piece not in ignored: external.append(piece)
	for item in items:
		var error := validate(item.definition, placement*item.local, external)
		if not error.is_empty(): return error
	# Internal geometry is preserved by a rigid transform; it was validated when built.
	return ""

func screen_candidates(items: Array, ports: Array, targets: Array, camera: Camera3D, cursor: Vector2, pieces: Array, ignored: Array, sticky: String = "", forced: Dictionary = {}, preferred: Transform3D = Transform3D.IDENTITY) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var permitted_turns: Array[int] = []
	for quarter in 4:
		var rotation_basis=Basis(Vector3.UP,quarter*PI/2)
		var permitted:=true
		for item in items:
			if item.definition.rotation_steps>=4: continue
			var rotation:=posmod(roundi((rotation_basis*item.local.basis).get_euler().y/(PI/2)),4)
			if rotation>=item.definition.rotation_steps: permitted=false
		if permitted: permitted_turns.append(quarter)
	for target in targets:
		if not forced.is_empty() and target.key!=forced.key: continue
		if camera.is_position_behind(target.point): continue
		var screen: Vector2 = camera.unproject_position(target.point)
		var pixels := cursor.distance_to(screen)
		var radius := target_radius*1.4 if target.key==sticky else target_radius
		if forced.is_empty() and pixels>radius: continue
		if not target_visible(target,camera,ignored): continue
		for port_index in ports.size():
			var port: Dictionary = ports[port_index]
			if not port.connector.compatible(target.connector): continue
			for quarter in permitted_turns:
				var basis := Basis(Vector3.UP,quarter*PI/2)
				if (basis*port.normal).dot(target.normal)>-ORIENTATION_TOLERANCE: continue
				var placement := Transform3D(basis,target.point-basis*port.point)
				var score := pixels + camera.global_position.distance_to(target.point)*0.03
				score+=(1.0-basis.z.dot(preferred.basis.z))*2.0
				score+=minf(100,(preferred*port.point).distance_to(target.point))*0.08
				if target.key==sticky: score-=8.0
				results.append({"transform":placement,"point":target.point,"target":target,"key":target.key+"/"+str(port_index)+"/"+str(quarter),"error":"","score":score})
	if forced.is_empty(): results.append_array(surface_candidates(items, preferred, pieces, ignored, camera, cursor, sticky))
	results.sort_custom(func(a,b):return a.score<b.score)
	# Limit expensive solid validation to plausible nearby alternatives.
	if results.size()>candidate_budget: results.resize(candidate_budget)
	for candidate in results:
		candidate.error=validate_group(items,candidate.transform,pieces,ignored)
		if not candidate.error.is_empty(): candidate.score+=1000.0
	results.sort_custom(func(a,b):return a.score<b.score)
	return results

# Native solids align opposing faces using their measured edges and centres.
# They share candidate selection and validation with tracks without track ports.
func surface_candidates(items: Array, preferred: Transform3D, pieces: Array, ignored: Array, camera: Camera3D, cursor: Vector2, sticky: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var placements: Dictionary = {}
	var source_boxes: Array[Dictionary] = []
	for item in items:
		for solid in item.definition.collision_solids:
			source_boxes.append({"box":Transform3D(preferred.basis, Vector3.ZERO) * item.local * solid, "definition":item.definition})
	if source_boxes.is_empty(): return results
	for piece in pieces:
		if piece in ignored: continue
		for solid_index in piece.definition.collision_solids.size():
			var target_box: AABB = piece.transform * piece.definition.collision_solids[solid_index]
			for axis in 3:
				for side in 2:
					var anchors := face_anchors(target_box, axis, side)
					for anchor_index in anchors.size():
						var point: Vector3 = anchors[anchor_index]
						if (camera.global_position[axis] - point[axis]) * (side * 2 - 1) <= 0: continue
						var key: String = "%s/solid%d/%d/%d/%d" % [piece.instance_id, solid_index, axis, side, anchor_index]
						if camera.is_position_behind(point): continue
						var pixels: float = cursor.distance_to(camera.unproject_position(point))
						if pixels > target_radius * (1.4 if key == sticky else 1.0): continue
						var target := {"piece":piece, "point":point, "key":key}
						if not target_visible(target, camera, ignored): continue
						for source_item in source_boxes:
							var source_box: AABB = source_item.box
							var sources := face_anchors(source_box, axis, 1 - side)
							if axis != 1 and permits_overlap(source_item.definition, piece.definition):
								# Centre a column on the wall joint instead of pushing it outside.
								for level in 3:
									var centre := source_box.get_center()
									centre.y = source_box.position.y + source_box.size.y * level * 0.5
									sources.append(centre)
							for source: Vector3 in sources:
								var placement := Transform3D(preferred.basis, point - source)
								# Side attachments retain elevation; top/bottom faces can stack.
								if axis != 1 and not is_equal_approx(placement.origin.y, preferred.origin.y): continue
								# Thin walls join at their ends rather than crossing at a midpoint.
								var length_axis: int = 0 if source_box.size.x > source_box.size.z else 2
								var width_axis: int = 2 if length_axis == 0 else 0
								if axis == width_axis and source_box.size[length_axis] > source_box.size[width_axis] * 4.0 and is_equal_approx(source[length_axis], source_box.get_center()[length_axis]): continue
								var offset := placement.origin - preferred.origin
								var score: float = pixels + Vector2(offset.x, offset.z).length() * 2.0 + absf(offset.y) * 0.1
								if not camera.is_position_behind(placement.origin): score += cursor.distance_to(camera.unproject_position(placement.origin)) * 0.5
								if key == sticky: score -= 8.0
								# Different face anchors can describe the same rigid placement.
								var placement_key := str(placement.origin)
								if placements.has(placement_key) and placements[placement_key].score <= score: continue
								var candidate := {"transform":placement, "point":point, "target":target, "key":key+"/"+str(source), "error":"", "score":score}
								placements[placement_key] = candidate
	results.assign(placements.values())
	return results

func face_anchors(box: AABB, axis: int, side: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var first: int = (axis + 1) % 3
	var second: int = (axis + 2) % 3
	for u in 3:
		for v in 3:
			var point := box.position
			point[axis] += box.size[axis] * side
			point[first] += box.size[first] * u * 0.5
			point[second] += box.size[second] * v * 0.5
			result.append(point)
	return result

func target_visible(target: Dictionary, camera: Camera3D, ignored: Array = []) -> bool:
	var origin := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(origin,target.point,1)
	var excluded: Array[RID] = []
	for piece in ignored:
		for body in piece.bodies: excluded.append(body.get_rid())
		if piece.rotor_component: excluded.append(piece.rotor_component.rotor.get_rid())
	query.exclude=excluded
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return true
	# End caps/rails can intersect the last part of the ray to their own port.
	var node := hit.collider as Node
	while node and not node is BuildingPiece: node=node.get_parent()
	return node==target.piece and (hit.position as Vector3).distance_to(target.point)<0.65

func world_to_grid(world: Vector3) -> Vector3i:
	return Vector3i(roundi(world.x / horizontal_step), roundi(world.y / vertical_step), roundi(world.z / horizontal_step))

func grid_to_world(grid: Vector3i) -> Vector3:
	return Vector3(grid.x * horizontal_step, grid.y * vertical_step, grid.z * horizontal_step)

func grid_position(world: Vector3) -> Vector3:
	return grid_to_world(world_to_grid(world))

func aligned(definition: PieceDefinition, proposed: Transform3D, pieces: Array, ignore: Node = null) -> Dictionary:
	var best = snap_radius
	var result = {"transform": proposed, "snapped": false, "point": Vector3.ZERO}
	for piece in pieces:
		if piece == ignore: continue
		for existing in piece.definition.connectors:
			var point: Vector3 = piece.transform * existing.position
			var normal: Vector3 = piece.basis * existing.outward
			for incoming in definition.connectors:
				if not incoming.compatible(existing): continue
				# Rotation is deliberate: R cycles candidates; snapping never rotates unexpectedly.
				if (proposed.basis * incoming.outward).dot(normal) > -ORIENTATION_TOLERANCE: continue
				if connector_occupied(point, normal, existing, pieces, piece, ignore): continue
				var distance: float = (proposed * incoming.position).distance_to(point)
				if distance >= best: continue
				best = distance
				result = {"transform": Transform3D(proposed.basis, point - proposed.basis * incoming.position), "snapped": true, "point": point}
	return result

func connector_occupied(point: Vector3, normal: Vector3, connector: TrackConnector, pieces: Array, owner_piece: Node, ignore: Node = null) -> bool:
	for piece in pieces:
		if piece == owner_piece or piece == ignore: continue
		for other in piece.definition.connectors:
			if connector.compatible(other) and (piece.transform * other.position).distance_to(point) < POSITION_TOLERANCE and (piece.basis * other.outward).dot(normal) < -ORIENTATION_TOLERANCE:
				return true
	return false

func validate(definition: PieceDefinition, placement: Transform3D, pieces: Array, ignore: Node = null) -> String:
	var box = placement * definition.bounds
	if intersects_solids(definition, placement, environment_solids): return "Blocked by the environment"
	# A reusable scene may have authored foundations below its placement origin.
	var bottom: float = placement.origin.y if definition.authoring_only else box.position.y
	if box.position.x < -boundary or box.end.x > boundary or box.position.z < -boundary or box.end.z > boundary or bottom < -0.01 or box.end.y > 32:
		return "Outside the build area (±48 m, 0–32 m high)"
	for piece in pieces:
		if piece == ignore: continue
		if permits_overlap(definition, piece.definition): continue
		if not box.grow(-0.015).intersects(piece.transform * piece.definition.bounds): continue
		if solid_overlap(definition, placement, piece.definition, piece.transform):
			return "Physical overlap with " + piece.definition.display_name
	return ""

func permits_overlap(a: PieceDefinition, b: PieceDefinition) -> bool:
	return a.authoring_only and b.authoring_only and (a.overlap_with.has(b.id) or b.overlap_with.has(a.id))

static func intersects_solids(definition: PieceDefinition, placement: Transform3D, solids: Array) -> bool:
	var bounds: AABB = placement * definition.bounds
	for solid: AABB in solids:
		if not bounds.grow(-0.001).intersects(solid): continue
		if definition.reserve_bounds or definition.surface_cells.is_empty(): return true
		# Existing catalog samples represent occupied 10 cm cells. Test their
		# volumes, not just centres: even a thin partition must block placement.
		for point in definition.surface_cells:
			var cell := placement * AABB(point - Vector3.ONE * 0.05, Vector3.ONE * 0.1)
			if cell.grow(-0.001).intersects(solid): return true
	return false

func solid_overlap(a: PieceDefinition, at: Transform3D, b: PieceDefinition, bt: Transform3D) -> bool:
	# A moving mechanism reserves its complete swept volume, including empty gaps.
	if not a.collision_solids.is_empty():
		var solids: Array = []
		for solid in a.collision_solids: solids.append(at * solid)
		if not b.collision_solids.is_empty():
			for solid in b.collision_solids:
				for other: AABB in solids:
					if (bt * solid).grow(-0.001).intersects(other): return true
			return false
		return intersects_solids(b, bt, solids)
	if not b.collision_solids.is_empty(): return solid_overlap(b, bt, a, at)
	if a.reserve_bounds or b.reserve_bounds:
		return (at*a.bounds).grow(-0.015).intersects((bt*b.bounds).grow(-0.015))
	# Right-angle rigid transforms preserve the per-axis sample tolerance. Index
	# each immutable definition once, then query in B's local space.
	var id=b.get_instance_id()
	if not sample_indices.has(id):
		var index: Dictionary = {}
		for point in b.surface_cells:
			var key=sample_key(point)
			if not index.has(key): index[key]=[]
			index[key].append(point)
		sample_indices[id]=index
	var occupied: Dictionary=sample_indices[id]
	var relative=bt.affine_inverse()*at
	for p in a.surface_cells:
		var w: Vector3=relative*p
		var low=sample_key(w-Vector3.ONE*0.065)
		var high=sample_key(w+Vector3.ONE*0.065)
		for x in range(low.x,high.x+1):
			for y in range(low.y,high.y+1):
				for z in range(low.z,high.z+1):
					for q in occupied.get(Vector3i(x,y,z), []):
						var delta: Vector3 = (w-q).abs()
						if delta.x < 0.065 and delta.y < 0.065 and delta.z < 0.065: return true
	return false

func sample_key(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x/0.1),roundi(point.y/0.1),roundi(point.z/0.1))

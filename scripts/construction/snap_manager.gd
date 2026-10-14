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

func screen_candidates(items: Array, ports: Array, targets: Array, camera: Camera3D, cursor: Vector2, pieces: Array, ignored: Array, sticky: String = "", forced: Dictionary = {}, preferred: Transform3D = Transform3D.IDENTITY, grab_offset: Variant = null) -> Array[Dictionary]:
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
	if forced.is_empty(): results.append_array(surface_candidates(items, preferred, pieces, ignored, camera, cursor, sticky, grab_offset))
	results.sort_custom(func(a,b):return a.score<b.score)
	# Limit expensive solid validation to plausible nearby alternatives.
	if results.size()>candidate_budget: results.resize(candidate_budget)
	for candidate in results:
		candidate.error=validate_group(items,candidate.transform,pieces,ignored)
		if not candidate.error.is_empty(): candidate.score+=1000.0
	results.sort_custom(func(a,b):return a.score<b.score)
	return results

# The cursor selects one physical surface. Alignment uses measured world geometry;
# camera projection never decides the attachment transform or its elevation.
func surface_candidates(items: Array, preferred: Transform3D, pieces: Array, ignored: Array, camera: Camera3D, cursor: Vector2, sticky: String, grab_offset: Variant = null) -> Array[Dictionary]:
	var hit := surface_hit(camera, cursor, ignored)
	if hit.is_empty() or hit.piece not in pieces or not hit.piece.definition.authoring_only: return []
	return face_candidates(items, preferred, hit.piece, hit.position, hit.normal, sticky, grab_offset)

func surface_hit(camera: Camera3D, cursor: Vector2, ignored: Array = [], collision_mask: int = 1) -> Dictionary:
	var excluded: Array[RID] = []
	for piece in ignored:
		for body in piece.bodies: excluded.append(body.get_rid())
	# Exact silhouette edges can fall between collision triangles. A two-pixel
	# pick tolerance resolves those misses without searching projected anchors.
	for offset in [Vector2.ZERO, Vector2(0,-2), Vector2(2,0), Vector2(-2,0), Vector2(0,2)]:
		var screen: Vector2 = cursor + offset
		var origin := camera.project_ray_origin(screen)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 250, collision_mask)
		query.exclude = excluded
		var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): continue
		var node := hit.collider as Node
		while node and not node is BuildingPiece: node = node.get_parent()
		if not node: continue
		hit.piece = node
		return hit
	return {}

func face_candidates(items: Array, preferred: Transform3D, target_piece: BuildingPiece, point: Vector3, normal: Vector3, sticky: String = "", grab_offset: Variant = null) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var placements: Dictionary = {}
	var hit_axis := normal.abs().max_axis_index()
	# Sloping and curved faces are not rectangular attachment planes.
	if absf(normal[hit_axis]) < 0.98: return results
	var solids: Array[AABB] = target_piece.definition.collision_solids
	for solid_index in solids.size():
		var target_box: AABB = target_piece.transform * solids[solid_index]
		var target_bounds: AABB = target_piece.transform * target_piece.definition.bounds
		if not target_box.grow(0.003).has_point(point): continue
		for axis in 3:
			for side in 2:
				var plane: float = target_box.position[axis] + target_box.size[axis] * side
				var edge_distance := absf(point[axis] - plane)
				var directly_hit := axis == hit_axis and normal[axis] * (side * 2 - 1) > 0
				if directly_hit:
					plane = point[axis]
					edge_distance = 0.0
				# A visible edge also offers its adjacent face, so thin floors can
				# join at an edge without having to orbit below the top surface.
				if not directly_hit and (axis == hit_axis or edge_distance > 0.18): continue
				var key := "%s/solid%d/%d/%d" % [target_piece.instance_id, solid_index, axis, side]
				for item_index in items.size():
					var item: Dictionary = items[item_index]
					var source_box: AABB = Transform3D(preferred.basis, Vector3.ZERO) * item.local * item.definition.bounds
					var origin: Vector3 = point + grab_offset if grab_offset != null else point - source_box.get_center()
					origin[axis] = plane - (source_box.position[axis] if side == 1 else source_box.end[axis])
					for tangent in 3:
						if tangent == axis: continue
						if tangent == 1:
							# Side joins align bases at the target's elevation, including
							# platforms placed between construction grid levels.
							origin.y = target_bounds.position.y - source_box.position.y
						else:
							origin[tangent] = target_bounds.position[tangent] + snappedf(origin[tangent] - target_bounds.position[tangent], horizontal_step)
							var best := 0.26
							var alignment_origin: float = origin[tangent]
							for target_fraction in [0.0, 0.5, 1.0]:
								for source_fraction in [0.0, 0.5, 1.0]:
									if is_equal_approx(source_box.size[tangent], target_bounds.size[tangent]) and source_fraction != target_fraction: continue
									var aligned_origin: float = target_bounds.position[tangent] + target_bounds.size[tangent] * target_fraction - source_box.position[tangent] - source_box.size[tangent] * source_fraction
									var distance := absf(aligned_origin - alignment_origin)
									if distance < best:
										best = distance
										origin[tangent] = aligned_origin
					var variants: Array[Vector3] = [origin]
					if axis != 1 and permits_overlap(item.definition, target_piece.definition):
						var joint := origin
						joint[axis] = plane - source_box.get_center()[axis]
						variants.push_front(joint)
					for variant_index in variants.size():
						var placement := Transform3D(preferred.basis, variants[variant_index])
						var score := edge_distance * 10.0
						# Near a thin floor's rim, joining its edge is the useful default.
						if directly_hit: score += 2.0 if hit_axis == 1 and target_bounds.size.y < 0.2 else -2.0
						var length_axis := 0 if source_box.size.x > source_box.size.z else 2
						var width_axis := 2 if length_axis == 0 else 0
						if axis == width_axis and source_box.size[length_axis] > source_box.size[width_axis] * 4.0:
							var end_distance := minf(absf(point[length_axis] - target_bounds.position[length_axis]), absf(point[length_axis] - target_bounds.end[length_axis]))
							if end_distance < 0.18: score += 4.0
						if key == sticky: score -= 0.4
						score += variant_index * 0.1 + item_index * 0.01
						var placement_key := str(placement.origin)
						if placements.has(placement_key) and placements[placement_key].score <= score: continue
						var contact := point
						contact[axis] = plane
						placements[placement_key] = {"transform":placement, "point":contact, "target":{"piece":target_piece, "point":contact, "key":key, "surface":true}, "key":key+"/"+str(item_index)+"/"+str(variant_index), "error":"", "score":score}
	results.assign(placements.values())
	return results

func target_visible(target: Dictionary, camera: Camera3D, ignored: Array = []) -> bool:
	var origin := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(origin,target.point,1)
	var excluded: Array[RID] = []
	for piece in ignored:
		for body in piece.bodies: excluded.append(body.get_rid())
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
	# Catalog scenery may have geometry below its placement origin.
	var bottom: float = placement.origin.y if definition.authoring_only else box.position.y
	if box.position.x < -boundary or box.end.x > boundary or box.position.z < -boundary or box.end.z > boundary or bottom < -0.01 or box.end.y > 32:
		return "Outside the build area (±48 m, 0–32 m high)"
	for piece in pieces:
		if piece == ignore: continue
		if permits_overlap(definition, piece.definition): continue
		if not inset_bounds(box, 0.015).intersects(piece.transform * piece.definition.bounds): continue
		if solid_overlap(definition, placement, piece.definition, piece.transform):
			return "Physical overlap with " + piece.definition.display_name
	return ""

func permits_overlap(a: PieceDefinition, b: PieceDefinition) -> bool:
	return a.authoring_only and b.authoring_only and (a.overlap_with.has(b.id) or b.overlap_with.has(a.id))

static func inset_bounds(bounds: AABB, margin: float) -> AABB:
	# Keep at least half of each thin dimension; a fixed shrink can invert it.
	var inset := (bounds.size * 0.25).min(Vector3.ONE * margin)
	return AABB(bounds.position + inset, bounds.size - inset * 2.0)

static func intersects_solids(definition: PieceDefinition, placement: Transform3D, solids: Array) -> bool:
	if not definition.collision_enabled and not definition.reserve_bounds and definition.collision_solids.is_empty(): return false
	var bounds: AABB = placement * definition.bounds
	for solid: AABB in solids:
		if not inset_bounds(bounds, 0.001).intersects(solid): continue
		if definition.reserve_bounds or definition.surface_cells.is_empty(): return true
		# Existing catalog samples represent occupied 10 cm cells. Test their
		# volumes, not just centres: even a thin partition must block placement.
		for point in definition.surface_cells:
			var cell := placement * AABB(point - Vector3.ONE * 0.05, Vector3.ONE * 0.1)
			if inset_bounds(cell, 0.001).intersects(solid): return true
	return false

func solid_overlap(a: PieceDefinition, at: Transform3D, b: PieceDefinition, bt: Transform3D) -> bool:
	if (not a.collision_enabled and not a.reserve_bounds and a.collision_solids.is_empty()) or (not b.collision_enabled and not b.reserve_bounds and b.collision_solids.is_empty()): return false
	# A moving mechanism reserves its complete swept volume, including empty gaps.
	if not a.collision_solids.is_empty():
		var solids: Array = []
		for solid in a.collision_solids: solids.append(at * solid)
		if not b.collision_solids.is_empty():
			for solid in b.collision_solids:
				for other: AABB in solids:
					if inset_bounds(bt * solid, 0.001).intersects(other): return true
			return false
		return intersects_solids(b, bt, solids)
	if not b.collision_solids.is_empty(): return solid_overlap(b, bt, a, at)
	if a.reserve_bounds or b.reserve_bounds:
		return inset_bounds(at * a.bounds, 0.015).intersects(inset_bounds(bt * b.bounds, 0.015))
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

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
	results.sort_custom(func(a,b):return a.score<b.score)
	# Limit expensive solid validation to plausible nearby alternatives.
	if results.size()>candidate_budget: results.resize(candidate_budget)
	for candidate in results:
		candidate.error=validate_group(items,candidate.transform,pieces,ignored)
		if not candidate.error.is_empty(): candidate.score+=1000.0
	results.sort_custom(func(a,b):return a.score<b.score)
	return results

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
	while node and not node is TrackPiece: node=node.get_parent()
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
	if PuzzleEnvironment.blocked(definition, placement, environment_solids): return "Blocked by the environment"
	if box.position.x < -boundary or box.end.x > boundary or box.position.z < -boundary or box.end.z > boundary or box.position.y < -0.01 or box.end.y > 32:
		return "Outside the build area (±48 m, 0–32 m high)"
	for piece in pieces:
		if piece == ignore: continue
		if not box.grow(-0.015).intersects(piece.transform * piece.definition.bounds): continue
		if solid_overlap(definition, placement, piece.definition, piece.transform):
			return "Physical overlap with " + piece.definition.display_name
	return ""

func solid_overlap(a: PieceDefinition, at: Transform3D, b: PieceDefinition, bt: Transform3D) -> bool:
	# A moving mechanism reserves its complete swept volume, including empty gaps.
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

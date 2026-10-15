class_name PieceAttachment
extends RefCounted
## Optional construction metadata. Positions stay in world space; only mounted
## accessories need a full orientation instead of the legacy quarter-turn yaw.

static func basis_values(basis: Basis) -> Array:
	return [basis.x.x, basis.x.y, basis.x.z, basis.y.x, basis.y.y, basis.y.z, basis.z.x, basis.z.y, basis.z.z]

static func basis_from(values: Array) -> Basis:
	return Basis(Vector3(values[0], values[1], values[2]), Vector3(values[3], values[4], values[5]), Vector3(values[6], values[7], values[8]))

static func valid_basis(value: Variant) -> bool:
	if not value is Array or value.size() != 9: return false
	for number in value:
		if not (number is float or number is int) or not is_finite(float(number)): return false
	var basis := basis_from(value)
	return absf(basis.x.length_squared() - 1.0) < 0.00001 and absf(basis.y.length_squared() - 1.0) < 0.00001 and absf(basis.z.length_squared() - 1.0) < 0.00001 and absf(basis.x.dot(basis.y)) < 0.00001 and absf(basis.y.dot(basis.z)) < 0.00001 and absf(basis.z.dot(basis.x)) < 0.00001 and absf(basis.determinant() - 1.0) < 0.00001

static func record_transform(item: Dictionary) -> Transform3D:
	var config: Dictionary = item.get("config", {})
	var basis := Basis(Vector3.UP, int(item.rotation) * PI / 2)
	if valid_basis(config.get("mount_basis")): basis = basis_from(config.mount_basis)
	return Transform3D(basis, Vector3(item.position[0], item.position[1], item.position[2]))

static func transformed_config(config: Dictionary, basis: Basis) -> Dictionary:
	var result := config.duplicate(true)
	if result.has("mount_target"): result.mount_basis = basis_values(basis)
	return result

static func validate(records: Array, catalog: PieceCatalog) -> String:
	var by_id: Dictionary = {}
	for item in records: by_id[item.uid] = item
	for item in records:
		var definition := catalog.get_piece(item.piece)
		var config: Dictionary = item.get("config", {})
		if not definition: return "Unknown attachment piece"
		if not definition.surface_mounted:
			if config.has("mount_target") or config.has("mount_basis"): return "This piece cannot be surface mounted"
			continue
		if not config.get("mount_target") is String or not valid_basis(config.get("mount_basis")): return "Point at a machine surface to mount this piece"
		var target: Dictionary = by_id.get(config.mount_target, {})
		if target.is_empty() or target.uid == item.uid: return "Mounting surface is missing"
		var support := catalog.get_piece(target.piece)
		# Accessories cannot support other accessories, avoiding cycles and deep
		# attachment trees. Fixed environment pieces are not construction members.
		if not support or support.surface_mounted or support.authoring_only: return "Choose a construction piece as the mounting surface"
		var contact := record_transform(item).origin
		var support_transform := record_transform(target)
		var local_contact := support_transform.affine_inverse() * contact
		if not supports_contact(support.configured(target.get("config", {})), local_contact): return "Accessory must stay on its mounting surface"
	return ""

static func supports_contact(definition: PieceDefinition, point: Vector3) -> bool:
	if not definition.bounds.grow(0.03).has_point(point): return false
	if not definition.collision_solids.is_empty():
		for solid in definition.collision_solids:
			if solid.grow(0.03).has_point(point): return true
		return false
	if not definition.surface_cells.is_empty():
		for cell in definition.surface_cells:
			var distance := (point - cell).abs()
			if distance.x <= 0.08 and distance.y <= 0.08 and distance.z <= 0.08: return true
		return false
	return true

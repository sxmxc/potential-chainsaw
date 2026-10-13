class_name BuildingPiece
extends Node3D

var definition: PieceDefinition
var base_definition: PieceDefinition
var instance_id: String
var configuration: Dictionary = {}
var model_node: Node3D
var meshes: Array[MeshInstance3D] = []
var bodies: Array[StaticBody3D] = []
var preview: bool = false
var behaviors: Array[PieceBehavior] = []
var tint_material: StandardMaterial3D

# Ports are derived from the authored components, never stored a second time.
# Names must be unique across the components on one piece because saved links
# address a stable piece ID and port name.
var input_ports: Dictionary:
	get:
		var ports: Dictionary = {}
		for behavior_node in behaviors:
			for port in behavior_node.inputs: ports[port] = behavior_node
		return ports
var output_ports: Dictionary:
	get:
		var ports: Dictionary = {}
		for behavior_node in behaviors:
			for port in behavior_node.output_ports(): ports[port] = behavior_node
		return ports

func setup(data: PieceDefinition, ghost: bool = false, config: Dictionary = {}) -> void:
	base_definition = data
	definition = data
	preview = ghost
	model_node = data.model.instantiate()
	model_node.position += data.placement_offset
	if model_node is PieceBehavior: behaviors.append(model_node)
	for behavior_node in model_node.find_children("*", "", true, false):
		if behavior_node is PieceBehavior: behaviors.append(behavior_node)
	for behavior_node in behaviors:
		behavior_node.preview_only = ghost
		if ghost: behavior_node.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model_node)
	apply_configuration(config)
	if not ghost and not data.collision_enabled and bodies.is_empty():
		# Decorative objects remain selectable without blocking marble travel.
		var pick_body := StaticBody3D.new()
		pick_body.collision_layer = 4
		pick_body.collision_mask = 0
		var pick_shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = data.bounds.size
		pick_shape.shape = box_shape
		pick_shape.position = data.bounds.get_center()
		pick_body.add_child(pick_shape)
		add_child(pick_body)
		bodies.append(pick_body)

func _collect(node: Node, collision_owned: bool = false) -> void:
	if node is CollisionObject3D:
		collision_owned = true
		if node is StaticBody3D and node not in bodies: bodies.append(node)
		if preview:
			node.collision_layer = 0
			node.collision_mask = 0
	if node is MeshInstance3D:
		if not meshes.has(node): meshes.append(node)
		if definition.collision_enabled and not preview and not collision_owned and not node.get_children().any(func(child): return child is StaticBody3D):
			var body = StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 2
			var collision = CollisionShape3D.new()
			collision.shape = node.mesh.create_trimesh_shape()
			var material = PhysicsMaterial.new()
			material.friction = 0.18
			material.bounce = 0.02
			body.physics_material_override = material
			node.add_child(body)
			body.add_child(collision)
			bodies.append(body)
	for child in node.get_children():
		if child is Node3D: _collect(child, collision_owned)

func apply_configuration(config: Dictionary) -> void:
	configuration = base_definition.normalized_configuration(config)
	definition = base_definition.configured(configuration)
	for behavior_node in behaviors:
		behavior_node.configure(base_definition.resolved_configuration(configuration))
	meshes.clear()
	bodies.clear()
	_collect(model_node, base_definition.native_collision)

func tint(color: Color, enabled: bool = true) -> void:
	if not tint_material:
		tint_material = StandardMaterial3D.new()
		tint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint_material.albedo_color = color
	for mesh in meshes:
		if not enabled:
			mesh.material_overlay = null
			continue
		mesh.material_overlay = tint_material

func serialize() -> Dictionary:
	return {"uid": instance_id, "piece": String(definition.id), "position": [position.x,position.y,position.z], "rotation": posmod(roundi(rotation.y / (PI / 2.0)), 4), "config": configuration.duplicate(true)}

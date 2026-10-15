class_name BuildingPiece
extends Node3D

var definition: PieceDefinition
var base_definition: PieceDefinition
var instance_id: String
var configuration: Dictionary = {}
var model_node: Node3D
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

# Wiring choices and committed links use the same component port contract.
func compatible_actions(target: BuildingPiece, event: String) -> Array:
	var sending := output_ports
	if not sending.has(event): return []
	var receiving := target.input_ports
	var state_port: bool = sending[event].state_outputs.has(event)
	return receiving.keys().filter(func(action): return receiving[action].state_inputs.has(action) == state_port)

func compatible_events(target: BuildingPiece) -> Array:
	return output_ports.keys().filter(func(event): return not compatible_actions(target, event).is_empty())

func setup(data: PieceDefinition, ghost: bool = false, config: Dictionary = {}) -> void:
	base_definition = data
	definition = data
	preview = ghost
	model_node = data.model.instantiate()
	model_node.position += data.placement_offset
	if model_node is PieceBehavior: behaviors.append(model_node)
	for behavior_node in model_node.find_children("*", "Node", true, false):
		if behavior_node is PieceBehavior: behaviors.append(behavior_node)
	for behavior_node in behaviors:
		behavior_node.preview_only = ghost
		if ghost: behavior_node.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model_node)
	apply_configuration(config)
	if not ghost and not data.collision_enabled and find_children("*", "StaticBody3D", true, false).is_empty():
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

# The hierarchy owns geometry, including children rebuilt by a configuration edit.
# Only unowned meshes need generated collision; authored physics stays intact.
func _prepare_collision() -> void:
	if preview:
		for body: CollisionObject3D in find_children("*", "CollisionObject3D", true, false):
			body.collision_layer = 0
			body.collision_mask = 0
		return
	if not definition.collision_enabled or base_definition.native_collision: return
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mesh.get_children().any(func(child): return child is StaticBody3D): continue
		var ancestor := mesh.get_parent()
		while ancestor != self and not ancestor is CollisionObject3D:
			ancestor = ancestor.get_parent()
		if ancestor is CollisionObject3D: continue
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 2
		var collision := CollisionShape3D.new()
		collision.shape = mesh.mesh.create_trimesh_shape()
		var material := PhysicsMaterial.new()
		material.friction = 0.18
		material.bounce = 0.02
		body.physics_material_override = material
		mesh.add_child(body)
		body.add_child(collision)

func apply_configuration(config: Dictionary) -> void:
	configuration = base_definition.normalized_configuration(config)
	definition = base_definition.configured(configuration)
	for behavior_node in behaviors:
		behavior_node.configure(base_definition.resolved_configuration(configuration))
	_prepare_collision()

func tint(color: Color, enabled: bool = true) -> void:
	if not tint_material:
		tint_material = StandardMaterial3D.new()
		tint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint_material.albedo_color = color
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if not enabled:
			mesh.material_overlay = null
			continue
		mesh.material_overlay = tint_material

func serialize() -> Dictionary:
	return {"uid": instance_id, "piece": String(definition.id), "position": [position.x,position.y,position.z], "rotation": posmod(roundi(rotation.y / (PI / 2.0)), 4), "config": PieceAttachment.transformed_config(configuration, basis)}

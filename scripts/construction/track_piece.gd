class_name TrackPiece
extends Node3D

const ElevatorGeometry = preload("res://scripts/mechanisms/elevator_geometry.gd")
const SupportGeometry = preload("res://scripts/construction/support_geometry.gd")

var definition: PieceDefinition
var base_definition: PieceDefinition
var instance_id: String
var configuration: Dictionary = {}
var model_node: Node3D
var meshes: Array[MeshInstance3D] = []
var bodies: Array[StaticBody3D] = []
var marker: MeshInstance3D
var preview: bool = false
var rotor_component: RotorComponent
var elevator_component: Node3D
var support_component: Node3D
var tint_material: StandardMaterial3D

func setup(data: PieceDefinition, ghost: bool = false, config: Dictionary = {}) -> void:
	base_definition = data
	definition = data
	preview = ghost
	model_node = data.model.instantiate()
	model_node.position += data.placement_offset
	add_child(model_node)
	if data.behavior == "elevator":
		elevator_component = model_node
		apply_configuration(config)
	elif data.behavior == "resizable_support":
		support_component = model_node
		apply_configuration(config)
	else:
		configuration = config.duplicate(true)
		_collect(model_node)
	if data.component_scene and not ghost:
		add_child(data.component_scene.instantiate())
	if data.behavior in ["start", "finish"]:
		marker = MeshInstance3D.new()
		var ring = TorusMesh.new()
		ring.inner_radius = 0.24
		ring.outer_radius = 0.29
		marker.mesh = ring
		marker.position = Vector3(0,0.72,0)
		var material = StandardMaterial3D.new()
		material.albedo_color = Color("59e5b1") if data.behavior == "start" else Color("ffc66d")
		material.emission_enabled = true
		material.emission = material.albedo_color
		marker.material_override = material
		add_child(marker)

func _collect(node: Node) -> void:
	if node is StaticBody3D:
		if not bodies.has(node): bodies.append(node)
		return
	if node is MeshInstance3D:
		if not meshes.has(node): meshes.append(node)
		if definition.behavior == "rotor" and node.name == "fan" and not preview:
			rotor_component = RotorComponent.new()
			add_child(rotor_component)
			rotor_component.configure(node)
		elif definition.collision_enabled and not preview:
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
		if child is Node3D: _collect(child)

func apply_configuration(config: Dictionary) -> void:
	configuration = config.duplicate(true)
	if base_definition.behavior == "elevator":
		configuration = ElevatorGeometry.normalized(configuration)
		definition = ElevatorGeometry.configured(base_definition, configuration)
		elevator_component.configure(configuration.elevator_height, configuration.elevator_speed, preview)
	elif base_definition.behavior == "resizable_support":
		configuration = SupportGeometry.normalized(configuration)
		definition = SupportGeometry.configured(base_definition, configuration)
		support_component.configure(configuration)
	else: return
	meshes.clear()
	bodies.clear()
	_collect(model_node)

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
	return {"uid": instance_id, "piece": String(definition.id), "position": [position.x,position.y,position.z], "rotation": roundi(rotation.y / (PI / 2.0)), "config": configuration.duplicate(true)}

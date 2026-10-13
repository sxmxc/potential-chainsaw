class_name BuildingPiece
extends Node3D

var definition: PieceDefinition
var base_definition: PieceDefinition
var instance_id: String
var configuration: Dictionary = {}
var model_node: Node3D
var meshes: Array[MeshInstance3D] = []
var bodies: Array[StaticBody3D] = []
var marker: MeshInstance3D
var preview: bool = false
var mechanism_component: MarbleMechanism
var support_component: Node3D
var tint_material: StandardMaterial3D

func setup(data: PieceDefinition, ghost: bool = false, config: Dictionary = {}) -> void:
	config = preload("res://scripts/mechanisms/settings_schema.gd").normalized(data.behavior, config)
	base_definition = data
	definition = data
	preview = ghost
	model_node = data.model.instantiate()
	model_node.position += data.placement_offset
	add_child(model_node)
	if data.behavior == "elevator":
		var elevator = model_node as BucketElevator
		elevator.preview_only = ghost
		mechanism_component = elevator
		apply_configuration(config)
	elif data.behavior == "resizable_support":
		support_component = model_node
		apply_configuration(config)
	else:
		configuration = config.duplicate(true)
		_collect(model_node)
	if data.behavior in ["gate", "diverter", "launcher", "sensor"] and not ghost:
		mechanism_component = load("res://scripts/mechanisms/" + data.behavior + ".gd").new()
		add_child(mechanism_component)
	if mechanism_component and data.behavior != "elevator": mechanism_component.configure(config)
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
		if preview:
			node.collision_layer = 0
			node.collision_mask = 0
		if not definition.authoring_only: return
	if node is MeshInstance3D:
		if not meshes.has(node): meshes.append(node)
		if definition.behavior == "rotor" and node.name == "fan" and not preview:
			var rotor = RotorComponent.new()
			mechanism_component = rotor
			add_child(rotor)
			rotor.setup(node)
		elif definition.behavior == "airflow" and node.name == "fan" and not preview:
			mechanism_component = preload("res://scripts/mechanisms/airflow.gd").new()
			add_child(mechanism_component)
			mechanism_component.setup(node, String(definition.id).contains("standing"))
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
	config = preload("res://scripts/mechanisms/settings_schema.gd").normalized(base_definition.behavior, config)
	configuration = base_definition.normalized_configuration(config)
	definition = base_definition.configured(configuration)
	if base_definition.behavior == "elevator":
		mechanism_component.configure(configuration)
	elif base_definition.behavior == "resizable_support":
		support_component.configure(configuration)
	else:
		if mechanism_component: mechanism_component.configure(config)
		return
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
	return {"uid": instance_id, "piece": String(definition.id), "position": [position.x,position.y,position.z], "rotation": posmod(roundi(rotation.y / (PI / 2.0)), 4), "config": configuration.duplicate(true)}

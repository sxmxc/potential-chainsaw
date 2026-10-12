class_name MarbleMechanism
extends Node3D

signal event_raised(event: String, marble: RigidBody3D)
var active: bool = false
var enabled: bool = true
var config: Dictionary = {}
var actions: Dictionary = {}
var events: Array[String] = []

func configure(settings: Dictionary) -> void:
	config = settings.duplicate(true)
	reset()

func reset() -> void:
	active = false
	enabled = bool(config.get("enabled", true))

func perform(action: String) -> bool:
	if not active or not actions.has(action): return false
	actions[action].call()
	event_raised.emit("activated", null)
	return true

func detection(size: Vector3, at: Vector3) -> Area3D:
	var area = Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.position = at
	area.add_child(shape)
	add_child(area)
	return area

func moving_box(size: Vector3, at: Vector3, color: Color) -> AnimatableBody3D:
	var body = AnimatableBody3D.new()
	body.sync_to_physics = false
	var physics = PhysicsMaterial.new()
	physics.friction = 0.05
	physics.bounce = 0
	body.physics_material_override = physics
	body.collision_layer = 1
	body.collision_mask = 2
	body.position = at
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var visual = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	body.add_child(visual)
	add_child(body)
	return body

func is_marble(body: Node3D) -> bool:
	return body is RigidBody3D and body.collision_layer & 2 != 0

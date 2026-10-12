class_name RotorComponent
extends Node

var rotor: AnimatableBody3D
var mesh: MeshInstance3D
var rest: Transform3D
var active: bool = false
var speed: float = 1.3
var angle: float = 0.0

func configure(target: MeshInstance3D) -> void:
	mesh = target
	rest = mesh.transform
	# Measured GLB blade extent is 0.676 m; separate arms leave the gaps open.
	# A single convex decomposition of the four-blade mesh fills those gaps.
	rotor = AnimatableBody3D.new()
	rotor.collision_layer = 1
	rotor.collision_mask = 2
	mesh.add_child(rotor)
	var sizes: Array[Vector3] = [Vector3(0.65, 0.15, 0.14)]
	if str(mesh.get_parent().name).contains("four"): sizes.append(Vector3(0.14, 0.15, 0.65))
	for size in sizes:
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position.y = 0.1
		rotor.add_child(collision)
	rotor.sync_to_physics = false
	rotor.top_level = true

func _physics_process(delta: float) -> void:
	if not is_instance_valid(mesh): return
	if active: angle += speed*delta
	mesh.transform = rest * Transform3D(Basis(Vector3.UP,angle),Vector3.ZERO)
	rotor.global_transform = mesh.global_transform

func reset() -> void:
	active = false
	angle = 0
	if is_instance_valid(mesh):
		mesh.transform = rest
		if rotor.is_inside_tree(): rotor.global_transform = mesh.global_transform

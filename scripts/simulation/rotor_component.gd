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
	# Decomposition preserves separate blades; a single convex hull would fill the gaps.
	mesh.create_multiple_convex_collisions()
	rotor = AnimatableBody3D.new()
	rotor.collision_layer = 1
	rotor.collision_mask = 2
	mesh.add_child(rotor)
	for child in mesh.get_children():
		if child is StaticBody3D:
			for shape in child.get_children():
				# Collision shapes are authored in mesh-local space, including before
				# the piece enters the tree. Preserve that local transform.
				shape.owner = null
				shape.reparent(rotor, false)
			child.queue_free()
	rotor.sync_to_physics = false

func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(mesh): return
	angle += speed*delta
	mesh.transform = rest * Transform3D(Basis(Vector3.UP,angle),Vector3.ZERO)

func reset() -> void:
	active = false
	angle = 0
	if is_instance_valid(mesh): mesh.transform = rest

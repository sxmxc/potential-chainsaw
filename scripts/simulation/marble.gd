extends RigidBody3D

const MODELS: Array[PackedScene] = [
	preload("res://assets/models/build_pieces/GLB format/marble-high.glb"),
	preload("res://assets/models/build_pieces/GLB format/marble-center-high.glb"),
	preload("res://assets/models/build_pieces/GLB format/marble-center-butterfly-high.glb"),
]

func _ready() -> void:
	# Only the visual changes; every variant shares the same rigid-body physics.
	var model = MODELS.pick_random().instantiate()
	model.name = "Model"
	add_child(model)

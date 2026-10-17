class_name Marble
extends RigidBody3D

# Assigned by the release before its output transfers the body to simulation.
var release_ordinal: int = 0

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

# Only intentional mechanism capture suspends ordinary rigid-body physics.
# A nonempty snapshot is the capture state and prevents a second claim.
var _captured_physics: Dictionary = {}
var carried: bool:
	get: return not _captured_physics.is_empty()

func capture() -> bool:
	if is_queued_for_deletion() or carried: return false
	_captured_physics = {"freeze": freeze, "freeze_mode": freeze_mode,
		"layer": collision_layer, "mask": collision_mask,
		"linear": linear_velocity, "angular": angular_velocity, "sleeping": sleeping}
	freeze = true
	freeze_mode = FREEZE_MODE_STATIC
	collision_layer = 0
	collision_mask = 0
	return true

func release_capture(exit_velocity: Variant = null) -> void:
	if not carried: return
	collision_layer = _captured_physics.layer
	collision_mask = _captured_physics.mask
	freeze_mode = _captured_physics.freeze_mode
	freeze = _captured_physics.freeze
	linear_velocity = _captured_physics.linear if exit_velocity == null else exit_velocity
	angular_velocity = _captured_physics.angular
	sleeping = _captured_physics.sleeping if exit_velocity == null else false
	_captured_physics.clear()

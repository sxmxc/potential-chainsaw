class_name MarbleChase
extends Node3D
## Persistent, non-colliding targets isolate the camera from rolling-body rotation.
## Two PCams allow the host to tween even when changing from one marble to another.
signal target_lost
signal changed

@export_range(0.5, 8.0) var follow_distance: float = 2.8
@export_range(0.1, 3.0) var height: float = 0.65
@export_range(0.0, 2.0) var look_ahead: float = 0.45
@export_range(1.0, 16.0) var orientation_smoothing: float = 7.0
@export_range(0.0, 2.0) var transition_duration: float = 0.65
@onready var views: Array[PhantomCamera3D] = [$ChaseA, $ChaseB]
@onready var targets: Array[Node3D] = [$TargetA, $TargetB]
var marble: RigidBody3D
var slot: int = 1
var heading: float = 0.0
var tilt: float = -0.22
var previous_position: Vector3
var preparing: bool = false
var preparation_ticks: int = 0

func _ready() -> void:
	process_priority = -20
	process_physics_priority = -20
	for view in views:
		view.spring_length = follow_distance
		view.tween_resource.duration = transition_duration

static func suitable(body: RigidBody3D) -> bool:
	return is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion() and body.is_visible_in_tree() and not body.get_meta("delivered", false)

func follow(body: RigidBody3D) -> bool:
	if not suitable(body): return false
	if marble == body: return true
	marble = body
	slot = 1 - slot
	var velocity = body.linear_velocity
	tilt = -0.22
	if Vector2(velocity.x, velocity.z).length() > 0.15:
		heading = atan2(-velocity.x, -velocity.z)
		tilt = clampf(atan2(velocity.y, Vector2(velocity.x, velocity.z).length())-0.22, -0.65, 0.25)
	previous_position = body.get_global_transform_interpolated().origin
	_update_target(previous_position)
	# Prime the destination, never the rendered Camera3D. The host starts its
	# transition at its current rendered pose, including interrupted transitions.
	views[slot].process_logic(0.0)
	# The spring arm resolves its child distance on physics ticks. Its inactive
	# distance may still be collapsed at the old target, so retain the current
	# view until it has resolved at the new position.
	preparing = true
	preparation_ticks = 0
	changed.emit()
	return true

func _physics_process(_delta: float) -> void:
	if not preparing: return
	if not suitable(marble):
		stop()
		target_lost.emit()
		return
	preparation_ticks += 1
	if preparation_ticks < 2: return
	views[slot].process_logic(0.0)
	views[slot].priority = 30
	views[1-slot].priority = 0
	preparing = false

func stop() -> void:
	preparing = false
	marble = null
	for view in views: view.priority = 0
	changed.emit()

func _process(delta: float) -> void:
	if not is_instance_valid(marble) or not suitable(marble):
		# A freed Object can compare equal to null while its chase view is active.
		if preparing or views[0].priority > 0 or views[1].priority > 0:
			stop()
			target_lost.emit()
		return
	var point = marble.get_global_transform_interpolated().origin
	var velocity = (point - previous_position) / maxf(delta, 0.001)
	previous_position = point
	# Carried marbles move by transforms rather than linear_velocity.
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.15:
		var desired = atan2(-velocity.x, -velocity.z)
		var turn = wrapf(desired-heading, -PI, PI)
		heading += clampf(turn * (1.0-exp(-delta*orientation_smoothing)), -2.8*delta, 2.8*delta)
		var desired_tilt = clampf(atan2(velocity.y, horizontal_speed)-0.22, -0.65, 0.25)
		tilt = lerpf(tilt, desired_tilt, 1.0-exp(-delta*orientation_smoothing))
	_update_target(point)

func _update_target(point: Vector3) -> void:
	var ahead = Vector3(-sin(heading), 0, -cos(heading)) * look_ahead
	targets[slot].global_position = point + Vector3.UP*height + ahead
	views[slot].set_third_person_rotation(Vector3(tilt, heading, 0))


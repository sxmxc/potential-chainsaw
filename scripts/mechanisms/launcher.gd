extends PieceBehavior

@export var area: Area3D
var cooldown: float = 0
var fired: Dictionary = {}
var has_fired: bool = false
var pending: bool = false
@export var loading_stop: AnimatableBody3D
@export var arrow: Node3D
@export var handle_animation: AnimationPlayer

func _ready() -> void:
	inputs = {"fire": func(_value: Variant): pending = true, "activate": func(_value: Variant): enabled = true, "deactivate": func(_value: Variant): enabled = false}
	outputs = ["activated"]
	outputs.append("fired")
	area.body_exited.connect(func(body: Node3D): fired.erase(body.get_instance_id()))
	reset()

func _physics_process(delta: float) -> void:
	if not active: return
	if not enabled:
		_update_handle()
		return
	cooldown = maxf(0, cooldown - delta)
	_update_handle()
	var was_blocked = loading_stop.position.y < 1
	loading_stop.position.y = 1.25 if not config.get("external", false) or pending or cooldown > 0 else 0.525
	# Let the physics server commit the raised stop before applying the launch impulse.
	if was_blocked and loading_stop.position.y > 1: return
	if not config.get("auto_rearm", true) and has_fired: return
	if cooldown > 0 or (config.get("external", false) and not pending): return
	for body in area.get_overlapping_bodies():
		if not is_marble(body) or fired.has(body.get_instance_id()): continue
		# Each shot has a configured output velocity, independent of arrival speed/spin.
		body.global_position = area.global_position
		body.linear_velocity = launch_velocity()
		body.angular_velocity = Vector3.ZERO
		body.sleeping = false
		body.reset_physics_interpolation()
		fired[body.get_instance_id()] = true
		has_fired = true
		pending = false
		cooldown = 0.5
		_update_handle()
		emit_output("fired", body)
		break

func _update_handle() -> void:
	if not handle_animation: return
	var clip: StringName = &"armed"
	var time := 0.0
	if not enabled:
		clip = &"unarmed"
	elif cooldown > 0.38:
		clip = &"fire"
		time = 0.5 - cooldown
	elif has_fired and not config.get("auto_rearm", true):
		clip = &"unarmed"
	elif cooldown > 0:
		clip = &"rearm"
		time = 0.38 - cooldown
	if handle_animation.current_animation != clip:
		handle_animation.play(clip)
	# Sample from the mechanism clock so pause and reset cannot leave a separate animation running.
	handle_animation.seek(time, true)

func launch_velocity() -> Vector3:
	var elevation := deg_to_rad(float(config.get("angle", 25)))
	return global_basis * Vector3(0, sin(elevation), -cos(elevation)) * float(config.get("strength", 4))

func build_trajectory(excluded: Array[RID] = []) -> PackedVector3Array:
	var points := PackedVector3Array()
	var gravity: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	gravity *= float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var velocity := launch_velocity()
	var origin := area.global_position
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = preload("res://scenes/marble_shape.tres")
	query.collision_mask = 1
	query.exclude = excluded + [loading_stop.get_rid()]
	query.transform.origin = origin
	points.append(origin)
	if not space.intersect_shape(query, 1).is_empty(): return points
	for sample_index in range(1, 81):
		var seconds := sample_index * 0.05
		var point := origin + velocity * seconds + gravity * seconds * seconds * 0.5
		query.transform.origin = points[-1]
		query.motion = point - points[-1]
		var travel := space.cast_motion(query)
		if travel[0] < 1.0:
			points.append(points[-1] + query.motion * travel[0])
			break
		points.append(point)
		if point.y < 0.0: break
	return points

func reset() -> void:
	super.reset()
	fired.clear()
	has_fired = false
	cooldown = 0
	pending = false
	if loading_stop: loading_stop.position.y = 0.525 if config.get("external", false) else 1.25
	if arrow: arrow.rotation.x = deg_to_rad(float(config.get("angle", 25)))
	_update_handle()

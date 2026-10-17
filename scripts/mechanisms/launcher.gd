extends PieceBehavior

@export var area: Area3D
@export var release_point: Marker3D
@export var loading_seat: Marker3D
const LOAD_TIME: float = 0.2
const RELEASE_TIME: float = 0.1
var stroking: bool = false
var seated_body: Marble
var seat_from: Vector3
var seat_time: float = 0.0
var cooldown: float = 0
var fired: Dictionary = {}
var has_fired: bool = false
var pending: bool = false
var waiting: Array[Marble] = []
@export var arrow: Node3D
@export var handle_animation: AnimationPlayer

func _ready() -> void:
	inputs = {"fire": func(_value: Variant): pending = true, "activate": func(_value: Variant): enabled = true, "deactivate": func(_value: Variant): enabled = false}
	outputs = ["activated"]
	outputs.append("fired")
	state_outputs = {"loaded": false}
	area.body_entered.connect(_capture_marble)
	area.body_exited.connect(func(body: Node3D):
		if body.global_position.distance_to(area.global_position) > 0.6: fired.erase(body.get_instance_id()))
	reset()

func _capture_marble(body: Node3D) -> void:
	if not active or not enabled or not body is Marble or body in waiting: return
	# Area overlap includes a sphere passing above the deck or beyond its lip.
	# Only a marble at loading height, behind the seat, can be claimed.
	var point := to_local(body.global_position)
	var armed_seat := to_local(arrow.to_global(loading_seat.position))
	if absf(point.y - armed_seat.y) > 0.05 or point.z < armed_seat.z: return
	if fired.has(body.get_instance_id()) or not body.capture(): return
	# Own arrivals while the loading cradle seats and throws the first marble.
	waiting.append(body)

func _release_waiting() -> void:
	for body in waiting:
		if is_instance_valid(body): body.release_capture()
	waiting.clear()

func _physics_process(delta: float) -> void:
	if not active: return
	for id in fired.keys():
		var marble_body: Marble = fired[id].get_ref()
		if not is_instance_valid(marble_body) or marble_body.global_position.distance_to(area.global_position) > 0.6: fired.erase(id)
	for body in area.get_overlapping_bodies(): _capture_marble(body)
	waiting = waiting.filter(func(body): return is_instance_valid(body) and body.carried)
	if not enabled:
		emit_output("loaded", false)
		return
	cooldown = maxf(0, cooldown - delta)
	_update_handle()
	if stroking:
		if waiting.is_empty():
			stroking = false
			return
		waiting[0].global_position = loading_seat.global_position
		if 0.5 - cooldown < RELEASE_TIME - 0.000001: return
		_release_loaded()
		return
	if cooldown > 0 or waiting.is_empty():
		emit_output("loaded", false)
		return
	if not config.get("auto_rearm", true) and has_fired: return
	if seated_body != waiting[0]:
		seated_body = waiting[0]
		seat_from = seated_body.global_position
		seat_time = 0.0
	seat_time = minf(LOAD_TIME, seat_time + delta)
	var armed_position := arrow.to_global(loading_seat.position)
	seated_body.global_position = seat_from.lerp(armed_position, smoothstep(0.0, LOAD_TIME, seat_time))
	var is_loaded := seat_time >= LOAD_TIME
	emit_output("loaded", is_loaded)
	if not is_loaded: return
	if config.get("external", false) and not pending: return
	stroking = true
	pending = false
	cooldown = 0.5
	emit_output("loaded", false)
	_update_handle()

func _release_loaded() -> void:
	var next_body: Marble = waiting.pop_front()
	fired[next_body.get_instance_id()] = weakref(next_body)
	next_body.global_position = release_point.global_position
	next_body.release_capture(launch_velocity())
	next_body.angular_velocity = Vector3.ZERO
	next_body.sleeping = false
	next_body.reset_physics_interpolation()
	has_fired = true
	stroking = false
	seated_body = null
	emit_output("fired", next_body)

func _exit_tree() -> void:
	_release_waiting()

func _update_handle() -> void:
	if not handle_animation: return
	var clip: StringName = &"armed"
	var time := 0.0
	if not enabled and not stroking:
		clip = &"unarmed"
	elif cooldown > 0.32:
		clip = &"fire"
		time = 0.5 - cooldown
	elif has_fired and not config.get("auto_rearm", true):
		clip = &"unarmed"
	elif cooldown > 0:
		clip = &"rearm"
		time = 0.32 - cooldown
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
	var origin := release_point.global_position
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = preload("res://scenes/marble_shape.tres")
	query.collision_mask = 1
	query.exclude = excluded
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
	_release_waiting()
	super.reset()
	fired.clear()
	has_fired = false
	cooldown = 0
	pending = false
	stroking = false
	seated_body = null
	seat_time = 0.0
	_update_handle()

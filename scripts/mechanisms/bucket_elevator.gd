extends Node3D

signal marble_loaded(body: RigidBody3D)
signal marble_unloaded(body: RigidBody3D)

const Geometry = preload("res://scripts/mechanisms/elevator_geometry.gd")
const BucketScene = preload("res://scenes/mechanisms/elevator_bucket.tscn")
const FrameScene = preload("res://scenes/mechanisms/elevator_frame_section.tscn")
const Capture = preload("res://scripts/mechanisms/marble_capture.gd")
const TURN_RADIUS = 0.75
const BUCKET_SPACING = 1.4
var lift_height: float = Geometry.DEFAULT_HEIGHT
var travel_speed: float = Geometry.DEFAULT_SPEED
var active: bool = false
var preview_only: bool = false
var phase: float = 0.0
var buckets: Array[Node3D] = []
var waiting: Array[RigidBody3D] = []
var loaded_count: int = 0
var unloaded_count: int = 0

func _ready() -> void:
	$LoadingSensor.body_entered.connect(_queue_marble)
	$LoadingSensor.body_exited.connect(_remove_waiting)
	configure(lift_height, travel_speed, false)

func configure(new_height: float, new_speed: float, ghost: bool) -> void:
	reset()
	lift_height = new_height
	travel_speed = new_speed
	preview_only = ghost
	for child in $Frames.get_children(): child.free()
	var shaft_length = lift_height + 1.1
	for index in ceili(shaft_length):
		var section = FrameScene.instantiate()
		section.position.y = float(index)
		section.scale.y = minf(1.0, shaft_length - float(index))
		$Frames.add_child(section)
	$TopDrive.position.y = lift_height + 0.85
	$Output.position.y = lift_height
	for bucket in $Buckets.get_children(): bucket.free()
	buckets.clear()
	var count = maxi(6, floori(loop_length() / BUCKET_SPACING))
	for index in count:
		var bucket = BucketScene.instantiate()
		$Buckets.add_child(bucket)
		buckets.append(bucket)
	if preview_only:
		for body in find_children("*", "CollisionObject3D", true, false):
			body.collision_layer = 0
			body.collision_mask = 0
	arrange(0)

func straight_length() -> float:
	return lift_height + 0.1

func loop_length() -> float:
	return 2.0 * straight_length() + TAU * TURN_RADIUS

func sample(distance_along: float) -> Dictionary:
	var distance = fposmod(distance_along, loop_length())
	var leg = straight_length()
	var arc = PI * TURN_RADIUS
	var point: Vector3
	var tip_angle = 0.0
	var ascending = distance < leg
	if ascending:
		point = Vector3(0, TURN_RADIUS + distance, 0)
		tip_angle = -deg_to_rad(65) * smoothstep(lift_height + 0.35, lift_height + 0.8, point.y)
	elif distance < leg + arc:
		var angle = (distance - leg) / TURN_RADIUS
		point = Vector3(0, lift_height + 0.85 + TURN_RADIUS * sin(angle), TURN_RADIUS - TURN_RADIUS * cos(angle))
		tip_angle = -deg_to_rad(65) * (1.0 - smoothstep(0, PI, angle))
	elif distance < 2.0 * leg + arc:
		point = Vector3(0, lift_height + 0.85 - (distance - leg - arc), 1.5)
	else:
		var angle = (distance - 2.0 * leg - arc) / TURN_RADIUS
		point = Vector3(0, TURN_RADIUS - TURN_RADIUS * sin(angle), TURN_RADIUS + TURN_RADIUS * cos(angle))
	return {"point": point, "tip": tip_angle, "ascending": ascending, "distance": distance}

func arrange(delta: float) -> void:
	for index in buckets.size():
		var pose_data = sample(phase + index * loop_length() / buckets.size())
		buckets[index].pose(pose_data.point, pose_data.tip, delta)
	$TopDrive.rotation.x = -phase / TURN_RADIUS
	$BottomDrive.rotation.x = -phase / TURN_RADIUS

func _physics_process(delta: float) -> void:
	if not active or preview_only: return
	phase = fposmod(phase + travel_speed * delta, loop_length())
	arrange(delta)
	for index in buckets.size():
		var bucket = buckets[index]
		var pose_data = sample(phase + index * loop_length() / buckets.size())
		if bucket.occupied() and pose_data.ascending and pose_data.point.y >= lift_height + 0.8:
			var released: RigidBody3D = bucket.transport.marble
			# Give the tipped marble momentum onto the outlet even at slow belt speeds.
			bucket.unload(global_basis * Vector3(0, 0, -clampf(travel_speed + 0.6, 1.4, 2.6)))
			unloaded_count += 1
			marble_unloaded.emit(released)
		elif not bucket.occupied() and pose_data.point.y < 0.22 and pose_data.point.z < 0.48:
			for body in waiting.duplicate():
				if not is_instance_valid(body) or Capture.is_carried(body): waiting.erase(body); continue
				var local_point = to_local(body.global_position)
				if absf(local_point.x) > 0.25 or local_point.y > 0.72 or local_point.z < -0.35: continue
				if bucket.capture(body):
					waiting.erase(body)
					loaded_count += 1
					marble_loaded.emit(body)
					break

func _queue_marble(body: Node3D) -> void:
	if body is RigidBody3D and body.collision_layer & 2 and not body in waiting and not Capture.is_carried(body): waiting.append(body)

func _remove_waiting(body: Node3D) -> void:
	waiting.erase(body)

func reset() -> void:
	active = false
	phase = 0
	for bucket in buckets: bucket.reset()
	waiting.clear()
	loaded_count = 0
	unloaded_count = 0
	if is_inside_tree(): arrange(0)

func _exit_tree() -> void:
	reset()

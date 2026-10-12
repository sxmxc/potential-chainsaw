extends Node3D

const Capture = preload("res://scripts/mechanisms/marble_capture.gd")
var transport: RefCounted
var capture_offset: Vector3
var capture_age: float = 0.0

func capture(body: RigidBody3D) -> bool:
	if occupied(): return false
	var candidate = Capture.new()
	if not candidate.claim(body, self): return false
	transport = candidate
	capture_offset = to_local(body.global_position)
	capture_age = 0
	return true

func occupied() -> bool:
	return transport != null and is_instance_valid(transport.marble)

func pose(point: Vector3, tip_angle: float, delta: float) -> void:
	position = point
	$Tray.rotation.x = tip_angle
	if not occupied(): return
	capture_age += delta
	var blend = smoothstep(0.0, 0.3, capture_age)
	var seat = Vector3(0, 0.45, lerpf(-0.15, -0.25, clampf(-tip_angle / deg_to_rad(65), 0, 1)))
	var seated: Vector3 = $Tray.transform * seat
	transport.place(global_transform * capture_offset.lerp(seated, blend))

func unload(velocity: Vector3) -> void:
	if transport:
		var body: RigidBody3D = transport.marble
		transport.release(velocity)
		if is_instance_valid(body):
			# Match outlet rolling speed instead of restoring the incoming spin.
			var collision = body.get_node("Collision") as CollisionShape3D
			var sphere = collision.shape as SphereShape3D
			body.angular_velocity = global_basis.y.cross(velocity) / sphere.radius
	transport = null

func reset() -> void:
	if transport: transport.release()
	transport = null
	capture_age = 0
	$Tray.rotation = Vector3.ZERO

func _exit_tree() -> void:
	reset()

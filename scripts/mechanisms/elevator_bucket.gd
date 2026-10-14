extends Node3D

var marble: Marble
var capture_offset: Vector3
var capture_age: float = 0.0

func capture(body: Marble) -> bool:
	if occupied(): return false
	if not is_instance_valid(body) or not body.capture(): return false
	marble = body
	capture_offset = to_local(body.global_position)
	capture_age = 0
	return true

func occupied() -> bool:
	return is_instance_valid(marble)

func pose(point: Vector3, tip_angle: float, delta: float) -> void:
	position = point
	$Tray.rotation.x = tip_angle
	if not occupied(): return
	capture_age += delta
	var blend = smoothstep(0.0, 0.3, capture_age)
	var seat = Vector3(0, 0.45, lerpf(-0.15, -0.25, clampf(-tip_angle / deg_to_rad(65), 0, 1)))
	var seated: Vector3 = $Tray.transform * seat
	marble.global_position = global_transform * capture_offset.lerp(seated, blend)

func unload(velocity: Vector3) -> void:
	if occupied():
		marble.release_capture(velocity)
		# Match outlet rolling speed instead of restoring the incoming spin.
		var collision = marble.get_node("Collision") as CollisionShape3D
		var sphere = collision.shape as SphereShape3D
		marble.angular_velocity = global_basis.y.cross(velocity) / sphere.radius
	marble = null

func reset() -> void:
	if occupied(): marble.release_capture()
	marble = null
	capture_age = 0
	$Tray.rotation = Vector3.ZERO

func _exit_tree() -> void:
	reset()

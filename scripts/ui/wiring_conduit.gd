class_name WiringConduit
extends MeshInstance3D

## One cached, world-space tube. Both rendering and hit testing use this centerline.
const RADIUS := 0.024
const SEGMENTS := 64
const SIDES := 12
const MATERIAL: Material = preload("res://resources/wiring_conduit_material.tres")
var points := PackedVector3Array()
var signature: Array = []
var emphasis: float = 0.0

func _init() -> void:
	material_override = MATERIAL
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func route(start: Vector3, finish: Vector3, lane: int = 0) -> void:
	var next_signature: Array = [start, finish, lane]
	if signature == next_signature: return
	signature = next_signature
	var span := Vector2(finish.x - start.x, finish.z - start.z).length()
	var lift := clampf(span * 0.22, 0.35, 1.8) + lane * 0.12
	var side := (finish - start).cross(Vector3.UP).normalized() * lane * 0.16
	if Vector2(finish.x - start.x, finish.z - start.z).length() < RADIUS * 4:
		# Stacked terminals need a lateral bow rather than a tube doubling back on itself.
		side = Vector3.FORWARD * (lift * 0.5 + lane * 0.16)
	var first := start + Vector3.UP * lift + side
	var second := finish + Vector3.UP * lift + side
	points.clear()
	for i in SEGMENTS + 1:
		points.append(start.bezier_interpolate(first, second, finish, i / float(SEGMENTS)))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var distance := 0.0
	# Parallel transport avoids twisting frames on vertical and very short connections.
	var previous_normal := Vector3.RIGHT
	for i in points.size():
		if i > 0: distance += points[i].distance_to(points[i - 1])
		var tangent := (points[mini(i + 1, SEGMENTS)] - points[maxi(i - 1, 0)]).normalized()
		var normal := previous_normal - tangent * previous_normal.dot(tangent)
		if normal.length_squared() < 0.001: normal = tangent.cross(Vector3.FORWARD)
		normal = normal.normalized()
		var binormal := tangent.cross(normal).normalized()
		previous_normal = normal
		for j in SIDES + 1:
			var angle := TAU * j / SIDES
			var radial := normal * cos(angle) + binormal * sin(angle)
			surface.set_normal(radial)
			surface.set_uv(Vector2(distance, j / float(SIDES)))
			surface.set_uv2(Vector2(i / float(SEGMENTS), 0))
			surface.add_vertex(points[i] + radial * RADIUS)
			if i < SEGMENTS and j < SIDES:
				var index := i * (SIDES + 1) + j
				for vertex in [index, index + SIDES + 1, index + 1, index + 1, index + SIDES + 1, index + SIDES + 2]:
					surface.add_index(vertex)
	mesh = surface.commit()

func project(camera: Camera3D) -> PackedVector2Array:
	var projected := PackedVector2Array()
	for point in points:
		# Never connect points across the camera plane in screen-space hit testing.
		if camera.is_position_behind(point): return PackedVector2Array()
		projected.append(camera.unproject_position(point))
	return projected

func emphasize(active: bool, delta: float) -> void:
	emphasis = move_toward(emphasis, 1.0 if active else 0.0, delta * 7.0)
	set_instance_shader_parameter("focus", emphasis)

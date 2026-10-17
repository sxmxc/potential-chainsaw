class_name WiringConduit
extends MeshInstance3D

## One cached signal path. Rendering and hit testing share its rounded centerline.
const RADIUS := 0.009
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
	var lift := 0.24 + lane * 0.08
	var side := (finish - start).cross(Vector3.UP).normalized() * lane * 0.16
	var height := maxf(start.y, finish.y) + lift
	var first := Vector3(start.x, height, start.z) + side
	var second := Vector3(finish.x, height, finish.z) + side
	if span < 0.08:
		# Route stacked terminals around the side instead of doubling back vertically.
		side = Vector3.FORWARD * (0.24 + lane * 0.16)
		first = start + side
		second = finish + side
	var path := PackedVector3Array([start])
	var corners: Array[Vector3] = [start, first, second, finish]
	for corner in range(1, 3):
		var incoming := corners[corner - 1] - corners[corner]
		var outgoing := corners[corner + 1] - corners[corner]
		var radius := minf(0.12, minf(incoming.length(), outgoing.length()) * 0.4)
		var entry := corners[corner] + incoming.normalized() * radius
		var exit := corners[corner] + outgoing.normalized() * radius
		path.append(entry)
		for step in range(1, 9):
			var t := step / 8.0
			path.append(entry.lerp(corners[corner], t).lerp(corners[corner].lerp(exit, t), t))
	path.append(finish)
	# Uniform distance samples keep picking and animation consistent along straight legs and bends.
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		lengths.append(lengths[-1] + path[i - 1].distance_to(path[i]))
	points.clear()
	var segment := 1
	for i in SEGMENTS + 1:
		var along := lengths[-1] * i / float(SEGMENTS)
		while segment < path.size() - 1 and lengths[segment] < along:
			segment += 1
		var fraction := (along - lengths[segment - 1]) / maxf(lengths[segment] - lengths[segment - 1], 0.000001)
		points.append(path[segment - 1].lerp(path[segment], fraction))
	points[0] = start
	points[-1] = finish
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

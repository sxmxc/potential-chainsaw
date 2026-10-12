extends MarbleMechanism

var area: Area3D
var blade: MeshInstance3D
var rest: Transform3D
var axis: Vector3 = Vector3.UP
var origin: Vector3 = Vector3(0, 0.3, 0)
var angle: float = 0
var arrow: Node3D

func setup(target: MeshInstance3D, standing: bool) -> void:
	blade = target
	rest = blade.transform
	if standing:
		axis = Vector3.FORWARD
		origin = Vector3(0, 0.5, -0.15)
	area = detection(Vector3.ONE, origin)
	arrow = Node3D.new()
	add_child(arrow)
	var shaft = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.035
	cylinder.bottom_radius = 0.035
	cylinder.height = 0.4
	shaft.mesh = cylinder
	shaft.position.y = 0.2
	arrow.add_child(shaft)
	var tip = MeshInstance3D.new()
	var cone = CylinderMesh.new()
	cone.top_radius = 0
	cone.bottom_radius = 0.1
	cone.height = 0.2
	tip.mesh = cone
	tip.position.y = 0.45
	arrow.add_child(tip)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("59e5b1")
	shaft.material_override = material
	tip.material_override = material
	actions = {"activate": func(): enabled = true, "deactivate": func(): enabled = false, "toggle": func(): enabled = not enabled, "switch_direction": switch_direction}
	events = ["activated"]
	configure({})

func configure(settings: Dictionary) -> void:
	super.configure(settings)
	update_field()

func switch_direction() -> void:
	config.reverse = not config.get("reverse", false)
	update_field()

func update_field() -> void:
	if not area: return
	var reach = clampf(float(config.get("range", 4)), 0.5, 10)
	var direction = axis * (-1 if config.get("reverse", false) else 1)
	arrow.position = origin + Vector3(0.58, 0, 0)
	arrow.rotation.x = (-PI / 2 if axis == Vector3.FORWARD else 0.0) + (PI if config.get("reverse", false) else 0.0)
	area.position = origin + direction * reach * 0.5
	var box = area.get_child(0).shape as BoxShape3D
	box.size = Vector3(0.9, reach, 0.9) if axis == Vector3.UP else Vector3(0.9, 0.9, reach)

func _physics_process(delta: float) -> void:
	if not active or not enabled: return
	var reverse = -1.0 if config.get("reverse", false) else 1.0
	angle += delta * 8 * reverse
	blade.transform = rest * Transform3D(Basis(axis, angle), Vector3.ZERO)
	var direction = global_basis * axis * reverse
	var reach = clampf(float(config.get("range", 4)), 0.5, 10)
	var power = clampf(float(config.get("power", 1.2)), 0, 5)
	for body in area.get_overlapping_bodies():
		if not is_marble(body): continue
		var distance = maxf(0, (body.global_position - to_global(origin)).dot(direction))
		body.apply_central_force(direction * power * pow(maxf(0, 1 - distance / reach), 2))

func reset() -> void:
	super.reset()
	angle = 0
	if is_instance_valid(blade): blade.transform = rest

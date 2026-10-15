extends PieceBehavior

@export var area: Area3D
@export var blade: MeshInstance3D
var rest: Transform3D
@export var axis: Vector3 = Vector3.UP
@export var origin: Vector3 = Vector3(0, 0.3, 0)
var angle: float = 0
@export var arrow: Node3D
@export var blade_speed: float = 8.0

func _ready() -> void:
	rest = blade.transform
	inputs = {"activate": func(_value: Variant): enabled = true, "deactivate": func(_value: Variant): enabled = false, "toggle": func(_value: Variant): enabled = not enabled, "switch_direction": switch_direction}
	outputs = ["activated"]
	configure(config)

func configure(settings: Dictionary) -> void:
	super.configure(settings)
	update_field()

func switch_direction(_value: Variant = null) -> void:
	config.reverse = not config.get("reverse", false)
	update_field()

func update_field() -> void:
	if not area: return
	var reach = float(config.get("range", 4))
	#var direction = axis * (-1 if config.get("reverse", false) else 1)
	#arrow.position = origin + Vector3(0.58, 0, 0)
	arrow.rotation.x = (-PI / 2 if axis == Vector3.FORWARD else 0.0) + (PI if config.get("reverse", false) else 0.0)
	#area.position = origin + direction * reach * 0.5
	var box: BoxShape3D = area.get_child(0).shape
	var dimensions: Vector3 = box.size
	dimensions[axis.abs().max_axis_index()] = reach
	box.size = dimensions

func _physics_process(delta: float) -> void:
	if not active or not enabled: return
	var reverse = -1.0 if config.get("reverse", false) else 1.0
	angle += delta * blade_speed * reverse
	blade.transform = rest * Transform3D(Basis(axis, angle), Vector3.ZERO)
	var direction = global_basis * axis * reverse
	var reach = float(config.get("range", 4))
	var power = float(config.get("power", 1.2))
	for body in area.get_overlapping_bodies():
		if not is_marble(body): continue
		var distance = maxf(0, (body.global_position - to_global(origin)).dot(direction))
		body.apply_central_force(direction * power * pow(maxf(0, 1 - distance / reach), 2))

func reset() -> void:
	super.reset()
	angle = 0
	if is_instance_valid(blade): blade.transform = rest

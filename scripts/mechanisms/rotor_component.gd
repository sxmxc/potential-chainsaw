class_name RotorComponent
extends PieceBehavior

@export var rotor: AnimatableBody3D
@export var mesh: MeshInstance3D
var rest: Transform3D
var speed: float = 1.3
var angle: float = 0.0

func _init() -> void:
	inputs = {"activate": func(_value: Variant): enabled = true, "deactivate": func(_value: Variant): enabled = false, "toggle": func(_value: Variant): enabled = not enabled}
	outputs = ["activated"]

func configure(settings: Dictionary) -> void:
	speed = float(settings.get("angular_speed", 1.3))
	super.configure(settings)

func _ready() -> void:
	rest = mesh.transform
	reset()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(mesh): return
	if active and enabled: angle += speed*delta
	mesh.transform = rest * Transform3D(Basis(Vector3.UP,angle),Vector3.ZERO)
	rotor.global_transform = mesh.global_transform

func reset() -> void:
	super.reset()
	angle = 0
	if is_instance_valid(mesh):
		mesh.transform = rest
		if rotor.is_inside_tree(): rotor.global_transform = mesh.global_transform

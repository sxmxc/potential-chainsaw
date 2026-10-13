extends PieceBehavior

@export var guide: AnimatableBody3D
@export var area: Area3D
var left: bool = false

func _ready() -> void:
	area.body_exited.connect(func(body):
		if not active or not is_marble(body) or absf(to_local(body.global_position).x) < 1: return
		emit_output("routed", body)
		if config.get("alternating", false): left = not left)
	inputs = {"switch_direction": func(_value: Variant): left = not left, "toggle": func(_value: Variant): left = not left, "left": func(_value: Variant): left = true, "right": func(_value: Variant): left = false}
	outputs = ["activated", "routed"]
	reset()

func _physics_process(delta: float) -> void:
	if active:
		guide.rotation.y = move_toward(guide.rotation.y, -PI / 6 if left else PI / 6, delta * 2)
		guide.position.z = move_toward(guide.position.z, 0.0, delta * 0.8)
		guide.position.x = move_toward(guide.position.x, 0.0, delta * 0.8)

func reset() -> void:
	super.reset()
	left = bool(config.get("left", false))
	if guide:
		guide.rotation.y = -PI / 6 if left else PI / 6
		guide.position.x = 0.0
		guide.position.z = 0.0


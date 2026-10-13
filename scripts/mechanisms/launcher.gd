extends PieceBehavior

@export var area: Area3D
var cooldown: float = 0
var fired: Dictionary = {}
var pending: bool = false
@export var loading_stop: AnimatableBody3D
@export var arrow: MeshInstance3D

func _ready() -> void:
	inputs = {"fire": func(_value: Variant): pending = true, "activate": func(_value: Variant): enabled = true, "deactivate": func(_value: Variant): enabled = false}
	outputs = ["activated"]
	outputs.append("fired")
	reset()

func _physics_process(delta: float) -> void:
	if not active or not enabled: return
	cooldown = maxf(0, cooldown - delta)
	var was_blocked = loading_stop.position.y < 1
	loading_stop.position.y = 1.25 if not config.get("external", false) or pending or cooldown > 0 else 0.525
	# Let the physics server commit the raised stop before applying the launch impulse.
	if was_blocked and loading_stop.position.y > 1: return
	if not config.get("auto_rearm", true) and not fired.is_empty(): return
	if cooldown > 0 or (config.get("external", false) and not pending): return
	for body in area.get_overlapping_bodies():
		if not is_marble(body) or fired.has(body.get_instance_id()): continue
		var elevation = deg_to_rad(float(config.get("angle", 25)))
		var direction = global_basis * Vector3(0, sin(elevation), -cos(elevation))
		body.apply_central_impulse(direction * body.mass * float(config.get("strength", 4)))
		fired[body.get_instance_id()] = true
		pending = false
		cooldown = 0.5
		emit_output("fired", body)
		break

func reset() -> void:
	super.reset()
	fired.clear()
	cooldown = 0
	pending = false
	if loading_stop: loading_stop.position.y = 0.525 if config.get("external", false) else 1.25
	if arrow: arrow.rotation.x = -deg_to_rad(float(config.get("angle", 25)))

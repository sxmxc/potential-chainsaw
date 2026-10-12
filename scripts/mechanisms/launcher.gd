extends MarbleMechanism

var area: Area3D
var cooldown: float = 0
var fired: Dictionary = {}
var pending: bool = false
var loading_stop: AnimatableBody3D
var arrow: AnimatableBody3D

func _ready() -> void:
	area = detection(Vector3(0.5, 0.65, 0.1), Vector3(0, 0.55, -0.55))
	loading_stop = moving_box(Vector3(0.48, 0.55, 0.1), Vector3(0, 1.25, -0.8), Color("80b9af"))
	arrow = moving_box(Vector3(0.08, 0.08, 0.6), Vector3(0.4, 0.65, -0.05), Color("ffc66d"))
	arrow.collision_layer = 0
	arrow.rotation.x = -PI / 6
	actions = {"fire": func(): pending = true, "activate": func(): enabled = true, "deactivate": func(): enabled = false}
	events = ["activated"]
	events.append("fired")
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
		var elevation = deg_to_rad(clampf(float(config.get("angle", 25)), 0, 65))
		var direction = global_basis * Vector3(0, sin(elevation), -cos(elevation))
		body.apply_central_impulse(direction * body.mass * clampf(float(config.get("strength", 4)), 0.5, 8))
		fired[body.get_instance_id()] = true
		pending = false
		cooldown = 0.5
		event_raised.emit("fired", body)
		break

func reset() -> void:
	super.reset()
	fired.clear()
	cooldown = 0
	pending = false
	if loading_stop: loading_stop.position.y = 0.525 if config.get("external", false) else 1.25
	if arrow: arrow.rotation.x = -deg_to_rad(clampf(float(config.get("angle", 25)), 0, 65))


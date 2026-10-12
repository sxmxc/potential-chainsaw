extends MarbleMechanism

var guide: AnimatableBody3D
var area: Area3D
var left: bool = false

func _ready() -> void:
	guide = moving_box(Vector3(0.08, 0.48, 1.2), Vector3(0, 0.49, 0.0), Color("80b9af"))
	area = detection(Vector3(2.6, 0.7, 1.6), Vector3(0, 0.55, 0))
	area.body_exited.connect(func(body):
		if not active or not is_marble(body) or absf(to_local(body.global_position).x) < 1: return
		event_raised.emit("routed", body)
		if config.get("alternating", false): left = not left)
	actions = {"switch_direction": func(): left = not left, "toggle": func(): left = not left, "left": func(): left = true, "right": func(): left = false}
	events = ["activated", "routed"]
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


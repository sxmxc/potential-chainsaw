extends MarbleMechanism

var area: Area3D
var indicator: AnimatableBody3D
var occupied: Dictionary = {}

func _ready() -> void:
	area = detection(Vector3(0.5, 0.7, 0.2), Vector3(0, 0.55, 0))
	indicator = moving_box(Vector3(0.06, 0.3, 0.1), Vector3(0.4, 0.65, 0), Color("59e5b1"))
	indicator.collision_layer = 0
	events.append("entered")
	events.append("exited")
	area.body_entered.connect(_entered)
	area.body_exited.connect(_exited)

func _entered(body: Node3D) -> void:
	if not active or not enabled or not is_marble(body) or occupied.has(body.get_instance_id()): return
	occupied[body.get_instance_id()] = true
	event_raised.emit("entered", body)

func _exited(body: Node3D) -> void:
	if not occupied.erase(body.get_instance_id()): return
	if active and config.get("detect_exit", false) and is_marble(body): event_raised.emit("exited", body)

func reset() -> void:
	super.reset()
	occupied.clear()

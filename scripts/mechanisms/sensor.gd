extends PieceBehavior

@export var area: Area3D
@export var indicator_animation: AnimationPlayer
var occupied: Dictionary = {}

func _init() -> void:
	state_outputs = {"occupied": false}

func _ready() -> void:
	outputs.append("entered")
	outputs.append("exited")
	area.body_entered.connect(_entered)
	area.body_exited.connect(_exited)
	reset()

func _entered(body: Node3D) -> void:
	if not active or not enabled or not is_marble(body) or occupied.has(body.get_instance_id()): return
	occupied[body.get_instance_id()] = true
	indicator_animation.play("occupied")
	emit_output("occupied", true)
	emit_output("entered", body)

func _exited(body: Node3D) -> void:
	if not occupied.erase(body.get_instance_id()): return
	if occupied.is_empty():
		indicator_animation.play("idle")
		emit_output("occupied", false)
	if active and config.get("detect_exit", false) and is_marble(body): emit_output("exited", body)

func reset() -> void:
	super.reset()
	occupied.clear()
	indicator_animation.play("idle")

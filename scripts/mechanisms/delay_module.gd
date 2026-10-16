extends PieceBehavior

@export var indicator: MeshInstance3D
@export var readout: Label3D
var delay_seconds: float = 1.0
var elapsed: float = 0.0
var pending: Array[Dictionary] = []

func _init() -> void:
	inputs = {"input": _enqueue, "reset": _clear}
	outputs = ["output"]

func reset() -> void:
	super.reset()
	delay_seconds = maxf(0.0, float(config.get("delay", 1.0)))
	elapsed = 0.0
	pending.clear()
	_update_display()

func _enqueue(value: Variant) -> void:
	if not enabled: return
	if delay_seconds == 0.0:
		emit_output("output", value)
		return
	# Keep object identity (e.g. a marble), but capture mutable value payloads now.
	var payload: Variant = value.duplicate(true) if value is Array or value is Dictionary else value
	pending.append({"due": elapsed + delay_seconds, "value": payload})
	_update_display()

func _clear(_value: Variant) -> void:
	if not enabled: return
	pending.clear()
	_update_display()

func _physics_process(delta: float) -> void:
	if not active or not enabled: return
	elapsed += delta
	# Pop before emitting: downstream wiring can reset or enqueue synchronously.
	while active and enabled and not pending.is_empty() and float(pending[0].due) <= elapsed + 0.0000001:
		var delivery: Dictionary = pending.pop_front()
		var payload: Variant = delivery.value
		if typeof(payload) == TYPE_OBJECT and not is_instance_valid(payload): continue
		emit_output("output", payload)
	_update_display()

func _update_display() -> void:
	if indicator:
		indicator.visible = not pending.is_empty()
		if not pending.is_empty():
			indicator.scale.x = clampf(1.0 - (float(pending[0].due) - elapsed) / delay_seconds, 0.001, 1.0)
	if readout: readout.text = "%ds" % delay_seconds

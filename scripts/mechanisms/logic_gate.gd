extends PieceBehavior

enum Operation { AND, OR, NOT }
@export var operation: Operation = Operation.AND
@export var indicator: MeshInstance3D

func _ready() -> void:
	inputs = {"a": _evaluate}
	state_inputs = {"a": false}
	if operation != Operation.NOT:
		inputs.b = _evaluate
		state_inputs.b = false
	outputs = ["rising"]
	state_outputs = {"result": false}
	reset()

func reset() -> void:
	super.reset()
	output_values.result = _result()
	_update_indicator()

func _result() -> bool:
	var a := bool(input_values.get("a", false))
	var b := bool(input_values.get("b", false))
	match operation:
		Operation.AND: return a and b
		Operation.OR: return a or b
		Operation.NOT: return not a
	return false

func signals_ready() -> void:
	super.signals_ready()
	# Initial true is an activation after the state network has settled.
	if enabled and output_values.result: emit_output("rising")

func _evaluate(_value: Variant) -> void:
	if not enabled: return
	var result := _result()
	var previous := bool(output_values.result)
	if result == previous: return
	emit_output("result", result)
	_update_indicator()
	if result and not initializing_signals: emit_output("rising")

func _update_indicator() -> void:
	if indicator: indicator.visible = bool(output_values.get("result", false))

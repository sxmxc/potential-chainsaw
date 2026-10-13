extends PieceBehavior

@export var pulse_input: String = "trigger"
@export var pulse_output: String = "passed"
@export var state_input_name: String = "value"
@export var state_output_name: String = "state"
@export var invert_key: String = ""
var received_pulses: int = 0

func _ready() -> void:
	inputs = {pulse_input: _pulse, state_input_name: _state}
	outputs = [pulse_output]
	state_inputs = {state_input_name: false}
	state_outputs = {state_output_name: false}
	reset()

func _pulse(value: Variant) -> void:
	received_pulses += 1
	emit_output(pulse_output, value)

func _state(value: Variant) -> void:
	var result: bool = value if value is bool else float(value) >= float(config.get("threshold", 2))
	if bool(config.get(invert_key, false)): result = not result
	emit_output(state_output_name, result)

func reset() -> void:
	super.reset()
	received_pulses = 0
	output_values[state_output_name] = bool(config.get(invert_key, false))

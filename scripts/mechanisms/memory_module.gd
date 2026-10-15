extends PieceBehavior

@export var indicator: MeshInstance3D
var stored: bool = false

func _init() -> void:
	inputs = {"set": _set_on, "reset": _set_off, "toggle": _toggle}
	outputs = ["changed"]
	state_outputs = {"state": false}

func reset() -> void:
	super.reset()
	stored = bool(config.get("initial_state", false))
	output_values.state = stored
	_update_indicator()

func _set_on(_value: Variant) -> void: _store(true)
func _set_off(_value: Variant) -> void: _store(false)
func _toggle(_value: Variant) -> void: _store(not stored)

func _store(value: bool) -> void:
	if not enabled or value == stored: return
	stored = value
	_update_indicator()
	emit_output("state", stored)
	emit_output("changed", stored)

func _update_indicator() -> void:
	if indicator: indicator.visible = stored

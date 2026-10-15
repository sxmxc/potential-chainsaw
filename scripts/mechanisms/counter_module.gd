extends PieceBehavior

@export var display: Label3D
@export var display3D: Label3D
@export var indicator: MeshInstance3D
var count: int = 0
var threshold: int = 1
var reached: bool = false

func _init() -> void:
	inputs = {"increment": _increment, "reset": _reset_count}
	outputs = ["reached"]
	state_outputs = {"threshold_reached": false}

func reset() -> void:
	super.reset()
	threshold = maxi(1, int(config.get("threshold", 3)))
	count = maxi(0, int(config.get("initial_count", 0)))
	reached = count >= threshold
	output_values.threshold_reached = reached
	_update_display()

func _increment(_value: Variant) -> void:
	if not enabled: return
	# Saturate only at the integer safety limit; no threshold wrapping/reset.
	count = mini(count, 2147483646) + 1
	if not reached and count >= threshold and config.get("infinite_count", false) == false:
		reached = true
		emit_output("threshold_reached", true)
		emit_output("reached", count)
	_update_display()

func _reset_count(_value: Variant) -> void:
	if not enabled: return
	count = maxi(0, int(config.get("initial_count", 0)))
	reached = count >= threshold
	emit_output("threshold_reached", reached)
	_update_display()

func _update_display() -> void:
	if !config.get("infinite_count", false):
		if display: display.text = "%d / %d" % [count, threshold]
	else:
		if display: display.text = "%d" % [count]
	if config.get("3d_label", false):
		if display3D: display3D.text = str(count)
	display3D.visible = config.get("3d_label", false)
	if indicator: indicator.visible = reached

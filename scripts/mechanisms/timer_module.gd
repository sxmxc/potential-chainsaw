extends PieceBehavior


@onready var indicator: MeshInstance3D = $Housing/Indicator
@onready var readout: Label3D = $Readout
@onready var clock_hand: Node3D = $ClockHand
@onready var timer: Timer = $Timer


func _init() -> void:
	inputs = {
		"start": _start,
		"stop": _stop,
		"reset": _restart,
	}
	outputs = ["tick"]


func _ready() -> void:
	timer.timeout.connect(_on_timeout)


func reset() -> void:
	super.reset()

	timer.stop()
	timer.paused = false
	timer.wait_time = 1.0 / maxf(0.01, float(config.get("frequency", 1.0)))
	timer.one_shot = not bool(config.get("loop", true))

	if bool(config.get("auto_start", true)):
		timer.start()

	_update_display()


func _start(_value: Variant) -> void:
	if not enabled:
		return

	if timer.paused:
		timer.paused = false
	elif timer.is_stopped():
		timer.start()

	_update_display()


func _stop(_value: Variant) -> void:
	if not enabled:
		return

	timer.paused = true
	_update_display()


func _restart(_value: Variant) -> void:
	if not enabled:
		return

	timer.paused = false
	timer.start()
	_update_display()


func _on_timeout() -> void:
	if active and enabled:
		emit_output("tick")

	_update_display()


func _process(_delta: float) -> void:
	var progress := 0.0

	if not timer.is_stopped():
		progress = 1.0 - timer.time_left / timer.wait_time

	if clock_hand:
		clock_hand.rotation.y = -TAU * progress

	if readout:
		readout.text = "%.2f%s" % [timer.time_left, get_config_property("frequency","unit")]


func _update_display() -> void:
	if indicator:
		indicator.visible = not timer.is_stopped() and not timer.paused

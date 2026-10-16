extends PieceBehavior


@onready var indicator: MeshInstance3D = $Housing/Indicator
@onready var readout: Label3D = $Readout
@onready var clock_hand: Node3D = $ClockHand
@onready var timer: Timer = $Timer
var has_started: bool = false


func _init() -> void:
	inputs = {
		"start": _start,
		"stop": _stop,
		"reset": _restart,
	}
	outputs = ["tick"]


func _ready() -> void:
	timer.timeout.connect(_on_timeout)
	activity_changed.connect(_activity_changed)
	_activity_changed(active)


func reset() -> void:
	super.reset()
	timer.stop()
	timer.paused = false
	# Retain the saved key; the value is the countdown duration in seconds.
	timer.wait_time = maxf(0.01, float(config.get("frequency", 1.0)))
	timer.one_shot = not bool(config.get("loop", true))
	has_started = false

	_update_display()


func start_run() -> void:
	super.start_run()
	if active and enabled and bool(config.get("auto_start", true)):
		_start(null)


func _activity_changed(_running: bool) -> void:
	# Suspend the clock without changing the separate Stop input's pause state.
	timer.process_mode = Node.PROCESS_MODE_INHERIT if active and enabled else Node.PROCESS_MODE_DISABLED
	_update_display()


func _start(_value: Variant) -> void:
	if not active or not enabled:
		return

	if timer.is_stopped():
		timer.paused = false
		timer.start()
		has_started = true
	else:
		timer.paused = false

	_update_display()


func _stop(_value: Variant) -> void:
	if not active or not enabled:
		return

	timer.paused = true
	_update_display()


func _restart(_value: Variant) -> void:
	if not active or not enabled:
		return

	timer.paused = false
	timer.start()
	has_started = true
	_update_display()


func _on_timeout() -> void:
	if active and enabled:
		emit_output("tick")

	_update_display()


func _process(_delta: float) -> void:
	_update_clock()


func _update_clock() -> void:
	var progress := 0.0

	if not timer.is_stopped():
		progress = 1.0 - timer.time_left / timer.wait_time

	if clock_hand:
		clock_hand.rotation.y = -TAU * progress

	if readout:
		var remaining := timer.time_left if has_started else timer.wait_time
		readout.text = "%.2fs" % remaining


func _update_display() -> void:
	if indicator:
		indicator.visible = active and enabled and not timer.is_stopped() and not timer.paused
	_update_clock()

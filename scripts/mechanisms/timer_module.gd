extends PieceBehavior

@export var indicator: MeshInstance3D
@export var readout: Label3D
@export var clock_hand: Node3D
var interval: float = 1.0
var remaining: float = 1.0
var running: bool = false
var looping: bool = true

func _init() -> void:
	inputs = {"start": _start, "stop": _stop, "reset": _restart}
	outputs = ["tick"]

func reset() -> void:
	super.reset()
	interval = 1.0 / maxf(0.01, float(config.get("frequency", 1.0)))
	remaining = interval
	looping = bool(config.get("loop", true))
	running = bool(config.get("auto_start", true))
	_update_display()

func _start(_value: Variant) -> void:
	if not enabled: return
	running = true
	_update_display()

func _stop(_value: Variant) -> void:
	if not enabled: return
	running = false
	_update_display()

func _restart(_value: Variant) -> void:
	if not enabled: return
	remaining = interval
	running = true
	_update_display()

func _physics_process(delta: float) -> void:
	if not active or not enabled or not running: return
	remaining -= delta
	while active and enabled and running and remaining <= 0.0000001:
		# Commit before emitting so a wired stop/reset takes effect immediately.
		if looping:
			remaining += interval
		else:
			remaining = interval
			running = false
		emit_output("tick")
	_update_display()

func _update_display() -> void:
	if indicator: indicator.visible = running
	if readout: readout.text = "%g /s" % (1.0 / interval)
	if clock_hand: clock_hand.rotation.y = -TAU * (1.0 - remaining / interval)

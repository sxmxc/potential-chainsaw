extends MarbleMechanism

var barrier: AnimatableBody3D
var open: bool = false
var elapsed: float = 0
var opened_at: float = -1
var timer_fired: bool = false
var clearance: Area3D
var pending_close: bool = false

func _ready() -> void:
	barrier = moving_box(Vector3(0.48, 0.55, 0.1), Vector3(0, 0.525, 0), Color("ffc66d"))
	clearance = detection(Vector3(0.5, 0.75, 0.5), Vector3(0, 0.6, 0))
	actions = {"open": func(): set_open(true), "close": func(): set_open(false), "toggle": func(): set_open(not open), "release": func(): set_open(true)}
	events = ["activated"]
	events.append("opened")
	events.append("closed")
	reset()

func set_open(value: bool) -> void:
	if not value and clearance and clearance.get_overlapping_bodies().any(func(body): return is_marble(body)):
		pending_close = true
		return
	pending_close = false
	if open == value: return
	open = value
	opened_at = elapsed if value else -1.0
	event_raised.emit("opened" if value else "closed", null)

func _physics_process(delta: float) -> void:
	if not active: return
	elapsed += delta
	if pending_close: set_open(false)
	var delay = float(config.get("delay", 0))
	if delay > 0 and not timer_fired and elapsed >= delay:
		timer_fired = true
		set_open(true)
	var close_delay = float(config.get("auto_close", 0))
	if open and close_delay > 0 and elapsed - opened_at >= close_delay: set_open(false)
	barrier.position.y = move_toward(barrier.position.y, 1.25 if open else 0.525, delta * 1.5)

func reset() -> void:
	super.reset()
	elapsed = 0
	opened_at = 0
	timer_fired = false
	pending_close = false
	open = bool(config.get("open", false))
	if barrier: barrier.position.y = 1.25 if open else 0.525

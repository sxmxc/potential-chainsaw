extends MarbleMechanism

var barrier: AnimatableBody3D
var open: bool = false
var elapsed: float = 0
var opened_at: float = -1
var timer_fired: bool = false
var clearance: Area3D
var pending_close: bool = false
var waiting_release: Array[RigidBody3D] = []

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
	waiting_release.clear()
	if value:
		for body in clearance.get_overlapping_bodies():
			if is_marble(body): waiting_release.append(body)
	opened_at = elapsed if value else -1.0
	event_raised.emit("opened" if value else "closed", null)

func _physics_process(delta: float) -> void:
	if not active: return
	elapsed += delta
	# Wait for the physics server to commit a clear opening before nudging.
	if open and barrier.position.y >= 1.0:
		for body in waiting_release:
			if not is_instance_valid(body) or body.freeze or not is_marble(body): continue
			var point = to_local(body.global_position)
			if absf(point.z) > 0.45 or absf(point.x) > 0.45: continue
			var direction = global_basis * Vector3(0, 0, -signf(point.z))
			var speed = body.linear_velocity.dot(direction)
			if speed >= 0.4 or direction.is_zero_approx(): continue
			body.sleeping = false
			body.apply_central_impulse(direction * body.mass * (0.8 - speed))
		waiting_release.clear()
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
	waiting_release.clear()
	open = bool(config.get("open", false))
	if barrier: barrier.position.y = 1.25 if open else 0.525

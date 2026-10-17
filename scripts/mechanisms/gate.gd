extends PieceBehavior

@export var barrier: AnimatableBody3D
@export var closed_height: float = 0.525
@export var open_height: float = 1.25
@export var release_height: float = 1.0
@export var travel_speed: float = 1.5
var open: bool = false
var elapsed: float = 0
var opened_at: float = -1
var timer_fired: bool = false
@export var clearance: Area3D
var pending_close: bool = false
var waiting_release: Array[RigidBody3D] = []

func _ready() -> void:
	clearance.body_entered.connect(func(body: Node3D):
		if active and open and is_marble(body) and body not in waiting_release: waiting_release.append(body))
	inputs = {"open": func(_value: Variant): set_open(true), "close": func(_value: Variant): set_open(false), "toggle": func(_value: Variant): set_open(not open), "release": func(_value: Variant): set_open(true)}
	outputs = ["activated"]
	outputs.append("opened")
	outputs.append("closed")
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
	emit_output("opened" if value else "closed", null)

func _physics_process(delta: float) -> void:
	if not active: return
	elapsed += delta
	# Wait for the physics server to commit a clear opening before nudging.
	if open and barrier.position.y >= release_height:
		for body in waiting_release:
			if not is_instance_valid(body) or body.freeze or not is_marble(body): continue
			var point = to_local(body.global_position)
			# Include a marble resting across the track's inlet seam, not only
			# centers already inside the one-metre channel.
			if absf(point.z) > 0.75 or absf(point.x) > 0.45: continue
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
	barrier.position.y = move_toward(barrier.position.y, open_height if open else closed_height, delta * travel_speed)

func reset() -> void:
	super.reset()
	elapsed = 0
	opened_at = 0
	timer_fired = false
	pending_close = false
	waiting_release.clear()
	open = bool(config.get("open", false))
	if barrier: barrier.position.y = open_height if open else closed_height

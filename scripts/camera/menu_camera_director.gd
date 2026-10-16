extends Node3D
## Scheduling only: PhantomCameraHost owns all transitions and interruption.
@export_range(6.0, 30.0) var wide_duration: float = 11.0
@export_range(4.0, 16.0) var detail_duration: float = 7.0
@export_range(8.0, 30.0) var chase_duration: float = 18.0
@onready var world: WorldManager = $"../Track"
@onready var detail: PhantomCamera3D = $Detail
@onready var detail_shots: Array[Node] = $Shots.get_children()
var active: bool = false
var remaining: float = 0.0
var shot: int = 0
var last_marble_id: int = 0
var detail_index: int = 0
var random = RandomNumberGenerator.new()

func _ready() -> void:
	random.randomize()
	world.simulation.state_changed.connect(_simulation_changed)
	world.simulation_camera.chase.target_lost.connect(_return_wide)
	_update_detail()

func set_active(value: bool) -> void:
	active = value
	_return_wide()

func _return_wide() -> void:
	world.simulation_camera.chase.stop()
	detail.priority = 0
	shot = 0
	remaining = wide_duration

func _simulation_changed(state: SimulationManager.State, _message: String) -> void:
	if state != SimulationManager.State.RUNNING: _return_wide()

func _process(delta: float) -> void:
	if not active: return
	remaining -= delta
	if remaining > 0.0: return
	match shot:
		0:
			_update_detail()
			detail_index = (detail_index + 1) % detail_shots.size()
			detail.priority = 20
			shot = 1
			remaining = detail_duration
		1:
			if _choose_marble():
				shot = 2
				remaining = random.randf_range(maxf(8.0, chase_duration-2.0), minf(30.0, chase_duration+2.0))
			else: _return_wide()
		2:
			world.simulation_camera.chase.stop()
			detail.priority = 0
			shot = 0
			remaining = wide_duration

func _choose_marble() -> bool:
	var candidates: Array[RigidBody3D] = []
	for body in world.simulation_camera.available():
		if body.linear_velocity.length() > 0.4 and not body.freeze:
			candidates.append(body)
	if candidates.size() > 1:
		candidates = candidates.filter(func(body): return body.get_instance_id() != last_marble_id)
	if candidates.is_empty(): return false
	var chosen = candidates[random.randi_range(0, candidates.size()-1)]
	last_marble_id = chosen.get_instance_id()
	return world.simulation_camera.follow(chosen)

func _update_detail() -> void:
	# Authored scene poses; the existing host still owns blending and interruption.
	detail.global_transform = detail_shots[detail_index].global_transform

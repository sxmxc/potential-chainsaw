extends Node3D
## Scheduling only: PhantomCameraHost owns all transitions and interruption.
@export_range(6.0, 60.0) var wide_duration: float = 24.0
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
var chase_age: float = 0.0
var unusable_time: float = 0.0
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
	shot = 0
	world.simulation_camera.chase.stop()
	detail.priority = 0
	remaining = wide_duration

func _simulation_changed(state: SimulationManager.State, _message: String) -> void:
	if state != SimulationManager.State.RUNNING: _return_wide()

func _process(delta: float) -> void:
	if not active: return
	if shot == 2:
		var body := world.simulation_camera.chase.marble
		if not MarbleChase.suitable(body) or body not in world.simulation_camera.available() or body.freeze:
			_return_wide()
			return
		if world.simulation_camera.chase.preparing: return
		detail.priority = 0
		chase_age += delta
		# A collision-compressed spring arm can put the marble outside the view.
		# Give the host time to finish its blend, then abandon obstructed shots.
		if chase_age > world.simulation_camera.chase.transition_duration + 0.5:
			var point := body.get_global_transform_interpolated().origin
			var camera := world.camera
			var frame := camera.get_viewport().get_visible_rect()
			var inset := minf(48.0, minf(frame.size.x, frame.size.y) * 0.05)
			var framed := not camera.is_position_behind(point) and frame.grow(-inset).has_point(camera.unproject_position(point))
			var ray := PhysicsRayQueryParameters3D.create(camera.global_position, point, 1)
			var clear := camera.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
			unusable_time = 0.0 if framed and clear and body.linear_velocity.length() > 0.15 else unusable_time + delta
			if unusable_time > 0.65:
				_return_wide()
				return
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
				chase_age = 0.0
				unusable_time = 0.0
				shot = 2
				remaining = random.randf_range(maxf(8.0, chase_duration-2.0), minf(30.0, chase_duration+2.0))
			else: _return_wide()
		2:
			_return_wide()

func _choose_marble() -> bool:
	var chosen: RigidBody3D
	var best_score: float = INF
	var camera := world.camera
	var frame := camera.get_viewport().get_visible_rect()
	for body in world.simulation_camera.available():
		if body.linear_velocity.length() <= 0.4 or body.freeze: continue
		var point := body.get_global_transform_interpolated().origin
		if camera.is_position_behind(point): continue
		var screen_point := camera.unproject_position(point)
		if not frame.grow(-minf(frame.size.x, frame.size.y) * 0.05).has_point(screen_point): continue
		var ray := PhysicsRayQueryParameters3D.create(camera.global_position, point, 1)
		if not camera.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		# Follow visible action near the current composition instead of a random
		# marble elsewhere in the machine. Prefer a fresh target when possible.
		var score := screen_point.distance_squared_to(frame.get_center()) / frame.size.length_squared()
		if body.get_instance_id() == last_marble_id: score += 1.0
		if score < best_score:
			best_score = score
			chosen = body
	if chosen == null: return false
	last_marble_id = chosen.get_instance_id()
	return world.simulation_camera.follow(chosen)

func _update_detail() -> void:
	# Authored scene poses; the existing host still owns blending and interruption.
	detail.global_transform = detail_shots[detail_index].global_transform

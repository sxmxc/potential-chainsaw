class_name SimulationCamera
extends Node

signal changed
@onready var world: WorldManager = get_parent()
@onready var chase: MarbleChase = $MarbleChase
@export var player_selection: bool = true

func _ready() -> void:
	await world.ready
	world.simulation.state_changed.connect(_state_changed)
	chase.changed.connect(func():
		world.camera.chase_active = is_instance_valid(chase.marble)
		world.camera.drag_button = 0
		changed.emit())

func available() -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	for body in world.simulation.marbles:
		if MarbleChase.suitable(body): result.append(body)
	return result

func follow(body: RigidBody3D) -> bool:
	if world.simulation.state not in [SimulationManager.State.RUNNING, SimulationManager.State.PAUSED]: return false
	if body not in available(): return false
	return chase.follow(body)

func next_marble() -> void:
	var bodies = available()
	if bodies.is_empty(): return
	follow(bodies[(bodies.find(chase.marble)+1) % bodies.size()])

func toggle_follow() -> void:
	if is_instance_valid(chase.marble): chase.stop()
	else: next_marble()

func _state_changed(state: SimulationManager.State, _message: String) -> void:
	if state not in [SimulationManager.State.RUNNING, SimulationManager.State.PAUSED]: chase.stop()
	changed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not player_selection or not world.visible or not world.camera.enabled: return
	if world.simulation.state not in [SimulationManager.State.RUNNING, SimulationManager.State.PAUSED]: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var origin = world.camera.project_ray_origin(event.position)
		var end = origin + world.camera.project_ray_normal(event.position)*300.0
		# Include track geometry, so a marble behind an opaque track isn't selected.
		var query = PhysicsRayQueryParameters3D.create(origin, end, 3)
		var hit = world.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider is RigidBody3D and follow(hit.collider):
			get_viewport().set_input_as_handled()

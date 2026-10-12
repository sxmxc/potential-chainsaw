extends SubViewportContainer

@onready var world_manager: WorldManager =$World/Track
@onready var animation=$World/CameraMotion
var active: bool = false
var restart_delay: float = 0.0
var loops: int = 0

func _ready() -> void:
	var catalog=PieceCatalog.new()
	var serializer=TrackSerializer.new(catalog)
	world_manager.configure(catalog)
	var data=serializer.decode(FileAccess.get_file_as_string("res://resources/examples/spiral-crossing.json"))
	world_manager.load_construction(data.pieces)
	world_manager.build.enabled=false
	world_manager.build.grid_visible=false
	world_manager.build.refresh_grid()
	world_manager.camera.enabled=false
	animation.play("showcase")
	animation.advance(0)
	world_manager.camera._update(1)

func set_active(value: bool) -> void:
	active=value
	if active:
		animation.play("showcase")
		start_roll()
	else:
		animation.pause()
		world_manager.simulation.reset()
		world_manager.build.enabled=false
		world_manager.build.refresh_grid()

func start_roll() -> void:
	world_manager.simulation.start()
	world_manager.build.enabled=false
	restart_delay=0
	loops+=1

func _process(delta: float) -> void:
	if not active: return
	if world_manager.simulation.state in [SimulationManager.State.SUCCESS,SimulationManager.State.FAILED]:
		restart_delay+=delta
		if restart_delay>1.8: start_roll()

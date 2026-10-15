extends SubViewportContainer

@onready var world_manager: WorldManager =$World/Track
@onready var animation=$World/CameraMotion
@onready var director=$World/CameraDirector
var active: bool = false
var loops: int = 0
const MACHINE_PATH = "res://resources/menu_machine.json"

func _ready() -> void:
	var catalog=PieceCatalog.new()
	var serializer=TrackSerializer.new(catalog)
	world_manager.configure(catalog)
	var data=serializer.decode(FileAccess.get_file_as_string(MACHINE_PATH))
	world_manager.load_construction(data.pieces)
	# No completion objective: this is a closed physical circulation machine.
	world_manager.simulation.puzzle={"objectives":[],"time_limit":3600}
	world_manager.build.grid_visible=false
	world_manager.build.refresh_grid()
	animation.play("showcase")
	animation.advance(0)
	world_manager.camera._update(1)

func set_active(value: bool) -> void:
	active=value
	if active:
		animation.play("showcase")
		start_roll()
		director.set_active(true)
	else:
		director.set_active(false)
		animation.pause()
		world_manager.simulation.reset()

func start_roll() -> void:
	world_manager.simulation.start()
	loops+=1

func _process(_delta: float) -> void:
	if not active: return
	if world_manager.simulation.state in [SimulationManager.State.SUCCESS,SimulationManager.State.FAILED]:
		start_roll()

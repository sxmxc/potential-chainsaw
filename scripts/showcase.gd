extends SubViewportContainer

@onready var sandbox=$World/Track
@onready var animation=$World/CameraMotion
var active: bool = false
var restart_delay: float = 0.0
var loops: int = 0

func _ready() -> void:
	var catalog=PieceCatalog.new()
	var serializer=TrackSerializer.new(catalog)
	sandbox.configure(catalog)
	var data=serializer.decode(FileAccess.get_file_as_string("res://resources/examples/spiral-crossing.json"))
	sandbox.load_construction(data.pieces)
	sandbox.build.enabled=false
	sandbox.build.grid_visible=false
	sandbox.build.refresh_grid()
	sandbox.camera.enabled=false
	animation.play("showcase")
	animation.advance(0)
	sandbox.camera._update(1)

func set_active(value: bool) -> void:
	active=value
	if active:
		animation.play("showcase")
		start_roll()
	else:
		animation.pause()
		sandbox.simulation.reset()
		sandbox.build.enabled=false
		sandbox.build.refresh_grid()

func start_roll() -> void:
	sandbox.simulation.start()
	sandbox.build.enabled=false
	restart_delay=0
	loops+=1

func _process(delta: float) -> void:
	if not active: return
	if sandbox.simulation.state in [SimulationManager.State.SUCCESS,SimulationManager.State.FAILED]:
		restart_delay+=delta
		if restart_delay>1.8: start_roll()

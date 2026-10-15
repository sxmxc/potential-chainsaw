extends Node3D
class_name WorldManager

@export var world_music_playlist: AudioStreamPlaylist

@onready var build: BuildManager = $BuildManager
@onready var simulation: SimulationManager = $SimulationManager
@onready var boundary: PuzzleBoundary = $PuzzleBoundary
@onready var camera: ConstructionCamera = $Camera
@onready var simulation_camera: SimulationCamera = $SimulationCamera

func _ready() -> void:
	simulation.state_changed.connect(_refresh_input.unbind(2))
	boundary.interaction_changed.connect(_refresh_input)
	set_input_enabled(false)

# Hosts control camera input; the world's current activity determines whether
# construction is also available. Resetting a run never overrides its host.
func set_input_enabled(active: bool) -> void:
	camera.enabled = active
	_refresh_input()

func _refresh_input() -> void:
	build.enabled = camera.enabled and simulation.state == SimulationManager.State.BUILD and boundary.tool.is_empty() and not boundary.selecting
	if not build.enabled: build.preview.hide()
	build.refresh_grid()
	build.options_changed.emit()

func play_music() -> void:
	if world_music_playlist != null:
		SoundManager.play_music_queue(world_music_playlist)

func configure(catalog: PieceCatalog) -> void:
	build.catalog=catalog
	build.camera=camera
	simulation.build=build

func load_construction(pieces: Array) -> void:
	# Reset callbacks must not treat the incoming puzzle as a dirty old build.
	build.dirty=false
	simulation.reset()
	build.restore(pieces)
	build.history.clear_history()
	build.dirty=false
	build.set_height(0)
	build.frame_all()

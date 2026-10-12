extends Node3D
class_name WorldManager

@export var world_music_playlist: AudioStreamPlaylist

@onready var build: BuildManager = $BuildManager
@onready var simulation: SimulationManager = $SimulationManager
@onready var camera: ConstructionCamera = $Camera
@onready var simulation_camera: SimulationCamera = $SimulationCamera

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
	build.history.clear()
	build.dirty=false
	build.set_height(0)
	build.frame_all()

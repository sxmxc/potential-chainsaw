extends Node3D

@onready var build: BuildManager = $BuildManager
@onready var simulation: SimulationManager = $SimulationManager
@onready var camera: ConstructionCamera = $Camera

func configure(catalog: PieceCatalog) -> void:
	build.catalog=catalog
	build.camera=camera
	simulation.build=build

func load_construction(pieces: Array) -> void:
	simulation.reset()
	build.restore(pieces)
	build.history.clear()
	build.dirty=false
	build.set_height(0)
	build.frame_all()

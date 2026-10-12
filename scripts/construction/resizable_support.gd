extends Node3D

const Geometry=preload("res://scripts/construction/support_geometry.gd")
@export var family: String = "support-four"

func _ready() -> void:
	configure({})

func configure(config: Dictionary) -> void:
	for child in get_children(): child.free()
	for section in Geometry.sections(family,config):
		var model=section.definition.model.instantiate()
		model.name=section.name
		model.transform=section.transform
		add_child(model)

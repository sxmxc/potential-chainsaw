extends Node3D

@export var family: String = "support-four"

func _ready() -> void:
	configure({})

func configure(config: Dictionary) -> void:
	for child in get_children(): child.free()
	var definition := PieceCatalog.REGISTRY.load_entry(StringName(family)) as SupportDefinition
	for section in definition.sections(config):
		var model=section.definition.model.instantiate()
		model.name=section.name
		model.transform=section.transform
		add_child(model)

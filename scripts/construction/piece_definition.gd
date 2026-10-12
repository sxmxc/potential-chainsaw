class_name PieceDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var category: String
@export_multiline var description: String
@export var model: PackedScene
@export var thumbnail: Texture2D
@export var placement_offset: Vector3
@export var bounds: AABB
@export var rotation_steps: int = 4
@export var connectors: Array[TrackConnector] = []
@export_enum("static", "start", "finish", "rotor", "decoration", "support", "elevator", "resizable_support") var behavior: String = "static"
@export var library_visible: bool = true
@export var component_scene: PackedScene
@export var collision_enabled: bool = true
@export var reserve_bounds: bool = false
@export var editable_in_simulation: bool = false
@export var spawn_position: Vector3 = Vector3(0, 0.48, 0)
@export var spawn_direction: Vector3 = Vector3.FORWARD
@export var trigger_position: Vector3 = Vector3(0, 0.5, 0)
@export var trigger_size: Vector3 = Vector3(0.7, 0.7, 0.7)
@export var surface_cells: PackedVector3Array

func footprint() -> Vector3:
	return bounds.size

func player_description() -> String:
	match behavior:
		"start": return "Release a marble here. Adjust its launch speed in the selection card."
		"finish": return "Catch the marble to complete your run."
		"rotor": return "Spinning blades can redirect a moving marble."
		"elevator": return "Lift marbles in circulating buckets. Select to adjust rise and travel speed."
		"support": return "Support an elevated section. Place freely or adjust its height."
		"resizable_support": return "One complete support. Its matching bottom, middle and top adjust to the building level. Select to change height or top style."
		"decoration": return "Add a finishing touch to your construction."
	if connectors.is_empty(): return "Place freely as a track accessory."
	var low=connectors[0].position.y
	var high=low
	for port in connectors:
		low=minf(low,port.position.y)
		high=maxf(high,port.position.y)
	if high-low>0.02: return "Connects track levels %.2f m apart." % (high-low)
	if connectors.size()>2: return "A junction with %d track connections." % connectors.size()
	return "Point at an open connector to attach. Tab cycles available orientations."

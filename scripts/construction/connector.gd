class_name TrackConnector
extends Resource

@export var position: Vector3
@export var outward: Vector3 = Vector3.FORWARD
@export var profile: StringName = &"standard"
## Both, entry, or exit. Static channels are bidirectional.
@export_enum("both", "entry", "exit") var direction: String = "both"

func compatible(other: TrackConnector) -> bool:
	return profile == other.profile and (direction == "both" or other.direction == "both" or direction != other.direction)

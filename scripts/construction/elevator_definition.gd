class_name ElevatorDefinition
extends PieceDefinition

const MIN_HEIGHT = 2.0
const MAX_HEIGHT = 12.0
const HEIGHT_STEP = 0.5
const DEFAULT_HEIGHT = 4.0
const MIN_SPEED = 0.25
const MAX_SPEED = 2.0
const DEFAULT_SPEED = 0.8

func normalized_configuration(config: Dictionary) -> Dictionary:
	var result = super.normalized_configuration(config)
	var settings := resolved_configuration(result)
	var lift_height = settings.get("elevator_height", DEFAULT_HEIGHT)
	var travel_speed = settings.get("elevator_speed", DEFAULT_SPEED)
	if not (lift_height is float or lift_height is int) or not is_finite(float(lift_height)): lift_height = DEFAULT_HEIGHT
	if not (travel_speed is float or travel_speed is int) or not is_finite(float(travel_speed)): travel_speed = DEFAULT_SPEED
	result.elevator_height = clampf(snappedf(float(lift_height), HEIGHT_STEP), MIN_HEIGHT, MAX_HEIGHT)
	result.elevator_speed = clampf(float(travel_speed), MIN_SPEED, MAX_SPEED)
	return result

func configured(config: Dictionary) -> PieceDefinition:
	var result = duplicate(false) as PieceDefinition
	var lift_height: float = normalized_configuration(config).elevator_height
	result.bounds = AABB(Vector3(-0.85, 0, -1.5), Vector3(1.7, lift_height + 2.1, 3.65))
	result.connectors = connectors.duplicate()
	for index in connectors.size():
		var port = connectors[index].duplicate() as TrackConnector
		if index == 1: port.position.y = lift_height + 0.25
		result.connectors[index] = port
	return result

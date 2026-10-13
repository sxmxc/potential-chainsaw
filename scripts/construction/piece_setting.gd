class_name PieceSetting
extends Resource
## An editable piece setting shared by the inspector and puzzle authoring.

enum Kind { NUMBER, FLAG, STRING }

@export var key: StringName
@export var label: String
@export_multiline var description: String
@export var kind: Kind = Kind.NUMBER
@export var default_number: float = 0.0
@export var default_flag: bool = false
@export var default_string: String = ""
@export var minimum: float = 0.0
@export var maximum: float = 1.0
@export var step: float = 0.1
@export var unit: String

func default_value() -> Variant:
	match kind:
		Kind.FLAG:
			return default_flag
		Kind.NUMBER:
			return default_number
		Kind.STRING:
			return default_string
		_:
			return default_number

func normalized(value: Variant) -> Variant:
	if kind == Kind.FLAG: return bool(value)
	if kind == Kind.STRING : return String(value)
	if not (value is float or value is int) or not is_finite(float(value)):
		return default_number
	return clampf(float(value), minimum, maximum)

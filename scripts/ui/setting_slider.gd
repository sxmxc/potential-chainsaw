@tool
class_name SettingSlider
extends HSlider

signal setting_changed(new_value: float)

@export var suffix: String = "":
	set(new_suffix):
		suffix = new_suffix
		if is_node_ready(): refresh_labels()

var dragging: bool = false

func _ready() -> void:
	changed.connect(refresh_labels)
	value_changed.connect(func(new_value: float):
		refresh_labels()
		if not dragging: setting_changed.emit(new_value))
	drag_started.connect(func(): dragging = true)
	drag_ended.connect(func(was_changed: bool):
		dragging = false
		if was_changed: setting_changed.emit(value))
	refresh_labels()

func refresh_labels() -> void:
	var unit := " " + suffix if not suffix.is_empty() else ""
	var precision := step_decimals(step)
	%Current.text = String.num(value, precision).trim_suffix(".0") + unit
	%Minimum.text = String.num(min_value, precision).trim_suffix(".0") + unit
	%Maximum.text = String.num(max_value, precision).trim_suffix(".0") + unit

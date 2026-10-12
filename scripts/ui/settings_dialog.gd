extends "res://scripts/ui/modal_window.gd"
signal sensitivity_changed(value: float)
signal reset_camera
func _ready() -> void:
	super()
	%Close.pressed.connect(close)
	%ResetCamera.pressed.connect(func():reset_camera.emit())
	%Sensitivity.value_changed.connect(func(value):sensitivity_changed.emit(value))
func set_sensitivity(value: float) -> void:
	%Sensitivity.set_value_no_signal(value)

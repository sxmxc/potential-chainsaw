extends "res://scripts/ui/modal_window.gd"
signal sensitivity_changed(value: float)
signal reset_camera
func _ready() -> void:
	super()
	%Close.pressed.connect(close)
	%ResetCamera.pressed.connect(func():reset_camera.emit())
	%Sensitivity.value_changed.connect(func(value):sensitivity_changed.emit(value))
	%Tabs.tab_changed.connect(func(_index): fit_content.call_deferred())
	visibility_changed.connect(func(): if visible: fit_content.call_deferred())

func fit_content() -> void:
	if not visible: return
	size=Vector2i(620,int(get_node("Surface").get_combined_minimum_size().y))
	popup_centered(size)
func set_sensitivity(value: float) -> void:
	%Sensitivity.set_value_no_signal(value)

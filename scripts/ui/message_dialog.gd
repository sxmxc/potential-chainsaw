extends "res://scripts/ui/modal_window.gd"
var dialog_text: String:
	set(value):
		dialog_text=value
		%Message.text=value
func _ready() -> void:
	super()
	%Close.pressed.connect(close)

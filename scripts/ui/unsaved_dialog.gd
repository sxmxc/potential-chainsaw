extends "res://scripts/ui/modal_window.gd"
signal confirmed
signal custom_action(action: StringName)
func _ready() -> void:
	super()
	%Cancel.pressed.connect(close)
	%Save.pressed.connect(func():hide(); confirmed.emit())
	%Discard.pressed.connect(func():hide(); custom_action.emit(&"discard"))

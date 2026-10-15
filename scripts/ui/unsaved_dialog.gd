extends "res://scripts/ui/modal_window.gd"
signal confirmed
signal custom_action(action: StringName)
func _ready() -> void:
	super()
	%Cancel.pressed.connect(close)
	%Save.pressed.connect(func():dismiss(confirmed.emit))
	%Discard.pressed.connect(func():dismiss(func(): custom_action.emit(&"discard")))

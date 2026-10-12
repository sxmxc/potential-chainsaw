extends "res://scripts/ui/modal_window.gd"
signal action_requested(action: String)
func _ready() -> void:
	super()
	for item in [[%New,"new"],[%Rename,"rename"],[%Load,"load"],[%Examples,"examples"],[%Settings,"settings"],[%Main,"main"],[%Quit,"quit"]]:
		item[0].pressed.connect(func():hide(); action_requested.emit(item[1]))
	%Resume.pressed.connect(close)

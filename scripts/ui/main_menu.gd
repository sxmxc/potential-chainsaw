extends Control
signal action_requested(action: String)
@onready var showcase=$Showcase

func _ready() -> void:
	%Campaign.pressed.connect(func():action_requested.emit("campaign"))
	%Sandbox.pressed.connect(func():action_requested.emit("sandbox"))
	%Load.pressed.connect(func():action_requested.emit("load"))
	%Examples.pressed.connect(func():action_requested.emit("examples"))
	%Settings.pressed.connect(func():action_requested.emit("settings"))
	%Quit.pressed.connect(func():action_requested.emit("quit"))

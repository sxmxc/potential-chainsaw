extends Control
signal action_requested(action: String)

@export var main_menu_playlist: AudioStreamPlaylist

@onready var showcase=$Showcase

func _ready() -> void:
	%Campaign.pressed.connect(func():action_requested.emit("campaign"))
	%Community.pressed.connect(func():action_requested.emit("community"))
	%Sandbox.pressed.connect(func():action_requested.emit("sandbox"))
	%Load.pressed.connect(func():action_requested.emit("load"))
	%Examples.pressed.connect(func():action_requested.emit("examples"))
	%PuzzleEditor.pressed.connect(func():action_requested.emit("puzzle_editor"))
	%Settings.pressed.connect(func():action_requested.emit("settings"))
	%Quit.pressed.connect(func():action_requested.emit("quit"))

func play_music() -> void:
	if main_menu_playlist != null:
		SoundManager.play_music_queue(main_menu_playlist)

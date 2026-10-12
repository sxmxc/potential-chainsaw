extends "res://scripts/ui/modal_window.gd"
signal action_requested(action: String)
func _ready() -> void:
	super()
	for item in [[%New,"new"],[%Rename,"rename"],[%Load,"load"],[%Examples,"examples"],[%Settings,"settings"],[%Main,"main"],[%Quit,"quit"]]:
		item[0].pressed.connect(func():hide(); action_requested.emit(item[1]))
	for item in [[%Restart,"restart_puzzle"],[%Levels,"levels"],[%Author,"author"],[%SaveDraft,"save"],[%TestPlayer,"test_player"],[%ReturnEditor,"return_editor"],[%Preserve,"preserve_solution"],[%Reference,"reference"]]:
		item[0].pressed.connect(func():hide(); action_requested.emit(item[1]))
	%Resume.pressed.connect(close)

func configure_mode(session: PuzzleSession) -> void:
	var session_mode = session.mode
	title = {"sandbox":"Sandbox menu", "campaign":"Level options", "editor":"Puzzle Editor", "test":"Player test"}.get(session_mode, "Menu")
	%Heading.text=title
	%Resume.text="Resume"
	for control in [%New,%Rename,%Load,%Examples]: control.visible=session_mode=="sandbox"
	%Restart.visible=session_mode in ["campaign","test"]
	%Levels.visible=session_mode=="campaign"
	%Author.visible=session_mode=="editor"
	%SaveDraft.visible=session_mode=="editor"
	%TestPlayer.visible=session_mode=="editor"
	%ReturnEditor.visible=session_mode=="test"
	%Preserve.visible=session_mode=="test"
	%Preserve.disabled=not session.test_success
	%Reference.visible=session_mode=="test" and not session.puzzle.get("solution",[]).is_empty()
	# Windows do not shrink themselves when actions disappear.
	size=Vector2i(350,int(get_node("Surface").get_combined_minimum_size().y))

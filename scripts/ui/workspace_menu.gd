extends "res://scripts/ui/modal_window.gd"
signal action_requested(action: String)
func _ready() -> void:
	super()
	for item in [[%New,"new"],[%Rename,"rename"],[%Load,"load"],[%Examples,"examples"],[%Settings,"settings"],[%Main,"main"],[%Quit,"quit"]]:
		item[0].pressed.connect(func():hide(); action_requested.emit(item[1]))
	for item in [[%Restart,"restart_puzzle"],[%Levels,"levels"],[%Author,"author"],[%SaveDraft,"save"],[%TestPlayer,"test_player"],[%ReturnEditor,"return_editor"],[%Preserve,"preserve_solution"],[%Reference,"reference"]]:
		item[0].pressed.connect(func():hide(); action_requested.emit(item[1]))
	%Resume.pressed.connect(close)

func configure_context(session: ConstructionSession) -> void:
	match session.context:
		ConstructionSession.Context.SANDBOX: title = "Sandbox menu"
		ConstructionSession.Context.AUTHORING: title = "Puzzle Editor"
		ConstructionSession.Context.PUZZLE_PLAY: title = "Level options"
		ConstructionSession.Context.PLAYER_TEST: title = "Player test"
	%Heading.text=title
	%Resume.text="Resume"
	for control in [%New,%Rename,%Load,%Examples]: control.visible=session.is_sandbox
	%Restart.visible=session.is_playing
	%Levels.visible=session.context == ConstructionSession.Context.PUZZLE_PLAY
	%Levels.text = "Campaign levels" if session.store.is_official(session.puzzle) else "Community puzzles"
	%Author.visible=session.is_authoring
	%SaveDraft.visible=session.is_authoring
	%TestPlayer.visible=session.is_authoring
	%ReturnEditor.visible=session.is_testing
	%Preserve.visible=session.is_testing
	%Preserve.disabled=not session.test_success
	%Reference.visible=session.is_testing and not session.puzzle.get("solution",[]).is_empty()
	# Windows do not shrink themselves when actions disappear.
	size=Vector2i(350,int(get_node("Surface").get_combined_minimum_size().y))

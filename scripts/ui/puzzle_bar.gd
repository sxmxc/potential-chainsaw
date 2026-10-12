extends PanelContainer

var session: PuzzleSession

func configure(value: PuzzleSession) -> void:
	session = value
	%Author.pressed.connect(func(): session.game.authoring.open())
	%TestPlayer.pressed.connect(func(): session.test_player())
	%ReturnEditor.pressed.connect(session.return_editor)
	%Reference.pressed.connect(session.restore_reference)
	%Preserve.pressed.connect(func(): if session.preserve_solution(): session.game.get_node("%HUD").show_status("Solution saved"))
	session.mode_changed.connect(refresh)
	session.game.sandbox.simulation.state_changed.connect(func(_state, _message): refresh())
	refresh()

func refresh() -> void:
	# Player information belongs in the shared top bar. This strip is for authoring.
	visible = session.mode == "test"
	%Author.visible = session.mode == "editor"
	%TestPlayer.visible = false # Shared primary Test action owns player tests.
	%ReturnEditor.visible = session.mode == "test"
	%Preserve.visible = session.mode == "test"
	%Reference.visible = session.mode == "test" and not session.puzzle.get("solution", []).is_empty()
	%Preserve.disabled = not session.test_success

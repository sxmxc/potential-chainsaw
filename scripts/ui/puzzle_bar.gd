extends PanelContainer

var session: PuzzleSession

func configure(value: PuzzleSession) -> void:
	session = value
	%ReturnEditor.pressed.connect(session.return_editor)
	var popup: PopupMenu = %SolutionActions.get_popup()
	popup.add_item("Save validated solution", 0)
	popup.add_item("Load reference solution", 1)
	popup.id_pressed.connect(func(id):
		if id == 0 and session.preserve_solution(): session.game.get_node("%HUD").show_status("Solution saved")
		elif id == 1: session.restore_reference())
	session.mode_changed.connect(refresh)
	session.game.sandbox.simulation.state_changed.connect(func(_state, _message): refresh())
	refresh()

func refresh() -> void:
	visible = session.mode == "test"
	var popup: PopupMenu = %SolutionActions.get_popup()
	popup.set_item_disabled(0, not session.test_success)
	popup.set_item_disabled(1, session.puzzle.get("solution", []).is_empty())

extends PanelContainer

var session: ConstructionSession

signal action_requested(action: String)

func configure(value: ConstructionSession) -> void:
	session = value
	%ReturnEditor.pressed.connect(func(): action_requested.emit("return_editor"))
	var popup: PopupMenu = %SolutionActions.get_popup()
	popup.add_item("Save validated solution", 0)
	popup.add_item("Load reference solution", 1)
	popup.id_pressed.connect(func(id): action_requested.emit("preserve_solution" if id == 0 else "reference"))
	session.changed.connect(refresh)
	session.world.simulation.state_changed.connect(func(_state, _message): refresh())
	refresh()

func refresh() -> void:
	visible = session.is_testing
	var popup: PopupMenu = %SolutionActions.get_popup()
	popup.set_item_disabled(0, not session.test_success)
	popup.set_item_disabled(1, session.puzzle.get("solution", []).is_empty())

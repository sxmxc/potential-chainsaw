extends Window

var session: PuzzleSession

func configure(value: PuzzleSession) -> void:
	session = value
	close_requested.connect(hide)
	%KeepBuilding.pressed.connect(hide)
	%Preserve.pressed.connect(func():
		if session.preserve_solution(): %Result.text = "Validated solution preserved separately from the starting layout.")
	%ReturnEditor.pressed.connect(func(): hide(); session.return_editor())
	%LevelSelection.pressed.connect(func(): hide(); session.game.puzzle_browser.open())
	%Next.pressed.connect(func():
		hide()
		var next = session.store.next_level(session.puzzle)
		if not next.is_empty(): session.player(next); return
		session.game.puzzle_browser.open())
	session.game.sandbox.simulation.state_changed.connect(result)
	session.mode_changed.connect(func(): if session.game.sandbox.simulation.state != SimulationManager.State.SUCCESS: hide())

func result(state: int, _message: String) -> void:
	if state != SimulationManager.State.SUCCESS or session.mode not in ["test", "campaign"]: hide(); return
	%Name.text = session.puzzle.name
	%Result.text = "Delivered in %.1f seconds. Your construction stays intact for another run." % session.game.sandbox.simulation.elapsed
	%Preserve.visible = session.mode == "test"
	%ReturnEditor.visible = session.mode == "test"
	%Next.visible = session.mode == "campaign"
	%LevelSelection.visible = session.mode == "campaign"
	var awards: Array = session.store.progress.get(session.puzzle.id, {}).get("awards", [])
	%Awards.text = "Awards earned: " + ", ".join(awards)
	%Awards.visible = not awards.is_empty()
	popup_centered(Vector2i(480, 360))
	%Surface.modulate.a = 0
	create_tween().tween_property(%Surface, "modulate:a", 1.0, 0.18)

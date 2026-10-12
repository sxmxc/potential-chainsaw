extends Window

var session: PuzzleSession

func configure(value: PuzzleSession) -> void:
	session = value
	close_requested.connect(hide)
	%Title.text="Player test complete" if session.mode=="test" else "Puzzle complete"
	%KeepBuilding.pressed.connect(func():hide(); session.game.sandbox.simulation.reset())
	%Preserve.pressed.connect(func():
		if session.preserve_solution(): %Result.text = "Solution saved.")
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
	%Title.text="Player test complete" if session.mode=="test" else "Puzzle complete"
	%Result.text = "Completed in %.1f seconds." % session.game.sandbox.simulation.elapsed
	%Preserve.visible = session.mode == "test"
	%ReturnEditor.visible = session.mode == "test"
	%Next.visible = session.mode == "campaign"
	%LevelSelection.visible = session.mode == "campaign"
	var awards: Array = session.store.progress.get(session.puzzle.id, {}).get("awards", [])
	%Awards.text = "Awards: " + ", ".join(awards)
	%Awards.visible = not awards.is_empty()
	popup_centered(Vector2i(480,int(%Surface.get_combined_minimum_size().y)))
	%Surface.modulate.a = 0
	create_tween().tween_property(%Surface, "modulate:a", 1.0, 0.18)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()

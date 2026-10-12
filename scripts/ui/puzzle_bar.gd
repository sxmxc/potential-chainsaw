extends PanelContainer

var session: PuzzleSession

func configure(value: PuzzleSession) -> void:
	session = value
	%Author.pressed.connect(func(): session.game.authoring.open())
	%TestPlayer.pressed.connect(func(): session.test_player())
	%ReturnEditor.pressed.connect(session.return_editor)
	%Reference.pressed.connect(session.restore_reference)
	%Preserve.pressed.connect(func(): if session.preserve_solution(): %Objective.text = "Validated solution saved · return to editor to publish")
	%Levels.pressed.connect(func(): session.game.puzzle_browser.open())
	%Restart.pressed.connect(func(): session.player(session.puzzle, session.mode == "test"))
	%Next.pressed.connect(func():
		var next = session.store.next_level(session.puzzle)
		if not next.is_empty(): session.player(next); return
		session.game.puzzle_browser.open())
	session.mode_changed.connect(refresh)
	session.game.sandbox.simulation.state_changed.connect(func(_state, _message): refresh())
	session.game.sandbox.simulation.objective_progress.connect(refresh)
	refresh()

func refresh() -> void:
	visible = session.mode != "sandbox"
	%Author.visible = session.mode == "editor"
	%TestPlayer.visible = session.mode == "editor"
	%ReturnEditor.visible = session.mode == "test"
	%Preserve.visible = session.mode == "test"
	%Reference.visible = session.mode == "test" and not session.puzzle.get("solution", []).is_empty()
	%Preserve.disabled = not session.test_success
	%Levels.visible = session.mode == "campaign"
	%Restart.visible = session.mode in ["test", "campaign"]
	%Next.visible = session.mode == "campaign" and session.game.sandbox.simulation.state == SimulationManager.State.SUCCESS
	if visible:
		%Objective.text = ("AUTHORING · " if session.mode == "editor" else "") + session.puzzle.name + " · " + session.puzzle.description
		%Hint.text = "\n".join(session.puzzle.get("hints", []))
		%Hint.visible = not %Hint.text.is_empty()
		var simulation: SimulationManager = session.game.sandbox.simulation
		var counts: Array[String] = []
		for objective in session.puzzle.get("objectives", []):
			if objective.get("type", "deliver") == "activate":
				counts.append("Event " + objective.get("event", "activated") + ": " + ("complete" if simulation.objectives.activations.has(objective.target + ":" + objective.get("event", "activated")) else "waiting"))
			else:
				var count = 0
				for delivery in simulation.objectives.deliveries.values():
					if delivery.collector == objective.target and (objective.get("source", "").is_empty() or delivery.source == objective.source): count += 1
				counts.append("Delivered %d / %d" % [count, objective.get("count", 1)])
		%Counters.text = " · ".join(counts)
		%Counters.visible = session.mode != "editor"

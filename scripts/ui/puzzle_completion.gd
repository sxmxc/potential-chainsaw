extends "res://scripts/ui/modal_window.gd"

signal levels_requested
signal presentation_requested(minimum: Vector2i)

var session: ConstructionSession

func configure(value: ConstructionSession) -> void:
	session = value
	%Title.text="Player test complete" if session.is_testing else "Puzzle complete"
	%KeepBuilding.pressed.connect(func():dismiss(session.world.simulation.reset))
	%Preserve.pressed.connect(func():
		if session.preserve_solution(): %Result.text = "Solution saved.")
	%ReturnEditor.pressed.connect(func(): dismiss(session.return_editor))
	%LevelSelection.pressed.connect(func(): dismiss(levels_requested.emit))
	%Next.pressed.connect(func(): dismiss(_next_level))
	session.world.simulation.state_changed.connect(result)
	session.changed.connect(func(): if session.world.simulation.state != SimulationManager.State.SUCCESS: hide())

func _next_level() -> void:
	var next = session.store.load_campaign().next_step(session.puzzle, session.progress.records).level
	if not next.is_empty(): session.player(next); return
	levels_requested.emit()

func result(state: int, _message: String) -> void:
	if state != SimulationManager.State.SUCCESS or not session.is_playing: hide(); return
	%Name.text = session.puzzle.name
	%Title.text="Player test complete" if session.is_testing else "Puzzle complete"
	%Result.text = "Completed in %.1f seconds." % session.world.simulation.elapsed
	%Preserve.visible = session.is_testing
	%ReturnEditor.visible = session.is_testing
	%Next.visible = session.context == ConstructionSession.Context.PUZZLE_PLAY and PuzzleStore.is_official(session.puzzle)
	%LevelSelection.visible = session.context == ConstructionSession.Context.PUZZLE_PLAY
	%LevelSelection.text = "Campaign levels" if PuzzleStore.is_official(session.puzzle) else "Community puzzles"
	var records: Dictionary = session.progress.records if PuzzleStore.is_official(session.puzzle) else session.progress.community_records
	var awards: Array = records.get(session.puzzle.id, {}).get("awards", [])
	%Awards.text = "Awards: " + ", ".join(awards)
	%Awards.visible = not awards.is_empty()
	presentation_requested.emit(Vector2i(480,int(%Surface.get_combined_minimum_size().y)))

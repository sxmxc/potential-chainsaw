extends Control
## Presentation only: the session has already recorded success before this opens.
signal levels_requested
signal presentation_requested

const PULSE = preload("res://scenes/ui/widgets/completion_pulse.tscn")
const REVEAL_TIME: float = 0.48
var session: ConstructionSession
var sequence: Tween
var closing: bool = false
var acknowledged: bool = false
var chapter_completed: int = 0
var pulses: Array[Node3D] = []
var return_focus: Control

func _ready() -> void:
	ButtonFeedback.install(self)
	for control: Control in [%Reveal, %Dock, %Accent]:
		control.offset_transform_enabled = true
		control.offset_transform_visual_only = false
	%Accent.offset_transform_pivot_ratio = Vector2.ZERO
	visibility_changed.connect(_visibility_changed)

func configure(value: ConstructionSession) -> void:
	session = value
	%KeepBuilding.pressed.connect(func(): dismiss(session.world.simulation.reset))
	%Preserve.pressed.connect(_preserve)
	%ReturnEditor.pressed.connect(func(): dismiss(session.return_editor))
	%LevelSelection.pressed.connect(func(): dismiss(levels_requested.emit))
	%Next.pressed.connect(func(): dismiss(_next_level))
	session.world.simulation.state_changed.connect(result)
	session.context_changed.connect(hide)

func _preserve() -> void:
	if closing or not session.preserve_solution(): return
	%NextDestination.text = "Solution saved. Your starting layout is preserved."
	%Preserve.hide()
	%ReturnEditor.theme_type_variation = &"PrimaryButton"
	%ReturnEditor.grab_focus()

func _next_level() -> void:
	var next: Dictionary = session.store.load_campaign().next_step(session.puzzle, session.progress.records).level
	if not next.is_empty(): session.player(next)
	else: levels_requested.emit()

func result(state: int, _message: String) -> void:
	if state != SimulationManager.State.SUCCESS or not session.is_playing:
		acknowledged = false
		hide()
		return
	if acknowledged: return
	acknowledged = true
	%Name.text = session.puzzle.name
	%Title.text = "It works!"
	%Context.text = "PLAYER TEST COMPLETE" if session.is_testing else "PUZZLE COMPLETE"
	%Result.text = "Your machine did it. All objectives met in %.1f seconds." % session.world.simulation.elapsed
	%Preserve.visible = session.is_testing
	%ReturnEditor.visible = session.is_testing
	%ReturnEditor.theme_type_variation = &"SecondaryButton"
	%Next.visible = not session.is_testing and PuzzleStore.is_official(session.puzzle)
	%LevelSelection.visible = not session.is_testing
	%LevelSelection.theme_type_variation = &"SecondaryButton" if %Next.visible else &"PrimaryButton"
	%LevelSelection.text = "Campaign levels" if PuzzleStore.is_official(session.puzzle) else "Community puzzles"
	var records: Dictionary = session.progress.records if PuzzleStore.is_official(session.puzzle) else session.progress.community_records
	var awards: Array = records.get(session.puzzle.id, {}).get("awards", [])
	var captions: Array[String] = []
	for award: String in awards:
		captions.append({"time": "Time award", "pieces": "Piece budget award"}.get(award, award.capitalize()))
	%Awards.text = " / ".join(captions)
	%Awards.visible = not session.is_testing and not captions.is_empty()
	%Progress.theme_type_variation = &"VictoryProgress"
	chapter_completed = 0
	%Chapter.visible = false
	%Progress.visible = false
	%NextDestination.text = "A successful design. Ready for another challenge?"
	if session.is_testing:
		%NextDestination.text = "Save this solution to verify your puzzle for publishing."
	elif %Next.visible:
		var campaign := session.campaign
		var chapter := campaign.chapter_for(session.puzzle)
		var progress := campaign.chapter_progress(chapter.id, session.progress.records)
		var milestone: bool = progress.total > 0 and progress.completed == progress.total
		%Context.text = "INTRODUCTION COMPLETE" if milestone and chapter.get("introduction", false) else ("CHAPTER COMPLETE" if milestone else "PUZZLE COMPLETE")
		if milestone:
			%Title.text = "Well built!"
			%Progress.theme_type_variation = &"VictoryMilestoneProgress"
		%Chapter.text = "%s  /  %d of %d complete" % [chapter.get("name", "Campaign"), progress.completed, progress.total]
		%Chapter.visible = true
		%Progress.visible = progress.total > 0
		%Progress.max_value = maxi(1, progress.total)
		chapter_completed = progress.completed
		var next: Dictionary = campaign.next_step(session.puzzle, session.progress.records).level
		%Next.text = "Next puzzle" if not next.is_empty() else "Choose a puzzle"
		%NextDestination.text = "Up next: " + str(next.name) if not next.is_empty() else "Choose your next challenge from the campaign."
	presentation_requested.emit()

func present() -> void:
	if visible and not closing: return
	_stop_sequence()
	closing = false
	if not visible: return_focus = get_viewport().gui_get_focus_owner()
	show()
	modulate = Color.WHITE
	mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
	for child in get_children():
		if child is Control: child.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
	focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	%Reveal.modulate.a = 0.0
	%Reveal.offset_transform_position_ratio = Vector2(-0.08, 0)
	%Dock.modulate.a = 0.0
	%Dock.offset_transform_position_ratio = Vector2(0, 0.24)
	%Accent.offset_transform_scale = Vector2(0.05, 1)
	%Progress.value = 0
	_objective_pulses()
	# One timeline: target response, title sweep, dock arrival, chapter fill.
	sequence = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	sequence.tween_property(%Reveal, "modulate:a", 1.0, 0.22).set_delay(0.10)
	sequence.tween_property(%Reveal, "offset_transform_position_ratio", Vector2.ZERO, REVEAL_TIME).set_delay(0.10)
	sequence.tween_property(%Accent, "offset_transform_scale", Vector2.ONE, 0.45).set_delay(0.26)
	sequence.tween_property(%Dock, "modulate:a", 1.0, 0.20).set_delay(0.24)
	sequence.tween_property(%Dock, "offset_transform_position_ratio", Vector2.ZERO, REVEAL_TIME).set_delay(0.24)
	sequence.tween_property(%Progress, "value", chapter_completed, 0.55).set_delay(0.48)
	for pulse: Node3D in pulses:
		sequence.tween_property(pulse, "scale", Vector3.ONE * 2.6, 0.85)
		sequence.tween_property(pulse.get_node("Ring"), "transparency", 1.0, 0.55).set_delay(0.3)
	sequence.chain().tween_callback(_clear_pulses)
	# Actions are available immediately; their hit areas follow the native transforms.
	for button: Button in [%Next, %Preserve, %LevelSelection]:
		if button.visible:
			button.grab_focus()
			break

func _objective_pulses() -> void:
	var targets: Array[String] = []
	for objective: Dictionary in session.puzzle.get("objectives", []):
		var target: String = objective.get("target", "")
		if target in targets: continue
		targets.append(target)
		var piece := session.world.build.find_piece(target)
		if not piece: continue
		var pulse: Node3D = PULSE.instantiate()
		session.world.add_child(pulse)
		var bounds: AABB = piece.definition.bounds
		pulse.global_position = piece.global_transform * (bounds.get_center() + Vector3.UP * (bounds.size.y * 0.5 + 0.04))
		pulses.append(pulse)

func dismiss(action: Callable = Callable()) -> void:
	if closing or not visible: return
	_stop_sequence()
	closing = true
	focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	# Keep the root blocking the world while descendants lose input.
	for child in get_children():
		if child is Control: child.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	sequence = create_tween()
	sequence.tween_property(self, "modulate:a", 0.0, 0.12)
	sequence.tween_callback(func():
		hide()
		if action.is_valid(): action.call())

func _stop_sequence() -> void:
	if sequence: sequence.kill()
	sequence = null
	_clear_pulses()

func _clear_pulses() -> void:
	for pulse: Node3D in pulses:
		if is_instance_valid(pulse): pulse.queue_free()
	pulses.clear()

func _visibility_changed() -> void:
	if is_visible_in_tree(): return
	_stop_sequence()
	closing = false
	modulate = Color.WHITE
	for child in get_children():
		if child is Control: child.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
	_restore_focus.call_deferred()

func _restore_focus() -> void:
	# GameManager restores HUD visibility in the same visibility notification.
	if is_visible_in_tree(): return
	if is_instance_valid(return_focus) and return_focus.is_visible_in_tree(): return_focus.grab_focus()

func _exit_tree() -> void:
	_stop_sequence()

func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		dismiss()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(_event: InputEvent) -> void:
	# Buttons receive GUI input first; remaining shortcuts cannot reach the workspace.
	if is_visible_in_tree(): get_viewport().set_input_as_handled()

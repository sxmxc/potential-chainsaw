extends Control
signal action_requested(action: String)

@export var main_menu_playlist: AudioStreamPlaylist

@onready var showcase=$Showcase
var action_motions: Array[UIMotion] = []
var actions_open: bool = true
var after_actions_hidden: Callable

func _ready() -> void:
	%Campaign.pressed.connect(request_action.bind("campaign"))
	%Community.pressed.connect(request_action.bind("community"))
	%Sandbox.pressed.connect(request_action.bind("sandbox"))
	%Load.pressed.connect(request_action.bind("load"))
	%Examples.pressed.connect(request_action.bind("examples"))
	%PuzzleEditor.pressed.connect(request_action.bind("puzzle_editor"))
	%Settings.pressed.connect(request_action.bind("settings"))
	%Quit.pressed.connect(request_action.bind("quit"))
	visibility_changed.connect(func():
		if not visible:
			after_actions_hidden = Callable()
			actions_open = false
			for motion in action_motions: motion.set_open(false, true))
	animate_actions.call_deferred()

func animate_actions() -> void:
	# Run after the application's button feedback is installed.
	prepare_actions()
	if is_visible_in_tree() and actions_open:
		for motion in action_motions: motion.enter()

func prepare_actions() -> void:
	if not action_motions.is_empty(): return
	for child in %Campaign.get_parent().get_children():
		if not child is Button or not child.visible: continue
		var motion := UIMotion.attach(child, Vector2(-UIMotion.MENU_ACTION_SHIFT, 0.0))
		motion.entrance_time = UIMotion.MENU_ACTION_TIME
		motion.entrance_delay = action_motions.size() * UIMotion.MENU_ACTION_DELAY
		motion.entrance_transition = Tween.TRANS_ELASTIC
		motion.exit_time = UIMotion.MENU_ACTION_TIME
		motion.exit_transition = Tween.TRANS_ELASTIC
		motion.exit_ease = Tween.EASE_IN
		motion.finished.connect(action_motion_finished)
		action_motions.append(motion)
	for index in action_motions.size():
		action_motions[index].exit_delay = (action_motions.size() - 1 - index) * UIMotion.MENU_ACTION_DELAY
		if not actions_open: action_motions[index].set_open(false, true)

func request_action(action: String) -> void:
	if not actions_open: return
	hide_actions(func(): action_requested.emit(action))

func hide_actions(action: Callable = Callable()) -> float:
	prepare_actions()
	actions_open = false
	after_actions_hidden = action
	var moving := false
	for motion in action_motions:
		if motion.control.visible or motion.tween: moving = true
		motion.set_open(false)
	if not moving:
		action_motion_finished()
		return 0.0
	return UIMotion.MENU_ACTION_TIME + maxi(0, action_motions.size() - 1) * UIMotion.MENU_ACTION_DELAY

func show_actions() -> void:
	prepare_actions()
	actions_open = true
	after_actions_hidden = Callable()
	for motion in action_motions: motion.set_open(true)

func action_motion_finished() -> void:
	if actions_open:
		focus_actions()
		return
	for motion in action_motions:
		if motion.control.visible or motion.tween: return
	var action := after_actions_hidden
	after_actions_hidden = Callable()
	if action.is_valid(): action.call()

func focus_actions() -> void:
	if not is_visible_in_tree() or not actions_open or action_motions.is_empty(): return
	if focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED or action_motions[0].tween: return
	if get_viewport().gui_get_focus_owner() == null: %Campaign.grab_focus()

func play_music() -> void:
	if main_menu_playlist != null:
		SoundManager.play_music_queue(main_menu_playlist)

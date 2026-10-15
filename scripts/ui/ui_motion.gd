class_name UIMotion
extends Node
## Small presentation helper. Owners still decide visibility and lifecycle.
signal finished

const ENTER_TIME: float = 0.16
const EXIT_TIME: float = 0.12
const SECTION_TIME: float = 0.09
const SCREEN_TIME: float = 0.20
const PANEL_SHIFT: float = 0.06
const SURFACE_SCALE: float = 0.985

var control: Control
var wanted: bool
var shift: Vector2
var closed_scale: float = 1.0
var entrance_time: float = ENTER_TIME
var tween: Tween
var input_states: Dictionary = {}
var saved_focus: Control.FocusBehaviorRecursive
var saved_filter: Control.MouseFilter
var contents_blocked: bool = false

static func attach(target: Control, displacement: Vector2 = Vector2.ZERO, scale_at_rest: float = 1.0) -> UIMotion:
	var motion := UIMotion.new()
	motion.control = target
	motion.wanted = target.visible
	motion.shift = displacement
	motion.closed_scale = scale_at_rest
	target.add_child(motion)
	target.offset_transform_enabled = true
	target.offset_transform_visual_only = false
	target.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	target.visibility_changed.connect(motion._visibility_changed)
	return motion

func set_open(value: bool, immediate: bool = false) -> void:
	if immediate or not control.is_inside_tree():
		wanted = value
		cancel()
		control.visible = value
		return
	if wanted == value and control.visible == value: return
	if wanted == value and tween and tween.is_running(): return
	wanted = value
	_stop()
	if value and not control.visible:
		control.show()
		_present(0.0)
	if not control.is_visible_in_tree():
		cancel()
		control.visible = value
		return
	_block_contents()
	tween = control.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var duration: float = entrance_time if value else EXIT_TIME
	tween.tween_property(control, "modulate:a", 1.0 if value else 0.0, duration)
	tween.tween_property(control, "offset_transform_position_ratio", Vector2.ZERO if value else shift, duration)
	tween.tween_property(control, "offset_transform_scale", Vector2.ONE if value else Vector2.ONE * closed_scale, duration)
	tween.chain().tween_callback(_complete)

func enter() -> void:
	cancel()
	wanted = false
	control.show()
	_present(0.0)
	set_open(true)

func cancel() -> void:
	_stop()
	_restore_contents()
	_present(1.0)

func _stop() -> void:
	if tween: tween.kill()
	tween = null

func _present(amount: float) -> void:
	control.modulate.a = amount
	control.offset_transform_position_ratio = shift * (1.0 - amount)
	control.offset_transform_scale = Vector2.ONE * lerpf(closed_scale, 1.0, amount)

func _block_contents() -> void:
	if contents_blocked: return
	contents_blocked = true
	saved_focus = control.focus_behavior_recursive
	saved_filter = control.mouse_filter
	control.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	var focus := control.get_viewport().gui_get_focus_owner()
	if focus and (focus == control or control.is_ancestor_of(focus)): focus.release_focus()
	for child in control.get_children():
		if child is Control:
			input_states[child] = child.mouse_behavior_recursive
			child.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED

func _restore_contents() -> void:
	if not contents_blocked: return
	contents_blocked = false
	for child: Control in input_states:
		if is_instance_valid(child): child.mouse_behavior_recursive = input_states[child]
	input_states.clear()
	control.focus_behavior_recursive = saved_focus
	control.mouse_filter = saved_filter

func _complete() -> void:
	tween = null
	control.visible = wanted
	_restore_contents()
	_present(1.0)
	finished.emit()

func _visibility_changed() -> void:
	if not control.is_visible_in_tree():
		cancel()
		if control.visible and not wanted: control.hide()

static func section(target: Control) -> void:
	# Each page uses the same cancellation and input lifecycle as panels.
	if not target.is_visible_in_tree(): return
	var motion: UIMotion
	if target.has_meta(&"section_motion"):
		motion = target.get_meta(&"section_motion")
	else:
		motion = attach(target)
		motion.entrance_time = SECTION_TIME
		target.set_meta(&"section_motion", motion)
	motion.enter()


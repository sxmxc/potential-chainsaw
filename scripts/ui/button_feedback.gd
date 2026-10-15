class_name ButtonFeedback
extends Node
## Presentation-only press response; button actions fire at their normal time.
const PRESS_SCALE: float = 0.975
const PRESS_TIME: float = 0.055
const RELEASE_TIME: float = 0.09
var button: Button
var tween: Tween

static func install(root: Node) -> void:
	if root is Button and not root is OptionButton and not root.has_meta(&"press_feedback"):
		var feedback := ButtonFeedback.new()
		feedback.button = root
		root.set_meta(&"press_feedback", true)
		root.add_child(feedback)
		root.offset_transform_enabled = true
		# Press compression retains the full, stationary click target.
		root.offset_transform_visual_only = true
		root.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
		root.button_down.connect(feedback._down)
		root.button_up.connect(feedback._up)
		root.mouse_exited.connect(feedback._up)
		root.focus_exited.connect(feedback._up)
		root.visibility_changed.connect(feedback._reset)
	for child in root.get_children():
		if not child is ButtonFeedback: install(child)

func _down() -> void:
	if not button.disabled: _animate(PRESS_SCALE, PRESS_TIME)

func _up() -> void:
	_animate(1.0, RELEASE_TIME)

func _animate(amount: float, duration: float) -> void:
	if tween: tween.kill()
	tween = button.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "offset_transform_scale", Vector2.ONE * amount, duration)

func _reset() -> void:
	if tween: tween.kill()
	button.offset_transform_scale = Vector2.ONE

extends Control
## A decorative child overlay: native anchors, clipping and inherited transforms
## track the real target, including scrolling and panel entrance animations.
var style: String = "pointer"
var inset_pointer: bool = false
var arrival: Tween

func _ready() -> void:
	$Pointer.visible = style == "pointer" and not inset_pointer
	$CardPointer.visible = style == "pointer" and inset_pointer
	for pointer: Control in [$Pointer, $CardPointer]:
		pointer.offset_transform_enabled = true
		pointer.offset_transform_visual_only = true
	visibility_changed.connect(_visibility_changed)
	_visibility_changed()

func _visibility_changed() -> void:
	if not is_inside_tree(): return
	if arrival: arrival.kill()
	if is_visible_in_tree():
		$Motion.play("invite")
		modulate.a = 0.0
		arrival = create_tween()
		arrival.tween_property(self, "modulate:a", 1.0, 0.14)
	else:
		$Motion.stop()

func refresh_availability() -> void:
	var target := get_parent() as Control
	visible = not (target is BaseButton and target.disabled)

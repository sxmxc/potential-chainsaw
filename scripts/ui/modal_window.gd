extends Window
signal closed
var return_focus: Control
func _ready() -> void:
	close_requested.connect(close)
	visibility_changed.connect(func():
		if visible:
			return_focus=get_parent().get_viewport().gui_get_focus_owner()
			focus_first.call_deferred()
		elif is_instance_valid(return_focus) and return_focus.is_visible_in_tree(): return_focus.grab_focus())

func focus_first() -> void:
	if not visible: return
	for control in find_children("*","Control",true,false):
		if control.is_visible_in_tree() and control.focus_mode==Control.FOCUS_ALL:
			if control is BaseButton and control.disabled: continue
			control.grab_focus()
			return
func close() -> void:
	hide()
	closed.emit()
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

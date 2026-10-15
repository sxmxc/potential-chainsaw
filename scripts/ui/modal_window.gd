extends Window
signal closed
signal dismissing
var return_focus: Control
var motion: UIMotion
var closing: bool = false
var after_close: Callable
func _ready() -> void:
	motion = UIMotion.attach($Surface, Vector2.ZERO, UIMotion.SURFACE_SCALE)
	motion.finished.connect(_finish_close)
	ButtonFeedback.install(self)
	close_requested.connect(close)
	visibility_changed.connect(func():
		if visible:
			closing = false
			after_close = Callable()
			return_focus=get_parent().get_viewport().gui_get_focus_owner()
			motion.enter()
		else:
			closing = false
			after_close = Callable()
			motion.cancel()
			$Surface.show()
			if is_instance_valid(return_focus) and return_focus.is_visible_in_tree(): return_focus.grab_focus())

func focus_first() -> void:
	if not visible or closing: return
	for control in find_children("*","Control",true,false):
		if control.is_visible_in_tree() and control.focus_mode==Control.FOCUS_ALL:
			if control is BaseButton and control.disabled: continue
			control.grab_focus()
			return
func close() -> void:
	dismiss()

func present(minimum: Vector2i = Vector2i.ZERO) -> void:
	# Reopening during an exit reverses it and abandons its pending action.
	if visible and closing:
		closing = false
		after_close = Callable()
		motion.set_open(true)
	popup_centered(minimum)

func dismiss(action: Callable = Callable()) -> void:
	if closing or not visible: return
	closing = true
	after_close = action
	dismissing.emit()
	motion.set_open(false)

func _finish_close() -> void:
	if not closing:
		focus_first()
		return
	var action := after_close
	hide()
	if action.is_valid(): action.call()
	else: closed.emit()
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

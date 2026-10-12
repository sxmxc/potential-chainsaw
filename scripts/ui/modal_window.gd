extends Window
signal closed
func _ready() -> void:
	close_requested.connect(close)
func close() -> void:
	hide()
	closed.emit()
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

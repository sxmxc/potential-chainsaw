extends "res://scripts/ui/modal_window.gd"
signal confirmed
func _ready() -> void:
	super()
	%Cancel.pressed.connect(close)
	%Save.pressed.connect(confirm)
	%Name.text_submitted.connect(func(_text):confirm())
	%Name.text_changed.connect(func(text): %Save.disabled=text.strip_edges().is_empty())
func confirm() -> void:
	if %Name.text.strip_edges().is_empty(): return
	hide()
	confirmed.emit()
func set_name_text(value: String) -> void:
	%Name.text=value
	%Save.disabled=value.strip_edges().is_empty()
func open() -> void:
	popup_centered()
	%Name.grab_focus()
	%Name.select_all()
func get_name_text() -> String:
	return %Name.text

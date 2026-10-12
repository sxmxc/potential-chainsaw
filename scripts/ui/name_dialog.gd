extends "res://scripts/ui/modal_window.gd"
signal confirmed
func _ready() -> void:
	super()
	%Cancel.pressed.connect(close)
	%Save.pressed.connect(confirm)
	%Name.text_submitted.connect(func(_text):confirm())
func confirm() -> void:
	hide()
	confirmed.emit()
func set_name_text(value: String) -> void:
	%Name.text=value
func open() -> void:
	popup_centered()
	%Name.grab_focus()
	%Name.select_all()
func get_name_text() -> String:
	return %Name.text

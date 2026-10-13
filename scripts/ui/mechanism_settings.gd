extends VBoxContainer

const NUMBER = preload("res://scenes/ui/widgets/mechanism_number.tscn")
const FLAG = preload("res://scenes/ui/widgets/piece_flag.tscn")
const TEXT = preload("res://scenes/ui/widgets/piece_text.tscn")
var build: BuildManager
var displayed_piece: BuildingPiece
var fields: Dictionary = {}

func configure(manager: BuildManager) -> void:
	build = manager
	# Preserve active controls until their input callback has returned.
	build.selection_changed.connect(func(_piece): refresh_current.call_deferred())
	refresh(null)

func refresh_current() -> void:
	refresh(build.selected)

func refresh(piece: BuildingPiece) -> void:
	if piece and piece == displayed_piece and build.selection.size() == 1:
		for setting in piece.definition.settings:
			var input = fields[String(setting.key)]
			var value: Variant = piece.configuration.get(setting.key, setting.default_value())
			var editable: bool = not build.rules or build.rules.permits(piece.instance_id, "configure")
			if input is SettingSlider:
				input.set_value_no_signal(float(value))
				input.editable = editable
				input.refresh_labels()
			elif input is LineEdit:
				if not input.has_focus(): input.text = String(value)
				input.editable = editable
			else:
				input.set_pressed_no_signal(bool(value))
				input.disabled = not editable
		return
	displayed_piece = piece if build.selection.size() == 1 else null
	fields.clear()
	for child in get_children(): remove_child(child); child.queue_free()
	if not piece or build.selection.size() != 1: return
	for setting in piece.definition.settings:
		var key := String(setting.key)
		var editable: bool = not build.rules or build.rules.permits(piece.instance_id, "configure")
		if setting.kind == PieceSetting.Kind.NUMBER:
			var row = NUMBER.instantiate()
			add_child(row)
			row.get_node("%Caption").text = setting.label
			var input: SettingSlider = row.get_node("%Value")
			input.suffix = setting.unit
			input.tooltip_text = setting.description
			input.min_value = setting.minimum
			input.max_value = setting.maximum
			input.step = setting.step
			input.set_value_no_signal(float(piece.configuration.get(setting.key, setting.default_number)))
			input.refresh_labels()
			input.editable = editable
			input.setting_changed.connect(change.bind(key))
			fields[key] = input
		elif setting.kind == PieceSetting.Kind.STRING:
			var row = TEXT.instantiate()
			add_child(row)
			row.get_node("%Caption").text = setting.label
			var input: LineEdit = row.get_node("%Value")
			input.text = String(piece.configuration.get(setting.key, setting.default_string))
			input.tooltip_text = setting.description
			input.editable = editable
			input.text_submitted.connect(change.bind(key))
			input.focus_exited.connect(func():
				if is_instance_valid(piece) and piece == build.selected and input.text != String(piece.configuration.get(key, setting.default_string)):
					change(input.text, key))
			fields[key] = input
		else:
			var input: CheckBox = FLAG.instantiate()
			input.text = setting.label
			input.tooltip_text = setting.description
			input.set_pressed_no_signal(bool(piece.configuration.get(setting.key, setting.default_flag)))
			input.disabled = not editable
			add_child(input)
			input.toggled.connect(change.bind(key))
			fields[key] = input

func change(value: Variant, key: String) -> void:
	if not build.selected or not build.enabled: return
	var config = build.selected.configuration.duplicate(true)
	config[key] = value
	build.configure_selected(config, "Mechanism setting")

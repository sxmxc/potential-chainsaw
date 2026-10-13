extends VBoxContainer

const Schema = preload("res://scripts/mechanisms/settings_schema.gd")
const NUMBERS = Schema.NUMBERS
const FLAGS = Schema.FLAGS
const NUMBER = preload("res://scenes/ui/widgets/mechanism_number.tscn")
const CAPTIONS={"power":"Air power","range":"Range","angular_speed":"Paddle speed","delay":"Open after","auto_close":"Close after","strength":"Added speed","angle":"Launch angle","quantity":"Marbles","interval":"Release interval","start_delay":"First release"}
const UNITS={"power":"N","range":"m","angular_speed":"rad/s","delay":"s","auto_close":"s","strength":"m/s","angle":"°","interval":"s","start_delay":"s"}
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
		for key in fields:
			var input = fields[key]
			var editable: bool = not build.rules or build.rules.permits(piece.instance_id, "configure")
			if input is SettingSlider:
				input.set_value_no_signal(piece.configuration.get(key, NUMBERS[piece.definition.behavior][key][1]))
				input.editable = editable
				input.refresh_labels()
			else:
				input.set_pressed_no_signal(piece.configuration.get(key, FLAGS[piece.definition.behavior][key][1]))
				input.disabled = not editable
		return
	displayed_piece = piece
	fields.clear()
	for child in get_children(): remove_child(child); child.queue_free()
	if not piece or build.selection.size() != 1: return
	var behavior = piece.definition.behavior
	for key in NUMBERS.get(behavior, {}):
		var field: Array = NUMBERS[behavior][key]
		var row=NUMBER.instantiate()
		add_child(row)
		row.get_node("%Caption").text=CAPTIONS.get(key,field[0])
		var input: SettingSlider=row.get_node("%Value")
		input.suffix=UNITS.get(key,"")
		input.tooltip_text="0 waits for a linked Open action." if key=="delay" else ("0 keeps the gate open." if key=="auto_close" else field[0])
		input.min_value = field[2]
		input.max_value = field[3]
		input.step = field[4]
		input.value = piece.configuration.get(key, field[1])
		input.editable = not build.rules or build.rules.permits(piece.instance_id, "configure")
		input.setting_changed.connect(change.bind(key))
		fields[key] = input
	for key in FLAGS.get(behavior, {}):
		var field: Array = FLAGS[behavior][key]
		var input = CheckBox.new()
		input.text = field[0]
		input.button_pressed = piece.configuration.get(key, field[1])
		input.disabled = build.rules != null and not build.rules.permits(piece.instance_id, "configure")
		add_child(input)
		input.toggled.connect(change.bind(key))
		fields[key] = input

func change(value: Variant, key: String) -> void:
	if not build.selected or not build.enabled: return
	var config = build.selected.configuration.duplicate(true)
	config[key] = value
	build.configure_selected(config, "Mechanism setting")

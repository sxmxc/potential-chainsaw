extends VBoxContainer

const Schema = preload("res://scripts/mechanisms/settings_schema.gd")
const NUMBERS = Schema.NUMBERS
const FLAGS = Schema.FLAGS
var build: BuildManager

func configure(manager: BuildManager) -> void:
	build = manager
	build.selection_changed.connect(refresh)
	refresh(null)

func refresh(piece: TrackPiece) -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	if not piece or build.selection.size() != 1: return
	var behavior = piece.definition.behavior
	for key in NUMBERS.get(behavior, {}):
		var field: Array = NUMBERS[behavior][key]
		var label = Label.new()
		label.text = field[0]
		label.theme_type_variation = "SmallMutedLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(label)
		var input = SpinBox.new()
		input.min_value = field[2]
		input.max_value = field[3]
		input.step = field[4]
		input.value = piece.configuration.get(key, field[1])
		input.editable = not build.rules or build.rules.permits(piece.instance_id, "configure")
		add_child(input)
		input.value_changed.connect(change.bind(key))
	for key in FLAGS.get(behavior, {}):
		var field: Array = FLAGS[behavior][key]
		var input = CheckBox.new()
		input.text = field[0]
		input.button_pressed = piece.configuration.get(key, field[1])
		input.disabled = build.rules != null and not build.rules.permits(piece.instance_id, "configure")
		add_child(input)
		input.toggled.connect(change.bind(key))

func change(value: Variant, key: String) -> void:
	if not build.selected or not build.enabled: return
	var config = build.selected.configuration.duplicate(true)
	config[key] = value
	build.configure_selected(config, "Mechanism setting")

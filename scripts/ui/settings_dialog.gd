extends "res://scripts/ui/modal_window.gd"

signal settings_changed(window_changed: bool)
signal reset_camera
const BINDING_ROW = preload("res://scenes/ui/widgets/key_binding.tscn")
const ACTION_NAMES = {
	"build_cancel": "Cancel / clear selection", "build_remove": "Delete", "build_rotate": "Rotate", "build_move_piece": "Move", "build_select_tool": "Selection tool",
	"build_grid": "Show grid", "build_snap": "Magnetic snapping", "build_frame": "Frame selection", "build_frame_all": "Frame construction",
	"build_height_up": "Raise build height", "build_height_down": "Lower build height", "build_height_up_fine": "Raise height (fine)", "build_height_down_fine": "Lower height (fine)",
	"build_undo": "Undo", "build_redo": "Redo", "build_duplicate": "Duplicate", "build_save_track": "Save", "build_test_track": "Test / pause", "build_select_all": "Select all", "build_cycle_snap": "Attachment alternatives",
	"camera_forward": "Pan forward", "camera_back": "Pan back", "camera_left": "Pan left", "camera_right": "Pan right"
}
var settings: RefCounted
var binding_buttons: Dictionary = {}
var pending_action: String = ""

func _ready() -> void:
	super()
	var categories: Array[Button] = [%CameraCategory, %AudioCategory, %DisplayCategory, %ControlsCategory]
	for index in categories.size():
		var button := categories[index]
		button.pressed.connect(func():
			%Tabs.current_tab = index
			button.set_pressed_no_signal(true))
	%Tabs.tab_changed.connect(func(index):
		for category in categories.size(): categories[category].set_pressed_no_signal(category == index))
	%Close.pressed.connect(close)
	%ResetCamera.pressed.connect(func(): reset_camera.emit())
	%Tabs.tab_changed.connect(func(index): cancel_binding(); UIMotion.section(%Tabs.get_tab_control(index)); fit_content.call_deferred())
	visibility_changed.connect(func():
		if visible: refresh_values(); fit_content.call_deferred()
		else: cancel_binding())
	%Defaults.pressed.connect(func():
		cancel_binding()
		settings.reset_defaults()
		refresh_values()
		settings_changed.emit(true))
	for item in [[%Sensitivity,"camera","sensitivity"],[%ZoomSensitivity,"camera","zoom_sensitivity"],[%Master,"audio","Master"],[%Music,"audio","Music"],[%SFX,"audio","SFX"],[%UI,"audio","UI"],[%RenderScale,"display","render_scale"]]:
		item[0].value_changed.connect(change_value.bind(item[1],item[2]))
	for item in [[%InvertX,"camera","invert_x"],[%InvertY,"camera","invert_y"],[%VSync,"display","vsync"]]:
		item[0].toggled.connect(change_value.bind(item[1],item[2]))
	for item in [[%WindowMode,"mode"],[%Resolution,"resolution"],[%FrameLimit,"fps"],[%AntiAliasing,"msaa"]]:
		item[0].item_selected.connect(change_value.bind("display",item[1]))

func configure(model: RefCounted) -> void:
	settings = model
	for action in ConstructionInput.actions():
		add_binding(action, ACTION_NAMES[action])
	refresh_values()

func add_binding(action: String, caption: String) -> void:
	var row = BINDING_ROW.instantiate()
	%Bindings.add_child(row)
	row.get_node("%Caption").text = caption
	var button: Button = row.get_node("%Binding")
	binding_buttons[action] = button
	button.disabled = action == "build_cancel"
	button.pressed.connect(func():
		cancel_binding()
		pending_action = action
		button.text = "Press a key…"
		%BindingStatus.text = "Press a key or shortcut. Escape cancels.")

func change_value(value: Variant, section: String, key: String) -> void:
	if not settings: return
	settings.values[section][key] = value
	refresh_values()
	settings_changed.emit(section == "display" and key in ["mode", "resolution", "vsync"])

func refresh_values() -> void:
	if not settings: return
	for item in [[%Sensitivity,"camera","sensitivity"],[%ZoomSensitivity,"camera","zoom_sensitivity"],[%Master,"audio","Master"],[%Music,"audio","Music"],[%SFX,"audio","SFX"],[%UI,"audio","UI"],[%RenderScale,"display","render_scale"]]:
		item[0].set_value_no_signal(settings.values[item[1]][item[2]])
	for item in [[%InvertX,"camera","invert_x"],[%InvertY,"camera","invert_y"],[%VSync,"display","vsync"]]:
		item[0].set_pressed_no_signal(settings.values[item[1]][item[2]])
	for item in [[%WindowMode,"mode"],[%Resolution,"resolution"],[%FrameLimit,"fps"],[%AntiAliasing,"msaa"]]:
		item[0].select(settings.values.display[item[1]])
	%Resolution.disabled = settings.values.display.mode != 0
	%SensitivityValue.text = "%.1f×" % settings.values.camera.sensitivity
	%ZoomSensitivityValue.text = "%.1f×" % settings.values.camera.zoom_sensitivity
	%RenderScaleValue.text = "%d%%" % roundi(settings.values.display.render_scale * 100)
	for bus in ["Master","Music","SFX","UI"]:
		get_node("%" + bus + "Value").text = "%d%%" % roundi(settings.values.audio[bus] * 100)
	for action in binding_buttons:
		if action != pending_action:
			var names: PackedStringArray = []
			for event in InputMap.action_get_events(action): names.append(event.as_text().replace(" (Physical)", ""))
			binding_buttons[action].text = " / ".join(names)
			binding_buttons[action].tooltip_text = binding_buttons[action].text

func cancel_binding() -> void:
	pending_action = ""
	if settings: refresh_values()
	%BindingStatus.text = "Click a shortcut to change it. Escape always cancels."

func _input(event: InputEvent) -> void:
	if not visible or closing or pending_action.is_empty() or not event is InputEventKey or not event.pressed or event.echo: return
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_ESCAPE:
		cancel_binding()
		return
	if event.keycode in [KEY_CTRL,KEY_SHIFT,KEY_ALT,KEY_META]: return
	var binding = InputEventKey.new()
	binding.keycode = event.keycode
	binding.ctrl_pressed = event.ctrl_pressed
	binding.shift_pressed = event.shift_pressed
	binding.alt_pressed = event.alt_pressed
	binding.meta_pressed = event.meta_pressed
	var conflict = ConstructionInput.binding_conflict(pending_action, binding)
	if conflict == "puzzle_editor":
		%BindingStatus.text = "That shortcut opens the Puzzle Editor. Choose another."
		return
	if not conflict.is_empty():
		%BindingStatus.text = "Already used by %s. Choose another." % binding_buttons[conflict].get_parent().get_node("%Caption").text.to_lower()
		return
	ConstructionInput.set_binding(pending_action, binding)
	cancel_binding()
	settings_changed.emit(false)

func fit_content() -> void:
	if not visible or closing: return
	var available: Vector2 = get_parent().get_viewport().get_visible_rect().size
	size = Vector2i(mini(900, int(available.x) - 32), mini(int(get_node("Surface").get_combined_minimum_size().y), int(available.y) - 32))
	popup_centered(size)

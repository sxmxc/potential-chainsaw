extends "res://scripts/ui/modal_window.gd"

signal settings_changed(window_changed: bool)
signal reset_camera
const BINDING_ROW = preload("res://scenes/ui/widgets/key_binding.tscn")
const ACTION_NAMES = {
	"cancel": "Cancel / clear selection", "remove": "Delete", "rotate": "Rotate", "move_piece": "Move", "select_tool": "Selection tool",
	"grid": "Show grid", "snap": "Magnetic snapping", "frame": "Frame selection", "frame_all": "Frame construction",
	"height_up": "Raise build height", "height_down": "Lower build height", "height_up_fine": "Raise height (fine)", "height_down_fine": "Lower height (fine)",
	"undo": "Undo", "redo": "Redo", "duplicate": "Duplicate", "save_track": "Save", "test_track": "Test / pause", "select_all": "Select all", "cycle_snap": "Attachment alternatives"
}
var settings: RefCounted
var binding_buttons: Dictionary = {}
var pending_action: String = ""

func _ready() -> void:
	super()
	%Close.pressed.connect(close)
	%ResetCamera.pressed.connect(func(): reset_camera.emit())
	%Tabs.tab_changed.connect(func(_index): cancel_binding(); fit_content.call_deferred())
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
	for action in ConstructionInput.SHORTCUTS:
		add_binding("build_" + action, ACTION_NAMES[action])
	for action in ConstructionInput.CAMERA_SHORTCUTS:
		add_binding(action, {"camera_forward":"Pan forward","camera_back":"Pan back","camera_left":"Pan left","camera_right":"Pan right"}[action])
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
	if not visible or pending_action.is_empty() or not event is InputEventKey or not event.pressed or event.echo: return
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
	# Ctrl+Shift+P remains the developer editor shortcut.
	if binding.keycode == KEY_P and binding.ctrl_pressed and binding.shift_pressed:
		%BindingStatus.text = "That shortcut opens the Puzzle Editor. Choose another."
		return
	for action in binding_buttons:
		if action == pending_action: continue
		for existing in InputMap.action_get_events(action):
			if existing is InputEventKey and (existing.keycode == binding.keycode or existing.physical_keycode == binding.keycode) and existing.ctrl_pressed == binding.ctrl_pressed and existing.shift_pressed == binding.shift_pressed and existing.alt_pressed == binding.alt_pressed and existing.meta_pressed == binding.meta_pressed:
				%BindingStatus.text = "Already used by %s. Choose another." % binding_buttons[action].get_parent().get_node("%Caption").text.to_lower()
				return
	settings.set_binding(pending_action, binding)
	cancel_binding()
	settings_changed.emit(false)

func fit_content() -> void:
	if not visible: return
	var available: Vector2 = get_parent().get_viewport().get_visible_rect().size
	size = Vector2i(mini(720, int(available.x) - 32), mini(int(get_node("Surface").get_combined_minimum_size().y), int(available.y) - 32))
	popup_centered(size)

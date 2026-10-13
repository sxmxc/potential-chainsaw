class_name ConstructionInput
extends RefCounted

const SHORTCUTS = {
	"cancel": [KEY_ESCAPE], "remove": [KEY_DELETE], "rotate": [KEY_R],
	"move_piece": [KEY_M], "select_tool": [KEY_V], "grid": [KEY_G],
	"snap": [KEY_C], "frame": [KEY_F], "frame_all": [KEY_HOME],
	"height_up": [KEY_PAGEUP], "height_down": [KEY_PAGEDOWN],
	"height_up_fine": [KEY_PAGEUP, false, true], "height_down_fine": [KEY_PAGEDOWN, false, true],
	"undo": [KEY_Z, true], "redo": [KEY_Y, true], "duplicate": [KEY_D, true],
	"save_track": [KEY_S, true], "test_track": [KEY_SPACE],
	"select_all": [KEY_A, true], "cycle_snap": [KEY_TAB]
}

const CAMERA_SHORTCUTS = {"camera_forward": KEY_W, "camera_back": KEY_S, "camera_left": KEY_A, "camera_right": KEY_D}

static func install(reset: bool = false) -> void:
	for action in actions():
		if InputMap.has_action(action):
			if not reset: continue
			InputMap.action_erase_events(action)
		else: InputMap.add_action(action)
		for event in default_events(action): InputMap.action_add_event(action, event)

static func actions() -> Array[String]:
	var result: Array[String] = []
	for shortcut in SHORTCUTS: result.append("build_" + shortcut)
	for action in CAMERA_SHORTCUTS: result.append(action)
	return result

static func default_events(action: String) -> Array[InputEventKey]:
	var event = InputEventKey.new()
	if action in CAMERA_SHORTCUTS:
		event.physical_keycode = CAMERA_SHORTCUTS[action]
	else:
		var data: Array = SHORTCUTS[action.trim_prefix("build_")]
		event.keycode = data[0]
		event.ctrl_pressed = data.size() > 1 and bool(data[1])
		event.shift_pressed = data.size() > 2 and bool(data[2])
	var result: Array[InputEventKey] = [event]
	if action == "build_redo":
		var shift_redo = InputEventKey.new()
		shift_redo.keycode = KEY_Z
		shift_redo.ctrl_pressed = true
		shift_redo.shift_pressed = true
		result.append(shift_redo)
	return result

static func set_binding(action: String, event: InputEventKey) -> void:
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)

static func binding_conflict(action: String, binding: InputEventKey) -> String:
	if binding.keycode == KEY_P and binding.ctrl_pressed and binding.shift_pressed:
		return "puzzle_editor"
	for other in actions():
		if other == action: continue
		for existing in InputMap.action_get_events(other):
			if existing is InputEventKey and (existing.keycode == binding.keycode or existing.physical_keycode == binding.keycode) and existing.ctrl_pressed == binding.ctrl_pressed and existing.shift_pressed == binding.shift_pressed and existing.alt_pressed == binding.alt_pressed and existing.meta_pressed == binding.meta_pressed:
				return other
	return ""

static func load_bindings(config: ConfigFile) -> void:
	if not config.has_section("bindings"): return
	for action in config.get_section_keys("bindings"):
		var event: Variant = config.get_value("bindings", action)
		if action in actions() and action != "build_cancel" and event is InputEventKey and (event.keycode != 0 or event.physical_keycode != 0):
			set_binding(action, event)

static func save_bindings(config: ConfigFile) -> void:
	# Persist overrides directly from the live InputMap, without a second copy.
	for action in actions():
		if action == "build_cancel": continue
		var events = InputMap.action_get_events(action)
		var defaults = default_events(action)
		var unchanged = events.size() == defaults.size()
		for index in events.size():
			if not unchanged: break
			var event = events[index] as InputEventKey
			unchanged = event != null and event.get_keycode_with_modifiers() == defaults[index].get_keycode_with_modifiers() and event.get_physical_keycode_with_modifiers() == defaults[index].get_physical_keycode_with_modifiers()
		if not unchanged and not events.is_empty(): config.set_value("bindings", action, events[0])

static func typing(viewport: Viewport) -> bool:
	var focus = viewport.gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit or focus is SpinBox

static func height_text(value: float) -> String:
	return ("%.3f" % value).rstrip("0").rstrip(".")

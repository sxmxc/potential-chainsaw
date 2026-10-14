class_name ConstructionInput
extends RefCounted

# Defaults are authored in Project Settings > Input Map and loaded by Godot.
static func actions() -> Array[String]:
	var result: Array[String] = []
	for property in ProjectSettings.get_property_list():
		var path: String = property.name
		if path.begins_with("input/build_") or path.begins_with("input/camera_"):
			result.append(path.trim_prefix("input/"))
	return result

static func reset_bindings() -> void:
	for action in actions():
		InputMap.action_erase_events(action)
		for event: InputEvent in ProjectSettings.get_setting("input/" + action).events:
			InputMap.action_add_event(action, event)

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
		var defaults: Array = ProjectSettings.get_setting("input/" + action).events
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

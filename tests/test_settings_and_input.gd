extends "res://tests/support/game_test.gd"

const Settings = preload("res://scripts/game_settings.gd")
var previous_bindings: Dictionary = {}

func before_each() -> void:
	super()
	for action in ConstructionInput.actions():
		previous_bindings[action] = InputMap.action_get_events(action)

func after_each() -> void:
	for action in previous_bindings:
		InputMap.action_erase_events(action)
		for event in previous_bindings[action]: InputMap.action_add_event(action, event)
	previous_bindings.clear()
	super()

func test_legacy_sensitivity_and_invalid_values() -> void:
	var config = ConfigFile.new()
	config.set_value("camera", "sensitivity", 2)
	config.set_value("display", "msaa", 1000)
	config.set_value("display", "mode", "invalid")
	config.set_value("audio", "Music", -5.0)
	assert_eq(config.save(SaveStorage.resolve(Settings.PATH)), OK)
	var restored = Settings.new()
	restored.load_saved()
	assert_eq(restored.values.camera.sensitivity, 2.0, "Old sensitivity-only settings still load")
	assert_eq(restored.values.display.msaa, 3)
	assert_eq(restored.values.display.mode, 0)
	assert_eq(restored.values.audio.Music, 0.0)
	assert_eq(restored.values.camera.zoom_sensitivity, 1.0)


func test_binding_persistence_uses_live_input_map() -> void:
	var settings := Settings.new()
	var redo = InputEventKey.new()
	redo.keycode = KEY_J
	redo.ctrl_pressed = true
	ConstructionInput.set_binding("build_redo", redo)
	var camera = InputEventKey.new()
	camera.physical_keycode = KEY_UP
	ConstructionInput.set_binding("camera_forward", camera)
	assert_eq(settings.save(), OK)
	ConstructionInput.reset_bindings()
	settings.load_saved()
	assert_eq(InputMap.action_get_events("build_redo").size(), 1, "Rebound redo replaces both default shortcuts")
	assert_true(InputMap.action_has_event("build_redo", redo))
	assert_eq(InputMap.action_get_events("camera_forward")[0].physical_keycode, KEY_UP, "Physical bindings retain their key type")
	ConstructionInput.reset_bindings()
	assert_eq(InputMap.action_get_events("build_redo").size(), 2, "Restore defaults restores both redo shortcuts")
	var conflict = InputEventKey.new()
	conflict.keycode = KEY_W
	assert_eq(ConstructionInput.binding_conflict("build_rotate", conflict), "camera_forward", "Logical shortcuts conflict with physical camera keys")
	conflict.keycode = KEY_P
	conflict.ctrl_pressed = true
	conflict.shift_pressed = true
	assert_eq(ConstructionInput.binding_conflict("build_rotate", conflict), "puzzle_editor")

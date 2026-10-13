extends "res://tests/support/scene_test.gd"

const Settings = preload("res://scripts/game_settings.gd")
var game: Node
var sender: GutInputSender

func before_each() -> void:
	super()
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	game.enter_sandbox()
	sender = GutInputSender.new(Input)
	autofree(sender)
	await settle()

func after_each() -> void:
	sender.release_all()
	await super()

func settle() -> void:
	for frame in 4: await get_tree().process_frame

func mouse_button(position: Vector2, button: int, pressed: bool) -> void:
	sender.mouse_motion(position)
	await get_tree().process_frame
	if button == MOUSE_BUTTON_LEFT:
		if pressed: sender.mouse_left_button_down(position)
		else: sender.mouse_left_button_up(position)
	else:
		if pressed: sender.mouse_right_button_down(position)
		else: sender.mouse_right_button_up(position)
	await get_tree().process_frame

func test_audio_graphics_and_camera_settings_apply() -> void:
	var dialog = game.settings_dialog
	dialog.get_node("%Music").value = 0.4
	dialog.get_node("%SFX").value = 0.0
	dialog.get_node("%Sensitivity").value = 1.8
	dialog.get_node("%ZoomSensitivity").value = 1.4
	dialog.get_node("%InvertY").set_pressed(true)
	dialog.get_node("%AntiAliasing").item_selected.emit(2)
	dialog.get_node("%FrameLimit").item_selected.emit(3)
	dialog.get_node("%RenderScale").value = 0.75
	assert_almost_eq(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Music")), 0.4, 0.001)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	assert_eq(game.sandbox.camera.sensitivity, 1.8)
	assert_almost_eq(game.sandbox.camera.zoom_sensitivity, 1.4, 0.0001)
	assert_true(game.sandbox.camera.invert_y)
	assert_eq(game.get_viewport().msaa_3d, Viewport.MSAA_4X)
	assert_eq(game.get_viewport().scaling_3d_scale, 0.75)
	assert_eq(Engine.max_fps, 120)
	var restored = Settings.new()
	restored.load_saved()
	assert_almost_eq(restored.values.camera.zoom_sensitivity, game.settings.values.camera.zoom_sensitivity, 0.0001, "Camera setting survives reload")
	assert_eq(restored.values.audio, game.settings.values.audio)
	assert_eq(restored.values.display, game.settings.values.display)

func test_legacy_sensitivity_and_invalid_values() -> void:
	var config = ConfigFile.new()
	config.set_value("camera", "sensitivity", 2)
	config.set_value("display", "msaa", 1000)
	config.set_value("display", "mode", "invalid")
	config.set_value("audio", "Music", -5.0)
	assert_eq(config.save(SavePaths.resolve(Settings.PATH)), OK)
	var restored = Settings.new()
	restored.load_saved()
	assert_eq(restored.values.camera.sensitivity, 2.0, "Old sensitivity-only settings still load")
	assert_eq(restored.values.display.msaa, 3)
	assert_eq(restored.values.display.mode, 0)
	assert_eq(restored.values.audio.Music, 0.0)
	assert_eq(restored.values.camera.zoom_sensitivity, 1.0)

func test_restore_defaults_restores_bindings_and_audio() -> void:
	var event = InputEventKey.new()
	event.keycode = KEY_J
	ConstructionInput.set_binding("build_rotate", event)
	game.settings_dialog.get_node("%Music").value = 0.0
	game.settings_dialog.get_node("%InvertX").set_pressed(true)
	game.settings_dialog.get_node("%Defaults").pressed.emit()
	assert_eq(InputMap.action_get_events("build_rotate")[0].keycode, KEY_R)
	assert_eq(game.settings.values, Settings.DEFAULTS)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	assert_eq(game.sandbox.camera.sensitivity, 1.0)
	var restored = Settings.new()
	restored.load_saved()
	assert_eq(restored.values, Settings.DEFAULTS)
	var config = ConfigFile.new()
	assert_eq(config.load(SavePaths.resolve(Settings.PATH)), OK)
	assert_false(config.has_section("bindings"), "Defaults need no saved binding overrides")

func test_key_rebinding_conflicts_and_escape() -> void:
	game.handle_action("settings")
	var dialog = game.settings_dialog
	dialog.get_node("%Tabs").current_tab = 3
	await settle()
	dialog.binding_buttons["build_rotate"].pressed.emit()
	var event = InputEventKey.new()
	event.keycode = KEY_DELETE
	event.pressed = true
	dialog._input(event)
	assert_eq(dialog.pending_action, "build_rotate", "Conflicting binding stays pending")
	assert_eq(InputMap.action_get_events("build_rotate")[0].keycode, KEY_R)
	event.keycode = KEY_J
	dialog._input(event)
	assert_eq(dialog.pending_action, "")
	assert_eq(InputMap.action_get_events("build_rotate")[0].keycode, KEY_J)
	ConstructionInput.install(true)
	var restored = Settings.new()
	restored.load_saved()
	assert_eq(InputMap.action_get_events("build_rotate")[0].keycode, KEY_J, "Saved binding replaces the default on reload")
	var piece = game.sandbox.build.spawn(game.catalog.get_piece("straight"), Transform3D.IDENTITY)
	dialog.close()
	game.sandbox.build.select(piece)
	game.sandbox.build._unhandled_input(event)
	assert_almost_eq(piece.rotation.y, PI / 2, 0.001, "Rebound shortcut rotates the selected track")
	game.handle_action("settings")
	dialog.binding_buttons["build_rotate"].pressed.emit()
	event.keycode = KEY_ESCAPE
	dialog._input(event)
	assert_eq(dialog.pending_action, "")
	assert_true(dialog.visible, "Escape cancels rebinding before closing settings")

func test_binding_persistence_uses_live_input_map() -> void:
	var redo = InputEventKey.new()
	redo.keycode = KEY_J
	redo.ctrl_pressed = true
	ConstructionInput.set_binding("build_redo", redo)
	var camera = InputEventKey.new()
	camera.physical_keycode = KEY_UP
	ConstructionInput.set_binding("camera_forward", camera)
	assert_eq(game.settings.save(), OK)
	ConstructionInput.install(true)
	game.settings.load_saved()
	assert_eq(InputMap.action_get_events("build_redo").size(), 1, "Rebound redo replaces both default shortcuts")
	assert_true(InputMap.action_has_event("build_redo", redo))
	assert_eq(InputMap.action_get_events("camera_forward")[0].physical_keycode, KEY_UP, "Physical bindings retain their key type")
	ConstructionInput.install()
	assert_eq(InputMap.action_get_events("build_redo").size(), 1, "Installing actions preserves a rebound redo")
	ConstructionInput.install(true)
	assert_eq(InputMap.action_get_events("build_redo").size(), 2, "Restore defaults restores both redo shortcuts")
	var conflict = InputEventKey.new()
	conflict.keycode = KEY_W
	assert_eq(ConstructionInput.binding_conflict("build_rotate", conflict), "camera_forward", "Logical shortcuts conflict with physical camera keys")
	conflict.keycode = KEY_P
	conflict.ctrl_pressed = true
	conflict.shift_pressed = true
	assert_eq(ConstructionInput.binding_conflict("build_rotate", conflict), "puzzle_editor")

func test_right_drag_keeps_selection_and_placement() -> void:
	var build: BuildManager = game.sandbox.build
	var piece = build.spawn(game.catalog.get_piece("straight"), Transform3D.IDENTITY)
	build.select(piece)
	var point = Vector2(650, 350)
	await mouse_button(point, MOUSE_BUTTON_RIGHT, true)
	var yaw: float = game.sandbox.camera.target_yaw
	var motion = InputEventMouseMotion.new()
	motion.position = point + Vector2(30, 0)
	motion.relative = Vector2(30, 0)
	game.get_viewport().push_input(motion, true)
	await settle()
	assert_eq(build.selected, piece)
	assert_ne(game.sandbox.camera.target_yaw, yaw)
	await mouse_button(point, MOUSE_BUTTON_RIGHT, false)
	build.choose(game.catalog.get_piece("straight"))
	await mouse_button(point, MOUSE_BUTTON_RIGHT, true)
	assert_not_null(build.chosen, "Right-click preserves the placement preview")
	await mouse_button(point, MOUSE_BUTTON_RIGHT, false)
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game.get_viewport().push_input(escape, true)
	await settle()
	assert_null(build.chosen, "Escape cancels placement")

func test_real_repeated_spinbox_clicks_keep_inspector_open() -> void:
	var build: BuildManager = game.sandbox.build
	var piece = build.spawn(game.catalog.get_piece("fan-standing-two"), Transform3D.IDENTITY)
	if not piece:
		fail_test("Fan fixture must exist")
		return
	build.select(piece)
	await settle()
	get_window().grab_focus()
	var inspector = game.get_node("%HUD").get_node("%Inspector")
	var field: SpinBox = inspector.get_node("%MechanismSettings").fields["power"]
	var initial = field.value
	for click in 3:
		var point = field.get_global_rect().position + Vector2(field.size.x - 8, 8)
		await mouse_button(point, MOUSE_BUTTON_LEFT, true)
		await settle()
		await mouse_button(point, MOUSE_BUTTON_LEFT, false)
	assert_eq(build.selected, piece)
	assert_true(inspector.visible)
	assert_almost_eq(field.value, initial + field.step * 3, 0.001)
	assert_eq(inspector.get_node("%MechanismSettings").fields.power, field, "The same input survives every click")
	build.undo()
	await settle()
	assert_true(inspector.visible, "Undo keeps properties visible on the restored piece")
	build.redo()
	await settle()
	assert_true(inspector.visible, "Redo keeps properties visible")

func test_settings_tabs_fit_supported_resolutions() -> void:
	for resolution in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]:
		game.qa_resolution(resolution.x, resolution.y)
		game.handle_action("settings")
		for tab in 4:
			game.settings_dialog.get_node("%Tabs").current_tab = tab
			await settle()
			assert_lt(game.settings_dialog.size.y, resolution.y, "Settings fit the viewport")
			assert_lt(game.settings_dialog.size.x, resolution.x, "Settings fit horizontally")
		game.settings_dialog.close()
		assert_true(game.sandbox.build.enabled)

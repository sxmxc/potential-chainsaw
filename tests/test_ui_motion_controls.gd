extends GutTest

func settle_motion() -> void:
	await wait_seconds(UIMotion.ENTER_TIME + UIMotion.EXIT_TIME)

func test_native_properties_and_interrupted_panel_input() -> void:
	var properties: Array[String] = []
	for property in ClassDB.class_get_property_list(&"Control"):
		properties.append(property.name)
	for property in ["offset_transform_enabled", "offset_transform_position_ratio", "offset_transform_scale", "offset_transform_pivot_ratio", "offset_transform_visual_only"]:
		assert_has(properties, property, "Installed ClassDB exposes the native presentation property")
	var container := HBoxContainer.new()
	add_child_autofree(container)
	var panel := PanelContainer.new()
	container.add_child(panel)
	var button := Button.new()
	panel.add_child(button)
	button.text = "Action"
	var neighbor := Button.new()
	neighbor.text = "Neighbor"
	container.add_child(neighbor)
	await get_tree().process_frame
	var motion := UIMotion.attach(panel, Vector2(-UIMotion.PANEL_SHIFT, 0.0))
	var original_rect := panel.get_rect()
	var neighbor_rect := neighbor.get_rect()
	button.grab_focus()
	motion.set_open(false)
	assert_true(panel.visible, "Closing panel retains its input-blocking surface until exit completes")
	assert_false(button.is_visible_in_tree() and button.has_focus(), "Closing releases keyboard focus")
	assert_eq(button.mouse_behavior_recursive, Control.MOUSE_BEHAVIOR_DISABLED)
	motion.set_open(true)
	motion.set_open(false)
	motion.set_open(true)
	await settle_motion()
	assert_true(panel.visible and button.is_visible_in_tree())
	assert_eq(button.mouse_behavior_recursive, Control.MOUSE_BEHAVIOR_INHERITED)
	assert_eq(panel.get_rect(), original_rect, "Motion leaves Container layout intact")
	assert_eq(neighbor.get_rect(), neighbor_rect, "Neighbor does not move")
	assert_eq(panel.offset_transform_position_ratio, Vector2.ZERO)
	assert_eq(panel.offset_transform_scale, Vector2.ONE)
	assert_eq(panel.modulate.a, 1.0)
	motion.set_open(false)
	await settle_motion()
	assert_false(panel.visible)
	motion.set_open(true)
	container.hide()
	container.show()
	await settle_motion()
	assert_true(panel.visible)
	assert_eq(panel.modulate.a, 1.0, "Ancestor hiding cancels partial presentation")
	assert_eq(panel.focus_behavior_recursive, Control.FOCUS_BEHAVIOR_INHERITED)
	motion.set_open(false)
	container.hide()
	container.show()
	assert_false(panel.visible, "Hiding an ancestor settles a pending exit")

func click(viewport: SubViewport, point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	viewport.push_input(move)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		viewport.push_input(event)
	await get_tree().process_frame

func test_moving_surface_blocks_clicks_and_hidden_surface_releases_them() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 400)
	add_child_autofree(viewport)
	var behind := Button.new()
	behind.size = Vector2(800, 400)
	viewport.add_child(behind)
	var panel := PanelContainer.new()
	panel.position = Vector2(200, 60)
	viewport.add_child(panel)
	var action := Button.new()
	action.custom_minimum_size = Vector2(160, 80)
	panel.add_child(action)
	var actions := [0]
	var background_clicks := [0]
	action.pressed.connect(func(): actions[0] += 1)
	behind.pressed.connect(func(): background_clicks[0] += 1)
	await get_tree().process_frame
	var motion := UIMotion.attach(panel, Vector2(-UIMotion.PANEL_SHIFT, 0.0))
	motion.set_open(false)
	await wait_seconds(UIMotion.EXIT_TIME * 0.3)
	motion.tween.pause()
	var visual_point: Vector2 = panel.get_global_transform_with_canvas() * Vector2(3.0, panel.size.y * 0.5)
	await click(viewport, visual_point)
	assert_eq(actions[0], 0, "Closing descendants cannot activate")
	assert_eq(background_clicks[0], 0, "Displayed moving surface blocks the world behind it")
	motion.tween.play()
	await settle_motion()
	await click(viewport, visual_point)
	assert_eq(background_clicks[0], 1, "A hidden panel leaves no invisible input area")
	motion.set_open(true)
	await settle_motion()
	await click(viewport, action.get_global_rect().get_center())
	assert_eq(actions[0], 1, "Completed entrance restores normal button input")


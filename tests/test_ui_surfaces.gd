extends GutTest

func test_catalog_shrinks_after_a_large_viewport_without_retaining_its_height() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 900)
	add_child_autoqfree(viewport)
	var column := VBoxContainer.new()
	viewport.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var catalog = load("res://scenes/ui/toolbox.tscn").instantiate()
	column.add_child(catalog)
	catalog.configure(PieceCatalog.new())
	await get_tree().process_frame
	await get_tree().process_frame
	viewport.size = Vector2i(1024, 380)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_lte(column.size.y, 380.0, "Resizing cannot retain a larger catalog minimum")
	assert_lte(catalog.size.y, 380.0)
	assert_gt(catalog.get_node("%Scroll").get_v_scroll_bar().max_value, catalog.size.y, "The full catalogue remains available by scrolling")

func test_long_message_keeps_action_visible_and_content_scrollable() -> void:
	if DisplayServer.get_name() == "headless":
		pending("Window layout requires a real renderer.")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 720)
	viewport.gui_embed_subwindows = true
	add_child_autoqfree(viewport)
	var dialog = load("res://scenes/ui/dialogs/message_dialog.tscn").instantiate()
	viewport.add_child(dialog)
	dialog.dialog_text = "A long explanation remains available.\n".repeat(80)
	dialog.present()
	await get_tree().process_frame
	await get_tree().process_frame
	var message := dialog.get_node("%Message") as RichTextLabel
	assert_lt(dialog.size.y, viewport.size.y, "Long messages cannot push the action beyond the viewport")
	assert_gt(message.get_v_scroll_bar().max_value, message.size.y, "Overflow can be read by scrolling")
	assert_true(Rect2(Vector2.ZERO, Vector2(dialog.size)).encloses(dialog.get_node("%Close").get_rect()), "The close action remains inside the dialog")

func test_extension_picker_empty_search_shows_compatible_pieces() -> void:
	var picker = load("res://scenes/ui/widgets/extension_picker.tscn").instantiate()
	add_child_autoqfree(picker)
	var build: BuildManager = autofree(BuildManager.new())
	build.catalog = PieceCatalog.new()
	picker.configure(build)
	picker.target = {"connector": build.catalog.get_piece("straight").connectors[0]}
	picker.refresh()
	assert_gt(picker.get_node("%Pieces").get_child_count(), 0, "An empty search includes compatible pieces")
	picker.get_node("%Search").text = "no matching piece name"
	picker.get_node("%Search").text_changed.emit("no matching piece name")
	assert_eq(picker.get_node("%Pieces").get_child_count(), 0)
	picker.get_node("%Search").clear()
	picker.get_node("%Search").text_changed.emit("")
	assert_gt(picker.get_node("%Pieces").get_child_count(), 0, "Clearing the search restores compatible pieces")

func test_modal_fits_content_growth_and_preserves_interrupted_close() -> void:
	if DisplayServer.get_name() == "headless":
		pending("The dummy display reports 1x1 native windows. Run this sizing check with a renderer.")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.gui_embed_subwindows = true
	add_child_autoqfree(viewport)
	var dialog = load("res://scenes/ui/dialogs/name_dialog.tscn").instantiate()
	viewport.add_child(dialog)
	dialog.set_name_text("A machine")
	var authored_width: int = dialog.size.x
	dialog.open()
	await get_tree().process_frame
	var surface := dialog.get_node("Surface") as Control
	assert_gte(dialog.size.x, authored_width, "Content sizing preserves the scene's chosen dialog width")
	assert_gte(dialog.size.y, int(ceilf(surface.get_combined_minimum_size().y)), "The saved dialog cannot clip its own contents")
	var extra := Label.new()
	extra.text = "More information\nAdditional details\nAnother line\nOne last line"
	dialog.get_node("Surface/Contents").add_child(extra)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gte(dialog.size.y, int(ceilf(surface.get_combined_minimum_size().y)), "Content growth resizes the native window")
	dialog.dismiss()
	dialog.present()
	await get_tree().create_timer(UIMotion.ENTER_TIME + 0.05).timeout
	assert_true(dialog.visible, "Reopening interrupts the close without hiding the dialog later")
	assert_false(dialog.closing)
	dialog.dismiss()
	await get_tree().create_timer(UIMotion.EXIT_TIME + 0.05).timeout
	assert_false(dialog.visible)

func test_settings_categories_preserve_values_and_binding_capture() -> void:
	var dialog = load("res://scenes/ui/dialogs/settings_dialog.tscn").instantiate()
	add_child_autoqfree(dialog)
	var settings := preload("res://scripts/game_settings.gd").new()
	dialog.configure(settings)
	var original := settings.values.duplicate(true)
	dialog.get_node("%ControlsCategory").pressed.emit()
	dialog.binding_buttons["build_rotate"].pressed.emit()
	assert_eq(dialog.pending_action, "build_rotate")
	dialog.get_node("%AudioCategory").pressed.emit()
	assert_eq(dialog.get_node("%Tabs").current_tab, 1)
	assert_eq(dialog.pending_action, "", "Leaving Controls cancels key capture")
	assert_true(dialog.get_node("%AudioCategory").button_pressed)
	assert_false(dialog.get_node("%ControlsCategory").button_pressed)
	assert_eq(settings.values, original, "Category navigation never changes or saves preferences")

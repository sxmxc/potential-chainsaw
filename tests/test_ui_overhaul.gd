extends "res://tests/support/scene_test.gd"

func settle() -> void:
	await wait_seconds(UIMotion.ENTER_TIME + UIMotion.EXIT_TIME + UIMotion.SCREEN_TIME)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("MARBLE_ENGINEER_UI_CAPTURE") != "1": return
	await RenderingServer.frame_post_draw
	assert_eq(get_viewport().get_texture().get_image().save_png("res://.godot/overhaul-" + label + ".png"), OK)

func test_catalog_inventory_goals_boundaries_and_publication_readiness() -> void:
	var game: GameManager = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1920, 1080)
	await settle()
	await capture("menu")
	var session := game.workspace.session
	var build := game.workspace.world.build
	var drawer := game.workspace.authoring
	var data: Dictionary = session.store.load_campaign().levels.filter(func(level): return level.id == "campaign-01")[0]
	session.editor(data)
	drawer.open()
	await settle()
	await capture("setup")
	var starting: Array = build.snapshot()
	drawer.get_node("%Tabs").current_tab = 1
	await settle()
	var toolbox := game.workspace.hud.get_node("%Toolbox")
	var previous: int = session.puzzle.inventory.get("straight", 0)
	toolbox.piece_chosen.emit(session.catalog.get_piece("straight"))
	assert_eq(session.puzzle.inventory.straight, previous + 1)
	assert_eq(build.snapshot(), starting, "Inventory selection never places a world object")
	assert_null(build.chosen)
	var row: Node = drawer.get_node("%InventoryList").get_child(0)
	row.get_node("%Quantity").value = 4
	assert_eq(session.puzzle.inventory.straight, 4, "Quantities commit directly")
	await capture("inventory")
	drawer.get_node("%Tabs").current_tab = 2
	await settle()
	var boundary := game.workspace.world.boundary
	assert_true(boundary.selecting)
	assert_false(build.enabled, "Boundary editing cannot accidentally place construction pieces")
	session.puzzle.restricted_zones = [[0, 0, 0, 2, 2, 2]]
	boundary.select_region(0)
	boundary.set_elevation(3.0, false)
	assert_eq(session.puzzle.restricted_zones[0][4], 3.0)
	assert_eq(session.puzzle.bounds, data.bounds, "Restricted elevation edits leave build elevations intact")
	var input := GutInputSender.new(boundary)
	var original_zone: Array = session.puzzle.restricted_zones[0].duplicate()
	var screen := build.camera.unproject_position(Vector3(1, 3, 1))
	build.dirty = false
	input.mouse_left_button_down(screen)
	input.mouse_left_button_up(screen)
	assert_false(build.dirty, "Selecting a region alone leaves the draft unchanged")
	input.mouse_left_button_down(screen)
	assert_not_null(boundary.drag_start, "The viewport selects the visible restricted volume")
	input.mouse_motion(screen + Vector2(70, 0))
	assert_ne(session.puzzle.restricted_zones[0], original_zone, "Dragging moves the spatial region")
	input.key_down(KEY_ESCAPE)
	input.key_up(KEY_ESCAPE)
	input.mouse_left_button_up(screen)
	assert_eq(session.puzzle.restricted_zones[0], original_zone, "Escape restores a cancelled region move")
	input.mouse_left_button_down(screen)
	input.mouse_motion(screen + Vector2(70, 0))
	game.handle_action("menu")
	input.mouse_left_button_up(screen)
	assert_eq(session.puzzle.restricted_zones[0], original_zone, "Opening a modal cancels a provisional region move")
	assert_null(boundary.drag_start)
	assert_false(build.enabled)
	game.menu_dialog.close()
	await settle()
	assert_true(boundary.selecting and not build.enabled, "Closing a modal retains the boundary tool")
	drawer.get_node("%RegionX").value = 1.25
	assert_eq(float(session.puzzle.restricted_zones[0][0]), 1.25)
	assert_eq(session.puzzle.bounds, data.bounds)
	drawer.refresh_zones()
	await capture("boundaries")
	drawer.get_node("%Tabs").current_tab = 3
	await settle()
	assert_true(build.enabled)
	var goal: Dictionary = session.puzzle.objectives[0]
	drawer.edit_objective(0)
	drawer.get_node("%RequiredCount").value = 2
	drawer.get_node("%AddObjective").pressed.emit()
	assert_eq(session.puzzle.objectives.size(), 1, "Editing replaces a goal rather than adding a duplicate")
	assert_eq(session.puzzle.objectives[0].count, 2)
	assert_eq(session.puzzle.objectives[0].target, goal.target)
	await capture("objectives")
	drawer.get_node("%Tabs").current_tab = 4
	await settle()
	assert_true(drawer.publish_blocked, "Editing requirements invalidates publication proof")
	assert_eq(drawer.get_node("%NextAction").text, "Test as player")
	assert_true(drawer.get_node("%PublishOnline").disabled)
	for action in ["SaveDraft", "Validate", "PublishOnline", "Export", "NewPuzzle", "OpenPuzzle"]:
		var button: Button = drawer.get_node("%" + action)
		if not button.is_visible_in_tree(): continue
		var text_width := button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
		assert_gte(button.size.x - button.get_theme_stylebox("normal").get_minimum_size().x, text_width, "Publishing utilities keep their full labels in flow containers")
	await capture("publish")
	drawer.hide()
	session.sandbox()
	assert_false(boundary.selecting)
	assert_true(build.enabled)
	assert_false(toolbox.inventory_editing)

func test_preview_navigation_and_pause_keep_context() -> void:
	var game: GameManager = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1920, 1080)
	await settle()
	var browser := game.get_node("%PuzzleBrowser")
	browser.open_campaign()
	await settle()
	assert_gt(browser.get_node("%Preview").get_node("%Models").get_child_count(), 0)
	await capture("campaign")
	browser.hide()
	game.modal_closed()
	game.handle_action("sandbox")
	await settle()
	game.handle_action("examples")
	await settle()
	var tracks := game.get_node("%TrackBrowser")
	assert_gt(tracks.get_node("%Preview").get_node("%Models").get_child_count(), 0)
	await capture("tracks")
	tracks.hide()
	game.modal_closed()
	game.handle_action("menu")
	await settle()
	assert_true(game.menu_dialog.get_node("%Resume").visible)
	assert_false(game.workspace.world.build.enabled)
	await capture("pause")
	game.menu_dialog.close()
	await settle()
	assert_true(game.workspace.world.build.enabled)
	game.handle_action("settings")
	await settle()
	await capture("settings")

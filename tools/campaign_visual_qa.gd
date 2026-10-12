extends SceneTree

var game: Node
var evidence: Array = []

func _initialize() -> void:
	call_deferred("run")

func capture(label: String, resolution: Vector2i) -> void:
	await create_timer(0.25).timeout
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var path = "res://docs/campaign-qa/%s-%dx%d.png" % [label, resolution.x, resolution.y]
	root.get_texture().get_image().save_png(path)
	evidence.append({"screen": label, "resolution": [resolution.x, resolution.y], "path": path})

func run() -> void:
	root.gui_embed_subwindows = true
	DirAccess.make_dir_recursive_absolute("res://docs/campaign-qa")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var session: PuzzleSession = game.puzzle_session
	var progress_before = session.store.progress.duplicate(true)
	var files = DirAccess.get_files_at("res://resources/campaign")
	var first: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/campaign/" + files[0]))
	var last: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/campaign/" + files[-1]))
	for resolution in [Vector2i(1024, 720), Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = resolution
		game.show_main_menu()
		await capture("main-menu", resolution)
		game.puzzle_browser.open()
		await capture("level-selection", resolution)
		game.puzzle_browser.hide()
		session.player(first)
		await capture("puzzle-hud", resolution)
		var build: BuildManager = game.sandbox.build
		build.choose(game.catalog.get_piece("straight"))
		build.proposed = Transform3D.IDENTITY
		build.valid = true
		build.ghost.visible = true
		build.commit()
		build.cancel()
		game.qa_test()
		for frame in 900:
			await physics_frame
			if game.sandbox.simulation.state != SimulationManager.State.RUNNING: break
		await capture("completion", resolution)
		game.completion.hide()
		session.editor(last)
		game.sandbox.build.select(game.sandbox.build.pieces[1])
		await capture("mechanism-inspector", resolution)
		game.authoring.open()
		var tabs: TabContainer = game.authoring.get_node("Surface/Contents/Tabs")
		for index in tabs.get_tab_count():
			tabs.current_tab = index
			await capture("author-" + tabs.get_tab_title(index).to_lower(), resolution)
		game.authoring.hide()
		session.test_player()
		await capture("test-as-player", resolution)
		session.return_editor()
		await capture("return-to-editor", resolution)
		if resolution.x == 1280:
			for index in [2, 3]:
				build.select(build.pieces[index])
				game.get_node("%HUD").get_node("%Inspector").get_node("Scroll").scroll_vertical = 230
				await capture("settings-" + build.selected.definition.behavior, resolution)
			for id in ["bucket-elevator", "fan-standing-two", "fan-simple-four", "diverter"]:
				var piece = build.spawn(game.catalog.get_piece(id), Transform3D(Basis.IDENTITY, Vector3(4, 0, 0)))
				build.select(piece)
				game.get_node("%HUD").get_node("%Inspector").get_node("Scroll").scroll_vertical = 230
				await capture("settings-" + id, resolution)
				session.editor(last)
	var file = FileAccess.open("res://docs/campaign-qa/evidence.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"))
	session.store.progress = progress_before
	session.store.write(PuzzleStore.PROGRESS, progress_before)
	print("CAPTURED ", evidence.size(), " campaign/editor screens")
	game.queue_free()
	await process_frame
	quit()

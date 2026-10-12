extends SceneTree

var game: Node
var evidence: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.gui_embed_subwindows=true
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	for resolution in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]:
		root.size=resolution
		game.show_main_menu()
		await capture("menu",resolution)
		for moment in [9.0,27.0]:
			game.get_node("Interface/Root/MainMenu/Showcase").animation.seek(moment,true)
			game.get_node("Interface/Root/MainMenu/Showcase").sandbox.camera._update(1)
			await capture("menu-%d" % moment,resolution)
		game.new_track()
		await capture("empty-sandbox",resolution)
		game.qa_example("first-roll")
		game.sandbox.build.select(game.sandbox.build.pieces[0])
		await capture("inspector",resolution)
		game.sandbox.build.select_connected(game.sandbox.build.pieces[0])
		await capture("multiselection",resolution)
		game.sandbox.build.move_selected()
		game.sandbox.build.proposed.origin+=Vector3(0,0,3)
		game.sandbox.build.valid=true
		game.sandbox.build.set_process(false)
		game.sandbox.build.apply_preview()
		await capture("group-drag",resolution)
		game.sandbox.build.cancel()
		game.sandbox.build.set_process(true)
		game.sandbox.build.choose(game.catalog.get_piece("curve"))
		Input.warp_mouse(Vector2(resolution.x*0.6,resolution.y*0.6))
		var motion=InputEventMouseMotion.new()
		motion.position=Vector2(resolution.x*0.6,resolution.y*0.6)
		motion.global_position=motion.position
		root.push_input(motion,true)
		await capture("placement",resolution)
		game.sandbox.build.cancel()
		game.qa_example("spiral-crossing")
		await capture("substantial-construction",resolution)
		game.sandbox.build.select_connected(game.sandbox.build.pieces[0])
		var anchor=game.sandbox.build.selection[0]
		game.sandbox.build.select(anchor)
		game.sandbox.build.refresh_connectors()
		for target in game.sandbox.build.targets:
			if target.piece==anchor:
				game.sandbox.build.choose_extension(game.catalog.get_piece("straight"),target)
				break
		# Position outside UI while retaining the explicitly chosen elevated target.
		motion=InputEventMouseMotion.new()
		motion.position=Vector2(resolution.x*0.63,resolution.y*0.48)
		root.push_input(motion,true)
		await capture("elevated-snap",resolution)
		game.sandbox.build.cancel()
		game.sandbox.build.select_connected(game.sandbox.build.pieces[2])
		game.sandbox.build.move_selected(true)
		await capture("group-placement",resolution)
		game.sandbox.build.cancel()
		var pair: Array[TrackPiece]=[game.sandbox.build.pieces[2],game.sandbox.build.pieces[3]]
		game.sandbox.build.set_selection(pair)
		game.sandbox.build.move_selected()
		for target in game.sandbox.build.targets:
			if target.piece==game.sandbox.build.pieces[0]:
				game.sandbox.build.forced_target=target
				break
		await capture("group-snap",resolution)
		game.sandbox.build.cancel()
		game.qa_test()
		game.sandbox.simulation.toggle_pause()
		await capture("simulation",resolution)
		game.sandbox.simulation.reset()
		game.handle_action("load")
		await capture("track-browser",resolution)
		game.get_node("Interface/Root/TrackBrowser").close()
		game.handle_action("save_as")
		await capture("save-dialog",resolution)
		game.name_dialog.close()
		game.handle_action("settings")
		await capture("settings",resolution)
		game.settings_dialog.get_node("Surface/Contents/Tabs").current_tab=1
		await capture("settings-build",resolution)
		game.settings_dialog.get_node("Surface/Contents/Tabs").current_tab=2
		await capture("settings-camera",resolution)
		game.get_node("Interface/Root/SettingsDialog").close()
	var output=FileAccess.open("res://docs/qa/layout_evidence.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(evidence,"\t"))
	print("VISUAL QA: captured ",evidence.size()," screens at native viewport sizes")
	quit()

func capture(state: String,resolution: Vector2i) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var image=root.get_texture().get_image()
	var path="res://docs/qa/"+state+"-%dx%d.png" % [resolution.x,resolution.y]
	image.save_png(path)
	var findings: Array = []
	inspect_controls(game,findings)
	evidence.append({"state":state,"requested":[resolution.x,resolution.y],"actual":[image.get_width(),image.get_height()],"findings":findings,"path":path})
	print(state," ",image.get_width(),"x",image.get_height()," / ",findings.size()," layout findings")

func inspect_controls(node: Node,findings: Array) -> void:
	if node is Control and node.is_visible_in_tree() and node is Button:
		if node.size.x+0.5<node.get_combined_minimum_size().x or node.size.y+0.5<node.get_combined_minimum_size().y:
			findings.append({"path":str(node.get_path()),"rule":"button_below_minimum_size"})
	if node is PanelContainer and node.is_visible_in_tree() and node.get_window()==root:
		var rect=node.get_global_rect()
		if rect.position.y < -0.5 or rect.end.y > root.size.y+0.5 or rect.position.x < -0.5 or rect.end.x > root.size.x+0.5:
			findings.append({"path":str(node.get_path()),"rule":"panel_outside_viewport"})
	for child in node.get_children(): inspect_controls(child,findings)

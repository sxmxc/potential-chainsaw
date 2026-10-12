extends SceneTree

var game: Node
var evidence: Array=[]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.enter_sandbox()
	var build: BuildManager=game.sandbox.build
	var families=["support-single","support-two","support-four","support-color-single","support-color-two","support-color-four"]
	for index in families.size():
		build.spawn(game.catalog.get_piece(families[index]),Transform3D(Basis.IDENTITY,Vector3((index%3)*2,0,floori(index/3.0)*3)),"",{"support_height":2.0+index*0.5,"support_double_top":index%2==1})
	var toolbox=game.get_node("Interface/Root/HUD/Margin/Layout/Body/Toolbox")
	toolbox.get_node("%Category").select(game.catalog.categories().find("Supports"))
	toolbox.refresh()
	game.sandbox.camera.target_focus=Vector3(2,2,1.5)
	game.sandbox.camera.target_distance=18
	game.sandbox.camera.target_pitch=0.4
	for resolution in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]:
		root.size=resolution
		DisplayServer.window_set_size(resolution)
		build.select(build.pieces[2])
		for frame in 35: await process_frame
		await capture("support-families",resolution)
		build.configure_selected({"support_height":4.125,"support_double_top":true},"Support settings")
		await capture("support-double-top",resolution)
	var file=FileAccess.open("res://docs/qa/support-visual-evidence.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"\t"))
	print("Support visual captures: ",evidence.size())
	quit()

func capture(label: String, resolution: Vector2i) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var frame_image=root.get_texture().get_image()
	var path="res://docs/qa/%s-%dx%d.png" % [label,resolution.x,resolution.y]
	frame_image.save_png(path)
	var inspector=game.get_node("Interface/Root/HUD/Margin/Layout/Body/Inspector") as Control
	var rect=inspector.get_global_rect()
	evidence.append({"path":path,"actual":[frame_image.get_width(),frame_image.get_height()],"requested":[resolution.x,resolution.y],"inspector_fits":rect.position.y>=0 and rect.end.y<=root.size.y and rect.end.x<=root.size.x,"hud_fits":hud_fits()})

func hud_fits() -> bool:
	for path in ["Margin/Layout/Top","Margin/Layout/Body/Toolbox","Margin/Layout/Bottom"]:
		var panel=game.get_node("Interface/Root/HUD/"+path) as Control
		var rect=panel.get_global_rect()
		if rect.position.y<0 or rect.end.y>root.size.y or rect.end.x>root.size.x: return false
	return true

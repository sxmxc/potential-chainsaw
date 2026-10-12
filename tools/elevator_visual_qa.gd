extends SceneTree

const Capture = preload("res://scripts/mechanisms/marble_capture.gd")
var game: Node
var evidence: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.qa_example("bucket-elevator-demo")
	var build: BuildManager=game.sandbox.build
	var lift=build.pieces[0]
	build.select(lift)
	game.sandbox.camera.target_focus=Vector3(0,2.7,0)
	game.sandbox.camera.target_distance=13
	game.sandbox.camera.target_yaw=0.6
	game.sandbox.camera.target_pitch=0.36
	for resolution in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]:
		root.size=resolution
		DisplayServer.window_set_size(resolution)
		for frame in 30: await process_frame
		await capture("elevator-build-%dx%d" % [resolution.x,resolution.y])
	root.size=Vector2i(1280,720)
	DisplayServer.window_set_size(root.size)
	game.sandbox.simulation.start()
	var stages: Dictionary={}
	for frame in 2400:
		await physics_frame
		var sim=game.sandbox.simulation
		if Capture.is_carried(sim.marble):
			var stage=""
			if sim.marble.position.y>4.7 and not stages.has("tipping"): stage="tipping"
			elif sim.marble.position.y>2.5 and not stages.has("ascent"): stage="ascent"
			elif not stages.has("loading"): stage="loading"
			if not stage.is_empty():
				stages[stage]=true
				sim.toggle_pause()
				await capture("elevator-"+stage)
				sim.toggle_pause()
		elif lift.elevator_component.unloaded_count>0 and not stages.has("discharge"):
			stages.discharge=true
			sim.toggle_pause()
			await capture("elevator-discharge")
			sim.toggle_pause()
		if sim.state==SimulationManager.State.SUCCESS:
			await capture("elevator-finish")
			break
	game.sandbox.simulation.reset()
	game.new_track()
	game.enter_sandbox()
	build=game.sandbox.build
	lift=build.spawn(game.catalog.get_piece("bucket-elevator"),Transform3D.IDENTITY,"",{"elevator_height":12.0})
	build.select(lift)
	game.sandbox.camera.target_focus=Vector3(0,6.5,0)
	game.sandbox.camera.target_distance=24
	for frame in 50: await process_frame
	await capture("elevator-maximum-height")
	await thumbnail()
	var file=FileAccess.open("res://docs/qa/elevator-visual-evidence.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"\t"))
	print("Elevator visual captures: ",evidence.size(),"; stages: ",stages)
	quit()

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var frame_image=root.get_texture().get_image()
	var path="res://docs/qa/"+label+".png"
	frame_image.save_png(path)
	evidence.append({"path":path,"size":[frame_image.get_width(),frame_image.get_height()]})

func thumbnail() -> void:
	var viewport=SubViewport.new()
	viewport.size=Vector2i(180,120)
	viewport.transparent_bg=true
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var model=load("res://scenes/mechanisms/bucket_elevator.tscn").instantiate()
	viewport.add_child(model)
	var camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=7.3
	viewport.add_child(camera)
	camera.position=Vector3(8,7,-10)
	camera.look_at(Vector3(0,2.7,0.2))
	camera.current=true
	var environment=WorldEnvironment.new()
	var settings=Environment.new()
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color.WHITE
	settings.ambient_light_energy=0.8
	environment.environment=settings
	viewport.add_child(environment)
	var light=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-45,-30,0)
	viewport.add_child(light)
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://resources/thumbnails/bucket-elevator.png")

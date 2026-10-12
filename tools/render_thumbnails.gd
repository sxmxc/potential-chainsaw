extends SceneTree

var viewport: SubViewport
var holder: Node3D
var camera: Camera3D

func _initialize() -> void:
	call_deferred("render_all")

func render_all() -> void:
	DirAccess.make_dir_recursive_absolute("res://resources/thumbnails")
	viewport=SubViewport.new()
	viewport.size=Vector2i(180,120)
	viewport.transparent_bg=true
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	holder=Node3D.new()
	viewport.add_child(holder)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	camera.current=true
	var environment=WorldEnvironment.new()
	var settings=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color.WHITE
	settings.ambient_light_energy=0.65
	environment.environment=settings
	viewport.add_child(environment)
	var light=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-45,-30,0)
	light.light_energy=1.3
	viewport.add_child(light)
	var catalog=PieceCatalog.new()
	var rendered = 0
	for def in catalog.pieces:
		if "--mechanisms" in OS.get_cmdline_user_args() and def.behavior not in ["gate", "diverter", "launcher", "sensor"]: continue
		if def.behavior in ["start","finish"]: continue
		var model: Node3D
		if "--mechanisms" in OS.get_cmdline_user_args(): model = load("res://scenes/track_piece.tscn").instantiate()
		else: model = def.model.instantiate()
		holder.add_child(model)
		if "--mechanisms" in OS.get_cmdline_user_args(): model.setup(def)
		var center=def.bounds.get_center()
		camera.position=center+Vector3(1.2,1.4,1.8)*maxf(1,def.bounds.size.length())
		camera.look_at(center)
		camera.size=maxf(0.7,def.bounds.size.length()*0.85)
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://resources/thumbnails/"+String(def.id)+".png")
		rendered += 1
		holder.remove_child(model)
		model.queue_free()
	print("Rendered ",rendered," thumbnails")
	quit()

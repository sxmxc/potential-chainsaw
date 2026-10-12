extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var sandbox=load("res://scenes/world.tscn").instantiate()
	root.add_child(sandbox)
	sandbox.configure(PieceCatalog.new())
	var build: BuildManager=sandbox.build
	build.enabled=true
	for x in 10:
		for z in 10: build.spawn(build.catalog.get_piece("straight"),Transform3D(Basis.IDENTITY,Vector3(x*1.5-7.5,1,z*1.5-7.5)))
	build.select_all()
	build.spawn(build.catalog.get_piece("straight"),Transform3D(Basis.IDENTITY,Vector3(20,4,0)))
	build.move_selected()
	build.camera.target_focus=Vector3(20,4,0)
	build.camera.target_distance=12
	build.camera._update(1)
	await physics_frame
	var target=build.targets[0]
	var cursor=build.camera.unproject_position(target.point)
	var times: Array[float] = []
	var candidate_count=0
	for i in 20:
		var start=Time.get_ticks_usec()
		var candidates=build.snap.screen_candidates(build.preview_items,build.preview_ports,build.targets,build.camera,cursor,build.pieces,build.moving_group)
		times.append((Time.get_ticks_usec()-start)/1000.0)
		candidate_count=candidates.size()
		await process_frame
	times.sort()
	var median_index = floori(times.size() / 2.0)
	var result={"group_pieces":100,"boundary_ports":build.preview_ports.size(),"external_targets":build.targets.size(),"validated_candidates":candidate_count,"samples":times.size(),"median_ms":times[median_index],"max_ms":times.back(),"renderer":"headless","note":"CPU solver sample; not a whole-game GPU frame-rate claim"}
	print(JSON.stringify(result))
	quit()

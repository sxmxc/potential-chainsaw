extends SceneTree

const Geometry = preload("res://scripts/mechanisms/elevator_geometry.gd")
const Capture = preload("res://scripts/mechanisms/marble_capture.gd")
var checks: int = 0
var failures: Array[String] = []
var game: Node

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)

func run() -> void:
	root.size = Vector2i(1280,720)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.enter_sandbox()
	var build: BuildManager = game.sandbox.build
	var definition = game.catalog.get_piece("bucket-elevator")
	check(definition != null and definition.category=="Mechanisms", "Elevator is registered in the existing catalog")
	var lift = build.spawn(definition, Transform3D.IDENTITY)
	check(lift.elevator_component.buckets.size()>=6, "One placed assembly has multiple reusable buckets")
	check(lift.bodies.size()>0 and lift.definition.reserve_bounds, "Frame/guide collision and complete mechanism volume are present")
	var first_definition = lift.definition
	build.select(lift)
	check(build.configure_selected({"elevator_height":6.0,"elevator_speed":1.2},"Elevator rise"), "Height is editable through the common build history")
	check(lift.position==Vector3.ZERO and lift.definition.connectors[1].position.y==6.25, "Height change anchors the inlet and updates the exact outlet")
	check(definition.connectors[1].position.y==4.25 and first_definition.connectors[1].position.y==4.25, "Instance resizing never changes shared catalog connector resources")
	check(is_equal_approx(lift.definition.bounds.end.y,8.1) and lift.elevator_component.buckets.size()>6, "Height updates bounds, frames and bucket count")
	build.undo()
	lift=build.pieces[0]
	check(lift.configuration.elevator_height==4.0 and lift.definition.connectors[1].position.y==4.25, "Undo restores configured geometry and output")
	build.redo()
	lift=build.pieces[0]
	check(lift.configuration.elevator_height==6.0, "Redo restores the elevator setting atomically")
	build.select(lift)
	var obstruction=build.spawn(game.catalog.get_piece("straight"),Transform3D(Basis.IDENTITY,Vector3(0,9,0.75)))
	check(not build.configure_selected({"elevator_height":10.0},"Elevator rise") and lift.configuration.elevator_height==6.0, "An obstructed height change rolls back configuration and geometry")
	build.pieces.erase(obstruction); obstruction.queue_free()
	check(not build.snap.validate(game.catalog.get_piece("straight"),Transform3D(Basis.IDENTITY,Vector3(0,3,0.75)),build.pieces).is_empty(), "Tracks cannot be placed inside the full swept assembly volume")
	var snapshot=build.snapshot()
	var saved=game.serializer.save_track("Elevator QA",snapshot)
	var decoded=game.serializer.load_track(saved)
	build.restore(decoded.pieces)
	lift=build.pieces[0]
	check(lift.configuration.elevator_height==6.0 and lift.configuration.elevator_speed==1.2 and lift.definition.connectors[1].position.y==6.25, "Existing save/load recreates settings and effective connector geometry")
	game.serializer.delete_track(saved)
	build.select(lift); build.move_selected(true)
	check(build.ghost.configuration.elevator_height==6.0 and build.ghost.definition.connectors[1].position.y==6.25, "Duplicate preview preserves configured height")
	check(build.ghost.elevator_component.preview_only and not build.ghost.elevator_component.active, "Ghost is stationary and cannot capture or collide")
	build.cancel()
	check(build.pieces.size()==1, "Cancel leaves no duplicate mechanism")
	check(lift.model_node.get_node("Loading/Approach/Straight").scene_file_path.ends_with("straight.glb") and lift.model_node.get_node("Output/Track/Straight").scene_file_path.ends_with("straight.glb"), "Loading and Output use the actual kit straight model")
	build.camera.set_process(false)
	var tray: Node3D=lift.elevator_component.buckets[0].get_node("Tray")
	build.camera.global_position=tray.global_position+Vector3(0,0.25,-3)
	build.camera.look_at(tray.global_position+Vector3(0,0.25,0))
	await physics_frame
	await physics_frame
	check(build.pick_piece(build.camera.unproject_position(tray.global_position+Vector3(0,0.25,0)))==lift,"Clicking a visible bucket selects the whole elevator through its pick-only shape")
	var pick_body=tray.get_node("SelectionBody") as StaticBody3D
	check(pick_body.collision_layer==4 and pick_body.collision_mask==0,"Bucket picking shapes are isolated from the marble's track collision layer")
	build.camera.global_position=Vector3(7,9,-10)
	var upper_point: Vector3=lift.transform*lift.definition.connectors[1].position
	build.camera.look_at(upper_point)
	await physics_frame
	await physics_frame
	var upper_target: Dictionary={}
	for target in build.snap.exposed(build.pieces):
		if (target.point as Vector3).distance_to(upper_point)<0.001: upper_target=target
	var incoming: Array[Dictionary]=[{"definition":game.catalog.get_piece("straight"),"local":Transform3D.IDENTITY}]
	var candidates=build.snap.screen_candidates(incoming,build.snap.boundary_sources(incoming),[upper_target],build.camera,build.camera.unproject_position(upper_point),build.pieces,[])
	check(not candidates.is_empty() and candidates[0].error.is_empty() and is_equal_approx(candidates[0].transform.origin.y,6.0),"Screen targeting attaches an exit track to the configured upper elevation automatically")
	build.camera.set_process(true)
	var normalized=Geometry.normalized({"elevator_height":999,"elevator_speed":-1})
	check(normalized.elevator_height==12.0 and normalized.elevator_speed==0.25, "Configuration limits are enforced")
	await test_route(2.0, 0.8, 0)
	await test_route(4.0, 2.0, 1)
	await test_route(12.0, 2.0, 2)
	await test_multiple()
	print("ELEVATOR RESULT: %d checks; %d failures" % [checks,failures.size()])
	var file=FileAccess.open("res://docs/elevator_test_results.txt",FileAccess.WRITE)
	file.store_string("%d checks; %d failures\n%s" % [checks,failures.size(),"\n".join(failures)])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func test_route(lift_height: float, conveyor_speed: float, quarter: int) -> void:
	game.new_track()
	game.enter_sandbox()
	var build: BuildManager=game.sandbox.build
	var rotation_basis=Basis(Vector3.UP,quarter*PI/2)
	var lift=build.spawn(game.catalog.get_piece("bucket-elevator"),Transform3D(rotation_basis,Vector3.ZERO),"",{"elevator_height":lift_height,"elevator_speed":conveyor_speed})
	build.spawn(game.catalog.get_piece("sandbox-start"),Transform3D(rotation_basis*Basis(Vector3.UP,PI),rotation_basis*Vector3(0,0,-2)))
	build.spawn(game.catalog.get_piece("straight"),Transform3D(rotation_basis,rotation_basis*Vector3(0,lift_height,-2)))
	build.spawn(game.catalog.get_piece("sandbox-finish"),Transform3D(rotation_basis*Basis(Vector3.UP,PI),rotation_basis*Vector3(0,lift_height,-3)))
	var sim: SimulationManager=game.sandbox.simulation
	check(sim.start(), "Connected elevator route starts at height %.1f, rotation %d" % [lift_height,quarter])
	var component=lift.elevator_component
	var saw_capture=false
	var max_rise=0.0
	var previous_position=sim.marble.position
	var biggest_step=0.0
	var paused=false
	for frame in 2400:
		await physics_frame
		if Capture.is_carried(sim.marble):
			saw_capture=true
			biggest_step=maxf(biggest_step,sim.marble.position.distance_to(previous_position))
			max_rise=maxf(max_rise,sim.marble.position.y)
			if not paused:
				paused=true
				var pose=sim.marble.global_transform
				var phase=component.phase
				sim.toggle_pause()
				for tick in 12: await physics_frame
				check(sim.marble.freeze and sim.marble.global_transform.is_equal_approx(pose) and component.phase==phase,"Pause holds captured marble and all buckets")
				sim.toggle_pause()
				check(sim.marble.freeze,"Resume keeps controlled transport frozen until discharge")
		previous_position=sim.marble.position
		if sim.state in [SimulationManager.State.SUCCESS,SimulationManager.State.FAILED]: break
	print("Elevator route H=",lift_height," q=",quarter," state=",sim.state," captures=",component.loaded_count," exits=",component.unloaded_count," marble=",sim.marble.position)
	check(saw_capture and max_rise>lift_height,"Real incoming marble visibly rides upward")
	check(biggest_step<0.08,"Capture/ascent has no frame teleport")
	check(component.loaded_count==1 and component.unloaded_count==1,"One bucket carries and releases each marble once")
	check(sim.state==SimulationManager.State.SUCCESS,"Released marble physically rolls into the connected finish")
	check(not sim.marble.freeze and sim.marble.collision_layer==2 and sim.marble.collision_mask==1 and not Capture.is_carried(sim.marble),"Discharge restores ordinary rigid-body collision and physics")
	sim.reset()
	check(component.phase==0 and not component.active and component.waiting.is_empty(),"Reset restores stationary arrangement and clears waiting state")
	check(sim.start(),"Repeated run starts without stale occupancy")
	for frame in 500:
		await physics_frame
		if Capture.is_carried(sim.marble): break
	var captured=sim.marble
	check(Capture.is_carried(captured),"Repeated run can capture again")
	component.reset()
	check(not captured.freeze and captured.collision_layer==2 and captured.collision_mask==1 and not Capture.is_carried(captured),"Reset while occupied restores marble properties before disposal")
	sim.reset()

func test_multiple() -> void:
	game.new_track()
	game.enter_sandbox()
	var build: BuildManager=game.sandbox.build
	var lift=build.spawn(game.catalog.get_piece("bucket-elevator"),Transform3D.IDENTITY)
	var component=lift.elevator_component
	build.spawn(game.catalog.get_piece("straight"),Transform3D(Basis.IDENTITY,Vector3(0,4,-2)))
	build.spawn(game.catalog.get_piece("sandbox-finish"),Transform3D(Basis(Vector3.UP,PI),Vector3(0,4,-3)))
	var marbles: Array[RigidBody3D]=[]
	var delivered: Array[int]=[]
	var claimed: Array[int]=[]
	component.marble_loaded.connect(func(body):claimed.append(body.get_instance_id()))
	component.marble_unloaded.connect(func(body):delivered.append(body.get_instance_id()))
	component.active=true
	for frame in 2200:
		if frame in [0,60,120]:
			var body=load("res://scenes/marble.tscn").instantiate() as RigidBody3D
			game.sandbox.add_child(body)
			body.position=Vector3(0,0.46,-1.25)
			body.linear_velocity=Vector3(0,0,1.2)
			marbles.append(body)
		await physics_frame
		if delivered.size()==3: break
	check(component.loaded_count==3 and component.unloaded_count==3,"Three closely spaced real arrivals queue and use successive buckets")
	var unique: Dictionary={}
	for id in claimed: unique[id]=true
	check(unique.size()==3 and claimed.size()==3 and delivered.size()==3,"Bucket ownership prevents duplicate capture and double occupancy")
	for body in marbles:
		check(not body.freeze and body.collision_layer==2 and body.collision_mask==1 and not Capture.is_carried(body),"Every discharged marble regains ordinary physics")
	var phase=component.phase
	for frame in 120: await physics_frame
	check(component.phase!=phase and component.active,"Empty conveyor continues circulating for subsequent arrivals")
	component.reset()
	for body in marbles: body.queue_free()

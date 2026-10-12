extends "res://tests/support/scene_test.gd"

const Geometry = preload("res://scripts/mechanisms/elevator_geometry.gd")
const Capture = preload("res://scripts/mechanisms/marble_capture.gd")
var game: Node

func test_bucket_elevator() -> void:
	get_tree().root.size = Vector2i(1280,720)
	game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	await get_tree().process_frame
	game.enter_sandbox()
	var build: BuildManager = game.sandbox.build
	var definition = game.catalog.get_piece("bucket-elevator")
	assert_true(definition != null and definition.category=="Mechanisms", "Elevator is registered in the existing catalog")
	var lift = build.spawn(definition, Transform3D.IDENTITY)
	assert_true(lift.elevator_component.buckets.size()>=6, "One placed assembly has multiple reusable buckets")
	assert_true(lift.bodies.size()>0 and lift.definition.reserve_bounds, "Frame/guide collision and complete mechanism volume are present")
	var first_definition = lift.definition
	build.select(lift)
	assert_true(build.configure_selected({"elevator_height":6.0,"elevator_speed":1.2},"Elevator rise"), "Height is editable through the common build history")
	assert_true(lift.position==Vector3.ZERO and lift.definition.connectors[1].position.y==6.25, "Height change anchors the inlet and updates the exact outlet")
	assert_true(definition.connectors[1].position.y==4.25 and first_definition.connectors[1].position.y==4.25, "Instance resizing never changes shared catalog connector resources")
	assert_true(is_equal_approx(lift.definition.bounds.end.y,8.1) and lift.elevator_component.buckets.size()>6, "Height updates bounds, frames and bucket count")
	build.undo()
	lift=build.pieces[0]
	assert_true(lift.configuration.elevator_height==4.0 and lift.definition.connectors[1].position.y==4.25, "Undo restores configured geometry and output")
	build.redo()
	lift=build.pieces[0]
	assert_true(lift.configuration.elevator_height==6.0, "Redo restores the elevator setting atomically")
	build.select(lift)
	var obstruction=build.spawn(game.catalog.get_piece("straight"),Transform3D(Basis.IDENTITY,Vector3(0,9,0.75)))
	assert_true(not build.configure_selected({"elevator_height":10.0},"Elevator rise") and lift.configuration.elevator_height==6.0, "An obstructed height change rolls back configuration and geometry")
	build.pieces.erase(obstruction); obstruction.queue_free()
	assert_true(not build.snap.validate(game.catalog.get_piece("straight"),Transform3D(Basis.IDENTITY,Vector3(0,3,0.75)),build.pieces).is_empty(), "Tracks cannot be placed inside the full swept assembly volume")
	var snapshot=build.snapshot()
	var saved=game.serializer.save_track("Elevator QA",snapshot)
	var decoded=game.serializer.load_track(saved)
	build.restore(decoded.pieces)
	lift=build.pieces[0]
	assert_true(lift.configuration.elevator_height==6.0 and lift.configuration.elevator_speed==1.2 and lift.definition.connectors[1].position.y==6.25, "Existing save/load recreates settings and effective connector geometry")
	game.serializer.delete_track(saved)
	build.select(lift); build.move_selected(true)
	assert_true(build.ghost.configuration.elevator_height==6.0 and build.ghost.definition.connectors[1].position.y==6.25, "Duplicate preview preserves configured height")
	assert_true(build.ghost.elevator_component.preview_only and not build.ghost.elevator_component.active, "Ghost is stationary and cannot capture or collide")
	build.cancel()
	assert_true(build.pieces.size()==1, "Cancel leaves no duplicate mechanism")
	assert_true(lift.model_node.get_node("Loading/Approach/Straight").scene_file_path.ends_with("straight.glb") and lift.model_node.get_node("Output/Track/Straight").scene_file_path.ends_with("straight.glb"), "Loading and Output use the actual kit straight model")
	build.camera.set_process(false)
	var tray: Node3D=lift.elevator_component.buckets[0].get_node("Tray")
	build.camera.global_position=tray.global_position+Vector3(0,0.25,-3)
	build.camera.look_at(tray.global_position+Vector3(0,0.25,0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(build.pick_piece(build.camera.unproject_position(tray.global_position+Vector3(0,0.25,0)))==lift,"Clicking a visible bucket selects the whole elevator through its pick-only shape")
	var pick_body=tray.get_node("SelectionBody") as StaticBody3D
	assert_true(pick_body.collision_layer==4 and pick_body.collision_mask==0,"Bucket picking shapes are isolated from the marble's track collision layer")
	build.camera.global_position=Vector3(7,9,-10)
	var upper_point: Vector3=lift.transform*lift.definition.connectors[1].position
	build.camera.look_at(upper_point)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var upper_target: Dictionary={}
	for target in build.snap.exposed(build.pieces):
		if (target.point as Vector3).distance_to(upper_point)<0.001: upper_target=target
	var incoming: Array[Dictionary]=[{"definition":game.catalog.get_piece("straight"),"local":Transform3D.IDENTITY}]
	var candidates=build.snap.screen_candidates(incoming,build.snap.boundary_sources(incoming),[upper_target],build.camera,build.camera.unproject_position(upper_point),build.pieces,[])
	assert_true(not candidates.is_empty() and candidates[0].error.is_empty() and is_equal_approx(candidates[0].transform.origin.y,6.0),"Screen targeting attaches an exit track to the configured upper elevation automatically")
	build.camera.set_process(true)
	var normalized=Geometry.normalized({"elevator_height":999,"elevator_speed":-1})
	assert_true(normalized.elevator_height==12.0 and normalized.elevator_speed==0.25, "Configuration limits are enforced")
	await exercise_route(2.0, 0.8, 0)
	await exercise_route(2.0, 0.25, 3)
	await exercise_route(4.0, 2.0, 1)
	await exercise_route(12.0, 2.0, 2)
	await exercise_multiple()
	game.queue_free()
	await get_tree().process_frame

func exercise_route(lift_height: float, conveyor_speed: float, quarter: int) -> void:
	game.new_track()
	game.enter_sandbox()
	var build: BuildManager=game.sandbox.build
	var rotation_basis=Basis(Vector3.UP,quarter*PI/2)
	var lift=build.spawn(game.catalog.get_piece("bucket-elevator"),Transform3D(rotation_basis,Vector3.ZERO),"",{"elevator_height":lift_height,"elevator_speed":conveyor_speed})
	build.spawn(game.catalog.get_piece("sandbox-start"),Transform3D(rotation_basis*Basis(Vector3.UP,PI),rotation_basis*Vector3(0,0,-2)))
	build.spawn(game.catalog.get_piece("straight"),Transform3D(rotation_basis,rotation_basis*Vector3(0,lift_height,-2)))
	build.spawn(game.catalog.get_piece("sandbox-finish"),Transform3D(rotation_basis*Basis(Vector3.UP,PI),rotation_basis*Vector3(0,lift_height,-3)))
	var sim: SimulationManager=game.sandbox.simulation
	assert_true(sim.start(), "Connected elevator route starts at height %.1f, rotation %d" % [lift_height,quarter])
	var component=lift.elevator_component
	var discharge: Dictionary = {"age": -1.0, "speed": 0.0, "checked": false}
	component.marble_unloaded.connect(func(body: RigidBody3D):
		discharge.age = 0.0
		discharge.speed = body.linear_velocity.length()
		assert_true(body.angular_velocity.is_equal_approx(rotation_basis.y.cross(body.linear_velocity) / 0.2), "Discharge spin matches outlet rolling direction after rotation"))
	var saw_capture=false
	var max_rise=0.0
	var previous_position=sim.marble.position
	var biggest_step=0.0
	var pause_tested=false
	for frame in 2400:
		await get_tree().physics_frame
		if discharge.age >= 0.0 and not discharge.checked:
			discharge.age += 1.0 / 120.0
			if discharge.age >= 0.5:
				discharge.checked = true
				var forward_speed: float = sim.marble.linear_velocity.dot(rotation_basis * Vector3.FORWARD)
				assert_true(forward_speed > discharge.speed * 0.85, "Landing on the outlet retains forward momentum")
		if Capture.is_carried(sim.marble):
			saw_capture=true
			biggest_step=maxf(biggest_step,sim.marble.position.distance_to(previous_position))
			max_rise=maxf(max_rise,sim.marble.position.y)
			if not pause_tested:
				pause_tested=true
				var pose=sim.marble.global_transform
				var phase=component.phase
				sim.toggle_pause()
				for tick in 12: await get_tree().physics_frame
				assert_true(sim.marble.freeze and sim.marble.global_transform.is_equal_approx(pose) and component.phase==phase,"Pause holds captured marble and all buckets")
				sim.toggle_pause()
				assert_true(sim.marble.freeze,"Resume keeps controlled transport frozen until discharge")
		previous_position=sim.marble.position
		if sim.state in [SimulationManager.State.SUCCESS,SimulationManager.State.FAILED]: break
	print("Elevator route H=",lift_height," q=",quarter," state=",sim.state," captures=",component.loaded_count," exits=",component.unloaded_count," marble=",sim.marble.position)
	assert_true(saw_capture and max_rise>lift_height,"Real incoming marble visibly rides upward")
	assert_true(biggest_step<0.08,"Capture/ascent has no frame teleport")
	assert_true(component.loaded_count==1 and component.unloaded_count==1,"One bucket carries and releases each marble once")
	assert_true(sim.state==SimulationManager.State.SUCCESS,"Released marble physically rolls into the connected finish")
	assert_true(not sim.marble.freeze and sim.marble.collision_layer==2 and sim.marble.collision_mask==1 and not Capture.is_carried(sim.marble),"Discharge restores ordinary rigid-body collision and physics")
	sim.reset()
	assert_true(component.phase==0 and not component.active and component.waiting.is_empty(),"Reset restores stationary arrangement and clears waiting state")
	assert_true(sim.start(),"Repeated run starts without stale occupancy")
	for frame in 500:
		await get_tree().physics_frame
		if Capture.is_carried(sim.marble): break
	var captured=sim.marble
	assert_true(Capture.is_carried(captured),"Repeated run can capture again")
	component.reset()
	assert_true(not captured.freeze and captured.collision_layer==2 and captured.collision_mask==1 and not Capture.is_carried(captured),"Reset while occupied restores marble properties before disposal")
	sim.reset()

func exercise_multiple() -> void:
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
		await get_tree().physics_frame
		if delivered.size()==3: break
	assert_true(component.loaded_count==3 and component.unloaded_count==3,"Three closely spaced real arrivals queue and use successive buckets")
	var unique: Dictionary={}
	for id in claimed: unique[id]=true
	assert_true(unique.size()==3 and claimed.size()==3 and delivered.size()==3,"Bucket ownership prevents duplicate capture and double occupancy")
	for body in marbles:
		assert_true(not body.freeze and body.collision_layer==2 and body.collision_mask==1 and not Capture.is_carried(body),"Every discharged marble regains ordinary physics")
	var phase=component.phase
	for frame in 120: await get_tree().physics_frame
	assert_true(component.phase!=phase and component.active,"Empty conveyor continues circulating for subsequent arrivals")
	component.reset()
	for body in marbles: body.queue_free()

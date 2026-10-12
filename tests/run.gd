extends SceneTree

var failures: Array[String] = []
var checks: int = 0
var game: Node
var catalog: PieceCatalog
var snap: SnapManager

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures.append(message)
		push_error("FAIL: "+message)

func run() -> void:
	root.size = Vector2i(1280, 720)
	catalog=PieceCatalog.new()
	snap=SnapManager.new()
	check(catalog.pieces.size()==165,"Imported models, start/finish, elevator and six support assemblies are cataloged")
	for v in [Vector3.ZERO,Vector3(-3,1.125,2.5),Vector3(12.5,4,-8)]:
		check(snap.grid_to_world(snap.world_to_grid(v)).is_equal_approx(v),"Grid round trip "+str(v))
	check(snap.grid_position(Vector3(-0.76,0.2,-0.26)).is_equal_approx(Vector3(-1,0.25,-0.5)),"Negative grid rounding")
	var straight=catalog.get_piece("straight")
	var wide=catalog.get_piece("straight-wide")
	check(not straight.connectors[0].compatible(wide.connectors[0]),"Different channel profiles reject")
	check(straight.connectors[0].compatible(straight.connectors[1]),"Bidirectional channel compatibility")
	var entry=TrackConnector.new()
	entry.direction="entry"
	var exit=TrackConnector.new()
	exit.direction="exit"
	check(entry.compatible(exit) and not entry.compatible(entry),"Directionality constraints")
	check(snap.solid_overlap(straight,Transform3D.IDENTITY,straight,Transform3D.IDENTITY),"Duplicate placement rejects")
	check(not snap.solid_overlap(straight,Transform3D.IDENTITY,straight,Transform3D(Basis(Vector3.UP,PI/2),Vector3(0,1,0))),"Elevated crossing allowed")
	check(not snap.solid_overlap(straight,Transform3D.IDENTITY,straight,Transform3D(Basis.IDENTITY,Vector3(0,0,1))),"Touching end faces allowed")
	var curve=catalog.get_piece("curve")
	check(curve.bounds.size.is_equal_approx(Vector3(2,0.5,2)),"Multi-cell curve retains measured bounds")
	var slant=catalog.get_piece("slant-a")
	check(abs(slant.connectors[0].position.y-slant.connectors[1].position.y)>0.24,"Slope endpoints have different elevations")
	var serializer=TrackSerializer.new(catalog)
	check(serializer.decode('{"version":99,"name":"bad","pieces":[]}').is_empty(),"Unknown save version fails safely")
	check(serializer.decode('{"version":1,"name":"bad","pieces":[{"piece":"straight","position":[0],"rotation":0}]}').is_empty(),"Malformed transforms reject atomically")
	check(serializer.load_track("../escape").is_empty(),"Save path traversal rejects")
	var unknown=serializer.decode('{"version":1,"name":"migration","pieces":[{"piece":"future-piece","position":[0,0,0],"rotation":0}]}')
	check(not unknown.is_empty() and unknown.pieces.is_empty() and serializer.warnings.size()==1,"Missing catalog entries report and skip")
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var build: BuildManager=game.sandbox.build
	check(ProjectSettings.get_setting("gui/theme/custom")=="res://resources/sandbox_theme.tres","Project-wide native Theme configured")
	var theme=load("res://resources/sandbox_theme.tres") as Theme
	for type in ["PrimaryButton","SecondaryButton","DangerButton","ToolboxButton","ToolbarButton","PanelTitle"]:
		check(not theme.get_type_variation_base(type).is_empty(),"Reusable Theme variation "+type)
	check(not build.enabled,"Main menu locks world editing")
	game.new_track()
	check(build.enabled and build.pieces.is_empty(),"New sandbox ready for construction")
	var before=build.snapshot()
	var placed=build.spawn(straight,Transform3D.IDENTITY)
	build.record(before,"Place")
	build.undo()
	check(build.pieces.is_empty(),"Undo initial placement")
	build.redo()
	check(build.pieces.size()==1,"Redo initial placement")
	placed=build.pieces[0]
	build.select(placed)
	build.move_selected()
	build.proposed=Transform3D(Basis.IDENTITY,Vector3(2,1,0))
	build.ghost.visible=true
	build.valid=true
	build.commit()
	check(build.pieces[0].position.is_equal_approx(Vector3(2,1,0)),"Movement confirms exact preview transform")
	build.undo()
	check(build.pieces[0].position==Vector3.ZERO,"Undo movement")
	build.redo()
	check(build.pieces[0].position.is_equal_approx(Vector3(2,1,0)),"Redo movement")
	build.select(build.pieces[0])
	build.rotate_piece()
	check(abs(build.pieces[0].basis.z.x)>0.99,"Quarter-turn rotation")
	build.undo()
	check(abs(build.pieces[0].basis.z.z)>0.99,"Undo rotation restores basis")
	build.select(build.pieces[0])
	build.move_selected()
	build.cancel()
	check(build.pieces.size()==1 and build.pieces[0].visible,"Cancelled movement preserves original")
	build.select(build.pieces[0])
	build.delete_selected()
	check(build.pieces.is_empty(),"Deletion")
	build.undo()
	check(build.pieces.size()==1,"Undo deletion")
	var data=build.snapshot()
	var saved=serializer.save_track("Automated round trip",data,"qa-roundtrip")
	check(not saved.is_empty(),"Persistent JSON write")
	var loaded=serializer.load_track(saved)
	check(loaded.pieces==data,"Save/load round trip preserves transforms, IDs and configuration")
	serializer.delete_track(saved)
	game.track_name="Workflow save"
	game.track_id="qa-workflow"
	check(game.save_current(),"HUD save action writes current construction")
	game.new_track()
	game.load_track("qa-workflow",false)
	check(build.snapshot()==data and not build.dirty,"Saved track reopens for editing")
	serializer.delete_track("qa-workflow")
	game.handle_action("settings")
	check(not build.enabled and game.settings_dialog.visible,"Saved settings scene opens as a modal")
	game.settings_dialog.close()
	check(build.enabled,"Closing settings restores construction input")
	await load("res://tests/construction_overhaul.gd").new().run(game,check)
	game.new_track()
	var rotor=build.spawn(catalog.get_piece("fan-two"),Transform3D(Basis.IDENTITY,Vector3(10,0,0)))
	await process_frame
	check(rotor.rotor_component!=null,"Imported fan attaches real rotating collision component")
	var rest=rotor.rotor_component.mesh.transform
	rotor.rotor_component.active=true
	for i in 4: await physics_frame
	check(not rotor.rotor_component.mesh.transform.is_equal_approx(rest),"Fan mechanism rotates during physics")
	rotor.rotor_component.reset()
	check(rotor.rotor_component.mesh.transform.is_equal_approx(rest),"Mechanism reset restores original transform")
	for id in ["first-roll","spiral-crossing"]:
		game.qa_example(id)
		var original=build.snapshot()
		for piece in build.pieces:
			check(snap.validate(piece.definition,piece.transform,build.pieces,piece).is_empty(),id+" placement validity "+piece.definition.display_name)
		check_connected_chain(build.pieces,id)
		check(game.qa_test(),id+" starts a real physics simulation")
		check(game.sandbox.simulation.marble is RigidBody3D,id+" uses rigid body marble")
		check(not build.enabled,id+" locks construction during simulation")
		game.sandbox.simulation.toggle_pause()
		check(game.sandbox.simulation.state==SimulationManager.State.PAUSED and game.sandbox.simulation.marble.freeze,"Pause freezes physics")
		game.sandbox.simulation.toggle_pause()
		for frame in range(7200):
			await physics_frame
			if game.sandbox.simulation.state in [SimulationManager.State.SUCCESS,SimulationManager.State.FAILED]: break
		print("Physics example ",id," state ",game.sandbox.simulation.state," time ",game.sandbox.simulation.elapsed," marble ",game.sandbox.simulation.marble.position)
		check(game.sandbox.simulation.state==SimulationManager.State.SUCCESS,id+" marble physically reaches finish")
		game.sandbox.simulation.reset()
		check(build.snapshot()==original,id+" reset preserves original construction")
		check(game.sandbox.simulation.marble==null and build.enabled,"Reset returns build mode and removes marble")
	game.new_track()
	check(not game.qa_test(),"Missing release/finish fails without leaving build mode")
	print("TEST RESULT: ",checks," checks, ",failures.size()," failures")
	var file=FileAccess.open("res://docs/test_results.txt",FileAccess.WRITE)
	file.store_string("%d checks; %d failures\n%s" % [checks,failures.size(),"\n".join(failures)])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func check_connected_chain(pieces: Array[TrackPiece], title: String) -> void:
	for i in range(0,pieces.size()-1):
		var a=pieces[i]
		var b=pieces[i+1]
		if a.definition.connectors.is_empty() or b.definition.connectors.is_empty(): continue
		var connected=false
		for ac in a.definition.connectors:
			for bc in b.definition.connectors:
				if ac.compatible(bc) and (a.transform*ac.position).distance_to(b.transform*bc.position)<0.015 and (a.basis*ac.outward).dot(b.basis*bc.outward)<-0.995: connected=true
		check(connected,title+" transition "+String(a.definition.id)+" → "+String(b.definition.id))

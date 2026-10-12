extends RefCounted

var check: Callable
var game: Node
var build: BuildManager

func run(app: Node, assertion: Callable) -> void:
	game=app
	check=assertion
	build=game.sandbox.build
	game.new_track()
	var straight=build.catalog.get_piece("straight")
	var a=build.spawn(straight,Transform3D(Basis.IDENTITY,Vector3(0,1,0)))
	var b=build.spawn(straight,Transform3D(Basis.IDENTITY,Vector3(0,2,2)))
	b.configuration["release_speed"]=2.1
	var group: Array[TrackPiece]=[a,b]
	build.set_selection(group)
	var original=build.snapshot()
	build.move_selected()
	check.call(build.ghosts.size()==2 and not a.visible and not b.visible,"Group movement creates one unified preview")
	build.proposed=Transform3D(Basis.IDENTITY,Vector3(3,3,0))
	build.valid=true
	build.apply_preview()
	build.commit()
	check.call(a.position==Vector3(3,3,0) and b.position==Vector3(3,4,2),"Group translation preserves elevation offsets")
	check.call(build.history.commands.size()==1,"Group movement is one history command")
	build.undo()
	check.call(build.snapshot()==original,"One undo restores the entire group")
	build.redo()
	check.call(build.pieces[1].position.y-build.pieces[0].position.y==1,"Redo preserves group elevation")
	build.select_all()
	var before_rotation=build.snapshot()
	build.rotate_piece()
	check.call(build.pieces[1].position.distance_to(build.pieces[0].position)>2 and absf(build.pieces[1].position.x-build.pieces[0].position.x)>1.9,"Group rotation rotates positions and orientations about a stable anchor")
	build.undo()
	check.call(build.snapshot()==before_rotation,"Group rotation undo is atomic")
	build.select_all()
	build.move_selected(true)
	check.call(build.ghosts.size()==2 and build.pieces.size()==2,"Duplicate assembly enters placement without spawning pieces")
	build.cancel()
	check.call(build.snapshot()==before_rotation,"Cancelled duplication leaves no pieces behind")
	build.move_selected(true)
	build.proposed.origin+=Vector3(5,0,0)
	build.valid=true
	build.apply_preview()
	build.commit()
	check.call(build.selection.size()==2 and build.pieces.size()==4 and build.selection[1].configuration.release_speed==2.1,"Confirmed group duplicate preserves data and selects the duplicate")
	build.delete_selected()
	check.call(build.pieces.size()==2,"Group deletion removes the complete selection")
	build.undo()
	check.call(build.pieces.size()==4,"One undo restores the deleted group")
	build.select_all()
	var before_cancel=build.snapshot()
	build.move_selected()
	build.proposed.origin+=Vector3(0,4,0)
	build.apply_preview()
	build.cancel()
	check.call(build.snapshot()==before_cancel and build.pieces.all(func(p):return p.visible),"Cancel restores original transforms and visibility")
	game.new_track()
	a=build.spawn(straight,Transform3D(Basis.IDENTITY,Vector3(0,3,0)))
	b=build.spawn(straight,Transform3D(Basis.IDENTITY,Vector3(0,3,1)))
	var support=build.spawn(build.catalog.get_piece("support-single-middle"),Transform3D(Basis.IDENTITY,Vector3(2,0,0)))
	build.select_connected(a)
	check.call(build.selection.size()==2 and support not in build.selection,"Connected selection follows compatible ports, excluding nearby supports")
	b.configuration["locked"]=true
	build.select_connected(a)
	check.call(build.selection.size()==1,"Connected selection respects locked pieces")
	b.configuration.erase("locked")
	build.camera.target_focus=Vector3(0,2,0)
	build.camera.target_distance=11
	build.camera._update(1)
	await game.get_tree().physics_frame
	var rect=ConstructionSelection.projected_bounds(a,build.camera)
	check.call(rect.has_area(),"3D selection projects the full transformed piece bounds")
	var box=Rect2(rect.position-Vector2(2,2),Vector2(8,8))
	check.call(a in ConstructionSelection.in_rectangle(build.pieces,build.camera,box),"Marquee intersection selects bounds even when the origin is outside")
	var sources: Array[Dictionary]=[{"definition":straight,"local":Transform3D.IDENTITY}]
	var ports=build.snap.boundary_sources(sources)
	var targets=build.snap.exposed(build.pieces)
	check.call(targets.size()==2,"Occupied internal connectors are excluded")
	var found: Array[Dictionary]=[]
	for target in targets:
		found=build.snap.screen_candidates(sources,ports,targets,build.camera,build.camera.unproject_position(target.point),build.pieces,[])
		if not found.is_empty() and found[0].error.is_empty(): break
	check.call(not found.is_empty() and found[0].error.is_empty(),"Screen-space targeting finds a valid elevated connector")
	if not found.is_empty():
		check.call(absf(found[0].transform.origin.y-3)<0.01 and build.height==0,"Connector alignment overrides height without changing the free-placement plane")
		var transform: Transform3D=found[0].transform
		var matched=false
		for port in straight.connectors:
			if (transform*port.position).distance_to(found[0].point)<0.015 and (transform.basis*port.outward).dot(found[0].target.normal)<-0.995: matched=true
		check.call(matched,"Automatic alignment matches exact connector position and facing")
		build.choose(straight)
		build.candidates=found
		build.candidate_key=found[0].key
		if found.size()>1:
			var first=build.candidate_key
			build.cursor_position=build.camera.unproject_position(found[0].point)
			build.cycle_candidate()
			check.call(build.candidate_key!=first,"Tab cycles alternative attachment orientations")
		build.cancel()
	# Real viewport input, with ray picking and the actual HUD present.
	game.new_track()
	a=build.spawn(straight,Transform3D(Basis.IDENTITY,Vector3(0,1,0)))
	build.camera.target_focus=Vector3(0,1,0)
	build.camera.target_distance=8
	build.camera._update(1)
	await game.get_tree().physics_frame
	var screen=build.camera.unproject_position(a.position+Vector3(0,0.25,0))
	await motion(screen)
	await mouse(screen,true)
	await mouse(screen,false)
	check.call(build.selected==a and a.position==Vector3(0,1,0),"Single click selects without accidentally moving")
	await mouse(screen,true)
	await motion(screen+Vector2(70,45))
	check.call(build.direct_drag and build.ghost!=null,"Pointer threshold starts dragging without a Move tool")
	await mouse(screen+Vector2(70,45),false)
	check.call(a.position.y==1 and build.history.commands.size()==1,"Releasing a direct drag preserves elevation and commits once")
	var moved=a.transform
	screen=build.camera.unproject_position(a.position+Vector3(0,0.25,0))
	await motion(screen)
	await mouse(screen,true)
	await motion(screen+Vector2(40,0))
	var escape=InputEventKey.new()
	escape.keycode=KEY_ESCAPE
	escape.pressed=true
	game.get_viewport().push_input(escape,true)
	await game.get_tree().process_frame
	check.call(a.transform==moved and a.visible and not build.chosen,"Escape cancels a direct drag without changing the original")
	await mouse(screen+Vector2(40,0),false)
	# Shift gestures, marquee, connected selection and UI ownership use viewport dispatch.
	game.new_track()
	a=build.spawn(straight,Transform3D(Basis.IDENTITY,Vector3(-1,1,0)))
	b=build.spawn(straight,Transform3D(Basis.IDENTITY,Vector3(1,2,0)))
	build.camera.target_focus=Vector3(0,1.5,0)
	build.camera.target_distance=10
	build.camera._update(1)
	await game.get_tree().physics_frame
	var sa=build.camera.unproject_position(a.position+Vector3(0,0.25,0))
	var sb=build.camera.unproject_position(b.position+Vector3(0,0.25,0))
	await motion(sa)
	await mouse(sa,true)
	await mouse(sa,false)
	await motion(sb)
	await mouse(sb,true,true)
	await mouse(sb,false,true)
	check.call(build.selection.size()==2,"Shift-click adds a piece at another elevation")
	await mouse(sb,true,true)
	await mouse(sb,false,true)
	check.call(build.selection.size()==1 and build.selected==a,"Shift-click toggles an existing selection off")
	var bounds=ConstructionSelection.projected_bounds(a,build.camera).merge(ConstructionSelection.projected_bounds(b,build.camera))
	var from=bounds.position-Vector2(25,25)
	var to=bounds.end+Vector2(25,25)
	await motion(from)
	await mouse(from,true)
	await motion(to)
	check.call(build.box_active,"Dragging empty space starts a selection rectangle")
	await mouse(to,false)
	check.call(build.selection.size()==2,"Marquee selects pieces at different elevations through viewport input")
	var count=build.pieces.size()
	var ui=game.get_node("Interface/Root/HUD").get_node("%Toolbox")
	var ui_point=ui.get_global_rect().position+Vector2(12,12)
	await motion(ui_point)
	await mouse(ui_point,true)
	await mouse(ui_point,false)
	check.call(build.pieces.size()==count and not build.pointer_down and not build.box_active,"UI clicks do not begin world gestures")
	game.new_track()
	a=build.spawn(straight,Transform3D(Basis.IDENTITY,Vector3(0,1,0)))
	b=build.spawn(straight,Transform3D(Basis.IDENTITY,Vector3(0,1,1)))
	build.camera.target_focus=Vector3(0,1,0)
	build.camera.target_distance=8
	build.camera._update(1)
	await game.get_tree().physics_frame
	screen=build.camera.unproject_position(a.position+Vector3(0,0.25,0))
	await motion(screen)
	await mouse(screen,true,false,true)
	await mouse(screen,false)
	check.call(build.selection.size()==2,"Double-click selects the actual connected assembly through viewport input")
	var search=ui.get_node("%Search")
	search.grab_focus()
	var key=InputEventKey.new()
	key.keycode=KEY_DELETE
	key.pressed=true
	game.get_viewport().push_input(key,true)
	check.call(build.pieces.size()==2,"Typing focus prevents destructive construction shortcuts")
	search.release_focus()
	build.select(null)
	key=InputEventKey.new()
	key.keycode=KEY_A
	key.ctrl_pressed=true
	key.pressed=true
	game.get_viewport().push_input(key,true)
	check.call(build.selection.size()==2,"Ctrl+A selects all editable pieces through InputMap")
	build.choose(straight)
	var free_screen=build.camera.unproject_position(Vector3(2,0,-2))
	await motion(free_screen)
	await mouse(free_screen,true)
	await mouse(free_screen,false)
	check.call(build.pieces.size()==3 and build.chosen==straight,"New-piece placement remains active after committing")
	free_screen=build.camera.unproject_position(Vector3(4,0,-2))
	await motion(free_screen)
	await mouse(free_screen,true)
	await mouse(free_screen,false)
	check.call(build.pieces.size()==4,"Consecutive placement requires no return to the library")
	var yaw=build.camera.target_yaw
	var right=InputEventMouseButton.new()
	right.button_index=MOUSE_BUTTON_RIGHT
	right.pressed=true
	right.position=free_screen
	game.get_viewport().push_input(right,true)
	await motion(free_screen+Vector2(20,0))
	check.call(build.chosen==null and build.camera.target_yaw==yaw,"Right-click cancels placement without accidentally orbiting")
	right.pressed=false
	game.get_viewport().push_input(right,true)
	# Every camera distance/angle uses the same elevated-port solver.
	for elevation in [0.0,4.0]:
		game.new_track()
		a=build.spawn(straight,Transform3D(Basis(Vector3.UP,PI/2),Vector3(0,elevation,0)))
		await game.get_tree().physics_frame
		for angle in [0.3,0.9,1.4]:
			for distance in [5.0,11.0,22.0]:
				build.camera.target_focus=Vector3(0,elevation,0)
				build.camera.target_yaw=angle
				build.camera.target_pitch=0.65
				build.camera.target_distance=distance
				build.camera._update(1)
				var elevated_targets=build.snap.exposed(build.pieces)
				var solutions: Array[Dictionary]=[]
				for target in elevated_targets:
					solutions=build.snap.screen_candidates(sources,ports,elevated_targets,build.camera,build.camera.unproject_position(target.point),build.pieces,[])
					if not solutions.is_empty() and solutions[0].error.is_empty(): break
				check.call(not solutions.is_empty() and solutions[0].error.is_empty(),"Rotated connector alignment at elevation %.0f / yaw %.1f / distance %.0f" % [elevation,angle,distance])
	# A slope attaches by measured elevation differences, not rounded coordinates.
	var slope=build.catalog.get_piece("slant-a")
	var slope_items: Array[Dictionary]=[{"definition":slope,"local":Transform3D.IDENTITY}]
	var available=build.snap.exposed(build.pieces)
	var slope_solutions: Array[Dictionary]=[]
	for target in available:
		slope_solutions=build.snap.screen_candidates(slope_items,build.snap.boundary_sources(slope_items),available,build.camera,build.camera.unproject_position(target.point),build.pieces,[])
		if not slope_solutions.is_empty() and slope_solutions[0].error.is_empty(): break
	check.call(not slope_solutions.is_empty() and slope_solutions[0].error.is_empty(),"Slopes automatically match elevated rotated ports")
	var wide_items: Array[Dictionary]=[{"definition":build.catalog.get_piece("straight-wide"),"local":Transform3D.IDENTITY}]
	check.call(build.snap.screen_candidates(wide_items,build.snap.boundary_sources(wide_items),available,build.camera,build.camera.unproject_position(available[0].point),build.pieces,[]).is_empty(),"Incompatible profiles never become magnetic candidates")
	var occlusion_target=available[0]
	var blocker=StaticBody3D.new()
	blocker.collision_layer=1
	var blocker_shape=CollisionShape3D.new()
	var box_shape=BoxShape3D.new()
	box_shape.size=Vector3(10,10,10)
	blocker_shape.shape=box_shape
	blocker.add_child(blocker_shape)
	build.add_child(blocker)
	blocker.position=build.camera.global_position.lerp(occlusion_target.point,0.5)
	await game.get_tree().physics_frame
	check.call(not build.snap.target_visible(occlusion_target,build.camera),"Opaque geometry occludes connector targeting")
	build.remove_child(blocker)
	blocker.queue_free()
	await game.get_tree().physics_frame
	build.camera.rotate_y(PI)
	check.call(build.snap.screen_candidates(sources,ports,available,build.camera,Vector2.ZERO,build.pieces,[]).is_empty(),"Connectors behind the camera are rejected")
	# Group snapping keeps both the original layout and its internal port graph.
	game.new_track()
	a=build.spawn(straight,Transform3D(Basis.IDENTITY,Vector3(0,1,0)))
	b=build.spawn(straight,Transform3D(Basis.IDENTITY,Vector3(0,1,1)))
	var external=build.spawn(straight,Transform3D(Basis.IDENTITY,Vector3(3,5,0)))
	group=[a,b]
	build.set_selection(group)
	build.move_selected()
	check.call(build.preview_ports.size()==2,"Group solver uses only exposed selection-boundary connectors")
	var targets_without_group=build.snap.exposed(build.pieces,group)
	check.call(targets_without_group.size()==2 and targets_without_group.all(func(t):return t.piece==external),"Moving-group ports are excluded from external targets")
	build.camera.target_focus=Vector3(3,5,0)
	build.camera.target_distance=10
	build.camera._update(1)
	await game.get_tree().physics_frame
	var group_solutions: Array[Dictionary]=[]
	for target in targets_without_group:
		group_solutions=build.snap.screen_candidates(build.preview_items,build.preview_ports,targets_without_group,build.camera,build.camera.unproject_position(target.point),build.pieces,group)
		if not group_solutions.is_empty() and group_solutions[0].error.is_empty(): break
	check.call(not group_solutions.is_empty() and group_solutions[0].error.is_empty(),"Entire group magnetically attaches to an external elevated connector")
	if not group_solutions.is_empty():
		build.proposed=group_solutions[0].transform
		build.valid=group_solutions[0].error.is_empty()
		build.apply_preview()
		build.commit()
		check.call(absf(a.position.y-5)<0.01 and absf(a.position.distance_to(b.position)-1)<0.01,"One rigid snapped transform preserves internal group layout")
		build.undo()
		check.call(build.pieces[0].position==Vector3(0,1,0) and build.pieces[1].position==Vector3(0,1,1),"One undo restores a snapped group move")
	build.cancel()
	game.new_track()
	var user_snapshot=build.snapshot()
	game.show_main_menu()
	var showcase=game.get_node("Interface/Root/MainMenu/Showcase")
	check.call(showcase.world_manager.get_world_3d()!=game.sandbox.get_world_3d(),"Showcase physics uses an isolated 3D world")
	check.call(showcase.world_manager.simulation.marble is RigidBody3D,"Showcase marble uses the existing real physics simulation")
	var initial=showcase.world_manager.simulation.marble.position
	var successes=0
	for frame in 1700:
		await game.get_tree().physics_frame
		if showcase.world_manager.simulation.state==SimulationManager.State.SUCCESS: successes+=1
	check.call(successes>0 and showcase.loops>=2,"Physical showcase reaches the finish and restarts gracefully")
	check.call(showcase.world_manager.simulation.marble.position.distance_to(initial)>0.1,"Showcase marble actually moves through the track")
	check.call(build.snapshot()==user_snapshot and not build.dirty,"Showcase loop leaves sandbox construction and dirty state untouched")
	showcase.animation.seek(9,true)
	showcase.world_manager.camera._update(1)
	var pose=showcase.world_manager.camera.transform
	showcase.animation.seek(27,true)
	showcase.world_manager.camera._update(1)
	check.call(not showcase.world_manager.camera.transform.is_equal_approx(pose),"Authored animation changes camera angle, dolly and elevation")
	showcase.animation.seek(0,true)
	showcase.world_manager.camera._update(1)
	pose=showcase.world_manager.camera.transform
	showcase.animation.seek(36,true)
	showcase.world_manager.camera._update(1)
	check.call(showcase.world_manager.camera.transform.is_equal_approx(pose),"Cinematic camera loop has matching endpoint poses")
	game.enter_sandbox()
	check.call(not showcase.active and showcase.world_manager.simulation.marble==null,"Entering the sandbox stops showcase simulation")

func motion(point: Vector2) -> void:
	var event=InputEventMouseMotion.new()
	event.position=point
	event.global_position=point
	game.get_viewport().push_input(event,true)
	await game.get_tree().process_frame

func mouse(point: Vector2, pressed: bool, shift: bool = false, double: bool = false) -> void:
	var event=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=pressed
	event.shift_pressed=shift
	event.double_click=double
	event.position=point
	event.global_position=point
	game.get_viewport().push_input(event,true)
	await game.get_tree().process_frame

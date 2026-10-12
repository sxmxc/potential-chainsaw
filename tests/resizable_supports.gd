extends SceneTree

const Geometry=preload("res://scripts/construction/support_geometry.gd")
const FAMILIES=["support-single","support-two","support-four","support-color-single","support-color-two","support-color-four"]
var failures: Array[String]=[]
var checks: int=0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition: failures.append(message); push_error("FAIL: "+message)

func run() -> void:
	root.size=Vector2i(1280,720)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.enter_sandbox()
	var build: BuildManager=game.sandbox.build
	var available=0
	for definition in game.catalog.pieces:
		check(definition.thumbnail!=null,"Preview resource exists for "+String(definition.id))
		if definition.category=="Supports" and definition.library_visible: available+=1
	check(available==6,"Inventory shows six support families instead of separate stack sections")
	for family in FAMILIES:
		var definition=game.catalog.get_piece(family)
		check(definition.library_visible and not game.catalog.get_piece(family+"-middle").library_visible,"Family is available and legacy sections remain save-compatible")
		for double_top in [false,true]:
			for target_height in [1.0,2.0,3.125,30.0]:
				var piece=build.spawn(definition,Transform3D.IDENTITY,"",{"support_height":target_height,"support_double_top":double_top})
				var sections=Geometry.sections(family,piece.configuration)
				var top=piece.model_node.get_node("Top")
				var bottom=piece.model_node.get_node("Bottom")
				check(top.scene_file_path.ends_with(family+("-top-double.glb" if double_top else "-top.glb")) and bottom.scene_file_path.ends_with(family+"-bottom.glb"),"Support uses its own top variant and matching bottom")
				check(top.scale.is_equal_approx(Vector3.ONE) and bottom.scale.is_equal_approx(Vector3.ONE) and is_equal_approx(top.position.y,target_height-0.5),"Top and bottom are unscaled at the exact bearing height")
				check(is_equal_approx(piece.definition.bounds.end.y,target_height+0.2) and piece.bodies.size()==piece.meshes.size(),"Bounds and mesh collision update once per actual segment")
				var expected=0.5
				for index in range(1,sections.size()-1):
					check(String(sections[index].definition.id)==family+"-middle" and is_equal_approx(sections[index].transform.origin.y,expected),"Matching middle sections extend continuously without gaps")
					expected+=sections[index].transform.basis.y.length()*0.5
				check(is_equal_approx(expected,top.position.y),"Middle reaches the top at fractional and maximum heights")
				build.pieces.erase(piece); piece.queue_free()
	var support=build.spawn(game.catalog.get_piece("support-four"),Transform3D.IDENTITY)
	build.select(support)
	check(build.configure_selected({"support_height":4.125,"support_double_top":true},"Support settings"),"Support settings use the common editing path")
	build.undo();support=build.pieces[0]
	check(support.configuration.support_height==2.0 and not support.configuration.support_double_top,"Undo restores support geometry and top style")
	build.redo();support=build.pieces[0]
	check(support.configuration.support_height==4.125 and support.configuration.support_double_top,"Redo restores one whole support assembly")
	build.select(support);build.elevate_selected(0.5)
	check(support.position.y==0 and support.configuration.support_height==4.625,"Height buttons extend the support instead of lifting its base off the ground")
	var save_id=game.serializer.save_track("Support QA",build.snapshot())
	var data=game.serializer.load_track(save_id)
	build.restore(data.pieces);support=build.pieces[0]
	check(support.configuration.support_height==4.625 and support.configuration.support_double_top and support.model_node.get_node("Top").scene_file_path.ends_with("support-four-top-double.glb"),"Save/load restores the exact family, height and top model")
	game.serializer.delete_track(save_id)
	build.select(support);build.move_selected(true)
	check(build.ghost.configuration==support.configuration and build.ghost.bodies.is_empty(),"Duplicate previews preserve settings and create no support collision")
	build.proposed=Transform3D(Basis.IDENTITY,Vector3(3,0,0));build.valid=true;build.ghost.visible=true;build.commit()
	check(build.pieces.size()==2 and build.selected.configuration.support_double_top,"Duplicate places a complete configured assembly")
	build.delete_selected();build.undo()
	check(build.pieces.size()==2,"Delete/undo restores the complete support as one action")
	game.new_track();game.enter_sandbox()
	build.set_height(5.0);build.choose(game.catalog.get_piece("support-color-single"))
	check(build.ghost.configuration.support_height==5.0,"Support preview automatically uses the active building level")
	build.set_height(3.125)
	check(build.ghost.configuration.support_height==3.125,"Changing building level resizes the existing preview")
	build.cancel()
	var track=build.spawn(game.catalog.get_piece("straight"),Transform3D(Basis.IDENTITY,Vector3(2,5,0)))
	game.get_node("Interface/Root/HUD").hide()
	build.camera.global_position=Vector3(7,10,8)
	build.camera.look_at(track.position+Vector3(0,0.25,0))
	build.camera.enabled=false;build.camera.set_process(false)
	await physics_frame
	await physics_frame
	build.set_height(1.0);build.choose(game.catalog.get_piece("support-four"))
	build.cursor_position=build.camera.unproject_position(track.position+Vector3(0,0.25,0))
	build.update_preview()
	check(build.ghost.configuration.support_height==5.0 and build.proposed.origin.y==0,"Hovering an elevated level track sizes the support to it with its base on ground")
	check(build.valid,"A fitted support can sit below the matching track without false overlap")
	print("SUPPORT RESULT: %d checks; %d failures" % [checks,failures.size()])
	var file=FileAccess.open("res://docs/support_test_results.txt",FileAccess.WRITE)
	file.store_string("%d checks; %d failures\n%s" % [checks,failures.size(),"\n".join(failures)])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

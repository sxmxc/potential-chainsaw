extends "res://tests/support/scene_test.gd"

var game: Node
var catalog: PieceCatalog
var snap: SnapManager

class TestCatalog:
	extends GutTest

	func test_catalog_models_and_previews_load() -> void:
		var piece_catalog = PieceCatalog.new()
		assert_eq(piece_catalog.query().size(), 207)
		for definition in piece_catalog.query():
			assert_not_null(definition.model, "%s model loads" % definition.id)
			if definition.model:
				assert_not_null(autofree(definition.model.instantiate()), "%s model instantiates" % definition.id)
			assert_not_null(definition.thumbnail, "%s preview loads" % definition.id)
			if definition.thumbnail:
				assert_true(definition.thumbnail.get_width() > 0 and definition.thumbnail.get_height() > 0, "%s preview has image data" % definition.id)
		for model in preload("res://scripts/simulation/marble.gd").MODELS:
			assert_not_null(autofree(model.instantiate()), "Marble variant instantiates")

class TestRegistry:
	extends GutTest

	func test_fixed_piece_positions_survive_json_precision_round_trip() -> void:
		var original := {"uid":"fixed", "piece":"straight", "position":[3.49997711181641, 0.0, 1.99997687339783], "rotation":0}
		var rules := PuzzleRules.new({"pieces":[original]}, PieceCatalog.new())
		var current := original.duplicate(true)
		var position := Vector3(original.position[0], original.position[1], original.position[2])
		current.position = [position.x, position.y, position.z]
		assert_eq(rules.validate([current]), "", "Engine position precision preserves fixed placements")
		current.position[0] += 0.001
		assert_eq(rules.validate([current]), "This piece is fixed in place", "Actual movement remains forbidden")

	func test_registry_ids_and_indexed_queries_match_saved_definitions() -> void:
		var definitions := PieceCatalog.new()
		var registry := PieceCatalog.REGISTRY
		assert_eq(registry.size(), 207, "Tracks, hidden support sections and scenery are registered")
		assert_true(registry.is_property_indexed(&"category"))
		assert_true(registry.is_property_indexed(&"behavior"))
		var registered_ids := registry.get_all_string_ids()
		for file in DirAccess.get_files_at("res://resources/pieces"):
			if not file.ends_with(".tres"): continue
			var saved := load("res://resources/pieces/" + file) as PieceDefinition
			assert_true(registered_ids.has(saved.id), file + " is in the authoritative registry")
		for id in registered_ids:
			var definition := definitions.get_piece(String(id))
			assert_not_null(definition, "Registered resource loads: " + String(id))
			if not definition: continue
			assert_eq(definition.id, id, "Registry and persistent piece IDs agree")
			assert_true(definitions.query({&"category":definition.category, &"behavior":definition.behavior}).has(definition), "AND query finds " + String(id))
		assert_null(definitions.get_piece("unregistered-piece"))
		assert_true(definitions.query({&"category":"Unknown category"}).is_empty())
		var expected: Array[String] = []
		for definition in definitions.query():
			if not expected.has(definition.category): expected.append(definition.category)
		expected.sort_custom(func(a: String, b: String): return a.naturalnocasecmp_to(b) < 0)
		expected.push_front("All pieces")
		assert_eq(definitions.categories(), expected, "Only registered categories appear, alphabetically, after All pieces")

	func test_registered_scenery_has_mesh_collision_and_legacy_asset_ids() -> void:
		var definitions := PieceCatalog.new()
		var scenery := definitions.query({&"behavior":"decoration"}).filter(func(definition): return definition.authoring_only)
		for asset in ["partition", "deck", "column", "machine"]:
			var definition := definitions.get_piece("environment:" + asset)
			assert_not_null(definition)
			if not definition: continue
			assert_true(scenery.has(definition))
			assert_true(definition.authoring_only)
			assert_true(definition.collision_enabled, "Imported scenery uses shared generated mesh collision")
			assert_eq(PuzzleEnvironment.get_asset(asset), definition)
			var object := autofree(BuildManager.PIECE_SCENE.instantiate()) as BuildingPiece
			object.setup(definition)
			assert_false(object.bodies.is_empty(), "Imported scenery has physical mesh collision")
			assert_false(definition.collision_solids.is_empty(), "Placement has measured occupied volumes")
		assert_null(PuzzleEnvironment.get_asset("unknown"))

class TestPersistence:
	extends "res://tests/support/game_test.gd"

	func test_json_save_replaces_complete_content() -> void:
		var path := test_directory.path_join("save.json")
		assert_eq(SaveStorage.write_json(path, {"name": "Original", "pieces": [1, 2, 3]}), "")
		var replacement := {"name": "Replacement", "pieces": []}
		assert_eq(SaveStorage.write_json(path, replacement), "")
		assert_eq(JSON.parse_string(FileAccess.get_file_as_string(path)), replacement)
		assert_false(FileAccess.file_exists(path + ".tmp"))

	func test_failed_json_save_preserves_existing_bytes() -> void:
		var path := test_directory.path_join("save.json")
		assert_eq(SaveStorage.write_json(path, {"name": "Keep this save"}), "")
		var original := FileAccess.get_file_as_bytes(path)
		# An unwritable temporary destination must never truncate the saved file.
		assert_eq(DirAccess.make_dir_absolute(path + ".tmp"), OK)
		assert_false(SaveStorage.write_json(path, {"name": "Rejected"}).is_empty())
		assert_eq(FileAccess.get_file_as_bytes(path), original)

	func test_failed_json_replacement_removes_temporary_file() -> void:
		var path := test_directory.path_join("directory")
		assert_eq(DirAccess.make_dir_absolute(path), OK)
		assert_false(SaveStorage.write_json(path, {"name": "Cannot replace a directory"}).is_empty())
		assert_true(DirAccess.dir_exists_absolute(path))
		assert_false(FileAccess.file_exists(path + ".tmp"))

	func test_save_paths_are_owned_by_each_instance() -> void:
		var definitions := PieceCatalog.new()
		var first_tracks := TrackSerializer.new(definitions)
		var first_puzzles := PuzzleStore.new(definitions)
		var draft := first_puzzles.create()
		assert_true(first_puzzles.save_draft(draft))
		var track_id := first_tracks.save_track("First fixture", [])
		assert_false(track_id.is_empty())
		OS.set_environment("MARBLE_ENGINEER_TEST_DATA", test_directory.path_join("second"))
		var second_tracks := TrackSerializer.new(definitions)
		var second_puzzles := PuzzleStore.new(definitions)
		assert_true(second_tracks.list_tracks().is_empty(), "Second instance cannot see first instance's track")
		assert_false(FileAccess.file_exists(second_puzzles.drafts_directory.path_join(draft.id + ".json")))
		assert_eq(first_tracks.load_track(track_id).name, "First fixture", "Existing instance retains its path after the environment changes")
		assert_true(FileAccess.file_exists(first_puzzles.drafts_directory.path_join(draft.id + ".json")))
		OS.set_environment("MARBLE_ENGINEER_TEST_DATA", test_directory)
		assert_eq(TrackSerializer.new(definitions).load_track(track_id).name, "First fixture", "Recreated instance resolves the current fixture")

func test_construction() -> void:
	catalog=PieceCatalog.new()
	snap=SnapManager.new()
	assert_true(catalog.query().size()==207,"Tracks, mechanisms, supports and native scenery share a catalog")
	for v in [Vector3.ZERO,Vector3(-3,1.125,2.5),Vector3(12.5,4,-8)]:
		assert_true(snap.grid_to_world(snap.world_to_grid(v)).is_equal_approx(v),"Grid round trip "+str(v))
	assert_true(snap.grid_position(Vector3(-0.76,0.2,-0.26)).is_equal_approx(Vector3(-1,0.25,-0.5)),"Negative grid rounding")
	var straight=catalog.get_piece("straight")
	var wide=catalog.get_piece("straight-wide")
	assert_true(not straight.connectors[0].compatible(wide.connectors[0]),"Different channel profiles reject")
	assert_true(straight.connectors[0].compatible(straight.connectors[1]),"Bidirectional channel compatibility")
	var entry=TrackConnector.new()
	entry.direction="entry"
	var exit=TrackConnector.new()
	exit.direction="exit"
	assert_true(entry.compatible(exit) and not entry.compatible(entry),"Directionality constraints")
	assert_true(snap.solid_overlap(straight,Transform3D.IDENTITY,straight,Transform3D.IDENTITY),"Duplicate placement rejects")
	assert_true(not snap.solid_overlap(straight,Transform3D.IDENTITY,straight,Transform3D(Basis(Vector3.UP,PI/2),Vector3(0,1,0))),"Elevated crossing allowed")
	assert_true(not snap.solid_overlap(straight,Transform3D.IDENTITY,straight,Transform3D(Basis.IDENTITY,Vector3(0,0,1))),"Touching end faces allowed")
	var curve=catalog.get_piece("curve")
	assert_true(curve.bounds.size.is_equal_approx(Vector3(2,0.5,2)),"Multi-cell curve retains measured bounds")
	var slant=catalog.get_piece("slant-a")
	assert_true(abs(slant.connectors[0].position.y-slant.connectors[1].position.y)>0.24,"Slope endpoints have different elevations")
	var serializer=TrackSerializer.new(catalog)
	assert_true(serializer.decode('{"version":99,"name":"bad","pieces":[]}').is_empty(),"Unknown save version fails safely")
	assert_true(serializer.decode('{"version":1,"name":"bad","pieces":[{"piece":"straight","position":[0],"rotation":0}]}').is_empty(),"Malformed transforms reject atomically")
	assert_true(serializer.load_track("../escape").is_empty(),"Save path traversal rejects")
	var unknown=serializer.decode('{"version":1,"name":"migration","pieces":[{"piece":"future-piece","position":[0,0,0],"rotation":0}]}')
	assert_true(not unknown.is_empty() and unknown.pieces.is_empty() and serializer.warnings.size()==1,"Missing catalog entries report and skip")
	game=load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	await get_tree().process_frame
	var build: BuildManager=game.workspace.world.build
	assert_true(ProjectSettings.get_setting("gui/theme/custom")=="res://resources/sandbox_theme.tres","Project-wide native Theme configured")
	var theme=load("res://resources/sandbox_theme.tres") as Theme
	for type in ["PrimaryButton","SecondaryButton","DangerButton","ToolboxButton","ToolbarButton","PanelTitle"]:
		assert_true(not theme.get_type_variation_base(type).is_empty(),"Reusable Theme variation "+type)
	assert_true(not build.enabled,"Main menu locks world editing")
	game.workspace.session.sandbox()
	assert_true(build.enabled and build.pieces.is_empty(),"New sandbox ready for construction")
	var before=build.snapshot()
	var placed=build.spawn(straight,Transform3D.IDENTITY)
	build.record(before,"Place")
	build.undo()
	assert_true(build.pieces.is_empty(),"Undo initial placement")
	build.redo()
	assert_true(build.pieces.size()==1,"Redo initial placement")
	placed=build.pieces[0]
	build.select(placed)
	build.move_selected()
	build.proposed=Transform3D(Basis.IDENTITY,Vector3(2,1,0))
	build.ghost.visible=true
	build.valid=true
	build.commit()
	assert_true(build.pieces[0].position.is_equal_approx(Vector3(2,1,0)),"Movement confirms exact preview transform")
	build.undo()
	assert_true(build.pieces[0].position==Vector3.ZERO,"Undo movement")
	build.redo()
	assert_true(build.pieces[0].position.is_equal_approx(Vector3(2,1,0)),"Redo movement")
	build.select(build.pieces[0])
	build.rotate_piece()
	assert_true(abs(build.pieces[0].basis.z.x)>0.99,"Quarter-turn rotation")
	build.undo()
	assert_true(abs(build.pieces[0].basis.z.z)>0.99,"Undo rotation restores basis")
	build.select(build.pieces[0])
	build.move_selected()
	build.cancel()
	assert_true(build.pieces.size()==1 and build.pieces[0].visible,"Cancelled movement preserves original")
	build.select(build.pieces[0])
	build.delete_selected()
	assert_true(build.pieces.is_empty(),"Deletion")
	build.undo()
	assert_true(build.pieces.size()==1,"Undo deletion")
	var data=build.snapshot()
	var saved=serializer.save_track("Automated round trip",data,"qa-roundtrip")
	assert_true(not saved.is_empty(),"Persistent JSON write")
	var loaded=serializer.load_track(saved)
	assert_true(loaded.pieces==data,"Save/load round trip preserves transforms, IDs and configuration")
	serializer.delete_track(saved)
	game.workspace.session.track_name="Workflow save"
	game.workspace.session.track_id="qa-workflow"
	assert_true(game.workspace.session.save_track(game.workspace.session.track_name, game.workspace.session.track_id),"Session saves the current Sandbox construction")
	game.workspace.session.sandbox()
	game.workspace.session.load_track("qa-workflow",false)
	assert_true(build.snapshot()==data and not build.dirty,"Saved track reopens for editing")
	serializer.delete_track("qa-workflow")
	game.handle_action("settings")
	assert_true(not build.enabled and game.settings_dialog.visible,"Saved settings scene opens as a modal")
	game.settings_dialog.close()
	assert_true(build.enabled,"Closing settings restores construction input")
	game.workspace.session.sandbox()
	var rotor=build.spawn(catalog.get_piece("fan-simple-two"),Transform3D(Basis.IDENTITY,Vector3(10,0,0)))
	await get_tree().process_frame
	assert_true(rotor.behaviors[0] is RotorComponent,"Imported fan attaches real rotating collision component")
	assert_has(rotor.bodies, rotor.behaviors[0].rotor, "Moving blade collision participates in common ray exclusions")
	var rest=rotor.behaviors[0].mesh.transform
	rotor.behaviors[0].active=true
	for i in 4: await get_tree().physics_frame
	assert_true(not rotor.behaviors[0].mesh.transform.is_equal_approx(rest),"Fan mechanism rotates during physics")
	rotor.behaviors[0].reset()
	assert_true(rotor.behaviors[0].mesh.transform.is_equal_approx(rest),"Mechanism reset restores original transform")
	for id in ["first-roll","spiral-crossing"]:
		game.qa_example(id)
		var original=build.snapshot()
		for piece in build.pieces:
			assert_true(snap.validate(piece.definition,piece.transform,build.pieces,piece).is_empty(),id+" placement validity "+piece.definition.display_name)
		check_connected_chain(build.pieces,id)
		assert_true(game.qa_test(),id+" starts a real physics simulation")
		assert_true(game.workspace.world.simulation.marble is RigidBody3D,id+" uses rigid body marble")
		assert_true(not build.enabled,id+" locks construction during simulation")
		game.workspace.world.simulation.toggle_pause()
		assert_true(game.workspace.world.simulation.state==SimulationManager.State.PAUSED and game.workspace.world.simulation.marble.freeze,"Pause freezes physics")
		game.workspace.world.simulation.toggle_pause()
		for frame in range(7200):
			await get_tree().physics_frame
			if game.workspace.world.simulation.state in [SimulationManager.State.SUCCESS,SimulationManager.State.FAILED]: break
		print("Physics example ",id," state ",game.workspace.world.simulation.state," time ",game.workspace.world.simulation.elapsed," marble ",game.workspace.world.simulation.marble.position)
		assert_true(game.workspace.world.simulation.state==SimulationManager.State.SUCCESS,id+" marble physically reaches finish")
		game.workspace.world.simulation.reset()
		assert_true(build.snapshot()==original,id+" reset preserves original construction")
		assert_true(game.workspace.world.simulation.marble==null and build.enabled,"Reset returns build mode and removes marble")
	game.workspace.session.sandbox()
	assert_true(not game.qa_test(),"Missing release fails without leaving build mode")

func check_connected_chain(pieces: Array[BuildingPiece], title: String) -> void:
	for i in range(0,pieces.size()-1):
		var a=pieces[i]
		var b=pieces[i+1]
		if a.definition.connectors.is_empty() or b.definition.connectors.is_empty(): continue
		var connected=false
		for ac in a.definition.connectors:
			for bc in b.definition.connectors:
				if ac.compatible(bc) and (a.transform*ac.position).distance_to(b.transform*bc.position)<0.015 and (a.basis*ac.outward).dot(b.basis*bc.outward)<-0.995: connected=true
		assert_true(connected,title+" transition "+String(a.definition.id)+" → "+String(b.definition.id))

class TestReservedBounds:
	extends GutTest

	func test_elevator_reserves_space_against_environment_solids_without_mesh_collision() -> void:
		var definitions := PieceCatalog.new()
		var elevator := definitions.get_piece("bucket-elevator").configured({"elevator_height": 6.0})
		var obstruction := AABB(Vector3(0, 3, 0.75), Vector3.ONE * 0.2)
		assert_true(SnapManager.intersects_solids(elevator, Transform3D.IDENTITY, [obstruction]), "Environment solids block the elevator's swept area, including empty bucket gaps")
		assert_false(SnapManager.intersects_solids(elevator, Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)), [obstruction]), "Separated elevator placement remains allowed")
		var display := definitions.get_piece("environment:factory-screen-panel-small")
		assert_false(SnapManager.intersects_solids(display, Transform3D.IDENTITY, [display.bounds]), "Decoration without collision or reserved space remains freely placeable")

	func test_thin_catwalk_solids_overlap_without_inverting_contact_bounds() -> void:
		var definitions := PieceCatalog.new()
		var catwalk := definitions.get_piece("environment:factory-catwalk-straight")
		var thin: AABB = catwalk.collision_solids.filter(func(solid: AABB): return solid.size.x < 0.002)[0]
		var probe := PieceDefinition.new()
		probe.bounds = thin
		probe.collision_solids = [thin]
		var snap := SnapManager.new()
		var touching := Transform3D(Basis.IDENTITY, Vector3(thin.size.x, 0, 0))
		assert_true(snap.solid_overlap(probe, Transform3D.IDENTITY, probe, Transform3D.IDENTITY), "Thin authored solids still block overlapping placement")
		assert_false(snap.solid_overlap(probe, Transform3D.IDENTITY, probe, touching), "Touching thin solids remain allowed")
		var rotated := Transform3D(Basis(Vector3.UP, PI / 2), Vector3.ZERO)
		assert_true(snap.solid_overlap(probe, rotated, probe, rotated), "Rotated thin solids retain overlap checks")
		probe.reserve_bounds = true
		assert_true(SnapManager.intersects_solids(probe, Transform3D.IDENTITY, [thin]), "Thin bounds work against environment solids")
		probe.collision_solids.clear()
		assert_true(snap.solid_overlap(probe, Transform3D.IDENTITY, probe, Transform3D.IDENTITY), "Reserved thin bounds remain usable")
		assert_false(snap.solid_overlap(probe, Transform3D.IDENTITY, probe, touching), "Reserved touching bounds remain allowed")
		var piece := autofree(BuildingPiece.new()) as BuildingPiece
		piece.definition = probe
		assert_false(snap.validate(probe, Transform3D.IDENTITY, [piece]).is_empty(), "Placement broad-phase retains thin overlapping pieces")
		assert_eq(snap.validate(probe, touching, [piece]), "", "Placement broad-phase allows thin touching pieces")

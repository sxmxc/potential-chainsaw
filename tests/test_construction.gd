extends GutTest

class TestPieceGeometry:
	extends GutTest

	func test_reconfigured_decoration_remains_pickable_and_excluded_from_drag_rays() -> void:
		var piece := BuildingPiece.new()
		add_child_autoqfree(piece)
		piece.setup(PieceCatalog.new().get_piece("environment:factory-screen-panel-small"))
		var camera := Camera3D.new()
		add_child_autoqfree(camera)
		var center := piece.definition.bounds.get_center()
		camera.position = center + Vector3.UP * 5
		camera.look_at(center, Vector3.FORWARD)
		var snap := SnapManager.new()
		for iteration in 2:
			if iteration == 1: piece.apply_configuration({})
			await get_tree().physics_frame
			await get_tree().physics_frame
			var screen := camera.unproject_position(center)
			assert_eq(snap.surface_hit(camera, screen, [], 4).get("piece"), piece, "Pick bounds survive configuration")
			assert_true(snap.surface_hit(camera, screen, [piece], 4).is_empty(), "A moving decoration cannot hit its own pick bounds")

	func test_rebuilt_support_geometry_receives_collision_and_selection_tint() -> void:
		var piece := BuildingPiece.new()
		add_child_autoqfree(piece)
		piece.setup(PieceCatalog.new().get_piece("support-single"))
		var original_count := piece.find_children("*", "StaticBody3D", true, false).size()
		piece.apply_configuration({"support_height": 6.0})
		var resized_bodies := piece.find_children("*", "StaticBody3D", true, false)
		assert_gt(resized_bodies.size(), original_count, "New support sections receive collision")
		piece.apply_configuration({"support_height": 6.0})
		assert_eq(piece.find_children("*", "StaticBody3D", true, false).size(), resized_bodies.size(), "Reconfiguration does not duplicate collision")
		piece.tint(Color.CYAN)
		for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
			assert_eq(mesh.material_overlay, piece.tint_material, "Tint includes every rebuilt mesh")
		for body: StaticBody3D in piece.find_children("*", "StaticBody3D", true, false):
			assert_eq(body.collision_layer, 1)
			assert_eq(body.collision_mask, 2)

	func test_native_and_generated_preview_geometry_never_participates_in_physics() -> void:
		var catalog := PieceCatalog.new()
		for id in ["straight", "support-single", "bucket-elevator"]:
			var definition := catalog.get_piece(id)
			var piece := BuildingPiece.new()
			add_child_autoqfree(piece)
			piece.setup(definition, true)
			var config: Dictionary = {}
			if not definition.height_setting.is_empty(): config[String(definition.height_setting)] = 6.0
			piece.apply_configuration(config)
			for body: CollisionObject3D in piece.find_children("*", "CollisionObject3D", true, false):
				assert_eq(body.collision_layer, 0, id + " preview has no collision layer")
				assert_eq(body.collision_mask, 0, id + " preview has no collision mask")

class TestPlacementPrecision:
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


class TestPersistence:
	extends "res://tests/support/game_test.gd"

	func test_menu_machine_preserves_every_piece_through_track_save() -> void:
		var source := FileAccess.get_file_as_string("res://resources/menu_machine.json")
		var original: Dictionary = JSON.parse_string(source)
		var serializer := TrackSerializer.new(PieceCatalog.new())
		var decoded := serializer.decode(source)
		assert_false(decoded.is_empty(), serializer.last_error)
		assert_eq(serializer.warnings, [] as Array[String], "The bundled example resolves every construction ID")
		assert_eq(decoded.get("pieces", []).size(), original.pieces.size())
		for index in original.pieces.size():
			var expected: Dictionary = original.pieces[index]
			var actual: Dictionary = decoded.pieces[index]
			assert_eq(actual.uid, expected.uid)
			assert_eq(actual.piece, expected.piece)
			assert_eq(actual.position, expected.position)
			assert_eq(actual.rotation, int(expected.rotation))
		var saved_id := serializer.save_track(decoded.name, decoded.pieces)
		assert_false(saved_id.is_empty(), serializer.last_error)
		var reloaded := serializer.load_track(saved_id)
		assert_eq(reloaded.get("pieces", []).size(), decoded.pieces.size())
		for index in decoded.pieces.size():
			var expected: Dictionary = decoded.pieces[index]
			var actual: Dictionary = reloaded.pieces[index]
			assert_eq(actual.uid, expected.uid)
			assert_eq(actual.piece, expected.piece)
			assert_eq(actual.rotation, expected.rotation)
			assert_eq(JSON.stringify(actual.config), JSON.stringify(expected.config))
			for axis in 3:
				assert_almost_eq(float(actual.position[axis]), float(expected.position[axis]), 0.000001)
		assert_eq(serializer.warnings, [] as Array[String])
		for size in ["short", "tall"]:
			var scenery_id: String = "environment:factory-structure-" + size
			var scenery: Dictionary = original.duplicate(true)
			scenery.pieces = [{"uid": "scenery", "piece": scenery_id, "position": [0, 0, 0], "rotation": 0}]
			assert_eq(serializer.decode(JSON.stringify(scenery)).pieces.size(), 0, "Authoring scenery remains excluded from personal tracks")
			assert_eq(serializer.warnings.size(), 1)

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

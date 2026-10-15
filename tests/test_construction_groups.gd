extends "res://tests/support/game_test.gd"

var game: Node
var build: BuildManager

func test_group_preview_preserves_relative_transforms_through_cancel_and_commit() -> void:
	game = load("res://scenes/construction_workspace.tscn").instantiate()
	add_child_autoqfree(game)
	await get_tree().process_frame
	build = game.world.build
	var definition := build.catalog.get_piece("straight")
	var first := build.spawn(definition, Transform3D(Basis(Vector3.UP, PI / 2), Vector3(1, 1, 0)), "first")
	var second := build.spawn(definition, Transform3D(Basis.IDENTITY, Vector3(3, 2, 0)), "second")
	build.set_selection([first, second])
	var before := build.snapshot()
	build.move_selected()
	build.preview.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(5, 3, 0))
	build.valid = true
	build.apply_preview()
	var shown: Array[Transform3D] = []
	for piece: BuildingPiece in build.preview.get_children(): shown.append(piece.global_transform)
	assert_true(shown[0].origin.is_equal_approx(Vector3(5, 3, 0)))
	assert_true(shown[1].origin.is_equal_approx(Vector3(5, 4, -2)), "Group rotation retains relative elevation")
	assert_eq(build.snapshot(), before, "Preview leaves original construction untouched")
	build.cancel()
	assert_true(first.visible and second.visible, "Cancel restores hidden originals")
	assert_eq(build.snapshot(), before)
	assert_false(build.history.has_undo(), "Cancel does not record an edit")
	build.move_selected()
	build.preview.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(5, 3, 0))
	build.valid = true
	build.apply_preview()
	build.commit()
	assert_true(first.global_transform.is_equal_approx(shown[0]), "Commit matches the visible preview")
	assert_true(second.global_transform.is_equal_approx(shown[1]))
	var after := build.snapshot()
	build.undo()
	assert_eq(build.snapshot(), before, "One undo restores the assembly")
	build.redo()
	assert_eq(build.snapshot(), after)

func test_resized_preview_commits_and_reloads_its_configuration_and_geometry() -> void:
	game = load("res://scenes/construction_workspace.tscn").instantiate()
	add_child_autoqfree(game)
	await get_tree().process_frame
	build = game.world.build
	build.choose(build.catalog.get_piece("support-single"))
	build.resize_height_preview(6.0)
	build.preview.transform = Transform3D(Basis.IDENTITY, Vector3(5, 0, 0))
	build.valid = true
	build.apply_preview()
	var shown := build.preview.get_child(0) as BuildingPiece
	var shown_bounds := shown.definition.bounds
	var shown_config := shown.configuration.duplicate(true)
	assert_eq(shown_config.support_height, 6.0)
	build.commit()
	build.cancel()
	assert_eq(build.pieces.size(), 1)
	assert_eq(build.pieces[0].configuration, shown_config)
	assert_eq(build.pieces[0].definition.bounds, shown_bounds, "Committed geometry matches the resized preview")
	var saved := build.snapshot()
	build.restore(saved)
	assert_eq(build.snapshot(), saved)
	assert_eq(build.pieces[0].definition.bounds, shown_bounds, "Reload preserves configured geometry")

func test_rejected_edits_preserve_live_nodes_and_history() -> void:
	game = load("res://scenes/construction_workspace.tscn").instantiate()
	add_child_autoqfree(game)
	var session: ConstructionSession = game.session
	var data := session.store.create()
	data.pieces = [
		{"uid": "anchor", "piece": "straight", "position": [0, 1, 0], "rotation": 0, "config": {}},
		{"uid": "other", "piece": "straight", "position": [0, 1, 2], "rotation": 0, "config": {}},
	]
	for item in data.pieces: data.permissions[item.uid] = {"rotate": true, "move": false}
	session.player(data, true)
	build = game.world.build
	assert_true(build.enabled, "The shared workspace accepts construction input")
	var original: Array[BuildingPiece] = build.pieces.duplicate()
	build.set_selection(original)
	var before := build.snapshot()
	watch_signals(build)
	build.rotate_piece()
	assert_eq(build.snapshot(), before, "Rotation cannot move a member with locked position")
	assert_eq(build.pieces, original, "Rejected edits preserve live piece references")
	assert_eq(build.selection, original, "Rejected edits preserve the whole selection")
	assert_false(build.history.has_undo(), "Rejection adds no history")
	assert_false(build.dirty, "Rejection does not dirty the construction")
	assert_signal_not_emitted(build, "changed", "Rejection does not reload the construction")
	for item in data.pieces: build.rules.puzzle.permissions[item.uid].move = true
	build.elevate_selected(20)
	assert_eq(build.pieces, original, "Puzzle bounds reject elevation before replacing nodes")
	assert_eq(build.snapshot(), before)
	assert_false(build.history.has_undo())
	build.rotate_piece()
	assert_true(build.history.has_undo(), "A permitted group edit records history")
	assert_true(build.pieces[1].position.is_equal_approx(Vector3(2, 1, 0)))
	build.undo()
	assert_eq(build.snapshot(), before, "One undo restores the complete group")
	build.redo()
	build.elevate_selected(0.5)
	assert_eq(build.selected.position.y, 1.5, "A permitted elevation applies to the group")
	build.move_selected()
	build.preview.position = Vector3(4, 2, 0)
	build.valid = true
	build.apply_preview()
	build.commit()
	assert_true(build.selected.position.is_equal_approx(Vector3(4, 2, 0)), "Move commits the validated preview")
	session.sandbox()
	var lift := build.spawn(build.catalog.get_piece("bucket-elevator"), Transform3D.IDENTITY)
	var bucket: Node3D = lift.behaviors[0].buckets[0]
	build.spawn(build.catalog.get_piece("straight"), Transform3D(Basis.IDENTITY, Vector3(0, 9, 0.75)))
	build.select(lift)
	assert_false(build.configure_selected({"elevator_height": 10.0}, "Blocked resize"))
	assert_eq(lift.behaviors[0].buckets[0], bucket, "Rejected configuration never rebuilds live mechanism children")
	assert_eq(lift.configuration.elevator_height, 4.0)
	assert_false(build.history.has_undo())

class TestConnectorConnectivity:
	extends GutTest

	func test_exposure_and_connected_selection_share_connection_rules() -> void:
		var snap := SnapManager.new()
		var definition := PieceCatalog.new().get_piece("straight")
		var a := autofree(BuildingPiece.new()) as BuildingPiece
		var b := autofree(BuildingPiece.new()) as BuildingPiece
		a.definition = definition
		b.definition = definition
		a.instance_id = "a"
		b.instance_id = "b"
		var pieces: Array[BuildingPiece] = [a, b]
		var frame := Transform3D(Basis(Vector3.UP, PI / 2), Vector3(4, 5, 2))
		a.transform = frame
		for sample in [
			{"offset": Vector3(0, 0, 1), "turn": 0.0, "connected": true},
			{"offset": Vector3(0, 0.01, 1), "turn": 0.0, "connected": true},
			{"offset": Vector3(0, 0.02, 1), "turn": 0.0, "connected": false},
			{"offset": Vector3(0, 0, 1), "turn": PI / 2, "connected": false},
		]:
			b.transform = frame * Transform3D(Basis(Vector3.UP, sample.turn), sample.offset)
			var expected_count := 2 if sample.connected else 4
			assert_eq(snap.exposed(pieces).size(), expected_count, "World targets respect position and facing")
			var items: Array[Dictionary] = [
				{"definition": definition, "local": frame.affine_inverse() * a.transform},
				{"definition": definition, "local": frame.affine_inverse() * b.transform},
			]
			assert_eq(snap.boundary_sources(items).size(), expected_count, "Group boundaries use the same connection rules")
			assert_eq(snap.connected_section(a, pieces).size(), 2 if sample.connected else 1)
		b.transform = frame * Transform3D(Basis.IDENTITY, Vector3(0, 0, 1))
		assert_eq(snap.exposed(pieces, [b]).size(), 2, "Ignored moving pieces do not occupy targets")
		assert_eq(snap.exposed(pieces)[0].key, "a:0", "Target keys retain authored connector indices")
		assert_eq(snap.connected_section(a, [a]), [a], "Excluded pieces cannot bridge connected selection")
		b.definition = PieceCatalog.new().get_piece("straight-wide")
		assert_eq(snap.exposed(pieces).size(), 4, "Different profiles cannot occupy each other's connectors")
		assert_eq(snap.connected_section(a, pieces), [a], "Different profiles cannot join a connected selection")

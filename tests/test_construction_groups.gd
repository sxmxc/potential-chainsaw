extends "res://tests/support/game_test.gd"

var game: Node
var build: BuildManager

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
	build.proposed.origin = Vector3(4, 2, 0)
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

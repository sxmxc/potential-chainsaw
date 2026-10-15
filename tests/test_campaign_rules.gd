extends "res://tests/support/game_test.gd"

var workspace: ConstructionWorkspace
var session: ConstructionSession
var build: BuildManager

func record(id: String, uid: String, at: Vector3, config: Dictionary = {}) -> Dictionary:
	return {"piece": id, "uid": uid, "position": [at.x, at.y, at.z], "rotation": 0, "config": config}

func test_campaign_rules() -> void:
	workspace = load("res://scenes/construction_workspace.tscn").instantiate()
	add_child_autoqfree(workspace)
	await get_tree().process_frame
	session = workspace.session
	build = workspace.world.build
	var data = session.store.create()
	data.pieces = [record("straight", "locked", Vector3.ZERO), record("straight", "editable", Vector3(2, 0, 0))]
	data.permissions.editable = {"move": true, "rotate": true, "remove": true, "duplicate": true}
	data.inventory = {"straight": 2}
	session.player(data, true)
	build.set_selection(build.pieces)
	build.move_selected()
	assert_true(build.preview.get_child_count() == 0, "Mixed group cannot move fixed members")
	build.rotate_piece()
	assert_true(build.snapshot() == data.pieces, "Mixed group rotation is atomic")
	build.elevate_selected(0.5)
	assert_true(build.snapshot() == data.pieces, "Mixed group elevation is atomic")
	build.move_selected(true)
	assert_true(build.preview.get_child_count() == 0, "Mixed group duplication blocked")
	build.delete_selected()
	assert_true(build.pieces.size() == 2, "Mixed group deletion blocked")
	build.select(build.pieces[1])
	build.move_selected(true)
	build.preview.position = Vector3(4, 0, 0)
	build.valid = build.snap.validate_group(build.placement_items(), build.preview.transform, build.pieces, build.moving_group).is_empty()
	assert_true(build.valid, "Proposed edit passes real placement validation")
	build.apply_preview()
	build.commit()
	assert_true(build.pieces.size() == 3 and build.rules.remaining("straight", build.snapshot()) == 1, "Duplicating authored editable piece costs inventory")
	build.undo()
	assert_true(build.rules.remaining("straight", build.snapshot()) == 2, "Undo duplication refunds exactly one")
	build.redo()
	build.select(build.pieces[1])
	build.delete_selected()
	assert_true(build.rules.remaining("straight", build.snapshot()) == 1, "Removing authored piece does not manufacture inventory")
	data = session.store.create()
	data.inventory = {"bucket-elevator": 1}
	data.configuration_limits = {"bucket-elevator": {"elevator_height": [4, 4]}}
	session.player(data, true)
	build.choose(workspace.catalog.get_piece("bucket-elevator"))
	build.preview.transform = Transform3D.IDENTITY
	build.valid = build.snap.validate_group(build.placement_items(), build.preview.transform, build.pieces, build.moving_group).is_empty()
	assert_true(build.valid, "Proposed edit passes real placement validation")
	build.apply_preview()
	build.commit()
	build.cancel()
	build.select(build.pieces[0])
	assert_true(not build.configure_selected({"elevator_height": 6, "elevator_speed": 0.8}, "Too tall"), "Inventory elevator height restriction enforced")
	build.rules.puzzle.configuration_limits = {}
	build.rules.puzzle.bounds[5] = 7
	assert_true(not build.configure_selected({"elevator_height": 6, "elevator_speed": 0.8}, "Outside height"), "Configured elevator volume respects elevation boundary")
	session.sandbox()
	build.restore([])
	var source = build.spawn(workspace.catalog.get_piece("sensor"), Transform3D.IDENTITY, "source", {"links": [{"event": "entered", "target": "target", "action": "open"}]})
	var target = build.spawn(workspace.catalog.get_piece("gate"), Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)), "target")
	build.set_selection([source, target])
	build.move_selected(true)
	build.preview.position = Vector3(0, 0, 3)
	build.valid = build.snap.validate_group(build.placement_items(), build.preview.transform, build.pieces, build.moving_group).is_empty()
	assert_true(build.valid, "Proposed edit passes real placement validation")
	build.apply_preview()
	build.commit()
	var duplicate_source = build.pieces[2]
	var duplicate_target = build.pieces[3]
	assert_true(duplicate_source.instance_id != source.instance_id and duplicate_source.configuration.links[0].target == duplicate_target.instance_id, "Duplicate group remaps internal links to fresh IDs")
	build.select(duplicate_target)
	build.delete_selected()
	assert_true(duplicate_source.configuration.links.is_empty() and source.configuration.links.size() == 1, "Deletion cleans only links to the removed target")
	build.undo()
	assert_true(build.pieces.size() == 4 and build.pieces[2].configuration.links.size() == 1, "Undo restores target and link together")
	var serializer = TrackSerializer.new(workspace.catalog)
	var payload = {"version": 1, "name": "Link round trip", "pieces": build.snapshot()}
	assert_true(serializer.decode(JSON.stringify(payload)).pieces == payload.pieces, "Mechanism links survive existing track serializer")
	build.pieces[0].configuration.links[0].action = "unsupported"
	assert_true(not workspace.world.build.validate_wiring().is_empty(), "Unsupported actions are rejected by link validator")

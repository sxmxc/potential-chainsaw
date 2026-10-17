extends GutTest

func test_loading_queue_keeps_capture_through_pause_and_restores_it_on_reset() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autoqfree(viewport)
	var piece := BuildingPiece.new()
	viewport.add_child(piece)
	piece.setup(PieceCatalog.new().get_piece("bucket-elevator"))
	var lift: BucketElevator = piece.behaviors[0]
	lift.set_physics_process(false)
	lift.start_run()
	var bodies: Array[Marble] = []
	for index in 3:
		var body: Marble = load("res://scenes/marble.tscn").instantiate()
		viewport.add_child(body)
		body.gravity_scale = 0
		body.position = Vector3(0, .45, -.3 + index * .05)
		bodies.append(body)
	for frame in 4: await get_tree().physics_frame
	assert_eq(lift.waiting.size(), 3, "The pocket retains bodies after capture disables sensor collision")
	lift.active = false
	for body in bodies:
		assert_true(body.carried)
		assert_true(body.freeze)
	lift.reset()
	for body in bodies:
		assert_false(body.carried)
		assert_false(body.freeze)
		assert_eq(body.collision_layer, 2)
		assert_eq(body.collision_mask, 1)
	assert_true(lift.waiting.is_empty())

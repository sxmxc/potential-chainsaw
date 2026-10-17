extends GutTest

func test_opening_gate_releases_a_marble_resting_across_its_inlet_seam() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autoqfree(viewport)
	var catalog := PieceCatalog.new()
	var gate := BuildingPiece.new()
	gate.position.y = 5
	viewport.add_child(gate)
	gate.setup(catalog.get_piece("gate"))
	var feeder := BuildingPiece.new()
	feeder.position = Vector3(0, 5, 1)
	viewport.add_child(feeder)
	feeder.setup(catalog.get_piece("straight"))
	var body: Marble = load("res://scenes/marble.tscn").instantiate()
	viewport.add_child(body)
	body.position = Vector3(0, 5.45, .53)
	var behavior := gate.behaviors[0]
	behavior.start_run()
	for frame in 12: await get_tree().physics_frame
	behavior.receive("open")
	for frame in 90: await get_tree().physics_frame
	assert_lt(body.position.z, .35, "Opening nudges a stalled inlet marble into the clear channel")

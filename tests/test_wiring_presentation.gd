extends "res://tests/support/game_test.gd"

var workspace: ConstructionWorkspace
var build: BuildManager
var overlay: Control

func before_each() -> void:
	super.before_each()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	add_child_autoqfree(viewport)
	workspace = load("res://scenes/construction_workspace.tscn").instantiate()
	viewport.add_child(workspace)
	await get_tree().process_frame
	build = workspace.world.build
	# Phantom Camera updates the rendered pose later in the frame. Pin a real pose
	# for these projection tests instead of depending on that host's render lifecycle.
	build.camera.set_process(false)
	build.camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	build.camera.global_position = Vector3(9, 10, 13)
	build.camera.look_at(Vector3(1, 1, 0))
	build.camera.force_update_transform()
	overlay = workspace.hud.get_node("%MechanismWiring")
	overlay.exclusions.clear()
	build.spawn(workspace.catalog.get_piece("sensor"), Transform3D.IDENTITY, "sensor")
	build.spawn(workspace.catalog.get_piece("gate"), Transform3D(Basis.IDENTITY, Vector3(3, 1, 0)), "gate")
	assert_true(build.edit_link("sensor", -1, {"event": "entered", "target": "gate", "action": "open"}))
	overlay.set_tool(true)
	overlay._process(0.1)

func test_curve_picking_and_camera_changes_share_cached_world_geometry() -> void:
	assert_eq(overlay.wires.size(), 1)
	var wire: Dictionary = overlay.wires[0]
	var conduit: WiringConduit = wire.visual
	assert_eq(conduit.points[0], overlay.port_world(build.find_piece("sensor"), true))
	assert_eq(conduit.points[-1], overlay.port_world(build.find_piece("gate"), false))
	assert_true(Array(conduit.points).any(func(point: Vector3): return point.y > maxf(conduit.points[0].y, conduit.points[-1].y)))
	assert_eq(overlay.wire_at(wire.points[32]).get("source"), "sensor", "Picking follows the elevated conduit")
	var original_mesh := conduit.mesh
	build.camera.position += Vector3(1, 0, 0)
	build.camera.force_update_transform()
	overlay.refresh_projection()
	assert_same(conduit.mesh, original_mesh, "Orbiting only reprojects picking; it never rebuilds the tube")
	assert_ne(overlay.wires[0].points[32], wire.points[32])

func test_selection_isolates_direct_incoming_and_outgoing_links_and_picking() -> void:
	build.spawn(workspace.catalog.get_piece("sensor"), Transform3D(Basis.IDENTITY, Vector3(0, 1, 4)), "other-sensor")
	build.spawn(workspace.catalog.get_piece("gate"), Transform3D(Basis.IDENTITY, Vector3(4, 1, 4)), "other-gate")
	build.spawn(workspace.catalog.get_piece("straight"), Transform3D(Basis.IDENTITY, Vector3(-3, 0, 0)), "track")
	assert_true(build.edit_link("other-sensor", -1, {"event": "entered", "target": "gate", "action": "open"}))
	assert_true(build.edit_link("other-sensor", -1, {"event": "entered", "target": "other-gate", "action": "open"}))
	overlay.set_tool(false)
	overlay.toggle_overlay()
	overlay._process(0.1)
	assert_eq(overlay.wires.size(), 3)
	var hidden_wire: Dictionary = overlay.wires.filter(func(wire: Dictionary): return wire.target == "other-gate")[0]
	var hidden_visual: WiringConduit = hidden_wire.visual
	build.select(build.find_piece("gate"))
	overlay._process(0.1)
	assert_eq(overlay.wires.size(), 2, "Selecting a receiver includes every incoming link")
	assert_true(overlay.wires.all(func(wire: Dictionary): return wire.target == "gate"))
	assert_false(is_instance_valid(hidden_visual), "Unrelated links have no rendered or occluded trace")
	assert_ne(overlay.wire_at(hidden_wire.points[32]).get("target", ""), "other-gate", "Hidden links cannot be picked")
	assert_false(overlay.terminals.has("other-gate:in"), "Unrelated terminals disappear in Wires view")
	build.select(build.find_piece("sensor"))
	overlay._process(0.1)
	assert_eq(overlay.wires.size(), 1, "Selection follows direct links without expanding through neighbors")
	assert_eq(overlay.wires[0].source, "sensor")
	build.set_selection([build.find_piece("sensor"), build.find_piece("other-gate")])
	overlay._process(0.1)
	assert_eq(overlay.wires.size(), 2, "Group selection combines directly related links")
	build.select(build.find_piece("track"))
	overlay._process(0.1)
	assert_eq(overlay.wires.size(), 3, "Selecting ordinary track restores the network")
	build.select(null)
	overlay._process(0.1)
	assert_eq(overlay.wires.size(), 3)
	assert_eq(build.find_piece("other-sensor").configuration.links.size(), 2, "Isolation never edits saved links")

func test_unconnected_selection_hides_links_but_connect_keeps_available_terminals() -> void:
	build.spawn(workspace.catalog.get_piece("gate"), Transform3D(Basis.IDENTITY, Vector3(5, 1, 0)), "unconnected")
	build.select(build.find_piece("unconnected"))
	overlay._process(0.1)
	assert_true(overlay.wires.is_empty(), "An unconnected functional piece has no related wires")
	assert_true(overlay.terminals.has("gate:in"), "Connect retains other terminals for making new connections")
	assert_true(overlay.terminals.has("sensor:out"))
	overlay.set_tool(false)
	overlay.toggle_overlay()
	overlay._process(0.1)
	assert_true(overlay.terminals.is_empty(), "Wires view shows only terminals used by isolated links")
	build.select(null)
	overlay._process(0.1)
	assert_eq(overlay.wires.size(), 1, "Clearing selection restores existing connections")

func test_remove_undo_and_restoration_do_not_retain_old_visuals() -> void:
	var old_visual: WiringConduit = overlay.wires[0].visual
	assert_true(build.edit_link("sensor", 0))
	overlay._process(0.1)
	assert_true(overlay.wires.is_empty())
	assert_false(is_instance_valid(old_visual))
	build.undo()
	overlay._process(0.1)
	assert_eq(overlay.wires.size(), 1)
	assert_eq(overlay.wires[0].link.action, "open")
	build.restore([])
	overlay._process(0.1)
	assert_true(overlay.wires.is_empty())
	assert_true(overlay.terminals.is_empty(), "Context replacement removes terminals as well as cables")

func test_drag_cancel_visibility_and_reset_keep_presentation_out_of_simulation() -> void:
	overlay.dragging = {"source": "sensor", "output": true}
	overlay.pointer = overlay.port_position(build.find_piece("gate"), false)
	overlay._process(0.1)
	assert_true(overlay.preview_conduit.visible)
	assert_eq(overlay.preview_conduit.points[-1], overlay.port_world(build.find_piece("gate"), false))
	overlay.escape()
	overlay._process(0.1)
	assert_false(overlay.preview_conduit.visible)
	assert_eq(build.find_piece("sensor").configuration.links.size(), 1, "Cancellation leaves saved wiring intact")
	workspace.hud.hide()
	overlay._process(0.1)
	assert_false(overlay.get_node("Network").visible, "3D presentation follows HUD visibility")
	workspace.hud.show()
	workspace.suspend_input()
	overlay._process(0.1)
	assert_false(overlay.get_node("Network").visible)
	workspace.resume_input()
	build.spawn(workspace.catalog.get_piece("sandbox-start"), Transform3D(Basis.IDENTITY, Vector3(6, 2, 0)), "release")
	assert_true(workspace.world.simulation.start())
	overlay._process(0.1)
	assert_false(overlay.get_node("Network").visible)
	workspace.world.simulation.reset()
	overlay._process(0.1)
	assert_true(overlay.get_node("Network").visible)
	assert_true(build.connect_mode)

func test_receiver_snap_requires_pointer_near_the_input_terminal() -> void:
	overlay.dragging = {"source": "sensor", "output": true}
	overlay.refresh_projection()
	var input_point: Vector2 = overlay.port_position(build.find_piece("gate"), false)
	assert_eq(overlay.receiver_at(input_point + Vector2(12, 0)).get("source"), "gate")
	assert_true(overlay.receiver_at(input_point + Vector2(20, 0)).is_empty(), "A nearby terminal cannot pull a distant cursor onto it")
	var bounds := ConstructionSelection.projected_bounds(build.find_piece("gate"), build.camera)
	var corners: Array[Vector2] = [bounds.position, bounds.end, Vector2(bounds.position.x, bounds.end.y), Vector2(bounds.end.x, bounds.position.y)]
	corners.sort_custom(func(a: Vector2, b: Vector2): return a.distance_to(input_point) > b.distance_to(input_point))
	assert_gt(corners[0].distance_to(input_point), 16.0)
	assert_true(overlay.receiver_at(corners[0]).is_empty(), "The piece's projected bounds are not a snap target")

func test_pending_relationship_stays_visible_through_port_choices_and_cancellation() -> void:
	assert_true(build.edit_link("sensor", 0))
	overlay.dragging = {"source": "sensor", "output": true}
	overlay.refresh_projection()
	var input_point: Vector2 = overlay.port_position(build.find_piece("gate"), false)
	overlay.finish_drag(input_point)
	assert_eq(overlay.context_source, "sensor")
	assert_eq(overlay.context_target, "gate")
	assert_true(overlay.dragging.is_empty())
	assert_true(build.find_piece("sensor").configuration.links.is_empty(), "Port choice has not committed a link yet")
	overlay._process(0.1)
	assert_true(overlay.preview_conduit.visible, "Releasing the drag retains a pending conduit behind the card")
	var pending_points: PackedVector3Array = overlay.preview_conduit.points.duplicate()
	overlay.pointer = Vector2(40, 40)
	overlay._process(0.1)
	assert_eq(overlay.preview_conduit.points, pending_points, "Using the port menu does not move the pending endpoints")
	overlay.apply_connection()
	overlay._process(0.1)
	assert_false(overlay.preview_conduit.visible)
	assert_eq(overlay.wires.size(), 1, "Confirm replaces the pending conduit with the saved connection")
	build.undo()
	overlay.open_context("sensor", "gate", "entered", -1, input_point)
	overlay._process(0.1)
	assert_true(overlay.preview_conduit.visible)
	overlay.escape()
	overlay._process(0.1)
	assert_false(overlay.preview_conduit.visible)
	assert_true(build.find_piece("sensor").configuration.links.is_empty(), "Cancel removes the pending conduit without saving")

func test_short_vertical_and_parallel_routes_have_finite_surface_frames() -> void:
	var conduit := WiringConduit.new()
	add_child_autoqfree(conduit)
	for end in [Vector3(0.001, 0, 0), Vector3(0, 5, 0), Vector3(4, -2, 3)]:
		conduit.route(Vector3.ZERO, end, 2)
		var arrays := conduit.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		assert_true(vertices.size() > 0)
		assert_true(Array(vertices).all(func(vertex: Vector3): return vertex.is_finite()))
		assert_true(Array(normals).all(func(normal: Vector3): return normal.is_finite() and normal.length_squared() > 0.99))
	conduit.route(Vector3.ZERO, Vector3(4, 0, 0))
	var first_lane := conduit.points[32]
	conduit.route(Vector3.ZERO, Vector3(4, 0, 0), 1)
	assert_ne(conduit.points[32], first_lane, "Fan-out links separate in elevation and depth")

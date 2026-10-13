extends GutTest

func test_menu_showcase() -> void:
	var showcase=load("res://scenes/showcase.tscn").instantiate()
	add_child_autoqfree(showcase)
	await get_tree().process_frame
	var world=showcase.world_manager
	var sim: SimulationManager=world.simulation
	var lifts: Array=[]
	for piece in world.build.pieces:
		for behavior_node in piece.behaviors:
			if behavior_node is BucketElevator: lifts.append(behavior_node)
	var baseline: Array=world.build.snapshot()
	for trial in 2:
		var captures: Dictionary={}
		var branches: Dictionary={}
		var callback: Callable=func(event, body):
			if event == "loaded": captures[body.get_instance_id()]=int(captures.get(body.get_instance_id(),0))+1
		for lift in lifts: lift.output_raised.connect(callback)
		showcase.set_active(true)
		var initial_loops: int=showcase.loops
		for frame in 120*180:
			await get_tree().physics_frame
			for body in sim.marbles:
				if absf(body.position.z)>9: branches[body.get_instance_id()]=true
		assert_true(sim.state==SimulationManager.State.RUNNING and showcase.loops==initial_loops,"Machine circulates for three minutes without failure/restart, trial %d" % trial)
		assert_true(sim.marbles.size()==12 and world.build.pieces.all(func(piece): return piece.behaviors.all(func(behavior_node): return not behavior_node is MarbleRelease or behavior_node.pending_releases.is_empty())),"Both sources release all twelve marbles")
		assert_true(captures.size()==12,"Every marble enters an elevator")
		for count in captures.values(): assert_true(count>=3,"Each marble completes at least two return circuits")
		assert_true(branches.size()>=6,"Multiple marbles take the alternate perimeter routes")
		print("SHOWCASE trial %d: captures=%s alternate marbles=%d" % [trial,captures.values(),branches.size()])
		showcase.set_active(false)
		for lift in lifts:
			lift.output_raised.disconnect(callback)
			assert_true(lift.waiting.is_empty() and not lift.active,"Leaving the menu clears capture state")
		assert_true(sim.marbles.is_empty(),"Leaving the menu clears all marbles")
		assert_true(world.build.snapshot()==baseline,"Reset preserves the authored machine")
		await get_tree().process_frame
	showcase.queue_free()
	await get_tree().process_frame

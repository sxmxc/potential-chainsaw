extends SceneTree

const Cleanup = preload("res://tests/cleanup.gd")
var failures: Array[String]=[]
var checks: int=0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var showcase=load("res://scenes/showcase.tscn").instantiate()
	root.add_child(showcase)
	await process_frame
	var world=showcase.world_manager
	var sim: SimulationManager=world.simulation
	var lifts: Array=[]
	for piece in world.build.pieces:
		if piece.elevator_component: lifts.append(piece.elevator_component)
	var baseline: Array=world.build.snapshot()
	for trial in 2:
		var captures: Dictionary={}
		var branches: Dictionary={}
		var callback: Callable=func(body): captures[body.get_instance_id()]=int(captures.get(body.get_instance_id(),0))+1
		for lift in lifts: lift.marble_loaded.connect(callback)
		showcase.set_active(true)
		var initial_loops: int=showcase.loops
		for frame in 120*180:
			await physics_frame
			for body in sim.marbles:
				if absf(body.position.z)>9: branches[body.get_instance_id()]=true
		check(sim.state==SimulationManager.State.RUNNING and showcase.loops==initial_loops,"Machine circulates for three minutes without failure/restart, trial %d" % trial)
		check(sim.marbles.size()==12 and sim.pending_releases.is_empty(),"Both sources release all twelve marbles")
		check(captures.size()==12,"Every marble enters an elevator")
		for count in captures.values(): check(count>=3,"Each marble completes at least two return circuits")
		check(branches.size()>=6,"Multiple marbles take the alternate perimeter routes")
		print("SHOWCASE trial %d: captures=%s alternate marbles=%d" % [trial,captures.values(),branches.size()])
		showcase.set_active(false)
		for lift in lifts:
			lift.marble_loaded.disconnect(callback)
			check(lift.waiting.is_empty() and not lift.active,"Leaving the menu clears capture state")
		check(sim.marbles.is_empty(),"Leaving the menu clears all marbles")
		check(world.build.snapshot()==baseline,"Reset preserves the authored machine")
		await process_frame
	showcase.queue_free()
	await process_frame
	await Cleanup.stop_audio(self)
	print("SHOWCASE RESULT: %d checks; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

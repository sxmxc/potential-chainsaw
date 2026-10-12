extends SceneTree

var game: Node
var failures: Array[String] = []
var report: Array[String] = []
var verified: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	var selected_names: Array[String] = []
	for filename in DirAccess.get_files_at("res://resources/campaign"):
		if not filename.ends_with(".json"): continue
		if "--level10" in OS.get_cmdline_user_args() and not filename.begins_with("10-"): continue
		var path = "res://resources/campaign/" + filename
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		selected_names.append(data.name)
		var level_failures = failures.size()
		session.player(data, true)
		for record in data.solution:
			var existing: TrackPiece
			for piece in build.pieces:
				if piece.instance_id == record.uid: existing = piece; break
			if existing:
				if existing.configuration != record.config:
					build.select(existing)
					if not build.configure_selected(record.config, "Reference configuration"): failures.append(data.name + ": reference configuration rejected")
			else:
				build.choose(game.catalog.get_piece(record.piece))
				if not build.ghost: failures.append(data.name + ": reference inventory rejected"); continue
				build.ghost.apply_configuration(record.config)
				build.preview_items[0].config = build.ghost.configuration.duplicate(true)
				build.preview_items[0].definition = build.ghost.definition
				build.proposed = Transform3D(Basis(Vector3.UP, int(record.rotation) * PI / 2), Vector3(record.position[0], record.position[1], record.position[2]))
				build.valid = build.snap.validate_group(build.preview_items, build.proposed, build.pieces).is_empty()
				build.ghost.visible = true
				if not build.valid: failures.append(data.name + ": reference placement rejected " + record.piece)
				build.commit()
				build.cancel()
		var error = build.rules.validate(build.snapshot())
		if not error.is_empty(): failures.append(data.name + ": " + error)
		var solution = build.snapshot()
		if not game.qa_test(): failures.append(data.name + ": simulation rejected"); continue
		for frame in int(float(data.time_limit) * 120 + 5):
			await physics_frame
			if "--trace" in OS.get_cmdline_user_args() and frame % 60 == 0 and game.sandbox.simulation.marble:
				var ball = game.sandbox.simulation.marble
				print("TRACE ", frame, " ", ball.position, " ", ball.linear_velocity)
			if game.sandbox.simulation.state in [SimulationManager.State.SUCCESS, SimulationManager.State.FAILED]: break
		var success = game.sandbox.simulation.state == SimulationManager.State.SUCCESS
		var line = "%02d %s: %s at %.2fs, marble %s" % [data.order, data.name, "PASS" if success else "FAIL", game.sandbox.simulation.elapsed, str(game.sandbox.simulation.marble.position)]
		print(line)
		if data.order == 10: print("ACTIVATIONS ",game.sandbox.simulation.objectives.activations)
		report.append(line)
		if success:
			data.pieces = session.puzzle.pieces
			data.solution = solution
			data.validation = {"physics_success": true, "fingerprint": session.store.fingerprint(data), "seconds": game.sandbox.simulation.elapsed, "engine": Engine.get_version_info().string, "tested_at": Time.get_datetime_string_from_system(true)}
			if "--publish-verified" in OS.get_cmdline_user_args() and failures.size() == level_failures:
				data.status = "published"
				verified.append({"path": path, "data": data})
		else: failures.append(data.name + ": physical solution failed")
		game.sandbox.simulation.reset()
		if build.snapshot() != solution: failures.append(data.name + ": reset changed construction")
		if "--negative" in OS.get_cmdline_user_args():
			session.player(data, true)
			game.qa_test()
			for frame in int(float(data.time_limit) * 120 + 5):
				await physics_frame
				if game.sandbox.simulation.state in [SimulationManager.State.SUCCESS, SimulationManager.State.FAILED]: break
			var incomplete_fails = game.sandbox.simulation.state != SimulationManager.State.SUCCESS
			print("INCOMPLETE ", data.name, ": ", "PASS" if incomplete_fails else "FAIL")
			if not incomplete_fails: failures.append(data.name + ": starting layout already succeeds")
			game.sandbox.simulation.reset()
	if failures.is_empty():
		for entry in verified:
			if not session.store.write(entry.path, entry.data): failures.append("Could not publish " + entry.path)
	var file = FileAccess.open("res://docs/campaign_results.txt", FileAccess.WRITE)
	file.store_string("\n".join(report) + "\nFailures: " + str(failures.size()) + "\n" + "\n".join(failures))
	print("CAMPAIGN FAILURES: ", failures.size())
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

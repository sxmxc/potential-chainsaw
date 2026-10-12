extends SceneTree

const Cleanup = preload("res://tests/cleanup.gd")

var failures: Array[String] = []
var checks: int = 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func item(id: String, uid: String, z: float, turn: int = 0) -> Dictionary:
	return {"piece": id, "uid": uid, "position": [0.0, 0.0, z], "rotation": turn, "config": {}}

func place(build: BuildManager, id: String, at: Vector3) -> void:
	build.choose(game.catalog.get_piece(id))
	if not build.ghost: return
	build.proposed = Transform3D(Basis.IDENTITY, at)
	build.valid = true
	build.ghost.visible = true
	build.commit()
	build.cancel()

func run() -> void:
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var session: PuzzleSession = game.puzzle_session
	var build: BuildManager = game.sandbox.build
	var data = session.store.create()
	data.id = "qa-puzzle-workflow"
	data.pieces = [item("sandbox-start", "start", 2), item("straight", "approach", 1), item("straight", "exit", -1), item("sandbox-finish", "finish", -2, 2)]
	data.inventory = {"straight": 1}
	data.objectives = [{"type": "deliver", "target": "finish", "count": 1}]
	data.bounds = [-2, -3, 2, 3, 0, 2]
	session.editor(data)
	check(session.mode == "editor" and build.rules == null, "Editor uses unrestricted existing construction")
	build.select(build.pieces[0])
	session.set_permissions({"move": false, "rotate": false, "configure": true, "remove": false, "duplicate": false, "config_keys": ["release_speed"], "limits": {"release_speed": [0.5, 2.0]}})
	game.authoring.open()
	check(game.authoring.visible, "Complete native visual authoring panel opens")
	game.authoring.hide()
	check(session.save(), "Draft saves outside sandbox track storage")
	var original = session.capture()
	check(not session.publish(), "Publishing an untested revision is rejected")
	game.message_dialog.close()
	check(session.test_player(), "Test as Player enters restricted session")
	check(build.rules != null and session.mode == "test", "Campaign restrictions active in test")
	var first = build.pieces[0]
	build.select(first)
	build.move_selected()
	check(build.ghost == null, "Fixed piece drag blocked")
	build.rotate_piece()
	check(first.rotation.y == 0, "Fixed piece rotation blocked")
	build.delete_selected()
	check(build.pieces.size() == 4, "Fixed deletion blocked")
	build.move_selected(true)
	check(build.ghost == null, "Fixed duplication blocked")
	var config = first.configuration.duplicate(true)
	config.release_speed = 3
	check(not build.configure_selected(config, "Forbidden setting"), "Mechanism configuration range enforced")
	config.release_speed = 1.5
	check(build.configure_selected(config, "Allowed setting"), "Fixed release allows permitted setting")
	place(build, "straight", Vector3(5, 0, 0))
	check(build.pieces.size() == 4, "Out-of-bounds placement rolls back atomically")
	place(build, "straight", Vector3.ZERO)
	check(build.pieces.size() == 5 and build.rules.remaining("straight", build.snapshot()) == 0, "Normal placement consumes inventory")
	build.choose(game.catalog.get_piece("straight"))
	check(build.ghost == null, "Inventory exhaustion blocks further placement")
	build.undo()
	check(build.pieces.size() == 4 and build.rules.remaining("straight", build.snapshot()) == 1, "Undo restores inventory")
	build.redo()
	check(build.pieces.size() == 5 and build.rules.remaining("straight", build.snapshot()) == 0, "Redo consumes inventory")
	build.select(build.pieces[-1])
	build.delete_selected()
	check(build.rules.remaining("straight", build.snapshot()) == 1, "Removing player piece restores inventory")
	build.undo()
	check(game.qa_test(), "Player solution starts actual physics")
	for frame in 1500:
		await physics_frame
		if game.sandbox.simulation.state in [SimulationManager.State.SUCCESS, SimulationManager.State.FAILED]: break
	check(game.sandbox.simulation.state == SimulationManager.State.SUCCESS, "Objectives detect physical collector arrival")
	check(session.preserve_solution(), "Successful player solution preserved separately")
	check(session.authored.pieces == original.pieces and session.authored.solution.size() == 5, "Solution never overwrites starting construction")
	session.return_editor()
	check(build.snapshot() == original.pieces and session.mode == "editor", "Returning from test restores authored layout")
	check(session.publish(), "Verified revision publishes")
	var levels = session.store.list_puzzles()
	check(levels.any(func(level): return level.id == data.id), "Published content appears in campaign")
	session.player(session.puzzle)
	place(build, "straight", Vector3.ZERO)
	check(game.qa_test(), "Published level runs in Campaign")
	for frame in 1500:
		await physics_frame
		if game.sandbox.simulation.state in [SimulationManager.State.SUCCESS, SimulationManager.State.FAILED]: break
	check(game.sandbox.simulation.state == SimulationManager.State.SUCCESS and session.store.progress.has(data.id), "Campaign completion records progress")
	var reopened = PuzzleStore.new(game.catalog)
	check(reopened.progress.has(data.id), "Progress persists across store reload")
	session.return_editor()
	session.editor(original)
	session.puzzle.description = "Revised"
	check(not session.publish(), "Content edit invalidates working solution proof")
	game.message_dialog.close()
	for path in [PuzzleStore.DRAFTS + "/" + data.id + ".json", PuzzleStore.PUBLISHED + "/" + data.id + ".json"]: DirAccess.remove_absolute(path)
	session.store.progress.erase(data.id)
	session.store.write(PuzzleStore.PROGRESS, session.store.progress)
	print("PUZZLE WORKFLOW: ", checks, " checks, ", failures.size(), " failures")
	game.queue_free()
	await process_frame
	await Cleanup.stop_audio(self)
	quit(0 if failures.is_empty() else 1)

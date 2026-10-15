extends "res://tests/support/scene_test.gd"

func test_community_author_publish_share_import_and_play() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	await get_tree().process_frame
	var session: ConstructionSession = game.workspace.session
	var data := session.store.create()
	data.creator = "GUT fixture"
	data.environment_instances = [{"uid": "scenery", "asset": "column", "position": [5, 0, 0], "rotation": 0}]
	data.pieces = [
		{"piece": "sandbox-start", "uid": "start", "position": [0, 0, 2], "rotation": 0, "config": {}},
		{"piece": "straight", "uid": "approach", "position": [0, 0, 1], "rotation": 0, "config": {}},
		{"piece": "straight", "uid": "bridge", "position": [0, 0, 0], "rotation": 0, "config": {}},
		{"piece": "straight", "uid": "exit", "position": [0, 0, -1], "rotation": 0, "config": {}},
		{"piece": "sandbox-finish", "uid": "finish", "position": [0, 0, -2], "rotation": 2, "config": {}}
	]
	data.objectives = [{"type": "deliver", "target": "finish", "count": 1}]
	session.editor(data)
	game.workspace.authoring.open()
	assert_false(game.workspace.authoring.get_node("%ChapterId").visible)
	assert_eq(game.workspace.authoring.get_node("%Publish").text, "Publish locally")
	game.workspace.authoring.hide()
	assert_false(session.publish(), "A player test is required")
	game.message_dialog.close()
	assert_true(session.test_player())
	assert_true(game.workspace.world.simulation.start())
	await wait_until(func(): return game.workspace.world.simulation.state == SimulationManager.State.SUCCESS, 12.0)
	assert_true(session.preserve_solution(), "Real physics supplies the validation proof")
	session.return_editor()
	assert_true(session.validate().is_empty())
	var fingerprint := session.store.fingerprint(session.capture())
	# Choosing a destination changes registration, never the tested gameplay.
	game.workspace.authoring.open()
	game.workspace.authoring.get_node("%Destination").item_selected.emit(1)
	assert_true(session.official_authoring)
	assert_eq(session.store.fingerprint(session.capture()), fingerprint)
	game.workspace.authoring.get_node("%Destination").item_selected.emit(0)
	assert_false(session.official_authoring)
	game.workspace.authoring.hide()
	assert_true(session.publish())
	assert_false(session.store.load_campaign().levels.any(func(item): return item.id == data.id))
	var portable := test_directory.path_join("shared.json")
	game.workspace.authoring.get_node("%ExportDialog").file_selected.emit(portable)
	var shared: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(portable))
	assert_false(shared.has("campaign"))
	assert_false(shared.has("chapter"))
	assert_eq(shared.creator, "GUT fixture")
	assert_has(shared.required_assets, "straight")
	assert_has(shared.required_assets, "environment:column")
	var official_progress := session.progress.records.duplicate(true)
	var official_state := session.progress.route.duplicate(true)
	# A receiving installation with isolated library directories.
	session.store.community_directory = test_directory.path_join("receiver/community")
	session.store.published_directory = test_directory.path_join("receiver/published")
	session.store.drafts_directory = test_directory.path_join("receiver/drafts")
	for path in [session.store.community_directory, session.store.published_directory, session.store.drafts_directory]: DirAccess.make_dir_recursive_absolute(path)
	# Forged official provenance and an official ID cannot grant campaign privileges.
	shared.id = "campaign-01"
	shared.campaign = {"chapter": {"id": "introduction"}}
	shared._source = "campaign"
	shared.validation.fingerprint = session.store.fingerprint(shared)
	assert_eq(SaveStorage.write_json(portable, shared), "")
	var installed := session.store.import_puzzle(portable)
	assert_false(installed.is_empty())
	assert_eq(installed.id, "campaign-01")
	assert_false(PuzzleStore.is_official(installed))
	var browser: Window = game.get_node("%PuzzleBrowser")
	browser.open(false, true)
	assert_true(browser.community and browser.get_node("%Import").visible)
	assert_false(browser.get_node("%Resume").visible)
	browser.get_node("%Levels").select(0)
	browser.get_node("%Open").pressed.emit()
	assert_eq(session.puzzle.id, installed.id)
	assert_not_null(session.environment_node, "Imported catalog scenery loads through the shared environment path")
	assert_true(game.workspace.world.simulation.start())
	await wait_until(func(): return game.workspace.world.simulation.state == SimulationManager.State.SUCCESS, 12.0)
	assert_eq(game.workspace.world.simulation.state, SimulationManager.State.SUCCESS)
	assert_true(session.progress.community_records[installed.id].completed)
	assert_eq(session.progress.records, official_progress)
	assert_eq(session.progress.route, official_state)
	assert_false(game.get_node("%PuzzleCompletion").get_node("%Next").visible)
	assert_true(PuzzleProgress.new(session.store.load_campaign()).community_records[installed.id].completed)
	assert_almost_eq(float(PuzzleProgress.new(session.store.load_campaign()).community_records[installed.id].best_time), float(session.progress.community_records[installed.id].best_time), 0.00001)
	assert_false(session.store.import_puzzle(portable).is_empty(), "Identical reimport is safe")
	shared.name = "Conflicting puzzle"
	shared.validation.fingerprint = session.store.fingerprint(shared)
	assert_eq(SaveStorage.write_json(portable, shared), "")
	assert_true(session.store.import_puzzle(portable).is_empty(), "Conflicting identity never overwrites installed content")
	assert_eq(session.store.list_community()[0].name, data.name)

func test_campaign_promotion_preserves_unlocks_and_rejects_stale_revisions() -> void:
	var store := PuzzleStore.new(PieceCatalog.new())
	var progress := PuzzleProgress.new(store.load_campaign())
	var data :Dictionary= store.load_campaign().levels.filter(func(item): return item.id == "campaign-01")[0]
	store.campaign_directory = test_directory.path_join("project/campaign")
	store.manifest_path = test_directory.path_join("project/manifest.json")
	store.chapters_path = test_directory.path_join("project/chapters.json")
	DirAccess.make_dir_recursive_absolute(store.campaign_directory)
	assert_eq(SaveStorage.write_json(store.chapters_path, {"version": 1, "chapters": []}), "")
	data.campaign = {"chapter": {"id": "new-chapter", "name": "Machines", "order": 2, "prerequisites": ["required-level"]}, "order": 1, "prerequisites": ["required-level"]}
	assert_true(store.add_to_campaign(data))
	var levels := store.load_campaign().levels
	assert_eq(levels.size(), 1)
	assert_false(store.load_campaign().unlocked(levels[0], progress.records))
	assert_eq(levels[0].campaign.prerequisites, ["required-level"])
	progress.records["required-level"] = {"completed": true}
	assert_true(store.load_campaign().unlocked(levels[0], progress.records))
	assert_true(store.add_to_campaign(data), "Identical promotion is idempotent")
	assert_eq(store.load_campaign().levels.size(), 1)
	var original := FileAccess.get_file_as_bytes(store.campaign_directory.path_join(data.id + ".json"))
	var chapters_before := FileAccess.get_file_as_bytes(store.chapters_path)
	var manifest_before := FileAccess.get_file_as_bytes(store.manifest_path)
	assert_eq(DirAccess.make_dir_absolute(store.chapters_path + ".tmp"), OK)
	assert_false(store.add_to_campaign(data), "Failure after writing content rolls back publication")
	assert_false(store.last_error.is_empty())
	assert_eq(FileAccess.get_file_as_bytes(store.campaign_directory.path_join(data.id + ".json")), original)
	assert_eq(FileAccess.get_file_as_bytes(store.chapters_path), chapters_before)
	assert_eq(FileAccess.get_file_as_bytes(store.manifest_path), manifest_before)
	assert_eq(DirAccess.remove_absolute(store.chapters_path + ".tmp"), OK)
	data.name = "Conflicting revision"
	assert_false(store.add_to_campaign(data))
	assert_eq(FileAccess.get_file_as_bytes(store.campaign_directory.path_join(data.id + ".json")), original)
	assert_eq(store.load_campaign().levels.size(), 1)

func test_unsafe_and_malformed_imports_are_rejected_before_resource_loading() -> void:
	var store := PuzzleStore.new(PieceCatalog.new())
	var safe := store.playable_content(store.load_campaign().levels.filter(func(item): return item.id == "campaign-01")[0])
	var path := test_directory.path_join("unsafe.json")
	var variants: Array[Dictionary] = []
	var scene := safe.duplicate(true)
	scene.environment_snapshot = "user://evil.tscn"
	variants.append(scene)
	scene = safe.duplicate(true)
	scene.environment_instances = [{"uid": "scene", "scene": "res://scenes/main.tscn", "position": [0, 0, 0], "rotation": 0}]
	variants.append(scene)
	scene = safe.duplicate(true)
	scene.pieces[0].piece = "environment_scene:res://scenes/main.tscn"
	variants.append(scene)
	scene = safe.duplicate(true)
	scene.id = "../escape"
	variants.append(scene)
	scene = safe.duplicate(true)
	scene.objectives = ["invalid"]
	variants.append(scene)
	scene = safe.duplicate(true)
	scene.permissions = {"start": {"limits": {"release_speed": ["bad", 2]}}}
	variants.append(scene)
	scene = safe.duplicate(true)
	scene.inventory = {"environment_scene:res://scenes/environments/service_block.tscn": 1}
	variants.append(scene)
	scene = safe.duplicate(true)
	scene.pieces[0].config.display_label = ["bad"]
	variants.append(scene)
	for invalid in variants:
		assert_eq(SaveStorage.write_json(path, invalid), "")
		assert_true(store.import_puzzle(path).is_empty())
		assert_false(store.last_error.is_empty())
	assert_true(store.list_community().is_empty())

func test_registration_owns_metadata_and_local_files_cannot_override_campaign() -> void:
	var store := PuzzleStore.new(PieceCatalog.new())
	var official :Dictionary= store.load_campaign().levels.filter(func(item): return item.id == "campaign-01")[0]
	assert_true(PuzzleStore.is_official(official))
	assert_false(official.has("prerequisites"))
	assert_false(official.has("chapter"))
	assert_eq(store.load_campaign().chapter_for(official).id, "introduction")
	var forged := store.playable_content(official)
	forged.name = "Community copy"
	forged._source = "campaign"
	assert_eq(SaveStorage.write_json(store.published_directory.path_join(official.id + ".json"), forged), "")
	assert_eq(store.load_campaign().levels.filter(func(item): return item.id == "campaign-01")[0].name, official.name)
	assert_false(PuzzleStore.is_official(store.list_community()[0]))

func test_record_validation_preserves_drafts_and_checks_distributed_solutions() -> void:
	var store := PuzzleStore.new(PieceCatalog.new())
	var data: Dictionary = store.load_campaign().levels.filter(func(item): return item.id == "campaign-01")[0]
	var original := data.duplicate(true)
	assert_true(PuzzleRules.definition_errors(data, store.catalog, true).is_empty(), "The saved reference obeys the puzzle rules")
	assert_false(DirAccess.dir_exists_absolute(SaveStorage.resolve("user://tracks")), "Puzzle validation does not initialize personal-track storage")
	assert_eq(data, original, "Validation must not normalize or rewrite authored records")
	data.solution[0].position[0] += 10
	assert_true(PuzzleRules.definition_errors(data, store.catalog).is_empty(), "An obsolete reference does not prevent editing and retesting a draft")
	assert_false(store.publication_errors(data).is_empty(), "Distribution rejects a reference that moves a fixed piece")
	assert_eq(data.solution[0].position[0], original.solution[0].position[0] + 10)
	for records in ["pieces", "solution"]:
		var invalid := original.duplicate(true)
		invalid[records][0].piece = "environment:column"
		assert_false(PuzzleRules.definition_errors(invalid, store.catalog).is_empty(), "Scenery cannot enter track records: " + records)
		invalid = original.duplicate(true)
		invalid[records][0].position[0] = 1001
		assert_false(PuzzleRules.definition_errors(invalid, store.catalog).is_empty(), "Coordinate limits apply to both layouts: " + records)
		invalid = original.duplicate(true)
		invalid[records][0].config.release_speed = "invalid"
		assert_false(PuzzleRules.definition_errors(invalid, store.catalog).is_empty(), "Release speed must remain numeric: " + records)
	var game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	await get_tree().process_frame
	var session: ConstructionSession = game.workspace.session
	session.editor(data)
	assert_true(session.validate(false).is_empty(), "The editor can retest a draft with an obsolete reference")
	assert_eq(session.validate(), store.publication_errors(session.capture()), "Editor validation uses the publisher's solution and proof gate")

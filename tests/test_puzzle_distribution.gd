extends "res://tests/support/game_test.gd"

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

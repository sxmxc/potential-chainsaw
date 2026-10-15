extends "res://tests/support/scene_test.gd"

func test_campaign_chapters() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	await get_tree().process_frame
	var browser: Window = game.get_node("%PuzzleBrowser")
	var authoring: PanelContainer = game.get_node("Workspace/Interface/HUD/Margin/Layout/Body/AuthoringSlot/PuzzleAuthoring")
	var store: PuzzleStore = game.workspace.session.store
	var progress: PuzzleProgress = game.workspace.session.progress
	progress.records = {}
	progress.route = {}
	var definition := store.load_campaign()
	var levels := definition.levels
	assert_true(levels.size() == 14, "All preserved published levels")
	for data in levels.filter(func(item): return item.id.begins_with("campaign-")):
		assert_true(definition.chapter_for(data).id == "introduction", "Stable introduction membership: " + data.id)
		assert_true(definition.unlocked(data, progress.records), "Introduction independently playable: " + data.id)
		assert_true(data.validation.fingerprint == store.fingerprint(data), "Known-good fingerprint retained: " + data.id)
	var chapters = definition.chapters
	assert_true(chapters.size() == 2 and chapters[0].optional and not chapters[1].optional, "Optional Introduction and separate Chapter 1")
	assert_true(definition.chapter_unlocked(chapters[1], progress.records), "Chapter 1 available without Introduction")
	browser.open_campaign()
	assert_true(browser.get_node("%StartChoice").visible, "Fresh campaign offers introduction choice")
	browser.get_node("%SkipIntroduction").pressed.emit()
	assert_true(progress.route.introduction_skipped and progress.records.is_empty(), "Skipping records choice without completion")
	assert_true(progress.route.current_chapter == "chapter-1", "Skipping enters Chapter 1")
	browser.open()
	assert_true(not browser.get_node("%StartChoice").visible, "Existing campaign hides choice")
	assert_true(browser.get_node("%Levels").item_count == 4, "Main chapter retains its own published puzzles")
	var target = progress.start_campaign(definition, true)
	assert_true(target.id == "campaign-01", "Play Introduction starts at Level 1")
	game.workspace.session.player(target)
	var reopened = PuzzleProgress.new(definition)
	assert_true(definition.resume_level(reopened.route, reopened.records).id == target.id, "Current campaign resumes after reload")
	browser.open()
	browser.show_chapter(0)
	assert_true(browser.get_node("%Levels").item_count == 10, "Level Select shows all ten introduction puzzles")
	var main1 = {"id": "qa-main-1", "order": 1, "prerequisites": ["campaign-10"], "chapter": {"id": "chapter-1", "name": "Chapter 1", "order": 1}}
	var main2 = {"id": "qa-main-2", "order": 2, "prerequisites": [], "chapter": main1.chapter}
	var future = {"id": "qa-future", "order": 1, "prerequisites": [], "chapter": {"id": "chapter-2", "name": "Chapter 2", "order": 2, "optional": false, "prerequisites": ["qa-main-2"]}}
	for item in [main1, main2, future]: item._source = "campaign"
	var mixed: Array = levels.filter(func(item): return item.id.begins_with("campaign-"))
	mixed.append_array([main1, main2, future])
	var mixed_definition := CampaignDefinition.new(store.base_chapters(), mixed)
	assert_true(mixed_definition.unlocked(main1, progress.records), "Legacy tutorial prerequisite never gates main entry")
	assert_true(not mixed_definition.unlocked(main2, progress.records), "Main levels retain their own sequence")
	assert_true(mixed_definition.chapters.size() == 3, "Future chapter discovered from puzzle metadata")
	assert_true(not mixed_definition.unlocked(future, progress.records), "Future chapter requirements enforced")
	progress.records[main1.id] = {"completed": true}
	assert_true(mixed_definition.unlocked(main2, progress.records), "Main completion unlocks next main puzzle")
	progress.records[main2.id] = {"completed": true}
	assert_true(mixed_definition.unlocked(future, progress.records), "Future chapter unlocks on main completion")
	var records: Dictionary = {}
	var route := {"current_chapter": "chapter-1", "current_level": ""}
	assert_eq(mixed_definition.resume_level(route, records).id, main1.id, "Main route starts independently of Introduction")
	var final_intro: Dictionary = levels.filter(func(item): return item.id == "campaign-10")[0]
	records[final_intro.id] = {"completed": true}
	assert_eq(mixed_definition.next_step(final_intro, records).level.id, main1.id, "Final Introduction puzzle joins main Level 1")
	records[main1.id] = {"completed": true}
	assert_eq(mixed_definition.next_step(main1, records).level.id, main2.id, "Main completion advances within the chapter")
	records[main2.id] = {"completed": true}
	assert_eq(mixed_definition.next_step(main2, records).level.id, future.id, "Main completion advances into the future chapter")
	records[future.id] = {"completed": true}
	assert_true(mixed_definition.next_step(future, records).level.is_empty(), "Finished campaign has no next puzzle")
	assert_eq(route, {"current_chapter": "chapter-1", "current_level": ""}, "Navigation queries leave route state untouched")
	progress.records.clear()
	for data in levels.filter(func(item): return item.id.begins_with("campaign-")): progress.complete(data, 12, 6, definition)
	assert_true(progress.route.current_chapter == "chapter-1", "Completing Introduction enters Chapter 1")
	assert_true(definition.chapter_progress("introduction", progress.records).completed == 10 and definition.chapter_progress("chapter-1", progress.records).completed == 0, "Tutorial and main progress counted separately")
	var legacy = {"campaign-01": {"completed": true, "revision": 1, "best_time": 3.5, "fewest_pieces": 4, "awards": ["time"], "custom_record": "preserve"}}
	assert_eq(SaveStorage.write_json(progress.progress_path, legacy), "")
	DirAccess.remove_absolute(progress.campaign_state_path)
	reopened = PuzzleProgress.new(definition)
	assert_true(JSON.stringify(reopened.records) == JSON.stringify(JSON.parse_string(JSON.stringify(legacy))), "Legacy save migration preserves every record field")
	assert_true(reopened.route.started and definition.resume_level(reopened.route, reopened.records).id == "campaign-02", "Legacy partial campaign resumes without new-player choice")
	reopened.complete(levels.filter(func(item): return item.id == "campaign-01")[0], 5, 7, definition)
	assert_true(reopened.records["campaign-01"].best_time == 3.5 and reopened.records["campaign-01"].custom_record == "preserve" and "time" in reopened.records["campaign-01"].awards, "Recompletion preserves best results, awards, and extra fields")
	var authored = store.create()
	game.workspace.session.editor(authored, true)
	authoring.open()
	authoring.get_node("%ChapterId").text = "chapter-3"
	authoring.get_node("%ChapterName").text = "Machines"
	authoring.get_node("%ChapterOrder").value = 3
	authoring.get_node("%ChapterRequirements").text = "qa-main-2"
	authoring.update_chapter()
	assert_true(game.workspace.session.puzzle.campaign.chapter.id == "chapter-3" and game.workspace.session.puzzle.campaign.chapter.prerequisites == ["qa-main-2"], "Editor configures new chapter and unlock requirements")

extends "res://tests/support/scene_test.gd"

class FixtureStore extends PuzzleStore:
	var fixture_levels: Array[Dictionary] = []
	func list_puzzles(drafts: bool = false) -> Array[Dictionary]:
		return super.list_puzzles(drafts) if fixture_levels.is_empty() or drafts else fixture_levels

func test_campaign_chapters() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1280, 720)
	await get_tree().process_frame
	var browser: Window = game.get_node("%PuzzleBrowser")
	var authoring: PanelContainer = game.get_node("%HUD").get_node("%PuzzleAuthoring")
	var store: PuzzleStore = game.puzzle_session.store
	store.progress = {}
	store.campaign = {}
	var levels = store.list_puzzles()
	assert_true(levels.size() == 10, "Ten preserved published levels")
	for data in levels:
		assert_true(store.chapter_for(data).id == "introduction", "Stable introduction membership: " + data.id)
		assert_true(store.unlocked(data, levels), "Introduction independently playable: " + data.id)
		assert_true(data.validation.fingerprint == store.fingerprint(data), "Known-good fingerprint retained: " + data.id)
	var chapters = store.list_chapters(levels)
	assert_true(chapters.size() == 2 and chapters[0].optional and not chapters[1].optional, "Optional Introduction and separate Chapter 1")
	assert_true(store.chapter_unlocked(chapters[1]), "Chapter 1 available without Introduction")
	browser.open_campaign()
	assert_true(browser.get_node("%StartChoice").visible, "Fresh campaign offers introduction choice")
	browser.get_node("%SkipIntroduction").pressed.emit()
	assert_true(store.campaign.introduction_skipped and store.progress.is_empty(), "Skipping records choice without completion")
	assert_true(store.campaign.current_chapter == "chapter-1", "Skipping enters empty Chapter 1")
	assert_true(not browser.get_node("%StartChoice").visible, "Existing campaign hides choice")
	assert_true(browser.get_node("%Levels").item_count == 0, "Main chapter does not reuse tutorial puzzles")
	var target = store.start_campaign(true)
	assert_true(target.id == "campaign-01", "Play Introduction starts at Level 1")
	game.puzzle_session.player(target)
	var reopened = PuzzleStore.new(game.catalog)
	assert_true(reopened.resume_level().id == target.id, "Current campaign resumes after reload")
	browser.open()
	browser.show_chapter(0)
	assert_true(browser.get_node("%Levels").item_count == 10, "Level Select shows all ten introduction puzzles")
	var main1 = {"id": "qa-main-1", "order": 1, "prerequisites": ["campaign-10"], "chapter": {"id": "chapter-1", "name": "Chapter 1", "order": 1}}
	var main2 = {"id": "qa-main-2", "order": 2, "prerequisites": [], "chapter": main1.chapter}
	var future = {"id": "qa-future", "order": 1, "prerequisites": [], "chapter": {"id": "chapter-2", "name": "Chapter 2", "order": 2, "optional": false, "prerequisites": ["qa-main-2"]}}
	var mixed: Array = levels.duplicate()
	mixed.append_array([main1, main2, future])
	assert_true(store.unlocked(main1, mixed), "Legacy tutorial prerequisite never gates main entry")
	assert_true(not store.unlocked(main2, mixed), "Main levels retain their own sequence")
	assert_true(store.list_chapters(mixed).size() == 3, "Future chapter discovered from puzzle metadata")
	assert_true(not store.unlocked(future, mixed), "Future chapter requirements enforced")
	store.progress[main1.id] = {"completed": true}
	assert_true(store.unlocked(main2, mixed), "Main completion unlocks next main puzzle")
	store.progress[main2.id] = {"completed": true}
	assert_true(store.unlocked(future, mixed), "Future chapter unlocks on main completion")
	var fixture_store = FixtureStore.new(game.catalog)
	fixture_store.fixture_levels.assign(mixed)
	fixture_store.progress.clear()
	assert_true(fixture_store.start_campaign(false).id == main1.id, "Skip starts at separate main Level 1 when authored")
	assert_true(fixture_store.progress.is_empty(), "Starting main campaign never completes introduction")
	fixture_store.complete(levels[-1], 12, 6)
	assert_true(fixture_store.resume_level().id == main1.id, "Final introduction puzzle joins the same main Level 1")
	fixture_store.complete(main1, 12, 6)
	assert_true(fixture_store.resume_level().id == main2.id, "Main campaign resumes at next main puzzle")
	fixture_store.complete(main2, 12, 6)
	assert_true(fixture_store.resume_level().id == future.id, "Main chapter completion advances into data-defined future chapter")
	fixture_store.complete(future, 12, 6)
	assert_true(fixture_store.resume_level().is_empty(), "Finished campaign returns to selection rather than replaying last puzzle")
	store.progress.clear()
	for data in levels: store.complete(data, 12, 6)
	assert_true(store.campaign.current_chapter == "chapter-1", "Completing Introduction enters Chapter 1")
	assert_true(store.chapter_progress("introduction", levels).completed == 10 and store.chapter_progress("chapter-1", levels).completed == 0, "Tutorial and main progress counted separately")
	var legacy = {"campaign-01": {"completed": true, "revision": 1, "best_time": 3.5, "fewest_pieces": 4, "awards": ["time"], "custom_record": "preserve"}}
	store.write(store.progress_path, legacy)
	DirAccess.remove_absolute(store.campaign_state_path)
	reopened = PuzzleStore.new(game.catalog)
	assert_true(JSON.stringify(reopened.progress) == JSON.stringify(JSON.parse_string(JSON.stringify(legacy))), "Legacy save migration preserves every record field")
	assert_true(reopened.campaign.started and reopened.resume_level().id == "campaign-02", "Legacy partial campaign resumes without new-player choice")
	reopened.complete(levels[0], 5, 7)
	assert_true(reopened.progress["campaign-01"].best_time == 3.5 and reopened.progress["campaign-01"].custom_record == "preserve" and "time" in reopened.progress["campaign-01"].awards, "Recompletion preserves best results, awards, and extra fields")
	var authored = store.create()
	game.puzzle_session.editor(authored)
	authoring.open()
	authoring.get_node("%ChapterId").text = "chapter-3"
	authoring.get_node("%ChapterName").text = "Machines"
	authoring.get_node("%ChapterOrder").value = 3
	authoring.get_node("%ChapterRequirements").text = "qa-main-2"
	authoring.update_chapter()
	assert_true(game.puzzle_session.puzzle.chapter.id == "chapter-3" and game.puzzle_session.puzzle.chapter.prerequisites == ["qa-main-2"], "Editor configures new chapter and unlock requirements")

func test_campaign_export_from_authoring_dialog() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	await get_tree().process_frame
	var store: PuzzleStore = game.puzzle_session.store
	var levels := store.list_puzzles()
	game.puzzle_session.editor(store.create())
	var authoring: PanelContainer = game.get_node("%HUD").get_node("%PuzzleAuthoring")
	var bundle_path = SavePaths.resolve("user://chapter-export.zip")
	authoring.get_node("%ExportDialog").file_selected.emit(bundle_path)
	assert_eq(authoring.get_node("%Validation").text, "Exported %d puzzles. Import the bundle into resources/campaign before building the game." % levels.size())
	var bundle = ZIPReader.new()
	assert_true(bundle.open(bundle_path) == OK, "Editor exports a readable campaign bundle")
	var manifest: Dictionary = JSON.parse_string(bundle.read_file("campaign_chapters.json").get_string_from_utf8())
	assert_true(manifest.chapters.size() == 2 and manifest.chapters[0].levels.size() == 10, "Bundle includes introduction assignments and empty main chapter")
	for data in levels:
		var exported: Dictionary = JSON.parse_string(bundle.read_file("campaign/" + data.id + ".json").get_string_from_utf8())
		assert_true(store.fingerprint(exported) == store.fingerprint(data), "Export preserves puzzle validation: " + data.id)
	bundle.close()
	DirAccess.remove_absolute(bundle_path)

extends SceneTree

const Cleanup = preload("res://tests/cleanup.gd")
var failures: Array[String] = []
var checks: int = 0

class FixtureStore extends PuzzleStore:
	var fixture_levels: Array[Dictionary] = []
	func list_puzzles(drafts: bool = false) -> Array[Dictionary]:
		return super.list_puzzles(drafts) if fixture_levels.is_empty() or drafts else fixture_levels

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var store: PuzzleStore = game.puzzle_session.store
	var previous_progress = store.progress.duplicate(true)
	var previous_campaign = store.campaign.duplicate(true)
	store.progress = {}
	store.campaign = {}
	var levels = store.list_puzzles()
	check(levels.size() == 10, "Ten preserved published levels")
	for data in levels:
		check(store.chapter_for(data).id == "introduction", "Stable introduction membership: " + data.id)
		check(store.unlocked(data, levels), "Introduction independently playable: " + data.id)
		check(data.validation.fingerprint == store.fingerprint(data), "Known-good fingerprint retained: " + data.id)
	var chapters = store.list_chapters(levels)
	check(chapters.size() == 2 and chapters[0].optional and not chapters[1].optional, "Optional Introduction and separate Chapter 1")
	check(store.chapter_unlocked(chapters[1]), "Chapter 1 available without Introduction")
	game.puzzle_browser.open_campaign()
	check(game.puzzle_browser.get_node("%StartChoice").visible, "Fresh campaign offers introduction choice")
	game.puzzle_browser.get_node("%SkipIntroduction").pressed.emit()
	check(store.campaign.introduction_skipped and store.progress.is_empty(), "Skipping records choice without completion")
	check(store.campaign.current_chapter == "chapter-1", "Skipping enters empty Chapter 1")
	check(not game.puzzle_browser.get_node("%StartChoice").visible, "Existing campaign hides choice")
	check(game.puzzle_browser.get_node("%Levels").item_count == 0, "Main chapter does not reuse tutorial puzzles")
	var target = store.start_campaign(true)
	check(target.id == "campaign-01", "Play Introduction starts at Level 1")
	game.puzzle_session.player(target)
	var reopened = PuzzleStore.new(game.catalog)
	check(reopened.resume_level().id == target.id, "Current campaign resumes after reload")
	game.puzzle_browser.open()
	game.puzzle_browser.show_chapter(0)
	check(game.puzzle_browser.get_node("%Levels").item_count == 10, "Level Select shows all ten introduction puzzles")
	var main1 = {"id": "qa-main-1", "order": 1, "prerequisites": ["campaign-10"], "chapter": {"id": "chapter-1", "name": "Chapter 1", "order": 1}}
	var main2 = {"id": "qa-main-2", "order": 2, "prerequisites": [], "chapter": main1.chapter}
	var future = {"id": "qa-future", "order": 1, "prerequisites": [], "chapter": {"id": "chapter-2", "name": "Chapter 2", "order": 2, "optional": false, "prerequisites": ["qa-main-2"]}}
	var mixed: Array = levels.duplicate()
	mixed.append_array([main1, main2, future])
	check(store.unlocked(main1, mixed), "Legacy tutorial prerequisite never gates main entry")
	check(not store.unlocked(main2, mixed), "Main levels retain their own sequence")
	check(store.list_chapters(mixed).size() == 3, "Future chapter discovered from puzzle metadata")
	check(not store.unlocked(future, mixed), "Future chapter requirements enforced")
	store.progress[main1.id] = {"completed": true}
	check(store.unlocked(main2, mixed), "Main completion unlocks next main puzzle")
	store.progress[main2.id] = {"completed": true}
	check(store.unlocked(future, mixed), "Future chapter unlocks on main completion")
	var fixture_store = FixtureStore.new(game.catalog)
	fixture_store.fixture_levels.assign(mixed)
	fixture_store.progress.clear()
	check(fixture_store.start_campaign(false).id == main1.id, "Skip starts at separate main Level 1 when authored")
	check(fixture_store.progress.is_empty(), "Starting main campaign never completes introduction")
	fixture_store.complete(levels[-1], 12, 6)
	check(fixture_store.resume_level().id == main1.id, "Final introduction puzzle joins the same main Level 1")
	fixture_store.complete(main1, 12, 6)
	check(fixture_store.resume_level().id == main2.id, "Main campaign resumes at next main puzzle")
	fixture_store.complete(main2, 12, 6)
	check(fixture_store.resume_level().id == future.id, "Main chapter completion advances into data-defined future chapter")
	fixture_store.complete(future, 12, 6)
	check(fixture_store.resume_level().is_empty(), "Finished campaign returns to selection rather than replaying last puzzle")
	store.progress.clear()
	for data in levels: store.complete(data, 12, 6)
	check(store.campaign.current_chapter == "chapter-1", "Completing Introduction enters Chapter 1")
	check(store.chapter_progress("introduction", levels).completed == 10 and store.chapter_progress("chapter-1", levels).completed == 0, "Tutorial and main progress counted separately")
	var legacy = {"campaign-01": {"completed": true, "revision": 1, "best_time": 3.5, "fewest_pieces": 4, "awards": ["time"], "custom_record": "preserve"}}
	store.write(PuzzleStore.PROGRESS, legacy)
	DirAccess.remove_absolute(PuzzleStore.CAMPAIGN_STATE)
	reopened = PuzzleStore.new(game.catalog)
	check(JSON.stringify(reopened.progress) == JSON.stringify(JSON.parse_string(JSON.stringify(legacy))), "Legacy save migration preserves every record field")
	check(reopened.campaign.started and reopened.resume_level().id == "campaign-02", "Legacy partial campaign resumes without new-player choice")
	reopened.complete(levels[0], 5, 7)
	check(reopened.progress["campaign-01"].best_time == 3.5 and reopened.progress["campaign-01"].custom_record == "preserve" and "time" in reopened.progress["campaign-01"].awards, "Recompletion preserves best results, awards, and extra fields")
	var authored = store.create()
	game.puzzle_session.editor(authored)
	game.authoring.open()
	game.authoring.get_node("%ChapterId").text = "chapter-3"
	game.authoring.get_node("%ChapterName").text = "Machines"
	game.authoring.get_node("%ChapterOrder").value = 3
	game.authoring.get_node("%ChapterRequirements").text = "qa-main-2"
	game.authoring.update_chapter()
	check(game.puzzle_session.puzzle.chapter.id == "chapter-3" and game.puzzle_session.puzzle.chapter.prerequisites == ["qa-main-2"], "Editor configures new chapter and unlock requirements")
	var bundle_path = SavePaths.resolve("user://chapter-export.zip")
	game.authoring.export_package(bundle_path)
	var bundle = ZIPReader.new()
	check(bundle.open(bundle_path) == OK, "Editor exports a readable campaign bundle")
	var manifest: Dictionary = JSON.parse_string(bundle.read_file("campaign_chapters.json").get_string_from_utf8())
	check(manifest.chapters.size() == 2 and manifest.chapters[0].levels.size() == 10, "Bundle includes introduction assignments and empty main chapter")
	for data in levels:
		var exported: Dictionary = JSON.parse_string(bundle.read_file("campaign/" + data.id + ".json").get_string_from_utf8())
		check(store.fingerprint(exported) == store.fingerprint(data), "Export preserves puzzle validation: " + data.id)
	bundle.close()
	DirAccess.remove_absolute(bundle_path)
	store.progress = previous_progress
	store.campaign = previous_campaign
	store.write(PuzzleStore.PROGRESS, previous_progress)
	store.write(PuzzleStore.CAMPAIGN_STATE, previous_campaign)
	print("CHAPTERS: %d checks; %d failures" % [checks, failures.size()])
	if "--visual-review" in OS.get_cmdline_user_args() and failures.is_empty():
		game.authoring.hide()
		game.new_track(false)
		game.show_main_menu()
		current_scene = game
		game.puzzle_browser.open_campaign()
		print("Visual review ready; test saves are isolated. Closes automatically after 180 seconds.")
		create_timer(180).timeout.connect(func(): quit())
		return
	game.queue_free()
	await process_frame
	await Cleanup.stop_audio(self)
	quit(0 if failures.is_empty() else 1)

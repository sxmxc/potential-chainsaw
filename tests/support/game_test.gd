extends GutTest

var previous_test_directory: String
var test_directory: String
var previous_max_fps: int
var previous_window_size: Vector2i
var previous_scale_size: Vector2i
var previous_scale_mode: int
var previous_scale_aspect: int
var previous_puzzle_paths: Array[String] = []
var previous_track_path: String
var runner_layer: CanvasLayer
var previous_runner_visibility: bool

func before_each() -> void:
	previous_test_directory = OS.get_environment("MARBLE_ENGINEER_TEST_DATA")
	test_directory = OS.get_user_data_dir().path_join("gut-tests").path_join(str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(test_directory)
	OS.set_environment("MARBLE_ENGINEER_TEST_DATA", test_directory)
	# PuzzleStore resolves static paths when scripts load, before GUT setup.
	previous_puzzle_paths = [PuzzleStore.DRAFTS, PuzzleStore.PUBLISHED, PuzzleStore.PROGRESS, PuzzleStore.CAMPAIGN_STATE]
	PuzzleStore.DRAFTS = test_directory.path_join("puzzles/drafts")
	PuzzleStore.PUBLISHED = test_directory.path_join("puzzles/published")
	PuzzleStore.PROGRESS = test_directory.path_join("campaign_progress.json")
	PuzzleStore.CAMPAIGN_STATE = test_directory.path_join("campaign_state.json")
	previous_track_path = TrackSerializer.SAVE_DIR
	TrackSerializer.SAVE_DIR = test_directory.path_join("tracks")
	previous_max_fps = Engine.max_fps
	previous_window_size = get_window().size
	previous_scale_size = get_window().content_scale_size
	previous_scale_mode = get_window().content_scale_mode
	previous_scale_aspect = get_window().content_scale_aspect
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	ConstructionInput.install(true)
	runner_layer = get_tree().root.get_node_or_null("GutRunner/GutLayer")
	if runner_layer:
		previous_runner_visibility = runner_layer.visible
		runner_layer.hide()

func after_each() -> void:
	# GUT owns queued fixture teardown. Stop global audio too.
	var sound_manager = get_tree().root.get_node_or_null("SoundManager")
	if sound_manager:
		for pool in [sound_manager.music, sound_manager.sound_effects, sound_manager.ui_sound_effects]:
			if pool == sound_manager.music:
				for tween in pool.tweens.values(): tween.kill()
				pool.tweens.clear()
			for player in pool.busy_players.duplicate():
				player.stop()
				pool.mark_player_as_available(player)
	await get_tree().process_frame
	Engine.max_fps = previous_max_fps
	get_window().size = previous_window_size
	get_window().content_scale_size = previous_scale_size
	get_window().content_scale_mode = previous_scale_mode as Window.ContentScaleMode
	get_window().content_scale_aspect = previous_scale_aspect as Window.ContentScaleAspect
	ConstructionInput.install(true)
	OS.set_environment("MARBLE_ENGINEER_TEST_DATA", previous_test_directory)
	PuzzleStore.DRAFTS = previous_puzzle_paths[0]
	PuzzleStore.PUBLISHED = previous_puzzle_paths[1]
	PuzzleStore.PROGRESS = previous_puzzle_paths[2]
	PuzzleStore.CAMPAIGN_STATE = previous_puzzle_paths[3]
	TrackSerializer.SAVE_DIR = previous_track_path
	if runner_layer: runner_layer.visible = previous_runner_visibility
	remove_test_directory(test_directory)

func remove_test_directory(path: String) -> void:
	# Only the unique fixture directory created above is removed.
	if path != test_directory and not path.begins_with(test_directory + "/"):
		fail_test("Refusing cleanup outside the fixture directory")
		return
	for filename in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(filename))
	for directory in DirAccess.get_directories_at(path): remove_test_directory(path.path_join(directory))
	DirAccess.remove_absolute(path)

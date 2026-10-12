extends SceneTree

const Cleanup = preload("res://tests/cleanup.gd")

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func playing_player(playlist: AudioStreamPlaylist) -> AudioStreamPlayer:
	for node in root.get_node("SoundManager").find_children("*", "AudioStreamPlayer", true, false):
		var player = node as AudioStreamPlayer
		if player.stream == playlist and player.playing and not player.stream_paused:
			return player
	return null

func settle() -> void:
	await create_timer(0.1).timeout

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var menu_playlist: AudioStreamPlaylist = game.get_node("%MainMenu").main_menu_playlist
	var world_playlist: AudioStreamPlaylist = game.sandbox.world_music_playlist
	await settle()
	check(playing_player(menu_playlist) != null, "Startup plays menu music")
	check(playing_player(world_playlist) == null, "Hidden World and showcase do not start world music")
	game.enter_sandbox()
	await settle()
	check(playing_player(world_playlist) != null and playing_player(menu_playlist) == null, "Entering World switches music")
	var original_player = playing_player(world_playlist)
	game.new_track()
	await settle()
	check(playing_player(world_playlist) == original_player, "New track keeps the same music player")
	game.show_main_menu()
	await settle()
	check(playing_player(menu_playlist) != null and playing_player(world_playlist) == null, "Returning to menu restores menu music")
	game.enter_sandbox()
	game.show_main_menu()
	game.enter_sandbox()
	await settle()
	check(playing_player(world_playlist) != null and playing_player(menu_playlist) == null, "Rapid transitions finish with the active mode's music")
	game.show_main_menu()
	game.puzzle_session.editor()
	await settle()
	check(playing_player(world_playlist) != null and playing_player(menu_playlist) == null, "Puzzle editor activates World music")
	game.show_main_menu()
	var campaign_files = DirAccess.get_files_at("res://resources/campaign")
	var campaign_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/campaign/" + campaign_files[0]))
	game.puzzle_session.player(campaign_data)
	await settle()
	check(playing_player(world_playlist) != null and playing_player(menu_playlist) == null, "Campaign activates World music")
	print("MUSIC TESTS: %d checks; %d failures" % [checks, failures.size()])
	game.queue_free()
	await process_frame
	await Cleanup.stop_audio(self)
	quit(0 if failures.is_empty() else 1)

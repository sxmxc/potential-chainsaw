extends "res://tests/support/scene_test.gd"

func playing_player(playlist: AudioStreamPlaylist) -> AudioStreamPlayer:
	# Player identity is part of this regression; inspect nodes through Node's API,
	# without touching the addon's pool bookkeeping or tween state.
	for node in get_tree().root.get_node("SoundManager").find_children("*", "AudioStreamPlayer", true, false):
		var player := node as AudioStreamPlayer
		if player.stream == playlist and player.playing and not player.stream_paused:
			return player
	return null

func settle() -> void:
	await get_tree().create_timer(0.1).timeout

func test_music_transitions() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	var menu_playlist: AudioStreamPlaylist = game.get_node("%MainMenu").main_menu_playlist
	var world_playlist: AudioStreamPlaylist = game.workspace.world.world_music_playlist
	await settle()
	assert_true(playing_player(menu_playlist) != null, "Startup plays menu music")
	assert_true(playing_player(world_playlist) == null, "Hidden World and showcase do not start world music")
	game.workspace.activate()
	await settle()
	assert_true(playing_player(world_playlist) != null and playing_player(menu_playlist) == null, "Entering World switches music")
	var original_player = playing_player(world_playlist)
	game.workspace.session.sandbox()
	await settle()
	assert_true(playing_player(world_playlist) == original_player, "New track keeps the same music player")
	game.show_main_menu()
	await settle()
	assert_true(playing_player(menu_playlist) != null and playing_player(world_playlist) == null, "Returning to menu restores menu music")
	game.workspace.activate()
	game.show_main_menu()
	game.workspace.activate()
	await settle()
	assert_true(playing_player(world_playlist) != null and playing_player(menu_playlist) == null, "Rapid transitions finish with the active mode's music")
	game.show_main_menu()
	game.workspace.session.editor()
	await settle()
	assert_true(playing_player(world_playlist) != null and playing_player(menu_playlist) == null, "Puzzle editor activates World music")
	game.show_main_menu()
	var campaign_files = DirAccess.get_files_at("res://resources/campaign")
	var campaign_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/campaign/" + campaign_files[0]))
	game.workspace.session.player(campaign_data)
	await settle()
	assert_true(playing_player(world_playlist) != null and playing_player(menu_playlist) == null, "Campaign activates World music")

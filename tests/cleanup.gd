extends RefCounted

static func stop_audio(tree: SceneTree) -> void:
	var sound_manager = tree.root.get_node_or_null("SoundManager")
	if not sound_manager:
		return
	for node in sound_manager.find_children("*", "AudioStreamPlayer", true, false):
		var player = node as AudioStreamPlayer
		player.stop()
		player.stream = null
	# Drain stopped audio playbacks before destroying the test tree.
	# --fixed-fps advances scene timers faster than the audio thread's real clock.
	OS.delay_msec(100)
	await tree.create_timer(0.1).timeout

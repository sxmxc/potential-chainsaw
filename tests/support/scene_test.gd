extends "res://tests/support/game_test.gd"

# main.tscn applies settings and starts music. Snapshot only;
# tests choose their own display/input setup instead of changing it here.
var previous_window: Dictionary
var previous_actions: Dictionary
var previous_audio: Dictionary
var previous_max_fps: int
var previous_auto_accept_quit: bool
var previous_vsync: int
var previous_msaa: int
var previous_render_scale: float

func before_each() -> void:
	super()
	previous_max_fps = Engine.max_fps
	previous_auto_accept_quit = get_tree().auto_accept_quit
	previous_msaa = get_viewport().msaa_3d
	previous_render_scale = get_viewport().scaling_3d_scale
	previous_window = {}
	for property in ["mode", "size", "position", "content_scale_size", "content_scale_mode", "content_scale_aspect"]:
		previous_window[property] = get_window().get(property)
	previous_vsync = DisplayServer.window_get_vsync_mode(get_window().get_window_id())
	previous_actions = {}
	for action in ConstructionInput.actions():
		if InputMap.has_action(action):
			previous_actions[action] = {"deadzone": InputMap.action_get_deadzone(action), "events": InputMap.action_get_events(action)}
		else:
			previous_actions[action] = null
	previous_audio = {}
	for bus in preload("res://scripts/game_settings.gd").DEFAULTS.audio:
		var index := AudioServer.get_bus_index(bus)
		if index >= 0:
			previous_audio[bus] = {"volume_db": AudioServer.get_bus_volume_db(index), "muted": AudioServer.is_bus_mute(index)}

func after_each() -> void:
	# Use the addon's public API; it owns fades and player availability.
	var audio := get_tree().root.get_node("SoundManager")
	audio.stop_music()
	assert_true(await wait_until(func(): return not audio.is_music_playing(), 1.0), "Scene music stops through the public API")
	Engine.max_fps = previous_max_fps
	get_tree().auto_accept_quit = previous_auto_accept_quit
	get_viewport().msaa_3d = previous_msaa
	get_viewport().scaling_3d_scale = previous_render_scale
	for property in previous_window:
		get_window().set(property, previous_window[property])
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(previous_vsync, get_window().get_window_id())
	for action in previous_actions:
		if InputMap.has_action(action): InputMap.erase_action(action)
		var saved: Variant = previous_actions[action]
		if saved == null: continue
		InputMap.add_action(action, saved.deadzone)
		for event in saved.events: InputMap.action_add_event(action, event)
	for bus in previous_audio:
		var index := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(index, previous_audio[bus].volume_db)
		AudioServer.set_bus_mute(index, previous_audio[bus].muted)
	super()

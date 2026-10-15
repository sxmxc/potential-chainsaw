extends RefCounted

const PATH = "user://settings.cfg"
const DEFAULTS = {
	"camera": {"sensitivity": 1.0, "zoom_sensitivity": 1.0, "invert_x": false, "invert_y": false},
	"audio": {"Master": 1.0, "Music": 1.0, "SFX": 1.0, "UI": 1.0},
	"display": {"mode": 0, "resolution": 0, "vsync": true, "fps": 0, "msaa": 0, "render_scale": 1.0}
}
const RESOLUTIONS = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const FPS_LIMITS = [0, 30, 60, 120, 144, 240]
var values: Dictionary = DEFAULTS.duplicate(true)

func load_saved() -> void:
	var config = ConfigFile.new()
	if config.load(SaveStorage.resolve(PATH)) != OK: return
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			var value: Variant = config.get_value(section, key, DEFAULTS[section][key])
			if value is float and not is_finite(value): continue
			if typeof(value) == typeof(DEFAULTS[section][key]) or (value is int and DEFAULTS[section][key] is float):
				values[section][key] = value
	values.camera.sensitivity = clampf(values.camera.sensitivity, 0.3, 2.5)
	values.camera.zoom_sensitivity = clampf(values.camera.zoom_sensitivity, 0.3, 2.5)
	for bus in values.audio: values.audio[bus] = clampf(values.audio[bus], 0.0, 1.0)
	values.display.mode = clampi(values.display.mode, 0, 2)
	values.display.resolution = clampi(values.display.resolution, 0, RESOLUTIONS.size() - 1)
	values.display.fps = clampi(values.display.fps, 0, FPS_LIMITS.size() - 1)
	values.display.msaa = clampi(values.display.msaa, 0, 3)
	values.display.render_scale = clampf(values.display.render_scale, 0.5, 1.0)
	ConstructionInput.load_bindings(config)

func save() -> Error:
	var config = ConfigFile.new()
	for section in values:
		for key in values[section]: config.set_value(section, key, values[section][key])
	ConstructionInput.save_bindings(config)
	return config.save(SaveStorage.resolve(PATH))

func reset_defaults() -> void:
	values = DEFAULTS.duplicate(true)
	ConstructionInput.reset_bindings()

func apply(game: Node, apply_window: bool = true) -> void:
	var camera: ConstructionCamera = game.workspace.world.camera
	camera.sensitivity = values.camera.sensitivity
	camera.zoom_sensitivity = values.camera.zoom_sensitivity
	camera.invert_x = values.camera.invert_x
	camera.invert_y = values.camera.invert_y
	for bus in values.audio:
		var index = AudioServer.get_bus_index(bus)
		if index < 0: continue
		AudioServer.set_bus_volume_linear(index, values.audio[bus])
		AudioServer.set_bus_mute(index, values.audio[bus] == 0.0)
	Engine.max_fps = FPS_LIMITS[values.display.fps]
	var viewports: Array[Viewport] = [game.get_viewport()]
	for node in game.find_children("*", "SubViewport", true, false): viewports.append(node)
	for viewport in viewports:
		viewport.msaa_3d = values.display.msaa
		viewport.scaling_3d_scale = values.display.render_scale
	if not apply_window or DisplayServer.get_name() == "headless": return
	var window: Window = game.get_window()
	window.mode = Window.MODE_WINDOWED if values.display.mode == 0 else Window.MODE_FULLSCREEN if values.display.mode == 1 else Window.MODE_EXCLUSIVE_FULLSCREEN
	if values.display.mode == 0:
		window.size = RESOLUTIONS[values.display.resolution]
		var available = DisplayServer.screen_get_usable_rect(window.current_screen)
		window.position = available.position + (available.size - window.size) / 2
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.display.vsync else DisplayServer.VSYNC_DISABLED, window.get_window_id())

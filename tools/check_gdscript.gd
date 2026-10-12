extends SceneTree

var checked_count: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	for setting in ProjectSettings.get_property_list():
		if setting.name.begins_with("debug/gdscript/warnings/") and ProjectSettings.get_setting(setting.name) is int and ProjectSettings.get_setting(setting.name) == 1:
			ProjectSettings.set_setting(setting.name, 2)
	call_deferred("check_scripts")

func check_scripts() -> void:
	# Compile a separate copy so checking this file cannot reload the running script.
	var checker = GDScript.new()
	checker.source_code = get_script().source_code
	checked_count += 1
	if checker.reload() != OK:
		failures.append(get_script().resource_path)
	for directory in ["res://scripts", "res://tests", "res://tools"]:
		check_directory(directory)
	for script_path in OS.get_cmdline_user_args():
		check_script(script_path)
	print("GDSCRIPT CHECK: %d scripts; %d failures" % [checked_count, failures.size()])
	for path in failures:
		print("FAILED: ", path)
	quit(0 if failures.is_empty() else 1)

func check_directory(path: String) -> void:
	for filename in DirAccess.get_files_at(path):
		if not filename.ends_with(".gd"):
			continue
		check_script(path.path_join(filename))
	for directory in DirAccess.get_directories_at(path):
		check_directory(path.path_join(directory))

func check_script(script_path: String) -> void:
	if script_path == get_script().resource_path:
		return
	var script: GDScript = load(script_path)
	checked_count += 1
	if not script or script.reload(true) != OK:
		failures.append(script_path)

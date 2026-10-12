class_name SavePaths
extends RefCounted

# Tests redirect only application saves, never Godot's caches or APPDATA.
static func resolve(path: String) -> String:
	var test_directory = OS.get_environment("MARBLE_ENGINEER_TEST_DATA")
	if OS.has_feature("editor") and not test_directory.is_empty() and path.begins_with("user://"):
		return test_directory.path_join(path.trim_prefix("user://"))
	return path

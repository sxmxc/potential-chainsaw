class_name SaveStorage
extends RefCounted

static func valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 100: return false
	for character in id:
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_": return false
	return true

# Tests redirect only application saves, never Godot's caches or APPDATA.
static func resolve(path: String) -> String:
	var test_directory = OS.get_environment("MARBLE_ENGINEER_TEST_DATA")
	if OS.has_feature("editor") and not test_directory.is_empty() and path.begins_with("user://"):
		return test_directory.path_join(path.trim_prefix("user://"))
	return path

# Replace the destination only after the complete JSON has reached the temp file.
# Callers own domain validation and paths; an empty result means the write succeeded.
static func write_json(path: String, data: Dictionary) -> String:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return "Could not write " + path + ": " + error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return "Could not finish saving " + path + ": " + error_string(error)
	return ""

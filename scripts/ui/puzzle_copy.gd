extends RefCounted

# Presentation only: never rewrite validated layouts or user-authored puzzle data.
static var introduction_text: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/introduction_copy.json"))

static func introduction(data: Dictionary) -> Dictionary:
	# Revisions authored by the user keep their own writing.
	if int(data.get("revision", 1)) != 1 or data.get("status","draft") != "published": return {}
	return introduction_text.get(data.get("id", ""), {})

static func objective(data: Dictionary) -> String:
	return introduction(data).get("objective", data.get("description", ""))

extends Label
class_name VersionLabel

@onready var version : String = ProjectSettings.get_setting("application/config/version")

func _ready() -> void:
	text = "v%s#%s" % [version, get_commit_hash()]

func get_commit_hash() -> String:
	var output = []
	# Run git rev-parse --short HEAD. 
	# Pass arguments as an array of strings.
	var exit_code = OS.execute("git", ["rev-parse", "--short", "HEAD"], output, true)
	
	if exit_code == 0 and output.size() > 0:
		return output[0].strip_edges() # Clean up trailing newlines
	else:
		push_error("Failed to execute git command. Exit code: ", exit_code)
		return "Unknown"

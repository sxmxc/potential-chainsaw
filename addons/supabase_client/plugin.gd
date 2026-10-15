@tool
extends EditorPlugin

const AUTOLOAD_NAME = "SupabaseClient"

func _enable_plugin() -> void:
	var plugin_script: Script = get_script()
	add_autoload_singleton(AUTOLOAD_NAME, plugin_script.resource_path.get_base_dir().path_join("supabase_client.gd"))

func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)

extends SceneTree
## Maintenance command: godot --headless --path . --script tools/export_community_catalog.gd
## Export from YARD's saved registry; never scan directories or invent asset IDs.

func _initialize() -> void:
	export_catalog.call_deferred()

func export_catalog() -> void:
	var assets: Dictionary = {}
	for definition in PieceCatalog.new().query():
		var settings: Dictionary = {}
		for setting in definition.settings:
			settings[String(setting.key)] = {"kind": int(setting.kind), "minimum": setting.minimum, "maximum": setting.maximum}
		var inputs: Dictionary = {}
		var outputs: Dictionary = {}
		var model := definition.model.instantiate()
		model.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(model)
		var components: Array[Node] = [model]
		components.append_array(model.find_children("*", "Node", true, false))
		for component in components:
			if component is PieceBehavior:
				for port in component.inputs: inputs[port] = component.state_inputs.has(port)
				for port in component.output_ports(): outputs[port] = component.state_outputs.has(port)
		assets[String(definition.id)] = {"connectors": definition.connectors.size(), "scenery": definition.authoring_only, "surface_mounted": definition.surface_mounted, "release": definition.has_behavior(MarbleRelease), "collector": definition.has_behavior(MarbleCollector), "settings": settings, "inputs": inputs, "outputs": outputs}
		model.free()
	var manifest := {"format": 1, "assets": assets, "game_version": str(ProjectSettings.get_setting("application/config/version", "0.0.1"))}
	manifest.compatibility = JSON.stringify({"assets": assets, "game_version": manifest.game_version}, "", true, true).sha256_text()
	for path in ["res://resources/community_catalog.json", "res://supabase/functions/community/catalog.json"]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if not file: push_error("Could not export catalog: " + path); quit(1); return
		file.store_string(JSON.stringify(manifest, "\t", true, true))
	print("Exported %d registry entries; compatibility %s" % [assets.size(), manifest.compatibility])
	quit()

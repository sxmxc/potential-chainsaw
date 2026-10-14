extends PanelContainer
signal connections_requested
var build: BuildManager
var session: ConstructionSession
const PERMISSIONS: Array[String] = ["move", "rotate", "configure", "remove", "duplicate"]
var refreshing: bool = false
var displayed_piece: BuildingPiece
func has_properties() -> bool:
	if not build.selected: return false
	var piece: BuildingPiece=build.selected
	if session and session.is_authoring and build.selection.any(func(object): return not object.definition.authoring_only): return true
	if build.selection.size() != 1: return false
	return (not piece.output_ports.is_empty() or not piece.input_ports.is_empty()) or not piece.definition.settings.is_empty()
func configure(manager: BuildManager) -> void:
	build=manager
	%MechanismSettings.configure(manager)
	get_viewport().size_changed.connect(fit_content)
	%Scroll.get_child(0).minimum_size_changed.connect(func():fit_content.call_deferred())
	%PermissionsToggle.pressed.connect(func(): %Permissions.visible = not %Permissions.visible; fit_content.call_deferred())
	%Preset.item_selected.connect(set_permission_preset)
	%ApplyPermissions.pressed.connect(apply_permissions)
	%EditConnections.pressed.connect(func(): connections_requested.emit())
	build.selection_changed.connect(refresh)
	refresh(null)
func refresh(piece: BuildingPiece) -> void:
	var selection_changed: bool = piece != displayed_piece
	displayed_piece = piece
	visible=piece!=null
	if not piece: return
	refreshing=true
	var count=build.selection.size()
	%PieceName.text=piece.definition.display_name if count==1 else "%d-piece assembly" % count
	%Details.text="Height: %s m" % ConstructionInput.height_text(piece.position.y) if count==1 else "Heights stay together"
	%Details.visible = count == 1
	%ConfigurationHeading.visible = count == 1 and not piece.definition.settings.is_empty()
	%Capabilities.visible = count == 1 and (not piece.input_ports.is_empty() or not piece.output_ports.is_empty())
	%ConnectionsHeading.visible = %Capabilities.visible
	%ConnectionSummary.visible = %Capabilities.visible
	%EditConnections.visible = %Capabilities.visible
	if %Capabilities.visible:
		var roles: PackedStringArray = []
		if not piece.output_ports.is_empty(): roles.append("Can send signals")
		if not piece.input_ports.is_empty(): roles.append("Can receive signals")
		%Capabilities.text = "\n".join(roles)
		var incoming := 0
		for source in build.pieces:
			for link in source.configuration.get("links", []):
				if link.get("target", "") == piece.instance_id: incoming += 1
		%ConnectionSummary.text = "%d incoming · %d outgoing" % [incoming, piece.configuration.get("links", []).size()]
	refresh_permissions(selection_changed)
	refreshing=false
	fit_content.call_deferred()

func fit_content() -> void:
	if not is_inside_tree(): return
	%Scroll.custom_minimum_size.y=minf(%Scroll.get_child(0).get_combined_minimum_size().y,get_viewport().get_visible_rect().size.y*0.65)

func refresh_permissions(selection_changed: bool) -> void:
	var tracks := build.selection.filter(func(object): return not object.definition.authoring_only)
	%PermissionsToggle.visible = session != null and session.is_authoring and not tracks.is_empty()
	if not %PermissionsToggle.visible or selection_changed: %Permissions.hide()
	if not %PermissionsToggle.visible: return
	%SelectionSummary.text = "Player permissions · %d track %s" % [tracks.size(), "piece" if tracks.size() == 1 else "pieces"]
	var permission: Dictionary = session.puzzle.permissions.get(tracks[0].instance_id, {})
	for action in PERMISSIONS: get_node("%Permit" + action.capitalize()).set_pressed_no_signal(permission.get(action, false))
	%RestrictSetting.set_pressed_no_signal(permission.has("config_keys"))
	%ConfigKeys.clear()
	var keys: Array = []
	for setting in tracks[0].definition.settings: keys.append(String(setting.key))
	keys.append_array(tracks[0].configuration.keys())
	var restrictions: Array = permission.get("config_keys", [])
	if restrictions.size() > 1:
		%ConfigKeys.add_item("Existing setting restrictions")
		%ConfigKeys.set_item_metadata(0, "")
	var seen: Array = []
	for key in keys:
		if key in seen: continue
		seen.append(key)
		%ConfigKeys.add_item(str(key).capitalize())
		var index: int = %ConfigKeys.item_count - 1
		%ConfigKeys.set_item_metadata(index, key)
		if restrictions.size() == 1 and key == restrictions[0]: %ConfigKeys.select(index)
	var key: String = %ConfigKeys.get_item_metadata(%ConfigKeys.selected) if %ConfigKeys.item_count > 0 else ""
	var limits: Array = permission.get("limits", {}).get(key, [0, 100])
	%SettingMin.set_value_no_signal(limits[0])
	%SettingMax.set_value_no_signal(limits[1])

func set_permission_preset(index: int) -> void:
	for action in PERMISSIONS:
		get_node("%Permit" + action.capitalize()).button_pressed = index == 4 or (index == 1 and action == "move") or (index == 2 and action == "rotate") or (index == 3 and action == "configure")

func apply_permissions() -> void:
	if not session or not session.is_authoring or not build.enabled or build.chosen: return
	var tracks := build.selection.filter(func(object): return not object.definition.authoring_only)
	if tracks.is_empty(): return
	var permission: Dictionary = session.puzzle.permissions.get(tracks[0].instance_id, {}).duplicate(true)
	for action in PERMISSIONS: permission[action] = get_node("%Permit" + action.capitalize()).button_pressed
	if not %RestrictSetting.button_pressed:
		permission.erase("config_keys")
		permission.erase("limits")
	elif %ConfigKeys.item_count > 0:
		var key: String = %ConfigKeys.get_item_metadata(%ConfigKeys.selected)
		if not key.is_empty():
			permission.config_keys = [key]
			permission.limits = {key: [%SettingMin.value, %SettingMax.value]}
	session.set_permissions(permission)
	refresh_permissions(false)

extends PanelContainer
var build: BuildManager
var session: PuzzleSession
const Schema = preload("res://scripts/mechanisms/settings_schema.gd")
const PERMISSIONS: Array[String] = ["move", "rotate", "configure", "remove", "duplicate"]
var refreshing: bool = false
var displayed_piece: BuildingPiece
func has_properties() -> bool:
	if not build.selected: return false
	var piece: BuildingPiece=build.selected
	if session and session.mode == "editor" and build.selection.any(func(object): return not object.definition.authoring_only): return true
	if build.selection.size() != 1: return false
	return piece.definition.behavior in ["start","elevator","resizable_support"] or (piece.mechanism_component and not piece.mechanism_component.events.is_empty()) or not preload("res://scripts/mechanisms/settings_schema.gd").NUMBERS.get(piece.definition.behavior,{}).is_empty() or not preload("res://scripts/mechanisms/settings_schema.gd").FLAGS.get(piece.definition.behavior,{}).is_empty()
func configure(manager: BuildManager) -> void:
	build=manager
	%MechanismSettings.configure(manager)
	%LinkSettings.configure(manager)
	%LinksToggle.pressed.connect(func(): %LinkSettings.visible=not %LinkSettings.visible; fit_content.call_deferred())
	get_viewport().size_changed.connect(fit_content)
	%Scroll.get_child(0).minimum_size_changed.connect(func():fit_content.call_deferred())
	%Speed.value_changed.connect(func(value): change_setting("release_speed", value, "Release speed"))
	%ElevatorHeight.value_changed.connect(func(value): change_setting("elevator_height", value, "Elevator rise"))
	%ElevatorSpeed.value_changed.connect(func(value): change_setting("elevator_speed", value, "Elevator speed"))
	%SupportHeight.value_changed.connect(func(value): change_setting("support_height", value, "Support height"))
	%SupportTop.item_selected.connect(func(index): change_setting("support_double_top", index == 1, "Support top style"))
	%PermissionsToggle.pressed.connect(func(): %Permissions.visible = not %Permissions.visible; fit_content.call_deferred())
	%Preset.item_selected.connect(set_permission_preset)
	%ApplyPermissions.pressed.connect(apply_permissions)
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
	%Speed.visible=count==1 and piece.definition.behavior=="start"
	%SpeedLabel.visible=%Speed.visible
	%Speed.value=piece.configuration.get("release_speed",1.4)
	%ElevatorSettings.visible=count==1 and piece.definition.behavior=="elevator"
	%ElevatorHeight.value=piece.configuration.get("elevator_height",4.0)
	%ElevatorSpeed.value=piece.configuration.get("elevator_speed",0.8)
	%SupportSettings.visible=count==1 and piece.definition.behavior=="resizable_support"
	%SupportHeight.value=piece.configuration.get("support_height",2.0)
	%SupportTop.select(1 if piece.configuration.get("support_double_top",false) else 0)
	%Details.visible = count == 1
	var editable: bool=not build.rules or build.rules.permits(piece.instance_id,"configure")
	for field in [%Speed,%ElevatorHeight,%ElevatorSpeed,%SupportHeight]: field.editable=editable
	%SupportTop.disabled=not editable
	if selection_changed: %LinkSettings.hide()
	%LinksToggle.visible=count==1 and piece.mechanism_component != null and not piece.mechanism_component.events.is_empty()
	refresh_permissions(selection_changed)
	refreshing=false
	fit_content.call_deferred()

func fit_content() -> void:
	if not is_inside_tree(): return
	%Scroll.custom_minimum_size.y=minf(%Scroll.get_child(0).get_combined_minimum_size().y,get_viewport().get_visible_rect().size.y*0.65)

func change_setting(key: String, value: Variant, label: String) -> void:
	if refreshing or not build.selected or not build.enabled: return
	var config=build.selected.configuration.duplicate(true)
	config[key]=value
	build.configure_selected(config,label)

func refresh_permissions(selection_changed: bool) -> void:
	var tracks := build.selection.filter(func(object): return not object.definition.authoring_only)
	%PermissionsToggle.visible = session != null and session.mode == "editor" and not tracks.is_empty()
	if not %PermissionsToggle.visible or selection_changed: %Permissions.hide()
	if not %PermissionsToggle.visible: return
	%SelectionSummary.text = "Player permissions · %d track %s" % [tracks.size(), "piece" if tracks.size() == 1 else "pieces"]
	var permission: Dictionary = session.puzzle.permissions.get(tracks[0].instance_id, {})
	for action in PERMISSIONS: get_node("%Permit" + action.capitalize()).set_pressed_no_signal(permission.get(action, false))
	%RestrictSetting.set_pressed_no_signal(permission.has("config_keys"))
	%ConfigKeys.clear()
	var keys: Array = Schema.NUMBERS.get(tracks[0].definition.behavior, {}).keys()
	keys.append_array(Schema.FLAGS.get(tracks[0].definition.behavior, {}).keys())
	keys.append_array(tracks[0].configuration.keys())
	if tracks[0].definition.behavior == "elevator": keys.append_array(["elevator_height", "elevator_speed"])
	if tracks[0].definition.behavior == "resizable_support": keys.append_array(["support_height", "support_double_top"])
	if tracks[0].definition.behavior == "start": keys.append("release_speed")
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
	if not session or session.mode != "editor" or not build.enabled or build.chosen: return
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

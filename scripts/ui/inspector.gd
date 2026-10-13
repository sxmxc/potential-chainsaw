extends PanelContainer
var build: BuildManager
var refreshing: bool = false
var displayed_piece: TrackPiece
func has_properties() -> bool:
	if not build.selected: return false
	var piece: TrackPiece=build.selected
	return piece.definition.authoring_only or piece.definition.behavior in ["start","elevator","resizable_support"] or not piece.supported_events().is_empty() or not preload("res://scripts/mechanisms/settings_schema.gd").NUMBERS.get(piece.definition.behavior,{}).is_empty() or not preload("res://scripts/mechanisms/settings_schema.gd").FLAGS.get(piece.definition.behavior,{}).is_empty()
func configure(manager: BuildManager) -> void:
	build=manager
	%MechanismSettings.configure(manager)
	%LinkSettings.configure(manager)
	%LinksToggle.pressed.connect(func(): %LinkSettings.visible=not %LinkSettings.visible; fit_content.call_deferred())
	get_viewport().size_changed.connect(fit_content)
	%Scroll.get_child(0).minimum_size_changed.connect(func():fit_content.call_deferred())
	%Move.pressed.connect(build.move_selected)
	%Rotate.pressed.connect(build.rotate_piece)
	%Duplicate.pressed.connect(func():build.move_selected(true))
	%Lower.pressed.connect(func():build.elevate_selected(-build.height_step(Input.is_key_pressed(KEY_SHIFT))))
	%Raise.pressed.connect(func():build.elevate_selected(build.height_step(Input.is_key_pressed(KEY_SHIFT))))
	%Delete.pressed.connect(build.delete_selected)
	%Speed.value_changed.connect(func(value):
		if refreshing or not build.selected or not build.enabled: return
		var config=build.selected.configuration.duplicate(true)
		config["release_speed"]=value
		build.configure_selected(config,"Release speed"))
	%ElevatorHeight.value_changed.connect(func(value):change_elevator("elevator_height",value,"Elevator rise"))
	%ElevatorSpeed.value_changed.connect(func(value):change_elevator("elevator_speed",value,"Elevator speed"))
	%SupportHeight.value_changed.connect(func(value):change_elevator("support_height",value,"Support height"))
	%SupportTop.item_selected.connect(func(index):change_support_top(index==1))
	build.selection_changed.connect(refresh)
	refresh(null)
func refresh(piece: TrackPiece) -> void:
	var selection_changed: bool = piece != displayed_piece
	displayed_piece = piece
	visible=piece!=null
	if not piece: return
	refreshing=true
	var count=build.selection.size()
	%PieceName.text=piece.definition.display_name if count==1 else "%d-piece assembly" % count
	%Details.text="Height: %s m" % ConstructionInput.height_text(piece.position.y) if count==1 else "Heights stay together"
	%Description.text="Rotates around the first selected piece."
	%Description.visible = count > 1
	%Speed.visible=count==1 and piece.definition.behavior=="start"
	%SpeedLabel.visible=%Speed.visible
	%Speed.value=piece.configuration.get("release_speed",1.4)
	%ElevatorSettings.visible=count==1 and piece.definition.behavior=="elevator"
	%ElevatorHeight.value=piece.configuration.get("elevator_height",4.0)
	%ElevatorSpeed.value=piece.configuration.get("elevator_speed",0.8)
	%SupportSettings.visible=count==1 and piece.definition.behavior=="resizable_support"
	%SupportHeight.value=piece.configuration.get("support_height",2.0)
	%SupportTop.select(1 if piece.configuration.get("support_double_top",false) else 0)
	%Details.visible=piece.definition.authoring_only
	%Description.hide()
	%Lower.visible=piece.definition.authoring_only
	%Raise.visible=piece.definition.authoring_only
	var editable: bool=not build.rules or build.rules.permits(piece.instance_id,"configure")
	for field in [%Speed,%ElevatorHeight,%ElevatorSpeed,%SupportHeight]: field.editable=editable
	%SupportTop.disabled=not editable
	if selection_changed: %LinkSettings.hide()
	%LinksToggle.visible=count==1 and not piece.supported_events().is_empty()
	refreshing=false
	if selection_changed: fit_content.call_deferred()

func fit_content() -> void:
	if not is_inside_tree(): return
	%Scroll.custom_minimum_size.y=minf(%Scroll.get_child(0).get_combined_minimum_size().y,get_viewport().get_visible_rect().size.y*0.65)

func change_elevator(key: String, value: float, label: String) -> void:
	if refreshing or not build.selected or not build.enabled: return
	var config=build.selected.configuration.duplicate(true)
	config[key]=value
	build.configure_selected(config,label)

func change_support_top(double_top: bool) -> void:
	if refreshing or not build.selected or not build.enabled: return
	var config=build.selected.configuration.duplicate(true)
	config.support_double_top=double_top
	build.configure_selected(config,"Support top style")

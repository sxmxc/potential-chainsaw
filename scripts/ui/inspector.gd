extends PanelContainer
var build: BuildManager
var refreshing: bool = false
func configure(manager: BuildManager) -> void:
	build=manager
	%MechanismSettings.configure(manager)
	%LinkSettings.configure(manager)
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
	visible=piece!=null
	if not piece: return
	refreshing=true
	var count=build.selection.size()
	%PieceName.text=piece.definition.display_name if count==1 else "%d-piece assembly" % count
	%Details.text=piece.definition.category+"\nElevation %s m" % ConstructionInput.height_text(piece.position.y) if count==1 else "Move, rotate or duplicate together.\nRelative heights stay connected."
	%Description.text="Drag to move · double-click to select connected tracks" if count==1 else "First selected piece is the rotation anchor."
	%Description.visible = count != 1 or piece.mechanism_component == null
	if count==1 and piece.support_component: %Description.text="Height changes extend the middle. The bottom stays anchored."
	elif count==1 and piece.elevator_component: %Description.text="Connect the lower input and upper output, then Test track to run the buckets."
	%Speed.visible=count==1 and piece.definition.behavior=="start"
	%SpeedLabel.visible=%Speed.visible
	%Speed.value=piece.configuration.get("release_speed",1.4)
	%ElevatorSettings.visible=count==1 and piece.definition.behavior=="elevator"
	%ElevatorHeight.value=piece.configuration.get("elevator_height",4.0)
	%ElevatorSpeed.value=piece.configuration.get("elevator_speed",0.8)
	%SupportSettings.visible=count==1 and piece.definition.behavior=="resizable_support"
	%SupportHeight.value=piece.configuration.get("support_height",2.0)
	%SupportTop.select(1 if piece.configuration.get("support_double_top",false) else 0)
	refreshing=false

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

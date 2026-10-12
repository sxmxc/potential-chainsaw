extends Control
signal action_requested(action: String)
var build: BuildManager
var simulation: SimulationManager
var library_open: bool = true
func configure(manager: BuildManager, simulator: SimulationManager) -> void:
	build=manager
	simulation=simulator
	%FileToolbar.configure(build,simulation)
	%FileToolbar.action_requested.connect(func(action):action_requested.emit(action))
	%BuildToolbar.configure(build,simulation)
	%BuildToolbar.library_toggled.connect(func():library_open=not library_open; refresh())
	%EditToolbar.configure(build)
	%Toolbox.configure(build.catalog)
	%Toolbox.piece_chosen.connect(build.choose)
	%Inspector.configure(build)
	%SelectionOverlay.set_marquee(Rect2(),false)
	%SelectionOverlay.build=build
	%SelectionOverlay.exclusions.assign([%Toolbox,%Inspector,%FileToolbar,%BuildToolbar,%EditToolbar,%Bottom])
	build.marquee_changed.connect(%SelectionOverlay.set_marquee)
	%ExtensionPicker.configure(build)
	build.status_changed.connect(show_status)
	build.options_changed.connect(refresh)
	build.changed.connect(refresh)
	build.history.changed.connect(refresh)
	build.selection_changed.connect(func(_piece):refresh())
	simulation.state_changed.connect(_state_changed)
	refresh()
func refresh() -> void:
	%FileToolbar.refresh()
	%BuildToolbar.refresh(library_open)
	%EditToolbar.refresh()
	%Toolbox.visible=library_open and simulation.state==SimulationManager.State.BUILD
	%Status.text="Drag pieces to move · Shift-click or draw a box to select together" if not build.chosen else "Placing "+build.chosen.display_name+" · point at a connector to attach"
	%Inspector.visible=not build.selection.is_empty() and simulation.state==SimulationManager.State.BUILD and not build.chosen
	%Bottom.size_flags_horizontal=0
	if not build.chosen: %Toolbox.clear_choice()
	else: %Toolbox.set_choice(build.chosen.id)
func show_status(text: String) -> void:
	%Status.text=text
	%Status.theme_type_variation=&"ErrorLabel" if text.begins_with("✕") else &"AccentLabel"
func _state_changed(state: SimulationManager.State, message: String) -> void:
	refresh()
	%Status.text=message
	%Status.theme_type_variation=&"SuccessLabel" if state==SimulationManager.State.SUCCESS else (&"ErrorLabel" if state==SimulationManager.State.FAILED else &"AccentLabel")
func set_track_name(value: String, saved: bool = false) -> void:
	%FileToolbar.has_saved_track=saved
	%FileToolbar.set_track_name(value)
	%FileToolbar.refresh()

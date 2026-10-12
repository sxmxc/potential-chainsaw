extends HBoxContainer
signal action_requested(action: String)
var build: BuildManager
var simulation: SimulationManager
var has_saved_track: bool = false
func configure(manager: BuildManager, simulator: SimulationManager) -> void:
	build=manager
	simulation=simulator
	%Undo.icon=get_theme_icon("undo","SandboxIcons")
	%Redo.icon=get_theme_icon("redo","SandboxIcons")
	%Save.pressed.connect(func():action_requested.emit("save"))
	%SaveAs.pressed.connect(func():action_requested.emit("save_as"))
	%Undo.pressed.connect(build.undo)
	%Redo.pressed.connect(build.redo)
	%Menu.pressed.connect(func():action_requested.emit("menu"))
	%Test.icon=get_theme_icon("play","SandboxIcons")
	%Pause.icon=get_theme_icon("pause","SandboxIcons")
	%Test.pressed.connect(func():simulation.start())
	%Pause.pressed.connect(simulation.toggle_pause)
	%Reset.pressed.connect(simulation.reset)
	refresh()
func refresh() -> void:
	%Undo.disabled=not build.enabled or build.history.cursor==0
	%Redo.disabled=not build.enabled or build.history.cursor>=build.history.commands.size()
	%Save.visible = build.rules == null
	%SaveAs.visible = false
	var state=simulation.state
	%Pause.visible=state in [SimulationManager.State.RUNNING,SimulationManager.State.PAUSED]
	%Pause.text="Resume" if state==SimulationManager.State.PAUSED else "Pause"
	%Reset.visible=state!=SimulationManager.State.BUILD
	%Test.text="Test track" if state==SimulationManager.State.BUILD else "Roll again"
	%SaveStatus.text="Unsaved changes" if build.dirty else ("Saved" if has_saved_track else "New construction")
	%SaveStatus.theme_type_variation="AccentSmallLabel" if build.dirty else "SmallMutedLabel"
func set_track_name(value: String) -> void:
	%TrackName.text=value

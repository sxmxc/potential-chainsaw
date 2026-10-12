extends HFlowContainer
signal library_toggled
var build: BuildManager
var simulation: SimulationManager
func configure(manager: BuildManager, simulator: SimulationManager) -> void:
	build=manager
	simulation=simulator
	%Grid.icon=get_theme_icon("grid","SandboxIcons")
	%Snap.icon=get_theme_icon("snap","SandboxIcons")
	%Select.pressed.connect(build.cancel)
	%Library.pressed.connect(func():library_toggled.emit())
	%Grid.pressed.connect(func():build.grid_visible=not build.grid_visible; build.refresh_grid(); build.options_changed.emit())
	%Snap.pressed.connect(func():build.snapping=not build.snapping; build.refresh_connectors(); build.options_changed.emit())
	%Lower.pressed.connect(func():build.set_height(build.height-build.height_step(Input.is_key_pressed(KEY_SHIFT))))
	%Raise.pressed.connect(func():build.set_height(build.height+build.height_step(Input.is_key_pressed(KEY_SHIFT))))
	%Ground.pressed.connect(func():build.set_height(0.0))
	%FrameAll.pressed.connect(build.frame_all)
func refresh(library_open: bool) -> void:
	%Grid.button_pressed=build.grid_visible
	%Snap.button_pressed=build.snapping
	%Library.button_pressed=library_open
	%Height.text="Level %s m" % ConstructionInput.height_text(build.height)
	%Select.disabled=not build.enabled
	%Select.text="Select" if not build.chosen else "Cancel"
	visible=simulation.state==SimulationManager.State.BUILD
	%Select.visible=build.chosen!=null

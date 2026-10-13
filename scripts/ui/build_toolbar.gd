extends VBoxContainer
signal library_toggled
var wiring: Control
var build: BuildManager
var simulation: SimulationManager
func configure(manager: BuildManager, simulator: SimulationManager) -> void:
	build=manager
	simulation=simulator
	%Connect.pressed.connect(func(): wiring.set_tool(not build.connect_mode))
	%Connections.pressed.connect(wiring.toggle_overlay)
	%Grid.icon=get_theme_icon("grid","SandboxIcons")
	%Snap.icon=get_theme_icon("snap","SandboxIcons")
	%Select.pressed.connect(build.cancel)
	%PlacementRotate.icon=get_theme_icon("rotate","SandboxIcons")
	%PlacementRotate.pressed.connect(build.rotate_piece)
	%Library.pressed.connect(func():library_toggled.emit())
	%Grid.pressed.connect(func():build.grid_visible=not build.grid_visible; build.refresh_grid(); build.options_changed.emit())
	%Snap.pressed.connect(func():build.snapping=not build.snapping; build.refresh_connectors(); build.options_changed.emit())
	%Lower.pressed.connect(func():build.set_height(build.height-build.height_step(Input.is_key_pressed(KEY_SHIFT))))
	%Raise.pressed.connect(func():build.set_height(build.height+build.height_step(Input.is_key_pressed(KEY_SHIFT))))
	%Ground.pressed.connect(func():build.set_height(0.0))
	%FrameAll.pressed.connect(build.frame_all)
	build.status_changed.connect(func(_message):refresh_placement())
func refresh(library_open: bool) -> void:
	%Connect.button_pressed=build.connect_mode
	%Connections.button_pressed=wiring.overlay_enabled
	%Grid.button_pressed=build.grid_visible
	%Snap.button_pressed=build.snapping
	%Library.button_pressed=library_open
	%Library.tooltip_text="Collapse pieces" if library_open else "Expand pieces"
	%Height.text="%s m" % ConstructionInput.height_text(build.height)
	%Select.disabled=not build.enabled
	visible=simulation.state==SimulationManager.State.BUILD
	refresh_placement()

func refresh_placement() -> void:
	%Placement.visible=build.chosen!=null
	if not build.chosen: return
	%ActivePiece.text="%d-piece assembly" % build.preview_items.size() if build.preview_items.size()>1 else build.chosen.display_name
	%ActivePiece.tooltip_text=%ActivePiece.text
	var preview_visible: bool=build.ghost!=null and build.ghost.visible
	var feedback: String=""
	if preview_visible and not build.valid: feedback="✕ "+build.validation_message
	elif preview_visible and build.is_snapped:
		feedback="Aligned"
		if build.candidates.size()>1: feedback+=" · Tab %d/%d" % [build.candidate_index()+1,build.candidates.size()]
	%PlacementState.text=feedback
	%PlacementState.visible=not feedback.is_empty()
	%PlacementState.theme_type_variation=&"ErrorLabel" if preview_visible and not build.valid else &"SmallMutedLabel"

func _process(_delta: float) -> void:
	if build and build.chosen: refresh_placement()

class_name WorkspaceHUD
extends Control
signal action_requested(action: String)
var build: BuildManager
var simulation: SimulationManager
var library_open: bool = true
var session: ConstructionSession
var notification_active: bool = false
var toolbox_motion: UIMotion
var status_motion: UIMotion
var guidance_motion: UIMotion
var displayed_instruction: String = ""

func _ready() -> void:
	toolbox_motion = UIMotion.attach(%Toolbox, Vector2(-UIMotion.PANEL_SHIFT, 0.0))
	status_motion = UIMotion.attach(%Bottom)
	guidance_motion = UIMotion.attach(%Guidance, Vector2(0, UIMotion.PANEL_SHIFT), UIMotion.SURFACE_SCALE)
	ButtonFeedback.install(self)
	%NotificationTimer.timeout.connect(func(): notification_active = false; refresh())
func configure(manager: BuildManager, simulator: SimulationManager, value: ConstructionSession) -> void:
	session = value
	build=manager
	simulation=simulator
	%FileToolbar.configure(build,simulation,session)
	%FileToolbar.action_requested.connect(func(action):action_requested.emit(action))
	%MechanismWiring.configure(build,simulation)
	%BuildToolbar.wiring = %MechanismWiring
	%BuildToolbar.configure(build,simulation)
	%BuildToolbar.library_toggled.connect(func():library_open=not library_open; refresh())
	%EditToolbar.configure(build)
	%Toolbox.configure(build.catalog,build)
	%Toolbox.piece_chosen.connect(func(definition):
		if %PuzzleAuthoring.accepts_inventory(): %PuzzleAuthoring.add_inventory(definition)
		else: build.choose(definition))
	%PuzzleAuthoring.inventory_mode_changed.connect(func(active):
		if %Toolbox.inventory_editing == active: return
		%Toolbox.inventory_editing = active
		if active:
			library_open = true
			build.cancel()
		%Toolbox.refresh()
		refresh())
	%Toolbox.collapsed.connect(func():library_open=false; refresh())
	%DismissGuidance.pressed.connect(func():
		session.get_parent().guidance.dismiss())
	%Inspector.session = session
	%Inspector.configure(build)
	%Inspector.connections_requested.connect(func(): %MechanismWiring.set_tool(true))
	%SelectionOverlay.set_marquee(Rect2(),false)
	%SelectionOverlay.build=build
	%SelectionOverlay.exclusions.assign([%Toolbox,%Inspector,%FileToolbar,%BuildToolbar.get_node("%Placement"),%EditToolbar,%Bottom,%Guidance])
	for control in %BuildToolbar.get_node("%Common").get_children():
		%SelectionOverlay.exclusions.append(control)
	%MechanismWiring.exclusions = %SelectionOverlay.exclusions
	build.marquee_changed.connect(%SelectionOverlay.set_marquee)
	%ExtensionPicker.configure(build)
	build.status_changed.connect(show_status)
	build.options_changed.connect(refresh)
	build.changed.connect(refresh)
	build.changed.connect(func(): if build.rules: %Toolbox.refresh())
	build.history.version_changed.connect(refresh)
	build.selection_changed.connect(func(_piece):refresh())
	simulation.state_changed.connect(_state_changed)
	session.changed.connect(refresh)
	session.get_parent().guidance.changed.connect(refresh_guidance)
	refresh()
func refresh_context() -> void:
	guidance_motion.set_open(false, true)
	displayed_instruction = ""
	%Toolbox.reset_filter()
	%MechanismWiring.clear_interaction()
	%MechanismWiring.overlay_enabled = false
	notification_active = false
	%NotificationTimer.stop()
	%Inspector.refresh(build.selected)
	refresh()

func refresh() -> void:
	%FileToolbar.refresh()
	%BuildToolbar.refresh(library_open)
	%EditToolbar.refresh()
	var show_library: bool = library_open and simulation.state == SimulationManager.State.BUILD
	var focus := get_viewport().gui_get_focus_owner()
	if not show_library and focus and %Toolbox.is_ancestor_of(focus):
		%BuildToolbar.get_node("%Library").grab_focus()
	toolbox_motion.set_open(show_library)
	if not notification_active:
		%Status.text=""
		if build.operation in ["move","duplicate"]:
			%Status.text="Click to place · Esc cancels"
		elif build.chosen:
			%Status.text="Point at a connector to attach" if build.snapping else "Free placement · R rotates · Esc cancels"
		%Status.theme_type_variation=&"MutedLabel"
	status_motion.set_open(not %Status.text.is_empty() and not build.chosen)
	%Inspector.visible=not build.selection.is_empty() and simulation.state==SimulationManager.State.BUILD and not build.chosen and %Inspector.has_properties()
	if %AuthoringSlot.visible or build.connect_mode: %Inspector.hide()
	if not build.chosen: %Toolbox.clear_choice()
	else: %Toolbox.set_choice(build.chosen.id)
	refresh_guidance()

func refresh_guidance() -> void:
	if not session:
		guidance_motion.set_open(false, true)
		return
	var guidance: WorldGuidance = session.get_parent().guidance
	var instruction := guidance.instruction
	if not instruction.is_empty():
		var temporary := not guidance.temporary.is_empty()
		var step := guidance.active_step()
		var manual: bool = step.get("complete", "dismissed") == "dismissed"
		var count: int = session.puzzle.get("guidance", []).size()
		%GuidanceProgress.visible = not temporary and count > 1
		%GuidanceProgress.text = "%d / %d" % [guidance.step_index + 1, count]
		%DismissGuidance.visible = session.is_playing and (temporary or manual)
		%DismissGuidance.text = "Close" if temporary else ("Done" if count > 0 and guidance.step_index == count - 1 else "Next")
		%DismissGuidance.tooltip_text = "Close preview" if temporary else "Show the next hint"
		%GuidanceText.text = instruction
		if instruction != displayed_instruction and guidance_motion.wanted: UIMotion.section(%GuidanceText)
	guidance_motion.set_open(not instruction.is_empty())
	displayed_instruction = instruction

func show_status(text: String) -> void:
	if build.chosen:
		notification_active=false
		%NotificationTimer.stop()
		status_motion.set_open(false)
		%BuildToolbar.refresh_placement()
		return
	%Status.text=text
	status_motion.set_open(not text.is_empty())
	notification_active=build.operation.is_empty() and not text.is_empty()
	%NotificationTimer.stop()
	if notification_active: %NotificationTimer.start()
	%Status.theme_type_variation=&"ErrorLabel" if text.begins_with("✕") else &"AccentLabel"
func _state_changed(state: SimulationManager.State, message: String) -> void:
	notification_active=false
	%NotificationTimer.stop()
	refresh()
	%Status.text=message
	status_motion.set_open(not %Status.text.is_empty())
	%Status.theme_type_variation=&"SuccessLabel" if state==SimulationManager.State.SUCCESS else (&"ErrorLabel" if state==SimulationManager.State.FAILED else &"AccentLabel")

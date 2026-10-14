class_name WorkspaceHUD
extends Control
signal action_requested(action: String)
var build: BuildManager
var simulation: SimulationManager
var library_open: bool = true
var session: ConstructionSession
var guidance_done: Dictionary = {}
var notification_until: int = 0
const Copy = preload("res://scripts/ui/puzzle_copy.gd")
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
	%Toolbox.piece_chosen.connect(build.choose)
	%Toolbox.collapsed.connect(func():library_open=false; refresh())
	%DismissGuidance.pressed.connect(func():
		if session: guidance_done[session.puzzle.get("id","")]=true
		refresh())
	%Inspector.session = session
	%Inspector.configure(build)
	%Inspector.connections_requested.connect(func(): %MechanismWiring.set_tool(true))
	%SelectionOverlay.set_marquee(Rect2(),false)
	%SelectionOverlay.build=build
	%SelectionOverlay.exclusions.assign([%Toolbox,%Inspector,%FileToolbar,%BuildToolbar.get_node("%Placement"),%EditToolbar,%Bottom])
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
	simulation.objective_progress.connect(func(): %FileToolbar.refresh())
	refresh()
func refresh_context() -> void:
	%Toolbox.reset_filter()
	%MechanismWiring.clear_interaction()
	%MechanismWiring.overlay_enabled = false
	notification_until = 0
	%Inspector.refresh(build.selected)
	refresh()

func _process(_delta: float) -> void:
	if not build: return
	if notification_until > 0 and Time.get_ticks_msec() >= notification_until:
		notification_until=0
		refresh()

func refresh() -> void:
	%FileToolbar.refresh()
	%BuildToolbar.refresh(library_open)
	%EditToolbar.refresh()
	%Toolbox.visible=library_open and simulation.state==SimulationManager.State.BUILD
	if notification_until==0:
		%Status.text=""
		if build.operation in ["move","duplicate"]:
			%Status.text="Click to place · Esc cancels"
		elif build.chosen:
			%Status.text="Point at a connector to attach" if build.snapping else "Free placement · R rotates · Esc cancels"
		%Status.theme_type_variation=&"MutedLabel"
	%Bottom.visible=not %Status.text.is_empty()
	if build.chosen: %Bottom.hide()
	%Inspector.visible=not build.selection.is_empty() and simulation.state==SimulationManager.State.BUILD and not build.chosen and %Inspector.has_properties()
	if %AuthoringSlot.visible or build.connect_mode: %Inspector.hide()
	%Bottom.size_flags_horizontal=0
	if not build.chosen: %Toolbox.clear_choice()
	else: %Toolbox.set_choice(build.chosen.id)
	refresh_guidance()

func refresh_guidance() -> void:
	%Guidance.hide()
	if not session or session.context != ConstructionSession.Context.PUZZLE_PLAY or session.puzzle.is_empty(): return
	if simulation.state != SimulationManager.State.BUILD: return
	if not session.store.is_official(session.puzzle): return
	var id: String = session.puzzle.id
	if session.store.completed(id) or guidance_done.has(id): return
	var copy: Dictionary=Copy.introduction(session.puzzle)
	if copy.is_empty() and not session.puzzle.campaign.chapter.get("introduction",false): return
	if build.dirty:
		guidance_done[id]=true
		return
	var hint: String=copy.get("begin","")
	if build.chosen: hint=copy.get("placing",hint)
	elif build.selected and build.selected.definition.behavior==copy.get("behavior",""):
		hint=copy.get("selected",hint)
	if hint.is_empty():
		var hints: Array=session.puzzle.get("hints",[])
		if not hints.is_empty(): hint=str(hints[0])
	%GuidanceText.text=hint
	%Guidance.visible=not hint.is_empty()

func show_status(text: String) -> void:
	if build.chosen:
		notification_until=0
		%Bottom.hide()
		%BuildToolbar.refresh_placement()
		return
	%Status.text=text
	%Bottom.visible=not text.is_empty()
	notification_until=Time.get_ticks_msec()+4000 if build.operation.is_empty() else 0
	%Status.theme_type_variation=&"ErrorLabel" if text.begins_with("✕") else &"AccentLabel"
func _state_changed(state: SimulationManager.State, message: String) -> void:
	notification_until=0
	refresh()
	%Status.text=message
	%Bottom.visible=not %Status.text.is_empty()
	%Status.theme_type_variation=&"SuccessLabel" if state==SimulationManager.State.SUCCESS else (&"ErrorLabel" if state==SimulationManager.State.FAILED else &"AccentLabel")

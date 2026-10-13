extends HBoxContainer
signal action_requested(action: String)
var build: BuildManager
var simulation: SimulationManager
var has_saved_track: bool = false
var session: PuzzleSession
var cameras: SimulationCamera
const FOLLOW_ICON = preload("res://assets/ui/icons/follow.svg")
const Copy = preload("res://scripts/ui/puzzle_copy.gd")
func configure(manager: BuildManager, simulator: SimulationManager) -> void:
	build=manager
	simulation=simulator
	cameras=simulation.get_parent().simulation_camera
	%FollowMarble.pressed.connect(cameras.toggle_follow)
	%NextMarble.pressed.connect(cameras.next_marble)
	cameras.changed.connect(refresh_camera)
	%Undo.icon=get_theme_icon("undo","SandboxIcons")
	%Redo.icon=get_theme_icon("redo","SandboxIcons")
	%Save.pressed.connect(func():action_requested.emit("save"))
	%Open.pressed.connect(func():action_requested.emit("open_puzzle"))
	%SaveAs.pressed.connect(func():action_requested.emit("save_as"))
	%Undo.pressed.connect(build.undo)
	%Redo.pressed.connect(build.redo)
	%Menu.pressed.connect(func():action_requested.emit("menu"))
	%Author.pressed.connect(func():action_requested.emit("author"))
	%Test.icon=get_theme_icon("play","SandboxIcons")
	%Pause.icon=get_theme_icon("pause","SandboxIcons")
	%Test.pressed.connect(func():
		if session and session.mode == "editor": session.test_player()
		else: simulation.start())
	%Pause.pressed.connect(simulation.toggle_pause)
	%Reset.pressed.connect(simulation.reset)
	refresh()
func refresh() -> void:
	%Undo.disabled=not build.enabled or not build.history.has_undo()
	%Redo.disabled=not build.enabled or not build.history.has_redo()
	%Save.visible = not session or session.mode in ["sandbox", "editor"]
	%Open.visible = session != null and session.mode == "editor"
	%Save.tooltip_text = "Save draft · Ctrl+S" if session and session.mode == "editor" else "Save track · Ctrl+S"
	%SaveAs.visible = false
	%Author.visible=session!=null and session.mode=="editor"
	var state=simulation.state
	%Pause.visible=state in [SimulationManager.State.RUNNING,SimulationManager.State.PAUSED]
	%Pause.tooltip_text="Resume · Space" if state==SimulationManager.State.PAUSED else "Pause · Space"
	%Pause.icon=get_theme_icon("play" if state==SimulationManager.State.PAUSED else "pause","SandboxIcons")
	%Reset.visible=state!=SimulationManager.State.BUILD
	%Test.tooltip_text="Test as player" if session and session.mode=="editor" else ("Test track · Space" if state==SimulationManager.State.BUILD else "Try again · Space")
	%Test.text="Test as player" if session and session.mode=="editor" else ""
	%Test.visible=state not in [SimulationManager.State.RUNNING,SimulationManager.State.PAUSED]
	%Undo.visible=state==SimulationManager.State.BUILD
	%Redo.visible=%Undo.visible
	%SaveStatus.text="Unsaved changes" if build.dirty else ("Saved" if has_saved_track else "")
	%SaveStatus.theme_type_variation="AccentSmallLabel" if build.dirty else "SmallMutedLabel"
	%Progress.visible=false
	if session and session.mode != "sandbox":
		%SaveStatus.text = "Draft" if session.mode == "editor" else Copy.objective(session.puzzle)
		%SaveStatus.theme_type_variation="MutedLabel"
		var counts: Array[String] = []
		for objective in session.puzzle.get("objectives", []):
			if objective.get("type", "deliver") == "activate":
				counts.append("Activated" if simulation.objectives.activations.has(objective.target + ":" + objective.get("event", "activated")) else "Waiting")
			else:
				var count = 0
				for delivery in simulation.objectives.deliveries.values():
					if delivery.collector == objective.target and (objective.get("source", "").is_empty() or delivery.source == objective.source): count += 1
				counts.append("%d / %d arrived" % [count, objective.get("count", 1)])
		%Progress.text = " · ".join(counts)
		%Progress.visible = session.mode != "editor" and not counts.is_empty()
	%SaveStatus.visible=not %SaveStatus.text.is_empty()
	%SaveStatus.tooltip_text=%SaveStatus.text
	%Identity.custom_minimum_size.x = 360 if session and session.mode in ["campaign", "test"] else 220
	%Reset.tooltip_text = "Return to build"
	refresh_camera()

func _process(_delta: float) -> void:
	if cameras: refresh_camera()

func refresh_camera() -> void:
	if not cameras: return
	var active = simulation.state in [SimulationManager.State.RUNNING,SimulationManager.State.PAUSED]
	var following = is_instance_valid(cameras.chase.marble)
	var count = cameras.available().size() if active else 0
	%FollowMarble.visible=active
	%FollowMarble.disabled=count==0 and not following
	%FollowMarble.set_pressed_no_signal(following)
	%FollowMarble.tooltip_text="Stop following" if following else "Follow marble"
	%FollowMarble.icon=get_theme_icon("cancel","SandboxIcons") if following else FOLLOW_ICON
	%NextMarble.visible=active and following and count>1
func set_track_name(value: String) -> void:
	%TrackName.text=value

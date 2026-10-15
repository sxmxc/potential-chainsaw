class_name ConstructionWorkspace
extends Node3D

signal action_requested(action: String)
signal activated
signal message_requested(text: String)
signal modal_opened
signal modal_closed

@onready var world: WorldManager = $World
@onready var session: ConstructionSession = $Session
@onready var hud: WorkspaceHUD = $Interface/HUD
@onready var authoring: PanelContainer = hud.get_node("%PuzzleAuthoring")
var catalog: PieceCatalog

func _ready() -> void:
	catalog = PieceCatalog.new()
	world.configure(catalog)
	session.configure(world, catalog)
	world.boundary.configure(session)
	hud.configure(world.build, world.simulation, session)
	authoring.configure(session)
	authoring.action_requested.connect(_request_action)
	authoring.visibility_changed.connect(func():
		hud.get_node("%AuthoringSlot").visible = authoring.visible
		hud.refresh())
	authoring.modal_opened.connect(modal_opened.emit)
	authoring.modal_closed.connect(modal_closed.emit)
	hud.action_requested.connect(_request_action)
	session.context_changed.connect(_context_changed)
	session.message_requested.connect(message_requested.emit)
	session.sandbox()

func _context_changed() -> void:
	authoring.hide()
	hud.refresh_context()
	activate()

func activate() -> void:
	show()
	hud.show()
	resume_input()
	activated.emit()

func deactivate() -> void:
	world.simulation.reset()
	world.build.cancel()
	world.boundary.cancel()
	suspend_input()
	authoring.hide()
	hud.hide()
	hide()

func suspend_input() -> void:
	world.boundary.cancel()
	world.build.enabled = false
	world.camera.enabled = false
	if world.build.ghost: world.build.ghost.hide()
	world.build.refresh_grid()

func resume_input() -> void:
	world.build.enabled = is_visible_in_tree() and world.simulation.state == SimulationManager.State.BUILD and world.boundary.tool.is_empty() and not world.boundary.selecting
	world.camera.enabled = is_visible_in_tree()
	world.build.refresh_grid()
	hud.refresh()

func has_modal() -> bool:
	return authoring.get_node("%ExportDialog").visible

func _request_action(action: String) -> void:
	if not handle_action(action): action_requested.emit(action)

# Context actions live here; application navigation and personal-save dialogs
# travel through action_requested to the application that hosts this workspace.
func handle_action(action: String) -> bool:
	match action:
		"author":
			if session.is_authoring: authoring.open()
		"test": session.start_simulation()
		"test_player":
			if session.is_authoring: session.test_player()
		"pause": world.simulation.toggle_pause()
		"reset": world.simulation.reset()
		"return_editor": session.return_editor()
		"preserve_solution":
			if session.preserve_solution(): world.build.show_status("Solution saved")
		"reference": session.restore_reference()
		"restart_puzzle":
			if session.is_playing: session.player(session.puzzle, session.is_testing)
		"save", "save_as":
			if not session.is_authoring: return false
			if not session.save_draft(): message_requested.emit("Could not save the puzzle draft")
		_: return false
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or ConstructionInput.typing(get_viewport()): return
	if event.is_action_pressed("build_save_track", false, true):
		_request_action("save")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_test_track", false, true) and world.camera.enabled:
		if world.simulation.state in [SimulationManager.State.RUNNING, SimulationManager.State.PAUSED]:
			world.simulation.toggle_pause()
		else:
			session.start_simulation()
		get_viewport().set_input_as_handled()

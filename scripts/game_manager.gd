extends Node

@onready var sandbox = $World
var puzzle_session: PuzzleSession
var authoring: Control
var puzzle_browser: Window
var puzzle_bar: PanelContainer
var completion: Window
var catalog: PieceCatalog
var serializer: TrackSerializer
var track_name: String = "Untitled track"
var track_id: String = ""
var name_dialog
var name_field: LineEdit
var unsaved_dialog
var menu_dialog
var settings_dialog
var message_dialog
var save_as: bool = false
var pending_action: Callable
var after_save: Callable
var music_context: String = ""
var settings = preload("res://scripts/game_settings.gd").new()

func _ready() -> void:
	ConstructionInput.install()
	get_tree().auto_accept_quit=false
	catalog=PieceCatalog.new()
	serializer=TrackSerializer.new(catalog)
	sandbox.configure(catalog)
	%HUD.configure(sandbox.build,sandbox.simulation)
	%MainMenu.action_requested.connect(handle_action)
	%HUD.action_requested.connect(handle_action)
	%TrackBrowser.serializer=serializer
	%TrackBrowser.track_requested.connect(func(id,example):guard(func():load_track(id,example)))
	%TrackBrowser.closed.connect(modal_closed)
	sandbox.build.changed.connect(update_name)
	create_dialogs()
	puzzle_session = PuzzleSession.new()
	add_child(puzzle_session)
	puzzle_session.configure(self)
	authoring = preload("res://scenes/ui/puzzle_authoring.tscn").instantiate()
	puzzle_browser = preload("res://scenes/ui/puzzle_browser.tscn").instantiate()
	%HUD.get_node("Margin/Layout/Body").add_child(authoring)
	add_child(puzzle_browser)
	authoring.configure(puzzle_session)
	puzzle_browser.configure(puzzle_session)
	puzzle_bar = preload("res://scenes/ui/puzzle_bar.tscn").instantiate()
	var layout = %HUD.get_node("Margin/Layout")
	layout.add_child(puzzle_bar)
	layout.move_child(puzzle_bar, 1)
	puzzle_bar.configure(puzzle_session)
	completion = preload("res://scenes/ui/puzzle_completion.tscn").instantiate()
	add_child(completion)
	completion.configure(puzzle_session)
	puzzle_session.mode_changed.connect(func():
		if puzzle_session.mode != "editor": authoring.hide()
		%HUD.get_node("%Toolbox").refresh()
		%HUD.refresh())
	%HUD.configure_session(puzzle_session)
	new_track(false)
	show_main_menu()
	load_settings()

func create_dialogs() -> void:
	name_dialog=%NameDialog
	name_field=name_dialog.get_node("Surface/Contents/Name")
	unsaved_dialog=%UnsavedDialog
	menu_dialog=%SandboxMenu
	settings_dialog=%SettingsDialog
	message_dialog=%MessageDialog
	name_dialog.confirmed.connect(finish_save)
	name_dialog.closed.connect(func():after_save=Callable(); modal_closed())
	unsaved_dialog.confirmed.connect(func():
		after_save=pending_action
		if track_id.is_empty(): prompt_save(false)
		else:
			if save_current(): run_after_save(); modal_closed())
	unsaved_dialog.custom_action.connect(func(action):
		if action==&"discard":
			var next=pending_action
			pending_action=Callable()
			next.call()
			modal_closed())
	unsaved_dialog.closed.connect(func():pending_action=Callable(); modal_closed())
	menu_dialog.action_requested.connect(handle_action)
	menu_dialog.closed.connect(modal_closed)
	settings_dialog.closed.connect(modal_closed)
	settings_dialog.reset_camera.connect(sandbox.camera.reset_view)
	settings_dialog.configure(settings)
	settings_dialog.settings_changed.connect(func(window_changed): settings.apply(self, window_changed); save_settings())
	message_dialog.closed.connect(modal_closed)
func handle_action(action: String) -> void:
	match action:
		"campaign": puzzle_browser.open_campaign()
		"puzzle_editor": puzzle_session.editor()
		"sandbox":
			if puzzle_session.mode != "sandbox": new_track()
			elif not %HUD.visible: enter_sandbox()
		"save":
			if puzzle_session.mode == "editor": puzzle_session.save(); return
			if puzzle_session.mode in ["campaign", "test"]: return
			if track_id.is_empty(): prompt_save(false)
			else: save_current(); modal_closed()
		"save_as":
			if puzzle_session.mode == "editor": puzzle_session.save()
			elif puzzle_session.mode == "sandbox": prompt_save(true)
		"rename": prompt_save(false)
		"load", "examples": open_modal(); %TrackBrowser.open(action=="examples")
		"menu": open_modal(); menu_dialog.configure_mode(puzzle_session); menu_dialog.popup_centered()
		"restart_puzzle": puzzle_session.player(puzzle_session.puzzle, puzzle_session.mode == "test"); modal_closed()
		"levels": puzzle_browser.open()
		"author": authoring.open()
		"test_player": puzzle_session.test_player(); modal_closed()
		"return_editor": puzzle_session.return_editor(); modal_closed()
		"preserve_solution":
			if puzzle_session.preserve_solution(): %HUD.show_status("Solution saved")
			modal_closed()
		"reference": puzzle_session.restore_reference(); modal_closed()
		"settings":
			# Preserve an active modal rather than opening a second exclusive Window.
			for dialog in [puzzle_browser,%TrackBrowser,name_dialog,unsaved_dialog,message_dialog,menu_dialog]:
				if dialog and dialog.visible and dialog.exclusive: return
			open_modal()
			settings_dialog.popup_centered()
		"new": guard(new_track)
		"main": guard(show_main_menu)
		"quit": guard(func():get_tree().quit())

func enter_sandbox() -> void:
	if music_context != "world":
		sandbox.play_music()
		music_context = "world"
	%MainMenu.showcase.set_active(false)
	sandbox.show()
	%MainMenu.hide()
	%HUD.show()
	sandbox.build.enabled=sandbox.simulation.state==SimulationManager.State.BUILD
	sandbox.camera.enabled=true
	sandbox.build.refresh_grid()
	%HUD.refresh()
	update_name()

func show_main_menu() -> void:
	if music_context != "menu":
		%MainMenu.play_music()
		music_context = "menu"
	sandbox.simulation.reset()
	sandbox.build.cancel()
	sandbox.build.enabled=false
	sandbox.camera.enabled=false
	sandbox.build.refresh_grid()
	%HUD.hide()
	%MainMenu.show()
	%MainMenu.get_node("%Sandbox").text="Continue building" if not sandbox.build.pieces.is_empty() else "Sandbox"
	sandbox.hide()
	%MainMenu.showcase.set_active(true)

func new_track(enter_world: bool = true) -> void:
	if puzzle_session: puzzle_session.sandbox()
	sandbox.load_construction([])
	track_name="Untitled track"
	track_id=""
	if enter_world:
		enter_sandbox()

func load_track(id: String, example: bool) -> void:
	if puzzle_session: puzzle_session.sandbox()
	var example_path = "res://resources/menu_machine.json" if id == "menu-machine" else "res://resources/examples/"+id+".json"
	var data=serializer.decode(FileAccess.get_file_as_string(example_path)) if example else serializer.load_track(id)
	if data.is_empty(): show_message(serializer.last_error); return
	sandbox.load_construction(data.pieces)
	if example and id == "menu-machine":
		# Use the same open-ended physical circulation as the menu showcase.
		sandbox.simulation.puzzle = {"objectives": [], "time_limit": 3600}
	track_name=data.name
	track_id="" if example else id
	enter_sandbox()
	if not serializer.warnings.is_empty(): show_message("\n".join(serializer.warnings))

func guard(action: Callable) -> void:
	if puzzle_session and puzzle_session.mode in ["campaign", "test"]:
		action.call()
		modal_closed()
		return
	if puzzle_session and puzzle_session.mode == "editor" and sandbox.build.dirty:
		if not puzzle_session.save(): show_message("Could not save the puzzle draft"); return
		action.call()
		modal_closed()
		return
	if sandbox.build.dirty:
		pending_action=action
		open_modal()
		unsaved_dialog.popup_centered()
	else: action.call(); modal_closed()

func prompt_save(as_copy: bool) -> void:
	save_as=as_copy
	name_field.text=track_name+" copy" if as_copy else track_name
	open_modal()
	name_dialog.popup_centered()
	name_field.grab_focus()
	name_field.select_all()

func finish_save() -> void:
	if name_field.text.strip_edges().is_empty(): show_message("Please enter a track name"); after_save=Callable(); return
	var old_name=track_name
	var old_id=track_id
	track_name=name_field.text.strip_edges()
	if save_as: track_id=""
	if not save_current(): track_name=old_name; track_id=old_id; after_save=Callable(); return
	run_after_save()
	modal_closed()

func save_current() -> bool:
	var id=serializer.save_track(track_name,sandbox.build.snapshot(),track_id)
	if id.is_empty(): show_message(serializer.last_error); return false
	track_id=id
	sandbox.build.dirty=false
	update_name()
	%HUD.show_status("Track saved")
	return true

func run_after_save() -> void:
	if after_save.is_valid() and not sandbox.build.dirty:
		var action=after_save
		after_save=Callable()
		pending_action=Callable()
		action.call()

func update_name() -> void:
	%HUD.set_track_name(track_name,not track_id.is_empty())

func open_modal() -> void:
	sandbox.build.enabled=false
	sandbox.camera.enabled=false
	if sandbox.build.ghost: sandbox.build.ghost.visible=false

func modal_closed() -> void:
	for dialog in [name_dialog,unsaved_dialog,menu_dialog,settings_dialog,message_dialog,%TrackBrowser,puzzle_browser]:
		if dialog and dialog.visible: return
	sandbox.build.enabled=%HUD.visible and sandbox.simulation.state==SimulationManager.State.BUILD
	sandbox.camera.enabled=%HUD.visible
	sandbox.build.refresh_grid()
	%HUD.refresh()

func show_message(text: String) -> void:
	open_modal()
	message_dialog.dialog_text=text
	message_dialog.popup_centered(Vector2i(500,160))

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST: handle_action("quit")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_P and not ConstructionInput.typing(get_viewport()):
		guard(func(): puzzle_session.editor())
		get_viewport().set_input_as_handled()
		return
	if ConstructionInput.typing(get_viewport()) or not %HUD.visible: return
	if event.is_action_pressed("build_save_track",false,true): handle_action("save")
	elif event.is_action_pressed("build_test_track",false,true):
		if sandbox.simulation.state in [SimulationManager.State.RUNNING,SimulationManager.State.PAUSED]: sandbox.simulation.toggle_pause()
		elif sandbox.camera.enabled:
			if puzzle_session.mode=="editor": puzzle_session.test_player()
			else: sandbox.simulation.start()

func save_settings() -> void:
	if settings.save() != OK: show_message("Couldn't save settings.")

func load_settings() -> void:
	settings.load_saved()
	settings.apply(self)
	settings_dialog.refresh_values()

func qa_summary() -> Dictionary:
	var hovered=get_viewport().gui_get_hovered_control()
	return {"pieces":sandbox.build.pieces.size(),"selected":sandbox.build.selection.size(),"operation":sandbox.build.operation,"candidates":sandbox.build.candidates.size(),"state":sandbox.simulation.state,"dirty":sandbox.build.dirty,"track":track_name,"catalog":catalog.pieces.size(),"height":sandbox.build.height,"main_menu":%MainMenu.visible,"ghost":sandbox.build.ghost!=null and sandbox.build.ghost.visible,"valid":sandbox.build.valid,"hovered":str(hovered.get_path()) if hovered else "","mouse":str(get_viewport().get_mouse_position())}

func qa_example(id: String) -> void:
	load_track(id,true)

func qa_test() -> bool:
	return sandbox.simulation.start()

func qa_resolution(width: int, height: int) -> Dictionary:
	get_window().size=Vector2i(width,height)
	# Embedded play can pin the native window size. Set the actual render viewport
	# as well so UI evidence uses the requested dimensions, without another game.
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect=Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size=Vector2i(width,height)
	return {"window":str(get_window().size),"viewport":str(get_viewport().get_visible_rect().size)}

func qa_choose(id: String) -> void:
	sandbox.build.choose(catalog.get_piece(id))

func qa_select(index: int) -> void:
	if index>=0 and index<sandbox.build.pieces.size(): sandbox.build.select(sandbox.build.pieces[index])

func qa_showcase() -> Dictionary:
	var showcase=%MainMenu.showcase
	return {"active":showcase.active,"loops":showcase.loops,"state":showcase.world_manager.simulation.state,"elapsed":showcase.world_manager.simulation.elapsed,"camera_time":showcase.animation.current_animation_position,"separate_world":showcase.world_manager.get_world_3d()!=sandbox.get_world_3d(),"position":str(showcase.world_manager.simulation.marble.position) if showcase.world_manager.simulation.marble else "none"}

func qa_screen(index: int) -> Dictionary:
	var piece=sandbox.build.pieces[index]
	var screen=sandbox.camera.unproject_position(piece.position+Vector3(0,0.25,0))
	return {"screen":[screen.x,screen.y],"position":str(piece.position),"piece":String(piece.definition.id)}

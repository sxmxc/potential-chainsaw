extends Node

@onready var sandbox = $Sandbox
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
	new_track()
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
	settings_dialog.sensitivity_changed.connect(func(value):sandbox.camera.sensitivity=value; save_settings())
	message_dialog.closed.connect(modal_closed)
func handle_action(action: String) -> void:
	match action:
		"sandbox":
			if not %HUD.visible: enter_sandbox()
		"save":
			if track_id.is_empty(): prompt_save(false)
			else: save_current(); modal_closed()
		"save_as": prompt_save(true)
		"rename": prompt_save(false)
		"load", "examples": open_modal(); %TrackBrowser.open(action=="examples")
		"menu": open_modal(); menu_dialog.popup_centered()
		"settings": open_modal(); settings_dialog.popup_centered()
		"new": guard(new_track)
		"main": guard(show_main_menu)
		"quit": guard(func():get_tree().quit())

func enter_sandbox() -> void:
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
	sandbox.simulation.reset()
	sandbox.build.cancel()
	sandbox.build.enabled=false
	sandbox.camera.enabled=false
	sandbox.build.refresh_grid()
	%HUD.hide()
	%MainMenu.show()
	%MainMenu.get_node("%Sandbox").text="Continue building" if not sandbox.build.pieces.is_empty() else "Start building"
	sandbox.hide()
	%MainMenu.showcase.set_active(true)

func new_track() -> void:
	sandbox.load_construction([])
	track_name="Untitled track"
	track_id=""
	enter_sandbox()

func load_track(id: String, example: bool) -> void:
	var data=serializer.decode(FileAccess.get_file_as_string("res://resources/examples/"+id+".json")) if example else serializer.load_track(id)
	if data.is_empty(): show_message(serializer.last_error); return
	sandbox.load_construction(data.pieces)
	track_name=data.name
	track_id="" if example else id
	enter_sandbox()
	if not serializer.warnings.is_empty(): show_message("\n".join(serializer.warnings))

func guard(action: Callable) -> void:
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
	%HUD.show_status("Saved ‘%s’ · %d pieces" % [track_name,sandbox.build.pieces.size()])
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
	for dialog in [name_dialog,unsaved_dialog,menu_dialog,settings_dialog,message_dialog,%TrackBrowser]:
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
	if ConstructionInput.typing(get_viewport()) or not %HUD.visible: return
	if event.is_action_pressed("build_save_track",false,true): handle_action("save")
	elif event.is_action_pressed("build_test_track",false,true):
		if sandbox.simulation.state in [SimulationManager.State.RUNNING,SimulationManager.State.PAUSED]: sandbox.simulation.toggle_pause()
		elif sandbox.camera.enabled: sandbox.simulation.start()

func save_settings() -> void:
	var config=ConfigFile.new()
	config.set_value("camera","sensitivity",sandbox.camera.sensitivity)
	config.save("user://settings.cfg")

func load_settings() -> void:
	var config=ConfigFile.new()
	if config.load("user://settings.cfg")==OK:
		sandbox.camera.sensitivity=clampf(float(config.get_value("camera","sensitivity",1)),0.3,2.5)
		settings_dialog.set_sensitivity(sandbox.camera.sensitivity)

func qa_summary() -> Dictionary:
	var hovered=get_viewport().gui_get_hovered_control()
	return {"pieces":sandbox.build.pieces.size(),"selected":sandbox.build.selection.size(),"operation":sandbox.build.operation,"candidates":sandbox.build.candidates.size(),"state":sandbox.simulation.state,"dirty":sandbox.build.dirty,"track":track_name,"catalog":catalog.pieces.size(),"height":sandbox.build.height,"main_menu":%MainMenu.visible,"ghost":sandbox.build.ghost!=null and sandbox.build.ghost.visible,"valid":sandbox.build.valid,"hovered":str(hovered.get_path()) if hovered else "","mouse":str(get_viewport().get_mouse_position())}

func qa_example(id: String) -> void:
	load_track(id,true)

func qa_test() -> bool:
	return sandbox.simulation.start()

func qa_resolution(width: int, height: int) -> Dictionary:
	get_window().size=Vector2i(width,height)
	return {"window":str(get_window().size),"viewport":str(get_viewport().get_visible_rect().size)}

func qa_choose(id: String) -> void:
	sandbox.build.choose(catalog.get_piece(id))

func qa_select(index: int) -> void:
	if index>=0 and index<sandbox.build.pieces.size(): sandbox.build.select(sandbox.build.pieces[index])

func qa_showcase() -> Dictionary:
	var showcase=%MainMenu.showcase
	return {"active":showcase.active,"loops":showcase.loops,"state":showcase.sandbox.simulation.state,"elapsed":showcase.sandbox.simulation.elapsed,"camera_time":showcase.animation.current_animation_position,"separate_world":showcase.sandbox.get_world_3d()!=sandbox.get_world_3d(),"position":str(showcase.sandbox.simulation.marble.position) if showcase.sandbox.simulation.marble else "none"}

func qa_screen(index: int) -> Dictionary:
	var piece=sandbox.build.pieces[index]
	var screen=sandbox.camera.unproject_position(piece.position+Vector3(0,0.25,0))
	return {"screen":[screen.x,screen.y],"position":str(piece.position),"piece":String(piece.definition.id)}

extends Node
class_name GameManager

@onready var workspace: ConstructionWorkspace = $Workspace
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
var community_service: CommunityService

func _ready() -> void:
	get_tree().auto_accept_quit=false
	workspace.action_requested.connect(handle_action)
	workspace.activated.connect(show_workspace)
	workspace.message_requested.connect(show_message)
	workspace.modal_opened.connect(open_modal)
	workspace.modal_closed.connect(modal_closed)
	%MainMenu.action_requested.connect(handle_action)
	%TrackBrowser.serializer = workspace.session.serializer
	%TrackBrowser.track_requested.connect(func(id, example): guard(func(): workspace.session.load_track(id, example)))
	%TrackBrowser.closed.connect(modal_closed)
	create_dialogs()
	community_service = CommunityService.new()
	add_child(community_service)
	community_service.configure(workspace.session.store, SupabaseCommunityBackend.new())
	%PuzzleBrowser.configure(workspace.session)
	%PuzzleBrowser.configure_online(community_service)
	%PuzzleBrowser.modal_opened.connect(open_modal)
	%PuzzleBrowser.closed.connect(modal_closed)
	%PuzzleCompletion.configure(workspace.session)
	%PuzzleCompletion.levels_requested.connect(func(): %PuzzleBrowser.open(false, not PuzzleStore.is_official(workspace.session.puzzle)))
	show_main_menu()
	load_settings()

func create_dialogs() -> void:
	name_dialog=%NameDialog
	name_field=name_dialog.get_node("Surface/Contents/Name")
	unsaved_dialog=%UnsavedDialog
	menu_dialog=%WorkspaceMenu
	settings_dialog=%SettingsDialog
	message_dialog=%MessageDialog
	name_dialog.confirmed.connect(finish_save)
	name_dialog.closed.connect(func():after_save=Callable(); modal_closed())
	unsaved_dialog.confirmed.connect(func():
		after_save=pending_action
		if workspace.session.track_id.is_empty(): prompt_save(false)
		else:
			if workspace.session.save_track(workspace.session.track_name, workspace.session.track_id): run_after_save(); modal_closed())
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
	settings_dialog.reset_camera.connect(workspace.world.camera.reset_view)
	settings_dialog.configure(settings)
	settings_dialog.settings_changed.connect(func(window_changed): settings.apply(self, window_changed); save_settings())
	message_dialog.closed.connect(modal_closed)
func handle_action(action: String) -> void:
	if workspace.handle_action(action):
		modal_closed()
		return
	match action:
		"campaign": guard(func(): %PuzzleBrowser.open_campaign())
		"puzzle_editor": guard(func(): workspace.session.editor())
		"community": guard(func(): %PuzzleBrowser.open(false, true))
		"publish_online":
			if not workspace.session.is_authoring or workspace.session.official_authoring: return
			var errors := workspace.session.validate()
			if not errors.is_empty(): show_message("\n".join(errors)); return
			if not workspace.session.publish(): return
			workspace.authoring.hide()
			%PuzzleBrowser.open_online(workspace.session.capture())
		"sandbox":
			if not workspace.session.is_sandbox: guard(workspace.session.sandbox)
			else: workspace.activate()
		"save":
			if not workspace.session.is_sandbox: return
			if workspace.session.track_id.is_empty(): prompt_save(false)
			else:
				workspace.session.save_track(workspace.session.track_name, workspace.session.track_id)
				modal_closed()
		"save_as":
			if workspace.session.is_sandbox: prompt_save(true)
		"rename":
			if workspace.session.is_sandbox: prompt_save(false)
		"load", "examples":
			if not workspace.session.is_sandbox: return
			open_modal()
			%TrackBrowser.open(action == "examples")
		"menu":
			open_modal()
			menu_dialog.configure_context(workspace.session)
			menu_dialog.popup_centered()
		"levels": %PuzzleBrowser.open(false, not PuzzleStore.is_official(workspace.session.puzzle))
		"open_puzzle":
			if not workspace.session.is_authoring: return
			guard(func(): workspace.authoring.hide(); %PuzzleBrowser.open(true))
		"settings":
			for dialog in [%PuzzleBrowser,%TrackBrowser,name_dialog,unsaved_dialog,message_dialog,menu_dialog]:
				if dialog and dialog.visible and dialog.exclusive: return
			open_modal()
			settings_dialog.popup_centered()
		"new": guard(workspace.session.sandbox)
		"main": guard(show_main_menu)
		"quit": guard(func(): get_tree().quit())

func show_workspace() -> void:
	if music_context != "world":
		workspace.world.play_music()
		music_context = "world"
	%MainMenu.showcase.set_active(false)
	%MainMenu.hide()

func show_main_menu() -> void:
	if music_context != "menu":
		%MainMenu.play_music()
		music_context = "menu"
	workspace.deactivate()
	%MainMenu.show()
	%MainMenu.get_node("%Sandbox").text = "Continue building" if workspace.session.is_sandbox and not workspace.world.build.pieces.is_empty() else "Sandbox"
	%MainMenu.showcase.set_active(true)

func guard(action: Callable) -> void:
	if workspace.session.is_playing:
		action.call()
		modal_closed()
		return
	if workspace.session.is_authoring and workspace.world.build.dirty:
		if not workspace.session.save_draft(): show_message("Could not save the puzzle draft"); return
		action.call()
		modal_closed()
		return
	if workspace.world.build.dirty:
		pending_action=action
		open_modal()
		unsaved_dialog.popup_centered()
	else: action.call(); modal_closed()

func prompt_save(as_copy: bool) -> void:
	save_as=as_copy
	name_field.text=workspace.session.track_name+" copy" if as_copy else workspace.session.track_name
	open_modal()
	name_dialog.popup_centered()
	name_field.grab_focus()
	name_field.select_all()

func finish_save() -> void:
	if name_field.text.strip_edges().is_empty(): show_message("Please enter a track name"); after_save=Callable(); return
	var id := "" if save_as else workspace.session.track_id
	if not workspace.session.save_track(name_field.text, id): after_save=Callable(); return
	run_after_save()
	modal_closed()

func run_after_save() -> void:
	if after_save.is_valid() and not workspace.world.build.dirty:
		var action=after_save
		after_save=Callable()
		pending_action=Callable()
		action.call()

func open_modal() -> void:
	workspace.suspend_input()

func modal_closed() -> void:
	for dialog in [name_dialog,unsaved_dialog,menu_dialog,settings_dialog,message_dialog,%TrackBrowser,%PuzzleBrowser]:
		if dialog and dialog.visible: return
	if workspace.has_modal(): return
	workspace.resume_input()

func show_message(text: String) -> void:
	open_modal()
	message_dialog.dialog_text=text
	message_dialog.popup_centered(Vector2i(500,160))

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST: handle_action("quit")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_P and not ConstructionInput.typing(get_viewport()):
		if workspace.session.store.can_add_to_campaign(): guard(func(): workspace.session.editor({}, true))
		get_viewport().set_input_as_handled()
		return

func save_settings() -> void:
	if settings.save() != OK: show_message("Couldn't save settings.")

func load_settings() -> void:
	settings.load_saved()
	settings.apply(self)
	settings_dialog.refresh_values()

func qa_summary() -> Dictionary:
	var hovered=get_viewport().gui_get_hovered_control()
	return {"pieces":workspace.world.build.pieces.size(),"selected":workspace.world.build.selection.size(),"operation":workspace.world.build.operation,"candidates":workspace.world.build.candidates.size(),"state":workspace.world.simulation.state,"dirty":workspace.world.build.dirty,"track":workspace.session.track_name,"catalog":workspace.catalog.REGISTRY.size(),"height":workspace.world.build.height,"main_menu":%MainMenu.visible,"ghost":workspace.world.build.ghost!=null and workspace.world.build.ghost.visible,"valid":workspace.world.build.valid,"hovered":str(hovered.get_path()) if hovered else "","mouse":str(get_viewport().get_mouse_position())}

func qa_example(id: String) -> void:
	workspace.session.load_track(id,true)

func qa_test() -> bool:
	return workspace.world.simulation.start()

func qa_resolution(width: int, height: int) -> Dictionary:
	get_window().size=Vector2i(width,height)
	# Embedded play can pin the native window size. Set the actual render viewport
	# as well so UI evidence uses the requested dimensions, without another game.
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect=Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size=Vector2i(width,height)
	return {"window":str(get_window().size),"viewport":str(get_viewport().get_visible_rect().size)}

func qa_choose(id: String) -> void:
	workspace.world.build.choose(workspace.catalog.get_piece(id))

func qa_select(index: int) -> void:
	if index>=0 and index<workspace.world.build.pieces.size(): workspace.world.build.select(workspace.world.build.pieces[index])

func qa_showcase() -> Dictionary:
	var showcase=%MainMenu.showcase
	return {"active":showcase.active,"loops":showcase.loops,"state":showcase.world_manager.simulation.state,"elapsed":showcase.world_manager.simulation.elapsed,"camera_time":showcase.animation.current_animation_position,"separate_world":showcase.world_manager.get_world_3d()!=workspace.world.get_world_3d(),"position":str(showcase.world_manager.simulation.marble.position) if showcase.world_manager.simulation.marble else "none"}

func qa_screen(index: int) -> Dictionary:
	var piece=workspace.world.build.pieces[index]
	var screen=workspace.world.camera.unproject_position(piece.position+Vector3(0,0.25,0))
	return {"screen":[screen.x,screen.y],"position":str(piece.position),"piece":String(piece.definition.id)}

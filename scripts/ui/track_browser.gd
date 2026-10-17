extends "res://scripts/ui/modal_window.gd"

signal track_requested(id: String, example: bool)
var serializer: TrackSerializer
var rows: Array = []
var examples: bool = false
var confirmation: ConfirmationDialog

func _ready() -> void:
	super()
	%Load.pressed.connect(load_selected)
	%RenameButton.pressed.connect(func():
		if not %Rename.visible:
			%Rename.show()
			%Rename.text=rows[selected_index()].name
			%Rename.grab_focus()
			%Rename.select_all()
			%RenameButton.text="Apply name"
		else: rename_selected())
	%Rename.text_submitted.connect(func(_text): rename_selected())
	%Rename.text_changed.connect(func(text): %RenameButton.disabled=text.strip_edges().is_empty())
	%List.item_selected.connect(func(_index): refresh_actions())
	%Delete.pressed.connect(delete_selected)
	%Close.pressed.connect(close)
	%List.item_activated.connect(func(_index):load_selected())
	confirmation=%DeleteConfirmation
	confirmation.get_ok_button().theme_type_variation = &"DangerButton"
	confirmation.confirmed.connect(func():
		var index=selected_index()
		if index<0: return
		var error=serializer.delete_track(rows[index].id)
		if error!=OK: %Info.text="Could not delete track: "+error_string(error)
		else: refresh())
func open(show_examples: bool = false) -> void:
	examples=show_examples
	title="Example tracks" if examples else "Your tracks"
	%Heading.text="Example tracks" if examples else "Saved tracks"
	%Rename.hide()
	%RenameButton.visible=not examples
	%Delete.visible=not examples
	refresh()
	present()

func refresh() -> void:
	%List.clear()
	rows=[{"id":"first-roll","name":"First Roll · slopes and a sweeping curve","count":7},{"id":"spiral-crossing","name":"Spiral Crossing · two levels and a full helix","count":14},{"id":"bucket-elevator-demo","name":"Bucket Elevator · carry a marble to an upper track","count":4},{"id":"menu-machine","name":"Cascade Foundry · four linked transport banks","count":269}] if examples else serializer.list_tracks()
	for row in rows: %List.add_item(row.name.split(" · ")[0] if examples else row.name)
	if not rows.is_empty(): %List.select(0)
	%Info.text="" if examples else ("No saved tracks yet. Save a machine in Sandbox to find it here." if rows.is_empty() else "Saved on this device")
	%Browse.visible = not rows.is_empty()
	%Rename.clear()
	refresh_actions()
	size=Vector2i(960,320 if rows.is_empty() else 560)

func refresh_actions() -> void:
	var selected: bool=selected_index()>=0
	%Load.visible = not rows.is_empty()
	%RenameButton.visible = not examples and not rows.is_empty()
	%Delete.visible = not examples and not rows.is_empty()
	%Load.disabled=not selected
	%RenameButton.disabled=not selected
	%Delete.disabled=not selected
	%Rename.hide()
	%RenameButton.text="Rename"
	%Selected.visible = selected
	if selected:
		var row: Dictionary = rows[selected_index()]
		%TrackTitle.text = row.name.split(" · ")[0] if examples else row.name
		%TrackDetails.text = "%d pieces" % row.count + (" · " + row.name.split(" · ")[1] if examples and " · " in row.name else "")
		var data: Dictionary = serializer.decode(FileAccess.get_file_as_string(("res://resources/menu_machine.json" if row.id == "menu-machine" else "res://resources/examples/" + row.id + ".json"))) if examples else serializer.load_track(row.id)
		%Preview.display(data, serializer.catalog)

func selected_index() -> int:
	var indices=%List.get_selected_items()
	return -1 if indices.is_empty() else indices[0]

func load_selected() -> void:
	var index=selected_index()
	if index<0: %Info.text="Choose a track first"; return
	var id=rows[index].id
	dismiss(func(): track_requested.emit(id,examples); closed.emit())

func rename_selected() -> void:
	var index=selected_index()
	if index<0 or %Rename.text.strip_edges().is_empty(): %Info.text="Select a track and enter its new name"; return
	var data=serializer.load_track(rows[index].id)
	if data.is_empty(): %Info.text=serializer.last_error; return
	if serializer.save_track(%Rename.text,data.pieces,rows[index].id).is_empty(): %Info.text=serializer.last_error
	else: refresh()

func delete_selected() -> void:
	var index=selected_index()
	if index<0: %Info.text="Choose a track first"; return
	confirmation.dialog_text="Delete ‘%s’? This cannot be undone." % rows[index].name
	confirmation.popup_centered()

extends Window

signal track_requested(id: String, example: bool)
signal closed
var serializer: TrackSerializer
var rows: Array = []
var examples: bool = false
var confirmation: ConfirmationDialog

func _ready() -> void:
	close_requested.connect(close)
	%Load.pressed.connect(load_selected)
	%RenameButton.pressed.connect(func():
		if not %Rename.visible:
			%Rename.show()
			%Rename.text=rows[selected_index()].name
			%Rename.grab_focus()
			%Rename.select_all()
			%RenameButton.text="Apply name"
		else: rename_selected())
	%Rename.text_changed.connect(func(text): %RenameButton.disabled=text.strip_edges().is_empty())
	%List.item_selected.connect(func(_index): refresh_actions())
	%Delete.pressed.connect(delete_selected)
	%Close.pressed.connect(close)
	%List.item_activated.connect(func(_index):load_selected())
	confirmation=%DeleteConfirmation
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
	popup_centered()

func refresh() -> void:
	%List.clear()
	rows=[{"id":"first-roll","name":"First Roll · slopes and a sweeping curve","count":7},{"id":"spiral-crossing","name":"Spiral Crossing · two levels and a full helix","count":14},{"id":"bucket-elevator-demo","name":"Bucket Elevator · carry a marble to an upper track","count":4}] if examples else serializer.list_tracks()
	for row in rows: %List.add_item("%s · %d %s" % [row.name,row.count,"piece" if row.count==1 else "pieces"])
	%Info.text="" if examples else ("No saved tracks yet." if rows.is_empty() else "Saved on this device")
	%Rename.clear()
	refresh_actions()
	size=Vector2i(660,300 if rows.is_empty() else 460)

func refresh_actions() -> void:
	var selected: bool=selected_index()>=0
	%Load.disabled=not selected
	%RenameButton.disabled=not selected
	%Delete.disabled=not selected
	%Rename.hide()
	%RenameButton.text="Rename"

func selected_index() -> int:
	var indices=%List.get_selected_items()
	return -1 if indices.is_empty() else indices[0]

func load_selected() -> void:
	var index=selected_index()
	if index<0: %Info.text="Choose a track first"; return
	var id=rows[index].id
	hide()
	track_requested.emit(id,examples)
	closed.emit()

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

func close() -> void:
	hide()
	closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

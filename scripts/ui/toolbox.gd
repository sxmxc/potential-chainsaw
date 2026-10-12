extends PanelContainer
signal piece_chosen(definition: PieceDefinition)
const CARD=preload("res://scenes/ui/widgets/piece_card.tscn")
var catalog: PieceCatalog
var selected_id: StringName
var buttons: Dictionary = {}
func configure(data: PieceCatalog) -> void:
	catalog=data
	for category in catalog.categories(): %Category.add_item(category)
	%Category.select(1)
	%Category.item_selected.connect(func(_index):refresh())
	%Search.text_changed.connect(func(text):
		if not text.is_empty(): %Category.select(0)
		refresh())
	refresh()
func refresh() -> void:
	for child in %Pieces.get_children():
		%Pieces.remove_child(child)
		child.queue_free()
	buttons.clear()
	for definition in catalog.pieces:
		if not definition.library_visible: continue
		if %Category.selected>0 and definition.category!=%Category.get_item_text(%Category.selected): continue
		if not %Search.text.is_empty() and not (definition.display_name+" "+definition.category).to_lower().contains(%Search.text.to_lower()): continue
		var card=CARD.instantiate()
		%Pieces.add_child(card)
		card.bind(definition,definition.id==selected_id)
		buttons[definition.id]=card
		card.chosen.connect(func(piece):
			selected_id=piece.id
			for id in buttons: buttons[id].button_pressed=id==selected_id
			piece_chosen.emit(piece))
	%Count.text="%d pieces · hover for details" % buttons.size() if not buttons.is_empty() else "No matches · try another search"
	# The inventory uses one or two visible rows according to filtered content.
	# Its Container still owns placement and scrolling; no rectangles are assigned.
	%Scroll.custom_minimum_size.y=112*minf(2,maxf(1,ceilf(buttons.size()/2.0)))
func clear_choice() -> void:
	selected_id=&""
	for button in buttons.values(): button.button_pressed=false

func set_choice(id: StringName) -> void:
	selected_id=id
	for key in buttons: buttons[key].button_pressed=key==id

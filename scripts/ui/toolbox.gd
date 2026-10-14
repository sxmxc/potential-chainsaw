extends PanelContainer
signal piece_chosen(definition: PieceDefinition)
signal collapsed
signal action_requested(action: String)
const CARD=preload("res://scenes/ui/widgets/piece_card.tscn")
var build: BuildManager
var catalog: PieceCatalog
var selected_id: StringName
var buttons: Dictionary = {}
var scroll_positions: Dictionary = {}
var filter_key: String = ""
var refresh_generation: int = 0
func configure(data: PieceCatalog, manager: BuildManager = null) -> void:
	build=manager
	catalog=data
	for category in catalog.categories(): %Category.add_item(category)
	%Category.select(0)
	%Category.get_popup().transparent_bg=true
	%Category.get_popup().transparent=true
	%Collapse.pressed.connect(func():collapsed.emit())
	%AddScenery.pressed.connect(func(): action_requested.emit("place_scenery"))
	get_viewport().size_changed.connect(fit_content)
	if get_parent() is Control: get_parent().resized.connect(fit_content)
	%Category.item_selected.connect(func(_index):refresh())
	%Search.text_changed.connect(func(text):
		if not text.is_empty(): %Category.select(0)
		refresh())
	refresh()
func refresh() -> void:
	if not filter_key.is_empty(): scroll_positions[filter_key]=%Scroll.scroll_vertical
	var inventory_ids: Array=[]
	if build and build.rules:
		inventory_ids=build.rules.puzzle.inventory.keys()
		inventory_ids.sort()
	filter_key=JSON.stringify(inventory_ids) if build and build.rules else "%s:%d:%s" % [build != null and build.authoring,%Category.selected,%Search.text.to_lower()]
	refresh_generation+=1
	for child in %Pieces.get_children():
		%Pieces.remove_child(child)
		child.queue_free()
	buttons.clear()
	var criteria: Dictionary[StringName, Variant] = {}
	if (not build or not build.rules) and %Category.selected > 0:
		criteria[&"category"] = %Category.get_item_text(%Category.selected)
	for definition in catalog.query(criteria):
		if not definition.library_visible: continue
		if definition.authoring_only and (not build or not build.authoring): continue
		if build and build.rules and not build.rules.puzzle.inventory.has(String(definition.id)): continue
		if not build or not build.rules:
			if not %Search.text.is_empty() and not (definition.display_name+" "+definition.category).to_lower().contains(%Search.text.to_lower()): continue
		var card=CARD.instantiate()
		%Pieces.add_child(card)
		card.bind(definition,definition.id==selected_id)
		if build and build.rules:
			var remaining = build.rules.remaining(String(definition.id), build.snapshot())
			card.get_node("%Quantity").text="× "+str(remaining)
			card.get_node("%Quantity").show()
			card.disabled = remaining <= 0
		buttons[definition.id]=card
		card.chosen.connect(func(piece):
			selected_id=piece.id
			for id in buttons: buttons[id].button_pressed=id==selected_id
			piece_chosen.emit(piece))
	%Count.text="No pieces available" if build and build.rules else "No matching pieces"
	%Count.visible=buttons.is_empty()
	%Pieces.columns=1 if buttons.size()==1 and build and build.rules else 2
	custom_minimum_size.x=164 if buttons.size()==1 and build and build.rules else 312
	var small_inventory: bool=build!=null and build.rules!=null and build.rules.puzzle.inventory.size()<=6
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN if small_inventory else Control.SIZE_EXPAND_FILL
	%Search.visible=not small_inventory
	%Category.visible=not small_inventory
	%AddScenery.visible=build != null and build.authoring
	fit_content.call_deferred()
	restore_scroll.call_deferred(refresh_generation)

func place_scene(path: String) -> void:
	if not build or not build.authoring or not build.enabled: return
	var definition := catalog.get_piece("environment_scene:" + path)
	if not definition:
		build.show_status("Could not load this scenery scene")
		return
	piece_chosen.emit(definition)

func restore_scroll(generation: int) -> void:
	# Let the container and scrollbar settle before restoring a previous filter.
	await get_tree().process_frame
	await get_tree().process_frame
	if generation==refresh_generation:
		%Scroll.scroll_vertical=int(scroll_positions.get(filter_key,0))

func fit_content() -> void:
	if not is_inside_tree(): return
	var row_height: float=160
	for card in buttons.values(): row_height=maxf(row_height,card.get_combined_minimum_size().y)
	var rows: int=ceili(float(buttons.size())/%Pieces.columns)
	var content_height: float=rows*row_height+maxi(0,rows-1)*%Pieces.get_theme_constant("v_separation")
	var overhead: float=get_combined_minimum_size().y-%Scroll.custom_minimum_size.y
	var parent_height: float = get_parent().size.y if get_parent() is Control else get_viewport().get_visible_rect().size.y * 0.68
	var available: float = maxf(0, minf(parent_height, get_viewport().get_visible_rect().size.y * 0.68) - overhead)
	%Scroll.custom_minimum_size.y=minf(content_height,available) if rows>0 else 0.0
func clear_choice() -> void:
	selected_id=&""
	for button in buttons.values(): button.button_pressed=false

func set_choice(id: StringName) -> void:
	selected_id=id
	for key in buttons: buttons[key].button_pressed=key==id

func reset_filter() -> void:
	%Category.select(0)
	%Search.set_text("")
	clear_choice()
	refresh()

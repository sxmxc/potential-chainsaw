extends PopupPanel

const CARD=preload("res://scenes/ui/widgets/piece_card.tscn")
var build: BuildManager
var target: Dictionary = {}
var motion: UIMotion

func _ready() -> void:
	motion = UIMotion.attach($Surface, Vector2.ZERO, UIMotion.SURFACE_SCALE)
	ButtonFeedback.install(self)
	visibility_changed.connect(func():
		if visible: motion.enter()
		else: motion.cancel(); $Surface.show())
	motion.finished.connect(func():
		if not motion.wanted: hide()
		elif visible: %Search.grab_focus())

func close_picker() -> void:
	motion.set_open(false)

func configure(manager: BuildManager) -> void:
	build=manager
	build.extension_requested.connect(open_for)
	%Search.text_changed.connect(func(_text):refresh())
	%Close.pressed.connect(close_picker)

func open_for(port: Dictionary, screen: Vector2) -> void:
	target=port
	%Search.clear()
	refresh()
	# Popup placement is cursor-dependent; the contents are entirely container-owned.
	var limit=get_parent().get_viewport_rect().size-Vector2(size)
	position=Vector2i(screen.clamp(Vector2.ZERO,limit.max(Vector2.ZERO)))
	popup()

func refresh() -> void:
	for child in %Pieces.get_children():
		%Pieces.remove_child(child)
		child.queue_free()
	for definition in build.catalog.query():
		var compatible:=false
		for port in definition.connectors:
			if port.compatible(target.connector): compatible=true
		if not compatible or not definition.display_name.to_lower().contains(%Search.text.to_lower()): continue
		var card=CARD.instantiate()
		%Pieces.add_child(card)
		card.bind(definition,false)
		card.chosen.connect(func(piece):
			hide()
			build.choose_extension(piece,target))

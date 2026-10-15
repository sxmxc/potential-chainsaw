extends Button
signal chosen(definition: PieceDefinition)
var definition: PieceDefinition
const TOOLTIP=preload("res://scenes/ui/widgets/compact_tooltip.tscn")
func _ready() -> void:
	ButtonFeedback.install(self)
	pressed.connect(func():chosen.emit(definition))
	toggled.connect(func(selected): %SelectedMark.visible=selected)
func bind(piece: PieceDefinition, selected: bool) -> void:
	definition=piece
	button_pressed=selected
	%SelectedMark.visible=selected
	tooltip_text=piece.display_name+"\n"+piece.player_description()
	%PieceName.text=card_name(piece)
	%Thumbnail.texture=piece.thumbnail
	%Quantity.hide()

func card_name(piece: PieceDefinition) -> String:
	if piece.id in [&"fan-simple-two",&"fan-simple-four",&"fan-standing-two",&"fan-standing-four",&"fan-two",&"fan-four"]:
		return piece.display_name.replace(" (","\n").replace(")","")
	var names: Dictionary={
		&"banner-hanging-double-high":"Tall hanging\nbanner",
		&"banner-double-high":"Tall double\nbanner",
		&"banner-hanging-double":"Double hanging\nbanner",
		&"support-color-single":"Single support\n(color)",
		&"support-color-two":"Two supports\n(color)",
		&"support-color-four":"Four supports\n(color)",
	}
	return names.get(piece.id,piece.display_name)

func _make_custom_tooltip(for_text: String) -> Object:
	var label=TOOLTIP.instantiate()
	label.text=for_text
	return label

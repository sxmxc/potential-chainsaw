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
	%PieceName.text=piece.display_name
	%Thumbnail.texture=piece.thumbnail
	%Quantity.hide()

func _make_custom_tooltip(for_text: String) -> Object:
	var label=TOOLTIP.instantiate()
	label.text=for_text
	return label

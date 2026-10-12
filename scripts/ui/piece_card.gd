extends Button
signal chosen(definition: PieceDefinition)
var definition: PieceDefinition
func _ready() -> void:
	pressed.connect(func():chosen.emit(definition))
func bind(piece: PieceDefinition, selected: bool) -> void:
	definition=piece
	button_pressed=selected
	tooltip_text=piece.display_name+"\n"+piece.player_description()
	%PieceName.text=piece.display_name
	%Thumbnail.texture=piece.thumbnail

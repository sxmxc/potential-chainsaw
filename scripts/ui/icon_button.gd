extends Button

## Shared utility button: the scene supplies its action, icon and tooltip.
@export var icon_name: StringName
const TOOLTIP = preload("res://scenes/ui/widgets/compact_tooltip.tscn")

func _ready() -> void:
	if not icon_name.is_empty(): icon=get_theme_icon(icon_name, "SandboxIcons")

func _make_custom_tooltip(for_text: String) -> Object:
	var label=TOOLTIP.instantiate()
	label.text=for_text
	return label

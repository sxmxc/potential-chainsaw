class_name MarbleCollector
extends PieceBehavior

signal marble_collected(body: RigidBody3D)
@export var area: Area3D
@export var display_label: Label3D

func configure(settings: Dictionary) -> void:
	super.configure(settings)
	display_label.text = String(config.get("display_label", ""))
	display_label.visible = not display_label.text.is_empty()

func _ready() -> void:
	outputs = ["collected"]
	area.body_entered.connect(_collect_marble)

func _collect_marble(body: Node3D) -> void:
	if not active or not enabled or not is_marble(body) or body.get_meta("delivered", false): return
	marble_collected.emit(body)
	emit_output("collected", body)

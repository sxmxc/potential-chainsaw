extends Node3D

@export var treatments: Dictionary[String, StandardMaterial3D] = {}
@export_range(0.05, 0.4, 0.01) var pointer_distance: float = 0.18
@export_range(0.4, 2.0, 0.05) var pointer_period: float = 1.1
@onready var arrival: AnimationPlayer = $Arrival
var current_kind: String = ""
var destination := Vector3.ZERO
var heading := Vector3.ZERO
var travel: Tween
var pointer_motion: Tween

func present(kind: String, point: Vector3, direction: Vector3) -> void:
	var height := 0.25
	if kind == "target": height = 0.025
	elif kind in ["direction", "problem"]: height = 0.15
	var next_position := point + Vector3.UP * height
	if visible and current_kind == kind and destination.is_equal_approx(next_position) and heading.is_equal_approx(direction): return
	var entering := not visible
	current_kind = kind
	destination = next_position
	heading = direction
	if travel: travel.kill()
	if entering:
		global_position = destination
	else:
		travel = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		travel.tween_property(self, "global_position", destination, UIMotion.ENTER_TIME)
	global_basis = Basis.IDENTITY
	$Pointer.visible = kind not in ["target", "problem"]
	$Area.visible = kind == "target"
	$Cross.visible = kind == "problem"
	if kind == "direction":
		look_at(global_position + direction, Vector3.RIGHT if absf(direction.normalized().dot(Vector3.UP)) >= 0.99 else Vector3.UP)
		$Pointer.rotation_degrees.x = 0
	else:
		$Pointer.rotation_degrees.x = -90
	if pointer_motion: pointer_motion.kill()
	pointer_motion = null
	$Pointer.position = Vector3.ZERO
	if $Pointer.visible:
		var offset := Vector3.UP * pointer_distance
		if kind == "direction": offset = Vector3.BACK * pointer_distance
		$Pointer.position = offset
		pointer_motion = create_tween().set_loops()
		pointer_motion.tween_property($Pointer, "position", Vector3.ZERO, pointer_period * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		pointer_motion.tween_interval(pointer_period * 0.1)
		pointer_motion.tween_property($Pointer, "position", offset, pointer_period * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = treatments.get(kind)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	show()
	arrival.play("arrive")
	arrival.advance(0)

func clear() -> void:
	if travel: travel.kill()
	travel = null
	if pointer_motion: pointer_motion.kill()
	pointer_motion = null
	$Pointer.position = Vector3.ZERO
	arrival.stop()
	hide()
	scale = Vector3.ONE
	current_kind = ""

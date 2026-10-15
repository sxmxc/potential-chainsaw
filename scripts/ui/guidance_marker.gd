extends Node3D

@export var treatments: Dictionary[String, StandardMaterial3D] = {}

func present(kind: String, point: Vector3, direction: Vector3) -> void:
	global_position = point + Vector3.UP * 0.5
	global_basis = Basis.IDENTITY
	$Pointer.visible = kind not in ["target", "problem"]
	$Area.visible = kind == "target"
	$Cross.visible = kind == "problem"
	if kind == "direction":
		global_position = point + Vector3.UP * 0.15
		look_at(position + direction, Vector3.RIGHT if absf(direction.normalized().dot(Vector3.UP)) >= 0.99 else Vector3.UP)
		$Pointer.rotation_degrees.x = 0
	else:
		$Pointer.rotation_degrees.x = -90
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = treatments.get(kind)
	$Caption.text = {"attention": "Look", "target": "Target", "direction": "Direction", "interaction": "Interact", "problem": "Blocked"}.get(kind, "")
	show()

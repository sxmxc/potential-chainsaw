extends SceneTree

func _initialize() -> void:
	var model=load("res://assets/models/GLB format/straight.glb").instantiate()
	var mesh=model.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
	var error=ResourceSaver.save(mesh.mesh.create_trimesh_shape(),"res://scenes/mechanisms/straight_track_collision.tres")
	model.free()
	quit(error)

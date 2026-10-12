extends SceneTree
func _initialize():
	for id in ["fan-two","fan-standing-four","fan-simple-two","tunnel"]:
		var n=load("res://assets/models/GLB format/"+id+".glb").instantiate()
		print(id)
		n.print_tree_pretty()
		n.free()
	quit()

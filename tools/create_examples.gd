extends SceneTree

var catalog: PieceCatalog
var layout: Array = []
var exit_position: Vector3
var exit_normal: Vector3
var counter: int = 0

func _initialize() -> void:
	catalog=PieceCatalog.new()
	DirAccess.make_dir_recursive_absolute("res://resources/examples")
	begin(Vector3(0,1.5,4),0)
	attach("ramp-long-a",0,true)
	attach("straight",0)
	attach("curve",2)
	attach("straight",-1)
	attach("straight",-1)
	attach("sandbox-finish",1)
	write("first-roll","First Roll")
	begin(Vector3(-5,4,2),-1)
	attach("helix-left",2,true)
	attach("straight",-1)
	attach("slant-long-a",-1,true)
	attach("curve",1)
	attach("straight",2)
	attach("straight",2)
	attach("curve",0)
	attach("straight",1)
	attach("straight",1)
	attach("sandbox-finish",-1)
	# Keep the structural column beneath the finish, away from the helix's lower channel.
	var finish_position=Vector3(layout[-1].position[0],layout[-1].position[1],layout[-1].position[2])
	for y in [0.0,0.5,1.0]:
		add_piece("support-single-middle",Transform3D(Basis.IDENTITY,Vector3(finish_position.x,y,finish_position.z)))
	write("spiral-crossing","Spiral Crossing")
	quit()

func begin(position: Vector3, turn: int) -> void:
	layout.clear()
	counter=0
	var t=Transform3D(Basis(Vector3.UP,turn*PI/2),position)
	add_piece("sandbox-start",t)
	exit_position=t*Vector3(0,0.25,-0.5)
	exit_normal=t.basis*Vector3.FORWARD

func attach(id: String, turn: int, high: bool=false) -> void:
	var def=catalog.get_piece(id)
	var basis=Basis(Vector3.UP,turn*PI/2)
	var entrance: TrackConnector
	for connector in def.connectors:
		if (basis*connector.outward).dot(exit_normal)<-0.99:
			if not entrance or (high and connector.position.y>entrance.position.y): entrance=connector
	assert(entrance!=null,"No compatible entrance: "+id)
	var t=Transform3D(basis,exit_position-basis*entrance.position)
	add_piece(id,t)
	for connector in def.connectors:
		if connector!=entrance:
			exit_position=t*connector.position
			exit_normal=basis*connector.outward
			break

func add_piece(id: String,t: Transform3D) -> void:
	counter+=1
	layout.append({"uid":"sample-%d" % counter,"piece":id,"position":[t.origin.x,t.origin.y,t.origin.z],"rotation":roundi(t.basis.get_euler().y/(PI/2)),"config":{}})

func write(id: String,title: String) -> void:
	var file=FileAccess.open("res://resources/examples/"+id+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"id":id,"name":title,"pieces":layout},"\t"))
	print("Wrote ",id," · ",layout.size()," pieces")


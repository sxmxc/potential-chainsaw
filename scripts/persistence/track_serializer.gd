class_name TrackSerializer
extends RefCounted

const FORMAT_VERSION = 1
var save_directory: String = SavePaths.resolve("user://tracks")
var catalog: PieceCatalog
var last_error: String = ""
var warnings: Array[String] = []

func _init(piece_catalog: PieceCatalog) -> void:
	catalog = piece_catalog
	DirAccess.make_dir_recursive_absolute(save_directory)

func save_track(name: String, pieces: Array, existing_id: String = "") -> String:
	last_error = ""
	if name.strip_edges().is_empty(): last_error="Please give your track a name"; return ""
	var id = existing_id if valid_id(existing_id) else "%d-%s" % [Time.get_unix_time_from_system(),Crypto.new().generate_random_bytes(6).hex_encode()]
	var data = {"version":FORMAT_VERSION,"id":id,"name":name.strip_edges().left(80),"modified":Time.get_datetime_string_from_system(true),"pieces":pieces}
	var path = save_directory+"/"+id+".json"
	var temp = path+".tmp"
	var file = FileAccess.open(temp,FileAccess.WRITE)
	if not file: last_error="Could not write track: "+error_string(FileAccess.get_open_error()); return ""
	file.store_string(JSON.stringify(data,"\t"))
	file.flush()
	file.close()
	var error = DirAccess.rename_absolute(temp,path)
	if error != OK: last_error="Could not finish saving: "+error_string(error); return ""
	return id

func load_track(id: String) -> Dictionary:
	if not valid_id(id): last_error="Invalid track identifier"; return {}
	return decode(FileAccess.get_file_as_string(save_directory+"/"+id+".json"))

func decode(text: String) -> Dictionary:
	last_error = ""
	warnings.clear()
	var json = JSON.new()
	if json.parse(text)!=OK: last_error="Invalid track file: "+json.get_error_message(); return {}
	var data = json.data
	if not data is Dictionary or not data.get("version") is float and not data.get("version") is int:
		last_error="Missing save format version"; return {}
	if int(data.version)!=FORMAT_VERSION: last_error="Unsupported track version; this build reads version 1"; return {}
	if not data.get("pieces") is Array or data.pieces.size()>5000: last_error="Invalid piece list (limit 5,000)"; return {}
	if not data.get("name") is String: last_error="Invalid track name"; return {}
	var clean: Array = []
	var uids: Dictionary = {}
	for item in data.pieces:
		if not item is Dictionary or not item.get("piece") is String:
			last_error="Invalid piece record"; return {}
		if not catalog.get_piece(item.piece) or catalog.get_piece(item.piece).authoring_only: warnings.append("Skipped unknown piece: "+item.piece); continue
		var p = item.get("position")
		if not p is Array or p.size()!=3: last_error="Invalid piece position"; return {}
		for value in p:
			if not (value is float or value is int) or not is_finite(float(value)) or abs(float(value))>1000:
				last_error="Invalid coordinate"; return {}
		if not (item.get("rotation") is float or item.get("rotation") is int): last_error="Invalid rotation"; return {}
		if not item.get("config",{}) is Dictionary: last_error="Invalid piece configuration"; return {}
		var uid = str(item.get("uid","loaded-%d" % clean.size()))
		if uids.has(uid): uid += "-%d" % clean.size()
		uids[uid] = true
		var config: Dictionary = item.get("config",{}).duplicate(true)
		if catalog.get_piece(item.piece).behavior == "elevator":
			config = preload("res://scripts/mechanisms/elevator_geometry.gd").normalized(config)
		elif catalog.get_piece(item.piece).behavior == "resizable_support":
			config = preload("res://scripts/construction/support_geometry.gd").normalized(config)
		if config.has("release_speed"):
			if not (config.release_speed is float or config.release_speed is int): last_error="Invalid release speed"; return {}
			config.release_speed = clampf(float(config.release_speed),0,6)
		clean.append({"uid":uid,"piece":item.piece,"position":p.duplicate(),"rotation":posmod(int(item.rotation),4),"config":config})
	data.pieces = clean
	data.name = data.name.left(80)
	return data

func list_tracks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for file in DirAccess.get_files_at(save_directory):
		if not file.ends_with(".json"): continue
		var data = load_track(file.get_basename())
		if not data.is_empty(): result.append({"id":file.get_basename(),"name":data.name,"modified":data.get("modified",""),"count":data.pieces.size()})
	result.sort_custom(func(a,b):return a.modified>b.modified)
	return result

func delete_track(id: String) -> Error:
	if not valid_id(id): return ERR_INVALID_PARAMETER
	return DirAccess.remove_absolute(save_directory+"/"+id+".json")

func valid_id(id: String) -> bool:
	if id.is_empty() or id.length()>100: return false
	for c in id:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_": return false
	return true

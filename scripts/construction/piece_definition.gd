class_name PieceDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var category: String
@export_multiline var description: String
@export_multiline var usage_hint: String
@export var model: PackedScene
@export var thumbnail: Texture2D
@export var placement_offset: Vector3
@export var bounds: AABB
@export var rotation_steps: int = 4
@export var connectors: Array[TrackConnector] = []
# Semantic tags such as start/finish are used by mode rules, not component factories.
@export var behavior: String = "static"
# Scenery is editable only in authoring; imported models use common mesh collision.
@export var authoring_only: bool = false
# Measured occupied volumes for placement; openings are represented by separate solids.
@export var collision_solids: Array[AABB] = []
# Authored scenery joints may interpenetrate these registered piece types.
@export var overlap_with: Array[StringName] = []
@export var library_visible: bool = true
@export var collision_enabled: bool = true
# Authored functional scenes provide their own collision instead of mesh baking.
@export var native_collision: bool = false
@export var height_setting: StringName
@export var ground_placement: bool = false
@export var height_offset: float = 0.0
@export var reserve_bounds: bool = false
@export var editable_in_simulation: bool = false
@export var surface_cells: PackedVector3Array

var settings: Array[PieceSetting]:
	get:
		var fields: Array[PieceSetting] = []
		if model:
			for group in _scene_fields(model.get_state()).values(): fields.append_array(group)
		return fields

# Read the same exported resources that live behavior nodes use, without
# instantiating physics objects during save loading and placement validation.
# Inherited/instanced scene overrides replace the fields at that node path.
func _scene_fields(state: SceneState, prefix: String = "") -> Dictionary:
	var groups: Dictionary = {}
	var inherited := state.get_base_scene_state()
	if inherited: groups.merge(_scene_fields(inherited, prefix), true)
	for index in state.get_node_count():
		var path := String(state.get_node_path(index))
		path = prefix if path == "." else (prefix.path_join(path) if not prefix.is_empty() else path)
		var instance := state.get_node_instance(index)
		if instance: groups.merge(_scene_fields(instance.get_state(), path), true)
		for property_index in state.get_node_property_count(index):
			if state.get_node_property_name(index, property_index) == &"configuration_fields":
				groups[path] = state.get_node_property_value(index, property_index)
	return groups

func has_behavior(behavior_script: Script, state: SceneState = null) -> bool:
	if not state:
		if not model: return false
		state = model.get_state()
	var inherited := state.get_base_scene_state()
	if inherited and has_behavior(behavior_script, inherited): return true
	for index in state.get_node_count():
		var instance := state.get_node_instance(index)
		if instance and has_behavior(behavior_script, instance.get_state()): return true
		for property_index in state.get_node_property_count(index):
			if state.get_node_property_name(index, property_index) != &"script": continue
			var node_script := state.get_node_property_value(index, property_index) as Script
			while node_script:
				if node_script == behavior_script: return true
				node_script = node_script.get_base_script()
	return false

func normalized_configuration(config: Dictionary) -> Dictionary:
	var result := config.duplicate(true)
	for setting in settings:
		# Leave omitted defaults omitted so existing construction records stay stable.
		if result.has(setting.key): result[setting.key] = setting.normalized(result[setting.key])
	return result

func resolved_configuration(config: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for setting in settings: result[String(setting.key)] = setting.default_value()
	result.merge(config, true)
	return result

func configured(_config: Dictionary) -> PieceDefinition:
	return self

func footprint() -> Vector3:
	return bounds.size

func player_description() -> String:
	if not usage_hint.is_empty(): return usage_hint
	if connectors.is_empty(): return "Place freely as a track accessory."
	var low=connectors[0].position.y
	var high=low
	for port in connectors:
		low=minf(low,port.position.y)
		high=maxf(high,port.position.y)
	if high-low>0.02: return "Connects track levels %.2f m apart." % (high-low)
	if connectors.size()>2: return "A junction with %d track connections." % connectors.size()
	return "Point at an open connector to attach. Tab cycles available orientations."

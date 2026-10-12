class_name ConstructionCamera
extends Camera3D

@export var composition_offset: Vector2 = Vector2.ZERO
@export var automatic_composition: bool = true
@onready var free_view: PhantomCamera3D = get_node_or_null("../FreeView")
var chase_active: bool = false

var focus_point: Vector3 = Vector3(0,1,0)
var target_focus: Vector3 = Vector3(0,1,0)
var yaw: float = 0.7
var target_yaw: float = 0.7
var pitch: float = 0.65
var target_pitch: float = 0.65
var distance: float = 15
var target_distance: float = 15
var sensitivity: float = 1.0
var zoom_sensitivity: float = 1.0
var invert_x: bool = false
var invert_y: bool = false
var drag_button: int = 0
var enabled: bool = true

func _ready() -> void:
	current = true
	near = 0.05
	far = 300
	fov = 48
	if free_view and not automatic_composition:
		free_view.camera_3d_resource.h_offset = h_offset
	_update(1)

func _process(delta: float) -> void:
	if chase_active: return
	if enabled and not ConstructionInput.typing(get_viewport()):
		var direction = Vector3.ZERO
		if Input.is_action_pressed("camera_forward", true): direction -= global_basis.z
		if Input.is_action_pressed("camera_back", true): direction += global_basis.z
		if Input.is_action_pressed("camera_left", true): direction -= global_basis.x
		if Input.is_action_pressed("camera_right", true): direction += global_basis.x
		direction.y = 0
		if direction.length_squared()>0: target_focus += direction.normalized()*delta*target_distance*0.5*sensitivity
	_update(1-exp(-delta*14))

func _update(weight: float) -> void:
	focus_point = focus_point.lerp(target_focus,weight)
	yaw = lerp(yaw,target_yaw,weight)
	pitch = lerp(pitch,target_pitch,weight)
	distance = lerp(distance,target_distance,weight)
	var pose = Transform3D(Basis.IDENTITY, focus_point + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance)
	pose = pose.looking_at(focus_point, Vector3.UP)
	if free_view:
		free_view.global_transform = pose
	else:
		transform = pose
	if automatic_composition:
		var viewport_size=get_viewport().get_visible_rect().size
		var span=2.0*distance*tan(deg_to_rad(48.0*0.5))
		var horizontal=-span*composition_offset.x*viewport_size.x/maxf(1,viewport_size.y)
		var vertical=span*composition_offset.y
		if free_view:
			free_view.camera_3d_resource.h_offset=horizontal
			free_view.camera_3d_resource.v_offset=vertical
		else:
			h_offset=horizontal
			v_offset=vertical

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or chase_active or ConstructionInput.typing(get_viewport()): return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			drag_button = event.button_index if event.pressed else 0
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: target_distance = maxf(1.2,target_distance*pow(0.88,zoom_sensitivity))
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: target_distance = minf(100,target_distance/pow(0.88,zoom_sensitivity))
	if event is InputEventMouseMotion:
		if drag_button == MOUSE_BUTTON_RIGHT:
			target_yaw -= event.relative.x*0.006*sensitivity*(-1.0 if invert_x else 1.0)
			target_pitch = clampf(target_pitch+event.relative.y*0.006*sensitivity*(-1.0 if invert_y else 1.0),-0.3,1.48)
		elif drag_button == MOUSE_BUTTON_MIDDLE:
			target_focus += pan_offset(event.position, event.relative, event.shift_pressed) * sensitivity

func pan_offset(pointer: Vector2, motion: Vector2, vertical: bool = false) -> Vector3:
	# Grab the construction plane beneath the cursor. A screen-space drag then
	# keeps that point beneath the cursor at any zoom, pitch or viewport size.
	# Shift uses a plane parallel to the view, preserving vertical camera pan.
	var normal := global_basis.z if vertical else Vector3.UP
	var plane := Plane(normal, normal.dot(focus_point))
	var previous = plane.intersects_ray(project_ray_origin(pointer - motion), project_ray_normal(pointer - motion))
	var current_cam = plane.intersects_ray(project_ray_origin(pointer), project_ray_normal(pointer))
	if previous == null or current_cam == null: return Vector3.ZERO
	# A nearly horizontal view can put the intersection far beyond the machine.
	if not vertical and (global_position.distance_to(previous) > distance * 8 or global_position.distance_to(current_cam) > distance * 8): return Vector3.ZERO
	return previous - current

func _input(event: InputEvent) -> void:
	# GUI consumption of a release must not leave an orbit/pan gesture latched.
	if event is InputEventMouseButton and not event.pressed and event.button_index==drag_button:
		drag_button=0

func frame_point(point: Vector3, framing_size: float = 3) -> void:
	target_focus = point
	target_distance = clampf(framing_size*2.2,3,100)

func reset_view() -> void:
	target_focus = Vector3(0,1,0)
	target_distance = 15
	target_pitch = 0.65
	target_yaw = 0.7

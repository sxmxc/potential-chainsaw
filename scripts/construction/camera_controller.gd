class_name ConstructionCamera
extends Camera3D

@export var composition_offset: Vector2 = Vector2.ZERO
@export var automatic_composition: bool = true

var focus_point: Vector3 = Vector3(0,1,0)
var target_focus: Vector3 = Vector3(0,1,0)
var yaw: float = 0.7
var target_yaw: float = 0.7
var pitch: float = 0.65
var target_pitch: float = 0.65
var distance: float = 15
var target_distance: float = 15
var sensitivity: float = 1.0
var drag_button: int = 0
var enabled: bool = true

func _ready() -> void:
	current = true
	near = 0.05
	far = 300
	fov = 48
	_update(1)

func _process(delta: float) -> void:
	if enabled and not ConstructionInput.typing(get_viewport()) and not Input.is_key_pressed(KEY_CTRL):
		var direction = Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W): direction -= global_basis.z
		if Input.is_physical_key_pressed(KEY_S) and not Input.is_key_pressed(KEY_CTRL): direction += global_basis.z
		if Input.is_physical_key_pressed(KEY_A): direction -= global_basis.x
		if Input.is_physical_key_pressed(KEY_D) and not Input.is_key_pressed(KEY_CTRL): direction += global_basis.x
		direction.y = 0
		if direction.length_squared()>0: target_focus += direction.normalized()*delta*target_distance*0.5*sensitivity
	_update(1-exp(-delta*14))

func _update(weight: float) -> void:
	focus_point = focus_point.lerp(target_focus,weight)
	yaw = lerp(yaw,target_yaw,weight)
	pitch = lerp(pitch,target_pitch,weight)
	distance = lerp(distance,target_distance,weight)
	position = focus_point + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	look_at(focus_point,Vector3.UP)
	if automatic_composition:
		var viewport_size=get_viewport().get_visible_rect().size
		var span=2.0*distance*tan(deg_to_rad(fov*0.5))
		h_offset=-span*composition_offset.x*viewport_size.x/maxf(1,viewport_size.y)
		v_offset=span*composition_offset.y

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or ConstructionInput.typing(get_viewport()): return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			drag_button = event.button_index if event.pressed else 0
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: target_distance = maxf(1.2,target_distance*0.88)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: target_distance = minf(100,target_distance/0.88)
	if event is InputEventMouseMotion:
		if drag_button == MOUSE_BUTTON_RIGHT:
			target_yaw -= event.relative.x*0.006*sensitivity
			target_pitch = clampf(target_pitch+event.relative.y*0.006*sensitivity,-0.3,1.48)
		elif drag_button == MOUSE_BUTTON_MIDDLE:
			var up = global_basis.y if event.shift_pressed else Vector3(global_basis.z.x,0,global_basis.z.z).normalized()
			target_focus += (-global_basis.x*event.relative.x+up*event.relative.y)*target_distance*0.0018*sensitivity

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

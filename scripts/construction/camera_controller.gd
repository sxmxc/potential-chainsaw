class_name ConstructionCamera
extends Camera3D

@export var composition_offset: Vector2 = Vector2.ZERO
@export var automatic_composition: bool = true
@onready var free_view: PhantomCamera3D = get_node_or_null("../FreeView")
var chase_active: bool = false
var build: BuildManager
var navigation_pivot := Vector3(0, 1, 0)
var orbit_pivot := Vector3.ZERO
var pan_depth: float = 15.0

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
var enabled: bool = true:
	set(value):
		enabled = value
		if not value: drag_button = 0

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
		if direction.length_squared()>0:
			var offset := direction.normalized()*delta*working_depth(working_pivot())*0.5*sensitivity
			target_focus += offset
			navigation_pivot += offset
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
		var tangents := view_tangents()
		var horizontal=-2.0*distance*tangents.x*composition_offset.x
		var vertical=2.0*distance*tangents.y*composition_offset.y
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
			if event.pressed:
				interrupt_transition()
				drag_button = event.button_index
				orbit_pivot = working_pivot()
				var hit := geometry_hit(event.position)
				if event.alt_pressed and drag_button == MOUSE_BUTTON_RIGHT and not hit.is_empty():
					orbit_pivot = hit.position
					navigation_pivot = orbit_pivot
				pan_depth = working_depth(hit.position if not hit.is_empty() else orbit_pivot)
			else: drag_button = 0
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(event.position, (1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0) * (event.factor if event.factor > 0 else 1.0))
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("build_frame", false, true) or event.is_action_pressed("build_frame_all", false, true):
			if build:
				if event.is_action_pressed("build_frame_all", false, true) or build.selection.is_empty(): build.frame_all()
				else: build.frame_pieces(build.selection)
				get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		if drag_button == MOUSE_BUTTON_RIGHT:
			var old_basis := view_basis()
			target_yaw -= event.relative.x*0.006*sensitivity*(-1.0 if invert_x else 1.0)
			target_pitch = clampf(target_pitch+event.relative.y*0.006*sensitivity*(-1.0 if invert_y else 1.0),-0.3,1.48)
			# Rotate the eye AND its aim around the latched pivot. Changing the pivot
			# alone must never recenter or translate the view at gesture start.
			target_focus = orbit_pivot + view_basis() * old_basis.inverse() * (target_focus - orbit_pivot)
			navigation_pivot = orbit_pivot
			_update(1)
		elif drag_button == MOUSE_BUTTON_MIDDLE:
			var offset := pan_offset(event.position, event.relative) * sensitivity
			target_focus += offset
			navigation_pivot += offset
			_update(1)
		if drag_button != 0: get_viewport().set_input_as_handled()

func pan_offset(pointer: Vector2, motion: Vector2) -> Vector3:
	# A view-facing plane has no horizon singularity and supports tall builds.
	var depth := pan_depth if drag_button == MOUSE_BUTTON_MIDDLE else working_depth(working_pivot())
	return project_position(pointer - motion, depth) - project_position(pointer, depth)

func working_pivot() -> Vector3:
	if build and not build.selection.is_empty(): return build.navigation_bounds(build.selection).get_center()
	return navigation_pivot

func working_depth(point: Vector3) -> float:
	return maxf(near * 4.0, - (get_camera_transform().affine_inverse() * point).z)

func view_basis() -> Basis:
	var offset := Vector3(sin(target_yaw)*cos(target_pitch), sin(target_pitch), cos(target_yaw)*cos(target_pitch))
	return Basis.looking_at(-offset, Vector3.UP)

func interrupt_transition() -> void:
	# Direct input takes over at the visible pose, rather than completing a frame.
	target_focus = focus_point
	target_distance = distance
	target_yaw = yaw
	target_pitch = pitch

func geometry_hit(pointer: Vector2) -> Dictionary:
	if not build: return {}
	var origin := project_ray_origin(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + project_ray_normal(pointer)*far, 5)
	var excluded: Array[RID] = []
	for piece in build.moving_group:
		for body: CollisionObject3D in piece.find_children("*", "CollisionObject3D", true, false): excluded.append(body.get_rid())
	query.exclude = excluded
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var node := hit.get("collider") as Node
	while node and not node is BuildingPiece: node = node.get_parent()
	return hit if node else {}

func zoom_at(pointer: Vector2, steps: float) -> void:
	var hit := geometry_hit(pointer)
	var depth := working_depth(hit.position if not hit.is_empty() else working_pivot())
	var anchor := project_position(pointer, depth)
	# Reparameterize the pending pose at the working depth without moving it.
	# Composition offsets scale with distance too, so include them in the ray.
	var eye_offset := view_basis().z
	if automatic_composition:
		var tangents := view_tangents()
		eye_offset += view_basis().x * (-2.0*tangents.x*composition_offset.x) + view_basis().y * (2.0*tangents.y*composition_offset.y)
	var pending_eye := target_focus + eye_offset*target_distance
	depth = maxf(near*4.0, (pending_eye - anchor).dot(view_basis().z))
	target_focus += eye_offset * (target_distance - depth)
	target_distance = depth
	var ratio := maxf(near*4.0, depth*pow(0.88, steps*zoom_sensitivity)) / depth
	target_focus = anchor + (target_focus - anchor)*ratio
	target_distance *= ratio
	navigation_pivot = anchor
	far = maxf(far, target_distance*3.0)
	if free_view: free_view.camera_3d_resource.far = far

func view_tangents() -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(1, viewport_size.y)
	var tangent := tan(deg_to_rad(fov*0.5))
	return Vector2(tangent*aspect, tangent) if keep_aspect == KEEP_HEIGHT else Vector2(tangent, tangent/aspect)

func _input(event: InputEvent) -> void:
	# GUI consumption of a release must not leave an orbit/pan gesture latched.
	if event is InputEventMouseButton and not event.pressed and event.button_index==drag_button:
		drag_button=0

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: drag_button = 0

func frame_point(point: Vector3, framing_size: float = 3) -> void:
	frame_bounds(AABB(point - Vector3.ONE*framing_size*0.5, Vector3.ONE*framing_size))

func frame_bounds(bounds: AABB) -> void:
	target_focus = bounds.get_center()
	navigation_pivot = target_focus
	var tangents := view_tangents()
	# Reserve padding plus the existing HUD composition offset on both axes.
	var usable := Vector2.ONE*0.9 - composition_offset.abs()*2.0 if automatic_composition else Vector2.ONE*0.9
	var required := near*4.0
	var inverse_basis := view_basis().inverse()
	for index in 8:
		var corner := inverse_basis * (bounds.get_endpoint(index) - target_focus)
		required = maxf(required, corner.z + maxf(absf(corner.x)/(tangents.x*usable.x), absf(corner.y)/(tangents.y*usable.y)))
	target_distance = required + near*2.0
	# Framing must not silently stop at the former 100-unit zoom limit.
	far = maxf(far, required + bounds.size.length()*2.0)
	if free_view: free_view.camera_3d_resource.far = far

func reset_view() -> void:
	drag_button = 0
	navigation_pivot = Vector3(0,1,0)
	target_focus = Vector3(0,1,0)
	target_distance = 15
	target_pitch = 0.65
	target_yaw = 0.7

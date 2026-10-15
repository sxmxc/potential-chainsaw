extends Control

var rectangle := Rect2()
var active := false
var build: BuildManager
var exclusions: Array[Control] = []
@onready var trajectories: MeshInstance3D = $Trajectories

func _process(_delta: float) -> void:
	if build: queue_redraw()

func _physics_process(_delta: float) -> void:
	_update_trajectories()

func set_marquee(value: Rect2, shown: bool) -> void:
	rectangle=value
	active=shown
	queue_redraw()

func _draw() -> void:
	if active:
		# Projected world feedback is genuinely dynamic; styles come from the Theme.
		draw_rect(rectangle,get_theme_color("marquee_fill","ConstructionOverlay"),true)
		draw_rect(rectangle,get_theme_color("marquee_border","ConstructionOverlay"),false,2.0)
	if not build or not build.enabled: return
	if not build.snapping or build.connect_mode: return
	for target in build.targets:
		if not build.chosen and target.piece not in build.selection: continue
		if build.chosen:
			var compatible:=false
			for port in build.preview_ports:
				if port.connector.compatible(target.connector): compatible=true
			if not compatible: continue
		if build.camera.is_position_behind(target.point): continue
		var screen: Vector2=build.camera.unproject_position(target.point)
		var covered:=false
		for control in exclusions:
			if control.is_visible_in_tree() and control.get_global_rect().has_point(screen): covered=true
		if covered or not build.snap.target_visible(target,build.camera,build.moving_group): continue
		var radius=get_theme_constant("connector_radius","ConstructionOverlay")
		var hovered: bool=screen.distance_to(build.cursor_position)<=radius
		var color=get_theme_color("connector_active" if target.key==build.sticky_target else ("connector_hover" if hovered else "connector_available"),"ConstructionOverlay")
		draw_circle(screen,radius,get_theme_color("connector_fill","ConstructionOverlay"))
		draw_arc(screen,radius,0,TAU,32,color,1.5,true)
		draw_line(screen-Vector2(3,0),screen+Vector2(3,0),color,1.5,true)
		draw_line(screen-Vector2(0,3),screen+Vector2(0,3),color,1.5,true)
	# Surface snaps have no connector handle. Show the chosen contact for both
	# surfaces and connectors through this same presentation owner.
	if not build.preview.visible or not build.is_snapped or build.candidates.is_empty(): return
	var point: Vector3 = build.candidates[build.candidate_index()].point
	if build.camera.is_position_behind(point): return
	var contact_screen := build.camera.unproject_position(point)
	for control in exclusions:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(contact_screen): return
	var contact_color := get_theme_color("connector_active" if build.valid else "connector_invalid", "ConstructionOverlay")
	draw_circle(contact_screen, get_theme_constant("contact_radius", "ConstructionOverlay"), contact_color, true, -1, true)

func _update_trajectories() -> void:
	var mesh := trajectories.mesh as ImmediateMesh
	mesh.clear_surfaces()
	trajectories.visible = is_visible_in_tree() and build != null and build.enabled
	if not trajectories.visible: return
	var pieces: Array[BuildingPiece] = []
	if build.chosen:
		pieces.assign(build.preview.get_children())
	else:
		pieces = build.selection
	if build.chosen and not build.preview.visible: return
	var trajectory_material := trajectories.material_override as StandardMaterial3D
	trajectory_material.albedo_color = get_theme_color("connector_active", "ConstructionOverlay")
	var excluded: Array[RID] = []
	for piece: BuildingPiece in build.moving_group:
		for body: CollisionObject3D in piece.find_children("*", "CollisionObject3D", true, false):
			excluded.append(body.get_rid())
	for piece: BuildingPiece in pieces:
		for behavior: PieceBehavior in piece.behaviors:
			var points := behavior.build_trajectory(excluded)
			if points.size() < 2: continue
			mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			for point in points: mesh.surface_add_vertex(point)
			mesh.surface_end()

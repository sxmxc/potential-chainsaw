class_name MarbleRelease
extends PieceBehavior

signal marble_spawned(body: RigidBody3D, ordinal: int)

@export var spawn_position: Vector3 = Vector3(0, 0.48, 0)
@export var spawn_direction: Vector3 = Vector3.FORWARD

@export var display_label: Label3D

var pending_releases: Array[Dictionary] = []
var elapsed: float = 0.0


func _init() -> void:
	outputs = ["released"]

func configure(settings: Dictionary) -> void:
	super.configure(settings)
	display_label.text = String(config.get("display_label", ""))
	display_label.visible = not display_label.text.is_empty()

func reset() -> void:
	super.reset()
	elapsed = 0.0
	pending_releases.clear()

func start_run() -> void:
	super.start_run()
	for index in int(config.get("quantity", 1)):
		pending_releases.append({"index": index, "time": float(config.get("start_delay", 0)) + index * float(config.get("interval", 1))})

	_release_due()

func _physics_process(delta: float) -> void:
	if not active or not enabled: return
	elapsed += delta
	_release_due()

func _release_due() -> void:
	if preview_only or not active or not enabled: return
	for release in pending_releases.duplicate():
		if elapsed < release.time: continue
		pending_releases.erase(release)
		var body: RigidBody3D = preload("res://scenes/marble.tscn").instantiate()
		add_child(body)
		body.global_position = global_transform * spawn_position
		body.reset_physics_interpolation()
		body.linear_velocity = global_basis * spawn_direction * float(config.get("release_speed", 1.4))
		body.angular_velocity = Vector3(body.linear_velocity.z, 0, -body.linear_velocity.x) / 0.2
		marble_spawned.emit(body, release.index)
		emit_output("released", body)

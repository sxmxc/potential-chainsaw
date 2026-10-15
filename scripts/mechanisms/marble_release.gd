class_name MarbleRelease
extends PieceBehavior

signal marble_spawned(body: Marble, ordinal: int)

@export var spawn_position: Vector3 = Vector3(0, 0.48, 0)
@export var spawn_direction: Vector3 = Vector3.FORWARD

@export var display_label: Label3D

var pending_releases: Array[Dictionary] = []
var elapsed: float = 0.0
var released_count: int = 0
var next_release_time: float = 0.0


func _init() -> void:
	outputs = ["released"]
	inputs = {"release": _request_release}

func configure(settings: Dictionary) -> void:
	super.configure(settings)
	display_label.text = String(config.get("display_label", ""))
	display_label.visible = not display_label.text.is_empty()

func reset() -> void:
	super.reset()
	elapsed = 0.0
	pending_releases.clear()
	released_count = 0
	next_release_time = float(config.get("start_delay", 0))

func start_run() -> void:
	super.start_run()
	if bool(config.get("signal_controlled", false)): return
	for index in int(config.get("quantity", 1)):
		pending_releases.append({"index": index, "time": float(config.get("start_delay", 0)) + index * float(config.get("interval", 1))})

	_release_due()

func _request_release(_value: Variant) -> void:
	if not bool(config.get("signal_controlled", false)) or not enabled: return
	if elapsed < next_release_time or released_count >= int(config.get("quantity", 1)): return
	pending_releases.append({"index": released_count, "time": elapsed})
	# Reserve supply and cooldown before outputs can feed back into this input.
	released_count += 1
	next_release_time = elapsed + float(config.get("interval", 1))
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
		var body: Marble = preload("res://scenes/marble.tscn").instantiate()
		add_child(body)
		body.global_position = global_transform * spawn_position
		body.reset_physics_interpolation()
		body.linear_velocity = global_basis * spawn_direction * float(config.get("release_speed", 1.4))
		body.angular_velocity = Vector3(body.linear_velocity.z, 0, -body.linear_velocity.x) / 0.2
		marble_spawned.emit(body, release.index)
		emit_output("released", body)


extends PanelContainer

@export var display_duration: float = 5.0
@export var slide_duration: float = 0.4

@onready var steam_user_label: Label = %SteamUserLabel
@onready var status_label: Label = %StatusLabel
@onready var steam_avatar: TextureRect = %SteamAvatar

var _tween: Tween

func _ready() -> void:
	# Enable Godot 4.7's offset transform.
	offset_transform_enabled = true
	offset_transform_visual_only = true
	offset_transform_position = Vector2.ZERO

	SteamClient.profile_updated.connect(_update_profile)
	SteamClient.connection_changed.connect(_on_connection_changed)

	_update_profile()
	_show_temporarily()


func _on_connection_changed(_connected: bool) -> void:
	_show_temporarily()

func _on_profile_updated() -> void:
	_update_profile()


func _update_profile() -> void:
	if not SteamClient.initialized:
		steam_user_label.text = "Steam unavailable"
		status_label.text = "🔴 Offline"
		steam_avatar.texture = null
		return

	steam_user_label.text = SteamClient.steam_name
	status_label.text = "🟢 Connected" if SteamClient.online else "🔴 Offline"
	steam_avatar.texture = SteamClient.avatar_texture


func _show_temporarily() -> void:
	if _tween and _tween.is_running():
		_tween.kill()

	_tween = create_tween()

	# Slide into view.
	_tween.tween_property(
		self,
		"offset_transform_position",
		Vector2.ZERO,
		slide_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Stay visible.
	_tween.tween_interval(display_duration)

	# Slide off the right edge.
	_tween.tween_property(
		self,
		"offset_transform_position",
		Vector2(_offscreen_distance(), 0.0),
		slide_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


func _offscreen_distance() -> float:
	var viewport_width := get_viewport_rect().size.x
	var right_edge := global_position.x + size.x
	var remaining_space := maxf(0.0, viewport_width - right_edge)

	return size.x + remaining_space + 20.0

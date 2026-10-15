
extends Node

signal profile_updated
signal connection_changed(connected: bool)

var initialized: bool = false
var online: bool = false
var steam_id: int = 0
var steam_name: String = ""
var avatar_texture: Texture2D

class WebTicket extends RefCounted:
	signal completed(result: Dictionary)
	var pending: bool = true

var web_tickets: Dictionary = {}


func _ready() -> void:
	var app_id: int = int(ProjectSettings.get_setting(
		"steam/initialization/app_data/app_id", 480
	))

	var result: Dictionary = Steam.steamInitEx(app_id)

	if result.get("status", -1) != 0:
		push_warning(
			"Steam unavailable: %s" % result.get("verbal", "Unknown")
		)
		return

	initialized = true
	Steam.get_ticket_for_web_api.connect(_on_web_ticket)
	steam_id = Steam.getSteamID()
	steam_name = Steam.getPersonaName()

	# Listen for Steam connection changes.
	Steam.steam_server_connected.connect(_on_steam_connected)
	Steam.steam_server_disconnected.connect(_on_steam_disconnected)

	# Load Steam avatar.
	Steam.avatar_loaded.connect(_on_avatar_loaded)
	Steam.getPlayerAvatar(Steam.AVATAR_MEDIUM, steam_id)

	# Initial connection state.
	_set_online(Steam.loggedOn())

	profile_updated.emit()


func _process(_delta: float) -> void:
	if initialized:
		Steam.run_callbacks()


func _on_steam_connected() -> void:
	_set_online(true)


func _on_steam_disconnected(_reason: int = 0) -> void:
	_set_online(false)
	_cancel_web_tickets()


## The caller owns the returned handle until its HTTP operation finishes.
## Ticket bytes are never saved or logged. Initialization is not server authentication.
func request_web_ticket(identity: String) -> Dictionary:
	if not initialized or not online:
		return {"ok": false, "message": "Steam is unavailable. Try again when connected."}
	if identity.is_empty() or identity.length() > 128 or web_tickets.size() >= 4:
		return {"ok": false, "message": "Steam authentication is busy. Try again shortly."}
	var handle: int = Steam.getAuthTicketForWebApi(identity)
	if handle == 0:
		return {"ok": false, "message": "Steam could not create an authentication ticket."}
	var pending := WebTicket.new()
	web_tickets[handle] = pending
	get_tree().create_timer(10.0).timeout.connect(func():
		if web_tickets.has(handle) and pending.pending:
			release_web_ticket(handle))
	return await pending.completed


func _on_web_ticket(handle: int, result: int, ticket_size: int, ticket_buffer: Array) -> void:
	if not web_tickets.has(handle): return
	var pending: WebTicket = web_tickets[handle]
	if not pending.pending: return
	if result != 1 or ticket_size <= 0 or ticket_size > 2560 or ticket_size > ticket_buffer.size():
		release_web_ticket(handle)
		return
	pending.pending = false
	var bytes := PackedByteArray(ticket_buffer).slice(0, ticket_size)
	# Bound the lifetime even if a caller disappears before releasing its ticket.
	get_tree().create_timer(30.0).timeout.connect(func():
		if web_tickets.get(handle) == pending: release_web_ticket(handle))
	pending.completed.emit({"ok": true, "handle": handle, "ticket": bytes.hex_encode()})


func release_web_ticket(handle: int) -> void:
	if not web_tickets.has(handle): return
	var pending: WebTicket = web_tickets[handle]
	web_tickets.erase(handle)
	Steam.cancelAuthTicket(handle)
	if pending.pending:
		pending.pending = false
		pending.completed.emit({"ok": false, "message": "Steam authentication did not complete. Try again."})


func _cancel_web_tickets() -> void:
	for handle: int in web_tickets.keys(): release_web_ticket(handle)


func _exit_tree() -> void:
	_cancel_web_tickets()


func _set_online(value: bool) -> void:
	if online == value:
		return

	online = value
	connection_changed.emit(online)
	profile_updated.emit()


func _on_avatar_loaded(
	user_id: int,
	size: int,
	data: PackedByteArray
) -> void:
	if user_id != steam_id:
		return

	if size <= 0 or data.size() != size * size * 4:
		return

	var image := Image.create_from_data(
		size,
		size,
		false,
		Image.FORMAT_RGBA8,
		data
	)

	avatar_texture = ImageTexture.create_from_image(image)
	profile_updated.emit()

class_name SupabaseCommunityBackend
extends Node
## Marble Engineer's routes and API-v1 envelope live only here.
signal authentication_changed

var client: Node = SupabaseClient
var steam: Node = SteamClient
var steam_verified: bool = false
const STEAM_TICKET_IDENTITY := "marble-engineer-community"

func _ready() -> void:
	client.authentication_changed.connect(authentication_changed.emit)
	steam.connection_changed.connect(func(_connected):
		steam_verified = false
		authentication_changed.emit())

func uses_automatic_auth() -> bool:
	return steam.initialized

func is_signed_in() -> bool:
	return (steam_verified and steam.online) if uses_automatic_auth() else client.is_signed_in()

func sign_in(email: String, password: String) -> Dictionary:
	return await client.sign_in_with_password(email, password)

func sign_out() -> Dictionary:
	return await client.sign_out()

func browse_puzzles(filters: Dictionary, compatibility: String) -> Dictionary:
	return await api(HTTPClient.METHOD_GET, "puzzles?" + query(filters, compatibility))

func get_my_puzzles(filters: Dictionary) -> Dictionary:
	return await api(HTTPClient.METHOD_GET, "mine?" + query(filters, ""), null, true)

func get_puzzle(id: String, revision: int, compatibility: String) -> Dictionary:
	return await api(HTTPClient.METHOD_GET, "puzzles/" + id.uri_encode() + "?revision=%d&compatibility=%s" % [revision, compatibility.uri_encode()])

func publish_puzzle(puzzle: Dictionary, compatibility: String) -> Dictionary:
	return await api(HTTPClient.METHOD_POST, "puzzles", {"puzzle": puzzle, "compatibility": compatibility}, true)

func unpublish_puzzle(id: String) -> Dictionary:
	return await api(HTTPClient.METHOD_DELETE, "puzzles/" + id.uri_encode(), null, true)

func query(filters: Dictionary, compatibility: String) -> String:
	return "offset=%d&search=%s&compatibility=%s" % [maxi(0, int(filters.get("offset", 0))), str(filters.get("search", "")).left(100).uri_encode(), compatibility.uri_encode()]

func api(method: int, route: String, body: Variant = null, authenticated: bool = false) -> Dictionary:
	if authenticated and uses_automatic_auth():
		var ticket: Dictionary = await steam.request_web_ticket(STEAM_TICKET_IDENTITY)
		if not ticket.ok:
			steam_verified = false
			authentication_changed.emit()
			return CommunityService.failure("authentication_failed", ticket.message)
		var response: Dictionary = await client.invoke_function("community", body, method, false, "v1/" + route, {"x-steam-ticket": ticket.ticket})
		steam.release_web_ticket(ticket.handle)
		var result := decode_envelope(response)
		steam_verified = response.ok and steam.online
		authentication_changed.emit()
		return result
	return decode_envelope(await client.invoke_function("community", body, method, authenticated, "v1/" + route))

static func decode_envelope(response: Dictionary) -> Dictionary:
	if response.status == 0: return CommunityService.failure(response.error.code, response.error.message)
	var parsed: Variant = response.data
	if not parsed is Dictionary or parsed.get("api_version") != 1 or not parsed.get("ok") is bool:
		if not response.ok: return CommunityService.failure(response.error.code, response.error.message)
		return CommunityService.failure("invalid_response", "The community service uses an unsupported response format.")
	if response.ok and parsed.ok and parsed.get("data") is Dictionary: return CommunityService.success(parsed.data)
	if not parsed.ok and parsed.get("error") is Dictionary and parsed.error.get("code") is String and parsed.error.get("message") is String:
		return CommunityService.failure(parsed.error.code, parsed.error.message.left(500))
	return CommunityService.failure("invalid_response", "The community service returned an invalid result.")
